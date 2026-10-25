begin;
-- Force current_date away from the Moscow business day. Document dates are Moscow dates.
set local TimeZone='Etc/GMT+12';
select set_config('request.jwt.claim.sub',(select id::text from auth.users limit 1),true) is not null as identity_ready;
do $$declare actor uuid=auth.uid();cid uuid=gen_random_uuid();co uuid=gen_random_uuid();sp uuid=gen_random_uuid();svc uuid=gen_random_uuid();site uuid=gen_random_uuid();driver uuid=gen_random_uuid();veh uuid=gen_random_uuid();trip uuid=gen_random_uuid();invoice uuid=gen_random_uuid();upd uuid=gen_random_uuid();registry uuid=gen_random_uuid();other_invoice uuid=gen_random_uuid();versions jsonb;day date=(clock_timestamp() at time zone 'Europe/Moscow')::date;body jsonb;begin
 insert into respectlogistic_customers(id,owner_id,inn,payload) values(cid,actor,'9900000000','{"name":"INVOICE-LINK-ROLLBACK","legalAddress":"TEST"}');
 insert into respectlogistic_contracts(id,owner_id,customer_id,kind,number,date,payload) values(co,actor,cid,'transport','LINK-'||co,current_date,'{}');
 insert into respectlogistic_specifications(id,owner_id,customer_id,contract_id,number,date,payload) values(sp,actor,cid,co,'LINK-'||sp,current_date,'{}');
 insert into respectlogistic_services(id,owner_id,customer_id,contract_id,specification_id,name,unit,price_kopecks) values(svc,actor,cid,co,sp,'Перевозка','т',12200);
 insert into respectlogistic_sites(id,owner_id,customer_id,contract_id,specification_id,service_id,payload) values(site,actor,cid,co,sp,svc,'{"name":"INVOICE SITE","routeKm":"10"}');
 insert into crm_drivers(id,owner_id,app_scope,full_name) values(driver,actor,'respectlogistic','INVOICE DRIVER');
 insert into crm_vehicles(id,owner_id,app_scope,plate,assigned_driver_id) values(veh,actor,'respectlogistic','L-'||substr(veh::text,1,8),driver);
 perform crm_save_trip(jsonb_build_object('id',trip,'customer_id',cid,'site_id',site,'vehicle_id',veh,'driver_id',driver,'trip_date',current_date,'loading_address','LOAD','unloading_address','UNLOAD','volume',10,'unit','т','unit_price',122,'service_name','Перевозка','status','sent'),null);
 versions=jsonb_build_object(trip,(select modified_at from crm_trips where id=trip));
 body=jsonb_build_object('id',invoice,'kind','invoice','customer_id',cid,'site_id',site,'document_date',day);
 perform respectlogistic_create_accounting_document(body,array[trip],versions);
 if (select total from respectlogistic_accounting_documents where id=invoice)<>1220 then raise exception 'TEST: invoice amount';end if;
 if (select document_date from respectlogistic_accounting_documents where id=invoice)<>day then raise exception 'TEST: Moscow midnight rejected';end if;
 begin perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid(),'document_date',day+1),array[trip],versions);raise exception using message='TEST: future document accepted',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',upd,'kind','upd','invoice_id',invoice),array[trip],versions);
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',registry,'kind','registry','invoice_id',invoice),array[trip],versions);
 if (select count(*) from respectlogistic_accounting_documents where invoice_id=invoice)<>2 then raise exception 'TEST: child links absent';end if;
 if (select snapshot->>'invoice_number' from respectlogistic_accounting_documents where id=upd) is distinct from (select number from respectlogistic_accounting_documents where id=invoice) then raise exception 'TEST: missing printed invoice reference';end if;
 if (select status from crm_trips where id=trip)<>'sent' then raise exception 'TEST: creating closing draft completed trip';end if;
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',upd,'kind','upd','invoice_id',invoice),array[trip],versions);
 begin perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',upd,'kind','upd','invoice_id',gen_random_uuid()),array[trip],versions);raise exception using message='TEST: reparented idempotent child',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 begin perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid(),'kind','upd','invoice_id',invoice),array[gen_random_uuid()],versions);raise exception using message='TEST: unrelated trip accepted',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 begin update respectlogistic_accounting_documents set status='cancelled' where id=invoice;raise exception using message='TEST: source invoice cancelled with active child',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid(),'kind','registry','invoice_id',invoice),array[trip],versions);raise exception using message='TEST: foreign invoice accepted',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 perform set_config('request.jwt.claim.sub',actor::text,true);
end$$;
set local role anon;
do $$begin
 begin perform respectlogistic_create_accounting_document('{}');raise exception using message='TEST: anonymous accounting RPC',errcode='P0002';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: Moscow midnight document date, invoice amounts, linked UPD and registry, immutable parent on retry, foreign invoice/trip denial, cancellation guard, anonymous execute denied. Rolled back.' as verification;
