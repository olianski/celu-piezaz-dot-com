-- Public signup is disabled; only a short-lived, server-created token can authorize account creation.
create table if not exists public.account_authorization_tokens (
  token uuid primary key,
  email text not null,
  role text not null check (role in ('technician','shop')),
  full_name text not null,
  phone text,
  expires_at timestamptz not null default (now() + interval '5 minutes')
);
alter table public.account_authorization_tokens enable row level security;
revoke all on public.account_authorization_tokens from anon, authenticated, public;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v record; t text;
begin
  t := new.raw_user_meta_data->>'_account_token';
  if t is null or t !~* '^[0-9a-f-]{36}$' then
    raise exception 'Public registration is disabled. Contact the administrator.';
  end if;
  select token,email,role,full_name,phone into v
  from public.account_authorization_tokens
  where token=t::uuid and email=lower(new.email) and expires_at>now()
  for update;
  if not found then raise exception 'Account creation was not authorized.'; end if;
  insert into public.users(id,role,name,phone) values(new.id,v.role,v.full_name,v.phone);
  delete from public.account_authorization_tokens where token=v.token;
  return new;
end;
$$;
