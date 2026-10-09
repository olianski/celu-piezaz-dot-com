-- Celu Piezaz Dot Com — auditoría de integridad y seguridad del catálogo.
begin;

do $$
begin
  if exists (
    select 1 from public.phone_models
    group by lower(btrim(regexp_replace(
      translate(lower(btrim(brand) || ' ' || btrim(model)),
        'áàäâãåéèëêíìïîóòöôõúùüûñçýÿ',
        'aaaaaaeeeeiiiiooooouuuuncyy'),
      '[^a-z0-9]+', ' ', 'g')))
    having count(*) > 1
  ) then raise exception 'Hay modelos de teléfono duplicados; no se creó el índice.'; end if;

  if exists (
    select 1 from public.products
    group by phone_model_id, part_type_id,
      coalesce(part_variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
    having count(*) > 1
  ) then raise exception 'Hay productos maestros duplicados; no se creó el índice.'; end if;

  if exists (
    select 1 from public.part_types
    group by lower(btrim(regexp_replace(name, '\s+', ' ', 'g')))
    having count(*) > 1
  ) then raise exception 'Hay tipos de repuesto duplicados; no se creó el índice.'; end if;

  if exists (
    select 1 from public.part_variants
    group by part_type_id, lower(btrim(regexp_replace(name, '\s+', ' ', 'g')))
    having count(*) > 1
  ) then raise exception 'Hay variantes duplicadas; no se creó el índice.'; end if;
end $$;

create unique index if not exists phone_models_catalog_key_uidx
on public.phone_models (
  lower(btrim(regexp_replace(
    translate(lower(btrim(brand) || ' ' || btrim(model)),
      'áàäâãåéèëêíìïîóòöôõúùüûñçýÿ',
      'aaaaaaeeeeiiiiooooouuuuncyy'),
    '[^a-z0-9]+', ' ', 'g')))
);
create unique index if not exists products_unique_catalog_key_uidx
on public.products (phone_model_id, part_type_id,
  (coalesce(part_variant_id, '00000000-0000-0000-0000-000000000000'::uuid)));
create unique index if not exists part_types_normalized_name_uidx
on public.part_types (lower(btrim(regexp_replace(name, '\s+', ' ', 'g'))));
create unique index if not exists part_variants_normalized_name_uidx
on public.part_variants (part_type_id, lower(btrim(regexp_replace(name, '\s+', ' ', 'g'))));
create unique index if not exists users_single_admin_uidx
on public.users ((role)) where role = 'admin';

create index if not exists idx_products_phone_model on public.products(phone_model_id);
create index if not exists idx_products_part_type on public.products(part_type_id);
create index if not exists idx_products_part_variant on public.products(part_variant_id);
create index if not exists idx_order_items_order on public.order_items(order_id);
create index if not exists idx_order_items_inventory on public.order_items(inventory_id);
create index if not exists idx_order_items_product on public.order_items(product_id);
create index if not exists idx_demand_technician on public.demand_requests(technician_id);

create or replace function public.prevent_shop_self_approval()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and auth.uid() = old.user_id
     and coalesce(public.current_user_role(), '') <> 'admin'
     and (new.status is distinct from old.status or new.active is distinct from old.active) then
    raise exception 'Solo el administrador puede aprobar, suspender o activar una tienda.';
  end if;
  return new;
end;
$$;
drop trigger if exists prevent_shop_self_approval_before_update on public.shops;
create trigger prevent_shop_self_approval_before_update
before update of status, active on public.shops
for each row execute function public.prevent_shop_self_approval();

create or replace function public.normalize_phone_model_before_write()
returns trigger language plpgsql set search_path = public, pg_temp
as $$
begin
  new.brand := regexp_replace(trim(coalesce(new.brand, '')), '\s+', ' ', 'g');
  new.model := regexp_replace(trim(coalesce(new.model, '')), '\s+', ' ', 'g');
  new.normalized_name := trim(regexp_replace(
    translate(lower(new.brand || ' ' || new.model),
      'áàäâãåéèëêíìïîóòöôõúùüûñçýÿ',
      'aaaaaaeeeeiiiiooooouuuuncyy'),
    '\s+', ' ', 'g'));
  return new;
end;
$$;

create or replace function public.set_phone_model_normalized_name()
returns trigger language plpgsql set search_path = public, pg_temp
as $$
begin
  new.normalized_name := trim(regexp_replace(
    translate(lower(trim(coalesce(new.brand, '') || ' ' || coalesce(new.model, ''))),
      'áàäâãåéèëêíìïîóòöôõúùüûñçýÿ',
      'aaaaaaeeeeiiiiooooouuuuncyy'),
    '\s+', ' ', 'g'));
  return new;
end;
$$;

delete from public.account_authorization_tokens where expires_at < now();
drop table if exists public.admin_account_provisioning;

create or replace function public.save_inventory_item(p_product_id uuid, p_price numeric, p_quantity integer)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_shop_id uuid; v_id uuid;
begin
  if public.current_user_role() <> 'shop' then raise exception 'Solo una tienda puede modificar inventario'; end if;
  if p_price is null or p_price < 0 or p_quantity is null or p_quantity < 0 then raise exception 'Precio o cantidad inválidos'; end if;
  if not exists (select 1 from public.products where id = p_product_id and active = true) then
    raise exception 'Ese producto no está activo en el catálogo maestro';
  end if;
  select id into v_shop_id from public.shops where user_id = auth.uid() and status = 'approved' and active = true;
  if v_shop_id is null then raise exception 'Tienda no disponible o pendiente de aprobación'; end if;
  insert into public.inventory(shop_id, product_id, price, quantity, active)
  values (v_shop_id, p_product_id, p_price, p_quantity, true)
  on conflict (shop_id, product_id) do update
    set price = excluded.price, quantity = excluded.quantity, active = true, updated_at = now();
  select id into v_id from public.inventory where shop_id = v_shop_id and product_id = p_product_id;
  return v_id;
end;
$$;

create or replace function public.place_order(p_shop_id uuid, p_delivery_type text, p_delivery_address text, p_items jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_order_id uuid; v_fee numeric(12,2); v_subtotal numeric(12,2) := 0;
  v_item jsonb; v_inventory public.inventory%rowtype; v_qty integer;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.users where id = auth.uid() and role = 'technician') then
    raise exception 'Solo un técnico puede crear pedidos';
  end if;
  if p_delivery_type not in ('local','outside_zone','pickup') then raise exception 'Tipo de entrega inválido'; end if;
  if p_delivery_type <> 'pickup' and nullif(trim(coalesce(p_delivery_address,'')), '') is null then
    raise exception 'La dirección es obligatoria para entrega';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'El pedido debe contener productos'; end if;
  select case p_delivery_type when 'outside_zone' then delivery_outside_fee else 0 end
    into v_fee from public.shops where id = p_shop_id and active = true and status = 'approved';
  if not found then raise exception 'La tienda no está disponible'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty is null or v_qty <= 0 then raise exception 'Cantidad inválida'; end if;
    select i.* into v_inventory
    from public.inventory i join public.products p on p.id=i.product_id and p.active=true
    where i.id=(v_item->>'inventory_id')::uuid and i.shop_id=p_shop_id and i.active=true and i.quantity>=v_qty
    for update of i;
    if not found then raise exception 'Producto no disponible, inactivo o con stock insuficiente'; end if;
    v_subtotal := v_subtotal + (v_inventory.price * v_qty);
  end loop;

  insert into public.orders(technician_id,shop_id,status,delivery_type,delivery_fee,delivery_address,total)
  values(auth.uid(),p_shop_id,'pending',p_delivery_type,v_fee,
    case when p_delivery_type='pickup' then null else trim(p_delivery_address) end,v_subtotal+v_fee)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select i.* into v_inventory
    from public.inventory i join public.products p on p.id=i.product_id and p.active=true
    where i.id=(v_item->>'inventory_id')::uuid and i.shop_id=p_shop_id and i.active=true
    for update of i;
    if not found or v_inventory.quantity < v_qty then raise exception 'El stock cambió mientras se creaba el pedido'; end if;
    insert into public.order_items(order_id,inventory_id,product_id,quantity,unit_price)
    values(v_order_id,v_inventory.id,v_inventory.product_id,v_qty,v_inventory.price);
    update public.inventory set quantity=quantity-v_qty, updated_at=now() where id=v_inventory.id;
  end loop;
  return v_order_id;
end;
$$;

commit;
