begin;
insert into auth.users(id,aud,role,email) values('00000000-0000-4000-8000-000000000081','authenticated','authenticated','respectlogistic-test-1@example.invalid'),('00000000-0000-4000-8000-000000000082','authenticated','authenticated','respectlogistic-test-2@example.invalid');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
set local role authenticated;
do $$declare result jsonb;begin
 result:=public.respectlogistic_customer_action('{"type":"customer.create","id":"10000000-0000-4000-8000-000000000001","data":{"name":"Тест","inn":"7700000009"}}');
 if jsonb_array_length(result->'customers')<>1 then raise exception 'Customer not created';end if;
 perform public.respectlogistic_customer_action('{"type":"contract.create","id":"20000000-0000-4000-8000-000000000001","customerId":"10000000-0000-4000-8000-000000000001","data":{"kind":"transport","date":"2026-10-01","endDate":"2026-12-31","notes":""}}');
 result:=public.respectlogistic_customer_action('{"type":"contract.create","id":"20000000-0000-4000-8000-000000000002","customerId":"10000000-0000-4000-8000-000000000001","data":{"kind":"transport","date":"2026-10-01","endDate":"2026-12-31","notes":""}}');
 if result->'contracts'->1->>'number'<>'ТР-2026-0002' then raise exception 'Incorrect contract number';end if;
 perform public.respectlogistic_customer_action('{"type":"specification.create","id":"30000000-0000-4000-8000-000000000001","customerId":"10000000-0000-4000-8000-000000000001","data":{"contractId":"20000000-0000-4000-8000-000000000001","date":"2026-10-02","services":[{"id":"40000000-0000-4000-8000-000000000001","name":"Песок","unit":"м³","priceKopecks":65000}]}}');
 perform public.respectlogistic_customer_action('{"type":"site.create","id":"50000000-0000-4000-8000-000000000001","customerId":"10000000-0000-4000-8000-000000000001","data":{"contractId":"20000000-0000-4000-8000-000000000001","specificationId":"30000000-0000-4000-8000-000000000001","serviceId":"40000000-0000-4000-8000-000000000001","name":"Объект","address":"Адрес","foreman":"Прораб","routeKm":"45.5"}}');
 result:=public.respectlogistic_customer_action('{"type":"site.create","id":"50000000-0000-4000-8000-000000000001","customerId":"10000000-0000-4000-8000-000000000001","data":{}}');
 if jsonb_array_length(result->'sites')<>1 or jsonb_array_length(result->'documents')<>4 then raise exception 'Duplicate command or missing documents';end if;
 begin
  perform public.respectlogistic_customer_action('{"type":"site.create","id":"50000000-0000-4000-8000-000000000002","customerId":"10000000-0000-4000-8000-000000000001","data":{"contractId":"20000000-0000-4000-8000-000000000002","specificationId":"30000000-0000-4000-8000-000000000001","serviceId":"40000000-0000-4000-8000-000000000001","name":"Ошибочный","address":"Адрес","foreman":"Прораб"}}');
  raise exception 'TEST missing relation guard';
 exception when foreign_key_violation then null;end;
 begin
  perform public.respectlogistic_customer_action('{"type":"customer.create","id":"10000000-0000-4000-8000-000000000002","data":{"name":"Дубль","inn":"7700000009"}}');
  raise exception 'TEST missing duplicate guard';
 exception when unique_violation then null;end;
 if (public.respectlogistic_read_workspace()->>'revision')::integer<>5 then raise exception 'Failed action must not create activity';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000082',true);
do $$declare result jsonb;begin
 result:=public.respectlogistic_read_workspace();
 if jsonb_array_length(result->'customers')<>0 or jsonb_array_length(result->'documents')<>0 then raise exception 'RLS leak';end if;
 begin
  perform public.respectlogistic_customer_action('{"type":"contract.create","id":"20000000-0000-4000-8000-000000000003","customerId":"10000000-0000-4000-8000-000000000001","data":{"kind":"supply","date":"2026-10-01"}}');
  raise exception 'TEST ownership guard missing';
 exception when others then if sqlerrm='TEST ownership guard missing' then raise;end if;end;
 begin
  insert into public.respectlogistic_customers(id,owner_id,inn,payload) values(gen_random_uuid(),'00000000-0000-4000-8000-000000000081','7800000002','{}');
  raise exception 'TEST ownership reassignment allowed';
 exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
