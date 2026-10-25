-- Distribution is separate from trips: actual volume is recorded only after unloading.
create table public.respectlogistic_dispatch_counters(owner_id uuid primary key references auth.users,request_no integer not null default 0,document_no integer not null default 0);
create table public.respectlogistic_dispatch_requests(
 id uuid primary key,owner_id uuid not null references auth.users,number integer not null,customer_id uuid not null references public.respectlogistic_customers,site_id uuid not null references public.respectlogistic_sites,
 date_from date not null,date_to date not null,payload jsonb not null,version integer not null default 1,cancelled_at timestamptz,deleted_at timestamptz,modified_at timestamptz not null default clock_timestamp(),created_at timestamptz not null default clock_timestamp(),
 unique(owner_id,number),check(date_to>=date_from and date_to-date_from<=366)
);
create table public.respectlogistic_dispatch_shifts(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users,request_id uuid not null references public.respectlogistic_dispatch_requests,shift_date date not null,
 vehicle_id uuid not null references public.crm_vehicles,driver_id uuid references public.crm_drivers,carrier_id uuid references public.crm_carriers,driver_name text not null,
 starts_at timestamptz not null,ends_at timestamptz not null,snapshot jsonb not null,status text not null default 'draft' check(status in ('draft','sent','accepted','rejected','completed','cancelled')),
 version integer not null default 1,sent_at timestamptz,seen_at timestamptz,accepted_at timestamptz,response_note text not null default '',modified_at timestamptz not null default clock_timestamp(),check(ends_at>starts_at)
);
create unique index dispatch_shift_unique_active on public.respectlogistic_dispatch_shifts(request_id,shift_date,vehicle_id) where status<>'cancelled';
create index dispatch_shift_owner_dates on public.respectlogistic_dispatch_shifts(owner_id,shift_date);
create index dispatch_shift_driver on public.respectlogistic_dispatch_shifts(driver_id,shift_date);
create index dispatch_shift_vehicle on public.respectlogistic_dispatch_shifts(vehicle_id,starts_at,ends_at);
create index dispatch_request_customer on public.respectlogistic_dispatch_requests(customer_id);
create index dispatch_request_site on public.respectlogistic_dispatch_requests(site_id);
create index dispatch_shift_carrier on public.respectlogistic_dispatch_shifts(carrier_id);
create table public.respectlogistic_dispatch_results(id uuid primary key,owner_id uuid not null references auth.users,shift_id uuid not null references public.respectlogistic_dispatch_shifts,trip_id uuid not null unique references public.crm_trips,volume numeric not null check(volume>0),unit text not null check(unit in ('т','м³')),created_at timestamptz not null default clock_timestamp());
create index dispatch_result_owner on public.respectlogistic_dispatch_results(owner_id);
create index dispatch_result_shift on public.respectlogistic_dispatch_results(shift_id);
create table public.respectlogistic_dispatch_events(id bigint generated always as identity primary key,owner_id uuid not null references auth.users,request_id uuid not null references public.respectlogistic_dispatch_requests,shift_id uuid references public.respectlogistic_dispatch_shifts,action text not null,detail jsonb not null default '{}',created_at timestamptz not null default clock_timestamp());
create index dispatch_event_owner on public.respectlogistic_dispatch_events(owner_id,created_at desc);
create index dispatch_event_request on public.respectlogistic_dispatch_events(request_id);
create index dispatch_event_shift on public.respectlogistic_dispatch_events(shift_id);
create table public.respectlogistic_dispatch_templates(id uuid primary key,owner_id uuid not null references auth.users,kind text not null check(kind in ('ttn','waybill','invoice')),name text not null,storage_path text not null unique,active boolean not null default true,created_at timestamptz not null default clock_timestamp());
create index dispatch_template_owner on public.respectlogistic_dispatch_templates(owner_id);
create table public.respectlogistic_dispatch_documents(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users,shift_id uuid not null references public.respectlogistic_dispatch_shifts,batch_id uuid not null,kind text not null check(kind in ('ttn','waybill','invoice')),ordinal integer not null,number integer not null,copies integer not null check(copies between 1 and 10),snapshot jsonb not null,created_at timestamptz not null default clock_timestamp(),unique(shift_id,batch_id,kind,ordinal),unique(owner_id,number));
create index dispatch_document_owner on public.respectlogistic_dispatch_documents(owner_id);
create index dispatch_document_shift on public.respectlogistic_dispatch_documents(shift_id);
do $$declare t text;begin foreach t in array array['counters','requests','shifts','results','events','templates','documents'] loop
 execute format('alter table public.respectlogistic_dispatch_%I enable row level security',t);
 execute format('revoke all on public.respectlogistic_dispatch_%I from public,anon,authenticated',t);
 execute format('create policy dispatch_owner on public.respectlogistic_dispatch_%I for select to authenticated using(owner_id=(select auth.uid()))',t);
 execute format('grant select on public.respectlogistic_dispatch_%I to authenticated',t);
end loop;end$$;

create function public.respectlogistic_read_dispatch() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 return jsonb_build_object(
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.number desc) from respectlogistic_dispatch_requests r where r.owner_id=actor and r.deleted_at is null),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(s) order by s.shift_date desc,s.starts_at,s.id) from respectlogistic_dispatch_shifts s where s.owner_id=actor),'[]'),
 'results',coalesce((select jsonb_agg(to_jsonb(r)) from respectlogistic_dispatch_results r where r.owner_id=actor),'[]'),
 'templates',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from respectlogistic_dispatch_templates t where t.owner_id=actor),'[]'),
 'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.number desc) from respectlogistic_dispatch_documents d where d.owner_id=actor),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.id desc) from (select * from respectlogistic_dispatch_events where owner_id=actor order by id desc limit 200) e),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'carrier_id',v.carrier_id,'is_subcontractor_vehicle',v.is_subcontractor_vehicle,'assigned_driver_id',v.assigned_driver_id,'status',v.status)) from crm_vehicles v where v.owner_id=actor and v.app_scope='respectlogistic' and v.archived_at is null),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'carrier_id',d.carrier_id,'ready',exists(select 1 from respectlogistic_driver_accounts a where a.owner_id=actor and a.driver_id=d.id and not a.blocked))) from crm_drivers d where d.owner_id=actor and d.app_scope='respectlogistic' and d.archived_at is null and d.job_status='active'),'[]'),
 'carriers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name)) from crm_carriers c where c.owner_id=actor and c.app_scope='respectlogistic' and not c.is_blocked),'[]'));
end$$;

create function public.respectlogistic_save_dispatch(p_record jsonb,p_expected integer default null,p_action text default 'save') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;r respectlogistic_dispatch_requests;s respectlogistic_sites;svc respectlogistic_services;v_payload jsonb;df date;dt date;zone text;num integer;begin
 if actor is null or rid is null or jsonb_typeof(p_record) is distinct from 'object' or octet_length(p_record::text)>30000 then raise exception 'Проверьте заявку';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into r from respectlogistic_dispatch_requests where id=rid for update;
 if r.id is not null and (r.owner_id<>actor or r.version is distinct from p_expected or r.deleted_at is not null) then raise exception 'Заявка недоступна или изменена. Обновите список';end if;
 if p_action in ('cancel','delete') then
  if r.id is null then raise exception 'Заявка не найдена';end if;
  update respectlogistic_dispatch_requests set cancelled_at=clock_timestamp(),deleted_at=case when p_action='delete' and not exists(select 1 from respectlogistic_dispatch_shifts where request_id=rid and sent_at is not null) then clock_timestamp() else deleted_at end,version=version+1,modified_at=clock_timestamp() where id=rid;
  update respectlogistic_dispatch_shifts set status='cancelled',version=version+1,modified_at=clock_timestamp() where request_id=rid and owner_id=actor and status not in ('completed','cancelled');
  insert into respectlogistic_dispatch_events(owner_id,request_id,action) values(actor,rid,'cancelled');return rid;
 end if;
 if p_action<>'save' or r.cancelled_at is not null then raise exception 'Отменённую заявку нельзя изменить';end if;
 df=(p_record->>'date_from')::date;dt=(p_record->>'date_to')::date;zone=coalesce(nullif(p_record->>'time_zone',''),'Europe/Moscow');
 if df is null or dt is null or dt<df or dt-df>366 then raise exception 'Укажите период до 366 дней';end if;
 if not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Неизвестный часовой пояс';end if;
 select * into s from respectlogistic_sites where id=(p_record->>'site_id')::uuid and owner_id=actor and customer_id=(p_record->>'customer_id')::uuid;
 if s.id is null then raise exception 'Выберите объект выбранного заказчика этой CRM';end if;
 select * into svc from respectlogistic_services where id=s.service_id and owner_id=actor and customer_id=s.customer_id;
 if svc.id is null then raise exception 'Услуга объекта недоступна';end if;
 if coalesce(trim(p_record->>'loading_address'),'')='' or coalesce(trim(p_record->>'unloading_address'),'')='' or coalesce(trim(p_record->>'contact_name'),'')='' or coalesce(trim(p_record->>'contact_phone'),'')='' then raise exception 'Укажите адреса, имя и телефон ответственного';end if;
 if nullif(p_record->>'loading_from','') is null or nullif(p_record->>'loading_to','') is null or nullif(p_record->>'unloading_from','') is null or nullif(p_record->>'unloading_to','') is null then raise exception 'Укажите режим погрузки и выгрузки';end if;
 perform (p_record->>'loading_from')::time,(p_record->>'loading_to')::time,(p_record->>'unloading_from')::time,(p_record->>'unloading_to')::time;
 if (p_record->>'loading_from')::time=(p_record->>'loading_to')::time then raise exception 'Укажите разное начало и окончание смены';end if;
 v_payload=jsonb_build_object('loading_address',trim(p_record->>'loading_address'),'loading_point',coalesce(p_record->>'loading_point',''),'unloading_address',trim(p_record->>'unloading_address'),'loading_from',p_record->>'loading_from','loading_to',p_record->>'loading_to','unloading_from',p_record->>'unloading_from','unloading_to',p_record->>'unloading_to','contact_name',trim(p_record->>'contact_name'),'contact_phone',trim(p_record->>'contact_phone'),'sender',coalesce(p_record->>'sender',''),'recipient',coalesce(p_record->>'recipient',''),'notes',coalesce(p_record->>'notes',''),'time_zone',zone,'service_name',svc.name,'unit',svc.unit,'unit_price',svc.price_kopecks/100.0,'site_name',s.payload->>'name');
 if r.id is null then
  insert into respectlogistic_dispatch_counters(owner_id,request_no) values(actor,1) on conflict(owner_id) do update set request_no=respectlogistic_dispatch_counters.request_no+1 returning request_no into num;
  insert into respectlogistic_dispatch_requests(id,owner_id,number,customer_id,site_id,date_from,date_to,payload) values(rid,actor,num,s.customer_id,s.id,df,dt,v_payload);
 else
  if exists(select 1 from respectlogistic_dispatch_shifts where request_id=rid and status not in ('cancelled','rejected') and (shift_date<df or shift_date>dt)) then raise exception 'За пределами нового периода есть смены. Сначала отмените их';end if;
  update respectlogistic_dispatch_requests set customer_id=s.customer_id,site_id=s.id,date_from=df,date_to=dt,payload=v_payload,version=version+1,modified_at=clock_timestamp() where id=rid;
  if r.payload is distinct from v_payload or r.site_id<>s.id or r.customer_id<>s.customer_id then
   if exists(select 1 from respectlogistic_dispatch_shifts x join respectlogistic_dispatch_shifts other on other.owner_id=actor and other.request_id<>rid and other.status not in ('cancelled','rejected') and (other.vehicle_id=x.vehicle_id or x.driver_id is not null and other.driver_id=x.driver_id) where x.request_id=rid and x.owner_id=actor and x.status in ('draft','sent','accepted','rejected') and x.starts_at>clock_timestamp() and tstzrange(other.starts_at,other.ends_at,'[)')&&tstzrange((x.shift_date+(v_payload->>'loading_from')::time) at time zone zone,((x.shift_date+case when (v_payload->>'loading_to')::time<(v_payload->>'loading_from')::time then 1 else 0 end)+(v_payload->>'loading_to')::time) at time zone zone,'[)')) then raise exception 'Новый режим пересекается с другой заявкой машины или водителя';end if;
   -- Historical shifts and completed results remain immutable. Future changes require re-send and acceptance.
   update respectlogistic_dispatch_shifts set snapshot=(snapshot-'unit_price')||jsonb_build_object('number',r.number,'customer_id',s.customer_id,'site_id',s.id)||v_payload,status='draft',sent_at=null,seen_at=null,accepted_at=null,version=version+1,modified_at=clock_timestamp(),starts_at=(shift_date+(v_payload->>'loading_from')::time) at time zone zone,ends_at=((shift_date+case when (v_payload->>'loading_to')::time<(v_payload->>'loading_from')::time then 1 else 0 end)+(v_payload->>'loading_to')::time) at time zone zone where request_id=rid and status in ('draft','sent','accepted','rejected') and starts_at>clock_timestamp();
  end if;
 end if;
 insert into respectlogistic_dispatch_events(owner_id,request_id,action) values(actor,rid,case when r.id is null then 'created' else 'updated' end);return rid;
end$$;

create function public.respectlogistic_assign_dispatch(p_id uuid,p_expected integer,p_from date,p_to date,p_assignments jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();r respectlogistic_dispatch_requests;v crm_vehicles;d crm_drivers;item jsonb;day date;starts timestamptz;ends timestamptz;old respectlogistic_dispatch_shifts;sid uuid;carrier uuid;dname text;begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into r from respectlogistic_dispatch_requests where id=p_id and owner_id=actor and cancelled_at is null and deleted_at is null for update;
 if r.id is null or r.version is distinct from p_expected then raise exception 'Заявка изменена или недоступна';end if;
 if p_from is null or p_to is null or p_from<r.date_from or p_to>r.date_to or p_to<p_from or p_to-p_from>30 or p_from<(clock_timestamp() at time zone (r.payload->>'time_zone'))::date then raise exception 'Выберите будущие даты в периоде заявки (до 31 дня за раз)';end if;
 if jsonb_typeof(p_assignments) is distinct from 'array' or jsonb_array_length(p_assignments) not between 1 and 50 or jsonb_array_length(p_assignments)*(p_to-p_from+1)>500 then raise exception 'Выберите от 1 до 50 машин, до 500 смен за раз';end if;
 if (select count(distinct x->>'vehicle_id') from jsonb_array_elements(p_assignments) x)<>jsonb_array_length(p_assignments) then raise exception 'Машина выбрана дважды';end if;
 for item in select * from jsonb_array_elements(p_assignments) loop
  select * into v from crm_vehicles where id=(item->>'vehicle_id')::uuid and owner_id=actor and app_scope='respectlogistic' and archived_at is null;
  if v.id is null or v.status not in ('available','busy') then raise exception 'Машина недоступна или на ремонте';end if;
  carrier=coalesce(v.carrier_id,case when v.is_subcontractor_vehicle then nullif(item->>'carrier_id','')::uuid end);
  if (v.carrier_id is not null or v.is_subcontractor_vehicle) and (carrier is null or not exists(select 1 from crm_carriers where id=carrier and owner_id=actor and app_scope='respectlogistic' and not is_blocked)) then raise exception 'Выберите контрагента этой машины';end if;
  d.id=null;dname=trim(coalesce(item->>'driver_name',''));
  if nullif(item->>'driver_id','') is not null then
   select * into d from crm_drivers where id=(item->>'driver_id')::uuid and owner_id=actor and app_scope='respectlogistic' and carrier_id is not distinct from carrier and archived_at is null and job_status='active';
   if d.id is null then raise exception 'Водитель недоступен или относится к другому исполнителю';end if;dname=d.full_name;
  end if;
  if carrier is null and d.id is null then raise exception 'Назначьте водителя своей машины';end if;
  if dname='' or length(dname)>400 then raise exception 'Укажите ФИО водителя для документов';end if;
  for day in select p_from+i from generate_series(0,p_to-p_from) i loop
   starts=(day+(r.payload->>'loading_from')::time) at time zone (r.payload->>'time_zone');
   ends=((day+case when (r.payload->>'loading_to')::time<(r.payload->>'loading_from')::time then 1 else 0 end)+(r.payload->>'loading_to')::time) at time zone (r.payload->>'time_zone');
   select * into old from respectlogistic_dispatch_shifts where request_id=r.id and shift_date=day and vehicle_id=v.id and status<>'cancelled' for update;
   if old.id is not null and old.driver_id is not distinct from d.id and old.driver_name=dname and old.carrier_id is not distinct from carrier then continue;end if;
   if old.status='completed' or exists(select 1 from respectlogistic_dispatch_results where shift_id=old.id) then raise exception 'По смене уже есть перевозки. Заменять её нельзя';end if;
   if exists(select 1 from respectlogistic_dispatch_shifts x where x.owner_id=actor and x.id is distinct from old.id and x.status not in ('cancelled','rejected') and (x.vehicle_id=v.id or d.id is not null and x.driver_id=d.id) and tstzrange(x.starts_at,x.ends_at,'[)')&&tstzrange(starts,ends,'[)')) then raise exception 'На это время машина или водитель уже назначены';end if;
   if old.id is not null then update respectlogistic_dispatch_shifts set status='cancelled',version=version+1,modified_at=clock_timestamp() where id=old.id;end if;
   insert into respectlogistic_dispatch_shifts(owner_id,request_id,shift_date,vehicle_id,driver_id,carrier_id,driver_name,starts_at,ends_at,snapshot)
   values(actor,r.id,day,v.id,d.id,carrier,dname,starts,ends,r.payload||jsonb_build_object('number',r.number,'customer_id',r.customer_id,'site_id',r.site_id,'plate',v.plate,'driver_name',dname,'customer_name',(select payload->>'name' from respectlogistic_customers where id=r.customer_id and owner_id=actor))) returning id into sid;
   insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action) values(actor,r.id,sid,'assigned');
  end loop;
 end loop;
end$$;

create function public.respectlogistic_dispatch_action(p_shift uuid,p_expected integer,p_action text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();s respectlogistic_dispatch_shifts;begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into s from respectlogistic_dispatch_shifts where id=p_shift and owner_id=actor for update;
 if s.id is null or s.version is distinct from p_expected then raise exception 'Смена изменена или недоступна';end if;
 if p_action='send' then
  if s.status not in ('draft','rejected','sent') or not exists(select 1 from respectlogistic_dispatch_requests where id=s.request_id and owner_id=actor and cancelled_at is null and deleted_at is null) then raise exception 'Эту смену нельзя отправить';end if;
  if s.carrier_id is not null then raise exception 'Приложение подключено для собственных водителей. Смену контрагента можно распечатать';end if;
  if not exists(select 1 from respectlogistic_driver_accounts a join crm_drivers d on d.id=a.driver_id where a.driver_id=s.driver_id and a.owner_id=actor and not a.blocked and d.owner_id=actor and d.app_scope='respectlogistic' and d.carrier_id is null and d.archived_at is null and d.job_status='active') then raise exception 'Сначала создайте или восстановите доступ водителю в разделе Сервис и водители';end if;
  if not exists(select 1 from crm_vehicles v where v.id=s.vehicle_id and v.owner_id=actor and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and v.status in ('available','busy')) then raise exception 'Машина недоступна';end if;
  if s.status='sent' then return;end if;
  update respectlogistic_dispatch_shifts set status='sent',sent_at=clock_timestamp(),seen_at=null,accepted_at=null,response_note='',version=version+1,modified_at=clock_timestamp() where id=s.id;
 elsif p_action='cancel' then
  if s.status='completed' then raise exception 'Выполненную смену отменять нельзя';end if;
  if s.status='cancelled' then return;end if;
  update respectlogistic_dispatch_shifts set status='cancelled',version=version+1,modified_at=clock_timestamp() where id=s.id;
 else raise exception 'Неизвестное действие';end if;
 insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action) values(actor,s.request_id,s.id,p_action);
end$$;

create function public.respectlogistic_driver_dispatch(p_token text,p_action text default 'list',p_id uuid default null,p_expected integer default null,p_record jsonb default '{}') returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;s respectlogistic_dispatch_shifts;begin
 a=respectlogistic_require_driver(p_token);
 if p_action='list' then
  update respectlogistic_dispatch_shifts set seen_at=clock_timestamp() where owner_id=a.owner_id and driver_id=a.driver_id and carrier_id is null and status='sent' and seen_at is null;
  return jsonb_build_object('dispatch_shifts',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'request_id',x.request_id,'shift_date',x.shift_date,'vehicle_id',x.vehicle_id,'starts_at',x.starts_at,'ends_at',x.ends_at,'status',x.status,'version',x.version,'sent_at',x.sent_at,'accepted_at',x.accepted_at,'response_note',x.response_note,'details',x.snapshot-'unit_price'-'customer_id'-'site_id','results',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'trip_id',r.trip_id,'volume',r.volume,'unit',r.unit,'created_at',r.created_at)) from respectlogistic_dispatch_results r where r.shift_id=x.id and r.owner_id=a.owner_id),'[]')) order by x.shift_date,x.starts_at) from respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.driver_id=a.driver_id and x.carrier_id is null and x.sent_at is not null and x.shift_date>=(clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date-30),'[]'),
   'dispatch_vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'odometer_km',v.odometer_km,'assigned_driver_id',v.assigned_driver_id,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=a.owner_id and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and exists(select 1 from respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.vehicle_id=v.id and x.driver_id=a.driver_id and x.status='accepted' and x.shift_date=(clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date)),'[]'));
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

create function public.respectlogistic_dispatch_result(p_shift uuid,p_record jsonb,p_expected integer,p_token text default null) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;s respectlogistic_dispatch_shifts;rid uuid=(p_record->>'id')::uuid;existing respectlogistic_dispatch_results;vol numeric=(p_record->>'volume')::numeric;u text=p_record->>'unit';tid uuid;tripdate date;oldsub text=current_setting('request.jwt.claim.sub',true);oldzone text=current_setting('TimeZone');begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null or rid is null or octet_length(p_record::text)>4000 then raise exception 'Проверьте данные выгрузки';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into s from respectlogistic_dispatch_shifts where id=p_shift and owner_id=actor for update;
 if s.id is null or p_token is not null and (s.driver_id is distinct from a.driver_id or s.carrier_id is not null) then raise exception 'Смена недоступна';end if;
 select * into existing from respectlogistic_dispatch_results where id=rid;
 if existing.id is not null then if existing.owner_id<>actor or existing.shift_id<>s.id then raise exception 'Запись недоступна';end if;return existing.trip_id;end if;
 if s.version is distinct from p_expected or s.status not in ('accepted','draft','sent') or p_token is not null and s.status<>'accepted' then raise exception 'Примите актуальную смену или обновите её';end if;
 if vol is null or vol<=0 or vol>1000000 or vol::text in ('NaN','Infinity','-Infinity') or u is null or u not in ('т','м³') or u is distinct from s.snapshot->>'unit' then raise exception 'Укажите фактический объём в единице услуги (т или м³)';end if;
 tripdate=coalesce(nullif(p_record->>'date','')::date,s.shift_date);
 if tripdate<s.shift_date or tripdate>s.shift_date+1 or tripdate>(clock_timestamp() at time zone (s.snapshot->>'time_zone'))::date then raise exception 'Проверьте дату фактической выгрузки';end if;
 if p_token is not null and not exists(select 1 from respectlogistic_driver_duties d where d.owner_id=actor and d.driver_id=a.driver_id and d.vehicle_id=s.vehicle_id and d.ended_at is null) then raise exception 'Сначала начните смену на назначенной машине';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);perform set_config('TimeZone',s.snapshot->>'time_zone',true);
 tid=crm_save_trip(jsonb_build_object('id',rid,'customer_id',s.snapshot->>'customer_id','site_id',s.snapshot->>'site_id','vehicle_id',s.vehicle_id,'driver_id',s.driver_id,'carrier_id',s.carrier_id,'vehicle_source',case when s.carrier_id is null then 'own' else 'contractor' end,'trip_date',tripdate,'loading_address',s.snapshot->>'loading_address','unloading_address',s.snapshot->>'unloading_address','service_name',s.snapshot->>'service_name','unit',u,'volume',vol,'unit_price',(s.snapshot->>'unit_price')::numeric,'status','delivered'),null);
 insert into respectlogistic_dispatch_results(id,owner_id,shift_id,trip_id,volume,unit) values(rid,actor,s.id,tid,vol,u);
 insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action,detail) values(actor,s.request_id,s.id,'unloaded',jsonb_build_object('trip_id',tid,'volume',vol,'unit',u));
 perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);perform set_config('TimeZone',oldzone,true);return tid;
exception when others then perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);perform set_config('TimeZone',oldzone,true);raise;
end$$;

create function public.respectlogistic_dispatch_template(p_record jsonb,p_archive boolean default false) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;path text=p_record->>'storage_path';begin
 if actor is null or rid is null or octet_length(p_record::text)>5000 then raise exception 'Проверьте шаблон';end if;
 if p_archive then update respectlogistic_dispatch_templates set active=false where id=rid and owner_id=actor;if not found then raise exception 'Шаблон недоступен';end if;return rid;end if;
 if p_record->>'kind' not in ('ttn','waybill','invoice') or coalesce(trim(p_record->>'name'),'')='' or path not like actor::text||'/'||rid::text||'/%' or path !~ '\.(pdf|docx)$' then raise exception 'Загрузите образец PDF или DOCX';end if;
 if not exists(select 1 from storage.objects where bucket_id='respectlogistic-dispatch-templates' and name=path) then raise exception 'Сначала загрузите файл';end if;
 if exists(select 1 from respectlogistic_dispatch_templates where id=rid and (owner_id<>actor or storage_path<>path)) then raise exception 'Шаблон недоступен';end if;
 insert into respectlogistic_dispatch_templates(id,owner_id,kind,name,storage_path) values(rid,actor,p_record->>'kind',left(trim(p_record->>'name'),400),path) on conflict(id) do nothing;return rid;
end$$;

create function public.respectlogistic_dispatch_documents(p_batch uuid,p_shifts uuid[],p_kinds jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();s respectlogistic_dispatch_shifts;item jsonb;n integer;count_value integer;copies_value integer;num integer;begin
 if actor is null or p_batch is null or coalesce(cardinality(p_shifts),0) not between 1 and 50 or jsonb_typeof(p_kinds) is distinct from 'array' or jsonb_array_length(p_kinds) not between 1 and 3 then raise exception 'Выберите смены и типы бланков';end if;
 if (select count(distinct x->>'kind') from jsonb_array_elements(p_kinds) x)<>jsonb_array_length(p_kinds) then raise exception 'Тип бланка выбран дважды';end if;
 for item in select * from jsonb_array_elements(p_kinds) loop
  count_value=(item->>'count')::integer;copies_value=(item->>'copies')::integer;
  if item->>'kind' not in ('ttn','waybill','invoice') or count_value is null or count_value not between 1 and 50 or copies_value is null or copies_value not between 1 and 10 then raise exception 'Укажите от 1 до 50 бланков и от 1 до 10 экземпляров';end if;
 end loop;
 if cardinality(p_shifts)*(select sum((x->>'count')::integer) from jsonb_array_elements(p_kinds) x)>200 then raise exception 'За один раз можно сформировать до 200 уникальных бланков';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 if exists(select 1 from respectlogistic_dispatch_documents where owner_id=actor and batch_id=p_batch) then return coalesce((select jsonb_agg(to_jsonb(d) order by d.number) from respectlogistic_dispatch_documents d where d.owner_id=actor and d.batch_id=p_batch),'[]');end if;
 if exists(select 1 from unnest(p_shifts) as requested(requested_id) where not exists(select 1 from respectlogistic_dispatch_shifts check_shift where check_shift.id=requested.requested_id and check_shift.owner_id=actor and check_shift.status<>'cancelled')) then raise exception 'Одна из смен недоступна или отменена';end if;
 for s in select * from respectlogistic_dispatch_shifts where id=any(p_shifts) and owner_id=actor loop
  for item in select * from jsonb_array_elements(p_kinds) loop
   for n in 1..(item->>'count')::integer loop
    insert into respectlogistic_dispatch_counters(owner_id,document_no) values(actor,1) on conflict(owner_id) do update set document_no=respectlogistic_dispatch_counters.document_no+1 returning document_no into num;
    insert into respectlogistic_dispatch_documents(owner_id,shift_id,batch_id,kind,ordinal,number,copies,snapshot) values(actor,s.id,p_batch,item->>'kind',n,num,(item->>'copies')::integer,s.snapshot||jsonb_build_object('shift_date',s.shift_date,'starts_at',s.starts_at,'ends_at',s.ends_at,'driver_name',s.driver_name));
   end loop;
  end loop;
 end loop;
 return coalesce((select jsonb_agg(to_jsonb(d) order by d.number) from respectlogistic_dispatch_documents d where d.owner_id=actor and d.batch_id=p_batch),'[]');
end$$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('respectlogistic-dispatch-templates','respectlogistic-dispatch-templates',false,5242880,array['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document']) on conflict(id) do nothing;
create policy dispatch_template_read on storage.objects for select to authenticated using(bucket_id='respectlogistic-dispatch-templates' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy dispatch_template_upload on storage.objects for insert to authenticated with check(bucket_id='respectlogistic-dispatch-templates' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy dispatch_template_delete on storage.objects for delete to authenticated using(bucket_id='respectlogistic-dispatch-templates' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.respectlogistic_dispatch_templates t where t.owner_id=(select auth.uid()) and t.storage_path=storage.objects.name));

revoke all on function public.respectlogistic_read_dispatch(),public.respectlogistic_save_dispatch(jsonb,integer,text),public.respectlogistic_assign_dispatch(uuid,integer,date,date,jsonb),public.respectlogistic_dispatch_action(uuid,integer,text),public.respectlogistic_dispatch_template(jsonb,boolean),public.respectlogistic_dispatch_documents(uuid,uuid[],jsonb),public.respectlogistic_driver_dispatch(text,text,uuid,integer,jsonb),public.respectlogistic_dispatch_result(uuid,jsonb,integer,text) from public,anon,authenticated;
grant execute on function public.respectlogistic_read_dispatch(),public.respectlogistic_save_dispatch(jsonb,integer,text),public.respectlogistic_assign_dispatch(uuid,integer,date,date,jsonb),public.respectlogistic_dispatch_action(uuid,integer,text),public.respectlogistic_dispatch_template(jsonb,boolean),public.respectlogistic_dispatch_documents(uuid,uuid[],jsonb),public.respectlogistic_dispatch_result(uuid,jsonb,integer,text) to authenticated;
grant execute on function public.respectlogistic_driver_dispatch(text,text,uuid,integer,jsonb),public.respectlogistic_dispatch_result(uuid,jsonb,integer,text) to anon;
notify pgrst,'reload schema';
create function public.respectlogistic_dispatch_send(p_ids uuid[],p_versions jsonb) returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();sid uuid;begin
 if actor is null or coalesce(cardinality(p_ids),0) not between 1 and 500 then raise exception 'Выберите смены для отправки';end if;
 foreach sid in array p_ids loop perform public.respectlogistic_dispatch_action(sid,(p_versions->>sid::text)::integer,'send');end loop;
end$$;
revoke all on function public.respectlogistic_dispatch_send(uuid[],jsonb) from public,anon,authenticated;
grant execute on function public.respectlogistic_dispatch_send(uuid[],jsonb) to authenticated;
revoke all on sequence public.respectlogistic_dispatch_events_id_seq from public,anon,authenticated;
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
