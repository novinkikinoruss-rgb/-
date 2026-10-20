-- Transport CRM: phase 2 schema (Supabase PostgreSQL).
-- Apply after database/schema.sql. RLS enabled without public policies: deny by default.
create table if not exists contractors (
 id uuid primary key default gen_random_uuid(),
 kind text not null check (kind in ('customer','carrier')),
 name text not null, inn varchar(12), kpp varchar(9), ogrn varchar(15),
 phone text, email text, address text, credit_days integer not null default 0,
 is_blocked boolean not null default false, created_at timestamptz not null default now()
);
create unique index if not exists contractors_kind_inn_idx on contractors(kind,inn) where inn is not null;
create table if not exists contracts (
 id uuid primary key default gen_random_uuid(),
 contractor_id uuid not null references contractors(id),
 contract_number text not null, start_date date, end_date date,
 created_at timestamptz not null default now(),
 unique(contractor_id,contract_number)
);
create table if not exists vehicles (
 id uuid primary key default gen_random_uuid(), plate text not null unique,
 brand text, model text, vehicle_type text not null default 'truck',
 mileage_km integer not null default 0 check(mileage_km>=0),
 next_service_km integer, status text not null default 'available',
 created_at timestamptz not null default now()
);
create table if not exists drivers (
 id uuid primary key default gen_random_uuid(), full_name text not null,
 phone text, license_number text, active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists transport_orders (
 id uuid primary key default gen_random_uuid(),
 order_number text not null unique,
 customer_id uuid not null references contractors(id),
 carrier_id uuid references contractors(id),
 vehicle_id uuid references vehicles(id),
 driver_id uuid references drivers(id),
 loading_address text not null, unloading_address text not null,
 planned_loading_at timestamptz, delivered_at timestamptz,
 cargo_description text, distance_km numeric(12,2) check(distance_km>=0),
 customer_rate numeric(14,2) not null default 0,
 carrier_rate numeric(14,2) not null default 0,
 fuel_cost numeric(14,2) not null default 0,
 other_cost numeric(14,2) not null default 0,
 status text not null default 'new' check(status in ('new','confirmed','assigned','in_transit','completed','cancelled')),
 created_at timestamptz not null default now()
);
create index if not exists transport_orders_customer_idx on transport_orders(customer_id);
create index if not exists transport_orders_status_idx on transport_orders(status);
create table if not exists fuel_transactions (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references vehicles(id),
 order_id uuid references transport_orders(id),
 fueled_at timestamptz not null default now(),
 liters numeric(12,3) not null check(liters>0),
 amount numeric(14,2) not null check(amount>=0)
);
create table if not exists maintenance (
 id uuid primary key default gen_random_uuid(),
 vehicle_id uuid not null references vehicles(id),
 serviced_at date not null, mileage_km integer,
 description text not null, cost numeric(14,2) not null default 0
);
create table if not exists transport_documents (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references transport_orders(id),
 doc_type text not null, storage_path text not null,
 uploaded_at timestamptz not null default now()
);
create table if not exists audit_log (
 id bigint generated always as identity primary key,
 actor_id uuid, table_name text not null, record_id text not null,
 operation text not null, changes jsonb,
 occurred_at timestamptz not null default now()
);
-- These tables must remain inaccessible through the browser API
-- until tenant-aware RLS policies and authenticated roles are implemented.
alter table customers enable row level security;
alter table contacts enable row level security;
alter table shipments enable row level security;
alter table tasks enable row level security;
alter table contractors enable row level security;
alter table contracts enable row level security;
alter table vehicles enable row level security;
alter table drivers enable row level security;
alter table transport_orders enable row level security;
alter table fuel_transactions enable row level security;
alter table maintenance enable row level security;
alter table transport_documents enable row level security;
alter table audit_log enable row level security;
