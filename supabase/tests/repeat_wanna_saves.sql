begin;

-- The same rollback-only behavioral test is used by the hosted smoke runner.
do $test$
declare
  owner_id text := 'user_codex_repeat_wanna_owner';
  follower_id text := 'user_codex_repeat_wanna_follower';
  stranger_id text := 'user_codex_repeat_wanna_stranger';
  place_payload jsonb := '{"canonical_name":"Repeat Wanna Smoke","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec497-repeat-wanna","confidence":1}';
  parent_id uuid;
  visit_id uuid := gen_random_uuid();
  event_id uuid := gen_random_uuid();
  private_event_id uuid := gen_random_uuid();
  payload jsonb;
  result jsonb;
  before_parent jsonb;
  after_parent jsonb;
  row_count integer;
  original_event_id uuid;
  original_date timestamptz;
  event_count integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.place_wanna_saves'::regclass) then
    raise exception 'Wanna table RLS must be enabled';
  end if;
  if has_table_privilege('authenticated', 'public.place_wanna_saves', 'insert') then
    raise exception 'Wanna writes must pass through owner RPC';
  end if;
  if exists (select 1 from pg_proc where oid in
      ('public.save_own_place_wanna(uuid,jsonb)'::regprocedure, 'public.visible_place_wannas(uuid[])'::regprocedure,
       'public.update_own_place_wanna(uuid,jsonb)'::regprocedure)
      and (not prosecdef or not ('search_path=pg_catalog, public, app' = any(proconfig))
           or has_function_privilege('anon', oid, 'execute')
           or not has_function_privilege('authenticated', oid, 'execute'))) then
    raise exception 'Wanna RPC security metadata changed';
  end if;
  insert into public.profiles(id, handle, display_name, is_private_profile)
    values(owner_id, 'codex_repeat_wanna_owner', 'Smoke Owner', false),
          (follower_id, 'codex_repeat_wanna_follower', 'Smoke Follower', false),
          (stranger_id, 'codex_repeat_wanna_stranger', 'Smoke Stranger', false);
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(follower_id, owner_id, 'username');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.save_own_place(place_payload,
    '{"status":"wanna_go","visibility":"followers","note":"First Wanna","source_type":"manual","nearby_confirmed":false}', '[]');
  parent_id := (result->>'user_place_id')::uuid;
  payload := jsonb_build_object('id', event_id, 'occurred_at', now(), 'note', 'Repeat before visit',
                               'visibility', 'followers', 'planned_date', '2026-10-01', 'attribute_answers', '[]'::jsonb);
  result := public.save_own_place_wanna(parent_id, payload);
  if result->>'planned_date' <> '2026-10-01' then raise exception 'Wanna calendar date changed'; end if;
  reset role;
  if (select status from public.user_places where id = parent_id) <> 'wanna_go' then
    raise exception 'Repeat Wanna changed Wanna-only status';
  end if;
  -- First repeat stays in history when a check-in subsequently wins.
  set local role authenticated;
  perform public.save_own_check_in(place_payload,
    jsonb_build_object('id', parent_id, 'status', 'been', 'visibility', 'followers',
                      'note', 'Actual check-in', 'rating_score', 4, 'source_type', 'manual', 'nearby_confirmed', false),
    '[]', jsonb_build_object('id', visit_id, 'visited_at', now(), 'note', 'Actual check-in',
                            'rating_score', 4, 'attribute_answers', '[]'::jsonb));
  reset role;
  select to_jsonb(up) into before_parent from public.user_places up where id = parent_id;
  event_id := gen_random_uuid();
  payload := payload || jsonb_build_object('id', event_id, 'note', 'Go back soon');
  set local role authenticated;
  perform public.save_own_place_wanna(parent_id, payload);
  perform public.save_own_place_wanna(parent_id, payload);
  perform public.save_own_place_wanna(parent_id, payload || jsonb_build_object('id', private_event_id, 'note', 'Private Wanna', 'visibility', 'self'));
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 3 then raise exception 'Owner history or retry deduplication failed: %', row_count; end if;
  result := public.activity_detail(event_id);
  if result->>'note' <> 'Go back soon' or result->>'event_type' <> 'place_want_to_go' then
    raise exception 'Feed event lost Wanna snapshot';
  end if;
  reset role;
  select to_jsonb(up) into after_parent from public.user_places up where id = parent_id;
  if before_parent is distinct from after_parent or after_parent->>'status' <> 'been' then
    raise exception 'Repeat Wanna changed check-in summary or counter input';
  end if;
  if (select count(*) from public.place_visits where user_place_id = parent_id and deleted_at is null) <> 1 then
    raise exception 'Repeat Wanna changed visits';
  end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', follower_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 2 then raise exception 'Follower event privacy failed'; end if;
  result := public.followed_feed(null, 50);
  if not exists (select 1 from jsonb_array_elements(result->'activity') item
                 where item->>'id' = event_id::text and item->>'note' = 'Go back soon') then
    raise exception 'Followed Feed lacks repeat Wanna';
  end if;
  if exists (select 1 from jsonb_array_elements(result->'activity') item where item->>'id' = private_event_id::text) then
    raise exception 'Private Wanna leaked to Feed';
  end if;
  begin
    perform public.save_own_place_wanna(parent_id, payload || jsonb_build_object('id', gen_random_uuid()));
    raise exception 'non-owner-write-allowed';
  exception when raise_exception then
    if sqlerrm <> 'invalid_user_place_identity' then raise; end if;
  end;
  reset role;
  insert into public.blocks(blocker_user_id, blocked_user_id) values(owner_id, follower_id);
  set local role authenticated;
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 0 then raise exception 'Blocked follower can read Wanna'; end if;
  reset role;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', stranger_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 0 then raise exception 'Stranger can read Wanna'; end if;
  reset role;
  perform set_config('request.jwt.claims', '{}', true);
  set local role anon;
  begin
    perform public.visible_place_wannas(array[parent_id]);
    raise exception 'anonymous-read-allowed';
  exception when insufficient_privilege then null;
  end;
  reset role;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  reset role;
  delete from public.blocks where blocker_user_id = owner_id and blocked_user_id = follower_id;
  select count(*) into event_count from public.feed_events where user_place_id = parent_id;
  select id, occurred_at into original_event_id, original_date from public.feed_events
    where user_place_id = parent_id and event_type = 'place_want_to_go'
      and not exists(select 1 from public.place_wanna_saves w where w.id = feed_events.id)
    order by occurred_at, id limit 1;
  set local role authenticated;
  payload := payload || jsonb_build_object('edited_at', now(), 'note', 'Edited repeat', 'planned_date', '2026-11-01');
  result := public.update_own_place_wanna(parent_id, payload);
  if result->>'id' <> event_id::text or result->>'note' <> 'Edited repeat'
    or result->>'planned_date' <> '2026-11-01' then raise exception 'Targeted edit failed'; end if;
  perform public.update_own_place_wanna(parent_id, payload || jsonb_build_object('edited_at', now() - interval '1 minute', 'note', 'Stale retry'));
  result := public.activity_detail(event_id);
  if result->>'note' <> 'Edited repeat' then raise exception 'Stale edit overwrote newer revision'; end if;
  result := public.update_own_place_wanna(parent_id, payload || jsonb_build_object(
    'id', gen_random_uuid(), 'is_historical_original', true, 'note', 'Edited original'));
  if result->>'id' <> original_event_id::text or (result->>'occurred_at')::timestamptz <> original_date then
    raise exception 'Historical edit changed original activity identity/date'; end if;
  perform public.update_own_place_wanna(parent_id, payload || jsonb_build_object(
    'id', gen_random_uuid(), 'is_historical_original', true, 'note', 'Duplicate original retry'));
  reset role;
  if (select count(*) from public.feed_events where user_place_id=parent_id) <> event_count then
    raise exception 'Editing appended Feed activity'; end if;
  if (select count(*) from public.place_wanna_saves where user_place_id=parent_id and is_historical_original) <> 1 then
    raise exception 'Original Wanna edit duplicated history'; end if;
  if (select note from public.place_wanna_saves where id=private_event_id) <> 'Private Wanna' then
    raise exception 'Edit changed another Wanna'; end if;
  if (select to_jsonb(up) from public.user_places up where id=parent_id) is distinct from before_parent then
    raise exception 'Edit changed check-in parent metadata'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', follower_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.activity_detail(event_id);
  if result->>'note' <> 'Edited repeat' then raise exception 'Follower cannot read updated Wanna'; end if;
  begin
    perform public.update_own_place_wanna(parent_id, payload);
    raise exception 'non-owner-edit-allowed';
  exception when raise_exception then
    if sqlerrm <> 'invalid_user_place_identity' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  -- Making the original Wanna private cannot broaden the check-in's visibility,
  -- but deleting the last check-in must restore that original's own privacy.
  perform public.update_own_place_wanna(parent_id, payload || jsonb_build_object(
    'id', original_event_id, 'is_historical_original', true, 'visibility', 'self',
    'note', 'Private edited original', 'planned_date', '2026-11-02',
    'edited_at', now() + interval '1 millisecond'));
  reset role;
  if has_column_privilege('authenticated', 'public.user_places', 'historical_want_note', 'select')
    or has_column_privilege('authenticated', 'public.user_places', 'historical_want_tags', 'select')
    or has_column_privilege('authenticated', 'public.user_places', 'historical_wanted_at', 'select') then
    raise exception 'Raw historical columns bypass event visibility'; end if;
  if (select to_jsonb(up) from public.user_places up where id=parent_id) is distinct from before_parent then
    raise exception 'Original privacy edit changed check-in parent'; end if;
  if exists (select 1 from pg_proc where oid='app.sync_user_place_after_place_visit_delete()'::regprocedure
    and (not prosecdef or provolatile <> 'v' or not ('search_path=public, app'=any(proconfig))
      or has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))) then
    raise exception 'Last-visit reconciliation security metadata changed'; end if;
  set local role authenticated;
  perform public.delete_own_check_in(visit_id);
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and deleted_at is null
    and status='wanna_go' and note='Private edited original' and visibility='self'
    and planned_date='2026-11-02' and saved_at=original_date and historical_wanted_at is null) then
    raise exception 'Last-check-in deletion failed to restore canonical original Wanna'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', follower_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if exists(select 1 from public.profile_visible_places(owner_id, null, null) where user_place_id=parent_id) then
    raise exception 'Restored private original leaked through profile projection'; end if;
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 0 then raise exception 'Restored private parent leaked event history'; end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.update_own_place_wanna(parent_id, payload || jsonb_build_object(
    'id', original_event_id, 'is_historical_original', true, 'visibility', 'self',
    'note', 'Edited after restoration', 'planned_date', '2026-11-03',
    'edited_at', now() + interval '2 milliseconds'));
  if result->>'note' <> 'Edited after restoration' then
    raise exception 'Original Wanna cannot be edited after last-check-in deletion'; end if;
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and status='wanna_go'
    and note='Edited after restoration' and visibility='self' and planned_date='2026-11-03') then
    raise exception 'Restored original projection did not follow its edited event'; end if;
  if (select count(*) from public.feed_events where user_place_id=parent_id) <> event_count then
    raise exception 'Restoration or subsequent edit appended duplicate activity'; end if;
  set local role authenticated;
  perform public.delete_own_user_place(parent_id);
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 0 then raise exception 'Deleted place still exposes Wanna'; end if;
  reset role;
end;
$test$;
select 'repeat Wanna create/edit, original history identity, stale retries, parent state, Feed snapshots, privacy, deletion, and grants passed' as result;
-- REC-540: owner-scoped removals, replacement ordering and stale creates.
do $remove_test$
declare
  owner_id text := 'user_codex_repeat_wanna_owner';
  stranger_id text := 'user_codex_repeat_wanna_stranger';
  place_payload jsonb := '{"canonical_name":"Import removal smoke","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec540-removal","confidence":1}';
  parent_id uuid;
  visit_id uuid := gen_random_uuid();
  other_visit_id uuid := gen_random_uuid();
  wanna_id uuid := gen_random_uuid();
  removal_id uuid := gen_random_uuid();
  list_id uuid := gen_random_uuid();
  payload jsonb;
  result jsonb;
begin
  if exists (select 1 from pg_proc where oid='public.delete_own_place_wanna(uuid,uuid,boolean)'::regprocedure
    and (not prosecdef or provolatile <> 'v' or not ('search_path=pg_catalog, public, app'=any(proconfig))
      or has_function_privilege('anon', oid, 'execute') or not has_function_privilege('authenticated', oid, 'execute'))) then
    raise exception 'Wanna deletion RPC security posture changed'; end if;
  if has_table_privilege('authenticated', 'app.deleted_place_wannas', 'insert')
    or not (select relrowsecurity from pg_class where oid='app.deleted_place_wannas'::regclass) then
    raise exception 'Deletion identities must stay private'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  result := public.save_own_place(place_payload,
    '{"status":"wanna_go","visibility":"self","note":"Remove original metadata","source_type":"manual","nearby_confirmed":false}', '[]');
  parent_id := (result->>'user_place_id')::uuid;
  perform public.save_own_check_in(place_payload,
    jsonb_build_object('id',parent_id,'status','been','visibility','self','source_type','manual','nearby_confirmed',false),
    '[]', jsonb_build_object('id',visit_id,'visited_at',now(),'note','Keep unrelated visit','attribute_answers','[]'::jsonb));
  perform public.delete_own_place_wanna(parent_id,removal_id,true);
  perform public.delete_own_place_wanna(parent_id,removal_id,true);
  reset role;
  if not exists(select 1 from public.place_visits where id=visit_id and deleted_at is null and note='Keep unrelated visit')
    or exists(select 1 from public.user_places where id=parent_id and (deleted_at is not null or historical_wanted_at is not null)) then
    raise exception 'Removing original Wanna erased an independent check-in or retained original metadata'; end if;
  payload := jsonb_build_object('id',wanna_id,'occurred_at',now(),'note','Replacement Wanna','visibility','self','attribute_answers','[]'::jsonb);
  set local role authenticated;
  perform public.save_own_place_wanna(parent_id,payload);
  perform public.save_own_check_in(place_payload,
    jsonb_build_object('id',parent_id,'status','been','visibility','self','source_type','manual','nearby_confirmed',false),
    '[]', jsonb_build_object('id',other_visit_id,'visited_at',now(),'note','Import check-in','attribute_answers','[]'::jsonb));
  perform public.delete_own_check_in(other_visit_id);
  reset role;
  if not exists(select 1 from public.place_visits where id=visit_id and deleted_at is null) then
    raise exception 'Import replacement erased another visit'; end if;
  -- Once the independent visit is removed, the replacement Wanna becomes the summary.
  set local role authenticated;
  perform public.delete_own_check_in(visit_id);
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and status='wanna_go'
    and deleted_at is null and note='Replacement Wanna') then
    raise exception 'Last visit failed to restore independent Wanna'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
  set local role authenticated;
  begin
    perform public.delete_own_place_wanna(parent_id,wanna_id,false);
    raise exception 'stranger-delete-allowed';
  exception when raise_exception then
    if sqlerrm <> 'invalid_user_place_identity' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  perform public.delete_own_place_wanna(parent_id,wanna_id,false);
  perform public.delete_own_place_wanna(parent_id,wanna_id,false);
  reset role;
  if exists(select 1 from public.feed_events where id=wanna_id)
    or exists(select 1 from public.user_places where id=parent_id and deleted_at is null) then
    raise exception 'Removed sole replacement Wanna left a ghost save'; end if;
  -- Reanimate the container as a new check-in, then deliver an old Wanna create.
  other_visit_id := gen_random_uuid();
  set local role authenticated;
  perform public.save_own_check_in(place_payload,
    jsonb_build_object('id',parent_id,'status','been','visibility','self','source_type','manual','nearby_confirmed',false),
    '[]', jsonb_build_object('id',other_visit_id,'visited_at',now(),'note','New check-in','attribute_answers','[]'::jsonb));
  begin
    perform public.save_own_place_wanna(parent_id,payload);
    raise exception 'deleted-wanna-recreated';
  exception when raise_exception then
    if sqlerrm <> 'wanna_deleted' then raise; end if;
  end;
  reset role;
  if not exists(select 1 from public.place_visits where id=other_visit_id and deleted_at is null) then
    raise exception 'Stale Wanna replay erased replacement check-in'; end if;
  insert into public.place_lists(id, owner_user_id, name, visibility) values(list_id, owner_id, 'Import keep list', 'stealth');
  insert into public.place_list_items(list_id, place_id, owner_user_place_id, source_user_place_id, added_by_user_id)
    select list_id, place_id, id, id, owner_id from public.user_places where id=parent_id;
  set local role authenticated;
  perform public.delete_own_check_in(other_visit_id);
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and deleted_at is null and status='wanna_go' and note is null)
    or not exists(select 1 from public.place_list_items where owner_user_place_id=parent_id and deleted_at is null) then
    raise exception 'Removing last check-in lost its list companion or retained visit metadata'; end if;
  set local role authenticated;
  perform public.delete_own_place_wanna(parent_id,gen_random_uuid(),true);
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and deleted_at is null and note is null) then
    raise exception 'Removing Wanna hid an active list membership'; end if;
  -- Offline deselect/reselect: the replacement event must be delivered before
  -- the old original and temporary-container deletions.
  place_payload := place_payload || '{"source_provider_place_id":"rec540-reselected"}'::jsonb;
  set local role authenticated;
  result := public.save_own_place(place_payload,
    '{"status":"wanna_go","visibility":"self","note":"Old original","source_type":"manual","nearby_confirmed":false}', '[]');
  parent_id := (result->>'user_place_id')::uuid;
  wanna_id := gen_random_uuid();
  payload := jsonb_build_object('id',wanna_id,'occurred_at',now(),'note','Reselected Wanna','visibility','self','attribute_answers','[]'::jsonb);
  perform public.save_own_place_wanna(parent_id,payload);
  perform public.delete_own_place_wanna(parent_id,gen_random_uuid(),true);
  perform public.delete_own_place_wanna(parent_id,gen_random_uuid(),true);
  reset role;
  if not exists(select 1 from public.user_places where id=parent_id and deleted_at is null and note='Reselected Wanna')
    or (select count(*) from public.feed_events where user_place_id=parent_id and event_type='place_want_to_go') <> 1 then
    raise exception 'Old removal erased or duplicated the reselected Wanna'; end if;
  set local role authenticated;
  perform public.delete_own_place_wanna(parent_id,wanna_id,false);
  reset role;
  if exists(select 1 from public.user_places where id=parent_id and deleted_at is null) then
    raise exception 'Temporary bookmark survived final Wanna removal'; end if;
end;
$remove_test$;
select 'import action removal, replacement, ownership, retry and security checks passed' as result;

rollback;
