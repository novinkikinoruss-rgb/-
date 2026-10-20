-- Initial CRM schema for Supabase PostgreSQL
create extension if not exists pgcrypto;
create table if not exists customers (id uuid primary key default gen_random_uuid(), name text not null, phone text, email text, created_at timestamptz not null default now());
create table if not exists contacts (id uuid primary key default gen_random_uuid(), customer_id uuid not null references customers(id) on delete cascade, full_name text not null, phone text, email text);
create table if not exists shipments (id uuid primary key default gen_random_uuid(), customer_id uuid not null references customers(id), origin text not null, destination text not null, cargo_description text, status text not null default 'new' check(status in ('new','planned','in_transit','delivered','cancelled')), price numeric(14,2), created_at timestamptz not null default now());
create table if not exists tasks (id uuid primary key default gen_random_uuid(), shipment_id uuid references shipments(id) on delete set null, title text not null, due_at timestamptz, done boolean not null default false);
-- Before production: configure authentication and row-level security policies.
