begin;

-- The floating place-profile save tray is an account-scoped canary. Keep the
-- global default off until the behavior train completes its internal soak.
insert into public.feature_flags(key, user_id, enabled)
values ('place_profile_save_tray_v1', null, false)
on conflict (key) where user_id is null
do update set enabled = excluded.enabled;

commit;
