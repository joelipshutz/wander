begin;
do $test$
declare
  owner_id text := 'user_codex_clip_owner';
  stranger_id text := 'user_codex_clip_stranger';
  venue jsonb := '{"canonical_name":"Clip Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec408-clip","confidence":1}';
  venue_id uuid;
  legacy_id uuid;
  event_count integer;
  first_save jsonb;
  repeated jsonb;
  saved public.user_places;
  before_row jsonb;
begin
  if exists (select 1 from pg_proc where oid = 'public.save_app_clip_place(uuid)'::regprocedure
      and (not prosecdef or provolatile <> 'v' or not ('search_path=pg_catalog, public, app' = any(proconfig))))
    or has_function_privilege('anon','public.save_app_clip_place(uuid)','execute')
    or not has_function_privilege('authenticated','public.save_app_clip_place(uuid)','execute')
    then raise exception 'Clip RPC security posture changed'; end if;
  insert into public.profiles(id,handle,display_name,is_private_profile,default_visibility)
    values(owner_id,'codex_clip_owner','Clip Owner',false,'self'),
          (stranger_id,'codex_clip_stranger','Clip Stranger',true,'followers');
  perform set_config('request.jwt.claim.sub',stranger_id,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
  set local role authenticated;
  first_save := public.save_own_place(venue,
    '{"status":"been","visibility":"self","note":"Keep existing note","source_type":"manual","nearby_confirmed":false}', '[]');
  venue_id := (first_save->>'place_id')::uuid;
  reset role;
  select to_jsonb(up) into before_row from public.user_places up where id = (first_save->>'user_place_id')::uuid;
  set local role authenticated;
  repeated := public.save_app_clip_place(venue_id);
  if repeated->>'created' <> 'false' then raise exception 'Existing visit was treated as a new save'; end if;
  reset role;
  if before_row is distinct from (select to_jsonb(up) from public.user_places up where id = (first_save->>'user_place_id')::uuid)
    then raise exception 'Clip changed an existing save'; end if;

  perform set_config('request.jwt.claim.sub',owner_id,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  first_save := public.save_app_clip_place(venue_id);
  repeated := public.save_app_clip_place(venue_id);
  if first_save->>'created' <> 'true' or repeated->>'created' <> 'false'
    or first_save->>'user_place_id' <> repeated->>'user_place_id' then raise exception 'Clip save is not idempotent'; end if;
  reset role;
  select * into saved from public.user_places where id = (first_save->>'user_place_id')::uuid;
  if saved.user_id <> owner_id or saved.status <> 'wanna_go' or saved.visibility <> 'self' or saved.note is not null
    then raise exception 'Clip did not preserve identity/default visibility boundaries'; end if;
  if (select count(*) from public.user_places where place_id = venue_id and user_id = owner_id) <> 1
    then raise exception 'Duplicate Clip save'; end if;

  -- A full-app edit to a Wanna must also survive a later Clip retry byte for byte.
  update public.user_places set note = 'Keep Wanna note', visibility = 'mutuals' where id = saved.id;
  select to_jsonb(up) into before_row from public.user_places up where id = saved.id;
  set local role authenticated;
  repeated := public.save_app_clip_place(venue_id);
  reset role;
  if before_row is distinct from (select to_jsonb(up) from public.user_places up where id = saved.id)
    then raise exception 'Clip retry overwrote Wanna edits'; end if;

  -- Soft-deleted snapshots can be saved again without reviving old content.
  select count(*) into event_count from public.feed_events where user_place_id = saved.id;
  update public.user_places set deleted_at = now(), planned_date = current_date + 1 where id = saved.id;
  set local role authenticated;
  repeated := public.save_app_clip_place(venue_id);
  reset role;
  select * into saved from public.user_places where id = (repeated->>'user_place_id')::uuid;
  if repeated->>'created' <> 'true' or saved.deleted_at is not null or saved.note is not null
    or saved.planned_date is not null or saved.visibility <> 'self'
    then raise exception 'Deleted save restore retained stale content'; end if;
  if (select count(*) from public.feed_events where user_place_id = saved.id) < event_count
    then raise exception 'Restore deleted event history'; end if;

  -- Provider-less canonical places must retain the exact shared UUID.
  insert into public.places(canonical_name, category, latitude, longitude, source_provider)
    values('Legacy Clip Smoke Place', 'coffee_tea_sweets', 0, 0, 'codex_smoke') returning id into legacy_id;
  perform set_config('request.jwt.claim.sub',stranger_id,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
  set local role authenticated;
  first_save := public.save_app_clip_place(legacy_id);
  reset role;
  select * into saved from public.user_places where id = (first_save->>'user_place_id')::uuid;
  if saved.place_id <> legacy_id or saved.user_id <> stranger_id or saved.visibility <> 'self'
    then raise exception 'Canonical ID or private-profile visibility was lost'; end if;

  set local role anon;
  begin
    perform public.save_app_clip_place(venue_id);
    raise exception 'anonymous write accepted';
  exception when insufficient_privilege then null;
  end;
  reset role;

  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  set local role authenticated;
  begin
    perform public.save_app_clip_place(venue_id);
    raise exception 'missing identity accepted';
  exception when raise_exception then
    if sqlerrm <> 'not_authenticated' then raise; end if;
  end;
  reset role;
end;
$test$;
rollback;
