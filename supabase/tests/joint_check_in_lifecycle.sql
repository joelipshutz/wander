begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(45);
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

-- Edits use precise timestamps and a persistent request receipt. Keep the
-- transaction-local base token frozen to exercise stale drafts independently.
insert into joint_life_results select 'edit_base',to_jsonb(updated_at) from public.place_visits
 where id='b5670000-0000-0000-0000-000000000012';
create function pg_temp.edit_joint_life(operation_id uuid default 'b5670000-0000-0000-0000-000000000055',
 body text default 'Edited own note', expected_at timestamptz default null)
returns jsonb language sql as $$
 select public.edit_joint_check_in((select (result->>'group_id')::uuid from joint_life_results where name='created'),
 coalesce(expected_at,(select (result#>>'{}')::timestamptz from joint_life_results where name='edit_base')),operation_id,
 '{"canonical_name":"Joint Life Cafe","category":"coffee_tea_sweets","latitude":34.05,"longitude":-118.25,"source_provider":"codex_joint_life_test","source_provider_place_id":"joint-life-cafe"}',
 '{"id":"b5670000-0000-0000-0000-000000000011","status":"been","visibility":"mutuals","source_type":"manual"}','[]',
 jsonb_build_object('id','b5670000-0000-0000-0000-000000000012','visited_at','2026-07-02T19:00:00Z','note',body,'attribute_answers','[]'::jsonb),null)
$$;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select throws_ok($$select public.save_own_check_in('{}','{}','[]','{"id":"b5670000-0000-0000-0000-000000000012"}',null)$$,
 'P0001','joint_check_in_upgrade_required','legacy edit cannot bypass joint conflict checks');
select throws_ok($$update public.place_visits set note='Bypass' where id='b5670000-0000-0000-0000-000000000012'$$,
 'P0001','joint_check_in_upgrade_required','direct legacy content update is guarded');
select is(pg_temp.edit_joint_life()->>'note','Edited own note','owner can edit only their contribution');
select is(pg_temp.edit_joint_life()->>'note','Edited own note','lost edit response replays the same receipt');
select throws_ok($$select pg_temp.edit_joint_life(body:='Changed payload')$$,'P0001','joint_check_in_request_conflict','edit request payload cannot change');
select throws_ok($$select pg_temp.edit_joint_life(operation_id:='b5670000-0000-0000-0000-000000000056',expected_at:='2026-01-01')$$,
 'P0001','joint_check_in_edit_conflict','stale draft cannot overwrite a newer contribution');
reset role;
select is((select note from public.user_places where id='b5670000-0000-0000-0000-000000000011'),'Newer own note','older contribution edit preserves latest place summary');
select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select throws_ok($$select pg_temp.edit_joint_life()$$,'P0001','joint_check_in_invitation_unavailable','group starter cannot edit another participant note');
reset role;

-- Three terminal responses advanced revision 1 -> 4. Leaving keeps the personal event.
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select lives_ok($$insert into joint_life_results values('left',public.leave_joint_check_in((select (result->>'group_id')::uuid from joint_life_results where name='created'),4,'b5670000-0000-0000-0000-000000000040'))$$,'accepted participant can leave');
select throws_ok($$select pg_temp.respond_joint_life('joint_life_guest')$$,'P0001','joint_check_in_invitation_unavailable','accept retry after leave never resurrects membership');
reset role;
select ok(exists(select 1 from public.place_visits where id='b5670000-0000-0000-0000-000000000012' and deleted_at is null),'leave preserves personal visit');
select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select lives_ok($$select public.set_joint_check_in_invitees((select (result->>'group_id')::uuid from joint_life_results where name='created'),5,array['joint_life_guest','joint_life_wanna'],'b5670000-0000-0000-0000-000000000041')$$,'owner can reinvite with a new generation');
reset role;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select throws_ok($$select pg_temp.respond_joint_life('joint_life_guest')$$,'P0001','stale_joint_check_in_invitation','old generation remains stale after reinvite');
select is((pg_temp.respond_joint_life('joint_life_guest',operation_id:='b5670000-0000-0000-0000-000000000042',generation:=2,revision:=2)->>'visit_id'),'b5670000-0000-0000-0000-000000000012','rejoin relinks surviving personal visit');
reset role;
select is((select count(*) from public.place_visits where user_place_id='b5670000-0000-0000-0000-000000000011' and deleted_at is null),2::bigint,'rejoin adds no extra visit or stats');
-- A deleted retained visit requires an explicit new visit; it is never restored implicitly.
savepoint retained_restore;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select public.leave_joint_check_in((select (result->>'group_id')::uuid from joint_life_results where name='created'),7,'b5670000-0000-0000-0000-000000000061');
reset role;
update public.place_visits set deleted_at=now() where id='b5670000-0000-0000-0000-000000000012';
select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select public.set_joint_check_in_invitees((select (result->>'group_id')::uuid from joint_life_results where name='created'),8,
 array['joint_life_guest','joint_life_wanna'],'b5670000-0000-0000-0000-000000000062');
reset role;
select set_config('request.jwt.claim.sub','joint_life_guest',true);
set local role authenticated;
select throws_ok($$select pg_temp.respond_joint_life('joint_life_guest',operation_id:='b5670000-0000-0000-0000-000000000063',generation:=3,revision:=3)$$,
 'P0001','joint_check_in_explicit_restore_required','deleted retained contribution is not resurrected');
select lives_ok($$select public.accept_joint_check_in((select (result->>'participant_id')::uuid from joint_life_results where name='joint_life_guest'),3,3,
 'b5670000-0000-0000-0000-000000000064',1,'b5670000-0000-0000-0000-000000000011','b5670000-0000-0000-0000-000000000065',
 '{"visibility":"mutuals"}','{"starts_fresh_visit":true,"note":"Explicit new contribution"}')$$,'explicit fresh action can create a new contribution');
reset role;
select ok((select deleted_at is not null from public.place_visits where id='b5670000-0000-0000-0000-000000000012'),'fresh action preserves old tombstone');
rollback to savepoint retained_restore;
release savepoint retained_restore;

savepoint capacity;
insert into public.profiles(id,handle,display_name) select 'joint_life_capacity_'||i,'jointlifecapacity'||i,'Fictional Guest '||i from generate_series(1,10)i;
insert into public.follows(follower_user_id,followed_user_id,source)
select 'joint_life_owner','joint_life_capacity_'||i,'profile' from generate_series(1,10)i
union all select 'joint_life_capacity_'||i,'joint_life_owner','profile' from generate_series(1,10)i;
select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select lives_ok($$select public.set_joint_check_in_invitees((select (result->>'group_id')::uuid from joint_life_results where name='created'),7,
 (select array_agg('joint_life_capacity_'||i) from generate_series(1,9)i),'b5670000-0000-0000-0000-000000000070')$$,'nine invited seats plus starter are allowed');
reset role;
select is((select count(*) from public.shared_visit_participants where group_id=(select (result->>'group_id')::uuid from joint_life_results where name='created')
 and status in ('owner','pending','accepted')),10::bigint,'pending seats count toward the ten-person cap');
set local role authenticated;
select throws_ok($$select public.set_joint_check_in_invitees((select (result->>'group_id')::uuid from joint_life_results where name='created'),8,
 (select array_agg('joint_life_capacity_'||i) from generate_series(1,10)i),'b5670000-0000-0000-0000-000000000071')$$,
 'P0001','joint_check_in_capacity','eleventh total person is rejected');
reset role;
select is((select revision from public.shared_visit_groups where id=(select (result->>'group_id')::uuid from joint_life_results where name='created')),8::bigint,'capacity rejection commits no revision or membership change');
rollback to savepoint capacity;
release savepoint capacity;

select set_config('request.jwt.claim.sub','joint_life_owner',true);
set local role authenticated;
select lives_ok($$select public.leave_joint_check_in((select (result->>'group_id')::uuid from joint_life_results where name='created'),7,'b5670000-0000-0000-0000-000000000043')$$,'owner leave closes group');
reset role;
select is((select count(*) from public.shared_visit_participants where group_id=(select (result->>'group_id')::uuid from joint_life_results where name='created') and status in ('owner','accepted','pending')),0::bigint,'closure clears every active and pending membership');
select * from finish();
rollback;
