begin;

do $test$
declare
  actor text := 'user_codex_follow_inbox_actor';
  recipient text := 'user_codex_follow_inbox_recipient';
  stranger text := 'user_codex_follow_inbox_stranger';
  first_id uuid;
  next_id uuid;
  n integer;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.follow_notification_receipts'::regclass)
    or has_table_privilege('authenticated', 'public.follow_notification_receipts', 'select')
    or has_table_privilege('authenticated', 'public.follow_notification_receipts', 'insert')
    or has_table_privilege('anon', 'public.follow_notification_receipts', 'select')
  then raise exception 'follow receipts must not be directly accessible'; end if;
  if has_function_privilege('anon', 'public.received_follow_notifications()', 'execute')
    or not has_function_privilege('authenticated', 'public.received_follow_notifications()', 'execute')
    or has_function_privilege('authenticated', 'app.record_follow_notification_receipt()', 'execute')
    or exists (select 1 from pg_proc where oid in
      ('public.received_follow_notifications()'::regprocedure,
       'app.record_follow_notification_receipt()'::regprocedure)
      and (not prosecdef or not ('search_path=public, app' = any(proconfig))))
  then raise exception 'follow inbox grants or security posture changed'; end if;
  if exists (select 1 from pg_proc where oid = 'public.received_follow_notifications()'::regprocedure
    and (provolatile <> 's' or not proretset or pronargs <> 0
      or exists (select 1 from aclexplode(coalesce(proacl, acldefault('f', proowner)))
        where grantee = 0 and privilege_type = 'EXECUTE')))
  then raise exception 'follow inbox read contract changed'; end if;

  insert into public.profiles(id, handle, display_name, is_private_profile)
    values(actor, 'codex_follow_inbox_actor', 'Smoke Actor', false),
          (recipient, 'codex_follow_inbox_recipient', 'Smoke Recipient', false),
          (stranger, 'codex_follow_inbox_stranger', 'Smoke Stranger', false);
  perform app.ensure_notification_preferences(recipient);
  update public.notification_preferences set push_enabled = false, social_graph_enabled = false
    where user_id = recipient;
  -- Launch defaults are not deliberate follows; keep their existing alert suppression.
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(actor, recipient, 'signup_default') returning id into first_id;
  if exists (select 1 from public.follow_notification_receipts where id = first_id)
    or exists (select 1 from public.notification_events where recipient_user_id = recipient)
  then raise exception 'signup default follow must not create an inbox or push alert'; end if;
  delete from public.follows where id = first_id;
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(actor, recipient, 'username') returning id into first_id;
  if not exists (select 1 from public.follow_notification_receipts where id = first_id and not is_mutual)
    or exists (select 1 from public.notification_events where recipient_user_id = recipient)
  then raise exception 'in-app receipt must exist independently of disabled push'; end if;
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(actor, recipient, 'username') on conflict (follower_user_id, followed_user_id) do nothing;
  if (select count(*) from public.follow_notification_receipts where recipient_id = recipient) <> 1
  then raise exception 'duplicate follow produced duplicate receipts'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  set local role authenticated;
  select count(*) into n from public.received_follow_notifications() where actor_id = actor;
  if n <> 1 then raise exception 'recipient cannot read their own notification'; end if;
  begin
    perform 1 from public.follow_notification_receipts;
    raise exception 'direct table access succeeded';
  exception when insufficient_privilege then null; end;
  reset role;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', stranger, 'role', 'authenticated')::text, true);
  set local role authenticated;
  if exists (select 1 from public.received_follow_notifications())
  then raise exception 'stranger can read another inbox'; end if;
  reset role;
  set local role anon;
  begin
    perform 1 from public.received_follow_notifications();
    raise exception 'anonymous inbox access succeeded';
  exception when insufficient_privilege then null; end;
  reset role;

  insert into public.follows(follower_user_id, followed_user_id, source)
    values(recipient, actor, 'username') returning id into next_id;
  if not (select is_mutual from public.follow_notification_receipts where id = next_id)
  then raise exception 'reciprocal follow must produce one mutual receipt'; end if;
  delete from public.follows where id = first_id;
  insert into public.follows(follower_user_id, followed_user_id, source)
    values(actor, recipient, 'username') returning id into next_id;
  if next_id = first_id or not exists (select 1 from public.follow_notification_receipts where id = next_id)
  then raise exception 'refollow did not create a new receipt identity'; end if;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', recipient, 'role', 'authenticated')::text, true);
  update public.profiles set is_private_profile = true where id = actor;
  set local role authenticated;
  if exists (select 1 from public.received_follow_notifications())
  then raise exception 'private actor exposed'; end if;
  reset role;
  update public.profiles set is_private_profile = false, deleted_at = now() where id = actor;
  set local role authenticated;
  if exists (select 1 from public.received_follow_notifications())
  then raise exception 'deleted actor exposed'; end if;
  reset role;
  update public.profiles set deleted_at = null where id = actor;
  insert into public.blocks(blocker_user_id, blocked_user_id) values(recipient, actor);
  set local role authenticated;
  if exists (select 1 from public.received_follow_notifications())
  then raise exception 'blocked actor exposed'; end if;
  reset role;
end;
$test$;

rollback;
