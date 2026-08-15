begin;

create index if not exists places_latitude_longitude_idx
  on public.places (latitude, longitude);

create function public.featured_places_in_view(
  min_lat double precision,
  min_lng double precision,
  max_lat double precision,
  max_lng double precision
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
  address text,
  locality text,
  region text,
  country text,
  time_zone_identifier text,
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
  community_save_count integer,
  category_override text,
  subcategory_override text,
  category_override_source text,
  category_override_confidence double precision,
  source_type text,
  attributes jsonb
)
language sql
stable
security definer
set search_path = public, app
set statement_timeout = '3s'
as $$
  with viewer as materialized (
    select profile.id
    from public.profiles profile
    where profile.id = app.current_user_id()
      and profile.deleted_at is null
  ),
  eligible_rows as materialized (
    select
      up.id as user_place_id,
      up.user_id as owner_user_id,
      up.place_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      p.canonical_name,
      p.category as legacy_category,
      p.primary_category,
      p.subcategory,
      p.category_source,
      p.category_confidence,
      p.raw_provider_type,
      p.address,
      p.locality,
      p.region,
      p.country,
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
      up.source_type,
      up.user_id = viewer.id as is_self,
      app.can_read_user_place(viewer.id, up.user_id, up.visibility) as is_socially_visible
    from viewer
    join public.places p
      on p.latitude between min_lat and max_lat
     and p.longitude between min_lng and max_lng
    join public.user_places up on up.place_id = p.id
    join public.profiles owner on owner.id = up.user_id
    where up.deleted_at is null
      and up.status = 'been'
      and owner.deleted_at is null
      and not app.is_blocked(viewer.id, up.user_id)
      and (
        app.can_read_user_place(viewer.id, up.user_id, up.visibility)
        or (
          up.visibility = 'followers'
          and not owner.is_private_profile
        )
      )
  ),
  place_stats as materialized (
    select
      eligible.place_id,
      count(distinct eligible.owner_user_id)::integer as community_save_count,
      round(avg(eligible.rating_score)::numeric, 1)::double precision as recommended_score,
      count(eligible.rating_score)::integer as recommended_count,
      bool_or(eligible.is_self) as includes_self,
      bool_or(eligible.is_socially_visible) as includes_social,
      max(coalesce(eligible.visited_at, eligible.saved_at, eligible.updated_at)) as latest_activity
    from eligible_rows eligible
    group by eligible.place_id
  ),
  ranked_places as materialized (
    select stats.*
    from place_stats stats
    order by
      stats.includes_self desc,
      stats.includes_social desc,
      stats.community_save_count desc,
      stats.recommended_score desc nulls last,
      stats.latest_activity desc,
      stats.place_id
    limit 120
  ),
  social_rows as materialized (
    select eligible.*
    from eligible_rows eligible
    join ranked_places ranked on ranked.place_id = eligible.place_id
    where eligible.is_socially_visible
  ),
  result_rows as (
    select
      social.user_place_id,
      social.place_id,
      social.owner_user_id,
      social.owner_handle,
      social.owner_display_name,
      social.owner_avatar_url,
      social.canonical_name,
      coalesce(social.category_override, social.primary_category, social.legacy_category) as category,
      coalesce(social.primary_category, social.legacy_category) as primary_category,
      social.subcategory,
      social.category_source,
      social.category_confidence,
      social.raw_provider_type,
      social.address,
      social.locality,
      social.region,
      social.country,
      null::text as time_zone_identifier,
      social.latitude,
      social.longitude,
      social.status,
      social.visibility,
      social.note,
      social.visited_at,
      social.saved_at,
      social.created_at,
      social.updated_at,
      social.rating_signal,
      social.rating_score,
      stats.recommended_score,
      stats.recommended_count,
      stats.community_save_count,
      social.category_override,
      social.subcategory_override,
      social.category_override_source,
      social.category_override_confidence,
      social.source_type,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'question_definition_id', attribute.question_definition_id,
            'question_key', attribute.question_key,
            'value_type', attribute.value_type,
            'value', attribute.value,
            'prompt', definition.prompt,
            'options', coalesce(definition.options, '[]'::jsonb),
            'is_system', coalesce(definition.is_system, false)
          )
          order by attribute.created_at, attribute.id
        )
        from public.place_attributes attribute
        left join public.question_definitions definition
          on definition.id = attribute.question_definition_id
        where attribute.user_place_id = social.user_place_id
      ), '[]'::jsonb) as attributes,
      stats.latest_activity as sort_activity,
      true as sort_social
    from social_rows social
    join ranked_places stats on stats.place_id = social.place_id

    union all

    select
      place.id as user_place_id,
      place.id as place_id,
      'recme_featured_community'::text as owner_user_id,
      'recme'::text as owner_handle,
      'rec.me community'::text as owner_display_name,
      null::text as owner_avatar_url,
      place.canonical_name,
      coalesce(place.primary_category, place.category) as category,
      coalesce(place.primary_category, place.category) as primary_category,
      place.subcategory,
      place.category_source,
      place.category_confidence,
      place.raw_provider_type,
      place.address,
      place.locality,
      place.region,
      place.country,
      null::text as time_zone_identifier,
      place.latitude,
      place.longitude,
      'been'::text as status,
      'followers'::text as visibility,
      null::text as note,
      stats.latest_activity as visited_at,
      stats.latest_activity as saved_at,
      stats.latest_activity as created_at,
      stats.latest_activity as updated_at,
      null::text as rating_signal,
      null::double precision as rating_score,
      stats.recommended_score,
      stats.recommended_count,
      stats.community_save_count,
      null::text as category_override,
      null::text as subcategory_override,
      null::text as category_override_source,
      null::double precision as category_override_confidence,
      'featured_community_aggregate'::text as source_type,
      '[]'::jsonb as attributes,
      stats.latest_activity as sort_activity,
      false as sort_social
    from ranked_places stats
    join public.places place on place.id = stats.place_id
    where not exists (
      select 1
      from social_rows social
      where social.place_id = stats.place_id
    )
  )
  select
    result.user_place_id,
    result.place_id,
    result.owner_user_id,
    result.owner_handle,
    result.owner_display_name,
    result.owner_avatar_url,
    result.canonical_name,
    result.category,
    result.primary_category,
    result.subcategory,
    result.category_source,
    result.category_confidence,
    result.raw_provider_type,
    result.address,
    result.locality,
    result.region,
    result.country,
    result.time_zone_identifier,
    result.latitude,
    result.longitude,
    result.status,
    result.visibility,
    result.note,
    result.visited_at,
    result.saved_at,
    result.created_at,
    result.updated_at,
    result.rating_signal,
    result.rating_score,
    result.recommended_score,
    result.recommended_count,
    result.community_save_count,
    result.category_override,
    result.subcategory_override,
    result.category_override_source,
    result.category_override_confidence,
    result.source_type,
    result.attributes
  from result_rows result
  order by
    result.community_save_count desc,
    result.recommended_score desc nulls last,
    result.sort_activity desc,
    result.sort_social desc,
    result.place_id,
    result.user_place_id;
$$;

comment on function public.featured_places_in_view(double precision, double precision, double precision, double precision) is
  'Returns at most 120 Featured-map place groups. Existing RLS-visible own/social rows retain detail; broader non-private Everyone check-ins contribute only anonymous place-level aggregates.';

revoke all on function public.featured_places_in_view(double precision, double precision, double precision, double precision) from public, anon;
grant execute on function public.featured_places_in_view(double precision, double precision, double precision, double precision) to authenticated;

commit;
