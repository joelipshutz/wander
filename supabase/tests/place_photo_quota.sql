begin;

create extension if not exists pgtap;

select plan(10);

select has_function('public', 'consume_place_photo_quota', array[]::text[]);
select function_privs_are(
  'public',
  'consume_place_photo_quota',
  array[]::text[],
  'authenticated',
  array['EXECUTE']
);
select function_privs_are(
  'public',
  'consume_place_photo_quota',
  array[]::text[],
  'anon',
  array[]::text[]
);
select is(
  (select prosecdef from pg_proc where oid = 'public.consume_place_photo_quota()'::regprocedure),
  true,
  'quota RPC is security definer'
);
select ok(
  'search_path=public, app' = any(
    (select proconfig from pg_proc where oid = 'public.consume_place_photo_quota()'::regprocedure)
  ),
  'quota RPC pins its search path'
);
select table_privs_are(
  'app',
  'place_photo_request_counters',
  'authenticated',
  array[]::text[]
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  'select public.consume_place_photo_quota()',
  '42501',
  'not_authenticated'
);

reset role;
truncate table app.place_photo_request_counters;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_quota_test', true);
select ok(public.consume_place_photo_quota(), 'authenticated request is admitted below the caps');

reset role;
insert into app.place_photo_request_counters (scope, period_key, request_count)
values ('user:user_quota_test', to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM-DD'), 120)
on conflict (scope) do update set period_key = excluded.period_key, request_count = excluded.request_count;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_quota_test', true);
select is(public.consume_place_photo_quota(), false, 'per-user daily cap rejects additional requests');

reset role;
truncate table app.place_photo_request_counters;
insert into app.place_photo_request_counters (scope, period_key, request_count)
values ('global', to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM'), 900);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_quota_test', true);
select is(public.consume_place_photo_quota(), false, 'global monthly cap rejects paid-overage requests');

select * from finish();
rollback;
