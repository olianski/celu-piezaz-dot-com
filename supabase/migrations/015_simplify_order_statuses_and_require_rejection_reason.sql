-- Simplifica el flujo de pedidos y exige motivo al rechazar.
begin;
drop function if exists public.update_order_status(uuid,text);
create function public.update_order_status(
  p_order_id uuid,
  p_next_status text,
  p_rejection_reason text default null
)
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
    update public.orders set status='accepted',rejection_reason=null,updated_at=now() where id=v_order.id;
  elsif v_order.status='pending' and p_next_status='rejected' then
    if nullif(trim(coalesce(p_rejection_reason,'')), '') is null then raise exception 'Debes indicar el motivo del rechazo'; end if;
    perform set_config('app.internal_stock_change','true',true);
    update public.inventory i set quantity=i.quantity+oi.quantity,active=p.active,updated_at=now()
    from public.order_items oi join public.products p on p.id=oi.product_id
    where oi.order_id=v_order.id and i.id=oi.inventory_id;
    perform set_config('app.internal_stock_change','false',true);
    update public.orders set status='rejected',rejection_reason=trim(p_rejection_reason),updated_at=now() where id=v_order.id;
  elsif v_order.status in ('accepted','preparing','out_for_delivery') and p_next_status='delivered' then
    update public.orders set status='delivered',updated_at=now() where id=v_order.id;
  else raise exception 'Cambio de estado no permitido'; end if;
  return true;
end;
$$;
revoke all on function public.update_order_status(uuid,text,text) from public,anon;
grant execute on function public.update_order_status(uuid,text,text) to authenticated;
commit;