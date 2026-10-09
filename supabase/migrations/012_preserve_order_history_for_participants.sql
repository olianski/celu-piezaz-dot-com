-- Keep past order descriptions and participant contact details visible to order participants only.
begin;

drop policy if exists users_own_profile on public.users;
create policy users_own_profile on public.users
for select to authenticated
using (
  id = auth.uid()
  or public.current_user_role() = 'admin'
  or exists (
    select 1 from public.orders o
    join public.shops s on s.id = o.shop_id
    where o.technician_id = public.users.id and s.user_id = auth.uid()
  )
);

drop policy if exists products_readable on public.products;
create policy products_readable on public.products
for select to authenticated
using (
  active = true
  or public.current_user_role() = 'admin'
  or exists (
    select 1 from public.order_items oi
    join public.orders o on o.id = oi.order_id
    where oi.product_id = public.products.id
      and (o.technician_id = auth.uid()
        or exists (select 1 from public.shops s where s.id = o.shop_id and s.user_id = auth.uid()))
  )
);

drop policy if exists catalog_models_readable on public.phone_models;
create policy catalog_models_readable on public.phone_models
for select to authenticated
using (
  active = true
  or public.current_user_role() = 'admin'
  or exists (
    select 1 from public.products p
    join public.order_items oi on oi.product_id = p.id
    join public.orders o on o.id = oi.order_id
    where p.phone_model_id = public.phone_models.id
      and (o.technician_id = auth.uid()
        or exists (select 1 from public.shops s where s.id = o.shop_id and s.user_id = auth.uid()))
  )
);

drop policy if exists catalog_types_readable on public.part_types;
create policy catalog_types_readable on public.part_types
for select to authenticated
using (
  active = true
  or public.current_user_role() = 'admin'
  or exists (
    select 1 from public.products p
    join public.order_items oi on oi.product_id = p.id
    join public.orders o on o.id = oi.order_id
    where p.part_type_id = public.part_types.id
      and (o.technician_id = auth.uid()
        or exists (select 1 from public.shops s where s.id = o.shop_id and s.user_id = auth.uid()))
  )
);

drop policy if exists catalog_variants_readable on public.part_variants;
create policy catalog_variants_readable on public.part_variants
for select to authenticated
using (
  active = true
  or public.current_user_role() = 'admin'
  or exists (
    select 1 from public.products p
    join public.order_items oi on oi.product_id = p.id
    join public.orders o on o.id = oi.order_id
    where p.part_variant_id = public.part_variants.id
      and (o.technician_id = auth.uid()
        or exists (select 1 from public.shops s where s.id = o.shop_id and s.user_id = auth.uid()))
  )
);

commit;
