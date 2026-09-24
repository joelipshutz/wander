begin;

do $$
declare signature text; job record; result jsonb;
begin
  if not (select relrowsecurity from pg_class where oid='public.signup_slack_deliveries'::regclass)
    or has_table_privilege('authenticated','public.signup_slack_deliveries','select,insert,update,delete')
    or has_table_privilege('anon','public.signup_slack_deliveries','select,insert,update,delete') then
    raise exception 'outbox exposed';
  end if;
  foreach signature in array array['public.claim_signup_slack()','public.settle_signup_slack(text,uuid,text,text)'] loop
    if not (select prosecdef and proconfig @> array['search_path=public'] from pg_proc where oid=signature::regprocedure)
      or has_function_privilege('authenticated',signature,'execute')
      or has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('service_role',signature,'execute') then
      raise exception 'worker RPC security mismatch';
    end if;
  end loop;

  -- Exercise the actual event-before-profile transaction order.
  result := public.mirror_clerk_profile('msg_signup_test_create','user.created',now(),
    'user_codex_signup_test','codexsignuptest','Signup Test',null);
  if result->>'action' <> 'upserted' then raise exception 'mirror failed'; end if;
  perform public.mirror_clerk_profile('msg_signup_test_create','user.created',now(),
    'user_codex_signup_test','codexsignuptest','Signup Test',null);
  perform public.mirror_clerk_profile('msg_signup_test_other_create','user.created',now(),
    'user_codex_signup_test','codexsignuptest','Signup Test',null);
  perform public.mirror_clerk_profile('msg_signup_test_update','user.updated',now(),
    'user_codex_signup_test','codexsignuptest','Updated Name',null);
  if (select count(*) from public.signup_slack_deliveries where profile_id='user_codex_signup_test') <> 1 then
    raise exception 'duplicate notification queued';
  end if;
  -- Update-only/bootstrap profiles are not new account events.
  perform public.mirror_clerk_profile('msg_signup_test_update_only','user.updated',now(),
    'user_codex_signup_update','codexsignupupdate','Update Only',null);
  if exists(select 1 from public.signup_slack_deliveries where profile_id='user_codex_signup_update') then
    raise exception 'profile update queued';
  end if;
  insert into public.clerk_identity_mappings(clerk_user_id,profile_id)
    values('user_codex_signup_production','user_codex_signup_test');
  update public.signup_slack_deliveries set next_attempt_at='1900-01-01' where profile_id='user_codex_signup_test';
  update public.profiles set onboarding_completed_at=now() where id='user_codex_signup_test';
  select * into job from public.claim_signup_slack() where profile_id='user_codex_signup_test';
  if job.profile_id is null or not (job.clerk_user_ids ? 'user_codex_signup_production') then
    raise exception 'claim context missing';
  end if;
  if exists(select 1 from public.claim_signup_slack() where profile_id=job.profile_id) then
    raise exception 'active claim reclaimed';
  end if;
  if public.settle_signup_slack(job.profile_id,gen_random_uuid(),'sent',null) then raise exception 'wrong claim accepted'; end if;
  if not public.settle_signup_slack(job.profile_id,job.claim_token,'retry','slack_unavailable') then raise exception 'retry failed'; end if;
  if not exists(select 1 from public.signup_slack_deliveries where profile_id=job.profile_id
    and status='pending' and next_attempt_at>now() and attempt_count=1) then raise exception 'backoff missing'; end if;
  update public.signup_slack_deliveries set next_attempt_at='1900-01-01' where profile_id=job.profile_id;
  select * into job from public.claim_signup_slack() where profile_id='user_codex_signup_test';
  if not public.settle_signup_slack(job.profile_id,job.claim_token,'sent',null) then raise exception 'success failed'; end if;
  if public.settle_signup_slack(job.profile_id,job.claim_token,'sent',null) then raise exception 'duplicate settlement accepted'; end if;
  if exists(select 1 from public.claim_signup_slack() where profile_id=job.profile_id) then raise exception 'sent job reclaimed'; end if;
  -- Expired lease recovers; exhausted retries stop.
  update public.signup_slack_deliveries set status='sending',attempt_count=11,
    claim_expires_at=now()-interval '1 minute' where profile_id=job.profile_id;
  select * into job from public.claim_signup_slack() where profile_id='user_codex_signup_test';
  if job.profile_id is null then raise exception 'expired lease not recovered'; end if;
  perform public.settle_signup_slack(job.profile_id,job.claim_token,'retry','slack_unavailable');
  if not exists(select 1 from public.signup_slack_deliveries where profile_id=job.profile_id and status='failed') then
    raise exception 'retry cap missing';
  end if;
  -- A stale delete does not cancel an active account's notification.
  perform public.mirror_clerk_profile('msg_signup_test_stale_delete','user.deleted',now()-interval '1 day',
    'user_codex_signup_test',null,null,null);
  if not exists(select 1 from public.signup_slack_deliveries where profile_id='user_codex_signup_test') then
    raise exception 'stale delete removed job';
  end if;
  perform public.mirror_clerk_profile('msg_signup_test_delete','user.deleted',now()+interval '1 second',
    'user_codex_signup_test',null,null,null);
  if exists(select 1 from public.signup_slack_deliveries where profile_id='user_codex_signup_test') then
    raise exception 'delete did not remove job';
  end if;
  perform public.mirror_clerk_profile('msg_signup_test_direct_create','user.created',now(),
    'user_codex_signup_direct','codexsignupdirect','Direct Deletion',null);
  delete from public.profiles where id='user_codex_signup_direct';
  if exists(select 1 from public.signup_slack_deliveries where profile_id='user_codex_signup_direct') then
    raise exception 'direct account purge retained outbox row';
  end if;
end;
$$;
select 'signup_slack_delivery: passed' as result;
rollback;
