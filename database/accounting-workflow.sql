-- Дополнение к существующей схеме crm_*. Не удаляет счета, оплаты и рейсы.
-- Устанавливать одной транзакцией после резервного копирования и проверки на тестовой базе.
begin;
alter table public.crm_invoices add column if not exists seller_snapshot jsonb not null default '{}'::jsonb;
alter table public.crm_invoices add column if not exists buyer_snapshot jsonb not null default '{}'::jsonb;
create table if not exists public.crm_invoice_lines (
 id uuid primary key default gen_random_uuid(), owner_id uuid not null default auth.uid(),
 invoice_id uuid not null references public.crm_invoices(id),
 trip_id uuid not null unique references public.crm_trips(id),
 site_id uuid not null references public.crm_sites(id),
 trip_number text not null, trip_date date not null, service_name text not null,
 volume numeric not null check(volume>0 and volume::text not in ('NaN','Infinity','-Infinity')),
 unit_price numeric not null check(unit_price>=0 and unit_price::text not in ('NaN','Infinity','-Infinity')),
 amount numeric(16,2) not null check(amount=round(volume*unit_price,2)),
 created_at timestamptz not null default now()
);
create table if not exists public.crm_accounting_documents (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),
 invoice_id uuid not null references public.crm_invoices(id),customer_id uuid not null references public.crm_customers(id),
 kind text not null check(kind in ('register','upd')), document_number text not null check(length(trim(document_number))>0),
 document_date date not null,amount numeric(16,2) not null check(amount>0),created_at timestamptz not null default now(),
 unique(invoice_id,kind),unique(owner_id,kind,document_number)
);
create table if not exists public.crm_accounting_document_trips (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),
 document_id uuid not null references public.crm_accounting_documents(id),trip_id uuid not null references public.crm_trips(id),
 unique(document_id,trip_id)
);
create table if not exists public.crm_payroll_accruals (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),
 trip_id uuid not null unique references public.crm_trips(id),driver_id uuid not null references public.crm_drivers(id),
 customer_id uuid not null references public.crm_customers(id),site_id uuid not null references public.crm_sites(id),accrual_date date not null,
 distance_km numeric not null check(distance_km>=0 and distance_km::text not in ('NaN','Infinity','-Infinity')),
 rate numeric not null default 70 check(rate=70),bonus_pct numeric not null check(bonus_pct>=0 and bonus_pct::text not in ('NaN','Infinity','-Infinity')),tax_pct numeric not null check(tax_pct>=0 and tax_pct::text not in ('NaN','Infinity','-Infinity')),
 base numeric(16,2) not null,bonus numeric(16,2) not null,tax numeric(16,2) not null,
 active boolean not null default true,created_at timestamptz not null default now(),
 check(base=round(distance_km*70,2)),check(bonus=round(base*bonus_pct/100,2)),check(tax=round((base+bonus)*tax_pct/100,2))
);
create table if not exists public.crm_payroll_payments (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),
 accrual_id uuid not null references public.crm_payroll_accruals(id),kind text not null check(kind in ('salary','tax')),
 amount numeric(16,2) not null check(amount>0),payment_date date not null,created_at timestamptz not null default now()
);
create table if not exists public.crm_payroll_deductions (
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid(),
 accrual_id uuid not null references public.crm_payroll_accruals(id),fine_id uuid not null references public.crm_driver_fines(id),
 amount numeric(16,2) not null check(amount>0),deduction_date date not null,created_at timestamptz not null default now(),
 unique(accrual_id,fine_id)
);
create index if not exists crm_payroll_deductions_fine_idx on public.crm_payroll_deductions(fine_id);
create index if not exists crm_payroll_deductions_accrual_idx on public.crm_payroll_deductions(accrual_id);
create index if not exists crm_invoice_lines_owner_invoice_idx on public.crm_invoice_lines(owner_id,invoice_id);
create index if not exists crm_accounting_documents_owner_idx on public.crm_accounting_documents(owner_id,document_date);
create index if not exists crm_accounting_document_trips_trip_idx on public.crm_accounting_document_trips(trip_id);
create index if not exists crm_payroll_accruals_owner_date_idx on public.crm_payroll_accruals(owner_id,accrual_date);
create index if not exists crm_payroll_payments_accrual_idx on public.crm_payroll_payments(accrual_id,kind);
do $$ declare t text; begin
 foreach t in array array['crm_invoice_lines','crm_accounting_documents','crm_accounting_document_trips','crm_payroll_accruals','crm_payroll_payments','crm_payroll_deductions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists accounting_owner on public.%I',t);
  execute format('create policy accounting_owner on public.%I for all to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()))',t);
  execute format('revoke all on public.%I from anon,authenticated',t);
  execute format('grant select,insert on public.%I to authenticated',t);
 end loop;
end $$;
-- UPDATE нужен триггеру начислений в контексте пользователя. Снимок защищён отдельным триггером.
grant update(active) on public.crm_payroll_accruals to authenticated;

create or replace function public.crm_check_accounting_links() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare i public.crm_invoices; d public.crm_accounting_documents; a public.crm_payroll_accruals; t public.crm_trips; o public.crm_orders; s public.crm_sites; f public.crm_driver_fines;
begin
 if auth.uid() is null or new.owner_id<>auth.uid() then raise exception 'Требуется авторизация владельца'; end if;
 if tg_table_name='crm_invoice_lines' then
  select * into i from public.crm_invoices where id=new.invoice_id and owner_id=auth.uid() and deleted_at is null;
  select * into t from public.crm_trips where id=new.trip_id and owner_id=auth.uid() and deleted_at is null;
  if t.order_id is not null then select * into o from public.crm_orders where id=t.order_id and owner_id=auth.uid(); end if;
  if i.id is null or t.id is null or t.status<>'delivered' or coalesce(t.customer_id,o.customer_id) is distinct from i.customer_id or coalesce(t.site_id,o.site_id) is distinct from new.site_id then raise exception 'Счёт и выполненный рейс должны принадлежать одному заказчику и объекту'; end if;
 elsif tg_table_name='crm_accounting_documents' then
  select * into i from public.crm_invoices where id=new.invoice_id and owner_id=auth.uid() and deleted_at is null;
  if i.id is null or i.customer_id<>new.customer_id or i.amount<>new.amount then raise exception 'Документ не соответствует счёту'; end if;
 elsif tg_table_name='crm_accounting_document_trips' then
  select * into d from public.crm_accounting_documents where id=new.document_id and owner_id=auth.uid();
  if d.id is null or not exists(select 1 from public.crm_invoice_lines where invoice_id=d.invoice_id and trip_id=new.trip_id and owner_id=auth.uid()) then raise exception 'Рейс отсутствует в счёте документа'; end if;
 elsif tg_table_name='crm_payroll_payments' then
  select * into a from public.crm_payroll_accruals where id=new.accrual_id and owner_id=auth.uid() and active for update;
  if a.id is null or new.payment_date<a.accrual_date then raise exception 'Нельзя оплатить отсутствующее начисление или указать дату до рейса'; end if;
  if (select coalesce(sum(amount),0) from public.crm_payroll_payments where accrual_id=a.id and kind=new.kind)+new.amount>(case when new.kind='salary' then a.base+a.bonus-(select coalesce(sum(amount),0) from public.crm_payroll_deductions where accrual_id=a.id) else a.tax end) then raise exception 'Сумма оплаты превышает остаток'; end if;
 elsif tg_table_name='crm_payroll_deductions' then
  select * into a from public.crm_payroll_accruals where id=new.accrual_id and owner_id=auth.uid() and active for update;
  select * into f from public.crm_driver_fines where id=new.fine_id and owner_id=auth.uid() and deleted_at is null for update;
  if a.id is null or f.id is null or f.paid or f.driver_id<>a.driver_id or new.deduction_date<a.accrual_date or new.deduction_date<f.fine_date then raise exception 'Проверьте водителя, дату, начисление и неоплаченный штраф';end if;
  if (select coalesce(sum(amount),0) from public.crm_payroll_deductions where fine_id=f.id)+new.amount>f.amount then raise exception 'Этот штраф уже удержан';end if;
  if (select coalesce(sum(amount),0) from public.crm_payroll_deductions where accrual_id=a.id)+new.amount+(select coalesce(sum(amount),0) from public.crm_payroll_payments where accrual_id=a.id and kind='salary')>a.base+a.bonus then raise exception 'Удержание превышает остаток зарплаты';end if;
 elsif tg_table_name='crm_payroll_accruals' then
  select * into t from public.crm_trips where id=new.trip_id and owner_id=auth.uid();
  if not new.active then
   if t.id is null or (t.status='delivered' and t.deleted_at is null) or exists(select 1 from public.crm_payroll_payments where accrual_id=new.id) or exists(select 1 from public.crm_payroll_deductions where accrual_id=new.id) then raise exception 'Нельзя скрыть действующее, оплаченное или удержанное начисление';end if;
   return new;
  end if;
  if t.order_id is not null then select * into o from public.crm_orders where id=t.order_id and owner_id=auth.uid(); end if;
  select * into s from public.crm_sites where id=new.site_id and owner_id=auth.uid();
  if t.id is null or t.status<>'delivered' or t.driver_id is distinct from new.driver_id or coalesce(t.customer_id,o.customer_id) is distinct from new.customer_id or coalesce(t.site_id,o.site_id) is distinct from new.site_id or s.customer_id is distinct from new.customer_id or not exists(select 1 from public.crm_drivers where id=new.driver_id and owner_id=auth.uid()) then raise exception 'Начисление должно соответствовать выполненному рейсу и его владельцу'; end if;
 end if;
 return new;
end $$;
do $$ declare t text;begin
 foreach t in array array['crm_invoice_lines','crm_accounting_documents','crm_accounting_document_trips','crm_payroll_accruals','crm_payroll_payments','crm_payroll_deductions'] loop
  execute format('drop trigger if exists accounting_links on public.%I',t);
  execute format('create trigger accounting_links before insert or update on public.%I for each row execute function public.crm_check_accounting_links()',t);
 end loop;
end $$;

create or replace function public.crm_create_invoice_from_trips(p_customer_id uuid,p_site_id uuid,p_trip_ids uuid[],p_number text,p_date date,p_seller jsonb) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_invoice uuid;v_register uuid;v_total numeric;v_count integer;v_buyer jsonb;
begin
 if auth.uid() is null then raise exception 'Требуется авторизация'; end if;
 if coalesce(cardinality(p_trip_ids),0)=0 or nullif(trim(p_number),'') is null or p_date is null or coalesce(trim(p_seller->>'name'),'')='' or coalesce(trim(p_seller->>'inn'),'')='' then raise exception 'Укажите рейсы, номер, дату и реквизиты исполнителя'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||':invoice:'||trim(p_number),0));
 if exists(select 1 from public.crm_invoices where owner_id=auth.uid() and invoice_number=trim(p_number)) then raise exception 'Счёт с таким номером уже существует'; end if;
 if not exists(select 1 from public.crm_sites where id=p_site_id and customer_id=p_customer_id and owner_id=auth.uid() and deleted_at is null) then raise exception 'Объект не принадлежит заказчику'; end if;
 select jsonb_build_object('id',id,'name',name,'inn',inn,'kpp',kpp,'legal_address',legal_address) into v_buyer from public.crm_customers where id=p_customer_id and owner_id=auth.uid() and deleted_at is null and not is_archived;
 if v_buyer is null then raise exception 'Заказчик недоступен'; end if;
 perform id from public.crm_trips where id=any(p_trip_ids) and owner_id=auth.uid() order by id for update;
 select count(*),sum(round(t.volume*t.unit_price,2)) into v_count,v_total from public.crm_trips t left join public.crm_orders o on o.id=t.order_id and o.owner_id=auth.uid()
 where t.id=any(p_trip_ids) and t.owner_id=auth.uid() and t.deleted_at is null and t.status='delivered' and coalesce(t.customer_id,o.customer_id)=p_customer_id and coalesce(t.site_id,o.site_id)=p_site_id and t.trip_date is not null and t.trip_date<=p_date and t.volume>0 and t.volume::text not in ('NaN','Infinity','-Infinity') and t.unit_price>=0 and t.unit_price::text not in ('NaN','Infinity','-Infinity');
 if v_count<>cardinality(p_trip_ids) or coalesce(v_total,0)<=0 then raise exception 'Выберите выполненные рейсы одного заказчика и объекта с корректными ценами и датами'; end if;
 if exists(select 1 from public.crm_invoice_lines where trip_id=any(p_trip_ids)) or exists(select 1 from public.crm_invoices where trip_id=any(p_trip_ids) and deleted_at is null) then raise exception 'Один из рейсов уже включён в счёт'; end if;
 insert into public.crm_invoices(customer_id,invoice_number,invoice_date,amount,seller_snapshot,buyer_snapshot) values(p_customer_id,trim(p_number),p_date,v_total,p_seller,v_buyer) returning id into v_invoice;
 insert into public.crm_invoice_lines(invoice_id,trip_id,site_id,trip_number,trip_date,service_name,volume,unit_price,amount)
 select v_invoice,t.id,p_site_id,t.trip_number,t.trip_date,coalesce(t.service_name,'Транспортные услуги'),t.volume,t.unit_price,round(t.volume*t.unit_price,2) from public.crm_trips t where t.id=any(p_trip_ids) and t.owner_id=auth.uid();
 insert into public.crm_accounting_documents(invoice_id,customer_id,kind,document_number,document_date,amount) values(v_invoice,p_customer_id,'register','РЕЕСТР-'||trim(p_number),p_date,v_total) returning id into v_register;
 insert into public.crm_accounting_document_trips(document_id,trip_id) select v_register,trip_id from public.crm_invoice_lines where invoice_id=v_invoice;
 return v_invoice;
end $$;

create or replace function public.crm_create_upd_from_invoice(p_invoice_id uuid,p_number text,p_date date) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare i public.crm_invoices;v_document uuid;
begin
 if auth.uid() is null or nullif(trim(p_number),'') is null or p_date is null then raise exception 'Укажите номер и дату УПД'; end if;
 select * into i from public.crm_invoices where id=p_invoice_id and owner_id=auth.uid() and deleted_at is null for update;
 if i.id is null then raise exception 'Счёт недоступен'; end if;
 if not exists(select 1 from public.crm_invoice_lines where invoice_id=i.id) then raise exception 'У счёта нет сохранённых строк рейсов'; end if;
 if exists(select 1 from public.crm_invoice_lines where invoice_id=i.id and trip_date>p_date) then raise exception 'Дата УПД не может предшествовать выполненным услугам'; end if;
 insert into public.crm_accounting_documents(invoice_id,customer_id,kind,document_number,document_date,amount) values(i.id,i.customer_id,'upd',trim(p_number),p_date,i.amount) returning id into v_document;
 insert into public.crm_accounting_document_trips(document_id,trip_id) select v_document,trip_id from public.crm_invoice_lines where invoice_id=i.id;
 return v_document;
end $$;

create or replace function public.crm_record_invoice_payment(p_invoice_id uuid,p_amount numeric,p_date date) returns uuid language plpgsql security invoker set search_path=public,pg_temp as $$
declare i public.crm_invoices;v_id uuid;
begin
 select * into i from public.crm_invoices where id=p_invoice_id and owner_id=auth.uid() and deleted_at is null for update;
 if i.id is null or p_date is null or p_date<i.invoice_date or p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,2) then raise exception 'Проверьте счёт, дату и положительную сумму оплаты до копеек'; end if;
 if (select coalesce(sum(amount),0) from public.crm_invoice_payments where invoice_id=i.id)+p_amount>i.amount then raise exception 'Оплата превышает остаток по счёту'; end if;
 insert into public.crm_invoice_payments(invoice_id,amount,payment_date) values(i.id,p_amount,p_date) returning id into v_id;
 return v_id;
end $$;

create or replace function public.crm_sync_payroll() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.crm_sites;d public.crm_drivers;o public.crm_orders;v_base numeric;v_bonus numeric;v_customer uuid;v_site uuid;
begin
 if new.status<>'delivered' or new.deleted_at is not null then
  if exists(select 1 from public.crm_payroll_payments p join public.crm_payroll_accruals a on a.id=p.accrual_id where a.trip_id=new.id) or exists(select 1 from public.crm_payroll_deductions p join public.crm_payroll_accruals a on a.id=p.accrual_id where a.trip_id=new.id) then raise exception 'Рейс уже оплачен: сначала нужна бухгалтерская корректировка'; end if;
  update public.crm_payroll_accruals set active=false where trip_id=new.id and owner_id=new.owner_id;return new;
 end if;
 if new.order_id is not null then select * into o from public.crm_orders where id=new.order_id and owner_id=new.owner_id;end if;
 v_site=coalesce(new.site_id,o.site_id);v_customer=coalesce(new.customer_id,o.customer_id);
 select * into s from public.crm_sites where id=v_site and owner_id=new.owner_id and deleted_at is null;
 select * into d from public.crm_drivers where id=new.driver_id and owner_id=new.owner_id;
 if s.id is null or s.customer_id is distinct from v_customer or d.id is null or s.route_km is null or new.trip_date is null then raise exception 'Для завершения рейса укажите водителя, заказчика, дату, объект и расстояние в одну сторону'; end if;
 if exists(select 1 from public.crm_payroll_accruals where trip_id=new.id) then
  if exists(select 1 from public.crm_payroll_accruals where trip_id=new.id and (driver_id<>new.driver_id or site_id<>v_site or customer_id<>v_customer or accrual_date<>new.trip_date)) then raise exception 'По рейсу уже зафиксировано начисление; требуется бухгалтерская корректировка'; end if;
  update public.crm_payroll_accruals set active=true where trip_id=new.id and owner_id=new.owner_id;return new;
 end if;
 v_base=round(s.route_km*70,2);v_bonus=round(v_base*d.bonus_pct/100,2);
 insert into public.crm_payroll_accruals(owner_id,trip_id,driver_id,customer_id,site_id,accrual_date,distance_km,bonus_pct,tax_pct,base,bonus,tax)
 values(new.owner_id,new.id,d.id,v_customer,v_site,new.trip_date,s.route_km,d.bonus_pct,d.tax_pct,v_base,v_bonus,round((v_base+v_bonus)*d.tax_pct/100,2));
 return new;
end $$;
drop trigger if exists crm_trip_payroll on public.crm_trips;
create trigger crm_trip_payroll after insert or update of status,deleted_at,driver_id,site_id,customer_id,trip_date on public.crm_trips for each row execute function public.crm_sync_payroll();

create or replace function public.crm_guard_billed_trip() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.crm_invoice_lines where trip_id=old.id) then
  if tg_op='DELETE' then raise exception 'Рейс включён в счёт и не может быть удалён'; end if;
  if (new.customer_id,new.site_id,new.order_id,new.trip_date,new.status,new.deleted_at,new.service_name,new.volume,new.unit_price) is distinct from (old.customer_id,old.site_id,old.order_id,old.trip_date,old.status,old.deleted_at,old.service_name,old.volume,old.unit_price) then raise exception 'Рейс включён в счёт: финансовые данные зафиксированы'; end if;
 end if;
 if tg_op='DELETE' and exists(select 1 from public.crm_payroll_accruals where trip_id=old.id) then raise exception 'У рейса есть начисление зарплаты; используйте архивирование';end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
drop trigger if exists crm_guard_billed_trip on public.crm_trips;
create trigger crm_guard_billed_trip before update or delete on public.crm_trips for each row execute function public.crm_guard_billed_trip();

create or replace function public.crm_pay_driver_accruals(p_accrual_ids uuid[],p_kind text,p_amount numeric,p_date date) returns numeric language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.crm_payroll_accruals;v_due numeric;v_remaining numeric=p_amount;v_total numeric=0;v_paid numeric;v_driver uuid;v_count integer=0;
begin
 if auth.uid() is null or p_kind not in ('salary','tax') or p_date is null or p_amount is null or p_amount<=0 or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<>round(p_amount,2) or coalesce(cardinality(p_accrual_ids),0)=0 then raise exception 'Проверьте начисления, вид, дату и сумму оплаты';end if;
 -- Единый порядок блокировок предотвращает взаимные блокировки при пересекающихся выплатах.
 perform id from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() order by id for update;
 for a in select * from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
  if v_driver is not null and v_driver<>a.driver_id then raise exception 'Выберите начисления одного водителя';end if;
  if p_date<a.accrual_date then raise exception 'Оплата не может предшествовать дате начисления';end if;
  v_driver=a.driver_id;v_count=v_count+1;
  select coalesce(sum(amount),0) into v_paid from public.crm_payroll_payments where accrual_id=a.id and kind=p_kind;
  v_total=v_total+case when p_kind='salary' then a.base+a.bonus-(select coalesce(sum(amount),0) from public.crm_payroll_deductions where accrual_id=a.id) else a.tax end-v_paid;
 end loop;
 if v_count<>cardinality(p_accrual_ids) or p_amount>v_total then raise exception 'Начисления недоступны или сумма превышает остаток';end if;
 for a in select * from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
  select coalesce(sum(amount),0) into v_paid from public.crm_payroll_payments where accrual_id=a.id and kind=p_kind;
  v_due=least(v_remaining,case when p_kind='salary' then a.base+a.bonus-(select coalesce(sum(amount),0) from public.crm_payroll_deductions where accrual_id=a.id) else a.tax end-v_paid);
  if v_due>0 then insert into public.crm_payroll_payments(accrual_id,kind,amount,payment_date) values(a.id,p_kind,v_due,p_date);v_remaining=v_remaining-v_due;end if;
  exit when v_remaining=0;
 end loop;
 return p_amount-v_remaining;
end $$;
create or replace function public.crm_guard_invoice_snapshot() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.crm_invoice_lines where invoice_id=old.id) then
  if tg_op='DELETE' then raise exception 'Счёт со связанными рейсами нельзя удалить';end if;
  if (new.customer_id,new.invoice_number,new.invoice_date,new.amount,new.deleted_at,new.seller_snapshot,new.buyer_snapshot) is distinct from (old.customer_id,old.invoice_number,old.invoice_date,old.amount,old.deleted_at,old.seller_snapshot,old.buyer_snapshot) then raise exception 'Счёт выпущен: данные и строки зафиксированы';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
drop trigger if exists crm_guard_invoice_snapshot on public.crm_invoices;
create trigger crm_guard_invoice_snapshot before update or delete on public.crm_invoices for each row execute function public.crm_guard_invoice_snapshot();
create or replace function public.crm_guard_invoice_payment() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare i public.crm_invoices;v_paid numeric;
begin
 select * into i from public.crm_invoices where id=new.invoice_id and owner_id=auth.uid() and deleted_at is null for update;
 if i.id is null or new.owner_id is distinct from auth.uid() or new.amount<=0 or new.amount::text in ('NaN','Infinity','-Infinity') or new.payment_date<i.invoice_date then raise exception 'Некорректная оплата или чужой счёт';end if;
 select coalesce(sum(amount),0) into v_paid from public.crm_invoice_payments where invoice_id=i.id and id<>new.id;
 if v_paid+new.amount>i.amount then raise exception 'Оплата превышает остаток по счёту';end if;
 return new;
end $$;
drop trigger if exists crm_guard_invoice_payment on public.crm_invoice_payments;
create trigger crm_guard_invoice_payment before insert or update on public.crm_invoice_payments for each row execute function public.crm_guard_invoice_payment();
-- Импорт расчёта ранее выполненных рейсов: только по явному действию пользователя.
create or replace function public.crm_prepare_payroll(p_trip_ids uuid[]) returns integer language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_count integer;
begin
 if auth.uid() is null or coalesce(cardinality(p_trip_ids),0)=0 then raise exception 'Выберите выполненные рейсы';end if;
 if exists(select 1 from public.crm_trips where id=any(p_trip_ids) and owner_id=auth.uid() and (status<>'delivered' or deleted_at is not null)) then raise exception 'Выберите выполненные активные рейсы';end if;
 update public.crm_trips set status=status where id=any(p_trip_ids) and owner_id=auth.uid() and status='delivered' and deleted_at is null;
 get diagnostics v_count=row_count;
 if v_count<>cardinality(p_trip_ids) then raise exception 'Рейсы недоступны или повторяются';end if;
 return v_count;
end $$;
revoke all on function public.crm_prepare_payroll(uuid[]) from public,anon;
grant execute on function public.crm_prepare_payroll(uuid[]) to authenticated;
create or replace function public.crm_apply_driver_fines(p_accrual_ids uuid[],p_fine_ids uuid[],p_date date) returns numeric language plpgsql security invoker set search_path=public,pg_temp as $$
declare a public.crm_payroll_accruals;f public.crm_driver_fines;v_driver uuid;v_remaining numeric;v_due numeric;v_take numeric;v_total numeric=0;v_count integer=0;
begin
 if auth.uid() is null or p_date is null or coalesce(cardinality(p_accrual_ids),0)=0 or coalesce(cardinality(p_fine_ids),0)=0 then raise exception 'Выберите начисления, штрафы и дату';end if;
 perform id from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() order by id for update;
 perform id from public.crm_driver_fines where id=any(p_fine_ids) and owner_id=auth.uid() order by id for update;
 for a in select * from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active loop
  if v_driver is not null and v_driver<>a.driver_id then raise exception 'Выберите одного водителя';end if;
  if a.accrual_date>p_date then raise exception 'Удержание предшествует начислению';end if;
  v_driver=a.driver_id;v_count=v_count+1;
 end loop;
 if v_count<>cardinality(p_accrual_ids) then raise exception 'Начисления недоступны или повторяются';end if;
 select count(*) into v_count from public.crm_driver_fines where id=any(p_fine_ids) and driver_id=v_driver and owner_id=auth.uid() and deleted_at is null and not paid and fine_date<=p_date;
 if v_count<>cardinality(p_fine_ids) then raise exception 'Штрафы недоступны, оплачены или относятся к другому водителю';end if;
 for f in select * from public.crm_driver_fines where id=any(p_fine_ids) and owner_id=auth.uid() order by fine_date,id loop
  select f.amount-coalesce(sum(amount),0) into v_remaining from public.crm_payroll_deductions where fine_id=f.id;
  for a in select * from public.crm_payroll_accruals where id=any(p_accrual_ids) and owner_id=auth.uid() and active order by accrual_date,id loop
   exit when v_remaining<=0;
   select a.base+a.bonus-(select coalesce(sum(amount),0) from public.crm_payroll_payments where accrual_id=a.id and kind='salary')-(select coalesce(sum(amount),0) from public.crm_payroll_deductions where accrual_id=a.id) into v_due;
   v_take=least(v_remaining,v_due);
   if v_take>0 then
    insert into public.crm_payroll_deductions(accrual_id,fine_id,amount,deduction_date) values(a.id,f.id,v_take,p_date);
    v_remaining=v_remaining-v_take;v_total=v_total+v_take;
   end if;
  end loop;
 end loop;
 if v_total<=0 then raise exception 'Нет доступной зарплаты для удержания или штрафы уже учтены';end if;
 return v_total;
end $$;
revoke all on function public.crm_apply_driver_fines(uuid[],uuid[],date) from public,anon;
grant execute on function public.crm_apply_driver_fines(uuid[],uuid[],date) to authenticated;
create or replace function public.crm_guard_allocated_fine() returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
begin
 if exists(select 1 from public.crm_payroll_deductions where fine_id=old.id) then
  if tg_op='DELETE' then raise exception 'Штраф учтён в зарплате и защищён от удаления';end if;
  if (new.driver_id,new.amount,new.fine_date,new.deleted_at) is distinct from (old.driver_id,old.amount,old.fine_date,old.deleted_at) then raise exception 'Штраф уже учтён в зарплате: требуется корректировка';end if;
 end if;
 if tg_op='DELETE' then return old;else return new;end if;
end $$;
drop trigger if exists crm_guard_allocated_fine on public.crm_driver_fines;
create trigger crm_guard_allocated_fine before update or delete on public.crm_driver_fines for each row execute function public.crm_guard_allocated_fine();
-- Функции доступны только вошедшим пользователям, выполняются с RLS вызывающего.
revoke all on function public.crm_create_invoice_from_trips(uuid,uuid,uuid[],text,date,jsonb),public.crm_create_upd_from_invoice(uuid,text,date),public.crm_record_invoice_payment(uuid,numeric,date),public.crm_pay_driver_accruals(uuid[],text,numeric,date) from public,anon;
grant execute on function public.crm_create_invoice_from_trips(uuid,uuid,uuid[],text,date,jsonb),public.crm_create_upd_from_invoice(uuid,text,date),public.crm_record_invoice_payment(uuid,numeric,date),public.crm_pay_driver_accruals(uuid[],text,numeric,date) to authenticated;
-- Архивирование выполняется атомарно; независимые архивы не восстанавливаются вместе с заказчиком.
create or replace function public.crm_archive_customer(p_customer_id uuid,p_restore boolean default false) returns void language plpgsql security invoker set search_path=public,pg_temp as $$
declare v_marker timestamptz;v_orders uuid[];v_trips uuid[];v_contracts uuid[];v_table text;v_column text;v_ids uuid[];
begin
 if auth.uid() is null then raise exception 'Требуется авторизация';end if;
 select deleted_at into v_marker from public.crm_customers where id=p_customer_id and owner_id=auth.uid() for update;
 if not found then raise exception 'Заказчик недоступен';end if;
 if not p_restore and (exists(select 1 from public.crm_invoices where customer_id=p_customer_id and owner_id=auth.uid() and deleted_at is null) or exists(select 1 from public.crm_payroll_accruals where customer_id=p_customer_id and owner_id=auth.uid())) then raise exception 'У заказчика есть счета или начисления зарплаты. Его финансовую историю нельзя архивировать вместе с рабочими данными';end if;
 if p_restore and v_marker is null then
  update public.crm_customers set is_archived=false where id=p_customer_id and owner_id=auth.uid();return;
 end if;
 if not p_restore then v_marker=clock_timestamp();end if;
 select coalesce(array_agg(id),'{}'::uuid[]) into v_orders from public.crm_orders where customer_id=p_customer_id and owner_id=auth.uid();
 select coalesce(array_agg(id),'{}'::uuid[]) into v_trips from public.crm_trips where owner_id=auth.uid() and (customer_id=p_customer_id or order_id=any(v_orders));
 select coalesce(array_agg(id),'{}'::uuid[]) into v_contracts from public.crm_contracts where customer_id=p_customer_id and owner_id=auth.uid();
 foreach v_table in array array['crm_documents','crm_driver_fines','crm_finance_entries','crm_fuel_entries','crm_tasks','crm_trips','crm_contract_rates','crm_specifications','crm_orders','crm_sites','crm_customer_sites','crm_contracts'] loop
  if to_regclass('public.'||v_table) is null then continue;end if;
  if v_table in ('crm_contract_rates','crm_specifications') then v_column='contract_id';v_ids=v_contracts;
  elsif v_table in ('crm_orders','crm_sites','crm_customer_sites','crm_contracts') then v_column='customer_id';v_ids=array[p_customer_id];
  else v_column='order_id';v_ids=v_orders;end if;
  if v_table in ('crm_documents','crm_finance_entries') then
   if p_restore then execute format('update public.%I set deleted_at=null where owner_id=$1 and (order_id=any($2) or trip_id=any($4)) and deleted_at=$3',v_table) using auth.uid(),v_orders,v_marker,v_trips;
   else execute format('update public.%I set deleted_at=$3 where owner_id=$1 and (order_id=any($2) or trip_id=any($4)) and deleted_at is null',v_table) using auth.uid(),v_orders,v_marker,v_trips;end if;
   continue;
  end if;
  if p_restore then
   execute format('update public.%I set deleted_at=null where owner_id=$1 and %I=any($2) and deleted_at=$3',v_table,v_column) using auth.uid(),v_ids,v_marker;
  else
   execute format('update public.%I set deleted_at=$3 where owner_id=$1 and %I=any($2) and deleted_at is null',v_table,v_column) using auth.uid(),v_ids,v_marker;
  end if;
 end loop;
 -- Прямые рейсы без заявки тоже входят в архив заказчика.
 if p_restore then update public.crm_trips set deleted_at=null where owner_id=auth.uid() and customer_id=p_customer_id and deleted_at=v_marker;
 else update public.crm_trips set deleted_at=v_marker where owner_id=auth.uid() and customer_id=p_customer_id and deleted_at is null;end if;
 update public.crm_customers set is_archived=not p_restore,deleted_at=case when p_restore then null else v_marker end where id=p_customer_id and owner_id=auth.uid();
end $$;
revoke all on function public.crm_archive_customer(uuid,boolean) from public,anon;
grant execute on function public.crm_archive_customer(uuid,boolean) to authenticated;
-- Старые выполненные рейсы намеренно не пересчитываются автоматически: тарифы могли измениться.
-- Начисления по ним импортируются после отдельной сверки истории.
notify pgrst,'reload schema';
commit;
