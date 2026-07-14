begin;

create or replace function public.list_shared_visit_invitees(input_source_visit_id uuid)
returns table (
  invitee_user_id text,
  participant_status text,
  invitation_generation integer
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.user_id,
    participant.status,
    participant.invitation_generation
  from public.shared_visit_groups shared_group
  join public.place_visits source_visit on source_visit.id = shared_group.source_visit_id
  join public.user_places source_place on source_place.id = source_visit.user_place_id
  join public.shared_visit_participants participant on participant.group_id = shared_group.id
  where shared_group.source_visit_id = input_source_visit_id
    and shared_group.owner_user_id = app.current_user_id()
    and shared_group.cancelled_at is null
    and source_visit.deleted_at is null
    and source_place.deleted_at is null
    and source_place.user_id = app.current_user_id()
    and participant.status in ('pending', 'accepted')
  order by participant.invited_at, participant.user_id
$$;

create or replace function public.set_shared_visit_invitees(
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
  normalized_invitee_ids text[];
  shared_group_id uuid;
  source_is_available boolean;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  select coalesce(array_agg(distinct invitee order by invitee), array[]::text[])
  into normalized_invitee_ids
  from unnest(coalesce(input_invitee_user_ids, array[]::text[])) invitee
  where nullif(btrim(invitee), '') is not null;

  if cardinality(normalized_invitee_ids) > 19 then
    raise exception 'shared_visit_participant_limit';
  end if;

  select exists (
    select 1
    from public.place_visits source_visit
    join public.user_places source_place on source_place.id = source_visit.user_place_id
    join public.profiles owner on owner.id = source_place.user_id
    where source_visit.id = input_source_visit_id
      and source_visit.deleted_at is null
      and source_place.deleted_at is null
      and source_place.user_id = viewer_id
      and source_place.status = 'been'
      and source_place.visibility <> 'self'
      and owner.deleted_at is null
      and not owner.is_private_profile
  ) into source_is_available;

  if not source_is_available then
    raise exception 'shared_visit_source_unavailable';
  end if;

  select shared_group.id
  into shared_group_id
  from public.shared_visit_groups shared_group
  where shared_group.source_visit_id = input_source_visit_id
    and shared_group.owner_user_id = viewer_id
  for update;

  if shared_group_id is not null then
    update public.shared_visit_participants participant
    set status = 'removed',
        invitation_snapshot = null,
        responded_at = coalesce(participant.responded_at, now()),
        cancelled_at = now(),
        updated_at = now()
    where participant.group_id = shared_group_id
      and participant.status in ('pending', 'accepted')
      and not (participant.user_id = any(normalized_invitee_ids));
  end if;

  if cardinality(normalized_invitee_ids) > 0 then
    perform *
    from public.create_shared_visit_invites(
      input_source_visit_id,
      normalized_invitee_ids
    );

    select shared_group.id
    into shared_group_id
    from public.shared_visit_groups shared_group
    where shared_group.source_visit_id = input_source_visit_id
      and shared_group.owner_user_id = viewer_id;
  end if;

  if shared_group_id is null then
    return;
  end if;

  update public.notification_events event
  set status = 'skipped',
      skip_reason = 'shared_visit_removed',
      claim_expires_at = null,
      updated_at = now()
  where event.notification_type = 'shared_visit'
    and event.status in ('pending', 'claimed')
    and exists (
      select 1
      from public.shared_visit_participants participant
      where participant.group_id = shared_group_id
        and participant.status = 'removed'
        and event.data->>'participant_id' = participant.id::text
        and event.data->>'invitation_generation' = participant.invitation_generation::text
    );

  return query
  select
    participant.id,
    participant.user_id,
    participant.status,
    participant.invitation_generation
  from public.shared_visit_participants participant
  where participant.group_id = shared_group_id
    and participant.user_id = any(normalized_invitee_ids)
    and participant.status in ('pending', 'accepted')
  order by participant.invited_at, participant.user_id;
end;
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
    select visit.id
    from public.place_visits visit
    join public.user_places user_place on user_place.id = visit.user_place_id
    where visit.id = any(coalesce(input_visit_ids, array[]::uuid[]))
      and visit.deleted_at is null
      and user_place.deleted_at is null
      and user_place.user_id = app.current_user_id()
    limit 50
  ), resolved_groups as (
    select requested.id as requested_visit_id, shared_group.id as group_id, true as is_source_visit
    from requested_visits requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.id
    where shared_group.cancelled_at is null
    union all
    select requested.id, participant.group_id, false
    from requested_visits requested
    join public.shared_visit_participants participant on participant.visit_id = requested.id
    join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    where participant.status = 'accepted' and shared_group.cancelled_at is null
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
      (resolved.is_source_visit and companion.status in ('pending', 'accepted'))
      or (not resolved.is_source_visit and companion.status in ('owner', 'accepted'))
    )
    and companion.user_id <> app.current_user_id()
    and not app.is_blocked(app.current_user_id(), companion.user_id)
    and profile.deleted_at is null
    and not profile.is_private_profile
    and (
      (resolved.is_source_visit and companion.status = 'pending')
      or companion.status = 'owner'
      or (
        companion.status = 'accepted'
        and companion_visit.deleted_at is null
        and companion_place.deleted_at is null
        and companion_place.visibility <> 'self'
        and app.can_read_user_place(app.current_user_id(), companion.user_id, companion_place.visibility)
      )
    )
  order by resolved.requested_visit_id, profile.display_name, profile.id
$$;

revoke all on function public.list_shared_visit_invitees(uuid) from public, anon;
revoke all on function public.set_shared_visit_invitees(uuid, text[]) from public, anon;
revoke all on function public.get_shared_visit_companion_context(uuid[]) from public, anon;
grant execute on function public.list_shared_visit_invitees(uuid) to authenticated;
grant execute on function public.set_shared_visit_invitees(uuid, text[]) to authenticated;
grant execute on function public.get_shared_visit_companion_context(uuid[]) to authenticated;

comment on function public.list_shared_visit_invitees(uuid) is
  'Returns the exact active invitee selection for a caller-owned source visit.';
comment on function public.set_shared_visit_invitees(uuid, text[]) is
  'Atomically reconciles a caller-owned source visit to the exact invitee set while preserving removed recipients independent visits.';
comment on function public.get_shared_visit_companion_context(uuid[]) is
  'Returns pending and accepted companions for caller-owned source visits and readable accepted companions for recipient visits.';

do $metadata$
declare
  procedure_name text;
  procedure_oid regprocedure;
  is_security_definer boolean;
  procedure_config text[];
begin
  foreach procedure_name in array array[
    'public.list_shared_visit_invitees(uuid)',
    'public.set_shared_visit_invitees(uuid,text[])',
    'public.get_shared_visit_companion_context(uuid[])'
  ] loop
    procedure_oid := procedure_name::regprocedure;
    select procedure.prosecdef, procedure.proconfig
    into is_security_definer, procedure_config
    from pg_proc procedure
    where procedure.oid = procedure_oid;

    if is_security_definer is distinct from true
       or not ('search_path=public, app' = any(coalesce(procedure_config, array[]::text[]))) then
      raise exception '% security metadata is invalid', procedure_name;
    end if;
    if not has_function_privilege('authenticated', procedure_oid, 'execute')
       or has_function_privilege('anon', procedure_oid, 'execute') then
      raise exception '% execute grants are invalid', procedure_name;
    end if;
  end loop;
end
$metadata$;

commit;
