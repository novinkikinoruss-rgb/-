alter table public.respectlogistic_invoice_vat add column modified_at timestamptz not null default clock_timestamp();
create or replace function public.respectlogistic_save_profit_expense(p_expense jsonb,p_expected_modified_at timestamptz default null) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();eid uuid=(p_expense->>'id')::uuid;previous respectlogistic_profit_expenses;
 cid uuid=nullif(p_expense->>'customer_id','')::uuid;sid uuid=nullif(p_expense->>'site_id','')::uuid;tid uuid=nullif(p_expense->>'trip_id','')::uuid;vid uuid=nullif(p_expense->>'vehicle_id','')::uuid;iid uuid=nullif(p_expense->>'invoice_id','')::uuid;
 day date=(p_expense->>'expense_date')::date;kind text=p_expense->>'category';value numeric=(p_expense->>'amount')::numeric;paid numeric=coalesce(nullif(p_expense->>'paid_amount','')::numeric,0);service text=nullif(trim(p_expense->>'service_name'),'');comment text=coalesce(p_expense->>'notes','');
 vrate numeric=nullif(p_expense->>'vat_rate','')::numeric;vconfirmed boolean=coalesce((p_expense->>'input_vat_confirmed')::boolean,false);profile public.respectlogistic_invoice_vat;
 trip public.crm_trips;site public.respectlogistic_sites;invoice public.crm_counterparty_invoices;allocated numeric;
begin
 if actor is null or eid is null or jsonb_typeof(p_expense) is distinct from 'object' or length(p_expense::text)>20000 then raise exception 'Некорректный расход';end if;
 if day is null or day>current_date or kind not in ('contractor','fuel','maintenance','leasing','insurance','tolls','tax','other') or kind is null then raise exception 'Проверьте дату и категорию расхода';end if;
 if value is null or value<=0 or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) or value>99999999999999.99 or paid<0 or paid>value or paid<>round(paid,2) or paid::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте сумму расхода и оплаты';end if;
 if length(comment)>4000 or length(coalesce(service,''))>500 then raise exception 'Примечание или услуга слишком длинные';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-profit',0));
 select * into previous from respectlogistic_profit_expenses where id=eid for update;
 if previous.id is not null then
  if previous.owner_id<>actor or previous.deleted_at is not null then raise exception 'Расход недоступен';end if;
  if p_expected_modified_at is null or p_expected_modified_at is distinct from previous.modified_at then raise exception 'Расход изменён в другой вкладке. Обновите список';end if;
 end if;
 if previous.id is not null then
  if not (p_expense ? 'vat_rate') then vrate=previous.vat_rate;end if;
  if not (p_expense ? 'input_vat_confirmed') then vconfirmed=previous.input_vat_confirmed;end if;
 end if;
 if vrate is not null and (vrate<0 or vrate>100 or vrate::text in ('NaN','Infinity','-Infinity')) then raise exception 'Проверьте ставку входного НДС';end if;
 if vconfirmed and vrate is null then raise exception 'Для подтверждённого вычета укажите ставку входного НДС';end if;
 if kind='tax' and (coalesce(vrate,0)>0 or vconfirmed) then raise exception 'На оплату налогов входной НДС не начисляется';end if;
 if tid is not null then
  select * into trip from rl_crm_trips where id=tid and deleted_at is null;
  if trip.id is null or trip.status='cancelled' then raise exception 'Рейс недоступен или отменён';end if;
  if vid is not null and vid is distinct from trip.vehicle_id then raise exception 'Выберите технику этого рейса';end if;
  cid=trip.customer_id;sid=trip.site_id;service=trip.service_name;vid=trip.vehicle_id;
 end if;
 if sid is not null then
  select * into site from respectlogistic_sites where id=sid and owner_id=actor;
  if site.id is null or (cid is not null and cid<>site.customer_id) then raise exception 'Объект относится к другому заказчику или недоступен';end if;
  cid=site.customer_id;
  if service is not null and tid is null and not exists(select 1 from respectlogistic_services s where s.id=site.service_id and s.owner_id=actor and s.name=service) then raise exception 'Выберите услугу этого объекта';end if;
 end if;
 if cid is not null and not exists(select 1 from respectlogistic_customers where id=cid and owner_id=actor) then raise exception 'Заказчик недоступен';end if;
 if vid is not null and not exists(select 1 from rl_crm_vehicles where id=vid) then raise exception 'Техника относится к другой CRM или недоступна';end if;
 if kind='contractor' then
  if iid is null or paid<>0 then raise exception 'Выберите счёт исполнителя. Его оплаты подтягиваются из раздела «Контрагенты»';end if;
  select * into invoice from rl_crm_counterparty_invoices where id=iid and deleted_at is null for update;
  if invoice.id is null then raise exception 'Счёт исполнителя недоступен';end if;
  if tid is not null and (trip.carrier_id is null or trip.carrier_id<>invoice.counterparty_id) then raise exception 'Счёт и рейс должны относиться к одному исполнителю';end if;
  select coalesce(sum(amount),0) into allocated from respectlogistic_profit_expenses where invoice_id=iid and owner_id=actor and deleted_at is null and id<>eid;
  if allocated+value>invoice.amount then raise exception 'Распределение превышает сумму счёта. Осталось распределить %',invoice.amount-allocated;end if;
  if p_expense ? 'vat_rate' or p_expense ? 'input_vat_confirmed' then
   select * into profile from respectlogistic_invoice_vat where invoice_id=iid and owner_id=actor for update;
   if profile.invoice_id is not null and (profile.vat_rate is distinct from vrate or profile.input_vat_confirmed is distinct from vconfirmed) and profile.modified_at is distinct from nullif(p_expense->>'invoice_vat_modified_at','')::timestamptz then raise exception 'Данные НДС по счёту изменены в другой вкладке. Обновите отчёт';end if;
   insert into respectlogistic_invoice_vat(invoice_id,owner_id,vat_rate,input_vat_confirmed) values(iid,actor,vrate,vconfirmed) on conflict(invoice_id) do update set vat_rate=excluded.vat_rate,input_vat_confirmed=excluded.input_vat_confirmed,modified_at=clock_timestamp();
  end if;
 elsif iid is not null then raise exception 'Счёт исполнителя используется только для расходов на контрагентов';end if;
 if previous.id is null then
  insert into respectlogistic_profit_expenses(id,owner_id,expense_date,category,amount,paid_amount,customer_id,site_id,service_name,trip_id,vehicle_id,invoice_id,notes,vat_rate,input_vat_confirmed)
  values(eid,actor,day,kind,value,paid,cid,sid,service,tid,vid,iid,comment,case when kind='contractor' then null else vrate end,case when kind='contractor' then false else vconfirmed end);
 else
  update respectlogistic_profit_expenses set expense_date=day,category=kind,amount=value,paid_amount=paid,customer_id=cid,site_id=sid,service_name=service,trip_id=tid,vehicle_id=vid,invoice_id=iid,notes=comment,vat_rate=case when kind='contractor' then null else vrate end,input_vat_confirmed=case when kind='contractor' then false else vconfirmed end,modified_at=clock_timestamp() where id=eid and owner_id=actor;
 end if;
 return eid;
end $$;

notify pgrst,'reload schema';
