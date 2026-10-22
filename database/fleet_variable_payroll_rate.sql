alter table public.crm_payroll_accruals drop constraint crm_payroll_accruals_rate_check;
alter table public.crm_payroll_accruals drop constraint crm_payroll_accruals_check;
alter table public.crm_payroll_accruals add constraint crm_payroll_accruals_rate_check check(rate>=0 and rate::text not in ('NaN','Infinity','-Infinity'));
alter table public.crm_payroll_accruals add constraint crm_payroll_accruals_check check(base=round(distance_km*rate,2));
notify pgrst,'reload schema';