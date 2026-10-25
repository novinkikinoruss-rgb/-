begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users limit 1),true);
do $$declare saved jsonb;actor uuid=auth.uid();previous timestamptz;begin
 select modified_at into previous from respectlogistic_company_balance where owner_id=actor;
 saved=respectlogistic_save_company_balance(60000.50,current_date,previous);
 if (saved->>'amount_kopecks')::bigint<>6000050 then raise exception 'TEST: wrong kopecks';end if;
 if respectlogistic_read_company_balance()->'balance' is distinct from saved then raise exception 'TEST: balance not read back';end if;
 begin perform respectlogistic_save_company_balance(1,current_date,null);raise exception using message='TEST: stale edit allowed',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 begin perform respectlogistic_save_company_balance(1.001,current_date,(saved->>'modified_at')::timestamptz);raise exception using message='TEST: extra decimals allowed',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 begin perform respectlogistic_save_company_balance(1,current_date+2,(saved->>'modified_at')::timestamptz);raise exception using message='TEST: future date allowed',errcode='P0002';exception when sqlstate 'P0001' then null;end;
 saved=respectlogistic_save_company_balance(0,current_date,(saved->>'modified_at')::timestamptz);
 if (saved->>'amount_kopecks')::bigint<>0 then raise exception 'TEST: zero balance lost';end if;
 saved=respectlogistic_save_company_balance(-10.25,current_date,(saved->>'modified_at')::timestamptz);
 if (saved->>'amount_kopecks')::bigint<>-1025 then raise exception 'TEST: negative balance lost';end if;
 perform set_config('balance.test_owner',actor::text,true);
end$$;
set local role authenticated;
do $$begin
 if not exists(select 1 from respectlogistic_company_balance where owner_id=auth.uid()) then raise exception 'TEST: owner select blocked';end if;
 begin update respectlogistic_company_balance set amount_kopecks=1;raise exception using message='TEST: direct write allowed',errcode='P0002';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 if exists(select 1 from respectlogistic_company_balance) or respectlogistic_read_company_balance()->'balance'<>'null'::jsonb then raise exception 'TEST: other owner sees balance';end if;
end$$;
set local role anon;
do $$begin
 begin perform respectlogistic_read_company_balance();raise exception using message='TEST: anon RPC allowed',errcode='P0002';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: dated manual balance, cents, zero, negative, conflicts, RLS and role grants. Rolled back.' as verification;
