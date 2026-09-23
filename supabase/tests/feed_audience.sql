begin;
create extension if not exists pgtap;
select plan(30);

select ok((select prosecdef and provolatile = 's' and prorettype = 'jsonb'::regtype
  from pg_proc where oid = 'app.activity_feed(text,text,integer)'::regprocedure),
  'projection preserves stable JSONB security-definer contract');
select ok((select prosecdef and provolatile = 's' from pg_proc
  where oid = 'public.activity_feed(text,text,integer)'::regprocedure), 'wrapper is stable security definer');
select ok((select 'search_path=public, app' = any(proconfig) from pg_proc
  where oid = 'app.activity_feed(text,text,integer)'::regprocedure), 'projection search path is pinned');
select ok((select 'search_path=app, public' = any(proconfig) from pg_proc
  where oid = 'public.activity_feed(text,text,integer)'::regprocedure), 'wrapper search path is pinned');
select ok(has_function_privilege('authenticated','public.activity_feed(text,text,integer)','execute'), 'authenticated RPC access');
select ok(not has_function_privilege('anon','public.activity_feed(text,text,integer)','execute'), 'no anonymous RPC access');
select ok(not has_function_privilege('authenticated','app.activity_feed(text,text,integer)','execute'), 'private helper is not directly callable');
select ok(not has_table_privilege('authenticated','public.feed_events','select'), 'raw events stay private');

insert into public.profiles(id, handle, display_name) values
('user_rec607_feed_viewer','rec607viewer','Audience viewer'),
('user_rec607_feed_friend','rec607friend','Audience friend'),
('user_rec607_feed_following','rec607following','Audience following'),
('user_rec607_feed_stranger','rec607stranger','Audience stranger');
delete from public.follows where follower_user_id like 'user_rec607_feed_%' and source = 'signup_default';
insert into public.follows(follower_user_id, followed_user_id, source) values
('user_rec607_feed_viewer','user_rec607_feed_friend','profile'),
('user_rec607_feed_friend','user_rec607_feed_viewer','profile'),
('user_rec607_feed_viewer','user_rec607_feed_following','profile');
insert into public.places(id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id)
select ('60700000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'Audience fixture ' || n, 'coffee', 0, 0, 'manual', 'rec607-' || n from generate_series(1,7) n;
insert into public.user_places(id, user_id, place_id, status, visibility, source_type, note)
select ('60710000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid, actor,
  ('60700000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'wanna_go', visibility, 'manual', 'Audience fixture ' || n
from (values
  (1,'user_rec607_feed_viewer','followers'),
  (2,'user_rec607_feed_viewer','self'),
  (3,'user_rec607_feed_friend','followers'),
  (4,'user_rec607_feed_friend','mutuals'),
  (5,'user_rec607_feed_following','followers'),
  (6,'user_rec607_feed_following','self'),
  (7,'user_rec607_feed_stranger','followers')
) fixtures(n,actor,visibility);
-- Own events are older than the first unfiltered page: filtering after LIMIT
-- would incorrectly report an empty Only Me feed.
update public.feed_events set occurred_at = case
  when actor_user_id = 'user_rec607_feed_viewer' then now() - interval '3 days'
  when actor_user_id = 'user_rec607_feed_friend' then now() - interval '2 days'
  else now() - interval '1 day' end
where actor_user_id like 'user_rec607_feed_%';

select set_config('request.jwt.claim.sub','user_rec607_feed_viewer',true);
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('everyone')->'activity'),5,'Everyone includes self and visible followed activity');
select is(jsonb_array_length(public.activity_feed('only_me')->'activity'),2,'Only Me includes self-only activity');
select is(jsonb_array_length(public.activity_feed('only_friends')->'activity'),2,'Only Friends includes mutual follows only');
select ok(not exists(select 1 from jsonb_array_elements(public.activity_feed('only_me')->'activity') e
  where e->'actor'->>'id' <> 'user_rec607_feed_viewer'), 'Only Me never returns another actor');
select ok(not exists(select 1 from jsonb_array_elements(public.activity_feed('only_friends')->'activity') e
  where e->'actor'->>'id' <> 'user_rec607_feed_friend'), 'Only Friends excludes self and one-way follows');
select is(public.activity_feed('only_me')->'activity'->0->'actor'->>'relationship','owner','own actor relationship');
select is(public.activity_feed('only_friends')->'activity'->0->'actor'->>'relationship','mutual','friend actor relationship');
select is(jsonb_array_length(public.activity_feed('only_me',null,1)->'activity'),1,'filter precedes page limit');
select ok(public.activity_feed('only_me',null,1)->>'next_cursor' is not null,'filtered page has a cursor');
select isnt(public.activity_feed('only_me',null,1)->'activity'->0->>'id',
  public.activity_feed('only_me',public.activity_feed('only_me',null,1)->>'next_cursor',1)->'activity'->0->>'id',
  'filtered cursor advances without duplicates');
select is(public.activity_feed('only_me',public.activity_feed('only_me',null,1)->>'next_cursor',1)->>'next_cursor',
  null::text,'final filtered page ends');
select is(jsonb_array_length(public.followed_feed(false)->'activity'),3,'older builds keep followed-only behavior');
select throws_ok($$select public.activity_feed('invalid')$$,'22023','Invalid feed audience','invalid audience rejected');
reset role;

update public.profiles set is_private_profile = true where id in ('user_rec607_feed_viewer','user_rec607_feed_friend');
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('only_me')->'activity'),2,'private account can still see its own activity');
select is(jsonb_array_length(public.activity_feed('only_friends')->'activity'),0,'private friend content remains excluded');
reset role;
update public.profiles set is_private_profile = false where id = 'user_rec607_feed_friend';
-- Going private changes existing saves to Self. Explicitly share these test
-- saves again before testing an ordinary reverse-edge unfollow.
update public.user_places set visibility = case
  when id = '60710000-0000-0000-0000-000000000003'::uuid then 'followers' else 'mutuals' end
where user_id = 'user_rec607_feed_friend';
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('only_friends')->'activity'),2,'reshared friend posts are visible before unfollow');
reset role;
delete from public.follows where follower_user_id = 'user_rec607_feed_friend' and followed_user_id = 'user_rec607_feed_viewer';
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('only_friends')->'activity'),0,'unfollow immediately removes friendship');
select is(jsonb_array_length(public.activity_feed('everyone')->'activity'),4,'Everyone still includes eligible one-way follow content');
reset role;
insert into public.blocks(blocker_user_id, blocked_user_id) values ('user_rec607_feed_viewer','user_rec607_feed_friend');
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('everyone')->'activity'),3,'blocked actor content is excluded');
reset role;
select set_config('request.jwt.claim.sub','user_rec607_feed_stranger',true);
set local role authenticated;
select is(jsonb_array_length(public.activity_feed('everyone')->'activity'),1,'stranger cannot read the first viewer feed');
select is(jsonb_array_length(public.activity_feed('only_friends')->'activity'),0,'no friends returns empty');
reset role;
set local role anon;
select throws_ok($$select public.activity_feed('everyone')$$,'42501',null,'anonymous execution denied');
reset role;

select * from finish();
rollback;
