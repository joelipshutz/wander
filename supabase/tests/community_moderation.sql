begin;

create extension if not exists pgtap;

select plan(45);

select has_table('public', 'content_reports', 'content reports table exists');
select has_table('public', 'moderation_report_events', 'moderation audit table exists');

select is(
  (select relrowsecurity from pg_class where oid = 'public.content_reports'::regclass),
  true,
  'content reports enforce RLS'
);
select is(
  (select relrowsecurity from pg_class where oid = 'public.moderation_report_events'::regclass),
  true,
  'moderation events enforce RLS'
);
select ok(
  not has_table_privilege('authenticated', 'public.content_reports', 'select'),
  'authenticated clients cannot read private reports'
);
select ok(
  not has_table_privilege('authenticated', 'public.moderation_report_events', 'select'),
  'authenticated clients cannot read the moderation audit trail'
);
select ok(
  has_table_privilege('service_role', 'public.content_reports', 'select,update'),
  'service role can operate the moderation queue'
);
select ok(
  has_table_privilege('service_role', 'public.moderation_report_events', 'select,insert'),
  'service role can read and append moderation events'
);

select has_function(
  'public',
  'submit_content_report',
  array['text', 'text', 'text', 'text', 'text']
);
select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.submit_content_report(text,text,text,text,text)'::regprocedure
  ),
  true,
  'report submission is a narrow security definer RPC'
);
select ok(
  (
    select 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.submit_content_report(text,text,text,text,text)'::regprocedure
  ),
  'report submission pins search_path'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.submit_content_report(text,text,text,text,text)',
    'execute'
  ),
  'authenticated clients can submit reports'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.submit_content_report(text,text,text,text,text)',
    'execute'
  ),
  'anonymous callers cannot submit reports'
);
select ok(
  not has_function_privilege('authenticated', 'app.community_text_allowed(text)', 'execute'),
  'clients cannot bypass the write-boundary content guard helper'
);

select ok(app.community_text_allowed('A quiet table with great noodles'), 'ordinary place text is allowed');
select ok(not app.community_text_allowed('you are a nigger'), 'an explicit blocked token is rejected');
select ok(not app.community_text_allowed('n1gg3r'), 'basic leetspeak evasion is rejected');
select ok(not app.community_text_allowed('Go kill yourself'), 'a targeted dangerous phrase is rejected');
select is(
  (
    select count(*)::integer
    from pg_trigger
    where not tgisinternal
      and tgname in (
        'profiles_community_text_guard',
        'user_places_community_text_guard',
        'place_visits_community_text_guard',
        'place_attributes_community_text_guard',
        'place_lists_community_text_guard',
        'activity_comments_community_text_guard'
      )
  ),
  6,
  'every current shared-text table has a server-side guard'
);

insert into public.profiles (id, handle, display_name, bio, is_private_profile)
values
  ('moderation_reporter', 'moderationreporter', 'Moderation Reporter', null, false),
  ('moderation_target', 'moderationtarget', 'Moderation Target', 'Target profile snapshot', false),
  ('moderation_stranger', 'moderationstranger', 'Moderation Stranger', null, false);

insert into public.follows (follower_user_id, followed_user_id, source)
values ('moderation_reporter', 'moderation_target', 'profile');

insert into public.places (
  id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id
) values (
  'b1000000-0000-0000-0000-000000000001',
  'Moderation Cafe',
  'coffee',
  34.0522,
  -118.2437,
  'codex_moderation',
  'moderation-cafe'
);

insert into public.user_places (
  id, user_id, place_id, status, note, visibility, source_type
) values (
  'b1100000-0000-0000-0000-000000000001',
  'moderation_target',
  'b1000000-0000-0000-0000-000000000001',
  'been',
  'A reportable shared place note',
  'followers',
  'manual'
);

create temporary table moderation_test_context (
  activity_id uuid not null
) on commit drop;
insert into moderation_test_context (activity_id)
select event.id
from public.feed_events event
where event.user_place_id = 'b1100000-0000-0000-0000-000000000001'
limit 1;
grant select on moderation_test_context to authenticated;

insert into public.activity_comments (id, activity_id, author_user_id, body)
select
  'b1200000-0000-0000-0000-000000000001',
  context.activity_id,
  'moderation_target',
  'A reportable comment'
from moderation_test_context context;

insert into public.place_lists (
  id, owner_user_id, name, description, visibility
) values (
  'b1300000-0000-0000-0000-000000000001',
  'moderation_target',
  'Reportable list',
  'A reportable list description',
  'followers'
);

insert into public.place_visits (
  id, user_place_id, visited_at, note, attribute_answers, backfilled_from_user_place
) values (
  'b1400000-0000-0000-0000-000000000001',
  'b1100000-0000-0000-0000-000000000001',
  now(),
  'A reportable visit',
  '[]'::jsonb,
  false
);

insert into public.visit_photos (
  id, visit_id, storage_bucket, storage_path, content_type, sort_order, upload_state
) values (
  'b1500000-0000-0000-0000-000000000001',
  'b1400000-0000-0000-0000-000000000001',
  'visit-photos',
  'moderation_target/b1400000-0000-0000-0000-000000000001/b1500000-0000-0000-0000-000000000001.jpg',
  'image/jpeg',
  0,
  'uploaded'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'moderation_reporter', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select isnt(
  public.submit_content_report(
    'profile',
    'moderation_target',
    'moderation_target',
    'harassment',
    'Please review this profile.'
  )->>'report_id',
  null,
  'viewer can report a visible profile'
);
select is(
  (
    select (result->>'is_duplicate')::boolean
    from (
      select public.submit_content_report(
        'profile', 'moderation_target', 'moderation_target', 'privacy', null
      ) as result
    ) submitted
  ),
  false,
  'a first report is not marked duplicate'
);

reset role;

select is(
  (
    select status from public.content_reports
    where reporter_user_id = 'moderation_reporter' and reason = 'harassment'
  ),
  'queued',
  'new reports enter the moderation queue'
);
select is(
  (
    select priority from public.content_reports
    where reporter_user_id = 'moderation_reporter' and reason = 'harassment'
  ),
  'normal',
  'non-safety-critical reports use normal priority'
);
select is(
  (
    select content_snapshot->>'bio' from public.content_reports
    where reporter_user_id = 'moderation_reporter' and reason = 'harassment'
  ),
  'Target profile snapshot',
  'the private report preserves a review snapshot'
);
select is(
  (
    select count(*)::integer
    from public.moderation_report_events event
    join public.content_reports report on report.id = event.report_id
    where report.reporter_user_id = 'moderation_reporter'
      and report.reason = 'harassment'
  ),
  1,
  'report submission creates an audit event'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'moderation_reporter', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select is(
  (
    public.submit_content_report(
      'profile',
      'moderation_target',
      'moderation_target',
      'harassment',
      'Duplicate detail does not create a second row.'
    )->>'is_duplicate'
  )::boolean,
  true,
  'same reporter subject and reason deduplicates for 24 hours'
);

reset role;

select is(
  (
    select count(*)::integer from public.content_reports
    where reporter_user_id = 'moderation_reporter'
      and subject_kind = 'profile'
      and reason = 'harassment'
  ),
  1,
  'duplicate submission leaves one report row'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'moderation_reporter', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$ select public.submit_content_report('profile', 'moderation_reporter', 'moderation_reporter', 'spam', null) $$,
  '22023',
  'cannot_report_self',
  'a caller cannot report themself'
);
select throws_ok(
  $$ select public.submit_content_report('profile', 'moderation_target', 'moderation_target', 'not_a_reason', null) $$,
  '22023',
  'invalid_report_reason',
  'server rejects unknown report reasons'
);

select is(
  public.submit_content_report(
    'activity',
    (select activity_id::text from moderation_test_context),
    'moderation_target',
    'spam',
    null
  )->>'status',
  'queued',
  'viewer can report visible activity'
);
select is(
  public.submit_content_report(
    'comment',
    'b1200000-0000-0000-0000-000000000001',
    'moderation_target',
    'harassment',
    null
  )->>'status',
  'queued',
  'viewer can report a visible comment'
);
select is(
  public.submit_content_report(
    'user_place',
    'b1100000-0000-0000-0000-000000000001',
    'moderation_target',
    'other',
    null
  )->>'status',
  'queued',
  'viewer can report a visible shared place memory'
);
select is(
  public.submit_content_report(
    'place_list',
    'b1300000-0000-0000-0000-000000000001',
    'moderation_target',
    'spam',
    null
  )->>'status',
  'queued',
  'viewer can report a visible list'
);
select is(
  public.submit_content_report(
    'visit_photo',
    'b1500000-0000-0000-0000-000000000001',
    'moderation_target',
    'sexual_content',
    null
  )->>'status',
  'queued',
  'viewer can report a visible user photo'
);
select throws_ok(
  $$
    select public.submit_content_report(
      'user_place',
      'b1100000-0000-0000-0000-000000000001',
      'moderation_stranger',
      'other',
      null
    )
  $$,
  '42501',
  'report_subject_not_visible',
  'caller cannot misattribute another person as content owner'
);

reset role;

select is(
  (select count(*)::integer from public.content_reports where reporter_user_id = 'moderation_reporter'),
  7,
  'all accepted reports are retained in the private queue'
);

insert into public.content_reports (
  reporter_user_id,
  reported_user_id,
  subject_kind,
  subject_id,
  reason,
  content_snapshot
)
select
  'moderation_reporter',
  'moderation_target',
  'profile',
  'rate-limit-' || sequence,
  'spam',
  '{}'::jsonb
from generate_series(1, 23) as sequence;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'moderation_reporter', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select throws_ok(
  $$ select public.submit_content_report('profile', 'moderation_target', 'moderation_target', 'dangerous_content', null) $$,
  '54000',
  'report_rate_limited',
  'server rate limits report flooding'
);

select throws_ok(
  $$ select public.update_own_profile('kill yourself', null, null, null, null, null, false) $$,
  '22023',
  'content_not_allowed',
  'profile writes are filtered on the server'
);
select throws_ok(
  $$ select public.update_own_profile(null, null, null, null, 'Safe Name', 'n1gg3r', false) $$,
  '22023',
  'content_not_allowed',
  'profile handles are filtered on the server'
);
select throws_ok(
  format(
    $$ select public.add_activity_comment(%L::uuid, 'go kill yourself') $$,
    (select activity_id from moderation_test_context)
  ),
  '22023',
  'content_not_allowed',
  'activity comment writes are filtered on the server'
);
select throws_ok(
  $$ select public.upsert_place_list('{"name":"kill yourself","description":"blocked","visibility":"followers"}'::jsonb) $$,
  '22023',
  'content_not_allowed',
  'list writes are filtered on the server'
);
select throws_ok(
  $$
    select public.save_own_place(
      '{
        "canonical_name":"Filtered Save",
        "category":"other",
        "latitude":34.05,
        "longitude":-118.25,
        "source_provider":"codex_moderation",
        "source_provider_place_id":"filtered-save"
      }'::jsonb,
      '{
        "status":"wanna_go",
        "visibility":"self",
        "note":"go kill yourself",
        "nearby_confirmed":false,
        "source_type":"manual"
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  '22023',
  'content_not_allowed',
  'shared place-note writes are filtered on the server'
);

reset role;

select throws_ok(
  $$
    update public.content_reports
    set status = 'resolved'
    where reporter_user_id = 'moderation_reporter' and reason = 'harassment'
  $$,
  '23514',
  'moderation_resolution_required',
  'closing a report requires a resolution action'
);

update public.content_reports
set status = 'resolved',
    resolution_action = 'no_violation',
    resolution_notes = 'Reviewed in rollback-only pgTAP.'
where reporter_user_id = 'moderation_reporter'
  and subject_kind = 'profile'
  and reason = 'harassment';

select ok(
  (
    select closed_at is not null
    from public.content_reports
    where reporter_user_id = 'moderation_reporter'
      and subject_kind = 'profile'
      and reason = 'harassment'
  ),
  'resolved reports receive a closed timestamp'
);
select is(
  (
    select count(*)::integer
    from public.moderation_report_events event
    join public.content_reports report on report.id = event.report_id
    where report.reporter_user_id = 'moderation_reporter'
      and report.subject_kind = 'profile'
      and report.reason = 'harassment'
  ),
  2,
  'resolution appends a second audit event'
);

select * from finish();

rollback;
