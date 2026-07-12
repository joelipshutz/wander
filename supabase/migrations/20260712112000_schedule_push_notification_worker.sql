begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'recme-push-notification-worker',
  '* * * * *',
  $schedule$
    with worker_config as (
      select
        max(decrypted_secret) filter (where name = 'recme_project_url') as project_url,
        max(decrypted_secret) filter (where name = 'recme_push_worker_secret') as worker_secret
      from vault.decrypted_secrets
    )
    select net.http_post(
      url := trim(trailing '/' from project_url) || '/functions/v1/push-notification-worker',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-wander-worker-secret', worker_secret
      ),
      body := '{"limit": 100}'::jsonb,
      timeout_milliseconds := 15000
    ) as request_id
    from worker_config
    where project_url is not null
      and worker_secret is not null
  $schedule$
);

comment on extension pg_cron is 'Runs the REC-60 push delivery worker once per minute.';
comment on extension pg_net is 'Provides asynchronous HTTP delivery for scheduled Supabase Edge Functions.';

commit;
