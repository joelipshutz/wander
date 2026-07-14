begin;

-- Follow-up for the already-hosted REC-88 migration: the existing-save path
-- must distinguish the local source id from user_places.source_user_place_id.
create or replace function public.accept_shared_visit(
  input_participant_id uuid,
  input_generation integer,
  input_snapshot_revision integer,
  input_operation_id uuid,
  input_user_place_id uuid,
  input_visit_id uuid,
  input_user_place jsonb,
  input_visit jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_selected_photo_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  participant_row public.shared_visit_participants;
  shared_group public.shared_visit_groups;
  operation_row public.shared_visit_operations;
  recipient_user_place public.user_places;
  recipient_visit public.place_visits;
  existing_user_place boolean := false;
  previous_status text;
  resolved_source_user_place_id uuid;
  input_visibility text;
  input_rating numeric;
  input_visited_at timestamptz;
  input_note text;
  input_attribute_answers jsonb;
  attr jsonb;
  attr_question_definition_id uuid;
  selected_photo_id uuid;
  source_photo jsonb;
  destination_photo_id uuid;
  destination_path text;
  destination_extension text;
  photo_copies jsonb := '[]'::jsonb;
  generated_backfill_id uuid;
  operation_result jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_operation_id is null or input_user_place_id is null or input_visit_id is null then
    raise exception 'invalid_shared_visit_operation_identity';
  end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object'
     or coalesce(jsonb_typeof(input_visit), '') <> 'object'
     or coalesce(jsonb_typeof(input_attributes), '') <> 'array' then
    raise exception 'invalid_shared_visit_acceptance_payload';
  end if;

  select * into operation_row
  from public.shared_visit_operations operation
  where operation.participant_id = input_participant_id
    and operation.invitation_generation = input_generation
    and operation.operation_type = 'accept'
  for update;

  if operation_row.status = 'completed' and operation_row.result is not null then
    return operation_row.result;
  end if;

  select * into participant_row
  from public.shared_visit_participants participant
  where participant.id = input_participant_id
    and participant.user_id = viewer_id
  for update;

  if participant_row.id is null then raise exception 'shared_visit_invitation_not_found'; end if;
  if participant_row.invitation_generation <> input_generation
     or participant_row.snapshot_revision <> input_snapshot_revision then
    raise exception 'stale_shared_visit_invitation';
  end if;

  if participant_row.status = 'accepted' and participant_row.visit_id is not null then
    select result into operation_result
    from public.shared_visit_operations
    where participant_id = participant_row.id
      and invitation_generation = participant_row.invitation_generation
      and operation_type = 'accept'
      and status = 'completed';
    return coalesce(operation_result, jsonb_build_object(
      'participant_id', participant_row.id,
      'visit_id', participant_row.visit_id,
      'status', participant_row.status,
      'photo_copies', '[]'::jsonb
    ));
  end if;
  if participant_row.status <> 'pending' or participant_row.invitation_snapshot is null then
    raise exception 'shared_visit_invitation_unavailable';
  end if;

  select * into shared_group
  from public.shared_visit_groups
  where id = participant_row.group_id and cancelled_at is null;
  if shared_group.id is null then raise exception 'shared_visit_invitation_unavailable'; end if;

  if exists (
    select 1 from public.profiles profile
    where profile.id = viewer_id and (profile.deleted_at is not null or profile.is_private_profile)
  ) then
    raise exception 'private_profile_prevents_shared_visit';
  end if;

  select source_visit.user_place_id
  into resolved_source_user_place_id
  from public.place_visits source_visit
  join public.user_places source_place on source_place.id = source_visit.user_place_id
  join public.profiles source_owner on source_owner.id = source_place.user_id
  where source_visit.id = shared_group.source_visit_id
    and source_visit.deleted_at is null
    and source_place.deleted_at is null
    and source_place.status = 'been'
    and source_place.visibility <> 'self'
    and source_owner.deleted_at is null
    and not source_owner.is_private_profile;
  if resolved_source_user_place_id is null then raise exception 'shared_visit_invitation_unavailable'; end if;

  input_visibility := coalesce(nullif(input_user_place->>'visibility', ''), 'followers');
  if input_visibility not in ('followers', 'mutuals', 'self') then
    raise exception 'invalid_shared_visit_visibility';
  end if;
  input_note := nullif(input_visit->>'note', '');
  input_visited_at := coalesce(nullif(input_visit->>'visited_at', '')::timestamptz, now());
  input_attribute_answers := coalesce(input_visit->'attribute_answers', '[]'::jsonb);
  if jsonb_typeof(input_attribute_answers) <> 'array' then
    raise exception 'invalid_visit_attribute_answers_payload';
  end if;
  if nullif(input_visit->>'rating_score', '') is not null then
    input_rating := (input_visit->>'rating_score')::numeric;
  end if;
  if input_rating is not null and (
    input_rating < 1 or input_rating > 5 or input_rating * 2 <> trunc(input_rating * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  if exists (
    select 1
    from unnest(coalesce(input_selected_photo_ids, array[]::uuid[])) selected_id
    where not exists (
      select 1
      from jsonb_array_elements(coalesce(participant_row.invitation_snapshot->'photos', '[]'::jsonb)) photo
      where photo->>'photo_id' = selected_id::text
    )
  ) then
    raise exception 'invalid_shared_visit_photo_selection';
  end if;
  if cardinality(coalesce(input_selected_photo_ids, array[]::uuid[])) > 10 then
    raise exception 'shared_visit_photo_limit';
  end if;

  insert into public.shared_visit_operations(
    id, participant_id, user_id, invitation_generation, operation_type, status
  ) values (
    input_operation_id, participant_row.id, viewer_id, input_generation, 'accept', 'started'
  )
  on conflict (participant_id, invitation_generation, operation_type) do nothing;

  select * into operation_row
  from public.shared_visit_operations operation
  where operation.participant_id = participant_row.id
    and operation.invitation_generation = input_generation
    and operation.operation_type = 'accept'
  for update;
  if operation_row.status = 'completed' and operation_row.result is not null then
    return operation_row.result;
  end if;

  select * into recipient_user_place
  from public.user_places user_place
  where user_place.user_id = viewer_id
    and user_place.place_id = shared_group.place_id
    and user_place.deleted_at is null
  for update;
  existing_user_place := recipient_user_place.id is not null;
  previous_status := recipient_user_place.status;

  if not existing_user_place then
    if exists (select 1 from public.user_places where id = input_user_place_id) then
      raise exception 'shared_visit_user_place_id_conflict';
    end if;

    insert into public.user_places(
      id, user_id, place_id, status, note, rating_score, visibility,
      nearby_confirmed, visited_at, source_type, source_user_place_id,
      attribution_user_id, deleted_at
    ) values (
      input_user_place_id, viewer_id, shared_group.place_id, 'been', input_note,
      input_rating, input_visibility, false, input_visited_at, 'social_save',
      resolved_source_user_place_id, shared_group.owner_user_id, null
    )
    returning * into recipient_user_place;
  else
    update public.user_places
    set status = 'been',
        note = input_note,
        rating_score = input_rating,
        visibility = input_visibility,
        visited_at = input_visited_at,
        source_type = 'social_save',
        source_user_place_id = resolved_source_user_place_id,
        attribution_user_id = shared_group.owner_user_id,
        deleted_at = null,
        updated_at = now()
    where id = recipient_user_place.id
    returning * into recipient_user_place;
  end if;

  delete from public.place_attributes where user_place_id = recipient_user_place.id;
  for attr in select value from jsonb_array_elements(input_attributes)
  loop
    if nullif(attr->>'question_key', '') is null
       or nullif(attr->>'value_type', '') is null
       or not (attr ? 'value')
       or attr->'value' = 'null'::jsonb then
      continue;
    end if;

    select definition.id into attr_question_definition_id
    from public.question_definitions definition
    where definition.question_key = attr->>'question_key'
      and (definition.owner_user_id = viewer_id or definition.is_system)
    order by (definition.owner_user_id = viewer_id) desc, definition.is_system desc
    limit 1;

    insert into public.place_attributes(
      user_place_id, question_definition_id, question_key, value_type, value
    ) values (
      recipient_user_place.id, attr_question_definition_id,
      attr->>'question_key', attr->>'value_type', attr->'value'
    );
  end loop;

  if not existing_user_place or previous_status = 'wanna_go' then
    select visit.id into generated_backfill_id
    from public.place_visits visit
    where visit.user_place_id = recipient_user_place.id
      and visit.backfilled_from_user_place
      and visit.deleted_at is null
    order by visit.created_at desc
    limit 1
    for update;

    if generated_backfill_id is null then
      raise exception 'shared_visit_backfilled_visit_missing';
    end if;
    if input_visit_id <> generated_backfill_id
       and exists (select 1 from public.place_visits where id = input_visit_id) then
      raise exception 'shared_visit_visit_id_conflict';
    end if;

    update public.place_visits
    set id = input_visit_id,
        visited_at = input_visited_at,
        note = input_note,
        rating_score = input_rating,
        attribute_answers = input_attribute_answers,
        updated_at = now()
    where id = generated_backfill_id
    returning * into recipient_visit;

    update public.notification_events
    set data = jsonb_set(data, '{visit_id}', to_jsonb(input_visit_id::text), true),
        updated_at = now()
    where actor_user_id = viewer_id
      and notification_type = 'followed_place_visit'
      and data->>'visit_id' = generated_backfill_id::text
      and status = 'pending';
  else
    if exists (select 1 from public.place_visits where id = input_visit_id) then
      raise exception 'shared_visit_visit_id_conflict';
    end if;
    insert into public.place_visits(
      id, user_place_id, visited_at, note, rating_score,
      attribute_answers, backfilled_from_user_place
    ) values (
      input_visit_id, recipient_user_place.id, input_visited_at, input_note,
      input_rating, input_attribute_answers, false
    )
    returning * into recipient_visit;
  end if;

  foreach selected_photo_id in array coalesce(input_selected_photo_ids, array[]::uuid[]) loop
    select photo into source_photo
    from jsonb_array_elements(coalesce(participant_row.invitation_snapshot->'photos', '[]'::jsonb)) photo
    where photo->>'photo_id' = selected_photo_id::text;

    destination_photo_id := gen_random_uuid();
    destination_extension := case lower(coalesce(source_photo->>'content_type', 'image/jpeg'))
      when 'image/png' then 'png'
      when 'image/heic' then 'heic'
      when 'image/heif' then 'heif'
      when 'image/webp' then 'webp'
      else 'jpg'
    end;
    destination_path := viewer_id || '/' || recipient_visit.id || '/' || destination_photo_id || '.' || destination_extension;

    insert into public.visit_photos(
      id, visit_id, storage_bucket, storage_path, content_type, byte_size,
      width, height, captured_at, sort_order, upload_state
    ) values (
      destination_photo_id,
      recipient_visit.id,
      'visit-photos',
      destination_path,
      coalesce(source_photo->>'content_type', 'image/jpeg'),
      nullif(source_photo->>'byte_size', '')::integer,
      nullif(source_photo->>'width', '')::integer,
      nullif(source_photo->>'height', '')::integer,
      nullif(source_photo->>'captured_at', '')::timestamptz,
      coalesce(nullif(source_photo->>'sort_order', '')::integer, 0),
      'pending_upload'
    );

    photo_copies := photo_copies || jsonb_build_array(jsonb_build_object(
      'source_photo_id', selected_photo_id,
      'source_bucket', source_photo->>'storage_bucket',
      'source_path', source_photo->>'storage_path',
      'destination_photo_id', destination_photo_id,
      'destination_bucket', 'visit-photos',
      'destination_path', destination_path,
      'content_type', coalesce(source_photo->>'content_type', 'image/jpeg')
    ));
  end loop;

  update public.shared_visit_participants
  set status = 'accepted',
      visit_id = recipient_visit.id,
      invitation_snapshot = null,
      responded_at = now(),
      cancelled_at = null,
      updated_at = now()
  where id = participant_row.id
  returning * into participant_row;

  operation_result := jsonb_build_object(
    'operation_id', operation_row.id,
    'participant_id', participant_row.id,
    'user_place_id', recipient_user_place.id,
    'visit_id', recipient_visit.id,
    'backfilled_from_user_place', recipient_visit.backfilled_from_user_place,
    'status', participant_row.status,
    'photo_copies', photo_copies
  );

  update public.shared_visit_operations
  set status = 'completed', result = operation_result, updated_at = now()
  where id = operation_row.id;

  return operation_result;
end;
$$;

revoke all on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[])
  from public, anon;
grant execute on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[])
  to authenticated;

do $metadata$
declare
  rpc_oid oid := 'public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[])'::regprocedure;
  valid boolean;
begin
  select
    procedure.prosecdef
    and procedure.provolatile = 'v'
    and pg_get_function_result(procedure.oid) = 'jsonb'
    and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    and has_function_privilege('authenticated', procedure.oid, 'execute')
    and not has_function_privilege('anon', procedure.oid, 'execute')
  into valid
  from pg_proc procedure
  where procedure.oid = rpc_oid;

  if valid is distinct from true then
    raise exception 'accept_shared_visit security metadata regression';
  end if;
end
$metadata$;

comment on function public.accept_shared_visit(uuid, integer, integer, uuid, uuid, uuid, jsonb, jsonb, jsonb, uuid[]) is
  'Atomically creates one recipient-owned save/visit and copy plan for the exact invitation snapshot generation.';

commit;
