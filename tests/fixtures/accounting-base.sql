-- Изолированный PostgreSQL для CI. Только используемая бухгалтерией часть схемы crm_*.
-- Это тестовая фикстура, не установочная схема рабочей CRM.
create schema auth;
create role anon nologin;
create role authenticated nologin;
create table auth.users(id uuid primary key,aud text,role text,email text);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema auth,public to authenticated;
grant execute on function auth.uid() to authenticated;
create table public.crm_customers(id uuid primary key default gen_random_uuid(),owner_id uuid default auth.uid(),name text not null,inn text,kpp text,legal_address text,is_archived boolean not null default false,deleted_at timestamptz);
create table public.crm_contracts(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),customer_id uuid not null references crm_customers(id),deleted_at timestamptz);
create table public.crm_sites(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),customer_id uuid not null references crm_customers(id),name text not null,loading_address text not null,unloading_address text not null,route_km numeric,deleted_at timestamptz);
create table public.crm_drivers(id uuid primary key default gen_random_uuid(),owner_id uuid default auth.uid(),full_name text not null,pay_rate_km numeric not null default 70,bonus_pct numeric not null default 13,tax_pct numeric not null default 44);
create table public.crm_orders(id uuid primary key default gen_random_uuid(),owner_id uuid default auth.uid(),customer_id uuid not null references crm_customers(id),site_id uuid references crm_sites(id),deleted_at timestamptz);
create table public.crm_trips(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),order_id uuid references crm_orders(id),customer_id uuid references crm_customers(id),site_id uuid references crm_sites(id),driver_id uuid references crm_drivers(id),trip_number text not null,trip_date date,status text not null default 'sent',service_name text,volume numeric,unit_price numeric,deleted_at timestamptz);
create table public.crm_invoices(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),customer_id uuid not null references crm_customers(id),order_id uuid references crm_orders(id),trip_id uuid references crm_trips(id),invoice_number text not null,invoice_date date not null default current_date,amount numeric not null,deleted_at timestamptz);
create table public.crm_invoice_payments(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),invoice_id uuid not null references crm_invoices(id),amount numeric not null,payment_date date not null default current_date);
create table public.crm_driver_fines(id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),driver_id uuid not null references crm_drivers(id),order_id uuid references crm_orders(id),fine_date date not null default current_date,amount numeric not null,reason text not null,paid boolean not null default false,deleted_at timestamptz);
do $$declare t text;begin
 foreach t in array array['crm_customers','crm_contracts','crm_sites','crm_drivers','crm_orders','crm_trips','crm_invoices','crm_invoice_payments','crm_driver_fines'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy own_rows on public.%I for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()))',t);
  execute format('grant select,insert,update,delete on public.%I to authenticated',t);
 end loop;
end$$;
