begin;

create extension if not exists pgtap;

select plan(29);

select is(
  (select prosecdef from pg_proc where oid = 'app.sync_user_place_latest_visit()'::regprocedure),
  true,
  'latest visit sync trigger function is security definer'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'app.sync_user_place_latest_visit()'::regprocedure),
  'latest visit sync trigger function pins search_path'
);

select ok(
  not has_function_privilege('authenticated', 'app.sync_user_place_latest_visit()', 'execute'),
  'authenticated cannot execute the latest visit sync trigger function directly'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgname = 'place_visits_sync_user_place_latest_visit'
      and tgrelid = 'public.place_visits'::regclass
      and not tgisinternal
  ),
  'place visits keep the parent latest visit timestamp in sync'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])'::regprocedure),
  false,
  'app visible_places_in_view runs as security invoker'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])'::regprocedure),
  false,
  'public visible_places_in_view runs as security invoker'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.profile_visible_places(text,text[],text[])'::regprocedure),
  false,
  'app profile_visible_places runs as security invoker'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.profile_visible_places(text,text[],text[])'::regprocedure),
  false,
  'public profile_visible_places runs as security invoker'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'app.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])'::regprocedure),
  'app visible_places_in_view pins search_path'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'app.profile_visible_places(text,text[],text[])'::regprocedure),
  'app profile_visible_places pins search_path'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'public.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])'::regprocedure),
  'public visible_places_in_view pins search_path'
);

select ok(
  (select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'public.profile_visible_places(text,text[],text[])'::regprocedure),
  'public profile_visible_places pins search_path'
);

select ok(
  (select pg_get_function_result('app.profile_visible_places(text,text[],text[])'::regprocedure))
    like '%saved_at timestamp with time zone%',
  'app profile_visible_places preserves persisted save timestamps in its return contract'
);

select ok(
  (select pg_get_function_result('public.profile_visible_places(text,text[],text[])'::regprocedure))
    like '%saved_at timestamp with time zone%',
  'public profile_visible_places preserves persisted save timestamps in its return contract'
);

select ok(
  has_function_privilege('authenticated', 'public.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])', 'execute'),
  'authenticated can execute public visible_places_in_view'
);

select ok(
  not has_function_privilege('anon', 'public.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])', 'execute'),
  'anon cannot execute public visible_places_in_view'
);

select ok(
  has_function_privilege('authenticated', 'public.profile_visible_places(text,text[],text[])', 'execute'),
  'authenticated can execute public profile_visible_places'
);

select ok(
  not has_function_privilege('anon', 'public.profile_visible_places(text,text[],text[])', 'execute'),
  'anon cannot execute public profile_visible_places'
);

insert into public.profiles (id, handle, display_name, avatar_url)
values
  ('user_activity_owner', 'activityowner', 'Activity Owner', 'https://example.com/activity-owner.jpg'),
  ('user_activity_viewer', 'activityviewer', 'Activity Viewer', null);

insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_activity_viewer', 'user_activity_owner', 'profile');

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values (
  '81000000-0000-0000-0000-000000000001',
  'Activity Timestamp Cafe',
  'coffee_tea_sweets',
  34.05,
  -118.25,
  'mapkit',
  'activity-timestamp-cafe'
);

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type,
  visited_at,
  saved_at,
  created_at,
  updated_at
)
values (
  '82000000-0000-0000-0000-000000000001',
  'user_activity_owner',
  '81000000-0000-0000-0000-000000000001',
  'been',
  'followers',
  'manual',
  '2026-07-09 20:00:00+00',
  '2026-07-08 19:00:00+00',
  '2026-07-08 18:00:00+00',
  '2026-07-10 21:00:00+00'
);

insert into public.place_visits (
  id,
  user_place_id,
  visited_at,
  note,
  rating_score,
  attribute_answers,
  backfilled_from_user_place
)
values (
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  '2026-07-11 20:00:00+00',
  'Explicit visit',
  4.5,
  '[]'::jsonb,
  false
);

update public.place_visits
set visited_at = '2026-07-12 20:00:00+00'
where id = '83000000-0000-0000-0000-000000000001';

select is(
  (select visited_at from public.user_places where id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-12 20:00:00+00'::timestamptz,
  'explicit visit edits update the parent Been timestamp'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_activity_viewer', true);

select is(
  (select owner_avatar_url from public.visible_places_in_view(34, -119, 35, -118, null, null, array['following']) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  'https://example.com/activity-owner.jpg',
  'visible places restores owner avatar URL'
);

select is(
  (select visited_at from public.visible_places_in_view(34, -119, 35, -118, null, null, array['following']) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-12 20:00:00+00'::timestamptz,
  'visible places returns the latest persisted visit time'
);

select is(
  (select saved_at from public.visible_places_in_view(34, -119, 35, -118, null, null, array['following']) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-08 19:00:00+00'::timestamptz,
  'visible places returns persisted save time'
);

select is(
  (select created_at from public.visible_places_in_view(34, -119, 35, -118, null, null, array['following']) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-08 18:00:00+00'::timestamptz,
  'visible places returns persisted creation time'
);

select is(
  (select updated_at from public.visible_places_in_view(34, -119, 35, -118, null, null, array['following']) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  (select updated_at from public.user_places where id = '82000000-0000-0000-0000-000000000001'),
  'visible places returns the persisted parent update time'
);

select is(
  (select owner_avatar_url from public.profile_visible_places('user_activity_owner', null, null) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  'https://example.com/activity-owner.jpg',
  'profile visible places restores owner avatar URL'
);

select is(
  (select visited_at from public.profile_visible_places('user_activity_owner', null, null) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-12 20:00:00+00'::timestamptz,
  'profile visible places returns the latest persisted visit time'
);

select is(
  (select saved_at from public.profile_visible_places('user_activity_owner', null, null) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-08 19:00:00+00'::timestamptz,
  'profile visible places returns persisted save time'
);

select is(
  (select created_at from public.profile_visible_places('user_activity_owner', null, null) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  '2026-07-08 18:00:00+00'::timestamptz,
  'profile visible places returns persisted creation time'
);

select is(
  (select updated_at from public.profile_visible_places('user_activity_owner', null, null) where user_place_id = '82000000-0000-0000-0000-000000000001'),
  (select updated_at from public.user_places where id = '82000000-0000-0000-0000-000000000001'),
  'profile visible places returns the persisted parent update time'
);

select * from finish();

rollback;
