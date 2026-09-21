begin;

-- Account creation is already signature-verified and deduplicated by the Clerk
-- webhook. Queue only future inserts; never backfill existing customers.
-- Store account IDs, not email addresses, in the notification outbox.
create table public.signup_slack_deliveries (
  profile_id text primary key,
  event_id text not null references public.clerk_webhook_events(svix_id) on delete cascade,
  signed_up_at timestamptz not null,
  status text not null default 'pending' check(status in ('pending','sending','sent','skipped','failed')),
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  claim_expires_at timestamptz,
  last_error text,
  sent_at timestamptz
);
alter table public.signup_slack_deliveries enable row level security;
revoke all on public.signup_slack_deliveries from public, anon, authenticated;
grant select, insert, update, delete on public.signup_slack_deliveries to service_role;
create index signup_slack_pending on public.signup_slack_deliveries(next_attempt_at)
  where status in ('pending','sending');

-- The event is inserted before its profile, in the same transaction. A profile
-- FK would reject valid new accounts. Deletions cancel via the same event stream.
create function app.enqueue_signup_slack()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.event_type = 'user.created' then
    insert into public.signup_slack_deliveries(profile_id,event_id,signed_up_at)
      values(new.clerk_user_id,new.svix_id,new.event_timestamp) on conflict do nothing;
  elsif new.event_type = 'user.deleted' then
    -- Ignore a stale deletion; the mirror rejects it too.
    delete from public.signup_slack_deliveries where profile_id = new.clerk_user_id
      and not exists(select 1 from public.clerk_profile_mirror_state s
        where s.clerk_user_id=new.clerk_user_id and s.last_event_timestamp > new.event_timestamp);
  end if;
  return new;
end;
$$;
revoke all on function app.enqueue_signup_slack() from public, anon, authenticated;
create trigger clerk_event_enqueue_signup_slack after insert on public.clerk_webhook_events
  for each row execute function app.enqueue_signup_slack();

create function app.purge_signup_slack()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  delete from public.signup_slack_deliveries where profile_id=old.id;
  return old;
end;
$$;
revoke all on function app.purge_signup_slack() from public,anon,authenticated;
create trigger profile_purge_signup_slack after delete on public.profiles
  for each row execute function app.purge_signup_slack();

create function public.claim_signup_slack()
returns table(profile_id text, display_name text, clerk_user_ids jsonb,
  signed_up_at timestamptz, claim_token uuid)
language plpgsql volatile security definer set search_path = public
as $$
begin
  update public.signup_slack_deliveries q set status='failed',last_error='delivery_needs_review'
    where q.status in ('pending','sending') and q.attempt_count >= 12
      and (q.claim_expires_at is null or q.claim_expires_at < now());
  -- A delayed create event must not resurrect a notification for a deleted user.
  update public.signup_slack_deliveries q set status='skipped',last_error='account_deleted'
    where q.status='pending' and exists(select 1 from public.clerk_profile_mirror_state s
      where s.clerk_user_id=q.profile_id and s.last_event_type='user.deleted');
  return query
  with candidates as (
    select q.profile_id from public.signup_slack_deliveries q
      join public.profiles p on p.id=q.profile_id and p.deleted_at is null
    where q.attempt_count < 12
      and ((q.status='pending' and q.next_attempt_at <= now())
        or (q.status='sending' and q.claim_expires_at < now()))
    order by q.next_attempt_at for update of q skip locked limit 5
  ), claimed as (
    update public.signup_slack_deliveries q set status='sending',claim_token=gen_random_uuid(),
      claim_expires_at=now()+interval '5 minutes',attempt_count=q.attempt_count+1
    from candidates c where q.profile_id=c.profile_id returning q.*
  )
  select c.profile_id,p.display_name,
    coalesce((select jsonb_agg(m.clerk_user_id) from
      (select mapping.clerk_user_id from public.clerk_identity_mappings mapping
       where mapping.profile_id=c.profile_id order by mapping.updated_at desc limit 4) m),'[]'::jsonb),
    c.signed_up_at,c.claim_token
  from claimed c join public.profiles p on p.id=c.profile_id;
end;
$$;

create function public.settle_signup_slack(p_id text,p_claim uuid,p_outcome text,p_error text)
returns boolean language plpgsql volatile security definer set search_path = public
as $$
begin
  if p_outcome is null or p_outcome not in ('sent','retry','skipped') then
    raise exception 'invalid_outcome';
  end if;
  update public.signup_slack_deliveries q set
    status=case when p_outcome in ('sent','skipped') then p_outcome
      when attempt_count >= 12 then 'failed' else 'pending' end,
    sent_at=case when p_outcome='sent' then now() else null end,
    last_error=case when p_outcome='sent' then null else left(p_error,64) end,
    next_attempt_at=now()+least(3600,30*power(2,attempt_count)::integer)*interval '1 second',
    claim_token=null,claim_expires_at=null
  where q.profile_id=p_id and q.claim_token=p_claim and q.status='sending' and q.claim_expires_at > now();
  return found;
end;
$$;
revoke all on function public.claim_signup_slack() from public,anon,authenticated;
revoke all on function public.settle_signup_slack(text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.claim_signup_slack() to service_role;
grant execute on function public.settle_signup_slack(text,uuid,text,text) to service_role;

-- Inert until the dedicated worker credential is configured in Vault.
select cron.schedule('astir-signup-slack-worker','* * * * *',$schedule$
  with config as (
    select max(decrypted_secret) filter(where name='recme_project_url') as url,
      max(decrypted_secret) filter(where name='astir_signup_slack_worker_secret') as secret
    from vault.decrypted_secrets
  ) select net.http_post(url:=trim(trailing '/' from url)||'/functions/v1/signup-slack-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-signup-worker-secret',secret),
    body:='{}'::jsonb,timeout_milliseconds:=10000) from config where url is not null and secret is not null
$schedule$);
commit;
