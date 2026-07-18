begin;

create or replace function public.create_shared_visit_invites(
  input_source_visit_id uuid,
  input_invitee_user_ids text[]
)
returns table (
  participant_id uuid,
  invitee_user_id text,
  participant_status text,
  invitation_generation integer
)
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  source_row record;
  shared_group public.shared_visit_groups;
  invitee_id text;
  participant_row public.shared_visit_participants;
  prior_status text;
  normalized_invitee_ids text[];
  invalid_invitee_ids text[];
  projected_participant_count integer;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  select array_agg(distinct invitee order by invitee)
  into normalized_invitee_ids
  from unnest(coalesce(input_invitee_user_ids, array[]::text[])) invitee
  where nullif(btrim(invitee), '') is not null;

  if coalesce(cardinality(normalized_invitee_ids), 0) = 0 then
    raise exception 'shared_visit_invitees_required';
  end if;
  if cardinality(normalized_invitee_ids) > 19 then
    raise exception 'shared_visit_participant_limit';
  end if;

  select
    source_visit.id as source_visit_id,
    user_place.place_id,
    user_place.visibility,
    place.canonical_name,
    owner.display_name as owner_display_name
  into source_row
  from public.place_visits source_visit
  join public.user_places user_place on user_place.id = source_visit.user_place_id
  join public.places place on place.id = user_place.place_id
  join public.profiles owner on owner.id = user_place.user_id
  where source_visit.id = input_source_visit_id
    and source_visit.deleted_at is null
    and user_place.deleted_at is null
    and user_place.user_id = viewer_id
    and user_place.status = 'been'
    and user_place.visibility <> 'self'
    and owner.deleted_at is null
    and not owner.is_private_profile;

  if source_row.source_visit_id is null then
    raise exception 'shared_visit_source_unavailable';
  end if;

  select array_agg(invitee)
  into invalid_invitee_ids
  from unnest(normalized_invitee_ids) invitee
  where invitee = viewer_id
    or not exists (
      select 1 from public.profiles profile
      where profile.id = invitee
        and profile.deleted_at is null
        and not profile.is_private_profile
    )
    or not app.is_mutual(viewer_id, invitee)
    or app.is_blocked(viewer_id, invitee);

  if coalesce(cardinality(invalid_invitee_ids), 0) > 0 then
    raise exception 'invalid_shared_visit_invitees';
  end if;

  insert into public.shared_visit_groups(
    source_visit_id, place_id, owner_user_id, cancelled_at
  ) values (
    source_row.source_visit_id,
    source_row.place_id,
    viewer_id,
    null
  )
  on conflict (source_visit_id) do update set
    cancelled_at = null,
    updated_at = now()
  returning * into shared_group;

  insert into public.shared_visit_participants(
    group_id, user_id, invited_by_user_id, status, snapshot_revision,
    invitation_snapshot, visit_id, responded_at
  ) values (
    shared_group.id, viewer_id, viewer_id, 'owner', 1,
    null, source_row.source_visit_id, now()
  )
  on conflict (group_id, user_id) do update set
    status = 'owner',
    visit_id = excluded.visit_id,
    responded_at = coalesce(public.shared_visit_participants.responded_at, now()),
    cancelled_at = null,
    updated_at = now();

  select count(distinct participant_user_id)
  into projected_participant_count
  from (
    select participant.user_id as participant_user_id
    from public.shared_visit_participants participant
    where participant.group_id = shared_group.id
      and participant.status in ('owner', 'pending', 'accepted')
    union
    select unnest(normalized_invitee_ids)
  ) projected;

  if projected_participant_count > 20 then
    raise exception 'shared_visit_participant_limit';
  end if;

  foreach invitee_id in array normalized_invitee_ids loop
    select participant.status
    into prior_status
    from public.shared_visit_participants participant
    where participant.group_id = shared_group.id
      and participant.user_id = invitee_id
    for update;

    insert into public.shared_visit_participants(
      group_id, user_id, invited_by_user_id, status, invitation_generation,
      snapshot_revision, invitation_snapshot, visit_id, invited_at, responded_at, cancelled_at
    ) values (
      shared_group.id, invitee_id, viewer_id, 'pending', 1,
      1, app.shared_visit_source_snapshot(source_row.source_visit_id), null, now(), null, null
    )
    on conflict (group_id, user_id) do update set
      invited_by_user_id = excluded.invited_by_user_id,
      status = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then 'pending'
        else public.shared_visit_participants.status
      end,
      invitation_generation = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then public.shared_visit_participants.invitation_generation + 1
        else public.shared_visit_participants.invitation_generation
      end,
      snapshot_revision = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then public.shared_visit_participants.snapshot_revision + 1
        else public.shared_visit_participants.snapshot_revision
      end,
      invitation_snapshot = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed')
          then app.shared_visit_source_snapshot(source_row.source_visit_id)
        else public.shared_visit_participants.invitation_snapshot
      end,
      visit_id = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then null
        else public.shared_visit_participants.visit_id
      end,
      invited_at = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then now()
        else public.shared_visit_participants.invited_at
      end,
      responded_at = case
        when public.shared_visit_participants.status in ('declined', 'cancelled', 'expired', 'removed') then null
        else public.shared_visit_participants.responded_at
      end,
      cancelled_at = null,
      updated_at = now()
    returning * into participant_row;

    if prior_status is null or prior_status in ('declined', 'cancelled', 'expired', 'removed') then
      update public.notification_events
      set status = 'skipped',
          skip_reason = 'shared_visit_superseded',
          updated_at = now()
      where recipient_user_id = invitee_id
        and actor_user_id = viewer_id
        and notification_type = 'followed_place_visit'
        and data->>'visit_id' = source_row.source_visit_id::text
        and status = 'pending';

      perform app.queue_notification_event(
        input_recipient_user_id := invitee_id,
        input_actor_user_id := viewer_id,
        input_notification_type := 'shared_visit',
        input_title := 'Shared visit',
        input_body := source_row.owner_display_name || ' saved ' || source_row.canonical_name || ' with you. Add your details from this visit',
        input_deeplink_url := 'recme://shared-visits/' || participant_row.id || '?generation=' || participant_row.invitation_generation,
        input_data := jsonb_build_object(
          'participant_id', participant_row.id,
          'invitation_generation', participant_row.invitation_generation,
          'group_id', shared_group.id,
          'source_visit_id', source_row.source_visit_id,
          'place_id', source_row.place_id,
          'actor_user_id', viewer_id
        ),
        input_dedupe_key := 'shared_visit:' || participant_row.id || ':' || participant_row.invitation_generation
      );
    end if;
  end loop;

  return query
  select participant.id, participant.user_id, participant.status, participant.invitation_generation
  from public.shared_visit_participants participant
  where participant.group_id = shared_group.id
    and participant.user_id = any(normalized_invitee_ids)
  order by participant.invited_at, participant.user_id;
end;
$$;

update public.notification_events
set body = regexp_replace(
      body,
      'Add your version of the visit\.$',
      'Add your details from this visit'
    ),
    updated_at = now()
where notification_type = 'shared_visit'
  and status in ('pending', 'claimed')
  and body like '%Add your version of the visit.';

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
    where shared_group.cancelled_at is null
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
      and shared_group.cancelled_at is null
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

revoke all on function public.create_shared_visit_invites(uuid, text[]) from public, anon;
revoke all on function public.get_shared_visit_companion_context(uuid[]) from public, anon;
grant execute on function public.create_shared_visit_invites(uuid, text[]) to authenticated;
grant execute on function public.get_shared_visit_companion_context(uuid[]) to authenticated;

comment on function public.create_shared_visit_invites(uuid, text[]) is
  'Creates idempotent mutual-friend invitations for the authenticated owner of a visible Been visit.';
comment on function public.get_shared_visit_companion_context(uuid[]) is
  'Returns authorized shared-visit companions for readable visit cards, including the viewer when someone else owns the card.';

do $metadata$
declare
  invite_oid regprocedure := 'public.create_shared_visit_invites(uuid,text[])'::regprocedure;
  companion_oid regprocedure := 'public.get_shared_visit_companion_context(uuid[])'::regprocedure;
  invite_security_definer boolean;
  invite_config text[];
  invite_volatility "char";
  companion_security_definer boolean;
  companion_config text[];
  companion_volatility "char";
begin
  select procedure.prosecdef, procedure.proconfig, procedure.provolatile
  into invite_security_definer, invite_config, invite_volatility
  from pg_proc procedure
  where procedure.oid = invite_oid;

  if invite_security_definer is distinct from true
     or invite_volatility is distinct from 'v'
     or not ('search_path=public, app' = any(coalesce(invite_config, array[]::text[]))) then
    raise exception 'create_shared_visit_invites metadata is invalid';
  end if;
  if not has_function_privilege('authenticated', invite_oid, 'execute')
     or has_function_privilege('anon', invite_oid, 'execute') then
    raise exception 'create_shared_visit_invites execute grants are invalid';
  end if;

  select procedure.prosecdef, procedure.proconfig, procedure.provolatile
  into companion_security_definer, companion_config, companion_volatility
  from pg_proc procedure
  where procedure.oid = companion_oid;

  if companion_security_definer is distinct from true
     or companion_volatility is distinct from 's'
     or not ('search_path=public, app' = any(coalesce(companion_config, array[]::text[]))) then
    raise exception 'get_shared_visit_companion_context metadata is invalid';
  end if;
  if not has_function_privilege('authenticated', companion_oid, 'execute')
     or has_function_privilege('anon', companion_oid, 'execute') then
    raise exception 'get_shared_visit_companion_context execute grants are invalid';
  end if;
end
$metadata$;

commit;
