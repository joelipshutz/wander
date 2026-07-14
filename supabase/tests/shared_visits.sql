begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(70);

create temporary table test_shared_participant_ids (
  user_id text primary key,
  participant_id uuid not null,
  invitation_generation integer not null
) on commit drop;
grant select, insert, update on table test_shared_participant_ids to authenticated;

select has_table('public', 'shared_visit_groups', 'shared visit groups table exists');
select has_table('public', 'shared_visit_participants', 'shared visit participants table exists');
select has_table('public', 'shared_visit_operations', 'shared visit operation ledger exists');
select has_column('public', 'profiles', 'is_private_profile', 'profiles persist account privacy');
select has_column(
  'public',
  'notification_preferences',
  'shared_visits_enabled',
  'notification preferences include shared visits'
);
select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'created_at'
  ),
  'shared visits preserve the profile creation timestamp contract'
);

select ok(
  not has_table_privilege('authenticated', 'public.shared_visit_groups', 'select'),
  'authenticated users cannot read shared visit groups directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.shared_visit_participants', 'select'),
  'authenticated users cannot read invitation snapshots directly'
);
select ok(
  not has_table_privilege('authenticated', 'public.shared_visit_operations', 'select'),
  'authenticated users cannot read operation ledger rows directly'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.create_shared_visit_invites(uuid,text[])'::regprocedure),
  true,
  'invite creation is a security-definer RPC'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.list_shared_visit_invitees(uuid)'::regprocedure),
  true,
  'invitee listing is a security-definer RPC'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.set_shared_visit_invitees(uuid,text[])'::regprocedure),
  true,
  'invitee reconciliation is a security-definer RPC'
);
select ok(
  (
    select bool_and('search_path=public, app' = any(coalesce(proconfig, array[]::text[])))
    from pg_proc
    where oid in (
      'public.list_shared_visit_invitees(uuid)'::regprocedure,
      'public.set_shared_visit_invitees(uuid,text[])'::regprocedure
    )
  ),
  'invitee management RPCs pin their search path'
);
select ok(
  has_function_privilege('authenticated', 'public.list_shared_visit_invitees(uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.set_shared_visit_invitees(uuid,text[])', 'execute'),
  'authenticated users can manage invitees through the narrow RPCs'
);
select ok(
  not has_function_privilege('anon', 'public.list_shared_visit_invitees(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.set_shared_visit_invitees(uuid,text[])', 'execute'),
  'anonymous users cannot manage invitees'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[])'::regprocedure),
  true,
  'acceptance is a security-definer RPC'
);
select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[])'::regprocedure
  ),
  'acceptance pins its search path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[])',
    'execute'
  ),
  'authenticated users can accept an invitation through the narrow RPC'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.accept_shared_visit(uuid,integer,integer,uuid,uuid,uuid,jsonb,jsonb,jsonb,uuid[])',
    'execute'
  ),
  'anonymous users cannot accept an invitation'
);
select ok(
  not has_function_privilege('authenticated', 'app.apply_private_profile_shared_visit_rules()', 'execute'),
  'authenticated users cannot invoke the private-profile trigger directly'
);
select has_trigger(
  'public',
  'blocks',
  'blocks_cancel_shared_visits',
  'hard blocks trigger shared-visit cleanup'
);
select is(
  (select prosecdef from pg_proc where oid = 'app.cancel_shared_visits_after_block()'::regprocedure),
  true,
  'hard-block cleanup is a security-definer trigger function'
);
select ok(
  not has_function_privilege('authenticated', 'app.cancel_shared_visits_after_block()', 'execute'),
  'authenticated users cannot invoke hard-block cleanup directly'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.current_profile()'::regprocedure),
  false,
  'current profile remains security invoker'
);
select ok(
  (
    select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.current_profile()'::regprocedure
  ),
  'current profile keeps a pinned search path'
);
select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and tablename = 'notification_device_tokens'
      and indexname = 'notification_device_tokens_active_device_idx'
      and indexdef ilike '%unique%where is_active%'
  ),
  'one physical APNs token can be active for only one account'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('shared_owner', 'sharedowner', 'Joe Owner', false),
  ('shared_recipient', 'sharedrecipient', 'Sarah Recipient', false),
  ('shared_friend_two', 'sharedfriendtwo', 'Maya Friend', false),
  ('shared_friend_three', 'sharedfriendthree', 'Ari Friend', false),
  ('shared_private', 'sharedprivate', 'Private Friend', true),
  ('shared_stranger', 'sharedstranger', 'Stranger', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('shared_owner', 'shared_recipient', 'profile'),
  ('shared_recipient', 'shared_owner', 'profile'),
  ('shared_owner', 'shared_friend_two', 'profile'),
  ('shared_friend_two', 'shared_owner', 'profile'),
  ('shared_owner', 'shared_friend_three', 'profile'),
  ('shared_friend_three', 'shared_owner', 'profile'),
  ('shared_owner', 'shared_private', 'profile'),
  ('shared_private', 'shared_owner', 'profile');

insert into public.places (
  id, canonical_name, category, primary_category, latitude, longitude,
  source_provider, source_provider_place_id
)
values (
  '81000000-0000-0000-0000-000000000001',
  'Shared Visit Cafe',
  'coffee_tea_sweets',
  'coffee_tea_sweets',
  34.05,
  -118.25,
  'codex_shared_visit_test',
  'shared-visit-cafe'
);

insert into public.user_places (
  id, user_id, place_id, status, note, rating_score, visibility,
  nearby_confirmed, visited_at, source_type
)
values (
  '82000000-0000-0000-0000-000000000001',
  'shared_owner',
  '81000000-0000-0000-0000-000000000001',
  'wanna_go',
  'Owner note inherited only by invited recipients',
  4.5,
  'mutuals',
  false,
  '2026-07-01T19:00:00Z',
  'manual'
);

insert into public.place_visits (
  id, user_place_id, visited_at, note, rating_score, attribute_answers, backfilled_from_user_place
)
values (
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  '2026-07-01T19:00:00Z',
  'Owner visit snapshot note',
  4.5,
  '[{"question_key":"restaurant_vibe","value_type":"multi_tag","value":["cozy"]}]'::jsonb,
  false
);

update public.user_places
set status = 'been'
where id = '82000000-0000-0000-0000-000000000001';

insert into public.visit_photos (
  id, visit_id, storage_bucket, storage_path, content_type,
  byte_size, width, height, sort_order, upload_state
)
values (
  '84000000-0000-0000-0000-000000000001',
  '83000000-0000-0000-0000-000000000001',
  'visit-photos',
  'shared_owner/83000000-0000-0000-0000-000000000001/84000000-0000-0000-0000-000000000001.jpg',
  'image/jpeg',
  1200,
  100,
  80,
  0,
  'uploaded'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_recipient', true);
select public.register_push_token(
  'abababababababababababababababababababababababababababababababab',
  'sandbox',
  'com.grayline.wander'
);

select is(
  (public.get_notification_preferences()).shared_visits_enabled,
  false,
  'shared visit notifications default off before one-tap enrollment'
);
select is(
  (public.get_notification_preferences()).push_enabled,
  false,
  'push delivery defaults off before one-tap enrollment'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"shared_visits_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'shared_friend_two', true);
select public.register_push_token(
  'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"shared_visits_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'shared_owner', true);

insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.create_shared_visit_invites(
  '83000000-0000-0000-0000-000000000001',
  array['shared_recipient']
);

select is(
  (select count(*)::integer from test_shared_participant_ids),
  1,
  'owner can invite one mutual friend to a visible Been visit'
);
select is(
  (
    select companion_user_id
    from public.get_shared_visit_companion_context(
      array['83000000-0000-0000-0000-000000000001'::uuid]
    )
  ),
  'shared_recipient',
  'source owner sees pending friend attribution immediately'
);
select is(
  (
    select invitee_user_id
    from public.list_shared_visit_invitees(
      '83000000-0000-0000-0000-000000000001'
    )
  ),
  'shared_recipient',
  'owner can load the existing invitee selection for editing'
);

reset role;

select is(
  (
    select status
    from public.shared_visit_participants
    where user_id = 'shared_recipient'
  ),
  'pending',
  'invite creates a pending participant'
);
select is(
  (
    select notification_type
    from public.notification_events
    where recipient_user_id = 'shared_recipient'
    order by created_at desc
    limit 1
  ),
  'shared_visit',
  'invite queues the dedicated shared-visit notification'
);
select results_eq(
  $$
    select title, body
    from public.notification_events
    where recipient_user_id = 'shared_recipient'
    order by created_at desc
    limit 1
  $$,
  $$ values ('Shared visit'::text, 'Joe Owner saved Shared Visit Cafe with you. Add your version of the visit.'::text) $$,
  'shared-visit notification uses recipient-safe copy'
);
select ok(
  (
    select data ?& array['participant_id', 'invitation_generation', 'place_id']
      and not (data ?| array['note', 'rating_score', 'latitude', 'longitude'])
    from public.notification_events
    where recipient_user_id = 'shared_recipient'
    order by created_at desc
    limit 1
  ),
  'shared-visit payload contains routing ids and no private snapshot fields'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_recipient', true);

select is(
  (
    select count(*)::integer
    from public.list_shared_visit_inbox(null, 50)
  ),
  1,
  'recipient inbox returns its pending invitation'
);
select is(
  (
    select source_snapshot->>'note'
    from public.get_shared_visit_context(
      (select participant_id from test_shared_participant_ids where user_id = 'shared_recipient'),
      1
    )
  ),
  'Owner visit snapshot note',
  'exact invitation context returns the generation snapshot'
);
select is(
  (
    select jsonb_array_length(source_snapshot->'photos')
    from public.get_shared_visit_context(
      (select participant_id from test_shared_participant_ids where user_id = 'shared_recipient'),
      1
    )
  ),
  1,
  'pending context includes uploaded source photo metadata'
);

select set_config('request.jwt.claim.sub', 'shared_stranger', true);
select is(
  (
    select count(*)::integer
    from public.get_shared_visit_context(
      (select participant_id from test_shared_participant_ids where user_id = 'shared_recipient'),
      1
    )
  ),
  0,
  'another account cannot resolve a recipient invitation'
);

select set_config('request.jwt.claim.sub', 'shared_recipient', true);

select is(
  public.accept_shared_visit(
    (select participant_id from test_shared_participant_ids where user_id = 'shared_recipient'),
    1,
    1,
    '85000000-0000-0000-0000-000000000001',
    '86000000-0000-0000-0000-000000000001',
    '87000000-0000-0000-0000-000000000001',
    '{"visibility":"mutuals"}'::jsonb,
    '{"visited_at":"2026-07-01T19:00:00Z","note":"Sarah edited her version","rating_score":5,"attribute_answers":[]}'::jsonb,
    '[]'::jsonb,
    array['84000000-0000-0000-0000-000000000001'::uuid]
  )->>'status',
  'accepted',
  'recipient can atomically accept the exact invitation generation'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.user_places
    where user_id = 'shared_recipient'
      and place_id = '81000000-0000-0000-0000-000000000001'
      and deleted_at is null
  ),
  1,
  'acceptance creates one independently owned recipient place'
);
select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '86000000-0000-0000-0000-000000000001'
      and deleted_at is null
  ),
  1,
  'acceptance creates exactly one recipient visit'
);
select is(
  (
    select note
    from public.place_visits
    where id = '87000000-0000-0000-0000-000000000001'
  ),
  'Sarah edited her version',
  'recipient edits are persisted only on the recipient visit'
);
select is(
  (
    select note
    from public.place_visits
    where id = '83000000-0000-0000-0000-000000000001'
  ),
  'Owner visit snapshot note',
  'recipient acceptance does not mutate the source visit'
);
select ok(
  (
    select storage_path like 'shared_recipient/87000000-0000-0000-0000-000000000001/%'
      and upload_state = 'pending_upload'
    from public.visit_photos
    where visit_id = '87000000-0000-0000-0000-000000000001'
  ),
  'selected inherited photo gets recipient-owned pending copy metadata'
);
select ok(
  (
    select status = 'accepted' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_recipient'
  ),
  'accepted invitations clear their private snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_recipient', true);

select is(
  public.accept_shared_visit(
    (select participant_id from test_shared_participant_ids where user_id = 'shared_recipient'),
    1,
    1,
    '85000000-0000-0000-0000-000000000001',
    '86000000-0000-0000-0000-000000000001',
    '87000000-0000-0000-0000-000000000001',
    '{"visibility":"mutuals"}'::jsonb,
    '{"visited_at":"2026-07-01T19:00:00Z","note":"Sarah edited her version","rating_score":5,"attribute_answers":[]}'::jsonb,
    '[]'::jsonb,
    array['84000000-0000-0000-0000-000000000001'::uuid]
  )->>'visit_id',
  '87000000-0000-0000-0000-000000000001',
  'retrying the same acceptance returns the committed operation result'
);

reset role;

select is(
  (
    select count(*)::integer
    from public.place_visits
    where user_place_id = '86000000-0000-0000-0000-000000000001'
      and deleted_at is null
  ),
  1,
  'acceptance retries cannot duplicate a visit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
select is(
  (
    select companion_user_id
    from public.get_shared_visit_companion_context(
      array['83000000-0000-0000-0000-000000000001'::uuid]
    )
  ),
  'shared_recipient',
  'source owner sees the accepted friend attribution'
);

select set_config('request.jwt.claim.sub', 'shared_recipient', true);
select is(
  (
    select companion_user_id
    from public.get_shared_visit_companion_context(
      array['87000000-0000-0000-0000-000000000001'::uuid]
    )
  ),
  'shared_owner',
  'recipient sees the source owner attribution'
);

select set_config('request.jwt.claim.sub', 'shared_owner', true);
insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.create_shared_visit_invites(
  '83000000-0000-0000-0000-000000000001',
  array['shared_friend_two']
);

select set_config('request.jwt.claim.sub', 'shared_friend_two', true);
select ok(
  public.decline_shared_visit(
    (select participant_id from test_shared_participant_ids where user_id = 'shared_friend_two'),
    1
  ),
  'a pending recipient can decline its invitation'
);

select set_config('request.jwt.claim.sub', 'shared_owner', true);
insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.create_shared_visit_invites(
  '83000000-0000-0000-0000-000000000001',
  array['shared_friend_two']
)
on conflict (user_id) do update set
  participant_id = excluded.participant_id,
  invitation_generation = excluded.invitation_generation;

reset role;

select is(
  (
    select invitation_generation
    from public.shared_visit_participants
    where user_id = 'shared_friend_two'
  ),
  2,
  'reinviting a terminal participant creates a new generation'
);
select ok(
  (
    select status = 'pending' and invitation_snapshot is not null
    from public.shared_visit_participants
    where user_id = 'shared_friend_two'
  ),
  'new invitation generation gets a fresh pending snapshot'
);

insert into public.blocks (blocker_user_id, blocked_user_id)
values ('shared_friend_two', 'shared_owner');

select ok(
  (
    select status = 'cancelled' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_friend_two'
  ),
  'blocking either side cancels the owner-recipient relationship and erases its snapshot'
);
select is(
  (
    select status
    from public.notification_events
    where data->>'participant_id' = (
      select participant_id::text
      from test_shared_participant_ids
      where user_id = 'shared_friend_two'
    )
    order by created_at desc
    limit 1
  ),
  'skipped',
  'blocking skips an unsent shared-visit notification'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.create_shared_visit_invites(
  '83000000-0000-0000-0000-000000000001',
  array['shared_friend_three']
);

select is(
  (
    select count(*)::integer
    from public.set_shared_visit_invitees(
      '83000000-0000-0000-0000-000000000001',
      array['shared_friend_three']
    )
  ),
  1,
  'exact reconciliation keeps the selected friend and removes other active participants'
);

reset role;

select ok(
  (
    select status = 'removed' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_recipient'
  ),
  'removing an accepted friend clears the shared attribution and private snapshot'
);
select is(
  (
    select count(*)::integer
    from public.place_visits
    where id = '87000000-0000-0000-0000-000000000001'
      and deleted_at is null
  ),
  1,
  'removing an accepted friend preserves their independently owned visit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
select is(
  (
    select invitee_user_id
    from public.list_shared_visit_invitees(
      '83000000-0000-0000-0000-000000000001'
    )
  ),
  'shared_friend_three',
  'invitee listing reflects the reconciled selection'
);

insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.set_shared_visit_invitees(
  '83000000-0000-0000-0000-000000000001',
  array['shared_recipient', 'shared_friend_three']
)
on conflict (user_id) do update set
  participant_id = excluded.participant_id,
  invitation_generation = excluded.invitation_generation;

select is(
  (
    select invitation_generation
    from test_shared_participant_ids
    where user_id = 'shared_recipient'
  ),
  2,
  're-adding a removed friend creates a fresh invitation generation'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
select throws_ok(
  $$
    select *
    from public.create_shared_visit_invites(
      '83000000-0000-0000-0000-000000000001',
      array['shared_private']
    )
  $$,
  'P0001',
  'invalid_shared_visit_invitees',
  'private profiles cannot be added to visits'
);

select set_config('request.jwt.claim.sub', 'shared_recipient', true);
select is(
  (public.update_profile_privacy(true, 'self')).is_private_profile,
  true,
  'recipient can make account privacy authoritative on the server'
);

reset role;

select is(
  (
    select visibility
    from public.user_places
    where id = '86000000-0000-0000-0000-000000000001'
  ),
  'self',
  'private-profile transition makes the independent recipient place private'
);
select ok(
  (
    select status = 'cancelled' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_recipient'
  ),
  'private-profile transition removes accepted attribution and clears snapshots'
);
select is(
  (
    select count(*)::integer
    from public.place_visits
    where id = '87000000-0000-0000-0000-000000000001'
      and deleted_at is null
  ),
  1,
  'privacy transition preserves the recipient independent visit'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
select is(
  (
    select count(*)::integer
    from public.set_shared_visit_invitees(
      '83000000-0000-0000-0000-000000000001',
      array[]::text[]
    )
  ),
  0,
  'owner can clear every friend from an existing shared visit'
);

reset role;

select ok(
  (
    select status = 'removed' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_friend_three'
  ),
  'clearing the friend set removes pending attribution and its snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_owner', true);
insert into test_shared_participant_ids(user_id, participant_id, invitation_generation)
select invitee_user_id, participant_id, invitation_generation
from public.set_shared_visit_invitees(
  '83000000-0000-0000-0000-000000000001',
  array['shared_friend_three']
)
on conflict (user_id) do update set
  participant_id = excluded.participant_id,
  invitation_generation = excluded.invitation_generation;

reset role;

update public.user_places
set visibility = 'self'
where id = '82000000-0000-0000-0000-000000000001';

select ok(
  (
    select cancelled_at is not null
    from public.shared_visit_groups
    where source_visit_id = '83000000-0000-0000-0000-000000000001'
  ),
  'making the source place stealth cancels the shared occasion'
);
select ok(
  (
    select status = 'cancelled' and invitation_snapshot is null
    from public.shared_visit_participants
    where user_id = 'shared_friend_three'
  ),
  'source stealth transition clears every still-pending invitation snapshot'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'shared_friend_three', true);
select is(
  (
    select route_status
    from public.resolve_shared_visit_destination(
      (select participant_id from test_shared_participant_ids where user_id = 'shared_friend_three'),
      (select invitation_generation from test_shared_participant_ids where user_id = 'shared_friend_three')
    )
  ),
  'cancelled',
  'generation-aware resolver reports the terminal destination'
);

do $pgtap_finish$
declare
  diagnostics text;
begin
  select string_agg(result.message, E'\n')
  into diagnostics
  from finish() as result(message);
  if diagnostics is not null then
    raise exception 'Shared Visits pgTAP failures:%', E'\n' || diagnostics;
  end if;
end
$pgtap_finish$;

rollback;
