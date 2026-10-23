create or replace function public.respectlogistic_read_profit() returns jsonb language sql stable security invoker set search_path=public,pg_temp as $$
 select public.crm_read_trip_workspace()||jsonb_build_object(
 'accounting_invoices',coalesce((select jsonb_agg(to_jsonb(d)||jsonb_build_object('credited',coalesce((select sum(c.amount) from respectlogistic_accounting_credits c where c.invoice_id=d.id),0))) from respectlogistic_accounting_documents d where d.owner_id=auth.uid() and d.kind in ('invoice','advance') and d.status in ('issued','sent','signed')),'[]'),
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
notify pgrst,'reload schema';
