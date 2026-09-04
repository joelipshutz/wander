begin;

-- Repeat check-ins can start from an owned server projection whose provider
-- identity is not present on-device. Accept the owned user_place UUID as the
-- canonical parent and recover the provider identity server-side before the
-- existing atomic save path runs.
create or replace function app.save_own_check_in(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb,
  input_visit jsonb default '{}'::jsonb,
  input_historical_want jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  provider text;
  provider_place_id text;
  requested_user_place_id uuid;
  prior_parent public.user_places;
  prior_attributes jsonb;
  saved_parent public.user_places;
  saved_visit public.place_visits;
  requested_visit_id uuid;
  requested_visited_at timestamptz;
  requested_rating numeric;
  existing_visit public.place_visits;
  captured_historical_note text;
  captured_historical_answers jsonb;
  captured_historical_tags text[];
  captured_historical_wanted_at timestamptz;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(jsonb_typeof(input_place), '') <> 'object' then
    raise exception 'invalid_place_payload';
  end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object' then
    raise exception 'invalid_user_place_payload';
  end if;
  if coalesce(jsonb_typeof(input_attributes), 'array') <> 'array' then
    raise exception 'invalid_attributes_payload';
  end if;
  if coalesce(jsonb_typeof(input_visit), '') <> 'object' then
    raise exception 'invalid_check_in_payload';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(input_historical_want) <> 'object' then
    raise exception 'invalid_historical_want_payload';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(coalesce(input_historical_want->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_historical_want_attributes';
  end if;
  if input_historical_want is not null
    and jsonb_typeof(coalesce(input_historical_want->'tags', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_historical_want_tags';
  end if;

  begin
    requested_visit_id := (input_visit->>'id')::uuid;
    requested_visited_at := (input_visit->>'visited_at')::timestamptz;
  exception when others then
    raise exception 'invalid_check_in_identity_or_date';
  end;
  if requested_visit_id is null or requested_visited_at is null then
    raise exception 'invalid_check_in_identity_or_date';
  end if;
  if requested_visited_at > now() then
    raise exception 'future_check_in_not_allowed';
  end if;
  if jsonb_typeof(coalesce(input_visit->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_visit_attribute_answers_payload';
  end if;

  if nullif(input_visit->>'rating_score', '') is not null then
    requested_rating := (input_visit->>'rating_score')::numeric;
  end if;
  if requested_rating is not null and (
    requested_rating < 1
    or requested_rating > 5
    or requested_rating * 2 <> trunc(requested_rating * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  if nullif(input_user_place->>'id', '') is not null then
    begin
      requested_user_place_id := (input_user_place->>'id')::uuid;
    exception when others then
      raise exception 'invalid_user_place_identity';
    end;

    select up.*
    into prior_parent
    from public.user_places up
    where up.id = requested_user_place_id
      and up.user_id = viewer_id
      and up.deleted_at is null
    limit 1;

    if prior_parent.id is null then
      raise exception 'invalid_user_place_identity';
    end if;

    select place.source_provider, place.source_provider_place_id
    into provider, provider_place_id
    from public.places place
    where place.id = prior_parent.place_id;

    if nullif(provider, '') is null
      or nullif(provider_place_id, '') is null then
      raise exception 'invalid_user_place_identity';
    end if;

    input_place := input_place || jsonb_build_object(
      'source_provider', provider,
      'source_provider_place_id', provider_place_id
    );
  else
    provider := coalesce(nullif(input_place->>'source_provider', ''), 'manual');
    provider_place_id := nullif(input_place->>'source_provider_place_id', '');
    if provider_place_id is null then
      provider_place_id := 'generated:' || md5(
        provider || ':' ||
        coalesce(input_place->>'canonical_name', '') || ':' ||
        coalesce(input_place->>'latitude', '') || ':' ||
        coalesce(input_place->>'longitude', '')
      );
    end if;

    select up.*
    into prior_parent
    from public.user_places up
    join public.places place on place.id = up.place_id
    where up.user_id = viewer_id
      and place.source_provider = provider
      and place.source_provider_place_id = provider_place_id
      and up.deleted_at is null
    limit 1;
  end if;

  if prior_parent.id is not null and prior_parent.status = 'wanna_go' then
    prior_attributes := app.user_place_attribute_answers(prior_parent.id);
  end if;

  perform set_config('app.explicit_check_in', 'on', true);
  select *
  into saved_parent
  from app.save_own_place(
    input_place,
    input_user_place || jsonb_build_object(
      'status', 'been',
      'planned_date', null
    ),
    input_attributes
  );

  if saved_parent.user_id <> viewer_id then
    raise exception 'not_owner';
  end if;

  if input_historical_want is not null then
    captured_historical_note := nullif(input_historical_want->>'note', '');
    captured_historical_answers := coalesce(input_historical_want->'attribute_answers', '[]'::jsonb);
    captured_historical_tags := coalesce(
      array(
        select jsonb_array_elements_text(
          coalesce(input_historical_want->'tags', '[]'::jsonb)
        )
      ),
      '{}'::text[]
    );
    begin
      captured_historical_wanted_at := (input_historical_want->>'wanted_at')::timestamptz;
    exception when others then
      raise exception 'invalid_historical_want_date';
    end;
  elsif prior_parent.id is not null and prior_parent.status = 'wanna_go' then
    captured_historical_note := prior_parent.note;
    captured_historical_answers := coalesce(prior_attributes, '[]'::jsonb);
    captured_historical_tags := app.visit_tags_from_attribute_answers(captured_historical_answers);
    captured_historical_wanted_at := coalesce(prior_parent.saved_at, prior_parent.created_at, now());
  end if;

  if captured_historical_wanted_at is not null then
    if jsonb_typeof(coalesce(captured_historical_answers, '[]'::jsonb)) <> 'array' then
      raise exception 'invalid_historical_want_attributes';
    end if;
    update public.user_places
    set historical_want_note = captured_historical_note,
        historical_want_attribute_answers = coalesce(captured_historical_answers, '[]'::jsonb),
        historical_want_tags = coalesce(captured_historical_tags, '{}'::text[]),
        historical_wanted_at = captured_historical_wanted_at
    where id = saved_parent.id
      and user_id = viewer_id
    returning * into saved_parent;
  end if;

  select *
  into existing_visit
  from public.place_visits
  where id = requested_visit_id;

  if existing_visit.id is not null
    and existing_visit.user_place_id <> saved_parent.id then
    raise exception 'check_in_id_conflict';
  end if;

  insert into public.place_visits (
    id,
    user_place_id,
    visited_at,
    note,
    rating_score,
    attribute_answers,
    backfilled_from_user_place,
    deleted_at
  )
  values (
    requested_visit_id,
    saved_parent.id,
    requested_visited_at,
    nullif(input_visit->>'note', ''),
    requested_rating,
    coalesce(input_visit->'attribute_answers', '[]'::jsonb),
    false,
    null
  )
  on conflict (id)
  do update set
    visited_at = excluded.visited_at,
    note = excluded.note,
    rating_score = excluded.rating_score,
    attribute_answers = excluded.attribute_answers,
    deleted_at = null,
    updated_at = now()
  returning * into saved_visit;

  update public.place_visits
  set deleted_at = coalesce(deleted_at, now()),
      updated_at = now()
  where user_place_id = saved_parent.id
    and backfilled_from_user_place
    and deleted_at is null;

  return jsonb_build_object(
    'user_place_id', saved_parent.id,
    'place_id', saved_parent.place_id,
    'visit_id', saved_visit.id,
    'visited_at', saved_visit.visited_at,
    'note', saved_visit.note,
    'rating_score', saved_visit.rating_score,
    'tags', to_jsonb(saved_visit.tags),
    'backfilled_from_user_place', saved_visit.backfilled_from_user_place
  );
end;
$$;

revoke all on function app.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function app.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb)
  to authenticated;

comment on function app.save_own_check_in(jsonb, jsonb, jsonb, jsonb, jsonb) is
  'Atomically saves an authenticated check-in, accepting an owned user_place UUID to preserve the canonical server parent when client projections lack provider identity.';

commit;
