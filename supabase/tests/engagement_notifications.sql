begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(17);

select has_column(
  'public',
  'notification_preferences',
  'engagement_enabled',
  'notification preferences expose a dedicated engagement category'
);
select col_default_is(
  'public',
  'notification_preferences',
  'engagement_enabled',
  'false',
  'engagement notifications default off'
);
select ok(
  (
    select prosecdef
      and 'search_path=pg_catalog, public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.queue_activity_engagement_notification()'::regprocedure
  ),
  'engagement trigger function is security definer with a pinned search path'
);
select ok(
  not has_function_privilege(
    'authenticated',
    'app.queue_activity_engagement_notification()',
    'execute'
  ),
  'authenticated callers cannot invoke the engagement trigger directly'
);
select is(
  (
    select count(*)::integer
    from pg_trigger
    where tgrelid in ('public.activity_likes'::regclass, 'public.activity_comments'::regclass)
      and tgfoid = 'app.queue_activity_engagement_notification()'::regprocedure
      and not tgisinternal
  ),
  2,
  'likes and comments both queue engagement notifications'
);

insert into public.profiles (id, handle, display_name)
values
  ('notify_engagement_owner', 'notifyengagementowner', 'Post Owner'),
  ('notify_engagement_actor', 'notifyengagementactor', 'Activity Actor'),
  ('notify_engagement_participant', 'notifyengagementparticipant', 'Prior Participant'),
  ('notify_engagement_commenter', 'notifyengagementcommenter', 'Prior Commenter'),
  ('notify_engagement_disabled', 'notifyengagementdisabled', 'Disabled Participant');

insert into public.follows (follower_user_id, followed_user_id, source)
values
  ('notify_engagement_actor', 'notify_engagement_owner', 'profile'),
  ('notify_engagement_participant', 'notify_engagement_owner', 'profile'),
  ('notify_engagement_commenter', 'notify_engagement_owner', 'profile'),
  ('notify_engagement_disabled', 'notify_engagement_owner', 'profile');

insert into public.places (
  id, canonical_name, category, latitude, longitude,
  source_provider, source_provider_place_id
)
values (
  'e1000000-0000-0000-0000-000000000001',
  'Notification Cafe',
  'coffee',
  34.0522,
  -118.2437,
  'mapkit',
  'engagement-notification-cafe'
);

insert into public.user_places (
  id, user_id, place_id, status, visibility, source_type
)
values (
  'e1100000-0000-0000-0000-000000000001',
  'notify_engagement_owner',
  'e1000000-0000-0000-0000-000000000001',
  'wanna_go',
  'followers',
  'manual'
);

select set_config(
  'recme.test_activity_id',
  (select id::text from public.feed_events where user_place_id = 'e1100000-0000-0000-0000-000000000001'),
  true
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'notify_engagement_owner', true);
select public.register_push_token(
  'e111111111111111111111111111111111111111111111111111111111111111',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'notify_engagement_actor', true);
select public.register_push_token(
  'e444444444444444444444444444444444444444444444444444444444444444',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'notify_engagement_commenter', true);
select public.register_push_token(
  'e555555555555555555555555555555555555555555555555555555555555555',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'notify_engagement_participant', true);
select public.register_push_token(
  'e222222222222222222222222222222222222222222222222222222222222222',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'notify_engagement_disabled', true);
select public.register_push_token(
  'e333333333333333333333333333333333333333333333333333333333333333',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled":true,"engagement_enabled":false}'::jsonb
);

select set_config('request.jwt.claim.sub', 'notify_engagement_actor', true);
select public.set_activity_like(
  current_setting('recme.test_activity_id')::uuid,
  true
);
reset role;

select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_owner'
      and notification_type = 'activity_liked'
  ),
  1,
  'a like notifies the post owner'
);
select is(
  (
    select data->>'activity_id' from public.notification_events
    where recipient_user_id = 'notify_engagement_owner'
      and notification_type = 'activity_liked'
    limit 1
  ),
  (select id::text from public.feed_events where user_place_id = 'e1100000-0000-0000-0000-000000000001'),
  'like payload carries the exact activity id'
);
select ok(
  (
    select deeplink_url from public.notification_events
    where recipient_user_id = 'notify_engagement_owner'
      and notification_type = 'activity_liked'
    limit 1
  ) like 'https://getrec.me/activities/%',
  'like notification deep-links to the exact comments page'
);
select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_actor'
  ),
  0,
  'the engagement actor is never notified about their own action'
);

do $$
begin
  if (select count(*) from public.notification_events
      where recipient_user_id = 'notify_engagement_owner'
        and notification_type = 'activity_liked') <> 1
     or (select count(*) from public.notification_events
         where recipient_user_id = 'notify_engagement_actor') <> 0 then
    raise exception 'hosted_like_notification_contract_failed';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'notify_engagement_participant', true);
select public.set_activity_like(
  current_setting('recme.test_activity_id')::uuid,
  true
);
reset role;

select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_actor'
      and notification_type = 'activity_liked'
  ),
  1,
  'a later like notifies a prior liker'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'notify_engagement_commenter', true);
select public.add_activity_comment(
  current_setting('recme.test_activity_id')::uuid,
  'I commented before the next participant.'
);
select set_config('request.jwt.claim.sub', 'notify_engagement_disabled', true);
select public.set_activity_like(
  current_setting('recme.test_activity_id')::uuid,
  true
);
reset role;

delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'notify_engagement_actor', true);
select public.add_activity_comment(
  current_setting('recme.test_activity_id')::uuid,
  'This should notify everyone who opted in.'
);
reset role;

select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_owner'
      and notification_type = 'activity_commented'
  ),
  1,
  'a comment notifies the post owner'
);
select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_participant'
      and notification_type = 'activity_commented'
  ),
  1,
  'a comment notifies a prior liker'
);
select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_commenter'
      and notification_type = 'activity_commented'
  ),
  1,
  'a comment notifies a prior commenter'
);
select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_disabled'
  ),
  0,
  'the engagement category toggle suppresses notifications'
);
select is(
  (
    select count(*)::integer from public.notification_events
    where recipient_user_id = 'notify_engagement_actor'
  ),
  0,
  'comment actors do not receive their own notification'
);
select is(
  (
    select count(distinct recipient_user_id)::integer
    from public.notification_events
    where notification_type = 'activity_commented'
  ),
  3,
  'comment recipients are deduplicated across owner, likes, and comments'
);
select is(
  (
    select data->>'event_type' from public.notification_events
    where notification_type = 'activity_commented'
    limit 1
  ),
  'place_want_to_go',
  'engagement notifications preserve the save type in routing data'
);

do $$
begin
  if (select count(*) from public.notification_events
      where recipient_user_id = 'notify_engagement_owner'
        and notification_type = 'activity_commented') <> 1
     or (select count(*) from public.notification_events
         where recipient_user_id = 'notify_engagement_participant'
           and notification_type = 'activity_commented') <> 1
     or (select count(*) from public.notification_events
         where recipient_user_id = 'notify_engagement_commenter'
           and notification_type = 'activity_commented') <> 1
     or (select count(*) from public.notification_events
         where recipient_user_id in ('notify_engagement_disabled', 'notify_engagement_actor')) <> 0 then
    raise exception 'hosted_comment_notification_contract_failed';
  end if;
end;
$$;

select * from finish();

rollback;
