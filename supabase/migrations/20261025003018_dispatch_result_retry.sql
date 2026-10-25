-- A retry cannot silently replace an already recorded unloading quantity.
create or replace function public.respectlogistic_dispatch_result(p_shift uuid,p_record jsonb,p_expected integer,p_token text default null) returns uuid language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare actor uuid=auth.uid();a respectlogistic_driver_accounts;s respectlogistic_dispatch_shifts;rid uuid=(p_record->>'id')::uuid;existing respectlogistic_dispatch_results;vol numeric=(p_record->>'volume')::numeric;u text=p_record->>'unit';tid uuid;tripdate date;oldsub text=current_setting('request.jwt.claim.sub',true);oldzone text=current_setting('TimeZone');begin
 if p_token is not null then a=respectlogistic_require_driver(p_token);actor=a.owner_id;end if;
 if actor is null or rid is null or octet_length(p_record::text)>4000 then raise exception 'Проверьте данные выгрузки';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text||'-dispatch',0));
 select * into s from respectlogistic_dispatch_shifts where id=p_shift and owner_id=actor for update;
 if s.id is null or p_token is not null and (s.driver_id is distinct from a.driver_id or s.carrier_id is not null) then raise exception 'Смена недоступна';end if;
 select * into existing from respectlogistic_dispatch_results where id=rid;
 if existing.id is not null then if existing.owner_id<>actor or existing.shift_id<>s.id then raise exception 'Запись недоступна';end if;if existing.volume is distinct from vol or existing.unit is distinct from u then raise exception 'Эта выгрузка уже сохранена с другим количеством. Обновите список';end if;return existing.trip_id;end if;
 if s.version is distinct from p_expected or s.status not in ('accepted','draft','sent') or p_token is not null and s.status<>'accepted' then raise exception 'Примите актуальную смену или обновите её';end if;
 if vol is null or vol<=0 or vol>1000000 or vol::text in ('NaN','Infinity','-Infinity') or u is null or u not in ('т','м³') or u is distinct from s.snapshot->>'unit' then raise exception 'Укажите фактический объём в единице услуги (т или м³)';end if;
 tripdate=coalesce(nullif(p_record->>'date','')::date,s.shift_date);
 if tripdate<s.shift_date or tripdate>s.shift_date+1 or tripdate>(clock_timestamp() at time zone (s.snapshot->>'time_zone'))::date then raise exception 'Проверьте дату фактической выгрузки';end if;
 if p_token is not null and not exists(select 1 from respectlogistic_driver_duties d where d.owner_id=actor and d.driver_id=a.driver_id and d.vehicle_id=s.vehicle_id and d.ended_at is null) then raise exception 'Сначала начните смену на назначенной машине';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);perform set_config('TimeZone',s.snapshot->>'time_zone',true);
 tid=crm_save_trip(jsonb_build_object('id',rid,'customer_id',s.snapshot->>'customer_id','site_id',s.snapshot->>'site_id','vehicle_id',s.vehicle_id,'driver_id',s.driver_id,'carrier_id',s.carrier_id,'vehicle_source',case when s.carrier_id is null then 'own' else 'contractor' end,'trip_date',tripdate,'loading_address',s.snapshot->>'loading_address','unloading_address',s.snapshot->>'unloading_address','service_name',s.snapshot->>'service_name','unit',u,'volume',vol,'unit_price',(s.snapshot->>'unit_price')::numeric,'status','delivered'),null);
 insert into respectlogistic_dispatch_results(id,owner_id,shift_id,trip_id,volume,unit) values(rid,actor,s.id,tid,vol,u);
 insert into respectlogistic_dispatch_events(owner_id,request_id,shift_id,action,detail) values(actor,s.request_id,s.id,'unloaded',jsonb_build_object('trip_id',tid,'volume',vol,'unit',u));
 perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);perform set_config('TimeZone',oldzone,true);return tid;
exception when others then perform set_config('request.jwt.claim.sub',coalesce(oldsub,''),true);perform set_config('TimeZone',oldzone,true);raise;
end$$;

notify pgrst,'reload schema';
