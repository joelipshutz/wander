begin;

-- Older privacy/block/delete paths remain valid. Reconcile v2 membership at the
-- storage boundary so those paths cannot leave live aliases to private visits.
create function app.reconcile_joint_check_in_lifecycle()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
declare target_id uuid; affected_user text; affected_parent uuid;
begin
  if tg_table_name = 'shared_visit_groups' then
    perform app.close_joint_check_in(new.id, coalesce(new.closed_reason, 'source_unavailable'));
    return new;
  end if;
  if tg_table_name = 'shared_visit_participants' then
    if exists(select 1 from public.shared_visit_groups where id = new.group_id and model_version = 2) then
      if new.status not in ('owner', 'accepted') and new.visit_id is not null then
        new.retained_visit_id := coalesce(new.visit_id, new.retained_visit_id);
        new.visit_id := null;
      end if;
      if new.status = 'cancelled' and old.status <> 'cancelled' then
        update public.shared_visit_groups set revision = revision + 1
          where id = new.group_id and model_version = 2 and cancelled_at is null;
      end if;
    end if;
    return new;
  end if;
  if tg_table_name = 'place_visits' then
    if tg_op = 'UPDATE' and tg_when = 'BEFORE' then
      if (new.visited_at is distinct from old.visited_at or new.user_place_id is distinct from old.user_place_id)
        and exists(select 1 from public.shared_visit_participants member
          join public.shared_visit_groups shared on shared.id = member.group_id
          where member.visit_id = old.id and member.status in ('owner','accepted')
            and shared.model_version = 2 and shared.cancelled_at is null) then
        raise exception 'joint_check_in_detach_before_changing_occasion';
      end if;
      return new;
    end if;
    for target_id in select shared.id from public.shared_visit_groups shared
      join public.shared_visit_participants member on member.group_id = shared.id
      where shared.model_version = 2 and shared.cancelled_at is null and member.visit_id = old.id
      order by shared.id for update of shared
    loop
      if exists(select 1 from public.shared_visit_groups where id = target_id and source_visit_id = old.id) then
        perform app.close_joint_check_in(target_id, 'source_deleted');
      else
        update public.shared_visit_participants set status = 'removed', retained_visit_id = visit_id,
          visit_id = null, cancelled_at = now(), invitation_snapshot = null
          where group_id = target_id and visit_id = old.id;
        update public.shared_visit_groups set revision = revision + 1 where id = target_id;
      end if;
    end loop;
    return coalesce(new, old);
  end if;
  if tg_table_name = 'user_places' then
    affected_user := new.user_id;
    affected_parent := new.id;
    if new.place_id is distinct from old.place_id and exists(
      select 1 from public.place_visits visit join public.shared_visit_participants member on member.visit_id = visit.id
      join public.shared_visit_groups shared on shared.id = member.group_id
      where visit.user_place_id = new.id and shared.model_version = 2 and shared.cancelled_at is null
        and member.status in ('owner','accepted')) then
      raise exception 'joint_check_in_detach_before_changing_occasion';
    end if;
    if new.deleted_at is null and new.visibility <> 'self' and new.status = 'been' then return new; end if;
  else
    affected_user := new.id;
    if new.deleted_at is null and not new.is_private_profile then return new; end if;
  end if;
  for target_id in select shared.id from public.shared_visit_groups shared
    where shared.model_version = 2 and shared.cancelled_at is null and exists(
      select 1 from public.shared_visit_participants member
      left join public.place_visits visit on visit.id = member.visit_id
      where member.group_id = shared.id and member.user_id = affected_user
        and member.status in ('owner','pending','accepted')
        and (affected_parent is null or visit.user_place_id = affected_parent))
    order by shared.id for update
  loop
    if exists(select 1 from public.shared_visit_groups where id = target_id and owner_user_id = affected_user) then
      perform app.close_joint_check_in(target_id, 'source_private_or_deleted');
    else
      update public.shared_visit_participants set status = 'removed', retained_visit_id = coalesce(visit_id, retained_visit_id),
        visit_id = null, cancelled_at = now(), invitation_snapshot = null
        where group_id = target_id and user_id = affected_user;
      update public.shared_visit_groups set revision = revision + 1 where id = target_id;
    end if;
  end loop;
  return new;
end;
$$;
revoke all on function app.reconcile_joint_check_in_lifecycle() from public, anon, authenticated;
create trigger joint_group_closed after update of cancelled_at on public.shared_visit_groups
  for each row when (new.model_version = 2 and old.cancelled_at is null and new.cancelled_at is not null)
  execute function app.reconcile_joint_check_in_lifecycle();
create trigger joint_participant_detached before update on public.shared_visit_participants
  for each row execute function app.reconcile_joint_check_in_lifecycle();
create trigger place_visits_00_joint_occasion before update of visited_at, user_place_id on public.place_visits
  for each row execute function app.reconcile_joint_check_in_lifecycle();
create trigger place_visits_00_joint_deleted after update of deleted_at on public.place_visits
  for each row when (old.deleted_at is null and new.deleted_at is not null)
  execute function app.reconcile_joint_check_in_lifecycle();
create trigger place_visits_00_joint_hard_deleted before delete on public.place_visits
  for each row execute function app.reconcile_joint_check_in_lifecycle();
create trigger user_places_00_joint_lifecycle after update of visibility, status, deleted_at, place_id on public.user_places
  for each row execute function app.reconcile_joint_check_in_lifecycle();
create trigger profiles_00_joint_lifecycle after update of is_private_profile, deleted_at on public.profiles
  for each row execute function app.reconcile_joint_check_in_lifecycle();

-- Preserve the deployed v1 implementation byte-for-byte behind private names.
-- Old clients must fail before the old acceptance ledger can return a v2 result.
alter function public.create_shared_visit_invites(uuid, text[]) set schema app;
alter function app.create_shared_visit_invites(uuid, text[]) rename to create_legacy_shared_visit_invites;
revoke all on function app.create_legacy_shared_visit_invites(uuid, text[]) from public, anon, authenticated;
alter function public.set_shared_visit_invitees(uuid, text[]) set schema app;
alter function app.set_shared_visit_invitees(uuid, text[]) rename to set_legacy_shared_visit_invitees;
revoke all on function app.set_legacy_shared_visit_invitees(uuid, text[]) from public, anon, authenticated;
alter function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) set schema app;
alter function app.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) rename to accept_legacy_shared_visit;
revoke all on function app.accept_legacy_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) from public, anon, authenticated;
alter function public.decline_shared_visit(uuid, integer) set schema app;
alter function app.decline_shared_visit(uuid, integer) rename to decline_legacy_shared_visit;
revoke all on function app.decline_legacy_shared_visit(uuid, integer) from public, anon, authenticated;

create function public.create_shared_visit_invites(input_source_visit_id uuid, input_invitee_user_ids text[])
returns table(participant_id uuid, invitee_user_id text, participant_status text, invitation_generation integer)
language plpgsql security definer set search_path = public, app
as $$
begin
  if exists(select 1 from public.shared_visit_groups where source_visit_id = input_source_visit_id and model_version = 2) then
    raise exception 'joint_check_in_upgrade_required';
  end if;
  return query select * from app.create_legacy_shared_visit_invites(input_source_visit_id, input_invitee_user_ids);
end;
$$;
create function public.set_shared_visit_invitees(input_source_visit_id uuid, input_invitee_user_ids text[])
returns table(participant_id uuid, invitee_user_id text, participant_status text, invitation_generation integer)
language plpgsql security definer set search_path = public, app
as $$
begin
  if exists(select 1 from public.shared_visit_groups where source_visit_id = input_source_visit_id and model_version = 2) then
    raise exception 'joint_check_in_upgrade_required';
  end if;
  return query select * from app.set_legacy_shared_visit_invitees(input_source_visit_id, input_invitee_user_ids);
end;
$$;
create function public.accept_shared_visit(input_participant_id uuid, input_generation integer, input_snapshot_revision integer,
  input_operation_id uuid, input_user_place_id uuid, input_visit_id uuid, input_user_place jsonb, input_visit jsonb,
  input_attributes jsonb default '[]'::jsonb, input_selected_photo_ids uuid[] default array[]::uuid[])
returns jsonb language plpgsql security definer set search_path = public, app
as $$
begin
  if exists(select 1 from public.shared_visit_participants member join public.shared_visit_groups shared on shared.id = member.group_id
    where member.id = input_participant_id and shared.model_version = 2) then raise exception 'joint_check_in_upgrade_required'; end if;
  return app.accept_legacy_shared_visit(input_participant_id, input_generation, input_snapshot_revision,
    input_operation_id, input_user_place_id, input_visit_id, input_user_place, input_visit, input_attributes, input_selected_photo_ids);
end;
$$;
create function public.decline_shared_visit(input_participant_id uuid, input_generation integer)
returns boolean language plpgsql security definer set search_path = public, app
as $$
begin
  if exists(select 1 from public.shared_visit_participants member join public.shared_visit_groups shared on shared.id = member.group_id
    where member.id = input_participant_id and shared.model_version = 2) then raise exception 'joint_check_in_upgrade_required'; end if;
  return app.decline_legacy_shared_visit(input_participant_id, input_generation);
end;
$$;

create function public.decline_joint_check_in(input_participant_id uuid, input_generation integer)
returns boolean language plpgsql security definer set search_path = pg_catalog, public, app
as $$
declare target public.shared_visit_groups; member public.shared_visit_participants;
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  select * into member from public.shared_visit_participants where id = input_participant_id and user_id = app.current_user_id();
  if member.id is null then raise exception 'joint_check_in_invitation_unavailable'; end if;
  target := app.lock_active_joint_check_in(member.group_id);
  select * into member from public.shared_visit_participants where id = input_participant_id for update;
  if member.invitation_generation is distinct from input_generation then raise exception 'stale_joint_check_in_invitation'; end if;
  if member.status = 'declined' then return true; end if;
  if member.status <> 'pending' then raise exception 'joint_check_in_invitation_unavailable'; end if;
  update public.shared_visit_participants set status = 'declined', invitation_snapshot = null,
    responded_at = now(), updated_at = now() where id = member.id;
  update public.shared_visit_groups set revision = revision + 1 where id = target.id;
  update public.notification_events set status = 'skipped', skip_reason = 'joint_check_in_declined', claim_expires_at = null, updated_at = now()
    where notification_type = 'shared_visit' and status in ('pending','claimed') and data->>'participant_id' = member.id::text;
  return true;
end;
$$;

revoke all on function public.create_shared_visit_invites(uuid, text[]) from public, anon;
revoke all on function public.set_shared_visit_invitees(uuid, text[]) from public, anon;
revoke all on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) from public, anon;
revoke all on function public.decline_shared_visit(uuid, integer) from public, anon;
revoke all on function public.decline_joint_check_in(uuid, integer) from public, anon;
grant execute on function public.create_shared_visit_invites(uuid, text[]) to authenticated;
grant execute on function public.set_shared_visit_invitees(uuid, text[]) to authenticated;
grant execute on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) to authenticated;
grant execute on function public.decline_shared_visit(uuid, integer) to authenticated;
grant execute on function public.decline_joint_check_in(uuid, integer) to authenticated;
commit;
