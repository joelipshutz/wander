begin;

alter table public.google_place_photo_cache
  drop constraint google_place_photo_cache_expiry_check;

update public.google_place_photo_cache
set expires_at = fetched_at + interval '6 months';

alter table public.google_place_photo_cache
  add constraint google_place_photo_cache_expiry_check check (
    expires_at > fetched_at
    and expires_at <= fetched_at + interval '6 months'
  );

comment on table public.google_place_photo_cache is
  'Private six-month metadata index for Google Places photos cached by the place-photo Edge Function. Only the service role can access it.';
comment on column public.google_place_photo_cache.expires_at is
  'Hard refresh boundary capped at six calendar months after fetched_at.';

commit;
