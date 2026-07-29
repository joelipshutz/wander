begin;

create extension if not exists pgtap;

select plan(14);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  true,
  'save_own_place runs as security definer for controlled canonical place upserts'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  'save_own_place pins search_path to public, app'
);

select ok(
  has_function_privilege('authenticated', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute'),
  'authenticated can execute app.save_own_place'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%personal_label%'
      and pg_get_constraintdef(oid) like '%restaurant_cuisine%'
    from pg_constraint
    where conrelid = 'public.question_definitions'::regclass
      and conname = 'question_definitions_value_type_check'
  ),
  'question definition value types include semantic map-save attributes'
);

select ok(
  (
    select pg_get_constraintdef(oid) like '%personal_label%'
      and pg_get_constraintdef(oid) like '%restaurant_cuisine%'
    from pg_constraint
    where conrelid = 'public.place_attributes'::regclass
      and conname = 'place_attributes_value_type_check'
  ),
  'place attribute value types include semantic map-save attributes'
);

insert into public.profiles (id, handle, display_name)
values ('user_save_owner', 'saveowner', 'Save Owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_save_owner', true);

select isnt_empty(
  $$
    select *
    from app.save_own_place(
      '{
        "canonical_name": "Save RPC Test",
        "category": "coffee",
        "latitude": 34.0501,
        "longitude": -118.2501,
        "source_provider": "mapkit",
        "source_provider_place_id": "save-rpc-test",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "nearby_confirmed": true,
        "source_type": "manual",
        "rating_score": 4.5
      }'::jsonb,
      '[{
        "question_key": "coffee_tags",
        "value_type": "multi_tag",
        "value": ["wifi solid"]
      }]'::jsonb
    )
  $$,
  'save_own_place creates an own place for an authenticated Clerk caller'
);

select is(
  (
    select rating_score
    from public.user_places
    where user_id = 'user_save_owner'
  ),
  4.5::numeric,
  'save_own_place stores half-step numeric rating score for been places'
);

select isnt_empty(
  $$
    select *
    from app.save_own_place(
      '{
        "canonical_name": "Semantic Save RPC Test",
        "category": "restaurants_food",
        "primary_category": "restaurants_food",
        "subcategory": "Restaurant",
        "latitude": 34.0503,
        "longitude": -118.2503,
        "source_provider": "mapkit",
        "source_provider_place_id": "semantic-save-rpc-test",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual",
        "rating_score": 3
      }'::jsonb,
      '[
        {
          "question_key": "personal_labels",
          "value_type": "personal_label",
          "value": ["date night"]
        },
        {
          "question_key": "restaurant_cuisine",
          "value_type": "restaurant_cuisine",
          "value": "Thai"
        }
      ]'::jsonb
    )
  $$,
  'save_own_place accepts the semantic attributes emitted by the map form'
);

select is(
  (
    select count(*)
    from public.place_attributes pa
    join public.user_places up on up.id = pa.user_place_id
    join public.places p on p.id = up.place_id
    where up.user_id = 'user_save_owner'
      and p.source_provider_place_id = 'semantic-save-rpc-test'
  ),
  2::bigint,
  'semantic map save commits both attributes atomically'
);

select is(
  (
    select pa.value_type
    from public.place_attributes pa
    join public.user_places up on up.id = pa.user_place_id
    join public.places p on p.id = up.place_id
    where up.user_id = 'user_save_owner'
      and p.source_provider_place_id = 'semantic-save-rpc-test'
      and pa.question_key = 'personal_labels'
  ),
  'personal_label',
  'semantic map save preserves personal label value type'
);

select is(
  (
    select pa.value_type
    from public.place_attributes pa
    join public.user_places up on up.id = pa.user_place_id
    join public.places p on p.id = up.place_id
    where up.user_id = 'user_save_owner'
      and p.source_provider_place_id = 'semantic-save-rpc-test'
      and pa.question_key = 'restaurant_cuisine'
  ),
  'restaurant_cuisine',
  'semantic map save preserves restaurant cuisine value type'
);

select throws_ok(
  $$
    select *
    from app.save_own_place(
      '{
        "canonical_name": "Save RPC Invalid Rating Test",
        "category": "coffee",
        "latitude": 34.0502,
        "longitude": -118.2502,
        "source_provider": "mapkit",
        "source_provider_place_id": "save-rpc-invalid-rating-test",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "nearby_confirmed": true,
        "source_type": "manual",
        "rating_score": 4.25
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'P0001',
  'invalid_rating_score',
  'save_own_place rejects non-half-step rating scores'
);

select isnt_empty(
  $$
    select public.save_own_place(
      '{
        "canonical_name": "Save RPC Test Updated",
        "category": "coffee",
        "latitude": 34.0501,
        "longitude": -118.2501,
        "source_provider": "mapkit",
        "source_provider_place_id": "save-rpc-test",
        "confidence": 0.95
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "mutuals",
        "nearby_confirmed": false,
        "source_type": "manual",
        "rating_score": 5,
        "planned_date": "2099-08-15"
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'save_own_place accepts a stale Wanna Go request for an existing check-in as a no-op'
);

select is(
  (
    select jsonb_build_object(
      'status', up.status,
      'note', up.note,
      'visibility', up.visibility,
      'rating_score', up.rating_score,
      'planned_date', up.planned_date,
      'attribute_count', (
        select count(*)
        from public.place_attributes pa
        where pa.user_place_id = up.id
      )
    )
    from public.user_places up
    join public.places p on p.id = up.place_id
    where up.user_id = 'user_save_owner'
      and p.source_provider = 'mapkit'
      and p.source_provider_place_id = 'save-rpc-test'
  ),
  '{
    "status": "been",
    "note": null,
    "visibility": "followers",
    "rating_score": 4.5,
    "planned_date": null,
    "attribute_count": 1
  }'::jsonb,
  'save_own_place preserves the complete existing check-in when Wanna Go is stale'
);

select * from finish();

rollback;
