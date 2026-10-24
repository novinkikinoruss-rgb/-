-- Sensitive driver notes are encrypted with a key held in Supabase Vault, never in source code.
do $$begin if not exists(select 1 from vault.secrets where name='respectlogistic_driver_notes_key') then perform vault.create_secret(encode(extensions.gen_random_bytes(32),'hex'),'respectlogistic_driver_notes_key','Encryption key for driver-private notes');end if;end$$;
create table public.respectlogistic_driver_notes(id uuid primary key,owner_id uuid not null references auth.users(id),driver_id uuid not null references public.crm_drivers(id),title text not null,encrypted_body bytea not null,has_credentials boolean not null default false,modified_at timestamptz not null default clock_timestamp(),deleted_at timestamptz);
create table public.respectlogistic_driver_shift_reports(
 id uuid primary key,owner_id uuid not null references auth.users(id),driver_id uuid not null references public.crm_drivers(id),vehicle_id uuid not null references public.crm_vehicles(id),shift_date date not null,odometer numeric not null check(odometer>=0),technical_note text not null default '',supplies_note text not null default '',comment text not null default '',status text not null default 'draft' check(status in ('draft','submitted','reviewed','rejected','cancelled')),supplies_status text not null default 'open' check(supplies_status in ('open','in_progress','done')),dispatcher_note text not null default '',created_at timestamptz not null default clock_timestamp(),modified_at timestamptz not null default clock_timestamp()
);
create unique index one_driver_shift on public.respectlogistic_driver_shift_reports(driver_id,vehicle_id,shift_date) where status not in ('rejected','cancelled');
create table public.respectlogistic_driver_shift_files(id uuid primary key,report_id uuid not null references public.respectlogistic_driver_shift_reports(id),owner_id uuid not null references auth.users(id),driver_id uuid not null references public.crm_drivers(id),trip_id uuid references public.crm_trips(id),kind text not null check(kind in ('odometer','document','other')),file_name text not null,mime_type text not null,file_size integer not null check(file_size>0 and file_size<=2097152),data bytea not null,created_at timestamptz not null default clock_timestamp());
alter table public.respectlogistic_driver_notes enable row level security;
alter table public.respectlogistic_driver_shift_reports enable row level security;
alter table public.respectlogistic_driver_shift_files enable row level security;
revoke all on public.respectlogistic_driver_notes,public.respectlogistic_driver_shift_reports,public.respectlogistic_driver_shift_files from public,anon,authenticated;
create policy driver_notes_owner on public.respectlogistic_driver_notes for select to authenticated using(owner_id=(select auth.uid()));
create policy driver_shift_owner on public.respectlogistic_driver_shift_reports for select to authenticated using(owner_id=(select auth.uid()));
create policy driver_shift_file_owner on public.respectlogistic_driver_shift_files for select to authenticated using(owner_id=(select auth.uid()));
grant select(id,owner_id,driver_id,title,has_credentials,modified_at,deleted_at) on public.respectlogistic_driver_notes to authenticated;
grant select on public.respectlogistic_driver_shift_reports to authenticated;
grant select(id,report_id,owner_id,driver_id,trip_id,kind,file_name,mime_type,file_size,created_at) on public.respectlogistic_driver_shift_files to authenticated;
create index driver_notes_driver on public.respectlogistic_driver_notes(driver_id);
create index driver_notes_owner on public.respectlogistic_driver_notes(owner_id);
create index shift_report_owner on public.respectlogistic_driver_shift_reports(owner_id,created_at desc);
create index shift_report_vehicle on public.respectlogistic_driver_shift_reports(vehicle_id);
create index shift_files_report on public.respectlogistic_driver_shift_files(report_id);
create index shift_files_trip on public.respectlogistic_driver_shift_files(trip_id);
create index shift_files_driver on public.respectlogistic_driver_shift_files(driver_id);
create index shift_files_owner on public.respectlogistic_driver_shift_files(owner_id);

create function public.respectlogistic_save_driver_note(p_record jsonb,p_expected timestamptz default null,p_delete boolean default false) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;did uuid=(p_record->>'driver_id')::uuid;n respectlogistic_driver_notes;key_value text;body jsonb;begin
 if actor is null or rid is null or did is null or length(p_record::text)>20000 or not exists(select 1 from crm_drivers where id=did and owner_id=actor and app_scope='respectlogistic' and carrier_id is null) then raise exception 'Водитель недоступен';end if;
 select * into n from respectlogistic_driver_notes where id=rid for update;
 if n.id is not null and (n.owner_id<>actor or n.driver_id<>did or n.deleted_at is not null or n.modified_at is distinct from p_expected) then raise exception 'Заметка недоступна или изменена';end if;
 if p_delete then
  if n.id is null then raise exception 'Заметка недоступна';end if;
  update respectlogistic_driver_notes set deleted_at=clock_timestamp(),modified_at=clock_timestamp() where id=rid;return rid;
 end if;
 if coalesce(trim(p_record->>'title'),'')='' then raise exception 'Укажите название заметки или приложения';end if;
 select decrypted_secret into key_value from vault.decrypted_secrets where name='respectlogistic_driver_notes_key';
 if key_value is null then raise exception 'Хранилище заметок не настроено';end if;
 body=jsonb_build_object('login',coalesce(p_record->>'login',''),'password',coalesce(p_record->>'password',''),'body',coalesce(p_record->>'body',''));
 insert into respectlogistic_driver_notes(id,owner_id,driver_id,title,encrypted_body,has_credentials) values(rid,actor,did,left(trim(p_record->>'title'),200),pgp_sym_encrypt(body::text,key_value,'cipher-algo=aes256'),coalesce(p_record->>'password','')<>'' or coalesce(p_record->>'login','')<>'') on conflict(id) do update set title=excluded.title,encrypted_body=excluded.encrypted_body,has_credentials=excluded.has_credentials,modified_at=clock_timestamp();return rid;
end$$;
create function public.respectlogistic_read_driver_note(p_id uuid,p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;n respectlogistic_driver_notes;key_value text;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 select * into n from respectlogistic_driver_notes where id=p_id and owner_id=actor and deleted_at is null;
 if actor is null or n.id is null or (a.driver_id is not null and n.driver_id<>a.driver_id) then raise exception 'Заметка недоступна';end if;
 select decrypted_secret into key_value from vault.decrypted_secrets where name='respectlogistic_driver_notes_key';
 return jsonb_build_object('id',n.id,'driver_id',n.driver_id,'title',n.title,'modified_at',n.modified_at)||pgp_sym_decrypt(n.encrypted_body,key_value)::jsonb;
end$$;

create function public.respectlogistic_driver_extras(p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null then raise exception 'Войдите повторно';end if;
 return jsonb_build_object(
 'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'driver_id',n.driver_id,'title',n.title,'has_credentials',n.has_credentials,'modified_at',n.modified_at)) from respectlogistic_driver_notes n where n.owner_id=actor and n.deleted_at is null and (a.driver_id is null or n.driver_id=a.driver_id)),'[]'),
 'shifts',coalesce((select jsonb_agg(to_jsonb(s)-'owner_id' order by s.created_at desc) from respectlogistic_driver_shift_reports s where s.owner_id=actor and (a.driver_id is null or s.driver_id=a.driver_id)),'[]'),
 'shift_files',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'report_id',f.report_id,'driver_id',f.driver_id,'trip_id',f.trip_id,'kind',f.kind,'file_name',f.file_name,'mime_type',f.mime_type,'file_size',f.file_size)) from respectlogistic_driver_shift_files f where f.owner_id=actor and (a.driver_id is null or f.driver_id=a.driver_id)),'[]'),
 'driver_trips',case when a.driver_id is null then '[]'::jsonb else coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'trip_number',t.trip_number,'trip_date',t.trip_date,'status',t.status,'service_name',t.service_name,'vehicle_id',t.vehicle_id,'object',s.payload->>'name')) from crm_trips t join respectlogistic_sites s on s.id=t.site_id and s.owner_id=actor where t.owner_id=actor and t.app_scope='respectlogistic' and t.driver_id=a.driver_id and t.deleted_at is null and t.trip_date>=current_date-30),'[]') end);
end$$;

create function public.respectlogistic_create_shift_report(p_token text,p_record jsonb) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;v crm_vehicles;r respectlogistic_driver_shift_reports;rid uuid=(p_record->>'id')::uuid;odo numeric=(p_record->>'odometer')::numeric;day date=(p_record->>'shift_date')::date;begin
 a=respectlogistic_require_driver(p_token);
 if rid is null or day is null or day>current_date or day<current_date-7 or length(p_record::text)>16000 then raise exception 'Проверьте дату смены (до 7 дней назад) и отчёт';end if;
 select * into r from respectlogistic_driver_shift_reports where id=rid;
 if r.id is not null then if r.owner_id<>a.owner_id or r.driver_id<>a.driver_id then raise exception 'Отчёт недоступен';end if;return rid;end if;
 select * into v from crm_vehicles where id=(p_record->>'vehicle_id')::uuid and owner_id=a.owner_id and assigned_driver_id=a.driver_id and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null;
 if v.id is null or odo is null or odo<v.odometer_km or odo>100000000 or odo::text in ('NaN','Infinity','-Infinity') then raise exception 'Проверьте машину и пробег';end if;
 insert into respectlogistic_driver_shift_reports(id,owner_id,driver_id,vehicle_id,shift_date,odometer,technical_note,supplies_note,comment) values(rid,a.owner_id,a.driver_id,v.id,day,odo,coalesce(p_record->>'technical_note',''),coalesce(p_record->>'supplies_note',''),coalesce(p_record->>'comment',''));return rid;
end$$;

create function public.respectlogistic_driver_upload_photo(p_token text,p_record jsonb,p_base64 text) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare a respectlogistic_driver_accounts;r respectlogistic_driver_shift_reports;rid uuid=(p_record->>'report_id')::uuid;fid uuid=(p_record->>'id')::uuid;tid uuid=nullif(p_record->>'trip_id','')::uuid;kind_value text=p_record->>'kind';bytes bytea;begin
 a=respectlogistic_require_driver(p_token);
 select * into r from respectlogistic_driver_shift_reports where id=rid and owner_id=a.owner_id and driver_id=a.driver_id for update;
 if r.id is null or r.status<>'draft' or fid is null or kind_value is null or kind_value not in ('odometer','document','other') or length(p_base64)>2796208 then raise exception 'Фото можно добавить в черновик отчёта, до 2 МБ';end if;
 if exists(select 1 from respectlogistic_driver_shift_files where id=fid) then if exists(select 1 from respectlogistic_driver_shift_files where id=fid and report_id=r.id) then return fid;else raise exception 'Файл недоступен';end if;end if;
 if (select count(*) from respectlogistic_driver_shift_files where report_id=r.id)>=6 then raise exception 'Не более 6 фотографий на смену';end if;
 if tid is not null and not exists(select 1 from crm_trips where id=tid and owner_id=a.owner_id and app_scope='respectlogistic' and driver_id=a.driver_id and vehicle_id=r.vehicle_id and deleted_at is null and trip_date=r.shift_date) then raise exception 'Выберите свой рейс на машине за эту смену';end if;
 bytes=decode(p_base64,'base64');
 if octet_length(bytes)<4 or octet_length(bytes)>2097152 or encode(substring(bytes from 1 for 3),'hex')<>'ffd8ff' then raise exception 'Отправьте фотографию JPEG до 2 МБ';end if;
 insert into respectlogistic_driver_shift_files(id,report_id,owner_id,driver_id,trip_id,kind,file_name,mime_type,file_size,data) values(fid,r.id,a.owner_id,a.driver_id,tid,kind_value,left(coalesce(nullif(p_record->>'file_name',''),'Фото смены.jpg'),200),'image/jpeg',octet_length(bytes),bytes);
 if tid is not null then update crm_trips set documents_confirmed=false where id=tid;end if;return fid;
end$$;

create function public.respectlogistic_shift_action(p_id uuid,p_action text,p_expected timestamptz,p_record jsonb default '{}',p_token text default null) returns void language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;r respectlogistic_driver_shift_reports;note text=left(coalesce(p_record->>'note',''),4000);begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 select * into r from respectlogistic_driver_shift_reports where id=p_id and owner_id=actor for update;
 if actor is null or r.id is null or (a.driver_id is not null and r.driver_id<>a.driver_id) then raise exception 'Отчёт недоступен';end if;
 if r.modified_at is distinct from p_expected then raise exception 'Отчёт изменён. Обновите данные';end if;
 if p_action='submit' and a.driver_id is not null then
  if r.status<>'draft' or not exists(select 1 from respectlogistic_driver_shift_files where report_id=r.id and kind='odometer') then raise exception 'Добавьте фото одометра перед отправкой';end if;
  update respectlogistic_driver_shift_reports set status='submitted' where id=r.id;
 elsif p_action='cancel' and a.driver_id is not null and r.status='draft' then update respectlogistic_driver_shift_reports set status='cancelled' where id=r.id;
 elsif a.driver_id is null and p_action='review' and r.status='submitted' then
  perform id from crm_vehicles where id=r.vehicle_id and owner_id=actor and app_scope='respectlogistic' and carrier_id is null and not is_subcontractor_vehicle and archived_at is null and odometer_km<=r.odometer for update;
  if not found then raise exception 'Пробег меньше текущего либо машина недоступна';end if;
  update crm_vehicles set odometer_km=r.odometer where id=r.vehicle_id;
  update respectlogistic_driver_shift_reports set status='reviewed',dispatcher_note=note where id=r.id;
 elsif a.driver_id is null and p_action='reject' and r.status='submitted' then
  if trim(note)='' then raise exception 'Укажите причину возврата отчёта';end if;
  update respectlogistic_driver_shift_reports set status='rejected',dispatcher_note=note where id=r.id;
 elsif a.driver_id is null and p_action='supplies' and r.status in ('submitted','reviewed') and p_record->>'supplies_status' in ('open','in_progress','done') then
  update respectlogistic_driver_shift_reports set supplies_status=p_record->>'supplies_status',dispatcher_note=note where id=r.id;
 else raise exception 'Недоступное действие по отчёту';end if;
 update respectlogistic_driver_shift_reports set modified_at=clock_timestamp() where id=r.id;
end$$;

create function public.respectlogistic_driver_file(p_id uuid,p_token text default null) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;f respectlogistic_driver_shift_files;begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 select * into f from respectlogistic_driver_shift_files where id=p_id and owner_id=actor;
 if actor is null or f.id is null or (a.driver_id is not null and f.driver_id<>a.driver_id) then raise exception 'Файл недоступен';end if;
 return jsonb_build_object('name',f.file_name,'mime_type',f.mime_type,'base64',encode(f.data,'base64'));
end$$;

create or replace function public.respectlogistic_confirm_trip_documents(p_trip_id uuid) returns void language plpgsql security definer set search_path=public,pg_temp as $$begin
 perform id from crm_trips where id=p_trip_id and owner_id=auth.uid() and app_scope='respectlogistic' and deleted_at is null for update;
 if not found then raise exception 'Рейс недоступен';end if;
 if not exists(select 1 from respectlogistic_trip_files where trip_id=p_trip_id and owner_id=auth.uid()) and not exists(select 1 from respectlogistic_driver_shift_files where trip_id=p_trip_id and owner_id=auth.uid()) then raise exception 'Сначала загрузите документы водителя';end if;
 update crm_trips set documents_confirmed=true where id=p_trip_id;
end$$;
revoke all on function public.respectlogistic_save_driver_note(jsonb,timestamptz,boolean),public.respectlogistic_read_driver_note(uuid,text),public.respectlogistic_driver_extras(text),public.respectlogistic_create_shift_report(text,jsonb),public.respectlogistic_driver_upload_photo(text,jsonb,text),public.respectlogistic_shift_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_driver_file(uuid,text) from public,anon,authenticated;
grant execute on function public.respectlogistic_save_driver_note(jsonb,timestamptz,boolean),public.respectlogistic_read_driver_note(uuid,text),public.respectlogistic_driver_extras(text),public.respectlogistic_shift_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_driver_file(uuid,text) to authenticated;
grant execute on function public.respectlogistic_read_driver_note(uuid,text),public.respectlogistic_driver_extras(text),public.respectlogistic_create_shift_report(text,jsonb),public.respectlogistic_driver_upload_photo(text,jsonb,text),public.respectlogistic_shift_action(uuid,text,timestamptz,jsonb,text),public.respectlogistic_driver_file(uuid,text) to anon;
notify pgrst,'reload schema';
