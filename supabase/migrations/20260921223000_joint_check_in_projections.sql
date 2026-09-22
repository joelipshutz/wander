begin;

-- Keyset order across actors and canonical groups. The existing actor index
-- remains useful for per-person activity, but cannot order a mixed feed page.
create index feed_events_joint_feed_cursor_idx on public.feed_events(occurred_at desc,id desc);

alter function app.can_read_activity_event(text, uuid) rename to can_read_legacy_activity_event;
revoke all on function app.can_read_legacy_activity_event(text, uuid) from public, anon, authenticated;

-- A shared audience never broadens the visibility of a person's contribution.
-- All card, media, profile and discussion paths consume this same filtered set.
create function app.readable_joint_check_in_members(input_viewer_id text, input_group_id uuid)
returns table(participant_id uuid, user_id text, visit_id uuid, user_place_id uuid, invited_at timestamptz, is_starter boolean)
language sql stable security definer rows 10 set search_path = pg_catalog, public, app
as $$
  select member.id, member.user_id, visit.id, parent.id, member.invited_at, member.status = 'owner'
  from public.shared_visit_groups shared
  join public.shared_visit_participants member on member.group_id = shared.id
  join public.place_visits visit on visit.id = member.visit_id
  join public.user_places parent on parent.id = visit.user_place_id and parent.user_id = member.user_id
  join public.profiles person on person.id = member.user_id
  join public.place_visits source on source.id = shared.source_visit_id
  join public.user_places source_parent on source_parent.id = source.user_place_id
  join public.profiles starter on starter.id = shared.owner_user_id
  where shared.id = input_group_id and shared.model_version = 2 and shared.cancelled_at is null
    and exists(select 1 from public.profiles viewer where viewer.id = input_viewer_id and viewer.deleted_at is null)
    and source.deleted_at is null and source_parent.deleted_at is null and source_parent.visibility <> 'self'
    and source_parent.status = 'been' and starter.deleted_at is null and not starter.is_private_profile
    and not app.is_blocked(input_viewer_id, starter.id)
    and member.status in ('owner','accepted') and visit.deleted_at is null and parent.deleted_at is null
    and parent.visibility <> 'self' and person.deleted_at is null and not person.is_private_profile
    and not app.is_blocked(input_viewer_id, person.id)
    and app.can_read_user_place(input_viewer_id, person.id, parent.visibility)
$$;

create function app.visible_joint_group_for_visit(input_viewer_id text, input_visit_id uuid)
returns uuid language sql stable security definer set search_path = pg_catalog, public, app
as $$
  select member.group_id from public.shared_visit_participants member
  where member.visit_id = input_visit_id and member.status in ('owner','accepted')
    and exists(select 1 from app.readable_joint_check_in_members(input_viewer_id, member.group_id) visible
      where visible.participant_id = member.id)
  limit 1
$$;

-- Legacy readers cannot misrepresent a canonical event as a solo post. Personal
-- visits remain readable when detached/closed; v2 readers handle active aliases.
create function app.can_read_activity_event(input_viewer_id text, input_activity_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public, app
as $$
  select exists(select 1 from public.feed_events event where event.id = input_activity_id
    and event.shared_visit_group_id is null
    and app.visible_joint_group_for_visit(input_viewer_id, event.visit_id) is null
    and app.can_read_legacy_activity_event(input_viewer_id, event.id))
$$;

create function app.joint_profile_json(input_user_id text, input_viewer_id text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object('id', person.id, 'handle', person.handle, 'display_name', person.display_name,
    'avatar_url', person.avatar_url, 'bio', person.bio, 'home_area', person.home_area,
    'is_private_profile', person.is_private_profile, 'created_at', person.created_at,
    'relationship', case when person.id = input_viewer_id then 'owner'
      when app.is_mutual(input_viewer_id, person.id) then 'mutual'
      when app.follows(input_viewer_id, person.id) then 'follower' else 'non_follower' end)
  from public.profiles person where person.id = input_user_id and person.deleted_at is null
$$;

create function app.joint_check_in_projection(input_viewer_id text, input_group_id uuid)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object('group_id', shared.id, 'model_version', 2,
    'canonical_activity_id', event.id, 'revision', shared.revision, 'occurred_at', event.occurred_at,
    'viewer_can_manage', shared.owner_user_id = input_viewer_id,
    'contributions', jsonb_agg(jsonb_build_object(
      'participant_id', visible.participant_id, 'visit_id', visible.visit_id, 'user_place_id', visible.user_place_id,
      'person', app.joint_profile_json(visible.user_id, input_viewer_id),
      'note', visit.note, 'rating', visit.rating_score, 'media', '[]'::jsonb, 'updated_at', visit.updated_at,
      'viewer_can_edit', visible.user_id = input_viewer_id)
      order by visible.is_starter desc, visible.invited_at, visible.participant_id))
  from public.shared_visit_groups shared
  join public.feed_events event on event.shared_visit_group_id = shared.id
  join lateral app.readable_joint_check_in_members(input_viewer_id, shared.id) visible on true
  join public.place_visits visit on visit.id = visible.visit_id
  where shared.id = input_group_id
  group by shared.id, event.id
$$;

-- Conversation identity is permanent once a detached personal discussion is used.
-- active member + unused personal discussion -> canonical read alias
-- detached/closed OR ever used personal thread -> personal event forever
-- writes must match the displayed resolved target; they never follow an alias.
create function app.resolve_activity_v2(input_viewer_id text, input_activity_id uuid)
returns uuid language plpgsql stable security definer set search_path = pg_catalog, public, app
as $$
declare event public.feed_events; group_id uuid;
begin
  select * into event from public.feed_events where id = input_activity_id;
  if event.id is null then return null; end if;
  if event.shared_visit_group_id is not null then
    if exists(select 1 from app.readable_joint_check_in_members(input_viewer_id, event.shared_visit_group_id)) then
      return event.id;
    end if;
    return null;
  end if;
  if not app.can_read_legacy_activity_event(input_viewer_id, event.id) then return null; end if;
  if event.standalone_engagement_started_at is null then
    group_id := app.visible_joint_group_for_visit(input_viewer_id, event.visit_id);
    if group_id is not null then
      return (select id from public.feed_events where shared_visit_group_id = group_id);
    end if;
  end if;
  return event.id;
end;
$$;

create function public.activity_detail_v2(input_activity_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, app
as $$
declare
 viewer_id text := app.current_user_id(); resolved_id uuid; event public.feed_events;
 first_member jsonb; joint jsonb; place_json jsonb; actor_json jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into event from public.feed_events where id = input_activity_id;
  if event.id is null then raise exception 'activity_not_visible'; end if;
  if event.shared_visit_group_id is null then
    resolved_id := app.resolve_activity_v2(viewer_id, input_activity_id);
    if resolved_id is null then raise exception 'activity_not_visible'; end if;
    if resolved_id <> input_activity_id then return public.activity_detail_v2(resolved_id); end if;
    -- Use the original projection directly: legacy access rejects active personal
    -- events even when their permanently pinned personal discussion is valid.
    place_json := app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id);
    actor_json := app.joint_profile_json(event.actor_user_id, viewer_id);
  else
    -- The projection is itself the authoritative readability check. Deriving
    -- its first member from the same result avoids evaluating all ten members
    -- three times for every card while keeping one privacy predicate.
    joint := app.joint_check_in_projection(viewer_id, event.shared_visit_group_id);
    if joint is null then raise exception 'activity_not_visible'; end if;
    first_member := joint->'contributions'->0;
    place_json := app.feed_wanna_place_projection((first_member->>'user_place_id')::uuid, (first_member->>'visit_id')::uuid, event.id);
    actor_json := first_member->'person';
  end if;
  return jsonb_build_object('id', event.id, 'event_type', event.event_type, 'occurred_at', event.occurred_at,
    'actor', actor_json, 'place', place_json, 'list', app.feed_list_projection(event.list_id),
    'note', case when joint is not null then null when event.event_type = 'list_created'
      then app.feed_list_projection(event.list_id)->>'description' else place_json->>'note' end,
    'rating', case when joint is null and event.event_type in ('place_been','list_item_added')
      then (place_json->>'rating_score')::double precision else null end,
    'media', '[]'::jsonb, 'joint_check_in', joint);
end;
$$;

create function public.joint_check_in_contexts(input_visit_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(input_visit_ids),0) > 50 then raise exception 'too_many_visit_ids'; end if;
  return (with mappings as (
    select requested.id, app.visible_joint_group_for_visit(viewer_id, requested.id) as group_id
    from (select distinct unnest(coalesce(input_visit_ids,'{}'::uuid[])) as id) requested
  ) select jsonb_build_object('mappings', coalesce((select jsonb_agg(jsonb_build_object('visit_id', id, 'group_id', group_id)) from mappings),'[]'::jsonb),
    'groups', coalesce((select jsonb_agg(app.joint_check_in_projection(viewer_id, group_id))
      from (select distinct group_id from mappings where group_id is not null) unique_groups),'[]'::jsonb)));
end;
$$;

create function public.followed_feed_v2(input_include_featured boolean default false,
  input_before text default null, input_limit integer default 25)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, app
as $$
declare viewer_id text := app.current_user_id(); page_limit integer := greatest(1, least(coalesce(input_limit,25),50));
 cursor_date timestamptz; cursor_id uuid; result jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_before is not null and position('|' in input_before) > 1 then
    begin
      cursor_date := split_part(input_before,'|',1)::timestamptz;
      cursor_id := split_part(input_before,'|',2)::uuid;
    exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'invalid_activity_cursor';
    end;
  end if;
  -- Canonical eligibility and member suppression occur before the keyset LIMIT.
  with followed_people as materialized (
    select followed_user_id as user_id from public.follows where follower_user_id=viewer_id
  ), candidate_groups as materialized (
    select distinct member.group_id from public.shared_visit_participants member
    join followed_people person on person.user_id=member.user_id
    join public.shared_visit_groups shared on shared.id=member.group_id
    where member.status in ('owner','accepted') and shared.model_version=2 and shared.cancelled_at is null
  ), visible_members as materialized (
    select candidate.group_id,visible.* from candidate_groups candidate
    cross join lateral app.readable_joint_check_in_members(viewer_id,candidate.group_id) visible
  ), followed_groups as materialized (
    select distinct member.group_id from visible_members member
    join followed_people person on person.user_id=member.user_id
  ), candidates as (
    select event.id, event.occurred_at from public.feed_events event
    where (cursor_date is null or (event.occurred_at,event.id) < (cursor_date,cursor_id)) and (
      (event.shared_visit_group_id in (select group_id from followed_groups))
      or (event.shared_visit_group_id is null and event.actor_user_id in (select user_id from followed_people)
        and app.can_read_legacy_activity_event(viewer_id,event.id)
        and not exists(select 1 from visible_members member where member.visit_id=event.visit_id)))
    order by event.occurred_at desc,event.id desc limit page_limit+1
  ), page as (select * from candidates order by occurred_at desc,id desc limit page_limit)
  select jsonb_build_object('activity',coalesce((select jsonb_agg(public.activity_detail_v2(id) order by occurred_at desc,id desc) from page),'[]'::jsonb),
    'featured_places','[]'::jsonb, 'fetched_at',now(),
    'next_cursor',case when (select count(*) from candidates)>page_limit
      then (select occurred_at::text||'|'||id::text from page order by occurred_at,id limit 1) else null end)
  into result;
  if input_include_featured then
    result := jsonb_set(result,'{featured_places}',coalesce(app.followed_feed(input_before,input_limit)->'featured_places','[]'::jsonb));
  end if;
  return result;
end;
$$;

create function public.activity_media_v2(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb) language plpgsql stable security definer set search_path = pg_catalog, public, app
as $$
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(input_activity_ids),0)>100 then raise exception 'too_many_activity_ids'; end if;
  return query
  with resolved as (
    select distinct app.resolve_activity_v2(app.current_user_id(),id) as id
    from unnest(coalesce(input_activity_ids,'{}'::uuid[])) id
  ), visits as (
    select event.id as activity_id,event.visit_id,null::uuid as participant_id,event.actor_user_id as user_id
    from resolved join public.feed_events event on event.id = resolved.id where event.shared_visit_group_id is null
    union all
    select event.id,visible.visit_id,visible.participant_id,visible.user_id
    from resolved join public.feed_events event on event.id = resolved.id
    join lateral app.readable_joint_check_in_members(app.current_user_id(),event.shared_visit_group_id) visible on true
    where event.shared_visit_group_id is not null
  ) select resolved.id,coalesce(jsonb_agg(jsonb_build_object('id', photo.id,'url',null,
      'storage_bucket',photo.storage_bucket,'storage_path',photo.storage_path,'accessibility_label','Activity photo',
      'participant_id',visits.participant_id,'visit_id',visits.visit_id,'owner_user_id',visits.user_id)
      order by visits.participant_id,photo.sort_order,photo.created_at,photo.id) filter(where photo.id is not null),'[]'::jsonb)
    from resolved left join visits on visits.activity_id=resolved.id
    left join public.visit_photos photo on photo.visit_id=visits.visit_id and photo.upload_state='uploaded' and photo.deleted_at is null
    where resolved.id is not null group by resolved.id;
end;
$$;

revoke all on function app.readable_joint_check_in_members(text,uuid) from public,anon,authenticated;
revoke all on function app.visible_joint_group_for_visit(text,uuid) from public,anon,authenticated;
revoke all on function app.can_read_activity_event(text,uuid) from public,anon,authenticated;
revoke all on function app.joint_profile_json(text,text) from public,anon,authenticated;
revoke all on function app.joint_check_in_projection(text,uuid) from public,anon,authenticated;
revoke all on function app.resolve_activity_v2(text,uuid) from public,anon,authenticated;
revoke all on function public.activity_detail_v2(uuid) from public,anon;
revoke all on function public.joint_check_in_contexts(uuid[]) from public,anon;
revoke all on function public.followed_feed_v2(boolean,text,integer) from public,anon;
revoke all on function public.activity_media_v2(uuid[]) from public,anon;
grant execute on function public.activity_detail_v2(uuid) to authenticated;
grant execute on function public.joint_check_in_contexts(uuid[]) to authenticated;
grant execute on function public.followed_feed_v2(boolean,text,integer) to authenticated;
grant execute on function public.activity_media_v2(uuid[]) to authenticated;
commit;
