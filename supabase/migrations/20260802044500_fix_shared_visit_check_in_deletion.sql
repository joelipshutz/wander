begin;

-- Reuse the established last-ticket reconciliation for soft deletes. Keeping
-- the ticket row avoids conflicting cascades through Shared Visits while all
-- read surfaces already treat deleted_at as the authoritative active filter.
drop trigger if exists place_visits_sync_user_place_after_soft_delete
  on public.place_visits;
create trigger place_visits_sync_user_place_after_soft_delete
  after update of deleted_at on public.place_visits
  for each row
  when (old.deleted_at is null and new.deleted_at is not null)
  execute function app.sync_user_place_after_place_visit_delete();

create or replace function app.delete_own_check_in(input_visit_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  target public.place_visits;
  parent public.user_places;
  transition text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select visit.*
  into target
  from public.place_visits visit
  where visit.id = input_visit_id;

  if target.id is null or target.deleted_at is not null then
    return jsonb_build_object(
      'visit_id', input_visit_id,
      'user_place_id', target.user_place_id,
      'transition', 'removed'
    );
  end if;

  select *
  into parent
  from public.user_places
  where id = target.user_place_id;

  if parent.user_id is distinct from viewer_id then
    raise exception 'not_owner';
  end if;

  update public.notification_events event
  set status = 'skipped',
      skip_reason = 'shared_visit_source_deleted',
      claim_expires_at = null,
      updated_at = now()
  where event.notification_type = 'shared_visit'
    and event.status in ('pending', 'claimed')
    and exists (
      select 1
      from public.shared_visit_groups shared_group
      join public.shared_visit_participants participant
        on participant.group_id = shared_group.id
      where shared_group.source_visit_id = target.id
        and event.data->>'participant_id' = participant.id::text
    );

  update public.place_visits
  set deleted_at = coalesce(deleted_at, now()),
      updated_at = now()
  where id = target.id;

  select *
  into parent
  from public.user_places
  where id = target.user_place_id;

  transition := case
    when parent.deleted_at is not null then 'removed'
    when parent.status = 'wanna_go' then 'wanna_go'
    else 'been'
  end;

  return jsonb_build_object(
    'visit_id', target.id,
    'user_place_id', target.user_place_id,
    'transition', transition
  );
end;
$$;

revoke all on function app.delete_own_check_in(uuid) from public, anon, authenticated;
grant execute on function app.delete_own_check_in(uuid) to authenticated;

comment on function app.delete_own_check_in(uuid) is
  'Soft-deletes one caller-owned check-in ticket and reconciles its parent without breaking Shared Visit references.';

commit;
