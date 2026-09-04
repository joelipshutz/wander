begin;

create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(17);

select ok((select not public and file_size_limit = 1048576 from storage.buckets where id = 'list-snapshots'), 'snapshot bucket is private and bounded');
select ok((select prosecdef and 'search_path=public, app' = any(proconfig) from pg_proc where oid = 'app.set_place_list_snapshot_cover(uuid)'::regprocedure), 'owner mutation has explicit definer posture and search path');
select ok((select not prosecdef and 'search_path=public, app' = any(proconfig) from pg_proc where oid = 'public.set_place_list_snapshot_cover(uuid)'::regprocedure), 'public wrapper is invoker with pinned search path');
select ok(not has_function_privilege('anon', 'public.set_place_list_snapshot_cover(uuid)', 'execute'), 'anonymous wrapper access denied');
select ok(not has_function_privilege('anon', 'app.set_place_list_snapshot_cover(uuid)', 'execute'), 'anonymous app function access denied');
select ok(has_function_privilege('authenticated', 'public.set_place_list_snapshot_cover(uuid)', 'execute') and has_function_privilege('authenticated', 'app.set_place_list_snapshot_cover(uuid)', 'execute'), 'authenticated wrapper and implementation grants exist');

insert into public.profiles (id, handle, display_name) values
 ('user_snapshot_smoke_owner', 'snapshot_smoke_owner', 'Snapshot Owner'),
 ('user_snapshot_smoke_collab', 'snapshot_smoke_collab', 'Snapshot Collaborator'),
 ('user_snapshot_smoke_stranger', 'snapshot_smoke_stranger', 'Snapshot Stranger');
insert into public.place_lists(id, owner_user_id, name, description, visibility) values
 ('41300000-0000-4000-8000-000000000001', 'user_snapshot_smoke_owner', 'Snapshot smoke', '', 'stealth');
insert into public.place_list_members(list_id, user_id, role) values
 ('41300000-0000-4000-8000-000000000001', 'user_snapshot_smoke_collab', 'collaborator');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok($$select public.set_place_list_snapshot_cover('41300000-0000-4000-8000-000000000001')$$, 'P0001', 'place_list_snapshot_not_found_or_forbidden', 'missing upload cannot become cover');
-- Storage metadata fixtures never leave this rolled-back transaction.
select lives_ok($$insert into storage.objects(bucket_id, name) values ('list-snapshots', '41300000-0000-4000-8000-000000000001/snapshot.jpg')$$, 'owner uploads snapshot');
select lives_ok($$select public.set_place_list_snapshot_cover('41300000-0000-4000-8000-000000000001')$$, 'owner attaches snapshot');
select is(public.place_list_detail('41300000-0000-4000-8000-000000000001')->'list'->>'snapshot_cover_path', '41300000-0000-4000-8000-000000000001/snapshot.jpg', 'detail returns durable cover reference');
select lives_ok($$update storage.objects set metadata = '{}'::jsonb where bucket_id = 'list-snapshots' and name = '41300000-0000-4000-8000-000000000001/snapshot.jpg'$$, 'owner retry can update object');

select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_collab', true);
select is((select count(*)::integer from storage.objects where bucket_id='list-snapshots' and name='41300000-0000-4000-8000-000000000001/snapshot.jpg'), 1, 'collaborator reads private cover');
select throws_ok($$select public.set_place_list_snapshot_cover('41300000-0000-4000-8000-000000000001')$$, 'P0001', 'place_list_snapshot_not_found_or_forbidden', 'collaborator cannot replace owner cover');
with changed as (update storage.objects set metadata='{}'::jsonb where bucket_id='list-snapshots' and name='41300000-0000-4000-8000-000000000001/snapshot.jpg' returning id) select is(count(*)::integer, 0, 'collaborator cannot overwrite object') from changed;

select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_stranger', true);
select is((select count(*)::integer from storage.objects where bucket_id='list-snapshots' and name='41300000-0000-4000-8000-000000000001/snapshot.jpg'), 0, 'stranger cannot read cover');
select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
select public.set_place_list_collaborators('41300000-0000-4000-8000-000000000001', '{}'::text[]);
select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_collab', true);
select is((select count(*)::integer from storage.objects where bucket_id='list-snapshots' and name='41300000-0000-4000-8000-000000000001/snapshot.jpg'), 0, 'removed collaborator loses cover access');
select set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
select public.delete_place_list('41300000-0000-4000-8000-000000000001');
select is((select count(*)::integer from storage.objects where bucket_id='list-snapshots' and name='41300000-0000-4000-8000-000000000001/snapshot.jpg'), 0, 'deleted list cover is inaccessible');
reset role;
select * from finish();
rollback;
