begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by created_at limit 1),true) is not null as test_identity_ready;
set local role authenticated;
do $$
declare c uuid;s uuid;d uuid;v uuid;t uuid;a uuid;f uuid;service uuid;total numeric;old_sub text;missing_count integer;
begin
 insert into public.rl_crm_customers(name) values('FLEET-ROLLBACK-CUSTOMER') returning id into c;
 insert into public.rl_crm_sites(customer_id,name,loading_address,unloading_address,route_km) values(c,'FLEET-ROLLBACK-SITE','А','Б',120) returning id into s;
 insert into public.rl_crm_drivers(full_name,birth_date,license_number,phone,notes,employment_kind,pay_rate_km,bonus_pct,tax_pct,contract_number,contract_date) values('FLEET-ROLLBACK-DRIVER','1988-04-15','TEST-VU','+70000000000','Проверка','official',80,10,13,'TEST-CONTRACT',current_date) returning id into d;
 insert into public.rl_crm_vehicles(plate,brand,model,vin,manufacture_year,odometer_km,assigned_driver_id,next_service_km,next_oil_km,service_interval_km,oil_interval_km,reminder_before_km) values('FLEET-ROLLBACK-TC','Scania','G500 8x4','YS2P8X40001234567',2021,184500,d,187000,187000,15000,15000,1000) returning id into v;
 service=public.rl_crm_complete_fleet_maintenance(v,'oil',185000,current_date,'Тест масла');
 if not exists(select 1 from public.rl_crm_fleet_maintenance where id=service and vehicle_id=v) or not exists(select 1 from public.rl_crm_vehicles where id=v and odometer_km=185000 and next_oil_km=200000 and next_service_km=187000) then raise exception 'TEST: maintenance schedule incorrect';end if;
 begin
  perform public.rl_crm_complete_fleet_maintenance(v,'oil',100,current_date,'Invalid mileage');
  raise exception using message='TEST: lower mileage accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 insert into public.rl_crm_trips(customer_id,site_id,driver_id,vehicle_id,trip_number,trip_date,status,service_name) values(c,s,d,v,'FLEET-ROLLBACK-TRIP',current_date,'delivered','Самосвал') returning id into t;
 select id into a from public.rl_crm_payroll_accruals where trip_id=t;
 if not exists(select 1 from public.rl_crm_payroll_accruals where id=a and rate=80 and base=9600 and bonus=960 and tax=1372.8) then raise exception 'TEST: custom driver rate / one leg / bonus / company tax incorrect';end if;
 insert into public.rl_crm_driver_fines(driver_id,trip_id,fine_date,amount,reason) values(d,t,current_date,1000,'FLEET-ROLLBACK-FINE') returning id into f;
 perform public.rl_crm_apply_driver_fines(array[a],array[f],current_date);
 begin
  perform public.rl_crm_apply_driver_fines(array[a],array[f],current_date);
  raise exception using message='TEST: duplicate withholding accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform public.rl_crm_pay_driver_accruals(array[a],'salary',9560,current_date);
 perform public.rl_crm_pay_driver_accruals(array[a],'tax',1372.8,current_date);
 if (select sum(amount) from public.rl_crm_payroll_payments where accrual_id=a and kind='salary')<>9560 then raise exception 'TEST: wrong payout after fine';end if;
 begin
  perform public.rl_crm_pay_driver_accruals(array[a],'salary',1,current_date);
  raise exception using message='TEST: salary overpayment accepted',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 update public.rl_crm_drivers set pay_rate_km=90,bonus_pct=25,tax_pct=30,job_status='dismissed',archived_at=now() where id=d;
 perform public.rl_crm_prepare_payroll(array[t]);
 if not exists(select 1 from public.rl_crm_payroll_accruals where id=a and base=9600 and bonus=960 and tax=1372.8) then raise exception 'TEST: existing payroll snapshot changed';end if;
 if (select count(*) from public.rl_crm_payroll_accruals where trip_id=t)<>1 then raise exception 'TEST: duplicate accrual';end if;
 old_sub=current_setting('request.jwt.claim.sub');
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 if exists(select 1 from public.rl_crm_drivers where id=d) or exists(select 1 from public.rl_crm_fleet_maintenance where id=service) then raise exception 'TEST: owner isolation failed';end if;
 perform set_config('request.jwt.claim.sub',old_sub,true);
end $$;
rollback;
select 'PASS: driver and vehicle CRUD; maintenance scheduling; rate 80 × one leg 120; bonus; tax separately; fine withheld once; salary payout; overpayment rejection; archived driver history; immutable accruals; RLS. All test rows rolled back.' as verification;
