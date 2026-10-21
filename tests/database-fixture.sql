create schema auth;
create role anon nologin;
create role authenticated nologin;
create table auth.users(id uuid primary key,aud text,role text,email text);
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
grant usage on schema public,auth to anon,authenticated;
grant execute on function auth.uid() to anon,authenticated;
