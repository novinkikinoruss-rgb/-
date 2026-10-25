-- Progress exists before a trip earns salary; completion reuses the existing trip/payroll RPC.
create table public.respectlogistic_mobile_runs(
 id uuid primary key,owner_id uuid not null references auth.users,driver_id uuid not null references public.crm_drivers,
 duty_id uuid not null references public.respectlogistic_driver_duties,shift_id uuid not null references public.respectlogistic_dispatch_shifts,
 shift_version integer not null,stage text not null default 'heading' check(stage in ('heading','loading','unloaded','completed','interrupted')),
 trip_id uuid references public.crm_trips,volume numeric,created_at timestamptz not null default clock_timestamp(),modified_at timestamptz not null default clock_timestamp()
);
create unique index mobile_one_run on public.respectlogistic_mobile_runs(driver_id) where stage not in ('completed','interrupted');
create index mobile_runs_owner on public.respectlogistic_mobile_runs(owner_id);
create index mobile_runs_duty on public.respectlogistic_mobile_runs(duty_id);
create index mobile_runs_shift on public.respectlogistic_mobile_runs(shift_id);
create index mobile_runs_trip on public.respectlogistic_mobile_runs(trip_id);
create table public.respectlogistic_mobile_expenses(
 id uuid primary key,owner_id uuid not null references auth.users,driver_id uuid not null references public.crm_drivers,vehicle_id uuid not null references public.crm_vehicles,
 kind text not null check(kind in ('fuel','repair')),expense_date date not null,litres numeric,price numeric,total numeric not null check(total>0 and total<100000000),note text not null default '',created_at timestamptz not null default clock_timestamp()
);
create index mobile_expenses_owner on public.respectlogistic_mobile_expenses(owner_id);
create index mobile_expenses_driver on public.respectlogistic_mobile_expenses(driver_id,expense_date);
create index mobile_expenses_vehicle on public.respectlogistic_mobile_expenses(vehicle_id);
create table public.respectlogistic_mobile_photos(
 id uuid primary key,owner_id uuid not null references auth.users,driver_id uuid not null references public.crm_drivers,
 run_id uuid references public.respectlogistic_mobile_runs,expense_id uuid references public.respectlogistic_mobile_expenses,
 kind text not null check(kind in ('document','receipt','repair')),file_name text not null,data bytea not null check(octet_length(data) between 4 and 2097152),created_at timestamptz not null default clock_timestamp(),check(num_nonnulls(run_id,expense_id)=1)
);
create index mobile_photos_owner on public.respectlogistic_mobile_photos(owner_id);
create index mobile_photos_driver on public.respectlogistic_mobile_photos(driver_id);
create index mobile_photos_run on public.respectlogistic_mobile_photos(run_id);
create index mobile_photos_expense on public.respectlogistic_mobile_photos(expense_id);
alter table public.respectlogistic_mobile_runs enable row level security;
alter table public.respectlogistic_mobile_expenses enable row level security;
alter table public.respectlogistic_mobile_photos enable row level security;
revoke all on public.respectlogistic_mobile_runs,public.respectlogistic_mobile_expenses,public.respectlogistic_mobile_photos from public,anon,authenticated;
create policy mobile_runs_owner on public.respectlogistic_mobile_runs for select to authenticated using(owner_id=(select auth.uid()));
create policy mobile_expenses_owner on public.respectlogistic_mobile_expenses for select to authenticated using(owner_id=(select auth.uid()));
create policy mobile_photos_owner on public.respectlogistic_mobile_photos for select to authenticated using(owner_id=(select auth.uid()));
grant select on public.respectlogistic_mobile_runs,public.respectlogistic_mobile_expenses to authenticated;
grant select(id,owner_id,driver_id,run_id,expense_id,kind,file_name,created_at) on public.respectlogistic_mobile_photos to authenticated;
alter table public.respectlogistic_driver_duties add column technical_note text not null default '',add column end_reason text;

create function public.respectlogistic_driver_mobile(p_token text default null,p_action text default 'list',p_record jsonb default '{}',p_base64 text default null) returns jsonb
language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;actor uuid;rid uuid=nullif(p_record->>'id','')::uuid;r respectlogistic_mobile_runs;d respectlogistic_driver_duties;s respectlogistic_dispatch_shifts;e respectlogistic_mobile_expenses;f respectlogistic_mobile_photos;report uuid;tid uuid;bytes bytea;vol numeric;lit numeric;price_value numeric;total_value numeric;day date;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;else actor=auth.uid();end if;
 if actor is null then raise exception 'Войдите повторно' using errcode='28000';end if;
 if octet_length(p_record::text)>16000 then raise exception 'Слишком много данных';end if;
 if p_action='list' then
 return jsonb_build_object('mobile_vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'assigned_driver_id',v.assigned_driver_id,'odometer_km',v.odometer_km,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=actor and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and (a.driver_id is null or v.assigned_driver_id=a.driver_id or exists(select 1 from respectlogistic_driver_duties dd where dd.owner_id=actor and dd.driver_id=a.driver_id and dd.vehicle_id=v.id and dd.ended_at is null) or exists(select 1 from respectlogistic_dispatch_shifts ss where ss.owner_id=actor and ss.driver_id=a.driver_id and ss.vehicle_id=v.id and ss.status='accepted' and (clock_timestamp() at time zone (ss.snapshot->>'time_zone'))::date between ss.shift_date and (ss.ends_at at time zone (ss.snapshot->>'time_zone'))::date))),'[]'),'mobile_runs',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.created_at desc) from respectlogistic_mobile_runs x where x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'expenses',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.expense_date desc,x.created_at desc) from respectlogistic_mobile_expenses x where x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'mobile_photos',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'run_id',x.run_id,'expense_id',x.expense_id,'kind',x.kind,'file_name',x.file_name)) from respectlogistic_mobile_photos x where x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'salary',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'trip_id',x.trip_id,'date',x.accrual_date,'base',x.base,'bonus',x.bonus,'deducted',coalesce((select sum(y.amount) from crm_payroll_deductions y where y.accrual_id=x.id and y.owner_id=actor),0),'trip_number',t.trip_number,'volume',t.volume,'unit',t.unit,'service_name',t.service_name) order by x.accrual_date desc) from crm_payroll_accruals x join crm_trips t on t.id=x.trip_id and t.owner_id=actor and t.app_scope='respectlogistic' and t.carrier_id is null and t.deleted_at is null where x.owner_id=actor and x.active and (a.driver_id is null or x.driver_id=a.driver_id) and x.driver_id=t.driver_id),'[]'));
 end if;
 if p_action='file' then
 select * into f from respectlogistic_mobile_photos where id=rid and owner_id=actor and (a.driver_id is null or driver_id=a.driver_id);
 if f.id is null then raise exception 'Фото недоступно';end if;
 return jsonb_build_object('base64',encode(f.data,'base64'),'name',f.file_name);
 end if;
 if a.driver_id is null then raise exception 'Требуется вход водителя';end if;
 -- Same lock as dispatch changes: assignment cannot change between validation and completion.
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 perform id from crm_drivers where id=a.driver_id and owner_id=actor and app_scope='respectlogistic' and carrier_id is null for update;
 if p_action='expense' then
 if rid is null then raise exception 'Нет номера записи';end if;
 select * into e from respectlogistic_mobile_expenses where id=rid;
 if e.id is not null then if e.owner_id<>actor or e.driver_id<>a.driver_id then raise exception 'Запись недоступна';end if;if e.vehicle_id is distinct from (p_record->>'vehicle_id')::uuid or e.kind is distinct from p_record->>'kind' or e.expense_date is distinct from (p_record->>'date')::date or e.litres is distinct from nullif(p_record->>'litres','')::numeric or e.price is distinct from nullif(p_record->>'price','')::numeric or e.total is distinct from (p_record->>'total')::numeric or e.note is distinct from coalesce(p_record->>'note','') then raise exception 'Запись уже сохранена с другими данными. Завершите загрузку фото с исходными значениями';end if;return to_jsonb(e)-'owner_id';end if;
 day=(p_record->>'date')::date;lit=nullif(p_record->>'litres','')::numeric;price_value=nullif(p_record->>'price','')::numeric;total_value=(p_record->>'total')::numeric;
 if day is null or day>(clock_timestamp() at time zone 'Europe/Moscow')::date or day<(clock_timestamp() at time zone 'Europe/Moscow')::date-30 or p_record->>'kind' is null or p_record->>'kind' not in ('fuel','repair') or total_value is null or total_value<=0 or total_value>=100000000 or total_value::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте дату и сумму';end if;
 if p_record->>'kind'='fuel' and (lit is null or price_value is null or lit<=0 or lit>10000 or price_value<=0 or price_value>10000 or lit::text='NaN' or price_value::text='NaN' or abs(round(lit*price_value,2)-total_value)>1) then raise exception 'Проверьте литры, цену и итог чека';end if;
 if not exists(select 1 from crm_vehicles v where v.id=(p_record->>'vehicle_id')::uuid and v.owner_id=actor and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and (v.assigned_driver_id=a.driver_id or exists(select 1 from respectlogistic_driver_duties x where x.owner_id=actor and x.driver_id=a.driver_id and x.vehicle_id=v.id and x.started_at::date<=day and coalesce(x.ended_at,clock_timestamp())::date>=day))) then raise exception 'Машина недоступна';end if;
 if p_record->>'kind'='repair' and trim(coalesce(p_record->>'note',''))='' then raise exception 'Опишите ремонт';end if;
 insert into respectlogistic_mobile_expenses(id,owner_id,driver_id,vehicle_id,kind,expense_date,litres,price,total,note) values(rid,actor,a.driver_id,(p_record->>'vehicle_id')::uuid,p_record->>'kind',day,lit,price_value,total_value,left(coalesce(p_record->>'note',''),4000));return jsonb_build_object('id',rid);
 end if;
 select * into d from respectlogistic_driver_duties where owner_id=actor and driver_id=a.driver_id and ended_at is null for update;
 if p_action='end' then
 if d.id is null then if exists(select 1 from respectlogistic_driver_duties where id=rid and owner_id=actor and driver_id=a.driver_id and ended_at is not null and end_reason=p_record->>'reason' and end_odometer=(p_record->>'odometer')::numeric and technical_note=p_record->>'technical_note') then return '{}';end if;raise exception 'Смена уже завершена';end if;
 if nullif(p_record->>'id','')::uuid is distinct from d.id then raise exception 'Смена изменилась. Обновите экран';end if;
 if trim(coalesce(p_record->>'technical_note',''))='' or p_record->>'reason' is null or p_record->>'reason' not in ('normal','breakdown') then raise exception 'Укажите техническое состояние машины';end if;
 if p_record->>'reason'='normal' and exists(select 1 from respectlogistic_mobile_runs where duty_id=d.id and stage not in ('completed','interrupted')) then raise exception 'Сначала сохраните текущий рейс или завершите смену из-за поломки';end if;
 perform respectlogistic_duty_action(p_token,d.vehicle_id,'end',(p_record->>'odometer')::numeric);
 update respectlogistic_driver_duties set technical_note=left(p_record->>'technical_note',4000),end_reason=p_record->>'reason' where id=d.id;
 update respectlogistic_mobile_runs set stage='interrupted',modified_at=clock_timestamp() where duty_id=d.id and stage not in ('completed','interrupted');
 day=(clock_timestamp() at time zone 'Europe/Moscow')::date;
 select id into report from respectlogistic_driver_shift_reports where owner_id=actor and driver_id=a.driver_id and vehicle_id=d.vehicle_id and shift_date=day and status not in ('rejected','cancelled');
 if report is null then insert into respectlogistic_driver_shift_reports(id,owner_id,driver_id,vehicle_id,shift_date,odometer,technical_note,comment,status) values(gen_random_uuid(),actor,a.driver_id,d.vehicle_id,day,(p_record->>'odometer')::numeric,left(p_record->>'technical_note',4000),case when p_record->>'reason'='breakdown' then 'Смена завершена: поломка' else 'Смена завершена' end,'submitted');
 else update respectlogistic_driver_shift_reports set technical_note=left(p_record->>'technical_note',4000),odometer=greatest(odometer,(p_record->>'odometer')::numeric),modified_at=clock_timestamp(),status=case when status='draft' then 'submitted' else status end where id=report;end if;
 return '{}';
 end if;
 if p_action='start' then
 if d.id is null then raise exception 'Сначала начните смену';end if;
 select * into r from respectlogistic_mobile_runs where id=rid;
 if r.id is not null then if r.owner_id<>actor or r.driver_id<>a.driver_id then raise exception 'Рейс недоступен';end if;return to_jsonb(r)-'owner_id';end if;
 select * into s from respectlogistic_dispatch_shifts where id=(p_record->>'shift_id')::uuid and owner_id=actor and driver_id=a.driver_id and carrier_id is null for update;
 if rid is null or s.id is null or s.status<>'accepted' or s.vehicle_id<>d.vehicle_id or (clock_timestamp() at time zone (s.snapshot->>'time_zone'))::date not between s.shift_date and (s.ends_at at time zone (s.snapshot->>'time_zone'))::date then raise exception 'Выберите принятую заявку на дату и машину смены';end if;
 insert into respectlogistic_mobile_runs(id,owner_id,driver_id,duty_id,shift_id,shift_version) values(rid,actor,a.driver_id,d.id,s.id,s.version);return jsonb_build_object('id',rid);
 end if;
 if p_action='photo' then
 if rid is null or p_base64 is null or length(p_base64)>2796208 then raise exception 'Выберите фото до 2 МБ';end if;
 select * into f from respectlogistic_mobile_photos where id=rid;
 if f.id is not null then if f.owner_id<>actor or f.driver_id<>a.driver_id then raise exception 'Фото недоступно';end if;return jsonb_build_object('id',rid);end if;
 if nullif(p_record->>'run_id','') is not null then
 select * into r from respectlogistic_mobile_runs where id=(p_record->>'run_id')::uuid and owner_id=actor and driver_id=a.driver_id for update;
 if r.id is null or r.stage<>'unloaded' or d.id is distinct from r.duty_id or p_record->>'kind' is distinct from 'document' then raise exception 'Фото доступно после выгрузки';end if;
 else
 select * into e from respectlogistic_mobile_expenses where id=(p_record->>'expense_id')::uuid and owner_id=actor and driver_id=a.driver_id for update;
 if e.id is null or p_record->>'kind' is null or p_record->>'kind' not in ('receipt','repair') then raise exception 'Расход недоступен';end if;
 end if;
 if (select count(*) from respectlogistic_mobile_photos x where (r.id is not null and x.run_id=r.id) or (e.id is not null and x.expense_id=e.id))>=12 then raise exception 'Не более 12 фотографий на запись';end if;
 bytes=decode(p_base64,'base64');if octet_length(bytes) not between 4 and 2097152 or substring(bytes from 1 for 3)<>decode('ffd8ff','hex') then raise exception 'Нужно фото JPEG до 2 МБ';end if;
 insert into respectlogistic_mobile_photos(id,owner_id,driver_id,run_id,expense_id,kind,file_name,data) values(rid,actor,a.driver_id,r.id,e.id,p_record->>'kind',left(coalesce(p_record->>'file_name','Фото.jpg'),200),bytes);return jsonb_build_object('id',rid);
 end if;
 select * into r from respectlogistic_mobile_runs where id=rid and owner_id=actor and driver_id=a.driver_id for update;
 if r.id is null then raise exception 'Рейс недоступен';end if;
 if p_action='complete' and r.stage='completed' then
 if r.volume is distinct from (p_record->>'volume')::numeric then raise exception 'Рейс уже сохранён с другим объёмом';end if;return jsonb_build_object('trip_id',r.trip_id);end if;
 if d.id is distinct from r.duty_id then raise exception 'Начните свою смену';end if;
 if p_action='stage' then
 if p_record->>'stage' is not distinct from r.stage then return '{}';end if;
 if (r.stage='heading' and p_record->>'stage'='loading') or (r.stage='loading' and p_record->>'stage'='unloaded') then update respectlogistic_mobile_runs set stage=p_record->>'stage',modified_at=clock_timestamp() where id=r.id;else raise exception 'Соблюдайте порядок этапов';end if;return '{}';
 elsif p_action='complete' then
 if r.stage<>'unloaded' or not exists(select 1 from respectlogistic_mobile_photos where run_id=r.id and kind='document') then raise exception 'После выгрузки сфотографируйте документы';end if;
 select * into s from respectlogistic_dispatch_shifts where id=r.shift_id and owner_id=actor and driver_id=a.driver_id and carrier_id is null for update;
 if s.id is null or s.version<>r.shift_version or s.status<>'accepted' then raise exception 'Заявка изменилась. Обратитесь к диспетчеру';end if;
 vol=(p_record->>'volume')::numeric;day=(clock_timestamp() at time zone (s.snapshot->>'time_zone'))::date;
 tid=respectlogistic_dispatch_result(r.shift_id,jsonb_build_object('id',r.id,'volume',vol,'unit',s.snapshot->>'unit','date',day),r.shift_version,p_token);
 -- Existing file infrastructure exposes these documents under the actual trip in CRM/Drive.
 select id into report from respectlogistic_driver_shift_reports where owner_id=actor and driver_id=a.driver_id and vehicle_id=d.vehicle_id and shift_date=day and status not in ('rejected','cancelled');
 if report is null then insert into respectlogistic_driver_shift_reports(id,owner_id,driver_id,vehicle_id,shift_date,odometer) values(gen_random_uuid(),actor,a.driver_id,d.vehicle_id,day,d.start_odometer) returning id into report;end if;
 insert into respectlogistic_driver_shift_files(id,report_id,owner_id,driver_id,trip_id,kind,file_name,mime_type,file_size,data) select x.id,report,actor,a.driver_id,tid,'document',x.file_name,'image/jpeg',octet_length(x.data),x.data from respectlogistic_mobile_photos x where x.run_id=r.id;
 update respectlogistic_mobile_runs set stage='completed',trip_id=tid,volume=vol,modified_at=clock_timestamp() where id=r.id;return jsonb_build_object('trip_id',tid);
 end if;
 raise exception 'Недоступное действие';
end$$;
revoke all on function public.respectlogistic_driver_mobile(text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.respectlogistic_driver_mobile(text,text,jsonb,text) to anon,authenticated;
notify pgrst,'reload schema';
