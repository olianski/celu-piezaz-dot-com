-- El inventario ya no controla unidades: cada publicación está disponible o agotada.
-- Se conserva order_items.quantity para no alterar el historial; los nuevos pedidos guardan 1 por producto.
begin;

create or replace function public.guard_inventory_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text;
  v_shop public.shops%rowtype;
  v_product_active boolean;
begin
  v_role := coalesce(public.current_user_role(), '');
  if v_role = 'admin' then
    if new.active and not exists(select 1 from public.products where id = new.product_id and active = true) then
      raise exception 'No puedes activar inventario para un producto inactivo.';
    end if;
    if new.price is null or new.price < 0 then
      raise exception 'Precio inválido.';
    end if;
    return new;
  end if;
  if v_role <> 'shop' then
    raise exception 'Solo una tienda puede modificar inventario.';
  end if;

  select * into v_shop
  from public.shops
  where id = new.shop_id and user_id = auth.uid();

  if not found or v_shop.status <> 'approved' or not v_shop.active then
    raise exception 'Tu tienda debe estar aprobada y activa antes de modificar inventario.';
  end if;

  select active into v_product_active from public.products where id = new.product_id;
  if not found or not v_product_active then
    raise exception 'Ese producto no está activo en el catálogo maestro.';
  end if;
  if new.price is null or new.price < 0 then
    raise exception 'Precio inválido.';
  end if;
  return new;
end;
$$;
revoke execute on function public.guard_inventory_write() from public, anon, authenticated;

drop function if exists public.save_inventory_item(uuid, numeric, integer);
create or replace function public.save_inventory_item(
  p_product_id uuid,
  p_price numeric,
  p_active boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_shop_id uuid;
  v_id uuid;
begin
  if public.current_user_role() <> 'shop' then
    raise exception 'Solo una tienda puede modificar inventario';
  end if;
  if p_price is null or p_price < 0 then
    raise exception 'Precio inválido';
  end if;
  if not exists (select 1 from public.products where id = p_product_id and active = true) then
    raise exception 'Ese producto no está activo en el catálogo maestro';
  end if;

  select id into v_shop_id
  from public.shops
  where user_id = auth.uid() and status = 'approved' and active = true;
  if v_shop_id is null then
    raise exception 'Tienda no disponible o pendiente de aprobación';
  end if;

  insert into public.inventory(shop_id, product_id, price, active)
  values (v_shop_id, p_product_id, p_price, coalesce(p_active, true))
  on conflict (shop_id, product_id) do update
    set price = excluded.price, active = excluded.active, updated_at = now();

  select id into v_id from public.inventory where shop_id = v_shop_id and product_id = p_product_id;
  return v_id;
end;
$$;
revoke all on function public.save_inventory_item(uuid, numeric, boolean) from public, anon;
grant execute on function public.save_inventory_item(uuid, numeric, boolean) to authenticated;

create or replace function public.place_order(
  p_shop_id uuid,
  p_delivery_type text,
  p_delivery_address text,
  p_items jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_fee numeric(12,2);
  v_subtotal numeric(12,2) := 0;
  v_item jsonb;
  v_inventory public.inventory%rowtype;
  v_count integer;
  v_distinct integer;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists(select 1 from public.users where id = auth.uid() and role = 'technician') then
    raise exception 'Solo un técnico puede crear pedidos';
  end if;
  if p_delivery_type not in ('local', 'outside_zone', 'pickup') then raise exception 'Tipo de entrega inválido'; end if;
  if p_delivery_type <> 'pickup' and nullif(trim(coalesce(p_delivery_address, '')), '') is null then
    raise exception 'La dirección es obligatoria para entrega';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe contener productos';
  end if;

  select count(*), count(distinct (x->>'inventory_id'))
  into v_count, v_distinct
  from jsonb_array_elements(p_items) x;
  if v_count <> v_distinct then raise exception 'El pedido contiene productos repetidos o inválidos'; end if;

  select case p_delivery_type when 'outside_zone' then delivery_outside_fee else 0 end
  into v_fee
  from public.shops
  where id = p_shop_id and active = true and status = 'approved';
  if not found then raise exception 'La tienda no está disponible'; end if;

  -- Cada elemento del pedido representa un producto; no se solicitan ni descuentan unidades.
  for v_item in select * from jsonb_array_elements(p_items) loop
    select i.* into v_inventory
    from public.inventory i
    join public.products p on p.id = i.product_id and p.active = true
    where i.id = (v_item->>'inventory_id')::uuid
      and i.shop_id = p_shop_id
      and i.active = true
    for update of i;

    if not found then raise exception 'Producto no disponible'; end if;
    v_subtotal := v_subtotal + v_inventory.price;
  end loop;

  insert into public.orders(technician_id, shop_id, status, delivery_type, delivery_fee, delivery_address, total)
  values(auth.uid(), p_shop_id, 'pending', p_delivery_type, v_fee,
    case when p_delivery_type = 'pickup' then null else trim(p_delivery_address) end,
    v_subtotal + v_fee)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select i.* into v_inventory
    from public.inventory i
    join public.products p on p.id = i.product_id and p.active = true
    where i.id = (v_item->>'inventory_id')::uuid
      and i.shop_id = p_shop_id
      and i.active = true
    for update of i;

    if not found then raise exception 'El producto dejó de estar disponible mientras se creaba el pedido'; end if;

    insert into public.order_items(order_id, inventory_id, product_id, quantity, unit_price)
    values(v_order_id, v_inventory.id, v_inventory.product_id, 1, v_inventory.price);
  end loop;

  return v_order_id;
end;
$$;
revoke all on function public.place_order(uuid, text, text, jsonb) from public, anon;
grant execute on function public.place_order(uuid, text, text, jsonb) to authenticated;

alter table public.inventory drop column if exists quantity;

commit;
