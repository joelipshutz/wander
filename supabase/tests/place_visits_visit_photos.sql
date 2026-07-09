begin;

create extension if not exists pgtap;

select plan(45);

select ok(
  exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'place_visits'
  ),
  'place_visits table exists'
);

select ok(
  exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'visit_photos'
  ),
  'visit_photos table exists'
);

select ok(
  exists (
    select 1
    from storage.buckets
    where id = 'visit-photos'
  ),
  'visit photos storage bucket exists'
);

select is(
  (
    select public
    from storage.buckets
    where id = 'visit-photos'
  ),
  false,
  'visit photos bucket is private'
);

select ok(
  (
    select allowed_mime_types @> array['image/jpeg', 'image/heic']::text[]
    from storage.buckets
    where id = 'visit-photos'
  ),
  'visit photos bucket allows common iOS image mime types'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'place_visits'
      and policyname = 'place visits readable through user place'
  ),
  'place visits have visibility read policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'visit_photos'
      and policyname = 'visit photos readable through visit'
  ),
  'visit photos have visibility read policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'visit photo objects readable through visit'
  ),
  'visit photo storage objects have visibility read policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'visit photo objects owner insert'
  ),
  'visit photo storage objects have owner insert policy'
);

select ok(
  has_table_privilege('authenticated', 'public.place_visits', 'select,insert,update,delete'),
  'authenticated has CRUD grants on place_visits'
);

select ok(
  has_table_privilege('authenticated', 'public.visit_photos', 'select,insert,update,delete'),
  'authenticated has CRUD grants on visit_photos'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.can_read_place_visit(uuid)'::regprocedure
  ),
  true,
  'can_read_place_visit runs as security definer'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.owns_place_visit(uuid)'::regprocedure
  ),
  true,
  'owns_place_visit runs as security definer'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.sync_backfilled_place_visit_for_user_place()'::regprocedure
  ),
  true,
  'backfilled visit sync trigger runs as security definer'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.sync_backfilled_place_visit_for_user_place()'::regprocedure
  ),
  'backfilled visit sync trigger pins search_path'
);

select ok(
  not has_function_privilege('authenticated', 'app.sync_backfilled_place_visit_for_user_place()', 'execute'),
  'authenticated cannot directly execute the backfilled visit trigger function'
);

select ok(
  has_function_privilege('authenticated', 'app.place_visit_rating_summary(uuid)', 'execute'),
  'authenticated can execute visit rating summary helper'
);

select ok(
  exists (
    select 1
    from pg_trigger
    where tgname = 'user_places_sync_backfilled_visit'
      and tgrelid = 'public.user_places'::regclass
      and not tgisinternal
  ),
  'user_places trigger keeps backfilled visits in sync'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_owner', 'visitowner', 'Visit Owner'),
  ('user_follower', 'visitfollower', 'Visit Follower'),
  ('user_mutual', 'visitmutual', 'Visit Mutual'),
  ('user_nonfollower', 'visitnonfollower', 'Visit Non Follower'),
  ('user_blocked', 'visitblocked', 'Visit Blocked');

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
  ('10000000-0000-0000-0000-000000000101', 'Visit Followers Place', 'coffee_tea_sweets', 34.01, -118.01, 'mapkit', 'visit-followers-place'),
  ('10000000-0000-0000-0000-000000000102', 'Visit Mutual Place', 'restaurants_food', 34.02, -118.02, 'mapkit', 'visit-mutual-place'),
  ('10000000-0000-0000-0000-000000000103', 'Visit Self Place', 'outdoors_nature', 34.03, -118.03, 'mapkit', 'visit-self-place'),
  ('10000000-0000-0000-0000-000000000104', 'Visit Wanna Place', 'bars_nightlife', 34.04, -118.04, 'mapkit', 'visit-wanna-place');

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  note,
  rating_score,
  visibility,
  visited_at,
  saved_at,
  source_type
)
values
  ('20000000-0000-0000-0000-000000000101', 'user_owner', '10000000-0000-0000-0000-000000000101', 'been', 'first visit', 4, 'followers', '2026-07-01T10:00:00Z', '2026-07-01T10:01:00Z', 'manual'),
  ('20000000-0000-0000-0000-000000000102', 'user_owner', '10000000-0000-0000-0000-000000000102', 'been', 'mutual visit', 3.5, 'mutuals', '2026-07-02T10:00:00Z', '2026-07-02T10:01:00Z', 'manual'),
  ('20000000-0000-0000-0000-000000000103', 'user_owner', '10000000-0000-0000-0000-000000000103', 'been', 'private visit', 5, 'self', '2026-07-03T10:00:00Z', '2026-07-03T10:01:00Z', 'manual'),
  ('20000000-0000-0000-0000-000000000104', 'user_owner', '10000000-0000-0000-0000-000000000104', 'wanna_go', 'want to go', null, 'followers', null, '2026-07-04T10:01:00Z', 'manual');

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
      and backfilled_from_user_place
      and deleted_at is null
  ),
  1,
  'been user_place insert creates one backfilled visit'
);

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000104'
  ),
  0,
  'wanna_go user_place insert does not create a visit'
);

select is(
  (
    select rating_score
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
      and backfilled_from_user_place
  ),
  4.0::numeric,
  'backfilled visit copies legacy rating score'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_owner', true);

update public.user_places
set note = 'updated first visit',
    rating_score = 4.5
where id = '20000000-0000-0000-0000-000000000101';

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
  ),
  1,
  'updating legacy save does not duplicate the backfilled visit'
);

select results_eq(
  $$
    select note, rating_score
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
  $$,
  $$
    values ('updated first visit'::text, 4.5::numeric)
  $$,
  'updating legacy save syncs note and rating onto the backfilled visit'
);

update public.user_places
set status = 'wanna_go'
where id = '20000000-0000-0000-0000-000000000101';

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
  ),
  0,
  'switching a save to wanna_go hides the backfilled visit'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
      and backfilled_from_user_place
  ),
  1,
  'wanna_go transition soft-deletes instead of duplicating the backfilled visit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_owner', true);

update public.user_places
set status = 'been',
    note = 'resurrected first visit',
    rating_score = 4
where id = '20000000-0000-0000-0000-000000000101';

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
  ),
  1,
  'switching back to been resurrects the same backfilled visit'
);

select is(
  (select count(*)::integer from public.place_visits),
  3,
  'owner can read all active own visits'
);

select set_config('request.jwt.claim.sub', 'user_follower', true);
select is(
  (select count(*)::integer from public.place_visits),
  1,
  'one-way follower can read followers-visible visits only'
);

select set_config('request.jwt.claim.sub', 'user_mutual', true);
select is(
  (select count(*)::integer from public.place_visits),
  2,
  'mutual can read followers and mutuals visits'
);

select set_config('request.jwt.claim.sub', 'user_nonfollower', true);
select is(
  (select count(*)::integer from public.place_visits),
  0,
  'non-follower cannot read visits'
);

select set_config('request.jwt.claim.sub', 'user_blocked', true);
select is(
  (select count(*)::integer from public.place_visits),
  0,
  'blocked viewer cannot read visits'
);

select set_config('request.jwt.claim.sub', 'user_owner', true);

select lives_ok(
  $$
    insert into public.place_visits (
      id,
      user_place_id,
      visited_at,
      note,
      rating_score
    )
    values (
      '40000000-0000-0000-0000-000000000101',
      '20000000-0000-0000-0000-000000000101',
      '2026-07-05T10:00:00Z',
      'second explicit visit',
      5
    )
  $$,
  'owner can insert an explicit additional visit'
);

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '20000000-0000-0000-0000-000000000101'
  ),
  2,
  'explicit visits can coexist with the synced backfilled visit'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'place_visits'
      and policyname = 'place visits owner insert'
      and with_check ilike '%backfilled_from_user_place%'
  ),
  'place visit owner insert policy keeps backfilled rows trigger-owned'
);

select set_config('request.jwt.claim.sub', 'user_follower', true);

select results_eq(
  $$
    select recommended_score, recommended_count
    from app.place_visit_rating_summary('10000000-0000-0000-0000-000000000101')
  $$,
  $$
    values (4.5::double precision, 2::integer)
  $$,
  'visit rating summary averages visible visit ratings'
);

select set_config('request.jwt.claim.sub', 'user_nonfollower', true);

select results_eq(
  $$
    select recommended_score, recommended_count
    from app.place_visit_rating_summary('10000000-0000-0000-0000-000000000101')
  $$,
  $$
    values (null::double precision, 0::integer)
  $$,
  'visit rating summary excludes non-visible visit ratings'
);

select set_config('request.jwt.claim.sub', 'user_owner', true);

select lives_ok(
  $$
    insert into public.visit_photos (
      id,
      visit_id,
      storage_path,
      content_type,
      byte_size,
      width,
      height,
      upload_state
    )
    values (
      '50000000-0000-0000-0000-000000000101',
      '40000000-0000-0000-0000-000000000101',
      'user_owner/40000000-0000-0000-0000-000000000101/50000000-0000-0000-0000-000000000101.jpg',
      'image/jpeg',
      120000,
      1600,
      1200,
      'uploaded'
    )
  $$,
  'owner can insert visit photo metadata for an owned visit and owned path'
);

select is(
  (
    select count(*)::integer
    from public.visit_photos
    where visit_id = '40000000-0000-0000-0000-000000000101'
  ),
  1,
  'owner can read own visit photo metadata'
);

select throws_ok(
  $$
    insert into public.visit_photos (
      id,
      visit_id,
      storage_path,
      content_type
    )
    values (
      '50000000-0000-0000-0000-000000000102',
      '40000000-0000-0000-0000-000000000101',
      'user_follower/40000000-0000-0000-0000-000000000101/50000000-0000-0000-0000-000000000102.jpg',
      'image/jpeg'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "visit_photos"',
  'owner cannot insert photo metadata under another user path'
);

select throws_ok(
  $$
    insert into public.visit_photos (
      id,
      visit_id,
      storage_path,
      content_type
    )
    values (
      '50000000-0000-0000-0000-000000000103',
      '40000000-0000-0000-0000-000000000101',
      'user_owner/40000000-0000-0000-0000-000000000999/50000000-0000-0000-0000-000000000103.jpg',
      'image/jpeg'
    )
  $$,
  '42501',
  'new row violates row-level security policy for table "visit_photos"',
  'owner cannot insert photo metadata for a mismatched visit path'
);

select set_config('request.jwt.claim.sub', 'user_follower', true);
select is(
  (select count(*)::integer from public.visit_photos),
  1,
  'one-way follower can read photo metadata for a visible visit'
);

select set_config('request.jwt.claim.sub', 'user_nonfollower', true);
select is(
  (select count(*)::integer from public.visit_photos),
  0,
  'non-follower cannot read visit photo metadata'
);

select set_config('request.jwt.claim.sub', 'user_blocked', true);
select is(
  (select count(*)::integer from public.visit_photos),
  0,
  'blocked viewer cannot read visit photo metadata'
);

select set_config('request.jwt.claim.sub', 'user_follower', true);

select is(
  app.can_read_place_visit('40000000-0000-0000-0000-000000000101'),
  true,
  'can_read_place_visit allows visible follower visit'
);

select is(
  app.owns_place_visit('40000000-0000-0000-0000-000000000101'),
  false,
  'owns_place_visit does not treat follower as owner'
);

select * from finish();

rollback;
