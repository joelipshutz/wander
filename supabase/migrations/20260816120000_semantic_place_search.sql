begin;

-- REC-280: Search-only semantic candidates over minimized canonical place
-- facts. User memories and people never enter this table or its documents.
create extension if not exists vector with schema extensions;

create table public.place_search_embeddings (
  place_id uuid primary key references public.places(id) on delete cascade,
  model text not null,
  dimensions integer not null check (dimensions = 1536),
  document_version integer not null check (document_version > 0),
  document_hash text not null check (document_hash ~ '^[0-9a-f]{64}$'),
  embedding extensions.vector(1536) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.place_search_embeddings enable row level security;
revoke all privileges on table public.place_search_embeddings from public, anon, authenticated;
grant select, insert, update, delete on table public.place_search_embeddings to service_role;

create trigger place_search_embeddings_updated_at
  before update on public.place_search_embeddings
  for each row execute function app.set_updated_at();

create or replace function app.canonical_place_embedding_document(
  input_name text,
  input_category text,
  input_subcategory text,
  input_locality text,
  input_region text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select concat_ws(
    ' | ',
    nullif(trim(coalesce(input_name, '')), ''),
    nullif(trim(coalesce(input_category, '')), ''),
    nullif(trim(coalesce(input_subcategory, '')), ''),
    nullif(trim(coalesce(input_locality, '')), ''),
    nullif(trim(coalesce(input_region, '')), '')
  );
$$;

revoke all on function app.canonical_place_embedding_document(text, text, text, text, text)
  from public, anon, authenticated;

-- One shared eligibility function keeps lexical and semantic retrieval from
-- drifting on privacy, social scope, favorite, category, or area semantics.
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
    from public.places as place
    join public.user_places as user_place
      on user_place.place_id = place.id
    join public.profiles as owner_profile
      on owner_profile.id = user_place.user_id
    where place.source_provider_place_id is not null
      and trim(place.source_provider_place_id) <> ''
      and place.source_provider in (
        'mapkit', 'google_maps', 'google_places', 'google_maps_link', 'apple_maps'
      )
      and coalesce(place.primary_category, place.category) in (
        'restaurants_food',
        'coffee_tea_sweets',
        'bars_nightlife',
        'outdoors_nature',
        'things_to_do',
        'shopping'
      )
      and (
        input_categories is null
        or cardinality(input_categories) = 0
        or coalesce(place.primary_category, place.category) = any(input_categories)
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
    max(save.affinity)::integer as affinity,
    avg(save.rating_score) filter (
      where save.status = 'been' and save.rating_score is not null
    )::double precision as average_rating,
    max(save.saved_at) as latest_save
  from eligible_saves as save
  group by save.place_id
  having not coalesce(input_favorite_only, false)
    or bool_or(save.status = 'been' and save.rating_score >= 4);
$$;

revoke all on function app.eligible_recme_place_search(text, text[], text, boolean, text)
  from public, anon, authenticated;

-- Preserve the existing public lexical contract while routing its eligibility
-- through the shared helper used by semantic retrieval.
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
  from app.eligible_recme_place_search(
    viewer_id,
    input_categories,
    input_area,
    input_favorite_only,
    normalized_scope
  ) as eligible
  join public.places as place
    on place.id = eligible.place_id
  where normalized_query = ''
    or place.discover_search_vector @@ search_query
  order by
    case
      when normalized_query = '' then 0::real
      else ts_rank_cd(place.discover_search_vector, search_query)
    end desc,
    eligible.affinity desc,
    eligible.average_rating desc nulls last,
    eligible.latest_save desc,
    place.id
  limit bounded_limit;
end;
$$;

revoke all on function public.search_recme_places(text, text[], text, boolean, text, integer)
  from public, anon;
grant execute on function public.search_recme_places(text, text[], text, boolean, text, integer)
  to authenticated, service_role;

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
  minimum_similarity double precision := least(
    greatest(coalesce(input_min_similarity, 0.35), -1),
    1
  );
begin
  if viewer_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

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
      viewer_id,
      input_categories,
      input_area,
      input_favorite_only,
      normalized_scope
    ) as eligible
    join public.place_search_embeddings as stored
      on stored.place_id = eligible.place_id
     and stored.model = 'text-embedding-3-small'
     and stored.dimensions = 1536
     and stored.document_version = 1
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
    place.confidence,
    scored.similarity::double precision
  from scored
  join public.places as place
    on place.id = scored.place_id
  where scored.similarity >= minimum_similarity
  order by
    scored.similarity desc,
    scored.affinity desc,
    scored.average_rating desc nulls last,
    scored.latest_save desc,
    place.id
  limit bounded_limit;
end;
$$;

revoke all on function public.search_recme_places_semantic(extensions.vector, text[], text, boolean, text, integer, double precision)
  from public, anon;
grant execute on function public.search_recme_places_semantic(extensions.vector, text[], text, boolean, text, integer, double precision)
  to authenticated, service_role;

comment on function public.search_recme_places_semantic(extensions.vector, text[], text, boolean, text, integer, double precision) is
  'Returns canonical venue facts from Search-only semantic candidates after the same privacy and hard-filter eligibility used by lexical rec.me search.';

-- The worker can request only missing or stale canonical documents. It never
-- receives saves, users, notes, answers, labels, ratings, photos, or coordinates.
create or replace function public.semantic_place_embedding_backfill_batch(
  input_model text,
  input_document_version integer,
  input_limit integer
)
returns table (
  place_id uuid,
  document text,
  document_hash text
)
language sql
stable
security definer
set search_path = ''
set statement_timeout = '3s'
as $$
  with candidates as (
    select
      place.id as place_id,
      app.canonical_place_embedding_document(
        place.canonical_name,
        coalesce(place.primary_category, place.category),
        place.subcategory,
        place.locality,
        place.region
      ) as document,
      place.updated_at
    from public.places as place
    where place.source_provider_place_id is not null
      and trim(place.source_provider_place_id) <> ''
      and place.source_provider in (
        'mapkit', 'google_maps', 'google_places', 'google_maps_link', 'apple_maps'
      )
      and coalesce(place.primary_category, place.category) in (
        'restaurants_food',
        'coffee_tea_sweets',
        'bars_nightlife',
        'outdoors_nature',
        'things_to_do',
        'shopping'
      )
      and exists (
        select 1
        from public.user_places as user_place
        join public.profiles as owner_profile
          on owner_profile.id = user_place.user_id
        where user_place.place_id = place.id
          and user_place.deleted_at is null
          and user_place.visibility <> 'self'
          and owner_profile.deleted_at is null
          and not coalesce(owner_profile.is_private_profile, false)
      )
  ), versioned as (
    select
      candidate.place_id,
      candidate.document,
      encode(
        extensions.digest(
          coalesce(input_model, '') || E'\n' ||
          coalesce(input_document_version, 0)::text || E'\n' ||
          candidate.document,
          'sha256'
        ),
        'hex'
      ) as document_hash,
      candidate.updated_at
    from candidates as candidate
  )
  select versioned.place_id, versioned.document, versioned.document_hash
  from versioned
  left join public.place_search_embeddings as stored
    on stored.place_id = versioned.place_id
  where stored.place_id is null
     or stored.model <> input_model
     or stored.document_version <> input_document_version
     or stored.document_hash <> versioned.document_hash
  order by
    case
      when stored.place_id is not null
       and (stored.model <> input_model or stored.document_version <> input_document_version)
        then 0
      when stored.place_id is null then 1
      else 2
    end,
    versioned.updated_at,
    versioned.place_id
  limit least(greatest(coalesce(input_limit, 50), 1), 100);
$$;

revoke all on function public.semantic_place_embedding_backfill_batch(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.semantic_place_embedding_backfill_batch(text, integer, integer)
  to service_role;

insert into public.feature_flags(key, user_id, enabled)
values ('semantic_place_search_v1', null, false)
on conflict (key) where user_id is null
do update set enabled = excluded.enabled;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'recme-semantic-place-embedding-refresh',
  '*/10 * * * *',
  $schedule$
    with worker_config as (
      select
        max(decrypted_secret) filter (where name = 'recme_project_url') as project_url,
        max(decrypted_secret) filter (where name = 'recme_push_worker_secret') as worker_secret
      from vault.decrypted_secrets
    )
    select net.http_post(
      url := trim(trailing '/' from project_url) || '/functions/v1/refresh-place-embeddings',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wander-worker-secret', worker_secret
      ),
      body := '{"limit":50}'::jsonb,
      timeout_milliseconds := 30000
    ) as request_id
    from worker_config
    where project_url is not null
      and worker_secret is not null
  $schedule$
);

commit;
