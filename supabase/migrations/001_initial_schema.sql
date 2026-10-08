-- Celu Piezaz Dot Com — Fase 2 / Supabase
-- PostgreSQL + Supabase Auth

create extension if not exists pgcrypto;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','shop','technician')),
  name text not null, phone text, created_at timestamptz not null default now()
);

create table public.shops (
  id uuid primary key default gen_random_uuid(), user_id uuid not null unique references public.users(id) on delete cascade,
  name text not null, address text,
  delivery_local_fee numeric(12,2) not null default 0 check (delivery_local_fee >= 0),
  delivery_outside_fee numeric(12,2) not null default 5000 check (delivery_outside_fee >= 0),
  active boolean not null default true, created_at timestamptz not null default now()
);

create table public.phone_models (
  id uuid primary key default gen_random_uuid(), brand text not null, model text not null, normalized_name text not null,
  active boolean not null default true, unique(brand, model)
);
create table public.part_types (id uuid primary key default gen_random_uuid(), name text not null unique, active boolean not null default true);
create table public.part_variants (id uuid primary key default gen_random_uuid(), part_type_id uuid not null references public.part_types(id) on delete cascade, name text not null, active boolean not null default true, unique(part_type_id,name));
create table public.products (id uuid primary key default gen_random_uuid(), phone_model_id uuid not null references public.phone_models(id), part_type_id uuid not null references public.part_types(id), part_variant_id uuid references public.part_variants(id), display_name text not null, normalized_search text not null, active boolean not null default true);
create table public.inventory (id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.shops(id) on delete cascade, product_id uuid not null references public.products(id), price numeric(12,2) not null check(price>=0), quantity integer not null default 0 check(quantity>=0), active boolean not null default true, updated_at timestamptz not null default now(), unique(shop_id,product_id));
create table public.orders (id uuid primary key default gen_random_uuid(), technician_id uuid not null references public.users(id), shop_id uuid not null references public.shops(id), status text not null default 'pending' check(status in ('pending','accepted','preparing','out_for_delivery','delivered','rejected','cancelled')), delivery_type text not null check(delivery_type in ('local','outside_zone','pickup')), delivery_fee numeric(12,2) not null default 0 check(delivery_fee>=0), delivery_address text, total numeric(12,2) not null default 0 check(total>=0), created_at timestamptz not null default now(), updated_at timestamptz not null default now());
create table public.order_items (id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade, inventory_id uuid not null references public.inventory(id), product_id uuid not null references public.products(id), quantity integer not null check(quantity>0), unit_price numeric(12,2) not null check(unit_price>=0));
create table public.demand_requests (id uuid primary key default gen_random_uuid(), technician_id uuid not null references public.users(id), product_id uuid not null references public.products(id), status text not null default 'open' check(status in ('open','notified','closed')), created_at timestamptz not null default now());

create index idx_products_search on public.products(normalized_search);
create index idx_inventory_product on public.inventory(product_id);
create index idx_orders_shop_status on public.orders(shop_id,status);
create index idx_orders_technician on public.orders(technician_id);
create index idx_demand_product_status on public.demand_requests(product_id,status);

create or replace function public.current_user_role() returns text language sql stable security definer set search_path=public as $$ select role from public.users where id=auth.uid(); $$;

alter table public.users enable row level security;
alter table public.shops enable row level security;
alter table public.phone_models enable row level security;
alter table public.part_types enable row level security;
alter table public.part_variants enable row level security;
alter table public.products enable row level security;
alter table public.inventory enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.demand_requests enable row level security;

create policy users_own_profile on public.users for select using(id=auth.uid() or public.current_user_role()='admin');
create policy admin_manages_users on public.users for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy active_shops_readable on public.shops for select using(active=true or user_id=auth.uid() or public.current_user_role()='admin');
create policy shop_owner_manages_shop on public.shops for all using(user_id=auth.uid() or public.current_user_role()='admin') with check(user_id=auth.uid() or public.current_user_role()='admin');
create policy catalog_models_readable on public.phone_models for select using(active=true or public.current_user_role()='admin');
create policy catalog_models_admin on public.phone_models for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy catalog_types_readable on public.part_types for select using(active=true or public.current_user_role()='admin');
create policy catalog_types_admin on public.part_types for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy catalog_variants_readable on public.part_variants for select using(active=true or public.current_user_role()='admin');
create policy catalog_variants_admin on public.part_variants for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy products_readable on public.products for select using(active=true or public.current_user_role()='admin');
create policy products_admin on public.products for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');
create policy inventory_readable on public.inventory for select using(active=true or exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy inventory_insert_own on public.inventory for insert with check(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy inventory_update_own on public.inventory for update using(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin') with check(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy inventory_delete_own on public.inventory for delete using(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy orders_read_participants on public.orders for select using(technician_id=auth.uid() or exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy orders_create_own on public.orders for insert with check(technician_id=auth.uid());
create policy orders_update_shop_admin on public.orders for update using(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin') with check(exists(select 1 from public.shops s where s.id=shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin');
create policy order_items_read_participants on public.order_items for select using(exists(select 1 from public.orders o where o.id=order_id and (o.technician_id=auth.uid() or exists(select 1 from public.shops s where s.id=o.shop_id and s.user_id=auth.uid()) or public.current_user_role()='admin')));
create policy order_items_create_own on public.order_items for insert with check(exists(select 1 from public.orders o where o.id=order_id and o.technician_id=auth.uid()));
create policy demand_read_own on public.demand_requests for select using(technician_id=auth.uid() or public.current_user_role()='admin');
create policy demand_create_own on public.demand_requests for insert with check(technician_id=auth.uid());
create policy demand_admin on public.demand_requests for all using(public.current_user_role()='admin') with check(public.current_user_role()='admin');

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end; $$;
create trigger inventory_touch_updated_at before update on public.inventory for each row execute function public.touch_updated_at();
create trigger orders_touch_updated_at before update on public.orders for each row execute function public.touch_updated_at();
