begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(80);

select is(
  (
    select count(*)::int
    from cron.job
    where jobname = 'recme-push-notification-worker'
      and schedule = '* * * * *'
      and active
  ),
  1,
  'push notification worker has one active once-per-minute schedule'
);

select ok(
  (
    select command like '%vault.decrypted_secrets%'
      and command like '%recme_push_worker_secret%'
      and command not like '%https://rugmtlgufrhlxwfkumhw.supabase.co%'
    from cron.job
    where jobname = 'recme-push-notification-worker'
  ),
  'push worker schedule reads runtime configuration from Vault instead of embedding hosted values'
);

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
insert into public.profiles (id, handle, display_name)
values
  ('user_activity_actor', 'activityactor', 'Activity Actor'),
  ('user_activity_follower', 'activityfollower', 'Activity Follower');

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
  (public.get_notification_preferences()).push_enabled,
  false,
  'push delivery defaults off until explicit one-tap enrollment'
);

select is(
  (public.get_notification_preferences()).social_graph_enabled,
  false,
  'social graph notifications default off before enrollment'
);

select is(
  (public.get_notification_preferences()).discovery_digest_enabled,
  false,
  'discovery digest notifications default off'
);

select is(
  (public.get_notification_preferences()).followed_activity_enabled,
  false,
  'followed-place activity notifications default off before enrollment'
);

select is(
  (public.get_notification_preferences()).shared_visits_enabled,
  false,
  'shared-visit notifications default off before enrollment'
);

select public.update_notification_preferences(
  '{"push_enabled":true,"social_graph_enabled":true,"shared_lists_enabled":true,"shared_visits_enabled":true,"recommendations_enabled":true,"capture_enabled":true,"discovery_digest_enabled":true,"followed_activity_enabled":true}'::jsonb
);

select set_config('request.jwt.claim.sub', 'user_notify_actor_enabled', true);
select public.register_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox',
  'com.grayline.wander'
);
reset role;

select is(
  (
    select count(*)::int
    from public.notification_device_tokens
    where user_id = 'user_notify_recipient' and is_active
  ),
  0,
  'registering the same physical token for another account deactivates its prior owner'
);

select is(
  (
    select count(*)::int
    from public.notification_device_tokens
    where user_id = 'user_notify_actor_enabled' and is_active
  ),
  1,
  'the physical token becomes active for the newly signed-in account'
);

select is(
  (
    select count(*)::int
    from public.notification_device_tokens
    where environment = 'sandbox'
      and app_bundle_id = 'com.grayline.wander'
      and token_hash = encode(
        extensions.digest(
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          'sha256'
        ),
        'hex'
      )
      and is_active
  ),
  1,
  'one physical APNs token has exactly one active account owner'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select public.register_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox',
  'com.grayline.wander'
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

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_no_token_recipient', true);
select public.update_notification_preferences(
  '{"push_enabled":true,"social_graph_enabled":true}'::jsonb
);
reset role;

insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_no_token_actor', 'user_no_token_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_no_token_recipient'),
  1,
  'consented events wait for a device token instead of being discarded'
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

insert into public.places (
  id, canonical_name, category, latitude, longitude,
  source_provider, source_provider_place_id
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

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_activity_follower', true);
select public.register_push_token(
  '1212121212121212121212121212121212121212121212121212121212121212',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences('{"push_enabled":true,"followed_activity_enabled":true}'::jsonb);
reset role;

insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_activity_follower', 'user_activity_actor', 'profile');

insert into public.user_places (
  id, user_id, place_id, status, note, visibility, source_type
)
values (
  '41000000-0000-0000-0000-000000000010',
  'user_activity_actor',
  '40000000-0000-0000-0000-000000000001',
  'been',
  'never include this private note',
  'followers',
  'manual'
);

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_activity_follower'),
  0,
  'the historical visit backfilled from a saved place does not generate a check-in push'
);

delete from public.notification_events;
insert into public.place_visits (
  id, user_place_id, visited_at, backfilled_from_user_place
)
values (
  '45000000-0000-0000-0000-000000000010',
  '41000000-0000-0000-0000-000000000010',
  now(),
  false
);

select is(
  (select notification_type from public.notification_events where recipient_user_id = 'user_activity_follower' limit 1),
  'followed_place_visit',
  'an explicit check-in queues an activity push'
);

select results_eq(
  $$ select title, body from public.notification_events where recipient_user_id = 'user_activity_follower' limit 1 $$,
  $$ values ('Activity Actor checked in'::text, 'Bar Nido'::text) $$,
  'followed-place push uses current check-in copy'
);

select ok(
  (
    select data ?& array['visit_id', 'user_place_id', 'place_id', 'actor_user_id']
      and not (data ?| array['note', 'rating_score', 'latitude', 'longitude'])
    from public.notification_events
    where recipient_user_id = 'user_activity_follower'
    limit 1
  ),
  'followed-place payload includes routing ids and excludes private visit data'
);

select ok(
  (
    select not_before > now() and not_before <= now() + interval '35 seconds'
    from public.notification_events
    where recipient_user_id = 'user_activity_follower'
    limit 1
  ),
  'generic check-in delivery uses only a 30-second Shared Visit supersession window'
);

delete from public.notification_events;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_activity_follower', true);
select public.update_notification_preferences('{"followed_activity_enabled": false}'::jsonb);
reset role;

insert into public.place_visits (
  id, user_place_id, visited_at, backfilled_from_user_place
)
values (
  '45000000-0000-0000-0000-000000000011',
  '41000000-0000-0000-0000-000000000010',
  now(),
  false
);

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_activity_follower'),
  0,
  'disabled followed-activity preference suppresses check-in pushes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_activity_follower', true);
select public.update_notification_preferences('{"followed_activity_enabled": true}'::jsonb);
reset role;
update public.user_places
set visibility = 'self'
where id = '41000000-0000-0000-0000-000000000010';

insert into public.place_visits (
  id, user_place_id, visited_at, backfilled_from_user_place
)
values (
  '45000000-0000-0000-0000-000000000012',
  '41000000-0000-0000-0000-000000000010',
  now(),
  false
);

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_activity_follower'),
  0,
  'self-only place activity is not disclosed to followers'
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
select public.update_notification_preferences('{"push_enabled":true,"social_graph_enabled":true}'::jsonb);
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
select public.update_notification_preferences('{"push_enabled":true,"social_graph_enabled":true}'::jsonb);
select public.block_user('user_block_actor');

reset role;
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_block_actor', 'user_block_recipient', 'profile');

select is(
  (select count(*)::int from public.notification_events where recipient_user_id = 'user_block_recipient'),
  0,
  'block relationships suppress follow push events even if a row is inserted later'
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
select public.update_notification_preferences('{"push_enabled":true,"recommendations_enabled":true}'::jsonb);

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
select public.update_notification_preferences('{"push_enabled":true,"shared_lists_enabled":true}'::jsonb);

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
select public.update_notification_preferences('{"push_enabled":true,"capture_enabled":true}'::jsonb);

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

select is(
  (select attempt_count from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  1,
  'claiming increments the push attempt count'
);

select ok(
  (select claim_expires_at is not null from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'claiming sets a claim expiry lease'
);

update public.notification_events
set claim_expires_at = now() - interval '1 minute'
where recipient_user_id = 'user_capture_owner';

select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  1,
  'expired claimed pushes can be reclaimed'
);

select is(
  (select attempt_count from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  2,
  'reclaiming increments the attempt count again'
);

select public.mark_push_notification_result(
  (select id from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'failed',
  'temporary_apns_transport_error',
  true
);

select is(
  (select status from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'pending',
  'retryable worker failures return the event to pending'
);

select ok(
  (select not_before > now() from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  'retryable worker failures apply a backoff window'
);

update public.notification_events
set not_before = now()
where recipient_user_id = 'user_capture_owner';

select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  1,
  'retryable pushes become claimable after backoff'
);

select is(
  (select attempt_count from public.notification_events where recipient_user_id = 'user_capture_owner' limit 1),
  3,
  'retry claim increments the attempt count'
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

delete from public.notification_events;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select public.unregister_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox'
);

select results_eq(
  $$
    select is_active, deactivation_reason
    from public.notification_device_tokens
    where user_id = 'user_notify_recipient' and environment = 'sandbox'
  $$,
  $$ values (false, 'client_unregistered'::text) $$,
  'client unregister records why the token became inactive'
);

select public.register_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox',
  'com.grayline.wander'
);

select results_eq(
  $$
    select is_active, deactivation_reason, deactivated_at is null
    from public.notification_device_tokens
    where user_id = 'user_notify_recipient' and environment = 'sandbox'
  $$,
  $$ values (true, null::text, true) $$,
  'registering again reactivates the token and clears deactivation metadata'
);

select public.register_push_token(
  '9999999999999999999999999999999999999999999999999999999999999999',
  'production',
  'com.grayline.wander'
);
reset role;

insert into public.notification_events(
  recipient_user_id, actor_user_id, notification_type, title, body,
  deeplink_url, data, dedupe_key, not_before
) values (
  'user_notify_recipient', 'user_notify_actor_enabled', 'followed_you',
  'Actor Enabled followed you', 'Actor Enabled started following you.',
  'recme://people/followers', '{}'::jsonb, 'delivery-reliability-mixed', now()
);

create temporary table notification_claim_snapshots (
  label text primary key,
  payload jsonb not null
);
grant select, insert on notification_claim_snapshots to service_role;

set local role service_role;
insert into notification_claim_snapshots(label, payload)
values ('first', public.claim_pending_push_notifications(10));

select is(
  jsonb_array_length((select payload from notification_claim_snapshots where label = 'first')),
  1,
  'the first per-token delivery event is claimed once'
);

select ok(
  coalesce((select payload->0->>'claim_token' <> '' from notification_claim_snapshots where label = 'first'), false),
  'claims include an attempt identity token'
);

select is(
  jsonb_array_length((select payload->0->'tokens' from notification_claim_snapshots where label = 'first')),
  2,
  'the claim includes both sandbox and production tokens'
);

select is(
  public.record_push_notification_delivery_results(
    ((select payload->0->>'event_id' from notification_claim_snapshots where label = 'first'))::uuid,
    ((select payload->0->>'claim_token' from notification_claim_snapshots where label = 'first'))::uuid,
    jsonb_build_array(
      jsonb_build_object(
        'token_id', (
          select id from public.notification_device_tokens
          where user_id = 'user_notify_recipient' and environment = 'sandbox' and is_active
        ),
        'status', 'accepted',
        'http_status', 200,
        'apns_id', '40000000-0000-4000-8000-000000000001'
      ),
      jsonb_build_object(
        'token_id', (
          select id from public.notification_device_tokens
          where user_id = 'user_notify_recipient' and environment = 'production' and is_active
        ),
        'status', 'retryable_failure',
        'http_status', 503,
        'apns_reason', 'ServiceUnavailable',
        'error_message', '503:ServiceUnavailable',
        'apns_id', '40000000-0000-4000-8000-000000000002'
      )
    )
  )->>'status',
  'pending',
  'one accepted token does not hide another token retry'
);

select results_eq(
  $$
    select status, accepted_at is not null
    from public.notification_events
    where dedupe_key = 'delivery-reliability-mixed'
  $$,
  $$ values ('pending'::text, true) $$,
  'mixed delivery remains pending while recording APNs acceptance'
);

select results_eq(
  $$
    select environment, delivery.status
    from public.notification_push_deliveries delivery
    join public.notification_device_tokens token on token.id = delivery.token_id
    where delivery.event_id = (
      select id from public.notification_events where dedupe_key = 'delivery-reliability-mixed'
    )
    order by environment
  $$,
  $$ values
    ('production'::text, 'retryable_failure'::text),
    ('sandbox'::text, 'accepted'::text)
  $$,
  'delivery state is stored independently for each APNs environment'
);

update public.notification_events
set not_before = now()
where dedupe_key = 'delivery-reliability-mixed';

insert into notification_claim_snapshots(label, payload)
values ('second', public.claim_pending_push_notifications(10));

select is(
  jsonb_array_length((select payload->0->'tokens' from notification_claim_snapshots where label = 'second')),
  1,
  'a retry claim excludes the token Apple already accepted'
);

select isnt(
  (select payload->0->>'claim_token' from notification_claim_snapshots where label = 'second'),
  (select payload->0->>'claim_token' from notification_claim_snapshots where label = 'first'),
  'a reclaimed event receives a new claim token'
);

select is(
  public.record_push_notification_delivery_results(
    ((select payload->0->>'event_id' from notification_claim_snapshots where label = 'first'))::uuid,
    ((select payload->0->>'claim_token' from notification_claim_snapshots where label = 'first'))::uuid,
    '[]'::jsonb
  )->>'status',
  'stale_claim',
  'a stale worker cannot settle a newer attempt'
);

select is(
  (
    select attempt_count
    from public.notification_push_deliveries delivery
    join public.notification_device_tokens token on token.id = delivery.token_id
    where delivery.event_id = (
      select id from public.notification_events where dedupe_key = 'delivery-reliability-mixed'
    ) and token.environment = 'sandbox'
  ),
  1,
  'a stale result does not mutate stored delivery attempts'
);

select is(
  public.record_push_notification_delivery_results(
    ((select payload->0->>'event_id' from notification_claim_snapshots where label = 'second'))::uuid,
    ((select payload->0->>'claim_token' from notification_claim_snapshots where label = 'second'))::uuid,
    jsonb_build_array(jsonb_build_object(
      'token_id', (
        select id from public.notification_device_tokens
        where user_id = 'user_notify_recipient' and environment = 'production' and is_active
      ),
      'status', 'permanent_token_failure',
      'http_status', 410,
      'apns_reason', 'Unregistered',
      'error_message', '410:Unregistered',
      'apns_id', '40000000-0000-4000-8000-000000000003'
    ))
  )->>'status',
  'sent',
  'an accepted token plus a permanently invalid token settles the event sent'
);

select results_eq(
  $$
    select is_active, deactivation_reason
    from public.notification_device_tokens
    where user_id = 'user_notify_recipient' and environment = 'production'
  $$,
  $$ values (false, 'Unregistered'::text) $$,
  'only the permanently rejected production token is deactivated with its APNs reason'
);

select is(
  (select status from public.notification_events where dedupe_key = 'delivery-reliability-mixed'),
  'sent',
  'the mixed-environment event reaches its terminal sent state'
);

insert into public.notification_events(
  recipient_user_id, actor_user_id, notification_type, title, body,
  deeplink_url, data, dedupe_key, not_before
) values (
  'user_notify_recipient', 'user_notify_actor_enabled', 'followed_you',
  'Actor Enabled followed you', 'Actor Enabled started following you.',
  'recme://people/followers', '{}'::jsonb, 'delivery-reliability-bad-event', now()
);
insert into notification_claim_snapshots(label, payload)
values ('bad-event', public.claim_pending_push_notifications(10));

select is(
  public.record_push_notification_delivery_results(
    ((select payload->0->>'event_id' from notification_claim_snapshots where label = 'bad-event'))::uuid,
    ((select payload->0->>'claim_token' from notification_claim_snapshots where label = 'bad-event'))::uuid,
    jsonb_build_array(jsonb_build_object(
      'token_id', (
        select id from public.notification_device_tokens
        where user_id = 'user_notify_recipient' and environment = 'sandbox' and is_active
      ),
      'status', 'permanent_event_failure',
      'http_status', 400,
      'apns_reason', 'PayloadTooLarge',
      'error_message', '400:PayloadTooLarge'
    ))
  )->>'status',
  'failed',
  'a permanent payload error fails the event instead of blaming the token'
);

select ok(
  (select is_active from public.notification_device_tokens
   where user_id = 'user_notify_recipient' and environment = 'sandbox'),
  'a permanent event error does not deactivate a healthy device token'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select public.unregister_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox'
);
reset role;

insert into public.notification_events(
  recipient_user_id, actor_user_id, notification_type, title, body,
  deeplink_url, data, dedupe_key, not_before
) values (
  'user_notify_recipient', 'user_notify_actor_enabled', 'followed_you',
  'Actor Enabled followed you', 'Actor Enabled started following you.',
  'recme://people/followers', '{}'::jsonb, 'delivery-reliability-await-token', now()
);

select is(
  (select count(*)::int from public.notification_events
   where dedupe_key = 'delivery-reliability-await-token'),
  1,
  'a consented event is retained when the account temporarily has no active token'
);

set local role service_role;
select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  0,
  'an event waiting for token repair is not claimed prematurely'
);
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select public.register_push_token(
  '8888888888888888888888888888888888888888888888888888888888888888',
  'production',
  'com.grayline.wander'
);
reset role;

set local role service_role;
select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  1,
  'registering a replacement token makes the retained event deliverable'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_notify_recipient', true);
select public.register_push_token(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'sandbox',
  'com.grayline.wander'
);
reset role;

insert into public.notification_events(
  recipient_user_id, actor_user_id, notification_type, title, body,
  deeplink_url, data, dedupe_key, not_before, max_attempts
) values (
  'user_notify_recipient', 'user_notify_actor_enabled', 'followed_you',
  'Actor Enabled followed you', 'Actor Enabled started following you.',
  'recme://people/followers', '{}'::jsonb, 'delivery-reliability-exhausted-partial',
  now(), 1
);

set local role service_role;
insert into notification_claim_snapshots(label, payload)
values ('exhausted-partial', public.claim_pending_push_notifications(10));

select is(
  public.record_push_notification_delivery_results(
    ((select payload->0->>'event_id' from notification_claim_snapshots where label = 'exhausted-partial'))::uuid,
    ((select payload->0->>'claim_token' from notification_claim_snapshots where label = 'exhausted-partial'))::uuid,
    jsonb_build_array(
      jsonb_build_object(
        'token_id', (
          select id from public.notification_device_tokens
          where user_id = 'user_notify_recipient' and environment = 'sandbox' and is_active
        ),
        'status', 'accepted',
        'http_status', 200
      ),
      jsonb_build_object(
        'token_id', (
          select id from public.notification_device_tokens
          where user_id = 'user_notify_recipient' and environment = 'production' and is_active
        ),
        'status', 'retryable_failure',
        'http_status', 503,
        'apns_reason', 'ServiceUnavailable'
      )
    )
  )->>'status',
  'failed',
  'an exhausted retry remains failed when one active token never accepted delivery'
);

select is(
  (select status from public.notification_events
   where dedupe_key = 'delivery-reliability-exhausted-partial'),
  'failed',
  'a success on one token cannot mask an exhausted active-token failure'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.notification_push_deliveries'::regclass),
  'per-token delivery state has RLS enabled'
);

select ok(
  not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'select'),
  'authenticated clients cannot read delivery diagnostics directly'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.record_push_notification_delivery_results(uuid,uuid,jsonb)'::regprocedure
  ),
  'delivery settlement is security definer'
);

select ok(
  (
    select proconfig @> array['search_path=app, public']
    from pg_proc
    where oid = 'public.record_push_notification_delivery_results(uuid,uuid,jsonb)'::regprocedure
  ),
  'delivery settlement pins its search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.record_push_notification_delivery_results(uuid,uuid,jsonb)',
    'execute'
  ),
  'authenticated clients cannot settle push deliveries'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.record_push_notification_delivery_results(uuid,uuid,jsonb)',
    'execute'
  ),
  'only the service worker can call delivery settlement'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid = 'public.notification_operations_snapshot(integer)'::regprocedure
  ),
  'notification operations snapshot is security definer'
);

select ok(
  (
    select proconfig @> array['search_path=app, public']
    from pg_proc
    where oid = 'public.notification_operations_snapshot(integer)'::regprocedure
  ),
  'notification operations snapshot pins its search path'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.notification_operations_snapshot(integer)',
    'execute'
  ),
  'authenticated clients cannot read the notification operations snapshot'
);

select ok(
  has_function_privilege(
    'service_role',
    'public.notification_operations_snapshot(integer)',
    'execute'
  ),
  'only the service worker can read the notification operations snapshot'
);

select is(
  jsonb_array_length(public.notification_operations_snapshot(30)->'histogram'),
  7,
  'notification operations snapshot returns every frequency bucket including zero'
);

select ok(
  public.notification_operations_snapshot(30)::text not like '%"user_id"%'
    and public.notification_operations_snapshot(30)::text not like '%user_notify_%',
  'notification operations snapshot never returns recipient identifiers'
);
reset role;

do $pgtap_finish$
declare
  diagnostics text;
begin
  select string_agg(result.message, E'\n')
  into diagnostics
  from finish() as result(message);
  if diagnostics is not null then
    raise exception 'Notifications pgTAP failures:%', E'\n' || diagnostics;
  end if;
end
$pgtap_finish$;

rollback;
