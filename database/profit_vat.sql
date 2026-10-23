alter table public.respectlogistic_profit_expenses add column vat_rate numeric(5,2) check(vat_rate between 0 and 100),add column input_vat_confirmed boolean not null default false,add check(not input_vat_confirmed or vat_rate is not null);
create table public.respectlogistic_profit_settings(owner_id uuid primary key default auth.uid() references auth.users(id),tax_regime text not null default 'osno' check(tax_regime='osno'),vat_rate numeric(5,2) not null default 22 check(vat_rate between 0 and 100),prices_include_vat boolean,modified_at timestamptz not null default now());
create table public.respectlogistic_invoice_vat(invoice_id uuid primary key references public.crm_counterparty_invoices(id),owner_id uuid not null default auth.uid() references auth.users(id),vat_rate numeric(5,2) check(vat_rate between 0 and 100),input_vat_confirmed boolean not null default false,check(not input_vat_confirmed or vat_rate is not null));
alter table public.respectlogistic_profit_settings enable row level security;
alter table public.respectlogistic_invoice_vat enable row level security;
create policy profit_settings_owner on public.respectlogistic_profit_settings for select to authenticated using(owner_id=(select auth.uid()));
create policy invoice_vat_owner on public.respectlogistic_invoice_vat for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_counterparty_invoices i where i.id=invoice_id));
revoke all on public.respectlogistic_profit_settings,public.respectlogistic_invoice_vat from public,anon,authenticated;
grant select on public.respectlogistic_profit_settings,public.respectlogistic_invoice_vat to authenticated;
create function public.respectlogistic_save_profit_settings(p_vat_rate numeric,p_prices_include_vat boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$begin
 if auth.uid() is null or p_vat_rate is null or p_vat_rate<0 or p_vat_rate>100 or p_vat_rate::text in ('NaN','Infinity','-Infinity') or p_prices_include_vat is null then raise exception 'Укажите ставку НДС и порядок его включения в цены';end if;
 insert into respectlogistic_profit_settings(owner_id,vat_rate,prices_include_vat) values(auth.uid(),p_vat_rate,p_prices_include_vat) on conflict(owner_id) do update set vat_rate=excluded.vat_rate,prices_include_vat=excluded.prices_include_vat,modified_at=clock_timestamp();
end$$;
create or replace function public.respectlogistic_read_profit() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select public.crm_read_trip_workspace()||jsonb_build_object(
 'settings',coalesce((select to_jsonb(s) from respectlogistic_profit_settings s where s.owner_id=(select auth.uid())),'{"tax_regime":"osno","vat_rate":22,"prices_include_vat":null}'::jsonb),
 'invoice_vat',coalesce((select jsonb_agg(to_jsonb(v)) from respectlogistic_invoice_vat v),'[]'),
 'expenses',coalesce((select jsonb_agg(to_jsonb(e) order by e.expense_date desc,e.created_at desc) from respectlogistic_profit_expenses e where e.owner_id=(select auth.uid()) and e.deleted_at is null),'[]'),
 'invoices',coalesce((select jsonb_agg(to_jsonb(i)) from rl_crm_counterparty_invoices i where i.deleted_at is null),'[]'),
 'accruals',coalesce((select jsonb_agg(to_jsonb(a)) from rl_crm_payroll_accruals a where a.active),'[]'),
 'payments',coalesce((select jsonb_agg(to_jsonb(p)) from rl_crm_payroll_payments p),'[]'),
 'deductions',coalesce((select jsonb_agg(to_jsonb(d)) from rl_crm_payroll_deductions d),'[]'))
$$;
-- Block changes to an allocated invoice that would silently corrupt object profitability.
create function public.respectlogistic_guard_allocated_invoice() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare allocated numeric;
begin
 select coalesce(sum(amount),0) into allocated from respectlogistic_profit_expenses where invoice_id=old.id and deleted_at is null;
 if allocated>0 and (new.amount<allocated or new.counterparty_id is distinct from old.counterparty_id or new.owner_id is distinct from old.owner_id or new.deleted_at is not null) then raise exception 'Счёт распределён по объектам. Сначала скорректируйте распределение в разделе «Прибыль»';end if;
 return new;
end$$;
create trigger respectlogistic_allocated_invoice before update on public.crm_counterparty_invoices for each row execute function public.respectlogistic_guard_allocated_invoice();
revoke all on function public.respectlogistic_save_profit_settings(numeric,boolean),public.respectlogistic_guard_allocated_invoice() from public,anon,authenticated;
grant execute on function public.respectlogistic_save_profit_settings(numeric,boolean) to authenticated;
notify pgrst,'reload schema';
