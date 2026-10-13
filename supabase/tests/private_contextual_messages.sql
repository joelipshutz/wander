begin;

-- Hosted-safe: synthetic identities and every message/graph mutation roll back.
do $test$
declare
  sender text := 'user_codex_private_message_sender';
  recipient text := 'user_codex_private_message_recipient';
  stranger text := 'user_codex_private_message_stranger';
  venue jsonb := '{"canonical_name":"Message Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec636-private-message","confidence":1}';
  fixture_place_id uuid; saved_id uuid; activity_id uuid; thread_id uuid; other_thread_id uuid;
  client_id uuid := gen_random_uuid(); first_message_id uuid; second_message_id uuid;
  payload jsonb; original jsonb; page jsonb; cursor jsonb; receipt jsonb; proc record;
  revoked_viewer text; global_live_enabled boolean;
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  if exists(select 1 from pg_class where oid in ('public.private_conversations'::regclass,'public.private_messages'::regclass) and not relrowsecurity)
    or has_table_privilege('authenticated','public.private_messages','select,insert,update,delete')
    or has_table_privilege('authenticated','public.private_conversations','select,insert,update,delete')
    or has_table_privilege('anon','public.private_messages','select,insert,update,delete')
    or has_table_privilege('anon','public.private_conversations','select,insert,update,delete')
  then raise exception 'private tables must deny direct client access and enable RLS'; end if;
  for proc in select p.*, n.nspname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='public' and p.proname in ('private_message_start','private_message_conversation','private_message_inbox','private_message_history','private_message_send','private_message_mark_read'))
       or (n.nspname='app' and p.proname in ('private_message_participant_enabled','private_message_pair_allowed','private_message_context_allowed','private_message_json','private_conversation_json'))
  loop
    if not proc.prosecdef or not ('search_path=pg_catalog, public, app'=any(proc.proconfig))
      or has_function_privilege('anon',proc.oid,'execute')
      or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
      or (proc.nspname='app' and has_function_privilege('authenticated',proc.oid,'execute'))
      or (proc.nspname='public' and (not has_function_privilege('authenticated',proc.oid,'execute') or proc.prorettype<>'jsonb'::regtype))
      or (proc.proname in ('private_message_start','private_message_send','private_message_mark_read') and proc.provolatile<>'v')
      or (proc.proname not in ('private_message_start','private_message_send','private_message_mark_read') and proc.provolatile<>'s')
    then raise exception 'private messaging RPC security metadata changed: %',proc.proname; end if;
  end loop;
  if not exists(select 1 from public.feature_flags where key='unified_live_v1' and user_id is null and value_type='boolean' and integer_value is null)
  then raise exception 'Live flag must be registered as Boolean'; end if;
  if has_table_privilege('authenticated','public.feature_flags','insert,update,delete,truncate')
    or has_table_privilege('anon','public.feature_flags','insert,update,delete,truncate')
  then raise exception 'participant approval flags must remain operator-owned'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (sender,'codex_message_sender','Message Sender',false),
    (recipient,'codex_message_recipient','Message Recipient',false),
    (stranger,'codex_message_stranger','Message Stranger',false);
  insert into public.feature_flags(key,user_id,enabled,value_type,integer_value)
    values ('unified_live_v1',sender,true,'boolean',null),
           ('unified_live_v1',recipient,true,'boolean',null),
           ('unified_live_v1',stranger,true,'boolean',null);
  insert into public.follows(follower_user_id,followed_user_id,source) values(sender,recipient,'username');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',sender,'role','authenticated')::text,true);
  set local role authenticated;
  payload := public.save_own_place(venue,'{"status":"been","visibility":"followers","note":"DO NOT COPY THIS SAVE NOTE","source_type":"manual","nearby_confirmed":false}','[]');
  fixture_place_id := (payload->>'place_id')::uuid;
  begin perform public.private_message_start(recipient,'place',fixture_place_id); raise exception 'one-way follow accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_start(sender,'place',fixture_place_id); raise exception 'self accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_start(stranger,'place',fixture_place_id); raise exception 'stranger accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform 1 from public.private_messages; raise exception 'direct private read accepted';
  exception when insufficient_privilege then null; end;
  reset role;
  select id into saved_id from public.user_places where user_id=sender and public.user_places.place_id=fixture_place_id and deleted_at is null;
  select id into activity_id from public.feed_events where user_place_id=saved_id order by created_at desc limit 1;
  if activity_id is null then raise exception 'activity fixture missing'; end if;
  insert into public.follows(follower_user_id,followed_user_id,source) values(recipient,sender,'username');
  -- Global/client enablement is not a substitute for both explicit internal
  -- participant overrides. Neither client may grant its own access.
  update public.feature_flags set enabled=false where key='unified_live_v1' and user_id=recipient;
  set local role authenticated;
  begin perform public.private_message_start(recipient,'place',fixture_place_id); raise exception 'unapproved participant accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin update public.feature_flags set enabled=true where key='unified_live_v1' and user_id=recipient; raise exception 'client granted messaging access';
  exception when insufficient_privilege then null; end;
  reset role;
  update public.feature_flags set enabled=true where key='unified_live_v1' and user_id=recipient;
  set local role authenticated;
  begin perform public.private_message_start(recipient,'activity',gen_random_uuid()); raise exception 'forged source accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  thread_id := (public.private_message_start(recipient,'activity',activity_id)->>'id')::uuid;
  if (public.private_message_start(recipient,'place',fixture_place_id)->>'id')::uuid<>thread_id then raise exception 'duplicate pair conversation'; end if;
  if jsonb_array_length(public.private_message_inbox()->'items')<>0 then raise exception 'empty draft conversation leaked to inbox'; end if;
  original := public.private_message_send(thread_id,'  A private reply  ',client_id,'activity',activity_id);
  first_message_id := (original->>'id')::uuid;
  if original->>'body'<>'A private reply' or original->>'senderID'<>sender
    or (original->>'conversationID')::uuid<>thread_id or original->>'sentAt' is null
    or original->>'clientID' is null or original::text like '%DO NOT COPY%'
    or original->'context'->>'title'<>'Message Smoke Park'
  then raise exception 'authoritative send payload or source minimization failed'; end if;
  payload := public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id);
  if payload is distinct from original then raise exception 'retry did not return identical acknowledgment'; end if;
  begin perform public.private_message_send(thread_id,'different content',client_id,'activity',activity_id); raise exception 'idempotency payload changed';
  exception when raise_exception then if sqlerrm<>'private_message_idempotency_conflict' then raise; end if; end;
  begin perform public.private_message_send(thread_id,E' \t\n ',gen_random_uuid()); raise exception 'whitespace body accepted';
  exception when raise_exception then if sqlerrm<>'private_message_invalid_body' then raise; end if; end;
  begin perform public.private_message_send(thread_id,repeat('a',2001),gen_random_uuid()); raise exception 'oversized body accepted';
  exception when raise_exception then if sqlerrm<>'private_message_invalid_body' then raise; end if; end;
  second_message_id := (public.private_message_send(thread_id,repeat('a',2000),gen_random_uuid(),'place',fixture_place_id)->>'id')::uuid;
  page := public.private_message_history(thread_id,null,null,1);
  cursor := page->'nextCursor';
  if jsonb_array_length(page->'items')<>1 or cursor='null'::jsonb then raise exception 'bounded first page failed'; end if;
  payload := public.private_message_history(thread_id,(cursor->>'timestamp')::timestamptz,(cursor->>'id')::uuid,1);
  if jsonb_array_length(payload->'items')<>1 or payload->'items'->0->>'id'=page->'items'->0->>'id' or payload->'nextCursor'<>'null'::jsonb
  then raise exception 'stable continuation page failed'; end if;
  begin perform public.private_message_history(thread_id,now(),null,1); raise exception 'partial cursor accepted';
  exception when raise_exception then if sqlerrm<>'private_message_invalid_cursor' then raise; end if; end;
  begin perform public.private_message_history(thread_id,now(),gen_random_uuid(),1); raise exception 'foreign cursor accepted';
  exception when raise_exception then if sqlerrm<>'private_message_invalid_cursor' then raise; end if; end;
  reset role;

  -- Revocation applies to already-established threads and every subsequent
  -- operation for both participants, including retries of acknowledged sends.
  -- A global enabled row must not replace the required per-account approval.
  select enabled into strict global_live_enabled from public.feature_flags
    where key='unified_live_v1' and user_id is null;
  update public.feature_flags set enabled=true where key='unified_live_v1' and user_id is null;
  update public.feature_flags set enabled=false where key='unified_live_v1' and user_id=recipient;
  foreach revoked_viewer in array array[sender,recipient] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',revoked_viewer,'role','authenticated')::text,true);
    set local role authenticated;
    page := public.private_message_inbox();
    if page->'items'<>'[]'::jsonb or page->'nextCursor'<>'null'::jsonb
    then raise exception 'revoked participant inbox or cursor leaked'; end if;
    begin perform public.private_message_conversation(thread_id); raise exception 'revoked participant conversation leaked';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    begin perform public.private_message_history(thread_id); raise exception 'revoked participant history leaked';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    begin perform public.private_message_send(thread_id,'Revoked send',gen_random_uuid()); raise exception 'revoked participant send accepted';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    begin perform public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id); raise exception 'revoked participant retry leaked';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    begin perform public.private_message_mark_read(thread_id,second_message_id); raise exception 'revoked participant read accepted';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    begin perform public.private_message_start(case when revoked_viewer=sender then recipient else sender end,'activity',activity_id);
      raise exception 'revoked participant reopened established thread';
    exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
    reset role;
  end loop;
  delete from public.feature_flags where key='unified_live_v1' and user_id=recipient;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',sender,'role','authenticated')::text,true);
  set local role authenticated;
  if public.private_message_inbox()->'items'<>'[]'::jsonb then raise exception 'global flag replaced absent participant override'; end if;
  begin perform public.private_message_history(thread_id); raise exception 'missing participant approval leaked history';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  insert into public.feature_flags(key,user_id,enabled,value_type,integer_value)
    values('unified_live_v1',recipient,true,'boolean',null);
  update public.feature_flags set enabled=global_live_enabled where key='unified_live_v1' and user_id is null;
  set local role authenticated;
  if jsonb_array_length(public.private_message_inbox()->'items')<>1
    or jsonb_array_length(public.private_message_history(thread_id)->'items')<>2
    or (public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id)->>'id')::uuid<>first_message_id
  then raise exception 'restored participant lost existing history or idempotent acknowledgment'; end if;
  reset role;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',recipient,'role','authenticated')::text,true);
  set local role authenticated;
  if (public.private_message_start(sender,'place',fixture_place_id)->>'id')::uuid<>thread_id then raise exception 'reverse pair duplicated'; end if;
  payload := public.private_message_conversation(thread_id);
  if (payload->>'unreadCount')::integer<>2 or payload->'participant'->>'id'<>sender then raise exception 'recipient unread/identity failed'; end if;
  perform public.private_message_mark_read(thread_id,second_message_id);
  receipt := public.private_message_history(thread_id)->'items'->0->'recipientReadAt';
  if receipt='null'::jsonb or (public.private_message_conversation(thread_id)->>'unreadCount')::integer<>0 then raise exception 'read acknowledgment failed'; end if;
  perform public.private_message_mark_read(thread_id,first_message_id);
  if public.private_message_history(thread_id)->'items'->0->'recipientReadAt' is distinct from receipt then raise exception 'read cursor regressed'; end if;
  begin perform public.private_message_mark_read(thread_id,gen_random_uuid()); raise exception 'forged read target accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
  set local role authenticated;
  if public.private_message_inbox()->'items'<>'[]'::jsonb then raise exception 'stranger inbox leaked'; end if;
  begin perform public.private_message_history(thread_id); raise exception 'stranger history leaked';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_send(thread_id,'injected',gen_random_uuid()); raise exception 'stranger send accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_mark_read(thread_id,first_message_id); raise exception 'stranger read accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;

  -- Revoked source removes its body/context from every read, while an unrelated
  -- private follow-on remains visible. Restoring source access is reversible.
  update public.user_places set visibility='self' where id=saved_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',sender,'role','authenticated')::text,true);
  set local role authenticated;
  if public.private_message_history(thread_id)->'items'<>'[]'::jsonb
    or public.private_message_conversation(thread_id)->'lastMessagePreview'<>'null'::jsonb
    or public.private_message_inbox()->'items'<>'[]'::jsonb then raise exception 'revoked context leaked'; end if;
  -- Sequential access/recovery contracts; the lock-wait race also requires
  -- a second session that revokes the source while start waits for its lock.
  begin perform public.private_message_start(recipient,'activity',activity_id); raise exception 'revoked activity reopened conversation';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_start(recipient,'place',fixture_place_id); raise exception 'revoked place reopened conversation';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id); raise exception 'revoked retry leaked acknowledgment';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  perform public.private_message_send(thread_id,'A separate private message',gen_random_uuid());
  if jsonb_array_length(public.private_message_history(thread_id)->'items')<>1 then raise exception 'noncontext message lost'; end if;
  reset role;
  update public.user_places set visibility='followers' where id=saved_id;
  set local role authenticated;
  if (public.private_message_start(recipient,'activity',activity_id)->>'id')::uuid is distinct from thread_id
    or (public.private_message_start(recipient,'place',fixture_place_id)->>'id')::uuid is distinct from thread_id
  then raise exception 'restored context did not reuse the original conversation'; end if;
  reset role;
  update public.user_places set deleted_at=clock_timestamp() where id=saved_id;
  set local role authenticated;
  if jsonb_array_length(public.private_message_history(thread_id)->'items')<>1
  then raise exception 'deleted source message leaked'; end if;
  reset role;
  update public.user_places set deleted_at=null where id=saved_id;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(recipient,sender);
  set local role authenticated;
  if public.private_message_inbox()->'items'<>'[]'::jsonb then raise exception 'blocked inbox leaked'; end if;
  begin perform public.private_message_history(thread_id); raise exception 'blocked history leaked';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  begin perform public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id); raise exception 'blocked retry accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  delete from public.blocks where blocker_user_id=recipient and blocked_user_id=sender;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(sender,recipient);
  set local role authenticated;
  begin perform public.private_message_start(recipient,'place',fixture_place_id); raise exception 'outgoing block accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  delete from public.blocks where blocker_user_id=sender and blocked_user_id=recipient;
  delete from public.follows where follower_user_id=recipient and followed_user_id=sender;
  set local role authenticated;
  begin perform public.private_message_conversation(thread_id); raise exception 'unfollowed conversation leaked';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  insert into public.follows(follower_user_id,followed_user_id,source) values(recipient,sender,'username'),(sender,stranger,'username'),(stranger,sender,'username');

  -- Tie timestamps exercise the UUID tiebreaker in both keyset APIs.
  set local role authenticated;
  other_thread_id := (public.private_message_start(stranger,'place',fixture_place_id)->>'id')::uuid;
  perform public.private_message_send(other_thread_id,'Second conversation',gen_random_uuid());
  reset role;
  update public.private_conversations set updated_at='2026-01-01T00:00:00.123456Z' where id in(thread_id,other_thread_id);
  update public.private_messages set sent_at='2026-01-01T00:00:00.123456Z' where conversation_id=thread_id;
  set local role authenticated;
  page := public.private_message_inbox(null,null,1); cursor := page->'nextCursor';
  payload := public.private_message_inbox((cursor->>'timestamp')::timestamptz,(cursor->>'id')::uuid,1);
  if jsonb_array_length(page->'items')<>1 or jsonb_array_length(payload->'items')<>1
    or page->'items'->0->>'id'=payload->'items'->0->>'id' then raise exception 'tied inbox pagination failed'; end if;
  page := public.private_message_history(thread_id,null,null,1); cursor := page->'nextCursor';
  payload := public.private_message_history(thread_id,(cursor->>'timestamp')::timestamptz,(cursor->>'id')::uuid,1);
  if jsonb_array_length(payload->'items')<>1 or page->'items'->0->>'id'=payload->'items'->0->>'id' then raise exception 'tied history pagination failed'; end if;
  reset role;

  update public.private_messages set sent_at=clock_timestamp()-interval '2 hours' where sender_id=sender;
  insert into public.private_messages(conversation_id,sender_id,client_id,body)
    select thread_id,sender,gen_random_uuid(),'Rate fixture' from generate_series(1,20);
  set local role authenticated;
  begin perform public.private_message_send(thread_id,'Quota exceeded',gen_random_uuid()); raise exception 'minute quota ignored';
  exception when raise_exception then if sqlerrm<>'private_message_rate_limited' then raise; end if; end;
  -- Idempotency remains available even at quota; acknowledgments are not sends.
  if (public.private_message_send(thread_id,'A private reply',client_id,'activity',activity_id)->>'id')::uuid<>first_message_id
  then raise exception 'retry consumed quota'; end if;
  reset role;
  update public.private_messages set sent_at=clock_timestamp()-interval '2 hours' where sender_id=sender;
  insert into public.private_messages(conversation_id,sender_id,client_id,body,sent_at)
    select thread_id,sender,gen_random_uuid(),'Day rate fixture',clock_timestamp()-interval '2 hours' from generate_series(1,200);
  set local role authenticated;
  begin perform public.private_message_send(thread_id,'Daily quota exceeded',gen_random_uuid()); raise exception 'daily quota ignored';
  exception when raise_exception then if sqlerrm<>'private_message_rate_limited' then raise; end if; end;
  if jsonb_array_length(public.private_message_history(thread_id,null,null,10000)->'items')<>50 then raise exception 'server page bound ignored'; end if;
  reset role;

  update public.profiles set deleted_at=clock_timestamp() where id=recipient;
  set local role authenticated;
  begin perform public.private_message_history(thread_id); raise exception 'deleted participant leaked';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  set local role authenticated;
  begin perform public.private_message_inbox(); raise exception 'missing identity accepted';
  exception when raise_exception then if sqlerrm<>'private_message_unavailable' then raise; end if; end;
  reset role;
  perform set_config('request.jwt.claims','{"role":"anon"}',true);
  set local role anon;
  begin perform public.private_message_inbox(); raise exception 'anonymous RPC accepted';
  exception when insufficient_privilege then null; end;
  reset role;
end;
$test$;

-- Exercise the daily new-pair quota without making 50 real start calls. Every
-- seeded row and RPC write is synthetic and remains inside this outer rollback.
do $conversation_quota_test$
declare
  quota_sender text := 'user_codex_pm_quota_sender';
  other_sender text := 'user_codex_pm_quota_other';
  peers text[]; handles text[]; allowed_peer text;
  quota_place_id uuid; existing_thread_id uuid; fiftieth_thread_id uuid;
  unrelated_thread_id uuid; replacement_thread_id uuid; payload jsonb;
  venue jsonb := '{"canonical_name":"Conversation Quota Smoke Park","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","latitude":0,"longitude":0,"source_provider":"codex_smoke","source_provider_place_id":"rec636-private-conversation-quota","confidence":1}';
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  select array_agg('user_codex_pm_quota_peer_' || n order by n),
         array_agg('codex_pm_quota_peer_' || n order by n)
    into peers, handles from generate_series(1,51) n;
  -- Abort rather than adopt, update or delete a preexisting identity or place.
  if exists(select 1 from public.profiles
      where id=any(array[quota_sender,other_sender] || peers)
        or handle=any(array['codex_pm_quota_sender','codex_pm_quota_other'] || handles))
    or exists(select 1 from public.places where source_provider='codex_smoke'
      and source_provider_place_id='rec636-private-conversation-quota')
  then raise exception 'conversation quota fixture collision'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (quota_sender,'codex_pm_quota_sender','Quota Sender',false),
    (other_sender,'codex_pm_quota_other','Other Quota Sender',false);
  insert into public.profiles(id,handle,display_name,is_private_profile)
    select peers[n],handles[n],'Quota Peer ' || n,false from generate_series(1,51) n;
  insert into public.feature_flags(key,user_id,enabled,value_type,integer_value)
    select 'unified_live_v1',fixture_id,true,'boolean',null
    from unnest(array[quota_sender,other_sender,peers[1],peers[50],peers[51]]) fixture_id;
  foreach allowed_peer in array array[other_sender,peers[1],peers[50],peers[51]] loop
    insert into public.follows(follower_user_id,followed_user_id,source)
      values(quota_sender,allowed_peer,'username'),(allowed_peer,quota_sender,'username');
  end loop;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',quota_sender,'role','authenticated')::text,true);
  set local role authenticated;
  payload := public.save_own_place(venue,
    '{"status":"been","visibility":"followers","source_type":"manual","nearby_confirmed":false}','[]');
  quota_place_id := (payload->>'place_id')::uuid;
  reset role;

  insert into public.private_conversations(low_user_id,high_user_id,created_by,created_at)
    select least(quota_sender,peers[n]),greatest(quota_sender,peers[n]),quota_sender,
      clock_timestamp()-interval '1 hour' from generate_series(1,49) n;
  select id into strict existing_thread_id from public.private_conversations
    where low_user_id=least(quota_sender,peers[1]) and high_user_id=greatest(quota_sender,peers[1]);
  set local role authenticated;
  fiftieth_thread_id := (public.private_message_start(peers[50],'place',quota_place_id)->>'id')::uuid;
  if fiftieth_thread_id is null then raise exception '50th daily conversation rejected'; end if;
  begin
    perform public.private_message_start(peers[51],'place',quota_place_id);
    raise exception '51st daily conversation accepted';
  exception when raise_exception then
    if sqlerrm<>'private_message_rate_limited' then raise; end if;
  end;
  if (public.private_message_start(peers[1],'place',quota_place_id)->>'id')::uuid is distinct from existing_thread_id
    or (public.private_message_start(peers[50],'place',quota_place_id)->>'id')::uuid is distinct from fiftieth_thread_id
  then raise exception 'daily quota blocked existing conversation reuse'; end if;
  reset role;
  if (select count(*) from public.private_conversations where created_by=quota_sender)<>50
    or exists(select 1 from public.private_conversations
      where low_user_id=least(quota_sender,peers[51]) and high_user_id=greatest(quota_sender,peers[51]))
  then raise exception 'daily quota rejection or reuse changed conversation count'; end if;

  -- Receiving a new conversation does not spend the recipient's creator quota.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_sender,'role','authenticated')::text,true);
  set local role authenticated;
  unrelated_thread_id := (public.private_message_start(quota_sender,'place',quota_place_id)->>'id')::uuid;
  if unrelated_thread_id is null then raise exception 'another sender inherited daily conversation quota'; end if;
  reset role;
  if (select count(*) from public.private_conversations where created_by=other_sender)<>1
    or (select count(*) from public.private_conversations where created_by=quota_sender)<>50
  then raise exception 'daily conversation quota charged the wrong creator'; end if;

  -- Move one fixture safely outside the rolling window, avoiding timing-sensitive
  -- equality at exactly 24 hours. The older conversation must remain intact.
  update public.private_conversations set created_at=clock_timestamp()-interval '25 hours'
    where low_user_id=least(quota_sender,peers[2]) and high_user_id=greatest(quota_sender,peers[2]);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',quota_sender,'role','authenticated')::text,true);
  set local role authenticated;
  replacement_thread_id := (public.private_message_start(peers[51],'place',quota_place_id)->>'id')::uuid;
  if replacement_thread_id is null then raise exception 'expired daily window did not restore conversation capacity'; end if;
  if (public.private_message_start(other_sender,'place',quota_place_id)->>'id')::uuid is distinct from unrelated_thread_id
  then raise exception 'recipient-created conversation was duplicated at daily quota'; end if;
  reset role;
  if (select count(*) from public.private_conversations where created_by=quota_sender)<>51
    or (select count(*) from public.private_conversations where created_by=quota_sender
      and created_at>clock_timestamp()-interval '1 day')<>50
  then raise exception 'daily conversation window counted expired rows or lost history'; end if;
end;
$conversation_quota_test$;

rollback;
