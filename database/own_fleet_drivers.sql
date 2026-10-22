-- Own fleet and drivers; existing payroll ledger remains authoritative.
alter table public.crm_drivers
 add column if not exists birth_date date,
 add column if not exists notes text not null default '',
 add column if not exists employment_kind text not null default 'official' check(employment_kind in ('official','self_employed')),
 add column if not exists job_status text not null default 'active' check(job_status in ('active','vacation','dismissed','blacklisted')),
 add column if not exists archived_at timestamptz,
 add column if not exists contract_number text,
 add column if not exists contract_date date;
alter table public.crm_vehicles
 add column if not exists vin text,
 add column if not exists manufacture_year integer check(manufacture_year between 1900 and 2200),
 add column if not exists assigned_driver_id uuid references public.crm_drivers(id),
 add column if not exists notes text not null default '',
 add column if not exists photo_url text,
 add column if not exists service_interval_km numeric not null default 15000 check(service_interval_km>0),
 add column if not exists oil_interval_km numeric not null default 15000 check(oil_interval_km>0),
 add column if not exists next_oil_km numeric,
 add column if not exists reminder_before_km numeric not null default 1000 check(reminder_before_km>=0),
 add column if not exists archived_at timestamptz;
create index if not exists crm_vehicles_assigned_driver_idx on public.crm_vehicles(assigned_driver_id);
create table if not exists public.crm_fleet_maintenance(
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null default auth.uid(),
 vehicle_id uuid not null references public.crm_vehicles(id),
 kind text not null check(kind in ('service','oil')),
 performed_date date not null default current_date,
 odometer_km numeric not null check(odometer_km>=0),
 notes text not null default '',
 created_at timestamptz not null default now()
);
alter table public.crm_fleet_maintenance enable row level security;
create policy fleet_maintenance_owner on public.crm_fleet_maintenance for select to authenticated using(owner_id=(select auth.uid()));
create policy fleet_maintenance_insert on public.crm_fleet_maintenance for insert to authenticated with check(owner_id=(select auth.uid()) and exists(select 1 from public.crm_vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid()) and v.carrier_id is null and not v.is_subcontractor_vehicle));
grant select,insert on public.crm_fleet_maintenance to authenticated;
create index crm_fleet_maintenance_owner_idx on public.crm_fleet_maintenance(owner_id,vehicle_id);
create index crm_fleet_maintenance_vehicle_idx on public.crm_fleet_maintenance(vehicle_id);
create or replace function public.crm_complete_fleet_maintenance(p_vehicle_id uuid,p_kind text,p_odometer numeric,p_date date,p_notes text default '')
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v public.crm_vehicles; result uuid;
begin
 if auth.uid() is null or p_kind not in ('service','oil') or p_date is null or p_date>current_date or p_odometer is null or p_odometer<0 or p_odometer::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте дату, пробег и вид обслуживания'; end if;
 select * into v from public.crm_vehicles where id=p_vehicle_id and owner_id=auth.uid() and carrier_id is null and not is_subcontractor_vehicle and archived_at is null for update;
 if v.id is null then raise exception 'Техника недоступна'; end if;
 if p_odometer<v.odometer_km then raise exception 'Пробег не может быть меньше текущего'; end if;
 insert into public.crm_fleet_maintenance(vehicle_id,kind,performed_date,odometer_km,notes) values(v.id,p_kind,p_date,p_odometer,coalesce(p_notes,'')) returning id into result;
 update public.crm_vehicles set odometer_km=p_odometer,
 next_service_km=case when p_kind='service' then p_odometer+service_interval_km else next_service_km end,
 next_oil_km=case when p_kind='oil' then p_odometer+oil_interval_km else next_oil_km end where id=v.id;
 return result;
end $$;
revoke all on function public.crm_complete_fleet_maintenance(uuid,text,numeric,date,text) from public,anon;
grant execute on function public.crm_complete_fleet_maintenance(uuid,text,numeric,date,text) to authenticated;
-- Persist a driver's agreed rate, not the old constant 70, in new accruals.
create or replace function public.crm_sync_payroll()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.crm_sites;d public.crm_drivers;o public.crm_orders;v_base numeric;v_bonus numeric;v_customer uuid;v_site uuid;
begin
 if new.status<>'delivered' or new.deleted_at is not null then
  if exists(select 1 from public.crm_payroll_payments p join public.crm_payroll_accruals a on a.id=p.accrual_id where a.trip_id=new.id) or exists(select 1 from public.crm_payroll_deductions p join public.crm_payroll_accruals a on a.id=p.accrual_id where a.trip_id=new.id) then raise exception 'Рейс уже оплачен: сначала нужна бухгалтерская корректировка'; end if;
  update public.crm_payroll_accruals set active=false where trip_id=new.id and owner_id=new.owner_id;return new;
 end if;
 if new.order_id is not null then select * into o from public.crm_orders where id=new.order_id and owner_id=new.owner_id;end if;
 v_site=coalesce(new.site_id,o.site_id);v_customer=coalesce(new.customer_id,o.customer_id);
 select * into s from public.crm_sites where id=v_site and owner_id=new.owner_id and deleted_at is null;
 select * into d from public.crm_drivers where id=new.driver_id and owner_id=new.owner_id;
 if s.id is null or s.customer_id is distinct from v_customer or d.id is null or s.route_km is null or new.trip_date is null then raise exception 'Для завершения рейса укажите водителя, заказчика, дату, объект и расстояние в одну сторону'; end if;
 if exists(select 1 from public.crm_payroll_accruals where trip_id=new.id) then
  if exists(select 1 from public.crm_payroll_accruals where trip_id=new.id and (driver_id<>new.driver_id or site_id<>v_site or customer_id<>v_customer or accrual_date<>new.trip_date)) then raise exception 'По рейсу уже зафиксировано начисление; требуется бухгалтерская корректировка'; end if;
  update public.crm_payroll_accruals set active=true where trip_id=new.id and owner_id=new.owner_id;return new;
 end if;
 if d.pay_rate_km<0 then raise exception 'Ставка водителя не может быть отрицательной';end if;
 v_base=round(s.route_km*d.pay_rate_km,2);v_bonus=round(v_base*d.bonus_pct/100,2);
 insert into public.crm_payroll_accruals(owner_id,trip_id,driver_id,customer_id,site_id,accrual_date,distance_km,rate,bonus_pct,tax_pct,base,bonus,tax)
 values(new.owner_id,new.id,d.id,v_customer,v_site,new.trip_date,s.route_km,d.pay_rate_km,d.bonus_pct,d.tax_pct,v_base,v_bonus,round((v_base+v_bonus)*d.tax_pct/100,2));
 return new;
end $$;
notify pgrst,'reload schema';