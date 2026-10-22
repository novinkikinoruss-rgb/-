create or replace function public.crm_guard_fleet_links()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if tg_table_name='crm_vehicles' then
 if new.assigned_driver_id is not null then
  if not exists(select 1 from public.crm_drivers d where d.id=new.assigned_driver_id and d.owner_id=new.owner_id and d.carrier_id is null) then raise exception 'Выберите водителя собственного автопарка';end if;
 end if;
 elsif tg_table_name='crm_driver_fines' then
 if new.trip_id is not null then
  if not exists(select 1 from public.crm_trips t where t.id=new.trip_id and t.owner_id=new.owner_id and t.driver_id=new.driver_id and t.deleted_at is null) then raise exception 'Штраф и рейс должны относиться к одному водителю';end if;
 end if;
 end if;
 return new;
end $$;
create trigger fleet_vehicle_driver_link before insert or update of assigned_driver_id on public.crm_vehicles for each row execute function public.crm_guard_fleet_links();
create trigger fleet_fine_trip_link before insert or update of trip_id,driver_id on public.crm_driver_fines for each row execute function public.crm_guard_fleet_links();
revoke all on function public.crm_guard_fleet_links() from public,anon;
grant execute on function public.crm_guard_fleet_links() to authenticated;