begin;
create extension if not exists pgtap;
select plan(44);

select ok((select prosecdef from pg_proc where oid = 'public.followed_feed(boolean,text,integer)'::regprocedure), 'public activity-only RPC is security definer');
select ok((select prosecdef from pg_proc where oid = 'app.followed_feed(boolean,text,integer)'::regprocedure), 'private activity-only projection is security definer');
select ok((select provolatile = 's' from pg_proc where oid = 'app.followed_feed(boolean,text,integer)'::regprocedure), 'projection remains stable');
select ok((select 'search_path=app, public' = any(proconfig) from pg_proc where oid = 'public.followed_feed(boolean,text,integer)'::regprocedure), 'public wrapper pins its search path');
select ok((select 'search_path=public, app' = any(proconfig) from pg_proc where oid = 'app.followed_feed(boolean,text,integer)'::regprocedure), 'projection pins its search path');
select ok(has_function_privilege('authenticated', 'public.followed_feed(boolean,text,integer)', 'execute'), 'authenticated can invoke the new overload');
select ok(not has_function_privilege('anon', 'public.followed_feed(boolean,text,integer)', 'execute'), 'anonymous cannot invoke the new overload');
select ok(not has_function_privilege('anon', 'app.followed_feed(boolean,text,integer)', 'execute'), 'anonymous cannot invoke the private projection');
select ok(has_function_privilege('authenticated', 'public.followed_feed(text,integer)', 'execute'), 'existing clients retain the original RPC');
select ok(not has_table_privilege('authenticated', 'public.feed_events', 'select'), 'raw feed events remain private');

insert into public.profiles(id, handle, display_name, is_private_profile) values
('user_rec531_feed_viewer', 'rec531feedviewer', 'Feed smoke viewer', false),
('user_rec531_feed_actor', 'rec531feedactor', 'Feed smoke actor', false),
('user_rec531_feed_stranger', 'rec531feedstranger', 'Feed smoke stranger', false);
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_rec531_feed_viewer', 'user_rec531_feed_actor', 'profile');
insert into public.places(id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id) values
('53100000-0000-0000-0000-000000000001', 'Feed smoke one', 'coffee', 0, 0, 'manual', 'rec531-one'),
('53100000-0000-0000-0000-000000000002', 'Feed smoke two', 'coffee', 0, 0, 'manual', 'rec531-two'),
('53100000-0000-0000-0000-000000000003', 'Feed smoke private', 'coffee', 0, 0, 'manual', 'rec531-private');
insert into public.user_places(id, user_id, place_id, status, visibility, source_type, note) values
('53110000-0000-0000-0000-000000000001','user_rec531_feed_actor','53100000-0000-0000-0000-000000000001','wanna_go','followers','manual','Visible smoke note'),
('53110000-0000-0000-0000-000000000002','user_rec531_feed_actor','53100000-0000-0000-0000-000000000002','wanna_go','followers','manual',null),
('53110000-0000-0000-0000-000000000003','user_rec531_feed_actor','53100000-0000-0000-0000-000000000003','wanna_go','self','manual','Private smoke note');
select set_config('request.jwt.claim.sub','user_rec531_feed_viewer',true);
set local role authenticated;
select is(jsonb_array_length(public.followed_feed(false)->'activity'),2,'authenticated viewer receives only visible activity');
select is(public.followed_feed(false)->'activity',public.followed_feed()->'activity','activity-only and original projections return identical authorized activity');
select is(public.followed_feed(false)->'featured_places','[]'::jsonb,'disabled Featured returns no candidates');
select ok(jsonb_array_length(public.followed_feed()->'featured_places') > 0,'original Featured implementation still returns candidates');
select is(public.followed_feed(true),public.followed_feed(),'explicit Featured restores the original result');
select is(public.followed_feed(false,null,1)->>'next_cursor',public.followed_feed(null,1)->>'next_cursor','activity-only preserves pagination cursor');
select is(jsonb_array_length(public.followed_feed(false,null,1)->'activity'),1,'activity-only respects page limit');
select isnt(public.followed_feed(false,null,1)->'activity'->0->>'id',public.followed_feed(false,public.followed_feed(false,null,1)->>'next_cursor',1)->'activity'->0->>'id','next page advances without duplicating the first event');
select ok(not (public.followed_feed(false)::text like '%Private smoke note%'),'private activity content is excluded');
reset role;

-- Cover every event branch copied into the activity-only projection. Distinct
-- notes identify each immutable ticket rather than accepting parent metadata.
insert into public.places(id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id) values
('53100000-0000-0000-0000-000000000004', 'Feed smoke visits', 'coffee', 0, 0, 'manual', 'rec531-visits'),
('53100000-0000-0000-0000-000000000005', 'Feed smoke social save', 'coffee', 0, 0, 'manual', 'rec531-social');
insert into public.user_places(id, user_id, place_id, status, visibility, source_type, note, rating_score) values
('53110000-0000-0000-0000-000000000004','user_rec531_feed_actor','53100000-0000-0000-0000-000000000004','been','followers','manual','Parent check-in smoke note',1),
('53110000-0000-0000-0000-000000000005','user_rec531_feed_actor','53100000-0000-0000-0000-000000000005','been','followers','social_save','Social save smoke note',null);
insert into public.place_visits(id, user_place_id, visited_at, note, rating_score, backfilled_from_user_place) values
('53120000-0000-0000-0000-000000000001','53110000-0000-0000-0000-000000000004',now()-interval '2 days','Explicit visit smoke note',4.5,false),
('53120000-0000-0000-0000-000000000002','53110000-0000-0000-0000-000000000004',now()-interval '1 day','Deleted visit smoke note',2,false);
insert into public.place_lists(id, owner_user_id, name, description, visibility)
values ('53130000-0000-0000-0000-000000000001','user_rec531_feed_actor','Feed smoke list','List creation smoke note','followers');
insert into public.place_list_items(id, list_id, place_id, owner_user_place_id, added_by_user_id)
values ('53140000-0000-0000-0000-000000000001','53130000-0000-0000-0000-000000000001',
        '53100000-0000-0000-0000-000000000004','53110000-0000-0000-0000-000000000004','user_rec531_feed_actor');
create temporary table rec531_feed_fixture_events as
select id, visit_id from public.feed_events
where actor_user_id = 'user_rec531_feed_actor' and visit_id is not null;
grant select on rec531_feed_fixture_events to authenticated;

select set_config('request.jwt.claim.sub','user_rec531_feed_actor',true);
set local role authenticated;
select public.save_own_place_wanna('53110000-0000-0000-0000-000000000004',jsonb_build_object(
  'id','53150000-0000-0000-0000-000000000001','occurred_at',now(),
  'note','Repeat Wanna smoke note','visibility','followers','attribute_answers','[]'::jsonb));
select public.save_own_place_wanna('53110000-0000-0000-0000-000000000004',jsonb_build_object(
  'id','53150000-0000-0000-0000-000000000002','occurred_at',now(),
  'note','Private repeat Wanna smoke note','visibility','self','attribute_answers','[]'::jsonb));
select public.save_own_place_wanna('53110000-0000-0000-0000-000000000004',jsonb_build_object(
  'id','53150000-0000-0000-0000-000000000003','occurred_at',now(),
  'note','Mutual repeat Wanna smoke note','visibility','mutuals','attribute_answers','[]'::jsonb));
select set_config('request.jwt.claim.sub','user_rec531_feed_viewer',true);
select is(public.followed_feed(false)->'activity',public.followed_feed()->'activity',
  'all activity types preserve the exact legacy projection');
select is((select array_agg(distinct item->>'event_type' order by item->>'event_type')
  from jsonb_array_elements(public.followed_feed(false)->'activity') item),
  array['list_created','list_item_added','place_been','place_saved','place_want_to_go']::text[],
  'activity-only includes list creation, list items, visits, social saves, and Wanna saves');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'=(select id::text from rec531_feed_fixture_events where visit_id='53120000-0000-0000-0000-000000000001')
    and item->>'note'='Explicit visit smoke note' and (item->>'rating')::numeric=4.5),
  'explicit check-in retains its own note and rating');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'=(select id::text from rec531_feed_fixture_events where visit_id='53120000-0000-0000-0000-000000000002')),
  'visit selected for deletion is visible before deletion');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'event_type'='list_created' and item->'list'->>'id'='53130000-0000-0000-0000-000000000001'
    and item->>'note'='List creation smoke note'),
  'list creation keeps the list description');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'event_type'='list_item_added' and item->'list'->>'id'='53130000-0000-0000-0000-000000000001'
    and item->'place'->>'user_place_id'='53110000-0000-0000-0000-000000000004'),
  'list item keeps its list and source place projection');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'='53150000-0000-0000-0000-000000000001' and item->>'note'='Repeat Wanna smoke note'
    and item->'rating'='null'::jsonb and item->'place'->'rating_score'='null'::jsonb),
  'repeat Wanna keeps its own note without inheriting the check-in rating');
select ok(not exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id' in ('53150000-0000-0000-0000-000000000002','53150000-0000-0000-0000-000000000003')),
  'a public parent does not expose private or mutual-only Wanna events to a one-way follower');

select set_config('request.jwt.claim.sub','user_rec531_feed_actor',true);
select public.delete_own_check_in('53120000-0000-0000-0000-000000000002');
select set_config('request.jwt.claim.sub','user_rec531_feed_viewer',true);
select is(public.followed_feed(false)->'activity',public.followed_feed()->'activity',
  'deleted explicit visits preserve legacy visibility parity');
select ok(not exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'=(select id::text from rec531_feed_fixture_events where visit_id='53120000-0000-0000-0000-000000000002')),
  'deleted explicit visit disappears from activity-only');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'=(select id::text from rec531_feed_fixture_events where visit_id='53120000-0000-0000-0000-000000000001')),
  'deleting one visit preserves another visit to the same place');
reset role;

update public.user_places set visibility='self' where id='53110000-0000-0000-0000-000000000004';
set local role authenticated;
select is(public.followed_feed(false)->'activity',public.followed_feed()->'activity',
  'source-place privacy changes preserve exact legacy parity');
select ok(not exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->'place'->>'user_place_id'='53110000-0000-0000-0000-000000000004'),
  'making a source private removes its visits, Wanna events, and public-list item activity');
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'event_type'='list_created' and item->'list'->>'id'='53130000-0000-0000-0000-000000000001'),
  'private source places do not suppress the independently visible list creation');
reset role;
update public.user_places set visibility='followers' where id='53110000-0000-0000-0000-000000000004';
update public.place_lists set visibility='stealth' where id='53130000-0000-0000-0000-000000000001';
set local role authenticated;
select is(public.followed_feed(false)->'activity',public.followed_feed()->'activity',
  'stealth list visibility preserves exact legacy parity');
select ok(not exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->'list'->>'id'='53130000-0000-0000-0000-000000000001'),
  'stealth lists exclude both list-created and list-item activity');
reset role;
update public.place_lists set visibility='followers' where id='53130000-0000-0000-0000-000000000001';
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_rec531_feed_actor','user_rec531_feed_viewer','profile');
set local role authenticated;
select ok(exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'='53150000-0000-0000-0000-000000000003'),
  'mutual Wanna becomes visible when the follow relationship is mutual');
reset role;
delete from public.follows where follower_user_id='user_rec531_feed_actor' and followed_user_id='user_rec531_feed_viewer';
set local role authenticated;
select ok(not exists(select 1 from jsonb_array_elements(public.followed_feed(false)->'activity') item
  where item->>'id'='53150000-0000-0000-0000-000000000003'),
  'mutual Wanna disappears when the reverse follow is removed');
select ok(not exists(select 1 from (values ('bad-cursor'),('bad-time|bad-id'),('2026-09-17T12:00:00Z|bad-id')) cursors(value)
  where public.followed_feed(false,cursors.value,25)-'featured_places'
    is distinct from public.followed_feed(cursors.value,25)-'featured_places'),
  'malformed cursor variants retain legacy first-page behavior');
select ok(not exists(select 1 from (values (null::integer),(-1),(0),(100)) limits(value)
  where public.followed_feed(false,null,limits.value)-'featured_places'
    is distinct from public.followed_feed(null,limits.value)-'featured_places'),
  'null, nonpositive, and excessive limits retain legacy bounds');
reset role;

select set_config('request.jwt.claim.sub','user_rec531_feed_stranger',true);
select is(jsonb_array_length(public.followed_feed(false)->'activity'),0,'non-follower receives no activity');
select set_config('request.jwt.claim.sub','user_rec531_feed_viewer',true);
insert into public.blocks(blocker_user_id,blocked_user_id) values ('user_rec531_feed_actor','user_rec531_feed_viewer');
select is(jsonb_array_length(public.followed_feed(false)->'activity'),0,'actor blocking viewer removes activity');
delete from public.blocks where blocker_user_id='user_rec531_feed_actor' and blocked_user_id='user_rec531_feed_viewer';
update public.profiles set is_private_profile=true where id='user_rec531_feed_actor';
select is(jsonb_array_length(public.followed_feed(false)->'activity'),0,'private profiles remain excluded');
update public.profiles set is_private_profile=false,deleted_at=now() where id='user_rec531_feed_actor';
select is(jsonb_array_length(public.followed_feed(false)->'activity'),0,'deleted actors remain excluded');
select set_config('request.jwt.claim.sub','',true);
select is(jsonb_array_length(app.followed_feed(false)->'activity'),0,'missing identity returns no activity');

do $strict_pgtap$
declare diagnostics text;
begin
  select string_agg(result.message, E'\n') into diagnostics from finish() as result(message);
  if diagnostics is not null then raise exception '%', diagnostics; end if;
end;
$strict_pgtap$;
rollback;
