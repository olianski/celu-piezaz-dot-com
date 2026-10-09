-- Allow only the validated order RPCs to update stock transactionally.
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
  if current_setting('app.internal_stock_change', true) = 'true' then
    return new;
  end if;

  v_role := coalesce(public.current_user_role(), '');
  if v_role = 'admin' then
    if new.active and not exists(select 1 from public.products where id=new.product_id and active=true) then
      raise exception 'No puedes activar inventario para un producto inactivo.';
    end if;
    return new;
  end if;
  if v_role <> 'shop' then raise exception 'Solo una tienda puede modificar inventario.'; end if;
  select * into v_shop from public.shops where id=new.shop_id and user_id=auth.uid();
  if not found or v_shop.status <> 'approved' or not v_shop.active then
    raise exception 'Tu tienda debe estar aprobada y activa antes de modificar inventario.';
  end if;
  select active into v_product_active from public.products where id=new.product_id;
  if not found or not v_product_active then raise exception 'Ese producto no está activo en el catálogo maestro.'; end if;
  if new.price is null or new.price < 0 or new.quantity is null or new.quantity < 0 then
    raise exception 'Precio o cantidad inválidos.';
  end if;
  return new;
end;
$$;

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
  v_qty integer;
  v_count integer;
  v_distinct integer;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists(select 1 from public.users where id=auth.uid() and role='technician') then
    raise exception 'Solo un técnico puede crear pedidos';
  end if;
  if p_delivery_type not in ('local','outside_zone','pickup') then raise exception 'Tipo de entrega inválido'; end if;
  if p_delivery_type <> 'pickup' and nullif(trim(coalesce(p_delivery_address,'')), '') is null then
    raise exception 'La dirección es obligatoria para entrega';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'El pedido debe contener productos';
  end if;

  select count(*),count(distinct (x->>'inventory_id'))
    into v_count,v_distinct from jsonb_array_elements(p_items) x;
  if v_count <> v_distinct then raise exception 'El pedido contiene productos repetidos'; end if;

  select case p_delivery_type when 'outside_zone' then delivery_outside_fee else 0 end
    into v_fee from public.shops where id=p_shop_id and active=true and status='approved';
  if not found then raise exception 'La tienda no está disponible'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    begin v_qty := (v_item->>'quantity')::integer;
    exception when others then raise exception 'Cantidad inválida'; end;
    if v_qty <= 0 then raise exception 'Cantidad inválida'; end if;
    select i.* into v_inventory
      from public.inventory i join public.products p on p.id=i.product_id and p.active=true
      where i.id=(v_item->>'inventory_id')::uuid
        and i.shop_id=p_shop_id and i.active=true and i.quantity >= v_qty
      for update of i;
    if not found then raise exception 'Producto no disponible, inactivo o con stock insuficiente'; end if;
    v_subtotal := v_subtotal + (v_inventory.price*v_qty);
  end loop;

  insert into public.orders(technician_id,shop_id,status,delivery_type,delivery_fee,delivery_address,total)
  values(auth.uid(),p_shop_id,'pending',p_delivery_type,v_fee,
    case when p_delivery_type='pickup' then null else trim(p_delivery_address) end,
    v_subtotal+v_fee)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select i.* into v_inventory
      from public.inventory i join public.products p on p.id=i.product_id and p.active=true
      where i.id=(v_item->>'inventory_id')::uuid
        and i.shop_id=p_shop_id and i.active=true
      for update of i;
    if not found or v_inventory.quantity < v_qty then
      raise exception 'El stock cambió mientras se creaba el pedido';
    end if;

    insert into public.order_items(order_id,inventory_id,product_id,quantity,unit_price)
    values(v_order_id,v_inventory.id,v_inventory.product_id,v_qty,v_inventory.price);

    perform set_config('app.internal_stock_change','true',true);
    update public.inventory set quantity=quantity-v_qty,updated_at=now() where id=v_inventory.id;
    perform set_config('app.internal_stock_change','false',true);
  end loop;
  return v_order_id;
end;
$$;

create or replace function public.update_order_status(p_order_id uuid,p_next_status text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_order public.orders%rowtype;
begin
  if coalesce(public.current_user_role(), '') not in ('shop','admin') then raise exception 'No autorizado'; end if;
  select o.* into v_order from public.orders o
  where o.id=p_order_id and (
    public.current_user_role()='admin'
    or exists(select 1 from public.shops s where s.id=o.shop_id and s.user_id=auth.uid())
  ) for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.status='pending' and p_next_status='accepted' then
    null;
  elsif v_order.status='pending' and p_next_status='rejected' then
    perform set_config('app.internal_stock_change','true',true);
    update public.inventory i
      set quantity=i.quantity+oi.quantity,active=p.active,updated_at=now()
    from public.order_items oi join public.products p on p.id=oi.product_id
    where oi.order_id=v_order.id and i.id=oi.inventory_id;
    perform set_config('app.internal_stock_change','false',true);
  elsif v_order.status='accepted' and p_next_status='preparing' then
    null;
  elsif v_order.status='preparing' and p_next_status='out_for_delivery' then
    null;
  elsif v_order.status='out_for_delivery' and p_next_status='delivered' then
    null;
  else raise exception 'Cambio de estado no permitido'; end if;

  update public.orders set status=p_next_status,updated_at=now() where id=v_order.id;
  return true;
end;
$$;

revoke all on function public.place_order(uuid,text,text,jsonb) from public,anon;
grant execute on function public.place_order(uuid,text,text,jsonb) to authenticated;
revoke all on function public.update_order_status(uuid,text) from public,anon;
grant execute on function public.update_order_status(uuid,text) to authenticated;
commit;
