begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by created_at limit 1),true);
do $$declare did uuid;other_driver uuid;vid uuid;cid uuid;sid uuid;tid uuid;token text;other_token text;stamp timestamptz;stage text;original_owner text;begin
 original_owner=current_setting('request.jwt.claim.sub');
 insert into rl_crm_customers(name) values('DRIVER-TRIP-ROLLBACK') returning id into cid;
 insert into rl_crm_sites(customer_id,name,loading_address,unloading_address,route_km) values(cid,'ROLLBACK OBJECT','Load street','Unload street',100) returning id into sid;
 insert into rl_crm_drivers(full_name,pay_rate_km,bonus_pct,tax_pct) values('DRIVER-TRIP-ROLLBACK',80,10,13) returning id into did;
 insert into rl_crm_drivers(full_name) values('OTHER-DRIVER-ROLLBACK') returning id into other_driver;
 insert into rl_crm_vehicles(plate,assigned_driver_id,odometer_km) values('TRIP-DRIVER-TEST',did,100) returning id into vid;
 insert into rl_crm_trips(customer_id,site_id,driver_id,vehicle_id,trip_number,trip_date,status,service_name,loading_address,unloading_address) values(cid,sid,did,vid,'DRIVER-ROLLBACK',current_date,'assigned','Delivery','Load street','Unload street') returning id,modified_at into tid,stamp;
 perform respectlogistic_driver_access(did,'password','rollback-'||did,'temporary-password-123');
 token=respectlogistic_driver_login('rollback-'||did,'temporary-password-123')->>'token';
 perform respectlogistic_driver_password(token,'permanent-password-456');
 perform respectlogistic_driver_access(other_driver,'password','rollback-'||other_driver,'temporary-password-123');
 other_token=respectlogistic_driver_login('rollback-'||other_driver,'temporary-password-123')->>'token';
 perform respectlogistic_driver_password(other_token,'permanent-password-456');
 -- Mirror production driver API: no company JWT present.
 perform set_config('request.jwt.claim.sub','',true);
 if jsonb_array_length(respectlogistic_driver_trips(token)->'driver_trips')<>1 or jsonb_array_length(respectlogistic_driver_trips(other_token)->'driver_trips')<>0 then raise exception 'TEST: trip data isolation';end if;
 begin perform respectlogistic_driver_trip_stage(other_token,tid,'accepted',stamp);raise exception using message='TEST: foreign driver edited trip',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 begin perform respectlogistic_driver_trip_stage(token,tid,'accepted',stamp);raise exception using message='TEST: work started without duty',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 perform respectlogistic_duty_action(token,vid,'start',100);
 begin perform respectlogistic_driver_trip_stage(token,tid,'completed',stamp);raise exception using message='TEST: skipped all stages',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 foreach stage in array array['accepted','loading','on_route','unloading','completed'] loop
  select modified_at into stamp from crm_trips where id=tid;
  perform respectlogistic_driver_trip_stage(token,tid,stage,stamp);
 end loop;
 perform respectlogistic_driver_trip_stage(token,tid,'completed',stamp);
 if nullif(current_setting('request.jwt.claim.sub',true),'') is not null then raise exception 'TEST: owner subject not restored';end if;
 if (select count(*) from crm_payroll_accruals where trip_id=tid)<>1 or not exists(select 1 from crm_payroll_accruals where trip_id=tid and base=8000 and bonus=800 and tax=1144) then raise exception 'TEST: payroll not generated exactly once';end if;
 if not exists(select 1 from crm_trips where id=tid and status='delivered' and not documents_confirmed) then raise exception 'TEST: documents automatically confirmed';end if;
 if (select count(*) from respectlogistic_driver_trip_events where trip_id=tid)<>5 then raise exception 'TEST: stage history duplicated';end if;
 perform set_config('request.jwt.claim.sub',original_owner,true);
end$$;
rollback;
select 'PASS: no owner JWT; own trips only; active duty required; ordered stages; existing payroll exactly once; driver completion does not confirm documents. Rolled back.' as verification;
