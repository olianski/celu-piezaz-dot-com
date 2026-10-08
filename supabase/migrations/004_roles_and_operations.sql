-- Celu Piezaz Dot Com — Fase 3 / roles reales y operaciones protegidas

alter table public.shops
  add column if not exists status text not null default 'approved'
  check (status in ('pending','approved','suspended'));

create or replace function public.get_my_profile()
returns table(id uuid, role text, name text, phone text)
language sql stable security definer set search_path=public
as $$ select id, role, name, phone from public.users where id=auth.uid(); $$;

create or replace function public.search_products(p_query text)
returns table(
  id uuid, display_name text, brand text, model text,
  part_type text, variant text
)
language sql stable security invoker set search_path=public
as $$
  select p.id, p.display_name, pm.brand, pm.model, pt.name, pv.name
  from public.products p
  join public.phone_models pm on pm.id=p.phone_model_id
  join public.part_types pt on pt.id=p.part_type_id
  left join public.part_variants pv on pv.id=p.part_variant_id
  where p.active
    and (
      p.normalized_search ilike '%' || lower(trim(coalesce(p_query,''))) || '%'
      or pm.normalized_name ilike '%' || lower(trim(coalesce(p_query,''))) || '%'
    )
  order by pm.brand, pm.model, pt.name, pv.name;
$$;

create or replace function public.save_inventory_item(
  p_product_id uuid,
  p_price numeric,
  p_quantity integer
)
returns uuid
language plpgsql security definer set search_path=public
as $$
declare v_shop_id uuid; v_id uuid;
begin
  if public.current_user_role() <> 'shop' then raise exception 'Solo una tienda puede modificar inventario'; end if;
  if p_price < 0 or p_quantity < 0 then raise exception 'Precio o cantidad inválidos'; end if;
  select id into v_shop_id from public.shops where user_id=auth.uid() and status='approved' and active=true;
  if v_shop_id is null then raise exception 'Tienda no disponible'; end if;
  insert into public.inventory(shop_id,product_id,price,quantity,active)
  values(v_shop_id,p_product_id,p_price,p_quantity,true)
  on conflict(shop_id,product_id) do update
    set price=excluded.price, quantity=excluded.quantity, active=true;
  select id into v_id from public.inventory where shop_id=v_shop_id and product_id=p_product_id;
  return v_id;
end;
$$;

create or replace function public.update_order_status(p_order_id uuid,p_next_status text)
returns boolean
language plpgsql security definer set search_path=public
as $$
declare v_order public.orders%rowtype;
begin
  if public.current_user_role() not in ('shop','admin') then raise exception 'No autorizado'; end if;
  select o.* into v_order
  from public.orders o
  where o.id=p_order_id
    and (public.current_user_role()='admin' or exists(select 1 from public.shops s where s.id=o.shop_id and s.user_id=auth.uid()))
  for update;
  if not found then raise exception 'Pedido no encontrado'; end if;

  if v_order.status='pending' and p_next_status='accepted' then null;
  elsif v_order.status='accepted' and p_next_status='delivered' then null;
  elsif v_order.status='pending' and p_next_status='rejected' then
    update public.inventory i
      set quantity=i.quantity+oi.quantity, active=true
    from public.order_items oi
    where oi.order_id=v_order.id and i.id=oi.inventory_id;
  else
    raise exception 'Cambio de estado no permitido';
  end if;

  update public.orders set status=p_next_status where id=v_order.id;
  return true;
end;
$$;

revoke all on function public.get_my_profile() from public;
grant execute on function public.get_my_profile() to authenticated;
revoke all on function public.search_products(text) from public;
grant execute on function public.search_products(text) to authenticated;
revoke all on function public.save_inventory_item(uuid,numeric,integer) from public;
grant execute on function public.save_inventory_item(uuid,numeric,integer) to authenticated;
revoke all on function public.update_order_status(uuid,text) from public;
grant execute on function public.update_order_status(uuid,text) to authenticated;
