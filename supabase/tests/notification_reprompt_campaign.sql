begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(10);

select is(
  (select value_type || ':' || integer_value::text from public.feature_flags
   where key = 'notification_reprompt_campaign' and user_id is null),
  'integer:0', 'notification re-prompt campaigns start disabled'
);
select throws_like(
  $$ update public.feature_flags set integer_value = -1 where key = 'notification_reprompt_campaign' and user_id is null $$,
  '%feature_flags_key_value_contract_check%', 'negative campaign versions are rejected'
);
select throws_like(
  $$ update public.feature_flags set integer_value = 1000001 where key = 'notification_reprompt_campaign' and user_id is null $$,
  '%feature_flags_key_value_contract_check%', 'campaign versions share the iOS upper bound'
);
select throws_like(
  $$ update public.feature_flags set value_type = 'boolean', integer_value = null where key = 'notification_reprompt_campaign' and user_id is null $$,
  '%feature_flags_key_value_contract_check%', 'campaigns require integer storage'
);
select ok(
  has_table_privilege('authenticated', 'public.feature_flags', 'select')
    and not has_table_privilege('authenticated', 'public.feature_flags', 'insert')
    and not has_table_privilege('authenticated', 'public.feature_flags', 'update')
    and not has_table_privilege('authenticated', 'public.feature_flags', 'delete'),
  'clients retain read-only access to the remote control plane'
);

insert into public.profiles(id, handle, display_name) values
  ('user_notification_reprompt_a', 'notification_reprompt_a', 'Notification Test A'),
  ('user_notification_reprompt_b', 'notification_reprompt_b', 'Notification Test B');
insert into public.feature_flags(key, user_id, enabled, value_type, integer_value) values
  ('notification_reprompt_campaign', 'user_notification_reprompt_a', false, 'integer', 7),
  ('notification_reprompt_campaign', 'user_notification_reprompt_b', false, 'integer', 9);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notification_reprompt_a', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select is(
  (select integer_value from public.feature_flags
   where key = 'notification_reprompt_campaign' and user_id = app.current_user_id()),
  7, 'the targeted account receives its own campaign version'
);
select is(
  (select count(*)::integer from public.feature_flags where key = 'notification_reprompt_campaign'),
  2, 'the account sees the global campaign and its own override'
);
select is(
  (select count(*)::integer from public.feature_flags
   where key = 'notification_reprompt_campaign' and user_id = 'user_notification_reprompt_b'),
  0, 'another account target remains hidden'
);
select throws_ok(
  $$ update public.feature_flags set integer_value = 8 where key = 'notification_reprompt_campaign' $$,
  '42501', 'permission denied for table feature_flags', 'clients cannot trigger a remote campaign'
);
reset role;
set local role anon;
select throws_ok(
  $$ select * from public.feature_flags $$,
  '42501', 'permission denied for table feature_flags', 'anonymous clients cannot read campaigns'
);
reset role;
select * from finish();
rollback;
