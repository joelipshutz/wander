begin;

drop function if exists public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists public.profile_visible_places(text, text[], text[]);
drop function if exists app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]);
drop function if exists app.profile_visible_places(text, text[], text[]);

create function app.visible_places_in_view(
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
  owner_avatar_url text,
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
  visited_at timestamptz,
  saved_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
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
set search_path = public, app
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      p.canonical_name,
      coalesce(up.category_override, p.primary_category, p.category) as effective_category,
      coalesce(p.primary_category, p.category) as primary_category,
      p.subcategory as place_subcategory,
      p.category_source,
      p.category_confidence,
      p.raw_provider_type,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.visited_at,
      up.saved_at,
      up.created_at,
      up.updated_at,
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
    vr.owner_avatar_url,
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
    vr.visited_at,
    vr.saved_at,
    vr.created_at,
    vr.updated_at,
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
    vr.owner_avatar_url,
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
    vr.visited_at,
    vr.saved_at,
    vr.created_at,
    vr.updated_at,
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

create function app.profile_visible_places(
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
  owner_avatar_url text,
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
  visited_at timestamptz,
  saved_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
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
set search_path = public, app
as $$
  with visible_rows as (
    select
      up.id as user_place_id,
      p.id as place_id,
      up.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      p.canonical_name,
      coalesce(up.category_override, p.primary_category, p.category) as effective_category,
      coalesce(p.primary_category, p.category) as primary_category,
      p.subcategory as place_subcategory,
      p.category_source,
      p.category_confidence,
      p.raw_provider_type,
      p.latitude,
      p.longitude,
      up.status,
      up.visibility,
      up.note,
      up.visited_at,
      up.saved_at,
      up.created_at,
      up.updated_at,
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
    vr.owner_avatar_url,
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
    vr.visited_at,
    vr.saved_at,
    vr.created_at,
    vr.updated_at,
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
    vr.owner_avatar_url,
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
    vr.visited_at,
    vr.saved_at,
    vr.created_at,
    vr.updated_at,
    vr.rating_signal,
    vr.rating_score,
    rs.recommended_score,
    rs.recommended_count,
    vr.category_override,
    vr.subcategory_override,
    vr.category_override_source,
    vr.category_override_confidence,
    vr.source_type
  order by vr.updated_at desc;
$$;

create function public.visible_places_in_view(
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
  owner_avatar_url text,
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
  visited_at timestamptz,
  saved_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
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
set search_path = public, app
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

create function public.profile_visible_places(
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
  owner_avatar_url text,
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
  visited_at timestamptz,
  saved_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
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
set search_path = public, app
as $$
  select *
  from app.profile_visible_places(profile_id, status_filter, category_filter);
$$;

revoke all on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) from public, anon;
revoke all on function app.profile_visible_places(text, text[], text[]) from public, anon;
revoke all on function public.profile_visible_places(text, text[], text[]) from public, anon;

grant execute on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function public.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) to authenticated;
grant execute on function app.profile_visible_places(text, text[], text[]) to authenticated;
grant execute on function public.profile_visible_places(text, text[], text[]) to authenticated;

commit;
