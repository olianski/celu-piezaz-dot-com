-- Celu Piezaz Dot Com — restringir acceso público y validar transiciones comerciales.
begin;

drop policy if exists active_shops_readable on public.shops;
create policy active_shops_readable on public.shops
for select to authenticated
using (
  auth.uid() is not null and (
    public.current_user_role() = 'admin'
    or user_id = auth.uid()
    or (public.current_user_role() = 'technician' and active = true and status = 'approved')
  )
);

drop policy if exists inventory_readable on public.inventory;
create policy inventory_readable on public.inventory
for select to authenticated
using (
  auth.uid() is not null and (
    public.current_user_role() = 'admin'
    or (public.current_user_role() = 'technician' and active = true)
    or exists (select 1 from public.shops s where s.id = inventory.shop_id and s.user_id = auth.uid())
  )
);

drop policy if exists catalog_models_readable on public.phone_models;
create policy catalog_models_readable on public.phone_models
for select to authenticated using (active = true or public.current_user_role() = 'admin');
drop policy if exists catalog_types_readable on public.part_types;
create policy catalog_types_readable on public.part_types
for select to authenticated using (active = true or public.current_user_role() = 'admin');
drop policy if exists catalog_variants_readable on public.part_variants;
create policy catalog_variants_readable on public.part_variants
for select to authenticated using (active = true or public.current_user_role() = 'admin');
drop policy if exists products_readable on public.products;
create policy products_readable on public.products
for select to authenticated using (active = true or public.current_user_role() = 'admin');

grant select on public.users, public.shops, public.phone_models, public.part_types,
  public.part_variants, public.products, public.inventory, public.orders,
  public.order_items, public.demand_requests to authenticated;
revoke select on public.shops, public.inventory, public.phone_models, public.part_types,
  public.part_variants, public.products, public.orders, public.order_items from anon, public;

create or replace function public.guard_shop_lifecycle()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_role text;
begin
  v_role := coalesce(public.current_user_role(), '');
  if tg_op = 'INSERT' then
    if auth.uid() is not null and v_role <> 'admin' then
      raise exception 'Solo el administrador puede crear perfiles de tienda.';
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    if auth.uid() is not null and old.user_id = auth.uid() and v_role <> 'admin' then
      raise exception 'Solo el administrador puede eliminar perfiles de tienda.';
    end if;
    return old;
  else
    if auth.uid() is not null and old.user_id = auth.uid() and v_role <> 'admin'
       and (new.status is distinct from old.status or new.active is distinct from old.active) then
      raise exception 'Solo el administrador puede aprobar, suspender o activar una tienda.';
    end if;
    return new;
  end if;
end;
$$;
drop trigger if exists prevent_shop_self_approval_before_update on public.shops;
drop trigger if exists guard_shop_lifecycle_before_change on public.shops;
create trigger guard_shop_lifecycle_before_change
before insert or update or delete on public.shops
for each row execute function public.guard_shop_lifecycle();

revoke insert, update, delete on public.orders, public.order_items from anon, authenticated, public;
grant select on public.orders, public.order_items to authenticated;

create or replace function public.update_order_status(p_order_id uuid, p_next_status text)
returns boolean language plpgsql security definer set search_path = public
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
    update public.inventory i
    set quantity=i.quantity+oi.quantity, active=p.active, updated_at=now()
    from public.order_items oi join public.products p on p.id=oi.product_id
    where oi.order_id=v_order.id and i.id=oi.inventory_id;
  elsif v_order.status='accepted' and p_next_status='preparing' then
    null;
  elsif v_order.status='preparing' and p_next_status='out_for_delivery' then
    null;
  elsif v_order.status='out_for_delivery' and p_next_status='delivered' then
    null;
  else raise exception 'Cambio de estado no permitido';
  end if;
  update public.orders set status=p_next_status, updated_at=now() where id=v_order.id;
  return true;
end;
$$;

revoke all on function public.update_order_status(uuid, text) from public, anon;
grant execute on function public.update_order_status(uuid, text) to authenticated;
revoke all on function public.place_order(uuid, text, text, jsonb) from public, anon;
grant execute on function public.place_order(uuid, text, text, jsonb) to authenticated;
revoke all on function public.save_inventory_item(uuid, numeric, integer) from public, anon;
grant execute on function public.save_inventory_item(uuid, numeric, integer) to authenticated;
revoke all on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
revoke all on function public.search_products(text) from public, anon;
grant execute on function public.search_products(text) to authenticated;

commit;
