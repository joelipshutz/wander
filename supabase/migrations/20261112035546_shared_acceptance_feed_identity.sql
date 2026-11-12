begin;
set local lock_timeout = '5s';

-- REC-686: first-save/Wanna acceptance writes a social_save parent, whose
-- trigger emits place_saved before the backfilled visit has its final UUID.
-- The completed receipt is the exact provenance we lacked in REC-636.
-- Acceptance -> final visit/participant -> completed receipt -> original event.
-- Do not change the general social-save trigger or infer a visit from proximity.
-- This private definer is callable only by the receipt trigger/migration owner.
-- Existing RPC authorization, locking, idempotency and return values are intact.
create function app.repair_shared_acceptance_feed_event(input_operation_id uuid)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  receipt public.shared_visit_operations;
  accepted_visit public.place_visits;
  event_ids uuid[];
begin
  select * into receipt from public.shared_visit_operations
    where id = input_operation_id and status = 'completed'
      and operation_type = 'accept' and result->>'status' = 'accepted';
  if receipt.id is null then return; end if;

  select visit.* into accepted_visit
  from public.place_visits visit
  join public.user_places parent on parent.id = visit.user_place_id
  join public.shared_visit_participants participant
    on participant.id = receipt.participant_id
    and participant.user_id = receipt.user_id
    and participant.status = 'accepted' and participant.visit_id = visit.id
    and participant.invitation_generation = receipt.invitation_generation
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
    and shared_group.place_id = parent.place_id and shared_group.cancelled_at is null
  where visit.id::text = receipt.result->>'visit_id'
    and parent.id::text = receipt.result->>'user_place_id'
    and parent.user_id = receipt.user_id and parent.deleted_at is null
    and visit.deleted_at is null and visit.backfilled_from_user_place;
  -- A converted Wanna's backfill inherits the older parent creation time.
  -- The receipt's final visit UUID proves identity; its creation time does not.
  if accepted_visit.id is null then return; end if;

  -- Both timestamps must equal the acceptance transaction, not the user-chosen
  -- visit time. Require one event and one receipt; ambiguity stays untouched.
  select array_agg(event.id) into event_ids
  from public.feed_events event
  join public.user_places parent on parent.id = accepted_visit.user_place_id
  where event.user_place_id = parent.id and event.actor_user_id = receipt.user_id
    and event.place_id = parent.place_id and event.event_type = 'place_saved'
    and event.visit_id is null and event.created_at = receipt.created_at
    and event.occurred_at = receipt.created_at;
  if cardinality(event_ids) is distinct from 1 then return; end if;
  if exists (select 1 from public.shared_visit_operations other
    where other.id <> receipt.id and other.user_id = receipt.user_id
      and other.status = 'completed' and other.created_at = receipt.created_at
      and other.result->>'user_place_id' = receipt.result->>'user_place_id')
    or exists (select 1 from public.feed_events event
      where event.visit_id = accepted_visit.id and event.event_type = 'place_been')
  then return; end if;

  -- Preserve original event identity/time and all engagement. No place, visit,
  -- note, rating, photo or audience is rewritten; cached clients refresh normally.
  update public.feed_events set event_type = 'place_been', visit_id = accepted_visit.id
    where id = event_ids[1] and event_type = 'place_saved' and visit_id is null;
end;
$$;
revoke all on function app.repair_shared_acceptance_feed_event(uuid) from public, anon, authenticated;

create function app.record_shared_acceptance_feed_identity()
returns trigger language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform app.repair_shared_acceptance_feed_event(new.id);
  return new;
end;
$$;
revoke all on function app.record_shared_acceptance_feed_identity() from public, anon, authenticated;

create trigger shared_visit_operations_feed_identity
  after insert or update of status, result on public.shared_visit_operations
  for each row when (new.status = 'completed')
  execute function app.record_shared_acceptance_feed_identity();

-- Existing receipts prove the same relation without guessing from current
-- mutable place ratings or notes. Re-running the helper is a no-op after repair.
do $$
declare operation_id uuid;
begin
  for operation_id in select id from public.shared_visit_operations where status = 'completed'
  loop
    perform app.repair_shared_acceptance_feed_event(operation_id);
  end loop;
end;
$$;

commit;
