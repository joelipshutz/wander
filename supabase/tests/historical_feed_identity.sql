begin;
create extension if not exists pgtap;
select no_plan();
create temporary table historical_feed_results(message text) on commit drop;
grant insert, select on historical_feed_results to authenticated, anon;

-- Reserved synthetic identities; all fixtures and repair operations roll back.
insert into public.profiles(id,handle,display_name,is_private_profile) values
('rec614_owner','rec614owner','Historical Owner',false),
('rec614_viewer','rec614viewer','Historical Viewer',false),
('rec614_author','rec614author','Historical Author',false),
('rec614_stranger','rec614stranger','Historical Stranger',false);
insert into public.follows(follower_user_id,followed_user_id,source) values
('rec614_viewer','rec614_owner','profile'),('rec614_author','rec614_owner','profile');
create temporary table historical_fixture(parent_id uuid, original_id uuid, visit_id uuid,
  notifications_before bigint);
grant select, update, insert on historical_fixture to authenticated;
select set_config('request.jwt.claim.sub','rec614_owner',true);
select set_config('request.jwt.claims','{"sub":"rec614_owner","role":"authenticated"}',true);
-- Existing historical rows predate today's sync. The save RPC intentionally
-- preserves persisted saved_at; it does not accept a client saved_at override.
insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
values ('a6140000-0000-0000-0000-000000000030','Historical Fixture','coffee',0,0,'manual','rec614-historical');
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,saved_at)
values ('a6140000-0000-0000-0000-000000000031','rec614_owner','a6140000-0000-0000-0000-000000000030','been','followers','manual','2026-07-13T17:28:01Z');
insert into historical_fixture(parent_id) values ('a6140000-0000-0000-0000-000000000031');
update historical_fixture f set original_id=e.id, visit_id=v.id
from public.feed_events e, public.place_visits v
where e.user_place_id=f.parent_id and e.visit_id is null and e.event_type='place_been'
  and v.user_place_id=f.parent_id and v.backfilled_from_user_place;
insert into historical_feed_results select is((select count(*)::integer from historical_fixture where original_id is not null),1,'historical save records an original activity');
insert into historical_feed_results select is((select occurred_at from public.feed_events where id=(select original_id from historical_fixture)),
  '2026-07-13T17:28:01Z'::timestamptz,'historical save uses the visit date, not sync time');
set local role authenticated;
select public.delete_own_user_place(parent_id) from historical_fixture;
select public.save_own_place(
  '{"canonical_name":"Historical Fixture","category":"coffee","latitude":0,"longitude":0,"source_provider":"manual","source_provider_place_id":"rec614-historical"}',
  jsonb_build_object('id',parent_id,'status','been','visibility','followers','source_type','manual','saved_at','2026-07-13T17:28:01Z'), '[]') from historical_fixture;
reset role;
update public.user_places set deleted_at=now() where id=(select parent_id from historical_fixture);
update public.user_places set deleted_at=null where id=(select parent_id from historical_fixture);
update public.user_places set status='been' where id=(select parent_id from historical_fixture);
insert into historical_feed_results select is((select count(*)::integer from public.feed_events where user_place_id=(select parent_id from historical_fixture) and event_type='place_been'),1,'delete/restore and repeated save do not republish Been');
insert into historical_feed_results select is((select visited_at from public.place_visits where id=(select visit_id from historical_fixture)),
  '2026-07-13T17:28:01Z'::timestamptz,'restore retains the actual visit date');

-- Genuine repeat visits retain separate event identities.
insert into public.place_visits(id,user_place_id,visited_at,backfilled_from_user_place)
select 'a6140000-0000-0000-0000-000000000001',parent_id,now()-interval '1 day',false from historical_fixture;
insert into public.place_visits(id,user_place_id,visited_at,backfilled_from_user_place)
select 'a6140000-0000-0000-0000-000000000002',parent_id,now(),false from historical_fixture;
insert into historical_feed_results select is((select count(distinct id)::integer from public.feed_events where visit_id in ('a6140000-0000-0000-0000-000000000001','a6140000-0000-0000-0000-000000000002')),2,'two explicit visits produce two distinct events');

-- Reproduce two erroneous legacy events from the old trigger.
insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
select duplicate.id,'rec614_owner','place_been',parent.id,parent.place_id,now()
from public.user_places parent cross join (values
('a6140000-0000-0000-0000-000000000011'::uuid),
('a6140000-0000-0000-0000-000000000012'::uuid)) duplicate(id)
where parent.id=(select parent_id from historical_fixture);
insert into public.activity_likes(activity_id,user_id,created_at)
select original_id,'rec614_viewer','2026-08-01T00:00:00Z' from historical_fixture;
insert into public.activity_likes(activity_id,user_id,created_at) values
('a6140000-0000-0000-0000-000000000011','rec614_viewer','2026-08-02T00:00:00Z'),
('a6140000-0000-0000-0000-000000000012','rec614_author','2026-08-03T00:00:00Z');
insert into public.activity_comments(id,activity_id,author_user_id,body) values
('a6140000-0000-0000-0000-000000000021','a6140000-0000-0000-0000-000000000011','rec614_author','First fixture comment'),
('a6140000-0000-0000-0000-000000000022','a6140000-0000-0000-0000-000000000012','rec614_viewer','Second fixture comment');
insert into public.activity_comment_likes(comment_id,user_id) values
('a6140000-0000-0000-0000-000000000021','rec614_viewer');
update historical_fixture set notifications_before=(select count(*) from public.notification_events);
create temporary table historical_untouched as
select * from public.feed_events where user_place_id is distinct from (select parent_id from historical_fixture) or visit_id is not null;

insert into historical_feed_results select throws_ok($$select app.repair_legacy_feed_events(parent_id,4,'2026-07-13T17:28:01Z') from historical_fixture$$,'P0001','legacy_repair_count_changed','repair rejects changed event count');
insert into historical_feed_results select throws_ok($$select app.repair_legacy_feed_events(parent_id,3,'2026-07-14T17:28:01Z') from historical_fixture$$,'P0001','legacy_repair_visit_mismatch','repair rejects mismatched visit date');
insert into historical_feed_results select throws_ok($$select app.repair_legacy_feed_events(null,3,'2026-07-13T17:28:01Z')$$,'P0001','invalid_legacy_repair_scope','repair requires one explicit parent');
insert into historical_feed_results select is(app.repair_legacy_feed_events(parent_id,3,'2026-07-13T17:28:01Z'),2,'repair consolidates only two duplicate legacy events') from historical_fixture;
insert into historical_feed_results select is(app.repair_legacy_feed_events(parent_id,3,'2026-07-13T17:28:01Z'),0,'repair is idempotent') from historical_fixture;
insert into historical_feed_results select is((select count(*)::integer from public.feed_events where user_place_id=(select parent_id from historical_fixture) and visit_id is null and event_type='place_been'),1,'only original legacy activity remains');
insert into historical_feed_results select is((select occurred_at from public.feed_events where id=(select original_id from historical_fixture)),
  '2026-07-13T17:28:01Z'::timestamptz,'original activity retains its timestamp');
insert into historical_feed_results select is((select count(*)::integer from public.activity_likes where activity_id=(select original_id from historical_fixture)),2,'likes merge as a set of people');
insert into historical_feed_results select is((select created_at from public.activity_likes where activity_id=(select original_id from historical_fixture) and user_id='rec614_viewer'),
  '2026-08-01T00:00:00Z'::timestamptz,'duplicate liker retains earliest timestamp');
insert into historical_feed_results select is((select count(*)::integer from public.activity_comments where activity_id=(select original_id from historical_fixture)),2,'both comments survive');
insert into historical_feed_results select is((select count(*)::integer from public.activity_comment_likes where comment_id='a6140000-0000-0000-0000-000000000021'),1,'comment IDs and their likes survive');
insert into historical_feed_results select is((select count(*) from public.notification_events),(select notifications_before from historical_fixture),'repair sends no new engagement notifications');
insert into historical_feed_results select is((select count(*)::integer from ((select * from historical_untouched except select * from public.feed_events) union all (select * from public.feed_events where user_place_id is distinct from (select parent_id from historical_fixture) or visit_id is not null except select * from historical_untouched)) delta),0,'other activity and genuine repeat events are unchanged');
insert into historical_feed_results select is((select count(*)::integer from public.place_visits where user_place_id=(select parent_id from historical_fixture) and deleted_at is null),3,'all actual visits survive');

select set_config('request.jwt.claim.sub','rec614_viewer',true);
select set_config('request.jwt.claims','{"sub":"rec614_viewer","role":"authenticated"}',true);
set local role authenticated;
insert into historical_feed_results select is(public.activity_detail('a6140000-0000-0000-0000-000000000011')->>'id',(select original_id::text from historical_fixture),'old detail link resolves for authorized follower');
insert into historical_feed_results select is(jsonb_array_length(public.activity_comments('a6140000-0000-0000-0000-000000000011')->'comments'),2,'old link exposes preserved comments');
insert into historical_feed_results select is(public.activity_engagement_summaries(array['a6140000-0000-0000-0000-000000000011'::uuid])->0->>'activity_id','a6140000-0000-0000-0000-000000000011','batch summary retains requested cache key');
insert into historical_feed_results select is((public.activity_engagement_summaries(array['a6140000-0000-0000-0000-000000000011'::uuid])->0->>'like_count')::integer,2,'old cache key gets consolidated engagement');
insert into historical_feed_results select is((select activity_id from public.activity_media(array['a6140000-0000-0000-0000-000000000011'::uuid])),'a6140000-0000-0000-0000-000000000011'::uuid,'media retains requested cache key');
insert into historical_feed_results select is((public.set_activity_like('a6140000-0000-0000-0000-000000000011',false)->>'like_count')::integer,1,'old-link unlike updates surviving activity');
insert into historical_feed_results select is((public.set_activity_like('a6140000-0000-0000-0000-000000000012',true)->>'like_count')::integer,2,'another old-link like updates same activity');
insert into historical_feed_results select is(public.add_activity_comment('a6140000-0000-0000-0000-000000000012','After repair')->'comment'->>'activity_id',(select original_id::text from historical_fixture),'old-link comment uses surviving ID');
reset role;

-- Visibility checks always run against the canonical activity.
select set_config('request.jwt.claim.sub','rec614_stranger',true);
select set_config('request.jwt.claims','{"sub":"rec614_stranger","role":"authenticated"}',true);
set local role authenticated;
insert into historical_feed_results select throws_ok($$select public.activity_detail('a6140000-0000-0000-0000-000000000011')$$,'P0001','activity_not_visible','stranger cannot read through alias');
insert into historical_feed_results select throws_ok($$select public.add_activity_comment('a6140000-0000-0000-0000-000000000011','Denied')$$,'P0001','activity_not_visible','stranger cannot write through alias');
insert into historical_feed_results select is((select count(*)::integer from public.activity_media(array['a6140000-0000-0000-0000-000000000011'::uuid])),0,'media alias does not leak to stranger');
reset role;
select set_config('request.jwt.claim.sub','rec614_viewer',true);
select set_config('request.jwt.claims','{"sub":"rec614_viewer","role":"authenticated"}',true);
insert into public.blocks(blocker_user_id,blocked_user_id) values ('rec614_owner','rec614_viewer');
set local role authenticated;
insert into historical_feed_results select throws_ok($$select public.set_activity_like('a6140000-0000-0000-0000-000000000011',true)$$,'P0001','activity_not_visible','block applies to old links');
reset role;
delete from public.blocks where blocker_user_id='rec614_owner' and blocked_user_id='rec614_viewer';
update public.profiles set is_private_profile=true where id='rec614_owner';
set local role authenticated;
insert into historical_feed_results select throws_ok($$select public.activity_detail('a6140000-0000-0000-0000-000000000011')$$,'P0001','activity_not_visible','private-account gate applies to old links');
reset role;
update public.profiles set is_private_profile=false where id='rec614_owner';
update public.user_places set deleted_at=now() where id=(select parent_id from historical_fixture);
set local role authenticated;
insert into historical_feed_results select throws_ok($$select public.activity_comments('a6140000-0000-0000-0000-000000000011')$$,'P0001','activity_not_visible','deleted source cannot be read through alias');
reset role;
update public.user_places set deleted_at=null where id=(select parent_id from historical_fixture);
insert into historical_feed_results select is((select count(*)::integer from public.feed_events where user_place_id=(select parent_id from historical_fixture) and event_type='place_been'),3,'restoring repaired parent preserves one legacy and two explicit events');
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
set local role anon;
insert into historical_feed_results select throws_ok($$select public.activity_detail('a6140000-0000-0000-0000-000000000011')$$,'42501',null,'anonymous execution remains denied');
reset role;

-- Historical parents without an event are restored at their persisted date;
-- a first active Wanna -> Been transition is new activity today.
insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
values ('a6140000-0000-0000-0000-000000000040','Transition Fixture','coffee',0,0,'manual','rec614-transition');
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,saved_at,deleted_at)
values ('a6140000-0000-0000-0000-000000000041','rec614_owner','a6140000-0000-0000-0000-000000000040','been','followers','manual','2026-07-01',now());
update public.user_places set deleted_at=null where id='a6140000-0000-0000-0000-000000000041';
insert into historical_feed_results select is((select occurred_at from public.feed_events where user_place_id='a6140000-0000-0000-0000-000000000041' and event_type='place_been'),'2026-07-01'::timestamptz,'restore with no existing event retains the historical date');
-- Simulate an explicit-check-in-only parent: restores must not invent a legacy
-- event merely because its existing event has a visit_id.
delete from public.feed_events where user_place_id='a6140000-0000-0000-0000-000000000041';
insert into public.place_visits(id,user_place_id,visited_at,backfilled_from_user_place)
values ('a6140000-0000-0000-0000-000000000042','a6140000-0000-0000-0000-000000000041',now(),false);
update public.user_places set deleted_at=now() where id='a6140000-0000-0000-0000-000000000041';
update public.user_places set deleted_at=null where id='a6140000-0000-0000-0000-000000000041';
insert into historical_feed_results select is((select count(*)::integer from public.feed_events where user_place_id='a6140000-0000-0000-0000-000000000041'),1,'explicit-check-in-only parent restore adds no legacy event');
insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
values ('a6140000-0000-0000-0000-000000000050','Wanna Transition Fixture','coffee',0,0,'manual','rec614-wanna-transition');
insert into public.user_places(id,user_id,place_id,status,visibility,source_type,saved_at)
values ('a6140000-0000-0000-0000-000000000051','rec614_owner','a6140000-0000-0000-0000-000000000050','wanna_go','followers','manual','2026-07-01');
update public.user_places set status='been' where id='a6140000-0000-0000-0000-000000000051';
insert into historical_feed_results select is((select occurred_at from public.feed_events where user_place_id='a6140000-0000-0000-0000-000000000051' and event_type='place_been'),now(),'first active Wanna-to-Been transition remains new activity');

-- Recreated functions preserve security, volatility, search paths and grants.
insert into historical_feed_results select ok(p.prosecdef and p.provolatile=signature.volatility
  and 'search_path=pg_catalog, public, app'=any(p.proconfig),signature.name || ' retains security metadata')
from (values
('app.canonical_activity_id(uuid)','s'::"char"),
('app.repair_legacy_feed_events(uuid,integer,timestamptz)','v'::"char"),
('app.can_read_activity_event(text,uuid)','s'::"char"),
('app.activity_engagement_json(text,uuid)','s'::"char"),
('public.activity_detail(uuid)','s'::"char"),
('public.activity_comments(uuid,text,integer)','s'::"char"),
('public.set_activity_like(uuid,boolean)','v'::"char"),
('public.add_activity_comment(uuid,text)','v'::"char"),
('public.activity_media(uuid[])','s'::"char")) signature(name,volatility)
join pg_proc p on p.oid=signature.name::regprocedure;
insert into historical_feed_results select ok(has_function_privilege('authenticated',signature,'execute')
  and not has_function_privilege('anon',signature,'execute'),signature || ' retains authenticated-only execution')
from (values ('public.activity_detail(uuid)'),('public.activity_comments(uuid,text,integer)'),
('public.set_activity_like(uuid,boolean)'),('public.add_activity_comment(uuid,text)'),('public.activity_media(uuid[])')) f(signature);
insert into historical_feed_results select ok(not has_function_privilege('authenticated',signature,'execute')
  and not has_function_privilege('anon',signature,'execute'),signature || ' remains private')
from (values ('app.canonical_activity_id(uuid)'),('app.repair_legacy_feed_events(uuid,integer,timestamptz)'),
('app.can_read_activity_event(text,uuid)'),('app.activity_engagement_json(text,uuid)'),('app.record_user_place_feed_event()')) f(signature);
insert into historical_feed_results select ok((select prosecdef and provolatile='v' and 'search_path=public, app'=any(proconfig) from pg_proc where oid='app.record_user_place_feed_event()'::regprocedure),'parent trigger retains its security metadata');
insert into historical_feed_results select ok((select relrowsecurity from pg_class where oid='app.activity_event_aliases'::regclass)
  and not has_table_privilege('authenticated','app.activity_event_aliases','select,insert,update,delete')
  and not has_table_privilege('anon','app.activity_event_aliases','select,insert,update,delete'),'alias table is private and RLS enabled');
do $strict_pgtap$
declare diagnostics text;
begin
  select string_agg(message,E'\n') into diagnostics from historical_feed_results where message like 'not ok%';
  if diagnostics is not null then raise exception 'Historical feed assertions failed: %',diagnostics; end if;
  select string_agg(result.message,E'\n') into diagnostics from finish() as result(message);
  if diagnostics is not null and diagnostics like '%failed%' then raise exception 'Historical feed plan failed: %',diagnostics; end if;
end;
$strict_pgtap$;
select count(*) as historical_feed_assertions_passed from historical_feed_results;
rollback;
