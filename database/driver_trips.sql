create table public.respectlogistic_driver_trip_events(
 id bigint generated always as identity primary key,owner_id uuid not null references auth.users,
 driver_id uuid not null references public.crm_drivers,trip_id uuid not null references public.crm_trips,
 stage text not null check(stage in ('accepted','loading','on_route','unloading','completed')),
 created_at timestamptz not null default clock_timestamp()
);
alter table public.respectlogistic_driver_trip_events enable row level security;
revoke all on public.respectlogistic_driver_trip_events from public,anon,authenticated;
create policy driver_trip_events_owner on public.respectlogistic_driver_trip_events for select to authenticated using(owner_id=(select auth.uid()));
grant select on public.respectlogistic_driver_trip_events to authenticated;
create index driver_trip_event_trip on public.respectlogistic_driver_trip_events(trip_id,id desc);
create index driver_trip_event_owner on public.respectlogistic_driver_trip_events(owner_id);
create index driver_trip_event_driver on public.respectlogistic_driver_trip_events(driver_id);

create function public.respectlogistic_driver_trips(p_token text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;begin
 a=respectlogistic_require_driver(p_token);
 return jsonb_build_object('driver_trips',coalesce((select jsonb_agg(jsonb_build_object(
 'id',t.id,'trip_number',t.trip_number,'trip_date',t.trip_date,'status',t.status,'modified_at',t.modified_at,
 'service_name',t.service_name,'vehicle_id',t.vehicle_id,'plate',v.plate,'volume',t.volume,'unit',t.unit,
 'loading_address',t.loading_address,'unloading_address',t.unloading_address,'route_km',s.route_km,
 'object',s.name,'customer',c.name,'documents_confirmed',t.documents_confirmed,
 'stage',case when t.status='delivered' then 'completed' when t.status='assigned' then '' else coalesce((select stage from respectlogistic_driver_trip_events e where e.trip_id=t.id and e.owner_id=a.owner_id and e.driver_id=a.driver_id order by e.id desc limit 1),case when t.status='sent' then 'accepted' when t.status='delivered' then 'completed' else '' end) end
 ) order by t.trip_date desc,t.trip_number)
 from crm_trips t join crm_vehicles v on v.id=t.vehicle_id and v.owner_id=a.owner_id and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle
 join crm_sites s on s.id=t.site_id and s.owner_id=a.owner_id and s.app_scope='respectlogistic'
 join crm_customers c on c.id=t.customer_id and c.owner_id=a.owner_id and c.app_scope='respectlogistic'
 where t.owner_id=a.owner_id and t.app_scope='respectlogistic' and t.driver_id=a.driver_id and t.carrier_id is null and t.deleted_at is null and (t.status in ('assigned','sent') or t.trip_date>=current_date-30)),'[]'));
end$$;

create function public.respectlogistic_driver_trip_stage(p_token text,p_id uuid,p_stage text,p_expected timestamptz) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;t crm_trips;last_stage text;next_stage text;previous_subject text=current_setting('request.jwt.claim.sub',true);begin
 a=respectlogistic_require_driver(p_token);
 select * into t from crm_trips where id=p_id and owner_id=a.owner_id and driver_id=a.driver_id and app_scope='respectlogistic' and carrier_id is null and deleted_at is null for update;
 if t.id is null or t.status='cancelled' then raise exception 'Рейс недоступен или отменён';end if;
 if not exists(select 1 from crm_vehicles where id=t.vehicle_id and owner_id=a.owner_id and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null) then raise exception 'Машина недоступна';end if;
 if t.trip_date>current_date then raise exception 'Работу по рейсу можно начать в его дату';end if;
 select stage into last_stage from respectlogistic_driver_trip_events where trip_id=t.id and owner_id=a.owner_id and driver_id=a.driver_id order by id desc limit 1;
 last_stage=case when t.status='assigned' then '' when t.status='delivered' then 'completed' else coalesce(last_stage,'accepted') end;
 if p_stage=last_stage then return;end if;
 if p_expected is null or t.modified_at is distinct from p_expected then raise exception 'Рейс изменён диспетчером. Обновите список';end if;
 next_stage=case last_stage when '' then 'accepted' when 'accepted' then 'loading' when 'loading' then 'on_route' when 'on_route' then 'unloading' when 'unloading' then 'completed' else null end;
 if p_stage is null or p_stage is distinct from next_stage or t.status='delivered' then raise exception 'Соблюдайте последовательность этапов рейса';end if;
 if not exists(select 1 from respectlogistic_driver_duties where owner_id=a.owner_id and driver_id=a.driver_id and vehicle_id=t.vehicle_id and ended_at is null) then raise exception 'Сначала начните смену на машине рейса';end if;
 -- Existing payroll/accounting triggers require the owner subject. Set it only inside this
 -- validated operation, then restore it; no owner JWT or arbitrary mutation is exposed.
 perform set_config('request.jwt.claim.sub',a.owner_id::text,true);
 update crm_trips set status=case when p_stage='completed' then 'delivered' else 'sent' end,modified_at=clock_timestamp() where id=t.id;
 insert into respectlogistic_driver_trip_events(owner_id,driver_id,trip_id,stage) values(a.owner_id,a.driver_id,t.id,p_stage);
 perform set_config('request.jwt.claim.sub',coalesce(previous_subject,''),true);
end$$;
revoke all on function public.respectlogistic_driver_trips(text),public.respectlogistic_driver_trip_stage(text,uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.respectlogistic_driver_trips(text),public.respectlogistic_driver_trip_stage(text,uuid,text,timestamptz) to anon;
notify pgrst,'reload schema';
