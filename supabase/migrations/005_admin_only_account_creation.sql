-- Celu Piezaz Dot Com: disable self-service account creation.
-- Only Supabase Auth Admin API can set app_metadata.provisioned_by_admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(new.raw_app_meta_data->>'provisioned_by_admin','false') <> 'true' then
    raise exception 'Public registration is disabled. Contact the platform administrator.';
  end if;

  insert into public.users (id, role, name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role','technician'),
    coalesce(new.raw_user_meta_data->>'name', split_part(coalesce(new.email,''),'@',1), 'Usuario'),
    new.raw_user_meta_data->>'phone'
  );
  return new;
end;
$$;
