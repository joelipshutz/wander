begin;

create extension if not exists pgtap;

select plan(12);

select ok(
  exists(select 1 from storage.buckets where id = 'google-place-photo-cache'),
  'Google place photo cache bucket exists'
);
select is(
  (select public from storage.buckets where id = 'google-place-photo-cache'),
  false,
  'Google place photo cache bucket is private'
);
select is(
  (select file_size_limit from storage.buckets where id = 'google-place-photo-cache'),
  10485760::bigint,
  'Google place photo cache limits objects to 10 MiB'
);
select is(
  (select allowed_mime_types from storage.buckets where id = 'google-place-photo-cache'),
  array['image/jpeg', 'image/png', 'image/webp']::text[],
  'Google place photo cache accepts only supported image types'
);

select has_table(
  'public',
  'google_place_photo_cache',
  'Google place photo cache metadata table exists'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.google_place_photo_cache'::regclass),
  true,
  'cache metadata has row-level security enabled'
);
select is(
  (select relforcerowsecurity from pg_class where oid = 'public.google_place_photo_cache'::regclass),
  true,
  'cache metadata forces row-level security'
);
select policies_are(
  'public',
  'google_place_photo_cache',
  array['place photo cache service role only'],
  'cache metadata has only the explicit service-role policy'
);
select ok(
  not has_table_privilege('anon', 'public.google_place_photo_cache', 'select')
    and not has_table_privilege('anon', 'public.google_place_photo_cache', 'insert')
    and not has_table_privilege('anon', 'public.google_place_photo_cache', 'update')
    and not has_table_privilege('anon', 'public.google_place_photo_cache', 'delete'),
  'anonymous clients have no cache metadata privileges'
);
select ok(
  not has_table_privilege('authenticated', 'public.google_place_photo_cache', 'select')
    and not has_table_privilege('authenticated', 'public.google_place_photo_cache', 'insert')
    and not has_table_privilege('authenticated', 'public.google_place_photo_cache', 'update')
    and not has_table_privilege('authenticated', 'public.google_place_photo_cache', 'delete'),
  'authenticated clients have no cache metadata privileges'
);
select ok(
  has_table_privilege('service_role', 'public.google_place_photo_cache', 'select')
    and has_table_privilege('service_role', 'public.google_place_photo_cache', 'insert')
    and has_table_privilege('service_role', 'public.google_place_photo_cache', 'update')
    and has_table_privilege('service_role', 'public.google_place_photo_cache', 'delete')
    and not has_table_privilege('service_role', 'public.google_place_photo_cache', 'truncate'),
  'service role has only the cache metadata privileges needed by the Edge Function'
);
select ok(
  exists(
    select 1
    from pg_constraint
    where conrelid = 'public.google_place_photo_cache'::regclass
      and conname = 'google_place_photo_cache_expiry_check'
      and pg_get_constraintdef(oid) like '%6 mons%'
  ),
  'cache metadata enforces the six-month refresh boundary'
);

select * from finish();
rollback;
