-- Extension-free equivalent of the snapshot policy/RPC checks for hosted smoke.
-- Reserved fixtures and all behavior mutations are rolled back.
begin;
set local plpgsql.check_asserts = on;

do $snapshot_smoke$
declare
  list_id uuid := gen_random_uuid();
  object_path text;
  denied boolean;
  changed integer;
begin
  object_path := list_id::text || '/snapshot.jpg';
  assert (select not public and file_size_limit = 1048576 and allowed_mime_types = array['image/jpeg']
          from storage.buckets where id = 'list-snapshots'), 'bucket must be private JPEG storage capped at 1 MiB';
  assert (select prosecdef and 'search_path=public, app' = any(proconfig)
          from pg_proc where oid = 'app.set_place_list_snapshot_cover(uuid)'::regprocedure), 'owner RPC posture';
  assert (select not prosecdef and 'search_path=public, app' = any(proconfig)
          from pg_proc where oid = 'public.set_place_list_snapshot_cover(uuid)'::regprocedure), 'wrapper posture';
  assert not has_function_privilege('anon', 'app.set_place_list_snapshot_cover(uuid)', 'execute')
     and not has_function_privilege('anon', 'public.set_place_list_snapshot_cover(uuid)', 'execute'), 'anonymous grants';
  assert has_function_privilege('authenticated', 'app.set_place_list_snapshot_cover(uuid)', 'execute')
     and has_function_privilege('authenticated', 'public.set_place_list_snapshot_cover(uuid)', 'execute'), 'authenticated grants';

  insert into public.profiles (id, handle, display_name) values
    ('user_snapshot_smoke_owner', 'snapshot_smoke_owner', 'Snapshot Owner'),
    ('user_snapshot_smoke_collab', 'snapshot_smoke_collab', 'Snapshot Collaborator'),
    ('user_snapshot_smoke_stranger', 'snapshot_smoke_stranger', 'Snapshot Stranger');
  insert into public.place_lists(id, owner_user_id, name, description, visibility)
    values (list_id, 'user_snapshot_smoke_owner', 'Snapshot smoke', '', 'stealth');
  insert into public.place_list_members(list_id, user_id, role)
    values (list_id, 'user_snapshot_smoke_collab', 'collaborator');

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  denied := false;
  begin
    perform public.set_place_list_snapshot_cover(list_id);
  exception when raise_exception then
    denied := sqlerrm = 'place_list_snapshot_not_found_or_forbidden';
  end;
  assert denied, 'missing object must not attach';

  insert into storage.objects(bucket_id, name) values ('list-snapshots', object_path);
  perform public.set_place_list_snapshot_cover(list_id);
  assert public.place_list_detail(list_id)->'list'->>'snapshot_cover_path' = object_path, 'durable cover in detail';
  update storage.objects set metadata = '{}'::jsonb where bucket_id = 'list-snapshots' and name = object_path;
  get diagnostics changed = row_count;
  assert changed = 1, 'owner retry may update object';

  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_collab', true);
  assert (select count(*) = 1 from storage.objects where bucket_id = 'list-snapshots' and name = object_path), 'collaborator reads cover';
  denied := false;
  begin
    perform public.set_place_list_snapshot_cover(list_id);
  exception when raise_exception then
    denied := sqlerrm = 'place_list_snapshot_not_found_or_forbidden';
  end;
  assert denied, 'collaborator must not replace cover';
  update storage.objects set metadata = '{}'::jsonb where bucket_id = 'list-snapshots' and name = object_path;
  get diagnostics changed = row_count;
  assert changed = 0, 'collaborator must not overwrite object';

  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_stranger', true);
  assert (select count(*) = 0 from storage.objects where bucket_id = 'list-snapshots' and name = object_path), 'stranger must not read cover';
  denied := false;
  begin
    insert into storage.objects(bucket_id, name) values ('list-snapshots', object_path);
  exception when insufficient_privilege then denied := true;
  end;
  assert denied, 'stranger must not write owner cover';

  reset role;
  insert into public.blocks(blocker_user_id, blocked_user_id)
    values ('user_snapshot_smoke_owner', 'user_snapshot_smoke_collab');
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_collab', true);
  assert (select count(*) = 0 from storage.objects where bucket_id = 'list-snapshots' and name = object_path), 'blocked collaborator loses access';
  reset role;
  delete from public.blocks where blocker_user_id = 'user_snapshot_smoke_owner' and blocked_user_id = 'user_snapshot_smoke_collab';
  set local role authenticated;

  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
  perform public.set_place_list_collaborators(list_id, '{}'::text[]);
  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_collab', true);
  assert (select count(*) = 0 from storage.objects where bucket_id = 'list-snapshots' and name = object_path), 'removed collaborator loses access';
  perform set_config('request.jwt.claim.sub', 'user_snapshot_smoke_owner', true);
  perform public.delete_place_list(list_id);
  assert (select count(*) = 0 from storage.objects where bucket_id = 'list-snapshots' and name = object_path), 'deleted list loses access';
  reset role;
end;
$snapshot_smoke$;
select 'snapshot storage and RPC smoke passed' as result;
rollback;

