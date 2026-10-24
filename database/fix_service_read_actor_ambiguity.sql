create or replace function public.respectlogistic_read_service() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_owner_id uuid=auth.uid();begin
 if v_owner_id is null then raise exception 'Войдите в CRM';end if;
 return jsonb_build_object(
 'partners',coalesce((select jsonb_agg(to_jsonb(p) order by p.name) from respectlogistic_service_partners p where p.owner_id=v_owner_id),'[]'),
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from respectlogistic_service_requests r where r.owner_id=v_owner_id),'[]'),
 'history',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from respectlogistic_service_history h where h.owner_id=v_owner_id),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'brand',v.brand,'model',v.model,'assigned_driver_id',v.assigned_driver_id,'odometer_km',v.odometer_km,'next_service_km',v.next_service_km,'next_oil_km',v.next_oil_km,'reminder_before_km',v.reminder_before_km)) from crm_vehicles v where v.owner_id=v_owner_id and v.app_scope='respectlogistic' and v.carrier_id is null and not v.is_subcontractor_vehicle and v.archived_at is null),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'phone',d.phone)) from crm_drivers d where d.owner_id=v_owner_id and d.app_scope='respectlogistic' and d.carrier_id is null and d.archived_at is null and d.job_status='active'),'[]'),
 'accounts',coalesce((select jsonb_agg(jsonb_build_object('driver_id',a.driver_id,'login',a.login,'blocked',a.blocked,'must_change_password',a.must_change_password)) from respectlogistic_driver_accounts a where a.owner_id=v_owner_id),'[]'));
end$$;
notify pgrst,'reload schema';