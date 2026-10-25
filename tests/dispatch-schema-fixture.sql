create table public.crm_carriers (id uuid default gen_random_uuid() primary key,name text,inn text,phone text,created_at timestamp with time zone default now(),owner_id uuid default auth.uid(),kpp text,ogrn text,legal_address text,is_blocked boolean default false,liability_insurance_until date,email text,app_scope text);
create table public.crm_drivers (id uuid default gen_random_uuid() primary key,full_name text,phone text,created_at timestamp with time zone default now(),owner_id uuid default auth.uid(),license_number text,license_until date,hire_date date,default_rate_per_km numeric default 0,pay_rate_km numeric default 70,bonus_pct numeric default 13,tax_pct numeric default 44,carrier_id uuid,birth_date date,notes text default ''::text,employment_kind text default 'official'::text,job_status text default 'active'::text,archived_at timestamp with time zone,contract_number text,contract_date date,app_scope text);
create table public.crm_trips (id uuid default gen_random_uuid() primary key,owner_id uuid default auth.uid(),order_id uuid,trip_number text,driver_id uuid,vehicle_id uuid,status text default 'assigned'::text,sent_at timestamp with time zone,created_at timestamp with time zone default now(),deleted_at timestamp with time zone,waybill_number text,trip_date date,ticket_number text,volume numeric default 0,unit_price numeric default 0,service_name text,site_id uuid,specification_id uuid,contract_id uuid,customer_id uuid,carrier_id uuid,loading_address text,unloading_address text,unit text default 'м³'::text,modified_at timestamp with time zone default now(),source_contract_id uuid,source_specification_id uuid,source_service_id uuid,app_scope text,documents_confirmed boolean default false,distance_km_snapshot numeric);
create table public.crm_vehicles (id uuid default gen_random_uuid() primary key,plate text,brand text,model text,status text default 'available'::text,created_at timestamp with time zone default now(),owner_id uuid default auth.uid(),odometer_km numeric default 0,fuel_norm_l100 numeric,vehicle_type text default 'truck'::text,trailer_plate text,cargo_capacity_kg numeric,volume_m3 numeric,osago_until date,kasko_until date,inspection_until date,tachograph_until date,next_service_km numeric,is_subcontractor_vehicle boolean default false,carrier_id uuid,phone text,vin text,manufacture_year integer,assigned_driver_id uuid,notes text default ''::text,photo_url text,service_interval_km numeric default 15000,oil_interval_km numeric default 15000,next_oil_km numeric,reminder_before_km numeric default 1000,archived_at timestamp with time zone,app_scope text);
create table public.respectlogistic_contracts (id uuid primary key,owner_id uuid default auth.uid(),customer_id uuid,kind text,number text,date date,end_date date,payload jsonb);
create table public.respectlogistic_customers (id uuid primary key,owner_id uuid default auth.uid(),inn text,payload jsonb,created_at timestamp with time zone default now());
create table public.respectlogistic_services (id uuid primary key,owner_id uuid default auth.uid(),customer_id uuid,contract_id uuid,specification_id uuid,name text,unit text,price_kopecks bigint);
create table public.respectlogistic_sites (id uuid primary key,owner_id uuid default auth.uid(),customer_id uuid,contract_id uuid,specification_id uuid,service_id uuid,payload jsonb);
create table public.respectlogistic_specifications (id uuid primary key,owner_id uuid default auth.uid(),customer_id uuid,contract_id uuid,number text,date date,payload jsonb);
create table public.crm_customers (id uuid default gen_random_uuid() primary key,name text,inn text,phone text,email text,created_at timestamp with time zone default now(),owner_id uuid default auth.uid(),kpp text,ogrn text,legal_address text,is_edo boolean default false,credit_days integer default 0,credit_limit numeric default 0,is_archived boolean default false,deleted_at timestamp with time zone,app_scope text);
create table public.crm_sites (id uuid default gen_random_uuid() primary key,owner_id uuid default auth.uid(),customer_id uuid,name text,loading_address text,unloading_address text,route_km numeric,created_at timestamp with time zone default now(),contract_id uuid,specification_id uuid,deleted_at timestamp with time zone,app_scope text);
CREATE OR REPLACE FUNCTION public.crm_save_trip(p_trip jsonb, p_expected_modified_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
end $function$
;
