begin;
create extension if not exists pgtap;
select no_plan();

select has_table('public', 'activity_comment_likes', 'comment likes have a separate table');
select ok((select relrowsecurity from pg_class where oid = 'public.activity_comment_likes'::regclass), 'comment likes enforce RLS');
select ok(not has_table_privilege('authenticated', 'public.activity_comment_likes', 'select,insert,update,delete'), 'clients cannot access comment like rows directly');
select ok(not has_table_privilege('anon', 'public.activity_comment_likes', 'select,insert,update,delete'), 'anonymous cannot access comment like rows');
select has_pk('public', 'activity_comment_likes', 'unique comment/user primary key');
select ok(p.prosecdef, signature || ' explicitly uses security definer')
from (values ('public.set_activity_comment_like(uuid,boolean)'), ('public.activity_comments(uuid,text,integer)'), ('app.activity_comment_likes_json(text,uuid)')) f(signature)
join pg_proc p on p.oid = f.signature::regprocedure;
select ok('search_path=pg_catalog, public, app' = any(p.proconfig), signature || ' pins search_path')
from (values ('public.set_activity_comment_like(uuid,boolean)'), ('public.activity_comments(uuid,text,integer)'), ('app.activity_comment_likes_json(text,uuid)')) f(signature)
join pg_proc p on p.oid = f.signature::regprocedure;
select is((select provolatile::text from pg_proc where oid='public.set_activity_comment_like(uuid,boolean)'::regprocedure), 'v', 'write RPC remains volatile');
select is((select provolatile::text from pg_proc where oid='public.activity_comments(uuid,text,integer)'::regprocedure), 's', 'comments RPC remains stable');
select is((select prorettype::regtype::text from pg_proc where oid='public.activity_comments(uuid,text,integer)'::regprocedure), 'jsonb', 'comments return type preserved');
select ok(has_function_privilege('authenticated','public.set_activity_comment_like(uuid,boolean)','execute'), 'authenticated may call like RPC');
select ok(not has_function_privilege('anon','public.set_activity_comment_like(uuid,boolean)','execute'), 'anonymous may not call like RPC');
select ok(not has_function_privilege('authenticated','app.activity_comment_likes_json(text,uuid)','execute'), 'internal helper cannot impersonate a viewer');
select ok(not has_function_privilege('anon','public.activity_comments(uuid,text,integer)','execute'), 'anonymous comments grant remains denied');

insert into public.profiles(id,handle,display_name,is_private_profile) values
('comment_like_owner','commentlikeowner','Comment Like Owner',false),
('comment_like_viewer','commentlikeviewer','Comment Like Viewer',false),
('comment_like_author','commentlikeauthor','Comment Like Author',false),
('comment_like_stranger','commentlikestranger','Comment Like Stranger',false);
insert into public.follows(follower_user_id,followed_user_id,source) values
('comment_like_viewer','comment_like_owner','profile'),
('comment_like_author','comment_like_owner','profile');
insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
values ('a5640000-0000-0000-0000-000000000001','Comment Like Fixture','coffee',34,-118,'mapkit','rec564-smoke');
insert into public.user_places(id,user_id,place_id,status,visibility,source_type)
values ('a5640000-0000-0000-0000-000000000002','comment_like_owner','a5640000-0000-0000-0000-000000000001','wanna_go','followers','manual');
create temp table comment_like_fixture(activity_id uuid, comment_id uuid);
insert into comment_like_fixture(activity_id) select id from public.feed_events where user_place_id='a5640000-0000-0000-0000-000000000002' limit 1;
select set_config('request.jwt.claim.sub','comment_like_author',true);
select set_config('request.jwt.claims','{"sub":"comment_like_author","role":"authenticated"}',true);
update comment_like_fixture set comment_id=(public.add_activity_comment(activity_id,'A test comment')->'comment'->>'id')::uuid;
grant select on comment_like_fixture to authenticated, anon;

select set_config('request.jwt.claim.sub','comment_like_viewer',true);
select set_config('request.jwt.claims','{"sub":"comment_like_viewer","role":"authenticated"}',true);
set local role authenticated;
select is((public.set_activity_comment_like(comment_id,true)->>'like_count')::integer,1,'first like counts once') from comment_like_fixture;
select is((public.set_activity_comment_like(comment_id,true)->>'like_count')::integer,1,'duplicate desired-state write is idempotent') from comment_like_fixture;
select is((public.activity_comments(activity_id)->'comments'->0->>'like_count')::integer,1,'reload retains count') from comment_like_fixture;
select is((public.activity_comments(activity_id)->'comments'->0->>'viewer_has_liked')::boolean,true,'reload retains viewer state') from comment_like_fixture;
select is((public.activity_engagement_summaries(array[activity_id])->0->>'like_count')::integer,0,'comment likes do not alter activity likes') from comment_like_fixture;
select throws_ok($$select public.set_activity_comment_like('a5640000-0000-0000-0000-999999999999',true)$$,'P0001','comment_not_visible','missing comment denied');
select throws_ok($$select public.set_activity_comment_like(comment_id,null) from comment_like_fixture$$,'P0001','like_state_required','null desired state rejected');

reset role;
select set_config('request.jwt.claim.sub','comment_like_author',true);
select set_config('request.jwt.claims','{"sub":"comment_like_author","role":"authenticated"}',true);
set local role authenticated;
select is((public.activity_comments(activity_id)->'comments'->0->>'viewer_has_liked')::boolean,false,'another account has its own state') from comment_like_fixture;
select is((public.set_activity_comment_like(comment_id,true)->>'like_count')::integer,2,'author may like own comment; another account adds one') from comment_like_fixture;
select is((public.set_activity_comment_like(comment_id,false)->>'like_count')::integer,1,'unlike removes only current user') from comment_like_fixture;
select is((public.set_activity_comment_like(comment_id,false)->>'like_count')::integer,1,'duplicate unlike preserves other likes') from comment_like_fixture;

reset role;
insert into public.blocks(blocker_user_id,blocked_user_id) values ('comment_like_author','comment_like_viewer');
select set_config('request.jwt.claim.sub','comment_like_author',true);
select is((public.activity_comments(activity_id)->'comments'->0->>'like_count')::integer,0,'blocked liker is omitted from count') from comment_like_fixture;
select set_config('request.jwt.claim.sub','comment_like_viewer',true);
select set_config('request.jwt.claims','{"sub":"comment_like_viewer","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','blocked comment author denies like');
select is(jsonb_array_length(public.activity_comments(activity_id)->'comments'),0,'blocked author comment is hidden') from comment_like_fixture;
reset role;
delete from public.blocks where blocker_user_id='comment_like_author' and blocked_user_id='comment_like_viewer';
insert into public.blocks(blocker_user_id,blocked_user_id) values ('comment_like_owner','comment_like_viewer');
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,false) from comment_like_fixture$$,'P0001','comment_not_visible','blocked activity denies unlike too');
reset role;
delete from public.blocks where blocker_user_id='comment_like_owner' and blocked_user_id='comment_like_viewer';

select set_config('request.jwt.claim.sub','comment_like_stranger',true);
select set_config('request.jwt.claims','{"sub":"comment_like_stranger","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','stranger cannot like followers activity');
reset role;
select set_config('request.jwt.claim.sub','comment_like_viewer',true);
select set_config('request.jwt.claims','{"sub":"comment_like_viewer","role":"authenticated"}',true);
update public.user_places set visibility='self' where id='a5640000-0000-0000-0000-000000000002';
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','changed activity visibility rechecked');
reset role;
update public.user_places set visibility='followers' where id='a5640000-0000-0000-0000-000000000002';
update public.profiles set deleted_at=now() where id='comment_like_author';
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','deleted comment author denied');
reset role;
update public.profiles set deleted_at=null where id='comment_like_author';
update public.user_places set deleted_at=now() where id='a5640000-0000-0000-0000-000000000002';
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','deleted source activity denied');
reset role;
update public.user_places set deleted_at=null where id='a5640000-0000-0000-0000-000000000002';
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','not_authenticated','missing identity denied');
reset role;
set local role anon;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'42501',null,'anonymous role cannot execute');
reset role;
select is((select count(*)::integer from public.activity_comment_likes where comment_id=(select comment_id from comment_like_fixture)),1,'denied writes never altered existing likes');
delete from public.activity_comments where id=(select comment_id from comment_like_fixture);
select is((select count(*)::integer from public.activity_comment_likes where comment_id=(select comment_id from comment_like_fixture)),0,'deleting comment cascades likes');
select set_config('request.jwt.claim.sub','comment_like_viewer',true);
select set_config('request.jwt.claims','{"sub":"comment_like_viewer","role":"authenticated"}',true);
set local role authenticated;
select throws_ok($$select public.set_activity_comment_like(comment_id,true) from comment_like_fixture$$,'P0001','comment_not_visible','deleted comment cannot be liked again');
reset role;
select * from finish();
rollback;
