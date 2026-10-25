-- Store waybill details separately from actual unload quantities. Existing shift history stays immutable.
create or replace function public.respectlogistic_save_dispatch(p_record jsonb,p_expected integer default null,p_action text default 'save') returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();rid uuid=(p_record->>'id')::uuid;r respectlogistic_dispatch_requests;s respectlogistic_sites;svc respectlogistic_services;v_payload jsonb;df date;dt date;zone text;num integer;begin
 if actor is null or rid is null or jsonb_typeof(p_record) is distinct from 'object' or octet_length(p_record::text)>30000 then raise exception 'Проверьте заявку';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into r from respectlogistic_dispatch_requests where id=rid for update;
 if r.id is not null and (r.owner_id<>actor or r.version is distinct from p_expected or r.deleted_at is not null) then raise exception 'Заявка недоступна или изменена. Обновите список';end if;
 if p_action in ('cancel','delete') then
  if r.id is null then raise exception 'Заявка не найдена';end if;
  update respectlogistic_dispatch_requests set cancelled_at=clock_timestamp(),deleted_at=case when p_action='delete' and not exists(select 1 from respectlogistic_dispatch_shifts where request_id=rid and sent_at is not null) then clock_timestamp() else deleted_at end,version=version+1,modified_at=clock_timestamp() where id=rid;
  update respectlogistic_dispatch_shifts set status='cancelled',version=version+1,modified_at=clock_timestamp() where request_id=rid and owner_id=actor and status not in ('completed','cancelled');
  insert into respectlogistic_dispatch_events(owner_id,request_id,action) values(actor,rid,'cancelled');return rid;
 end if;
 if p_action<>'save' or r.cancelled_at is not null then raise exception 'Отменённую заявку нельзя изменить';end if;
 df=(p_record->>'date_from')::date;dt=(p_record->>'date_to')::date;zone=coalesce(nullif(p_record->>'time_zone',''),'Europe/Moscow');
 if df is null or dt is null or dt<df or dt-df>366 then raise exception 'Укажите период до 366 дней';end if;
 if not exists(select 1 from pg_timezone_names where name=zone) then raise exception 'Неизвестный часовой пояс';end if;
 select * into s from respectlogistic_sites where id=(p_record->>'site_id')::uuid and owner_id=actor and customer_id=(p_record->>'customer_id')::uuid;
 if s.id is null then raise exception 'Выберите объект выбранного заказчика этой CRM';end if;
 select * into svc from respectlogistic_services where id=s.service_id and owner_id=actor and customer_id=s.customer_id;
 if svc.id is null then raise exception 'Услуга объекта недоступна';end if;
 if coalesce(trim(p_record->>'loading_address'),'')='' or coalesce(trim(p_record->>'unloading_address'),'')='' or coalesce(trim(p_record->>'contact_name'),'')='' or coalesce(trim(p_record->>'contact_phone'),'')='' then raise exception 'Укажите адреса, имя и телефон ответственного';end if;
 if nullif(p_record->>'loading_from','') is null or nullif(p_record->>'loading_to','') is null or nullif(p_record->>'unloading_from','') is null or nullif(p_record->>'unloading_to','') is null then raise exception 'Укажите режим погрузки и выгрузки';end if;
 perform (p_record->>'loading_from')::time,(p_record->>'loading_to')::time,(p_record->>'unloading_from')::time,(p_record->>'unloading_to')::time;
 if (p_record->>'loading_from')::time=(p_record->>'loading_to')::time then raise exception 'Укажите разное начало и окончание смены';end if;
 v_payload=jsonb_build_object('loading_address',trim(p_record->>'loading_address'),'loading_point',coalesce(p_record->>'loading_point',''),'unloading_address',trim(p_record->>'unloading_address'),'unloading_point',coalesce(p_record->>'unloading_point',''),'cargo_name',coalesce(p_record->>'cargo_name',''),'cargo_mass',coalesce(p_record->>'cargo_mass',''),'loading_from',p_record->>'loading_from','loading_to',p_record->>'loading_to','unloading_from',p_record->>'unloading_from','unloading_to',p_record->>'unloading_to','contact_name',trim(p_record->>'contact_name'),'contact_phone',trim(p_record->>'contact_phone'),'sender',coalesce(p_record->>'sender',''),'recipient',coalesce(p_record->>'recipient',''),'notes',coalesce(p_record->>'notes',''),'time_zone',zone,'service_name',svc.name,'unit',svc.unit,'unit_price',svc.price_kopecks/100.0,'site_name',s.payload->>'name');
 if r.id is null then
  insert into respectlogistic_dispatch_counters(owner_id,request_no) values(actor,1) on conflict(owner_id) do update set request_no=respectlogistic_dispatch_counters.request_no+1 returning request_no into num;
  insert into respectlogistic_dispatch_requests(id,owner_id,number,customer_id,site_id,date_from,date_to,payload) values(rid,actor,num,s.customer_id,s.id,df,dt,v_payload);
 else
  if exists(select 1 from respectlogistic_dispatch_shifts where request_id=rid and status not in ('cancelled','rejected') and (shift_date<df or shift_date>dt)) then raise exception 'За пределами нового периода есть смены. Сначала отмените их';end if;
  update respectlogistic_dispatch_requests set customer_id=s.customer_id,site_id=s.id,date_from=df,date_to=dt,payload=v_payload,version=version+1,modified_at=clock_timestamp() where id=rid;
  if r.payload is distinct from v_payload or r.site_id<>s.id or r.customer_id<>s.customer_id then
   if exists(select 1 from respectlogistic_dispatch_shifts x join respectlogistic_dispatch_shifts other on other.owner_id=actor and other.request_id<>rid and other.status not in ('cancelled','rejected') and (other.vehicle_id=x.vehicle_id or x.driver_id is not null and other.driver_id=x.driver_id) where x.request_id=rid and x.owner_id=actor and x.status in ('draft','sent','accepted','rejected') and x.starts_at>clock_timestamp() and tstzrange(other.starts_at,other.ends_at,'[)')&&tstzrange((x.shift_date+(v_payload->>'loading_from')::time) at time zone zone,((x.shift_date+case when (v_payload->>'loading_to')::time<(v_payload->>'loading_from')::time then 1 else 0 end)+(v_payload->>'loading_to')::time) at time zone zone,'[)')) then raise exception 'Новый режим пересекается с другой заявкой машины или водителя';end if;
   -- Historical shifts and completed results remain immutable. Future changes require re-send and acceptance.
   update respectlogistic_dispatch_shifts set snapshot=(snapshot-'unit_price')||jsonb_build_object('number',r.number,'customer_id',s.customer_id,'site_id',s.id,'customer_name',(select c.payload->>'name' from respectlogistic_customers c where c.id=s.customer_id and c.owner_id=actor))||v_payload,status='draft',sent_at=null,seen_at=null,accepted_at=null,version=version+1,modified_at=clock_timestamp(),starts_at=(shift_date+(v_payload->>'loading_from')::time) at time zone zone,ends_at=((shift_date+case when (v_payload->>'loading_to')::time<(v_payload->>'loading_from')::time then 1 else 0 end)+(v_payload->>'loading_to')::time) at time zone zone where request_id=rid and status in ('draft','sent','accepted','rejected') and starts_at>clock_timestamp() and not exists(select 1 from respectlogistic_dispatch_results result where result.shift_id=respectlogistic_dispatch_shifts.id);
  end if;
 end if;
 insert into respectlogistic_dispatch_events(owner_id,request_id,action) values(actor,rid,case when r.id is null then 'created' else 'updated' end);return rid;
end$$;

notify pgrst,'reload schema';
