-- Pedido transaccional: calcula total y reserva/descuenta stock en una sola operación.
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
  v_inventory inventory%rowtype;
  v_qty integer;
begin
  if auth.uid() is null then
    raise exception 'No autenticado';
  end if;

  if not exists (
    select 1 from users
    where id = auth.uid() and role = 'technician'
  ) then
    raise exception 'Solo un técnico puede crear pedidos';
  end if;

  if p_delivery_type not in ('local','outside_zone','pickup') then
    raise exception 'Tipo de entrega inválido';
  end if;

  if p_delivery_type <> 'pickup'
     and nullif(trim(coalesce(p_delivery_address,'')), '') is null then
    raise exception 'La dirección es obligatoria para entrega';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'El pedido debe contener productos';
  end if;

  select case p_delivery_type
    when 'outside_zone' then delivery_outside_fee
    else 0
  end
  into v_fee
  from shops
  where id = p_shop_id and active = true;

  if not found then
    raise exception 'La tienda no está disponible';
  end if;

  -- Bloquea las filas de inventario para impedir vender simultáneamente
  -- una cantidad que ya fue consumida por otro pedido.
  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := greatest((v_item->>'quantity')::integer, 0);

    if v_qty <= 0 then
      raise exception 'Cantidad inválida';
    end if;

    select * into v_inventory
    from inventory
    where id = (v_item->>'inventory_id')::uuid
      and shop_id = p_shop_id
      and active = true
    for update;

    if not found then
      raise exception 'Producto no disponible en esta tienda';
    end if;

    if v_inventory.quantity < v_qty then
      raise exception 'Stock insuficiente';
    end if;

    v_subtotal := v_subtotal + (v_inventory.price * v_qty);
  end loop;

  insert into orders(
    technician_id, shop_id, status, delivery_type,
    delivery_fee, delivery_address, total
  )
  values(
    auth.uid(), p_shop_id, 'pending', p_delivery_type,
    v_fee, case when p_delivery_type = 'pickup' then null else trim(p_delivery_address) end,
    v_subtotal + v_fee
  )
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items)
  loop
    v_qty := (v_item->>'quantity')::integer;

    select * into v_inventory
    from inventory
    where id = (v_item->>'inventory_id')::uuid
      and shop_id = p_shop_id
      and active = true
    for update;

    insert into order_items(order_id, inventory_id, product_id, quantity, unit_price)
    values(v_order_id, v_inventory.id, v_inventory.product_id, v_qty, v_inventory.price);

    update inventory
    set quantity = quantity - v_qty
    where id = v_inventory.id;
  end loop;

  return v_order_id;
end;
$$;

revoke all on function public.place_order(uuid,text,text,jsonb) from public;
grant execute on function public.place_order(uuid,text,text,jsonb) to authenticated;
