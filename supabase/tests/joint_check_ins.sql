begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(13);

insert into public.profiles(id, handle, display_name)
values ('joint_core_owner', 'jointcoreowner', 'Fictional Ryan'),
       ('joint_core_guest', 'jointcoreguest', 'Fictional Joe');
insert into public.follows(follower_user_id, followed_user_id, source)
values ('joint_core_owner', 'joint_core_guest', 'profile'),
       ('joint_core_guest', 'joint_core_owner', 'profile');
create temporary table joint_results(name text primary key, result jsonb);
grant all on joint_results to authenticated;

create function pg_temp.create_joint_fixture(
  request_id uuid default 'b5660000-0000-0000-0000-000000000001',
  visit_id uuid default 'b5660000-0000-0000-0000-000000000002',
  note text default 'Fictional first contribution',
  invitees text[] default array['joint_core_guest']::text[],
  consent integer default 1
)
returns jsonb language sql as $$
  select public.save_joint_check_in(
    '{"canonical_name":"Joint Core Cafe","category":"coffee_tea_sweets","latitude":34.05,"longitude":-118.25,"source_provider":"codex_joint_core_test","source_provider_place_id":"joint-core-cafe"}',
    '{"status":"been","visibility":"followers","source_type":"manual"}', '[]',
    jsonb_build_object('id', visit_id, 'visited_at', '2026-07-02T19:00:00Z', 'note', note, 'rating_score', 4.5, 'attribute_answers', '[]'::jsonb),
    null, invitees, request_id, consent)
$$;

select set_config('request.jwt.claim.sub', 'joint_core_owner', true);
set local role authenticated;
select throws_ok($$select pg_temp.create_joint_fixture()$$, 'P0001', 'joint_check_in_creation_unavailable', 'creation fails closed while flag is off');
reset role;
select is((select count(*) from public.place_visits where id = 'b5660000-0000-0000-0000-000000000002'), 0::bigint, 'disabled creation never publishes a personal visit');
update public.feature_flags set enabled = true where key = 'joint_check_ins_v2' and user_id is null;
set local role authenticated;
select lives_ok($$insert into joint_results values ('created', pg_temp.create_joint_fixture())$$, 'atomic joint publication succeeds for a mutual invitation');
select is((select result->>'model_version' from joint_results where name = 'created'), '2', 'result explicitly carries v2 identity');
select is((pg_temp.create_joint_fixture()->>'canonical_activity_id'), (select result->>'canonical_activity_id' from joint_results where name = 'created'), 'lost-response retry returns the same conversation');
select throws_ok($$select pg_temp.create_joint_fixture(note := 'Changed under same operation')$$, 'P0001', 'joint_check_in_request_conflict', 'request cannot be reused with a different payload');
select throws_ok($$select pg_temp.create_joint_fixture(request_id := 'b5660000-0000-0000-0000-000000000003')$$, 'P0001', 'joint_check_in_already_published', 'published visit cannot be silently converted by a different request');
select throws_ok($$select pg_temp.create_joint_fixture(request_id := 'b5660000-0000-0000-0000-000000000004', visit_id := 'b5660000-0000-0000-0000-000000000005', invitees := array['not_a_mutual'])$$, 'P0001', 'invalid_joint_check_in_invitees', 'invalid invitee rejects the whole publication');
reset role;
select is((select count(*) from public.place_visits where id = 'b5660000-0000-0000-0000-000000000005'), 0::bigint, 'invalid invitee leaves no personal visit behind');
select is((select count(*) from public.feed_events where visit_id = 'b5660000-0000-0000-0000-000000000002' or shared_visit_group_id = (select (result->>'group_id')::uuid from joint_results where name = 'created')), 2::bigint, 'one personal event and one distinct canonical event commit together');
select is((select count(*) from public.shared_visit_participants where group_id = (select (result->>'group_id')::uuid from joint_results where name = 'created') and status = 'pending'), 1::bigint, 'retry does not duplicate the pending invitation');
update public.feature_flags set enabled = false where key = 'joint_check_ins_v2' and user_id is null;
set local role authenticated;
select lives_ok($$select pg_temp.create_joint_fixture()$$, 'committed creation replay remains available after kill switch');
reset role;
update public.shared_visit_groups set cancelled_at = now(), closed_reason = 'test_closure'
where id = (select (result->>'group_id')::uuid from joint_results where name = 'created');
set local role authenticated;
select throws_ok($$select pg_temp.create_joint_fixture()$$, 'P0001', 'joint_check_in_closed', 'replay after closure cannot resurrect the group');
reset role;

select * from finish();
rollback;
