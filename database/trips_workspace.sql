-- Spreadsheet trips, owned reference bridge and atomic write operations.
alter table public.crm_trips
 add column if not exists loading_address text,
 add column if not exists unloading_address text,
 add column if not exists unit text not null default 'м³',
 add column if not exists modified_at timestamptz not null default now(),
 add column if not exists source_contract_id uuid references public.respectlogistic_contracts(id),
 add column if not exists source_specification_id uuid references public.respectlogistic_specifications(id),
 add column if not exists source_service_id uuid references public.respectlogistic_services(id);
create index if not exists crm_trip_source_contract_idx on public.crm_trips(source_contract_id);
create index if not exists crm_trip_source_spec_idx on public.crm_trips(source_specification_id);
create index if not exists crm_trip_source_service_idx on public.crm_trips(source_service_id);
create index if not exists crm_trip_owner_date_idx on public.crm_trips(owner_id,trip_date desc);
create table public.crm_trip_counters(owner_id uuid not null default auth.uid(),counter_date date not null,value integer not null check(value>0),primary key(owner_id,counter_date));
alter table public.crm_trip_counters enable row level security;
create policy trip_counter_owner on public.crm_trip_counters for all to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
grant select,insert,update on public.crm_trip_counters to authenticated;
create function public.crm_touch_trip() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$begin new.modified_at=clock_timestamp();return new;end$$;
create trigger trip_modified_at before update on public.crm_trips for each row execute function public.crm_touch_trip();
create function public.crm_read_trip_workspace() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
select jsonb_build_object(
 'trips',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'loading_address',coalesce(t.loading_address,s.loading_address,''),'unloading_address',coalesce(t.unloading_address,s.unloading_address,''),
 'locked',exists(select 1 from crm_invoice_lines x where x.trip_id=t.id) or exists(select 1 from crm_payroll_accruals a where a.trip_id=t.id and (exists(select 1 from crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from crm_payroll_deductions d where d.accrual_id=a.id))))
 order by t.trip_date desc nulls last,t.created_at desc,t.id) from crm_trips t left join crm_sites s on s.id=t.site_id where t.owner_id=(select auth.uid()) and t.deleted_at is null),'[]'),
 'customers',coalesce((select jsonb_agg(x.obj order by x.obj->>'name') from (
 select jsonb_build_object('id',c.id,'name',c.payload->>'name') as obj from respectlogistic_customers c where c.owner_id=(select auth.uid())
 union all select jsonb_build_object('id',c.id,'name',c.name) from crm_customers c where c.owner_id=(select auth.uid()) and c.deleted_at is null and not c.is_archived and not exists(select 1 from respectlogistic_customers r where r.id=c.id and r.owner_id=(select auth.uid()))
 ) x),'[]'),
 'sites',coalesce((select jsonb_agg(x.obj order by x.obj->>'name') from (
 select jsonb_build_object('id',s.id,'customer_id',s.customer_id,'name',s.payload->>'name','loading_address',coalesce(s.payload->>'loadingAddress',''),'unloading_address',coalesce(s.payload->>'address',''),'route_km',s.payload->>'routeKm','service_name',v.name,'unit',v.unit,'unit_price',v.price_kopecks/100.0,'contract_number',c.number) as obj
 from respectlogistic_sites s join respectlogistic_services v on v.id=s.service_id join respectlogistic_contracts c on c.id=s.contract_id where s.owner_id=(select auth.uid())
 union all select jsonb_build_object('id',s.id,'customer_id',s.customer_id,'name',s.name,'loading_address',s.loading_address,'unloading_address',s.unloading_address,'route_km',s.route_km,'service_name',sp.service_name,'unit',sp.unit,'unit_price',sp.rate,'contract_number',c.contract_number)
 from crm_sites s left join crm_specifications sp on sp.id=s.specification_id left join crm_contracts c on c.id=s.contract_id where s.owner_id=(select auth.uid()) and s.deleted_at is null and not exists(select 1 from respectlogistic_sites r where r.id=s.id and r.owner_id=(select auth.uid()))
 ) x),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'carrier_id',v.carrier_id,'is_subcontractor_vehicle',v.is_subcontractor_vehicle,'assigned_driver_id',v.assigned_driver_id,'archived_at',v.archived_at) order by v.plate) from crm_vehicles v where v.owner_id=(select auth.uid())),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'carrier_id',d.carrier_id,'job_status',d.job_status,'archived_at',d.archived_at) order by d.full_name) from crm_drivers d where d.owner_id=(select auth.uid())),'[]'),
 'carriers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'is_blocked',c.is_blocked) order by c.name) from crm_carriers c where c.owner_id=(select auth.uid())),'[]')
)
$$;
create function public.crm_save_trip(p_trip jsonb,p_expected_modified_at timestamptz default null)
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
 if origin_value='' or destination_value='' or greatest(length(origin_value),length(destination_value))>4000 then raise exception 'Заполните адреса погрузки и выгрузки';end if;
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
  insert into crm_customers(id,owner_id,name,inn,kpp,ogrn,phone,email,legal_address)
  values(cid,actor,r_customer.payload->>'name',r_customer.inn,r_customer.payload->>'kpp',r_customer.payload->>'ogrn',r_customer.payload->>'phone',r_customer.payload->>'email',r_customer.payload->>'legalAddress')
  on conflict(id) do update set name=excluded.name,inn=excluded.inn,kpp=excluded.kpp,ogrn=excluded.ogrn,phone=excluded.phone,email=excluded.email,legal_address=excluded.legal_address where crm_customers.owner_id=actor and crm_customers.deleted_at is null and not crm_customers.is_archived;
  get diagnostics rows_changed=row_count;if rows_changed<>1 then raise exception 'Заказчик в архиве или недоступен';end if;
 elsif not exists(select 1 from crm_customers where id=cid and owner_id=actor and deleted_at is null and not is_archived) then raise exception 'Заказчик недоступен';end if;
 select * into r_site from respectlogistic_sites where id=sid and owner_id=actor;
 if r_site.id is not null then
  if r_site.customer_id<>cid then raise exception 'Объект относится к другому заказчику';end if;
  select * into r_service from respectlogistic_services where id=r_site.service_id and owner_id=actor;
  insert into crm_sites(id,owner_id,customer_id,name,loading_address,unloading_address,route_km)
  values(sid,actor,cid,coalesce(r_site.payload->>'name','Объект'),coalesce(r_site.payload->>'loadingAddress',''),coalesce(r_site.payload->>'address',''),nullif(r_site.payload->>'routeKm','')::numeric)
  on conflict(id) do update set customer_id=excluded.customer_id,name=excluded.name,loading_address=excluded.loading_address,unloading_address=excluded.unloading_address,route_km=excluded.route_km where crm_sites.owner_id=actor and crm_sites.deleted_at is null;
  get diagnostics rows_changed=row_count;if rows_changed<>1 then raise exception 'Объект в архиве или недоступен';end if;
 end if;
 select * into s from crm_sites where id=sid and owner_id=actor and deleted_at is null;
 if s.id is null or s.customer_id<>cid then raise exception 'Выберите объект этого заказчика';end if;
 select * into v from crm_vehicles where id=vid and owner_id=actor;
 if v.id is null or (v.archived_at is not null and vid is distinct from old_trip.vehicle_id) then raise exception 'Техника недоступна или в архиве';end if;
 carrier=coalesce(v.carrier_id,case when v.is_subcontractor_vehicle then nullif(p_trip->>'carrier_id','')::uuid end);
 if (v.is_subcontractor_vehicle or v.carrier_id is not null) and carrier is null then raise exception 'Укажите контрагента для выбранной техники';end if;
 if carrier is not null and not exists(select 1 from crm_carriers where id=carrier and owner_id=actor and not is_blocked) then raise exception 'Контрагент недоступен или заблокирован';end if;
 if did is not null then
  select * into d from crm_drivers where id=did and owner_id=actor;
  if d.id is null or d.carrier_id is distinct from carrier then raise exception 'Выберите водителя выбранного исполнителя';end if;
  if d.archived_at is not null and did is distinct from old_trip.driver_id then raise exception 'Водитель в архиве';end if;
 end if;
 if status_value='delivered' and carrier is null and did is null then raise exception 'Для выполненного рейса собственной техники укажите водителя';end if;
 if number_value='' then
  if old_trip.id is not null then number_value=old_trip.trip_number;
  else
   insert into crm_trip_counters(owner_id,counter_date,value) values(actor,date_value,1) on conflict(owner_id,counter_date) do update set value=crm_trip_counters.value+1 returning value into n;
   number_value='Р-'||to_char(date_value,'YYYYMMDD')||'-'||lpad(n::text,4,'0');
  end if;
 end if;
 if length(number_value)>100 then raise exception 'Номер рейса слишком длинный';end if;
 if exists(select 1 from crm_trips where owner_id=actor and trip_number=number_value and id<>tid and deleted_at is null) then raise exception 'Рейс с таким номером уже существует';end if;
 if old_trip.id is null then
  insert into crm_trips(id,owner_id,customer_id,site_id,vehicle_id,driver_id,carrier_id,trip_number,trip_date,loading_address,unloading_address,volume,unit,unit_price,service_name,status,contract_id,specification_id,source_contract_id,source_specification_id,source_service_id)
  values(tid,actor,cid,sid,vid,did,carrier,number_value,date_value,origin_value,destination_value,volume_value,coalesce(nullif(p_trip->>'unit',''),'м³'),price_value,nullif(p_trip->>'service_name',''),status_value,s.contract_id,s.specification_id,r_site.contract_id,r_site.specification_id,r_site.service_id);
 else
  update crm_trips set customer_id=cid,site_id=sid,vehicle_id=vid,driver_id=did,carrier_id=carrier,trip_number=number_value,trip_date=date_value,loading_address=origin_value,unloading_address=destination_value,volume=volume_value,unit=coalesce(nullif(p_trip->>'unit',''),'м³'),unit_price=price_value,service_name=nullif(p_trip->>'service_name',''),status=status_value,contract_id=s.contract_id,specification_id=s.specification_id,source_contract_id=r_site.contract_id,source_specification_id=r_site.specification_id,source_service_id=r_site.service_id where id=tid and owner_id=actor;
 end if;
 return tid;
end $$;
create function public.crm_delete_trips(p_ids uuid[],p_versions jsonb)
returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();n integer;item public.crm_trips;
begin
 if actor is null or coalesce(cardinality(p_ids),0)=0 or cardinality(p_ids)>5000 or jsonb_typeof(p_versions) is distinct from 'object' then raise exception 'Выберите рейсы для удаления';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
 perform id from crm_trips where id=any(p_ids) and owner_id=actor order by id for update;
 select count(*) into n from crm_trips where id=any(p_ids) and owner_id=actor and deleted_at is null;
 if n<>cardinality(p_ids) then raise exception 'Выборка изменилась. Обновите список рейсов';end if;
 for item in select * from crm_trips where id=any(p_ids) and owner_id=actor loop
  if (p_versions->>item.id::text)::timestamptz is distinct from item.modified_at then raise exception 'Рейс % изменён в другой вкладке. Обновите список',item.trip_number;end if;
  if exists(select 1 from crm_invoice_lines x where x.trip_id=item.id) or exists(select 1 from crm_payroll_accruals a where a.trip_id=item.id and (exists(select 1 from crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from crm_payroll_deductions f where f.accrual_id=a.id))) then raise exception 'Рейс % включён в счёт или имеет выплаты/удержания. Выборка не удалена',item.trip_number;end if;
 end loop;
 update crm_trips set deleted_at=clock_timestamp() where id=any(p_ids) and owner_id=actor;
 get diagnostics n=row_count;return n;
end $$;
revoke all on function public.crm_read_trip_workspace(),public.crm_save_trip(jsonb,timestamptz),public.crm_delete_trips(uuid[],jsonb),public.crm_touch_trip() from public,anon;
grant execute on function public.crm_read_trip_workspace(),public.crm_save_trip(jsonb,timestamptz),public.crm_delete_trips(uuid[],jsonb),public.crm_touch_trip() to authenticated;
notify pgrst,'reload schema';
