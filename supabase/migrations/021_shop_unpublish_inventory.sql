-- Retirar una publicación de la tienda sin borrar el inventario histórico ni romper pedidos anteriores.
begin;
alter table public.inventory add column if not exists listed boolean not null default true;

create or replace function public.unpublish_inventory_item(p_inventory_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_shop_id uuid;
begin
  if public.current_user_role() <> 'shop' then
    raise exception 'Solo una tienda puede retirar sus publicaciones.';
  end if;
  select id into v_shop_id
  from public.shops
  where user_id = auth.uid() and status = 'approved' and active = true;
  if v_shop_id is null then
    raise exception 'Tienda no disponible o pendiente de aprobación.';
  end if;
  update public.inventory
     set listed = false, active = false, updated_at = now()
   where id = p_inventory_id and shop_id = v_shop_id;
  if not found then
    raise exception 'No se encontró esa publicación en tu tienda.';
  end if;
  return true;
end;
$$;
revoke all on function public.unpublish_inventory_item(uuid) from public, anon;
grant execute on function public.unpublish_inventory_item(uuid) to authenticated;

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
  insert into public.inventory(shop_id, product_id, price, active, listed)
  values (v_shop_id, p_product_id, p_price, coalesce(p_active, true), true)
  on conflict (shop_id, product_id) do update
    set price = excluded.price, active = excluded.active, listed = true, updated_at = now();
  select id into v_id from public.inventory where shop_id = v_shop_id and product_id = p_product_id;
  return v_id;
end;
$$;
revoke all on function public.save_inventory_item(uuid, numeric, boolean) from public, anon;
grant execute on function public.save_inventory_item(uuid, numeric, boolean) to authenticated;
commit;