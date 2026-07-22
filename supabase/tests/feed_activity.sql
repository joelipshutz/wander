begin;

create extension if not exists pgtap;

select plan(22);

select ok(
  exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'feed_events'
  ),
  'feed events table exists'
);

select is(
  (select relrowsecurity from pg_class where oid = 'public.feed_events'::regclass),
  true,
  'feed events enforce RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.feed_events', 'select'),
  'authenticated cannot read the append-only event table directly'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.followed_feed(text, integer)'::regprocedure),
  true,
  'followed feed projection runs as security definer'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[])) from pg_proc where oid = 'app.followed_feed(text, integer)'::regprocedure),
  'followed feed projection pins search_path'
);

select ok(
  not has_function_privilege('authenticated', 'app.record_user_place_feed_event()', 'execute'),
  'authenticated cannot call the user-place event trigger directly'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app.record_feed_event(text, text, uuid, uuid, uuid, uuid)',
    'execute'
  ),
  'authenticated cannot create arbitrary feed events directly'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('feed_viewer', 'feedviewer', 'Feed Viewer', false),
  ('feed_actor', 'feedactor', 'Feed Actor', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values ('feed_viewer', 'feed_actor', 'profile');

insert into public.places (
  id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id
)
values
  ('70000000-0000-0000-0000-000000000001', 'Maya''s Noodles', 'restaurant', 34.0522, -118.2437, 'mapkit', 'feed-noodles'),
  ('70000000-0000-0000-0000-000000000002', 'Fern Coffee', 'coffee', 34.0450, -118.2500, 'mapkit', 'feed-coffee');

insert into public.user_places (
  id, user_id, place_id, status, visibility, source_type, rating_score, note
)
values
  ('71000000-0000-0000-0000-000000000001', 'feed_actor', '70000000-0000-0000-0000-000000000001', 'been', 'followers', 'manual', 4.5, 'The chili oil is worth the trip.'),
  ('71000000-0000-0000-0000-000000000002', 'feed_actor', '70000000-0000-0000-0000-000000000002', 'wanna_go', 'followers', 'social_save', null, null);

select is(
  (select count(*)::integer from public.feed_events where actor_user_id = 'feed_actor' and event_type = 'place_been'),
  1,
  'new Been place records one immutable Been event'
);

select is(
  (select count(*)::integer from public.feed_events where actor_user_id = 'feed_actor' and event_type = 'place_saved'),
  1,
  'social saves record a distinct saved event'
);

update public.user_places
set note = 'Still the chili oil order.'
where id = '71000000-0000-0000-0000-000000000001';

select is(
  (select count(*)::integer from public.feed_events where actor_user_id = 'feed_actor'),
  2,
  'editing a note does not produce duplicate activity'
);

insert into public.place_lists (id, owner_user_id, name, description, visibility)
values ('72000000-0000-0000-0000-000000000001', 'feed_actor', 'Weeknight tables', 'Comfortable dinners for a Tuesday.', 'followers');

select is(
  (select count(*)::integer from public.feed_events where list_id = '72000000-0000-0000-0000-000000000001' and event_type = 'list_created'),
  1,
  'new list records a list-created event'
);

insert into public.place_list_items (
  id, list_id, place_id, owner_user_place_id, added_by_user_id
)
values (
  '73000000-0000-0000-0000-000000000001',
  '72000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001',
  '71000000-0000-0000-0000-000000000001',
  'feed_actor'
);

select is(
  (select count(*)::integer from public.feed_events where list_item_id = '73000000-0000-0000-0000-000000000001' and event_type = 'list_item_added'),
  1,
  'adding a place to a list records a list-item event'
);

select set_config('request.jwt.claim.sub', 'feed_viewer', true);

select is(
  jsonb_array_length(public.followed_feed()->'activity'),
  4,
  'followed viewer receives each eligible activity type'
);

select is(
  jsonb_array_length(public.followed_feed(null, 1)->'activity'),
  1,
  'feed respects the requested page limit'
);

select ok(
  (public.followed_feed(null, 1)->>'next_cursor') is not null,
  'limited feed returns a keyset cursor when more activity exists'
);

update public.user_places
set visibility = 'self'
where id = '71000000-0000-0000-0000-000000000001';

select is(
  jsonb_array_length(public.followed_feed()->'activity'),
  2,
  'current source visibility removes both place and list-item events'
);

update public.user_places
set visibility = 'followers'
where id = '71000000-0000-0000-0000-000000000001';

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('feed_viewer', 'feed_actor');

select is(
  jsonb_array_length(public.followed_feed()->'activity'),
  0,
  'a current block removes historical activity immediately'
);

delete from public.blocks
where blocker_user_id = 'feed_viewer' and blocked_user_id = 'feed_actor';

update public.profiles
set is_private_profile = true
where id = 'feed_actor';

select is(
  jsonb_array_length(public.followed_feed()->'activity'),
  0,
  'private-mode accounts are omitted from the feed projection'
);

select ok(
  has_function_privilege('authenticated', 'public.followed_feed(text, integer)', 'execute'),
  'authenticated can execute the public followed-feed RPC'
);

select ok(
  not has_function_privilege('authenticated', 'app.followed_feed(text, integer)', 'execute'),
  'authenticated cannot bypass the public followed-feed RPC boundary'
);

set local role authenticated;

select lives_ok(
  $$ select public.followed_feed(null, 1) $$,
  'authenticated callers can execute the public RPC without requiring private helper access'
);

reset role;

select ok(
  not has_function_privilege('anon', 'public.followed_feed(text, integer)', 'execute'),
  'anon cannot execute the public followed-feed RPC'
);

select * from finish();
rollback;
