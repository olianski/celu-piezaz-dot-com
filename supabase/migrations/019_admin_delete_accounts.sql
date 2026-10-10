-- Eliminación definitiva de cuentas de técnicos y tiendas, con limpieza transaccional.
-- Elimina también el historial de pedidos asociado, solicitudes y publicaciones.
create or replace function public.admin_delete_account(p_user_id uuid, p_admin_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_role text;
  v_shop_ids uuid[];
begin
  if p_user_id is null or p_admin_id is null then
    raise exception 'Falta identificar la cuenta que se eliminará.';
  end if;
  if p_user_id = p_admin_id then
    raise exception 'No puedes eliminar tu propia cuenta de administrador.';
  end if;

  if not exists (select 1 from public.users where id = p_admin_id and role = 'admin') then
    raise exception 'Solo un administrador puede eliminar cuentas.';
  end if;

  select role into v_role from public.users where id = p_user_id;
  if v_role is null then
    raise exception 'No se encontró la cuenta.';
  end if;
  if v_role not in ('technician', 'shop') then
    raise exception 'Solo se pueden eliminar técnicos o tiendas.';
  end if;

  select coalesce(array_agg(id), '{}'::uuid[]) into v_shop_ids
  from public.shops where user_id = p_user_id;

  -- Los pedidos deben borrarse primero por sus claves foráneas restrictivas.
  delete from public.orders
  where technician_id = p_user_id
     or shop_id = any(v_shop_ids);

  delete from public.demand_requests where technician_id = p_user_id;

  -- Las publicaciones se eliminan al borrar la ficha de tienda (CASCADE).
  delete from public.shops where user_id = p_user_id;
  delete from public.users where id = p_user_id;
  delete from auth.users where id = p_user_id;

  return true;
end;
$$;

revoke all on function public.admin_delete_account(uuid, uuid) from public, anon, authenticated;
grant execute on function public.admin_delete_account(uuid, uuid) to service_role;
