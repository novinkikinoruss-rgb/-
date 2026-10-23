-- Scope uniqueness too: a plate in another CRM must not prevent adding our vehicle.
alter table public.crm_vehicles drop constraint crm_vehicles_plate_key;
create unique index crm_vehicle_app_plate_unique on public.crm_vehicles(owner_id,coalesce(app_scope,'legacy'),plate);
create function public.respectlogistic_guard_fleet_scope() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare item jsonb=to_jsonb(new);carrier uuid=nullif(item->>'carrier_id','')::uuid;driver uuid=nullif(item->>'assigned_driver_id','')::uuid;
begin
 if item->>'app_scope' is distinct from 'respectlogistic' then return new;end if;
 if carrier is not null and not exists(select 1 from public.rl_crm_carriers c where c.id=carrier and c.owner_id=new.owner_id) then raise exception 'Контрагент относится к другой CRM';end if;
 if driver is not null and not exists(select 1 from public.rl_crm_drivers d where d.id=driver and d.owner_id=new.owner_id and d.carrier_id is null) then raise exception 'Водитель относится к другой CRM';end if;
 return new;
end $$;
create trigger respectlogistic_driver_scope before insert or update on public.crm_drivers for each row execute function public.respectlogistic_guard_fleet_scope();
create trigger respectlogistic_vehicle_scope before insert or update on public.crm_vehicles for each row execute function public.respectlogistic_guard_fleet_scope();
create function public.respectlogistic_reset_trip_documents() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if new.app_scope='respectlogistic' and (old.trip_date is distinct from new.trip_date or old.vehicle_id is distinct from new.vehicle_id or old.driver_id is distinct from new.driver_id or old.site_id is distinct from new.site_id or old.customer_id is distinct from new.customer_id or old.service_name is distinct from new.service_name) then new.documents_confirmed=false;end if;
 return new;
end $$;
create trigger respectlogistic_trip_documents_reset before update on public.crm_trips for each row execute function public.respectlogistic_reset_trip_documents();
revoke all on function public.rl_crm_prepare_payroll(uuid[]),public.rl_crm_pay_driver_accruals(uuid[],text,numeric,date),public.rl_crm_apply_driver_fines(uuid[],uuid[],date),public.rl_crm_complete_fleet_maintenance(uuid,text,numeric,date,text),public.respectlogistic_guard_fleet_scope(),public.respectlogistic_reset_trip_documents() from public,anon;
grant execute on function public.rl_crm_prepare_payroll(uuid[]),public.rl_crm_pay_driver_accruals(uuid[],text,numeric,date),public.rl_crm_apply_driver_fines(uuid[],uuid[],date),public.rl_crm_complete_fleet_maintenance(uuid,text,numeric,date,text),public.respectlogistic_guard_fleet_scope(),public.respectlogistic_reset_trip_documents() to authenticated;
notify pgrst,'reload schema';
