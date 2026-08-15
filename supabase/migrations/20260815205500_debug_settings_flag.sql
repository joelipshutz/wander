begin;

-- Debug settings defaults off for everyone. The two tester overrides are
-- managed as hosted feature-flag data after their current profiles are
-- verified, keeping environment-specific account ids out of migrations and
-- out of the iOS binary.
insert into public.feature_flags(key, user_id, enabled)
values ('debug_settings', null, false)
on conflict (key) where user_id is null
do update set enabled = excluded.enabled;

commit;
