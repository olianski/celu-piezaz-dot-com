-- Celu Piezaz Dot Com — Fase 3
-- Tiendas, catálogo normalizado y estados de pedido alineados con el MVP.

create extension if not exists unaccent;

create or replace function public.normalize_search_text(p_text text)
returns text
language sql
immutable
strict
as $
  select regexp_replace(
    replace(replace(replace(replace(replace(unaccent(lower(trim(p_text))), 'display','pantalla'), 'lcd','pantalla'), 'battery','bateria'), 'charging port','puerto de carga'), 'back cover','tapa trasera'),
    '\\s+', ' ', 'g'
  );
$;

-- Alta segura: el registro público siempre nace como técnico.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.users (id, role, name, phone)
  values (new.id, 'technician', coalesce(nullif(trim(new.raw_user_meta_data->>'name'),''), split_part(coalesce(new.email,''),'@',1), 'Usuario'), nullif(trim(new.raw_user_meta_data->>'phone'),''));
  return new;
end; $$;

-- Catálogo: variante obligatoria y clave única.
alter table public.products alter column part_variant_id set not null;
create unique index if not exists uq_products_catalog_key on public.products(phone_model_id,part_type_id,part_variant_id);

-- Alias de búsqueda.
create table if not exists public.phone_model_aliases (
  id uuid primary key default gen_random_uuid(),
  phone_model_id uuid not null references public.phone_models(id) on delete cascade,
  alias text not null,
  normalized_alias text not null,
  active boolean not null default true,
  unique(phone_model_id,normalized_alias)
);
create unique index if not exists uq_phone_model_alias_normalized on public.phone_model_aliases(normalized_alias);
create index if not exists idx_phone_model_aliases_search on public.phone_model_aliases(normalized_alias);
alter table public.phone_model_aliases enable row level security;
create policy aliases_readable on public.phone_model_aliases for select using(active=true or public.current_user_role()='admin');
create policy aliases_admin on public.phone_model_aliases for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');

-- Ciclo de vida de tienda.
alter table public.shops
  add column if not exists status text not null default 'pending' check(status in ('pending','approved','suspended')),
  add column if not exists approved_at timestamptz,
  add column if not exists approved_by uuid references public.users(id);
create index if not exists idx_shops_status on public.shops(status,active);
update public.shops set status='approved', approved_at=coalesce(approved_at,now()) where status='pending' and active=true;

create or replace function public.shop_is_approved(p_shop_id uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.shops where id=p_shop_id and active=true and status='approved'); $$;

drop policy if exists shop_owner_manages_shop on public.shops;
create policy shop_owner_manages_shop on public.shops for all
using((user_id=auth.uid() and public.current_user_role()='shop') or public.current_user_role()='admin')
with check((user_id=auth.uid() and public.current_user_role()='shop') or public.current_user_role()='admin');

drop policy if exists active_shops_readable on public.shops;
create policy active_shops_readable on public.shops for select
using((active=true and status='approved') or user_id=auth.uid() or public.current_user_role()='admin');

-- Inventario: solo tienda aprobada puede publicar o editar.
drop policy if exists inventory_insert_own on public.inventory;
create policy inventory_insert_own on public.inventory for insert with check(
  public.current_user_role()='admin' or (
    exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid())
    and public.shop_is_approved(shop_id) and public.current_user_role()='shop'
  )
);
drop policy if exists inventory_update_own on public.inventory;
create policy inventory_update_own on public.inventory for update
using(public.current_user_role()='admin' or exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()))
with check(public.current_user_role()='admin' or (exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) and public.shop_is_approved(shop_id) and public.current_user_role()='shop'));


-- RPC real de inventario: el backend resuelve la tienda desde auth.uid().
create or replace function public.save_inventory_item(p_product_id uuid,p_price numeric,p_quantity integer)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_shop_id uuid; v_inventory_id uuid;
begin
  if auth.uid() is null or public.current_user_role() <> 'shop' then raise exception 'Solo una tienda autorizada puede modificar inventario'; end if;
  select id into v_shop_id from public.shops where user_id=auth.uid() and active=true and status='approved' limit 1;
  if v_shop_id is null then raise exception 'La tienda no está aprobada'; end if;
  if not exists(select 1 from public.products where id=p_product_id and active=true) then raise exception 'Producto maestro inválido'; end if;
  if p_price is null or p_price < 0 then raise exception 'Precio inválido'; end if;
  if p_quantity is null or p_quantity < 0 then raise exception 'Cantidad inválida'; end if;
  insert into public.inventory(shop_id,product_id,price,quantity,active) values(v_shop_id,p_product_id,round(p_price,2),p_quantity,true)
  on conflict(shop_id,product_id) do update set price=excluded.price,quantity=excluded.quantity,active=true;
  select id into v_inventory_id from public.inventory where shop_id=v_shop_id and product_id=p_product_id;
  return v_inventory_id;
end; $$;
revoke all on function public.save_inventory_item(uuid,numeric,integer) from public;
grant execute on function public.save_inventory_item(uuid,numeric,integer) to authenticated;

-- Estados simplificados: pendiente -> aceptado -> entregado. Rechazo/cancelación devuelve stock.
update public.orders set status='accepted' where status='preparing';
update public.orders set status='delivered' where status='out_for_delivery';
alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check(status in ('pending','accepted','delivered','rejected','cancelled'));

drop policy if exists orders_create_own on public.orders;
drop policy if exists order_items_create_own on public.order_items;
drop policy if exists orders_update_shop_admin on public.orders;
create policy orders_update_admin_only on public.orders for update using(public.current_user_role()='admin') with check(public.current_user_role()='admin');

create or replace function public.update_order_status(p_order_id uuid,p_next_status text)
returns boolean language plpgsql security definer set search_path = public
as $$
declare v_order public.orders%rowtype; v_item public.order_items%rowtype;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  select * into v_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Pedido no encontrado'; end if;
  if p_next_status not in ('accepted','delivered','rejected','cancelled') then raise exception 'Estado inválido'; end if;
  if public.current_user_role()='shop' then
    if not exists(select 1 from public.shops s where s.id=v_order.shop_id and s.user_id=auth.uid()) then raise exception 'No puedes modificar este pedido'; end if;
    if p_next_status='accepted' and v_order.status <> 'pending' then raise exception 'El pedido ya no está pendiente'; end if;
    if p_next_status='delivered' and v_order.status <> 'accepted' then raise exception 'Solo puedes finalizar un pedido aceptado'; end if;
    if p_next_status='rejected' and v_order.status <> 'pending' then raise exception 'Solo puedes rechazar un pedido pendiente'; end if;
  elsif public.current_user_role()='technician' then
    if v_order.technician_id <> auth.uid() or p_next_status <> 'cancelled' or v_order.status not in ('pending','accepted') then raise exception 'No puedes modificar este pedido'; end if;
  elsif public.current_user_role() <> 'admin' then raise exception 'No autorizado'; end if;
  if p_next_status in ('rejected','cancelled') and v_order.status in ('pending','accepted') then
    for v_item in select * from public.order_items where order_id=v_order.id loop
      update public.inventory set quantity=quantity+v_item.quantity,active=true where id=v_item.inventory_id;
    end loop;
  end if;
  update public.orders set status=p_next_status where id=v_order.id;
  return true;
end; $$;
revoke all on function public.update_order_status(uuid,text) from public;
grant execute on function public.update_order_status(uuid,text) to authenticated;

-- Solo inventario de tiendas aprobadas se ofrece al marketplace.
drop policy if exists inventory_readable on public.inventory;
create policy inventory_readable on public.inventory for select using(
  (active=true and quantity>0 and exists(select 1 from public.shops s where s.id=shop_id and s.active=true and s.status='approved'))
  or exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid())
  or public.current_user_role()='admin'
);

-- place_order reforzado: tienda aprobada, items únicos y stock bloqueado.
create or replace function public.place_order(p_shop_id uuid,p_delivery_type text,p_delivery_address text,p_items jsonb)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_order_id uuid; v_fee numeric(12,2); v_subtotal numeric(12,2):=0; v_item jsonb; v_inventory inventory%rowtype; v_qty integer; v_count integer; v_distinct integer;
begin
  if auth.uid() is null then raise exception 'No autenticado'; end if;
  if not exists(select 1 from users where id=auth.uid() and role='technician') then raise exception 'Solo un técnico puede crear pedidos'; end if;
  if p_delivery_type not in ('local','outside_zone','pickup') then raise exception 'Tipo de entrega inválido'; end if;
  if p_delivery_type <> 'pickup' and nullif(trim(coalesce(p_delivery_address,'')),'') is null then raise exception 'La dirección es obligatoria para entrega'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'El pedido debe contener productos'; end if;
  select count(*),count(distinct (x->>'inventory_id')) into v_count,v_distinct from jsonb_array_elements(p_items) x;
  if v_count <> v_distinct then raise exception 'El pedido contiene productos repetidos'; end if;
  select case p_delivery_type when 'outside_zone' then delivery_outside_fee else 0 end into v_fee from shops where id=p_shop_id and active=true and status='approved';
  if not found then raise exception 'La tienda no está disponible'; end if;
  for v_item in select * from jsonb_array_elements(p_items) loop
    begin v_qty := (v_item->>'quantity')::integer; exception when others then raise exception 'Cantidad inválida'; end;
    if v_qty <= 0 then raise exception 'Cantidad inválida'; end if;
    select * into v_inventory from inventory where id=(v_item->>'inventory_id')::uuid and shop_id=p_shop_id and active=true and quantity>0 for update;
    if not found then raise exception 'Producto no disponible en esta tienda'; end if;
    if v_inventory.quantity < v_qty then raise exception 'Stock insuficiente'; end if;
    v_subtotal := v_subtotal + (v_inventory.price*v_qty);
  end loop;
  insert into orders(technician_id,shop_id,status,delivery_type,delivery_fee,delivery_address,total)
  values(auth.uid(),p_shop_id,'pending',p_delivery_type,v_fee,case when p_delivery_type='pickup' then null else trim(p_delivery_address) end,v_subtotal+v_fee) returning id into v_order_id;
  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    select * into v_inventory from inventory where id=(v_item->>'inventory_id')::uuid and shop_id=p_shop_id and active=true for update;
    insert into order_items(order_id,inventory_id,product_id,quantity,unit_price) values(v_order_id,v_inventory.id,v_inventory.product_id,v_qty,v_inventory.price);
    update inventory set quantity=quantity-v_qty where id=v_inventory.id;
  end loop;
  return v_order_id;
end; $$;
revoke all on function public.place_order(uuid,text,text,jsonb) from public;
grant execute on function public.place_order(uuid,text,text,jsonb) to authenticated;

-- Búsqueda backend: soporta varias palabras, tildes, alias y sinónimos básicos.
create or replace function public.search_products(p_query text)
returns table(id uuid,display_name text,normalized_search text,brand text,model text,part_type text,variant text)
language sql
stable
security invoker
set search_path = public
as $$
with q as (select public.normalize_search_text(coalesce(p_query,'')) as text),
tokens as (select token from q,cross join lateral regexp_split_to_table(q.text,'\\s+') token where token<>'')
select p.id,p.display_name,p.normalized_search,pm.brand,pm.model,pt.name,pv.name
from public.products p
join public.phone_models pm on pm.id=p.phone_model_id
join public.part_types pt on pt.id=p.part_type_id
join public.part_variants pv on pv.id=p.part_variant_id
where p.active=true and pm.active=true and pt.active=true and pv.active=true
  and exists(select 1 from q where q.text<>'')
  and not exists(
    select 1 from tokens t
    where not(
      p.normalized_search ilike '%'||t.token||'%'
      or public.normalize_search_text(pm.brand) ilike '%'||t.token||'%'
      or public.normalize_search_text(pm.model) ilike '%'||t.token||'%'
      or exists(select 1 from public.phone_model_aliases a where a.phone_model_id=pm.id and a.active=true and a.normalized_alias ilike '%'||t.token||'%')
    )
  )
order by pm.brand,pm.model,pt.name,pv.name
limit 100;
$$;
