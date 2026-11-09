begin;
insert into auth.users(id) select gen_random_uuid() where not exists(select 1 from auth.users);
select set_config('request.jwt.claim.sub',(select id::text from auth.users order by id limit 1),true) is not null as identity_ready;
set local role authenticated;
do $$
declare actor uuid=auth.uid(); other_actor uuid=gen_random_uuid(); result jsonb; affected integer;
begin
 if actor is null then raise exception 'TEST: an existing authenticated user is required';end if;
 if has_function_privilege('anon','public.respectlogistic_read_ui_settings()','EXECUTE') or has_function_privilege('anon','public.respectlogistic_save_ui_setting(uuid,text,jsonb)','EXECUTE') then raise exception 'TEST: anonymous settings RPC access';end if;
 perform public.respectlogistic_save_ui_setting(actor,'tables','{"density":"comfortable","wrap":false}');
 perform public.respectlogistic_save_ui_setting(actor,'trips','{"order":["number","date"],"widths":{"number":170},"pageSize":100}');
 result=public.respectlogistic_read_ui_settings();
 if result#>>'{tables,density}'<>'comfortable' or (result#>>'{trips,pageSize}')::integer<>100 then raise exception 'TEST: settings not persisted by key';end if;
 perform public.respectlogistic_save_ui_setting(actor,'tables','{"density":"compact","wrap":true}');
 result=public.respectlogistic_read_ui_settings();
 if result#>>'{tables,density}'<>'compact' or (result#>>'{trips,pageSize}')::integer<>100 then raise exception 'TEST: update lost another settings key';end if;
 begin
  perform public.respectlogistic_save_ui_setting(other_actor,'tables','{}');
  raise exception 'TEST: another owner accepted' using errcode='P0002';
 exception when insufficient_privilege then null;end;
 begin
  perform public.respectlogistic_save_ui_setting(actor,'unknown','{}');
  raise exception 'TEST: arbitrary settings key accepted' using errcode='P0002';
 exception when raise_exception then null;end;
 begin
  perform public.respectlogistic_save_ui_setting(actor,'tables','[]');
  raise exception 'TEST: non-object accepted' using errcode='P0002';
 exception when raise_exception then null;end;
 begin
  perform public.respectlogistic_save_ui_setting(actor,'tables',jsonb_build_object('oversized',repeat('x',17000)));
  raise exception 'TEST: oversized value accepted' using errcode='P0002';
 exception when raise_exception then null;end;
 perform set_config('request.jwt.claim.sub',other_actor::text,true);
 if public.respectlogistic_read_ui_settings()<>'{}'::jsonb then raise exception 'TEST: another user read private preferences';end if;
 update public.respectlogistic_user_settings set setting_value='{}' where owner_id=actor;
 get diagnostics affected=row_count;if affected<>0 then raise exception 'TEST: RLS allowed another owner update';end if;
 begin
  insert into public.respectlogistic_user_settings(owner_id,setting_key,setting_value) values(actor,'tables','{}');
  raise exception 'TEST: RLS allowed another owner insert' using errcode='P0002';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 if public.respectlogistic_read_ui_settings()#>>'{tables,density}'<>'compact' then raise exception 'TEST: another user changed settings';end if;
end;
$$;
select 'PASS: persistence, independent keys, update, size validation, owner assertion, RLS and anonymous denial' as verification;
rollback;
