begin;
select set_config('request.jwt.claim.sub',(select id::text from auth.users limit 1),true) is not null as identity_ready;
do $$declare actor uuid=auth.uid();s jsonb;begin
 s=respectlogistic_google_settings('save','{"clientId":"test.apps.googleusercontent.com","clientSecret":"fixture-secret"}');
 if (s->>'configured')::boolean or not(s->>'hasClient')::boolean or s::text like '%fixture-secret%' then raise exception 'TEST: unsafe or premature status';end if;
 perform respectlogistic_google_settings('token','{"refreshToken":"fixture-refresh"}');
 s=respectlogistic_google_settings();if not(s->>'configured')::boolean or s::text like '%fixture-refresh%' then raise exception 'TEST: token leaked or connection missing';end if;
 perform respectlogistic_google_settings('save','{"clientId":"test.apps.googleusercontent.com","clientSecret":""}');
 if respectlogistic_google_settings('credentials')->>'refreshToken'<>'fixture-refresh' then raise exception 'TEST: blank secret reset connection';end if;
 perform respectlogistic_google_settings('save','{"clientId":"changed.apps.googleusercontent.com","clientSecret":"changed-secret"}');
 if (respectlogistic_google_settings()->>'configured')::boolean then raise exception 'TEST: changed credentials retained stale token';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 if respectlogistic_google_settings('credentials')<>'{}'::jsonb then raise exception 'TEST: foreign credentials visible';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
end$$;
set local role authenticated;
do $$begin
 begin perform encrypted_config from respectlogistic_google_connections;raise exception using message='TEST: raw credentials readable',errcode='P0002';exception when insufficient_privilege then null;end;
end$$;
set local role anon;
do $$begin
 begin perform respectlogistic_google_settings();raise exception using message='TEST: anonymous Google settings',errcode='P0002';exception when insufficient_privilege then null;end;
end$$;
reset role;
rollback;
select 'PASS: Google encryption, safe status, token replacement, owner isolation and denied raw secrets/anonymous RPC. Rolled back.' as verification;
