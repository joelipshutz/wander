begin;

-- Slack notifications have independent state. An email outage cannot block
-- receipt or Slack, and adding email later does not reclassify Slack as email.
create table public.feedback_slack_deliveries (
  feedback_id uuid primary key references public.app_feedback(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','sending','sent','failed')),
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  claim_expires_at timestamptz,
  last_error text,
  sent_at timestamptz
);
alter table public.feedback_slack_deliveries enable row level security;
revoke all on public.feedback_slack_deliveries from public, anon, authenticated;
grant select, insert, update, delete on public.feedback_slack_deliveries to service_role;
create index feedback_slack_pending on public.feedback_slack_deliveries(next_attempt_at)
  where status in ('pending','sending');

create function app.enqueue_feedback_slack()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.submitted_at is not null then
    insert into public.feedback_slack_deliveries(feedback_id) values(new.id) on conflict do nothing;
  end if;
  return new;
end;
$$;
revoke all on function app.enqueue_feedback_slack() from public, anon, authenticated;
create trigger app_feedback_enqueue_slack after insert or update of submitted_at on public.app_feedback
  for each row execute function app.enqueue_feedback_slack();
insert into public.feedback_slack_deliveries(feedback_id)
  select id from public.app_feedback where submitted_at is not null;

create function public.claim_feedback_slack()
returns table(id uuid, user_id text, body text, attachments jsonb, app_version text,
  build_number text, submitted_at timestamptz, display_name text, handle text,
  clerk_user_ids jsonb, claim_token uuid)
language plpgsql volatile security definer set search_path = public
as $$
begin
  update public.feedback_slack_deliveries q set status='failed', last_error='delivery_needs_review'
    where q.status in ('pending','sending') and q.attempt_count >= 12
      and (q.claim_expires_at is null or q.claim_expires_at < now());
  return query
  with candidates as (
    select q.feedback_id from public.feedback_slack_deliveries q
      join public.app_feedback f on f.id=q.feedback_id
      join public.profiles p on p.id=f.user_id and p.deleted_at is null
    where f.submitted_at is not null and q.attempt_count < 12
      and ((q.status='pending' and q.next_attempt_at <= now()) or (q.status='sending' and q.claim_expires_at < now()))
    order by q.next_attempt_at for update of q skip locked limit 1
  ), claimed as (
    update public.feedback_slack_deliveries q set status='sending', claim_token=gen_random_uuid(),
      claim_expires_at=now()+interval '5 minutes', attempt_count=q.attempt_count+1
    from candidates c where q.feedback_id=c.feedback_id returning q.feedback_id,q.claim_token
  )
  select f.id,f.user_id,f.body,f.attachments,f.app_version,f.build_number,f.submitted_at,
    p.display_name,p.handle,
    coalesce((select jsonb_agg(m.clerk_user_id) from
      (select mapping.clerk_user_id from public.clerk_identity_mappings mapping
       where mapping.profile_id=f.user_id order by mapping.updated_at desc limit 4) m),'[]'::jsonb),
    c.claim_token
  from claimed c join public.app_feedback f on f.id=c.feedback_id join public.profiles p on p.id=f.user_id;
end;
$$;

create function public.settle_feedback_slack(p_id uuid,p_claim uuid,p_accepted boolean,p_error text)
returns boolean language plpgsql volatile security definer set search_path = public
as $$
begin
  update public.feedback_slack_deliveries q set
    status=case when p_accepted then 'sent' when attempt_count >= 12 then 'failed' else 'pending' end,
    sent_at=case when p_accepted then now() else null end,
    last_error=case when p_accepted then null else left(p_error,64) end,
    next_attempt_at=now()+least(3600,30*power(2,attempt_count)::integer)*interval '1 second',
    claim_token=null,claim_expires_at=null
  where q.feedback_id=p_id and q.claim_token=p_claim and q.status='sending' and q.claim_expires_at > now();
  return found;
end;
$$;
revoke all on function public.claim_feedback_slack() from public,anon,authenticated;
revoke all on function public.settle_feedback_slack(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.claim_feedback_slack() to service_role;
grant execute on function public.settle_feedback_slack(uuid,uuid,boolean,text) to service_role;

-- Remains inert until this dedicated Slack worker secret is configured in Vault.
select cron.schedule('astir-feedback-slack-worker','* * * * *',$schedule$
  with config as (
    select max(decrypted_secret) filter(where name='recme_project_url') as url,
      max(decrypted_secret) filter(where name='astir_feedback_slack_worker_secret') as secret
    from vault.decrypted_secrets
  ) select net.http_post(url:=trim(trailing '/' from url)||'/functions/v1/feedback-slack-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-feedback-worker-secret',secret),
    body:='{}'::jsonb,timeout_milliseconds:=10000) from config where url is not null and secret is not null
$schedule$);
commit;
