begin;

create extension if not exists pgtap;

select plan(18);

select is(
  (select prosecdef from pg_proc where oid = 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)'::regprocedure),
  true,
  'semantic place search is a narrow security-definer boundary'
);

select ok(
  (select exists (
     select 1
     from unnest(coalesce(proconfig, array[]::text[])) as setting
     where setting ~ '^search_path=(""|)$'
   ) from pg_proc where oid = 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)'::regprocedure),
  'semantic search pins an empty search_path'
);

select ok(
  (select 'statement_timeout=3s' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc
   where oid = 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)'::regprocedure),
  'semantic search has a bounded statement timeout'
);

select ok(
  has_function_privilege('authenticated', 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)', 'execute'),
  'authenticated callers can execute semantic search'
);

select ok(
  not has_function_privilege('anon', 'public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)', 'execute'),
  'anonymous callers cannot execute semantic search'
);

select ok(
  not pg_get_function_result('public.search_recme_places_semantic(extensions.vector,text[],text,boolean,text,integer,double precision)'::regprocedure)
    ~* '(user_id|note|rating_score|visibility|save_count|attributes|embedding)',
  'semantic results expose canonical facts and the bounded similarity only'
);

select ok(
  has_function_privilege('service_role', 'public.semantic_place_embedding_backfill_batch(text,integer,integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.semantic_place_embedding_backfill_batch(text,integer,integer)', 'execute')
    and not has_function_privilege('anon', 'public.semantic_place_embedding_backfill_batch(text,integer,integer)', 'execute'),
  'only the service role can fetch minimized embedding documents'
);

select ok(
  not has_table_privilege('authenticated', 'public.place_search_embeddings', 'select')
    and not has_table_privilege('anon', 'public.place_search_embeddings', 'select')
    and has_table_privilege('service_role', 'public.place_search_embeddings', 'select'),
  'stored vectors are not directly readable by app roles'
);

select is(
  app.canonical_place_embedding_document(
    'Quiet Coffee',
    'coffee_tea_sweets',
    'coffee_shop',
    'Los Angeles',
    'CA'
  ),
  'Quiet Coffee | coffee_tea_sweets | coffee_shop | Los Angeles | CA',
  'canonical embedding document contains only approved coarse place facts'
);

create function pg_temp.embedding(first_component double precision, second_component double precision)
returns extensions.vector
language sql
immutable
as $$
  select (
    '[' || first_component::text || ',' || second_component::text || ',' ||
    array_to_string(array_fill(0::double precision, array[1534]), ',') || ']'
  )::extensions.vector;
$$;

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('semantic_viewer', 'semanticviewer', 'Semantic Viewer', false),
  ('semantic_friend', 'semanticfriend', 'Semantic Friend', false),
  ('semantic_stranger', 'semanticstranger', 'Semantic Stranger', false),
  ('semantic_blocked', 'semanticblocked', 'Semantic Blocked', false),
  ('semantic_private', 'semanticprivate', 'Semantic Private', true);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('semantic_viewer', 'semantic_friend', 'profile'),
  ('semantic_friend', 'semantic_viewer', 'profile');

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('semantic_viewer', 'semantic_blocked');

insert into public.places (
  id, canonical_name, category, primary_category, subcategory, category_source,
  locality, region, latitude, longitude, source_provider, source_provider_place_id, confidence
)
values
  ('61000000-0000-0000-0000-000000000001', 'Literal Friend Coffee', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Los Angeles', 'CA', 34.01, -118.01, 'mapkit', 'semantic-friend', 1),
  ('61000000-0000-0000-0000-000000000002', 'Rainy Community Cafe', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Los Angeles', 'CA', 34.02, -118.02, 'google_places', 'semantic-community', 1),
  ('61000000-0000-0000-0000-000000000003', 'Blocked Rainy Cafe', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Los Angeles', 'CA', 34.03, -118.03, 'mapkit', 'semantic-blocked', 1),
  ('61000000-0000-0000-0000-000000000004', 'Private Rainy Cafe', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Los Angeles', 'CA', 34.04, -118.04, 'mapkit', 'semantic-private', 1),
  ('61000000-0000-0000-0000-000000000005', 'Self Rainy Cafe', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Los Angeles', 'CA', 34.05, -118.05, 'mapkit', 'semantic-self', 1),
  ('61000000-0000-0000-0000-000000000006', 'Favorite Rainy Cafe', 'coffee_tea_sweets', 'coffee_tea_sweets', 'coffee_shop', 'provider', 'Santa Monica', 'CA', 34.06, -118.06, 'apple_maps', 'semantic-favorite', 1);

insert into public.user_places (
  id, user_id, place_id, status, visibility, rating_score, source_type, saved_at
)
values
  ('62000000-0000-0000-0000-000000000001', 'semantic_friend', '61000000-0000-0000-0000-000000000001', 'been', 'mutuals', 4, 'social_seed', '2026-01-01'),
  ('62000000-0000-0000-0000-000000000002', 'semantic_stranger', '61000000-0000-0000-0000-000000000002', 'been', 'followers', 3, 'social_seed', '2026-01-02'),
  ('62000000-0000-0000-0000-000000000003', 'semantic_blocked', '61000000-0000-0000-0000-000000000003', 'been', 'followers', 5, 'social_seed', '2026-01-03'),
  ('62000000-0000-0000-0000-000000000004', 'semantic_private', '61000000-0000-0000-0000-000000000004', 'been', 'followers', 5, 'social_seed', '2026-01-04'),
  ('62000000-0000-0000-0000-000000000005', 'semantic_stranger', '61000000-0000-0000-0000-000000000005', 'been', 'self', 5, 'social_seed', '2026-01-05'),
  ('62000000-0000-0000-0000-000000000006', 'semantic_stranger', '61000000-0000-0000-0000-000000000006', 'been', 'followers', 5, 'social_seed', '2026-01-06');

insert into public.place_search_embeddings (
  place_id, model, dimensions, document_version, document_hash, embedding
)
select
  place.id,
  'text-embedding-3-small',
  1536,
  1,
  repeat(substr(place.id::text, 1, 1), 64),
  case place.id
    when '61000000-0000-0000-0000-000000000001'::uuid then pg_temp.embedding(0, 1)
    else pg_temp.embedding(1, 0)
  end
from public.places as place
where place.id between
  '61000000-0000-0000-0000-000000000001'::uuid and
  '61000000-0000-0000-0000-000000000006'::uuid;

select is(
  (select count(*)::integer
   from public.semantic_place_embedding_backfill_batch('text-embedding-3-small', 2, 100)
   where place_id between
     '61000000-0000-0000-0000-000000000001'::uuid and
     '61000000-0000-0000-0000-000000000006'::uuid),
  4,
  'document-version changes make every public canonical place stale without embedding private or self-only places'
);

select is(
  (select count(*)::integer
   from public.semantic_place_embedding_backfill_batch('text-embedding-3-small', 2, 100)
   where place_id between
       '61000000-0000-0000-0000-000000000001'::uuid and
       '61000000-0000-0000-0000-000000000006'::uuid
     and document ~* '(note|rating|latitude|longitude|semantic_friend|semantic_stranger)'),
  0,
  'backfill documents exclude memory, identity, rating, and coordinate fields'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'semantic_viewer', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (select canonical_name
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), array['coffee_tea_sweets'], 'Los Angeles', false, 'everyone', 20, 0.35
   ) limit 1),
  'Rainy Community Cafe',
  'semantic similarity can recover a non-literal community place'
);

select is(
  (select count(*)::integer
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), null, null, false, 'everyone', 20, 0.35
   )
   where canonical_name in ('Blocked Rainy Cafe', 'Private Rainy Cafe', 'Self Rainy Cafe')),
  0,
  'blocks, private profiles, and self-only saves remain excluded'
);

select is(
  (select array_agg(canonical_name order by canonical_name)::text
   from public.search_recme_places_semantic(
     pg_temp.embedding(0, 1), null, null, false, 'friends', 20, 0.35
   )),
  '{"Literal Friend Coffee"}',
  'friends remains a hard mutual-only scope'
);

select is(
  (select array_agg(canonical_name order by canonical_name)::text
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), null, null, true, 'everyone', 20, 0.35
   )),
  '{"Favorite Rainy Cafe"}',
  'favorite remains a hard eligible Been rating filter'
);

select is(
  (select count(*)::integer
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), array['outdoors_nature'], null, false, 'everyone', 20, 0.35
   )),
  0,
  'category remains a hard filter before semantic ranking'
);

select is(
  (select count(*)::integer
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), null, 'Santa Monica', false, 'everyone', 20, 0.35
   )),
  1,
  'area remains a hard filter before semantic ranking'
);

select is(
  (select source_provider || ':' || source_provider_place_id
   from public.search_recme_places_semantic(
     pg_temp.embedding(1, 0), null, 'Santa Monica', false, 'everyone', 20, 0.35
   )),
  'apple_maps:semantic-favorite',
  'semantic results preserve canonical provider identity'
);

select * from finish();

rollback;
