-- Enforce approved and active shops in PostgreSQL, not only in the client-side query.
drop policy if exists inventory_readable on public.inventory;
create policy inventory_readable on public.inventory
for select to authenticated
using (
  auth.uid() is not null and (
    public.current_user_role() = 'admin'
    or (
      public.current_user_role() = 'technician'
      and active = true
      and exists (
        select 1 from public.shops s
        where s.id = public.inventory.shop_id
          and s.active = true
          and s.status = 'approved'
      )
    )
    or exists (
      select 1 from public.shops s
      where s.id = public.inventory.shop_id and s.user_id = auth.uid()
    )
  )
);
