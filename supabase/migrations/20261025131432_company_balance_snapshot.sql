-- A dated manual cash snapshot, separate from earned profit and payment ledgers.
create table public.respectlogistic_company_balance(
 owner_id uuid primary key references auth.users(id),
 amount_kopecks bigint not null check(amount_kopecks between -100000000000000 and 100000000000000),
 balance_date date not null,
 modified_at timestamptz not null default clock_timestamp()
);
alter table public.respectlogistic_company_balance enable row level security;
revoke all on public.respectlogistic_company_balance from public,anon,authenticated;
grant select on public.respectlogistic_company_balance to authenticated;
create policy company_balance_owner on public.respectlogistic_company_balance for select to authenticated using(owner_id=(select auth.uid()));
create function public.respectlogistic_read_company_balance() returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Войдите в CRM';end if;
 return jsonb_build_object('balance',(select to_jsonb(b)-'owner_id' from public.respectlogistic_company_balance b where b.owner_id=(select auth.uid())));
end$$;
create function public.respectlogistic_save_company_balance(p_amount numeric,p_date date,p_expected timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid=auth.uid();previous public.respectlogistic_company_balance;saved public.respectlogistic_company_balance;begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 if p_amount is null or not(p_amount between -1000000000000 and 1000000000000) or p_amount<>round(p_amount,2) or p_date is null or p_date>(clock_timestamp() at time zone 'Europe/Moscow')::date or p_date<date '1900-01-01' then raise exception 'Укажите остаток в рублях (до двух знаков) и дату не позднее сегодняшней';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-company-balance',0));
 select * into previous from public.respectlogistic_company_balance where owner_id=actor for update;
 if previous.modified_at is distinct from p_expected then raise exception 'Остаток уже изменён. Обновите данные и повторите';end if;
 insert into public.respectlogistic_company_balance(owner_id,amount_kopecks,balance_date) values(actor,(p_amount*100)::bigint,p_date)
 on conflict(owner_id) do update set amount_kopecks=excluded.amount_kopecks,balance_date=excluded.balance_date,modified_at=clock_timestamp() returning * into saved;
 return to_jsonb(saved)-'owner_id';
end$$;
revoke all on function public.respectlogistic_read_company_balance(),public.respectlogistic_save_company_balance(numeric,date,timestamptz) from public,anon,authenticated;
grant execute on function public.respectlogistic_read_company_balance(),public.respectlogistic_save_company_balance(numeric,date,timestamptz) to authenticated;
notify pgrst,'reload schema';
