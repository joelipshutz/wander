begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);
insert into public.profiles(id,handle,display_name) values('user_codex_slack_feedback','codexslackfeedback','Feedback Test');
do $security$
declare signature text;
begin
  if not (select relrowsecurity from pg_class where oid='public.feedback_slack_deliveries'::regclass)
    or has_table_privilege('authenticated','public.feedback_slack_deliveries','select,insert,update,delete')
    or has_table_privilege('anon','public.feedback_slack_deliveries','select,insert,update,delete') then
    raise exception 'private Slack outbox required'; end if;
  foreach signature in array array['public.claim_feedback_slack()','public.settle_feedback_slack(uuid,uuid,boolean,text)'] loop
    if has_function_privilege('authenticated',signature,'execute') or has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('service_role',signature,'execute')
      or not (select prosecdef and proconfig @> array['search_path=public'] from pg_proc where oid=signature::regprocedure)
      then raise exception 'Slack RPC security violation'; end if;
  end loop;
end;
$security$;
set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_slack_feedback',true);
select public.begin_own_feedback('54500000-0000-0000-0000-000000000003','Server-first feedback','[]','1','1');
reset role;
do $$ begin
 if exists(select 1 from public.feedback_slack_deliveries where feedback_id='54500000-0000-0000-0000-000000000003') then raise exception 'draft queued'; end if;
end $$;
set local role authenticated;
select public.submit_own_feedback('54500000-0000-0000-0000-000000000003');
select public.submit_own_feedback('54500000-0000-0000-0000-000000000003');
reset role;
do $delivery$
declare job record;
begin
  -- Keep fictional work first without consuming or settling existing reports.
  update public.feedback_slack_deliveries set next_attempt_at='1900-01-01' where feedback_id='54500000-0000-0000-0000-000000000003';
  if (select count(*) from public.feedback_slack_deliveries where feedback_id='54500000-0000-0000-0000-000000000003') <> 1 then raise exception 'duplicate outbox job'; end if;
  select * into job from public.claim_feedback_slack();
  if job.id is distinct from '54500000-0000-0000-0000-000000000003'::uuid or job.handle <> 'codexslackfeedback' then raise exception 'claim context missing'; end if;
  if public.settle_feedback_slack(job.id,gen_random_uuid(),true,null) then raise exception 'stale token accepted'; end if;
  if not public.settle_feedback_slack(job.id,job.claim_token,false,'slack_unavailable') then raise exception 'retry settlement failed'; end if;
  update public.feedback_slack_deliveries set next_attempt_at='1900-01-01' where feedback_id=job.id;
  select * into job from public.claim_feedback_slack();
  if not public.settle_feedback_slack(job.id,job.claim_token,true,null) then raise exception 'success settlement failed'; end if;
  if public.settle_feedback_slack(job.id,job.claim_token,true,null) then raise exception 'duplicate settlement accepted'; end if;
  if (select email_status from public.app_feedback where id=job.id) <> 'pending' then raise exception 'Slack changed email status'; end if;
  delete from public.profiles where id='user_codex_slack_feedback';
  if exists(select 1 from public.feedback_slack_deliveries where feedback_id=job.id) then raise exception 'purge did not cascade'; end if;
end;
$delivery$;
select pass('private Slack outbox, submitted-only admission, retries, claims, contact context and cascade');
select * from finish();
rollback;
