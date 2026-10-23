begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by created_at limit 1),true) is not null as identity_ready;
set local role authenticated;
do $$
declare c uuid=gen_random_uuid();co uuid=gen_random_uuid();sp uuid=gen_random_uuid();sv uuid=gen_random_uuid();s uuid=gen_random_uuid();t uuid=gen_random_uuid();d uuid;v uuid;foreign_vehicle uuid;carrier uuid;invoice uuid;expense uuid=gen_random_uuid();allocation uuid=gen_random_uuid();body jsonb;version timestamptz;profile_version timestamptz;actor text;ws jsonb;
begin
 insert into respectlogistic_customers(id,inn,payload) values(c,substr(floor(random()*9000000000+1000000000)::bigint::text,1,10),'{"name":"PROFIT-TEST-CUSTOMER"}');
 insert into respectlogistic_contracts(id,customer_id,kind,number,date,payload) values(co,c,'transport','PF-'||substr(co::text,1,8),current_date,'{}');
 insert into respectlogistic_specifications(id,customer_id,contract_id,number,date,payload) values(sp,c,co,'PF-SP-'||substr(sp::text,1,8),current_date,'{}');
 insert into respectlogistic_services(id,customer_id,contract_id,specification_id,name,unit,price_kopecks) values(sv,c,co,sp,'Вывоз','м³',12200);
 insert into respectlogistic_sites(id,customer_id,contract_id,specification_id,service_id,payload) values(s,c,co,sp,sv,'{"name":"PROFIT-TEST-SITE","loadingAddress":"А","address":"Б","routeKm":"120"}');
 insert into rl_crm_drivers(full_name,pay_rate_km,bonus_pct,tax_pct) values('PROFIT-TEST-DRIVER',80,10,13) returning id into d;
 insert into rl_crm_vehicles(plate,assigned_driver_id) values('PF-'||substr(t::text,1,7),d) returning id into v;
 perform crm_save_trip(jsonb_build_object('id',t,'customer_id',c,'site_id',s,'vehicle_id',v,'driver_id',d,'trip_date',current_date,'trip_number','','loading_address','А','unloading_address','Б','volume',10,'unit','м³','unit_price',122,'service_name','Вывоз','status','delivered'),null);
 perform respectlogistic_save_profit_settings(22,true);
 if (respectlogistic_read_profit()->'settings'->>'prices_include_vat')::boolean is distinct from true then raise exception 'TEST: VAT settings not saved';end if;
 body=jsonb_build_object('id',expense,'expense_date',current_date,'category','fuel','amount',122,'paid_amount',122,'trip_id',t,'vat_rate',22,'input_vat_confirmed',true,'notes','PROFIT-TEST-FUEL');
 perform respectlogistic_save_profit_expense(body,null);
 if not exists(select 1 from respectlogistic_profit_expenses where id=expense and customer_id=c and site_id=s and vehicle_id=v and vat_rate=22 and input_vat_confirmed) then raise exception 'TEST: expense/VAT/context missing';end if;
 select modified_at into version from respectlogistic_profit_expenses where id=expense;
 perform respectlogistic_save_profit_expense(body||'{"amount":244,"paid_amount":200}',version);
 begin
  perform respectlogistic_save_profit_expense(body,version);
  raise exception using message='TEST: stale expense edit accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 insert into crm_vehicles(plate) values('PF-LEGACY-'||substr(t::text,1,7)) returning id into foreign_vehicle;
 begin
  perform respectlogistic_save_profit_expense(body||jsonb_build_object('id',gen_random_uuid(),'trip_id','','vehicle_id',foreign_vehicle),null);
  raise exception using message='TEST: foreign app vehicle cost accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 insert into rl_crm_carriers(name) values('PROFIT-TEST-CARRIER') returning id into carrier;
 insert into rl_crm_counterparty_invoices(counterparty_id,invoice_number,invoice_date,amount,paid_amount) values(carrier,'PF-INVOICE',current_date,610,305) returning id into invoice;
 body=jsonb_build_object('id',allocation,'expense_date',current_date,'category','contractor','amount',366,'paid_amount',0,'invoice_id',invoice,'customer_id',c,'site_id',s,'service_name','Вывоз','vat_rate',22,'input_vat_confirmed',true);
 perform respectlogistic_save_profit_expense(body,null);
 if not exists(select 1 from respectlogistic_invoice_vat where invoice_id=invoice and owner_id=auth.uid() and vat_rate=22 and input_vat_confirmed) then raise exception 'TEST: invoice VAT missing';end if;
 begin
  perform respectlogistic_save_profit_expense(body||jsonb_build_object('id',gen_random_uuid(),'amount',300),null);
  raise exception using message='TEST: overallocated invoice accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  update rl_crm_counterparty_invoices set amount=300 where id=invoice;
  raise exception using message='TEST: allocated invoice silently shrunk',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform respectlogistic_save_profit_expense(body||jsonb_build_object('id',gen_random_uuid(),'amount',1,'vat_rate',20,'input_vat_confirmed',false),null);
  raise exception using message='TEST: stale invoice VAT profile overwritten',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 ws=respectlogistic_read_profit();
 if not (ws->'expenses')@>jsonb_build_array(jsonb_build_object('id',expense)) or not (ws->'invoices')@>jsonb_build_array(jsonb_build_object('id',invoice)) then raise exception 'TEST: profit workspace missing records';end if;

 if (select distance_km_snapshot from rl_crm_trips where id=t) is distinct from 120::numeric then raise exception 'TEST: delivered trip distance snapshot missing';end if;
 update respectlogistic_sites set payload=payload||'{"routeKm":"999"}' where id=s;
 if (select distance_km_snapshot from rl_crm_trips where id=t) is distinct from 120::numeric then raise exception 'TEST: object edit changed trip distance snapshot';end if;
 body=jsonb_build_object('id',expense,'customer_id',c,'site_id',s,'date_from',current_date,'date_to',current_date+30,'revenue',10000,'cost',5000);
 perform respectlogistic_save_finance_record('plan',body,null,false);
 select modified_at into version from respectlogistic_profit_plans where id=expense;
 perform respectlogistic_save_finance_record('plan',body||'{"cost":6000}',version,false);
 begin
  perform respectlogistic_save_finance_record('plan',body,version,false);
  raise exception using message='TEST: stale plan accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 body=jsonb_build_object('id',allocation,'title','TEST-TAX','kind','tax','due_date',current_date+5,'amount',220,'paid_amount',20,'customer_id',c);
 perform respectlogistic_save_finance_record('event',body,null,false);
 begin
  perform respectlogistic_save_finance_record('event',body||'{"paid_amount":221}',(select modified_at from respectlogistic_finance_events where id=allocation),false);
  raise exception using message='TEST: overpaid calendar event accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_set_finance_due_date('invoice',invoice,current_date+7);
 if not exists(select 1 from respectlogistic_finance_due_dates where source_id=invoice and due_date=current_date+7) then raise exception 'TEST: due date missing';end if;
 if (select paid_amount from rl_crm_counterparty_invoices where id=invoice) is distinct from 305::numeric then raise exception 'TEST: calendar changed invoice payment';end if;
 if (select amount from respectlogistic_profit_expenses where id=expense) is distinct from 244::numeric then raise exception 'TEST: planning duplicated actual cost';end if;
 ws=respectlogistic_read_profit();
 if not(ws->'plans')@>jsonb_build_array(jsonb_build_object('id',expense)) or not(ws->'events')@>jsonb_build_array(jsonb_build_object('id',allocation)) then raise exception 'TEST: planning RPC missing data';end if;

 actor=current_setting('request.jwt.claim.sub');perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 ws=respectlogistic_read_profit();
 if (ws->'plans')@>jsonb_build_array(jsonb_build_object('id',expense)) or (ws->'events')@>jsonb_build_array(jsonb_build_object('id',allocation)) or (ws->'due_dates')@>jsonb_build_array(jsonb_build_object('source_id',invoice)) then raise exception 'TEST: other owner reads planning';end if;
 begin
  perform respectlogistic_set_finance_due_date('invoice',invoice,current_date);
  raise exception using message='TEST: other owner modifies due date',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform respectlogistic_save_finance_record('plan',jsonb_build_object('id',expense),null,true);
  raise exception using message='TEST: other owner deletes plan',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 if (ws->'expenses')@>jsonb_build_array(jsonb_build_object('id',expense)) or (ws->'invoice_vat')@>jsonb_build_array(jsonb_build_object('invoice_id',invoice)) then raise exception 'TEST: other owner can read financial data';end if;
 begin
  perform respectlogistic_save_profit_expense(jsonb_build_object('id',gen_random_uuid(),'expense_date',current_date,'category','fuel','amount',1,'customer_id',c),null);
  raise exception using message='TEST: other owner can write customer cost',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform set_config('request.jwt.claim.sub',actor,true);
 select modified_at into version from respectlogistic_profit_expenses where id=allocation;
 perform respectlogistic_delete_profit_expense(allocation,version);
 if (respectlogistic_read_profit()->'expenses')@>jsonb_build_array(jsonb_build_object('id',allocation)) then raise exception 'TEST: deleted allocation still reported';end if;
 if not exists(select 1 from rl_crm_counterparty_invoices where id=invoice and amount=610 and paid_amount=305) then raise exception 'TEST: deleting allocation changed invoice/payments';end if;
end $$;
rollback;
select 'PASS: expense CRUD; derived trip/customer/object context; VAT22 settings/input tax; stale edits; legacy/owner isolation; invoice allocation cap; guarded invoice changes; stale VAT profile; soft deletion preserves invoice payments. All fixtures rolled back.' as verification;
