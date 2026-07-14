begin;

create extension if not exists pgtap;

select plan(44);

select is(
  (select prosecdef from pg_proc where oid = 'app.update_own_profile(text,text,text,boolean,text,text)'::regprocedure),
  false,
  'profile updates run as the authenticated caller'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.update_own_profile(text,text,text,boolean,text,text)'::regprocedure),
  'profile updates pin search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.update_own_profile(text,text,text,boolean,text,text)', 'execute'),
  'authenticated can update their profile'
);

select ok(
  not has_function_privilege('anon', 'public.update_own_profile(text,text,text,boolean,text,text)', 'execute'),
  'anonymous callers cannot update profiles'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.mute_profile(text)'::regprocedure),
  false,
  'mute runs as the authenticated caller'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.mute_profile(text)'::regprocedure),
  'mute pins search_path'
);

select ok(
  has_function_privilege('authenticated', 'public.mute_profile(text)', 'execute'),
  'authenticated can mute profiles'
);

select ok(
  not has_function_privilege('anon', 'public.mute_profile(text)', 'execute'),
  'anonymous callers cannot mute profiles'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profile_mutes'::regclass),
  'profile mutes enforce RLS'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.account_storage_objects(text,timestamptz)'::regprocedure),
  true,
  'account storage inventory is a narrow security definer function'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.account_storage_objects(text,timestamptz)'::regprocedure),
  'account storage inventory pins search_path'
);

select ok(
  has_function_privilege('service_role', 'public.account_storage_objects(text,timestamptz)', 'execute'),
  'service role can inventory account storage before deletion'
);

select ok(
  not has_function_privilege('authenticated', 'public.account_storage_objects(text,timestamptz)', 'execute'),
  'authenticated clients cannot inventory arbitrary account storage'
);

select is(
  (select prosecdef from pg_proc where oid = 'app.claim_pending_push_notifications(integer)'::regprocedure),
  true,
  'push claims remain security definer'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc where oid = 'app.claim_pending_push_notifications(integer)'::regprocedure),
  'push claims retain their pinned search_path'
);

select is(
  (select prosecdef from pg_proc
   where oid = 'app.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)'::regprocedure),
  true,
  'Clerk mirroring remains security definer'
);

select ok(
  (select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
   from pg_proc
   where oid = 'app.mirror_clerk_profile(text,text,timestamptz,text,text,text,text)'::regprocedure),
  'Clerk mirroring retains its pinned search_path'
);

insert into public.profiles (
  id, handle, display_name, avatar_url, avatar_url_source, avatar_storage_path
)
values
  (
    'user_profile_redesign_owner',
    'redesignowner',
    'Redesign Owner',
    'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_profile_redesign_owner/avatar.jpg?v=test',
    'app',
    'user_profile_redesign_owner/avatar.jpg'
  ),
  ('user_profile_redesign_muted', 'redesignmuted', 'Muted Member', null, 'clerk', null),
  ('user_profile_redesign_other', 'redesignother', 'Other Member', null, 'clerk', null);

insert into public.places (
  id, canonical_name, category, address, locality, region, country,
  latitude, longitude, source_provider, source_provider_place_id
)
values (
  '89000000-0000-0000-0000-000000000001',
  'Calendar Cafe',
  'coffee',
  '100 Profile Way',
  'Los Angeles',
  'CA',
  'United States',
  34.0522,
  -118.2437,
  'mapkit',
  'rec89-calendar-cafe'
);

insert into public.user_places (
  id, user_id, place_id, status, visibility, source_type
)
values (
  '89000000-0000-0000-0000-000000000002',
  'user_profile_redesign_owner',
  '89000000-0000-0000-0000-000000000001',
  'been',
  'followers',
  'manual'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);

select is(
  public.update_own_profile('Places I love', 'Los Angeles', 'mutuals', true, 'Ryan Tester', 'ryan_tester')->>'bio',
  'Places I love',
  'owner can update profile bio'
);

select is(
  (select display_name from public.profiles where id = 'user_profile_redesign_owner'),
  'Ryan Tester',
  'owner can persist display name'
);

select is(
  (select handle from public.profiles where id = 'user_profile_redesign_owner'),
  'ryan_tester',
  'owner can persist a unique normalized handle'
);

select is(
  public.update_own_profile(null, null, null, null, null, null)->>'bio',
  'Places I love',
  'partial preference updates preserve profile details'
);

select throws_ok(
  $$ select public.update_own_profile(null, null, null, null, null, 'redesignother') $$,
  '23505',
  'handle_taken',
  'owner cannot claim another active profile handle'
);

select is(
  (select home_area from public.profiles where id = 'user_profile_redesign_owner'),
  'Los Angeles',
  'owner can persist home city'
);

select is(
  (select default_visibility from public.profiles where id = 'user_profile_redesign_owner'),
  'mutuals',
  'owner can persist default save visibility'
);

select is(
  (select is_private_profile from public.profiles where id = 'user_profile_redesign_owner'),
  true,
  'owner can persist private-profile mode'
);

select ok(
  (select created_at is not null and is_private_profile from public.current_profile()),
  'current profile returns membership date and privacy state'
);

reset role;
select app.mirror_clerk_profile(
  'evt_profile_identity_preservation',
  'user.updated',
  '2099-01-01T00:00:00Z',
  'user_profile_redesign_owner',
  'clerk_replacement',
  'Clerk Replacement',
  null
);
select is(
  (select handle || '|' || display_name from public.profiles where id = 'user_profile_redesign_owner'),
  'ryan_tester|Ryan Tester',
  'Clerk updates preserve app-owned profile identity'
);
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);

select is(
  (select bio from public.profiles where id = 'user_profile_redesign_other'),
  null,
  'owner profile update does not modify another profile'
);

select public.mute_profile('user_profile_redesign_muted');

select is(
  (select count(*)::integer from public.profile_mutes),
  1,
  'owner can persist a mute'
);

select is(
  (select id from public.muted_profiles()),
  'user_profile_redesign_muted',
  'muted profile list returns the muted member'
);

select set_config('request.jwt.claim.sub', 'user_profile_redesign_other', true);

select is(
  (select count(*)::integer from public.profile_mutes),
  0,
  'another authenticated member cannot read owner mutes'
);

select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);
select public.register_push_token(
  '8989898989898989898989898989898989898989898989898989898989898989',
  'sandbox',
  'com.grayline.wander'
);
select public.update_notification_preferences(
  '{"push_enabled": true, "social_graph_enabled": true}'::jsonb
);

reset role;

insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_profile_redesign_muted', 'user_profile_redesign_owner', 'profile');

select is(
  (select count(*)::integer from public.notification_events
   where recipient_user_id = 'user_profile_redesign_owner'),
  0,
  'muted actor cannot enqueue a notification for the muter'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);
select public.unmute_profile('user_profile_redesign_muted');
reset role;

select app.queue_notification_event(
  'user_profile_redesign_owner',
  'user_profile_redesign_muted',
  'followed_you',
  'Muted Member',
  'Muted Member started following you.',
  'recme://profile/user_profile_redesign_muted',
  '{}'::jsonb,
  'rec89-queued-before-mute',
  now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);
select public.mute_profile('user_profile_redesign_muted');
set local role service_role;
select public.claim_pending_push_notifications(10);
reset role;

select is(
  (select status from public.notification_events where dedupe_key = 'rec89-queued-before-mute'),
  'skipped',
  'claim worker skips notifications queued before the actor was muted'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_profile_redesign_owner', true);

select is(
  (select owner_avatar_url from public.profile_visible_places(
    'user_profile_redesign_owner', array['been'], null
  )),
  'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/user_profile_redesign_owner/avatar.jpg?v=test',
  'profile places include the owner avatar'
);

select is(
  (select locality from public.profile_visible_places(
    'user_profile_redesign_owner', array['been'], null
  )),
  'Los Angeles',
  'profile places include locality for profile insights'
);

select is(
  (select country from public.profile_visible_places(
    'user_profile_redesign_owner', array['been'], null
  )),
  'United States',
  'profile places include country for profile insights'
);

set local role service_role;

insert into public.clerk_profile_mirror_state(
  clerk_user_id, last_event_id, last_event_type, last_event_timestamp
)
values (
  'user_profile_redesign_owner',
  'evt_rec89_newer_update',
  'user.updated',
  '2031-01-01T00:00:00Z'
)
on conflict (clerk_user_id) do update set
  last_event_id = excluded.last_event_id,
  last_event_type = excluded.last_event_type,
  last_event_timestamp = excluded.last_event_timestamp;

select is(
  (select count(*)::integer from public.account_storage_objects(
    'user_profile_redesign_owner',
    '2030-01-01T00:00:00Z'::timestamptz
  )),
  0,
  'stale delete events cannot inventory or remove account storage'
);

update public.clerk_profile_mirror_state
set last_event_id = 'evt_rec89_older_update',
    last_event_timestamp = '2029-01-01T00:00:00Z'
where clerk_user_id = 'user_profile_redesign_owner';

select ok(
  exists (
    select 1 from public.account_storage_objects(
      'user_profile_redesign_owner',
      '2030-01-01T00:00:00Z'::timestamptz
    )
    where bucket_id = 'profile-avatars'
      and object_path = 'user_profile_redesign_owner/avatar.jpg'
  ),
  'account purge inventories the profile avatar before deleting rows'
);

select is(
  public.mirror_clerk_profile(
    'evt_rec89_hard_delete',
    'user.deleted',
    '2030-01-01T00:00:00Z',
    'user_profile_redesign_owner',
    null,
    null,
    null
  )->>'action',
  'hard_deleted',
  'Clerk delete event permanently deletes the profile'
);

reset role;

select ok(
  not exists (select 1 from public.profiles where id = 'user_profile_redesign_owner'),
  'hard delete removes the profile row'
);

select ok(
  not exists (select 1 from public.user_places where user_id = 'user_profile_redesign_owner'),
  'hard delete cascades owner saves and visits'
);

select ok(
  not exists (select 1 from public.profile_mutes
              where muter_user_id = 'user_profile_redesign_owner'),
  'hard delete removes private mute records'
);

select ok(
  not exists (select 1 from public.notification_device_tokens
              where user_id = 'user_profile_redesign_owner'),
  'hard delete removes device tokens'
);

select ok(
  exists (select 1 from public.places where id = '89000000-0000-0000-0000-000000000001'),
  'hard delete preserves shared canonical place data'
);

select * from finish(true);

rollback;
