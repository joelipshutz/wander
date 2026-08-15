begin;

create extension if not exists pgtap;

select plan(17);

select is(
  (select prosecdef from pg_proc where oid = 'public.featured_places_in_view(double precision,double precision,double precision,double precision)'::regprocedure),
  true,
  'Featured viewport RPC is explicitly security definer'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'public.featured_places_in_view(double precision,double precision,double precision,double precision)'::regprocedure),
  'Featured viewport RPC pins search_path'
);

select ok(
  (select 'statement_timeout=3s' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'public.featured_places_in_view(double precision,double precision,double precision,double precision)'::regprocedure),
  'Featured viewport RPC has a bounded statement timeout'
);

select ok(
  has_function_privilege('authenticated', 'public.featured_places_in_view(double precision,double precision,double precision,double precision)', 'execute'),
  'authenticated can execute Featured viewport RPC'
);

select ok(
  not has_function_privilege('anon', 'public.featured_places_in_view(double precision,double precision,double precision,double precision)', 'execute'),
  'anonymous cannot execute Featured viewport RPC'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('featured_viewer', 'featuredviewer', 'Featured Viewer', false),
  ('featured_followed', 'featuredfollowed', 'Featured Followed', false),
  ('featured_community', 'featuredcommunity', 'Featured Community', false),
  ('featured_private', 'featuredprivate', 'Featured Private', true),
  ('featured_blocked', 'featuredblocked', 'Featured Blocked', false),
  ('featured_bulk', 'featuredbulk', 'Featured Bulk', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values ('featured_viewer', 'featured_followed', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('featured_blocked', 'featured_viewer');

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values
  ('91000000-0000-0000-0000-000000000001', 'Shared Social Place', 'coffee_tea_sweets', 34.01, -118.01, 'mapkit', 'featured-shared'),
  ('91000000-0000-0000-0000-000000000002', 'Community Only Place', 'restaurants_food', 34.02, -118.02, 'mapkit', 'featured-community'),
  ('91000000-0000-0000-0000-000000000003', 'Private Place', 'parks_nature', 34.03, -118.03, 'mapkit', 'featured-private'),
  ('91000000-0000-0000-0000-000000000004', 'Mutuals Place', 'arts_culture', 34.04, -118.04, 'mapkit', 'featured-mutuals'),
  ('91000000-0000-0000-0000-000000000005', 'Blocked Place', 'shopping', 34.05, -118.05, 'mapkit', 'featured-blocked'),
  ('91000000-0000-0000-0000-000000000006', 'Community Wanna', 'coffee_tea_sweets', 34.06, -118.06, 'mapkit', 'featured-wanna'),
  ('91000000-0000-0000-0000-000000000007', 'Viewer Self Place', 'coffee_tea_sweets', 34.07, -118.07, 'mapkit', 'featured-self');

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  note,
  rating_score,
  source_type,
  saved_at
)
values
  ('91100000-0000-0000-0000-000000000001', 'featured_followed', '91000000-0000-0000-0000-000000000001', 'been', 'followers', 'Visible followed note', 3, 'manual', '2026-08-01 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000002', 'featured_community', '91000000-0000-0000-0000-000000000001', 'been', 'followers', 'Hidden stranger note on shared place', 5, 'manual', '2026-08-02 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000003', 'featured_community', '91000000-0000-0000-0000-000000000002', 'been', 'followers', 'Hidden stranger note', 4.5, 'manual', '2026-08-03 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000004', 'featured_private', '91000000-0000-0000-0000-000000000003', 'been', 'followers', 'Private profile note', 5, 'manual', '2026-08-04 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000005', 'featured_community', '91000000-0000-0000-0000-000000000004', 'been', 'mutuals', 'Mutuals note', 5, 'manual', '2026-08-05 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000006', 'featured_blocked', '91000000-0000-0000-0000-000000000005', 'been', 'followers', 'Blocked note', 5, 'manual', '2026-08-06 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000007', 'featured_community', '91000000-0000-0000-0000-000000000006', 'wanna_go', 'followers', 'Wanna note', null, 'manual', '2026-08-07 12:00:00+00'),
  ('91100000-0000-0000-0000-000000000008', 'featured_viewer', '91000000-0000-0000-0000-000000000007', 'been', 'self', 'Viewer note', 4, 'manual', '2026-08-08 12:00:00+00');

insert into public.question_definitions (
  id,
  owner_user_id,
  question_key,
  prompt,
  value_type,
  options,
  is_system
)
values (
  '91200000-0000-0000-0000-000000000001',
  'featured_community',
  'featured_private_tag',
  'Private community answer',
  'text',
  '[]'::jsonb,
  false
);

insert into public.place_attributes (
  user_place_id,
  question_definition_id,
  question_key,
  value_type,
  value
)
values (
  '91100000-0000-0000-0000-000000000003',
  '91200000-0000-0000-0000-000000000001',
  'featured_private_tag',
  'text',
  '"do not expose"'::jsonb
);

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
select
  ('92000000-0000-0000-0000-' || lpad(series::text, 12, '0'))::uuid,
  'Bulk Featured ' || series,
  'place',
  34.10 + series::double precision / 100000,
  -118.10,
  'mapkit',
  'featured-bulk-' || series
from generate_series(1, 125) series;

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type,
  saved_at
)
select
  ('93000000-0000-0000-0000-' || lpad(series::text, 12, '0'))::uuid,
  'featured_bulk',
  ('92000000-0000-0000-0000-' || lpad(series::text, 12, '0'))::uuid,
  'been',
  'followers',
  'manual',
  '2026-07-01 12:00:00+00'::timestamptz + make_interval(secs => series)
from generate_series(1, 125) series;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'featured_viewer', true);

select is(
  (select count(*)::integer from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where user_place_id = '91100000-0000-0000-0000-000000000001'),
  1,
  'RLS-visible followed row retains its real row'
);

select is(
  (select owner_user_id from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000001'),
  'featured_followed',
  'social place does not add a synthetic aggregate row'
);

select is(
  (select community_save_count from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000001'),
  2,
  'social place carries broader community support'
);

select is(
  (select owner_user_id from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000002'),
  'recme_featured_community',
  'community-only place uses an anonymous aggregate owner'
);

select is(
  (select user_place_id from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000002'),
  '91000000-0000-0000-0000-000000000002'::uuid,
  'community-only place returns a synthetic stable id instead of a stranger save id'
);

select is(
  (select count(*)::integer from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where owner_user_id = 'featured_community'),
  0,
  'Featured output never returns the non-followed contributor identity'
);

select is(
  (select note from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000002'),
  null::text,
  'community-only place redacts stranger notes'
);

select is(
  (select attributes from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000002'),
  '[]'::jsonb,
  'community-only place redacts stranger attributes'
);

select results_eq(
  $$
    select recommended_score, recommended_count, community_save_count
    from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9)
    where place_id = '91000000-0000-0000-0000-000000000002'
  $$,
  $$ values (4.5::double precision, 1::integer, 1::integer) $$,
  'community-only place exposes only aggregate quality evidence'
);

select results_eq(
  $$
    select canonical_name
    from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9)
    where place_id in (
      '91000000-0000-0000-0000-000000000003',
      '91000000-0000-0000-0000-000000000004',
      '91000000-0000-0000-0000-000000000005',
      '91000000-0000-0000-0000-000000000006'
    )
  $$,
  $$ select null::text where false $$,
  'private profiles, mutual-only saves, blocks, and Wanna saves stay excluded'
);

select is(
  (select owner_user_id from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9) where place_id = '91000000-0000-0000-0000-000000000007'),
  'featured_viewer',
  'viewer self-visible check-in remains eligible'
);

select is(
  (select count(distinct place_id)::integer from public.featured_places_in_view(33.9, -118.3, 34.3, -117.9)),
  120,
  'Featured RPC caps each viewport at 120 candidate place groups'
);

select * from finish();

rollback;
