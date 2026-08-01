begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(12);

select ok(
  (
    select bool_and(not procedure.prosecdef)
    from pg_proc procedure
    where procedure.oid = any(array[
      'public.current_user_calendar_snapshot()'::regprocedure,
      'public.visible_place_lists_snapshot()'::regprocedure,
      'public.social_surface_snapshot(double precision,double precision,double precision,double precision)'::regprocedure
    ])
  ),
  'surface snapshot RPCs run as security invoker'
);

select ok(
  (
    select bool_and(
      'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    )
    from pg_proc procedure
    where procedure.oid = any(array[
      'public.current_user_calendar_snapshot()'::regprocedure,
      'public.visible_place_lists_snapshot()'::regprocedure,
      'public.social_surface_snapshot(double precision,double precision,double precision,double precision)'::regprocedure
    ])
  ),
  'surface snapshot RPCs pin public and app'
);

select ok(
  (
    select bool_and(
      has_function_privilege('authenticated', procedure.oid, 'execute')
      and not has_function_privilege('anon', procedure.oid, 'execute')
    )
    from pg_proc procedure
    where procedure.oid = any(array[
      'public.current_user_calendar_snapshot()'::regprocedure,
      'public.visible_place_lists_snapshot()'::regprocedure,
      'public.social_surface_snapshot(double precision,double precision,double precision,double precision)'::regprocedure
    ])
  ),
  'surface snapshot RPCs are authenticated-only'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_surface_owner', 'surfaceowner', 'Surface Owner'),
  ('user_surface_friend', 'surfacefriend', 'Surface Friend'),
  ('user_surface_stranger', 'surfacestranger', 'Surface Stranger');

insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_surface_owner', 'user_surface_friend', 'profile');

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id,
  confidence
)
values
  (
    '91000000-0000-0000-0000-000000000001',
    'Surface Owner Place',
    'coffee_tea_sweets',
    34.0522,
    -118.2437,
    'surface_snapshot_test',
    'owner-place',
    1
  ),
  (
    '91000000-0000-0000-0000-000000000002',
    'Surface Friend Place',
    'coffee_tea_sweets',
    34.0523,
    -118.2438,
    'surface_snapshot_test',
    'friend-place',
    1
  );

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  nearby_confirmed,
  source_type
)
values
  (
    '92000000-0000-0000-0000-000000000001',
    'user_surface_owner',
    '91000000-0000-0000-0000-000000000001',
    'been',
    'followers',
    false,
    'manual'
  ),
  (
    '92000000-0000-0000-0000-000000000002',
    'user_surface_friend',
    '91000000-0000-0000-0000-000000000002',
    'been',
    'followers',
    false,
    'manual'
  );

insert into public.place_visits (
  id,
  user_place_id,
  visited_at,
  rating_score,
  tags
)
values (
  '93000000-0000-0000-0000-000000000001',
  '92000000-0000-0000-0000-000000000001',
  '2026-07-29 12:00:00+00',
  4,
  array['coffee']
);

insert into public.place_lists (
  id,
  owner_user_id,
  name,
  description,
  visibility
)
values (
  '94000000-0000-0000-0000-000000000001',
  'user_surface_owner',
  'Surface List',
  'Snapshot regression fixture',
  'followers'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_surface_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  jsonb_array_length((public.current_user_calendar_snapshot())->'places'),
  1,
  'calendar snapshot contains only the current owner places'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements((public.current_user_calendar_snapshot())->'visits') visit
    where visit->>'id' = '93000000-0000-0000-0000-000000000001'
  ),
  'calendar snapshot batches the current owner visit'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements((public.visible_place_lists_snapshot())->'summaries') summary
    where summary->>'id' = '94000000-0000-0000-0000-000000000001'
  ),
  'list snapshot includes a visible list summary'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements((public.visible_place_lists_snapshot())->'details') detail
    where detail->'list'->>'id' = '94000000-0000-0000-0000-000000000001'
  ),
  'list snapshot includes visible list details'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements((public.visible_place_lists_snapshot())->'owner_places') place_row
    where place_row->>'owner_user_id' = 'user_surface_owner'
  ),
  'list snapshot batches the list owner place projection'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      (public.social_surface_snapshot(34, -119, 35, -118))->'following'
    ) profile
    where profile->>'id' = 'user_surface_friend'
  ),
  'social snapshot includes the current viewer following graph'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      (public.social_surface_snapshot(34, -119, 35, -118))->'followed_places'
    ) place_row
    where place_row->>'owner_user_id' = 'user_surface_friend'
  ),
  'social snapshot batches followed-profile places'
);

select ok(
  exists (
    select 1
    from jsonb_array_elements(
      (public.social_surface_snapshot(34, -119, 35, -118))->'viewport_places'
    ) place_row
    where place_row->>'owner_user_id' = 'user_surface_friend'
  ),
  'social snapshot preserves viewport RLS visibility'
);

select set_config('request.jwt.claim.sub', 'user_surface_stranger', true);

select is(
  jsonb_array_length((public.current_user_calendar_snapshot())->'places'),
  0,
  'calendar snapshot does not expose another owner data'
);

select * from finish();

rollback;
