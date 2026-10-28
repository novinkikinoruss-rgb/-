-- Hide orphan trip-generated reports from drivers; preserve the owner audit and immutable dispatch history.
CREATE OR REPLACE FUNCTION public.respectlogistic_driver_extras(p_token text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object(
 'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'driver_id',n.driver_id,'title',n.title,'has_credentials',n.has_credentials,'modified_at',n.modified_at)) from respectlogistic_driver_notes n where n.owner_id=actor and n.deleted_at is null and (a.driver_id is null or n.driver_id=a.driver_id)),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(s)-'owner_id' order by s.created_at desc) from respectlogistic_driver_shift_reports s where s.owner_id=actor and (a.driver_id is null or s.driver_id=a.driver_id) and (a.driver_id is null or not exists(select 1 from respectlogistic_driver_shift_files hf where hf.report_id=s.id and hf.owner_id=actor and hf.trip_id is not null) or exists(select 1 from respectlogistic_driver_shift_files vf left join crm_trips vt on vt.id=vf.trip_id and vt.owner_id=actor and vt.app_scope='respectlogistic' where vf.report_id=s.id and vf.owner_id=actor and (vf.trip_id is null or vt.id is not null and vt.deleted_at is null)))),'[]'),
 'shift_files',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'report_id',f.report_id,'driver_id',f.driver_id,'trip_id',f.trip_id,'kind',f.kind,'file_name',f.file_name,'mime_type',f.mime_type,'file_size',f.file_size)) from respectlogistic_driver_shift_files f where (f.trip_id is null or exists(select 1 from crm_trips et where et.id=f.trip_id and et.owner_id=actor and et.app_scope='respectlogistic' and et.deleted_at is null)) and f.owner_id=actor and (a.driver_id is null or f.driver_id=a.driver_id)),'[]'),
 'driver_trips',case when a.driver_id is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'trip_number',t.trip_number,'trip_date',t.trip_date,'status',t.status,'service_name',t.service_name,'vehicle_id',t.vehicle_id,'object',s.payload->>'name')) from crm_trips t join respectlogistic_sites s on s.id=t.site_id and s.owner_id=actor where t.owner_id=actor and t.app_scope='respectlogistic' and t.driver_id=a.driver_id and t.deleted_at is null and t.trip_date>=current_date-30),'[]') end);
end$function$

;
CREATE OR REPLACE FUNCTION public.respectlogistic_read_dispatch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare actor uuid=auth.uid();begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 return jsonb_build_object(
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.number desc) from respectlogistic_dispatch_requests r where r.owner_id=actor and r.deleted_at is null),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(s) order by s.shift_date desc,s.starts_at,s.id) from respectlogistic_dispatch_shifts s where s.owner_id=actor),'[]'),
 'results',coalesce((select jsonb_agg(to_jsonb(r)||jsonb_build_object('trip_deleted',not exists(select 1 from crm_trips rt where rt.id=r.trip_id and rt.owner_id=actor and rt.app_scope='respectlogistic' and rt.deleted_at is null))) from respectlogistic_dispatch_results r where r.owner_id=actor),'[]'),
 'templates',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from respectlogistic_dispatch_templates t where t.owner_id=actor),'[]'),
 'documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.number desc) from respectlogistic_dispatch_documents d where d.owner_id=actor),'[]'),
 'events',coalesce((select jsonb_agg(to_jsonb(e) order by e.id desc) from (select * from respectlogistic_dispatch_events where owner_id=actor order by id desc limit 200) e),'[]'),
 'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'plate',v.plate,'carrier_id',v.carrier_id,'is_subcontractor_vehicle',v.is_subcontractor_vehicle,'assigned_driver_id',v.assigned_driver_id,'status',v.status)) from crm_vehicles v where v.owner_id=actor and v.app_scope='respectlogistic' and v.archived_at is null),'[]'),
 'drivers',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'full_name',d.full_name,'carrier_id',d.carrier_id,'ready',exists(select 1 from respectlogistic_driver_accounts a where a.owner_id=actor and a.driver_id=d.id and not a.blocked))) from crm_drivers d where d.owner_id=actor and d.app_scope='respectlogistic' and d.archived_at is null and d.job_status='active'),'[]'),
 'carriers',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name)) from crm_carriers c where c.owner_id=actor and c.app_scope='respectlogistic' and not c.is_blocked),'[]'));
end$function$

;
notify pgrst,'reload schema';
