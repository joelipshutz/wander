begin;

-- Receipts and all effects commit together. The request lock only serializes
-- retries of the same caller/request; authorization never depends on a lock.
create function app.lock_joint_check_in_request(input_request_id uuid)
returns text language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null or not exists (
    select 1 from public.profiles where id = viewer_id and deleted_at is null
  ) then raise exception 'not_authenticated'; end if;
  if input_request_id is null then raise exception 'invalid_joint_check_in_request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'astir:joint-request:' || viewer_id || ':' || input_request_id::text, 0));
  return viewer_id;
end;
$$;

create function app.joint_check_in_payload_hash(input_payload jsonb)
returns text language sql immutable security invoker
set search_path = pg_catalog
as $$ select encode(sha256(convert_to(input_payload::text, 'UTF8')), 'hex') $$;

create function app.lock_active_joint_check_in(input_group_id uuid)
returns public.shared_visit_groups language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare target public.shared_visit_groups;
begin
  select * into target from public.shared_visit_groups where id = input_group_id for update;
  if target.id is null or target.model_version <> 2 then
    raise exception 'joint_check_in_unavailable';
  end if;
  if target.cancelled_at is not null or not exists (
    select 1 from public.place_visits visit
    join public.user_places parent on parent.id = visit.user_place_id
    join public.profiles owner on owner.id = target.owner_user_id
    where visit.id = target.source_visit_id and visit.deleted_at is null
      and parent.deleted_at is null and parent.status = 'been' and parent.visibility <> 'self'
      and owner.deleted_at is null and not owner.is_private_profile
  ) then raise exception 'joint_check_in_closed'; end if;
  return target;
end;
$$;

create function app.joint_check_in_mutation_result(input_group_id uuid, input_visit_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'group_id', shared.id, 'model_version', 2, 'group_revision', shared.revision,
    'canonical_activity_id', case when member.status in ('owner', 'accepted') then canonical.id else null end, 'visit_id', visit.id,
    'user_place_id', parent.id, 'place_id', parent.place_id,
    'visited_at', visit.visited_at, 'note', visit.note, 'rating_score', visit.rating_score,
    'tags', to_jsonb(visit.tags), 'attribute_answers', visit.attribute_answers,
    'backfilled_from_user_place', visit.backfilled_from_user_place,
    'user_place', to_jsonb(parent), 'user_place_attributes', app.user_place_attribute_answers(parent.id),
    'participant_id', member.id, 'status', member.status, 'photo_copies', '[]'::jsonb
  )
  from public.shared_visit_groups shared
  join public.feed_events canonical on canonical.shared_visit_group_id = shared.id
  join public.place_visits visit on visit.id = input_visit_id
  join public.user_places parent on parent.id = visit.user_place_id
  join public.shared_visit_participants member
    on member.group_id = shared.id and member.user_id = parent.user_id
  where shared.id = input_group_id and parent.user_id = app.current_user_id()
$$;

-- Caller holds the group lock. This is the shared exact-set implementation for
-- initial publication and later owner management; pending seats count as occupied.
create function app.reconcile_joint_check_in_invitees(input_group_id uuid, input_invitee_ids text[])
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  target public.shared_visit_groups;
  normalized text[];
  invitee text;
  prior public.shared_visit_participants;
  member public.shared_visit_participants;
  snapshot jsonb;
begin
  select * into target from public.shared_visit_groups where id = input_group_id;
  if target.model_version is distinct from 2 or target.cancelled_at is not null
    or target.owner_user_id is distinct from app.current_user_id() then
    raise exception 'joint_check_in_not_owner';
  end if;
  select coalesce(array_agg(distinct btrim(value) order by btrim(value)), array[]::text[])
  into normalized from unnest(coalesce(input_invitee_ids, array[]::text[])) value
  where nullif(btrim(value), '') is not null;
  if cardinality(normalized) > 9 then raise exception 'joint_check_in_capacity'; end if;
  if exists (
    select 1 from unnest(normalized) person where person = target.owner_user_id
      or not app.is_mutual(target.owner_user_id, person)
      or app.is_blocked(target.owner_user_id, person)
      or not exists (select 1 from public.profiles where id = person and deleted_at is null and not is_private_profile)
  ) then raise exception 'invalid_joint_check_in_invitees'; end if;

  perform 1 from public.shared_visit_participants where group_id = target.id order by id for update;
  update public.shared_visit_participants
  set status = 'removed', retained_visit_id = coalesce(visit_id, retained_visit_id), visit_id = null,
      invitation_snapshot = null, cancelled_at = now(), responded_at = coalesce(responded_at, now())
  where group_id = target.id and status in ('pending', 'accepted') and not (user_id = any(normalized));

  snapshot := app.shared_visit_source_snapshot(target.source_visit_id)
    || jsonb_build_object('note', null, 'rating_score', null, 'attribute_answers', '[]'::jsonb,
                         'tags', '[]'::jsonb, 'photos', '[]'::jsonb);
  foreach invitee in array normalized loop
    select * into prior from public.shared_visit_participants
    where group_id = target.id and user_id = invitee;
    if prior.id is not null and prior.status in ('pending', 'accepted') then continue; end if;
    insert into public.shared_visit_participants(group_id, user_id, invited_by_user_id,
      status, invitation_snapshot)
    values(target.id, invitee, target.owner_user_id, 'pending', snapshot)
    on conflict (group_id, user_id) do update
      set status = 'pending', invitation_generation = public.shared_visit_participants.invitation_generation + 1,
          snapshot_revision = public.shared_visit_participants.snapshot_revision + 1,
          invitation_snapshot = excluded.invitation_snapshot,
          retained_visit_id = coalesce(public.shared_visit_participants.visit_id, public.shared_visit_participants.retained_visit_id),
          visit_id = null, consent_version = null, invited_at = now(), responded_at = null, cancelled_at = null
    returning * into member;
    update public.notification_events event
    set status = 'skipped', skip_reason = 'shared_visit_superseded', updated_at = now()
    where event.recipient_user_id = invitee and event.actor_user_id = target.owner_user_id
      and event.notification_type = 'followed_place_visit' and event.status = 'pending'
      and event.data->>'visit_id' = target.source_visit_id::text;
    perform app.queue_notification_event(
      input_recipient_user_id := invitee, input_actor_user_id := target.owner_user_id,
      input_notification_type := 'shared_visit', input_title := 'Check in together',
      input_body := 'You have an invitation to a joint check-in.',
      input_deeplink_url := 'recme://shared-visits/' || member.id || '?generation=' || member.invitation_generation,
      input_data := jsonb_build_object('participant_id', member.id,
        'invitation_generation', member.invitation_generation, 'group_id', target.id,
        'source_visit_id', target.source_visit_id, 'place_id', target.place_id,
        'actor_user_id', target.owner_user_id, 'model_version', 2),
      input_dedupe_key := 'shared_visit:' || member.id || ':' || member.invitation_generation
    );
  end loop;

  update public.notification_events event
  set status = 'skipped', skip_reason = 'joint_check_in_invitation_removed', claim_expires_at = null, updated_at = now()
  where event.notification_type = 'shared_visit' and event.status in ('pending', 'claimed')
    and exists (select 1 from public.shared_visit_participants removed_member
      where removed_member.group_id = target.id and removed_member.status = 'removed'
        and event.data->>'participant_id' = removed_member.id::text);
end;
$$;

create function public.save_joint_check_in(
  input_place jsonb, input_user_place jsonb, input_attributes jsonb, input_visit jsonb,
  input_historical_want jsonb, input_invitee_user_ids text[], input_operation_id uuid,
  input_consent_version integer
)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.lock_joint_check_in_request(input_operation_id);
  fingerprint text;
  prior public.joint_check_in_operations;
  target public.shared_visit_groups;
  saved jsonb;
  outcome jsonb;
  visit public.place_visits;
  parent public.user_places;
  enabled boolean;
begin
  if input_consent_version is distinct from 1 then raise exception 'joint_check_in_consent_required'; end if;
  fingerprint := app.joint_check_in_payload_hash(jsonb_build_object(
    'place', input_place, 'parent', input_user_place, 'attributes', input_attributes,
    'visit', input_visit, 'historical_want', input_historical_want,
    'invitees', input_invitee_user_ids, 'consent', input_consent_version));
  select * into prior from public.joint_check_in_operations
  where actor_user_id = viewer_id and request_id = input_operation_id;
  if prior.request_id is not null then
    target := app.lock_active_joint_check_in(prior.group_id);
    if target.owner_user_id <> viewer_id then raise exception 'joint_check_in_not_owner'; end if;
    if prior.operation_kind <> 'create' or prior.payload_hash <> fingerprint then
      raise exception 'joint_check_in_request_conflict';
    end if;
    return app.joint_check_in_mutation_result(target.id, target.source_visit_id);
  end if;

  select flag.enabled into enabled from public.feature_flags flag
  where flag.key = 'joint_check_ins_v2' and (flag.user_id = viewer_id or flag.user_id is null)
  order by (flag.user_id is not null) desc limit 1;
  if enabled is distinct from true then raise exception 'joint_check_in_creation_unavailable'; end if;
  if (select is_private_profile from public.profiles where id = viewer_id) then
    raise exception 'joint_check_in_private_profile';
  end if;
  if coalesce(cardinality(input_invitee_user_ids), 0) < 1
    or coalesce(cardinality(input_invitee_user_ids), 0) > 9 then
    raise exception 'joint_check_in_capacity';
  end if;
  if exists(select 1 from public.place_visits where id = (input_visit->>'id')::uuid) then
    raise exception 'joint_check_in_already_published';
  end if;
  saved := app.save_own_check_in(input_place, input_user_place, input_attributes, input_visit, input_historical_want);
  select * into visit from public.place_visits where id = (saved->>'visit_id')::uuid;
  select * into parent from public.user_places where id = visit.user_place_id;
  if parent.user_id is distinct from viewer_id or parent.visibility = 'self' then
    raise exception 'joint_check_in_private_place';
  end if;
  insert into public.shared_visit_groups(source_visit_id, place_id, owner_user_id, model_version)
  values(visit.id, parent.place_id, viewer_id, 2) returning * into target;
  insert into public.feed_events(actor_user_id, event_type, user_place_id, place_id, occurred_at, shared_visit_group_id)
  values(viewer_id, 'place_been', parent.id, parent.place_id, visit.visited_at, target.id);
  insert into public.shared_visit_participants(group_id, user_id, invited_by_user_id, status,
    visit_id, retained_visit_id, consent_version, responded_at)
  values(target.id, viewer_id, viewer_id, 'owner', visit.id, visit.id, input_consent_version, now());
  perform app.reconcile_joint_check_in_invitees(target.id, input_invitee_user_ids);
  outcome := app.joint_check_in_mutation_result(target.id, visit.id);
  insert into public.joint_check_in_operations(actor_user_id, request_id, group_id, operation_kind,
    payload_hash, committed_result)
  values(viewer_id, input_operation_id, target.id, 'create', fingerprint, outcome);
  return outcome;
end;
$$;

revoke all on function app.lock_joint_check_in_request(uuid) from public, anon, authenticated;
revoke all on function app.joint_check_in_payload_hash(jsonb) from public, anon, authenticated;
revoke all on function app.lock_active_joint_check_in(uuid) from public, anon, authenticated;
revoke all on function app.joint_check_in_mutation_result(uuid, uuid) from public, anon, authenticated;
revoke all on function app.reconcile_joint_check_in_invitees(uuid, text[]) from public, anon, authenticated;
revoke all on function public.save_joint_check_in(jsonb, jsonb, jsonb, jsonb, jsonb, text[], uuid, integer) from public, anon;
grant execute on function public.save_joint_check_in(jsonb, jsonb, jsonb, jsonb, jsonb, text[], uuid, integer) to authenticated;

-- Parent compatibility triggers synthesize a visit before the explicit one
-- exists. Suppress only that synthetic insert during the atomic v2 append;
-- deleting it afterward would run last-visit reconciliation and replace labels.
create function app.skip_joint_check_in_backfill()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
begin
  if new.backfilled_from_user_place
    and current_setting('app.joint_check_in_append', true) = 'on' then return null; end if;
  return new;
end;
$$;
revoke all on function app.skip_joint_check_in_backfill() from public, anon, authenticated;
create trigger place_visits_skip_joint_backfill before insert on public.place_visits
  for each row execute function app.skip_joint_check_in_backfill();

-- Preserve saved-place metadata when appending a contribution. The existing
-- save_own_check_in path intentionally edits the parent; accepting an invitation
-- must not do that. The group lock precedes the same parent advisory/row locks
-- used by ordinary saves. No source note, rating, attributes or photos are copied.
create function app.save_joint_check_in_contribution(
  input_group_id uuid, input_participant_id uuid, input_parent_id uuid,
  input_visit_id uuid, input_parent jsonb, input_visit jsonb, input_private boolean
)
returns uuid language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  target public.shared_visit_groups;
  member public.shared_visit_participants;
  parent public.user_places;
  saved public.place_visits;
  latest public.place_visits;
  venue public.places;
  occasion timestamptz;
  visibility text;
  score numeric;
  prior_explicit text := current_setting('app.explicit_check_in', true);
  prior_append text := current_setting('app.joint_check_in_append', true);
begin
  select * into target from public.shared_visit_groups where id = input_group_id;
  select * into member from public.shared_visit_participants
    where id = input_participant_id and group_id = target.id and user_id = viewer_id;
  if member.id is null then raise exception 'joint_check_in_invitation_unavailable'; end if;
  if input_parent_id is null or input_visit_id is null
    or jsonb_typeof(input_parent) is distinct from 'object'
    or jsonb_typeof(input_visit) is distinct from 'object'
    or jsonb_typeof(coalesce(input_visit->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_joint_check_in_contribution';
  end if;
  select * into venue from public.places where id = target.place_id;
  perform pg_advisory_xact_lock(hashtextextended('recme:place-provider:' || viewer_id || ':'
    || venue.source_provider || ':' || venue.source_provider_place_id, 0));
  perform pg_advisory_xact_lock(hashtextextended('recme:user-place:' || viewer_id || ':' || target.place_id::text, 0));
  select * into parent from public.user_places
    where user_id = viewer_id and place_id = target.place_id for update;
  if parent.deleted_at is not null then raise exception 'joint_check_in_explicit_restore_required'; end if;

  visibility := coalesce(parent.visibility, nullif(input_parent->>'visibility', ''), 'followers');
  if input_private then
    if parent.id is not null and visibility <> 'self' then
      raise exception 'joint_check_in_private_save_requires_self';
    end if;
    visibility := 'self';
  elsif visibility = 'self' then raise exception 'joint_check_in_private_place';
  end if;
  if visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_joint_check_in_visibility';
  end if;

  select visited_at into occasion from public.place_visits where id = target.source_visit_id;
  if member.retained_visit_id is not null then
    select * into saved from public.place_visits where id = member.retained_visit_id for update;
    if saved.id is not null and saved.deleted_at is null and saved.user_place_id = parent.id
      and saved.visited_at = occasion then
      -- A surviving contribution is reused without replacing detached edits.
      return saved.id;
    elsif coalesce((input_visit->>'starts_fresh_visit')::boolean, false) is not true then
      raise exception 'joint_check_in_explicit_restore_required';
    end if;
    -- Only an explicit fresh-save action may replace missing/moved linkage.
    -- It uses a new UUID and never resurrects or rewrites the retained visit.
  end if;
  if exists(select 1 from public.place_visits where id = input_visit_id) then
    raise exception 'joint_check_in_visit_id_conflict';
  end if;
  select visited_at into occasion from public.place_visits where id = target.source_visit_id;
  if nullif(input_visit->>'visited_at', '') is not null
    and (input_visit->>'visited_at')::timestamptz is distinct from occasion then
    raise exception 'joint_check_in_occasion_changed';
  end if;
  score := nullif(input_visit->>'rating_score', '')::numeric;
  if score is not null and (score < 1 or score > 5 or score * 2 <> trunc(score * 2)) then
    raise exception 'invalid_rating_score';
  end if;
  perform set_config('app.explicit_check_in', 'on', true);
  perform set_config('app.joint_check_in_append', 'on', true);
  if parent.id is null then
    if exists(select 1 from public.user_places where id = input_parent_id) then
      raise exception 'joint_check_in_parent_id_conflict';
    end if;
    insert into public.user_places(id, user_id, place_id, status, visibility, source_type)
    values(input_parent_id, viewer_id, target.place_id, 'been', visibility, 'manual')
    returning * into parent;
  elsif parent.status = 'wanna_go' then
    update public.user_places set
      historical_want_note = parent.note,
      historical_want_attribute_answers = app.user_place_attribute_answers(parent.id),
      historical_want_tags = app.visit_tags_from_attribute_answers(app.user_place_attribute_answers(parent.id)),
      historical_wanted_at = coalesce(parent.saved_at, parent.created_at),
      status = 'been', planned_date = null, updated_at = now()
    where id = parent.id returning * into parent;
  end if;
  insert into public.place_visits(id, user_place_id, visited_at, note, rating_score, attribute_answers, backfilled_from_user_place)
  values(input_visit_id, parent.id, occasion, nullif(input_visit->>'note', ''), score,
    coalesce(input_visit->'attribute_answers', '[]'::jsonb), false) returning * into saved;
  select * into latest from public.place_visits where user_place_id = parent.id and deleted_at is null
    order by visited_at desc, created_at desc, id desc limit 1;
  update public.user_places set status = 'been', visited_at = latest.visited_at,
    note = latest.note, rating_score = latest.rating_score, updated_at = now()
    where id = parent.id;
  perform set_config('app.explicit_check_in', coalesce(prior_explicit, ''), true);
  perform set_config('app.joint_check_in_append', coalesce(prior_append, ''), true);
  return saved.id;
end;
$$;

-- Both terminal choices share validation/receipts, but only acceptance creates
-- membership. Private saving never returns a conversation alias.
create function app.respond_to_joint_check_in(
  input_participant_id uuid, input_generation integer, input_snapshot_revision integer,
  input_operation_id uuid, input_consent_version integer, input_user_place_id uuid,
  input_visit_id uuid, input_user_place jsonb, input_visit jsonb, input_private boolean
)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.lock_joint_check_in_request(input_operation_id);
  target public.shared_visit_groups;
  member public.shared_visit_participants;
  prior public.joint_check_in_operations;
  fingerprint text;
  kind text := case when input_private then 'save_privately' else 'accept' end;
  saved_id uuid;
  outcome jsonb;
begin
  select * into member from public.shared_visit_participants
    where id = input_participant_id and user_id = viewer_id;
  if member.id is null then raise exception 'joint_check_in_invitation_unavailable'; end if;
  target := app.lock_active_joint_check_in(member.group_id);
  select * into member from public.shared_visit_participants where id = member.id for update;
  if member.invitation_generation is distinct from input_generation
    or member.snapshot_revision is distinct from input_snapshot_revision then
    raise exception 'stale_joint_check_in_invitation';
  end if;
  if app.is_blocked(viewer_id, target.owner_user_id) then
    raise exception 'joint_check_in_invitation_unavailable';
  end if;
  if not input_private then
    if input_consent_version is distinct from 1 then raise exception 'joint_check_in_consent_required'; end if;
    if (select is_private_profile from public.profiles where id = viewer_id) then
      raise exception 'joint_check_in_private_profile';
    end if;
  end if;
  fingerprint := app.joint_check_in_payload_hash(jsonb_build_object(
    'kind', kind, 'participant', input_participant_id, 'generation', input_generation,
    'revision', input_snapshot_revision, 'consent', input_consent_version,
    'parent_id', input_user_place_id, 'visit_id', input_visit_id,
    'parent', input_user_place, 'visit', input_visit));
  select * into prior from public.joint_check_in_operations
    where actor_user_id = viewer_id and request_id = input_operation_id;
  if prior.request_id is not null then
    if prior.operation_kind <> kind or prior.payload_hash <> fingerprint then
      raise exception 'joint_check_in_request_conflict';
    end if;
    if member.status <> (case when input_private then 'declined' else 'accepted' end)
      or member.retained_visit_id is distinct from (prior.committed_result->>'visit_id')::uuid then
      raise exception 'joint_check_in_invitation_unavailable';
    end if;
    if not exists(select 1 from public.place_visits owned
      join public.user_places owned_parent on owned_parent.id = owned.user_place_id
      where owned.id = member.retained_visit_id and owned.deleted_at is null
        and owned_parent.deleted_at is null and owned_parent.user_id = viewer_id
        and (input_private or owned_parent.visibility <> 'self')) then
      raise exception 'joint_check_in_contribution_unavailable';
    end if;
    return app.joint_check_in_mutation_result(target.id, member.retained_visit_id);
  end if;
  if member.status <> 'pending' or member.invitation_snapshot is null then
    raise exception 'joint_check_in_invitation_unavailable';
  end if;
  if not input_private and not app.is_mutual(viewer_id, target.owner_user_id) then
    raise exception 'joint_check_in_invitation_unavailable';
  end if;
  saved_id := app.save_joint_check_in_contribution(target.id, member.id, input_user_place_id,
    input_visit_id, input_user_place, input_visit, input_private);
  update public.shared_visit_participants set
    status = case when input_private then 'declined' else 'accepted' end,
    visit_id = case when input_private then null else saved_id end,
    retained_visit_id = saved_id, invitation_snapshot = null,
    consent_version = case when input_private then null else input_consent_version end,
    responded_at = now(), updated_at = now() where id = member.id;
  update public.shared_visit_groups set revision = revision + 1 where id = target.id;
  update public.notification_events set status = 'skipped', skip_reason = 'joint_check_in_responded',
    claim_expires_at = null, updated_at = now()
    where notification_type = 'shared_visit' and status in ('pending', 'claimed')
      and data->>'participant_id' = member.id::text;
  outcome := app.joint_check_in_mutation_result(target.id, saved_id);
  insert into public.joint_check_in_operations(actor_user_id, request_id, group_id,
    operation_kind, participant_id, invitation_generation, payload_hash, committed_result)
  values(viewer_id, input_operation_id, target.id, kind, member.id, input_generation, fingerprint, outcome);
  return outcome;
end;
$$;

create function public.accept_joint_check_in(
  input_participant_id uuid, input_generation integer, input_snapshot_revision integer,
  input_operation_id uuid, input_consent_version integer, input_user_place_id uuid,
  input_visit_id uuid, input_user_place jsonb, input_visit jsonb
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog, public, app
as $$ select app.respond_to_joint_check_in(input_participant_id, input_generation,
  input_snapshot_revision, input_operation_id, input_consent_version, input_user_place_id,
  input_visit_id, input_user_place, input_visit, false) $$;

create function public.save_joint_invitation_privately(
  input_participant_id uuid, input_generation integer, input_snapshot_revision integer,
  input_operation_id uuid, input_user_place_id uuid, input_visit_id uuid,
  input_user_place jsonb, input_visit jsonb
)
returns jsonb language sql volatile security definer
set search_path = pg_catalog, public, app
as $$ select app.respond_to_joint_check_in(input_participant_id, input_generation,
  input_snapshot_revision, input_operation_id, null, input_user_place_id,
  input_visit_id, input_user_place, input_visit, true) $$;

create function public.set_joint_check_in_invitees(input_group_id uuid,
  input_expected_revision bigint, input_invitee_user_ids text[], input_operation_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.lock_joint_check_in_request(input_operation_id);
  target public.shared_visit_groups;
  prior public.joint_check_in_operations;
  fingerprint text;
  outcome jsonb;
begin
  target := app.lock_active_joint_check_in(input_group_id);
  if target.owner_user_id <> viewer_id then raise exception 'joint_check_in_not_owner'; end if;
  fingerprint := app.joint_check_in_payload_hash(jsonb_build_object('group', input_group_id,
    'revision', input_expected_revision, 'invitees', input_invitee_user_ids));
  select * into prior from public.joint_check_in_operations
    where actor_user_id = viewer_id and request_id = input_operation_id;
  if prior.request_id is not null then
    if prior.operation_kind <> 'set_invitees' or prior.payload_hash <> fingerprint then
      raise exception 'joint_check_in_request_conflict';
    end if;
    return app.joint_check_in_mutation_result(target.id, target.source_visit_id);
  end if;
  if target.revision is distinct from input_expected_revision then
    raise exception 'stale_joint_check_in_revision';
  end if;
  perform app.reconcile_joint_check_in_invitees(target.id, input_invitee_user_ids);
  update public.shared_visit_groups set revision = revision + 1 where id = target.id;
  outcome := app.joint_check_in_mutation_result(target.id, target.source_visit_id);
  insert into public.joint_check_in_operations(actor_user_id, request_id, group_id,
    operation_kind, expected_revision, payload_hash, committed_result)
  values(viewer_id, input_operation_id, target.id, 'set_invitees', input_expected_revision, fingerprint, outcome);
  return outcome;
end;
$$;

create function app.close_joint_check_in(input_group_id uuid, input_reason text)
returns void language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
begin
  perform 1 from public.shared_visit_groups where id = input_group_id and model_version = 2 for update;
  if not found then return; end if;
  update public.shared_visit_groups set cancelled_at = now(), closed_reason = input_reason, revision = revision + 1
    where id = input_group_id and model_version = 2 and cancelled_at is null;
  update public.shared_visit_participants set status = 'cancelled',
    retained_visit_id = coalesce(visit_id, retained_visit_id), visit_id = null,
    invitation_snapshot = null, cancelled_at = coalesce(cancelled_at, now()), updated_at = now()
    where group_id = input_group_id and status in ('owner', 'pending', 'accepted');
  update public.notification_events event set status = 'skipped', skip_reason = 'joint_check_in_closed',
    claim_expires_at = null, updated_at = now()
    where event.status in ('pending', 'claimed') and (event.data->>'group_id' = input_group_id::text
      or exists(select 1 from public.feed_events canonical where canonical.shared_visit_group_id = input_group_id
        and event.data->>'activity_id' = canonical.id::text));
end;
$$;

create function public.leave_joint_check_in(input_group_id uuid,
  input_expected_revision bigint, input_operation_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.lock_joint_check_in_request(input_operation_id);
  target public.shared_visit_groups;
  member public.shared_visit_participants;
  prior public.joint_check_in_operations;
  fingerprint text;
  outcome jsonb;
  saved_id uuid;
begin
  select * into target from public.shared_visit_groups where id = input_group_id and model_version = 2 for update;
  select * into member from public.shared_visit_participants
    where group_id = target.id and user_id = viewer_id for update;
  if member.id is null then raise exception 'joint_check_in_unavailable'; end if;
  fingerprint := app.joint_check_in_payload_hash(jsonb_build_object('group', input_group_id, 'revision', input_expected_revision));
  select * into prior from public.joint_check_in_operations where actor_user_id = viewer_id and request_id = input_operation_id;
  if prior.request_id is not null then
    if prior.operation_kind <> 'leave' or prior.payload_hash <> fingerprint then
      raise exception 'joint_check_in_request_conflict';
    end if;
    if member.invitation_generation <> prior.invitation_generation or member.status not in ('removed', 'cancelled') then
      raise exception 'stale_joint_check_in_invitation';
    end if;
    return prior.committed_result;
  end if;
  if target.cancelled_at is not null then raise exception 'joint_check_in_closed'; end if;
  if member.status not in ('owner', 'accepted') then raise exception 'joint_check_in_not_member'; end if;
  if target.revision is distinct from input_expected_revision then raise exception 'stale_joint_check_in_revision'; end if;
  saved_id := member.visit_id;
  if target.owner_user_id = viewer_id then
    perform app.close_joint_check_in(target.id, 'owner_closed');
  else
    update public.shared_visit_participants set status = 'removed', retained_visit_id = visit_id,
      visit_id = null, cancelled_at = now(), invitation_snapshot = null, updated_at = now() where id = member.id;
    update public.shared_visit_groups set revision = revision + 1 where id = target.id;
  end if;
  outcome := jsonb_build_object('group_id', target.id, 'model_version', 2,
    'group_revision', (select revision from public.shared_visit_groups where id = target.id),
    'status', case when target.owner_user_id = viewer_id then 'closed' else 'removed' end,
    'visit_id', saved_id, 'personal_activity_id', (select id from public.feed_events where visit_id = saved_id));
  insert into public.joint_check_in_operations(actor_user_id, request_id, group_id, operation_kind,
    participant_id, invitation_generation, expected_revision, payload_hash, committed_result)
  values(viewer_id, input_operation_id, target.id, 'leave', member.id, member.invitation_generation,
    input_expected_revision, fingerprint, outcome);
  return outcome;
end;
$$;

revoke all on function app.save_joint_check_in_contribution(uuid, uuid, uuid, uuid, jsonb, jsonb, boolean) from public, anon, authenticated;
revoke all on function app.respond_to_joint_check_in(uuid, integer, integer, uuid, integer, uuid, uuid, jsonb, jsonb, boolean) from public, anon, authenticated;
revoke all on function app.close_joint_check_in(uuid, text) from public, anon, authenticated;
revoke all on function public.accept_joint_check_in(uuid, integer, integer, uuid, integer, uuid, uuid, jsonb, jsonb) from public, anon;
revoke all on function public.save_joint_invitation_privately(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb) from public, anon;
revoke all on function public.set_joint_check_in_invitees(uuid, bigint, text[], uuid) from public, anon;
revoke all on function public.leave_joint_check_in(uuid, bigint, uuid) from public, anon;
grant execute on function public.accept_joint_check_in(uuid, integer, integer, uuid, integer, uuid, uuid, jsonb, jsonb) to authenticated;
grant execute on function public.save_joint_invitation_privately(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb) to authenticated;
grant execute on function public.set_joint_check_in_invitees(uuid, bigint, text[], uuid) to authenticated;
grant execute on function public.leave_joint_check_in(uuid, bigint, uuid) to authenticated;


-- A v2 edit carries both an exact server timestamp and a durable request key.
-- Legacy callers still own their visits, but cannot overwrite shared content
-- without first refreshing the joint projection and using this contract.
alter function app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb) rename to save_own_check_in_before_v2;
revoke all on function app.save_own_check_in_before_v2(jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon,authenticated;
create function app.save_own_check_in(input_place jsonb,input_user_place jsonb,input_attributes jsonb default '[]',
 input_visit jsonb default '{}',input_historical_want jsonb default null)
returns jsonb language plpgsql security definer set search_path=public,app as $$
begin
 if exists(select 1 from public.shared_visit_participants member join public.shared_visit_groups shared on shared.id=member.group_id
  where member.visit_id=nullif(input_visit->>'id','')::uuid and member.status in ('owner','accepted')
    and shared.model_version=2 and shared.cancelled_at is null)
  and current_setting('app.joint_edit_visit_id',true) is distinct from input_visit->>'id' then
  raise exception 'joint_check_in_upgrade_required';
 end if;
 return app.save_own_check_in_before_v2(input_place,input_user_place,input_attributes,input_visit,input_historical_want);
end $$;
revoke all on function app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon;
grant execute on function app.save_own_check_in(jsonb,jsonb,jsonb,jsonb,jsonb) to authenticated;

create function app.guard_joint_contribution_edit() returns trigger language plpgsql security definer
set search_path=pg_catalog,public,app as $$
begin
 if (new.note is distinct from old.note or new.rating_score is distinct from old.rating_score
     or new.attribute_answers is distinct from old.attribute_answers)
  and exists(select 1 from public.shared_visit_participants member join public.shared_visit_groups shared on shared.id=member.group_id
    where member.visit_id=old.id and member.status in ('owner','accepted') and shared.model_version=2 and shared.cancelled_at is null)
  and current_setting('app.joint_edit_visit_id',true) is distinct from old.id::text then
  raise exception 'joint_check_in_upgrade_required';
 end if;
 return new;
end $$;
revoke all on function app.guard_joint_contribution_edit() from public,anon,authenticated;
create trigger place_visits_joint_edit before update of note,rating_score,attribute_answers on public.place_visits
 for each row execute function app.guard_joint_contribution_edit();

create function public.edit_joint_check_in(input_group_id uuid,input_expected_updated_at timestamptz,input_operation_id uuid,
 input_place jsonb,input_user_place jsonb,input_attributes jsonb,input_visit jsonb,input_historical_want jsonb)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,app as $$
declare viewer_id text; target public.shared_visit_groups; member public.shared_visit_participants;
 visit public.place_visits; latest public.place_visits; parent public.user_places;
 receipt public.joint_check_in_operations; fingerprint text; result jsonb;
 prior_edit text:=current_setting('app.joint_edit_visit_id',true);
begin
 viewer_id:=app.lock_joint_check_in_request(input_operation_id);
 target:=app.lock_active_joint_check_in(input_group_id);
 select * into member from public.shared_visit_participants where group_id=target.id and user_id=viewer_id
   and status in ('owner','accepted') for update;
 if member.id is null or member.visit_id is distinct from nullif(input_visit->>'id','')::uuid then
   raise exception 'joint_check_in_invitation_unavailable';
 end if;
 fingerprint:=app.joint_check_in_payload_hash(jsonb_build_object('group',input_group_id,'expected',input_expected_updated_at,
   'place',input_place,'parent',input_user_place,'attributes',input_attributes,'visit',input_visit,'history',input_historical_want));
 select * into receipt from public.joint_check_in_operations where actor_user_id=viewer_id and request_id=input_operation_id;
 if receipt.request_id is not null then
   if receipt.operation_kind<>'edit' or receipt.payload_hash<>fingerprint then raise exception 'joint_check_in_request_conflict'; end if;
   return app.joint_check_in_mutation_result(target.id,member.visit_id);
 end if;
 select p.* into parent from public.user_places p join public.place_visits v on v.user_place_id=p.id
   where v.id=member.visit_id and p.user_id=viewer_id and p.deleted_at is null for update of p;
 select * into visit from public.place_visits where id=member.visit_id and deleted_at is null for update;
 if parent.id is null or visit.id is null then raise exception 'joint_check_in_contribution_unavailable'; end if;
 if input_expected_updated_at is null or visit.updated_at is distinct from input_expected_updated_at then
   raise exception 'joint_check_in_edit_conflict';
 end if;
 if (input_visit->>'visited_at')::timestamptz is distinct from visit.visited_at
   or nullif(input_user_place->>'id','')::uuid is distinct from parent.id then
   raise exception 'joint_check_in_detach_before_changing_occasion';
 end if;
 perform set_config('app.joint_edit_visit_id',visit.id::text,true);
 perform app.save_own_check_in(input_place,input_user_place,input_attributes,input_visit,input_historical_want);
 -- An edit to an older visit must not move the personal place summary backwards.
 select * into latest from public.place_visits where user_place_id=parent.id and deleted_at is null
   order by visited_at desc,created_at desc,id desc limit 1;
 update public.user_places set note=latest.note,rating_score=latest.rating_score,visited_at=latest.visited_at
   where id=parent.id;
 perform set_config('app.joint_edit_visit_id',coalesce(prior_edit,''),true);
 result:=app.joint_check_in_mutation_result(target.id,visit.id);
 insert into public.joint_check_in_operations(actor_user_id,request_id,group_id,operation_kind,participant_id,payload_hash,committed_result)
 values(viewer_id,input_operation_id,target.id,'edit',member.id,fingerprint,jsonb_build_object('visit_id',visit.id));
 return result;
end $$;
revoke all on function public.edit_joint_check_in(uuid,timestamptz,uuid,jsonb,jsonb,jsonb,jsonb,jsonb) from public,anon;
grant execute on function public.edit_joint_check_in(uuid,timestamptz,uuid,jsonb,jsonb,jsonb,jsonb,jsonb) to authenticated;

commit;
