begin;

create extension if not exists pgtap;

select plan(16);

select is(
  (select prosecdef from pg_proc where oid = 'public.search_recme_places(text,text[],text,boolean,text,integer)'::regprocedure),
  true,
  'global rec.me place search is a narrow security-definer boundary'
);

select ok(
  (select exists (
     select 1
     from unnest(coalesce(proconfig, array[]::text[])) as setting
     where setting ~ '^search_path=(""|)$'
   ) from pg_proc where oid = 'public.search_recme_places(text,text[],text,boolean,text,integer)'::regprocedure),
  'global search pins an empty search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.search_recme_places(text,text[],text,boolean,text,integer)', 'execute'),
  'authenticated callers can search the rec.me place corpus'
);

select ok(
  not has_function_privilege('anon', 'public.search_recme_places(text,text[],text,boolean,text,integer)', 'execute'),
  'anonymous callers cannot search the rec.me place corpus'
);

select ok(
  not pg_get_function_result('public.search_recme_places(text,text[],text,boolean,text,integer)'::regprocedure)
    ~* '(user_id|note|rating_score|visibility|save_count|attributes)',
  'the RPC return shape contains canonical place facts only'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public'
      and indexname = 'places_discover_search_vector_idx'
      and indexdef ilike '%using gin%'
  ),
  'global lexical search has a GIN index'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('user_recme_search_viewer', 'searchviewer', 'Search Viewer', false),
  ('user_recme_search_friend', 'searchfriend', 'Search Friend', false),
  ('user_recme_search_followed', 'searchfollowed', 'Search Followed', false),
  ('user_recme_search_stranger', 'searchstranger', 'Search Stranger', false),
  ('user_recme_search_blocked', 'searchblocked', 'Search Blocked', false),
  ('user_recme_search_private', 'searchprivate', 'Search Private', true);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('user_recme_search_viewer', 'user_recme_search_friend', 'profile'),
  ('user_recme_search_friend', 'user_recme_search_viewer', 'profile'),
  ('user_recme_search_viewer', 'user_recme_search_followed', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('user_recme_search_viewer', 'user_recme_search_blocked');

insert into public.places (
  id, canonical_name, category, primary_category, subcategory, category_source,
  latitude, longitude, source_provider, source_provider_place_id, confidence
)
values
  ('11000000-0000-0000-0000-000000000001', 'REC225 Friend Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.01, -118.01, 'mapkit', 'friend-coffee', 1),
  ('11000000-0000-0000-0000-000000000002', 'REC225 Stranger Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.02, -118.02, 'google_places', 'stranger-coffee', 1),
  ('11000000-0000-0000-0000-000000000003', 'REC225 Blocked Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.03, -118.03, 'mapkit', 'blocked-coffee', 1),
  ('11000000-0000-0000-0000-000000000004', 'REC225 Mixed Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.04, -118.04, 'mapkit', 'mixed-coffee', 1),
  ('11000000-0000-0000-0000-000000000005', 'REC225 Self Only Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.05, -118.05, 'mapkit', 'self-only-coffee', 1),
  ('11000000-0000-0000-0000-000000000006', 'REC225 Private Profile Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.06, -118.06, 'mapkit', 'private-profile-coffee', 1),
  ('11000000-0000-0000-0000-000000000007', 'REC225 Home Address', 'areas_addresses', 'areas_addresses', 'neighborhood', 'provider', 34.07, -118.07, 'mapkit', 'home-address', 1),
  ('11000000-0000-0000-0000-000000000008', 'REC225 Manual Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.08, -118.08, 'manual', 'manual-coffee', 1),
  ('11000000-0000-0000-0000-000000000009', 'REC225 Favorite Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.09, -118.09, 'apple_maps', 'favorite-coffee', 1),
  ('11000000-0000-0000-0000-000000000010', 'REC225 Followed Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 34.10, -118.10, 'google_maps', 'followed-coffee', 1);

insert into public.user_places (
  id, user_id, place_id, status, visibility, rating_score, source_type, saved_at
)
values
  ('21000000-0000-0000-0000-000000000001', 'user_recme_search_friend', '11000000-0000-0000-0000-000000000001', 'been', 'mutuals', 4, 'social_seed', '2026-01-01'),
  ('21000000-0000-0000-0000-000000000002', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000002', 'been', 'followers', 3, 'social_seed', '2026-01-02'),
  ('21000000-0000-0000-0000-000000000003', 'user_recme_search_blocked', '11000000-0000-0000-0000-000000000003', 'been', 'followers', 5, 'social_seed', '2026-01-03'),
  ('21000000-0000-0000-0000-000000000004', 'user_recme_search_blocked', '11000000-0000-0000-0000-000000000004', 'been', 'followers', 5, 'social_seed', '2026-01-04'),
  ('21000000-0000-0000-0000-000000000005', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000004', 'been', 'followers', 4, 'social_seed', '2026-01-05'),
  ('21000000-0000-0000-0000-000000000006', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000005', 'been', 'self', 5, 'social_seed', '2026-01-06'),
  ('21000000-0000-0000-0000-000000000007', 'user_recme_search_private', '11000000-0000-0000-0000-000000000006', 'been', 'followers', 5, 'social_seed', '2026-01-07'),
  ('21000000-0000-0000-0000-000000000008', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000007', 'been', 'followers', 5, 'social_seed', '2026-01-08'),
  ('21000000-0000-0000-0000-000000000009', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000008', 'been', 'followers', 5, 'social_seed', '2026-01-09'),
  ('21000000-0000-0000-0000-000000000010', 'user_recme_search_stranger', '11000000-0000-0000-0000-000000000009', 'been', 'followers', 5, 'social_seed', '2026-01-10'),
  ('21000000-0000-0000-0000-000000000011', 'user_recme_search_followed', '11000000-0000-0000-0000-000000000010', 'been', 'followers', 4, 'social_seed', '2026-01-11');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_recme_search_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select canonical_name from public.search_recme_places('REC225', array['coffee_tea_sweets'], null, false, 'everyone', 20) limit 1),
  'REC225 Friend Coffee',
  'mutual-friend saves receive the strongest default social bias'
);

select is(
  (select array_agg(canonical_name order by canonical_name)::text
   from public.search_recme_places('REC225', array['coffee_tea_sweets'], null, false, 'friends', 20)),
  '{"REC225 Friend Coffee"}',
  'explicit friends scope is mutual-only'
);

select is(
  (select array_agg(canonical_name order by canonical_name)::text
   from public.search_recme_places('REC225', array['coffee_tea_sweets'], null, false, 'following', 20)),
  '{"REC225 Followed Coffee","REC225 Friend Coffee"}',
  'following scope includes one-way follows and mutual friends'
);

select is(
  (select count(*)::integer from public.search_recme_places('Blocked', null, null, false, 'everyone', 20)),
  0,
  'places contributed only by blocked users are excluded'
);

select is(
  (select count(*)::integer from public.search_recme_places('Mixed', null, null, false, 'everyone', 20)),
  1,
  'a place remains discoverable when it also has an eligible non-blocked save'
);

select is(
  (select count(*)::integer from public.search_recme_places('Self Only', null, null, false, 'everyone', 20)),
  0,
  'self-only memories do not contribute to global discoverability'
);

select is(
  (select count(*)::integer from public.search_recme_places('Private Profile', null, null, false, 'everyone', 20)),
  0,
  'private profiles do not contribute to global discoverability'
);

select is(
  (select count(*)::integer from public.search_recme_places('REC225', null, null, false, 'everyone', 20)
   where canonical_name in ('REC225 Home Address', 'REC225 Manual Coffee')),
  0,
  'unsafe address categories and manual providers are excluded'
);

select is(
  (select array_agg(canonical_name order by canonical_name)::text
   from public.search_recme_places('REC225', array['coffee_tea_sweets'], null, true, 'everyone', 20)),
  '{"REC225 Favorite Coffee","REC225 Followed Coffee","REC225 Friend Coffee","REC225 Mixed Coffee"}',
  'favorite intent uses anonymous eligible been ratings of four or higher'
);

select is(
  (select source_provider || ':' || source_provider_place_id
   from public.search_recme_places('Favorite', null, null, false, 'everyone', 20)),
  'apple_maps:favorite-coffee',
  'global results preserve canonical provider identity'
);

select * from finish();

rollback;
