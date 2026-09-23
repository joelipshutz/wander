begin;
savepoint rec590_private_list;

-- Exercise the exact self-only/manual save path used for a new stealth-list
-- companion. No migration is needed for this regression; all fixtures roll back.
do $test$
declare
  owner_id text := 'user_codex_private_list_owner';
  follower_id text := 'user_codex_private_list_follower';
  provider_id text := 'rec590-private-list-' || gen_random_uuid()::text;
  list_id uuid := gen_random_uuid();
  parent_id uuid;
  place_id uuid;
  event_ids uuid[];
  event_id uuid;
  saved jsonb;
  feed jsonb;
begin
  insert into public.profiles(id, handle, display_name, default_visibility, is_private_profile)
    values (owner_id, 'codex_private_list_owner', 'Smoke Owner', 'followers', false),
           (follower_id, 'codex_private_list_follower', 'Smoke Follower', 'followers', false);
  insert into public.follows(follower_user_id, followed_user_id, source)
    values (follower_id, owner_id, 'username');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', owner_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', owner_id, true);
  set local role authenticated;
  saved := public.save_own_place(
    jsonb_build_object('canonical_name', 'Private List Smoke', 'category', 'coffee_tea_sweets',
      'primary_category', 'coffee_tea_sweets', 'latitude', 0, 'longitude', 0,
      'source_provider', 'codex_smoke', 'source_provider_place_id', provider_id, 'confidence', 1),
    '{"status":"wanna_go","visibility":"self","source_type":"manual","nearby_confirmed":false}'::jsonb,
    '[]'::jsonb
  );
  parent_id := (saved->>'user_place_id')::uuid;
  place_id := (saved->>'place_id')::uuid;
  if parent_id is null or place_id is null then raise exception 'private companion save failed'; end if;
  reset role;

  if (select visibility from public.user_places where id = parent_id) <> 'self' then
    raise exception 'private companion widened the initial save audience';
  end if;
  insert into public.place_lists(id, owner_user_id, name, visibility)
    values (list_id, owner_id, 'Private smoke list', 'stealth');
  insert into public.place_list_items(list_id, place_id, owner_user_place_id, source_user_place_id, added_by_user_id)
    values (list_id, place_id, parent_id, parent_id, owner_id);
  select array_agg(id) into event_ids from public.feed_events where user_place_id = parent_id;
  if coalesce(array_length(event_ids, 1), 0) = 0 then raise exception 'fixture did not exercise any activity'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', follower_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', follower_id, true);
  set local role authenticated;
  if exists (select 1 from public.user_places where id = parent_id)
    or exists (select 1 from public.visible_place_wannas(array[parent_id])) then
    raise exception 'private companion is readable by a follower';
  end if;
  foreach event_id in array event_ids loop
    begin
      perform public.activity_detail(event_id);
      raise exception 'private companion can be opened by activity link';
    exception when raise_exception then
      if sqlerrm <> 'activity_not_visible' then raise; end if;
    end;
  end loop;
  feed := public.followed_feed(false, null, 50);
  if exists (select 1 from jsonb_array_elements(feed->'activity') item
             where (item->>'id')::uuid = any(event_ids)) then
    raise exception 'private companion leaked to the followed Feed';
  end if;
  reset role;
end
$test$;

rollback to savepoint rec590_private_list;
release savepoint rec590_private_list;
rollback;
