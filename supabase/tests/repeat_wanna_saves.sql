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
begin
  if not (select relrowsecurity from pg_class where oid = 'public.place_wanna_saves'::regclass) then
    raise exception 'Wanna table RLS must be enabled';
  end if;
  if has_table_privilege('authenticated', 'public.place_wanna_saves', 'insert') then
    raise exception 'Wanna writes must pass through owner RPC';
  end if;
  if exists (select 1 from pg_proc where oid in
      ('public.save_own_place_wanna(uuid,jsonb)'::regprocedure, 'public.visible_place_wannas(uuid[])'::regprocedure)
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
  perform public.delete_own_user_place(parent_id);
  select count(*) into row_count from public.visible_place_wannas(array[parent_id]);
  if row_count <> 0 then raise exception 'Deleted place still exposes Wanna'; end if;
  reset role;
end;
$test$;
select 'repeat Wanna RPC, idempotency, parent state, Feed snapshots, visibility, blocks, deletion, and grants passed' as result;
rollback;
