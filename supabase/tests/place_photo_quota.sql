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
  coalesce(
    (
      select proconfig @> array['search_path=public, app']
      from pg_proc
      where oid = 'public.consume_place_photo_quota()'::regprocedure
    ),
    false
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
insert into app.place_photo_request_counters (scope, period_key, request_count)
values
  ('global', to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM'), 900),
  ('user:user_quota_test', to_char(statement_timestamp() at time zone 'UTC', 'YYYY-MM-DD'), 120);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_quota_test', true);
select ok(
  public.consume_place_photo_quota(),
  'authenticated request is admitted despite legacy counters at their former limits'
);
select is(
  (
    select bool_and(public.consume_place_photo_quota())
    from generate_series(1, 250)
  ),
  true,
  'repeated authenticated requests are admitted without an application-side cap'
);

reset role;
select is(
  (select count(*) from app.place_photo_request_counters),
  2::bigint,
  'admission no longer mutates the legacy counter table'
);

select * from finish();
rollback;
