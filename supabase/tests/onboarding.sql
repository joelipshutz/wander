begin;

create extension if not exists pgtap;

select plan(18);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'onboarding_completed_at'
  ),
  'profiles include durable onboarding completion state'
);

select is(
  (select prosecdef from pg_proc
   where oid = 'app.update_own_profile(text,text,text,boolean,text,text,boolean)'::regprocedure),
  false,
  'profile provision and completion run as the authenticated caller'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc
   where oid = 'app.update_own_profile(text,text,text,boolean,text,text,boolean)'::regprocedure),
  'profile provision pins search_path'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.profile_handle_available(text)'::regprocedure),
  true,
  'handle availability is a narrow security definer function'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.profile_handle_available(text)'::regprocedure),
  'handle availability pins search_path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.update_own_profile(text,text,text,boolean,text,text,boolean)',
    'execute'
  ),
  'authenticated callers can provision and complete their profile'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.update_own_profile(text,text,text,boolean,text,text,boolean)',
    'execute'
  ),
  'anonymous callers cannot provision profiles'
);

select ok(
  has_function_privilege('authenticated', 'public.profile_handle_available(text)', 'execute'),
  'authenticated callers can check handle availability'
);

select ok(
  not has_function_privilege('anon', 'public.profile_handle_available(text)', 'execute'),
  'anonymous callers cannot check private handle inventory'
);

insert into public.profiles(id, handle, display_name, onboarding_completed_at)
values ('user_onboarding_taken', 'taken_handle', 'Existing Member', now());

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_onboarding_new', true);

select is(
  public.profile_handle_available('@fresh_handle'),
  true,
  'a valid unused normalized handle is available'
);

select is(
  public.profile_handle_available('taken_handle'),
  false,
  'an active profile handle is unavailable without exposing its owner'
);

select is(
  public.profile_handle_available('not valid'),
  false,
  'invalid handles are unavailable'
);

select is(
  public.update_own_profile(
    null, null, null, null, 'New Friend', '@fresh_handle', false
  )->>'handle',
  'fresh_handle',
  'identity save self-provisions when the Clerk webhook has not arrived'
);

select is(
  (select onboarding_completed_at from public.profiles where id = 'user_onboarding_new'),
  null,
  'identity save does not complete optional onboarding steps'
);

select ok(
  (public.update_own_profile(null, null, null, null, null, null, true)
    ->>'onboarding_completed_at') is not null,
  'final completion sets the durable timestamp'
);

select is(
  (select onboarding_completed_at from public.current_profile()),
  (select onboarding_completed_at from public.profiles where id = 'user_onboarding_new'),
  'current profile returns durable completion state'
);

create temporary table onboarding_completion_snapshot as
select onboarding_completed_at
from public.profiles
where id = 'user_onboarding_new';

with retry as (
  select public.update_own_profile(null, null, null, null, null, null, true)
)
select is(
  (select onboarding_completed_at from public.profiles where id = 'user_onboarding_new'),
  snapshot.onboarding_completed_at,
  'marking completion is idempotent'
)
from onboarding_completion_snapshot snapshot
cross join retry;

select throws_ok(
  $$ select public.update_own_profile(null, null, null, null, 'Taken', 'taken_handle', false) $$,
  '23505',
  'handle_taken',
  'final identity save remains authoritative against a claimed handle'
);

select * from finish();

rollback;
