begin;

create extension if not exists pgtap;

select plan(8);

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
    select *
    from app.save_own_place(
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
        "rating_score": 5
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'save_own_place can upsert an existing canonical place through the RPC'
);

select is_empty(
  $$
    select 1
    from public.user_places
    where user_id = 'user_save_owner'
      and rating_score is not null
  $$,
  'save_own_place clears rating score for wanna go places'
);

select * from finish();

rollback;
