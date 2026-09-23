-- Joe requested username-searchable delivery diagnostics on 2026-09-21.
-- Export only public handles, opaque account identity, preferences and daily counts.
-- Existing content/token/delivery tables remain private and unchanged.
begin;

create function public.notification_recipient_analytics_snapshot(input_window_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
with bounds as (
  select (now() at time zone 'UTC')::date as today,
    least(greatest(coalesce(input_window_days,30),1),30) as days
), recipients as (
  select p.id, p.handle, p.created_at, n.push_enabled,
    jsonb_build_object(
      'social_graph', coalesce(n.social_graph_enabled,false),
      'shared_lists', coalesce(n.shared_lists_enabled,false),
      'recommendations', coalesce(n.recommendations_enabled,false),
      'capture', coalesce(n.capture_enabled,false),
      'discovery_digest', coalesce(n.discovery_digest_enabled,false),
      'followed_activity', coalesce(n.followed_activity_enabled,false),
      'shared_visits', coalesce(n.shared_visits_enabled,false),
      'wanna_go_reminders', coalesce(n.wanna_go_reminders_enabled,false),
      'engagement', coalesce(n.engagement_enabled,false),
      'reservation_reminders', coalesce(n.reservation_reminders_enabled,false)
    ) as preferences,
    (select count(*) from public.notification_device_tokens t
      where t.user_id=p.id and t.is_active and t.environment='production') as active_production_tokens
  from public.profiles p
  left join public.notification_preferences n on n.user_id=p.id
  where p.deleted_at is null and p.id not in (
    'user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc'
  )
), accepted_events as (
  -- Count one notification even if Apple accepted it for several devices.
  select e.id, e.recipient_user_id, min(d.accepted_at) as accepted_at
  from public.notification_events e
  join public.notification_push_deliveries d on d.event_id=e.id and d.status='accepted'
  join public.notification_device_tokens t on t.id=d.token_id and t.environment='production'
  join recipients r on r.id=e.recipient_user_id
  group by e.id,e.recipient_user_id
), daily_accepted as (
  select recipient_user_id, (accepted_at at time zone 'UTC')::date as day, count(*) as accepted
  from accepted_events, bounds
  where accepted_at >= (today-days+1)::timestamp at time zone 'UTC'
  group by recipient_user_id,day
), daily_outcomes as (
  select e.recipient_user_id,
    (case when e.status='failed' then coalesce(e.failed_at,e.updated_at)
      when e.status='skipped' then e.updated_at else e.created_at end at time zone 'UTC')::date as day,
    count(*) filter(where e.status='failed') as failed,
    count(*) filter(where e.status='skipped') as skipped,
    count(*) filter(where e.status in ('pending','claimed')) as pending
  from public.notification_events e join recipients r on r.id=e.recipient_user_id
  where e.status in ('failed','skipped','pending','claimed')
    and not exists(select 1 from accepted_events a where a.id=e.id)
  group by e.recipient_user_id,day
), rows as (
  select r.id as user_id, coalesce(r.handle,'') as username,
    coalesce(r.push_enabled,false) as push_enabled,
    (r.push_enabled is not null) as preferences_known,
    r.active_production_tokens, r.preferences,
    (select jsonb_agg(jsonb_build_object(
      'day', to_char(series.day_at::date,'YYYY-MM-DD'),
      'accepted',coalesce(a.accepted,0), 'failed',coalesce(o.failed,0),
      'skipped',coalesce(o.skipped,0), 'pending',coalesce(o.pending,0)
    ) order by series.day_at)
    from bounds b
    cross join lateral generate_series((b.today-b.days+1)::timestamp,b.today::timestamp,interval '1 day') as series(day_at)
    left join daily_accepted a on a.recipient_user_id=r.id and a.day=series.day_at::date
    left join daily_outcomes o on o.recipient_user_id=r.id and o.day=series.day_at::date
    ) as daily_counts
  from recipients r
)
select jsonb_build_object('snapshot_at',now(),'window_days',(select days from bounds),
  'analytics_audience','external_recipients_v1',
  'recipients',coalesce(jsonb_agg(to_jsonb(rows)),'[]'::jsonb)) from rows;
$$;

revoke all on function public.notification_recipient_analytics_snapshot(integer) from public, anon, authenticated;
grant execute on function public.notification_recipient_analytics_snapshot(integer) to service_role;
comment on function public.notification_recipient_analytics_snapshot(integer) is
  'Service-only username lookup diagnostics: current preferences and daily notification counts, no content, token or notification identifiers. APNs acceptance is not confirmed device delivery.';

-- Refresh independently of notification traffic, including recipients with zero sends.
select cron.schedule('astir-notification-recipient-analytics','*/15 * * * *',$schedule$
  with config as (
    select max(decrypted_secret) filter(where name='recme_project_url') as project_url,
      max(decrypted_secret) filter(where name='recme_push_worker_secret') as worker_secret
    from vault.decrypted_secrets
  )
  select net.http_post(
    url:=trim(trailing '/' from project_url)||'/functions/v1/push-notification-worker',
    headers:=jsonb_build_object('Content-Type','application/json','x-wander-worker-secret',worker_secret),
    body:='{"analytics_snapshot":true}'::jsonb, timeout_milliseconds:=15000
  ) from config where project_url is not null and worker_secret is not null;
$schedule$);
commit;
