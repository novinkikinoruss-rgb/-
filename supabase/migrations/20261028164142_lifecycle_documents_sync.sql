CREATE OR REPLACE FUNCTION public.respectlogistic_driver_mobile(p_token text DEFAULT NULL::text, p_action text DEFAULT 'list'::text, p_record jsonb DEFAULT '{}'::jsonb, p_base64 text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare a respectlogistic_driver_accounts;actor uuid;rid uuid=nullif(p_record->>'id','')::uuid;r respectlogistic_mobile_runs;d respectlogistic_driver_duties;s respectlogistic_dispatch_shifts;e respectlogistic_mobile_expenses;f respectlogistic_mobile_photos;report uuid;tid uuid;bytes bytea;vol numeric;lit numeric;price_value numeric;total_value numeric;day date;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;else actor=auth.uid();end if;
 if actor is null then raise exception 'Войдите повторно' using errcode='28000';end if;
 if octet_length(p_record::text)>16000 then raise exception 'Слишком много данных';end if;
 if p_action='list' then
 return jsonb_build_object('mobile_vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'assigned_driver_id',v.assigned_driver_id,'odometer_km',v.odometer_km,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=actor and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null and (a.driver_id is null or v.assigned_driver_id=a.driver_id or exists(select 1 from respectlogistic_driver_duties dd where dd.owner_id=actor and dd.driver_id=a.driver_id and dd.vehicle_id=v.id and dd.ended_at is null) or exists(select 1 from respectlogistic_dispatch_shifts ss where ss.owner_id=actor and ss.driver_id=a.driver_id and ss.vehicle_id=v.id and ss.status='accepted' and (clock_timestamp() at time zone (ss.snapshot->>'time_zone'))::date between ss.shift_date and (ss.ends_at at time zone (ss.snapshot->>'time_zone'))::date))),'[]'),'mobile_runs',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.created_at desc) from respectlogistic_mobile_runs x where (x.trip_id is null or exists(select 1 from crm_trips mt where mt.id=x.trip_id and mt.owner_id=actor and mt.app_scope='respectlogistic' and mt.deleted_at is null)) and exists(select 1 from respectlogistic_dispatch_shifts ms join respectlogistic_dispatch_requests mr on mr.id=ms.request_id and mr.owner_id=actor where ms.id=x.shift_id and ms.owner_id=actor and ms.status<>'cancelled' and mr.cancelled_at is null) and x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'expenses',coalesce((select jsonb_agg(to_jsonb(x)-'owner_id' order by x.expense_date desc,x.created_at desc) from respectlogistic_mobile_expenses x where x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'mobile_photos',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'run_id',x.run_id,'expense_id',x.expense_id,'kind',x.kind,'file_name',x.file_name)) from respectlogistic_mobile_photos x where (x.run_id is null or exists(select 1 from respectlogistic_mobile_runs pr left join crm_trips pt on pt.id=pr.trip_id and pt.owner_id=actor and pt.app_scope='respectlogistic' join respectlogistic_dispatch_shifts ps on ps.id=pr.shift_id and ps.owner_id=actor join respectlogistic_dispatch_requests pq on pq.id=ps.request_id and pq.owner_id=actor where pr.id=x.run_id and pr.owner_id=actor and (pr.trip_id is null or pt.id is not null and pt.deleted_at is null) and ps.status<>'cancelled' and pq.cancelled_at is null)) and x.owner_id=actor and (a.driver_id is null or x.driver_id=a.driver_id)),'[]'),
 'salary',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'trip_id',x.trip_id,'date',x.accrual_date,'base',x.base,'bonus',x.bonus,'deducted',coalesce((select sum(y.amount) from crm_payroll_deductions y where y.accrual_id=x.id and y.owner_id=actor),0),'trip_number',t.trip_number,'volume',t.volume,'unit',t.unit,'service_name',t.service_name) order by x.accrual_date desc) from crm_payroll_accruals x join crm_trips t on t.id=x.trip_id and t.owner_id=actor and t.app_scope='respectlogistic' and t.carrier_id is null and t.deleted_at is null where x.owner_id=actor and x.active and (a.driver_id is null or x.driver_id=a.driver_id) and x.driver_id=t.driver_id),'[]'));
 end if;
 if p_action='file' then
 select * into f from respectlogistic_mobile_photos where id=rid and owner_id=actor and (a.driver_id is null or driver_id=a.driver_id);
 if f.id is null or f.run_id is not null and not exists(select 1 from respectlogistic_mobile_runs fr join respectlogistic_dispatch_shifts fs on fs.id=fr.shift_id and fs.owner_id=actor join respectlogistic_dispatch_requests fq on fq.id=fs.request_id and fq.owner_id=actor left join crm_trips ft on ft.id=fr.trip_id and ft.owner_id=actor and ft.app_scope='respectlogistic' where fr.id=f.run_id and fr.owner_id=actor and fs.status<>'cancelled' and fq.cancelled_at is null and (fr.trip_id is null or ft.id is not null and ft.deleted_at is null)) then raise exception 'Фото недоступно';end if;
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
end$function$

;

CREATE OR REPLACE FUNCTION public.respectlogistic_driver_dispatch(p_token text, p_action text DEFAULT 'list'::text, p_id uuid DEFAULT NULL::uuid, p_expected integer DEFAULT NULL::integer, p_record jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare a respectlogistic_driver_accounts;s respectlogistic_dispatch_shifts;begin
 a=respectlogistic_require_driver(p_token);
 if p_action='list' then
  update respectlogistic_dispatch_shifts set seen_at=clock_timestamp() where owner_id=a.owner_id and driver_id=a.driver_id and carrier_id is null and status='sent' and seen_at is null;
  return jsonb_build_object('dispatch_shifts',coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'request_id',x.request_id,'shift_date',x.shift_date,'vehicle_id',x.vehicle_id,'starts_at',x.starts_at,'ends_at',x.ends_at,'status',x.status,'version',x.version,'sent_at',x.sent_at,'accepted_at',x.accepted_at,'response_note',x.response_note,'details',x.snapshot-'unit_price'-'customer_id'-'site_id','results',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'trip_id',r.trip_id,'volume',r.volume,'unit',r.unit,'created_at',r.created_at)) from respectlogistic_dispatch_results r where r.shift_id=x.id and r.owner_id=a.owner_id and exists(select 1 from crm_trips rt where rt.id=r.trip_id and rt.owner_id=a.owner_id and rt.app_scope='respectlogistic' and rt.deleted_at is null)),'[]')) order by x.shift_date,x.starts_at) from respectlogistic_dispatch_shifts x where x.owner_id=a.owner_id and x.driver_id=a.driver_id and x.carrier_id is null and x.sent_at is not null and x.status<>'cancelled' and exists(select 1 from respectlogistic_dispatch_requests rq where rq.id=x.request_id and rq.owner_id=a.owner_id and rq.cancelled_at is null) and x.shift_date>=(clock_timestamp() at time zone (x.snapshot->>'time_zone'))::date-30),'[]'),
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
end$function$

;

CREATE OR REPLACE FUNCTION public.respectlogistic_driver_extras(p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object(
 'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'driver_id',n.driver_id,'title',n.title,'has_credentials',n.has_credentials,'modified_at',n.modified_at)) from respectlogistic_driver_notes n where n.owner_id=actor and n.deleted_at is null and (a.driver_id is null or n.driver_id=a.driver_id)),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(s)-'owner_id' order by s.created_at desc) from respectlogistic_driver_shift_reports s where s.owner_id=actor and (a.driver_id is null or s.driver_id=a.driver_id)),'[]'),
 'shift_files',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'report_id',f.report_id,'driver_id',f.driver_id,'trip_id',f.trip_id,'kind',f.kind,'file_name',f.file_name,'mime_type',f.mime_type,'file_size',f.file_size)) from respectlogistic_driver_shift_files f where (f.trip_id is null or exists(select 1 from crm_trips et where et.id=f.trip_id and et.owner_id=actor and et.app_scope='respectlogistic' and et.deleted_at is null)) and f.owner_id=actor and (a.driver_id is null or f.driver_id=a.driver_id)),'[]'),
 'driver_trips',case when a.driver_id is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'trip_number',t.trip_number,'trip_date',t.trip_date,'status',t.status,'service_name',t.service_name,'vehicle_id',t.vehicle_id,'object',s.payload->>'name')) from crm_trips t join respectlogistic_sites s on s.id=t.site_id and s.owner_id=actor where t.owner_id=actor and t.app_scope='respectlogistic' and t.driver_id=a.driver_id and t.deleted_at is null and t.trip_date>=current_date-30),'[]') end);
end$function$

;

CREATE OR REPLACE FUNCTION public.respectlogistic_accounting_action(p_id uuid, p_action text, p_expected_modified_at timestamp with time zone, p_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor uuid=auth.uid();doc respectlogistic_accounting_documents;advance respectlogistic_accounting_documents;item crm_trips;seller jsonb;buyer jsonb;value numeric;credited numeric;line jsonb;credit_id uuid;
begin
 if actor is null or length(p_payload::text)>20000 then raise exception 'Некорректный запрос';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-accounting',0));
 select * into doc from respectlogistic_accounting_documents where id=p_id and owner_id=actor for update;
 if doc.id is null then raise exception 'Документ недоступен';end if;
 if doc.modified_at is distinct from p_expected_modified_at then raise exception 'Документ изменён в другой вкладке. Обновите данные';end if;
 select coalesce(sum(amount),0) into credited from respectlogistic_accounting_credits where invoice_id=doc.id;
 if p_action='issue' then
  if doc.status<>'draft' then raise exception 'Документ уже сформирован';end if;
  select payload into seller from respectlogistic_accounting_company where owner_id=actor;
  select payload||jsonb_build_object('inn',inn) into buyer from respectlogistic_customers where id=doc.customer_id and owner_id=actor;
  if coalesce(seller->>'name','')='' or coalesce(seller->>'inn','')='' or coalesce(seller->>'legalAddress','')='' or coalesce(buyer->>'legalAddress','')='' then raise exception 'Заполните реквизиты: %',concat_ws('; ',case when coalesce(seller->>'name','')='' then 'название вашей компании' end,case when coalesce(seller->>'inn','')='' then 'ИНН вашей компании' end,case when coalesce(seller->>'legalAddress','')='' then 'юридический адрес вашей компании' end,case when coalesce(buyer->>'legalAddress','')='' then 'юридический адрес заказчика' end);end if;
  if doc.kind in ('invoice','advance') and (coalesce(seller->>'account','')!~ '^[0-9]{20}$' or coalesce(seller->>'bik','')!~ '^[0-9]{9}$' or coalesce(seller->>'bank','')='') then raise exception 'Заполните банк, БИК и расчётный счёт своей компании';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
  perform t.id from crm_trips t join respectlogistic_accounting_trips l on l.trip_id=t.id where l.document_id=doc.id order by t.id for update of t;
  for line in select * from jsonb_array_elements(doc.snapshot->'items') loop
   if line->>'trip_id' is null then continue;end if;
   select * into item from rl_crm_trips where id=(line->>'trip_id')::uuid and deleted_at is null;
   if item.id is null or item.status not in ('sent','delivered') or item.customer_id is distinct from doc.customer_id or item.site_id is distinct from (line->>'site_id')::uuid or item.trip_number is distinct from line->>'trip_number' or item.trip_date is distinct from (line->>'trip_date')::date or item.volume is distinct from (line->>'quantity')::numeric or item.unit_price is distinct from (line->>'price')::numeric or item.loading_address is distinct from line->>'loading_address' or item.unloading_address is distinct from line->>'unloading_address' or item.unit is distinct from line->>'unit' or coalesce(item.service_name,'Услуга') is distinct from line->>'service' or (select plate from rl_crm_vehicles where id=item.vehicle_id) is distinct from line->>'plate' then raise exception 'Данные рейса изменились. Отмените черновик и сформируйте новый';end if;
   if doc.kind in ('upd','registry') then
    if (p_payload->>'complete_trips')::boolean is distinct from true then raise exception 'Подтвердите выполнение услуг и завершение рейсов';end if;
    if item.trip_date>(clock_timestamp() at time zone 'Europe/Moscow')::date or (item.carrier_id is null and item.driver_id is null) then raise exception 'Для завершения рейса проверьте дату и водителя';end if;
    update crm_trips set status='delivered' where id=item.id and status<>'delivered';
   end if;
  end loop;
  update respectlogistic_accounting_documents set status='issued',snapshot=snapshot||jsonb_build_object('seller',seller,'customer',buyer) where id=doc.id;
 elsif p_action in ('sent','signed') then
  if (p_action='sent' and doc.status<>'issued') or (p_action='signed' and doc.status not in ('issued','sent')) then raise exception 'Недопустимый переход статуса';end if;
  update respectlogistic_accounting_documents set status=p_action where id=doc.id;
 elsif p_action='cancel' then
  if doc.status in ('signed','cancelled') or doc.paid_amount>0 or exists(select 1 from respectlogistic_accounting_credits where invoice_id=doc.id or advance_id=doc.id) then raise exception 'Оплаченный, зачтённый или подписанный документ требует корректировки';end if;
  update respectlogistic_accounting_documents set status='cancelled' where id=doc.id;
  update respectlogistic_accounting_trips set active=false where document_id=doc.id;
 elsif p_action='payment' then
  value=(p_payload->>'paid_amount')::numeric;
  if doc.kind not in ('invoice','advance') or doc.status not in ('issued','sent','signed') or value is null or value<0 or value>doc.total-credited or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) then raise exception 'Проверьте сумму оплаты с учётом зачтённого аванса';end if;
  if doc.kind='advance' and value<(select coalesce(sum(amount),0) from respectlogistic_accounting_credits where advance_id=doc.id) then raise exception 'Часть аванса уже зачтена';end if;
  update respectlogistic_accounting_documents set paid_amount=value where id=doc.id;
 elsif p_action='credit' then
  value=(p_payload->>'amount')::numeric;credit_id=(p_payload->>'id')::uuid;
  select * into advance from respectlogistic_accounting_documents where id=(p_payload->>'advance_id')::uuid and owner_id=actor for update;
  if credit_id is null or doc.kind<>'invoice' or doc.status not in ('issued','sent','signed') or advance.kind is distinct from 'advance' or advance.status not in ('issued','sent','signed') or advance.customer_id is distinct from doc.customer_id or (advance.site_id is not null and advance.site_id is distinct from doc.site_id) then raise exception 'Выберите оплаченный аванс того же заказчика и объекта';end if;
  if advance.service_name is not null and exists(select 1 from jsonb_array_elements(doc.snapshot->'items') i where trim(coalesce(i->>'service',''))<>trim(advance.service_name)) then raise exception 'Услуга аванса отличается от услуг счёта';end if;
  if exists(select 1 from respectlogistic_accounting_credits where id=credit_id) then raise exception 'Зачёт уже зарегистрирован. Обновите данные';end if;
  if value is null or value<=0 or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) or value>doc.total-doc.paid_amount-credited or value>advance.paid_amount-(select coalesce(sum(amount),0) from respectlogistic_accounting_credits where advance_id=advance.id) then raise exception 'Сумма превышает доступный аванс или остаток счёта';end if;
  insert into respectlogistic_accounting_credits(id,owner_id,advance_id,invoice_id,amount) values(credit_id,actor,advance.id,doc.id,value);
  update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=advance.id;
 else raise exception 'Неизвестное действие';end if;
 update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=doc.id;
 insert into respectlogistic_accounting_history(owner_id,document_id,action,detail) values(actor,doc.id,p_action,jsonb_build_object('before_status',doc.status,'before_paid',doc.paid_amount,'payload',p_payload));
end$function$

;
-- Close unfinished work on every way of ending a duty or cancelling an assignment.
create function public.respectlogistic_interrupt_mobile_work() returns trigger language plpgsql set search_path=public,pg_temp as $$begin
 if tg_table_name='respectlogistic_driver_duties' then
  if new.ended_at is not null and old.ended_at is null then update respectlogistic_mobile_runs set stage='interrupted',modified_at=clock_timestamp() where duty_id=new.id and owner_id=new.owner_id and stage not in ('completed','interrupted');end if;
 elsif new.status='cancelled' and old.status<>'cancelled' then update respectlogistic_mobile_runs set stage='interrupted',modified_at=clock_timestamp() where shift_id=new.id and owner_id=new.owner_id and stage not in ('completed','interrupted');end if;return new;
end$$;
revoke all on function public.respectlogistic_interrupt_mobile_work() from public,anon,authenticated;
create trigger mobile_end_duty after update of ended_at on public.respectlogistic_driver_duties for each row execute function public.respectlogistic_interrupt_mobile_work();
create trigger mobile_cancel_shift after update of status on public.respectlogistic_dispatch_shifts for each row execute function public.respectlogistic_interrupt_mobile_work();
update public.respectlogistic_mobile_runs r set stage='interrupted',modified_at=clock_timestamp() where stage not in ('completed','interrupted') and exists(select 1 from public.respectlogistic_driver_duties d where d.id=r.duty_id and d.owner_id=r.owner_id and d.ended_at is not null);

alter table public.respectlogistic_accounting_documents add column deleted_at timestamptz;
create function public.respectlogistic_manage_accounting_document(p_id uuid,p_expected timestamptz,p_action text,p_record jsonb default '{}') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();d respectlogistic_accounting_documents;day date;due date;ids uuid[];versions jsonb;rid uuid;begin
 if actor is null or octet_length(p_record::text)>16000 then raise exception 'Войдите в CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-accounting',0));
 select * into d from respectlogistic_accounting_documents where id=p_id and owner_id=actor for update;
 if d.id is null or d.modified_at is distinct from p_expected then raise exception 'Документ недоступен или изменён. Обновите список';end if;
 if p_action='restore' then update respectlogistic_accounting_documents set deleted_at=null,modified_at=clock_timestamp() where id=d.id;
 elsif p_action in ('delete','archive') then
  if p_action='delete' and d.status<>'cancelled' then perform respectlogistic_accounting_action(d.id,'cancel',d.modified_at,'{}');end if;
  update respectlogistic_accounting_documents set deleted_at=clock_timestamp(),modified_at=clock_timestamp() where id=d.id;
 elsif p_action='edit' then
  if d.status<>'draft' or d.deleted_at is not null then raise exception 'Сформированный документ исправляется новой версией; исходная версия сохраняется';end if;
  day=(p_record->>'document_date')::date;due=nullif(p_record->>'due_date','')::date;
  if day is null or day>(clock_timestamp() at time zone 'Europe/Moscow')::date or due<day or exists(select 1 from respectlogistic_accounting_trips l join crm_trips t on t.id=l.trip_id and t.owner_id=actor and t.app_scope='respectlogistic' where l.document_id=d.id and l.owner_id=actor and l.active and t.trip_date>day) then raise exception 'Проверьте дату документа, рейсов и срок оплаты';end if;
  update respectlogistic_accounting_documents set document_date=day,due_date=due,notes=left(coalesce(p_record->>'notes',''),4000),modified_at=clock_timestamp() where id=d.id;
 elsif p_action='revise' then
  select array_agg(l.trip_id order by l.trip_id),jsonb_object_agg(t.id,t.modified_at) into ids,versions from respectlogistic_accounting_trips l join crm_trips t on t.id=l.trip_id and t.owner_id=actor and t.app_scope='respectlogistic' and t.deleted_at is null where l.document_id=d.id and l.owner_id=actor and l.active;
  perform respectlogistic_accounting_action(d.id,'cancel',d.modified_at,'{}');
  rid=respectlogistic_create_accounting_document(jsonb_build_object('id',gen_random_uuid(),'kind',d.kind,'customer_id',d.customer_id,'site_id',d.site_id,'invoice_id',d.invoice_id,'document_date',coalesce(p_record->>'document_date',(clock_timestamp() at time zone 'Europe/Moscow')::date::text),'due_date',nullif(p_record->>'due_date',''),'notes',coalesce(p_record->>'notes',d.notes),'service_name',d.service_name,'amount',d.total),coalesce(ids,'{}'),coalesce(versions,'{}'));
  insert into respectlogistic_accounting_history(owner_id,document_id,action,detail) values(actor,rid,'revision',jsonb_build_object('source_document',d.id,'source_number',d.number));return rid;
 else raise exception 'Действие недоступно';end if;
 insert into respectlogistic_accounting_history(owner_id,document_id,action,detail) values(actor,d.id,p_action,jsonb_build_object('previous_status',d.status,'record',p_record));return d.id;
end$$;
revoke all on function public.respectlogistic_manage_accounting_document(uuid,timestamptz,text,jsonb) from public,anon,authenticated;
grant execute on function public.respectlogistic_manage_accounting_document(uuid,timestamptz,text,jsonb) to authenticated;
notify pgrst,'reload schema';

create table public.respectlogistic_google_connections(owner_id uuid primary key references auth.users,encrypted_config bytea not null,last_sync timestamptz,last_error text,modified_at timestamptz not null default clock_timestamp());
alter table public.respectlogistic_google_connections enable row level security;
revoke all on public.respectlogistic_google_connections from public,anon,authenticated;
create policy google_connection_owner on public.respectlogistic_google_connections for select to authenticated using(owner_id=(select auth.uid()));
grant select(owner_id,last_sync,last_error,modified_at) on public.respectlogistic_google_connections to authenticated;
create function public.respectlogistic_google_settings(p_action text default 'status',p_record jsonb default '{}') returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();r respectlogistic_google_connections;key_value text;cfg jsonb='{}';begin
 if actor is null then raise exception 'Войдите как администратор' using errcode='28000';end if;
 if octet_length(p_record::text)>16000 then raise exception 'Слишком большой запрос';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-google',0));
 select * into r from respectlogistic_google_connections where owner_id=actor for update;
 if r.owner_id is not null or p_action in ('save','token') then
  select decrypted_secret into key_value from vault.decrypted_secrets where name='respectlogistic_google_connections_key';
  if key_value is null then perform vault.create_secret(encode(gen_random_bytes(32),'hex'),'respectlogistic_google_connections_key','Google OAuth configuration encryption');select decrypted_secret into key_value from vault.decrypted_secrets where name='respectlogistic_google_connections_key';end if;
  if r.owner_id is not null then cfg=pgp_sym_decrypt(r.encrypted_config,key_value)::jsonb;end if;
 end if;
 if p_action='credentials' then return cfg;end if; -- owner-only; server routes use the owner's verified JWT, never a service-role key.
 if p_action='save' then
  if coalesce(p_record->>'clientId','')!~ '^[a-zA-Z0-9._-]+\.apps\.googleusercontent\.com$' then raise exception 'Проверьте OAuth Client ID';end if;
  if coalesce(p_record->>'clientSecret','')<>'' and (p_record->>'clientSecret') is distinct from cfg->>'clientSecret' or (p_record->>'clientId') is distinct from cfg->>'clientId' then cfg=cfg-'refreshToken';end if;
  cfg=cfg||jsonb_build_object('clientId',p_record->>'clientId','clientSecret',coalesce(nullif(p_record->>'clientSecret',''),cfg->>'clientSecret'),'rootFolder','16EV7FQC6-89aIsFXJE9DPWH5O1LKD5W8','spreadsheetId','11k_GIdfhfW9EmUztr-EjHqDhl1PteepuloRrA0Pfdho');
  if coalesce(cfg->>'clientSecret','')='' then raise exception 'Введите Client Secret OAuth-клиента Google';end if;
 elsif p_action='token' then
  if coalesce(p_record->>'refreshToken','')='' or coalesce(cfg->>'clientId','')='' then raise exception 'Нет подтверждённого подключения Google';end if;cfg=cfg||jsonb_build_object('refreshToken',p_record->>'refreshToken');
 elsif p_action='synced' then update respectlogistic_google_connections set last_sync=clock_timestamp(),last_error=null,modified_at=clock_timestamp() where owner_id=actor;
 elsif p_action='error' then update respectlogistic_google_connections set last_error=left(p_record->>'message',1000),modified_at=clock_timestamp() where owner_id=actor;
 elsif p_action<>'status' then raise exception 'Действие недоступно';end if;
 if p_action in ('save','token') then insert into respectlogistic_google_connections(owner_id,encrypted_config) values(actor,pgp_sym_encrypt(cfg::text,key_value,'cipher-algo=aes256')) on conflict(owner_id) do update set encrypted_config=excluded.encrypted_config,modified_at=clock_timestamp();end if;
 select * into r from respectlogistic_google_connections where owner_id=actor;
 return jsonb_build_object('configured',coalesce(cfg->>'refreshToken','')<>'','hasClient',coalesce(cfg->>'clientId','')<>'','clientId',cfg->>'clientId','folderUrl','https://drive.google.com/drive/folders/16EV7FQC6-89aIsFXJE9DPWH5O1LKD5W8','sheetUrl','https://docs.google.com/spreadsheets/d/11k_GIdfhfW9EmUztr-EjHqDhl1PteepuloRrA0Pfdho/edit','lastSync',r.last_sync,'error',r.last_error);
end$$;
revoke all on function public.respectlogistic_google_settings(text,jsonb) from public,anon,authenticated;
grant execute on function public.respectlogistic_google_settings(text,jsonb) to authenticated;
notify pgrst,'reload schema';

-- A stale file ID must not expose the history of a deleted trip to a driver.
create or replace function public.respectlogistic_driver_file(p_id uuid,p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;f respectlogistic_driver_shift_files;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 select * into f from respectlogistic_driver_shift_files where id=p_id and owner_id=actor;
 if actor is null or f.id is null or (a.driver_id is not null and (f.driver_id<>a.driver_id or (f.trip_id is not null and not exists(select 1 from crm_trips t where t.id=f.trip_id and t.owner_id=actor and t.app_scope='respectlogistic' and t.deleted_at is null)))) then raise exception 'Файл недоступен';end if;
 return jsonb_build_object('name',f.file_name,'mime_type',f.mime_type,'base64',encode(f.data,'base64'));
end$$;
