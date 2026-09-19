begin;
do $test$
declare
  owner_id text := 'user_codex_card_owner';
  stranger_id text := 'user_codex_card_stranger';
  venue jsonb := '{"canonical_name":"Card Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec546-card","confidence":1}';
  saved jsonb;
  card_place_id uuid;
  activity_id uuid;
  list_id uuid;
  invite_token text;
  card_token text;
  profile_card_token text;
  image_path text;
  kinds text[] := array['profile','place','list','activity','invite'];
  identifiers text[];
  result jsonb;
  i integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.share_card_previews'::regclass)
    or has_table_privilege('authenticated', 'public.share_card_previews', 'select')
    or has_table_privilege('anon', 'public.share_card_previews', 'select') then
    raise exception 'card table must not be enumerable';
  end if;
  if exists (select 1 from pg_proc where oid in
      ('public.create_share_card_preview(text,text,text,text)'::regprocedure,
       'public.share_card_preview(text,text,text)'::regprocedure)
      and (not prosecdef or not ('search_path=public, app, extensions' = any(proconfig))))
    or has_function_privilege('anon','public.create_share_card_preview(text,text,text,text)','execute')
    or not has_function_privilege('authenticated','public.create_share_card_preview(text,text,text,text)','execute')
    or not has_function_privilege('anon','public.share_card_preview(text,text,text)','execute')
    then raise exception 'card RPC security posture changed'; end if;
  insert into public.profiles(id, handle, display_name, is_private_profile)
    values(owner_id, 'codex_card_owner', 'Smoke Owner', false),
          (stranger_id, 'codex_card_stranger', 'Smoke Stranger', false);
  perform set_config('request.jwt.claim.sub',owner_id,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  saved := public.save_own_place(venue,
    '{"status":"been","visibility":"self","note":"NEVER PUBLISH PRIVATE NOTE","source_type":"manual","nearby_confirmed":false}', '[]');
  card_place_id := (saved->>'place_id')::uuid;
  list_id := public.upsert_place_list('{"name":"Smoke card list","visibility":"stealth"}');
  invite_token := public.create_place_list_invite(list_id)->>'token';
  reset role;
  -- Resolve the event from its canonical place without relying on save response aliases.
  select event.id into activity_id from public.feed_events event
    join public.user_places up on up.id = event.user_place_id
    where up.user_id = owner_id and up.place_id = card_place_id limit 1;
  if activity_id is null then raise exception 'missing smoke activity'; end if;
  identifiers := array[owner_id, card_place_id::text, list_id::text, activity_id::text, invite_token];
  for i in 1..5 loop
    image_path := owner_id || '/' || gen_random_uuid()::text || '/preview.png';
    set local role authenticated;
    insert into storage.objects(bucket_id,name) values('share-card-previews',image_path);
    card_token := public.create_share_card_preview(kinds[i],identifiers[i],image_path,'Approved smoke card')->>'token';
    if card_token !~ '^[a-f0-9]{48}$' then raise exception 'invalid card token'; end if;
    if i = 1 then profile_card_token := card_token; end if;
    reset role;
    perform set_config('request.jwt.claim.sub','',true);
    perform set_config('request.jwt.claims','{"role":"anon"}',true);
    set local role anon;
    result := public.share_card_preview(card_token,kinds[i],identifiers[i]);
    if result->>'image_path' is distinct from image_path or result->>'title' is distinct from 'Approved smoke card'
      or (select count(*) from jsonb_object_keys(result)) <> 2
      or result::text like '%NEVER PUBLISH%' then raise exception 'card payload leaked or changed'; end if;
    if public.share_card_preview(card_token,kinds[i],'wrong-route') is not null
      or public.share_card_preview(card_token,'other-kind',identifiers[i]) is not null
      or public.share_card_preview(repeat('0',48),kinds[i],identifiers[i]) is not null
      or public.share_card_preview('../bad',kinds[i],identifiers[i]) is not null
      then raise exception 'unbound or invalid card token accepted'; end if;
    begin
      perform public.create_share_card_preview(kinds[i],identifiers[i],image_path,'Forbidden');
      raise exception 'anonymous publication accepted';
    exception when insufficient_privilege then null; end;
    reset role;
    perform set_config('request.jwt.claim.sub',owner_id,true);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  end loop;
  -- A stranger cannot publish a private activity/list or write another owner's folder.
  perform set_config('request.jwt.claim.sub',stranger_id,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
  set local role authenticated;
  for i in 3..5 loop
    begin
      perform public.create_share_card_preview(kinds[i],identifiers[i],image_path,'Forbidden');
      raise exception 'unauthorized target accepted';
    exception when raise_exception then
      if sqlerrm <> 'share_target_unavailable' then raise; end if;
    end;
  end loop;
  begin
    insert into storage.objects(bucket_id,name) values('share-card-previews',owner_id || '/' || gen_random_uuid()::text || '/preview.png');
    raise exception 'foreign folder accepted';
  exception when insufficient_privilege then null; end;
  begin
    perform public.create_share_card_preview('profile',stranger_id,image_path,'Forbidden');
    raise exception 'foreign artwork accepted';
  exception when raise_exception then
    if sqlerrm <> 'share_artwork_unavailable' then raise; end if;
  end;
  reset role;
  update public.place_list_invites set revoked_at = now() where token_hash = encode(extensions.digest(invite_token,'sha256'),'hex');
  set local role anon;
  if public.share_card_preview(card_token,'invite',invite_token) is not null then raise exception 'revoked invite still resolved'; end if;
  reset role;
  update public.profiles set deleted_at = now() where id = owner_id;
  set local role anon;
  if public.share_card_preview(profile_card_token,'profile',owner_id) is not null then raise exception 'deleted publisher still resolved'; end if;
  reset role;
end;
$test$;
rollback;
