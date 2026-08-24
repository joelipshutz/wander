begin;

create extension if not exists pgtap;

select plan(20);

select ok(
  not has_table_privilege('authenticated', 'public.place_taxonomy_snapshots', 'select'),
  'authenticated clients cannot read private taxonomy snapshots directly'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.viewer_place_taxonomy(uuid)'::regprocedure),
  true,
  'viewer taxonomy helper is a narrow security-definer boundary'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.viewer_place_taxonomy(uuid)'::regprocedure
  ),
  'viewer taxonomy helper pins its search path'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('taxonomy_viewer', 'taxonomyviewer', 'Taxonomy Viewer', false),
  ('taxonomy_owner', 'taxonomyowner', 'Taxonomy Owner', false),
  ('taxonomy_late_viewer', 'taxonomylateviewer', 'Taxonomy Late Viewer', false),
  ('taxonomy_list_viewer', 'taxonomylistviewer', 'Taxonomy List Viewer', false);

insert into public.profiles (id, handle, display_name, is_private_profile)
select
  'taxonomy_voter_' || series,
  'taxonomyvoter' || series,
  'Taxonomy Voter ' || series,
  false
from generate_series(1, 10) series;

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('taxonomy_viewer', 'taxonomy_owner', 'profile'),
  ('taxonomy_late_viewer', 'taxonomy_owner', 'profile');

insert into public.places (
  id,
  canonical_name,
  category,
  primary_category,
  subcategory,
  category_source,
  raw_provider_type,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values (
  'a6200000-0000-0000-0000-000000000001',
  'Private Taxonomy Cafe',
  'coffee_tea_sweets',
  'coffee_tea_sweets',
  'Coffee shop',
  'provider',
  'coffee_shop',
  34.01,
  -118.01,
  'mapkit',
  'private-taxonomy-cafe'
);

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  category_override,
  subcategory_override,
  category_override_source,
  category_override_confidence,
  source_type
)
values (
  'a6210000-0000-0000-0000-000000000001',
  'taxonomy_owner',
  'a6200000-0000-0000-0000-000000000001',
  'been',
  'followers',
  'bars_nightlife',
  'Wine Bar',
  'user',
  1,
  'manual'
);

insert into public.place_attributes (
  user_place_id,
  question_definition_id,
  question_key,
  value_type,
  value
)
values (
  'a6210000-0000-0000-0000-000000000001',
  null,
  'restaurant_cuisine',
  'restaurant_cuisine',
  '"Steakhouse"'::jsonb
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_viewer', true);

select is(
  (
    select primary_category
    from public.profile_visible_places('taxonomy_owner', null, null)
    where place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'coffee_tea_sweets',
  'another viewer sees the provider category before consensus'
);

select is(
  (
    select category_override
    from public.profile_visible_places('taxonomy_owner', null, null)
    where place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  null::text,
  'another viewer cannot see the owner category override'
);

select ok(
  not (
    select attributes @> '[{"question_key":"restaurant_cuisine"}]'::jsonb
    from public.profile_visible_places('taxonomy_owner', null, null)
    where place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'another viewer cannot see the owner food type'
);

select isnt_empty(
  $$
    select *
    from public.save_own_place(
      '{
        "canonical_name": "Private Taxonomy Cafe",
        "category": "coffee_tea_sweets",
        "primary_category": "coffee_tea_sweets",
        "subcategory": "Coffee shop",
        "category_source": "provider",
        "raw_provider_type": "coffee_shop",
        "latitude": 34.01,
        "longitude": -118.01,
        "source_provider": "mapkit",
        "source_provider_place_id": "private-taxonomy-cafe",
        "confidence": 0.99
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'viewer can create a save that freezes the current provider default'
);

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_owner', true);

select isnt_empty(
  $$
    select *
    from public.save_own_place(
      '{
        "canonical_name": "Private Taxonomy Cafe",
        "category": "bars_nightlife",
        "primary_category": "bars_nightlife",
        "subcategory": "Wine Bar",
        "category_source": "provider",
        "raw_provider_type": "wine_bar",
        "latitude": 34.01,
        "longitude": -118.01,
        "source_provider": "mapkit",
        "source_provider_place_id": "private-taxonomy-cafe",
        "confidence": 0.99
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "category_override": "bars_nightlife",
        "subcategory_override": "Wine Bar",
        "category_override_source": "user",
        "category_override_confidence": 1,
        "nearby_confirmed": false,
        "source_type": "manual",
        "rating_score": 4
      }'::jsonb,
      '[{
        "question_key": "restaurant_cuisine",
        "value_type": "restaurant_cuisine",
        "value": "Steakhouse"
      }]'::jsonb
    )
  $$,
  'a provider refresh updates canonical taxonomy without replacing prior snapshots'
);

reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_viewer', true);

select results_eq(
  $$
    select primary_category, subcategory
    from app.viewer_place_taxonomy('a6200000-0000-0000-0000-000000000001')
  $$,
  $$ values ('coffee_tea_sweets'::text, 'Coffee shop'::text) $$,
  'an existing saver retains the first provider snapshot after refresh'
);

select ok(
  (
    select attributes @> '[{
      "question_key": "__viewer_taxonomy_primary_category",
      "value": "coffee_tea_sweets"
    }]'::jsonb
    from public.profile_visible_places('taxonomy_owner', null, null)
    where place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'social projections carry only the authenticated viewer snapshot envelope'
);

reset role;

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  category_override,
  subcategory_override,
  category_override_source,
  category_override_confidence,
  source_type
)
select
  ('a6220000-0000-0000-0000-' || lpad(series::text, 12, '0'))::uuid,
  'taxonomy_voter_' || series,
  'a6200000-0000-0000-0000-000000000001',
  'been',
  'followers',
  case when series <= 9 then 'restaurants_food' else 'bars_nightlife' end,
  case when series <= 9 then 'Restaurant' else 'Wine Bar' end,
  'user',
  1,
  'manual'
from generate_series(1, 10) series;

insert into public.place_attributes (
  user_place_id,
  question_definition_id,
  question_key,
  value_type,
  value
)
select
  ('a6220000-0000-0000-0000-' || lpad(series::text, 12, '0'))::uuid,
  null,
  'restaurant_cuisine',
  'restaurant_cuisine',
  to_jsonb(case when series <= 9 then 'Seafood' else 'Steakhouse' end)
from generate_series(1, 10) series;

select is(
  (select category_voter_count from public.places where id = 'a6200000-0000-0000-0000-000000000001'),
  11,
  'category consensus counts distinct active user selections, including the original owner'
);

select is(
  (select consensus_primary_category from public.places where id = 'a6200000-0000-0000-0000-000000000001'),
  'restaurants_food',
  'the plurality category becomes the global default after ten selectors'
);

select is(
  (select consensus_subcategory from public.places where id = 'a6200000-0000-0000-0000-000000000001'),
  'Restaurant',
  'the plurality subcategory becomes the global default after ten selectors'
);

select is(
  (select consensus_food_type from public.places where id = 'a6200000-0000-0000-0000-000000000001'),
  'Seafood',
  'the plurality food type becomes the global default after ten selectors'
);

select is(
  (
    select food_type
    from app.viewer_place_taxonomy('a6200000-0000-0000-0000-000000000001')
  ),
  null::text,
  'an existing saver with no original food type does not inherit a later consensus food type'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_late_viewer', true);

select results_eq(
  $$
    select primary_category, subcategory, food_type
    from app.viewer_place_taxonomy('a6200000-0000-0000-0000-000000000001')
  $$,
  $$ values ('restaurants_food'::text, 'Restaurant'::text, 'Seafood'::text) $$,
  'a person without a prior relation receives the current consensus default'
);

reset role;

insert into public.place_lists (
  id,
  owner_user_id,
  name,
  visibility
)
values (
  'a6230000-0000-0000-0000-000000000001',
  'taxonomy_list_viewer',
  'Taxonomy Snapshot List',
  'stealth'
);

insert into public.place_list_items (
  id,
  list_id,
  place_id,
  source_user_place_id,
  added_by_user_id
)
values (
  'a6240000-0000-0000-0000-000000000001',
  'a6230000-0000-0000-0000-000000000001',
  'a6200000-0000-0000-0000-000000000001',
  'a6210000-0000-0000-0000-000000000001',
  'taxonomy_list_viewer'
);

select is(
  (
    select primary_category
    from public.place_taxonomy_snapshots
    where user_id = 'taxonomy_list_viewer'
      and place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'restaurants_food',
  'a list-only relation captures the effective default at first add'
);

select is(
  (
    select captured_for
    from public.place_taxonomy_snapshots
    where user_id = 'taxonomy_list_viewer'
      and place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'list',
  'list-only snapshot records why it was captured'
);

select ok(
  not has_function_privilege('anon', 'app.viewer_place_taxonomy(uuid)', 'execute'),
  'anonymous callers cannot execute viewer taxonomy projection'
);

select ok(
  not has_function_privilege('anon', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute'),
  'anonymous callers cannot use taxonomy-aware place writes'
);

select * from finish();

rollback;
