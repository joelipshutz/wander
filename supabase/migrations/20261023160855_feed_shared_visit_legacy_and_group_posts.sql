begin;
set local lock_timeout = '5s';

-- REC-636. Historical identity follows the exact compatibility proof in
-- 20261015202706 activity_media, plus aliases from 20260924031627. No rows,
-- comments, or engagement are rewritten. Explicit visit identity wins.
-- This private definer reads provenance, not a caller-selected viewer. Its
-- result is gated by both existing activity and recursive source authorization.
create function app.feed_shared_visit_source(input_activity_id uuid)
returns uuid language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select coalesce(event.visit_id, compatibility_visit.id)
  from public.feed_events event
  left join public.user_places parent
    on event.visit_id is null and parent.id = event.user_place_id
    and parent.deleted_at is null and parent.user_id = event.actor_user_id
    and parent.place_id = event.place_id
  left join public.place_visits compatibility_visit
    on compatibility_visit.user_place_id = parent.id
    and compatibility_visit.backfilled_from_user_place
    and compatibility_visit.deleted_at is null
    and compatibility_visit.visited_at = event.occurred_at
    and not exists (select 1 from public.feed_events linked
      where linked.visit_id = compatibility_visit.id and linked.event_type = 'place_been')
    and not exists (select 1 from public.feed_events competing
      where competing.user_place_id = parent.id and competing.event_type = 'place_been'
        and competing.occurred_at = event.occurred_at and competing.id <> event.id)
  where event.id = app.canonical_activity_id(input_activity_id)
    and event.event_type = 'place_been'
    and app.current_user_id() is not null
    and app.can_read_activity_event(app.current_user_id(), event.id)
    and app.can_read_visit_source(app.current_user_id(), coalesce(event.visit_id, compatibility_visit.id))
$$;
revoke all on function app.feed_shared_visit_source(uuid) from public, anon, authenticated;

-- Prior definition: 20261022233153. Same ABI, volatility, search path and grants.
create or replace function public.feed_shared_visit_context(input_activity_ids uuid[])
returns table(activity_id uuid, visit_id uuid, group_id uuid, companions jsonb)
language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  with requested as (
    select requested.id, resolved_visit.id as visit_id, event.actor_user_id
    from (select distinct unnest((coalesce(input_activity_ids, array[]::uuid[]))[1:50]) as id) requested
    join public.feed_events event on event.id = app.canonical_activity_id(requested.id)
    cross join lateral (select app.feed_shared_visit_source(requested.id) as id) resolved_visit
    where resolved_visit.id is not null
  ), resolved as (
    select requested.*, shared_group.id as shared_group_id, true as is_source
    from requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.visit_id
    where shared_group.cancelled_at is null
      and shared_group.owner_user_id = requested.actor_user_id
    union all
    select requested.*, shared_group.id, false
    from requested
    join public.shared_visit_participants participant on participant.visit_id = requested.visit_id
      and participant.user_id = requested.actor_user_id and participant.status = 'accepted'
    join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    where shared_group.cancelled_at is null
  )
  select resolved.id, resolved.visit_id, resolved.shared_group_id,
    jsonb_agg(jsonb_build_object(
      'status', participant.status,
      'profile', jsonb_build_object(
        'id', visible.companion_user_id,
        'handle', visible.companion_handle,
        'display_name', visible.companion_display_name,
        'avatar_url', visible.companion_avatar_url,
        'relationship', case
          when visible.companion_user_id = app.current_user_id() then 'owner'
          when app.is_mutual(app.current_user_id(), visible.companion_user_id) then 'mutual'
          when app.follows(app.current_user_id(), visible.companion_user_id) then 'follower'
          else 'non_follower' end))
      order by (visible.companion_user_id = app.current_user_id()) desc,
        visible.companion_display_name, visible.companion_user_id)
  from resolved
  -- Reuse the audited visibility boundary; no direct profile snapshot joins.
  cross join lateral public.get_shared_visit_companion_context(array[resolved.visit_id]) visible
  join public.shared_visit_participants participant
    on participant.group_id = resolved.shared_group_id
    and participant.user_id = visible.companion_user_id
  where (
      participant.status in ('owner', 'accepted')
      and app.can_read_visit_source(app.current_user_id(), participant.visit_id)
    ) or (
      participant.status = 'pending' and resolved.is_source
      and resolved.actor_user_id = app.current_user_id()
    )
  -- No visible companion means no group identity is disclosed either.
  group by resolved.id, resolved.visit_id, resolved.shared_group_id
  order by resolved.id
$$;

-- Definer is deliberate: private group tables are inaccessible to clients.
-- The authenticated viewer is obtained internally, never supplied as a param.
revoke all on function public.feed_shared_visit_context(uuid[]) from public, anon;
grant execute on function public.feed_shared_visit_context(uuid[]) to authenticated;
comment on function public.feed_shared_visit_context(uuid[]) is
  'Viewer-authorized exact shared-visit attribution for up to 50 readable check-in events; pending invitations are source-owner-only.';


-- Supplemental context for one already-readable shared check-in. It is not a
-- Feed page: the caller must not count these rows as matching its Feed filters.
-- Every returned original has exact owner/accepted provenance and is checked
-- independently. Pending, cancelled, ambiguous and inaccessible members vanish.
-- Existing groups allow at most 20 participants. New comments target the source
-- original when readable, otherwise the first readable canonical original ID.
-- Existing comments and likes always keep their original IDs.
create function public.shared_visit_posts(input_activity_id uuid)
returns table(group_id uuid, comment_activity_id uuid, visit_id uuid, activity jsonb)
language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  with authorized_group as materialized (
    select distinct context.group_id
    from public.feed_shared_visit_context(array[input_activity_id]) context
  ), members as materialized (
    select shared_group.id as group_id, participant.visit_id,
      participant.user_id, participant.status
    from authorized_group
    join public.shared_visit_groups shared_group on shared_group.id = authorized_group.group_id
      and shared_group.cancelled_at is null
    join public.shared_visit_participants participant on participant.group_id = shared_group.id
      and participant.status in ('owner', 'accepted')
    where app.can_read_visit_source(app.current_user_id(), participant.visit_id)
    order by (participant.status = 'owner') desc, participant.user_id
    limit 20
  ), originals as materialized (
    select distinct members.group_id, members.visit_id, members.status, event.id
    from members
    join public.place_visits visit on visit.id = members.visit_id and visit.deleted_at is null
    join public.feed_events event on event.user_place_id = visit.user_place_id
      and event.actor_user_id = members.user_id and event.event_type = 'place_been'
      and (event.visit_id = members.visit_id or (event.visit_id is null
        and visit.backfilled_from_user_place and event.occurred_at = visit.visited_at))
    where event.id = app.canonical_activity_id(event.id)
      and app.feed_shared_visit_source(event.id) = members.visit_id
  ), projected as materialized (
    select originals.*, public.activity_detail(originals.id) as detail,
      app.feed_place_projection((select user_place_id from public.place_visits where id = originals.visit_id),
        originals.visit_id) as visit_place
    from originals
  )
  select projected.group_id,
    first_value(projected.id) over (partition by projected.group_id
      order by (projected.status = 'owner') desc, projected.id) as comment_activity_id,
    projected.visit_id,
    projected.detail || jsonb_build_object(
      'place', projected.visit_place, 'note', projected.visit_place->'note',
      'rating', projected.visit_place->'rating_score',
      'media', coalesce(media.media, '[]'::jsonb))
  from projected
  left join lateral public.activity_media(array[projected.id]) media on media.activity_id = projected.id
  order by (projected.status = 'owner') desc, projected.id
  limit 20
$$;
revoke all on function public.shared_visit_posts(uuid) from public, anon;
grant execute on function public.shared_visit_posts(uuid) to authenticated;
comment on function public.shared_visit_posts(uuid) is
  'At most 20 currently readable owner/accepted original check-ins for one exact shared visit; preserves original discussion IDs.';

commit;
