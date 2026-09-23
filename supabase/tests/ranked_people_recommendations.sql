begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions,pg_temp;
select plan(1);
create function pg_temp.require(ok boolean, description text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'people ranking: %',description; end if; end;
$$;
-- All test data, visibility settings, follows and the preview function roll back.
update app.profile_discovery_settings set follow_on_signup=false;
insert into app.profile_discovery_settings(profile_id,hidden_from_suggestions)
 select id,true from public.profiles on conflict(profile_id) do update set hidden_from_suggestions=true;
insert into public.profiles(id,handle,display_name,home_area,created_at) values
 ('user_rank_viewer','rankviewer','Viewer','Los Angeles','2026-01-01'),
 ('user_rank_curated','rankcurated','Curated','New York','2026-01-01'),
 ('user_rank_contact','rankcontact','Contact','New York','2026-01-01'),
 ('user_rank_localcontact','ranklocalcontact','Local contact','  LOS   ANGELES  ','2026-01-01'),
 ('user_rank_local','ranklocal','Local','Los Angeles','2026-01-01'),
 ('user_rank_graph','rankgraph','Graph','Los Angeles','2026-01-01'),
 ('user_rank_mutual','rankmutual','Mutual','Paris','2026-01-01'),
 ('user_rank_general','rankgeneral','General',null,'2026-01-01');
insert into app.profile_discovery_settings(profile_id,suggestion_priority) values('user_rank_curated',100);
insert into public.follows(follower_user_id,followed_user_id,source) values
 ('user_rank_viewer','user_rank_mutual','signup_default'),
 ('user_rank_mutual','user_rank_graph','signup_default'),
 ('user_rank_graph','user_rank_viewer','signup_default');
select pg_temp.require(not has_function_privilege('anon','public.ranked_people_recommendations(text[],integer)','execute'),'anonymous cannot rank people');
select pg_temp.require((select not prosecdef and 'search_path=pg_catalog, public, app'=any(proconfig) from pg_proc where oid='public.ranked_people_recommendations(text[],integer)'::regprocedure),'ranking preserves caller RLS and pinned search path');
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_rank_viewer',true);
select pg_temp.require((select array_agg(id order by result_rank) from public.ranked_people_recommendations(array['user_rank_contact','user_rank_localcontact'],20))=
 array['user_rank_curated','user_rank_localcontact','user_rank_contact','user_rank_graph','user_rank_local','user_rank_general'],'curated priority then combined contact/location and social signals');
select pg_temp.require((select reason_kind='contacts' from public.ranked_people_recommendations(array['user_rank_contact'],20) where id='user_rank_contact'),'contacts explain matching');
select pg_temp.require((select reason_kind='nearby' from public.ranked_people_recommendations('{}',20) where id='user_rank_local'),'home area explains local relevance');
select pg_temp.require((select shared_follow_count=1 and reason_kind='shared_follows' from public.ranked_people_recommendations('{}',20) where id='user_rank_graph'),'social proximity combines with follows-you and location');
select pg_temp.require((select count(*)=6 from public.ranked_people_recommendations(array['user_rank_contact','user_rank_contact','missing'],50)),'duplicates and unmatched contacts do not add profiles');
select pg_temp.require((select count(*)=2 from public.ranked_people_recommendations('{}',2)),'requested limit honored');
select pg_temp.require(not exists(select 1 from public.ranked_people_recommendations(array_fill('x'::text,array[101]),20)),'oversized contact list fails closed');
reset role;
savepoint contact_graph;
insert into public.profiles(id,handle,display_name,created_at)
 select 'user_rank_peer_'||n,'rankpeer'||n,'Contact '||n,'2026-01-01'::timestamptz from generate_series(1,6) n;
insert into public.profiles(id,handle,display_name,created_at) values
 ('user_rank_one','rankone','One contact','2026-01-01'),
 ('user_rank_two','ranktwo','Two contacts','2026-01-01'),
 ('user_rank_six','ranksix','Six contacts','2026-01-01'),
 ('user_rank_ineligible','rankineligible','Ineligible support','2026-01-01'),
 ('user_rank_private','rankprivate','Private contact','2026-01-01'),
 ('user_rank_deleted','rankdeleted','Deleted contact','2026-01-01'),
 ('user_rank_blocked','rankblocked','Blocked contact','2026-01-01'),
 ('user_rank_hidden','rankhidden','Hidden contact','2026-01-01');
update public.profiles set is_private_profile=true where id='user_rank_private';
update public.profiles set deleted_at=now() where id='user_rank_deleted';
insert into public.blocks(blocker_user_id,blocked_user_id) values('user_rank_blocked','user_rank_viewer');
insert into app.profile_discovery_settings(profile_id,hidden_from_suggestions) values('user_rank_hidden',true);
insert into public.follows(follower_user_id,followed_user_id,source)
 select 'user_rank_peer_'||n,'user_rank_six','signup_default' from generate_series(1,6) n;
insert into public.follows(follower_user_id,followed_user_id,source) values
 ('user_rank_peer_1','user_rank_one','signup_default'),
 ('user_rank_peer_1','user_rank_two','signup_default'),
 ('user_rank_peer_2','user_rank_two','signup_default'),
 ('user_rank_private','user_rank_ineligible','signup_default'),
 ('user_rank_deleted','user_rank_ineligible','signup_default'),
 ('user_rank_blocked','user_rank_ineligible','signup_default'),
 ('user_rank_hidden','user_rank_ineligible','signup_default');
create function pg_temp.rank_contacts() returns text[] language sql as $$
 select array_agg('user_rank_peer_'||n) from generate_series(1,6) n;
$$;
set local role authenticated;
select pg_temp.require((select array_agg(id order by result_rank) from public.ranked_people_recommendations(pg_temp.rank_contacts(),50)
 where id in ('user_rank_one','user_rank_two','user_rank_six','user_rank_local'))=
 array['user_rank_six','user_rank_local','user_rank_two','user_rank_one'],'more contacts increase score, with two contacts below same-area and six above it');
select pg_temp.require((select contact_follow_count=6 and shared_follow_count=0 and reason_kind='contact_follows'
 from public.ranked_people_recommendations(pg_temp.rank_contacts(),50) where id='user_rank_six'),'contacts support candidates before viewer follows those contacts, with truthful count and reason');
select pg_temp.require((select contact_follow_count=6 from public.ranked_people_recommendations(pg_temp.rank_contacts()||pg_temp.rank_contacts()||array['missing'],50)
 where id='user_rank_six'),'duplicate and unknown contact IDs do not inflate support');
select pg_temp.require((select contact_follow_count=0 and shared_follow_count=0 and reason_kind='suggested'
 from public.ranked_people_recommendations('{}',50) where id='user_rank_six'),'removing contact IDs removes graph support and its reason');
select pg_temp.require((select contact_follow_count=0 and reason_kind='suggested'
 from public.ranked_people_recommendations(array['user_rank_private','user_rank_deleted','user_rank_blocked','user_rank_hidden','user_rank_viewer'],50)
 where id='user_rank_ineligible'),'private, deleted, blocked, hidden and self intermediaries add no contact support');
reset role;
-- Two peers become actual follows too: still only two supporting people.
insert into public.follows(follower_user_id,followed_user_id,source) values
 ('user_rank_viewer','user_rank_peer_1','signup_default'),
 ('user_rank_viewer','user_rank_peer_2','signup_default');
-- Graph now has only follows-you + same area = 65, above capped social support 60.
delete from public.follows where follower_user_id='user_rank_mutual' and followed_user_id='user_rank_graph';
set local role authenticated;
select pg_temp.require((select contact_follow_count=2 and shared_follow_count=2 from public.ranked_people_recommendations(pg_temp.rank_contacts(),50)
 where id='user_rank_two'),'overlapping connections preserve accurate individual reason counts');
select pg_temp.require((select array_agg(id order by result_rank) from public.ranked_people_recommendations(pg_temp.rank_contacts(),50)
 where id in ('user_rank_two','user_rank_local'))=array['user_rank_local','user_rank_two'],'contact plus actual follow is scored once per person, not twice');
select pg_temp.require((select array_agg(id order by result_rank) from public.ranked_people_recommendations(pg_temp.rank_contacts(),50)
 where id in ('user_rank_six','user_rank_graph'))=array['user_rank_graph','user_rank_six'],'social boost caps at 60 so six contacts do not overwhelm other signals');
select pg_temp.require((select contact_follow_count=0 and shared_follow_count=2 and reason_kind='shared_follows'
 from public.ranked_people_recommendations('{}',50) where id='user_rank_two'),'without contact access, actual follows still provide social support');
reset role;
-- Strong contact-graph support cannot override candidate privacy either.
update public.profiles set is_private_profile=true where id='user_rank_six';
set local role authenticated;
select pg_temp.require(not exists(select 1 from public.ranked_people_recommendations(pg_temp.rank_contacts(),50) where id='user_rank_six'),'contact graph never widens candidate visibility');
reset role;
rollback to savepoint contact_graph;
release savepoint contact_graph;
update public.profiles set is_private_profile=true where id='user_rank_curated';
insert into public.blocks(blocker_user_id,blocked_user_id) values('user_rank_contact','user_rank_viewer');
insert into app.profile_discovery_settings(profile_id,hidden_from_suggestions) values('user_rank_localcontact',true);
update public.profiles set deleted_at=now() where id='user_rank_graph';
set local role authenticated;
select pg_temp.require((select array_agg(id order by result_rank) from public.ranked_people_recommendations(array['user_rank_curated','user_rank_contact','user_rank_localcontact','user_rank_graph'],20))=
 array['user_rank_local','user_rank_general'],'contacts and curated priority never override private/block/hidden/deleted filters');
select set_config('request.jwt.claim.sub','user_rank_general',true);
select pg_temp.require(not exists(select 1 from public.ranked_people_recommendations('{}',20) where reason_kind='nearby'),'missing viewer area gives no fabricated location signal');
reset role;
select pg_temp.require((select count(*)=3 from public.follows where follower_user_id like 'user_rank_%'),'ranking never follows people');
select pass('Shared people ranking, combined signals, consent payload bounds and privacy passed');
select * from finish();
rollback;
