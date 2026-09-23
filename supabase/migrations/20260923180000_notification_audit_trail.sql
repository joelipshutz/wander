begin;

-- Service-only outbox: one immutable record per event transition/device attempt.
-- Joe requested recipient and message columns for authenticated support diagnostics.
create table public.notification_delivery_audit (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.notification_events(id) on delete cascade,
  recipient_user_id text not null references public.profiles(id) on delete cascade,
  recorded_at timestamptz not null default clock_timestamp(),
  occurred_at timestamptz not null,
  record_kind text not null,
  status text not null,
  environment text not null,
  attempt_count integer not null,
  notification_type text not null,
  title text not null,
  body text not null,
  reason text,
  http_status integer,
  history_source text not null,
  exported_at timestamptz
);
create index notification_delivery_audit_unexported_idx
  on public.notification_delivery_audit(recorded_at,id) where exported_at is null;
create index notification_delivery_audit_event_idx on public.notification_delivery_audit(event_id,occurred_at);
alter table public.notification_delivery_audit enable row level security;
revoke all on public.notification_delivery_audit from public,anon,authenticated;
grant select on public.notification_delivery_audit to service_role;

-- Only machine reason codes, never transport exceptions containing URLs/tokens.
create function app.notification_audit_reason(value text) returns text
language sql immutable set search_path=public,app as $$
  select case when value is null or value='' then null
    when value=any(array[
      'BadCollapseId','BadDeviceToken','BadExpirationDate','BadMessageId','BadPriority','BadTopic',
      'DeviceTokenNotForTopic','DuplicateHeaders','IdleTimeout','InvalidPushType','MissingDeviceToken',
      'MissingTopic','PayloadEmpty','TopicDisallowed','BadCertificate','BadCertificateEnvironment',
      'ExpiredProviderToken','Forbidden','InvalidProviderToken','MissingProviderToken','BadPath',
      'MethodNotAllowed','Unregistered','PayloadTooLarge','TooManyProviderTokenUpdates','TooManyRequests',
      'InternalServerError','ServiceUnavailable','Shutdown','ExpiredToken',
      'apns_not_configured','push_claim_expired_max_attempts','retryable_token_delivery_failure',
      'awaiting_active_token','all_token_deliveries_failed','actor_muted','notification_expired',
      'push_disabled','category_disabled','no_active_tokens','no_active_device_tokens','recipient_deleted'
    ]) then value else 'transport_or_other_error' end
$$;

create function app.record_notification_event_audit() returns trigger
language plpgsql security definer set search_path=public,app as $$
begin
  if new.recipient_user_id in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc') then return new; end if;
  if tg_op='UPDATE' and (new.status,new.attempt_count,new.skip_reason,new.error_message,new.title,new.body)
    is not distinct from (old.status,old.attempt_count,old.skip_reason,old.error_message,old.title,old.body) then return new; end if;
  insert into public.notification_delivery_audit(event_id,recipient_user_id,occurred_at,record_kind,status,
    environment,attempt_count,notification_type,title,body,reason,history_source)
  values(new.id,new.recipient_user_id,clock_timestamp(),'notification',new.status,'not_applicable',
    new.attempt_count,new.notification_type,new.title,new.body,
    app.notification_audit_reason(coalesce(new.skip_reason,new.error_message)),'live_transition');
  return new;
end $$;

create function app.record_notification_attempt_audit() returns trigger
language plpgsql security definer set search_path=public,app as $$
declare e public.notification_events%rowtype; env text;
begin
  if tg_op='UPDATE' and (new.status,new.attempt_count,new.last_http_status,new.last_apns_reason,new.last_error_message)
    is not distinct from (old.status,old.attempt_count,old.last_http_status,old.last_apns_reason,old.last_error_message) then return new; end if;
  select * into strict e from public.notification_events where id=new.event_id;
  if e.recipient_user_id in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc') then return new; end if;
  select environment into env from public.notification_device_tokens where id=new.token_id;
  insert into public.notification_delivery_audit(event_id,recipient_user_id,occurred_at,record_kind,status,
    environment,attempt_count,notification_type,title,body,reason,http_status,history_source)
  values(e.id,e.recipient_user_id,clock_timestamp(),'device_attempt',new.status,env,new.attempt_count,
    e.notification_type,e.title,e.body,app.notification_audit_reason(coalesce(new.last_apns_reason,new.last_error_message)),
    new.last_http_status,'live_transition');
  return new;
end $$;
revoke all on function app.notification_audit_reason(text),app.record_notification_event_audit(),app.record_notification_attempt_audit() from public,anon,authenticated;

-- Baseline existing records honestly: prior overwritten attempts cannot be reconstructed.
-- Triggers are installed in this transaction, so concurrent writes cannot create a gap.
lock table public.notification_events,public.notification_push_deliveries in share row exclusive mode;
insert into public.notification_delivery_audit(event_id,recipient_user_id,occurred_at,record_kind,status,
  environment,attempt_count,notification_type,title,body,reason,history_source)
select e.id,e.recipient_user_id,e.updated_at,'notification',e.status,'not_applicable',e.attempt_count,
  e.notification_type,e.title,e.body,app.notification_audit_reason(coalesce(e.skip_reason,e.error_message)),'historical_snapshot'
from public.notification_events e join public.profiles p on p.id=e.recipient_user_id
where e.updated_at>=now()-interval '30 days' and p.deleted_at is null
  and e.recipient_user_id not in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc');
insert into public.notification_delivery_audit(event_id,recipient_user_id,occurred_at,record_kind,status,
  environment,attempt_count,notification_type,title,body,reason,http_status,history_source)
select e.id,e.recipient_user_id,d.updated_at,'device_attempt',d.status,t.environment,d.attempt_count,
  e.notification_type,e.title,e.body,app.notification_audit_reason(coalesce(d.last_apns_reason,d.last_error_message)),
  d.last_http_status,'historical_snapshot'
from public.notification_push_deliveries d join public.notification_events e on e.id=d.event_id
join public.notification_device_tokens t on t.id=d.token_id join public.profiles p on p.id=e.recipient_user_id
where d.updated_at>=now()-interval '30 days' and p.deleted_at is null
  and e.recipient_user_id not in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc');
create trigger notification_event_audit after insert or update on public.notification_events
  for each row execute function app.record_notification_event_audit();
create trigger notification_attempt_audit after insert or update on public.notification_push_deliveries
  for each row execute function app.record_notification_attempt_audit();

create function public.notification_audit_export_batch(input_limit integer default 200) returns jsonb
language sql stable security definer set search_path=public,app as $$
select coalesce(jsonb_agg(to_jsonb(rows) order by rows.recorded_at,rows.audit_id),'[]'::jsonb) from (
  select a.id as audit_id,md5(a.event_id::text) as notification_ref,a.recipient_user_id as user_id,
    coalesce(p.handle,'') as username,a.recorded_at,a.occurred_at,a.record_kind,a.status,a.environment,
    a.attempt_count,a.notification_type,a.title,a.body,a.reason,a.http_status,a.history_source
  from public.notification_delivery_audit a join public.profiles p on p.id=a.recipient_user_id
  where a.exported_at is null and p.deleted_at is null
    and a.recipient_user_id not in ('user_3EhATWssjvHxwGiUaoWR5VTgeoy','user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc')
  order by a.recorded_at,a.id limit least(greatest(coalesce(input_limit,200),1),200)
) rows
$$;
create function public.ack_notification_audit_export(input_ids uuid[]) returns void
language sql security definer set search_path=public,app as $$
  update public.notification_delivery_audit set exported_at=now() where id=any(input_ids) and exported_at is null
$$;
revoke all on function public.notification_audit_export_batch(integer),public.ack_notification_audit_export(uuid[]) from public,anon,authenticated;
grant execute on function public.notification_audit_export_batch(integer),public.ack_notification_audit_export(uuid[]) to service_role;
commit;
