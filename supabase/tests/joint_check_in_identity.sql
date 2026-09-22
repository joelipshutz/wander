begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(18);

select has_column('public', 'shared_visit_groups', 'model_version', 'groups have an explicit version');
select has_column('public', 'feed_events', 'standalone_engagement_started_at', 'discussion identity survives empty engagement');
select ok((select relrowsecurity from pg_class where oid = 'public.joint_check_in_operations'::regclass), 'request receipts enforce RLS');
select ok(not has_table_privilege('authenticated', 'public.joint_check_in_operations', 'select,insert,update,delete'), 'clients cannot access request receipts directly');
select ok(not has_function_privilege('authenticated', 'app.guard_joint_check_in_identity()', 'execute'), 'identity guard is private');
select ok((select prosecdef and 'search_path=pg_catalog, public, app' = any(proconfig) from pg_proc where oid = 'app.guard_joint_check_in_identity()'::regprocedure), 'identity guard pins definer search path');
select is((select enabled from public.feature_flags where key = 'joint_check_ins_v2' and user_id is null), false, 'creation is off by default');

insert into public.profiles(id, handle, display_name)
values ('joint_identity_owner', 'jointidentityowner', 'Fictional Owner'),
       ('joint_identity_other', 'jointidentityother', 'Fictional Other');
insert into public.places(id, canonical_name, category, primary_category, latitude, longitude, source_provider, source_provider_place_id)
values ('a5660000-0000-0000-0000-000000000001', 'Joint identity fixture', 'coffee_tea_sweets', 'coffee_tea_sweets', 34.05, -118.25, 'codex_joint_identity_test', 'joint-identity-fixture');
select set_config('app.explicit_check_in', 'on', true);
insert into public.user_places(id, user_id, place_id, status, visibility, source_type)
values ('a5660000-0000-0000-0000-000000000002', 'joint_identity_owner', 'a5660000-0000-0000-0000-000000000001', 'been', 'followers', 'manual');
insert into public.place_visits(id, user_place_id, visited_at, backfilled_from_user_place)
values ('a5660000-0000-0000-0000-000000000003', 'a5660000-0000-0000-0000-000000000002', '2026-07-01T19:00:00Z', false),
       ('a5660000-0000-0000-0000-000000000004', 'a5660000-0000-0000-0000-000000000002', '2026-07-02T19:00:00Z', false);
insert into public.shared_visit_groups(id, source_visit_id, place_id, owner_user_id)
values ('a5660000-0000-0000-0000-000000000005', 'a5660000-0000-0000-0000-000000000003', 'a5660000-0000-0000-0000-000000000001', 'joint_identity_owner');
select is((select model_version::integer from public.shared_visit_groups where id = 'a5660000-0000-0000-0000-000000000005'), 1, 'legacy creation keeps version one');
insert into public.shared_visit_groups(id, source_visit_id, place_id, owner_user_id, model_version)
values ('a5660000-0000-0000-0000-000000000006', 'a5660000-0000-0000-0000-000000000004', 'a5660000-0000-0000-0000-000000000001', 'joint_identity_owner', 2);
insert into public.feed_events(id, actor_user_id, event_type, user_place_id, place_id, occurred_at, shared_visit_group_id)
values ('a5660000-0000-0000-0000-000000000007', 'joint_identity_owner', 'place_been', 'a5660000-0000-0000-0000-000000000002', 'a5660000-0000-0000-0000-000000000001', '2026-07-02T19:00:00Z', 'a5660000-0000-0000-0000-000000000006');
select is((select count(*) from public.feed_events where visit_id = 'a5660000-0000-0000-0000-000000000004'), 1::bigint, 'personal event still exists beside canonical event');
select ok((select visit_id is null from public.feed_events where id = 'a5660000-0000-0000-0000-000000000007'), 'canonical event does not impersonate a personal visit');
select throws_ok($$update public.shared_visit_groups set model_version = 2 where id = 'a5660000-0000-0000-0000-000000000005'$$, 'P0001', 'joint_check_in_version_immutable', 'legacy groups cannot be silently converted');
select throws_ok($$update public.shared_visit_groups set owner_user_id = 'joint_identity_other' where id = 'a5660000-0000-0000-0000-000000000006'$$, 'P0001', 'joint_check_in_identity_immutable', 'canonical ownership cannot be reassigned');
select throws_ok($$update public.feed_events set shared_visit_group_id = null where id = 'a5660000-0000-0000-0000-000000000007'$$, 'P0001', 'joint_check_in_event_identity_immutable', 'canonical event cannot become a personal conversation');
select throws_ok($$update public.feed_events set actor_user_id = 'joint_identity_other' where id = 'a5660000-0000-0000-0000-000000000007'$$, 'P0001', 'invalid_joint_check_in_event', 'canonical event author must match group owner');
select throws_ok($$update public.feed_events set occurred_at = '2026-07-03T19:00:00Z' where id = 'a5660000-0000-0000-0000-000000000007'$$, 'P0001', 'joint_check_in_event_identity_immutable', 'acceptance and edits cannot bump canonical date');
update public.feed_events set standalone_engagement_started_at = now() where visit_id = 'a5660000-0000-0000-0000-000000000004';
select throws_ok($$update public.feed_events set standalone_engagement_started_at = null where visit_id = 'a5660000-0000-0000-0000-000000000004'$$, 'P0001', 'joint_check_in_discussion_identity_immutable', 'removing all engagement cannot reset personal discussion identity');
update public.shared_visit_groups set revision = 2, cancelled_at = now(), closed_reason = 'owner_left' where id = 'a5660000-0000-0000-0000-000000000006';
select throws_ok($$update public.shared_visit_groups set revision = 1 where id = 'a5660000-0000-0000-0000-000000000006'$$, 'P0001', 'joint_check_in_revision_regression', 'group revision never moves backwards');
select throws_ok($$update public.shared_visit_groups set cancelled_at = null, closed_reason = null where id = 'a5660000-0000-0000-0000-000000000006'$$, 'P0001', 'joint_check_in_closed', 'closed canonical group cannot be reopened');

select * from finish();
rollback;
