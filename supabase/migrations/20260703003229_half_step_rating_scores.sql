begin;

drop function if exists public.save_own_place(jsonb, jsonb, jsonb);
drop function if exists public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists public.profile_visible_places(text, text[], text[]);
drop function if exists app.save_own_place(jsonb, jsonb, jsonb);
drop function if exists app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists app.profile_visible_places(text, text[], text[]);

alter table public.user_places
  alter column rating_score type numeric(2, 1)
  using rating_score::numeric(2, 1);

alter table public.user_places
  drop constraint if exists user_places_rating_score_check;

alter table public.user_places
  add constraint user_places_rating_score_check
  check (
    rating_score is null
    or (
      rating_score between 1 and 5
      and rating_score * 2 = trunc(rating_score * 2)
    )
  );

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

create or replace function app.visible_places_in_view(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  status_filter text[] default null,
  category_filter text[] default null,
  owner_scope text[] default null
)
returns table (
  user_place_id uuid,
  place_id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  category_source text,
  category_confidence double precision,
  raw_provider_type text,
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score double precision,
  recommended_score double precision,
  recommended_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      p.canonical_name,
      coalesce(up.category_override, p.primary_category, p.category) as effective_category,
      coalesce(p.primary_category, p.category) as primary_category,
      coalesce(up.subcategory_override, p.subcategory) as effective_subcategory,
      p.subcategory as place_subcategory,
      p.category_source,
      p.category_confidence,
      p.raw_provider_type,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.rating_signal,
      up.rating_score::double precision as rating_score,
      up.category_override,
      up.subcategory_override,
      up.category_override_source,
      up.category_override_confidence,
      up.source_type
    from public.user_places up
    join public.places p on p.id = up.place_id
    join public.profiles owner on owner.id = up.user_id
    where up.deleted_at is null
      and p.latitude between min_lat and max_lat
      and p.longitude between min_lng and max_lng
      and (status_filter is null or up.status = any(status_filter))
      and (category_filter is null or coalesce(up.category_override, p.primary_category, p.category) = any(category_filter))
      and (
        owner_scope is null
        or ('you' = any(owner_scope) and up.user_id = app.current_user_id())
        or ('following' = any(owner_scope) and up.user_id <> app.current_user_id() and app.follows(app.current_user_id(), up.user_id))
        or ('friends' = any(owner_scope) and up.user_id <> app.current_user_id() and app.is_mutual(app.current_user_id(), up.user_id))
        or ('social' = any(owner_scope) and up.user_id <> app.current_user_id())
      )
  ),
  visible_rating_rows as (
    select up.place_id, up.rating_score
    from public.user_places up
    where up.deleted_at is null
      and up.status = 'been'
      and up.rating_score is not null
      and up.place_id in (select distinct place_id from visible_rows)
  ),
  rating_summary as (
    select
      place_id,
      round(avg(rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from visible_rating_rows
    group by place_id
  )
  select
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.canonical_name,
    vr.effective_category as category,
    vr.primary_category,
    vr.place_subcategory as subcategory,
    vr.category_source,
    vr.category_confidence,
    vr.raw_provider_type,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    coalesce(rs.recommended_count, 0),
    vr.category_override,
    vr.subcategory_override,
    vr.category_override_source,
    vr.category_override_confidence,
    vr.source_type,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_definition_id', pa.question_definition_id,
          'question_key', pa.question_key,
          'value_type', pa.value_type,
          'value', pa.value,
          'prompt', qd.prompt,
          'options', coalesce(qd.options, '[]'::jsonb),
          'is_system', coalesce(qd.is_system, false)
        )
      ) filter (where pa.id is not null),
      '[]'::jsonb
    ) as attributes
  from visible_rows vr
  left join rating_summary rs on rs.place_id = vr.place_id
  left join public.place_attributes pa on pa.user_place_id = vr.user_place_id
  left join public.question_definitions qd on qd.id = pa.question_definition_id
  group by
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.canonical_name,
    vr.effective_category,
    vr.primary_category,
    vr.place_subcategory,
    vr.category_source,
    vr.category_confidence,
    vr.raw_provider_type,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    rs.recommended_count,
    vr.category_override,
    vr.subcategory_override,
    vr.category_override_source,
    vr.category_override_confidence,
    vr.source_type;
$$;

create or replace function app.profile_visible_places(
  profile_id text,
  status_filter text[] default null,
  category_filter text[] default null
)
returns table (
  user_place_id uuid,
  place_id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  category_source text,
  category_confidence double precision,
  raw_provider_type text,
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score double precision,
  recommended_score double precision,
  recommended_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      p.canonical_name,
      coalesce(up.category_override, p.primary_category, p.category) as effective_category,
      coalesce(p.primary_category, p.category) as primary_category,
      coalesce(up.subcategory_override, p.subcategory) as effective_subcategory,
      p.subcategory as place_subcategory,
      p.category_source,
      p.category_confidence,
      p.raw_provider_type,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.rating_signal,
      up.rating_score::double precision as rating_score,
      up.category_override,
      up.subcategory_override,
      up.category_override_source,
      up.category_override_confidence,
      up.source_type,
      up.updated_at
    from public.user_places up
    join public.places p on p.id = up.place_id
    join public.profiles owner on owner.id = up.user_id
    where up.user_id = profile_id
      and up.deleted_at is null
      and (status_filter is null or up.status = any(status_filter))
      and (category_filter is null or coalesce(up.category_override, p.primary_category, p.category) = any(category_filter))
  ),
  visible_rating_rows as (
    select up.place_id, up.rating_score
    from public.user_places up
    where up.deleted_at is null
      and up.status = 'been'
      and up.rating_score is not null
      and up.place_id in (select distinct place_id from visible_rows)
  ),
  rating_summary as (
    select
      place_id,
      round(avg(rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from visible_rating_rows
    group by place_id
  )
  select
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.canonical_name,
    vr.effective_category as category,
    vr.primary_category,
    vr.place_subcategory as subcategory,
    vr.category_source,
    vr.category_confidence,
    vr.raw_provider_type,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    coalesce(rs.recommended_count, 0),
    vr.category_override,
    vr.subcategory_override,
    vr.category_override_source,
    vr.category_override_confidence,
    vr.source_type,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_definition_id', pa.question_definition_id,
          'question_key', pa.question_key,
          'value_type', pa.value_type,
          'value', pa.value,
          'prompt', qd.prompt,
          'options', coalesce(qd.options, '[]'::jsonb),
          'is_system', coalesce(qd.is_system, false)
        )
      ) filter (where pa.id is not null),
      '[]'::jsonb
    ) as attributes
  from visible_rows vr
  left join rating_summary rs on rs.place_id = vr.place_id
  left join public.place_attributes pa on pa.user_place_id = vr.user_place_id
  left join public.question_definitions qd on qd.id = pa.question_definition_id
  group by
    vr.user_place_id,
    vr.place_id,
    vr.owner_user_id,
    vr.owner_handle,
    vr.owner_display_name,
    vr.canonical_name,
    vr.effective_category,
    vr.primary_category,
    vr.place_subcategory,
    vr.category_source,
    vr.category_confidence,
    vr.raw_provider_type,
    vr.latitude,
    vr.longitude,
    vr.status,
    vr.visibility,
    vr.note,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    rs.recommended_count,
    vr.category_override,
    vr.subcategory_override,
    vr.category_override_source,
    vr.category_override_confidence,
    vr.source_type,
    vr.updated_at
  order by vr.updated_at desc;
$$;

create or replace function public.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns jsonb
language sql
security invoker
set search_path = app, public
as $$
  select jsonb_build_object(
    'user_place_id', saved.id,
    'place_id', saved.place_id
  )
  from app.save_own_place(input_place, input_user_place, input_attributes) as saved;
$$;

create or replace function public.visible_places_in_view(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision,
  status_filter text[] default null,
  category_filter text[] default null,
  owner_scope text[] default null
)
returns table (
  user_place_id uuid,
  place_id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  category_source text,
  category_confidence double precision,
  raw_provider_type text,
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score double precision,
  recommended_score double precision,
  recommended_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select *
  from app.visible_places_in_view(
    min_lat,
    min_lng,
    max_lat,
    max_lng,
    status_filter,
    category_filter,
    owner_scope
  );
$$;

create or replace function public.profile_visible_places(
  profile_id text,
  status_filter text[] default null,
  category_filter text[] default null
)
returns table (
  user_place_id uuid,
  place_id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  category_source text,
  category_confidence double precision,
  raw_provider_type text,
  latitude double precision,
  longitude double precision,
  status text,
  visibility text,
  note text,
  rating_signal text,
  rating_score double precision,
  recommended_score double precision,
  recommended_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security invoker
set search_path = app, public
as $$
  select *
  from app.profile_visible_places(profile_id, status_filter, category_filter);
$$;

revoke all on function app.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function app.profile_visible_places(text, text[], text[]) from public, anon;
revoke all on function public.profile_visible_places(text, text[], text[]) from public, anon;

grant execute on function app.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function app.profile_visible_places(text, text[], text[]) to authenticated;
grant execute on function public.profile_visible_places(text, text[], text[]) to authenticated;

commit;
