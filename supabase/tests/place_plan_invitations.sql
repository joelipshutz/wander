begin;

-- Safe for the hosted smoke runner: all identities, storage metadata, and plans
-- are fixtures in this rolled-back transaction. No real image objects are sent.
do $test$
declare
  sender text := 'user_codex_plan_sender';
  recipient text := 'user_codex_plan_recipient';
  stranger text := 'user_codex_plan_stranger';
  venue jsonb := '{"canonical_name":"Plan Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec486-place-plan","confidence":1}';
  place_id uuid;
  image_path text := 'user_codex_plan_sender/11111111-2222-4333-8444-555555555555/preview.png';
  invite_token text;
  invitation_id uuid;
  result jsonb;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.place_plan_invitations'::regclass)
    or has_table_privilege('authenticated', 'public.place_plan_invitations', 'select')
    or has_table_privilege('anon', 'public.place_plan_invitations', 'select') then
    raise exception 'plan table must not be enumerable';
  end if;
  if exists (select 1 from pg_proc where oid in
      ('public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz)'::regprocedure,
       'public.place_plan_preview(text)'::regprocedure)
    and (not prosecdef or not ('search_path=public, app, extensions' = any(proconfig)))) then
    raise exception 'plan RPC security posture changed';
  end if;
  if has_function_privilege('anon', 'public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz)', 'execute')
    or not has_function_privilege('authenticated', 'public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz)', 'execute')
    or not has_function_privilege('anon', 'public.place_plan_preview(text)', 'execute') then
    raise exception 'plan RPC grants changed';
  end if;
  if exists (select 1 from pg_proc
    where oid = 'public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz)'::regprocedure
      and (provolatile <> 'v' or prorettype <> 'jsonb'::regtype
        or exists (select 1 from aclexplode(coalesce(proacl, acldefault('f', proowner)))
          where grantee = 0 and privilege_type = 'EXECUTE')))
  then raise exception 'create plan RPC volatility, result, or public grant changed'; end if;
  if has_function_privilege('anon', 'public.received_place_plan_invitations()', 'execute')
    or has_function_privilege('anon', 'public.open_received_place_plan_invitation(uuid)', 'execute')
    or has_function_privilege('authenticated', 'app.place_plan_payload(uuid)', 'execute')
    or has_function_privilege('anon', 'app.place_plan_payload(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.received_place_plan_invitations()', 'execute')
    or not has_function_privilege('authenticated', 'public.open_received_place_plan_invitation(uuid)', 'execute')
  then raise exception 'inbox grants changed'; end if;
  if exists (select 1 from pg_proc where oid in
      ('public.received_place_plan_invitations()'::regprocedure,
       'public.open_received_place_plan_invitation(uuid)'::regprocedure,
       'app.place_plan_payload(uuid)'::regprocedure)
    and (not prosecdef or not ('search_path=public, app, extensions' = any(proconfig))))
  then raise exception 'inbox RPC security posture changed'; end if;
  insert into public.profiles(id, handle, display_name, is_private_profile)
    values(sender, 'codex_plan_sender', 'Smoke Sender', false),
          (recipient, 'codex_plan_recipient', 'Smoke Recipient', false),
          (stranger, 'codex_plan_stranger', 'Smoke Stranger', false);
  insert into public.follows(follower_user_id, followed_user_id, source) values(sender, recipient, 'username');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', sender, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.save_own_place(venue,
    '{"status":"been","visibility":"followers","note":"NEVER PUBLISH PRIVATE SAVE NOTE","source_type":"manual","nearby_confirmed":false}', '[]');
  place_id := (result->>'place_id')::uuid;
  insert into storage.objects(bucket_id, name) values ('place-plan-previews', image_path);
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  perform public.save_own_place(venue,
    '{"status":"wanna_go","visibility":"followers","source_type":"manual","nearby_confirmed":false}', '[]');
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', sender, 'role', 'authenticated')::text, true);
  set local role authenticated;
  invite_token := public.create_place_plan_invitation(place_id, recipient, image_path,
    'Meet at the park?', 'Smoke Sender’s been and you wanna go', 'Sep 20, 2026 at 10 AM', 'Let’s go to Plan Smoke Park together', '2026-09-20T17:00:00Z')->>'token';
  if invite_token !~ '^[a-f0-9]{48}$' then raise exception 'invalid plan token'; end if;
  reset role;
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  set local role anon;
  result := public.place_plan_preview(invite_token);
  if result->>'title' is distinct from 'Let’s go to Plan Smoke Park together'
    or result->>'date_label' is distinct from 'Sep 20, 2026 at 10 AM'
    or result->>'message' is distinct from 'Meet at the park?'
    or result->>'image_path' is distinct from image_path
    or result::text like '%NEVER PUBLISH%'
    or result ? 'user_place_id' or result ? 'rating_score' or result ? 'visits'
  then raise exception 'plan preview contract or privacy failed'; end if;
  if public.place_plan_preview('invalid') is not null
    or public.place_plan_preview(repeat('0',48)) is not null then
    raise exception 'invalid tokens must have no preview';
  end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.received_place_plan_invitations();
  if jsonb_array_length(result) <> 1 or result->0->>'read_at' is not null
    or result->0->'invitation'->>'title' is distinct from 'Let’s go to Plan Smoke Park together'
    or result::text like '%NEVER PUBLISH%' or result::text like '%token_hash%'
    or result::text like '%' || invite_token || '%'
  then raise exception 'recipient inbox contract failed'; end if;
  invitation_id := (result->0->>'id')::uuid;
  result := public.open_received_place_plan_invitation(invitation_id);
  if result is distinct from public.place_plan_preview(invite_token)
    or public.received_place_plan_invitations()->0->>'read_at' is null
    or jsonb_array_length(public.received_place_plan_invitations()) <> 1
  then raise exception 'opening must mark read and preserve the invitation'; end if;
  reset role;
  update public.place_plan_invitations set read_at = '2026-01-01T00:00:00Z' where id = invitation_id;
  set local role authenticated;
  perform public.open_received_place_plan_invitation(invitation_id);
  reset role;
  if (select read_at from public.place_plan_invitations where id = invitation_id) <> '2026-01-01T00:00:00Z'::timestamptz
  then raise exception 'reopening changed first-read timestamp'; end if;
  update public.place_plan_invitations set expires_at = now() - interval '1 second' where id = invitation_id;
  set local role authenticated;
  if jsonb_array_length(public.received_place_plan_invitations()) <> 0
    or public.open_received_place_plan_invitation(invitation_id) is not null
    or public.place_plan_preview(invite_token) is not null
  then raise exception 'expired invitation remained available'; end if;
  reset role;
  update public.place_plan_invitations set expires_at = now() + interval '1 day' where id = invitation_id;
  update public.profiles set deleted_at = now() where id = sender;
  set local role authenticated;
  if jsonb_array_length(public.received_place_plan_invitations()) <> 0
    or public.open_received_place_plan_invitation(invitation_id) is not null
  then raise exception 'deleted sender remained visible'; end if;
  reset role;
  update public.profiles set deleted_at = null where id = sender;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', stranger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if jsonb_array_length(public.received_place_plan_invitations()) <> 0
    or public.open_received_place_plan_invitation(invitation_id) is not null
  then raise exception 'stranger could open recipient inbox'; end if;
  begin
    perform public.create_place_plan_invitation(place_id, recipient, image_path, 'Hijack', 'Hijack', 'Date TBD', 'Hijack');
    raise exception 'stranger could create a plan';
  exception when raise_exception then
    if sqlerrm <> 'plan_not_available' then raise; end if;
  end;
  reset role;
  insert into public.blocks(blocker_user_id, blocked_user_id) values(recipient, sender);
  set local role anon;
  if public.place_plan_preview(invite_token) is not null then raise exception 'blocked invitation remained available'; end if;
  begin
    perform public.received_place_plan_invitations();
    raise exception 'anonymous inbox read allowed';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if jsonb_array_length(public.received_place_plan_invitations()) <> 0
    or public.open_received_place_plan_invitation(invitation_id) is not null
  then raise exception 'blocked invitation appeared in inbox'; end if;
  reset role;
end;
$test$;

-- Exercise the exact authenticated RPC for both one-sided invitation directions.
-- Separate fixtures keep the original shared-place / inbox contract unchanged.
do $one_sided$
declare
  sender text := 'user_codex_plan_solo_sender';
  recipient text := 'user_codex_plan_solo_recipient';
  venue jsonb := '{"canonical_name":"One Sided Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec578-one-sided-plan","confidence":1}';
  venue_id uuid;
  image_path text := 'user_codex_plan_solo_sender/11111111-2222-4333-8444-555555555555/preview.png';
  invite_token text;
  result jsonb;
  owner_id text;
  blocked_by text;
begin
  insert into public.profiles(id, handle, display_name, is_private_profile)
    values(sender, 'codex_plan_solo_sender', 'Solo Sender', false),
          (recipient, 'codex_plan_solo_recipient', 'Solo Recipient', false);
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(sender, recipient, 'username');

  perform set_config('request.jwt.claims', jsonb_build_object('sub', sender, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.save_own_place(venue,
    '{"status":"been","visibility":"self","note":"NEVER PUBLISH SOLO SAVE NOTE","source_type":"manual","nearby_confirmed":false}', '[]');
  venue_id := (result->>'place_id')::uuid;
  insert into storage.objects(bucket_id, name) values ('place-plan-previews', image_path);
  invite_token := public.create_place_plan_invitation(venue_id, recipient, image_path,
    'Go together?', 'I love this place', 'Date TBD', 'A favorite to try together')->>'token';
  if invite_token is null or invite_token !~ '^[a-f0-9]{48}$'
  then raise exception 'sender-only plan failed'; end if;
  reset role;
  if exists (select 1 from public.user_places where user_id = recipient and deleted_at is null)
  then raise exception 'sender-only fixture requires a recipient with zero saves'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.received_place_plan_invitations();
  if jsonb_array_length(result) <> 1 or result::text like '%NEVER PUBLISH%'
    or public.open_received_place_plan_invitation((result->0->>'id')::uuid)
      is distinct from public.place_plan_preview(invite_token)
  then raise exception 'sender-only plan did not reach recipient safely'; end if;
  perform public.save_own_place(venue,
    '{"status":"been","visibility":"followers","note":"NEVER PUBLISH RECIPIENT NOTE","source_type":"manual","nearby_confirmed":false}', '[]');
  reset role;
  update public.user_places set deleted_at = now() where user_id = sender and place_id = venue_id;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', sender, 'role', 'authenticated')::text, true);
  set local role authenticated;
  invite_token := public.create_place_plan_invitation(venue_id, recipient, image_path,
    'Take me here?', 'You love this place', 'Date TBD', 'Your favorite to try together')->>'token';
  if invite_token is null or invite_token !~ '^[a-f0-9]{48}$'
  then raise exception 'recipient-only plan failed'; end if;
  reset role;
  if exists (select 1 from public.user_places where user_id = sender and deleted_at is null)
  then raise exception 'recipient-only fixture requires a sender with zero active saves'; end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  result := public.received_place_plan_invitations();
  if jsonb_array_length(result) <> 2 or result::text like '%NEVER PUBLISH%'
    or public.place_plan_preview(invite_token)->>'connection' is distinct from 'You love this place'
  then raise exception 'recipient-only plan did not reach recipient safely'; end if;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', sender, 'role', 'authenticated')::text, true);

  -- A hidden or deleted recipient save cannot authorize a sender with no saves.
  update public.user_places set visibility = 'self' where user_id = recipient and place_id = venue_id;
  set local role authenticated;
  begin
    perform public.create_place_plan_invitation(venue_id, recipient, image_path, 'Hidden', 'Hidden', 'Date TBD', 'Hidden');
    raise exception 'hidden recipient save authorized a plan';
  exception when raise_exception then if sqlerrm <> 'plan_not_available' then raise; end if; end;
  reset role;
  update public.user_places set visibility = 'followers', deleted_at = now()
    where user_id = recipient and place_id = venue_id;
  set local role authenticated;
  begin
    perform public.create_place_plan_invitation(venue_id, recipient, image_path, 'Deleted', 'Deleted', 'Date TBD', 'Deleted');
    raise exception 'two deleted saves authorized a plan';
  exception when raise_exception then if sqlerrm <> 'plan_not_available' then raise; end if; end;
  reset role;
  update public.user_places set deleted_at = null where user_id = recipient and place_id = venue_id;
  delete from public.follows where follower_user_id = sender and followed_user_id = recipient;
  set local role authenticated;
  begin
    perform public.create_place_plan_invitation(venue_id, recipient, image_path, 'Unfollowed', 'Unfollowed', 'Date TBD', 'Unfollowed');
    raise exception 'unreadable recipient save authorized a plan';
  exception when raise_exception then if sqlerrm <> 'plan_not_available' then raise; end if; end;
  reset role;
  insert into public.follows(follower_user_id, followed_user_id, source) values(sender, recipient, 'username');

  -- Blocks and deleted accounts must deny either ownership direction.
  foreach owner_id in array array[sender, recipient] loop
    update public.user_places set deleted_at = case when user_id = owner_id then null else now() end
      where place_id = venue_id and user_id in (sender, recipient);
    foreach blocked_by in array array[sender, recipient] loop
      insert into public.follows(follower_user_id, followed_user_id, source)
        values(sender, recipient, 'username') on conflict do nothing;
      set local role authenticated;
      perform public.create_place_plan_invitation(venue_id, recipient, image_path,
        'Available', 'Available', 'Date TBD', 'Available before block or deletion');
      reset role;
      insert into public.blocks(blocker_user_id, blocked_user_id)
        values(blocked_by, case when blocked_by = sender then recipient else sender end);
      set local role authenticated;
      begin
        perform public.create_place_plan_invitation(venue_id, recipient, image_path, 'Blocked', 'Blocked', 'Date TBD', 'Blocked');
        raise exception 'block allowed a one-sided plan';
      exception when raise_exception then if sqlerrm <> 'plan_not_available' then raise; end if; end;
      reset role;
      delete from public.blocks where blocker_user_id = blocked_by
        and blocked_user_id = case when blocked_by = sender then recipient else sender end;
      insert into public.follows(follower_user_id, followed_user_id, source)
        values(sender, recipient, 'username') on conflict do nothing;
      update public.profiles set deleted_at = now() where id = blocked_by;
      set local role authenticated;
      begin
        perform public.create_place_plan_invitation(venue_id, recipient, image_path, 'Deleted account', 'Deleted account', 'Date TBD', 'Deleted account');
        raise exception 'deleted account allowed a one-sided plan';
      exception when raise_exception then if sqlerrm <> 'plan_not_available' then raise; end if; end;
      reset role;
      update public.profiles set deleted_at = null where id = blocked_by;
    end loop;
  end loop;
end;
$one_sided$;

rollback;
