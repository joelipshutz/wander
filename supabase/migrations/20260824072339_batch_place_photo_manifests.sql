begin;

-- Resolve the first RLS-visible visit photo for many places in one round trip.
-- SECURITY INVOKER is intentional: user_places, place_visits, visit_photos,
-- profiles, follows, and blocks keep their existing RLS policies authoritative.
-- input_user_ids can only narrow the visible result set to list contributors.
create or replace function public.first_visible_place_photos_by_users(
  input_place_ids uuid[],
  input_user_ids text[] default null
)
returns table (
  place_id uuid,
  photo_id uuid,
  storage_bucket text,
  storage_path text,
  width integer,
  height integer
)
language sql
stable
security invoker
set search_path = public, app
as $$
  with requested_places as (
    select distinct requested.place_id
    from unnest(coalesce(input_place_ids, array[]::uuid[])) as requested(place_id)
    where requested.place_id is not null
    limit 64
  ),
  ranked_photos as (
    select
      up.place_id,
      vp.id as photo_id,
      vp.storage_bucket,
      vp.storage_path,
      vp.width,
      vp.height,
      row_number() over (
        partition by up.place_id
        order by vp.created_at asc, vp.sort_order asc, vp.id asc
      ) as photo_rank
    from requested_places requested
    join public.user_places up on up.place_id = requested.place_id
    join public.place_visits pv on pv.user_place_id = up.id
    join public.visit_photos vp on vp.visit_id = pv.id
    where up.deleted_at is null
      and pv.deleted_at is null
      and vp.deleted_at is null
      and vp.upload_state = 'uploaded'
      and (
        input_user_ids is null
        or up.user_id = any(coalesce(input_user_ids, array[]::text[]))
      )
  )
  select
    ranked.place_id,
    ranked.photo_id,
    ranked.storage_bucket,
    ranked.storage_path,
    ranked.width,
    ranked.height
  from ranked_photos ranked
  where ranked.photo_rank = 1
  order by ranked.place_id
$$;

revoke all on function public.first_visible_place_photos_by_users(uuid[], text[])
  from public, anon;
grant execute on function public.first_visible_place_photos_by_users(uuid[], text[])
  to authenticated;

create index if not exists visit_photos_uploaded_cover_idx
  on public.visit_photos(visit_id, created_at, sort_order, id)
  where deleted_at is null and upload_state = 'uploaded';

update storage.buckets
set file_size_limit = 16777216
where id = 'google-place-photo-cache';

alter table public.google_place_photo_cache
  drop constraint if exists google_place_photo_cache_byte_size_check;
alter table public.google_place_photo_cache
  add constraint google_place_photo_cache_byte_size_check
  check (byte_size is null or byte_size between 1 and 16777216);

comment on function public.first_visible_place_photos_by_users(uuid[], text[]) is
  'Batch, RLS-authoritative first visible photo lookup for up to 64 canonical places; contributor ids can only narrow results.';

commit;
