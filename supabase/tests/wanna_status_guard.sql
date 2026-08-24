begin;

create extension if not exists pgtap;

select plan(13);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  'app.save_own_place remains a security-definer function with a pinned search path'
);

select ok(
  (
    select not prosecdef
      and 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  'public.save_own_place remains an invoker wrapper with a pinned search path'
);

select ok(
  (
    select not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.save_visible_place(uuid,uuid)'::regprocedure
  ),
  'app.save_visible_place remains an invoker function with a pinned search path'
);

select ok(
  (
    select not prosecdef
      and 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.save_visible_place(uuid,uuid)'::regprocedure
  ),
  'public.save_visible_place remains an invoker wrapper with a pinned search path'
);

select ok(
  has_function_privilege('authenticated', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'app.save_own_place(jsonb,jsonb,jsonb)', 'execute')
    and has_function_privilege('authenticated', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
    and not has_function_privilege('anon', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
    and has_function_privilege('authenticated', 'app.save_visible_place(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'app.save_visible_place(uuid,uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.save_visible_place(uuid,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.save_visible_place(uuid,uuid)', 'execute'),
  'save RPC grants remain authenticated-only'
);

select ok(
  pg_get_functiondef('app.save_own_place(jsonb,jsonb,jsonb)'::regprocedure)
    like '%pg_advisory_xact_lock%recme:user-place:%',
  'own-place saves serialize against concurrent social and check-in writes'
);

select ok(
  pg_get_functiondef('app.save_visible_place(uuid,uuid)'::regprocedure)
    like '%pg_advisory_xact_lock%recme:user-place:%',
  'social saves serialize against concurrent own-place writes'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_wanna_guard_owner', 'wannaguardowner', 'Wanna Guard Owner'),
  ('user_wanna_guard_source', 'wannaguardsource', 'Wanna Guard Source');

insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_wanna_guard_owner', 'user_wanna_guard_source', 'profile');

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id,
  confidence
)
values
  (
    '11111111-1111-4111-8111-111111111190',
    'Own Save Guard',
    'coffee',
    34.0501,
    -118.2501,
    'mapkit',
    'own-save-guard',
    1
  ),
  (
    '22222222-2222-4222-8222-222222222290',
    'Social Save Guard',
    'coffee',
    34.0502,
    -118.2502,
    'mapkit',
    'social-save-guard',
    1
  ),
  (
    '66666666-6666-4666-8666-666666666690',
    'Social Note Isolation Guard',
    'coffee',
    34.0503,
    -118.2503,
    'mapkit',
    'social-note-isolation-guard',
    1
  );

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  note,
  rating_score,
  visibility,
  source_type
)
values
  (
    '33333333-3333-4333-8333-333333333390',
    'user_wanna_guard_owner',
    '11111111-1111-4111-8111-111111111190',
    'been',
    'original own note',
    4.5,
    'followers',
    'manual'
  ),
  (
    '44444444-4444-4444-8444-444444444490',
    'user_wanna_guard_owner',
    '22222222-2222-4222-8222-222222222290',
    'been',
    'original social note',
    4,
    'followers',
    'manual'
  ),
  (
    '55555555-5555-4555-8555-555555555590',
    'user_wanna_guard_source',
    '22222222-2222-4222-8222-222222222290',
    'been',
    'source note',
    5,
    'followers',
    'manual'
  ),
  (
    '77777777-7777-4777-8777-777777777790',
    'user_wanna_guard_source',
    '66666666-6666-4666-8666-666666666690',
    'been',
    'source private note',
    5,
    'followers',
    'manual'
  );

insert into public.place_attributes (user_place_id, question_key, value_type, value)
values
  (
    '44444444-4444-4444-8444-444444444490',
    'coffee_tags',
    'multi_tag',
    '["owner value"]'::jsonb
  ),
  (
    '55555555-5555-4555-8555-555555555590',
    'coffee_tags',
    'multi_tag',
    '["source value"]'::jsonb
  );

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_wanna_guard_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    select public.save_own_place(
      '{
        "canonical_name": "Mutated Own Save Guard",
        "category": "coffee",
        "latitude": 35,
        "longitude": -119,
        "source_provider": "mapkit",
        "source_provider_place_id": "own-save-guard",
        "confidence": 0.1
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "self",
        "nearby_confirmed": false,
        "source_type": "manual",
        "planned_date": "2099-08-15"
      }'::jsonb,
      '[]'::jsonb
    )->>'user_place_id'
  ),
  '33333333-3333-4333-8333-333333333390',
  'stale own Wanna Go save returns the existing check-in'
);

select is(
  (
    select jsonb_build_object(
      'place_name', p.canonical_name,
      'latitude', p.latitude,
      'status', up.status,
      'note', up.note,
      'rating_score', up.rating_score,
      'visibility', up.visibility,
      'planned_date', up.planned_date
    )
    from public.user_places up
    join public.places p on p.id = up.place_id
    where up.id = '33333333-3333-4333-8333-333333333390'
  ),
  '{
    "place_name": "Own Save Guard",
    "latitude": 34.0501,
    "status": "been",
    "note": "original own note",
    "rating_score": 4.5,
    "visibility": "followers",
    "planned_date": null
  }'::jsonb,
  'stale own Wanna Go save leaves the canonical place and check-in unchanged'
);

select is(
  (
    select public.save_visible_place(
      '22222222-2222-4222-8222-222222222290',
      '55555555-5555-4555-8555-555555555590'
    )->>'user_place_id'
  ),
  '44444444-4444-4444-8444-444444444490',
  'stale social Wanna Go save returns the existing check-in'
);

select is(
  (
    select jsonb_build_object(
      'status', up.status,
      'note', up.note,
      'rating_score', up.rating_score,
      'source_type', up.source_type,
      'attribute', (
        select pa.value
        from public.place_attributes pa
        where pa.user_place_id = up.id
          and pa.question_key = 'coffee_tags'
      )
    )
    from public.user_places up
    where up.id = '44444444-4444-4444-8444-444444444490'
  ),
  '{
    "status": "been",
    "note": "original social note",
    "rating_score": 4,
    "source_type": "manual",
    "attribute": ["owner value"]
  }'::jsonb,
  'stale social Wanna Go save leaves the complete check-in unchanged'
);

select public.save_visible_place(
  '66666666-6666-4666-8666-666666666690',
  '77777777-7777-4777-8777-777777777790'
);

select is(
  (
    select up.note
    from public.user_places up
    where up.user_id = 'user_wanna_guard_owner'
      and up.place_id = '66666666-6666-4666-8666-666666666690'
      and up.deleted_at is null
  ),
  null::text,
  'a new social save does not copy the source account note'
);

update public.user_places
set note = 'owner private note'
where user_id = 'user_wanna_guard_owner'
  and place_id = '66666666-6666-4666-8666-666666666690';

select public.save_visible_place(
  '66666666-6666-4666-8666-666666666690',
  '77777777-7777-4777-8777-777777777790'
);

select is(
  (
    select up.note
    from public.user_places up
    where up.user_id = 'user_wanna_guard_owner'
      and up.place_id = '66666666-6666-4666-8666-666666666690'
      and up.deleted_at is null
  ),
  'owner private note',
  'a repeated social save preserves the viewer account note'
);

select * from finish();

rollback;
