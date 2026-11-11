-- Reserved synthetic fixtures. The smoke runner owns the surrounding rollback.
insert into public.profiles(id, handle, display_name, default_visibility, is_private_profile, deleted_at)
values ('user_codex_supabase_smoke', 'codex_smoke', 'Codex Smoke Test', 'followers', false, null),
 ('user_codex_supabase_smoke_collab', 'codex_smoke_collab', 'Codex Smoke Collaborator', 'followers', false, null),
 ('user_codex_supabase_smoke_stranger', 'codex_smoke_stranger', 'Codex Smoke Stranger', 'followers', false, null)
on conflict(id) do update set deleted_at = null;

insert into public.places(id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id)
select ('68700000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
 'Snapshot fixture ' || n, 'coffee_tea_sweets', 34, -118, 'codex_smoke', 'snapshot-fixture-' || n
from generate_series(1, 9) n;
insert into public.user_places(id, user_id, place_id, status, visibility, source_type)
select ('68710000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
 case when n = 9 then 'user_codex_supabase_smoke_stranger' else 'user_codex_supabase_smoke' end,
 ('68700000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
 'wanna_go', 'followers', 'manual' from generate_series(1, 9) n;

create function pg_temp.snapshot_assert(condition boolean, message text)
returns void language plpgsql as $$ begin
 if condition is distinct from true then raise exception 'Snapshot regression: %', message; end if;
end $$;
select pg_temp.snapshot_assert(
 (select prosecdef and provolatile = 'v' and 'search_path=pg_catalog, public, app' = any(proconfig)
 from pg_proc where oid = 'app.create_map_snapshot_list(uuid,jsonb,uuid[])'::regprocedure)
 and (select not prosecdef and provolatile = 'v' and 'search_path=pg_catalog, public, app' = any(proconfig)
 from pg_proc where oid = 'public.create_map_snapshot_list(uuid,jsonb,uuid[])'::regprocedure)
 and has_function_privilege('authenticated', 'public.create_map_snapshot_list(uuid,jsonb,uuid[])', 'execute')
 and has_function_privilege('authenticated', 'app.create_map_snapshot_list(uuid,jsonb,uuid[])', 'execute')
 and not has_function_privilege('anon', 'public.create_map_snapshot_list(uuid,jsonb,uuid[])', 'execute')
 and not has_function_privilege('anon', 'app.create_map_snapshot_list(uuid,jsonb,uuid[])', 'execute'), 'RPC security metadata');
select pg_temp.snapshot_assert(
 (select prosecdef and provolatile = 'v' and 'search_path=public, app' = any(proconfig)
 from pg_proc where oid = 'app.record_place_list_item_feed_event()'::regprocedure)
 and not has_function_privilege('authenticated', 'app.record_place_list_item_feed_event()', 'execute')
 and not has_function_privilege('authenticated', 'app.feed_list_projection(uuid)', 'execute'), 'private helper security');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_map_snapshot_list('68720000-0000-4000-8000-000000000001', '{"name":"Snapshot fixture","visibility":"stealth"}',
 array(select ('68710000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid from generate_series(1,7) n));
-- Lost response/restart retries, including duplicate source ids, do not reseed.
select public.create_map_snapshot_list('68720000-0000-4000-8000-000000000001', '{"name":"Renamed snapshot","visibility":"stealth"}',
 array['68710000-0000-4000-8000-000000000001'::uuid,'68710000-0000-4000-8000-000000000001'::uuid]);
reset role;
select pg_temp.snapshot_assert((select count(*) = 1 from public.feed_events where list_id = '68720000-0000-4000-8000-000000000001'), 'seven initial places produce one event');
select pg_temp.snapshot_assert((select count(*) = 7 from public.place_list_items where list_id = '68720000-0000-4000-8000-000000000001' and deleted_at is null), 'retry preserves initial membership');
select pg_temp.snapshot_assert((select name = 'Renamed snapshot' and visibility = 'stealth' from public.place_lists where id = '68720000-0000-4000-8000-000000000001'), 'retry metadata and privacy');
select pg_temp.snapshot_assert((select count(*) = 8 from public.user_places where user_id = 'user_codex_supabase_smoke' and id::text like '68710000%' and status = 'wanna_go'), 'source saves unchanged');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
select public.add_place_list_item('68720000-0000-4000-8000-000000000001', '68700000-0000-4000-8000-000000000008', '68710000-0000-4000-8000-000000000008', null);
-- Retry an initial item via the ordinary outbox path: no second event.
select public.add_place_list_item('68720000-0000-4000-8000-000000000001', '68700000-0000-4000-8000-000000000001', '68710000-0000-4000-8000-000000000001', null);
insert into storage.objects(bucket_id, name) values ('list-snapshots', '68720000-0000-4000-8000-000000000001/snapshot.jpg');
select public.set_place_list_snapshot_cover('68720000-0000-4000-8000-000000000001');
reset role;
select pg_temp.snapshot_assert((select count(*) = 2 from public.feed_events where list_id = '68720000-0000-4000-8000-000000000001'), 'later addition emits exactly one ordinary event');
select pg_temp.snapshot_assert(app.feed_list_projection('68720000-0000-4000-8000-000000000001')->>'snapshot_cover_path' = '68720000-0000-4000-8000-000000000001/snapshot.jpg', 'feed exposes authorized cover reference');
select pg_temp.snapshot_assert(not app.can_read_place_list('68720000-0000-4000-8000-000000000001', 'user_codex_supabase_smoke_stranger'), 'stealth remains private');

-- Failed ownership validation rolls back the list and its creation event.
set local role authenticated;
do $$ begin
 begin
  perform public.create_map_snapshot_list('68720000-0000-4000-8000-000000000002', '{"name":"Invalid fixture"}', array['68710000-0000-4000-8000-000000000009'::uuid]);
  raise exception 'Foreign source unexpectedly accepted';
 exception when raise_exception then
  if sqlerrm <> 'snapshot_source_not_owned' then raise; end if;
 end;
end $$;
reset role;
select pg_temp.snapshot_assert(not exists(select 1 from public.place_lists where id = '68720000-0000-4000-8000-000000000002'), 'invalid batch leaves no partial list');

insert into public.place_list_members(list_id, user_id, role)
values ('68720000-0000-4000-8000-000000000001', 'user_codex_supabase_smoke_collab', 'collaborator');
select pg_temp.snapshot_assert(app.can_read_place_list('68720000-0000-4000-8000-000000000001', 'user_codex_supabase_smoke_collab'), 'collaborator keeps list access');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
do $$ begin
 begin
  perform public.create_map_snapshot_list('68720000-0000-4000-8000-000000000001', '{"name":"Stolen capture"}', '{}'::uuid[]);
  raise exception 'Collaborator unexpectedly changed capture';
 exception when raise_exception then
  if sqlerrm <> 'place_list_not_found_or_forbidden' then raise; end if;
 end;
end $$;
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
select public.delete_place_list('68720000-0000-4000-8000-000000000001');
do $$ begin
 begin
  perform public.create_map_snapshot_list('68720000-0000-4000-8000-000000000001', '{"name":"Deleted capture retry"}', '{}'::uuid[]);
  raise exception 'Deleted capture unexpectedly resurrected';
 exception when raise_exception then
  if sqlerrm <> 'place_list_not_found_or_forbidden' then raise; end if;
 end;
end $$;
reset role;
select pg_temp.snapshot_assert(not app.can_read_place_list('68720000-0000-4000-8000-000000000001', 'user_codex_supabase_smoke_collab'), 'deleted snapshot stays hidden');
select pg_temp.snapshot_assert(app.feed_list_projection('68720000-0000-4000-8000-000000000001') is null, 'deleted snapshot has no feed projection');
set local role anon;
do $$ begin
 begin
  perform public.create_map_snapshot_list('68720000-0000-4000-8000-000000000003', '{"name":"Anonymous capture"}', '{}'::uuid[]);
  raise exception 'Anonymous snapshot unexpectedly accepted';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
