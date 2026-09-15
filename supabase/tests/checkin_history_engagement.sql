begin;
create extension if not exists pgtap;
select plan(21);

insert into public.profiles (id, handle, display_name, is_private_profile) values
  ('user_codex_checkin_owner', 'codexcheckinowner', 'Check-in Owner', false),
  ('user_codex_checkin_viewer', 'codexcheckinviewer', 'Check-in Viewer', false),
  ('user_codex_checkin_stranger', 'codexcheckinstranger', 'Check-in Stranger', false);
insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_codex_checkin_viewer', 'user_codex_checkin_owner', 'username');
insert into public.places (id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id)
values ('a4930000-0000-0000-0000-000000000011', 'Check-in Regression', 'coffee', 0, 0, 'manual', 'checkin-regression');
insert into public.user_places (id, user_id, place_id, status, visibility, source_type)
values ('a4930000-0000-0000-0000-000000000012', 'user_codex_checkin_owner',
        'a4930000-0000-0000-0000-000000000011', 'been', 'followers', 'manual');

create temporary table checkin_engagement_fixture as
select parent.id as parent_id, visit.id as compatibility_id, event.id as parent_event_id
from public.user_places parent
join public.place_visits visit on visit.user_place_id = parent.id and visit.backfilled_from_user_place
join public.feed_events event on event.user_place_id = parent.id and event.visit_id is null and event.event_type = 'place_been'
where parent.id = 'a4930000-0000-0000-0000-000000000012';
grant select on checkin_engagement_fixture to authenticated;

select ok((select prosecdef and provolatile = 's'
    and 'search_path=pg_catalog, public, app' = any(proconfig)
  from pg_proc where oid = 'public.place_activity_engagement_summaries(uuid[])'::regprocedure),
  'summary RPC preserves stable security definer and pinned search path');
select ok(has_function_privilege('authenticated','public.place_activity_engagement_summaries(uuid[])','execute')
  and not has_function_privilege('anon','public.place_activity_engagement_summaries(uuid[])','execute'),
  'summary RPC preserves authenticated-only access');
select ok(not has_function_privilege('authenticated','app.backfill_missing_check_in_events()','execute')
  and not has_function_privilege('anon','app.backfill_missing_check_in_events()','execute'),
  'repair is private maintenance only');

select set_config('request.jwt.claim.sub', 'user_codex_checkin_owner', true);
set local role authenticated;
select is((public.place_activity_engagement_summaries(array[(select parent_id from checkin_engagement_fixture)])->0->>'visit_id'),
  (select compatibility_id::text from checkin_engagement_fixture), 'owner compatibility tile resolves its visit');
select is((public.place_activity_engagement_summaries(array[(select parent_id from checkin_engagement_fixture)])->0->>'activity_id'),
  (select parent_event_id::text from checkin_engagement_fixture), 'compatibility tile keeps the original conversation ID');
select ok((public.set_activity_like((select parent_event_id from checkin_engagement_fixture), true)->>'viewer_has_liked')::boolean,
  'owner can like their check-in');
select is(public.add_activity_comment((select parent_event_id from checkin_engagement_fixture), 'Owner comment')->'comment'->>'body',
  'Owner comment', 'owner can comment on their check-in');
select isnt(public.activity_detail((select parent_event_id from checkin_engagement_fixture)), null::jsonb,
  'owner activity is available for sharing');

select set_config('request.jwt.claim.sub', 'user_codex_checkin_viewer', true);
select is((public.place_activity_engagement_summaries(array[(select parent_id from checkin_engagement_fixture)])->0->>'visit_id'),
  (select compatibility_id::text from checkin_engagement_fixture), 'follower resolves the same compatibility visit');
select ok((public.set_activity_like((select parent_event_id from checkin_engagement_fixture), true)->>'viewer_has_liked')::boolean,
  'follower can like the check-in');
select is(public.add_activity_comment((select parent_event_id from checkin_engagement_fixture), 'Viewer comment')->'comment'->>'body',
  'Viewer comment', 'follower can comment on the check-in');
select isnt(public.activity_detail((select parent_event_id from checkin_engagement_fixture)), null::jsonb,
  'follower activity is available for sharing');
select set_config('request.jwt.claim.sub', 'user_codex_checkin_stranger', true);
select is(jsonb_array_length(public.place_activity_engagement_summaries(array[(select parent_id from checkin_engagement_fixture)])),
  0, 'stranger does not gain visibility from the compatibility mapping');
reset role;

-- Simulate an explicit visit predating the recording trigger. Only reserved
-- test fixtures are changed; the whole test (including repair) rolls back.
insert into public.place_visits (id,user_place_id,visited_at,backfilled_from_user_place)
values ('a4930000-0000-0000-0000-000000000013','a4930000-0000-0000-0000-000000000012',now()-interval '60 days',false);
delete from public.feed_events where visit_id='a4930000-0000-0000-0000-000000000013';
select app.backfill_missing_check_in_events();
select app.backfill_missing_check_in_events();
select is((select count(*)::integer from public.feed_events where visit_id='a4930000-0000-0000-0000-000000000013'),
  1,'repair creates exactly one event for an old explicit visit and is idempotent');
select is((select occurred_at from public.feed_events where visit_id='a4930000-0000-0000-0000-000000000013'),
  (select visited_at from public.place_visits where id='a4930000-0000-0000-0000-000000000013'),
  'repair retains the historical timestamp');
select is((select count(*)::integer from public.activity_comments where activity_id=(select parent_event_id from checkin_engagement_fixture)),
  2,'repair preserves the existing parent conversation');

select set_config('request.jwt.claim.sub', 'user_codex_checkin_viewer', true);
set local role authenticated;
select ok(exists(select 1 from jsonb_array_elements(public.place_activity_engagement_summaries(
  array[(select parent_id from checkin_engagement_fixture)])) event
  where event->>'visit_id'='a4930000-0000-0000-0000-000000000013'
    and event->>'activity_id' <> (select parent_event_id::text from checkin_engagement_fixture)),
  'an old explicit repeat resolves its own conversation instead of borrowing the compatibility event');
reset role;

-- Socially saved Been records use place_saved rather than place_been.
insert into public.places (id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id)
values ('a4930000-0000-0000-0000-000000000021', 'Social Check-in Regression', 'coffee', 0, 0, 'manual', 'social-checkin-regression');
insert into public.user_places (id, user_id, place_id, status, visibility, source_type)
values ('a4930000-0000-0000-0000-000000000022', 'user_codex_checkin_owner',
        'a4930000-0000-0000-0000-000000000021', 'been', 'followers', 'social_save');
select is((public.place_activity_engagement_summaries(array['a4930000-0000-0000-0000-000000000022'::uuid])->0->>'visit_id'),
  (select id::text from public.place_visits where user_place_id='a4930000-0000-0000-0000-000000000022' and backfilled_from_user_place),
  'social-save compatibility visit resolves its activity');
select is((public.place_activity_engagement_summaries(array['a4930000-0000-0000-0000-000000000022'::uuid])->0->>'event_type'),
  'place_saved', 'social-save compatibility keeps the original event kind');

select set_config('request.jwt.claim.sub', 'user_codex_checkin_owner', true);
set local role authenticated;
select public.delete_own_check_in('a4930000-0000-0000-0000-000000000013');
select set_config('request.jwt.claim.sub', 'user_codex_checkin_viewer', true);
select ok(not exists(select 1 from jsonb_array_elements(public.place_activity_engagement_summaries(
  array[(select parent_id from checkin_engagement_fixture)])) event
  where event->>'visit_id'='a4930000-0000-0000-0000-000000000013'), 'deleted explicit check-in is absent from engagement history');
reset role;
select app.backfill_missing_check_in_events();
select ok(not app.can_read_activity_event('user_codex_checkin_viewer',
  (select id from public.feed_events where visit_id='a4930000-0000-0000-0000-000000000013')),
  'repair never revives engagement on an owner-deleted check-in');
select * from finish();
rollback;
