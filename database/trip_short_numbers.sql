-- Short app-scoped trip numbers. Existing references stay unchanged; deleted numbers remain reserved.
create or replace function public.crm_save_trip(p_trip jsonb,p_expected_modified_at timestamptz default null)
returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 actor uuid=auth.uid();tid uuid=(p_trip->>'id')::uuid;old_trip public.crm_trips;
 cid uuid=(p_trip->>'customer_id')::uuid;sid uuid=(p_trip->>'site_id')::uuid;vid uuid=(p_trip->>'vehicle_id')::uuid;did uuid=nullif(p_trip->>'driver_id','')::uuid;carrier uuid;
 r_customer public.respectlogistic_customers;r_site public.respectlogistic_sites;r_service public.respectlogistic_services;
 s public.crm_sites;v public.crm_vehicles;d public.crm_drivers;rows_changed integer;n integer;number_value text=trim(coalesce(p_trip->>'trip_number',''));date_value date=(p_trip->>'trip_date')::date;
 volume_value numeric=(p_trip->>'volume')::numeric;price_value numeric=coalesce(nullif(p_trip->>'unit_price','')::numeric,0);status_value text=coalesce(p_trip->>'status','assigned');origin_value text=trim(coalesce(p_trip->>'loading_address',''));destination_value text=trim(coalesce(p_trip->>'unloading_address',''));
begin
 if actor is null or tid is null or cid is null or sid is null or vid is null or date_value is null then raise exception 'Заполните заказчика, объект, дату и технику';end if;
 if jsonb_typeof(p_trip) is distinct from 'object' or length(p_trip::text)>30000 then raise exception 'Некорректный запрос';end if;
 if volume_value is null or volume_value<0 or volume_value::text in ('NaN','Infinity','-Infinity') or price_value<0 or price_value::text in ('NaN','Infinity','-Infinity') then raise exception 'Объём и цена должны быть неотрицательными числами';end if;
 if status_value not in ('assigned','sent','delivered','cancelled') then raise exception 'Выберите статус рейса';end if;
 if status_value='delivered' and date_value>current_date then raise exception 'Выполненный рейс не может иметь будущую дату';end if;
 if origin_value='' or destination_value='' or greatest(length(origin_value),length(destination_value))>4000 then raise exception 'Заполните адреса погрузки и выгрузки';end if;
 
 if exists(select 1 from crm_trips where id=tid and (owner_id<>actor or app_scope is distinct from 'respectlogistic')) then raise exception 'Рейс относится к другой CRM';end if;
 if not exists(select 1 from respectlogistic_customers where id=cid and owner_id=actor) or not exists(select 1 from respectlogistic_sites where id=sid and owner_id=actor) then raise exception 'Выберите заказчика и объект этой CRM';end if;
 if not exists(select 1 from rl_crm_vehicles where id=vid) or (did is not null and not exists(select 1 from rl_crm_drivers where id=did)) then raise exception 'Техника или водитель относятся к другой CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
 select * into old_trip from crm_trips where id=tid and owner_id=actor for update;
 if old_trip.id is not null then
  if old_trip.deleted_at is not null then raise exception 'Рейс удалён. Обновите список';end if;
  if p_expected_modified_at is null or old_trip.modified_at is distinct from p_expected_modified_at then raise exception 'Рейс изменён в другой вкладке. Обновите список перед редактированием';end if;
  if exists(select 1 from crm_invoice_lines x where x.trip_id=tid) or exists(select 1 from crm_payroll_accruals a where a.trip_id=tid and (exists(select 1 from crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from crm_payroll_deductions f where f.accrual_id=a.id))) then raise exception 'Рейс включён в счёт или по нему есть выплаты/удержания. Нужна бухгалтерская корректировка';end if;
 end if;
 -- Reuse the customer/site UUIDs already visible in the customer workspace.
 select * into r_customer from respectlogistic_customers where id=cid and owner_id=actor;
 if r_customer.id is not null then
  insert into crm_customers(app_scope,id,owner_id,name,inn,kpp,ogrn,phone,email,legal_address)
  values('respectlogistic',cid,actor,r_customer.payload->>'name',r_customer.inn,r_customer.payload->>'kpp',r_customer.payload->>'ogrn',r_customer.payload->>'phone',r_customer.payload->>'email',r_customer.payload->>'legalAddress')
  on conflict(id) do update set app_scope='respectlogistic',name=excluded.name,inn=excluded.inn,kpp=excluded.kpp,ogrn=excluded.ogrn,phone=excluded.phone,email=excluded.email,legal_address=excluded.legal_address where crm_customers.owner_id=actor and crm_customers.deleted_at is null and not crm_customers.is_archived;
  get diagnostics rows_changed=row_count;if rows_changed<>1 then raise exception 'Заказчик в архиве или недоступен';end if;
 elsif not exists(select 1 from crm_customers where id=cid and owner_id=actor and deleted_at is null and not is_archived) then raise exception 'Заказчик недоступен';end if;
 select * into r_site from respectlogistic_sites where id=sid and owner_id=actor;
 if r_site.id is not null then
  if r_site.customer_id<>cid then raise exception 'Объект относится к другому заказчику';end if;
  select * into r_service from respectlogistic_services where id=r_site.service_id and owner_id=actor;
  insert into crm_sites(app_scope,id,owner_id,customer_id,name,loading_address,unloading_address,route_km)
  values('respectlogistic',sid,actor,cid,coalesce(r_site.payload->>'name','Объект'),coalesce(r_site.payload->>'loadingAddress',''),coalesce(r_site.payload->>'address',''),nullif(r_site.payload->>'routeKm','')::numeric)
  on conflict(id) do update set app_scope='respectlogistic',customer_id=excluded.customer_id,name=excluded.name,loading_address=excluded.loading_address,unloading_address=excluded.unloading_address,route_km=excluded.route_km where crm_sites.owner_id=actor and crm_sites.deleted_at is null;
  get diagnostics rows_changed=row_count;if rows_changed<>1 then raise exception 'Объект в архиве или недоступен';end if;
 end if;
 select * into s from crm_sites where id=sid and owner_id=actor and deleted_at is null;
 if s.id is null or s.customer_id<>cid then raise exception 'Выберите объект этого заказчика';end if;
 select * into v from crm_vehicles where id=vid and owner_id=actor;
 if v.id is null or (v.archived_at is not null and vid is distinct from old_trip.vehicle_id) then raise exception 'Техника недоступна или в архиве';end if;
 if p_trip ? 'vehicle_source' and (p_trip->>'vehicle_source' not in ('own','contractor') or ((p_trip->>'vehicle_source'='contractor') is distinct from (v.carrier_id is not null or v.is_subcontractor_vehicle))) then raise exception 'Выберите машину для выбранного вида исполнителя';end if;
 carrier=coalesce(v.carrier_id,case when v.is_subcontractor_vehicle then nullif(p_trip->>'carrier_id','')::uuid end);
 if (v.is_subcontractor_vehicle or v.carrier_id is not null) and carrier is null then raise exception 'Укажите контрагента для выбранной техники';end if;
 if carrier is not null and not exists(select 1 from crm_carriers where id=carrier and owner_id=actor and app_scope='respectlogistic' and not is_blocked) then raise exception 'Контрагент недоступен или заблокирован';end if;
 if did is not null then
  select * into d from crm_drivers where id=did and owner_id=actor;
  if d.id is null or d.carrier_id is distinct from carrier then raise exception 'Выберите водителя выбранного исполнителя';end if;
  if d.archived_at is not null and did is distinct from old_trip.driver_id then raise exception 'Водитель в архиве';end if;
 end if;
 if status_value='delivered' and carrier is null and did is null then raise exception 'Для выполненного рейса собственной техники укажите водителя';end if;
 if number_value='' then
  if old_trip.id is not null then number_value=old_trip.trip_number;
  else
   select candidate::text into number_value from generate_series(1,1000) candidate
   where not exists(select 1 from crm_trips t where t.owner_id=actor and t.app_scope='respectlogistic' and t.trip_number=candidate::text)
   order by candidate limit 1;
   if number_value is null then raise exception 'Номера рейсов от 1 до 1000 уже заняты';end if;
  end if;
 end if;
 if old_trip.id is null or number_value is distinct from old_trip.trip_number then
  if number_value !~ '^[1-9][0-9]{0,3}$' then raise exception 'Номер рейса должен быть целым числом от 1 до 1000';end if;
  if number_value::integer>1000 then raise exception 'Номер рейса должен быть от 1 до 1000';end if;
 end if;
 if exists(select 1 from crm_trips where owner_id=actor and app_scope='respectlogistic' and trip_number=number_value and id<>tid) then raise exception 'Рейс с таким номером уже существует';end if;
 if old_trip.id is null then
  insert into crm_trips(app_scope,id,owner_id,customer_id,site_id,vehicle_id,driver_id,carrier_id,trip_number,trip_date,loading_address,unloading_address,volume,unit,unit_price,service_name,status,contract_id,specification_id,source_contract_id,source_specification_id,source_service_id)
  values('respectlogistic',tid,actor,cid,sid,vid,did,carrier,number_value,date_value,origin_value,destination_value,volume_value,coalesce(nullif(p_trip->>'unit',''),'м³'),price_value,nullif(p_trip->>'service_name',''),status_value,s.contract_id,s.specification_id,r_site.contract_id,r_site.specification_id,r_site.service_id);
 else
  update crm_trips set customer_id=cid,site_id=sid,vehicle_id=vid,driver_id=did,carrier_id=carrier,trip_number=number_value,trip_date=date_value,loading_address=origin_value,unloading_address=destination_value,volume=volume_value,unit=coalesce(nullif(p_trip->>'unit',''),'м³'),unit_price=price_value,service_name=nullif(p_trip->>'service_name',''),status=status_value,contract_id=s.contract_id,specification_id=s.specification_id,source_contract_id=r_site.contract_id,source_specification_id=r_site.specification_id,source_service_id=r_site.service_id where id=tid and owner_id=actor;
 end if;
 return tid;
end $$;

notify pgrst,'reload schema';
