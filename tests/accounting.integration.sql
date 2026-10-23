begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by created_at limit 1),true) is not null as identity_ready;
set local role authenticated;
do $$
declare c uuid=gen_random_uuid();co uuid=gen_random_uuid();sp uuid=gen_random_uuid();sv uuid=gen_random_uuid();s uuid=gen_random_uuid();t uuid=gen_random_uuid();d uuid;v uuid;foreign_vehicle uuid;carrier uuid;invoice uuid;expense uuid=gen_random_uuid();allocation uuid=gen_random_uuid();body jsonb;version timestamptz;profile_version timestamptz;actor text;ws jsonb;inv uuid=gen_random_uuid();up uuid=gen_random_uuid();reg uuid=gen_random_uuid();adv uuid=gen_random_uuid();site2 uuid=gen_random_uuid();trip2 uuid=gen_random_uuid();reg2 uuid=gen_random_uuid();versions jsonb;before_version timestamptz;result uuid;
begin
 insert into respectlogistic_customers(id,inn,payload) values(c,substr(floor(random()*9000000000+1000000000)::bigint::text,1,10),'{"name":"PROFIT-TEST-CUSTOMER","legalAddress":"TEST legal address"}');
 insert into respectlogistic_contracts(id,customer_id,kind,number,date,payload) values(co,c,'transport','PF-'||substr(co::text,1,8),current_date,'{}');
 insert into respectlogistic_specifications(id,customer_id,contract_id,number,date,payload) values(sp,c,co,'PF-SP-'||substr(sp::text,1,8),current_date,'{}');
 insert into respectlogistic_services(id,customer_id,contract_id,specification_id,name,unit,price_kopecks) values(sv,c,co,sp,'Вывоз','м³',12200);
 insert into respectlogistic_sites(id,customer_id,contract_id,specification_id,service_id,payload) values(s,c,co,sp,sv,'{"name":"PROFIT-TEST-SITE","loadingAddress":"А","address":"Б","routeKm":"120"}');
 insert into rl_crm_drivers(full_name,pay_rate_km,bonus_pct,tax_pct) values('PROFIT-TEST-DRIVER',80,10,13) returning id into d;
 insert into rl_crm_vehicles(plate,assigned_driver_id) values('PF-'||substr(t::text,1,7),d) returning id into v;
 perform crm_save_trip(jsonb_build_object('id',t,'customer_id',c,'site_id',s,'vehicle_id',v,'driver_id',d,'trip_date',current_date,'trip_number','','loading_address','А','unloading_address','Б','volume',10,'unit','м³','unit_price',122,'service_name','Вывоз','status','sent'),null);

 perform respectlogistic_save_accounting_company('{"name":"ACCOUNTING-TEST","inn":"7707083893","legalAddress":"TEST","bank":"TEST BANK","bik":"044525225","account":"40702810000000000000"}');
 versions=jsonb_build_object(t,(select modified_at from rl_crm_trips where id=t));
 body=jsonb_build_object('id',inv,'kind','invoice','customer_id',c,'site_id',s,'document_date',current_date,'due_date',current_date+7);
 result=respectlogistic_create_accounting_document(body,array[t],versions);
 if result<>inv or (select total from respectlogistic_accounting_documents where id=inv)<>1220 or (select vat from respectlogistic_accounting_documents where id=inv)<>220 then raise exception 'TEST: invoice money/VAT mismatch';end if;
 if respectlogistic_create_accounting_document(body,array[t],versions)<>inv then raise exception 'TEST: retry not idempotent';end if;
 begin
  perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid()),array[t],versions);
  raise exception using message='TEST: duplicate invoice accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 select modified_at into before_version from respectlogistic_accounting_documents where id=inv;
 perform respectlogistic_accounting_action(inv,'issue',before_version,'{}');
 if (select status from rl_crm_trips where id=t)<>'sent' then raise exception 'TEST: invoice completed a trip';end if;
 begin
  perform respectlogistic_accounting_action(inv,'sent',before_version,'{}');
  raise exception using message='TEST: stale action accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  update rl_crm_trips set unit_price=999 where id=t;
  raise exception using message='TEST: invoiced trip silently changed',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  update rl_crm_trips set app_scope=null where id=t;
  raise exception using message='TEST: billed trip moved to another app',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform crm_delete_trips(array[t],jsonb_build_object(t,(select modified_at from rl_crm_trips where id=t)));
  raise exception using message='TEST: invoiced trip deleted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',up,'kind','upd'),array[t],versions);
 select modified_at into version from respectlogistic_accounting_documents where id=up;
 begin
  perform respectlogistic_accounting_action(up,'issue',version,'{"complete_trips":false}');
  raise exception using message='TEST: completion accepted without explicit confirmation',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_accounting_action(up,'issue',version,'{"complete_trips":true}');
 if (select status from rl_crm_trips where id=t)<>'delivered' or (select documents_confirmed from rl_crm_trips where id=t) then raise exception 'TEST: trip completion or driver docs status wrong';end if;
 if not exists(select 1 from rl_crm_payroll_accruals where trip_id=t and active) then raise exception 'TEST: completion did not accrue payroll';end if;
 ws=crm_read_trip_workspace();
 if not(ws->'accounting_documents')@>jsonb_build_array(jsonb_build_object('id',up,'trip_ids',jsonb_build_array(t))) then raise exception 'TEST: closing document missing in trips';end if;
 if not exists(select 1 from jsonb_array_elements(ws->'trips') x where x->>'id'=t::text and (x->>'locked')::boolean) then raise exception 'TEST: billed trip not marked locked';end if;
 versions=jsonb_build_object(t,(select modified_at from rl_crm_trips where id=t));
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',reg,'kind','registry'),array[t],versions);
 if (select number from respectlogistic_accounting_documents where id=reg) not like 'РЕЕСТР-1/%' then raise exception 'TEST: first registry number wrong';end if;
 perform respectlogistic_accounting_action(reg,'cancel',(select modified_at from respectlogistic_accounting_documents where id=reg),'{}');
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid(),'kind','registry'),array[t],versions);
 if (select max(value) from respectlogistic_accounting_counters where owner_id=auth.uid() and kind='registry' and scope=s::text)<>2 then raise exception 'TEST: cancelled registry number reused';end if;
 insert into respectlogistic_sites(id,customer_id,contract_id,specification_id,service_id,payload) values(site2,c,co,sp,sv,'{"name":"ACCOUNTING-SECOND-SITE","loadingAddress":"А","address":"Б","routeKm":"40"}');
 perform crm_save_trip(jsonb_build_object('id',trip2,'customer_id',c,'site_id',site2,'vehicle_id',v,'driver_id',d,'trip_date',current_date,'trip_number','','loading_address','А','unloading_address','Б','volume',2,'unit','м³','unit_price',122,'service_name','Вывоз','status','sent'),null);
 versions=versions||jsonb_build_object(trip2,(select modified_at from rl_crm_trips where id=trip2));
 begin
  perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',gen_random_uuid(),'kind','registry'),array[t,trip2],versions);
  raise exception using message='TEST: mixed-object registry accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',reg2,'kind','registry','site_id',site2),array[trip2],versions);
 if (select number from respectlogistic_accounting_documents where id=reg2) not like 'РЕЕСТР-1/%' then raise exception 'TEST: object registry counter not independent';end if;
 perform respectlogistic_create_accounting_document(body||jsonb_build_object('id',adv,'kind','advance','service_name','Вывоз','amount',200),'{}','{}');
 perform respectlogistic_accounting_action(adv,'issue',(select modified_at from respectlogistic_accounting_documents where id=adv),'{}');
 perform respectlogistic_accounting_action(adv,'payment',(select modified_at from respectlogistic_accounting_documents where id=adv),'{"paid_amount":100}');
 perform respectlogistic_accounting_action(inv,'credit',(select modified_at from respectlogistic_accounting_documents where id=inv),jsonb_build_object('id',gen_random_uuid(),'advance_id',adv,'amount',100));
 perform respectlogistic_accounting_action(inv,'payment',(select modified_at from respectlogistic_accounting_documents where id=inv),'{"paid_amount":50}');
 begin
  perform respectlogistic_accounting_action(inv,'payment',(select modified_at from respectlogistic_accounting_documents where id=inv),'{"paid_amount":1220}');
  raise exception using message='TEST: overpayment after credit accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform respectlogistic_accounting_action(adv,'payment',(select modified_at from respectlogistic_accounting_documents where id=adv),'{"paid_amount":0}');
  raise exception using message='TEST: consumed advance reduced',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform respectlogistic_accounting_action(inv,'cancel',(select modified_at from respectlogistic_accounting_documents where id=inv),'{}');
  raise exception using message='TEST: paid document cancelled',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 ws=respectlogistic_read_profit();
 if not(ws->'accounting_invoices')@>jsonb_build_array(jsonb_build_object('id',inv,'credited',100,'paid_amount',50)) then raise exception 'TEST: calendar missing credited invoice';end if;
 actor=current_setting('request.jwt.claim.sub');perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 ws=respectlogistic_read_accounting();
 if jsonb_array_length(ws->'documents')<>0 or jsonb_array_length(ws->'links')<>0 or jsonb_array_length(ws->'credits')<>0 or ws->'company'<>'{}'::jsonb then raise exception 'TEST: other owner can read accounting';end if;
 begin
  perform respectlogistic_accounting_action(inv,'sent',(select modified_at from respectlogistic_accounting_documents where id=inv),'{}');
  raise exception using message='TEST: other owner modifies invoice',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform set_config('request.jwt.claim.sub',actor,true);
 begin
  insert into respectlogistic_accounting_documents(id,owner_id,kind,customer_id,number,document_date,total,vat,snapshot) values(gen_random_uuid(),auth.uid(),'advance',c,'FORGED',current_date,1,0,'{}');
  raise exception using message='TEST: direct financial insert accepted',errcode='P0002';
 exception when insufficient_privilege then null;end;
end $$;
rollback;
select 'PASS: invoice VAT, idempotency, duplicate/stale guards, immutable trip data, UPD completion/payroll/attachments, independent registry numbering, advance payments/credits/caps, calendar and ownership/RLS. Fixtures rolled back.' as verification;
