begin;

create or replace function app.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns public.user_places
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  provider text;
  provider_place_id text;
  existing_place_id uuid;
  place_row public.places;
  saved_row public.user_places;
  input_rating_score numeric;
  input_primary_category text;
  input_subcategory text;
  input_category_source text;
  input_category_confidence double precision;
  input_raw_provider_type text;
  input_category_override text;
  input_subcategory_override text;
  input_category_override_source text;
  input_category_override_confidence double precision;
  attr jsonb;
  attr_question_key text;
  attr_value_type text;
  attr_question_definition_id uuid;
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

  if nullif(input_user_place->>'rating_score', '') is not null then
    input_rating_score := (input_user_place->>'rating_score')::numeric;
  end if;

  if input_rating_score is not null and (
    input_rating_score < 1
    or input_rating_score > 5
    or input_rating_score * 2 <> trunc(input_rating_score * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

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

  -- Serialize all saves for the provider identity. Existing canonical places
  -- also share a lock with social saves so a concurrent check-in always wins.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:place-provider:' || viewer_id || ':' || provider || ':' || provider_place_id,
      0
    )
  );

  select p.id
  into existing_place_id
  from public.places p
  where p.source_provider = provider
    and p.source_provider_place_id = provider_place_id;

  if existing_place_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'recme:user-place:' || viewer_id || ':' || existing_place_id::text,
        0
      )
    );
  end if;

  if input_user_place->>'status' = 'wanna_go' then
    select up.*
    into saved_row
    from public.places p
    join public.user_places up
      on up.place_id = p.id
     and up.user_id = viewer_id
     and up.deleted_at is null
    where p.source_provider = provider
      and p.source_provider_place_id = provider_place_id
      and up.status = 'been'
    limit 1;

    if saved_row.id is not null then
      return saved_row;
    end if;
  end if;

  input_raw_provider_type := nullif(input_place->>'raw_provider_type', '');
  input_primary_category := app.place_primary_category(
    coalesce(nullif(input_place->>'primary_category', ''), nullif(input_place->>'category', ''), input_raw_provider_type, 'place')
  );
  input_subcategory := app.place_subcategory(
    coalesce(nullif(input_place->>'subcategory', ''), input_raw_provider_type, input_place->>'category'),
    input_primary_category
  );
  input_category_source := lower(coalesce(nullif(input_place->>'category_source', ''), 'legacy'));
  if input_category_source not in ('provider', 'deterministic', 'ai', 'legacy', 'unknown') then
    input_category_source := 'legacy';
  end if;

  if nullif(input_place->>'category_confidence', '') is not null then
    input_category_confidence := greatest(0, least((input_place->>'category_confidence')::double precision, 1));
  else
    input_category_confidence := nullif(input_place->>'confidence', '')::double precision;
  end if;

  input_category_override := nullif(input_user_place->>'category_override', '');
  if input_category_override is not null then
    input_category_override := app.place_primary_category(input_category_override);
    input_subcategory_override := app.place_subcategory(
      coalesce(nullif(input_user_place->>'subcategory_override', ''), input_category_override),
      input_category_override
    );
    input_category_override_source := lower(coalesce(nullif(input_user_place->>'category_override_source', ''), 'user'));
    if input_category_override_source not in ('user', 'ai', 'deterministic', 'unknown') then
      input_category_override_source := 'user';
    end if;
    if nullif(input_user_place->>'category_override_confidence', '') is not null then
      input_category_override_confidence := greatest(0, least((input_user_place->>'category_override_confidence')::double precision, 1));
    end if;
  end if;

  insert into public.places (
    canonical_name,
    category,
    primary_category,
    subcategory,
    category_source,
    category_confidence,
    raw_provider_type,
    address,
    locality,
    region,
    country,
    latitude,
    longitude,
    source_provider,
    source_provider_place_id,
    confidence
  )
  values (
    input_place->>'canonical_name',
    input_primary_category,
    input_primary_category,
    input_subcategory,
    input_category_source,
    input_category_confidence,
    coalesce(input_raw_provider_type, nullif(input_place->>'category', '')),
    nullif(input_place->>'address', ''),
    nullif(input_place->>'locality', ''),
    nullif(input_place->>'region', ''),
    nullif(input_place->>'country', ''),
    (input_place->>'latitude')::double precision,
    (input_place->>'longitude')::double precision,
    provider,
    provider_place_id,
    nullif(input_place->>'confidence', '')::double precision
  )
  on conflict (source_provider, source_provider_place_id)
  do update set
    canonical_name = excluded.canonical_name,
    category = excluded.primary_category,
    primary_category = excluded.primary_category,
    subcategory = excluded.subcategory,
    category_source = excluded.category_source,
    category_confidence = excluded.category_confidence,
    raw_provider_type = excluded.raw_provider_type,
    address = excluded.address,
    locality = excluded.locality,
    region = excluded.region,
    country = excluded.country,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    confidence = excluded.confidence,
    updated_at = now()
  returning * into place_row;

  insert into public.user_places (
    user_id,
    place_id,
    status,
    note,
    rating_signal,
    rating_score,
    category_override,
    subcategory_override,
    category_override_source,
    category_override_confidence,
    visibility,
    nearby_confirmed,
    source_type
  )
  values (
    viewer_id,
    place_row.id,
    input_user_place->>'status',
    nullif(input_user_place->>'note', ''),
    nullif(input_user_place->>'rating_signal', ''),
    case when input_user_place->>'status' = 'been' then input_rating_score else null end,
    input_category_override,
    input_subcategory_override,
    input_category_override_source,
    input_category_override_confidence,
    input_user_place->>'visibility',
    coalesce((input_user_place->>'nearby_confirmed')::boolean, false),
    input_user_place->>'source_type'
  )
  on conflict (user_id, place_id)
  do update set
    status = excluded.status,
    note = excluded.note,
    rating_signal = excluded.rating_signal,
    rating_score = excluded.rating_score,
    category_override = excluded.category_override,
    subcategory_override = excluded.subcategory_override,
    category_override_source = excluded.category_override_source,
    category_override_confidence = excluded.category_override_confidence,
    visibility = excluded.visibility,
    nearby_confirmed = excluded.nearby_confirmed,
    source_type = excluded.source_type,
    deleted_at = null,
    updated_at = now()
  returning * into saved_row;

  delete from public.place_attributes pa
  where pa.user_place_id = saved_row.id
    and not exists (
      select 1
      from jsonb_array_elements(input_attributes) as incoming(attr)
      where incoming.attr->>'question_key' = pa.question_key
    );

  for attr in select value from jsonb_array_elements(input_attributes)
  loop
    attr_question_key := nullif(attr->>'question_key', '');
    attr_value_type := nullif(attr->>'value_type', '');

    if attr_question_key is null
       or attr_value_type is null
       or not (attr ? 'value')
       or attr->'value' = 'null'::jsonb then
      continue;
    end if;

    select qd.id
    into attr_question_definition_id
    from public.question_definitions qd
    where qd.question_key = attr_question_key
      and (qd.owner_user_id = viewer_id or qd.is_system)
    order by (qd.owner_user_id = viewer_id) desc, qd.is_system desc
    limit 1;

    insert into public.place_attributes (
      user_place_id,
      question_definition_id,
      question_key,
      value_type,
      value
    )
    values (
      saved_row.id,
      attr_question_definition_id,
      attr_question_key,
      attr_value_type,
      attr->'value'
    )
    on conflict (user_place_id, question_key)
    do update set
      question_definition_id = excluded.question_definition_id,
      value_type = excluded.value_type,
      value = excluded.value,
      updated_at = now();
  end loop;

  return saved_row;
end;
$$;

create or replace function public.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = app, public
as $$
declare
  viewer_id text := app.current_user_id();
  saved public.user_places;
  requested_planned_date date;
  planned_date_kind text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into saved
  from app.save_own_place(input_place, input_user_place, input_attributes);

  if saved.status = 'been'
     and input_user_place->>'status' = 'wanna_go' then
    return jsonb_build_object(
      'user_place_id', saved.id,
      'place_id', saved.place_id
    );
  end if;

  if input_user_place ? 'planned_date' then
    planned_date_kind := jsonb_typeof(input_user_place->'planned_date');
    if planned_date_kind not in ('string', 'null') then
      raise exception 'invalid_planned_date';
    end if;

    if planned_date_kind = 'string' then
      begin
        requested_planned_date := (input_user_place->>'planned_date')::date;
      exception
        when invalid_datetime_format or datetime_field_overflow then
          raise exception 'invalid_planned_date';
      end;
    end if;

    if requested_planned_date is not null
       and input_user_place->>'status' <> 'wanna_go' then
      raise exception 'planned_date_requires_wanna_go';
    end if;

    update public.user_places
    set planned_date = requested_planned_date
    where id = saved.id
      and user_id = viewer_id
    returning * into saved;
  end if;

  return jsonb_build_object(
    'user_place_id', saved.id,
    'place_id', saved.place_id
  );
end;
$$;

create or replace function app.save_visible_place(input_place_id uuid, input_source_user_place_id uuid)
returns public.user_places
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  source_row public.user_places;
  saved_row public.user_places;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into source_row
  from public.user_places up
  where up.id = input_source_user_place_id
    and up.place_id = input_place_id
    and up.deleted_at is null;

  if source_row.id is null then
    raise exception 'source_not_visible';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:user-place:' || viewer_id || ':' || input_place_id::text,
      0
    )
  );

  select *
  into saved_row
  from public.user_places up
  where up.user_id = viewer_id
    and up.place_id = input_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if saved_row.id is not null then
    return saved_row;
  end if;

  insert into public.user_places (
    user_id,
    place_id,
    status,
    note,
    rating_signal,
    visibility,
    source_type,
    source_user_place_id,
    attribution_user_id
  )
  values (
    viewer_id,
    input_place_id,
    'wanna_go',
    source_row.note,
    source_row.rating_signal,
    'followers',
    'social_save',
    source_row.id,
    source_row.user_id
  )
  on conflict (user_id, place_id)
  do update set
    status = excluded.status,
    note = excluded.note,
    rating_signal = excluded.rating_signal,
    source_type = excluded.source_type,
    source_user_place_id = excluded.source_user_place_id,
    attribution_user_id = excluded.attribution_user_id,
    deleted_at = null,
    updated_at = now()
  returning * into saved_row;

  insert into public.place_attributes (user_place_id, question_definition_id, question_key, value_type, value)
  select saved_row.id, pa.question_definition_id, pa.question_key, pa.value_type, pa.value
  from public.place_attributes pa
  where pa.user_place_id = source_row.id
  on conflict (user_place_id, question_key)
  do update set
    question_definition_id = excluded.question_definition_id,
    value_type = excluded.value_type,
    value = excluded.value,
    updated_at = now();

  return saved_row;
end;
$$;

comment on function app.save_own_place(jsonb, jsonb, jsonb) is
  'Authenticated own-place save. Existing check-ins are authoritative and cannot be replaced by a stale Wanna Go save.';
comment on function public.save_own_place(jsonb, jsonb, jsonb) is
  'Authenticated own-place save wrapper. Applies optional Wanna Go dates without mutating an existing check-in.';
comment on function app.save_visible_place(uuid, uuid) is
  'Copies a visible place into the authenticated account unless that account already has an authoritative check-in.';

revoke all on function app.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function app.save_visible_place(uuid, uuid) from public, anon;

grant execute on function app.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function app.save_visible_place(uuid, uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_proc
    where oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'app.save_own_place security posture changed';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
      and not prosecdef
      and 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.save_own_place security posture changed';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'app.save_visible_place(uuid,uuid)'::regprocedure
      and not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'app.save_visible_place security posture changed';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.save_visible_place(uuid,uuid)'::regprocedure
      and not prosecdef
      and 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.save_visible_place security posture changed';
  end if;

  if not has_function_privilege('authenticated', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'app.save_visible_place(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'app.save_visible_place(uuid,uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.save_visible_place(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.save_visible_place(uuid,uuid)', 'execute') then
    raise exception 'REC-190 RPC grants are invalid';
  end if;
end;
$$;

commit;
