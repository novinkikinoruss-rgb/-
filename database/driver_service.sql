-- Driver service access is separate from CRM users; no driver receives the owner's JWT.
create table public.respectlogistic_service_partners(
 id uuid primary key,owner_id uuid not null default auth.uid() references auth.users(id),name text not null,address text not null,phone text not null,contact text not null default '',working_hours text not null,time_zone text not null default 'Europe/Moscow',
 contract_number text not null,contract_from date not null,contract_until date,work_kinds text[] not null,notes text not null default '',archived boolean not null default false,modified_at timestamptz not null default clock_timestamp(),check(contract_until is null or contract_until>=contract_from)
);
create table public.respectlogistic_driver_accounts(
 driver_id uuid primary key references public.crm_drivers(id),owner_id uuid not null references auth.users(id),login text not null unique,password_hash text not null,blocked boolean not null default false,must_change_password boolean not null default true,failed_attempts integer not null default 0,locked_until timestamptz,modified_at timestamptz not null default clock_timestamp()
);
create table public.respectlogistic_driver_sessions(token_hash text primary key,driver_id uuid not null references public.respectlogistic_driver_accounts(driver_id),created_at timestamptz not null default now(),expires_at timestamptz not null default now()+interval '14 days');
create table public.respectlogistic_service_requests(
 id uuid primary key,owner_id uuid not null references auth.users(id),driver_id uuid not null references public.crm_drivers(id),vehicle_id uuid not null references public.crm_vehicles(id),partner_id uuid not null references public.respectlogistic_service_partners(id),kind text not null check(kind in ('service','oil','repair','tyres')),
 status text not null default 'requested' check(status in ('requested','confirmed','arrived','completed','rejected','cancelled')),requested_date date,scheduled_at timestamptz,reported_odometer numeric not null check(reported_odometer>=0),driver_note text not null default '',dispatcher_note text not null default '',partner_snapshot jsonb not null,maintenance_id uuid references public.crm_fleet_maintenance(id),created_at timestamptz not null default clock_timestamp(),modified_at timestamptz not null default clock_timestamp()
);
create unique index one_open_service_request on public.respectlogistic_service_requests(vehicle_id,kind) where status in ('requested','confirmed','arrived');
create table public.respectlogistic_service_history(id uuid primary key default gen_random_uuid(),request_id uuid not null references public.respectlogistic_service_requests(id),owner_id uuid not null references auth.users(id),actor text not null,action text not null,note text not null default '',created_at timestamptz not null default clock_timestamp());
do $$declare t text;begin foreach t in array array['service_partners','driver_accounts','driver_sessions','service_requests','service_history'] loop
 execute format('alter table public.respectlogistic_%I enable row level security',t);
 execute format('revoke all on public.respectlogistic_%I from public,anon,authenticated',t);
end loop;end$$;
create policy service_partner_owner on public.respectlogistic_service_partners for select to authenticated using(owner_id=(select auth.uid()));
create policy service_request_owner on public.respectlogistic_service_requests for select to authenticated using(owner_id=(select auth.uid()));
create policy service_history_owner on public.respectlogistic_service_history for select to authenticated using(owner_id=(select auth.uid()));
grant select on public.respectlogistic_service_partners,public.respectlogistic_service_requests,public.respectlogistic_service_history to authenticated;
create index service_partner_owner on public.respectlogistic_service_partners(owner_id);
create index service_request_owner on public.respectlogistic_service_requests(owner_id,created_at desc);
create index service_request_driver on public.respectlogistic_service_requests(driver_id);
create index service_request_partner on public.respectlogistic_service_requests(partner_id);
create index service_request_vehicle on public.respectlogistic_service_requests(vehicle_id);
create index service_history_request on public.respectlogistic_service_history(request_id,created_at);
create index driver_account_owner on public.respectlogistic_driver_accounts(owner_id);
create index driver_session_driver on public.respectlogistic_driver_sessions(driver_id);

create function public.respectlogistic_save_service_partner(p_record jsonb,p_expected timestamptz default null) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;old respectlogistic_service_partners;kinds text[];zone text=coalesce(p_record->>'time_zone','Europe/Moscow');begin
 if actor is null or rid is null or jsonb_typeof(p_record) is distinct from 'object' or length(p_record::text)>20000 then raise exception 'Некорректная карточка сервиса';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-service',0));
 select * into old from respectlogistic_service_partners where id=rid for update;
 if old.id is not null and (old.owner_id<>actor or old.modified_at is distinct from p_expected) then raise exception 'Карточка недоступна или изменена. Обновите данные';end if;
 if coalesce(trim(p_record->>'name'),'')='' or coalesce(trim(p_record->>'address'),'')='' or coalesce(trim(p_record->>'phone'),'')='' or coalesce(trim(p_record->>'working_hours'),'')='' or coalesce(trim(p_record->>'contract_number'),'')='' or nullif(p_record->>'contract_from','') is null then raise exception 'Укажите название, адрес, телефон, график и договор сервиса';end if;
 if not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Проверьте часовой пояс сервиса';end if;
 select array_agg(distinct x) into kinds from jsonb_array_elements_text(p_record->'work_kinds') x;
 if coalesce(cardinality(kinds),0)=0 or exists(select 1 from unnest(kinds) k where k not in ('service','oil','repair','tyres')) then raise exception 'Выберите виды работ';end if;
 insert into respectlogistic_service_partners(id,owner_id,name,address,phone,contact,working_hours,time_zone,contract_number,contract_from,contract_until,work_kinds,notes,archived)
 values(rid,actor,trim(p_record->>'name'),trim(p_record->>'address'),trim(p_record->>'phone'),coalesce(p_record->>'contact',''),p_record->>'working_hours',zone,p_record->>'contract_number',(p_record->>'contract_from')::date,nullif(p_record->>'contract_until','')::date,kinds,coalesce(p_record->>'notes',''),coalesce((p_record->>'archived')::boolean,false))
 on conflict(id) do update set name=excluded.name,address=excluded.address,phone=excluded.phone,contact=excluded.contact,working_hours=excluded.working_hours,time_zone=excluded.time_zone,contract_number=excluded.contract_number,contract_from=excluded.contract_from,contract_until=excluded.contract_until,work_kinds=excluded.work_kinds,notes=excluded.notes,archived=excluded.archived,modified_at=clock_timestamp();return rid;
end$$;

create function public.respectlogistic_driver_access(p_driver uuid,p_action text,p_login text default null,p_password text default null) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();begin
 if actor is null or not exists(select 1 from crm_drivers where id=p_driver and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and archived_at is null and job_status='active') then raise exception 'Водитель компании недоступен';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_driver::text||'-driver-access',0));
 if p_action='password' then
  if coalesce(p_login,'')!~ '^[a-zA-Z0-9_.+@-]{3,80}$' or p_password is null or length(p_password)<12 or octet_length(p_password)>72 then raise exception 'Логин: 3–80 латинских символов; пароль: от 12 символов и до 72 байт';end if;
  insert into respectlogistic_driver_accounts(driver_id,owner_id,login,password_hash) values(p_driver,actor,lower(p_login),crypt(p_password,gen_salt('bf',10))) on conflict(driver_id) do update set login=excluded.login,password_hash=excluded.password_hash,blocked=false,must_change_password=true,failed_attempts=0,locked_until=null,modified_at=clock_timestamp();
 elsif p_action in ('block','unblock') then
  update respectlogistic_driver_accounts set blocked=p_action='block',modified_at=clock_timestamp() where driver_id=p_driver and owner_id=actor;
  if not found then raise exception 'Сначала создайте доступ водителю';end if;
 else raise exception 'Неизвестное действие';end if;
 delete from respectlogistic_driver_sessions where driver_id=p_driver;
end$$;

create function public.respectlogistic_driver_login(p_login text,p_password text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;token text;begin
 if length(coalesce(p_login,''))>80 or octet_length(coalesce(p_password,''))>72 then return '{"error":"Неверный логин или пароль"}';end if;
 select * into a from respectlogistic_driver_accounts where login=lower(trim(p_login)) for update;
 if a.driver_id is null or a.blocked or a.locked_until>now() or not exists(select 1 from crm_drivers where id=a.driver_id and owner_id=a.owner_id and app_scope='respectlogistic' and carrier_id is null and archived_at is null and job_status='active') then return '{"error":"Неверный логин или пароль либо доступ временно ограничен"}';end if;
 if p_password is null or crypt(p_password,a.password_hash) is distinct from a.password_hash then
  update respectlogistic_driver_accounts set failed_attempts=failed_attempts+1,locked_until=case when failed_attempts>=4 then now()+interval '10 minutes' else null end where driver_id=a.driver_id;
  return '{"error":"Неверный логин или пароль либо доступ временно ограничен"}';
 end if;
 update respectlogistic_driver_accounts set failed_attempts=0,locked_until=null where driver_id=a.driver_id;
 delete from respectlogistic_driver_sessions where driver_id=a.driver_id and expires_at<now();
 token=encode(gen_random_bytes(32),'hex');insert into respectlogistic_driver_sessions(token_hash,driver_id) values(encode(digest(token,'sha256'),'hex'),a.driver_id);
 return jsonb_build_object('token',token,'must_change_password',a.must_change_password,'expires_at',now()+interval '14 days');
end$$;

create function public.respectlogistic_require_driver(p_token text,p_allow_password_change boolean default false) returns public.respectlogistic_driver_accounts language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;begin
 if p_token is null or p_token!~ '^[0-9a-f]{64}$' then raise exception 'Войдите в приложение повторно' using errcode='28000';end if;
 select da.* into a from respectlogistic_driver_sessions s join respectlogistic_driver_accounts da on da.driver_id=s.driver_id join crm_drivers d on d.id=da.driver_id and d.owner_id=da.owner_id
 where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and not da.blocked and d.app_scope='respectlogistic' and d.carrier_id is null and d.archived_at is null and d.job_status='active';
 if a.driver_id is null then raise exception 'Доступ отключён или сессия истекла. Войдите повторно' using errcode='28000';end if;
 if a.must_change_password and not p_allow_password_change then raise exception 'Сначала смените временный пароль' using errcode='28000';end if;return a;
end$$;

create function public.respectlogistic_driver_password(p_token text,p_password text) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;begin
 a=respectlogistic_require_driver(p_token,true);
 if p_password is null or length(p_password)<12 or octet_length(p_password)>72 then raise exception 'Пароль должен содержать от 12 символов и не более 72 байт';end if;
 if crypt(p_password,a.password_hash)=a.password_hash then raise exception 'Новый пароль должен отличаться от временного';end if;
 update respectlogistic_driver_accounts set password_hash=crypt(p_password,gen_salt('bf',10)),must_change_password=false,modified_at=clock_timestamp() where driver_id=a.driver_id;
 delete from respectlogistic_driver_sessions where driver_id=a.driver_id and token_hash<>encode(digest(p_token,'sha256'),'hex');
end$$;
create function public.respectlogistic_driver_logout(p_token text) returns void language sql security definer set search_path=public,extensions,pg_temp as $$delete from respectlogistic_driver_sessions where token_hash=encode(digest(p_token,'sha256'),'hex')$$;

create function public.respectlogistic_create_service_request(p_record jsonb,p_token text default null) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;v crm_vehicles;p respectlogistic_service_partners;rid uuid=(p_record->>'id')::uuid;vid uuid=(p_record->>'vehicle_id')::uuid;pid uuid=(p_record->>'partner_id')::uuid;k text=p_record->>'kind';odo numeric=(p_record->>'reported_odometer')::numeric;previous respectlogistic_service_requests;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null or rid is null or vid is null or pid is null or k is null or k not in ('service','oil','repair','tyres') or length(p_record::text)>10000 then raise exception 'Проверьте заявку';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-service',0));
 select * into previous from respectlogistic_service_requests where id=rid;
 if previous.id is not null then if previous.owner_id<>actor or (a.driver_id is not null and previous.driver_id<>a.driver_id) then raise exception 'Заявка недоступна';end if;return rid;end if;
 select * into v from crm_vehicles where id=vid and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null;
 if v.id is null or v.assigned_driver_id is null or (a.driver_id is not null and v.assigned_driver_id<>a.driver_id) or not exists(select 1 from crm_drivers where id=v.assigned_driver_id and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and archived_at is null and job_status='active') then raise exception 'Выберите собственную машину с закреплённым действующим водителем';end if;
 select * into p from respectlogistic_service_partners where id=pid and owner_id=actor and not archived;
 if p.id is null or not(k=any(p.work_kinds)) or p.contract_from>(now() at time zone p.time_zone)::date or (p.contract_until is not null and p.contract_until<(now() at time zone p.time_zone)::date) then raise exception 'Сервис или договор недоступен для этих работ';end if;
 if odo is null or odo<v.odometer_km or odo>100000000 or odo::text in ('NaN','Infinity','-Infinity') then raise exception 'Пробег не может быть меньше текущего';end if;
 if nullif(p_record->>'requested_date','')::date<current_date then raise exception 'Желаемая дата не может быть в прошлом';end if;
 if exists(select 1 from respectlogistic_service_requests where vehicle_id=vid and kind=k and status in ('requested','confirmed','arrived')) then raise exception 'По этому обслуживанию уже есть открытая заявка';end if;
 insert into respectlogistic_service_requests(id,owner_id,driver_id,vehicle_id,partner_id,kind,requested_date,reported_odometer,driver_note,partner_snapshot) values(rid,actor,v.assigned_driver_id,vid,pid,k,nullif(p_record->>'requested_date','')::date,odo,left(coalesce(p_record->>'driver_note',''),4000),to_jsonb(p)-'owner_id');
 insert into respectlogistic_service_history(request_id,owner_id,actor,action) values(rid,actor,case when a.driver_id is null then 'dispatcher' else 'driver' end,'requested');return rid;
end$$;

create function public.respectlogistic_service_action(p_id uuid,p_action text,p_expected timestamptz,p_record jsonb default '{}',p_token text default null) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;r respectlogistic_service_requests;p respectlogistic_service_partners;scheduled timestamptz;odo numeric;performed date;maintenance uuid;note text=left(coalesce(p_record->>'note',''),4000);begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null or p_id is null or length(p_record::text)>10000 then raise exception 'Заявка недоступна';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-service',0));
 select * into r from respectlogistic_service_requests where id=p_id and owner_id=actor for update;
 if r.id is null or (a.driver_id is not null and r.driver_id<>a.driver_id) then raise exception 'Заявка недоступна';end if;
 if r.modified_at is distinct from p_expected then raise exception 'Заявка изменена. Обновите данные';end if;
 if a.driver_id is not null and p_action not in ('arrived','cancel') then raise exception 'Запись подтверждает диспетчер';end if;
 if p_action='confirm' then
  if r.status<>'requested' or (p_record->>'service_agreed')::boolean is distinct from true then raise exception 'Подтвердите согласование записи с сервисом';end if;
  select * into p from respectlogistic_service_partners where id=r.partner_id and owner_id=actor and not archived;
  scheduled=nullif(p_record->>'scheduled_local','')::timestamp at time zone p.time_zone;
  if p.id is null or scheduled is null or scheduled<=now() or scheduled>now()+interval '1 year' or not(r.kind=any(p.work_kinds)) or (scheduled at time zone p.time_zone)::date<p.contract_from or (p.contract_until is not null and (scheduled at time zone p.time_zone)::date>p.contract_until) then raise exception 'Проверьте время записи и срок договора сервиса';end if;
  if not exists(select 1 from crm_vehicles where id=r.vehicle_id and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null and assigned_driver_id=r.driver_id) then raise exception 'Машина или назначенный водитель изменились';end if;
  update respectlogistic_service_requests set status='confirmed',scheduled_at=scheduled,dispatcher_note=note,partner_snapshot=to_jsonb(p)-'owner_id' where id=r.id;
 elsif p_action='arrived' then
  if r.status<>'confirmed' then raise exception 'Сначала дождитесь подтверждения записи';end if;
  update respectlogistic_service_requests set status='arrived' where id=r.id;
 elsif p_action in ('reject','cancel') then
  if r.status not in ('requested','confirmed','arrived') or (a.driver_id is not null and r.status<>'requested') then raise exception 'Подтверждённую запись отменяет диспетчер';end if;
  if a.driver_id is null and trim(note)='' then raise exception 'Укажите причину отмены или отказа';end if;
  update respectlogistic_service_requests set status=case when p_action='reject' then 'rejected' else 'cancelled' end,dispatcher_note=case when a.driver_id is null then note else dispatcher_note end where id=r.id;
 elsif p_action='complete' then
  if r.status not in ('confirmed','arrived') then raise exception 'Можно закрыть только подтверждённую запись';end if;
  odo=(p_record->>'odometer')::numeric;performed=(p_record->>'performed_date')::date;
  if performed is null or performed>current_date or performed<r.created_at::date or odo is null or odo<r.reported_odometer or odo>100000000 or odo::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте дату и пробег обслуживания';end if;
  if r.kind in ('service','oil') then maintenance=rl_crm_complete_fleet_maintenance(r.vehicle_id,r.kind,odo,performed,note||' · Заявка '||r.id::text);
  else
   perform id from crm_vehicles where id=r.vehicle_id and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null and odometer_km<=odo for update;
   if not found then raise exception 'Проверьте машину и текущий пробег';end if;
   update crm_vehicles set odometer_km=odo where id=r.vehicle_id;
  end if;
  update respectlogistic_service_requests set status='completed',reported_odometer=odo,maintenance_id=maintenance,dispatcher_note=note where id=r.id;
 else raise exception 'Неизвестное действие';end if;
 update respectlogistic_service_requests set modified_at=clock_timestamp() where id=r.id;
 insert into respectlogistic_service_history(request_id,owner_id,actor,action,note) values(r.id,actor,case when a.driver_id is null then 'dispatcher' else 'driver' end,p_action,note);
end$$;

create function public.respectlogistic_read_service() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 return jsonb_build_object(
 'partners',coalesce((select jsonb_agg(to_jsonb(p) order by p.name) from respectlogistic_service_partners p where p.owner_id=actor),'[]'),
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from respectlogistic_service_requests r where r.owner_id=actor),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from respectlogistic_service_history h where h.owner_id=actor),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'assigned_driver_id',v.assigned_driver_id,'odometer_km',v.odometer_km,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=actor and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'phone',d.phone)) from crm_drivers d where d.owner_id=actor and d.app_scope='respectlogistic' and d.carrier_id is null and d.archived_at is null and d.job_status='active'),'[]'),
 'accounts',coalesce((select jsonb_agg(jsonb_build_object('driver_id',a.driver_id,'login',a.login,'blocked',a.blocked,'must_change_password',a.must_change_password)) from respectlogistic_driver_accounts a where a.owner_id=actor),'[]'));
end$$;

create function public.respectlogistic_driver_service(p_token text) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;begin
 a=respectlogistic_require_driver(p_token);
 return jsonb_build_object('driver',jsonb_build_object('id',a.driver_id,'full_name',(select full_name from crm_drivers where id=a.driver_id)),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'odometer_km',v.odometer_km,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=a.owner_id and v.assigned_driver_id=a.driver_id and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null),'[]'),
 'partners',coalesce((select jsonb_agg(to_jsonb(p)-'owner_id' order by p.name) from respectlogistic_service_partners p where p.owner_id=a.owner_id and not p.archived and p.contract_from<=(now() at time zone p.time_zone)::date and (p.contract_until is null or p.contract_until>=(now() at time zone p.time_zone)::date)),'[]'),
 'requests',coalesce((select jsonb_agg(to_jsonb(r)-'owner_id' order by r.created_at desc) from respectlogistic_service_requests r where r.owner_id=a.owner_id and r.driver_id=a.driver_id),'[]'));
end$$;

revoke all on function public.respectlogistic_save_service_partner(jsonb,timestamptz),public.respectlogistic_driver_access(uuid,text,text,text),public.respectlogistic_driver_login(text,text),public.respectlogistic_require_driver(text,boolean),public.respectlogistic_driver_password(text,text),public.respectlogistic_driver_logout(text),public.respectlogistic_create_service_request(jsonb,text),public.respectlogistic_service_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_read_service(),public.respectlogistic_driver_service(text) from public,anon,authenticated;
grant execute on function public.respectlogistic_save_service_partner(jsonb,timestamptz),public.respectlogistic_driver_access(uuid,text,text,text),public.respectlogistic_create_service_request(jsonb,text),public.respectlogistic_service_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_read_service() to authenticated;
grant execute on function public.respectlogistic_driver_login(text,text),public.respectlogistic_driver_password(text,text),public.respectlogistic_driver_logout(text),public.respectlogistic_create_service_request(jsonb,text),public.respectlogistic_service_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_driver_service(text) to anon;
notify pgrst,'reload schema';
