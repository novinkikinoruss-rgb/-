-- Explicit application provenance. Never adopt unclassified legacy rows.
alter table public.crm_carriers add column if not exists app_scope text;
create index if not exists crm_carriers_app_owner_idx on public.crm_carriers(owner_id,app_scope);
alter table public.crm_drivers add column if not exists app_scope text;
create index if not exists crm_drivers_app_owner_idx on public.crm_drivers(owner_id,app_scope);
alter table public.crm_vehicles add column if not exists app_scope text;
create index if not exists crm_vehicles_app_owner_idx on public.crm_vehicles(owner_id,app_scope);
alter table public.crm_customers add column if not exists app_scope text;
create index if not exists crm_customers_app_owner_idx on public.crm_customers(owner_id,app_scope);
alter table public.crm_sites add column if not exists app_scope text;
create index if not exists crm_sites_app_owner_idx on public.crm_sites(owner_id,app_scope);
alter table public.crm_trips add column if not exists app_scope text;
create index if not exists crm_trips_app_owner_idx on public.crm_trips(owner_id,app_scope);
create or replace view public.rl_crm_carriers with(security_invoker=true) as select t.* from public.crm_carriers t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_carriers to authenticated;
alter view public.rl_crm_carriers alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_drivers with(security_invoker=true) as select t.* from public.crm_drivers t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_drivers to authenticated;
alter view public.rl_crm_drivers alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_vehicles with(security_invoker=true) as select t.* from public.crm_vehicles t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_vehicles to authenticated;
alter view public.rl_crm_vehicles alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_customers with(security_invoker=true) as select t.* from public.crm_customers t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_customers to authenticated;
alter view public.rl_crm_customers alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_sites with(security_invoker=true) as select t.* from public.crm_sites t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_sites to authenticated;
alter view public.rl_crm_sites alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_trips with(security_invoker=true) as select t.* from public.crm_trips t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
grant select,insert,update on public.rl_crm_trips to authenticated;
alter view public.rl_crm_trips alter column app_scope set default 'respectlogistic';
create or replace view public.rl_crm_documents with(security_invoker=true) as select t.* from public.crm_documents t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_trips p where p.id=t.trip_id) with cascaded check option;
grant select,insert,update on public.rl_crm_documents to authenticated;
create or replace view public.rl_crm_driver_fines with(security_invoker=true) as select t.* from public.crm_driver_fines t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_drivers p where p.id=t.driver_id) and (t.trip_id is null or exists(select 1 from public.rl_crm_trips p where p.id=t.trip_id)) with cascaded check option;
grant select,insert,update on public.rl_crm_driver_fines to authenticated;
create or replace view public.rl_crm_payroll_accruals with(security_invoker=true) as select t.* from public.crm_payroll_accruals t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_trips p where p.id=t.trip_id) with cascaded check option;
grant select,insert,update on public.rl_crm_payroll_accruals to authenticated;
create or replace view public.rl_crm_payroll_payments with(security_invoker=true) as select t.* from public.crm_payroll_payments t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_payroll_accruals p where p.id=t.accrual_id) with cascaded check option;
grant select,insert,update on public.rl_crm_payroll_payments to authenticated;
create or replace view public.rl_crm_payroll_deductions with(security_invoker=true) as select t.* from public.crm_payroll_deductions t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_payroll_accruals p where p.id=t.accrual_id) with cascaded check option;
grant select,insert,update on public.rl_crm_payroll_deductions to authenticated;
create or replace view public.rl_crm_fleet_maintenance with(security_invoker=true) as select t.* from public.crm_fleet_maintenance t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_vehicles p where p.id=t.vehicle_id) with cascaded check option;
grant select,insert,update on public.rl_crm_fleet_maintenance to authenticated;
create or replace view public.rl_crm_counterparty_contracts with(security_invoker=true) as select t.* from public.crm_counterparty_contracts t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_carriers p where p.id=t.counterparty_id) with cascaded check option;
grant select,insert,update on public.rl_crm_counterparty_contracts to authenticated;
create or replace view public.rl_crm_counterparty_specifications with(security_invoker=true) as select t.* from public.crm_counterparty_specifications t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_counterparty_contracts p where p.id=t.contract_id) with cascaded check option;
grant select,insert,update on public.rl_crm_counterparty_specifications to authenticated;
create or replace view public.rl_crm_counterparty_invoices with(security_invoker=true) as select t.* from public.crm_counterparty_invoices t where t.owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_carriers p where p.id=t.counterparty_id) with cascaded check option;
grant select,insert,update on public.rl_crm_counterparty_invoices to authenticated;
create or replace function public.crm_read_trip_workspace() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
select jsonb_build_object(
 'trips',coalesce((select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'loading_address',coalesce(t.loading_address,s.loading_address,''),'unloading_address',coalesce(t.unloading_address,s.unloading_address,''),
 'locked',exists(select 1 from crm_invoice_lines x where x.trip_id=t.id) or exists(select 1 from rl_crm_payroll_accruals a where a.trip_id=t.id and (exists(select 1 from rl_crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from rl_crm_payroll_deductions d where d.accrual_id=a.id))))
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
$$;
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
   loop
    insert into crm_trip_counters(owner_id,counter_date,value) values(actor,date_value,1) on conflict(owner_id,counter_date) do update set value=crm_trip_counters.value+1 returning value into n;
    number_value='Р-'||to_char(date_value,'YYYYMMDD')||'-'||lpad(n::text,4,'0');
    exit when not exists(select 1 from crm_trips where owner_id=actor and trip_number=number_value and deleted_at is null);
   end loop;
  end if;
 end if;
 if length(number_value)>100 then raise exception 'Номер рейса слишком длинный';end if;
 if exists(select 1 from crm_trips where owner_id=actor and trip_number=number_value and id<>tid and deleted_at is null) then raise exception 'Рейс с таким номером уже существует';end if;
 if old_trip.id is null then
  insert into crm_trips(app_scope,id,owner_id,customer_id,site_id,vehicle_id,driver_id,carrier_id,trip_number,trip_date,loading_address,unloading_address,volume,unit,unit_price,service_name,status,contract_id,specification_id,source_contract_id,source_specification_id,source_service_id)
  values('respectlogistic',tid,actor,cid,sid,vid,did,carrier,number_value,date_value,origin_value,destination_value,volume_value,coalesce(nullif(p_trip->>'unit',''),'м³'),price_value,nullif(p_trip->>'service_name',''),status_value,s.contract_id,s.specification_id,r_site.contract_id,r_site.specification_id,r_site.service_id);
 else
  update crm_trips set customer_id=cid,site_id=sid,vehicle_id=vid,driver_id=did,carrier_id=carrier,trip_number=number_value,trip_date=date_value,loading_address=origin_value,unloading_address=destination_value,volume=volume_value,unit=coalesce(nullif(p_trip->>'unit',''),'м³'),unit_price=price_value,service_name=nullif(p_trip->>'service_name',''),status=status_value,contract_id=s.contract_id,specification_id=s.specification_id,source_contract_id=r_site.contract_id,source_specification_id=r_site.specification_id,source_service_id=r_site.service_id where id=tid and owner_id=actor;
 end if;
 return tid;
end $$;
create or replace function public.crm_delete_trips(p_ids uuid[],p_versions jsonb)
returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();n integer;item public.rl_crm_trips;
begin
 if actor is null or coalesce(cardinality(p_ids),0)=0 or cardinality(p_ids)>5000 or jsonb_typeof(p_versions) is distinct from 'object' then raise exception 'Выберите рейсы для удаления';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-trips',0));
 perform id from rl_crm_trips where id=any(p_ids) and owner_id=actor order by id for update;
 select count(*) into n from rl_crm_trips where id=any(p_ids) and owner_id=actor and deleted_at is null;
 if n<>cardinality(p_ids) then raise exception 'Выборка изменилась. Обновите список рейсов';end if;
 for item in select * from rl_crm_trips where id=any(p_ids) and owner_id=actor loop
  if (p_versions->>item.id::text)::timestamptz is distinct from item.modified_at then raise exception 'Рейс % изменён в другой вкладке. Обновите список',item.trip_number;end if;
  if exists(select 1 from crm_invoice_lines x where x.trip_id=item.id) or exists(select 1 from crm_payroll_accruals a where a.trip_id=item.id and (exists(select 1 from crm_payroll_payments p where p.accrual_id=a.id) or exists(select 1 from crm_payroll_deductions f where f.accrual_id=a.id))) then raise exception 'Рейс % включён в счёт или имеет выплаты/удержания. Выборка не удалена',item.trip_number;end if;
 end loop;
 update rl_crm_trips set deleted_at=clock_timestamp() where id=any(p_ids) and owner_id=actor;
 get diagnostics n=row_count;return n;
end $$;

-- Boundaries for existing payroll RPCs; retain originals for the other application.
CREATE OR REPLACE FUNCTION public.rl_crm_apply_driver_fines(p_accrual_ids uuid[], p_fine_ids uuid[], p_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.crm_payroll_accruals;f public.crm_driver_fines;v_driver uuid;v_remaining numeric;v_due numeric;v_take numeric;v_total numeric=0;v_count integer=0;
begin
 if auth.uid() is null or p_date is null or coalesce(cardinality(p_accrual_ids),0)=0 or coalesce(cardinality(p_fine_ids),0)=0 then raise exception 'Выберите начисления, штрафы и дату';end if;
 perform id from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() order by id for update;
 perform id from public.rl_crm_driver_fines where id=any(p_fine_ids) and owner_id=auth.uid() order by id for update;
 for a in select * from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active loop
  if v_driver is not null and v_driver<>a.driver_id then raise exception 'Выберите одного водителя';end if;
  if a.accrual_date>p_date then raise exception 'Удержание предшествует начислению';end if;
  v_driver=a.driver_id;v_count=v_count+1;
 end loop;
 if v_count<>cardinality(p_accrual_ids) then raise exception 'Начисления недоступны или повторяются';end if;
 select count(*) into v_count from public.rl_crm_driver_fines where id=any(p_fine_ids) and driver_id=v_driver and owner_id=auth.uid() and deleted_at is null and not paid and fine_date<=p_date;
 if v_count<>cardinality(p_fine_ids) then raise exception 'Штрафы недоступны, оплачены или относятся к другому водителю';end if;
 for f in select * from public.rl_crm_driver_fines where id=any(p_fine_ids) and owner_id=auth.uid() order by fine_date,id loop
  select f.amount-coalesce(sum(amount),0) into v_remaining from public.rl_crm_payroll_deductions where fine_id=f.id;
  for a in select * from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
   exit when v_remaining<=0;
   select a.base+a.bonus-(select coalesce(sum(amount),0) from public.rl_crm_payroll_payments where accrual_id=a.id and kind='salary')-(select coalesce(sum(amount),0) from public.rl_crm_payroll_deductions where accrual_id=a.id) into v_due;
   v_take=least(v_remaining,v_due);
   if v_take>0 then
    insert into public.rl_crm_payroll_deductions(accrual_id,fine_id,amount,deduction_date) values(a.id,f.id,v_take,p_date);
    v_remaining=v_remaining-v_take;v_total=v_total+v_take;
   end if;
  end loop;
 end loop;
 if v_total<=0 then raise exception 'Нет доступной зарплаты для удержания или штрафы уже учтены';end if;
 return v_total;
end $function$
;
CREATE OR REPLACE FUNCTION public.rl_crm_complete_fleet_maintenance(p_vehicle_id uuid, p_kind text, p_odometer numeric, p_date date, p_notes text DEFAULT ''::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.crm_vehicles; result uuid;
begin
 if auth.uid() is null or p_kind not in ('service','oil') or p_date is null or p_date>current_date or p_odometer is null or p_odometer<0 or p_odometer::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте дату, пробег и вид обслуживания'; end if;
 select * into v from public.rl_crm_vehicles where id=p_vehicle_id and owner_id=auth.uid() and carrier_id is null and not is_subcontractor_vehicle and archived_at is null for update;
 if v.id is null then raise exception 'Техника недоступна'; end if;
 if p_odometer<v.odometer_km then raise exception 'Пробег не может быть меньше текущего'; end if;
 insert into public.rl_crm_fleet_maintenance(vehicle_id,kind,performed_date,odometer_km,notes) values(v.id,p_kind,p_date,p_odometer,coalesce(p_notes,'')) returning id into result;
 update public.rl_crm_vehicles set odometer_km=p_odometer,
 next_service_km=case when p_kind='service' then p_odometer+service_interval_km else next_service_km end,
 next_oil_km=case when p_kind='oil' then p_odometer+oil_interval_km else next_oil_km end where id=v.id;
 return result;
end $function$
;
CREATE OR REPLACE FUNCTION public.rl_crm_pay_driver_accruals(p_accrual_ids uuid[], p_kind text, p_amount numeric, p_date date)
 RETURNS numeric
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare a public.crm_payroll_accruals;v_due numeric;v_remaining numeric=p_amount;v_total numeric=0;v_paid numeric;v_driver uuid;v_count integer=0;
begin
 if auth.uid() is null or p_kind not in ('salary','tax') or p_date is null or p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,2) or coalesce(cardinality(p_accrual_ids),0)=0 then raise exception 'Проверьте начисления, вид, дату и сумму оплаты';end if;
 -- Единый порядок блокировок предотвращает взаимные блокировки при пересекающихся выплатах.
 perform id from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() order by id for update;
 for a in select * from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
  if v_driver is not null and v_driver<>a.driver_id then raise exception 'Выберите начисления одного водителя';end if;
  if p_date<a.accrual_date then raise exception 'Оплата не может предшествовать дате начисления';end if;
  v_driver=a.driver_id;v_count=v_count+1;
  select coalesce(sum(amount),0) into v_paid from public.rl_crm_payroll_payments where accrual_id=a.id and kind=p_kind;
  v_total=v_total+case when p_kind='salary' then a.base+a.bonus-(select coalesce(sum(amount),0) from public.rl_crm_payroll_deductions where accrual_id=a.id) else a.tax end-v_paid;
 end loop;
 if v_count<>cardinality(p_accrual_ids) or p_amount>v_total then raise exception 'Начисления недоступны или сумма превышает остаток';end if;
 for a in select * from public.rl_crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
  select coalesce(sum(amount),0) into v_paid from public.rl_crm_payroll_payments where accrual_id=a.id and kind=p_kind;
  v_due=least(v_remaining,case when p_kind='salary' then a.base+a.bonus-(select coalesce(sum(amount),0) from public.rl_crm_payroll_deductions where accrual_id=a.id) else a.tax end-v_paid);
  if v_due>0 then insert into public.rl_crm_payroll_payments(accrual_id,kind,amount,payment_date) values(a.id,p_kind,v_due,p_date);v_remaining=v_remaining-v_due;end if;
  exit when v_remaining=0;
 end loop;
 return p_amount-v_remaining;
end $function$
;
CREATE OR REPLACE FUNCTION public.rl_crm_prepare_payroll(p_trip_ids uuid[])
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_count integer;
begin
 if auth.uid() is null or coalesce(cardinality(p_trip_ids),0)=0 then raise exception 'Выберите выполненные рейсы';end if;
 if exists(select 1 from public.rl_crm_trips where id=any(p_trip_ids) and owner_id=auth.uid() and (status<>'delivered' or deleted_at is not null)) then raise exception 'Выберите выполненные активные рейсы';end if;
 update public.rl_crm_trips set status=status where id=any(p_trip_ids) and owner_id=auth.uid() and status='delivered' and deleted_at is null;
 get diagnostics v_count=row_count;
 if v_count<>cardinality(p_trip_ids) then raise exception 'Рейсы недоступны или повторяются';end if;
 return v_count;
end $function$
;
notify pgrst,'reload schema';
