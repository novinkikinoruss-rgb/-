create function public.respectlogistic_read_trip_progress() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$begin
 if auth.uid() is null then raise exception 'Войдите в CRM';end if;
 return coalesce((select jsonb_agg(to_jsonb(latest)) from (
 select distinct on (e.trip_id) e.trip_id,e.driver_id,e.stage,e.created_at from respectlogistic_driver_trip_events e join crm_trips t on t.id=e.trip_id and t.owner_id=e.owner_id and t.driver_id=e.driver_id
 where e.owner_id=auth.uid() and t.app_scope='respectlogistic' and t.deleted_at is null order by e.trip_id,e.id desc
 ) latest),'[]');
end$$;
revoke all on function public.respectlogistic_read_trip_progress() from public,anon,authenticated;
grant execute on function public.respectlogistic_read_trip_progress() to authenticated;
notify pgrst,'reload schema';
