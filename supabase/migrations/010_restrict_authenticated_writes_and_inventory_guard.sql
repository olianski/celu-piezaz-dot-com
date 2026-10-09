-- Apply all sensitive RLS policies only to signed-in roles and guard inventory writes.
begin;

alter policy demand_admin on public.demand_requests to authenticated;
alter policy demand_create_own on public.demand_requests to authenticated;
alter policy demand_read_own on public.demand_requests to authenticated;
alter policy inventory_delete_own on public.inventory to authenticated;
alter policy inventory_insert_own on public.inventory to authenticated;
alter policy inventory_update_own on public.inventory to authenticated;
alter policy order_items_create_own on public.order_items to authenticated;
alter policy order_items_read_participants on public.order_items to authenticated;
alter policy orders_create_own on public.orders to authenticated;
alter policy orders_read_participants on public.orders to authenticated;
alter policy orders_update_shop_admin on public.orders to authenticated;
alter policy catalog_types_admin on public.part_types to authenticated;
alter policy catalog_variants_admin on public.part_variants to authenticated;
alter policy catalog_models_admin on public.phone_models to authenticated;
alter policy products_admin on public.products to authenticated;
alter policy shop_owner_manages_shop on public.shops to authenticated;
alter policy admin_manages_users on public.users to authenticated;
alter policy users_own_profile on public.users to authenticated;

create or replace function public.guard_inventory_write()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_role text; v_shop public.shops%rowtype; v_product_active boolean;
begin
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
revoke execute on function public.guard_inventory_write() from public, anon, authenticated;
drop trigger if exists guard_inventory_write_before_change on public.inventory;
create trigger guard_inventory_write_before_change before insert or update on public.inventory
for each row execute function public.guard_inventory_write();

drop policy if exists demand_create_own on public.demand_requests;
create policy demand_create_own on public.demand_requests
for insert to authenticated
with check (
  technician_id = auth.uid()
  and public.current_user_role() = 'technician'
  and exists (select 1 from public.products p where p.id = demand_requests.product_id and p.active = true)
);

revoke all on public.users, public.shops, public.phone_models, public.part_types,
  public.part_variants, public.products, public.inventory, public.orders,
  public.order_items, public.demand_requests, public.account_authorization_tokens
from anon, public;
grant select, update on public.users to authenticated;
grant select, update, delete on public.shops to authenticated;
grant select, insert, update, delete on public.phone_models, public.part_types,
  public.part_variants, public.products to authenticated;
grant select, insert, update, delete on public.inventory to authenticated;
grant select on public.orders, public.order_items to authenticated;
grant select, insert, update on public.demand_requests to authenticated;
commit;
