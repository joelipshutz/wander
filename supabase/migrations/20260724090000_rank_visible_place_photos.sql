begin;

-- Keep this gallery SECURITY INVOKER so the existing user_places,
-- place_visits, visit_photos, profiles, follows, and block RLS policies remain
-- authoritative. Ranking must never make a photo visible that the current
-- authenticated viewer could not already read.
--
-- The Google Places image is intentionally not part of this RPC; the iOS
-- presenter prepends it. This function ranks the eligible user-photo tail:
-- the viewer first, accounts the viewer follows next, and any future
-- policy-visible non-followed accounts last. Follower count is the popularity
-- signal inside each social tier. Under the current v0.1 visibility contract,
-- non-followed user-place rows remain excluded by RLS.
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
  with viewer as (
    select app.current_user_id() as id
  ),
  eligible_photos as materialized (
    select
      photo.id as photo_id,
      photo.storage_bucket,
      photo.storage_path,
      photo.width,
      photo.height,
      coalesce(photo.captured_at, visit.visited_at, photo.created_at) as captured_at,
      photo.created_at,
      photo.sort_order as source_sort_order,
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
  ),
  contributor_ranks as (
    select
      contributor.contributor_user_id,
      case
        when contributor.contributor_user_id = viewer.id then 0
        when exists (
          select 1
          from public.follows viewer_follow
          where viewer_follow.follower_user_id = viewer.id
            and viewer_follow.followed_user_id = contributor.contributor_user_id
        ) then 1
        else 2
      end as social_rank,
      (
        select count(*)::integer
        from public.follows follower
        where follower.followed_user_id = contributor.contributor_user_id
      ) as follower_count
    from (
      select distinct eligible.contributor_user_id
      from eligible_photos eligible
    ) contributor
    cross join viewer
  ),
  ranked as (
    select
      eligible.*,
      (
        row_number() over (
          order by
            contributor_rank.social_rank asc,
            contributor_rank.follower_count desc,
            eligible.created_at asc,
            eligible.source_sort_order asc,
            eligible.photo_id asc
        ) - 1
      )::integer as rank_cursor
    from eligible_photos eligible
    join contributor_ranks contributor_rank
      on contributor_rank.contributor_user_id = eligible.contributor_user_id
  )
  select
    ranked.photo_id,
    ranked.storage_bucket,
    ranked.storage_path,
    ranked.width,
    ranked.height,
    ranked.captured_at,
    ranked.created_at,
    ranked.rank_cursor as sort_order,
    ranked.contributor_user_id,
    ranked.contributor_display_name,
    ranked.contributor_handle,
    ranked.contributor_avatar_url,
    ranked.status
  from ranked
  where input_after_created_at is null
     or input_after_sort_order is null
     or input_after_photo_id is null
     or ranked.rank_cursor > input_after_sort_order
  order by ranked.rank_cursor asc
  limit least(greatest(coalesce(input_limit, 40), 1), 100)
$$;

comment on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer) is
  'Returns one cursor-paginated page of RLS-visible user photos ranked by viewer ownership, followed accounts, follower popularity, and stable photo order.';

revoke all on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer)
  from public, anon;
grant execute on function public.visible_place_photos(uuid, timestamptz, integer, uuid, integer)
  to authenticated;

commit;
