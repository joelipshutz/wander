begin;

alter table public.notification_device_tokens
  add column if not exists deactivated_at timestamptz,
  add column if not exists deactivation_reason text,
  add column if not exists last_delivery_status text,
  add column if not exists last_delivery_error text,
  add column if not exists last_accepted_at timestamptz,
  add column if not exists last_apns_id uuid;

update public.notification_device_tokens
set deactivated_at = coalesce(deactivated_at, updated_at),
    deactivation_reason = coalesce(deactivation_reason, 'legacy_deactivation')
where not is_active;

alter table public.notification_device_tokens
  drop constraint if exists notification_device_tokens_last_delivery_status_check;
alter table public.notification_device_tokens
  add constraint notification_device_tokens_last_delivery_status_check check (
    last_delivery_status is null or last_delivery_status in (
      'accepted', 'retryable_failure', 'permanent_token_failure', 'permanent_event_failure'
    )
  ),
  add constraint notification_device_tokens_deactivation_reason_length_check check (
    deactivation_reason is null or length(deactivation_reason) <= 160
  ),
  add constraint notification_device_tokens_last_delivery_error_length_check check (
    last_delivery_error is null or length(last_delivery_error) <= 500
  );

alter table public.notification_events
  add column if not exists claim_token uuid,
  add column if not exists expires_at timestamptz,
  add column if not exists accepted_at timestamptz;

update public.notification_events
set expires_at = created_at + interval '24 hours'
where expires_at is null;

alter table public.notification_events
  alter column expires_at set default (now() + interval '24 hours'),
  alter column expires_at set not null;

create table if not exists public.notification_push_deliveries (
  event_id uuid not null references public.notification_events(id) on delete cascade,
  token_id uuid not null references public.notification_device_tokens(id) on delete cascade,
  status text not null check (status in (
    'accepted', 'retryable_failure', 'permanent_token_failure', 'permanent_event_failure'
  )),
  attempt_count integer not null default 1 check (attempt_count between 1 and 20),
  last_http_status integer check (last_http_status is null or last_http_status between 100 and 599),
  last_apns_reason text check (last_apns_reason is null or length(last_apns_reason) <= 160),
  last_error_message text check (last_error_message is null or length(last_error_message) <= 500),
  last_apns_id uuid,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (event_id, token_id)
);

create index if not exists notification_push_deliveries_token_idx
  on public.notification_push_deliveries(token_id, updated_at desc);

drop trigger if exists notification_push_deliveries_set_updated_at
  on public.notification_push_deliveries;
create trigger notification_push_deliveries_set_updated_at
  before update on public.notification_push_deliveries
  for each row execute function app.set_updated_at();

alter table public.notification_push_deliveries enable row level security;
revoke all on table public.notification_push_deliveries from public, anon, authenticated;
grant select, insert, update, delete on table public.notification_push_deliveries to service_role;

create or replace function public.register_push_token(
  input_device_token text,
  input_environment text default 'production',
  input_app_bundle_id text default 'com.grayline.wander'
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_device_token, '')));
  normalized_environment text := lower(trim(coalesce(input_environment, 'production')));
  normalized_bundle_id text := coalesce(nullif(trim(input_app_bundle_id), ''), 'com.grayline.wander');
  normalized_token_hash text;
  output_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if normalized_environment not in ('sandbox', 'production') then raise exception 'invalid_push_environment'; end if;
  if length(normalized_token) not between 32 and 512 or normalized_token !~ '^[a-f0-9]+$' then
    raise exception 'invalid_push_token';
  end if;

  normalized_token_hash := encode(extensions.digest(normalized_token, 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('notification-user:' || viewer_id, 0));
  perform pg_advisory_xact_lock(hashtextextended(
    'notification-token:' || normalized_environment || ':' || normalized_bundle_id || ':' || normalized_token_hash,
    0
  ));
  perform app.ensure_notification_preferences(viewer_id);

  update public.notification_device_tokens
  set is_active = false,
      deactivated_at = now(),
      deactivation_reason = 'token_reassigned',
      last_seen_at = now(),
      updated_at = now()
  where environment = normalized_environment
    and app_bundle_id = normalized_bundle_id
    and token_hash = normalized_token_hash
    and user_id <> viewer_id
    and is_active;

  insert into public.notification_device_tokens(
    user_id, platform, environment, app_bundle_id, device_token,
    is_active, last_registered_at, last_seen_at,
    deactivated_at, deactivation_reason
  ) values (
    viewer_id, 'ios', normalized_environment, normalized_bundle_id,
    normalized_token, true, now(), now(), null, null
  )
  on conflict (user_id, platform, environment, token_hash)
  do update set
    app_bundle_id = excluded.app_bundle_id,
    device_token = excluded.device_token,
    is_active = true,
    last_registered_at = now(),
    last_seen_at = now(),
    deactivated_at = null,
    deactivation_reason = null
  returning id into output_id;

  return output_id;
end;
$$;

create or replace function public.unregister_push_token(
  input_device_token text,
  input_environment text default null
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_token text := lower(trim(coalesce(input_device_token, '')));
  normalized_environment text := nullif(lower(trim(coalesce(input_environment, ''))), '');
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;

  update public.notification_device_tokens
  set is_active = false,
      deactivated_at = now(),
      deactivation_reason = 'client_unregistered',
      last_seen_at = now()
  where user_id = viewer_id
    and token_hash = encode(extensions.digest(normalized_token, 'sha256'), 'hex')
    and (normalized_environment is null or environment = normalized_environment);
end;
$$;

create or replace function app.deactivate_push_tokens(
  input_token_ids uuid[],
  input_reason text default null
)
returns integer
language plpgsql
security definer
set search_path = public, app
as $$
declare
  updated_count integer;
begin
  update public.notification_device_tokens
  set is_active = false,
      deactivated_at = now(),
      deactivation_reason = left(coalesce(nullif(trim(input_reason), ''), 'worker_deactivated'), 160),
      last_seen_at = now()
  where id = any(coalesce(input_token_ids, array[]::uuid[]));

  get diagnostics updated_count = row_count;
  return updated_count;
end;
$$;

-- Events are retained while a consented account has no active token. A later
-- launch can repair token registration and make the event claimable before its
-- 24-hour expiry instead of losing the notification at enqueue time.
create or replace function app.queue_notification_event(
  input_recipient_user_id text,
  input_actor_user_id text,
  input_notification_type text,
  input_title text,
  input_body text,
  input_deeplink_url text default null,
  input_data jsonb default '{}'::jsonb,
  input_dedupe_key text default null,
  input_not_before timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  recipient_preferences public.notification_preferences;
  output_event_id uuid;
  actor_is_muted boolean := false;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit',
    'activity_liked', 'activity_commented'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = input_recipient_user_id and profile.deleted_at is null
  ) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (
      select 1 from public.profiles profile
      where profile.id = input_actor_user_id and profile.deleted_at is null
    ) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
    if to_regclass('public.profile_mutes') is not null then
      execute
        'select exists (
           select 1 from public.profile_mutes
           where muter_user_id = $1 and muted_user_id = $2
         )'
      into actor_is_muted
      using input_recipient_user_id, input_actor_user_id;
      if actor_is_muted then return null; end if;
    end if;
  end if;

  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then return null; end if;

  if input_dedupe_key is not null then
    select id into output_event_id
    from public.notification_events
    where dedupe_key = input_dedupe_key and status in ('pending', 'claimed')
    order by created_at desc limit 1;
    if output_event_id is not null then return output_event_id; end if;
  end if;

  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before, expires_at
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now()),
    now() + interval '24 hours'
  ) returning id into output_event_id;
  return output_event_id;
end;
$$;

-- Keep a short supersession window for Shared Visit creation without making a
-- normal follower check-in wait multiple minutes for the once-per-minute worker.
create or replace function app.notify_followed_place_visit_insert()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  activity record;
  follower record;
  actor_name text;
begin
  if new.deleted_at is not null
    or new.backfilled_from_user_place
    or new.visited_at < date_trunc('day', now())
    or new.visited_at > now() then
    return new;
  end if;

  select up.user_id, up.place_id, up.visibility, place.canonical_name,
         profile.display_name, profile.handle
  into activity
  from public.user_places up
  join public.places place on place.id = up.place_id
  join public.profiles profile on profile.id = up.user_id and profile.deleted_at is null
  where up.id = new.user_place_id
    and up.deleted_at is null
    and up.status = 'been';

  if activity.user_id is null then return new; end if;
  actor_name := coalesce(nullif(btrim(activity.display_name), ''), '@' || activity.handle);

  for follower in
    select follow.follower_user_id
    from public.follows follow
    where follow.followed_user_id = activity.user_id
      and app.can_read_user_place(follow.follower_user_id, activity.user_id, activity.visibility)
  loop
    perform app.queue_notification_event(
      input_recipient_user_id := follower.follower_user_id,
      input_actor_user_id := activity.user_id,
      input_notification_type := 'followed_place_visit',
      input_title := actor_name || ' checked in',
      input_body := activity.canonical_name,
      input_deeplink_url := 'recme://places/' || activity.place_id,
      input_data := jsonb_build_object(
        'visit_id', new.id,
        'user_place_id', new.user_place_id,
        'place_id', activity.place_id,
        'actor_user_id', activity.user_id
      ),
      input_dedupe_key := 'followed_place_visit:' || new.id || ':' || follower.follower_user_id,
      input_not_before := now() + interval '30 seconds'
    );
  end loop;
  return new;
end;
$$;

create or replace function app.claim_pending_push_notifications(input_limit integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  bounded_limit integer := least(greatest(coalesce(input_limit, 10), 1), 20);
  output_payload jsonb;
begin
  with muted_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'actor_muted', error_message = null
    where event.status in ('pending', 'claimed')
      and event.actor_user_id is not null
      and exists (
        select 1 from public.profile_mutes muted
        where muted.muter_user_id = event.recipient_user_id
          and muted.muted_user_id = event.actor_user_id
      )
    returning event.id
  ), expired_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'notification_expired', error_message = null
    where event.status in ('pending', 'claimed') and event.expires_at <= now()
    returning event.id
  ), exhausted_claims as (
    update public.notification_events event
    set status = 'failed', failed_at = now(), claim_expires_at = null,
        claim_token = null,
        error_message = coalesce(nullif(event.error_message, ''), 'push_claim_expired_max_attempts')
    where event.status = 'claimed'
      and event.claim_expires_at <= now()
      and event.attempt_count >= event.max_attempts
    returning event.id
  ), claimable as (
    select event.id
    from public.notification_events event
    where (
        (event.status = 'pending' and event.not_before <= now())
        or (event.status = 'claimed' and event.claim_expires_at <= now())
      )
      and event.expires_at > now()
      and event.attempt_count < event.max_attempts
      and exists (
        select 1
        from public.notification_device_tokens token
        where token.user_id = event.recipient_user_id
          and token.is_active
          and not exists (
            select 1
            from public.notification_push_deliveries delivery
            where delivery.event_id = event.id
              and delivery.token_id = token.id
              and delivery.status in (
                'accepted', 'permanent_token_failure', 'permanent_event_failure'
              )
          )
      )
      and not exists (
        select 1 from public.profile_mutes muted
        where muted.muter_user_id = event.recipient_user_id
          and muted.muted_user_id = event.actor_user_id
      )
    order by event.created_at
    for update skip locked
    limit bounded_limit
  ), updated as (
    update public.notification_events event
    set status = 'claimed',
        claimed_at = now(),
        claim_expires_at = now() + interval '10 minutes',
        claim_token = gen_random_uuid(),
        attempt_count = event.attempt_count + 1,
        last_attempted_at = now()
    from claimable
    where event.id = claimable.id
    returning event.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'event_id', updated.id,
    'claim_token', updated.claim_token,
    'recipient_user_id', updated.recipient_user_id,
    'actor_user_id', updated.actor_user_id,
    'notification_type', updated.notification_type,
    'title', updated.title,
    'body', updated.body,
    'deeplink_url', updated.deeplink_url,
    'data', updated.data,
    'attempt_count', updated.attempt_count,
    'max_attempts', updated.max_attempts,
    'claim_expires_at', updated.claim_expires_at,
    'tokens', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', token.id,
        'device_token', token.device_token,
        'environment', token.environment,
        'app_bundle_id', token.app_bundle_id
      ) order by token.last_seen_at desc)
      from public.notification_device_tokens token
      where token.user_id = updated.recipient_user_id
        and token.is_active
        and not exists (
          select 1
          from public.notification_push_deliveries delivery
          where delivery.event_id = updated.id
            and delivery.token_id = token.id
            and delivery.status in (
              'accepted', 'permanent_token_failure', 'permanent_event_failure'
            )
        )
    ), '[]'::jsonb)
  ) order by updated.created_at), '[]'::jsonb)
  into output_payload
  from updated;

  return output_payload;
end;
$$;

create or replace function app.record_push_notification_delivery_results(
  input_event_id uuid,
  input_claim_token uuid,
  input_results jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  event_row public.notification_events;
  accepted_count integer;
  retryable_count integer;
  permanent_token_count integer;
  permanent_event_count integer;
  active_unfinished_count integer;
  next_status text;
  retry_delay_seconds integer;
begin
  if coalesce(jsonb_typeof(input_results), '') <> 'array'
     or jsonb_array_length(input_results) > 100 then
    raise exception 'invalid_push_delivery_results';
  end if;

  select * into event_row
  from public.notification_events
  where id = input_event_id
    and status = 'claimed'
    and claim_token = input_claim_token
  for update;

  if event_row.id is null then
    return jsonb_build_object('status', 'stale_claim');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'notification-user:' || event_row.recipient_user_id,
    0
  ));

  if exists (
    select 1
    from jsonb_array_elements(input_results) result
    where coalesce(result->>'token_id', '') !~
            '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
       or result->>'status' not in (
            'accepted', 'retryable_failure', 'permanent_token_failure', 'permanent_event_failure'
          )
       or length(coalesce(result->>'apns_reason', '')) > 160
       or length(coalesce(result->>'error_message', '')) > 500
  ) then
    raise exception 'invalid_push_delivery_result';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(input_results) result
    left join public.notification_device_tokens token
      on token.id = (result->>'token_id')::uuid
     and token.user_id = event_row.recipient_user_id
    where token.id is null
  ) then
    raise exception 'push_delivery_token_recipient_mismatch';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(input_results) result
    group by result->>'token_id'
    having count(*) > 1
  ) then
    raise exception 'duplicate_push_delivery_token_result';
  end if;

  insert into public.notification_push_deliveries(
    event_id, token_id, status, attempt_count, last_http_status,
    last_apns_reason, last_error_message, last_apns_id, accepted_at
  )
  select
    event_row.id,
    (result->>'token_id')::uuid,
    result->>'status',
    1,
    case when result ? 'http_status' then (result->>'http_status')::integer end,
    nullif(result->>'apns_reason', ''),
    nullif(result->>'error_message', ''),
    case
      when coalesce(result->>'apns_id', '') ~
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
      then (result->>'apns_id')::uuid
    end,
    case when result->>'status' = 'accepted' then now() end
  from jsonb_array_elements(input_results) result
  on conflict (event_id, token_id) do update set
    status = excluded.status,
    attempt_count = least(20, public.notification_push_deliveries.attempt_count + 1),
    last_http_status = excluded.last_http_status,
    last_apns_reason = excluded.last_apns_reason,
    last_error_message = excluded.last_error_message,
    last_apns_id = excluded.last_apns_id,
    accepted_at = coalesce(public.notification_push_deliveries.accepted_at, excluded.accepted_at);

  update public.notification_device_tokens token
  set is_active = case
        when result.status = 'permanent_token_failure' then false
        else token.is_active
      end,
      deactivated_at = case
        when result.status = 'permanent_token_failure' then now()
        else token.deactivated_at
      end,
      deactivation_reason = case
        when result.status = 'permanent_token_failure'
          then left(coalesce(result.apns_reason, 'apns_permanent_token_failure'), 160)
        else token.deactivation_reason
      end,
      last_delivery_status = result.status,
      last_delivery_error = left(result.error_message, 500),
      last_accepted_at = case
        when result.status = 'accepted' then now()
        else token.last_accepted_at
      end,
      last_apns_id = result.apns_id,
      last_seen_at = now()
  from (
    select
      (item->>'token_id')::uuid as token_id,
      item->>'status' as status,
      nullif(item->>'apns_reason', '') as apns_reason,
      nullif(item->>'error_message', '') as error_message,
      case
        when coalesce(item->>'apns_id', '') ~
          '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'
        then (item->>'apns_id')::uuid
      end as apns_id
    from jsonb_array_elements(input_results) item
  ) result
  where token.id = result.token_id;

  select
    count(*) filter (where status = 'accepted'),
    count(*) filter (where status = 'retryable_failure'),
    count(*) filter (where status = 'permanent_token_failure'),
    count(*) filter (where status = 'permanent_event_failure')
  into accepted_count, retryable_count, permanent_token_count, permanent_event_count
  from public.notification_push_deliveries
  where event_id = event_row.id;

  select count(*) into active_unfinished_count
  from public.notification_device_tokens token
  where token.user_id = event_row.recipient_user_id
    and token.is_active
    and not exists (
      select 1
      from public.notification_push_deliveries delivery
      where delivery.event_id = event_row.id
        and delivery.token_id = token.id
        and delivery.status in (
          'accepted', 'permanent_token_failure', 'permanent_event_failure'
        )
    );

  if active_unfinished_count > 0 then
    next_status := case
      when event_row.attempt_count < event_row.max_attempts then 'pending'
      else 'failed'
    end;
  elsif accepted_count > 0 then
    next_status := 'sent';
  elsif permanent_event_count = 0
        and event_row.attempt_count < event_row.max_attempts
        and event_row.expires_at > now() then
    next_status := 'pending';
  else
    next_status := 'failed';
  end if;
  retry_delay_seconds := least(3600, greatest(30, event_row.attempt_count * 300));

  update public.notification_events
  set status = next_status,
      not_before = case
        when next_status = 'pending' and active_unfinished_count > 0
          then now() + make_interval(secs => retry_delay_seconds)
        when next_status = 'pending' then now()
        else not_before
      end,
      claimed_at = case when next_status = 'pending' then null else claimed_at end,
      claim_expires_at = null,
      claim_token = null,
      accepted_at = case when accepted_count > 0 then coalesce(accepted_at, now()) else accepted_at end,
      delivered_at = case when next_status = 'sent' then coalesce(delivered_at, now()) else delivered_at end,
      failed_at = case when next_status = 'failed' then now() else failed_at end,
      skip_reason = null,
      error_message = case
        when next_status = 'sent' then null
        when next_status = 'pending' and active_unfinished_count > 0
          then 'retryable_token_delivery_failure'
        when next_status = 'pending' then 'awaiting_active_token'
        else 'all_token_deliveries_failed'
      end
  where id = event_row.id;

  return jsonb_build_object(
    'status', next_status,
    'accepted_count', accepted_count,
    'retryable_count', retryable_count,
    'permanent_token_failure_count', permanent_token_count,
    'permanent_event_failure_count', permanent_event_count
  );
end;
$$;

create or replace function public.record_push_notification_delivery_results(
  input_event_id uuid,
  input_claim_token uuid,
  input_results jsonb
)
returns jsonb
language sql
security definer
set search_path = app, public
as $$
  select app.record_push_notification_delivery_results(
    input_event_id,
    input_claim_token,
    input_results
  );
$$;

comment on table public.notification_push_deliveries is
  'Per-device APNs acceptance and failure state. Contains token ids and bounded diagnostics, never raw device tokens.';
comment on column public.notification_events.accepted_at is
  'Time at least one APNs request was accepted. APNs acceptance does not prove device presentation.';
comment on function public.record_push_notification_delivery_results(uuid, uuid, jsonb) is
  'Service-role settlement for one claimed event. The claim token rejects stale workers and results are stored per device token.';
comment on function app.notify_followed_place_visit_insert() is
  'Queues privacy-filtered explicit check-in pushes after a 30-second Shared Visit supersession window.';

revoke all on function public.register_push_token(text, text, text) from public, anon;
grant execute on function public.register_push_token(text, text, text) to authenticated;
revoke all on function public.unregister_push_token(text, text) from public, anon;
grant execute on function public.unregister_push_token(text, text) to authenticated;

revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz)
  from public, anon, authenticated;
revoke all on function app.notify_followed_place_visit_insert()
  from public, anon, authenticated;
revoke all on function app.claim_pending_push_notifications(integer)
  from public, anon, authenticated;
grant execute on function app.claim_pending_push_notifications(integer) to service_role;

revoke all on function app.deactivate_push_tokens(uuid[], text)
  from public, anon, authenticated;
grant execute on function app.deactivate_push_tokens(uuid[], text) to service_role;

revoke all on function app.record_push_notification_delivery_results(uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.record_push_notification_delivery_results(uuid, uuid, jsonb)
  from public, anon, authenticated;
grant execute on function app.record_push_notification_delivery_results(uuid, uuid, jsonb)
  to service_role;
grant execute on function public.record_push_notification_delivery_results(uuid, uuid, jsonb)
  to service_role;

commit;
