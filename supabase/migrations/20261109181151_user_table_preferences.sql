-- Personal view preferences for respectlogistic; no customer/finance records.
create table public.respectlogistic_user_settings (
 owner_id uuid not null references auth.users(id) on delete cascade,
 setting_key text not null check (setting_key in ('tables','trips')),
 setting_value jsonb not null check (jsonb_typeof(setting_value)='object' and octet_length(setting_value::text)<=16384),
 modified_at timestamptz not null default now(),
 primary key(owner_id,setting_key)
);
alter table public.respectlogistic_user_settings enable row level security;
create policy respectlogistic_user_settings_owner on public.respectlogistic_user_settings
 for all to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
revoke all on public.respectlogistic_user_settings from public,anon,authenticated;
grant select,insert,update on public.respectlogistic_user_settings to authenticated;

create function public.respectlogistic_read_ui_settings() returns jsonb
 language plpgsql stable security invoker set search_path='' as $$
declare actor uuid=(select auth.uid()); result jsonb;
begin
 if actor is null then raise exception 'Войдите в CRM' using errcode='42501';end if;
 select coalesce(jsonb_object_agg(setting_key,setting_value),'{}'::jsonb) into result
 from public.respectlogistic_user_settings where owner_id=actor;
 return result;
end;
$$;
create function public.respectlogistic_save_ui_setting(p_owner uuid,p_key text,p_value jsonb) returns void
 language plpgsql security invoker set search_path='' as $$
declare actor uuid=(select auth.uid());
begin
 if actor is null or p_owner is distinct from actor then raise exception 'Настройки относятся к другому пользователю' using errcode='42501';end if;
 if p_key is null or p_key not in ('tables','trips') then raise exception 'Неизвестный раздел настроек';end if;
 if p_value is null or jsonb_typeof(p_value)<>'object' or octet_length(p_value::text)>16384 then raise exception 'Некорректные настройки';end if;
 insert into public.respectlogistic_user_settings(owner_id,setting_key,setting_value)
 values(actor,p_key,p_value)
 on conflict(owner_id,setting_key) do update set setting_value=excluded.setting_value,modified_at=now();
end;
$$;
revoke all on function public.respectlogistic_read_ui_settings() from public,anon,authenticated;
revoke all on function public.respectlogistic_save_ui_setting(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.respectlogistic_read_ui_settings() to authenticated;
grant execute on function public.respectlogistic_save_ui_setting(uuid,text,jsonb) to authenticated;
comment on table public.respectlogistic_user_settings is 'Owner-scoped CRM list appearance; browser storage is not used for view settings.';
