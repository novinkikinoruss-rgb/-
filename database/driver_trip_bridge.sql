-- Reuse the existing payroll fine ledger. A notice never deducts salary by itself.
alter table public.respectlogistic_road_fines add column linked_fine_id uuid unique references public.crm_driver_fines;
create function public.respectlogistic_prepare_road_fine(p_id uuid) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare f respectlogistic_road_fines;fid uuid;begin
 select * into f from respectlogistic_road_fines where id=p_id and owner_id=auth.uid() for update;
 if auth.uid() is null or f.id is null or f.driver_id is null then raise exception 'Сначала определите водителя';end if;
 if f.linked_fine_id is not null then return f.linked_fine_id;end if;
 if not exists(select 1 from crm_drivers where id=f.driver_id and owner_id=auth.uid() and app_scope='respectlogistic' and carrier_id is null) then raise exception 'Водитель недоступен';end if;
 insert into crm_driver_fines(owner_id,driver_id,fine_date,amount,reason) values(auth.uid(),f.driver_id,f.violation_at::date,f.amount,'Постановление №'||f.notice_number||' · '||f.reason||' · '||f.location) returning id into fid;
 update respectlogistic_road_fines set linked_fine_id=fid,modified_at=clock_timestamp() where id=f.id;return fid;
end$$;
revoke all on function public.respectlogistic_prepare_road_fine(uuid) from public,anon,authenticated;
grant execute on function public.respectlogistic_prepare_road_fine(uuid) to authenticated;
create or replace function public.respectlogistic_driver_road_data(p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object('duties',coalesce((select jsonb_agg((to_jsonb(d)-'owner_id')||jsonb_build_object('plate',(select plate from crm_vehicles where id=d.vehicle_id and owner_id=actor)) order by started_at desc) from respectlogistic_driver_duties d where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'),
 'fines',coalesce((select jsonb_agg((to_jsonb(f)-'owner_id')||jsonb_build_object('plate',(select plate from crm_vehicles where id=f.vehicle_id and owner_id=actor),'deducted',coalesce((select sum(amount) from crm_payroll_deductions where fine_id=f.linked_fine_id and owner_id=actor),0)) order by violation_at desc) from respectlogistic_road_fines f where owner_id=actor and (a.driver_id is null or driver_id=a.driver_id)),'[]'));
end$$;

create or replace function public.respectlogistic_queue_trip_documents() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.app_scope is distinct from 'respectlogistic' then return new;end if;
 if new.status='delivered' and new.documents_confirmed and new.deleted_at is null and
  (exists(select 1 from respectlogistic_trip_files where trip_id=new.id and owner_id=new.owner_id) or exists(select 1 from respectlogistic_driver_shift_files where trip_id=new.id and owner_id=new.owner_id)) then
  if tg_op='INSERT' or old.status is distinct from new.status or old.documents_confirmed is distinct from new.documents_confirmed or old.trip_date is distinct from new.trip_date or old.vehicle_id is distinct from new.vehicle_id or old.site_id is distinct from new.site_id or old.service_name is distinct from new.service_name then
   insert into respectlogistic_drive_exports(trip_id,owner_id) values(new.id,new.owner_id) on conflict(trip_id) do update set version=gen_random_uuid(),state='pending',error=null,folder_url=null,updated_at=now();
  end if;
 else delete from respectlogistic_drive_exports where trip_id=new.id;end if;
 return new;
end$$;
create or replace function public.respectlogistic_claim_drive_export(p_trip_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare q respectlogistic_drive_exports;result jsonb;begin
 select * into q from respectlogistic_drive_exports where trip_id=p_trip_id and owner_id=auth.uid() for update;
 if q.trip_id is null or q.state='complete' or (q.state='processing' and q.updated_at>now()-interval '5 minutes') then return null;end if;
 select jsonb_build_object('trip_id',t.id,'version',q.version,'customer',c.payload->>'name','site',s.payload->>'name','service',t.service_name,'date',t.trip_date,'plate',v.plate,'files',(
 select jsonb_agg(file) from (
  select jsonb_build_object('id',f.id,'file_name',f.file_name,'mime_type',f.mime_type,'storage_path',f.storage_path) as file from respectlogistic_trip_files f where f.trip_id=t.id and f.owner_id=auth.uid()
  union all
  select jsonb_build_object('id',f.id,'file_name',f.file_name,'mime_type',f.mime_type,'storage_path','shift:'||f.id::text) from respectlogistic_driver_shift_files f where f.trip_id=t.id and f.owner_id=auth.uid()
 ) all_files)) into result
 from crm_trips t join respectlogistic_customers c on c.id=t.customer_id and c.owner_id=t.owner_id join respectlogistic_sites s on s.id=t.site_id and s.owner_id=t.owner_id join crm_vehicles v on v.id=t.vehicle_id and v.owner_id=t.owner_id
 where t.id=p_trip_id and t.owner_id=auth.uid() and t.app_scope='respectlogistic' and t.deleted_at is null and t.status='delivered' and t.documents_confirmed;
 if result is null then return null;end if;
 update respectlogistic_drive_exports set state='processing',updated_at=now() where trip_id=p_trip_id;return result;
end$$;
notify pgrst,'reload schema';
