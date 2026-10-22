-- Контрагенты: связь исполнителя с техникой, водителями, рейсами и счетами.
alter table public.crm_vehicles add column if not exists carrier_id uuid references public.crm_carriers(id);
alter table public.crm_drivers add column if not exists carrier_id uuid references public.crm_carriers(id);
alter table public.crm_trips add column if not exists carrier_id uuid references public.crm_carriers(id);

create index if not exists crm_vehicles_carrier_idx on public.crm_vehicles(carrier_id);
create index if not exists crm_drivers_carrier_idx on public.crm_drivers(carrier_id);
create index if not exists crm_trips_carrier_date_idx on public.crm_trips(carrier_id,trip_date);

create table if not exists public.crm_counterparty_invoices (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid(),
 counterparty_id uuid not null references public.crm_carriers(id),
 invoice_number text not null,
 invoice_date date not null default current_date,
 amount numeric(14,2) not null check(amount>0),
 paid_amount numeric(14,2) not null default 0 check(paid_amount>=0 and paid_amount<=amount),
 status text not null default 'Ожидает оплаты',
 notes text,
 deleted_at timestamptz,
 created_at timestamptz not null default now(),
 unique(owner_id,counterparty_id,invoice_number)
);
alter table public.crm_counterparty_invoices enable row level security;
drop policy if exists crm_counterparty_invoices_owner on public.crm_counterparty_invoices;
create policy crm_counterparty_invoices_owner on public.crm_counterparty_invoices for all to authenticated
 using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
grant select,insert,update,delete on public.crm_counterparty_invoices to authenticated;
create index if not exists crm_counterparty_invoices_counterparty_idx on public.crm_counterparty_invoices(counterparty_id,invoice_date);
