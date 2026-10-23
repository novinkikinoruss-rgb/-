-- Private driver documents and a durable, explicit Drive export queue.
alter table public.crm_trips add column if not exists documents_confirmed boolean not null default false;
create or replace view public.rl_crm_trips with(security_invoker=true) as select t.* from public.crm_trips t where t.owner_id=(select auth.uid()) and t.app_scope='respectlogistic' with cascaded check option;
create table public.respectlogistic_trip_files(
 id uuid primary key default gen_random_uuid(),owner_id uuid not null default auth.uid() references auth.users(id),
 trip_id uuid not null references public.crm_trips(id),file_name text not null,doc_type text not null check(doc_type in ('ttn','waybill','ticket','invoice','other')),
 storage_path text not null unique,mime_type text not null,file_size bigint not null check(file_size>0 and file_size<=10485760),created_at timestamptz not null default now()
);
alter table public.respectlogistic_trip_files enable row level security;
create policy trip_files_owner on public.respectlogistic_trip_files for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_trips t where t.id=trip_id and t.deleted_at is null));
grant select on public.respectlogistic_trip_files to authenticated;
create view public.rl_crm_trip_files with(security_invoker=true) as select * from public.respectlogistic_trip_files;
grant select on public.rl_crm_trip_files to authenticated;
create table public.respectlogistic_drive_exports(
 trip_id uuid primary key references public.crm_trips(id),owner_id uuid not null references auth.users(id),version uuid not null default gen_random_uuid(),
 state text not null default 'pending' check(state in ('pending','processing','awaiting_connection','complete','error')),
 folder_url text,error text,updated_at timestamptz not null default now()
);
alter table public.respectlogistic_drive_exports enable row level security;
create policy drive_exports_owner on public.respectlogistic_drive_exports for select to authenticated using(owner_id=(select auth.uid()) and exists(select 1 from public.rl_crm_trips t where t.id=trip_id and t.deleted_at is null));
grant select on public.respectlogistic_drive_exports to authenticated;
create view public.rl_crm_drive_exports with(security_invoker=true) as select * from public.respectlogistic_drive_exports;
grant select on public.rl_crm_drive_exports to authenticated;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('respectlogistic-trip-documents','respectlogistic-trip-documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp']) on conflict(id) do nothing;
create policy respectlogistic_document_read on storage.objects for select to authenticated using(bucket_id='respectlogistic-trip-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.rl_crm_trips t where t.id::text=(storage.foldername(name))[2] and t.deleted_at is null));
create policy respectlogistic_document_insert on storage.objects for insert to authenticated with check(bucket_id='respectlogistic-trip-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and exists(select 1 from public.rl_crm_trips t where t.id::text=(storage.foldername(name))[2] and t.deleted_at is null));
create policy respectlogistic_document_cleanup on storage.objects for delete to authenticated using(bucket_id='respectlogistic-trip-documents' and (storage.foldername(name))[1]=(select auth.uid())::text and not exists(select 1 from public.respectlogistic_trip_files f where f.storage_path=name));

create function public.respectlogistic_register_trip_file(p_trip_id uuid,p_path text,p_name text,p_type text) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare result uuid;obj storage.objects;
begin
 if auth.uid() is null or not exists(select 1 from crm_trips where id=p_trip_id and owner_id=auth.uid() and app_scope='respectlogistic' and deleted_at is null) then raise exception 'Рейс недоступен';end if;
 perform id from crm_trips where id=p_trip_id for update;
 if p_path not like auth.uid()::text||'/'||p_trip_id::text||'/%' or length(trim(p_name))=0 or length(p_name)>255 then raise exception 'Некорректный файл';end if;
 select * into obj from storage.objects where bucket_id='respectlogistic-trip-documents' and name=p_path;
 if obj.id is null then raise exception 'Файл не загружен в хранилище';end if;
 insert into respectlogistic_trip_files(trip_id,owner_id,file_name,doc_type,storage_path,mime_type,file_size) values(p_trip_id,auth.uid(),p_name,p_type,p_path,obj.metadata->>'mimetype',(obj.metadata->>'size')::bigint) returning id into result;
 update crm_trips set documents_confirmed=false where id=p_trip_id;
 delete from respectlogistic_drive_exports where trip_id=p_trip_id;
 return result;
end $$;
create function public.respectlogistic_confirm_trip_documents(p_trip_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform id from crm_trips where id=p_trip_id and owner_id=auth.uid() and app_scope='respectlogistic' and deleted_at is null for update;
 if not found then raise exception 'Рейс недоступен';end if;
 if not exists(select 1 from respectlogistic_trip_files where trip_id=p_trip_id and owner_id=auth.uid()) then raise exception 'Сначала загрузите документы водителя';end if;
 update crm_trips set documents_confirmed=true where id=p_trip_id;
end $$;
create function public.respectlogistic_queue_trip_documents() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if new.app_scope is distinct from 'respectlogistic' then return new;end if;
 if new.status='delivered' and new.documents_confirmed and new.deleted_at is null and exists(select 1 from respectlogistic_trip_files where trip_id=new.id) then
  if tg_op='INSERT' or old.status is distinct from new.status or old.documents_confirmed is distinct from new.documents_confirmed or old.trip_date is distinct from new.trip_date or old.vehicle_id is distinct from new.vehicle_id or old.site_id is distinct from new.site_id or old.service_name is distinct from new.service_name then
   insert into respectlogistic_drive_exports(trip_id,owner_id) values(new.id,new.owner_id) on conflict(trip_id) do update set version=gen_random_uuid(),state='pending',error=null,folder_url=null,updated_at=now();
  end if;
 else delete from respectlogistic_drive_exports where trip_id=new.id;end if;
 return new;
end $$;
create trigger respectlogistic_trip_export after insert or update on public.crm_trips for each row execute function public.respectlogistic_queue_trip_documents();

create function public.respectlogistic_claim_drive_export(p_trip_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare q respectlogistic_drive_exports;result jsonb;
begin
 select * into q from respectlogistic_drive_exports where trip_id=p_trip_id and owner_id=auth.uid() for update;
 if q.trip_id is null or q.state='complete' or (q.state='processing' and q.updated_at>now()-interval '5 minutes') then return null;end if;
 select jsonb_build_object('trip_id',t.id,'version',q.version,'customer',c.payload->>'name','site',s.payload->>'name','service',t.service_name,'date',t.trip_date,'plate',v.plate,'files',(select jsonb_agg(to_jsonb(f)) from respectlogistic_trip_files f where f.trip_id=t.id and f.owner_id=auth.uid())) into result
 from crm_trips t join respectlogistic_customers c on c.id=t.customer_id join respectlogistic_sites s on s.id=t.site_id join crm_vehicles v on v.id=t.vehicle_id
 where t.id=p_trip_id and t.owner_id=auth.uid() and t.app_scope='respectlogistic' and t.deleted_at is null and t.status='delivered' and t.documents_confirmed;
 if result is null then return null;end if;
 update respectlogistic_drive_exports set state='processing',updated_at=now() where trip_id=p_trip_id;
 return result;
end $$;
create function public.respectlogistic_finish_drive_export(p_trip_id uuid,p_version uuid,p_state text,p_url text default null,p_error text default null) returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if p_state not in ('complete','error','awaiting_connection') then raise exception 'Некорректный статус архива';end if;
 if p_url is not null and p_url not like 'https://drive.google.com/drive/folders/%' then raise exception 'Некорректная ссылка';end if;
 update respectlogistic_drive_exports set state=p_state,folder_url=p_url,error=left(p_error,500),updated_at=now() where trip_id=p_trip_id and owner_id=auth.uid() and version=p_version and state='processing';
 return found;
end $$;
revoke all on function public.respectlogistic_register_trip_file(uuid,text,text,text),public.respectlogistic_confirm_trip_documents(uuid),public.respectlogistic_claim_drive_export(uuid),public.respectlogistic_finish_drive_export(uuid,uuid,text,text,text),public.respectlogistic_queue_trip_documents() from public,anon;
grant execute on function public.respectlogistic_register_trip_file(uuid,text,text,text),public.respectlogistic_confirm_trip_documents(uuid),public.respectlogistic_claim_drive_export(uuid),public.respectlogistic_finish_drive_export(uuid,uuid,text,text,text) to authenticated;
notify pgrst,'reload schema';
