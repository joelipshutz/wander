begin;

-- Version-aware invitation reads retain the existing v1 DTO contract.

create or replace function public.list_shared_visit_inbox_v2(
  input_before timestamptz default null,
  input_limit integer default 50
)
returns table (
  model_version integer,
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    shared_group.model_version::integer,
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    case when shared_group.model_version = 2 then
      app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
        || jsonb_build_object('note',null,'rating_score',null,'attribute_answers','[]'::jsonb,'tags','[]'::jsonb,'photos','[]'::jsonb)
    else app.private_taxonomy_snapshot_projection(participant.invitation_snapshot) end
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.user_id = app.current_user_id()
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
    and (input_before is null or participant.invited_at < input_before)
  order by participant.invited_at desc, participant.id
  limit greatest(1, least(coalesce(input_limit, 50), 50))
$$;

create or replace function public.list_shared_visit_inbox(
  input_before timestamptz default null,
  input_limit integer default 50
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    case when shared_group.model_version = 2 then
      app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
        || jsonb_build_object('note',null,'rating_score',null,'attribute_answers','[]'::jsonb,'tags','[]'::jsonb,'photos','[]'::jsonb)
    else app.private_taxonomy_snapshot_projection(participant.invitation_snapshot) end
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.user_id = app.current_user_id()
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.model_version=1
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
    and (input_before is null or participant.invited_at < input_before)
  order by participant.invited_at desc, participant.id
  limit greatest(1, least(coalesce(input_limit, 50), 50))
$$;

create or replace function public.get_shared_visit_context_v2(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  model_version integer,
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    shared_group.model_version::integer,
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    case when shared_group.model_version = 2 then
      app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
        || jsonb_build_object('note',null,'rating_score',null,'attribute_answers','[]'::jsonb,'tags','[]'::jsonb,'photos','[]'::jsonb)
    else app.private_taxonomy_snapshot_projection(participant.invitation_snapshot) end
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
    and participant.invitation_generation = input_generation
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
$$;

create or replace function public.get_shared_visit_context(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    case when shared_group.model_version = 2 then
      app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
        || jsonb_build_object('note',null,'rating_score',null,'attribute_answers','[]'::jsonb,'tags','[]'::jsonb,'photos','[]'::jsonb)
    else app.private_taxonomy_snapshot_projection(participant.invitation_snapshot) end
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
    and participant.invitation_generation = input_generation
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.model_version=1
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
$$;

create or replace function public.resolve_shared_visit_destination_v2(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  model_version integer,
  participant_id uuid,
  requested_generation integer,
  current_generation integer,
  route_status text,
  place_id uuid,
  accepted_visit_id uuid,
  source_visit_id uuid
)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    shared_group.model_version::integer,
    participant.id,
    input_generation,
    participant.invitation_generation,
    case
      when participant.invitation_generation <> input_generation then 'stale'
      when participant.status = 'pending' and participant.invitation_snapshot is not null
        and shared_group.cancelled_at is null then 'pending'
      when participant.status = 'accepted' and participant.visit_id is not null then 'accepted'
      else participant.status
    end,
    shared_group.place_id,
    participant.visit_id,
    shared_group.source_visit_id
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
$$;

create or replace function public.resolve_shared_visit_destination(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  participant_id uuid,
  requested_generation integer,
  current_generation integer,
  route_status text,
  place_id uuid,
  accepted_visit_id uuid,
  source_visit_id uuid
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    input_generation,
    participant.invitation_generation,
    case
      when participant.invitation_generation <> input_generation then 'stale'
      when participant.status = 'pending' and participant.invitation_snapshot is not null
        and shared_group.cancelled_at is null then 'pending'
      when participant.status = 'accepted' and participant.visit_id is not null then 'accepted'
      else participant.status
    end,
    shared_group.place_id,
    participant.visit_id,
    shared_group.source_visit_id
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  where shared_group.model_version=1
    and participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
$$;

create or replace function public.get_shared_visit_companion_context(input_visit_ids uuid[])
returns table (
  visit_id uuid,
  companion_user_id text,
  companion_handle text,
  companion_display_name text,
  companion_avatar_url text
)
language sql
stable
security definer
set search_path = public, app
as $$
  with requested_visits as (
    select
      visit.id,
      user_place.user_id as visit_owner_user_id
    from public.place_visits visit
    join public.user_places user_place on user_place.id = visit.user_place_id
    where visit.id = any(coalesce(input_visit_ids, array[]::uuid[]))
      and visit.deleted_at is null
      and user_place.deleted_at is null
      and app.can_read_user_place(
        app.current_user_id(),
        user_place.user_id,
        user_place.visibility
      )
    limit 50
  ), resolved_groups as (
    select
      requested.id as requested_visit_id,
      requested.visit_owner_user_id,
      shared_group.id as group_id,
      true as is_source_visit
    from requested_visits requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.id
    where shared_group.model_version=1 and shared_group.cancelled_at is null
    union all
    select
      requested.id,
      requested.visit_owner_user_id,
      participant.group_id,
      false
    from requested_visits requested
    join public.shared_visit_participants participant on participant.visit_id = requested.id
    join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    where participant.status = 'accepted'
      and shared_group.model_version=1 and shared_group.cancelled_at is null
  )
  select
    resolved.requested_visit_id,
    companion.user_id,
    profile.handle,
    profile.display_name,
    profile.avatar_url
  from resolved_groups resolved
  join public.shared_visit_participants companion on companion.group_id = resolved.group_id
  join public.profiles profile on profile.id = companion.user_id
  left join public.place_visits companion_visit on companion_visit.id = companion.visit_id
  left join public.user_places companion_place on companion_place.id = companion_visit.user_place_id
  where (
      (resolved.is_source_visit and companion.status = 'accepted')
      or (
        resolved.is_source_visit
        and resolved.visit_owner_user_id = app.current_user_id()
        and companion.status = 'pending'
      )
      or (not resolved.is_source_visit and companion.status in ('owner', 'accepted'))
    )
    and companion.user_id <> resolved.visit_owner_user_id
    and not app.is_blocked(app.current_user_id(), companion.user_id)
    and profile.deleted_at is null
    and (
      companion.user_id = app.current_user_id()
      or not profile.is_private_profile
    )
    and (
      (
        resolved.is_source_visit
        and resolved.visit_owner_user_id = app.current_user_id()
        and companion.status = 'pending'
      )
      or companion.status = 'owner'
      or (
        companion.status = 'accepted'
        and (
          companion.user_id = app.current_user_id()
          or (
            companion_visit.deleted_at is null
            and companion_place.deleted_at is null
            and companion_place.visibility <> 'self'
            and app.can_read_user_place(
              app.current_user_id(),
              companion.user_id,
              companion_place.visibility
            )
          )
        )
      )
    )
  order by
    resolved.requested_visit_id,
    (companion.user_id = app.current_user_id()) desc,
    profile.display_name,
    profile.id
$$;

revoke all on function public.list_shared_visit_inbox_v2(timestamptz,integer) from public,anon;
grant execute on function public.list_shared_visit_inbox_v2(timestamptz,integer) to authenticated;

revoke all on function public.get_shared_visit_context_v2(uuid,integer) from public,anon;
grant execute on function public.get_shared_visit_context_v2(uuid,integer) to authenticated;

revoke all on function public.resolve_shared_visit_destination_v2(uuid,integer) from public,anon;
grant execute on function public.resolve_shared_visit_destination_v2(uuid,integer) to authenticated;

create or replace function app.queue_activity_engagement_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  activity public.feed_events;
  actor public.profiles;
  actor_id text;
  action_id text;
  notification_type text;
  notification_title text;
  subject_name text;
  recipient_id text;
  notification_body text;
begin
  if tg_table_name = 'activity_likes' then
    actor_id := new.user_id;
    action_id := new.user_id;
    notification_type := 'activity_liked';
    notification_title := 'New like';
  elsif tg_table_name = 'activity_comments' then
    actor_id := new.author_user_id;
    action_id := new.id::text;
    notification_type := 'activity_commented';
    notification_title := 'New comment';
  else
    raise exception 'unsupported_activity_engagement_table';
  end if;

  select * into activity
  from public.feed_events
  where id = new.activity_id;

  select * into actor
  from public.profiles
  where id = actor_id
    and deleted_at is null;

  if activity.id is null or actor.id is null then
    return new;
  end if;

  select coalesce(place.canonical_name, list.name, 'a post')
  into subject_name
  from (select 1) singleton
  left join public.places place on place.id = activity.place_id
  left join public.place_lists list on list.id = activity.list_id;

  for recipient_id in
    select participant.user_id
    from (
      select activity.actor_user_id as user_id
      union
      select member.user_id from public.shared_visit_participants member
        where member.group_id=activity.shared_visit_group_id and member.status in ('owner','accepted')
      union
      select activity_like.user_id
      from public.activity_likes activity_like
      where activity_like.activity_id = activity.id
      union
      select comment.author_user_id
      from public.activity_comments comment
      where comment.activity_id = activity.id
    ) participant
    where participant.user_id <> actor_id
      and app.resolve_activity_v2(participant.user_id, activity.id)=activity.id
      and not app.is_blocked(participant.user_id,actor_id)
  loop
    notification_body := case
      when activity.shared_visit_group_id is not null then 'There is new activity on a joint check-in.'
      when notification_type = 'activity_liked' and recipient_id = activity.actor_user_id
        then actor.display_name || ' liked your post about ' || subject_name || '.'
      when notification_type = 'activity_liked'
        then actor.display_name || ' liked a post you engaged with about ' || subject_name || '.'
      when recipient_id = activity.actor_user_id
        then actor.display_name || ' commented on your post about ' || subject_name || '.'
      else actor.display_name || ' also commented on a post about ' || subject_name || '.'
    end;

    perform app.queue_notification_event(
      input_recipient_user_id := recipient_id,
      input_actor_user_id := actor_id,
      input_notification_type := notification_type,
      input_title := notification_title,
      input_body := notification_body,
      input_deeplink_url := 'https://getrec.me/activities/' || activity.id,
      input_data := jsonb_strip_nulls(jsonb_build_object(
        'activity_id', activity.id,
        'model_version', case when activity.shared_visit_group_id is not null then 2 else null end,
        'place_id', activity.place_id,
        'list_id', activity.list_id,
        'event_type', activity.event_type,
        'actor_user_id', actor_id
      )),
      input_dedupe_key := notification_type || ':' || activity.id || ':' || action_id || ':' || recipient_id
    );
  end loop;

  return new;
end;
$$;


create function app.joint_notification_is_current(input_event public.notification_events)
returns boolean language sql stable security definer set search_path=pg_catalog,public,app
as $$
 select case when input_event.data->>'model_version' is distinct from '2' then true
   when input_event.notification_type='shared_visit' then exists(
     select 1 from public.shared_visit_participants member join public.shared_visit_groups shared on shared.id=member.group_id
     join public.profiles owner on owner.id=shared.owner_user_id
     where member.id::text=input_event.data->>'participant_id'
       and member.invitation_generation::text=input_event.data->>'invitation_generation'
       and member.user_id=input_event.recipient_user_id and member.status='pending'
       and shared.cancelled_at is null and owner.deleted_at is null and not owner.is_private_profile
       and not app.is_blocked(input_event.recipient_user_id,shared.owner_user_id))
   else exists(select 1 from public.feed_events event
     where event.id::text=input_event.data->>'activity_id'
       and app.resolve_activity_v2(input_event.recipient_user_id,event.id)=event.id
       and not app.is_blocked(input_event.recipient_user_id,input_event.actor_user_id)) end
$$;
revoke all on function app.joint_notification_is_current(public.notification_events) from public,anon,authenticated;

-- Keep the current delivery governor intact, adding v2 authorization before it
-- claims any event. Preferences, expiry, token settlement and limits still apply.
alter function app.claim_pending_push_notifications(integer) rename to claim_pending_push_notifications_before_joint;
revoke all on function app.claim_pending_push_notifications_before_joint(integer) from public,anon,authenticated,service_role;
create function app.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,app
as $$
begin
 update public.notification_events event set status='skipped',skip_reason='joint_check_in_access_changed',
   claim_token=null,claim_expires_at=null,updated_at=now()
   where event.status in ('pending','claimed') and event.data->>'model_version'='2'
     and not app.joint_notification_is_current(event);
 return app.claim_pending_push_notifications_before_joint(input_limit);
end;
$$;
revoke all on function app.claim_pending_push_notifications(integer) from public,anon,authenticated;
grant execute on function app.claim_pending_push_notifications(integer) to service_role;


alter function public.set_activity_like(uuid,boolean) set schema app;
alter function app.set_activity_like(uuid,boolean) rename to set_activity_like_legacy;
revoke all on function app.set_activity_like_legacy(uuid,boolean) from public,anon,authenticated;
create function public.set_activity_like(input_activity_id uuid,input_is_liked boolean) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,app
as $$
begin
 if exists(select 1 from public.feed_events event where event.id=input_activity_id
   and (event.shared_visit_group_id is not null or app.visible_joint_group_for_visit(app.current_user_id(),event.visit_id) is not null)) then
   raise exception 'joint_check_in_upgrade_required';
 end if;
 return app.set_activity_like_legacy(input_activity_id,input_is_liked);
end;
$$;
revoke all on function public.set_activity_like(uuid,boolean) from public,anon;
grant execute on function public.set_activity_like(uuid,boolean) to authenticated;


alter function public.add_activity_comment(uuid,text) set schema app;
alter function app.add_activity_comment(uuid,text) rename to add_activity_comment_legacy;
revoke all on function app.add_activity_comment_legacy(uuid,text) from public,anon,authenticated;
create function public.add_activity_comment(input_activity_id uuid,input_body text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public,app
as $$
begin
 if exists(select 1 from public.feed_events event where event.id=input_activity_id
   and (event.shared_visit_group_id is not null or app.visible_joint_group_for_visit(app.current_user_id(),event.visit_id) is not null)) then
   raise exception 'joint_check_in_upgrade_required';
 end if;
 return app.add_activity_comment_legacy(input_activity_id,input_body);
end;
$$;
revoke all on function public.add_activity_comment(uuid,text) from public,anon;
grant execute on function public.add_activity_comment(uuid,text) to authenticated;


commit;
