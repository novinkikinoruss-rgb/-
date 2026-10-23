-- Isolated accounting documents. Writes are validated RPCs, snapshots stay immutable.
create table public.respectlogistic_accounting_company(owner_id uuid primary key default auth.uid() references auth.users(id),payload jsonb not null,modified_at timestamptz not null default clock_timestamp());
create table public.respectlogistic_accounting_documents(
 id uuid primary key,owner_id uuid not null default auth.uid() references auth.users(id),kind text not null check(kind in ('invoice','advance','upd','registry')),
 customer_id uuid not null references public.respectlogistic_customers(id),site_id uuid references public.respectlogistic_sites(id),service_name text,
 number text not null,document_date date not null,due_date date,status text not null default 'draft' check(status in ('draft','issued','sent','signed','cancelled')),
 total numeric(16,2) not null check(total>0),vat numeric(16,2) not null,paid_amount numeric(16,2) not null default 0 check(paid_amount>=0 and paid_amount<=total),
 snapshot jsonb not null,notes text not null default '',created_at timestamptz not null default clock_timestamp(),modified_at timestamptz not null default clock_timestamp(),unique(owner_id,kind,number)
);
create table public.respectlogistic_accounting_trips(document_id uuid not null references public.respectlogistic_accounting_documents(id),trip_id uuid not null references public.crm_trips(id),owner_id uuid not null references auth.users(id),kind text not null,active boolean not null default true,primary key(document_id,trip_id));
create unique index accounting_trip_once on public.respectlogistic_accounting_trips(owner_id,kind,trip_id) where active;
create table public.respectlogistic_accounting_counters(owner_id uuid not null references auth.users(id),kind text not null,scope text not null,year integer not null,value integer not null,primary key(owner_id,kind,scope,year));
create table public.respectlogistic_accounting_credits(id uuid primary key,owner_id uuid not null references auth.users(id),advance_id uuid not null references public.respectlogistic_accounting_documents(id),invoice_id uuid not null references public.respectlogistic_accounting_documents(id),amount numeric(16,2) not null check(amount>0),created_at timestamptz not null default clock_timestamp());
create table public.respectlogistic_accounting_history(id uuid primary key default gen_random_uuid(),owner_id uuid not null references auth.users(id),document_id uuid not null references public.respectlogistic_accounting_documents(id),action text not null,detail jsonb not null default '{}',created_at timestamptz not null default clock_timestamp());
do $$declare t text;begin foreach t in array array['company','documents','trips','counters','credits','history'] loop
 execute format('alter table public.respectlogistic_accounting_%I enable row level security',t);
 execute format('create policy accounting_owner on public.respectlogistic_accounting_%I for select to authenticated using(owner_id=(select auth.uid()))',t);
 execute format('revoke all on public.respectlogistic_accounting_%I from public,anon,authenticated',t);
 execute format('grant select on public.respectlogistic_accounting_%I to authenticated',t);
end loop;end$$;
create index accounting_documents_owner_date on public.respectlogistic_accounting_documents(owner_id,document_date desc);
create index accounting_trips_trip on public.respectlogistic_accounting_trips(trip_id);
create index accounting_credits_advance on public.respectlogistic_accounting_credits(advance_id);
create index accounting_credits_invoice on public.respectlogistic_accounting_credits(invoice_id);
create index accounting_history_document on public.respectlogistic_accounting_history(document_id,created_at);

create function public.respectlogistic_save_accounting_company(p_payload jsonb) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or jsonb_typeof(p_payload) is distinct from 'object' or length(p_payload::text)>15000 or coalesce(trim(p_payload->>'name'),'')='' or coalesce(p_payload->>'inn','')!~ '^([0-9]{10}|[0-9]{12})$' then raise exception 'Заполните название и ИНН своей компании';end if;
 insert into respectlogistic_accounting_company(owner_id,payload) values(auth.uid(),p_payload) on conflict(owner_id) do update set payload=excluded.payload,modified_at=clock_timestamp();
end$$;

create function public.respectlogistic_create_accounting_document(p_record jsonb,p_trip_ids uuid[] default '{}',p_versions jsonb default '{}') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;k text=p_record->>'kind';cid uuid=nullif(p_record->>'customer_id','')::uuid;sid uuid=nullif(p_record->>'site_id','')::uuid;day date=(p_record->>'document_date')::date;due date=nullif(p_record->>'due_date','')::date;item crm_trips;buyer jsonb;seller jsonb;items jsonb='[]';line jsonb;gross numeric;tax numeric;total_value numeric=0;vat_value numeric=0;n integer;prefix text;num text;service text=nullif(trim(p_record->>'service_name'),'');previous respectlogistic_accounting_documents;
begin
 if actor is null or rid is null or k is null or k not in ('invoice','advance','upd','registry') or day is null or day>current_date or coalesce(cardinality(p_trip_ids),0)>500 or length(p_record::text)>20000 then raise exception 'Проверьте вид, дату документа и число рейсов (до 500)';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-accounting',0));
 select * into previous from respectlogistic_accounting_documents where id=rid;
 if previous.id is not null then
  if previous.owner_id<>actor then raise exception 'Документ недоступен';end if;
  if previous.kind is distinct from k or previous.customer_id is distinct from cid then raise exception 'Идентификатор уже использован';end if;return rid;
 end if;
 select payload||jsonb_build_object('inn',inn) into buyer from respectlogistic_customers where id=cid and owner_id=actor;
 if buyer is null then raise exception 'Выберите заказчика этой CRM';end if;
 if sid is not null and not exists(select 1 from respectlogistic_sites where id=sid and customer_id=cid and owner_id=actor) then raise exception 'Выберите объект заказчика';end if;
 if due<day then raise exception 'Срок оплаты не может быть раньше даты документа';end if;
 select payload into seller from respectlogistic_accounting_company where owner_id=actor;
 if k='advance' then
  if coalesce(cardinality(p_trip_ids),0)<>0 or service is null then raise exception 'Для аванса укажите услугу без выбора рейсов';end if;
  gross=(p_record->>'amount')::numeric;
  if gross is null or gross<=0 or gross>1000000000000 or gross::text in ('NaN','Infinity','-Infinity') or gross<>round(gross,2) then raise exception 'Укажите положительную сумму аванса до копейки';end if;
  tax=round(gross*22/122,2);items=jsonb_build_array(jsonb_build_object('service',service,'quantity',1,'unit','усл.','price',gross,'gross',gross,'net',gross-tax,'vat',tax));total_value=gross;vat_value=tax;
 else
  if coalesce(cardinality(p_trip_ids),0)=0 or (select count(distinct x) from unnest(p_trip_ids) x)<>cardinality(p_trip_ids) then raise exception 'Выберите рейсы без повторов';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
  perform id from crm_trips where id=any(p_trip_ids) and owner_id=actor and app_scope='respectlogistic' order by id for update;
  if (select count(*) from rl_crm_trips where id=any(p_trip_ids) and customer_id=cid and deleted_at is null and status in ('sent','delivered'))<>cardinality(p_trip_ids) then raise exception 'Выберите рейсы одного заказчика в работе или выполненные. Запланированные и отменённые рейсы не закрываются';end if;
  if k='registry' and (sid is null or exists(select 1 from rl_crm_trips where id=any(p_trip_ids) and site_id is distinct from sid)) then raise exception 'Реестр создаётся отдельно по одному объекту';end if;
  if sid is not null and exists(select 1 from rl_crm_trips where id=any(p_trip_ids) and site_id is distinct from sid) then raise exception 'Выбранные рейсы относятся к другому объекту';end if;
  if exists(select 1 from respectlogistic_accounting_trips where trip_id=any(p_trip_ids) and owner_id=actor and kind=k and active) then raise exception 'Часть рейсов уже включена в такой документ. Отмените ошибочный черновик или исключите эти рейсы';end if;
  for item in select * from rl_crm_trips where id=any(p_trip_ids) order by trip_date,id loop
   if item.modified_at is distinct from (p_versions->>item.id::text)::timestamptz then raise exception 'Рейс % изменился. Обновите список',item.trip_number;end if;
   if item.trip_date is null or item.trip_date>day or item.volume<=0 or item.unit_price<=0 or item.volume::text in ('NaN','Infinity','-Infinity') or item.unit_price::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте дату, положительный объём и цену рейса %',item.trip_number;end if;
   if service is not null and trim(coalesce(item.service_name,''))<>service then raise exception 'В выборке есть другая услуга';end if;
   gross=round(item.volume*item.unit_price,2);tax=round(gross*22/122,2);total_value=total_value+gross;vat_value=vat_value+tax;
   select jsonb_build_object('trip_id',item.id,'trip_number',item.trip_number,'trip_date',item.trip_date,'modified_at',item.modified_at,'site_id',item.site_id,'object',s.payload->>'name','plate',v.plate,'service',coalesce(item.service_name,'Услуга'),'quantity',item.volume,'unit',item.unit,'price',item.unit_price,'gross',gross,'net',gross-tax,'vat',tax,'loading_address',item.loading_address,'unloading_address',item.unloading_address,'contract',c.number) into line from respectlogistic_sites s join rl_crm_vehicles v on v.id=item.vehicle_id left join respectlogistic_contracts c on c.id=s.contract_id where s.id=item.site_id and s.owner_id=actor;
   if line is null then raise exception 'Объект или техника рейса недоступны';end if;items=items||jsonb_build_array(line);
  end loop;
 end if;
 if total_value<=0 or total_value>1000000000000 then raise exception 'Некорректная итоговая сумма';end if;
 insert into respectlogistic_accounting_counters(owner_id,kind,scope,year,value) values(actor,k,case when k='registry' then sid::text else '' end,extract(year from day)::integer,1) on conflict(owner_id,kind,scope,year) do update set value=respectlogistic_accounting_counters.value+1 returning value into n;
 prefix=case k when 'invoice' then 'СЧ' when 'advance' then 'АВ' when 'upd' then 'УПД' else 'РЕЕСТР' end;num=prefix||'-'||n||'/'||extract(year from day)::integer;
 if k='registry' then num=num||'-'||substr(replace(sid::text,'-',''),1,8);end if;
 insert into respectlogistic_accounting_documents(id,owner_id,kind,customer_id,site_id,service_name,number,document_date,due_date,total,vat,snapshot,notes) values(rid,actor,k,cid,sid,service,num,day,due,total_value,vat_value,jsonb_build_object('seller',coalesce(seller,'{}'),'customer',buyer,'items',items,'vat_rate',22,'prices_include_vat',true),left(coalesce(p_record->>'notes',''),4000));
 insert into respectlogistic_accounting_trips(document_id,trip_id,owner_id,kind) select rid,x,actor,k from unnest(p_trip_ids) x;
 insert into respectlogistic_accounting_history(owner_id,document_id,action) values(actor,rid,'created');return rid;
end$$;

create function public.respectlogistic_accounting_action(p_id uuid,p_action text,p_expected_modified_at timestamptz,p_payload jsonb default '{}') returns void language plpgsql security definer set search_path=public,pg_temp as $$
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
  if coalesce(seller->>'name','')='' or coalesce(seller->>'inn','')='' or coalesce(seller->>'legalAddress','')='' or coalesce(buyer->>'legalAddress','')='' then raise exception 'Для формирования заполните название, ИНН и юридический адрес своей компании и заказчика';end if;
  if doc.kind in ('invoice','advance') and (coalesce(seller->>'account','')!~ '^[0-9]{20}$' or coalesce(seller->>'bik','')!~ '^[0-9]{9}$' or coalesce(seller->>'bank','')='') then raise exception 'Заполните банк, БИК и расчётный счёт своей компании';end if;
  perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
  perform t.id from crm_trips t join respectlogistic_accounting_trips l on l.trip_id=t.id where l.document_id=doc.id order by t.id for update of t;
  for line in select * from jsonb_array_elements(doc.snapshot->'items') loop
   if line->>'trip_id' is null then continue;end if;
   select * into item from rl_crm_trips where id=(line->>'trip_id')::uuid and deleted_at is null;
   if item.id is null or item.status not in ('sent','delivered') or item.customer_id is distinct from doc.customer_id or item.site_id is distinct from (line->>'site_id')::uuid or item.trip_number is distinct from line->>'trip_number' or item.trip_date is distinct from (line->>'trip_date')::date or item.volume is distinct from (line->>'quantity')::numeric or item.unit_price is distinct from (line->>'price')::numeric or item.unit is distinct from line->>'unit' or coalesce(item.service_name,'Услуга') is distinct from line->>'service' or (select plate from rl_crm_vehicles where id=item.vehicle_id) is distinct from line->>'plate' then raise exception 'Данные рейса изменились. Отмените черновик и сформируйте новый';end if;
   if doc.kind in ('upd','registry') then
    if (p_payload->>'complete_trips')::boolean is distinct from true then raise exception 'Подтвердите выполнение услуг и завершение рейсов';end if;
    if item.trip_date>current_date or (item.carrier_id is null and item.driver_id is null) then raise exception 'Для завершения рейса проверьте дату и водителя';end if;
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
  if exists(select 1 from respectlogistic_accounting_credits where id=credit_id) then raise exception 'Зачёт уже зарегистрирован. Обновите данные';end if;
  if value is null or value<=0 or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) or value>doc.total-doc.paid_amount-credited or value>advance.paid_amount-(select coalesce(sum(amount),0) from respectlogistic_accounting_credits where advance_id=advance.id) then raise exception 'Сумма превышает доступный аванс или остаток счёта';end if;
  insert into respectlogistic_accounting_credits(id,owner_id,advance_id,invoice_id,amount) values(credit_id,actor,advance.id,doc.id,value);
  update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=advance.id;
 else raise exception 'Неизвестное действие';end if;
 update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=doc.id;
 insert into respectlogistic_accounting_history(owner_id,document_id,action,detail) values(actor,doc.id,p_action,jsonb_build_object('before_status',doc.status,'before_paid',doc.paid_amount,'payload',p_payload));
end$$;

create function public.respectlogistic_read_accounting() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select crm_read_trip_workspace()||jsonb_build_object(
 'company',coalesce((select payload from respectlogistic_accounting_company where owner_id=auth.uid()),'{}'),
 'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from respectlogistic_accounting_documents d where d.owner_id=auth.uid()),'[]'),
 'links',coalesce((select jsonb_agg(to_jsonb(l)) from respectlogistic_accounting_trips l where l.owner_id=auth.uid()),'[]'),
 'credits',coalesce((select jsonb_agg(to_jsonb(c)) from respectlogistic_accounting_credits c where c.owner_id=auth.uid()),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from respectlogistic_accounting_history h where h.owner_id=auth.uid()),'[]'))
$$;

create function public.respectlogistic_guard_accounted_trip() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if old.app_scope is distinct from 'respectlogistic' then if tg_op='DELETE' then return old;else return new;end if;end if;
 if exists(select 1 from respectlogistic_accounting_trips l join respectlogistic_accounting_documents d on d.id=l.document_id where l.trip_id=old.id and l.active and d.status in ('issued','sent','signed')) then
  if tg_op='DELETE' then raise exception 'Рейс связан с бухгалтерским документом';end if;
  if row(new.customer_id,new.site_id,new.vehicle_id,new.driver_id,new.carrier_id,new.trip_number,new.trip_date,new.volume,new.unit,new.unit_price,new.service_name,new.loading_address,new.unloading_address,new.deleted_at) is distinct from row(old.customer_id,old.site_id,old.vehicle_id,old.driver_id,old.carrier_id,old.trip_number,old.trip_date,old.volume,old.unit,old.unit_price,old.service_name,old.loading_address,old.unloading_address,old.deleted_at) or (old.status='delivered' and new.status<>'delivered') or new.status in ('assigned','cancelled') then raise exception 'Рейс включён в бухгалтерский документ. Требуется отмена или корректировка документа';end if;
 end if;if tg_op='DELETE' then return old;end if;return new;
end$$;
create trigger respectlogistic_accounting_trip_guard before update or delete on public.crm_trips for each row execute function public.respectlogistic_guard_accounted_trip();
revoke all on function public.respectlogistic_save_accounting_company(jsonb),public.respectlogistic_create_accounting_document(jsonb,uuid[],jsonb),public.respectlogistic_accounting_action(uuid,text,timestamptz,jsonb),public.respectlogistic_read_accounting(),public.respectlogistic_guard_accounted_trip() from public,anon,authenticated;
grant execute on function public.respectlogistic_save_accounting_company(jsonb),public.respectlogistic_create_accounting_document(jsonb,uuid[],jsonb),public.respectlogistic_accounting_action(uuid,text,timestamptz,jsonb),public.respectlogistic_read_accounting() to authenticated;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION public.crm_read_trip_workspace()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
select jsonb_build_object(
 'accounting_documents',coalesce((select jsonb_agg(to_jsonb(ad)||jsonb_build_object('trip_ids',(select jsonb_agg(al.trip_id) from respectlogistic_accounting_trips al where al.document_id=ad.id and al.active))) from respectlogistic_accounting_documents ad where ad.owner_id=auth.uid() and ad.status in ('issued','sent','signed')),'[]'),
 'trips',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'loading_address',coalesce(t.loading_address,s.loading_address,''),'unloading_address',coalesce(t.unloading_address,s.unloading_address,''),
 'locked',exists(select 1 from respectlogistic_accounting_trips al join respectlogistic_accounting_documents ad on ad.id=al.document_id where al.trip_id=t.id and al.active and ad.status in ('issued','sent','signed')) or exists(select 1 from crm_invoice_lines x where x.trip_id=t.id) or exists(select 1 from rl_crm_payroll_accruals a where a.trip_id=t.id and (exists(select 1 from rl_crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from rl_crm_payroll_deductions d where d.accrual_id=a.id))))
 order by t.trip_date desc nulls last,t.created_at desc,t.id) from rl_crm_trips t left join rl_crm_sites s on s.id=t.site_id where t.owner_id=(select auth.uid()) and t.deleted_at is null),'[]'),
 'customers',coalesce((select jsonb_agg(x.obj order by x.obj->>'name') from (
 select jsonb_build_object('id',c.id,'name',c.payload->>'name') as obj from respectlogistic_customers c where c.owner_id=(select auth.uid())
 union all select jsonb_build_object('id',c.id,'name',c.name) from rl_crm_customers c where c.owner_id=(select auth.uid()) and c.deleted_at is null and not c.is_archived and not exists(select 1 from respectlogistic_customers r where r.id=c.id and r.owner_id=(select auth.uid()))
 ) x),'[]'),
 'sites',coalesce((select jsonb_agg(x.obj order by x.obj->>'name') from (
 select jsonb_build_object('id',s.id,'customer_id',s.customer_id,'name',s.payload->>'name','loading_address',coalesce(s.payload->>'loadingAddress',''),'unloading_address',coalesce(s.payload->>'address',''),'route_km',s.payload->>'routeKm','service_name',v.name,'unit',v.unit,'unit_price',v.price_kopecks/100.0,'contract_number',c.number) as obj
 from respectlogistic_sites s join respectlogistic_services v on v.id=s.service_id join respectlogistic_contracts c on c.id=s.contract_id where s.owner_id=(select auth.uid())
 union all select jsonb_build_object('id',s.id,'customer_id',s.customer_id,'name',s.name,'loading_address',s.loading_address,'unloading_address',s.unloading_address,'route_km',s.route_km,'service_name',sp.service_name,'unit',sp.unit,'unit_price',sp.rate,'contract_number',c.contract_number)
 from rl_crm_sites s left join crm_specifications sp on sp.id=s.specification_id left join crm_contracts c on c.id=s.contract_id where s.owner_id=(select auth.uid()) and s.deleted_at is null and not exists(select 1 from respectlogistic_sites r where r.id=s.id and r.owner_id=(select auth.uid()))
 ) x),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'carrier_id',v.carrier_id,'is_subcontractor_vehicle',v.is_subcontractor_vehicle,'assigned_driver_id',v.assigned_driver_id,'archived_at',v.archived_at) order by v.plate) from rl_crm_vehicles v where v.owner_id=(select auth.uid())),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'carrier_id',d.carrier_id,'job_status',d.job_status,'archived_at',d.archived_at) order by d.full_name) from rl_crm_drivers d where d.owner_id=(select auth.uid())),'[]'),
 'carriers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'is_blocked',c.is_blocked) order by c.name) from rl_crm_carriers c where c.owner_id=(select auth.uid())),'[]')
)
$function$;
