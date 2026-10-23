create table public.respectlogistic_profit_expenses(
 id uuid primary key,owner_id uuid not null default auth.uid() references auth.users(id),expense_date date not null,
 category text not null check(category in ('contractor','fuel','maintenance','leasing','insurance','tolls','tax','other')),
 amount numeric(16,2) not null check(amount>0),paid_amount numeric(16,2) not null default 0 check(paid_amount>=0 and paid_amount<=amount),
 customer_id uuid references public.respectlogistic_customers(id),site_id uuid references public.respectlogistic_sites(id),service_name text,
 trip_id uuid references public.crm_trips(id),vehicle_id uuid references public.crm_vehicles(id),invoice_id uuid references public.crm_counterparty_invoices(id),notes text not null default '',
 created_at timestamptz not null default now(),modified_at timestamptz not null default clock_timestamp(),deleted_at timestamptz,
 check((category='contractor' and invoice_id is not null and paid_amount=0) or (category<>'contractor' and invoice_id is null))
);
create index profit_expense_owner_date_idx on public.respectlogistic_profit_expenses(owner_id,expense_date) where deleted_at is null;
create index profit_expense_invoice_idx on public.respectlogistic_profit_expenses(invoice_id) where deleted_at is null;
create index profit_expense_trip_idx on public.respectlogistic_profit_expenses(trip_id);
alter table public.respectlogistic_profit_expenses enable row level security;
create policy profit_expense_read on public.respectlogistic_profit_expenses for select to authenticated using(owner_id=(select auth.uid()));
revoke all on public.respectlogistic_profit_expenses from public,anon,authenticated;
grant select on public.respectlogistic_profit_expenses to authenticated;

create function public.respectlogistic_read_profit() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select public.crm_read_trip_workspace()||jsonb_build_object(
 'expenses',coalesce((select jsonb_agg(to_jsonb(e) order by e.expense_date desc,e.created_at desc) from respectlogistic_profit_expenses e where e.owner_id=(select auth.uid()) and e.deleted_at is null),'[]'),
 'invoices',coalesce((select jsonb_agg(to_jsonb(i)) from rl_crm_counterparty_invoices i where i.deleted_at is null),'[]'),
 'accruals',coalesce((select jsonb_agg(to_jsonb(a)) from rl_crm_payroll_accruals a where a.active),'[]'),
 'payments',coalesce((select jsonb_agg(to_jsonb(p)) from rl_crm_payroll_payments p),'[]'),
 'deductions',coalesce((select jsonb_agg(to_jsonb(d)) from rl_crm_payroll_deductions d),'[]')
 )
$$;
create function public.respectlogistic_save_profit_expense(p_expense jsonb,p_expected_modified_at timestamptz default null) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();eid uuid=(p_expense->>'id')::uuid;previous respectlogistic_profit_expenses;
 cid uuid=nullif(p_expense->>'customer_id','')::uuid;sid uuid=nullif(p_expense->>'site_id','')::uuid;tid uuid=nullif(p_expense->>'trip_id','')::uuid;vid uuid=nullif(p_expense->>'vehicle_id','')::uuid;iid uuid=nullif(p_expense->>'invoice_id','')::uuid;
 day date=(p_expense->>'expense_date')::date;kind text=p_expense->>'category';value numeric=(p_expense->>'amount')::numeric;paid numeric=coalesce(nullif(p_expense->>'paid_amount','')::numeric,0);service text=nullif(trim(p_expense->>'service_name'),'');comment text=coalesce(p_expense->>'notes','');
 trip public.crm_trips;site public.respectlogistic_sites;invoice public.crm_counterparty_invoices;allocated numeric;
begin
 if actor is null or eid is null or jsonb_typeof(p_expense) is distinct from 'object' or length(p_expense::text)>20000 then raise exception 'Некорректный расход';end if;
 if day is null or day>current_date or kind not in ('contractor','fuel','maintenance','leasing','insurance','tolls','tax','other') or kind is null then raise exception 'Проверьте дату и категорию расхода';end if;
 if value is null or value<=0 or value::text in ('NaN','Infinity','-Infinity') or value<>round(value,2) or value>99999999999999.99 or paid<0 or paid>value or paid<>round(paid,2) or paid::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте сумму расхода и оплаты';end if;
 if length(comment)>4000 or length(coalesce(service,''))>500 then raise exception 'Примечание или услуга слишком длинные';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-profit',0));
 select * into previous from respectlogistic_profit_expenses where id=eid for update;
 if previous.id is not null then
  if previous.owner_id<>actor or previous.deleted_at is not null then raise exception 'Расход недоступен';end if;
  if p_expected_modified_at is null or p_expected_modified_at is distinct from previous.modified_at then raise exception 'Расход изменён в другой вкладке. Обновите список';end if;
 end if;
 if tid is not null then
  select * into trip from rl_crm_trips where id=tid and deleted_at is null;
  if trip.id is null or trip.status='cancelled' then raise exception 'Рейс недоступен или отменён';end if;
  cid=trip.customer_id;sid=trip.site_id;service=trip.service_name;vid=coalesce(vid,trip.vehicle_id);
 end if;
 if sid is not null then
  select * into site from respectlogistic_sites where id=sid and owner_id=actor;
  if site.id is null or (cid is not null and cid<>site.customer_id) then raise exception 'Объект относится к другому заказчику или недоступен';end if;
  cid=site.customer_id;
  if service is not null and tid is null and not exists(select 1 from respectlogistic_services s where s.id=site.service_id and s.owner_id=actor and s.name=service) then raise exception 'Выберите услугу этого объекта';end if;
 end if;
 if cid is not null and not exists(select 1 from respectlogistic_customers where id=cid and owner_id=actor) then raise exception 'Заказчик недоступен';end if;
 if vid is not null and not exists(select 1 from rl_crm_vehicles where id=vid) then raise exception 'Техника относится к другой CRM или недоступна';end if;
 if kind='contractor' then
  if iid is null or paid<>0 then raise exception 'Выберите счёт исполнителя. Его оплаты подтягиваются из раздела «Контрагенты»';end if;
  select * into invoice from rl_crm_counterparty_invoices where id=iid and deleted_at is null for update;
  if invoice.id is null then raise exception 'Счёт исполнителя недоступен';end if;
  if tid is not null and (trip.carrier_id is null or trip.carrier_id<>invoice.counterparty_id) then raise exception 'Счёт и рейс должны относиться к одному исполнителю';end if;
  select coalesce(sum(amount),0) into allocated from respectlogistic_profit_expenses where invoice_id=iid and owner_id=actor and deleted_at is null and id<>eid;
  if allocated+value>invoice.amount then raise exception 'Распределение превышает сумму счёта. Осталось распределить %',invoice.amount-allocated;end if;
 elsif iid is not null then raise exception 'Счёт исполнителя используется только для расходов на контрагентов';end if;
 if previous.id is null then
  insert into respectlogistic_profit_expenses(id,owner_id,expense_date,category,amount,paid_amount,customer_id,site_id,service_name,trip_id,vehicle_id,invoice_id,notes)
  values(eid,actor,day,kind,value,paid,cid,sid,service,tid,vid,iid,comment);
 else
  update respectlogistic_profit_expenses set expense_date=day,category=kind,amount=value,paid_amount=paid,customer_id=cid,site_id=sid,service_name=service,trip_id=tid,vehicle_id=vid,invoice_id=iid,notes=comment,modified_at=clock_timestamp() where id=eid and owner_id=actor;
 end if;
 return eid;
end $$;
create function public.respectlogistic_delete_profit_expense(p_id uuid,p_expected_modified_at timestamptz) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare e respectlogistic_profit_expenses;
begin
 if auth.uid() is null then raise exception 'Войдите в CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||'-profit',0));
 select * into e from respectlogistic_profit_expenses where id=p_id and owner_id=auth.uid() and deleted_at is null for update;
 if e.id is null then raise exception 'Расход недоступен';end if;
 if p_expected_modified_at is null or p_expected_modified_at is distinct from e.modified_at then raise exception 'Расход изменён в другой вкладке. Обновите список';end if;
 update respectlogistic_profit_expenses set deleted_at=clock_timestamp(),modified_at=clock_timestamp() where id=e.id;
end $$;
revoke all on function public.respectlogistic_read_profit(),public.respectlogistic_save_profit_expense(jsonb,timestamptz),public.respectlogistic_delete_profit_expense(uuid,timestamptz) from public,anon;
grant execute on function public.respectlogistic_read_profit(),public.respectlogistic_save_profit_expense(jsonb,timestamptz),public.respectlogistic_delete_profit_expense(uuid,timestamptz) to authenticated;
notify pgrst,'reload schema';
