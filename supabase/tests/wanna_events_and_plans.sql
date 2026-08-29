begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(40);

create temporary table test_wanna_participant_ids (
  user_id text primary key,
  participant_id uuid not null,
  invitation_generation integer not null
) on commit drop;
grant select on table test_wanna_participant_ids to authenticated;
create temporary table test_wanna_feed_ids (
  wanna_event_id uuid primary key,
  feed_event_id uuid not null
) on commit drop;
grant select on table test_wanna_feed_ids to authenticated;

select has_table('public', 'place_wanna_events', 'immutable Wanna event table exists');
select has_table('public', 'place_plans', 'Wanna plan table exists');
select has_table('public', 'place_plan_participants', 'Wanna participant table exists');
select has_table('public', 'place_plan_operations', 'Wanna acceptance ledger exists');

select ok(
  not has_table_privilege('authenticated', 'public.place_wanna_events', 'select')
    and not has_table_privilege('authenticated', 'public.place_plans', 'select')
    and not has_table_privilege('authenticated', 'public.place_plan_participants', 'select')
    and not has_table_privilege('authenticated', 'public.place_plan_operations', 'select'),
  'Wanna storage remains RPC-only'
);
select has_column('public', 'feed_events', 'wanna_event_id', 'Feed stores the immutable Wanna event identity');
select has_column('public', 'feed_events', 'place_plan_id', 'Feed may decorate a Wanna with one plan');
select has_trigger(
  'public',
  'place_visits',
  'place_visits_fulfill_first_wanna',
  'first explicit check-in resolves active Wanna events'
);

select ok(
  (
    select bool_and(
      procedure.prosecdef
        and 'search_path=public, app' = any(coalesce(procedure.proconfig, array[]::text[]))
    )
    from pg_proc procedure
    where procedure.oid in (
      'public.save_own_wanna(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure,
      'public.own_wanna_events()'::regprocedure,
      'public.feed_wanna_context(uuid[])'::regprocedure,
      'public.list_wanna_plan_inbox(timestamptz,integer)'::regprocedure,
      'public.accept_wanna_plan(uuid,integer,uuid,uuid)'::regprocedure,
      'public.decline_wanna_plan(uuid,integer)'::regprocedure,
      'public.resolve_own_active_wannas(uuid,text,uuid)'::regprocedure
    )
  ),
  'all iOS-facing Wanna RPCs are security definer with a pinned search path'
);
select ok(
  (
    select bool_and(
      has_function_privilege('authenticated', procedure.oid, 'execute')
        and not has_function_privilege('anon', procedure.oid, 'execute')
    )
    from pg_proc procedure
    where procedure.oid in (
      'public.save_own_wanna(jsonb,jsonb,jsonb,jsonb,jsonb)'::regprocedure,
      'public.own_wanna_events()'::regprocedure,
      'public.feed_wanna_context(uuid[])'::regprocedure,
      'public.list_wanna_plan_inbox(timestamptz,integer)'::regprocedure,
      'public.accept_wanna_plan(uuid,integer,uuid,uuid)'::regprocedure,
      'public.decline_wanna_plan(uuid,integer)'::regprocedure,
      'public.resolve_own_active_wannas(uuid,text,uuid)'::regprocedure
    )
  ),
  'only authenticated callers may execute Wanna RPCs'
);
select ok(
  not has_function_privilege('authenticated', 'app.visible_plan_participants(uuid,text,boolean)', 'execute')
    and not has_function_privilege('authenticated', 'app.fulfill_wannas_after_first_check_in()', 'execute'),
  'authenticated callers cannot invoke internal Wanna helpers directly'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('wanna_owner', 'wannaowner', 'Wanna Owner', false),
  ('wanna_invitee_one', 'wannainviteeone', 'Invitee One', false),
  ('wanna_invitee_two', 'wannainviteetwo', 'Invitee Two', false),
  ('wanna_stranger', 'wannastranger', 'Wanna Stranger', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('wanna_owner', 'wanna_invitee_one', 'profile'),
  ('wanna_invitee_one', 'wanna_owner', 'profile'),
  ('wanna_owner', 'wanna_invitee_two', 'profile'),
  ('wanna_invitee_two', 'wanna_owner', 'profile');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_owner', true);

select isnt_empty(
  $$
    select public.save_own_wanna(
      '{
        "canonical_name": "REC-357 Coffee",
        "category": "coffee_tea_sweets",
        "primary_category": "coffee_tea_sweets",
        "latitude": 34.05,
        "longitude": -118.25,
        "source_provider": "codex_rec357",
        "source_provider_place_id": "rec357-coffee",
        "confidence": 1
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb,
      '{
        "id": "91000000-0000-0000-0000-000000000001",
        "planned_date": "2026-08-28"
      }'::jsonb,
      '{
        "id": "92000000-0000-0000-0000-000000000001",
        "sharing": "feed",
        "invitee_user_ids": ["wanna_invitee_one", "wanna_invitee_two"]
      }'::jsonb
    )
  $$,
  'creator can atomically save one Wanna with multiple invitees and an optional date'
);

reset role;
insert into test_wanna_participant_ids (user_id, participant_id, invitation_generation)
select user_id, id, invitation_generation
from public.place_plan_participants
where plan_id = '92000000-0000-0000-0000-000000000001'
  and role = 'invitee';
insert into test_wanna_feed_ids (wanna_event_id, feed_event_id)
select wanna_event_id, id
from public.feed_events
where wanna_event_id = '91000000-0000-0000-0000-000000000001';
select is(
  (select count(*)::integer from public.place_wanna_events where user_id = 'wanna_owner'),
  1,
  'saving creates one immutable creator event'
);
select results_eq(
  $$ select sharing, planned_date from public.place_plans where id = '92000000-0000-0000-0000-000000000001' $$,
  $$ values ('feed'::text, date '2026-08-28') $$,
  'plan preserves Feed sharing and the optional date'
);
select is(
  (select count(*)::integer from public.place_plan_participants where plan_id = '92000000-0000-0000-0000-000000000001'),
  3,
  'one creator and two independent invitees are stored'
);
select is(
  (select count(*)::integer from public.feed_events where wanna_event_id = '91000000-0000-0000-0000-000000000001'),
  1,
  'creator produces exactly one Feed statement'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_invitee_one', true);
select is(
  (select count(*)::integer from public.list_wanna_plan_inbox(null, 50)),
  1,
  'each invitee receives an independent inbox invitation'
);

select isnt_empty(
  $$
    select public.accept_wanna_plan(
      participant.participant_id,
      participant.invitation_generation,
      '93000000-0000-0000-0000-000000000001',
      '94000000-0000-0000-0000-000000000001'
    )
    from test_wanna_participant_ids participant
    where participant.user_id = 'wanna_invitee_one'
  $$,
  'acceptance atomically creates the invitee-owned Wanna'
);
reset role;
select results_eq(
  $$
    select state, participant_wanna_event_id
    from public.place_plan_participants
    where plan_id = '92000000-0000-0000-0000-000000000001'
      and user_id = 'wanna_invitee_one'
  $$,
  $$ values ('accepted'::text, '93000000-0000-0000-0000-000000000001'::uuid) $$,
  'acceptance links only the invitee participant to the new event'
);
select is(
  (select status from public.user_places where user_id = 'wanna_invitee_one'),
  'wanna_go',
  'acceptance adds the place to the invitee Wanna state'
);
select is(
  (select source from public.place_wanna_events where id = '93000000-0000-0000-0000-000000000001'),
  'plan_acceptance',
  'accepted Wanna records its event source'
);
select is(
  (select count(*)::integer from public.feed_events where place_plan_id = '92000000-0000-0000-0000-000000000001'),
  1,
  'acceptance does not create a duplicate public Feed post'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_invitee_one', true);
select is(
  public.accept_wanna_plan(
    (select participant_id from test_wanna_participant_ids
      where user_id = 'wanna_invitee_one'),
    1,
    '93000000-0000-0000-0000-000000000001',
    '94000000-0000-0000-0000-000000000001'
  )->>'wanna_event_id',
  '93000000-0000-0000-0000-000000000001',
  'acceptance retries are idempotent'
);

select set_config('request.jwt.claim.sub', 'wanna_invitee_two', true);
select is(
  public.decline_wanna_plan(
    (select participant_id from test_wanna_participant_ids
      where user_id = 'wanna_invitee_two'),
    1
  ),
  true,
  'an invitee may decline independently'
);
reset role;
select is(
  (select count(*)::integer from public.place_wanna_events where user_id = 'wanna_invitee_two'),
  0,
  'declining creates no personal Wanna'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_invitee_one', true);
select is(
  (
    select jsonb_array_length(context.participants)
    from public.feed_wanna_context(array[
      (select feed_event_id from test_wanna_feed_ids
        where wanna_event_id = '91000000-0000-0000-0000-000000000001')
    ]) context
  ),
  2,
  'public Feed context shows the creator and accepted invitee, never the declined invitee'
);

select set_config('request.jwt.claim.sub', 'wanna_stranger', true);
select is(
  (
    select count(*)::integer
    from public.feed_wanna_context(array[
      (select feed_event_id from test_wanna_feed_ids
        where wanna_event_id = '91000000-0000-0000-0000-000000000001')
    ])
  ),
  0,
  'a non-follower cannot retrieve Feed plan context'
);

reset role;
update public.user_places set status = 'been' where user_id = 'wanna_owner';
insert into public.place_visits (
  id, user_place_id, visited_at, attribute_answers, backfilled_from_user_place
)
select
  '95000000-0000-0000-0000-000000000001', id, now(), '[]'::jsonb, false
from public.user_places where user_id = 'wanna_owner';

select is(
  (select state from public.place_wanna_events where id = '91000000-0000-0000-0000-000000000001'),
  'fulfilled',
  'first check-in fulfills all active creator Wannas without a prompt'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_owner', true);
select isnt_empty(
  $$
    select public.save_own_wanna(
      '{
        "canonical_name": "REC-357 Coffee",
        "category": "coffee_tea_sweets",
        "primary_category": "coffee_tea_sweets",
        "latitude": 34.05,
        "longitude": -118.25,
        "source_provider": "codex_rec357",
        "source_provider_place_id": "rec357-coffee",
        "confidence": 1
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb,
      '{"id": "91000000-0000-0000-0000-000000000002"}'::jsonb,
      null
    )
  $$,
  'a user may create another Wanna after visiting'
);
reset role;
select is(
  (select status from public.user_places where user_id = 'wanna_owner'),
  'been',
  'a return Wanna does not erase the Been compatibility state'
);
select results_eq(
  $$
    select state, was_visited_before
    from public.place_wanna_events
    where id = '91000000-0000-0000-0000-000000000002'
  $$,
  $$ values ('active'::text, true) $$,
  'the immutable event snapshot drives wants-to-go-back copy'
);

reset role;
insert into public.place_visits (
  id, user_place_id, visited_at, attribute_answers, backfilled_from_user_place
)
select
  '95000000-0000-0000-0000-000000000002', id, now(), '[]'::jsonb, false
from public.user_places where user_id = 'wanna_owner';
select is(
  (select state from public.place_wanna_events where id = '91000000-0000-0000-0000-000000000002'),
  'active',
  'a repeat check-in saves first and leaves the Wanna for the Keep or Remove choice'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_owner', true);
select is(
  public.resolve_own_active_wannas(
    (select place_id from public.user_places where user_id = 'wanna_owner'),
    'keep',
    '95000000-0000-0000-0000-000000000002'
  ),
  0,
  'Keep is a non-destructive resolution'
);
reset role;
select is(
  (select state from public.place_wanna_events where id = '91000000-0000-0000-0000-000000000002'),
  'active',
  'Keep preserves active Wanna state'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_owner', true);
select is(
  public.resolve_own_active_wannas(
    (select place_id from public.user_places where user_id = 'wanna_owner'),
    'remove',
    '95000000-0000-0000-0000-000000000002'
  ),
  1,
  'Remove fulfills the active Wanna explicitly'
);
reset role;
select is(
  (select state from public.place_wanna_events where id = '91000000-0000-0000-0000-000000000002'),
  'fulfilled',
  'Remove preserves history while removing current Wanna state'
);

reset role;
update public.profiles set is_private_profile = true where id = 'wanna_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'wanna_owner', true);
select isnt_empty(
  $$
    select public.save_own_wanna(
      '{
        "canonical_name": "REC-357 Coffee",
        "category": "coffee_tea_sweets",
        "primary_category": "coffee_tea_sweets",
        "latitude": 34.05,
        "longitude": -118.25,
        "source_provider": "codex_rec357",
        "source_provider_place_id": "rec357-coffee",
        "confidence": 1
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual"
      }'::jsonb,
      '[]'::jsonb,
      '{"id": "91000000-0000-0000-0000-000000000003"}'::jsonb,
      '{
        "id": "92000000-0000-0000-0000-000000000003",
        "sharing": "feed",
        "invitee_user_ids": ["wanna_invitee_one"]
      }'::jsonb
    )
  $$,
  'a private creator may still share a plan directly with an invited friend'
);
reset role;
select is(
  (select sharing from public.place_plans where id = '92000000-0000-0000-0000-000000000003'),
  'private',
  'private profile forces the plan to stay between participants'
);
select is(
  (select count(*)::integer from public.feed_events where wanna_event_id = '91000000-0000-0000-0000-000000000003'),
  0,
  'private plan produces no follower Feed event'
);
select is(
  (select count(*)::integer from public.place_wanna_events where user_id = 'wanna_owner'),
  3,
  'multiple immutable Wanna moments coexist for one user and place'
);

select * from finish();
rollback;
