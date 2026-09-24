begin;
do $$
declare job record;
begin
  perform public.mirror_clerk_profile('msg_signup_name_wait','user.created',now(),
    'user_codex_name_wait','generatedhandle','generatedhandle',null);
  update public.signup_slack_deliveries set next_attempt_at='1900-01-01' where profile_id='user_codex_name_wait';
  if exists(select 1 from public.claim_signup_slack() where profile_id='user_codex_name_wait') then
    raise exception 'unfinished onboarding delivered early'; end if;
  if (select attempt_count from public.signup_slack_deliveries where profile_id='user_codex_name_wait') <> 0 then
    raise exception 'waiting consumed a retry'; end if;
  update public.profiles set display_name='Chosen Name',onboarding_completed_at=now() where id='user_codex_name_wait';
  select * into job from public.claim_signup_slack() where profile_id='user_codex_name_wait';
  if job.display_name is distinct from 'Chosen Name' then raise exception 'chosen name not delivered'; end if;
  perform public.settle_signup_slack(job.profile_id,job.claim_token,'sent',null);
  perform public.mirror_clerk_profile('msg_signup_name_timeout','user.created',now()-interval '10 minutes',
    'user_codex_name_timeout','generatedfallback','generatedfallback',null);
  update public.signup_slack_deliveries set next_attempt_at='1900-01-01' where profile_id='user_codex_name_timeout';
  select * into job from public.claim_signup_slack() where profile_id='user_codex_name_timeout';
  if job.profile_id is null or job.display_name is not null then raise exception 'timeout fallback incorrect'; end if;
end;
$$;
rollback;
