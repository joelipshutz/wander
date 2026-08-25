begin;

create extension if not exists pgtap;

select plan(33);

select ok(
  exists (
    select 1
    from pg_constraint constraint_row
    where constraint_row.conrelid = 'public.place_attributes'::regclass
      and constraint_row.conname = 'place_attributes_no_viewer_taxonomy_projection_keys'
      and pg_get_constraintdef(constraint_row.oid) like '%__viewer_taxonomy_primary_category%'
      and pg_get_constraintdef(constraint_row.oid) like '%__viewer_taxonomy_subcategory%'
      and pg_get_constraintdef(constraint_row.oid) like '%__viewer_taxonomy_food_type%'
  ),
  'place attributes reject every reserved viewer taxonomy projection key'
);

select ok(
  position(
    'for update of place'
    in pg_get_functiondef('app.recompute_place_taxonomy_consensus(uuid)'::regprocedure)
  ) > 0,
  'consensus recomputation serializes each place before tallying votes'
);

select ok(
  not (
    app.private_taxonomy_snapshot_projection(
      '{"attribute_answers":[{"question_key":"restaurant_cuisine","value":"Thai"},{"question_key":"personal_labels","value":["date night"]}]}'::jsonb
    )->'attribute_answers' @> '[{"question_key":"restaurant_cuisine"}]'::jsonb
  ),
  'legacy shared-visit snapshots hide the source owner food type at projection time'
);

select ok(
  not has_table_privilege('authenticated', 'public.place_taxonomy_snapshots', 'select'),
  'authenticated clients cannot read private taxonomy snapshots directly'
);

select ok(
  not has_column_privilege('authenticated', 'public.user_places', 'category_override', 'select')
  and not has_column_privilege('authenticated', 'public.user_places', 'subcategory_override', 'select')
  and not has_column_privilege('authenticated', 'public.user_places', 'historical_want_attribute_answers', 'select'),
  'raw user-place reads cannot select private taxonomy columns'
);

select ok(
  not has_column_privilege('authenticated', 'public.place_visits', 'attribute_answers', 'select'),
  'raw visit reads cannot select private attribute answers'
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
  ('taxonomy_list_viewer', 'taxonomylistviewer', 'Taxonomy List Viewer', false),
  ('taxonomy_social_viewer', 'taxonomysocialviewer', 'Taxonomy Social Viewer', false);

insert into public.profiles (id, handle, display_name, is_private_profile, deleted_at)
values (
  'taxonomy_deleted_owner',
  'taxonomydeletedowner',
  'Taxonomy Deleted Owner',
  false,
  now()
);

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
  ('taxonomy_late_viewer', 'taxonomy_owner', 'profile'),
  ('taxonomy_viewer', 'taxonomy_deleted_owner', 'profile');

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

insert into public.place_attributes (
  user_place_id,
  question_definition_id,
  question_key,
  value_type,
  value
) values (
  'a6210000-0000-0000-0000-000000000001',
  null,
  '__viewer_taxonomy_primary_category',
  'text',
  '"coffee_tea_sweets"'::jsonb
);

select is(
  (
    select count(*)
    from public.place_attributes
    where user_place_id = 'a6210000-0000-0000-0000-000000000001'
      and question_key = '__viewer_taxonomy_primary_category'
  ),
  0::bigint,
  'legacy clients can echo derived viewer taxonomy without persisting it or failing the save'
);

select throws_ok(
  $$
    update public.place_attributes
    set question_key = '__viewer_taxonomy_primary_category'
    where user_place_id = 'a6210000-0000-0000-0000-000000000001'
      and question_key = 'restaurant_cuisine'
  $$,
  '23514',
  'new row for relation "place_attributes" violates check constraint "place_attributes_no_viewer_taxonomy_projection_keys"',
  'existing attributes cannot be changed into derived viewer taxonomy projection rows'
);

-- Simulate a cuisine copied into a social save before REC-362. The lineage
-- marker stays false unless the recipient later changes that value.
insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values (
  'a6210000-0000-0000-0000-000000000002',
  'taxonomy_social_viewer',
  'a6200000-0000-0000-0000-000000000001',
  'wanna_go',
  'followers',
  'social_save'
);

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values (
  'a6210000-0000-0000-0000-000000000003',
  'taxonomy_deleted_owner',
  'a6200000-0000-0000-0000-000000000001',
  'been',
  'followers',
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
  'a6210000-0000-0000-0000-000000000002',
  null,
  'restaurant_cuisine',
  'restaurant_cuisine',
  '"Steakhouse"'::jsonb
);

update public.place_attributes
set taxonomy_is_personal = false
where user_place_id = 'a6210000-0000-0000-0000-000000000002'
  and question_key = 'restaurant_cuisine';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_social_viewer', true);

select ok(
  (select food_type is null
   from app.viewer_place_taxonomy('a6200000-0000-0000-0000-000000000001'))
  and not (
    select attributes @> '[{"question_key":"restaurant_cuisine"}]'::jsonb
    from public.profile_visible_places('taxonomy_social_viewer', null, null)
    where place_id = 'a6200000-0000-0000-0000-000000000001'
  ),
  'a legacy copied cuisine is hidden even from the recipient projection until they select it'
);

select is(
  (
    select count(*)
    from public.place_attributes
    where user_place_id = 'a6210000-0000-0000-0000-000000000002'
      and question_key = 'restaurant_cuisine'
  ),
  0::bigint,
  'a social-save recipient cannot directly read a legacy copied cuisine'
);

reset role;

select is(
  (select food_type_voter_count
   from public.places
   where id = 'a6200000-0000-0000-0000-000000000001'),
  1,
  'a legacy copied cuisine does not count as a consensus selection'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'taxonomy_viewer', true);

select is(
  (
    select count(*)
    from app.visible_places_in_view(34, -119, 35, -118, null, null, null)
    where owner_user_id = 'taxonomy_deleted_owner'
  ),
  0::bigint,
  'the security-definer map projection preserves deleted-profile filtering'
);

select is(
  (
    select count(*)
    from public.user_places
    where id = 'a6210000-0000-0000-0000-000000000001'
  ),
  1::bigint,
  'ordinary social save fields remain directly readable through visibility RLS'
);

select is(
  (
    select count(*)
    from public.place_attributes
    where user_place_id = 'a6210000-0000-0000-0000-000000000001'
      and question_key = 'restaurant_cuisine'
  ),
  0::bigint,
  'raw social attribute reads cannot see another owner food type'
);

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
