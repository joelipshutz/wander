begin;

create extension if not exists pgtap;

select plan(22);

select is(
  (select enabled from public.feature_flags where key = 'first_visit_nux' and user_id is null),
  true,
  'first-visit NUX is globally enabled'
);

select is(
  (
    select value_type || ':' || integer_value::text
    from public.feature_flags
    where key = 'place_profile_action_variant' and user_id is null
  ),
  'integer:5',
  'place-profile action variant is a registered integer flag'
);

select has_column(
  'public',
  'feature_flags',
  'value_type',
  'feature flags declare their value type'
);

select has_column(
  'public',
  'feature_flags',
  'integer_value',
  'feature flags can store integer values'
);

select results_eq(
  $$
    select conname::text
    from pg_constraint
    where conrelid = 'public.feature_flags'::regclass
      and conname in (
        'feature_flags_value_type_check',
        'feature_flags_registered_key_check',
        'feature_flags_key_value_contract_check'
      )
    order by conname
  $$,
  $$
    select conname
    from (
      values
        ('feature_flags_key_value_contract_check'),
        ('feature_flags_registered_key_check'),
        ('feature_flags_value_type_check')
    ) as expected(conname)
    order by conname
  $$,
  'feature flags enforce their registered key, type, and range contracts'
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

select is(
  (select enabled from public.feature_flags where key = 'semantic_place_search_v1' and user_id is null),
  false,
  'semantic place search remains globally disabled for Release builds'
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

select throws_like(
  $$ insert into public.feature_flags(key, user_id, enabled) values ('other_flag', null, true) $$,
  '%feature_flags_registered_key_check%',
  'unknown feature flag keys are rejected by the registry constraint'
);

select throws_like(
  $$ insert into public.feature_flags(key, user_id, enabled, value_type, integer_value) values ('debug_settings', null, false, 'integer', 2) $$,
  '%feature_flags_key_value_contract_check%',
  'boolean feature flags reject integer storage'
);

select throws_like(
  $$ insert into public.feature_flags(key, user_id, enabled, value_type, integer_value) values ('place_profile_action_variant', null, false, 'integer', 6) $$,
  '%feature_flags_key_value_contract_check%',
  'integer feature flags reject out-of-range values'
);

select throws_like(
  $$ insert into public.feature_flags(key, user_id, enabled, value_type, integer_value) values ('place_profile_action_variant', null, false, 'integer', null) $$,
  '%feature_flags_key_value_contract_check%',
  'integer feature flags require a concrete value'
);

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
