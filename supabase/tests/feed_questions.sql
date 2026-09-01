begin;

create extension if not exists pgtap;

select plan(32);

select has_column('public', 'feed_events', 'question_text', 'Feed events store question text');
select col_type_is('public', 'feed_events', 'question_text', 'text', 'question text uses text storage');
select has_function('public', 'create_feed_question', array['text']);
select is(
  (select prosecdef from pg_proc where oid = 'public.create_feed_question(text)'::regprocedure),
  true,
  'question creation is security definer'
);
select is(
  (select provolatile from pg_proc where oid = 'public.create_feed_question(text)'::regprocedure),
  'v'::"char",
  'question creation is explicitly volatile'
);
select ok(
  (
    select 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.create_feed_question(text)'::regprocedure
  ),
  'question creation pins search_path'
);
select ok(
  has_function_privilege('authenticated', 'public.create_feed_question(text)', 'execute'),
  'authenticated callers can create questions'
);
select ok(
  not has_function_privilege('anon', 'public.create_feed_question(text)', 'execute'),
  'anonymous callers cannot create questions'
);

insert into public.profiles (id, handle, display_name, is_private_profile)
values
  ('question_owner', 'questionowner', 'Question Owner', false),
  ('question_follower', 'questionfollower', 'Question Follower', false),
  ('question_disabled', 'questiondisabled', 'Question Disabled', false),
  ('question_stranger', 'questionstranger', 'Question Stranger', false);

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('question_follower', 'question_owner', 'profile'),
  ('question_disabled', 'question_owner', 'profile');

create temporary table feed_question_fixture (
  activity_id uuid primary key
) on commit drop;
grant select, insert on feed_question_fixture to authenticated;

create temporary table feed_question_long_fixture (
  activity_id uuid primary key
) on commit drop;
grant select, insert on feed_question_long_fixture to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'question_follower', true);
select public.update_notification_preferences(
  '{"push_enabled":true,"followed_activity_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'question_owner', true);
select lives_ok(
  $$
    insert into feed_question_fixture (activity_id)
    select (public.create_feed_question('  Where is the best iced latte in West LA?  ')->>'id')::uuid
  $$,
  'an authenticated profile can ask a question'
);
reset role;

select is(
  (
    select count(*)::integer
    from public.feed_events
    where actor_user_id = 'question_owner' and event_type = 'question_asked'
  ),
  1,
  'question creation records exactly one immutable Feed event'
);
select is(
  (
    select question_text
    from public.feed_events
    where actor_user_id = 'question_owner' and event_type = 'question_asked'
  ),
  'Where is the best iced latte in West LA?',
  'question creation trims surrounding whitespace'
);
select ok(
  (
    select user_place_id is null and place_id is null and visit_id is null
      and list_id is null and list_item_id is null
    from public.feed_events
    where actor_user_id = 'question_owner' and event_type = 'question_asked'
  ),
  'question events cannot masquerade as place or list activity'
);
select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'question_follower'
      and notification_type = 'question_asked'
  ),
  1,
  'an eligible follower receives one question notification'
);
select ok(
  (
    select data ?& array['activity_id', 'event_type', 'actor_user_id']
      and not (data ?| array['question_text', 'note', 'latitude', 'longitude'])
    from public.notification_events
    where recipient_user_id = 'question_follower'
      and notification_type = 'question_asked'
  ),
  'question notification routing data excludes private content fields'
);
select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'question_disabled'
      and notification_type = 'question_asked'
  ),
  0,
  'the disabled followed-activity preference suppresses question notifications'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_owner', true);
select is(
  public.followed_feed(null, 25)->'activity'->0->>'question_text',
  'Where is the best iced latte in West LA?',
  'the author sees their own question immediately in Feed'
);

select set_config('request.jwt.claim.sub', 'question_follower', true);
select is(
  public.followed_feed(null, 25)->'activity'->0->>'event_type',
  'question_asked',
  'a follower sees the question in Feed'
);
select is(
  public.activity_detail(
    (select activity_id from feed_question_fixture)
  )->>'question_text',
  'Where is the best iced latte in West LA?',
  'a follower can resolve the exact question thread'
);

select set_config('request.jwt.claim.sub', 'question_stranger', true);
select throws_ok(
  $$
    select public.activity_detail(
      (select activity_id from feed_question_fixture)
    )
  $$,
  'P0001',
  'activity_not_visible',
  'a non-follower cannot resolve the question thread'
);

select set_config('request.jwt.claim.sub', 'question_follower', true);
select lives_ok(
  $$
    select public.add_activity_comment(
      (select activity_id from feed_question_fixture),
      'Try Goodboybob in Santa Monica.'
    )
  $$,
  'a follower can answer through the existing comment contract'
);

select set_config('request.jwt.claim.sub', 'question_owner', true);
select is(
  public.activity_comments(
    (select activity_id from feed_question_fixture),
    null,
    50
  )->'comments'->0->>'body',
  'Try Goodboybob in Santa Monica.',
  'the question owner can read the answer thread'
);
reset role;

select results_eq(
  $$
    select title, body
    from public.notification_events
    where recipient_user_id = 'question_owner'
      and notification_type = 'activity_commented'
    order by created_at desc
    limit 1
  $$,
  $$
    values (
      'New answer'::text,
      'Question Follower answered your question: Where is the best iced latte in West LA?'::text
    )
  $$,
  'an answer sends question-specific notification copy to the owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_owner', true);
select throws_ok(
  $$ select public.create_feed_question('   ') $$,
  'P0001',
  'invalid_question_text',
  'blank questions are rejected'
);
select throws_ok(
  $$ select public.create_feed_question(repeat('a', 281)) $$,
  'P0001',
  'invalid_question_text',
  'questions longer than 280 characters are rejected'
);
select throws_ok(
  $$ select public.create_feed_question('go kill yourself') $$,
  '22023',
  'content_not_allowed',
  'question text uses the shared community-content guard'
);

reset role;
update public.profiles set is_private_profile = true where id = 'question_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_follower', true);
select is(
  jsonb_array_length(public.followed_feed(null, 25)->'activity'),
  0,
  'private profiles immediately hide questions from followers'
);
select set_config('request.jwt.claim.sub', 'question_owner', true);
select is(
  public.activity_detail(
    (select activity_id from feed_question_fixture)
  )->>'event_type',
  'question_asked',
  'a private author retains access to their own question'
);

reset role;
update public.profiles set is_private_profile = false where id = 'question_owner';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_follower', true);
select isnt(
  public.submit_content_report(
    'activity',
    (select activity_id::text from feed_question_fixture),
    'question_owner',
    'spam',
    null
  )->>'report_id',
  null,
  'a follower can report a visible question'
);
reset role;
select is(
  (
    select content_snapshot->>'question_text'
    from public.content_reports
    where reporter_user_id = 'question_follower'
      and reported_user_id = 'question_owner'
      and subject_kind = 'activity'
  ),
  'Where is the best iced latte in West LA?',
  'question reports preserve the question text for moderation review'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'question_owner', true);
select lives_ok(
  $$
    insert into feed_question_long_fixture (activity_id)
    select (public.create_feed_question(repeat('a', 280))->>'id')::uuid
  $$,
  'a maximum-length question still queues bounded notification copy'
);
select set_config('request.jwt.claim.sub', 'question_follower', true);
select lives_ok(
  $$
    select public.add_activity_comment(
      (select activity_id from feed_question_long_fixture),
      'A concise answer.'
    )
  $$,
  'answering a maximum-length question still queues bounded notification copy'
);
reset role;
select ok(
  (
    select max(char_length(body)) <= 240
    from public.notification_events
    where data->>'activity_id' = (
      select activity_id::text from feed_question_long_fixture
    )
  ),
  'maximum-length question and answer notifications stay within the queue copy contract'
);

select * from finish();
rollback;
