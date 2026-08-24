begin;

-- Social map/profile rows keep the source person's memory content while
-- resolving taxonomy for the authenticated viewer. The source person's
-- category overrides and restaurant food type are never projected to others.
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
      own.id as user_place_id,
      place.id as place_id,
      own.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      place.canonical_name,
      global_default.primary_category,
      global_default.subcategory,
      global_default.category_source,
      global_default.category_confidence,
      place.raw_provider_type,
      place.latitude,
      place.longitude,
      own.status,
      own.visibility,
      own.note,
      own.visited_at,
      own.saved_at,
      own.created_at,
      own.updated_at,
      own.rating_signal,
      own.rating_score::double precision as rating_score,
      case when own.user_id = app.current_user_id() then own.category_override end as category_override,
      case when own.user_id = app.current_user_id() then own.subcategory_override end as subcategory_override,
      case when own.user_id = app.current_user_id() then own.category_override_source end as category_override_source,
      case when own.user_id = app.current_user_id() then own.category_override_confidence end as category_override_confidence,
      own.source_type,
      own.user_id = app.current_user_id() as is_self
    from public.user_places own
    join public.places place on place.id = own.place_id
    join public.profiles owner on owner.id = own.user_id
    cross join lateral app.global_place_taxonomy(place.id) global_default
    cross join lateral app.viewer_place_taxonomy(place.id) viewer_default
    where own.deleted_at is null
      and place.latitude between min_lat and max_lat
      and place.longitude between min_lng and max_lng
      and (status_filter is null or own.status = any(status_filter))
      and (category_filter is null or viewer_default.primary_category = any(category_filter))
      and (
        owner_scope is null
        or ('you' = any(owner_scope) and own.user_id = app.current_user_id())
        or ('following' = any(owner_scope) and own.user_id <> app.current_user_id() and app.follows(app.current_user_id(), own.user_id))
        or ('friends' = any(owner_scope) and own.user_id <> app.current_user_id() and app.is_mutual(app.current_user_id(), own.user_id))
        or ('social' = any(owner_scope) and own.user_id <> app.current_user_id())
      )
  ),
  rating_summary as (
    select
      rated.place_id,
      round(avg(rated.rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from public.user_places rated
    where rated.deleted_at is null
      and rated.status = 'been'
      and rated.rating_score is not null
      and rated.place_id in (select distinct place_id from visible_rows)
    group by rated.place_id
  )
  select
    visible.user_place_id,
    visible.place_id,
    visible.owner_user_id,
    visible.owner_handle,
    visible.owner_display_name,
    visible.owner_avatar_url,
    visible.canonical_name,
    visible.primary_category as category,
    visible.primary_category,
    visible.subcategory,
    visible.category_source,
    visible.category_confidence,
    visible.raw_provider_type,
    visible.latitude,
    visible.longitude,
    visible.status,
    visible.visibility,
    visible.note,
    visible.visited_at,
    visible.saved_at,
    visible.created_at,
    visible.updated_at,
    visible.rating_signal,
    visible.rating_score,
    summary.recommended_score,
    coalesce(summary.recommended_count, 0),
    visible.category_override,
    visible.subcategory_override,
    visible.category_override_source,
    visible.category_override_confidence,
    visible.source_type,
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
        ) order by attribute.created_at, attribute.id
      )
      from public.place_attributes attribute
      left join public.question_definitions definition on definition.id = attribute.question_definition_id
      where attribute.user_place_id = visible.user_place_id
        and (visible.is_self or attribute.question_key <> 'restaurant_cuisine')
    ), '[]'::jsonb) || app.viewer_taxonomy_projection_attributes(visible.place_id)
  from visible_rows visible
  left join rating_summary summary on summary.place_id = visible.place_id;
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
      own.id as user_place_id,
      place.id as place_id,
      own.user_id as owner_user_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      place.canonical_name,
      global_default.primary_category,
      global_default.subcategory,
      global_default.category_source,
      global_default.category_confidence,
      place.raw_provider_type,
      place.address,
      place.locality,
      place.region,
      place.country,
      place.latitude,
      place.longitude,
      own.status,
      own.visibility,
      own.note,
      own.visited_at,
      own.saved_at,
      own.created_at,
      own.updated_at,
      own.rating_signal,
      own.rating_score::double precision as rating_score,
      case when own.user_id = app.current_user_id() then own.category_override end as category_override,
      case when own.user_id = app.current_user_id() then own.subcategory_override end as subcategory_override,
      case when own.user_id = app.current_user_id() then own.category_override_source end as category_override_source,
      case when own.user_id = app.current_user_id() then own.category_override_confidence end as category_override_confidence,
      own.source_type,
      own.user_id = app.current_user_id() as is_self
    from public.user_places own
    join public.places place on place.id = own.place_id
    join public.profiles owner on owner.id = own.user_id
    cross join lateral app.global_place_taxonomy(place.id) global_default
    cross join lateral app.viewer_place_taxonomy(place.id) viewer_default
    where own.user_id = profile_id
      and own.deleted_at is null
      and owner.deleted_at is null
      and (status_filter is null or own.status = any(status_filter))
      and (category_filter is null or viewer_default.primary_category = any(category_filter))
  ),
  rating_summary as (
    select
      rated.place_id,
      round(avg(rated.rating_score)::numeric, 1)::double precision as recommended_score,
      count(*)::integer as recommended_count
    from public.user_places rated
    where rated.deleted_at is null
      and rated.status = 'been'
      and rated.rating_score is not null
      and rated.place_id in (select distinct place_id from visible_rows)
    group by rated.place_id
  )
  select
    visible.user_place_id,
    visible.place_id,
    visible.owner_user_id,
    visible.owner_handle,
    visible.owner_display_name,
    visible.owner_avatar_url,
    visible.canonical_name,
    visible.primary_category as category,
    visible.primary_category,
    visible.subcategory,
    visible.category_source,
    visible.category_confidence,
    visible.raw_provider_type,
    visible.address,
    visible.locality,
    visible.region,
    visible.country,
    visible.latitude,
    visible.longitude,
    visible.status,
    visible.visibility,
    visible.note,
    visible.visited_at,
    visible.saved_at,
    visible.created_at,
    visible.updated_at,
    visible.rating_signal,
    visible.rating_score,
    summary.recommended_score,
    coalesce(summary.recommended_count, 0),
    visible.category_override,
    visible.subcategory_override,
    visible.category_override_source,
    visible.category_override_confidence,
    visible.source_type,
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
        ) order by attribute.created_at, attribute.id
      )
      from public.place_attributes attribute
      left join public.question_definitions definition on definition.id = attribute.question_definition_id
      where attribute.user_place_id = visible.user_place_id
        and (visible.is_self or attribute.question_key <> 'restaurant_cuisine')
    ), '[]'::jsonb) || app.viewer_taxonomy_projection_attributes(visible.place_id)
  from visible_rows visible
  left join rating_summary summary on summary.place_id = visible.place_id
  order by visible.updated_at desc;
$$;

revoke all on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[])
  from public, anon;
revoke all on function app.profile_visible_places(text, text[], text[])
  from public, anon;
grant execute on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[])
  to authenticated;
grant execute on function app.profile_visible_places(text, text[], text[])
  to authenticated;

create or replace function public.featured_places_in_view(
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
      own.id as user_place_id,
      own.user_id as owner_user_id,
      own.place_id,
      owner.handle as owner_handle,
      owner.display_name as owner_display_name,
      owner.avatar_url as owner_avatar_url,
      place.canonical_name,
      global_default.primary_category,
      global_default.subcategory,
      global_default.category_source,
      global_default.category_confidence,
      place.raw_provider_type,
      place.address,
      place.locality,
      place.region,
      place.country,
      place.latitude,
      place.longitude,
      own.status,
      own.visibility,
      own.note,
      own.visited_at,
      own.saved_at,
      own.created_at,
      own.updated_at,
      own.rating_signal,
      own.rating_score::double precision as rating_score,
      case when own.user_id = viewer.id then own.category_override end as category_override,
      case when own.user_id = viewer.id then own.subcategory_override end as subcategory_override,
      case when own.user_id = viewer.id then own.category_override_source end as category_override_source,
      case when own.user_id = viewer.id then own.category_override_confidence end as category_override_confidence,
      own.source_type,
      own.user_id = viewer.id as is_self,
      app.can_read_user_place(viewer.id, own.user_id, own.visibility) as is_socially_visible
    from viewer
    join public.places place
      on place.latitude between min_lat and max_lat
     and place.longitude between min_lng and max_lng
    cross join lateral app.global_place_taxonomy(place.id) global_default
    join public.user_places own on own.place_id = place.id
    join public.profiles owner on owner.id = own.user_id
    where own.deleted_at is null
      and own.status = 'been'
      and owner.deleted_at is null
      and not app.is_blocked(viewer.id, own.user_id)
      and (
        app.can_read_user_place(viewer.id, own.user_id, own.visibility)
        or (own.visibility = 'followers' and not owner.is_private_profile)
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
    order by stats.includes_self desc, stats.includes_social desc,
      stats.community_save_count desc, stats.recommended_score desc nulls last,
      stats.latest_activity desc, stats.place_id
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
      social.primary_category as category,
      social.primary_category,
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
          ) order by attribute.created_at, attribute.id
        )
        from public.place_attributes attribute
        left join public.question_definitions definition on definition.id = attribute.question_definition_id
        where attribute.user_place_id = social.user_place_id
          and (social.is_self or attribute.question_key <> 'restaurant_cuisine')
      ), '[]'::jsonb) || app.viewer_taxonomy_projection_attributes(social.place_id) as attributes,
      stats.latest_activity as sort_activity,
      true as sort_social
    from social_rows social
    join ranked_places stats on stats.place_id = social.place_id

    union all

    select
      place.id,
      place.id,
      'recme_featured_community'::text,
      'recme'::text,
      'rec.me community'::text,
      null::text,
      place.canonical_name,
      global_default.primary_category,
      global_default.primary_category,
      global_default.subcategory,
      global_default.category_source,
      global_default.category_confidence,
      place.raw_provider_type,
      place.address,
      place.locality,
      place.region,
      place.country,
      null::text,
      place.latitude,
      place.longitude,
      'been'::text,
      'followers'::text,
      null::text,
      stats.latest_activity,
      stats.latest_activity,
      stats.latest_activity,
      stats.latest_activity,
      null::text,
      null::double precision,
      stats.recommended_score,
      stats.recommended_count,
      stats.community_save_count,
      null::text,
      null::text,
      null::text,
      null::double precision,
      'featured_community_aggregate'::text,
      app.viewer_taxonomy_projection_attributes(place.id),
      stats.latest_activity,
      false
    from ranked_places stats
    join public.places place on place.id = stats.place_id
    cross join lateral app.global_place_taxonomy(place.id) global_default
    where not exists (
      select 1 from social_rows social where social.place_id = stats.place_id
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
  order by result.community_save_count desc,
    result.recommended_score desc nulls last,
    result.sort_activity desc,
    result.sort_social desc,
    result.place_id,
    result.user_place_id;
$$;

revoke all on function public.featured_places_in_view(double precision, double precision, double precision, double precision)
  from public, anon;
grant execute on function public.featured_places_in_view(double precision, double precision, double precision, double precision)
  to authenticated;

create or replace function app.feed_place_projection(
  input_user_place_id uuid,
  input_visit_id uuid default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select jsonb_build_object(
    'user_place_id', source_place.id,
    'place_id', place.id,
    'owner_user_id', source_place.user_id,
    'owner_handle', owner.handle,
    'owner_display_name', owner.display_name,
    'owner_avatar_url', owner.avatar_url,
    'canonical_name', place.canonical_name,
    'category', global_default.primary_category,
    'primary_category', global_default.primary_category,
    'subcategory', global_default.subcategory,
    'category_source', global_default.category_source,
    'category_confidence', global_default.category_confidence,
    'raw_provider_type', place.raw_provider_type,
    'address', place.address,
    'locality', place.locality,
    'region', place.region,
    'country', place.country,
    'time_zone_identifier', null,
    'latitude', place.latitude,
    'longitude', place.longitude,
    'status', source_place.status,
    'visibility', source_place.visibility,
    'note', coalesce(source_visit.note, source_place.note),
    'visited_at', coalesce(source_visit.visited_at, source_place.visited_at),
    'saved_at', source_place.saved_at,
    'created_at', source_place.created_at,
    'updated_at', coalesce(source_visit.updated_at, source_place.updated_at),
    'rating_signal', source_place.rating_signal,
    'rating_score', coalesce(source_visit.rating_score, source_place.rating_score),
    'recommended_score', null,
    'recommended_count', 0,
    'category_override', case when source_place.user_id = app.current_user_id() then source_place.category_override end,
    'subcategory_override', case when source_place.user_id = app.current_user_id() then source_place.subcategory_override end,
    'category_override_source', case when source_place.user_id = app.current_user_id() then source_place.category_override_source end,
    'category_override_confidence', case when source_place.user_id = app.current_user_id() then source_place.category_override_confidence end,
    'source_type', source_place.source_type,
    'attributes', app.viewer_taxonomy_projection_attributes(place.id)
  )
  from public.user_places source_place
  join public.places place on place.id = source_place.place_id
  join public.profiles owner on owner.id = source_place.user_id
  cross join lateral app.global_place_taxonomy(place.id) global_default
  left join public.place_visits source_visit
    on source_visit.id = input_visit_id
   and source_visit.user_place_id = source_place.id
   and source_visit.deleted_at is null
  where source_place.id = input_user_place_id
    and source_place.deleted_at is null
    and (input_visit_id is null or source_visit.id is not null)
$$;

revoke all on function app.feed_place_projection(uuid, uuid)
  from public, anon, authenticated;

-- Search category filtering and returned defaults are viewer-aware, while the
-- underlying retrieval still uses minimized canonical place documents.
create or replace function app.eligible_recme_place_search(
  input_viewer_id text,
  input_categories text[],
  input_area text,
  input_favorite_only boolean,
  input_scope text
)
returns table (
  place_id uuid,
  affinity integer,
  average_rating double precision,
  latest_save timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with eligible_saves as (
    select
      place.id as place_id,
      user_place.saved_at,
      user_place.rating_score,
      user_place.status,
      case
        when user_place.user_id = input_viewer_id then 3
        when app.is_mutual(input_viewer_id, user_place.user_id) then 2
        when app.follows(input_viewer_id, user_place.user_id) then 1
        else 0
      end as affinity
    from public.places place
    cross join lateral app.viewer_place_taxonomy(place.id) viewer_default
    join public.user_places user_place on user_place.place_id = place.id
    join public.profiles owner_profile on owner_profile.id = user_place.user_id
    where place.source_provider_place_id is not null
      and trim(place.source_provider_place_id) <> ''
      and place.source_provider in ('mapkit', 'google_maps', 'google_places', 'google_maps_link', 'apple_maps')
      and viewer_default.primary_category in (
        'restaurants_food', 'coffee_tea_sweets', 'bars_nightlife',
        'outdoors_nature', 'things_to_do', 'shopping'
      )
      and (
        input_categories is null
        or cardinality(input_categories) = 0
        or viewer_default.primary_category = any(input_categories)
      )
      and (
        trim(coalesce(input_area, '')) = ''
        or concat_ws(' ', place.address, place.locality, place.region, place.country)
          ilike ('%' || left(trim(input_area), 100) || '%')
      )
      and user_place.deleted_at is null
      and user_place.visibility <> 'self'
      and owner_profile.deleted_at is null
      and not coalesce(owner_profile.is_private_profile, false)
      and not app.is_blocked(input_viewer_id, user_place.user_id)
      and case lower(trim(coalesce(input_scope, 'everyone')))
        when 'mine' then user_place.user_id = input_viewer_id
        when 'friends' then app.is_mutual(input_viewer_id, user_place.user_id)
        when 'following' then app.follows(input_viewer_id, user_place.user_id)
        else true
      end
  )
  select
    save.place_id,
    max(save.affinity)::integer,
    avg(save.rating_score) filter (
      where save.status = 'been' and save.rating_score is not null
    )::double precision,
    max(save.saved_at)
  from eligible_saves save
  group by save.place_id
  having not coalesce(input_favorite_only, false)
    or bool_or(save.status = 'been' and save.rating_score >= 4)
$$;

revoke all on function app.eligible_recme_place_search(text, text[], text, boolean, text)
  from public, anon, authenticated;

create or replace function public.search_recme_places(
  input_query text,
  input_categories text[],
  input_area text,
  input_favorite_only boolean,
  input_scope text,
  input_limit integer
)
returns table (
  id uuid,
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
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  confidence double precision
)
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '3s'
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_query text := left(trim(coalesce(input_query, '')), 160);
  normalized_scope text := lower(trim(coalesce(input_scope, 'everyone')));
  bounded_limit integer := least(greatest(coalesce(input_limit, 20), 1), 20);
  search_query tsquery;
begin
  if viewer_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if normalized_scope not in ('everyone', 'mine', 'friends', 'following') then
    raise exception 'invalid_search_scope' using errcode = '22023';
  end if;
  if normalized_query <> '' then search_query := websearch_to_tsquery('simple', normalized_query); end if;

  return query
  select
    place.id,
    place.canonical_name,
    viewer_default.primary_category,
    viewer_default.primary_category,
    viewer_default.subcategory,
    viewer_default.category_source,
    viewer_default.category_confidence,
    place.raw_provider_type,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    place.confidence
  from app.eligible_recme_place_search(
    viewer_id, input_categories, input_area, input_favorite_only, normalized_scope
  ) eligible
  join public.places place on place.id = eligible.place_id
  cross join lateral app.viewer_place_taxonomy(place.id) viewer_default
  where normalized_query = '' or place.discover_search_vector @@ search_query
  order by
    case when normalized_query = '' then 0::real else ts_rank_cd(place.discover_search_vector, search_query) end desc,
    eligible.affinity desc,
    eligible.average_rating desc nulls last,
    eligible.latest_save desc,
    place.id
  limit bounded_limit;
end;
$$;

create or replace function public.search_recme_places_semantic(
  input_embedding extensions.vector,
  input_categories text[],
  input_area text,
  input_favorite_only boolean,
  input_scope text,
  input_limit integer,
  input_min_similarity double precision
)
returns table (
  id uuid,
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
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  confidence double precision,
  semantic_similarity double precision
)
language plpgsql
stable
security definer
set search_path = ''
set statement_timeout = '3s'
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_scope text := lower(trim(coalesce(input_scope, 'everyone')));
  bounded_limit integer := least(greatest(coalesce(input_limit, 20), 1), 20);
  minimum_similarity double precision := least(greatest(coalesce(input_min_similarity, 0.35), -1), 1);
begin
  if viewer_id is null then raise exception 'authentication_required' using errcode = '42501'; end if;
  if normalized_scope not in ('everyone', 'mine', 'friends', 'following') then
    raise exception 'invalid_search_scope' using errcode = '22023';
  end if;
  if extensions.vector_dims(input_embedding) <> 1536 then
    raise exception 'invalid_embedding_dimensions' using errcode = '22023';
  end if;

  return query
  with scored as (
    select
      eligible.place_id,
      eligible.affinity,
      eligible.average_rating,
      eligible.latest_save,
      1 - (stored.embedding operator(extensions.<=>) input_embedding) as similarity
    from app.eligible_recme_place_search(
      viewer_id, input_categories, input_area, input_favorite_only, normalized_scope
    ) eligible
    join public.place_search_embeddings stored
      on stored.place_id = eligible.place_id
     and stored.model = 'text-embedding-3-small'
     and stored.dimensions = 1536
     and stored.document_version = 1
  )
  select
    place.id,
    place.canonical_name,
    viewer_default.primary_category,
    viewer_default.primary_category,
    viewer_default.subcategory,
    viewer_default.category_source,
    viewer_default.category_confidence,
    place.raw_provider_type,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    place.confidence,
    scored.similarity::double precision
  from scored
  join public.places place on place.id = scored.place_id
  cross join lateral app.viewer_place_taxonomy(place.id) viewer_default
  where scored.similarity >= minimum_similarity
  order by scored.similarity desc, scored.affinity desc,
    scored.average_rating desc nulls last, scored.latest_save desc, place.id
  limit bounded_limit;
end;
$$;

revoke all on function public.search_recme_places(text, text[], text, boolean, text, integer)
  from public, anon;
grant execute on function public.search_recme_places(text, text[], text, boolean, text, integer)
  to authenticated, service_role;
revoke all on function public.search_recme_places_semantic(extensions.vector, text[], text, boolean, text, integer, double precision)
  from public, anon;
grant execute on function public.search_recme_places_semantic(extensions.vector, text[], text, boolean, text, integer, double precision)
  to authenticated, service_role;

comment on function app.visible_places_in_view(double precision, double precision, double precision, double precision, text[], text[], text[]) is
  'Returns RLS-visible saves with global canonical taxonomy plus a private authenticated-viewer taxonomy envelope.';
comment on function app.profile_visible_places(text, text[], text[]) is
  'Returns an RLS-visible profile without exposing the profile owner''s private taxonomy choices to another viewer.';
comment on function public.featured_places_in_view(double precision, double precision, double precision, double precision) is
  'Returns Featured rows with private taxonomy removed and the authenticated viewer''s own frozen/default taxonomy projected.';
comment on function app.feed_place_projection(uuid, uuid) is
  'Projects a feed place without another user''s private category, subcategory, or food type.';

do $$
declare
  signature regprocedure;
begin
  foreach signature in array array[
    'app.visible_places_in_view(double precision,double precision,double precision,double precision,text[],text[],text[])'::regprocedure,
    'app.profile_visible_places(text,text[],text[])'::regprocedure
  ] loop
    if not exists (
      select 1 from pg_proc procedure
      where procedure.oid = signature
        and not procedure.prosecdef
        and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    ) then
      raise exception 'visible taxonomy RPC % security posture changed', signature;
    end if;
  end loop;

  if not exists (
    select 1 from pg_proc procedure
    where procedure.oid = 'public.featured_places_in_view(double precision,double precision,double precision,double precision)'::regprocedure
      and procedure.prosecdef
      and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
  ) then
    raise exception 'Featured taxonomy RPC security posture changed';
  end if;

  if has_function_privilege('anon', 'public.featured_places_in_view(double precision,double precision,double precision,double precision)', 'execute')
     or has_function_privilege('anon', 'public.search_recme_places(text,text[],text,boolean,text,integer)', 'execute')
     or has_function_privilege('anon', 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)', 'execute') then
    raise exception 'taxonomy read RPCs must remain authenticated-only';
  end if;
end;
$$;

commit;
