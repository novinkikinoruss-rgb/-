-- Запуск только в тестовом Supabase после database/accounting-workflow.sql:
-- psql "$TEST_DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/accounting.integration.sql
-- Все фикстуры и проверки откатываются. Не требует данных реальных пользователей.
begin;
insert into auth.users(id,aud,role,email) values
 ('00000000-0000-4000-8000-000000000071','authenticated','authenticated','crm-accounting-test-1@example.invalid'),
 ('00000000-0000-4000-8000-000000000072','authenticated','authenticated','crm-accounting-test-2@example.invalid');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000071',true);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000071","role":"authenticated"}',true);
set local role authenticated;
do $$
declare c uuid;s uuid;d uuid;t1 uuid;t2 uuid;i uuid;u uuid;a uuid;f uuid;v numeric;n integer;
begin
 insert into public.crm_customers(name) values('Тестовый заказчик бухгалтерии') returning id into c;
 insert into public.crm_sites(customer_id,name,loading_address,unloading_address,route_km) values(c,'Тестовый объект','Погрузка','Разгрузка',100) returning id into s;
 insert into public.crm_drivers(full_name,bonus_pct,tax_pct) values('Тестовый водитель',10,30) returning id into d;
 insert into public.crm_trips(customer_id,site_id,driver_id,trip_number,trip_date,status,service_name,volume,unit_price) values(c,s,d,'ТЕСТ-1','2026-10-10','delivered','Услуга 1',2.5,1200) returning id into t1;
 insert into public.crm_trips(customer_id,site_id,driver_id,trip_number,trip_date,status,service_name,volume,unit_price) values(c,s,d,'ТЕСТ-2','2026-10-11','delivered','Услуга 2',3,2000) returning id into t2;
 select id into a from public.crm_payroll_accruals where trip_id=t1;
 if a is null or not exists(select 1 from public.crm_payroll_accruals where id=a and base=7000 and bonus=700 and tax=2310) then raise exception 'TEST: неверное начисление при завершении рейса';end if;
 i=public.crm_create_invoice_from_trips(c,s,array[t1,t2],'ТЕСТ-СЧЁТ','2026-10-12','{"name":"Тестовый исполнитель","inn":"0000000000"}'::jsonb);
 select amount into v from public.crm_invoices where id=i;
 if v<>9000 then raise exception 'TEST: сумма счёта должна быть 9000';end if;
 select count(*) into n from public.crm_invoice_lines where invoice_id=i;
 if n<>2 then raise exception 'TEST: счёт должен содержать два рейса';end if;
 select count(*) into n from public.crm_accounting_document_trips l join public.crm_accounting_documents doc on doc.id=l.document_id where doc.invoice_id=i and doc.kind='register';
 if n<>2 then raise exception 'TEST: реестр не прикреплён к двум рейсам';end if;
 begin
  perform public.crm_create_invoice_from_trips(c,s,array[t1],'ТЕСТ-ДУБЛЬ','2026-10-12','{"name":"Тест","inn":"0000000000"}'::jsonb);
  raise exception using message='TEST: повторный счёт не заблокирован',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 u=public.crm_create_upd_from_invoice(i,'ТЕСТ-УПД','2026-10-13');
 select count(*) into n from public.crm_accounting_document_trips where document_id=u;
 if n<>2 then raise exception 'TEST: УПД должен содержать оба рейса счёта';end if;
 begin
  update public.crm_trips set volume=5 where id=t1;
  raise exception using message='TEST: выпущенный счёт не защищает рейс',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform public.crm_record_invoice_payment(i,3000,'2026-10-15');
 begin
  perform public.crm_record_invoice_payment(i,7000,'2026-10-16');
  raise exception using message='TEST: переплата счёта не заблокирована',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 perform public.crm_pay_driver_accruals(array[a],'salary',3000,'2026-10-16');
 perform public.crm_pay_driver_accruals(array[a],'tax',500,'2026-10-16');
 select sum(amount) into v from public.crm_payroll_payments where accrual_id=a and kind='salary';
 if v<>3000 then raise exception 'TEST: частичная выплата потеряна';end if;
 begin
  perform public.crm_pay_driver_accruals(array[a],'salary',5000,'2026-10-17');
  raise exception using message='TEST: переплата зарплаты не заблокирована',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 insert into public.crm_driver_fines(driver_id,amount,reason,fine_date) values(d,500,'Тестовый штраф','2026-10-12') returning id into f;
 perform public.crm_apply_driver_fines(array[a],array[f],'2026-10-17');
 select sum(amount) into v from public.crm_payroll_deductions where fine_id=f;
 if v<>500 then raise exception 'TEST: штраф не удержан';end if;
 begin
  perform public.crm_apply_driver_fines(array[a],array[f],'2026-10-17');
  raise exception using message='TEST: штраф удержан повторно',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 begin
  perform public.crm_pay_driver_accruals(array[a],'salary',4300,'2026-10-17');
  raise exception using message='TEST: выплата не учла удержанный штраф',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 update public.crm_sites set route_km=200 where id=s;
 update public.crm_drivers set bonus_pct=20 where id=d;
 perform public.crm_prepare_payroll(array[t1,t2]);
 if not exists(select 1 from public.crm_payroll_accruals where id=a and base=7000 and bonus=700 and tax=2310) then raise exception 'TEST: прошлое начисление изменилось';end if;
 select count(*) into n from public.crm_payroll_accruals where trip_id in (t1,t2);
 if n<>2 then raise exception 'TEST: повторная обработка создала дубли начислений';end if;
 -- RLS: другой вошедший пользователь не видит и не изменяет документы первого.
 perform set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000072',true);
 perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000072","role":"authenticated"}',true);
 if exists(select 1 from public.crm_invoices where id=i) or exists(select 1 from public.crm_invoice_lines where invoice_id=i) then raise exception 'TEST: нарушена изоляция документов';end if;
 begin
  perform public.crm_create_upd_from_invoice(i,'ЧУЖОЙ','2026-10-17');
  raise exception using message='TEST: доступ к чужому счёту не заблокирован',errcode='P0002';
 exception when sqlstate 'P0001' then null;end;
 raise notice 'Все интеграционные проверки бухгалтерии прошли';
end $$;
rollback;
