begin;

-- REC-225: privacy-safe Discover search over canonical places contributed by rec.me saves.

alter table public.places
  add column if not exists discover_search_vector tsvector
  generated always as (
    setweight(to_tsvector('simple', coalesce(canonical_name, '')), 'A') ||
    setweight(to_tsvector('simple', coalesce(primary_category, category, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(subcategory, '')), 'B') ||
    setweight(to_tsvector('simple', coalesce(raw_provider_type, '')), 'C') ||
    setweight(
      to_tsvector(
        'simple',
        coalesce(address, '') || ' ' || coalesce(locality, '') || ' ' ||
        coalesce(region, '') || ' ' || coalesce(country, '')
      ),
      'C'
    )
  ) stored;

create index if not exists places_discover_search_vector_idx
  on public.places using gin (discover_search_vector);

create index if not exists places_discover_primary_category_idx
  on public.places (primary_category)
  where source_provider_place_id is not null;

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
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_query text := left(trim(coalesce(input_query, '')), 160);
  normalized_area text := left(trim(coalesce(input_area, '')), 100);
  normalized_scope text := lower(trim(coalesce(input_scope, 'everyone')));
  bounded_limit integer := least(greatest(coalesce(input_limit, 20), 1), 20);
  search_query tsquery;
begin
  if viewer_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  if normalized_scope not in ('everyone', 'mine', 'friends', 'following') then
    raise exception 'invalid_search_scope' using errcode = '22023';
  end if;

  if normalized_query <> '' then
    search_query := websearch_to_tsquery('simple', normalized_query);
  end if;

  return query
  with filtered_places as (
    select
      place.*,
      case
        when normalized_query = '' then 0::real
        else ts_rank_cd(place.discover_search_vector, search_query)
      end as lexical_rank
    from public.places as place
    where place.source_provider_place_id is not null
      and trim(place.source_provider_place_id) <> ''
      and place.source_provider in ('mapkit', 'google_maps', 'google_places', 'google_maps_link', 'apple_maps')
      and coalesce(place.primary_category, place.category) in (
        'restaurants_food',
        'coffee_tea_sweets',
        'bars_nightlife',
        'outdoors_nature',
        'things_to_do',
        'shopping'
      )
      and (
        normalized_query = ''
        or place.discover_search_vector @@ search_query
      )
      and (
        input_categories is null
        or cardinality(input_categories) = 0
        or coalesce(place.primary_category, place.category) = any(input_categories)
      )
      and (
        normalized_area = ''
        or concat_ws(' ', place.address, place.locality, place.region, place.country) ilike ('%' || normalized_area || '%')
      )
  ), eligible_saves as (
    select
      place.id as place_id,
      place.lexical_rank,
      user_place.saved_at,
      user_place.rating_score,
      user_place.status,
      case
        when user_place.user_id = viewer_id then 3
        when app.is_mutual(viewer_id, user_place.user_id) then 2
        when app.follows(viewer_id, user_place.user_id) then 1
        else 0
      end as affinity
    from filtered_places as place
    join public.user_places as user_place
      on user_place.place_id = place.id
    join public.profiles as owner_profile
      on owner_profile.id = user_place.user_id
    where user_place.deleted_at is null
      and user_place.visibility <> 'self'
      and owner_profile.deleted_at is null
      and not coalesce(owner_profile.is_private_profile, false)
      and not app.is_blocked(viewer_id, user_place.user_id)
      and case normalized_scope
        when 'mine' then user_place.user_id = viewer_id
        when 'friends' then app.is_mutual(viewer_id, user_place.user_id)
        when 'following' then app.follows(viewer_id, user_place.user_id)
        else true
      end
  ), ranked_places as (
    select
      save.place_id,
      max(save.lexical_rank) as lexical_rank,
      max(save.affinity) as affinity,
      avg(save.rating_score) filter (where save.status = 'been' and save.rating_score is not null) as average_rating,
      bool_or(save.status = 'been' and save.rating_score >= 4) as has_favorite_signal,
      max(save.saved_at) as latest_save
    from eligible_saves as save
    group by save.place_id
  )
  select
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.category_source,
    place.category_confidence,
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
  from ranked_places as ranked
  join public.places as place
    on place.id = ranked.place_id
  where not coalesce(input_favorite_only, false)
     or ranked.has_favorite_signal
  order by
    ranked.lexical_rank desc,
    ranked.affinity desc,
    ranked.average_rating desc nulls last,
    ranked.latest_save desc,
    place.id
  limit bounded_limit;
end;
$$;

revoke all on function public.search_recme_places(text, text[], text, boolean, text, integer)
  from public, anon;
grant execute on function public.search_recme_places(text, text[], text, boolean, text, integer)
  to authenticated, service_role;

comment on function public.search_recme_places(text, text[], text, boolean, text, integer) is
  'Returns canonical public venue facts contributed by privacy-eligible rec.me saves; never returns save or owner details.';

commit;
