begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(58);
insert into public.profiles(id, handle, display_name) values
 ('joint_life_owner','jointlifeowner','Fictional Ryan'),
 ('joint_life_guest','jointlifeguest','Fictional Joe'),
 ('joint_life_private','jointlifeprivate','Fictional Private'),
 ('joint_life_wanna','jointlifewanna','Fictional Wanna');
insert into public.follows(follower_user_id, followed_user_id, source)
select 'joint_life_owner', id, 'profile' from public.profiles where id in ('joint_life_guest','joint_life_private','joint_life_wanna')
union all select id, 'joint_life_owner', 'profile' from public.profiles where id in ('joint_life_guest','joint_life_private','joint_life_wanna');
update public.feature_flags set enabled = true where key = 'joint_check_ins_v2' and user_id is null;
create temporary table joint_life_results(name text primary key, result jsonb);
grant all on joint_life_results to authenticated;
select set_config('request.jwt.claim.sub', 'joint_life_owner', true);
set local role authenticated;
insert into joint_life_results values('created',public.save_joint_check_in(
 '{"canonical_name":"Joint Life Cafe","category":"coffee_tea_sweets","latitude":34.05,"longitude":-118.25,"source_provider":"codex_joint_life_test","source_provider_place_id":"joint-life-cafe"}',
 '{"status":"been","visibility":"followers","source_type":"manual"}', '[]',
 '{"id":"b5670000-0000-0000-0000-000000000001","visited_at":"2026-07-02T19:00:00Z","note":"Owner only","rating_score":4.5}',
 null, array['joint_life_guest','joint_life_private','joint_life_wanna'], 'b5670000-0000-0000-0000-000000000002',1));
reset role;
insert into joint_life_results
select user_id, jsonb_build_object('participant_id', id, 'generation', invitation_generation, 'revision', snapshot_revision)
from public.shared_visit_participants where group_id = (select (result->>'group_id')::uuid from joint_life_results where name='created');
create function pg_temp.respond_joint_life(who text, private_save boolean default false,
 operation_id uuid default 'b5670000-0000-0000-0000-000000000003',
 generation integer default 1, revision integer default 1, note text default 'Own contribution')
returns jsonb language plpgsql as $$
declare member_id uuid; parent_id uuid; visit_id uuid;
begin
 select (result->>'participant_id')::uuid into member_id from joint_life_results where name=who;
 parent_id := case who when 'joint_life_guest' then 'b5670000-0000-0000-0000-000000000011'::uuid
 when 'joint_life_private' then 'b5670000-0000-0000-0000-000000000021'::uuid else 'b5670000-0000-0000-0000-000000000031'::uuid end;
 visit_id := case who when 'joint_life_guest' then 'b5670000-0000-0000-0000-000000000012'::uuid
 when 'joint_life_private' then 'b5670000-0000-0000-0000-000000000022'::uuid else 'b5670000-0000-0000-0000-000000000032'::uuid end;
 if private_save then
  return public.save_joint_invitation_privately(member_id,generation,revision,operation_id,parent_id,visit_id,'{"visibility":"followers"}',jsonb_build_object('note',note));
 end if;
 return public.accept_joint_check_in(member_id,generation,revision,operation_id,1,parent_id,visit_id,'{"visibility":"followers"}',jsonb_build_object('note',note));
end;
$$;
-- The guest has a newer visit and an existing Friends parent with private metadata.
select set_config('app.explicit_check_in','on',true);
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note,category_override)
select 'b5670000-0000-0000-0000-000000000011','joint_life_guest',(result->>'place_id')::uuid,'been','mutuals','manual','Newer own note','restaurants_food'
from joint_life_results where name='created';
insert into public.place_visits(id,user_place_id,visited_at,note,rating_score,attribute_answers,backfilled_from_user_place)
values('b5670000-0000-0000-0000-000000000013','b5670000-0000-0000-0000-000000000011','2026-07-03T19:00:00Z','Newer own note',5,'[]',false);
update public.place_visits set deleted_at=now() where user_place_id='b5670000-0000-0000-0000-000000000011' and backfilled_from_user_place;
insert into public.place_attributes(user_place_id,question_key,value_type,value)
values('b5670000-0000-0000-0000-000000000011','my_private_label','text','"Keep label"');
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
select 'b5670000-0000-0000-0000-000000000021','joint_life_private',(result->>'place_id')::uuid,'been','self','manual','Private history'
from joint_life_results where name='created';
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,note)
select 'b5670000-0000-0000-0000-000000000031','joint_life_wanna',(result->>'place_id')::uuid,'wanna_go','mutuals','manual','Original Wanna'
from joint_life_results where name='created';
select set_config('app.explicit_check_in','',true);
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select lives_ok($$insert into joint_life_results values('accepted',pg_temp.respond_joint_life('joint_life_guest'))$$,'accept an existing saved place');
select is((select result->'user_place'->>'visibility' from joint_life_results where name='accepted'),'mutuals','acceptance inherits existing Friends visibility');
select is((select result->'user_place'->>'note' from joint_life_results where name='accepted'),'Newer own note','older joint visit never replaces newer summary');
select is((select result->>'note' from joint_life_results where name='accepted'),'Own contribution','contribution belongs to the invitee');
select is((select result->>'rating_score' from joint_life_results where name='accepted'),null::text,'blank rating does not copy owner score');
select is((pg_temp.respond_joint_life('joint_life_guest')->>'visit_id'),'b5670000-0000-0000-0000-000000000012','same operation replays one visit');
select throws_ok($$select pg_temp.respond_joint_life('joint_life_guest',operation_id:='b5670000-0000-0000-0000-000000000099')$$,'P0001','joint_check_in_invitation_unavailable','another operation cannot duplicate an accepted generation');
select throws_ok($$select pg_temp.respond_joint_life('joint_life_guest',note:='Changed payload')$$,'P0001','joint_check_in_request_conflict','acceptance request is bound to payload');
select throws_ok($$select pg_temp.respond_joint_life('joint_life_private')$$,'P0001','joint_check_in_invitation_unavailable','cross-account replay exposes no invitation');
reset role;
select is((select count(*) from public.place_visits where user_place_id='b5670000-0000-0000-0000-000000000011' and deleted_at is null),2::bigint,'one visit appended to existing history');
select is((select value::text from public.place_attributes where user_place_id='b5670000-0000-0000-0000-000000000011' and question_key='my_private_label'),'"Keep label"','parent attributes retained');
select is((select category_override from public.user_places where id='b5670000-0000-0000-0000-000000000011'),'restaurants_food','parent classification retained');
select set_config('request.jwt.claim.sub','joint_life_private',true);
set local role authenticated;
select throws_ok($$select pg_temp.respond_joint_life('joint_life_private')$$,'P0001','joint_check_in_private_place','acceptance cannot widen Self place');
select lives_ok($$insert into joint_life_results values('private',pg_temp.respond_joint_life('joint_life_private',true))$$,'Save privately commits independently');
select is((select result->>'canonical_activity_id' from joint_life_results where name='private'),null::text,'private save has no conversation alias');
select is((select result->>'status' from joint_life_results where name='private'),'declined','private save declines invitation');
select is((pg_temp.respond_joint_life('joint_life_private',true)->>'visit_id'),'b5670000-0000-0000-0000-000000000022','private save retry reuses visit');
select throws_ok($$select pg_temp.respond_joint_life('joint_life_private',operation_id:='b5670000-0000-0000-0000-000000000088')$$,'P0001','joint_check_in_invitation_unavailable','private save generation cannot later accept');
reset role;
select set_config('request.jwt.claim.sub','joint_life_wanna',true);
set local role authenticated;
select lives_ok($$insert into joint_life_results values('wanna',pg_temp.respond_joint_life('joint_life_wanna'))$$,'Wanna transitions to Been');
select is((select result->'user_place'->>'historical_want_note' from joint_life_results where name='wanna'),'Original Wanna','original Wanna data preserved');
reset role;
select is((select count(*) from public.place_visits where user_place_id='b5670000-0000-0000-0000-000000000031' and deleted_at is null),1::bigint,'Wanna acceptance creates exactly one real visit');
insert into public.profiles(id,handle,display_name) values
 ('joint_view_guest','jointviewguest','Fictional Guest Follower'),
 ('joint_view_owner','jointviewowner','Fictional Owner Follower'),
 ('joint_view_none','jointviewnone','Fictional Outsider');
-- New profiles automatically follow seed accounts. Isolate only these synthetic
-- actors so live activity cannot push the historical fixture off page one.
delete from public.follows where follower_user_id in ('joint_view_guest','joint_view_owner','joint_view_none');
insert into public.follows(follower_user_id,followed_user_id,source) values
 ('joint_view_guest','joint_life_guest','profile'),('joint_life_guest','joint_view_guest','profile'),
 ('joint_view_owner','joint_life_owner','profile');
insert into public.visit_photos(visit_id,storage_path,content_type,upload_state) values
 ('b5670000-0000-0000-0000-000000000001','joint_life_owner/source/fictional.jpg','image/jpeg','uploaded'),
 ('b5670000-0000-0000-0000-000000000012','joint_life_guest/source/fictional.jpg','image/jpeg','uploaded');
insert into joint_life_results values('personal_guest',jsonb_build_object('id',(select id from public.feed_events where visit_id='b5670000-0000-0000-0000-000000000012')));
create function pg_temp.joint_activity_id() returns uuid language sql as $$select (result->>'canonical_activity_id')::uuid from joint_life_results where name='created'$$;
create function pg_temp.personal_activity_id() returns uuid language sql as $$select (result->>'id')::uuid from joint_life_results where name='personal_guest'$$;
select set_config('request.jwt.claim.sub','joint_view_guest',true);
set local role authenticated;
select is(jsonb_array_length(public.activity_detail_v2(pg_temp.joint_activity_id())->'joint_check_in'->'contributions'),1,'viewer sees only readable guest, with no hidden count');
select is(public.activity_detail_v2(pg_temp.joint_activity_id())->'actor'->>'id','joint_life_guest','hidden starter is not serialized as actor');
select is(public.activity_detail_v2(pg_temp.joint_activity_id())->'joint_check_in'->'contributions'->0->>'note','Own contribution','visible contributor note preserved');
select is(public.activity_detail_v2(pg_temp.personal_activity_id())->>'id',pg_temp.joint_activity_id()::text,'unused personal event resolves canonical read alias');
select is((public.joint_check_in_contexts(array['b5670000-0000-0000-0000-000000000001'::uuid])->'mappings'->0->>'group_id'),null::text,'unreadable profile subject gets no joint context');
select is((select jsonb_array_length(media) from public.activity_media_v2(array[pg_temp.joint_activity_id()])),1,'media contains only readable contributor photo');
select is((select media->0->>'owner_user_id' from public.activity_media_v2(array[pg_temp.joint_activity_id()])),'joint_life_guest','hidden starter photo never used as fallback');
select is((select count(*) from jsonb_array_elements(public.followed_feed_v2(false,null,50)->'activity') activity where activity->>'id'=pg_temp.joint_activity_id()::text),1::bigint,'following only an accepted guest still yields one canonical tile');
select is((select count(*) from jsonb_array_elements(public.followed_feed_v2(false,null,50)->'activity') activity where activity->>'id'=pg_temp.personal_activity_id()::text),0::bigint,'member event suppressed before paging');
select throws_ok($$select public.activity_detail(pg_temp.joint_activity_id())$$,'P0001','activity_not_visible','old detail cannot expose canonical event as a solo owner card');
select throws_ok($$select public.set_activity_like_v2(pg_temp.personal_activity_id(),true)$$,'P0001','activity_context_changed','stale personal write cannot silently redirect to joint audience');
select lives_ok($$select public.set_activity_like_v2(pg_temp.joint_activity_id(),true)$$,'eligible follower can like the shared conversation');
select throws_ok($$select public.add_activity_comment_v2(pg_temp.joint_activity_id(),'Fictional comment','b5680000-0000-0000-0000-000000000001')$$,'P0001','joint_check_in_discussion_consent_required','comment requires shared-audience acknowledgement');
select lives_ok($$insert into joint_life_results values('comment',public.add_activity_comment_v2(pg_temp.joint_activity_id(),'Fictional comment','b5680000-0000-0000-0000-000000000001',1))$$,'comment published once to canonical discussion');
select is(public.add_activity_comment_v2(pg_temp.joint_activity_id(),'Fictional comment','b5680000-0000-0000-0000-000000000001',1)->'comment'->>'id',(select result->'comment'->>'id' from joint_life_results where name='comment'),'lost-response comment retry returns same comment');
select throws_ok($$select public.add_activity_comment_v2(pg_temp.joint_activity_id(),'Changed comment','b5680000-0000-0000-0000-000000000001',1)$$,'P0001','joint_check_in_request_conflict','comment key cannot be rebound to different text');
select lives_ok($$select public.delete_own_activity_comment((select (result->'comment'->>'id')::uuid from joint_life_results where name='comment'))$$,'author deletes comment');
select throws_ok($$select public.add_activity_comment_v2(pg_temp.joint_activity_id(),'Fictional comment','b5680000-0000-0000-0000-000000000001',1)$$,'P0001','comment_deleted','delayed retry never resurrects deleted comment');
reset role;
select ok(not exists(select 1 from public.joint_check_in_operations where actor_user_id='joint_view_guest' and committed_result::text like '%Fictional comment%'),'receipt does not retain deleted body');
select set_config('request.jwt.claim.sub','joint_view_none',true);
set local role authenticated;
select throws_ok($$select public.activity_detail_v2(pg_temp.joint_activity_id())$$,'P0001','activity_not_visible','unrelated viewer cannot read joint occasion');
select is(public.activity_engagement_summaries_v2(array[pg_temp.joint_activity_id()]),'[]'::jsonb,'inaccessible group leaks no engagement count');
reset role;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select lives_ok($$select public.leave_joint_check_in((select (result->>'group_id')::uuid from joint_life_results where name='created'),4,'b5680000-0000-0000-0000-000000000002')$$,'guest leaves shared audience');
reset role;
select set_config('request.jwt.claim.sub','joint_view_guest',true);
set local role authenticated;
select lives_ok($$select public.set_activity_like(pg_temp.personal_activity_id(),true)$$,'legacy like on detached personal discussion still works');
select lives_ok($$select public.set_activity_like(pg_temp.personal_activity_id(),false)$$,'legacy unlike works');
reset role;
select ok((select standalone_engagement_started_at is not null from public.feed_events where id=pg_temp.personal_activity_id()),'personal identity survives removal of all engagement');
select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select lives_ok($$select public.set_joint_check_in_invitees((select (result->>'group_id')::uuid from joint_life_results where name='created'),5,array['joint_life_guest','joint_life_wanna'],'b5680000-0000-0000-0000-000000000003')$$,'reinvite after personal engagement');
reset role;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select lives_ok($$select pg_temp.respond_joint_life('joint_life_guest',operation_id:='b5680000-0000-0000-0000-000000000004',generation:=2,revision:=2)$$,'rejoin retains original contribution');
reset role;
select set_config('request.jwt.claim.sub','joint_view_guest',true);
set local role authenticated;
select is(public.activity_detail_v2(pg_temp.personal_activity_id())->>'id',pg_temp.personal_activity_id()::text,'pinned personal discussion never redirects after rejoin');
select is(public.activity_detail_v2(pg_temp.joint_activity_id())->>'id',pg_temp.joint_activity_id()::text,'shared tile retains its own discussion');
reset role;
-- A starter block cuts off access through the guest; guest personal history remains.
insert into public.blocks(blocker_user_id,blocked_user_id) values('joint_life_owner','joint_view_guest');
select set_config('request.jwt.claim.sub','joint_view_guest',true);
set local role authenticated;
select throws_ok($$select public.activity_detail_v2(pg_temp.joint_activity_id())$$,'P0001','activity_not_visible','starter block cannot be bypassed through another participant');
select lives_ok($$select public.activity_detail_v2(pg_temp.personal_activity_id())$$,'block leaves authorized independent personal discussion reachable');
reset role;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select throws_ok($$update public.place_visits set visited_at=visited_at+interval '1 day' where id='b5670000-0000-0000-0000-000000000012'$$,'P0001','joint_check_in_detach_before_changing_occasion','accepted occasion cannot silently move');
select lives_ok($$select public.delete_own_check_in('b5670000-0000-0000-0000-000000000012')$$,'legacy owned delete can detach a v2 contribution');
reset role;
select is((select status from public.shared_visit_participants where group_id=(select (result->>'group_id')::uuid from joint_life_results where name='created') and user_id='joint_life_guest'),'removed','deleting contribution detaches membership');
select ok((select cancelled_at is null from public.shared_visit_groups where id=(select (result->>'group_id')::uuid from joint_life_results where name='created')),'other participant deletion does not close group');
update public.user_places set visibility='self' where id=(select (result->>'user_place_id')::uuid from joint_life_results where name='created');
select ok((select cancelled_at is not null from public.shared_visit_groups where id=(select (result->>'group_id')::uuid from joint_life_results where name='created')),'starter Self closes group permanently');
update public.user_places set visibility='followers' where id=(select (result->>'user_place_id')::uuid from joint_life_results where name='created');
select set_config('request.jwt.claim.sub','joint_view_owner',true);
set local role authenticated;
select throws_ok($$select public.activity_detail_v2(pg_temp.joint_activity_id())$$,'P0001','activity_not_visible','restoring privacy never reopens group');
reset role;
select * from finish();
rollback;
