CREATE OR REPLACE FUNCTION public.respectlogistic_duty_action(p_token text, p_vehicle uuid, p_action text, p_odometer numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare a respectlogistic_driver_accounts;v crm_vehicles;d respectlogistic_driver_duties;begin
 a=respectlogistic_require_driver(p_token);
 -- Lock the vehicle so a concurrent start cannot race an end/start on this vehicle.
 select * into v from crm_vehicles where id=p_vehicle and owner_id=a.owner_id and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle for update;
 if v.id is null or p_odometer is null or p_odometer<0 or p_odometer>100000000 or p_odometer::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте машину и пробег';end if;
 select * into d from respectlogistic_driver_duties where driver_id=a.driver_id and ended_at is null for update;
 if p_action='start' then
  if d.id is not null then raise exception 'Сначала завершите текущую смену';end if;
  if (v.assigned_driver_id is distinct from a.driver_id and not exists(select 1 from public.respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.driver_id=a.driver_id and x.vehicle_id=v.id and x.carrier_id is null and x.status='accepted' and (clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date between x.shift_date and (x.ends_at at time zone (x.snapshot->>'time_zone'))::date)) or v.archived_at is not null or p_odometer<coalesce(v.odometer_km,0) then raise exception 'Машина не закреплена за вами или пробег меньше текущего';end if;
  insert into respectlogistic_driver_duties(owner_id,driver_id,vehicle_id,start_odometer) values(a.owner_id,a.driver_id,v.id,p_odometer) returning id into d.id;
 elsif p_action='end' then
  if d.id is null or d.vehicle_id<>v.id or p_odometer<d.start_odometer then raise exception 'Нет открытой смены на этой машине либо пробег уменьшился';end if;
  update respectlogistic_driver_duties set ended_at=clock_timestamp(),end_odometer=p_odometer where id=d.id;
 else raise exception 'Недоступное действие';end if;
 return d.id;
end$function$;
