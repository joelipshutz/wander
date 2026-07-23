begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(17);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  false,
  'public save_own_place remains security invoker'
);

select ok(
  (
    select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
  ),
  'public save_own_place retains its pinned search path'
);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.own_wanna_go_plans()'::regprocedure
  ),
  false,
  'own_wanna_go_plans runs as security invoker'
);

select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.own_wanna_go_plans()'::regprocedure
  ),
  'own_wanna_go_plans pins public and app'
);

select ok(
  has_function_privilege('authenticated', 'public.own_wanna_go_plans()', 'execute')
    and not has_function_privilege('anon', 'public.own_wanna_go_plans()', 'execute'),
  'only authenticated callers can execute own_wanna_go_plans'
);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.update_notification_preferences(jsonb)'::regprocedure
  ),
  'notification preference update retains definer security and a pinned search path'
);

select is(
  (
    select pg_get_expr(attribute_default.adbin, attribute_default.adrelid)
    from pg_attribute attribute
    join pg_attrdef attribute_default
      on attribute_default.adrelid = attribute.attrelid
     and attribute_default.adnum = attribute.attnum
    where attribute.attrelid = 'public.notification_preferences'::regclass
      and attribute.attname = 'wanna_go_reminders_enabled'
  ),
  'false',
  'Wanna go reminders default off before explicit notification enrollment'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_wanna_plan_owner', 'wannaplanowner', 'Wanna Plan Owner'),
  ('user_wanna_plan_stranger', 'wannaplanstranger', 'Wanna Plan Stranger');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_wanna_plan_owner', true);

select isnt_empty(
  $$
    select public.save_own_place(
      '{
        "canonical_name": "Wanna Plan Test",
        "category": "restaurants_food",
        "primary_category": "restaurants_food",
        "latitude": 34.0501,
        "longitude": -118.2501,
        "source_provider": "mapkit",
        "source_provider_place_id": "wanna-plan-test",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "planned_date": "2026-08-15",
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'authenticated save_own_place accepts the production Wanna planned-date payload'
);

select is(
  (
    select user_place.planned_date
    from public.user_places user_place
    where user_place.user_id = 'user_wanna_plan_owner'
  ),
  date '2026-08-15',
  'planned date persists on the owner user-place row'
);

select is(
  (
    select plan.planned_date
    from public.own_wanna_go_plans() plan
  ),
  date '2026-08-15',
  'owner plan RPC returns the persisted Wanna date'
);

select is(
  (
    select count(*)::integer
    from public.own_wanna_go_plans()
  ),
  1,
  'owner plan RPC returns only the owner dated Wanna rows'
);

select throws_ok(
  $$
    select public.save_own_place(
      '{
        "canonical_name": "Wanna Plan Test",
        "category": "restaurants_food",
        "primary_category": "restaurants_food",
        "latitude": 34.0501,
        "longitude": -118.2501,
        "source_provider": "mapkit",
        "source_provider_place_id": "wanna-plan-test",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "nearby_confirmed": false,
        "planned_date": "2026-08-15",
        "source_type": "manual",
        "rating_score": 4
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'P0001',
  'planned_date_requires_wanna_go',
  'a planned date cannot be attached to a Been save'
);

select public.save_own_place(
  '{
    "canonical_name": "Wanna Plan Test",
    "category": "restaurants_food",
    "primary_category": "restaurants_food",
    "latitude": 34.0501,
    "longitude": -118.2501,
    "source_provider": "mapkit",
    "source_provider_place_id": "wanna-plan-test",
    "confidence": 0.9
  }'::jsonb,
  '{
    "status": "been",
    "visibility": "followers",
    "nearby_confirmed": false,
    "planned_date": null,
    "source_type": "manual",
    "rating_score": 4
  }'::jsonb,
  '[]'::jsonb
);

select is(
  (
    select user_place.planned_date
    from public.user_places user_place
    where user_place.user_id = 'user_wanna_plan_owner'
  ),
  null::date,
  'changing a Wanna save to Been clears its planned date'
);

select is_empty(
  $$ select * from public.own_wanna_go_plans() $$,
  'cleared and non-Wanna rows disappear from reminder reconciliation'
);

select is(
  (
    public.update_notification_preferences(
      '{"push_enabled":true,"wanna_go_reminders_enabled":true}'::jsonb
    )
  ).wanna_go_reminders_enabled,
  true,
  'owner can enable Wanna go reminders with the existing preference RPC'
);

select set_config('request.jwt.claim.sub', 'user_wanna_plan_stranger', true);

select is_empty(
  $$ select * from public.own_wanna_go_plans() $$,
  'another authenticated user cannot read the owner planned date'
);

select is(
  (public.get_notification_preferences()).wanna_go_reminders_enabled,
  false,
  'a newly created preference row keeps Wanna go reminders off'
);

select * from finish();

rollback;
