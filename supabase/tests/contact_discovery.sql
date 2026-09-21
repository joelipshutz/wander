begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);
create function pg_temp.require(ok boolean, description text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'contact discovery: %', description; end if; end;
$$;

-- Synthetic identities only. Every fixture and setting rolls back.
insert into public.profiles(id,handle,display_name) values
 ('user_cd_viewer','cdviewer','CD Viewer'),('user_cd_match','cdmatch','CD Match'),
 ('user_cd_other','cdother','CD Other');
delete from public.follows where follower_user_id like 'user_cd_%';
insert into public.clerk_identity_mappings(clerk_user_id,profile_id) values
 ('user_cd_match','user_cd_match'),('user_cd_other','user_cd_other');
select pg_temp.require(not has_function_privilege('authenticated','public.match_contact_discovery(text,text[])','execute'), 'no direct client matching');
select pg_temp.require(not has_function_privilege('anon','public.set_contact_discovery_enabled(boolean)','execute'), 'anonymous cannot consent');
select pg_temp.require(not has_function_privilege('authenticated','public.sync_contact_discovery_identity(text,text,timestamptz,text[])','execute'), 'clients cannot claim identifiers');
select pg_temp.require((select bool_and(prosecdef and 'search_path=pg_catalog, app, public'=any(proconfig)) from pg_proc
 where oid in ('public.match_contact_discovery(text,text[])'::regprocedure,
 'public.sync_contact_discovery_identity(text,text,timestamptz,text[])'::regprocedure,
 'public.set_contact_discovery_enabled(boolean)'::regprocedure)), 'definers pin search path');
select pg_temp.require(not has_table_privilege('authenticated','app.contact_discovery_identifiers','select,insert,update,delete'), 'index inaccessible');
select pg_temp.require(not has_table_privilege('service_role','app.contact_discovery_key','select'), 'pepper inaccessible outside narrow functions');
select pg_temp.require((select bool_and(relrowsecurity) from pg_class where oid in
 ('app.contact_discovery_key'::regclass,'app.contact_discovery_settings'::regclass,
 'app.contact_discovery_identifiers'::regclass,'app.contact_discovery_identity_state'::regclass,
 'app.contact_discovery_usage'::regclass)), 'private tables use RLS');

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_cd_viewer',true);
select pg_temp.require(not public.own_contact_discovery_enabled(), 'new accounts default off');
select pg_temp.require(not public.admit_contact_discovery(1), 'no matching without consent');
select public.set_contact_discovery_enabled(true);
select pg_temp.require(public.own_contact_discovery_enabled(), 'viewer consent');
select set_config('request.jwt.claim.sub','user_cd_match',true);
select pg_temp.require(not public.own_contact_discovery_enabled(), 'consent scoped to account');
select public.set_contact_discovery_enabled(true);
reset role;

select public.sync_contact_discovery_identity('user_cd_match','user_cd_match','2026-09-20T00:00:00Z',
 array['email:friend@example.test','phone:+12133734253','email:friend@example.test']);
select pg_temp.require((select count(*)=2 from app.contact_discovery_identifiers where clerk_user_id='user_cd_match'), 'deduplicate verified index');
select pg_temp.require((select count(*)=1 from public.match_contact_discovery('user_cd_viewer',
 array['email:friend@example.test','phone:+12133734253','email:absent@example.test'])), 'email and phone deduplicate to one member');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_other',array['email:friend@example.test'])), 'nonconsenting viewer cannot match');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_match',array['email:friend@example.test'])), 'never suggest self');
select pg_temp.require(not exists(select 1 from public.follows where follower_user_id='user_cd_viewer'), 'matching never follows');
select pg_temp.require((select count(*)=2 from app.contact_discovery_identifiers where clerk_user_id='user_cd_match'), 'unmatched contacts not retained');

update public.profiles set is_private_profile=true where id='user_cd_match';
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'private excluded');
update public.profiles set is_private_profile=false where id='user_cd_match';
insert into app.profile_discovery_settings(profile_id,hidden_from_suggestions) values('user_cd_match',true);
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'hidden excluded');
update app.profile_discovery_settings set hidden_from_suggestions=false where profile_id='user_cd_match';
insert into public.blocks(blocker_user_id,blocked_user_id) values('user_cd_match','user_cd_viewer');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'reverse block excluded');
delete from public.blocks where blocker_user_id='user_cd_match';
insert into public.blocks(blocker_user_id,blocked_user_id) values('user_cd_viewer','user_cd_match');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'forward block excluded');
delete from public.blocks where blocker_user_id='user_cd_viewer';
insert into public.follows(follower_user_id,followed_user_id,source) values('user_cd_viewer','user_cd_match','contacts');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'already followed excluded');
delete from public.follows where follower_user_id='user_cd_viewer';

select public.sync_contact_discovery_identity('user_cd_match','user_cd_match','2026-09-21T00:00:00Z',array['email:new@example.test']);
select public.sync_contact_discovery_identity('user_cd_match','user_cd_match','2026-09-20T00:00:00Z',array['email:friend@example.test']);
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:friend@example.test'])), 'old webhook cannot resurrect removed identifiers');
select pg_temp.require((select count(*)=1 from public.match_contact_discovery('user_cd_viewer',array['email:new@example.test'])), 'new identifier matches');
set local role authenticated;
select set_config('request.jwt.claim.sub','user_cd_match',true);
select public.set_contact_discovery_enabled(false);
reset role;
select public.sync_contact_discovery_identity('user_cd_match','user_cd_match','2026-09-22T00:00:00Z',array['email:new@example.test']);
select pg_temp.require(not exists(select 1 from app.contact_discovery_identifiers where clerk_user_id='user_cd_match'), 'disable clears index and webhook cannot recreate it');
select pg_temp.require(not exists(select 1 from public.match_contact_discovery('user_cd_viewer',array['email:new@example.test'])), 'opted out target excluded');

set local role authenticated;
select set_config('request.jwt.claim.sub','user_cd_viewer',true);
select pg_temp.require(not public.admit_contact_discovery(5001), 'oversized request rejected');
select pg_temp.require(public.admit_contact_discovery(5000), 'first bounded request allowed');
reset role;
update app.contact_discovery_usage set identifiers=30000 where user_id='user_cd_viewer';
set local role authenticated;
select pg_temp.require(not public.admit_contact_discovery(1), 'identifier quota enforced');
select public.set_contact_discovery_enabled(false);
select public.set_contact_discovery_enabled(true);
select pg_temp.require(not public.admit_contact_discovery(1), 'consent cycling cannot reset quota');
reset role;
update app.contact_discovery_usage set identifiers=0,requests=24 where user_id='user_cd_viewer';
set local role authenticated;
select pg_temp.require(not public.admit_contact_discovery(0), 'request quota enforced');
reset role;
update app.contact_discovery_usage set window_start=now()-interval '25 hours' where user_id='user_cd_viewer';
set local role authenticated;
select pg_temp.require(public.admit_contact_discovery(1), 'quota resets after window');
select set_config('request.jwt.claim.sub','user_cd_match',true);
select public.set_contact_discovery_enabled(true);
reset role;
select public.sync_contact_discovery_identity('user_cd_match','user_cd_match','2026-09-23T00:00:00Z',array['email:new@example.test']);
update public.profiles set deleted_at=now() where id='user_cd_match';
select pg_temp.require(not exists(select 1 from app.contact_discovery_identity_state where user_id='user_cd_match'), 'account deletion clears identity index');
select pg_temp.require(not exists(select 1 from app.contact_discovery_settings where user_id='user_cd_match'), 'account deletion clears consent');
select pass('Contact discovery consent, verified index, privacy, quotas and deletion checks passed');
select * from finish();
rollback;
