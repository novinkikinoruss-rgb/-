-- Keep an accepted overnight vehicle available through the end day, matching duty authorization.
create or replace function public.respectlogistic_driver_dispatch(p_token text,p_action text default 'list',p_id uuid default null,p_expected integer default null,p_record jsonb default '{}') returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;s respectlogistic_dispatch_shifts;begin
 a=respectlogistic_require_driver(p_token);
 if p_action='list' then
  update respectlogistic_dispatch_shifts set seen_at=clock_timestamp() where owner_id=a.owner_id and driver_id=a.driver_id and carrier_id is null and status='sent' and seen_at is null;
  return jsonb_build_object('dispatch_shifts',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'request_id',x.request_id,'shift_date',x.shift_date,'vehicle_id',x.vehicle_id,'starts_at',x.starts_at,'ends_at',x.ends_at,'status',x.status,'version',x.version,'sent_at',x.sent_at,'accepted_at',x.accepted_at,'response_note',x.response_note,'details',x.snapshot-'unit_price'-'customer_id'-'site_id','results',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'trip_id',r.trip_id,'volume',r.volume,'unit',r.unit,'created_at',r.created_at)) from respectlogistic_dispatch_results r where r.shift_id=x.id and r.owner_id=a.owner_id),'[]')) order by x.shift_date,x.starts_at) from respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.driver_id=a.driver_id and x.carrier_id is null and x.sent_at is not null and x.shift_date>=(clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date-30),'[]'),
   'dispatch_vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'odometer_km',v.odometer_km,'assigned_driver_id',v.assigned_driver_id,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=a.owner_id and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and exists(select 1 from respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.vehicle_id=v.id and x.driver_id=a.driver_id and x.status='accepted' and (clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date between x.shift_date and (x.ends_at at time zone (x.snapshot->>'time_zone'))::date)),'[]'));
 end if;
 perform pg_advisory_xact_lock(hashtextextended(a.owner_id::text||'-dispatch',0));
 select * into s from respectlogistic_dispatch_shifts where id=p_id and owner_id=a.owner_id and driver_id=a.driver_id and carrier_id is null for update;
 if s.id is null or s.sent_at is null or s.status='cancelled' then raise exception 'Смена недоступна или отменена';end if;
 if p_action='accept' and s.status='accepted' then return '{}';end if;
 if s.version is distinct from p_expected then raise exception 'Смена изменена диспетчером. Обновите список';end if;
 if p_action in ('accept','reject') and s.status='sent' then
  if p_action='reject' and trim(coalesce(p_record->>'note',''))='' then raise exception 'Укажите причину отказа';end if;
  update respectlogistic_dispatch_shifts set status=case when p_action='accept' then 'accepted' else 'rejected' end,accepted_at=case when p_action='accept' then clock_timestamp() else null end,response_note=left(coalesce(p_record->>'note',''),2000),version=version+1,modified_at=clock_timestamp() where id=s.id;
 elsif p_action='finish' and s.status='accepted' then
  if s.shift_date>(clock_timestamp() at time zone (s.snapshot->>'time_zone'))::date then raise exception 'Завершить работу можно только в дату смены';end if;
  update respectlogistic_dispatch_shifts set status='completed',version=version+1,modified_at=clock_timestamp() where id=s.id;
 else raise exception 'Действие недоступно для текущего статуса';end if;
 insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action,detail) values(a.owner_id,s.request_id,s.id,'driver_'||p_action,jsonb_build_object('driver_id',a.driver_id,'version',s.version,'snapshot',s.snapshot));
 return '{}';
end$$;

