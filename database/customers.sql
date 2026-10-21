-- Respectlogistic customer module. Shared Supabase, isolated respectlogistic_* tables.
-- No modification of the original crm_* tables and no service-role functions.
begin;
create table public.respectlogistic_customers (
 id uuid primary key, owner_id uuid not null default auth.uid() references auth.users(id),
 inn text not null check(inn ~ '^\d{10}$'), payload jsonb not null check(jsonb_typeof(payload)='object'),
 created_at timestamptz not null default now(), unique(owner_id,id),unique(owner_id,inn)
);
create table public.respectlogistic_contract_counters (
 owner_id uuid not null default auth.uid() references auth.users(id),kind text not null check(kind in ('transport','supply')),
 year integer not null, value integer not null check(value>0),primary key(owner_id,kind,year)
);
create table public.respectlogistic_contracts (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,
 kind text not null check(kind in ('transport','supply')),number text not null,date date not null,end_date date,
 payload jsonb not null, unique(owner_id,id),unique(owner_id,customer_id,id),unique(owner_id,number),
 foreign key(owner_id,customer_id) references public.respectlogistic_customers(owner_id,id),
 check(end_date is null or end_date>=date)
);
create table public.respectlogistic_specifications (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,contract_id uuid not null,
 number text not null,date date not null,payload jsonb not null,
 unique(owner_id,id),unique(owner_id,customer_id,contract_id,id),unique(owner_id,number),
 foreign key(owner_id,customer_id,contract_id) references public.respectlogistic_contracts(owner_id,customer_id,id)
);
create table public.respectlogistic_services (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,contract_id uuid not null,specification_id uuid not null,
 name text not null check(length(trim(name))>0),unit text not null check(length(trim(unit))>0),price_kopecks bigint not null check(price_kopecks between 1 and 999999999999),
 unique(owner_id,customer_id,contract_id,specification_id,id),
 foreign key(owner_id,customer_id,contract_id,specification_id) references public.respectlogistic_specifications(owner_id,customer_id,contract_id,id)
);
create table public.respectlogistic_sites (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,contract_id uuid not null,specification_id uuid not null,service_id uuid not null,
 payload jsonb not null,unique(owner_id,id),
 foreign key(owner_id,customer_id,contract_id,specification_id,service_id) references public.respectlogistic_services(owner_id,customer_id,contract_id,specification_id,id)
);
create table public.respectlogistic_documents (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,entity_id uuid not null,
 folder text not null check(folder in ('contracts','specifications','sites')),title text not null,snapshot jsonb not null,
 created_at timestamptz not null default now(),foreign key(owner_id,customer_id) references public.respectlogistic_customers(owner_id,id)
);
create table public.respectlogistic_activity (
 id uuid primary key,owner_id uuid not null default auth.uid(),customer_id uuid not null,text text not null,created_at timestamptz not null default now(),
 foreign key(owner_id,customer_id) references public.respectlogistic_customers(owner_id,id)
);
create index on public.respectlogistic_contracts(owner_id,customer_id);
create index on public.respectlogistic_specifications(owner_id,customer_id,contract_id);
create index on public.respectlogistic_services(owner_id,customer_id,contract_id,specification_id);
create index on public.respectlogistic_sites(owner_id,customer_id,contract_id,specification_id,service_id);
create index on public.respectlogistic_documents(owner_id,customer_id);
create index on public.respectlogistic_activity(owner_id,customer_id,created_at desc);
do $$declare relation text;begin
 foreach relation in array array['respectlogistic_customers','respectlogistic_contract_counters','respectlogistic_contracts','respectlogistic_specifications','respectlogistic_services','respectlogistic_sites','respectlogistic_documents','respectlogistic_activity'] loop
  execute format('alter table public.%I enable row level security',relation);
  execute format('create policy own_data on public.%I for all to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id)',relation);
  execute format('revoke all on public.%I from anon',relation);
  execute format('grant select,insert,update on public.%I to authenticated',relation);
 end loop;
end$$;

create function public.respectlogistic_read_workspace() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select jsonb_build_object(
 'revision',(select count(*) from respectlogistic_activity),
 'customers',coalesce((select jsonb_agg(c.payload||jsonb_build_object('id',c.id,'inn',c.inn,'createdAt',c.created_at) order by c.created_at) from respectlogistic_customers c),'[]'),
 'contracts',coalesce((select jsonb_agg(c.payload||jsonb_build_object('id',c.id,'customerId',c.customer_id,'number',c.number,'date',c.date,'endDate',coalesce(c.end_date::text,'')) order by c.date,c.number) from respectlogistic_contracts c),'[]'),
 'specifications',coalesce((select jsonb_agg(s.payload||jsonb_build_object('id',s.id,'customerId',s.customer_id,'contractId',s.contract_id,'number',s.number,'date',s.date,'services',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'unit',v.unit,'priceKopecks',v.price_kopecks) order by v.id) from respectlogistic_services v where v.specification_id=s.id),'[]')) order by s.date,s.number) from respectlogistic_specifications s),'[]'),
 'sites',coalesce((select jsonb_agg(s.payload||jsonb_build_object('id',s.id,'customerId',s.customer_id,'contractId',s.contract_id,'specificationId',s.specification_id,'serviceId',s.service_id) order by s.id) from respectlogistic_sites s),'[]'),
 'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'customerId',d.customer_id,'entityId',d.entity_id,'folder',d.folder,'title',d.title,'snapshot',d.snapshot,'createdAt',d.created_at) order by d.created_at,d.id) from respectlogistic_documents d),'[]'),
 'activity',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'customerId',a.customer_id,'text',a.text,'createdAt',a.created_at) order by a.created_at desc,a.id) from respectlogistic_activity a),'[]'))
$$;
create function public.respectlogistic_customer_action(command jsonb) returns jsonb language plpgsql security invoker set search_path=public,pg_temp as $$
declare
 actor uuid:=auth.uid(); action text:=command->>'type'; request_id uuid:=(command->>'id')::uuid;
 customer_id_value uuid; contract_id_value uuid; specification_id_value uuid; service_id_value uuid;
 d jsonb:=command->'data'; c respectlogistic_contracts; s respectlogistic_specifications;
 n integer; yr integer; doc_number text; event_text text; folder_value text; doc_title text;
 doc_snapshot jsonb; customer_snapshot jsonb; service jsonb; inn_value text; checksum integer; weights integer[]:=array[2,4,10,3,5,9,4,6,8];
begin
 if actor is null then raise exception 'Необходим вход';end if;
 if jsonb_typeof(d) is distinct from 'object' or request_id is null then raise exception 'Некорректное действие';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,0));
 if exists(select 1 from respectlogistic_activity a where a.id=request_id and a.owner_id=actor) then return respectlogistic_read_workspace();end if;
 if exists(select 1 from jsonb_each_text(d) t where length(t.value)>100000) then raise exception 'Слишком большой запрос';end if;
 customer_id_value:=case when action='customer.create' then request_id else (command->>'customerId')::uuid end;
 if action in ('customer.create','customer.update') then
  inn_value:=d->>'inn';
  if inn_value is null or inn_value !~ '^\d{10}$' then raise exception 'Проверьте ИНН организации';end if;
  checksum:=0;for n in 1..9 loop checksum:=checksum+substring(inn_value,n,1)::integer*weights[n];end loop;
  if checksum%11%10<>substring(inn_value,10,1)::integer then raise exception 'Некорректная контрольная сумма ИНН';end if;
  if coalesce(trim(d->>'name'),'')='' then raise exception 'Заполните название компании';end if;
  if coalesce(d->>'kpp','')<>'' and (d->>'kpp')!~'^\d{9}$' then raise exception 'Проверьте КПП';end if;
  if coalesce(d->>'ogrn','')<>'' and (d->>'ogrn')!~'^\d{13}$' then raise exception 'Проверьте ОГРН';end if;
  if coalesce(d->>'bik','')<>'' and (d->>'bik')!~'^\d{9}$' then raise exception 'Проверьте БИК';end if;
  if (coalesce(d->>'account','')<>'' and (d->>'account')!~'^\d{20}$') or (coalesce(d->>'correspondent','')<>'' and (d->>'correspondent')!~'^\d{20}$') then raise exception 'Проверьте банковские счета';end if;
  if action='customer.create' then
   insert into respectlogistic_customers(id,owner_id,inn,payload) values(request_id,actor,inn_value,d);
   event_text:='Создана карточка заказчика';
  else
   update respectlogistic_customers set inn=inn_value,payload=d where id=customer_id_value and owner_id=actor;
   if not found then raise exception 'Заказчик не найден';end if;
   event_text:='Карточка заказчика обновлена';
  end if;
 else
  select payload into customer_snapshot from respectlogistic_customers where id=customer_id_value and owner_id=actor;
  if not found then raise exception 'Заказчик не найден';end if;
  if action='contract.create' then
   if (d->>'kind') not in ('transport','supply') or d->>'kind' is null or d->>'date' is null then raise exception 'Выберите тип и дату договора';end if;
   yr:=extract(year from (d->>'date')::date);
   insert into respectlogistic_contract_counters(owner_id,kind,year,value) values(actor,d->>'kind',yr,1)
    on conflict(owner_id,kind,year) do update set value=respectlogistic_contract_counters.value+1 returning value into n;
   doc_number:=(case when d->>'kind'='transport' then 'ТР' else 'ПС' end)||'-'||yr||'-'||lpad(n::text,greatest(4,length(n::text)),'0');
   insert into respectlogistic_contracts(id,owner_id,customer_id,kind,number,date,end_date,payload) values(request_id,actor,customer_id_value,d->>'kind',doc_number,(d->>'date')::date,nullif(d->>'endDate','')::date,d);
   doc_snapshot:=d||jsonb_build_object('number',doc_number,'customer',customer_snapshot);folder_value:='contracts';doc_title:='Договор '||doc_number;event_text:='Создан договор '||doc_number;
  elsif action='specification.create' then
   contract_id_value:=(d->>'contractId')::uuid;
   select * into c from respectlogistic_contracts where id=contract_id_value and customer_id=customer_id_value and owner_id=actor;
   if not found then raise exception 'Выберите договор этого заказчика';end if;
   if d->>'date' is null or (d->>'date')::date<c.date or (d->>'date')::date>c.end_date then raise exception 'Дата спецификации должна входить в период договора';end if;
   if jsonb_typeof(d->'services') is distinct from 'array' then raise exception 'Добавьте услуги';end if;
   if jsonb_array_length(d->'services') not between 1 and 100 then raise exception 'Добавьте от 1 до 100 услуг';end if;
   select count(*)+1 into n from respectlogistic_specifications where contract_id=contract_id_value and owner_id=actor;
   doc_number:=c.number||'/СП-'||lpad(n::text,greatest(2,length(n::text)),'0');
   insert into respectlogistic_specifications(id,owner_id,customer_id,contract_id,number,date,payload) values(request_id,actor,customer_id_value,contract_id_value,doc_number,(d->>'date')::date,d-'services');
   for service in select value from jsonb_array_elements(d->'services') loop
    if coalesce(service->>'priceKopecks','')!~'^\d+$' then raise exception 'Цена должна быть целым числом копеек';end if;
    insert into respectlogistic_services(id,owner_id,customer_id,contract_id,specification_id,name,unit,price_kopecks) values((service->>'id')::uuid,actor,customer_id_value,contract_id_value,request_id,service->>'name',service->>'unit',(service->>'priceKopecks')::bigint);
   end loop;
   folder_value:='specifications';doc_title:='Спецификация '||doc_number;event_text:='Создана спецификация '||doc_number;
   doc_snapshot:=d||jsonb_build_object('number',doc_number,'customer',customer_snapshot,'contract',c.payload||jsonb_build_object('number',c.number));
  elsif action='site.create' then
   contract_id_value:=(d->>'contractId')::uuid;specification_id_value:=(d->>'specificationId')::uuid;service_id_value:=(d->>'serviceId')::uuid;
   if coalesce(trim(d->>'name'),'')='' or coalesce(trim(d->>'address'),'')='' or coalesce(trim(d->>'foreman'),'')='' then raise exception 'Заполните название, адрес и прораба';end if;
   if coalesce(d->>'routeKm','')<>'' and ((d->>'routeKm')!~'^\d+(\.\d{1,3})?$' or (d->>'routeKm')::numeric>100000) then raise exception 'Проверьте расстояние в одну сторону';end if;
   insert into respectlogistic_sites(id,owner_id,customer_id,contract_id,specification_id,service_id,payload) values(request_id,actor,customer_id_value,contract_id_value,specification_id_value,service_id_value,d);
   folder_value:='sites';doc_title:='Карточка объекта «'||(d->>'name')||'»';event_text:='Создан объект «'||(d->>'name')||'»';
   doc_snapshot:=d;
  else raise exception 'Неизвестное действие';end if;
  insert into respectlogistic_documents(id,owner_id,customer_id,entity_id,folder,title,snapshot) values(request_id,actor,customer_id_value,request_id,folder_value,doc_title,doc_snapshot);
 end if;
 insert into respectlogistic_activity(id,owner_id,customer_id,text) values(request_id,actor,customer_id_value,event_text);
 return respectlogistic_read_workspace();
end$$;
revoke all on function public.respectlogistic_read_workspace() from public,anon;
revoke all on function public.respectlogistic_customer_action(jsonb) from public,anon;
grant execute on function public.respectlogistic_read_workspace(),public.respectlogistic_customer_action(jsonb) to authenticated;
commit;
