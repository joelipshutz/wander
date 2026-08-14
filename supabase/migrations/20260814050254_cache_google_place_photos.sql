begin;

-- Google Places content may only be cached temporarily. The Edge Function
-- refreshes rows after 30 days and keeps the image objects in this private,
-- service-role-only bucket so TestFlight installs can share the cache without
-- exposing Storage credentials to the iOS client.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'google-place-photo-cache',
  'google-place-photo-cache',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table public.google_place_photo_cache (
  cache_key text primary key
    check (cache_key ~ '^[0-9a-f]{64}$'),
  object_path text,
  provider_place_id text not null,
  provider_primary_type text,
  provider_types text[] not null default '{}',
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  content_type text
    check (content_type is null or content_type in ('image/jpeg', 'image/png', 'image/webp')),
  byte_size bigint check (byte_size is null or byte_size between 1 and 10485760),
  author_name text,
  author_profile_url text,
  author_avatar_url text,
  source_photo_url text,
  flag_content_url text,
  fetched_at timestamptz not null,
  expires_at timestamptz not null,
  last_accessed_at timestamptz not null default now(),
  constraint google_place_photo_cache_object_metadata_check check (
    (object_path is null and content_type is null and byte_size is null)
    or
    (object_path is not null and content_type is not null and byte_size is not null and source_photo_url is not null)
  ),
  constraint google_place_photo_cache_expiry_check check (
    expires_at > fetched_at
    and expires_at <= fetched_at + interval '30 days'
  )
);

alter table public.google_place_photo_cache enable row level security;
alter table public.google_place_photo_cache force row level security;

create policy "place photo cache service role only"
  on public.google_place_photo_cache
  for all
  to service_role
  using (true)
  with check (true);

revoke all on table public.google_place_photo_cache
  from public, anon, authenticated, service_role;
grant select, insert, update, delete on table public.google_place_photo_cache
  to service_role;

comment on table public.google_place_photo_cache is
  'Private 30-day metadata index for Google Places photos cached by the place-photo Edge Function. Only the service role can access it.';
comment on column public.google_place_photo_cache.cache_key is
  'SHA-256 digest of a normalized place lookup identity; raw names, addresses, and coordinates are not stored.';
comment on column public.google_place_photo_cache.expires_at is
  'Hard refresh boundary capped at 30 days after fetched_at.';

commit;
