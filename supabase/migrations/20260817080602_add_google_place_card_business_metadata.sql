begin;

alter table public.google_place_photo_cache
  add column provider_rating double precision,
  add column provider_user_rating_count integer,
  add column provider_open_now boolean,
  add column provider_next_open_time timestamptz,
  add column provider_next_close_time timestamptz,
  add column provider_utc_offset_minutes integer,
  add constraint google_place_photo_cache_rating_check check (
    provider_rating is null or provider_rating between 1 and 5
  ),
  add constraint google_place_photo_cache_rating_count_check check (
    provider_user_rating_count is null or provider_user_rating_count >= 0
  ),
  add constraint google_place_photo_cache_utc_offset_check check (
    provider_utc_offset_minutes is null
      or provider_utc_offset_minutes between -840 and 840
  );

comment on column public.google_place_photo_cache.provider_rating is
  'Google Places rating used by the selected Map place card.';
comment on column public.google_place_photo_cache.provider_user_rating_count is
  'Google Places rating count used by the selected Map place card.';
comment on column public.google_place_photo_cache.provider_open_now is
  'Google Places currentOpeningHours.openNow value for the selected Map place card.';
comment on column public.google_place_photo_cache.provider_next_open_time is
  'Google Places currentOpeningHours.nextOpenTime value for the selected Map place card.';
comment on column public.google_place_photo_cache.provider_next_close_time is
  'Google Places currentOpeningHours.nextCloseTime value for the selected Map place card.';
comment on column public.google_place_photo_cache.provider_utc_offset_minutes is
  'Google Places UTC offset used to render business-hour times in the place timezone.';
comment on column public.google_place_photo_cache.fetched_at is
  'Last Google business-metadata refresh; opening-hours fields are reused for at most 15 minutes.';

commit;
