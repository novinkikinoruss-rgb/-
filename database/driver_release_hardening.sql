create or replace function public.respectlogistic_driver_road_data(p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object('duties',coalesce((select jsonb_agg((to_jsonb(d)-'owner_id')||jsonb_build_object('plate',(select plate from crm_vehicles where id=d.vehicle_id and owner_id=actor)) order by started_at desc) from respectlogistic_driver_duties d where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'),
 'fines',coalesce((select jsonb_agg((to_jsonb(f)-'owner_id')||jsonb_build_object('plate',(select plate from crm_vehicles where id=f.vehicle_id and owner_id=actor),'deducted',coalesce((select sum(amount) from crm_payroll_deductions where fine_id=f.linked_fine_id and owner_id=actor),0)) order by violation_at desc) from respectlogistic_road_fines f where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'));
end$$;

-- Sending today's report also closes its open period; historic reports cannot end a newer duty.
create function public.respectlogistic_close_report_duty() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare d respectlogistic_driver_duties;begin
 if new.status='submitted' and old.status='draft' and new.shift_date=current_date then
  select * into d from respectlogistic_driver_duties where driver_id=new.driver_id and owner_id=new.owner_id and vehicle_id=new.vehicle_id and ended_at is null and started_at<=new.created_at for update;
  if d.id is not null then
   if new.odometer<d.start_odometer then raise exception 'Пробег отчёта меньше пробега в начале смены';end if;
   update respectlogistic_driver_duties set ended_at=clock_timestamp(),end_odometer=new.odometer where id=d.id;
  end if;
 end if;return new;
end$$;
revoke all on function public.respectlogistic_close_report_duty() from public,anon,authenticated;
create trigger close_report_duty after update of status on public.respectlogistic_driver_shift_reports for each row execute function public.respectlogistic_close_report_duty();
notify pgrst,'reload schema';

