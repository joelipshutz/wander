begin;

-- The gallery remains SECURITY INVOKER so user_places, place_visits,
-- visit_photos, profiles, and storage RLS stay authoritative for the current
-- authenticated viewer. The explicit visibility/profile predicates make the
-- carousel narrower than general visit visibility: stealth/mutual-only saves
-- and private profiles never contribute photos, including for their owner.
create or replace function public.visible_place_photos(
  input_place_id uuid,
  input_after_created_at timestamptz default null,
  input_after_sort_order integer default null,
  input_after_photo_id uuid default null,
  input_limit integer default 40
)
returns table (
  photo_id uuid,
  storage_bucket text,
  storage_path text,
  width integer,
  height integer,
  captured_at timestamptz,
  created_at timestamptz,
  sort_order integer,
  contributor_user_id text,
  contributor_display_name text,
  contributor_handle text,
  contributor_avatar_url text,
  status text
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    photo.id as photo_id,
    photo.storage_bucket,
    photo.storage_path,
    photo.width,
    photo.height,
    coalesce(photo.captured_at, visit.visited_at, photo.created_at) as captured_at,
    photo.created_at,
    photo.sort_order,
    contributor.id as contributor_user_id,
    contributor.display_name as contributor_display_name,
    contributor.handle as contributor_handle,
    contributor.avatar_url as contributor_avatar_url,
    user_place.status
  from public.visit_photos photo
  join public.place_visits visit on visit.id = photo.visit_id
  join public.user_places user_place on user_place.id = visit.user_place_id
  join public.profiles contributor on contributor.id = user_place.user_id
  where user_place.place_id = input_place_id
    and user_place.visibility = 'followers'
    and user_place.deleted_at is null
    and visit.deleted_at is null
    and photo.deleted_at is null
    and photo.upload_state = 'uploaded'
    and contributor.deleted_at is null
    and not contributor.is_private_profile
    and (
      input_after_created_at is null
      or input_after_sort_order is null
      or input_after_photo_id is null
      or (photo.created_at, photo.sort_order, photo.id)
        > (input_after_created_at, input_after_sort_order, input_after_photo_id)
    )
  order by photo.created_at asc, photo.sort_order asc, photo.id asc
  limit least(greatest(coalesce(input_limit, 40), 1), 100)
$$;

comment on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer) is
  'Returns one cursor-paginated page of RLS-visible user photos from Everyone-visible saves owned by public profiles.';

revoke all on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer)
  from public, anon;
grant execute on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer)
  to authenticated;

commit;
