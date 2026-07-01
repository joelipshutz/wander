begin;

create extension if not exists pgtap;

select plan(18);

insert into public.profiles (id, handle, display_name)
values
  ('user_owner', 'owner', 'Owner'),
  ('user_follower', 'follower', 'Follower'),
  ('user_mutual', 'mutual', 'Mutual'),
  ('user_nonfollower', 'nonfollower', 'Non Follower'),
  ('user_blocked', 'blocked', 'Blocked');

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('user_follower', 'user_owner', 'profile'),
  ('user_mutual', 'user_owner', 'profile'),
  ('user_owner', 'user_mutual', 'profile'),
  ('user_blocked', 'user_owner', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('user_owner', 'user_blocked');

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
  ('10000000-0000-0000-0000-000000000001', 'Followers Place', 'coffee', 34.0, -118.0, 'mapkit', 'followers-place'),
  ('10000000-0000-0000-0000-000000000002', 'Mutual Place', 'restaurant', 34.1, -118.1, 'mapkit', 'mutual-place'),
  ('10000000-0000-0000-0000-000000000003', 'Self Place', 'hike', 34.2, -118.2, 'mapkit', 'self-place');

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values
  ('20000000-0000-0000-0000-000000000001', 'user_owner', '10000000-0000-0000-0000-000000000001', 'been', 'followers', 'manual'),
  ('20000000-0000-0000-0000-000000000002', 'user_owner', '10000000-0000-0000-0000-000000000002', 'been', 'mutuals', 'manual'),
  ('20000000-0000-0000-0000-000000000003', 'user_owner', '10000000-0000-0000-0000-000000000003', 'been', 'self', 'manual');

insert into public.question_definitions (
  id,
  owner_user_id,
  question_key,
  prompt,
  value_type,
  options,
  is_system
)
values
  (
    '30000000-0000-0000-0000-000000000001',
    null,
    'rating_signal',
    'how much did you like it?',
    'emoji_scale',
    '["meh", "fine", "good", "great"]',
    true
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    'user_owner',
    'custom_vibe',
    'what is the exact vibe?',
    'text',
    '[]',
    false
  ),
  (
    '30000000-0000-0000-0000-000000000003',
    'user_owner',
    'private_note_prompt',
    'what private detail do I care about?',
    'text',
    '[]',
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
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000001',
  'rating_signal',
  'emoji_scale',
  '"great"'
),
(
  '20000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-000000000002',
  'custom_vibe',
  'text',
  '"sunny and low-key"'
);

set local role authenticated;

select set_config('request.jwt.claim.sub', 'user_owner', true);
select is((select count(*) from public.user_places)::int, 3, 'owner can read followers mutuals and self places');
select is((select count(*) from public.place_attributes)::int, 2, 'owner can read own place attributes');

select set_config('request.jwt.claim.sub', 'user_follower', true);
select is((select count(*) from public.user_places)::int, 1, 'one-way follower can read followers places only');
select is((select count(*) from public.user_places where visibility = 'mutuals')::int, 0, 'one-way follower cannot read mutuals places');
select is((select count(*) from public.place_attributes)::int, 2, 'one-way follower can read attributes attached to visible places');
select is((select count(*) from public.question_definitions where question_key = 'custom_vibe')::int, 1, 'one-way follower can read custom question definition attached to a visible place');
select is((select count(*) from public.question_definitions where question_key = 'private_note_prompt')::int, 0, 'one-way follower cannot read unattached custom question definitions');

select set_config('request.jwt.claim.sub', 'user_mutual', true);
select is((select count(*) from public.user_places)::int, 2, 'mutual can read followers and mutuals places');
select is((select count(*) from public.user_places where visibility = 'self')::int, 0, 'mutual cannot read self places');

select set_config('request.jwt.claim.sub', 'user_nonfollower', true);
select is((select count(*) from public.user_places)::int, 0, 'non-follower cannot read places');
select is((select count(*) from public.profiles where id = 'user_owner')::int, 1, 'non-follower can read unblocked profile shell');

select set_config('request.jwt.claim.sub', 'user_blocked', true);
select is((select count(*) from public.user_places)::int, 0, 'blocked viewer cannot read places');
select is((select count(*) from public.profiles where id = 'user_owner')::int, 0, 'blocked viewer cannot read profile shell');
select is((select app.viewer_relationship('user_owner')), 'non_follower', 'blocked viewer relationship to blocker is non-follower');
select is_empty(
  $$ select * from app.search_profiles_by_handle('own') $$,
  'blocked viewer cannot find blocker in username search'
);
select is_empty(
  $$ select * from app.profile_following('user_blocked') where id = 'user_owner' $$,
  'blocked viewer following graph excludes blocker even with stale follow edge'
);

select set_config('request.jwt.claim.sub', 'user_mutual', true);
select isnt_empty(
  $$ select * from app.visible_places_in_view(33.9, -118.3, 34.3, -117.9, null, null, array['friends']) $$,
  'visible_places_in_view returns mutual/friends rows'
);
select isnt_empty(
  $$ select * from app.search_profiles_by_handle('own') $$,
  'search_profiles_by_handle returns unblocked near-exact handles'
);

select * from finish();

rollback;
