-- Celu Piezaz Dot Com — perfil inicial de usuario.
-- Se ejecuta después de que Supabase Auth cree el usuario.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

alter table public.users
  add constraint users_role_metadata_check
  check (role in ('admin','shop','technician'));
