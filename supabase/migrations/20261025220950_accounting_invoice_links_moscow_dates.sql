-- Keep existing document/trip uniqueness, numbering, owner checks and financial locks.
alter table public.respectlogistic_accounting_documents add column invoice_id uuid references public.respectlogistic_accounting_documents(id);
create index accounting_documents_invoice on public.respectlogistic_accounting_documents(invoice_id);
create or replace function public.respectlogistic_create_accounting_document(p_record jsonb,p_trip_ids uuid[] default '{}',p_versions jsonb default '{}') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;k text=p_record->>'kind';cid uuid=nullif(p_record->>'customer_id','')::uuid;sid uuid=nullif(p_record->>'site_id','')::uuid;day date=(p_record->>'document_date')::date;due date=nullif(p_record->>'due_date','')::date;item crm_trips;buyer jsonb;seller jsonb;items jsonb='[]';line jsonb;gross numeric;tax numeric;total_value numeric=0;vat_value numeric=0;n integer;prefix text;num text;service text=nullif(trim(p_record->>'service_name'),'');previous respectlogistic_accounting_documents;parent respectlogistic_accounting_documents;parent_id uuid=nullif(p_record->>'invoice_id','')::uuid;
begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 if rid is null or k is null or k not in ('invoice','advance','upd','registry') or length(p_record::text)>20000 then raise exception 'Проверьте вид документа';end if;
 if day is null or day>(clock_timestamp() at time zone 'Europe/Moscow')::date then raise exception 'Дата документа не может быть позже сегодняшней даты по Москве';end if;
 if coalesce(cardinality(p_trip_ids),0)>500 then raise exception 'Выбрано более 500 рейсов. Разделите выборку на несколько счетов';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-accounting',0));
 select * into previous from respectlogistic_accounting_documents where id=rid;
 if previous.id is not null then
  if previous.owner_id<>actor then raise exception 'Документ недоступен';end if;
  if previous.invoice_id is distinct from parent_id or previous.kind is distinct from k or previous.customer_id is distinct from cid then raise exception 'Идентификатор уже использован';end if;return rid;
 end if;
 if parent_id is not null then
  select * into parent from respectlogistic_accounting_documents where id=parent_id and owner_id=actor for update;
  if parent.id is null or parent.kind<>'invoice' or parent.status='cancelled' or parent.customer_id is distinct from cid or k not in ('upd','registry') then raise exception 'Выберите действующий счёт этого заказчика для УПД или реестра';end if;
  if exists(select 1 from unnest(p_trip_ids) x where not exists(select 1 from respectlogistic_accounting_trips l where l.document_id=parent.id and l.trip_id=x and l.owner_id=actor and l.active)) then raise exception 'УПД и реестр должны включать рейсы выбранного счёта';end if;
  if k='upd' and (select count(*) from respectlogistic_accounting_trips where document_id=parent.id and owner_id=actor and active)<>coalesce(cardinality(p_trip_ids),0) then raise exception 'УПД должен включать все рейсы счёта';end if;
  if k='registry' and exists(select 1 from respectlogistic_accounting_trips l join rl_crm_trips t on t.id=l.trip_id where l.document_id=parent.id and l.owner_id=actor and l.active and t.site_id=sid and not (t.id=any(p_trip_ids))) then raise exception 'Выберите все рейсы объекта в этом счёте';end if;
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
   if parent_id is not null and not exists(select 1 from jsonb_array_elements(parent.snapshot->'items') source_line(value) where source_line.value->>'trip_id'=item.id::text and (source_line.value->>'quantity')::numeric=item.volume and (source_line.value->>'price')::numeric=item.unit_price and source_line.value->>'unit'=item.unit and source_line.value->>'service'=item.service_name and source_line.value->>'site_id'=item.site_id::text) then raise exception 'Рейс изменился после создания счёта. Сначала исправьте счёт';end if;
   gross=round(item.volume*item.unit_price,2);tax=round(gross*22/122,2);total_value=total_value+gross;vat_value=vat_value+tax;
   select jsonb_build_object('trip_id',item.id,'trip_number',item.trip_number,'trip_date',item.trip_date,'modified_at',item.modified_at,'site_id',item.site_id,'object',s.payload->>'name','plate',v.plate,'service',coalesce(item.service_name,'Услуга'),'quantity',item.volume,'unit',item.unit,'price',item.unit_price,'gross',gross,'net',gross-tax,'vat',tax,'loading_address',item.loading_address,'unloading_address',item.unloading_address,'contract',c.number) into line from respectlogistic_sites s join rl_crm_vehicles v on v.id=item.vehicle_id left join respectlogistic_contracts c on c.id=s.contract_id where s.id=item.site_id and s.owner_id=actor;
   if line is null then raise exception 'Объект или техника рейса недоступны';end if;items=items||jsonb_build_array(line);
  end loop;
 end if;
 if total_value<=0 or total_value>1000000000000 then raise exception 'Некорректная итоговая сумма';end if;
 insert into respectlogistic_accounting_counters(owner_id,kind,scope,year,value) values(actor,k,case when k='registry' then sid::text else '' end,extract(year from day)::integer,1) on conflict(owner_id,kind,scope,year) do update set value=respectlogistic_accounting_counters.value+1 returning value into n;
 prefix=case k when 'invoice' then 'СЧ' when 'advance' then 'АВ' when 'upd' then 'УПД' else 'РЕЕСТР' end;num=prefix||'-'||n||'/'||extract(year from day)::integer;
 if k='registry' then num=num||'-'||substr(replace(sid::text,'-',''),1,8);end if;
 insert into respectlogistic_accounting_documents(id,owner_id,kind,customer_id,site_id,service_name,number,document_date,due_date,total,vat,snapshot,notes,invoice_id) values(rid,actor,k,cid,sid,service,num,day,due,total_value,vat_value,jsonb_build_object('seller',coalesce(seller,'{}'),'customer',buyer,'items',items,'vat_rate',22,'prices_include_vat',true,'invoice_number',parent.number,'invoice_id',parent.id),left(coalesce(p_record->>'notes',''),4000),parent_id);
 insert into respectlogistic_accounting_trips(document_id,trip_id,owner_id,kind) select rid,x,actor,k from unnest(p_trip_ids) x;
 insert into respectlogistic_accounting_history(owner_id,document_id,action) values(actor,rid,'created');return rid;
end$$;

notify pgrst,'reload schema';

-- A source invoice cannot be cancelled while closing documents still refer to it.
create function public.respectlogistic_guard_invoice_children() returns trigger language plpgsql set search_path=public,pg_temp as $$begin
 if new.status='cancelled' and old.status is distinct from new.status and exists(select 1 from respectlogistic_accounting_documents d where d.invoice_id=new.id and d.owner_id=new.owner_id and d.status<>'cancelled') then raise exception 'Сначала отмените связанные УПД и реестры';end if;return new;
end$$;
revoke all on function public.respectlogistic_guard_invoice_children() from public,anon,authenticated;
create trigger respectlogistic_invoice_children before update of status on public.respectlogistic_accounting_documents for each row execute function public.respectlogistic_guard_invoice_children();

revoke all on function public.respectlogistic_create_accounting_document(jsonb,uuid[],jsonb) from public,anon,authenticated;
grant execute on function public.respectlogistic_create_accounting_document(jsonb,uuid[],jsonb) to authenticated;
