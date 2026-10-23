create or replace function public.crm_sync_payroll()
returns trigger language plpgsql security invoker set search_path=public,pg_temp as $$
declare s public.crm_sites;d public.crm_drivers;o public.crm_orders;v_base numeric;v_bonus numeric;v_customer uuid;v_site uuid;
begin
 if new.carrier_id is not null or exists(select 1 from public.crm_drivers where id=new.driver_id and owner_id=new.owner_id and carrier_id is not null) then
  if exists(select 1 from public.crm_payroll_accruals where trip_id=new.id) then raise exception 'По рейсу уже есть начисление штатному водителю. Требуется корректировка перед сменой исполнителя';end if;
  return new;
 end if;
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
 if d.pay_rate_km<0 then raise exception 'Ставка водителя не может быть отрицательной';end if;
 v_base=round(s.route_km*d.pay_rate_km,2);v_bonus=round(v_base*d.bonus_pct/100,2);
 insert into public.crm_payroll_accruals(owner_id,trip_id,driver_id,customer_id,site_id,accrual_date,distance_km,rate,bonus_pct,tax_pct,base,bonus,tax)
 values(new.owner_id,new.id,d.id,v_customer,v_site,new.trip_date,s.route_km,d.pay_rate_km,d.bonus_pct,d.tax_pct,v_base,v_bonus,round((v_base+v_bonus)*d.tax_pct/100,2));
 return new;
end $$;
notify pgrst,'reload schema';
