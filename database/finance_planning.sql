create table public.respectlogistic_profit_plans(
 id uuid primary key,owner_id uuid not null default auth.uid() references auth.users(id),customer_id uuid not null references public.respectlogistic_customers(id),site_id uuid references public.respectlogistic_sites(id),service_name text,
 date_from date not null,date_to date not null check(date_to>=date_from),revenue numeric(16,2) not null check(revenue>=0),cost numeric(16,2) not null check(cost>=0),notes text not null default '',modified_at timestamptz not null default clock_timestamp(),deleted_at timestamptz,check(revenue>0 or cost>0)
);
create table public.respectlogistic_finance_events(
 id uuid primary key,owner_id uuid not null default auth.uid() references auth.users(id),title text not null check(length(trim(title))>0),kind text not null check(kind in ('incoming','outgoing','tax')),
 due_date date not null,amount numeric(16,2) not null check(amount>0),paid_amount numeric(16,2) not null default 0 check(paid_amount>=0 and paid_amount<=amount),customer_id uuid references public.respectlogistic_customers(id),site_id uuid references public.respectlogistic_sites(id),service_name text,notes text not null default '',modified_at timestamptz not null default clock_timestamp(),deleted_at timestamptz
);
create table public.respectlogistic_finance_due_dates(
 owner_id uuid not null default auth.uid() references auth.users(id),source_kind text not null check(source_kind in ('invoice','expense','salary','payroll_tax')),source_id uuid not null,due_date date not null,primary key(owner_id,source_kind,source_id)
);
alter table public.respectlogistic_profit_plans enable row level security;
alter table public.respectlogistic_finance_events enable row level security;
alter table public.respectlogistic_finance_due_dates enable row level security;
create policy profit_plan_owner on public.respectlogistic_profit_plans for select to authenticated using(owner_id=(select auth.uid()));
create policy finance_event_owner on public.respectlogistic_finance_events for select to authenticated using(owner_id=(select auth.uid()));
create policy finance_due_owner on public.respectlogistic_finance_due_dates for select to authenticated using(owner_id=(select auth.uid()));
revoke all on public.respectlogistic_profit_plans,public.respectlogistic_finance_events,public.respectlogistic_finance_due_dates from public,anon,authenticated;
grant select on public.respectlogistic_profit_plans,public.respectlogistic_finance_events,public.respectlogistic_finance_due_dates to authenticated;
create index profit_plan_owner_period on public.respectlogistic_profit_plans(owner_id,date_from,date_to) where deleted_at is null;
create index finance_event_owner_due on public.respectlogistic_finance_events(owner_id,due_date) where deleted_at is null;

create function public.respectlogistic_save_finance_record(p_kind text,p_record jsonb,p_expected_modified_at timestamptz default null,p_delete boolean default false) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;cid uuid=nullif(p_record->>'customer_id','')::uuid;sid uuid=nullif(p_record->>'site_id','')::uuid;service text=nullif(trim(p_record->>'service_name'),'');comment text=coalesce(p_record->>'notes','');previous jsonb;site public.respectlogistic_sites;
 date1 date;date2 date;value1 numeric;value2 numeric;title_value text;kind_value text;
begin
 if actor is null or rid is null or p_kind not in ('plan','event') or p_kind is null or jsonb_typeof(p_record) is distinct from 'object' or length(p_record::text)>20000 then raise exception 'Некорректная запись';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-finance-planning',0));
 if p_kind='plan' then select to_jsonb(x) into previous from respectlogistic_profit_plans x where x.id=rid for update;else select to_jsonb(x) into previous from respectlogistic_finance_events x where x.id=rid for update;end if;
 if previous is not null then
  if (previous->>'owner_id')::uuid<>actor or previous->>'deleted_at' is not null then raise exception 'Запись недоступна';end if;
  if p_expected_modified_at is null or p_expected_modified_at is distinct from (previous->>'modified_at')::timestamptz then raise exception 'Запись изменена в другой вкладке. Обновите данные';end if;
 end if;
 if p_delete then
  if previous is null then raise exception 'Запись недоступна';end if;
  if p_kind='plan' then update respectlogistic_profit_plans set deleted_at=clock_timestamp(),modified_at=clock_timestamp() where id=rid and owner_id=actor;else update respectlogistic_finance_events set deleted_at=clock_timestamp(),modified_at=clock_timestamp() where id=rid and owner_id=actor;end if;
  return rid;
 end if;
 if sid is not null then select * into site from respectlogistic_sites where id=sid and owner_id=actor;if site.id is null or (cid is not null and cid<>site.customer_id) then raise exception 'Объект недоступен или относится к другому заказчику';end if;cid=site.customer_id;end if;
 if cid is not null and not exists(select 1 from respectlogistic_customers where id=cid and owner_id=actor) then raise exception 'Заказчик недоступен';end if;
 if length(comment)>4000 or length(coalesce(service,''))>500 then raise exception 'Текст слишком длинный';end if;
 if p_kind='plan' then
  date1=(p_record->>'date_from')::date;date2=(p_record->>'date_to')::date;value1=(p_record->>'revenue')::numeric;value2=(p_record->>'cost')::numeric;
  if cid is null or date1 is null or date2 is null or date2<date1 then raise exception 'Укажите заказчика и период плана';end if;
  if value1 is null or value2 is null or value1<0 or value2<0 or value1+value2<=0 or greatest(value1,value2)>99999999999999.99 or value1::text in ('NaN','Infinity','-Infinity') or value2::text in ('NaN','Infinity','-Infinity') or value1<>round(value1,2) or value2<>round(value2,2) then raise exception 'Проверьте выручку и расходы плана';end if;
  if previous is null then insert into respectlogistic_profit_plans(id,owner_id,customer_id,site_id,service_name,date_from,date_to,revenue,cost,notes) values(rid,actor,cid,sid,service,date1,date2,value1,value2,comment);
  else update respectlogistic_profit_plans set customer_id=cid,site_id=sid,service_name=service,date_from=date1,date_to=date2,revenue=value1,cost=value2,notes=comment,modified_at=clock_timestamp() where id=rid and owner_id=actor;end if;
 else
  date1=(p_record->>'due_date')::date;value1=(p_record->>'amount')::numeric;value2=coalesce(nullif(p_record->>'paid_amount','')::numeric,0);title_value=trim(coalesce(p_record->>'title',''));kind_value=p_record->>'kind';
  if date1 is null or title_value='' or length(title_value)>250 or kind_value is null or kind_value not in ('incoming','outgoing','tax') then raise exception 'Укажите название, вид и срок платежа';end if;
  if value1 is null or value1<=0 or value2<0 or value2>value1 or value1>99999999999999.99 or value1::text in ('NaN','Infinity','-Infinity') or value2::text in ('NaN','Infinity','-Infinity') or value1<>round(value1,2) or value2<>round(value2,2) then raise exception 'Проверьте сумму платежа и оплаты';end if;
  if previous is null then insert into respectlogistic_finance_events(id,owner_id,title,kind,due_date,amount,paid_amount,customer_id,site_id,service_name,notes) values(rid,actor,title_value,kind_value,date1,value1,value2,cid,sid,service,comment);
  else update respectlogistic_finance_events set title=title_value,kind=kind_value,due_date=date1,amount=value1,paid_amount=value2,customer_id=cid,site_id=sid,service_name=service,notes=comment,modified_at=clock_timestamp() where id=rid and owner_id=actor;end if;
 end if;
 return rid;
end$$;
create function public.respectlogistic_set_finance_due_date(p_source_kind text,p_source_id uuid,p_due_date date) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if auth.uid() is null or p_source_kind not in ('invoice','expense','salary','payroll_tax') or p_source_kind is null then raise exception 'Некорректный источник платежа';end if;
 if p_source_kind='invoice' then
  if not exists(select 1 from rl_crm_counterparty_invoices where id=p_source_id and deleted_at is null) then raise exception 'Счёт недоступен';end if;
 elsif p_source_kind='expense' then
  if not exists(select 1 from respectlogistic_profit_expenses where id=p_source_id and owner_id=auth.uid() and deleted_at is null and invoice_id is null) then raise exception 'Расход недоступен';end if;
 else
  if not exists(select 1 from rl_crm_payroll_accruals where id=p_source_id) then raise exception 'Начисление недоступно';end if;
 end if;
 if p_due_date is null then delete from respectlogistic_finance_due_dates where owner_id=auth.uid() and source_kind=p_source_kind and source_id=p_source_id;
 else insert into respectlogistic_finance_due_dates(owner_id,source_kind,source_id,due_date) values(auth.uid(),p_source_kind,p_source_id,p_due_date) on conflict(owner_id,source_kind,source_id) do update set due_date=excluded.due_date;end if;
end$$;

alter table public.crm_trips add column distance_km_snapshot numeric check(distance_km_snapshot>=0 and distance_km_snapshot::text not in ('NaN','Infinity','-Infinity'));
create or replace view public.rl_crm_trips with(security_invoker=true) as select t.* from public.crm_trips t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
create function public.respectlogistic_capture_trip_distance() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare raw text;
begin
 if new.app_scope is distinct from 'respectlogistic' or new.status<>'delivered' or new.distance_km_snapshot is not null then return new;end if;
 if tg_op='UPDATE' then if old.status='delivered' then return new;end if;end if;
 select s.payload->>'routeKm' into raw from respectlogistic_sites s where s.id=new.site_id and s.owner_id=new.owner_id;
 if raw ~ '^[0-9]+([.][0-9]+)?$' then new.distance_km_snapshot=raw::numeric;end if;
 return new;
end$$;
create trigger respectlogistic_trip_distance before insert or update of status on public.crm_trips for each row execute function public.respectlogistic_capture_trip_distance();

create or replace function public.respectlogistic_read_profit() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select public.crm_read_trip_workspace()||jsonb_build_object(
 'settings',coalesce((select to_jsonb(s) from respectlogistic_profit_settings s where s.owner_id=(select auth.uid())),'{"tax_regime":"osno","vat_rate":22,"prices_include_vat":null}'::jsonb),
 'invoice_vat',coalesce((select jsonb_agg(to_jsonb(v)) from respectlogistic_invoice_vat v),'[]'),
 'expenses',coalesce((select jsonb_agg(to_jsonb(e) order by e.expense_date desc,e.created_at desc) from respectlogistic_profit_expenses e where e.owner_id=(select auth.uid()) and e.deleted_at is null),'[]'),
 'invoices',coalesce((select jsonb_agg(to_jsonb(i)) from rl_crm_counterparty_invoices i where i.deleted_at is null),'[]'),
 'accruals',coalesce((select jsonb_agg(to_jsonb(a)) from rl_crm_payroll_accruals a where a.active),'[]'),
 'payments',coalesce((select jsonb_agg(to_jsonb(p)) from rl_crm_payroll_payments p),'[]'),
 'deductions',coalesce((select jsonb_agg(to_jsonb(d)) from rl_crm_payroll_deductions d),'[]'),
 'plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.date_from desc,p.id) from respectlogistic_profit_plans p where p.owner_id=(select auth.uid()) and p.deleted_at is null),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.due_date,e.id) from respectlogistic_finance_events e where e.owner_id=(select auth.uid()) and e.deleted_at is null),'[]'),
 'due_dates',coalesce((select jsonb_agg(to_jsonb(d)) from respectlogistic_finance_due_dates d where d.owner_id=(select auth.uid())),'[]'))
$$;
revoke all on function public.respectlogistic_save_finance_record(text,jsonb,timestamptz,boolean),public.respectlogistic_set_finance_due_date(text,uuid,date),public.respectlogistic_capture_trip_distance() from public,anon,authenticated;
grant execute on function public.respectlogistic_save_finance_record(text,jsonb,timestamptz,boolean),public.respectlogistic_set_finance_due_date(text,uuid,date),public.respectlogistic_capture_trip_distance() to authenticated;
notify pgrst,'reload schema';
