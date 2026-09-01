begin;

create extension if not exists pgtap;

select plan(18);

select has_function(
  'public',
  'visible_place_photos',
  array['uuid', 'timestamptz', 'integer', 'uuid', 'integer']
);

select function_privs_are(
  'public',
  'visible_place_photos',
  array['uuid', 'timestamptz', 'integer', 'uuid', 'integer'],
  'authenticated',
  array['EXECUTE']
);

select function_privs_are(
  'public',
  'visible_place_photos',
  array['uuid', 'timestamptz', 'integer', 'uuid', 'integer'],
  'anon',
  array[]::text[]
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.visible_place_photos(uuid,timestamptz,integer,uuid,integer)'::regprocedure
  ),
  false,
  'place photo gallery stays security invoker so row visibility remains authoritative'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.visible_place_photos(uuid,timestamptz,integer,uuid,integer)'::regprocedure
  ),
  'place photo gallery pins search_path'
);

select has_function(
  'public',
  'visible_place_photos_for_places',
  array['uuid[]', 'timestamptz', 'integer', 'uuid', 'integer']
);

select function_privs_are(
  'public',
  'visible_place_photos_for_places',
  array['uuid[]', 'timestamptz', 'integer', 'uuid', 'integer'],
  'authenticated',
  array['EXECUTE']
);

select function_privs_are(
  'public',
  'visible_place_photos_for_places',
  array['uuid[]', 'timestamptz', 'integer', 'uuid', 'integer'],
  'anon',
  array[]::text[]
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.visible_place_photos_for_places(uuid[],timestamptz,integer,uuid,integer)'::regprocedure
  ),
  false,
  'grouped place photo gallery stays security invoker'
);

select ok(
  (
    select 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.visible_place_photos_for_places(uuid[],timestamptz,integer,uuid,integer)'::regprocedure
  ),
  'grouped place photo gallery pins search_path'
);

insert into public.profiles (id, handle, display_name, avatar_url, is_private_profile)
values
  ('gallery_public_owner', 'publicowner', 'Public Owner', 'https://example.com/public.jpg', false),
  ('gallery_popular_owner', 'popularowner', 'Popular Owner', 'https://example.com/popular.jpg', false),
  ('gallery_stealth_owner', 'stealthowner', 'Stealth Owner', 'https://example.com/stealth.jpg', false),
  ('gallery_private_owner', 'privateowner', 'Private Owner', 'https://example.com/private.jpg', true),
  ('gallery_viewer', 'galleryviewer', 'Gallery Viewer', null, false),
  ('gallery_blocked_viewer', 'galleryblocked', 'Gallery Blocked', null, false),
  ('gallery_popularity_fan_one', 'popularityfanone', 'Popularity Fan One', null, false),
  ('gallery_popularity_fan_two', 'popularityfantwo', 'Popularity Fan Two', null, false),
  ('gallery_popularity_fan_three', 'popularityfanthree', 'Popularity Fan Three', null, false);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('gallery_viewer', 'gallery_public_owner', 'profile'),
  ('gallery_viewer', 'gallery_popular_owner', 'profile'),
  ('gallery_viewer', 'gallery_private_owner', 'profile'),
  ('gallery_blocked_viewer', 'gallery_public_owner', 'profile'),
  ('gallery_popularity_fan_one', 'gallery_public_owner', 'profile'),
  ('gallery_popularity_fan_one', 'gallery_popular_owner', 'profile'),
  ('gallery_popularity_fan_two', 'gallery_popular_owner', 'profile'),
  ('gallery_popularity_fan_three', 'gallery_popular_owner', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('gallery_public_owner', 'gallery_blocked_viewer');

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
  (
    '71000000-0000-0000-0000-000000000133',
    'Gallery Place',
    'restaurants_food',
    34.01,
    -118.01,
    'mapkit',
    'rec-133-gallery'
  ),
  (
    '71000000-0000-0000-0000-000000000134',
    'Gallery Place Duplicate',
    'restaurants_food',
    34.01001,
    -118.01001,
    'google_places',
    'rec-134-gallery-duplicate'
  );

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  visited_at,
  saved_at,
  source_type
)
values
  (
    '72000000-0000-0000-0000-000000000130',
    'gallery_viewer',
    '71000000-0000-0000-0000-000000000133',
    'been',
    'followers',
    '2026-07-23T18:00:00Z',
    '2026-07-23T18:00:00Z',
    'manual'
  ),
  (
    '72000000-0000-0000-0000-000000000131',
    'gallery_public_owner',
    '71000000-0000-0000-0000-000000000133',
    'been',
    'followers',
    '2026-07-20T18:00:00Z',
    '2026-07-20T18:00:00Z',
    'manual'
  ),
  (
    '72000000-0000-0000-0000-000000000132',
    'gallery_stealth_owner',
    '71000000-0000-0000-0000-000000000133',
    'been',
    'self',
    '2026-07-21T18:00:00Z',
    '2026-07-21T18:00:00Z',
    'manual'
  ),
  (
    '72000000-0000-0000-0000-000000000133',
    'gallery_private_owner',
    '71000000-0000-0000-0000-000000000133',
    'been',
    'followers',
    '2026-07-22T18:00:00Z',
    '2026-07-22T18:00:00Z',
    'manual'
  ),
  (
    '72000000-0000-0000-0000-000000000135',
    'gallery_popular_owner',
    '71000000-0000-0000-0000-000000000133',
    'been',
    'followers',
    '2026-07-22T19:00:00Z',
    '2026-07-22T19:00:00Z',
    'manual'
  ),
  (
    '72000000-0000-0000-0000-000000000136',
    'gallery_public_owner',
    '71000000-0000-0000-0000-000000000134',
    'been',
    'followers',
    '2026-07-24T18:00:00Z',
    '2026-07-24T18:00:00Z',
    'manual'
  );

insert into public.place_visits (
  id,
  user_place_id,
  visited_at,
  backfilled_from_user_place
)
values
  ('73000000-0000-0000-0000-000000000130', '72000000-0000-0000-0000-000000000130', '2026-07-23T18:00:00Z', false),
  ('73000000-0000-0000-0000-000000000131', '72000000-0000-0000-0000-000000000131', '2026-07-20T18:00:00Z', false),
  ('73000000-0000-0000-0000-000000000132', '72000000-0000-0000-0000-000000000132', '2026-07-21T18:00:00Z', false),
  ('73000000-0000-0000-0000-000000000133', '72000000-0000-0000-0000-000000000133', '2026-07-22T18:00:00Z', false),
  ('73000000-0000-0000-0000-000000000135', '72000000-0000-0000-0000-000000000135', '2026-07-22T19:00:00Z', false),
  ('73000000-0000-0000-0000-000000000136', '72000000-0000-0000-0000-000000000136', '2026-07-24T18:00:00Z', false);

insert into public.visit_photos (
  id,
  visit_id,
  storage_path,
  content_type,
  width,
  height,
  captured_at,
  sort_order,
  upload_state,
  created_at
)
values
  (
    '74000000-0000-0000-0000-000000000130',
    '73000000-0000-0000-0000-000000000130',
    'gallery_viewer/73000000-0000-0000-0000-000000000130/74000000-0000-0000-0000-000000000130.jpg',
    'image/jpeg',
    1600,
    1200,
    '2026-07-23T18:10:00Z',
    0,
    'uploaded',
    '2026-07-23T18:10:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000131',
    '73000000-0000-0000-0000-000000000131',
    'gallery_public_owner/73000000-0000-0000-0000-000000000131/74000000-0000-0000-0000-000000000131.jpg',
    'image/jpeg',
    1600,
    1200,
    '2026-07-20T18:10:00Z',
    0,
    'uploaded',
    '2026-07-20T18:10:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000132',
    '73000000-0000-0000-0000-000000000131',
    'gallery_public_owner/73000000-0000-0000-0000-000000000131/74000000-0000-0000-0000-000000000132.jpg',
    'image/jpeg',
    1200,
    1600,
    '2026-07-20T18:20:00Z',
    1,
    'uploaded',
    '2026-07-20T18:20:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000133',
    '73000000-0000-0000-0000-000000000132',
    'gallery_stealth_owner/73000000-0000-0000-0000-000000000132/74000000-0000-0000-0000-000000000133.jpg',
    'image/jpeg',
    1200,
    1200,
    '2026-07-21T18:10:00Z',
    0,
    'uploaded',
    '2026-07-21T18:10:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000134',
    '73000000-0000-0000-0000-000000000133',
    'gallery_private_owner/73000000-0000-0000-0000-000000000133/74000000-0000-0000-0000-000000000134.jpg',
    'image/jpeg',
    1200,
    1200,
    '2026-07-22T18:10:00Z',
    0,
    'uploaded',
    '2026-07-22T18:10:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000135',
    '73000000-0000-0000-0000-000000000135',
    'gallery_popular_owner/73000000-0000-0000-0000-000000000135/74000000-0000-0000-0000-000000000135.jpg',
    'image/jpeg',
    1600,
    1200,
    '2026-07-22T19:10:00Z',
    0,
    'uploaded',
    '2026-07-22T19:10:00Z'
  ),
  (
    '74000000-0000-0000-0000-000000000136',
    '73000000-0000-0000-0000-000000000136',
    'gallery_public_owner/73000000-0000-0000-0000-000000000136/74000000-0000-0000-0000-000000000136.jpg',
    'image/jpeg',
    1200,
    1600,
    '2026-07-24T18:10:00Z',
    0,
    'uploaded',
    '2026-07-24T18:10:00Z'
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'gallery_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select count(*)::integer
    from public.visible_place_photos('71000000-0000-0000-0000-000000000133')
  ),
  4,
  'gallery returns only photos from Everyone-visible saves owned by public profiles'
);

select results_eq(
  $$
    select photo_id::text, sort_order, contributor_user_id, contributor_handle, status
    from public.visible_place_photos('71000000-0000-0000-0000-000000000133')
  $$,
  $$
    values
      ('74000000-0000-0000-0000-000000000130', 0, 'gallery_viewer', 'galleryviewer', 'been'),
      ('74000000-0000-0000-0000-000000000135', 1, 'gallery_popular_owner', 'popularowner', 'been'),
      ('74000000-0000-0000-0000-000000000131', 2, 'gallery_public_owner', 'publicowner', 'been'),
      ('74000000-0000-0000-0000-000000000132', 3, 'gallery_public_owner', 'publicowner', 'been')
  $$,
  'gallery ranks the viewer first, then followed contributors by follower popularity'
);

select is(
  (
    select photo_id::text
    from public.visible_place_photos(
      '71000000-0000-0000-0000-000000000133',
      null,
      null,
      null,
      1
    )
  ),
  '74000000-0000-0000-0000-000000000130',
  'gallery first page honors its requested limit'
);

select is(
  (
    select photo_id::text
    from public.visible_place_photos(
      '71000000-0000-0000-0000-000000000133',
      '2026-07-23T18:10:00Z',
      0,
      '74000000-0000-0000-0000-000000000130',
      1
    )
  ),
  '74000000-0000-0000-0000-000000000135',
  'gallery cursor returns the next stable photo'
);

select is(
  (
    select count(*)::integer
    from public.visible_place_photos_for_places(
      array[
        '71000000-0000-0000-0000-000000000133'::uuid,
        '71000000-0000-0000-0000-000000000134'::uuid,
        '71000000-0000-0000-0000-000000000134'::uuid
      ]
    )
  ),
  5,
  'grouped gallery includes eligible photos from every equivalent place row once'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'gallery_stealth_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select count(*)::integer
    from public.visible_place_photos('71000000-0000-0000-0000-000000000133')
  ),
  0,
  'gallery excludes stealth photos even for their owner'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'gallery_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select count(*)::integer
    from public.visible_place_photos('71000000-0000-0000-0000-000000000133')
  ),
  4,
  'gallery keeps public contributor photos visible for followers'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'gallery_blocked_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select count(*)::integer
    from public.visible_place_photos('71000000-0000-0000-0000-000000000133')
  ),
  0,
  'gallery RLS excludes photos from blocked contributors'
);

do $strict_pgtap$
declare
  diagnostics text;
begin
  select string_agg(message, E'\n')
  into diagnostics
  from finish() as result(message);

  if diagnostics is not null then
    raise exception 'Visible place photo gallery pgTAP failures:%', E'\n' || diagnostics;
  end if;
end;
$strict_pgtap$;

rollback;
