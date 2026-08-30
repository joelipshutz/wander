begin;

create extension if not exists pgtap;

select plan(41);

select has_table(
  'app',
  'social_import_paid_work_admissions',
  'paid-work admission table exists in the private app schema'
);
select is(
  (
    select relrowsecurity
    from pg_class
    where oid = 'app.social_import_paid_work_admissions'::regclass
  ),
  true,
  'paid-work admission rows enforce RLS as defense in depth'
);
select columns_are(
  'app',
  'social_import_paid_work_admissions',
  array['id', 'user_id', 'client_request_id', 'state', 'started_at', 'finished_at'],
  'admission storage contains lifecycle metadata only'
);
select table_privs_are(
  'app',
  'social_import_paid_work_admissions',
  'authenticated',
  array[]::text[]
);
select table_privs_are(
  'app',
  'social_import_paid_work_admissions',
  'anon',
  array[]::text[]
);
select table_privs_are(
  'app',
  'social_import_paid_work_admissions',
  'service_role',
  array[]::text[]
);

select has_function(
  'public',
  'begin_social_import_paid_work',
  array['text']::text[]
);
select has_function(
  'public',
  'finish_social_import_paid_work',
  array['text', 'uuid']::text[]
);
select function_privs_are(
  'public',
  'begin_social_import_paid_work',
  array['text']::text[],
  'authenticated',
  array['EXECUTE']
);
select function_privs_are(
  'public',
  'begin_social_import_paid_work',
  array['text']::text[],
  'anon',
  array[]::text[]
);
select function_privs_are(
  'public',
  'begin_social_import_paid_work',
  array['text']::text[],
  'service_role',
  array[]::text[]
);
select function_privs_are(
  'public',
  'finish_social_import_paid_work',
  array['text', 'uuid']::text[],
  'authenticated',
  array['EXECUTE']
);
select function_privs_are(
  'public',
  'finish_social_import_paid_work',
  array['text', 'uuid']::text[],
  'anon',
  array[]::text[]
);
select function_privs_are(
  'public',
  'finish_social_import_paid_work',
  array['text', 'uuid']::text[],
  'service_role',
  array[]::text[]
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.begin_social_import_paid_work(text)'::regprocedure
  ),
  true,
  'begin admission is a narrow security-definer RPC'
);
select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.finish_social_import_paid_work(text,uuid)'::regprocedure
  ),
  true,
  'finish admission is a narrow security-definer RPC'
);
select ok(
  (
    select exists (
      select 1
      from unnest(coalesce(proconfig, array[]::text[])) as setting
      where setting in ('search_path=', 'search_path=""')
    )
    from pg_proc
    where oid = 'public.begin_social_import_paid_work(text)'::regprocedure
  ),
  'begin admission pins an empty search path'
);
select ok(
  (
    select exists (
      select 1
      from unnest(coalesce(proconfig, array[]::text[])) as setting
      where setting in ('search_path=', 'search_path=""')
    )
    from pg_proc
    where oid = 'public.finish_social_import_paid_work(text,uuid)'::regprocedure
  ),
  'finish admission pins an empty search path'
);
select ok(
  obj_description('app.social_import_paid_work_admissions'::regclass, 'pg_class')
    like '%never stores URLs, captions, media, or provider payloads%',
  'table metadata documents the no-content boundary'
);
select ok(
  obj_description('public.begin_social_import_paid_work(text)'::regprocedure, 'pg_proc') is not null
    and obj_description(
      'public.finish_social_import_paid_work(text,uuid)'::regprocedure,
      'pg_proc'
    ) is not null,
  'both RPCs document their narrow admission lifecycle purpose'
);
select ok(
  pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%pg_advisory_xact_lock%recme:social-import-paid-work:%'
    and pg_get_functiondef('public.finish_social_import_paid_work(text,uuid)'::regprocedure)
      like '%pg_advisory_xact_lock%recme:social-import-paid-work:%'
    and pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%app.current_user_id()%'
    and pg_get_functiondef('public.finish_social_import_paid_work(text,uuid)'::regprocedure)
      like '%app.current_user_id()%'
    and pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%social_import_apify_gemini_v1%'
  ,
  'RPCs serialize, derive ownership, and gate paid work on the hosted flag'
);
select ok(
  pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%interval ''5 minutes''%'
    and pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%active_count >= 3%'
    and pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%recent_start_count >= 20%'
    and pg_get_functiondef('public.begin_social_import_paid_work(text)'::regprocedure)
      like '%interval ''24 hours''%'
  ,
  'begin admission preserves stale expiry, concurrency, and rolling quota limits'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select throws_ok(
  $$select * from public.begin_social_import_paid_work('anonymous-request')$$,
  '42501',
  'not_authenticated'
);
select throws_ok(
  $$select public.finish_social_import_paid_work(
    'anonymous-request',
    '00000000-0000-0000-0000-000000000000'::uuid
  )$$,
  '42501',
  'not_authenticated'
);

reset role;
insert into public.profiles (id, handle, display_name)
values ('user_social_import_admission_test', 'socialimportadmission', 'Social Import Admission');
truncate table app.social_import_paid_work_admissions;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('flag-global-off')$$,
  $$values (false, 'disabled'::text)$$,
  'a missing account override honors the globally disabled paid-import flag'
);

reset role;
update public.feature_flags
set enabled = true
where key = 'social_import_apify_gemini_v1'
  and user_id is null;
insert into public.feature_flags (
  key, user_id, enabled, value_type, integer_value
) values (
  'social_import_apify_gemini_v1',
  'user_social_import_admission_test',
  false,
  'boolean',
  null
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('flag-account-off')$$,
  $$values (false, 'disabled'::text)$$,
  'an account-level disabled override wins over the enabled global flag'
);

reset role;
update public.feature_flags
set enabled = false
where key = 'social_import_apify_gemini_v1'
  and user_id is null;
update public.feature_flags
set enabled = true
where key = 'social_import_apify_gemini_v1'
  and user_id = 'user_social_import_admission_test';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select throws_ok(
  $$select * from public.begin_social_import_paid_work('bad request id')$$,
  '22023',
  'invalid_client_request_id'
);
select results_eq(
  $$
    select admitted, decision, admission_id is not null
    from public.begin_social_import_paid_work('request-first')
  $$,
  $$values (true, 'started'::text, true)$$,
  'first bounded request is admitted'
);
select results_eq(
  $$
    select admitted, decision, admission_id is not null
    from public.begin_social_import_paid_work('request-first')
  $$,
  $$values (false, 'duplicate'::text, false)$$,
  'an in-flight client request is suppressed as a duplicate'
);

reset role;
select set_config(
  'test.social_import_admission_id',
  (
    select id::text
    from app.social_import_paid_work_admissions
    where user_id = 'user_social_import_admission_test'
      and client_request_id = 'request-first'
      and state = 'in_flight'
  ),
  true
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select ok(
  public.finish_social_import_paid_work(
    'request-first',
    current_setting('test.social_import_admission_id')::uuid
  ),
  'the owner can finish the exact admitted attempt'
);
select is(
  public.finish_social_import_paid_work(
    'request-first',
    current_setting('test.social_import_admission_id')::uuid
  ),
  false,
  'finish is idempotent after the slot is released'
);
select results_eq(
  $$
    select admitted, decision, admission_id is not null
    from public.begin_social_import_paid_work('request-first')
  $$,
  $$values (false, 'replay_required'::text, false)$$,
  'a finished client request requests a content-free replay with a fresh ID'
);

reset role;
truncate table app.social_import_paid_work_admissions;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('concurrent-1')$$,
  $$values (true, 'started'::text)$$,
  'first concurrent slot is admitted'
);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('concurrent-2')$$,
  $$values (true, 'started'::text)$$,
  'second concurrent slot is admitted'
);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('concurrent-3')$$,
  $$values (true, 'started'::text)$$,
  'third concurrent slot is admitted'
);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('concurrent-4')$$,
  $$values (false, 'busy'::text)$$,
  'a fourth concurrent request is rejected before paid work'
);

reset role;
update app.social_import_paid_work_admissions
set started_at = clock_timestamp() - interval '10 minutes'
where user_id = 'user_social_import_admission_test'
  and client_request_id = 'concurrent-1';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('concurrent-1')$$,
  $$values (true, 'started'::text)$$,
  'a stale orphan expires and the same client request can retry'
);
reset role;
select results_eq(
  $$
    select
      count(*) filter (where state = 'expired'),
      count(*) filter (where state = 'in_flight')
    from app.social_import_paid_work_admissions
    where user_id = 'user_social_import_admission_test'
      and client_request_id = 'concurrent-1'
  $$,
  $$values (1::bigint, 1::bigint)$$,
  'stale retry keeps one expired audit row and one active attempt'
);

truncate table app.social_import_paid_work_admissions;
insert into app.social_import_paid_work_admissions (
  user_id, client_request_id, state, started_at, finished_at
)
select
  'user_social_import_admission_test',
  'quota-recent-' || ordinal::text,
  'finished',
  clock_timestamp() - interval '1 hour',
  clock_timestamp() - interval '59 minutes'
from generate_series(1, 20) as ordinal;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('quota-blocked')$$,
  $$values (false, 'quota'::text)$$,
  'the twenty-first rolling 24-hour start is rejected'
);

reset role;
truncate table app.social_import_paid_work_admissions;
insert into app.social_import_paid_work_admissions (
  user_id, client_request_id, state, started_at, finished_at
)
select
  'user_social_import_admission_test',
  'quota-old-' || ordinal::text,
  'finished',
  clock_timestamp() - interval '25 hours',
  clock_timestamp() - interval '24 hours 59 minutes'
from generate_series(1, 20) as ordinal;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_social_import_admission_test', true);
select results_eq(
  $$select admitted, decision from public.begin_social_import_paid_work('quota-window-open')$$,
  $$values (true, 'started'::text)$$,
  'starts outside the rolling 24-hour window do not consume quota'
);
select throws_ok(
  $$select count(*) from app.social_import_paid_work_admissions$$,
  '42501',
  'permission denied for table social_import_paid_work_admissions'
);

select * from finish();
rollback;
