-- Celu Piezaz Dot Com — esquema MVP
-- PostgreSQL / Supabase compatible

create table users (
  id uuid primary key,
  role text not null check (role in ('admin','shop','technician')),
  name text not null,
  phone text,
  created_at timestamptz not null default now()
);

create table shops (
  id uuid primary key,
  user_id uuid not null references users(id),
  name text not null,
  address text,
  delivery_local_fee numeric(12,2) not null default 0,
  delivery_outside_fee numeric(12,2) not null default 5000,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table phone_models (
  id uuid primary key,
  brand text not null,
  model text not null,
  normalized_name text not null,
  active boolean not null default true,
  unique(brand, model)
);

create table part_types (
  id uuid primary key,
  name text not null unique,
  active boolean not null default true
);

create table part_variants (
  id uuid primary key,
  part_type_id uuid not null references part_types(id),
  name text not null,
  active boolean not null default true,
  unique(part_type_id, name)
);

create table products (
  id uuid primary key,
  phone_model_id uuid not null references phone_models(id),
  part_type_id uuid not null references part_types(id),
  part_variant_id uuid references part_variants(id),
  display_name text not null,
  normalized_search text not null,
  active boolean not null default true
);

create table inventory (
  id uuid primary key,
  shop_id uuid not null references shops(id),
  product_id uuid not null references products(id),
  price numeric(12,2) not null check (price >= 0),
  quantity integer not null default 0 check (quantity >= 0),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(shop_id, product_id)
);

create table orders (
  id uuid primary key,
  technician_id uuid not null references users(id),
  shop_id uuid not null references shops(id),
  status text not null check (status in ('pending','accepted','preparing','out_for_delivery','delivered','rejected','cancelled')),
  delivery_type text not null check (delivery_type in ('local','outside_zone','pickup')),
  delivery_fee numeric(12,2) not null default 0,
  delivery_address text,
  total numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table order_items (
  id uuid primary key,
  order_id uuid not null references orders(id) on delete cascade,
  inventory_id uuid not null references inventory(id),
  product_id uuid not null references products(id),
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0)
);

create table demand_requests (
  id uuid primary key,
  technician_id uuid not null references users(id),
  product_id uuid not null references products(id),
  status text not null default 'open' check (status in ('open','notified','closed')),
  created_at timestamptz not null default now()
);

create index idx_products_search on products(normalized_search);
create index idx_inventory_product on inventory(product_id);
create index idx_orders_shop_status on orders(shop_id, status);
create index idx_orders_technician on orders(technician_id);
create index idx_demand_product_status on demand_requests(product_id, status);