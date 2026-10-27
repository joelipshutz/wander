begin;

-- REC-636: additive attribution for already-readable check-in events. Prior
-- companion contracts: 20260714013000, 20260714024500, 20260714043000,
-- 20260714214500 and 20260923222333. Their viewer/visibility rules remain
-- authoritative; this endpoint adds exact group identity and explicit status.
-- It never creates, accepts, changes or combines stored visits/discussions.
create function public.feed_shared_visit_context(input_activity_ids uuid[])
returns table(activity_id uuid, visit_id uuid, group_id uuid, companions jsonb)
language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  with requested as (
    select event.id, event.visit_id, event.actor_user_id
    from public.feed_events event
    where event.id = any((coalesce(input_activity_ids, array[]::uuid[]))[1:50])
      and event.event_type = 'place_been'
      and event.visit_id is not null
      and app.current_user_id() is not null
      and app.can_read_activity_event(app.current_user_id(), event.id)
      and app.can_read_visit_source(app.current_user_id(), event.visit_id)
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

commit;
