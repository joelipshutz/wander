begin;

alter table public.google_place_photo_cache
  drop constraint google_place_photo_cache_expiry_check;

alter table public.google_place_photo_cache
  alter column expires_at drop not null;

update public.google_place_photo_cache
set expires_at = null;

comment on table public.google_place_photo_cache is
  'Private metadata index for Google Places photos cached indefinitely by the place-photo Edge Function. Only the service role can access it.';
comment on column public.google_place_photo_cache.expires_at is
  'Deprecated compatibility column. Null means the cache entry has no automatic expiration.';

commit;
