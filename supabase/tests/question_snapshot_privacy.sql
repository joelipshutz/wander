begin;
create extension if not exists pgtap;
select plan(18);

select ok((select not prosecdef and provolatile = 'i'
  and ('search_path=""' = any(proconfig) or 'search_path=' = any(proconfig))
  from pg_proc where oid = 'app.private_taxonomy_snapshot_projection(jsonb)'::regprocedure),
  'snapshot projection retains immutable invoker and empty search path');
select ok((select prosecdef and provolatile = 's' and 'search_path=public, app' = any(proconfig)
  from pg_proc where oid = 'app.shared_visit_source_snapshot(uuid)'::regprocedure),
  'snapshot source retains stable definer and pinned search path');
select ok(not has_function_privilege('authenticated', 'app.private_taxonomy_snapshot_projection(jsonb)', 'execute')
  and not has_function_privilege('anon', 'app.private_taxonomy_snapshot_projection(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'app.shared_visit_source_snapshot(uuid)', 'execute')
  and not has_function_privilege('anon', 'app.shared_visit_source_snapshot(uuid)', 'execute'),
  'snapshot helpers remain private');
select ok(not has_column_privilege('authenticated', 'public.shared_visit_participants', 'invitation_snapshot', 'select'),
  'stored snapshots remain inaccessible through direct table reads');
select is(app.private_taxonomy_snapshot_projection(null), null::jsonb, 'null snapshot stays null');
select is(app.private_taxonomy_snapshot_projection('{"attribute_answers":false}'::jsonb)->'attribute_answers',
  '[]'::jsonb, 'malformed answer containers do not leak question values');
select is(app.private_taxonomy_snapshot_projection('{"attribute_answers":[{"question_key":"placeXdetail_keep","value":"one"},{"question_key":"customXquestion_keep","value":"two"}]}'::jsonb)->'attribute_answers',
  '[{"question_key":"placeXdetail_keep","value":"one"},{"question_key":"customXquestion_keep","value":"two"}]'::jsonb,
  'prefix filtering is literal and preserves unrelated keys');

-- Reserved fixture setup under the normal regression harness role. All actual
-- saves and invitations use supported authenticated RPCs and roll back.
insert into public.profiles(id, handle, display_name, is_private_profile) values
  ('user_codex_question_snapshot_owner', 'questionsnapshotowner', 'Question Snapshot Owner', false),
  ('user_codex_question_snapshot_viewer', 'questionsnapshotviewer', 'Question Snapshot Viewer', false);
insert into public.follows(follower_user_id, followed_user_id, source) values
  ('user_codex_question_snapshot_owner', 'user_codex_question_snapshot_viewer', 'username'),
  ('user_codex_question_snapshot_viewer', 'user_codex_question_snapshot_owner', 'username');
create temporary table question_snapshot_fixture(
  parent_id uuid, visit_id uuid, participant_id uuid, generation integer,
  full_answers jsonb, ordinary_answers jsonb
) on commit drop;
grant select, insert on question_snapshot_fixture to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_question_snapshot_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $fixture$
declare
  saved jsonb;
  invitation record;
  visit_id uuid := gen_random_uuid();
  ordinary jsonb := '[{"question_key":"coffee_tags","value_type":"multi_tag","value":["Quiet"]}]';
  answers jsonb;
begin
  answers := ordinary || '[{"question_key":"place_detail_outlets","value_type":"single_choice","value":"A few"},{"question_key":"place_detail_custom_5ebaaf58-4c10-4faa-a021-09b357aa461d","value_type":"text","value":{"schema_version":1,"prompt":"Can I bring a dog?","answer":"no"}},{"question_key":"custom_question_legacy","value_type":"text","value":"private legacy answer"},{"question_key":"restaurant_cuisine","value_type":"restaurant_cuisine","value":"Thai"}]'::jsonb;
  saved := public.save_own_check_in(
    '{"canonical_name":"Question Snapshot Regression","category":"coffee","latitude":0,"longitude":0,"source_provider":"test","source_provider_place_id":"question-snapshot-regression"}'::jsonb,
    '{"status":"been","visibility":"followers","source_type":"manual"}'::jsonb,
    answers,
    jsonb_build_object('id', visit_id, 'visited_at', '2026-09-02T12:00:00Z', 'note', 'Source note', 'attribute_answers', answers), null);
  select * into invitation from public.create_shared_visit_invites(visit_id, array['user_codex_question_snapshot_viewer']);
  insert into question_snapshot_fixture values ((saved->>'user_place_id')::uuid, visit_id,
    invitation.participant_id, invitation.invitation_generation, answers, ordinary);
end
$fixture$;

select is((select details.attribute_answers from public.own_place_visit_details(
  array[(select parent_id from question_snapshot_fixture)]) details
  where details.id = (select visit_id from question_snapshot_fixture)),
  (select full_answers from question_snapshot_fixture), 'owner hydration retains complete source answers');
select set_config('request.jwt.claim.sub', 'user_codex_question_snapshot_viewer', true);
select is((select source_snapshot->'attribute_answers' from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  (select ordinary_answers from question_snapshot_fixture), 'new invitation omits firsthand and private question answers');
select is((select source_snapshot->>'note' from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  'Source note', 'new invitation preserves the source note');
select is((select source_snapshot->'tags' from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  '["quiet"]'::jsonb, 'new invitation preserves ordinary tags');

reset role;
select is(app.shared_visit_source_snapshot((select visit_id from question_snapshot_fixture))->'attribute_answers',
  (select ordinary_answers from question_snapshot_fixture), 'snapshot construction applies the same question filter');

-- Model a pending snapshot stored before this migration. Only this reserved
-- fixture is changed; production migration never rewrites stored snapshots.
update public.shared_visit_participants
set invitation_snapshot = jsonb_build_object('note', 'Legacy note', 'tags', '["quiet"]'::jsonb,
  'attribute_answers', (select full_answers from question_snapshot_fixture))
where id = (select participant_id from question_snapshot_fixture);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_question_snapshot_viewer', true);
select is((select source_snapshot->'attribute_answers' from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  (select ordinary_answers from question_snapshot_fixture), 'context sanitizes an already-stored pending snapshot');
select is((select source_snapshot->'attribute_answers' from public.list_shared_visit_inbox(null, 50)
  where participant_id = (select participant_id from question_snapshot_fixture)),
  (select ordinary_answers from question_snapshot_fixture), 'inbox sanitizes an already-stored pending snapshot');
select is((select source_snapshot->>'note' from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  'Legacy note', 'legacy snapshot keeps unrelated content');
reset role;
select is((select invitation_snapshot->'attribute_answers' from public.shared_visit_participants
  where id = (select participant_id from question_snapshot_fixture)),
  (select full_answers from question_snapshot_fixture), 'reading sanitized snapshots does not rewrite stored history');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_question_snapshot_owner', true);
select public.delete_own_check_in((select visit_id from question_snapshot_fixture));
select set_config('request.jwt.claim.sub', 'user_codex_question_snapshot_viewer', true);
select is((select count(*)::integer from public.get_shared_visit_context(
  (select participant_id from question_snapshot_fixture), (select generation from question_snapshot_fixture))),
  0, 'owner-deleted check-in remains unavailable to its invitee');
reset role;
select ok(not has_function_privilege('anon', 'public.get_shared_visit_context(uuid,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.get_shared_visit_context(uuid,integer)', 'execute'),
  'existing authenticated context access remains unchanged');

select * from finish();
rollback;
