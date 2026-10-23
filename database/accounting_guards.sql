create or replace function public.respectlogistic_accounting_action(p_id uuid,p_action text,p_expected_modified_at timestamptz,p_payload jsonb default '{}') returns void language plpgsql security definer set search_path=public,pg_temp as $$
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
   if item.id is null or item.status not in ('sent','delivered') or item.customer_id is distinct from doc.customer_id or item.site_id is distinct from (line->>'site_id')::uuid or item.trip_number is distinct from line->>'trip_number' or item.trip_date is distinct from (line->>'trip_date')::date or item.volume is distinct from (line->>'quantity')::numeric or item.unit_price is distinct from (line->>'price')::numeric or item.loading_address is distinct from line->>'loading_address' or item.unloading_address is distinct from line->>'unloading_address' or item.unit is distinct from line->>'unit' or coalesce(item.service_name,'Услуга') is distinct from line->>'service' or (select plate from rl_crm_vehicles where id=item.vehicle_id) is distinct from line->>'plate' then raise exception 'Данные рейса изменились. Отмените черновик и сформируйте новый';end if;
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
  if advance.service_name is not null and exists(select 1 from jsonb_array_elements(doc.snapshot->'items') i where trim(coalesce(i->>'service',''))<>trim(advance.service_name)) then raise exception 'Услуга аванса отличается от услуг счёта';end if;
  if exists(select 1 from respectlogistic_accounting_credits where id=credit_id) then raise exception 'Зачёт уже зарегистрирован. Обновите данные';end if;
  if value is null or value<=0 or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) or value>doc.total-doc.paid_amount-credited or value>advance.paid_amount-(select coalesce(sum(amount),0) from respectlogistic_accounting_credits where advance_id=advance.id) then raise exception 'Сумма превышает доступный аванс или остаток счёта';end if;
  insert into respectlogistic_accounting_credits(id,owner_id,advance_id,invoice_id,amount) values(credit_id,actor,advance.id,doc.id,value);
  update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=advance.id;
 else raise exception 'Неизвестное действие';end if;
 update respectlogistic_accounting_documents set modified_at=clock_timestamp() where id=doc.id;
 insert into respectlogistic_accounting_history(owner_id,document_id,action,detail) values(actor,doc.id,p_action,jsonb_build_object('before_status',doc.status,'before_paid',doc.paid_amount,'payload',p_payload));
end$$;


create or replace function public.respectlogistic_guard_accounted_trip() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if old.app_scope is distinct from 'respectlogistic' then if tg_op='DELETE' then return old;else return new;end if;end if;
 if exists(select 1 from respectlogistic_accounting_trips l join respectlogistic_accounting_documents d on d.id=l.document_id where l.trip_id=old.id and l.active and d.status in ('issued','sent','signed')) then
  if tg_op='DELETE' then raise exception 'Рейс связан с бухгалтерским документом';end if;
  if row(new.app_scope,new.owner_id,new.customer_id,new.site_id,new.vehicle_id,new.driver_id,new.carrier_id,new.trip_number,new.trip_date,new.volume,new.unit,new.unit_price,new.service_name,new.loading_address,new.unloading_address,new.deleted_at) is distinct from row(old.app_scope,old.owner_id,old.customer_id,old.site_id,old.vehicle_id,old.driver_id,old.carrier_id,old.trip_number,old.trip_date,old.volume,old.unit,old.unit_price,old.service_name,old.loading_address,old.unloading_address,old.deleted_at) or (old.status='delivered' and new.status<>'delivered') or new.status in ('assigned','cancelled') then raise exception 'Рейс включён в бухгалтерский документ. Требуется отмена или корректировка документа';end if;
 end if;if tg_op='DELETE' then return old;end if;return new;
end$$;
