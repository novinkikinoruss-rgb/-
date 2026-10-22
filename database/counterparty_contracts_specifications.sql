create table public.crm_counterparty_contracts (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid(),
 counterparty_id uuid not null references public.crm_carriers(id),
 number text not null check(length(trim(number))>0),
 kind text not null default 'transport' check(kind in ('transport','supply')),
 date date not null default current_date,
 end_date date check(end_date is null or end_date>=date),
 notes text not null default '',
 created_at timestamptz not null default now(),
 unique(owner_id,counterparty_id,number)
);
create table public.crm_counterparty_specifications (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid(),
 contract_id uuid not null references public.crm_counterparty_contracts(id),
 number text not null check(length(trim(number))>0),
 date date not null default current_date,
 services jsonb not null check(jsonb_typeof(services)='array' and jsonb_array_length(services) between 1 and 100),
 created_at timestamptz not null default now(),
 unique(owner_id,contract_id,number)
);
alter table public.crm_counterparty_contracts enable row level security;
alter table public.crm_counterparty_specifications enable row level security;
create policy counterparty_contract_owner on public.crm_counterparty_contracts for all to authenticated
 using(owner_id=(select auth.uid()))
 with check(owner_id=(select auth.uid()) and exists(select 1 from public.crm_carriers c where c.id=counterparty_id and c.owner_id=(select auth.uid())));
create policy counterparty_specification_owner on public.crm_counterparty_specifications for all to authenticated
 using(owner_id=(select auth.uid()))
 with check(owner_id=(select auth.uid()) and exists(select 1 from public.crm_counterparty_contracts c where c.id=contract_id and c.owner_id=(select auth.uid()) and date>=c.date and (c.end_date is null or date<=c.end_date)));
grant select,insert,update on public.crm_counterparty_contracts,public.crm_counterparty_specifications to authenticated;
create index counterparty_contract_owner_idx on public.crm_counterparty_contracts(owner_id,counterparty_id);
create index counterparty_specification_owner_idx on public.crm_counterparty_specifications(owner_id,contract_id);
create index counterparty_contract_carrier_idx on public.crm_counterparty_contracts(counterparty_id);
create index counterparty_specification_contract_idx on public.crm_counterparty_specifications(contract_id);
alter table public.crm_counterparty_invoices add column if not exists due_date date;
notify pgrst,'reload schema';
