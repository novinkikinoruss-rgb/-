-- Replace one dated assignment atomically; reported work and issued snapshots remain immutable.
create function public.respectlogistic_replace_dispatch_driver(p_shift uuid,p_expected integer,p_driver uuid default null,p_driver_name text default '',p_send boolean default false) returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare actor uuid=auth.uid();old respectlogistic_dispatch_shifts;r respectlogistic_dispatch_requests;replacement respectlogistic_dispatch_shifts;begin
 if actor is null then raise exception 'Войдите в CRM';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into old from respectlogistic_dispatch_shifts where id=p_shift and owner_id=actor for update;
 if old.id is null or old.version is distinct from p_expected or old.status in ('completed','cancelled') then raise exception 'Назначение изменено или недоступно. Обновите список';end if;
 if exists(select 1 from respectlogistic_dispatch_results where shift_id=old.id and owner_id=actor) then raise exception 'По смене уже есть перевозки. Исторического водителя менять нельзя';end if;
 if old.driver_id is not null and exists(select 1 from respectlogistic_driver_duties where owner_id=actor and driver_id=old.driver_id and vehicle_id=old.vehicle_id and ended_at is null) then raise exception 'Сначала завершите открытый период управления прежнего водителя на этой машине';end if;
 select * into r from respectlogistic_dispatch_requests where id=old.request_id and owner_id=actor and cancelled_at is null and deleted_at is null for update;
 if r.id is null then raise exception 'Заявка отменена или недоступна';end if;
 perform respectlogistic_assign_dispatch(r.id,r.version,old.shift_date,old.shift_date,jsonb_build_array(jsonb_build_object('vehicle_id',old.vehicle_id,'driver_id',p_driver,'driver_name',p_driver_name,'carrier_id',old.carrier_id)));
 select * into replacement from respectlogistic_dispatch_shifts where owner_id=actor and request_id=r.id and vehicle_id=old.vehicle_id and shift_date=old.shift_date and status<>'cancelled';
 if replacement.id is null or replacement.id=old.id then raise exception 'Выберите другого водителя';end if;
 if coalesce(p_send,false) then perform respectlogistic_dispatch_action(replacement.id,replacement.version,'send');end if;
 insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action,detail) values(actor,r.id,replacement.id,'driver_replaced',jsonb_build_object('previous_shift_id',old.id,'previous_driver_id',old.driver_id,'driver_id',replacement.driver_id));
 return replacement.id;
end$$;
revoke all on function public.respectlogistic_replace_dispatch_driver(uuid,integer,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.respectlogistic_replace_dispatch_driver(uuid,integer,uuid,text,boolean) to authenticated;
notify pgrst,'reload schema';
