begin;
set local lock_timeout = '5s';

-- REC-646: Storage performs authenticated object-info reads while serving
-- protected photos. The September 23 policy allowed bytes/transforms but only
-- owners could pass the info operation, returning NoSuchKey to valid viewers.
-- Preserve the existing authenticated-only policy and recursive source gate.
-- Signing, listing and writes remain outside this viewer read policy.
alter policy "visit photo objects readable through visit"
on storage.objects
using (
  bucket_id = 'visit-photos'
  and storage.allow_any_operation(array[
    'object.get_authenticated',
    'render.image_authenticated',
    'object.get_authenticated_info',
    'object.head_authenticated_info'
  ])
  and public.can_read_visit_photo(bucket_id, name)
);

-- Prior definitions: 20260811220214, 20260923222333, 20260924031627,
-- 20260925002745. Retain aliases, requested cache keys, ordering, return type,
-- STABLE SECURITY DEFINER, pinned search_path and authenticated-only execution.
-- The definer can see compatibility visits, but both the activity and every
-- photo's original/copy lineage must authorize the current viewer.
--
-- Older parent events predate visit_id. Resolve only their unique backfilled
-- original visit, proven by parent/actor/place and exact historical timestamp.
-- Never borrow a later visit. Explicit visit IDs remain authoritative, even
-- when that visit has no photos. Do not rewrite posts or their metadata.
create or replace function public.activity_media(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb)
language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select requested.id as activity_id,
    coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', photo.id,
        'url', null,
        'storage_bucket', photo.storage_bucket,
        'storage_path', photo.storage_path,
        'accessibility_label', 'Activity photo'
      ) order by photo.sort_order, photo.created_at, photo.id)
      from public.visit_photos photo
      where photo.visit_id = coalesce(event.visit_id, compatibility_visit.id)
        and photo.upload_state = 'uploaded'
        and photo.deleted_at is null
        and app.can_read_photo_source(app.current_user_id(), photo.id)
    ), '[]'::jsonb) as media
  from (select distinct unnest(coalesce(input_activity_ids, '{}'::uuid[])) as id) requested
  join public.feed_events event on event.id = app.canonical_activity_id(requested.id)
  left join public.user_places parent
    on event.visit_id is null and event.event_type = 'place_been'
    and parent.id = event.user_place_id and parent.deleted_at is null
    and parent.user_id = event.actor_user_id and parent.place_id = event.place_id
  left join public.place_visits compatibility_visit
    on compatibility_visit.user_place_id = parent.id
    and compatibility_visit.backfilled_from_user_place
    and compatibility_visit.deleted_at is null
    and compatibility_visit.visited_at = event.occurred_at
    and not exists (
      select 1 from public.feed_events linked
      where linked.visit_id = compatibility_visit.id and linked.event_type = 'place_been'
    )
    and not exists (
      select 1 from public.feed_events competing
      where competing.user_place_id = parent.id and competing.event_type = 'place_been'
        and competing.occurred_at = event.occurred_at and competing.id <> event.id
    )
  where app.can_read_activity_event(app.current_user_id(), event.id)
  order by event.occurred_at desc, event.id desc
$$;
revoke all on function public.activity_media(uuid[]) from public, anon;
grant execute on function public.activity_media(uuid[]) to authenticated;

commit;
