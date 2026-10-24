-- Driver attribution uses recorded duty intervals, never today's vehicle assignment.
create table public.respectlogistic_driver_duties(
 id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users,
 driver_id uuid not null references public.crm_drivers, vehicle_id uuid not null references public.crm_vehicles,
 started_at timestamptz not null default clock_timestamp(), ended_at timestamptz,
 start_odometer numeric not null check(start_odometer>=0), end_odometer numeric,
 check(ended_at is null or ended_at>=started_at),check(end_odometer is null or end_odometer>=start_odometer)
);
create unique index driver_one_open_duty on public.respectlogistic_driver_duties(driver_id) where ended_at is null;
create unique index vehicle_one_open_duty on public.respectlogistic_driver_duties(vehicle_id) where ended_at is null;
create index duty_vehicle_period on public.respectlogistic_driver_duties(vehicle_id,started_at,ended_at);
create index duty_owner on public.respectlogistic_driver_duties(owner_id);
create table public.respectlogistic_road_fines(
 id uuid primary key,owner_id uuid not null references auth.users,vehicle_id uuid not null references public.crm_vehicles,
 driver_id uuid references public.crm_drivers,duty_id uuid references public.respectlogistic_driver_duties,
 violation_at timestamptz not null,location text not null,reason text not null,notice_number text not null,
 amount numeric not null check(amount>0 and amount<=10000000),assignment text not null check(assignment in ('duty','manual','unassigned')),
 manual_reason text not null default '',acknowledged_at timestamptz,dispute text not null default '',
 created_at timestamptz not null default clock_timestamp(),modified_at timestamptz not null default clock_timestamp(),
 unique(owner_id,notice_number)
);
alter table public.respectlogistic_driver_duties enable row level security;
alter table public.respectlogistic_road_fines enable row level security;
revoke all on public.respectlogistic_driver_duties,public.respectlogistic_road_fines from public,anon,authenticated;
create policy duty_owner on public.respectlogistic_driver_duties for select to authenticated using(owner_id=(select auth.uid()));
create policy road_fine_owner on public.respectlogistic_road_fines for select to authenticated using(owner_id=(select auth.uid()));
grant select on public.respectlogistic_driver_duties,public.respectlogistic_road_fines to authenticated;
create index road_fine_driver on public.respectlogistic_road_fines(driver_id);
create index road_fine_vehicle on public.respectlogistic_road_fines(vehicle_id);

create function public.respectlogistic_duty_action(p_token text,p_vehicle uuid,p_action text,p_odometer numeric) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;v crm_vehicles;d respectlogistic_driver_duties;begin
 a=respectlogistic_require_driver(p_token);
 -- Lock the vehicle so a concurrent start cannot race an end/start on this vehicle.
 select * into v from crm_vehicles where id=p_vehicle and owner_id=a.owner_id and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle for update;
 if v.id is null or p_odometer is null or p_odometer<0 or p_odometer>100000000 or p_odometer::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте машину и пробег';end if;
 select * into d from respectlogistic_driver_duties where driver_id=a.driver_id and ended_at is null for update;
 if p_action='start' then
  if d.id is not null then raise exception 'Сначала завершите текущую смену';end if;
  if v.assigned_driver_id is distinct from a.driver_id or v.archived_at is not null or p_odometer<coalesce(v.odometer_km,0) then raise exception 'Машина не закреплена за вами или пробег меньше текущего';end if;
  insert into respectlogistic_driver_duties(owner_id,driver_id,vehicle_id,start_odometer) values(a.owner_id,a.driver_id,v.id,p_odometer) returning id into d.id;
 elsif p_action='end' then
  if d.id is null or d.vehicle_id<>v.id or p_odometer<d.start_odometer then raise exception 'Нет открытой смены на этой машине либо пробег уменьшился';end if;
  update respectlogistic_driver_duties set ended_at=clock_timestamp(),end_odometer=p_odometer where id=d.id;
 else raise exception 'Недоступное действие';end if;
 return d.id;
end$$;

create function public.respectlogistic_save_road_fine(p_record jsonb) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;vid uuid=(p_record->>'vehicle_id')::uuid;did uuid=nullif(p_record->>'driver_id','')::uuid;at_time timestamptz=(p_record->>'violation_at')::timestamptz;price numeric=(p_record->>'amount')::numeric;d respectlogistic_driver_duties;method text='unassigned';begin
 if actor is null or rid is null or at_time is null or at_time>clock_timestamp() or price is null or price<=0 or price>10000000 or price::text in ('NaN','Infinity','-Infinity') or length(p_record::text)>12000 then raise exception 'Проверьте время нарушения и сумму';end if;
 perform id from crm_vehicles where id=vid and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle for update;
 if not found then raise exception 'Машина недоступна';end if;
 if coalesce(trim(p_record->>'notice_number'),'')='' or coalesce(trim(p_record->>'location'),'')='' or coalesce(trim(p_record->>'reason'),'')='' then raise exception 'Укажите номер постановления, место и причину';end if;
 if exists(select 1 from respectlogistic_road_fines where id=rid) then
  if exists(select 1 from respectlogistic_road_fines where id=rid and owner_id=actor) then return rid;end if;
  raise exception 'Штраф недоступен';
 end if;
 select * into d from respectlogistic_driver_duties where owner_id=actor and vehicle_id=vid and started_at<=at_time and (ended_at is null or at_time<ended_at) order by started_at desc limit 1;
 if did is not null then
  if not exists(select 1 from crm_drivers where id=did and owner_id=actor and app_scope='respectlogistic' and carrier_id is null) or coalesce(trim(p_record->>'manual_reason'),'')='' then raise exception 'Для ручного назначения укажите своего водителя и основание';end if;
  method='manual';d.id=null;
 elsif d.id is not null then did=d.driver_id;method='duty';end if;
 insert into respectlogistic_road_fines(id,owner_id,vehicle_id,driver_id,duty_id,violation_at,location,reason,notice_number,amount,assignment,manual_reason)
 values(rid,actor,vid,did,d.id,at_time,left(trim(p_record->>'location'),1000),left(trim(p_record->>'reason'),2000),left(trim(p_record->>'notice_number'),150),price,method,coalesce(p_record->>'manual_reason',''));
 return rid;
end$$;

create function public.respectlogistic_driver_road_data(p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object('duties',coalesce((select jsonb_agg(to_jsonb(d)-'owner_id' order by started_at desc) from respectlogistic_driver_duties d where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'),
 'fines',coalesce((select jsonb_agg(to_jsonb(f)-'owner_id' order by violation_at desc) from respectlogistic_road_fines f where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'));
end$$;

create function public.respectlogistic_road_fine_response(p_token text,p_id uuid,p_dispute text default '') returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;begin
 a=respectlogistic_require_driver(p_token);
 if length(p_dispute)>4000 then raise exception 'Комментарий до 4000 символов';end if;
 update respectlogistic_road_fines set acknowledged_at=clock_timestamp(),dispute=coalesce(p_dispute,''),modified_at=clock_timestamp() where id=p_id and owner_id=a.owner_id and driver_id=a.driver_id;
 if not found then raise exception 'Штраф недоступен';end if;
end$$;
revoke all on function public.respectlogistic_duty_action(text,uuid,text,numeric),public.respectlogistic_save_road_fine(jsonb),public.respectlogistic_driver_road_data(text),public.respectlogistic_road_fine_response(text,uuid,text) from public,anon,authenticated;
grant execute on function public.respectlogistic_save_road_fine(jsonb),public.respectlogistic_driver_road_data(text) to authenticated;
grant execute on function public.respectlogistic_duty_action(text,uuid,text,numeric),public.respectlogistic_driver_road_data(text),public.respectlogistic_road_fine_response(text,uuid,text) to anon;
notify pgrst,'reload schema';
