begin;

create extension if not exists pgtap;

select plan(2);

insert into public.profiles (id, handle, display_name)
values ('user_save_owner', 'saveowner', 'Save Owner');

insert into public.question_definitions (
  id,
  owner_user_id,
  question_key,
  prompt,
  value_type,
  options,
  is_system
)
values (
  '30000000-0000-0000-0000-000000000101',
  null,
  'rating_signal',
  'how much did you like it?',
  'emoji_scale',
  '["meh", "fine", "good", "great"]',
  true
);

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
        "source_type": "manual"
      }'::jsonb,
      '[{
        "question_key": "rating_signal",
        "value_type": "emoji_scale",
        "value": "great"
      }]'::jsonb
    )
  $$,
  'save_own_place creates an own place for an authenticated Clerk caller'
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
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'save_own_place can upsert an existing canonical place through the RPC'
);

select * from finish();

rollback;
