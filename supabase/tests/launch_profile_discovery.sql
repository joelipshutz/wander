begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);

-- All fixtures, configuration and notification checks roll back. Never contact Clerk/APNs.
reset role;
update app.profile_discovery_settings set follow_on_signup = false, suggestion_priority = 0;
insert into public.profiles(id, handle, display_name) values
  ('user_launch_founder_a', 'launchfoundera', 'Founder A'),
  ('user_launch_founder_b', 'launchfounderb', 'Founder B'),
  ('user_launch_priority', 'launchpriority', 'Priority Person'),
  ('user_launch_hidden', 'launchhidden', 'Hidden Person'),
  ('user_launch_reverse', 'launchreverse', 'Reverse Follow'),
  ('user_launch_bridge', 'launchbridge', 'Bridge Person'),
  ('user_launch_shared', 'launchshared', 'Shared Person'),
  ('user_launch_existing', 'launchexisting', 'Existing Person');
insert into app.profile_discovery_settings(profile_id, follow_on_signup, suggestion_priority, hidden_from_suggestions) values
  ('user_launch_founder_a', true, 0, false),
  ('user_launch_founder_b', true, 0, false),
  ('user_launch_priority', false, 100, false),
  ('user_launch_hidden', false, 1000, true);
insert into public.notification_preferences(user_id,push_enabled,social_graph_enabled) values
  ('user_launch_founder_a',true,true),
  ('user_launch_founder_b',true,true),
  ('user_launch_priority',true,true);

do $security$
begin
  if has_table_privilege('authenticated', 'app.profile_discovery_settings', 'insert,update,delete')
    or has_table_privilege('anon', 'app.profile_discovery_settings', 'select,insert,update,delete')
    or not (select relrowsecurity from pg_class where oid='app.profile_discovery_settings'::regclass)
    or has_function_privilege('authenticated', 'app.apply_signup_default_follows()', 'execute')
    or has_function_privilege('anon', 'app.apply_signup_default_follows()', 'execute') then
    raise exception 'launch configuration or signup trigger is client writable';
  end if;
  if not exists(select 1 from pg_proc where oid='app.apply_signup_default_follows()'::regprocedure
      and prosecdef and 'search_path=public, app'=any(proconfig))
    or not exists(select 1 from pg_proc where oid='app.discover_profile_recommendations(integer)'::regprocedure
      and not prosecdef and provolatile='s' and 'search_path=public, app'=any(proconfig))
    or not exists(select 1 from pg_proc where oid='public.discover_profile_recommendations(integer)'::regprocedure
      and not prosecdef and provolatile='s' and 'search_path=app, public'=any(proconfig))
    or has_function_privilege('anon','public.discover_profile_recommendations(integer)','execute')
    or not has_function_privilege('authenticated','public.discover_profile_recommendations(integer)','execute') then
    raise exception 'launch function security posture changed';
  end if;
end
$security$;

-- Exercise the real authenticated profile-creation path, including webhook-style upsert retries.
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_launch_new',true);
select public.update_own_profile(input_display_name := 'New Person', input_handle := 'launchnew');
select public.update_own_profile(input_display_name := 'New Person', input_handle := 'launchnew', input_mark_onboarding_complete := true);
reset role;
insert into public.profiles(id,handle,display_name) values ('user_launch_new','launchnew','New Person')
  on conflict(id) do update set display_name=excluded.display_name;
do $signup$
begin
  if (select count(*) from public.follows where follower_user_id='user_launch_new' and source='signup_default')<>2
    or exists(select 1 from public.follows where follower_user_id='user_launch_existing')
    or exists(select 1 from public.notification_events where actor_user_id='user_launch_new') then
    raise exception 'default follows were duplicated, backfilled, absent or notified';
  end if;
end
$signup$;

set local role authenticated;
select public.unfollow_user('user_launch_founder_a');
select public.update_own_profile(input_display_name := 'Updated Person');
reset role;
do $unfollow$
begin
  if exists(select 1 from public.follows where follower_user_id='user_launch_new' and followed_user_id='user_launch_founder_a') then
    raise exception 'profile update restored an intentional unfollow';
  end if;
end
$unfollow$;

-- Known default targets that become private, hidden or deleted must be skipped.
update public.profiles set is_private_profile=true where id='user_launch_founder_a';
update app.profile_discovery_settings set hidden_from_suggestions=true where profile_id='user_launch_founder_b';
insert into public.profiles(id,handle,display_name) values ('user_launch_unavailable','launchunavailable','Unavailable Test');
do $unavailable$
begin
  if exists(select 1 from public.follows where follower_user_id='user_launch_unavailable') then
    raise exception 'signup followed a private or hidden target';
  end if;
end
$unavailable$;
update public.profiles set is_private_profile=false, deleted_at=now() where id='user_launch_founder_a';
insert into public.profiles(id,handle,display_name) values ('user_launch_deleted','launchdeleted','Deleted Test');
do $deleted$
begin
  if exists(select 1 from public.follows where follower_user_id='user_launch_deleted') then
    raise exception 'signup followed a deleted target';
  end if;
end
$deleted$;
update app.profile_discovery_settings set follow_on_signup=false;

insert into public.follows(follower_user_id,followed_user_id,source) values
  ('user_launch_reverse','user_launch_new','profile'),
  ('user_launch_new','user_launch_bridge','profile'),
  ('user_launch_bridge','user_launch_shared','profile'),
  ('user_launch_bridge','user_launch_priority','profile');
set local role authenticated;
select set_config('request.jwt.claim.sub','user_launch_new',true);
do $suggestions$
begin
  if (select id from public.discover_profile_recommendations(1)) is distinct from 'user_launch_priority'
    or (select reason_kind from public.discover_profile_recommendations(50) where id='user_launch_priority') is distinct from 'shared_follows'
    or (select shared_follow_count from public.discover_profile_recommendations(50) where id='user_launch_priority') is distinct from 1
    or (select reason_kind from public.discover_profile_recommendations(50) where id='user_launch_reverse') is distinct from 'follows_you'
    or exists(select 1 from public.discover_profile_recommendations(50) where id='user_launch_hidden')
    or not exists(select 1 from public.search_profiles_by_handle('launchhidden') where id='user_launch_hidden') then
    raise exception 'priority/exclusion changed relationship copy or unrelated profile search';
  end if;
  begin
    update app.profile_discovery_settings set hidden_from_suggestions=false;
    raise exception 'test_client_configuration_write';
  exception when insufficient_privilege then null; end;
end
$suggestions$;
select public.follow_user('user_launch_priority');
do $already_followed$
begin
  if exists(select 1 from public.discover_profile_recommendations(50) where id='user_launch_priority') then
    raise exception 'priority bypasses existing follows';
  end if;
end
$already_followed$;
select public.unfollow_user('user_launch_priority');
reset role;
do $manual_notification$
begin
  if not exists(select 1 from public.notification_events where actor_user_id='user_launch_new' and recipient_user_id='user_launch_priority') then
    raise exception 'ordinary follow notifications stopped';
  end if;
end
$manual_notification$;
insert into public.blocks(blocker_user_id,blocked_user_id) values ('user_launch_priority','user_launch_new');
set local role authenticated;
do $block$
begin
  if exists(select 1 from public.discover_profile_recommendations(50) where id='user_launch_priority') then
    raise exception 'priority bypasses a reverse block';
  end if;
end
$block$;
reset role;
delete from public.blocks where blocker_user_id='user_launch_priority' and blocked_user_id='user_launch_new';
insert into public.blocks(blocker_user_id,blocked_user_id) values ('user_launch_new','user_launch_priority');
set local role authenticated;
do $forward_block$
begin
  if exists(select 1 from public.discover_profile_recommendations(50) where id='user_launch_priority') then
    raise exception 'priority bypasses a forward block';
  end if;
end
$forward_block$;
reset role;
delete from public.blocks where blocker_user_id='user_launch_new' and blocked_user_id='user_launch_priority';
update public.profiles set is_private_profile=true where id='user_launch_priority';
set local role authenticated;
do $private$
begin
  if exists(select 1 from public.discover_profile_recommendations(50) where id='user_launch_priority') then
    raise exception 'priority bypasses profile privacy';
  end if;
end
$private$;
reset role;
update app.profile_discovery_settings set hidden_from_suggestions=false where profile_id='user_launch_hidden';
set local role authenticated;
do $restore$
begin
  if (select id from public.discover_profile_recommendations(1)) is distinct from 'user_launch_hidden' then
    raise exception 'suggestion hiding cannot be reversed';
  end if;
end
$restore$;
select pass('Launch follows, notifications, retries, manual unfollows, priority, privacy, hiding and administration passed');
select * from finish();
rollback;
