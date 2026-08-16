begin;

create extension if not exists pgtap;

select plan(13);

select is(
  (select enabled from public.feature_flags where key = 'first_visit_nux' and user_id is null),
  true,
  'first-visit NUX is globally enabled'
);

select is(
  (select enabled from public.feature_flags where key = 'debug_settings' and user_id is null),
  false,
  'debug settings is globally disabled'
);

select is(
  (select enabled from public.feature_flags where key = 'place_profile_save_tray_v1' and user_id is null),
  false,
  'place-profile save tray is globally disabled'
);

select ok(
  has_table_privilege('authenticated', 'public.feature_flags', 'select'),
  'authenticated clients can read resolved flag rows'
);

select ok(
  not has_table_privilege('authenticated', 'public.feature_flags', 'insert')
    and not has_table_privilege('authenticated', 'public.feature_flags', 'update')
    and not has_table_privilege('authenticated', 'public.feature_flags', 'delete'),
  'authenticated clients cannot mutate feature flags'
);

select ok(
  not has_table_privilege('anon', 'public.feature_flags', 'select'),
  'anonymous clients cannot read feature flags'
);

insert into public.profiles(id, handle, display_name)
values
  ('user_feature_flag_a', 'featureflaga', 'Feature Flag A'),
  ('user_feature_flag_b', 'featureflagb', 'Feature Flag B');

insert into public.feature_flags(key, user_id, enabled)
values
  ('first_visit_nux', 'user_feature_flag_a', false),
  ('first_visit_nux', 'user_feature_flag_b', true);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_feature_flag_a', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select count(*)::integer from public.feature_flags where key = 'first_visit_nux'),
  2,
  'a user sees the global row and only their own override'
);

select is(
  (select count(*)::integer from public.feature_flags where key = 'debug_settings'),
  1,
  'a normal user sees only the globally disabled debug-settings row'
);

select is(
  (
    select enabled
    from public.feature_flags
    where key = 'first_visit_nux'
      and user_id = app.current_user_id()
  ),
  false,
  'the current user can read their disabled override'
);

select is(
  (
    select count(*)::integer
    from public.feature_flags
    where user_id = 'user_feature_flag_b'
  ),
  0,
  'the current user cannot read another user override'
);

select throws_ok(
  $$ insert into public.feature_flags(key, user_id, enabled) values ('other_flag', 'user_feature_flag_a', true) $$,
  '42501',
  'permission denied for table feature_flags',
  'authenticated clients cannot insert overrides'
);

select throws_ok(
  $$ update public.feature_flags set enabled = true where user_id = 'user_feature_flag_a' $$,
  '42501',
  'permission denied for table feature_flags',
  'authenticated clients cannot update overrides'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$ select * from public.feature_flags $$,
  '42501',
  'permission denied for table feature_flags',
  'anonymous clients cannot read flags'
);

select * from finish();

rollback;
