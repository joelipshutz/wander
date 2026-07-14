begin;

create or replace function app.cancel_shared_visits_after_block()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  with cancelled_participants as (
    update public.shared_visit_participants participant
    set status = 'cancelled', invitation_snapshot = null,
        cancelled_at = coalesce(participant.cancelled_at, now()), updated_at = now()
    from public.shared_visit_groups shared_group
    where participant.group_id = shared_group.id
      and participant.status in ('pending', 'accepted')
      and (
        (shared_group.owner_user_id = new.blocker_user_id and participant.user_id = new.blocked_user_id)
        or
        (shared_group.owner_user_id = new.blocked_user_id and participant.user_id = new.blocker_user_id)
      )
    returning participant.id
  )
  update public.notification_events event
  set status = 'skipped', skip_reason = 'blocked', claim_expires_at = null, updated_at = now()
  where event.notification_type = 'shared_visit'
    and event.status in ('pending', 'claimed')
    and event.data->>'participant_id' in (
      select cancelled.id::text from cancelled_participants cancelled
    );

  return new;
end;
$$;

drop trigger if exists blocks_cancel_shared_visits on public.blocks;
create trigger blocks_cancel_shared_visits
  after insert on public.blocks
  for each row execute function app.cancel_shared_visits_after_block();

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
    select requested.id as requested_visit_id, shared_group.id as group_id
    from requested_visits requested
    join public.shared_visit_groups shared_group on shared_group.source_visit_id = requested.id
    where shared_group.cancelled_at is null
    union all
    select requested.id, participant.group_id
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
  where companion.status in ('owner', 'accepted')
    and companion.user_id <> app.current_user_id()
    and not app.is_blocked(app.current_user_id(), companion.user_id)
    and profile.deleted_at is null
    and not profile.is_private_profile
    and (
      companion.status = 'owner'
      or (
        companion_visit.deleted_at is null
        and companion_place.deleted_at is null
        and companion_place.visibility <> 'self'
        and app.can_read_user_place(app.current_user_id(), companion.user_id, companion_place.visibility)
      )
    )
  order by resolved.requested_visit_id, profile.display_name, profile.id
$$;

revoke all on function app.cancel_shared_visits_after_block() from public, anon, authenticated;
revoke all on function public.get_shared_visit_companion_context(uuid[]) from public, anon;
grant execute on function public.get_shared_visit_companion_context(uuid[]) to authenticated;

comment on function app.cancel_shared_visits_after_block() is
  'Erases owner-recipient shared context and skips unsent shared-visit pushes when either account hard-blocks the other.';
comment on function public.get_shared_visit_companion_context(uuid[]) is
  'Returns readable companions for caller-owned visits while excluding private or blocked profiles.';

do $$
declare
  cleanup_security_definer boolean;
  cleanup_config text[];
  companion_security_definer boolean;
  companion_config text[];
begin
  select procedure.prosecdef, procedure.proconfig
  into cleanup_security_definer, cleanup_config
  from pg_proc procedure
  where procedure.oid = 'app.cancel_shared_visits_after_block()'::regprocedure;

  if cleanup_security_definer is distinct from true
     or not ('search_path=public, app' = any(coalesce(cleanup_config, array[]::text[]))) then
    raise exception 'cancel_shared_visits_after_block security metadata is invalid';
  end if;
  if has_function_privilege('authenticated', 'app.cancel_shared_visits_after_block()', 'execute')
     or has_function_privilege('anon', 'app.cancel_shared_visits_after_block()', 'execute') then
    raise exception 'cancel_shared_visits_after_block execute grants are too broad';
  end if;
  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.blocks'::regclass
      and trigger_row.tgname = 'blocks_cancel_shared_visits'
      and not trigger_row.tgisinternal
  ) then
    raise exception 'blocks_cancel_shared_visits trigger is missing';
  end if;

  select procedure.prosecdef, procedure.proconfig
  into companion_security_definer, companion_config
  from pg_proc procedure
  where procedure.oid = 'public.get_shared_visit_companion_context(uuid[])'::regprocedure;

  if companion_security_definer is distinct from true
     or not ('search_path=public, app' = any(coalesce(companion_config, array[]::text[]))) then
    raise exception 'get_shared_visit_companion_context security metadata is invalid';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.get_shared_visit_companion_context(uuid[])',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.get_shared_visit_companion_context(uuid[])',
    'execute'
  ) then
    raise exception 'get_shared_visit_companion_context execute grants are invalid';
  end if;
end;
$$;

commit;
