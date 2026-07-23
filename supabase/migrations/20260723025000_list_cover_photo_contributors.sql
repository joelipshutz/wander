begin;

-- This narrower companion to first_visible_place_photo is intentionally
-- SECURITY INVOKER. The caller can only reduce the set of RLS-visible photos
-- to known list contributors; supplying another user id cannot expand access.
create or replace function public.first_visible_place_photo_by_users(
  input_place_id uuid,
  input_user_ids text[]
)
returns table (
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
  select
    vp.id as photo_id,
    vp.storage_bucket,
    vp.storage_path,
    vp.width,
    vp.height
  from public.visit_photos vp
  join public.place_visits pv on pv.id = vp.visit_id
  join public.user_places up on up.id = pv.user_place_id
  where up.place_id = input_place_id
    and up.user_id = any(coalesce(input_user_ids, array[]::text[]))
    and up.deleted_at is null
    and pv.deleted_at is null
    and vp.deleted_at is null
    and vp.upload_state = 'uploaded'
  order by vp.created_at asc, vp.sort_order asc, vp.id asc
  limit 1
$$;

revoke all on function public.first_visible_place_photo_by_users(uuid, text[]) from public, anon;
grant execute on function public.first_visible_place_photo_by_users(uuid, text[]) to authenticated;

commit;
