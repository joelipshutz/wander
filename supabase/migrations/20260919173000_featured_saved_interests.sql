begin;

-- REC-550: keep the existing authenticated-only SECURITY DEFINER projection,
-- return shape, visibility/block rules, 3s timeout and private taxonomy boundary.
-- Reserve at most half of 120 place groups for positive saved-interest matches;
-- remaining capacity retains the existing relationship/community discovery order.
create function app.featured_taste_subcategory(category text, subcategory text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when lower(trim(category)) = 'coffee_tea_sweets'
      and lower(trim(subcategory)) in ('coffee shop', 'cafe', 'café', 'coffee stand', 'coffee lounge', 'roastery')
      then 'coffee'
    else nullif(lower(trim(subcategory)), '')
  end
$$;
revoke all on function app.featured_taste_subcategory(text,text) from public, anon, authenticated;

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
  -- Taste belongs only to the authenticated viewer, including private saves.
  -- Reuse their frozen/overridden taxonomy; never read another owner's choices.
  liked_taxonomy as materialized (
    select lower(trim(taxonomy.primary_category)) as category,
      app.featured_taste_subcategory(taxonomy.primary_category, taxonomy.subcategory) as subcategory
    from viewer
    join public.user_places own on own.user_id = viewer.id
    cross join lateral app.viewer_place_taxonomy(own.place_id) taxonomy
    where own.deleted_at is null
      and (own.status = 'wanna_go' or (own.status = 'been' and own.rating_score >= 4))
  ),
  taste_total as (select count(*)::double precision as count from liked_taxonomy),
  category_taste as (
    select category, count(*)::double precision as count from liked_taxonomy group by category
  ),
  subcategory_taste as (
    select category, subcategory, count(*)::double precision as count
    from liked_taxonomy where subcategory is not null group by category, subcategory
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
  place_taste as materialized (
    select stats.*,
      case when category.count > 0 then 1.1 * least(1, 0.35 + category.count / total.count) else 0 end
        + case when subtype.count > 0 then 3.0 * least(1, 0.35 + subtype.count / total.count) else 0 end as taste_score
    from place_stats stats
    cross join lateral app.viewer_place_taxonomy(stats.place_id) taxonomy
    cross join taste_total total
    left join category_taste category on category.category = lower(trim(taxonomy.primary_category))
    left join subcategory_taste subtype
      on subtype.category = lower(trim(taxonomy.primary_category))
     and subtype.subcategory = app.featured_taste_subcategory(taxonomy.primary_category, taxonomy.subcategory)
  ),
  taste_places as materialized (
    select * from place_taste
    where taste_score > 0
    order by taste_score desc, includes_self desc, includes_social desc,
      community_save_count desc, recommended_score desc nulls last, latest_activity desc, place_id
    limit 60
  ),
  ranked_places as materialized (
    select * from taste_places
    union all
    (select stats.* from place_taste stats
      where not exists(select 1 from taste_places taste where taste.place_id = stats.place_id)
      order by stats.includes_self desc, stats.includes_social desc,
        stats.community_save_count desc, stats.recommended_score desc nulls last,
        stats.latest_activity desc, stats.place_id
      limit (120 - (select count(*) from taste_places)))
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
          and (
            attribute.question_key <> 'restaurant_cuisine'
            or (
              social.is_self
              and (
                social.source_type is distinct from 'social_save'
                or attribute.taxonomy_is_personal is true
              )
            )
          )
      ), '[]'::jsonb) || app.viewer_taxonomy_projection_attributes(social.place_id) as attributes,
      stats.latest_activity as sort_activity,
      stats.taste_score as sort_taste,
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
      stats.taste_score,
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
  order by result.sort_taste desc, result.community_save_count desc,
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

comment on function public.featured_places_in_view(double precision,double precision,double precision,double precision) is
  'At most 120 privacy-eligible Featured groups: up to 60 saved-interest matches plus social/community discovery. Viewer taste stays private; no fabricated visits.';

commit;
