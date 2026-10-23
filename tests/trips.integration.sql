begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by created_at limit 1),true) is not null as identity_ready;
set local role authenticated;
do $$
declare c uuid=gen_random_uuid();co uuid=gen_random_uuid();sp uuid=gen_random_uuid();sv uuid=gen_random_uuid();s uuid=gen_random_uuid();d uuid;v uuid;carrier uuid;cv uuid;t uuid=gen_random_uuid();free_trip uuid=gen_random_uuid();ct uuid=gen_random_uuid();number_value text;free_number text;file_path text;file_id uuid;export_body jsonb;body jsonb;ver timestamptz;free_ver timestamptz;a uuid;actor text;ws jsonb;
begin
 insert into respectlogistic_customers(id,inn,payload) values(c,substr(floor(random()*9000000000+1000000000)::bigint::text,1,10),jsonb_build_object('name','TRIP-TEST-CUSTOMER'));
 insert into respectlogistic_contracts(id,customer_id,kind,number,date,payload) values(co,c,'transport','TRIP-TEST-'||substr(co::text,1,8),current_date,'{}');
 insert into respectlogistic_specifications(id,customer_id,contract_id,number,date,payload) values(sp,c,co,'TRIP-SP-'||substr(sp::text,1,8),current_date,'{}');
 insert into respectlogistic_services(id,customer_id,contract_id,specification_id,name,unit,price_kopecks) values(sv,c,co,sp,'Самосвал','м³',250000);
 insert into respectlogistic_sites(id,customer_id,contract_id,specification_id,service_id,payload) values(s,c,co,sp,sv,'{"name":"TRIP-TEST-SITE","loadingAddress":"Погрузка А","address":"Выгрузка Б","routeKm":"120"}');
 insert into rl_crm_drivers(full_name,pay_rate_km,bonus_pct,tax_pct) values('TRIP-TEST-DRIVER',80,10,13) returning id into d;
 insert into rl_crm_vehicles(plate,assigned_driver_id) values('TRIP-TEST-'||substr(t::text,1,4),d) returning id into v;
 body=jsonb_build_object('id',t,'customer_id',c,'site_id',s,'vehicle_id',v,'driver_id',d,'trip_date',current_date,'trip_number','','loading_address','Погрузка уточнённая','unloading_address','Выгрузка уточнённая','volume',12.5,'unit','м³','unit_price',2500,'service_name','Самосвал','status','assigned');
 perform crm_save_trip(body,null);
 if not exists(select 1 from crm_trips where id=t and volume=12.5 and loading_address='Погрузка уточнённая' and source_service_id=sv) then raise exception 'TEST: trip fields not saved';end if;

 select trip_number into number_value from crm_trips where id=t;
 if number_value !~ '^[1-9][0-9]{0,3}$' or number_value::integer>1000 then raise exception 'TEST: automatic number is not short';end if;
 insert into crm_trips(customer_id,site_id,vehicle_id,trip_number,trip_date,status) values(c,s,v,number_value,current_date,'assigned');
 begin
  perform crm_save_trip(body||jsonb_build_object('id',gen_random_uuid(),'trip_number',number_value),null);
  raise exception using message='TEST: duplicate manual number accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform crm_save_trip(body||jsonb_build_object('id',gen_random_uuid(),'trip_number','1001'),null);
  raise exception using message='TEST: number outside range accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform crm_save_trip(body||jsonb_build_object('id',gen_random_uuid(),'vehicle_source','contractor'),null);
  raise exception using message='TEST: wrong vehicle source accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 if not exists(select 1 from crm_customers where id=c) or not exists(select 1 from crm_sites where id=s and customer_id=c and route_km=120) then raise exception 'TEST: customer/site bridge missing';end if;
 select modified_at into ver from crm_trips where id=t;
 perform crm_save_trip(body||'{"volume":15}'::jsonb,ver);
 begin
  perform crm_save_trip(body,ver);
  raise exception using message='TEST: stale edit accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 select modified_at into ver from crm_trips where id=t;
 perform crm_save_trip(body||'{"volume":15,"status":"delivered"}'::jsonb,ver);
 select id into a from crm_payroll_accruals where trip_id=t;
 if not exists(select 1 from crm_payroll_accruals where id=a and base=9600 and bonus=960 and tax=1372.8) then raise exception 'TEST: payroll not linked';end if;
 perform crm_pay_driver_accruals(array[a],'salary',100,current_date);
 perform crm_save_trip(body||jsonb_build_object('id',free_trip),null);
 select modified_at,trip_number into free_ver,free_number from crm_trips where id=free_trip;
 select modified_at into ver from crm_trips where id=t;
 begin
  perform crm_delete_trips(array[t,free_trip],jsonb_build_object(t::text,ver,free_trip::text,free_ver));
  raise exception using message='TEST: paid trip deleted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 if exists(select 1 from crm_trips where id in (t,free_trip) and deleted_at is not null) then raise exception 'TEST: partial bulk deletion';end if;
 perform crm_delete_trips(array[free_trip],jsonb_build_object(free_trip::text,free_ver));
 if not exists(select 1 from crm_trips where id=free_trip and deleted_at is not null) then raise exception 'TEST: soft delete missing';end if;
 begin
  perform crm_save_trip(body||jsonb_build_object('id',gen_random_uuid(),'trip_number',free_number),null);
  raise exception using message='TEST: deleted number reused',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 insert into rl_crm_carriers(name) values('TRIP-TEST-CARRIER') returning id into carrier;
 insert into rl_crm_vehicles(plate,carrier_id,is_subcontractor_vehicle) values('TRIP-TEST-EXTERNAL',carrier,true) returning id into cv;
 perform crm_save_trip(body||jsonb_build_object('id',ct,'vehicle_id',cv,'driver_id','','status','delivered'),null);
 if not exists(select 1 from crm_trips where id=ct and carrier_id=carrier) then raise exception 'TEST: contractor classification missing';end if;
 if exists(select 1 from crm_payroll_accruals where trip_id=ct) then raise exception 'TEST: contractor created employee salary';end if;
 begin
  perform respectlogistic_confirm_trip_documents(ct);
  raise exception using message='TEST: empty document set confirmed',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 file_path=auth.uid()::text||'/'||ct::text||'/'||gen_random_uuid()::text||'.pdf';
 insert into storage.objects(bucket_id,name,metadata) values('respectlogistic-trip-documents',file_path,'{"mimetype":"application/pdf","size":100}');
 file_id=respectlogistic_register_trip_file(ct,file_path,'TEST-TTN.pdf','ttn');
 if not exists(select 1 from rl_crm_trip_files where id=file_id and trip_id=ct) then raise exception 'TEST: uploaded document missing';end if;
 if exists(select 1 from respectlogistic_drive_exports where trip_id=ct) then raise exception 'TEST: incomplete set queued';end if;
 perform respectlogistic_confirm_trip_documents(ct);
 if not exists(select 1 from crm_trips where id=ct and documents_confirmed) or not exists(select 1 from respectlogistic_drive_exports where trip_id=ct and state='pending') then raise exception 'TEST: confirmed completed trip not queued';end if;
 export_body=respectlogistic_claim_drive_export(ct);
 if export_body->>'customer'<>'TRIP-TEST-CUSTOMER' or export_body->>'site'<>'TRIP-TEST-SITE' or export_body->>'plate'<>'TRIP-TEST-EXTERNAL' or jsonb_array_length(export_body->'files')<>1 then raise exception 'TEST: archive hierarchy / files wrong';end if;
 if respectlogistic_claim_drive_export(ct) is not null then raise exception 'TEST: concurrent export claimed twice';end if;
 if not respectlogistic_finish_drive_export(ct,(export_body->>'version')::uuid,'awaiting_connection',null,'Not configured in test') then raise exception 'TEST: pending connection status lost';end if;
 if not exists(select 1 from respectlogistic_drive_exports where trip_id=ct and state='awaiting_connection' and folder_url is null) then raise exception 'TEST: false archive success';end if;
 update crm_trips set service_name='Другой вид услуги' where id=ct;
 if exists(select 1 from crm_trips where id=ct and documents_confirmed) or exists(select 1 from respectlogistic_drive_exports where trip_id=ct) then raise exception 'TEST: changed trip retained confirmed archive';end if;

 insert into crm_drivers(full_name) values('OTHER-CRM-SYNTHETIC') returning id into d;
 if exists(select 1 from rl_crm_drivers where id=d) then raise exception 'TEST: same owner foreign driver visible';end if;
 begin
  perform crm_save_trip(body||jsonb_build_object('id',gen_random_uuid(),'driver_id',d),null);
  raise exception using message='TEST: foreign driver accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 ws=crm_read_trip_workspace();
 if not (ws->'trips')@>jsonb_build_array(jsonb_build_object('id',t,'locked',true)) then raise exception 'TEST: locked trip not returned';end if;
 if (ws->'trips')@>jsonb_build_array(jsonb_build_object('id',free_trip)) then raise exception 'TEST: deleted trip visible';end if;
 if (ws->'drivers')@>jsonb_build_array(jsonb_build_object('id',d)) then raise exception 'TEST: foreign driver in RPC';end if;
 if exists(select 1 from jsonb_array_elements(ws->'trips') x where (x->>'id')::uuid in(select id from crm_trips where app_scope is distinct from 'respectlogistic')) then raise exception 'TEST: foreign trip visible';end if;
 actor=current_setting('request.jwt.claim.sub');perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 ws=crm_read_trip_workspace();if (ws->'trips')@>jsonb_build_array(jsonb_build_object('id',t)) then raise exception 'TEST: owner isolation failed';end if;
 perform set_config('request.jwt.claim.sub',actor,true);
end $$;
rollback;
select 'PASS: current customer/site bridge; create/edit; address snapshots; stale version rejection; employee payroll; atomic protected bulk delete; soft delete; contractor tagging without employee payroll; owner isolation. Test data rolled back.' as verification;
