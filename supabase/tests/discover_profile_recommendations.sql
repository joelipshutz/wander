begin;

create extension if not exists pgtap;

select plan(23);

select is(
  (select prosecdef from pg_proc where oid = 'app.discover_profile_recommendations(integer)'::regprocedure),
  false,
  'recommendations run as the authenticated caller'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.discover_profile_recommendations(integer)'::regprocedure),
  'app recommendations pin search_path'
);

select ok(
  (select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'public.discover_profile_recommendations(integer)'::regprocedure),
  'public recommendations pin search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.discover_profile_recommendations(integer)', 'execute'),
  'authenticated can request recommendations'
);

select ok(
  not has_function_privilege('anon', 'public.discover_profile_recommendations(integer)', 'execute'),
  'anonymous callers cannot request recommendations'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.follow_user(text,text)'::regprocedure),
  false,
  'follow remains security invoker'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.follow_user(text,text)'::regprocedure),
  'follow pins search_path'
);

insert into public.profiles (
  id, handle, display_name, bio, home_area, is_private_profile, created_at
)
values
  ('user_discover_viewer', 'discoverviewer', 'Discover Viewer', null, 'Los Angeles', false, '2025-01-01T00:00:00Z'),
  ('user_discover_follows_viewer', 'afollowsviewer', 'Follows Viewer', 'Coffee and parks.', null, false, '2024-01-01T00:00:00Z'),
  ('user_discover_bridge', 'bridgeperson', 'Bridge Person', null, null, false, '2024-02-01T00:00:00Z'),
  ('user_discover_shared', 'bsharedperson', 'Shared Person', 'Neighborhood places.', null, false, '2024-03-01T00:00:00Z'),
  ('user_discover_fallback_new', 'cnewpublic', 'New Public', null, null, false, '2100-06-01T00:00:00Z'),
  ('user_discover_fallback_old', 'doldpublic', 'Old Public', null, null, false, '2099-06-01T00:00:00Z'),
  ('user_discover_followed', 'followedalready', 'Already Followed', null, null, false, '2025-05-01T00:00:00Z'),
  ('user_discover_private', 'privateperson', 'Private Person', null, null, true, '2025-07-01T00:00:00Z'),
  ('user_discover_blocked', 'blockedperson', 'Blocked Person', null, null, false, '2025-07-02T00:00:00Z'),
  ('user_discover_blocker', 'blockerperson', 'Blocker Person', null, null, false, '2025-07-03T00:00:00Z');

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('user_discover_follows_viewer', 'user_discover_viewer', 'profile'),
  ('user_discover_viewer', 'user_discover_bridge', 'profile'),
  ('user_discover_bridge', 'user_discover_shared', 'profile'),
  ('user_discover_viewer', 'user_discover_followed', 'profile'),
  ('user_discover_private', 'user_discover_fallback_old', 'profile'),
  ('user_discover_private', 'user_discover_followed', 'profile'),
  ('user_discover_fallback_old', 'user_discover_private', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values
  ('user_discover_viewer', 'user_discover_blocked'),
  ('user_discover_blocker', 'user_discover_viewer');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_discover_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select string_agg(id, ',' order by result_rank)
   from public.discover_profile_recommendations(50)
   where id like 'user_discover_%'),
  'user_discover_follows_viewer,user_discover_shared,user_discover_fallback_new,user_discover_fallback_old',
  'recommendations exclude self, existing follows, private profiles, and blocks in both directions'
);

select is(
  (select reason_kind from public.discover_profile_recommendations(20) where id = 'user_discover_follows_viewer'),
  'follows_you',
  'follows-you is the highest-precedence reason'
);

select is(
  (select reason_kind from public.discover_profile_recommendations(20) where id = 'user_discover_shared'),
  'shared_follows',
  'shared graph evidence produces the aggregate shared-follows reason'
);

select is(
  (select shared_follow_count from public.discover_profile_recommendations(20) where id = 'user_discover_shared'),
  1,
  'shared-follow count is aggregate-only and correct'
);

select is(
  (select reason_kind from public.discover_profile_recommendations(20) where id = 'user_discover_fallback_new'),
  'suggested',
  'remaining public profiles receive the generic reason'
);

select is(
  (select count(*)::integer from public.discover_profile_recommendations(2)),
  2,
  'recommendation limit is honored'
);

select is(
  (select result_rank from public.discover_profile_recommendations(20) where id = 'user_discover_fallback_new'),
  3,
  'generic fallback ranking is stable after graph-backed candidates'
);

select is(
  (select max(result_rank)
   from public.discover_profile_recommendations(1000)
   where id like 'user_discover_%'),
  4,
  'oversized recommendation limit is safely bounded without changing eligible rows'
);

select is(
  (select count(*)::integer from public.search_profiles_by_handle('private')),
  0,
  'member search excludes private profiles'
);

select is(
  (select count(*)::integer from public.search_profiles_by_handle('discoverviewer')),
  0,
  'member search excludes the current user'
);

select is(
  (select string_agg(id, ',' order by id) from public.profile_following('user_discover_private')),
  null,
  'another caller cannot enumerate a private profile following graph'
);

select is(
  (select count(*)::integer from public.profile_following('user_discover_fallback_old') where id = 'user_discover_private'),
  0,
  'following results omit private profiles'
);

select is(
  (select count(*)::integer from public.profile_followers('user_discover_followed') where id = 'user_discover_private'),
  0,
  'follower results omit private profiles'
);

select throws_ok(
  $$ select public.follow_user('user_discover_private') $$,
  'P0001',
  'profile_not_followable',
  'direct follow rejects a private target'
);

select throws_ok(
  $$ select public.follow_user('user_missing_profile') $$,
  'P0001',
  'profile_not_followable',
  'direct follow does not disclose whether an unavailable target is private or absent'
);

select set_config('request.jwt.claim.sub', 'user_discover_private', true);

select is(
  (select string_agg(id, ',' order by id) from public.profile_following('user_discover_private')),
  'user_discover_fallback_old,user_discover_followed',
  'a private owner can still view their own public following graph'
);

select * from finish();

rollback;
