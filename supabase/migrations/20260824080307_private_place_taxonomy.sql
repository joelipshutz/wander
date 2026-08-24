begin;

-- REC-362 keeps provider taxonomy canonical, freezes the effective default for
-- people who already relate to a place, and promotes only anonymous aggregate
-- plurality results after ten distinct selections for a taxonomy dimension.
alter table public.places
  add column if not exists provider_food_type text,
  add column if not exists consensus_primary_category text,
  add column if not exists consensus_subcategory text,
  add column if not exists consensus_food_type text,
  add column if not exists category_voter_count integer not null default 0,
  add column if not exists subcategory_voter_count integer not null default 0,
  add column if not exists food_type_voter_count integer not null default 0;

alter table public.places
  drop constraint if exists places_taxonomy_voter_counts_nonnegative;
alter table public.places
  add constraint places_taxonomy_voter_counts_nonnegative
  check (
    category_voter_count >= 0
    and subcategory_voter_count >= 0
    and food_type_voter_count >= 0
  );

create table public.place_taxonomy_snapshots (
  user_id text not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  primary_category text not null,
  subcategory text,
  food_type text,
  captured_for text not null check (captured_for in ('save', 'check_in', 'list', 'backfill')),
  captured_at timestamptz not null default now(),
  primary key (user_id, place_id)
);

create index place_taxonomy_snapshots_place_idx
  on public.place_taxonomy_snapshots (place_id, user_id);

alter table public.place_taxonomy_snapshots enable row level security;
revoke all on table public.place_taxonomy_snapshots from public, anon, authenticated;

comment on table public.place_taxonomy_snapshots is
  'Private first-relation taxonomy defaults. Rows are server-managed and never exposed as another person''s save metadata.';

create index if not exists user_places_category_vote_idx
  on public.user_places (place_id, category_override, user_id)
  where deleted_at is null
    and category_override is not null
    and category_override_source = 'user';

create index if not exists user_places_subcategory_vote_idx
  on public.user_places (place_id, subcategory_override, user_id)
  where deleted_at is null
    and subcategory_override is not null
    and category_override_source = 'user';

create index if not exists place_attributes_food_type_vote_idx
  on public.place_attributes (question_key, user_place_id)
  where question_key = 'restaurant_cuisine';

-- Rows written before REC-362 have no provenance. A null marker remains valid
-- for ordinary saves, while legacy social-save cuisine is treated as copied
-- and hidden until that recipient explicitly writes their own value.
alter table public.place_attributes
  add column if not exists taxonomy_is_personal boolean;

comment on column public.place_attributes.taxonomy_is_personal is
  'True when restaurant_cuisine was inserted or changed after private taxonomy enforcement; null legacy social-save values are never projected or counted.';

create or replace function app.mark_personal_taxonomy_write()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if new.question_key = 'restaurant_cuisine' then
    new.taxonomy_is_personal := true;
  end if;
  return new;
end;
$$;

revoke all on function app.mark_personal_taxonomy_write()
  from public, anon, authenticated;

drop trigger if exists place_attributes_mark_personal_taxonomy on public.place_attributes;
create trigger place_attributes_mark_personal_taxonomy
  before insert or update of value
  on public.place_attributes
  for each row execute function app.mark_personal_taxonomy_write();

create or replace function app.taxonomy_food_type_value(input_value jsonb)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(trim(case jsonb_typeof(input_value)
    when 'string' then input_value #>> '{}'
    when 'array' then input_value ->> 0
    else null
  end), '')
$$;

revoke all on function app.taxonomy_food_type_value(jsonb)
  from public, anon, authenticated;

create or replace function app.global_place_taxonomy(input_place_id uuid)
returns table (
  primary_category text,
  subcategory text,
  food_type text,
  category_source text,
  category_confidence double precision
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    coalesce(place.consensus_primary_category, place.primary_category, place.category, 'place'),
    coalesce(place.consensus_subcategory, place.subcategory),
    coalesce(place.consensus_food_type, place.provider_food_type),
    case
      when place.consensus_primary_category is not null
        or place.consensus_subcategory is not null then 'consensus'
      else place.category_source
    end,
    case
      when place.consensus_primary_category is not null
        or place.consensus_subcategory is not null then 1::double precision
      else place.category_confidence
    end
  from public.places place
  where place.id = input_place_id
$$;

create or replace function app.viewer_place_taxonomy(input_place_id uuid)
returns table (
  primary_category text,
  subcategory text,
  food_type text,
  category_source text,
  category_confidence double precision,
  is_frozen boolean
)
language sql
stable
security definer
set search_path = public, app
as $$
  with viewer as (
    select app.current_user_id() as id
  ),
  own_place as (
    select own.*
    from viewer
    join public.user_places own
      on own.user_id = viewer.id
     and own.place_id = input_place_id
     and own.deleted_at is null
  ),
  own_food_type as (
    select app.taxonomy_food_type_value(attribute.value) as value
    from own_place
    join public.place_attributes attribute on attribute.user_place_id = own_place.id
    where attribute.question_key = 'restaurant_cuisine'
      and (
        own_place.source_type is distinct from 'social_save'
        or attribute.taxonomy_is_personal is true
      )
    limit 1
  ),
  snapshot as (
    select stored.*
    from viewer
    join public.place_taxonomy_snapshots stored
      on stored.user_id = viewer.id
     and stored.place_id = input_place_id
  ),
  global_default as (
    select * from app.global_place_taxonomy(input_place_id)
  )
  select
    coalesce(own_place.category_override, snapshot.primary_category, global_default.primary_category),
    case
      when own_place.category_override is not null then own_place.subcategory_override
      when snapshot.primary_category is not null then snapshot.subcategory
      else global_default.subcategory
    end,
    case
      when own_food_type.value is not null then own_food_type.value
      when snapshot.primary_category is not null then snapshot.food_type
      else global_default.food_type
    end,
    case
      when own_place.category_override is not null then 'user'
      when snapshot.primary_category is not null then 'snapshot'
      else global_default.category_source
    end,
    case
      when own_place.category_override is not null or snapshot.primary_category is not null then 1::double precision
      else global_default.category_confidence
    end,
    snapshot.primary_category is not null
  from global_default
  left join own_place on true
  left join own_food_type on true
  left join snapshot on true
$$;

revoke all on function app.global_place_taxonomy(uuid) from public, anon;
revoke all on function app.viewer_place_taxonomy(uuid) from public, anon;
grant execute on function app.global_place_taxonomy(uuid) to authenticated, service_role;
grant execute on function app.viewer_place_taxonomy(uuid) to authenticated, service_role;

create or replace function app.viewer_taxonomy_projection_attributes(input_place_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(jsonb_agg(attribute order by attribute->>'question_key'), '[]'::jsonb)
  from app.viewer_place_taxonomy(input_place_id) taxonomy
  cross join lateral (
    select jsonb_build_object(
      'question_definition_id', null,
      'question_key', candidate.question_key,
      'value_type', 'text',
      'value', to_jsonb(candidate.value),
      'prompt', null,
      'options', '[]'::jsonb,
      'is_system', true
    ) as attribute
    from (values
      ('__viewer_taxonomy_primary_category', case when taxonomy.is_frozen then taxonomy.primary_category else null end),
      ('__viewer_taxonomy_subcategory', case when taxonomy.is_frozen then taxonomy.subcategory else null end),
      ('__viewer_taxonomy_food_type', taxonomy.food_type)
    ) candidate(question_key, value)
    where candidate.value is not null
  ) projected
$$;

revoke all on function app.viewer_taxonomy_projection_attributes(uuid) from public, anon;
grant execute on function app.viewer_taxonomy_projection_attributes(uuid)
  to authenticated, service_role;

create or replace function app.capture_place_taxonomy_snapshot(
  input_user_id text,
  input_place_id uuid,
  input_captured_for text
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if input_user_id is null or input_place_id is null then
    return;
  end if;

  insert into public.place_taxonomy_snapshots (
    user_id,
    place_id,
    primary_category,
    subcategory,
    food_type,
    captured_for
  )
  select
    input_user_id,
    input_place_id,
    taxonomy.primary_category,
    taxonomy.subcategory,
    taxonomy.food_type,
    case
      when input_captured_for in ('save', 'check_in', 'list', 'backfill') then input_captured_for
      else 'save'
    end
  from app.global_place_taxonomy(input_place_id) taxonomy
  on conflict (user_id, place_id) do nothing;
end;
$$;

create or replace function app.remove_unused_place_taxonomy_snapshot(
  input_user_id text,
  input_place_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if input_user_id is null or input_place_id is null then
    return;
  end if;

  if not exists (
    select 1
    from public.user_places own
    where own.user_id = input_user_id
      and own.place_id = input_place_id
      and own.deleted_at is null
  ) and not exists (
    select 1
    from public.place_list_items item
    where item.added_by_user_id = input_user_id
      and item.place_id = input_place_id
      and item.deleted_at is null
  ) then
    delete from public.place_taxonomy_snapshots stored
    where stored.user_id = input_user_id
      and stored.place_id = input_place_id;
  end if;
end;
$$;

revoke all on function app.capture_place_taxonomy_snapshot(text, uuid, text)
  from public, anon, authenticated;
revoke all on function app.remove_unused_place_taxonomy_snapshot(text, uuid)
  from public, anon, authenticated;

create or replace function app.recompute_place_taxonomy_consensus(input_place_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  provider_category text;
  provider_subcategory text;
  provider_food_type text;
  category_voters integer := 0;
  subcategory_voters integer := 0;
  food_type_voters integer := 0;
  category_winner text;
  subcategory_winner text;
  food_type_winner text;
begin
  select
    coalesce(place.primary_category, place.category, 'place'),
    place.subcategory,
    place.provider_food_type
  into provider_category, provider_subcategory, provider_food_type
  from public.places place
  where place.id = input_place_id
  -- Serialize each place before tallying so concurrent votes cannot publish a
  -- stale last-writer-wins consensus cache.
  for update of place;

  if provider_category is null then
    return;
  end if;

  select count(distinct vote.user_id)::integer
  into category_voters
  from public.user_places vote
  where vote.place_id = input_place_id
    and vote.deleted_at is null
    and vote.category_override is not null
    and vote.category_override_source = 'user';

  select candidate.value
  into category_winner
  from (
    select min(vote.category_override) as value, count(distinct vote.user_id) as votes
    from public.user_places vote
    where vote.place_id = input_place_id
      and vote.deleted_at is null
      and vote.category_override is not null
      and vote.category_override_source = 'user'
    group by lower(trim(vote.category_override))
  ) candidate
  order by
    candidate.votes desc,
    case when lower(trim(candidate.value)) = lower(trim(provider_category)) then 0 else 1 end,
    lower(candidate.value),
    candidate.value
  limit 1;

  select count(distinct vote.user_id)::integer
  into subcategory_voters
  from public.user_places vote
  where vote.place_id = input_place_id
    and vote.deleted_at is null
    and vote.subcategory_override is not null
    and vote.category_override_source = 'user';

  select candidate.value
  into subcategory_winner
  from (
    select min(vote.subcategory_override) as value, count(distinct vote.user_id) as votes
    from public.user_places vote
    where vote.place_id = input_place_id
      and vote.deleted_at is null
      and vote.subcategory_override is not null
      and vote.category_override_source = 'user'
    group by lower(trim(vote.subcategory_override))
  ) candidate
  order by
    candidate.votes desc,
    case when lower(trim(candidate.value)) = lower(trim(coalesce(provider_subcategory, ''))) then 0 else 1 end,
    lower(candidate.value),
    candidate.value
  limit 1;

  with food_votes as (
    select
      own.user_id,
      app.taxonomy_food_type_value(attribute.value) as value
    from public.place_attributes attribute
    join public.user_places own on own.id = attribute.user_place_id
    where own.place_id = input_place_id
      and own.deleted_at is null
      and attribute.question_key = 'restaurant_cuisine'
      and (
        own.source_type is distinct from 'social_save'
        or attribute.taxonomy_is_personal is true
      )
  )
  select count(distinct vote.user_id)::integer
  into food_type_voters
  from food_votes vote
  where vote.value is not null;

  with food_votes as (
    select
      own.user_id,
      app.taxonomy_food_type_value(attribute.value) as value
    from public.place_attributes attribute
    join public.user_places own on own.id = attribute.user_place_id
    where own.place_id = input_place_id
      and own.deleted_at is null
      and attribute.question_key = 'restaurant_cuisine'
      and (
        own.source_type is distinct from 'social_save'
        or attribute.taxonomy_is_personal is true
      )
  )
  select candidate.value
  into food_type_winner
  from (
    select min(vote.value) as value, count(distinct vote.user_id) as votes
    from food_votes vote
    where vote.value is not null
    group by lower(trim(vote.value))
  ) candidate
  order by
    candidate.votes desc,
    case when lower(trim(candidate.value)) = lower(trim(coalesce(provider_food_type, ''))) then 0 else 1 end,
    lower(candidate.value),
    candidate.value
  limit 1;

  update public.places place
  set
    consensus_primary_category = case when category_voters >= 10 then category_winner else null end,
    consensus_subcategory = case when subcategory_voters >= 10 then subcategory_winner else null end,
    consensus_food_type = case when food_type_voters >= 10 then food_type_winner else null end,
    category_voter_count = category_voters,
    subcategory_voter_count = subcategory_voters,
    food_type_voter_count = food_type_voters
  where place.id = input_place_id;
end;
$$;

revoke all on function app.recompute_place_taxonomy_consensus(uuid)
  from public, anon, authenticated;

create or replace function app.user_place_taxonomy_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  affected_place_id uuid := coalesce(new.place_id, old.place_id);
  affected_user_id text := coalesce(new.user_id, old.user_id);
begin
  if tg_op <> 'DELETE' and new.deleted_at is null then
    perform app.capture_place_taxonomy_snapshot(
      new.user_id,
      new.place_id,
      case when new.status = 'been' then 'check_in' else 'save' end
    );
  end if;

  perform app.recompute_place_taxonomy_consensus(affected_place_id);
  perform app.remove_unused_place_taxonomy_snapshot(affected_user_id, affected_place_id);
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function app.place_attribute_taxonomy_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  old_place_id uuid;
  new_place_id uuid;
begin
  if tg_op <> 'INSERT' and old.question_key = 'restaurant_cuisine' then
    select own.place_id into old_place_id
    from public.user_places own where own.id = old.user_place_id;
  end if;

  if tg_op <> 'DELETE' and new.question_key = 'restaurant_cuisine' then
    select own.place_id into new_place_id
    from public.user_places own where own.id = new.user_place_id;
  end if;

  if old_place_id is not null then
    perform app.recompute_place_taxonomy_consensus(old_place_id);
  end if;
  if new_place_id is not null and new_place_id is distinct from old_place_id then
    perform app.recompute_place_taxonomy_consensus(new_place_id);
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function app.place_list_item_taxonomy_maintenance()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if tg_op <> 'DELETE' and new.deleted_at is null then
    perform app.capture_place_taxonomy_snapshot(new.added_by_user_id, new.place_id, 'list');
  end if;

  if tg_op <> 'INSERT' then
    perform app.remove_unused_place_taxonomy_snapshot(old.added_by_user_id, old.place_id);
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function app.user_place_taxonomy_maintenance()
  from public, anon, authenticated;
revoke all on function app.place_attribute_taxonomy_maintenance()
  from public, anon, authenticated;
revoke all on function app.place_list_item_taxonomy_maintenance()
  from public, anon, authenticated;

update public.places place
set provider_food_type = app.restaurant_cuisine_guess(
  place.raw_provider_type,
  place.subcategory,
  coalesce(place.primary_category, place.category),
  place.canonical_name,
  null
)
where coalesce(place.primary_category, place.category) = 'restaurants_food'
  and place.provider_food_type is null;

insert into public.place_taxonomy_snapshots (
  user_id,
  place_id,
  primary_category,
  subcategory,
  food_type,
  captured_for,
  captured_at
)
select
  relation.user_id,
  relation.place_id,
  taxonomy.primary_category,
  taxonomy.subcategory,
  taxonomy.food_type,
  'backfill',
  relation.first_related_at
from (
  select combined.user_id, combined.place_id, min(combined.first_related_at) as first_related_at
  from (
  select
    own.user_id,
    own.place_id,
    min(coalesce(own.saved_at, own.created_at)) as first_related_at
  from public.user_places own
  where own.deleted_at is null
  group by own.user_id, own.place_id

  union

  select
    item.added_by_user_id,
    item.place_id,
    min(item.created_at) as first_related_at
  from public.place_list_items item
  where item.deleted_at is null
  group by item.added_by_user_id, item.place_id
  ) combined
  group by combined.user_id, combined.place_id
) relation
cross join lateral app.global_place_taxonomy(relation.place_id) taxonomy
on conflict (user_id, place_id) do nothing;

-- Noun's MapKit identity row received a Google Places taxonomy refresh from
-- Coffee shop to Wine Bar at 2026-08-24 06:57:27 UTC. All existing relations
-- predate that refresh, so preserve the prior provider default for those users
-- while leaving Wine Bar canonical for people without a prior relation.
update public.place_taxonomy_snapshots snapshot
set
  primary_category = 'coffee_tea_sweets',
  subcategory = 'Coffee shop',
  food_type = null
from public.places place
where snapshot.place_id = place.id
  and place.source_provider = 'mapkit'
  and place.source_provider_place_id = 'mapkit_noun_3399034_-11844389'
  and snapshot.captured_at < '2026-08-24 06:57:27.15276+00'::timestamptz;

do $$
declare
  place_row record;
begin
  for place_row in select id from public.places loop
    perform app.recompute_place_taxonomy_consensus(place_row.id);
  end loop;
end;
$$;

drop trigger if exists user_places_taxonomy_maintenance on public.user_places;
create trigger user_places_taxonomy_maintenance
  after insert or update or delete
  on public.user_places
  for each row execute function app.user_place_taxonomy_maintenance();

drop trigger if exists place_attributes_taxonomy_maintenance on public.place_attributes;
create trigger place_attributes_taxonomy_maintenance
  after insert or update or delete
  on public.place_attributes
  for each row execute function app.place_attribute_taxonomy_maintenance();

drop trigger if exists place_list_items_taxonomy_maintenance on public.place_list_items;
create trigger place_list_items_taxonomy_maintenance
  after insert or update or delete
  on public.place_list_items
  for each row execute function app.place_list_item_taxonomy_maintenance();

-- Preserve the established authenticated write boundary. Provider-backed
-- refreshes may update canonical taxonomy; viewer-effective consensus rows may
-- not write themselves back as provider truth.
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
  input_provider_food_type text;
  updates_provider_taxonomy boolean;
  stored_category_source text;
  input_category_override text;
  input_subcategory_override text;
  input_category_override_source text;
  input_category_override_confidence double precision;
  attr jsonb;
  attr_question_key text;
  attr_value_type text;
  attr_question_definition_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_place), '') <> 'object' then raise exception 'invalid_place_payload'; end if;
  if coalesce(jsonb_typeof(input_user_place), '') <> 'object' then raise exception 'invalid_user_place_payload'; end if;
  if coalesce(jsonb_typeof(input_attributes), 'array') <> 'array' then raise exception 'invalid_attributes_payload'; end if;

  if nullif(input_user_place->>'rating_score', '') is not null then
    input_rating_score := (input_user_place->>'rating_score')::numeric;
  end if;
  if input_rating_score is not null and (
    input_rating_score < 1 or input_rating_score > 5
    or input_rating_score * 2 <> trunc(input_rating_score * 2)
  ) then
    raise exception 'invalid_rating_score';
  end if;

  provider := coalesce(nullif(input_place->>'source_provider', ''), 'manual');
  provider_place_id := nullif(input_place->>'source_provider_place_id', '');
  if provider_place_id is null then
    provider_place_id := 'generated:' || md5(
      provider || ':' || coalesce(input_place->>'canonical_name', '') || ':' ||
      coalesce(input_place->>'latitude', '') || ':' || coalesce(input_place->>'longitude', '')
    );
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:place-provider:' || viewer_id || ':' || provider || ':' || provider_place_id,
      0
    )
  );

  select place.id into existing_place_id
  from public.places place
  where place.source_provider = provider
    and place.source_provider_place_id = provider_place_id;

  if existing_place_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('recme:user-place:' || viewer_id || ':' || existing_place_id::text, 0)
    );
  end if;

  if input_user_place->>'status' = 'wanna_go' then
    select own.* into saved_row
    from public.places place
    join public.user_places own
      on own.place_id = place.id
     and own.user_id = viewer_id
     and own.deleted_at is null
    where place.source_provider = provider
      and place.source_provider_place_id = provider_place_id
      and own.status = 'been'
    limit 1;
    if saved_row.id is not null then return saved_row; end if;
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
  updates_provider_taxonomy := input_category_source in ('provider', 'deterministic', 'ai', 'legacy', 'unknown');
  stored_category_source := case
    when input_category_source in ('provider', 'deterministic', 'ai', 'legacy', 'unknown') then input_category_source
    else 'legacy'
  end;

  if nullif(input_place->>'category_confidence', '') is not null then
    input_category_confidence := greatest(0, least((input_place->>'category_confidence')::double precision, 1));
  else
    input_category_confidence := nullif(input_place->>'confidence', '')::double precision;
  end if;

  if input_primary_category = 'restaurants_food' then
    input_provider_food_type := app.restaurant_cuisine_guess(
      input_raw_provider_type,
      input_subcategory,
      input_primary_category,
      input_place->>'canonical_name',
      null
    );
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
    canonical_name, category, primary_category, subcategory, category_source,
    category_confidence, raw_provider_type, provider_food_type, address,
    locality, region, country, latitude, longitude, source_provider,
    source_provider_place_id, confidence
  ) values (
    input_place->>'canonical_name', input_primary_category, input_primary_category,
    input_subcategory, stored_category_source, input_category_confidence,
    coalesce(input_raw_provider_type, nullif(input_place->>'category', '')),
    input_provider_food_type, nullif(input_place->>'address', ''),
    nullif(input_place->>'locality', ''), nullif(input_place->>'region', ''),
    nullif(input_place->>'country', ''), (input_place->>'latitude')::double precision,
    (input_place->>'longitude')::double precision, provider, provider_place_id,
    nullif(input_place->>'confidence', '')::double precision
  )
  on conflict (source_provider, source_provider_place_id)
  do update set
    canonical_name = excluded.canonical_name,
    category = case when updates_provider_taxonomy then excluded.primary_category else public.places.category end,
    primary_category = case when updates_provider_taxonomy then excluded.primary_category else public.places.primary_category end,
    subcategory = case when updates_provider_taxonomy then excluded.subcategory else public.places.subcategory end,
    category_source = case when updates_provider_taxonomy then excluded.category_source else public.places.category_source end,
    category_confidence = case when updates_provider_taxonomy then excluded.category_confidence else public.places.category_confidence end,
    raw_provider_type = case when updates_provider_taxonomy then excluded.raw_provider_type else public.places.raw_provider_type end,
    provider_food_type = case when updates_provider_taxonomy then excluded.provider_food_type else public.places.provider_food_type end,
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
    user_id, place_id, status, note, rating_signal, rating_score,
    category_override, subcategory_override, category_override_source,
    category_override_confidence, visibility, nearby_confirmed, source_type
  ) values (
    viewer_id, place_row.id, input_user_place->>'status',
    nullif(input_user_place->>'note', ''), nullif(input_user_place->>'rating_signal', ''),
    case when input_user_place->>'status' = 'been' then input_rating_score else null end,
    input_category_override, input_subcategory_override, input_category_override_source,
    input_category_override_confidence, input_user_place->>'visibility',
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

  delete from public.place_attributes existing
  where existing.user_place_id = saved_row.id
    and not exists (
      select 1 from jsonb_array_elements(input_attributes) incoming(attr)
      where incoming.attr->>'question_key' = existing.question_key
    );

  for attr in select value from jsonb_array_elements(input_attributes)
  loop
    attr_question_key := nullif(attr->>'question_key', '');
    attr_value_type := nullif(attr->>'value_type', '');
    if attr_question_key is null or attr_value_type is null
       or not (attr ? 'value') or attr->'value' = 'null'::jsonb then
      continue;
    end if;

    select definition.id into attr_question_definition_id
    from public.question_definitions definition
    where definition.question_key = attr_question_key
      and (definition.owner_user_id = viewer_id or definition.is_system)
    order by (definition.owner_user_id = viewer_id) desc, definition.is_system desc
    limit 1;

    insert into public.place_attributes (
      user_place_id, question_definition_id, question_key, value_type, value
    ) values (
      saved_row.id, attr_question_definition_id, attr_question_key,
      attr_value_type, attr->'value'
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

create or replace function app.save_visible_place(input_place_id uuid, input_source_user_place_id uuid)
returns public.user_places
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  source_row public.user_places;
  saved_row public.user_places;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  select * into source_row
  from public.user_places source
  where source.id = input_source_user_place_id
    and source.place_id = input_place_id
    and source.deleted_at is null
    and app.can_read_user_place(viewer_id, source.user_id, source.visibility);
  if source_row.id is null then raise exception 'source_not_visible'; end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('recme:user-place:' || viewer_id || ':' || input_place_id::text, 0)
  );

  select * into saved_row
  from public.user_places own
  where own.user_id = viewer_id
    and own.place_id = input_place_id
    and own.deleted_at is null
    and own.status = 'been';
  if saved_row.id is not null then return saved_row; end if;

  insert into public.user_places (
    user_id, place_id, status, note, rating_signal, visibility, source_type,
    source_user_place_id, attribution_user_id
  ) values (
    viewer_id, input_place_id, 'wanna_go', source_row.note,
    source_row.rating_signal, 'followers', 'social_save', source_row.id,
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

  insert into public.place_attributes (
    user_place_id, question_definition_id, question_key, value_type, value
  )
  select
    saved_row.id, attribute.question_definition_id, attribute.question_key,
    attribute.value_type, attribute.value
  from public.place_attributes attribute
  where attribute.user_place_id = source_row.id
    and attribute.question_key <> 'restaurant_cuisine'
  on conflict (user_place_id, question_key)
  do update set
    question_definition_id = excluded.question_definition_id,
    value_type = excluded.value_type,
    value = excluded.value,
    updated_at = now();

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
security definer
set search_path = public, app
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

create or replace function app.shared_visit_source_snapshot(input_source_visit_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select jsonb_build_object(
    'visited_at', source_visit.visited_at,
    'note', source_visit.note,
    'rating_score', source_visit.rating_score,
    'attribute_answers', coalesce((
      select jsonb_agg(answer.value order by answer.ordinality)
      from jsonb_array_elements(coalesce(source_visit.attribute_answers, '[]'::jsonb))
        with ordinality answer(value, ordinality)
      where answer.value->>'question_key' is distinct from 'restaurant_cuisine'
    ), '[]'::jsonb),
    'tags', to_jsonb(source_visit.tags),
    'photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'photo_id', photo.id,
          'storage_bucket', photo.storage_bucket,
          'storage_path', photo.storage_path,
          'content_type', photo.content_type,
          'byte_size', photo.byte_size,
          'width', photo.width,
          'height', photo.height,
          'captured_at', photo.captured_at,
          'sort_order', photo.sort_order
        ) order by photo.sort_order, photo.created_at
      )
      from public.visit_photos photo
      where photo.visit_id = source_visit.id
        and photo.deleted_at is null
        and photo.upload_state = 'uploaded'
    ), '[]'::jsonb)
  )
  from public.place_visits source_visit
  where source_visit.id = input_source_visit_id
    and source_visit.deleted_at is null
$$;

create or replace function app.private_taxonomy_snapshot_projection(input_snapshot jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when input_snapshot is null then null
    when jsonb_typeof(input_snapshot) <> 'object' then input_snapshot
    else jsonb_set(
      input_snapshot,
      '{attribute_answers}',
      coalesce((
        select jsonb_agg(answer.value order by answer.ordinality)
        from jsonb_array_elements(
          case
            when jsonb_typeof(input_snapshot->'attribute_answers') = 'array'
              then input_snapshot->'attribute_answers'
            else '[]'::jsonb
          end
        ) with ordinality answer(value, ordinality)
        where answer.value->>'question_key' is distinct from 'restaurant_cuisine'
      ), '[]'::jsonb),
      true
    )
  end
$$;

revoke all on function app.private_taxonomy_snapshot_projection(jsonb)
  from public, anon, authenticated;

-- Project legacy invitation snapshots through the same privacy filter used for
-- new invitations. Stored snapshots remain untouched.
create or replace function public.list_shared_visit_inbox(
  input_before timestamptz default null,
  input_limit integer default 50
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.user_id = app.current_user_id()
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
    and (input_before is null or participant.invited_at < input_before)
  order by participant.invited_at desc, participant.id
  limit greatest(1, least(coalesce(input_limit, 50), 50))
$$;

create or replace function public.get_shared_visit_context(
  input_participant_id uuid,
  input_generation integer
)
returns table (
  participant_id uuid,
  group_id uuid,
  invitation_generation integer,
  snapshot_revision integer,
  participant_status text,
  invited_at timestamptz,
  source_visit_id uuid,
  source_owner_user_id text,
  source_owner_handle text,
  source_owner_display_name text,
  source_owner_avatar_url text,
  place_id uuid,
  canonical_name text,
  category text,
  primary_category text,
  subcategory text,
  address text,
  locality text,
  region text,
  country text,
  latitude double precision,
  longitude double precision,
  source_provider text,
  source_provider_place_id text,
  source_snapshot jsonb
)
language sql
stable
security definer
set search_path = public, app
as $$
  select
    participant.id,
    shared_group.id,
    participant.invitation_generation,
    participant.snapshot_revision,
    participant.status,
    participant.invited_at,
    shared_group.source_visit_id,
    owner.id,
    owner.handle,
    owner.display_name,
    owner.avatar_url,
    place.id,
    place.canonical_name,
    place.category,
    place.primary_category,
    place.subcategory,
    place.address,
    place.locality,
    place.region,
    place.country,
    place.latitude,
    place.longitude,
    place.source_provider,
    place.source_provider_place_id,
    app.private_taxonomy_snapshot_projection(participant.invitation_snapshot)
  from public.shared_visit_participants participant
  join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
  join public.profiles owner on owner.id = shared_group.owner_user_id
  join public.places place on place.id = shared_group.place_id
  where participant.id = input_participant_id
    and participant.user_id = app.current_user_id()
    and participant.invitation_generation = input_generation
    and participant.status = 'pending'
    and participant.invitation_snapshot is not null
    and shared_group.cancelled_at is null
    and owner.deleted_at is null
    and not owner.is_private_profile
$$;

revoke all on function public.list_shared_visit_inbox(timestamptz, integer)
  from public, anon;
revoke all on function public.get_shared_visit_context(uuid, integer)
  from public, anon;
grant execute on function public.list_shared_visit_inbox(timestamptz, integer)
  to authenticated;
grant execute on function public.get_shared_visit_context(uuid, integer)
  to authenticated;

comment on function app.save_own_place(jsonb, jsonb, jsonb) is
  'Authenticated own-place save. Provider refreshes update canonical taxonomy; viewer consensus cannot overwrite provider truth.';
comment on function app.save_visible_place(uuid, uuid) is
  'Narrow security-definer copy of an explicitly viewer-visible place without the source owner''s private food type; preserves the viewer''s first-relation taxonomy snapshot.';
comment on function app.shared_visit_source_snapshot(uuid) is
  'Builds a shareable visit snapshot without the source owner''s private restaurant food type.';
comment on function app.private_taxonomy_snapshot_projection(jsonb) is
  'Removes private restaurant food type answers from legacy and current shared-visit snapshot projections without mutating stored history.';

revoke all on function app.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function app.save_visible_place(uuid, uuid) from public, anon;
revoke all on function app.shared_visit_source_snapshot(uuid) from public, anon, authenticated;
revoke all on function public.save_own_place(jsonb, jsonb, jsonb) from public, anon;
grant execute on function app.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function app.save_visible_place(uuid, uuid) to authenticated;
grant execute on function public.save_own_place(jsonb, jsonb, jsonb) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_proc
    where oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'app.save_own_place security posture changed';
  end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'app.save_visible_place(uuid,uuid)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'app.save_visible_place security posture changed';
  end if;

  if not exists (
    select 1 from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.save_own_place security posture changed';
  end if;

  if has_function_privilege('anon', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'app.save_visible_place(uuid,uuid)', 'execute')
     or has_function_privilege('anon', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute') then
    raise exception 'taxonomy write RPCs must remain authenticated-only';
  end if;
end;
$$;

commit;
