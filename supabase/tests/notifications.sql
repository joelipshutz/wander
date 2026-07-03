begin;

create extension if not exists pgtap;

select plan(23);

insert into public.profiles (id, handle, display_name)
values
  ('user_notify_recipient', 'notifyrecipient', 'Notify Recipient'),
  ('user_notify_actor_disabled', 'actordisabled', 'Actor Disabled'),
  ('user_notify_actor_enabled', 'actorenabled', 'Actor Enabled'),
  ('user_no_token_recipient', 'notoken', 'No Token'),
  ('user_no_token_actor', 'notokenactor', 'No Token Actor'),
  ('user_original_follower', 'originalfollower', 'Original Follower'),
  ('user_followback_actor', 'followbackactor', 'Followback Actor'),
  ('user_block_recipient', 'blockrecipient', 'Block Recipient'),
  ('user_block_actor', 'blockactor', 'Block Actor'),
  ('user_source_owner', 'sourceowner', 'Source Owner'),
  ('user_social_saver', 'socialsaver', 'Social Saver'),
  ('user_list_owner', 'listowner', 'List Owner'),
  ('user_list_collab', 'listcollab', 'List Collab'),
  ('user_capture_owner', 'captureowner', 'Capture Owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);

select ok(
  public.register_push_token(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'sandbox',
    'com.grayline.wander'
  ) is not null,
  'register_push_token stores a token for the current user'
);

select is(
  (select count(*)::int from public.notification_device_tokens where user_id = 'user_notify_recipient' and is_active),
  1,
  'registered token is active and owner-readable'
);

select is(
  (public.get_notification_preferences()).social_graph_enabled,
  true,
  'social graph notifications default on'
);

select is(
  (public.get_notification_preferences()).discovery_digest_enabled,
  false,
  'discovery digest notifications default off'
);

select is(
  (public.update_notification_preferences('{"social_graph_enabled": false}'::jsonb)).social_graph_enabled,
  false,
  'current user can disable social graph notifications'
);

reset role;
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_notify_actor_disabled', 'user_notify_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_notify_recipient'),
  0,
  'disabled social graph preference suppresses follow push events'
);

insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_no_token_actor', 'user_no_token_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_no_token_recipient'),
  0,
  'users without active device tokens do not receive queued push events'
);

select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select (public.update_notification_preferences('{"social_graph_enabled": true}'::jsonb)).social_graph_enabled;

reset role;
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_notify_actor_enabled', 'user_notify_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_notify_recipient'),
  1,
  'enabled recipient gets a follow push event'
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_notify_recipient' limit 1),
  'followed_you',
  'follow push uses the followed_you type'
);

select ok(
  (select body from public.notification_events where recipient_user_id = 'user_notify_recipient' limit 1)
    like '%Actor Enabled started following you%',
  'follow push body names the actor without private payload data'
);

reset role;
delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_original_follower', true);
select public.register_push_token(
  'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'sandbox',
  'com.grayline.wander'
);
reset role;
insert into public.follows(follower_user_id, followed_user_id, source)
values
  ('user_original_follower', 'user_followback_actor', 'profile'),
  ('user_followback_actor', 'user_original_follower', 'profile');

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_original_follower' limit 1),
  'mutual_follow',
  'following someone back queues a mutual follow push for the original follower'
);

reset role;
delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_block_recipient', true);
select public.register_push_token(
  'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
  'sandbox',
  'com.grayline.wander'
);
select public.block_user('user_block_actor');

reset role;
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_block_actor', 'user_block_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_block_recipient'),
  0,
  'block relationships suppress follow push events even if a row is inserted later'
);

insert into public.places (
  id,
  canonical_name,
  category,
  latitude,
  longitude,
  source_provider,
  source_provider_place_id
)
values (
  '40000000-0000-0000-0000-000000000001',
  'Bar Nido',
  'bars_nightlife',
  34.07,
  -118.30,
  'mapkit',
  'bar-nido'
);

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  note,
  visibility,
  source_type
)
values (
  '41000000-0000-0000-0000-000000000001',
  'user_source_owner',
  '40000000-0000-0000-0000-000000000001',
  'been',
  'private-ish note should not ship',
  'followers',
  'manual'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_source_owner', true);
select public.register_push_token(
  'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  'sandbox',
  'com.grayline.wander'
);

reset role;
delete from public.notification_events;

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type,
  source_user_place_id,
  attribution_user_id
)
values (
  '41000000-0000-0000-0000-000000000003',
  'user_social_saver',
  '40000000-0000-0000-0000-000000000001',
  'been',
  'followers',
  'social_save',
  '41000000-0000-0000-0000-000000000001',
  'user_source_owner'
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_source_owner' limit 1),
  'place_saved_from_your_map',
  'social saves queue a recommendation reward-loop push'
);

select ok(
  (select data ? 'place_id' and not (data ? 'note') from public.notification_events where recipient_user_id = 'user_source_owner' limit 1),
  'social save payload includes safe ids and excludes private notes'
);

reset role;
delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_list_collab', true);
select public.register_push_token(
  'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
  'sandbox',
  'com.grayline.wander'
);

reset role;
insert into public.place_lists (
  id,
  owner_user_id,
  name,
  description,
  visibility
)
values (
  '44000000-0000-0000-0000-000000000001',
  'user_list_owner',
  'Saturday plan',
  'Shared shortlist',
  'followers'
);

insert into public.place_list_members (
  list_id,
  user_id,
  role
)
values (
  '44000000-0000-0000-0000-000000000001',
  'user_list_collab',
  'collaborator'
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_list_collab' order by created_at desc limit 1),
  'list_collaborator_added',
  'adding a collaborator queues a shared-list push'
);

reset role;
delete from public.notification_events;

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  visibility,
  source_type
)
values (
  '41000000-0000-0000-0000-000000000002',
  'user_list_owner',
  '40000000-0000-0000-0000-000000000001',
  'been',
  'followers',
  'manual'
);

insert into public.place_list_items (
  list_id,
  place_id,
  owner_user_place_id,
  added_by_user_id
)
values (
  '44000000-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '41000000-0000-0000-0000-000000000002',
  'user_list_owner'
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_list_collab' limit 1),
  'list_place_added',
  'adding a place to a shared list queues a list-place push'
);

reset role;
delete from public.notification_events;

update public.place_list_members
set deleted_at = now()
where list_id = '44000000-0000-0000-0000-000000000001'
  and user_id = 'user_list_collab';

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_list_collab'),
  0,
  'removing a collaborator is intentionally in-app only and does not push'
);

reset role;
delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_capture_owner', true);
select public.register_push_token(
  'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
  'sandbox',
  'com.grayline.wander'
);

reset role;
insert into public.source_artifacts (
  id,
  user_id,
  type,
  original_input,
  normalized_input,
  normalized_source_hash
)
values (
  '42000000-0000-0000-0000-000000000001',
  'user_capture_owner',
  'url',
  'https://maps.app.goo.gl/example',
  'https://maps.app.goo.gl/example',
  'capture_hash'
);

insert into public.extraction_jobs (
  id,
  source_artifact_id,
  owner_user_id,
  source_type,
  normalized_source_hash,
  status
)
values (
  '43000000-0000-0000-0000-000000000001',
  '42000000-0000-0000-0000-000000000001',
  'user_capture_owner',
  'link',
  'capture_hash',
  'running'
);

set local role service_role;
select is(
  public.complete_extraction_job(
    '43000000-0000-0000-0000-000000000001',
    'needs_confirmation',
    '[]'::jsonb,
    0.86,
    '["worker_started"]'::jsonb,
    null,
    null
  )->>'status',
  'needs_confirmation',
  'service completion still returns the extraction status'
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'capture_ready',
  'needs-confirmation extraction completion queues a capture-ready push'
);

select public.complete_extraction_job(
  '43000000-0000-0000-0000-000000000001',
  'needs_confirmation',
  '[]'::jsonb,
  0.86,
  '["worker_started"]'::jsonb,
  null,
  null
);

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_capture_owner'),
  1,
  'capture-ready completion is deduped after the first needs-confirmation transition'
);

select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  1,
  'service worker can claim one pending push event with active tokens'
);

select is(
  (select status from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'claimed',
  'claiming marks the event claimed'
);

select public.mark_push_notification_result(
  (select id from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'sent',
  null
);

select is(
  (select status from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'sent',
  'service worker can mark a claimed push event sent'
);

select * from finish();

rollback;
