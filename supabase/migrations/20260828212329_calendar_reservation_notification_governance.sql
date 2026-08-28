begin;

-- REC-200 turns the existing push queue into the single production reminder
-- arbiter. Calendar text, notes, attendees, and raw locations never enter this
-- schema; the client sends only a hashed occurrence key and a resolved place.
alter table public.notification_preferences
  add column if not exists reservation_reminders_enabled boolean not null default false;

alter table public.notification_events
  add column if not exists source text not null default 'server',
  add column if not exists priority smallint not null default 50,
  add column if not exists conflict_group text,
  add column if not exists recipient_timezone text,
  add column if not exists latest_at timestamptz;

update public.notification_events
set latest_at = expires_at
where latest_at is null;

alter table public.notification_events
  alter column latest_at set default (now() + interval '24 hours'),
  alter column latest_at set not null,
  drop constraint if exists notification_events_source_length_check,
  drop constraint if exists notification_events_priority_check,
  drop constraint if exists notification_events_conflict_group_length_check,
  drop constraint if exists notification_events_recipient_timezone_length_check,
  drop constraint if exists notification_events_delivery_window_check,
  add constraint notification_events_source_length_check
    check (length(source) between 1 and 64),
  add constraint notification_events_priority_check
    check (priority between 0 and 100),
  add constraint notification_events_conflict_group_length_check
    check (conflict_group is null or length(conflict_group) between 1 and 160),
  add constraint notification_events_recipient_timezone_length_check
    check (recipient_timezone is null or length(recipient_timezone) between 1 and 64),
  add constraint notification_events_delivery_window_check
    check (latest_at >= not_before);

alter table public.notification_events
  drop constraint if exists notification_events_notification_type_check;
alter table public.notification_events
  add constraint notification_events_notification_type_check check (
    notification_type in (
      'followed_you', 'mutual_follow', 'list_collaborator_added',
      'list_place_added', 'place_saved_from_your_map', 'capture_ready',
      'followed_activity_digest', 'followed_place_visit', 'shared_visit',
      'activity_liked', 'activity_commented', 'import_finished',
      'wanna_go_reminder', 'save_streak_reminder',
      'calendar_reservation_live', 'calendar_reservation_follow_up'
    )
  );

create index if not exists notification_events_governance_claim_idx
  on public.notification_events(status, not_before, priority desc, created_at)
  where status in ('pending', 'claimed');

create index if not exists notification_events_recipient_source_idx
  on public.notification_events(recipient_user_id, source, status, created_at desc);

create table if not exists public.calendar_reservations (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.profiles(id) on delete cascade,
  occurrence_key text not null,
  source_provider text not null,
  source_provider_place_id text not null,
  canonical_name text not null,
  locality text,
  start_at timestamptz not null,
  end_at timestamptz not null,
  event_timezone text not null,
  resolved_place_id uuid references public.places(id) on delete set null,
  last_seen_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, occurrence_key),
  check (occurrence_key ~ '^[a-f0-9]{64}$'),
  check (length(source_provider) between 1 and 40),
  check (length(source_provider_place_id) between 1 and 500),
  check (length(canonical_name) between 1 and 120),
  check (locality is null or length(locality) <= 120),
  check (length(event_timezone) between 1 and 64),
  check (end_at > start_at),
  check (completed_at is null or cancelled_at is null)
);

create index if not exists calendar_reservations_user_start_idx
  on public.calendar_reservations(user_id, start_at desc);

create index if not exists calendar_reservations_place_open_idx
  on public.calendar_reservations(user_id, resolved_place_id, start_at desc)
  where completed_at is null and cancelled_at is null;

drop trigger if exists calendar_reservations_set_updated_at
  on public.calendar_reservations;
create trigger calendar_reservations_set_updated_at
  before update on public.calendar_reservations
  for each row execute function app.set_updated_at();

alter table public.calendar_reservations enable row level security;

drop policy if exists "calendar reservations owner readable"
  on public.calendar_reservations;
create policy "calendar reservations owner readable"
  on public.calendar_reservations for select
  to authenticated
  using (user_id = app.current_user_id());

revoke all on table public.calendar_reservations from public, anon, authenticated;
grant select on table public.calendar_reservations to authenticated;
grant select, insert, update, delete on table public.calendar_reservations to service_role;

create or replace function app.notification_type_enabled(
  input_preferences public.notification_preferences,
  input_notification_type text
)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(input_preferences.push_enabled, false)
    and case
      when input_notification_type in ('followed_you', 'mutual_follow') then input_preferences.social_graph_enabled
      when input_notification_type in ('list_collaborator_added', 'list_place_added') then input_preferences.shared_lists_enabled
      when input_notification_type = 'shared_visit' then input_preferences.shared_visits_enabled
      when input_notification_type = 'place_saved_from_your_map' then input_preferences.recommendations_enabled
      when input_notification_type in ('capture_ready', 'import_finished') then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
      when input_notification_type in ('activity_liked', 'activity_commented') then input_preferences.engagement_enabled
      when input_notification_type = 'wanna_go_reminder' then input_preferences.wanna_go_reminders_enabled
      when input_notification_type = 'save_streak_reminder' then true
      when input_notification_type in ('calendar_reservation_live', 'calendar_reservation_follow_up')
        then input_preferences.reservation_reminders_enabled
      else false
    end
$$;

-- Preserve the established nine-argument queue ABI used by existing triggers.
-- New governance metadata is applied by app.queue_notification_intent below.
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
    'activity_liked', 'activity_commented', 'import_finished',
    'wanna_go_reminder', 'save_streak_reminder',
    'calendar_reservation_live', 'calendar_reservation_follow_up'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if length(trim(coalesce(input_title, ''))) not between 1 and 120
     or length(trim(coalesce(input_body, ''))) not between 1 and 240 then
    raise exception 'invalid_notification_copy';
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
    deeplink_url, data, dedupe_key, not_before, expires_at, latest_at
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now()),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours'),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours')
  ) returning id into output_event_id;
  return output_event_id;
end;
$$;

create or replace function app.queue_notification_intent(
  input_recipient_user_id text,
  input_notification_type text,
  input_title text,
  input_body text,
  input_deeplink_url text,
  input_data jsonb,
  input_dedupe_key text,
  input_earliest_at timestamptz,
  input_latest_at timestamptz,
  input_source text,
  input_priority smallint default 50,
  input_conflict_group text default null,
  input_recipient_timezone text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  output_event_id uuid;
  normalized_earliest timestamptz := coalesce(input_earliest_at, now());
  normalized_latest timestamptz := coalesce(input_latest_at, normalized_earliest + interval '24 hours');
begin
  if normalized_latest < normalized_earliest then
    raise exception 'invalid_notification_delivery_window';
  end if;
  if length(trim(coalesce(input_source, ''))) not between 1 and 64 then
    raise exception 'invalid_notification_source';
  end if;
  if input_priority not between 0 and 100 then
    raise exception 'invalid_notification_priority';
  end if;

  output_event_id := app.queue_notification_event(
    input_recipient_user_id := input_recipient_user_id,
    input_actor_user_id := null,
    input_notification_type := input_notification_type,
    input_title := input_title,
    input_body := input_body,
    input_deeplink_url := input_deeplink_url,
    input_data := input_data,
    input_dedupe_key := input_dedupe_key,
    input_not_before := normalized_earliest
  );

  if output_event_id is null then return null; end if;

  update public.notification_events
  set title = left(trim(input_title), 120),
      body = left(trim(input_body), 240),
      deeplink_url = nullif(trim(coalesce(input_deeplink_url, '')), ''),
      data = coalesce(input_data, '{}'::jsonb),
      not_before = normalized_earliest,
      latest_at = normalized_latest,
      expires_at = normalized_latest,
      source = trim(input_source),
      priority = input_priority,
      conflict_group = nullif(trim(coalesce(input_conflict_group, '')), ''),
      recipient_timezone = nullif(trim(coalesce(input_recipient_timezone, '')), ''),
      updated_at = now()
  where id = output_event_id
    and status = 'pending';

  return output_event_id;
end;
$$;

create or replace function public.update_notification_preferences(input_preferences jsonb)
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_preferences public.notification_preferences;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_preferences), '') <> 'object' then
    raise exception 'invalid_notification_preferences_payload';
  end if;

  perform app.ensure_notification_preferences(viewer_id);
  update public.notification_preferences set
    push_enabled = coalesce((input_preferences->>'push_enabled')::boolean, push_enabled),
    social_graph_enabled = coalesce((input_preferences->>'social_graph_enabled')::boolean, social_graph_enabled),
    shared_lists_enabled = coalesce((input_preferences->>'shared_lists_enabled')::boolean, shared_lists_enabled),
    shared_visits_enabled = coalesce((input_preferences->>'shared_visits_enabled')::boolean, shared_visits_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled),
    followed_activity_enabled = coalesce((input_preferences->>'followed_activity_enabled')::boolean, followed_activity_enabled),
    wanna_go_reminders_enabled = coalesce((input_preferences->>'wanna_go_reminders_enabled')::boolean, wanna_go_reminders_enabled),
    engagement_enabled = coalesce((input_preferences->>'engagement_enabled')::boolean, engagement_enabled),
    reservation_reminders_enabled = coalesce((input_preferences->>'reservation_reminders_enabled')::boolean, reservation_reminders_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

-- The authenticated client already computes Wanna/streak times in the user's
-- calendar. It reconciles those plans here so production reminders no longer
-- bypass the shared remote governor. Import completion uses the same RPC as a
-- one-shot source and therefore does not cancel older import events.
create or replace function public.reconcile_client_notification_intents(
  input_source text,
  input_intents jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_source text := lower(trim(coalesce(input_source, '')));
  notification_type text;
  intent jsonb;
  intent_key text;
  intent_data jsonb;
  earliest_at timestamptz;
  latest_at timestamptz;
  queued_ids uuid[] := array[]::uuid[];
  supplied_dedupe_keys text[] := array[]::text[];
  dedupe_key text;
  output_event_id uuid;
  event_already_queued boolean;
  created_count integer := 0;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_intents), '') <> 'array'
     or jsonb_array_length(input_intents) > 100 then
    raise exception 'invalid_notification_intents_payload';
  end if;

  notification_type := case normalized_source
    when 'wanna_go_reminder' then 'wanna_go_reminder'
    when 'save_streak_reminder' then 'save_streak_reminder'
    when 'import_finished' then 'import_finished'
    else null
  end;
  if notification_type is null then raise exception 'invalid_notification_intent_source'; end if;

  for intent in select value from jsonb_array_elements(input_intents)
  loop
    if coalesce(jsonb_typeof(intent), '') <> 'object' then
      raise exception 'invalid_notification_intent';
    end if;
    intent_key := trim(coalesce(intent->>'intent_key', ''));
    if length(intent_key) not between 1 and 160 then
      raise exception 'invalid_notification_intent_key';
    end if;
    intent_data := coalesce(intent->'data', '{}'::jsonb);
    if coalesce(jsonb_typeof(intent_data), '') <> 'object'
       or pg_column_size(intent_data) > 4096 then
      raise exception 'invalid_notification_intent_data';
    end if;

    if normalized_source = 'wanna_go_reminder' then
      if (intent_data - array['place_id', 'user_place_id', 'planned_date']) <> '{}'::jsonb
         or coalesce(intent->>'deeplink_url', '') not like 'recme://places/%' then
        raise exception 'invalid_wanna_go_notification_intent';
      end if;
    elsif normalized_source = 'save_streak_reminder' then
      if (intent_data - array['streak_count', 'copy_variant', 'scheduled_weekday', 'reminder_kind']) <> '{}'::jsonb
         or coalesce(intent->>'deeplink_url', '') <> 'recme://add/here-now' then
        raise exception 'invalid_save_streak_notification_intent';
      end if;
    elsif normalized_source = 'import_finished' then
      if (intent_data - array['batch_ids']) <> '{}'::jsonb
         or coalesce(jsonb_typeof(intent_data->'batch_ids'), '') <> 'array'
         or jsonb_array_length(intent_data->'batch_ids') > 100
         or nullif(trim(coalesce(intent->>'deeplink_url', '')), '') is not null then
        raise exception 'invalid_import_notification_intent';
      end if;
    end if;

    earliest_at := coalesce((intent->>'earliest_at')::timestamptz, now());
    latest_at := coalesce((intent->>'latest_at')::timestamptz, earliest_at + interval '24 hours');
    if earliest_at > now() + interval '400 days'
       or latest_at < earliest_at
       or latest_at > earliest_at + interval '48 hours' then
      raise exception 'invalid_notification_intent_delivery_window';
    end if;

    dedupe_key := 'client:' || viewer_id || ':' || normalized_source || ':' || intent_key;
    supplied_dedupe_keys := array_append(supplied_dedupe_keys, dedupe_key);
    select exists (
      select 1
      from public.notification_events event
      where event.recipient_user_id = viewer_id
        and event.dedupe_key = dedupe_key
        and event.status in ('pending', 'claimed')
    ) into event_already_queued;
    output_event_id := app.queue_notification_intent(
      input_recipient_user_id := viewer_id,
      input_notification_type := notification_type,
      input_title := intent->>'title',
      input_body := intent->>'body',
      input_deeplink_url := intent->>'deeplink_url',
      input_data := intent_data,
      input_dedupe_key := dedupe_key,
      input_earliest_at := earliest_at,
      input_latest_at := latest_at,
      input_source := normalized_source,
      input_priority := coalesce((intent->>'priority')::smallint, 40),
      input_conflict_group := intent->>'conflict_group',
      input_recipient_timezone := intent->>'recipient_timezone'
    );
    if output_event_id is not null then
      queued_ids := array_append(queued_ids, output_event_id);
      if not event_already_queued then
        created_count := created_count + 1;
      end if;
    end if;
  end loop;

  if normalized_source in ('wanna_go_reminder', 'save_streak_reminder') then
    update public.notification_events
    set status = 'skipped',
        skip_reason = 'client_intent_reconciled',
        failed_at = now(),
        claim_expires_at = null,
        claim_token = null,
        updated_at = now()
    where recipient_user_id = viewer_id
      and source = normalized_source
      and status in ('pending', 'claimed')
      and not (dedupe_key = any(supplied_dedupe_keys));
  end if;

  return jsonb_build_object(
    'queued_event_ids', to_jsonb(queued_ids),
    'queued_count', cardinality(queued_ids),
    'created_count', created_count
  );
end;
$$;

create or replace function public.sync_calendar_reservations(
  input_reservations jsonb,
  input_window_start timestamptz,
  input_window_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  reservation_input jsonb;
  reservation_row public.calendar_reservations;
  occurrence_keys text[] := array[]::text[];
  occurrence_key text;
  provider text;
  provider_place_id text;
  canonical_name text;
  event_timezone text;
  reservation_start timestamptz;
  reservation_end timestamptz;
  first_prompt_at timestamptz;
  follow_up_at timestamptz;
  synced_count integer := 0;
  queued_count integer := 0;
  cancelled_count integer := 0;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_reservations), '') <> 'array'
     or jsonb_array_length(input_reservations) > 100 then
    raise exception 'invalid_calendar_reservations_payload';
  end if;
  if input_window_start is null or input_window_end is null
     or input_window_end <= input_window_start
     or input_window_end > input_window_start + interval '190 days' then
    raise exception 'invalid_calendar_reservation_window';
  end if;

  for reservation_input in select value from jsonb_array_elements(input_reservations)
  loop
    if coalesce(jsonb_typeof(reservation_input), '') <> 'object' then
      raise exception 'invalid_calendar_reservation';
    end if;
    occurrence_key := lower(trim(coalesce(reservation_input->>'occurrence_key', '')));
    provider := lower(trim(coalesce(reservation_input->>'source_provider', '')));
    provider_place_id := trim(coalesce(reservation_input->>'source_provider_place_id', ''));
    canonical_name := trim(coalesce(reservation_input->>'canonical_name', ''));
    event_timezone := trim(coalesce(reservation_input->>'event_timezone', ''));
    reservation_start := (reservation_input->>'start_at')::timestamptz;
    reservation_end := (reservation_input->>'end_at')::timestamptz;

    if occurrence_key !~ '^[a-f0-9]{64}$'
       or length(provider) not between 1 and 40
       or length(provider_place_id) not between 1 and 500
       or length(canonical_name) not between 1 and 120
       or length(event_timezone) not between 1 and 64
       or not exists (select 1 from pg_timezone_names where name = event_timezone)
       or reservation_end <= reservation_start
       or reservation_start < input_window_start
       or reservation_start >= input_window_end then
      raise exception 'invalid_calendar_reservation';
    end if;

    occurrence_keys := array_append(occurrence_keys, occurrence_key);
    insert into public.calendar_reservations(
      user_id, occurrence_key, source_provider, source_provider_place_id,
      canonical_name, locality, start_at, end_at, event_timezone,
      resolved_place_id, last_seen_at, cancelled_at
    ) values (
      viewer_id, occurrence_key, provider, provider_place_id,
      canonical_name, nullif(trim(coalesce(reservation_input->>'locality', '')), ''),
      reservation_start, reservation_end, event_timezone,
      (
        select place.id from public.places place
        where place.source_provider = provider
          and place.source_provider_place_id = provider_place_id
        limit 1
      ),
      now(), null
    )
    on conflict (user_id, occurrence_key) do update set
      source_provider = excluded.source_provider,
      source_provider_place_id = excluded.source_provider_place_id,
      canonical_name = excluded.canonical_name,
      locality = excluded.locality,
      start_at = excluded.start_at,
      end_at = excluded.end_at,
      event_timezone = excluded.event_timezone,
      resolved_place_id = coalesce(excluded.resolved_place_id, public.calendar_reservations.resolved_place_id),
      last_seen_at = now(),
      cancelled_at = null
    returning * into reservation_row;
    synced_count := synced_count + 1;

    if reservation_row.completed_at is not null then
      continue;
    end if;

    first_prompt_at := reservation_start + interval '1 hour';
    follow_up_at := (
      date_trunc('day', reservation_start at time zone event_timezone)
        + interval '1 day 8 hours'
    ) at time zone event_timezone;

    if now() < follow_up_at
       and app.queue_notification_intent(
        input_recipient_user_id := viewer_id,
        input_notification_type := 'calendar_reservation_live',
        input_title := 'How’s ' || canonical_name || '?',
        input_body := 'Your take helps friends know if it fits. Check in on rec.me.',
        input_deeplink_url := 'recme://add/reservations/' || reservation_row.id,
        input_data := jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'live'
        ),
        input_dedupe_key := 'calendar_reservation:live:' || reservation_row.id,
        input_earliest_at := greatest(first_prompt_at, now()),
        input_latest_at := follow_up_at,
        input_source := 'calendar_reservation',
        input_priority := 70,
        input_conflict_group := 'calendar_reservation:' || reservation_row.id,
        input_recipient_timezone := event_timezone
      ) is not null then
      queued_count := queued_count + 1;
    end if;

    if now() < follow_up_at + interval '12 hours'
       and app.queue_notification_intent(
        input_recipient_user_id := viewer_id,
        input_notification_type := 'calendar_reservation_follow_up',
        input_title := 'How was ' || canonical_name || '?',
        input_body := 'Save the details while they’re fresh and help your friends know if it fits.',
        input_deeplink_url := 'recme://add/reservations/' || reservation_row.id,
        input_data := jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'follow_up'
        ),
        input_dedupe_key := 'calendar_reservation:follow_up:' || reservation_row.id,
        input_earliest_at := greatest(follow_up_at, now()),
        input_latest_at := follow_up_at + interval '12 hours',
        input_source := 'calendar_reservation',
        input_priority := 60,
        input_conflict_group := 'calendar_reservation:' || reservation_row.id,
        input_recipient_timezone := event_timezone
      ) is not null then
      queued_count := queued_count + 1;
    end if;
  end loop;

  with cancelled as (
    update public.calendar_reservations reservation
    set cancelled_at = now(), updated_at = now()
    where reservation.user_id = viewer_id
      and reservation.completed_at is null
      and reservation.cancelled_at is null
      and reservation.start_at >= input_window_start
      and reservation.start_at < input_window_end
      and not (reservation.occurrence_key = any(occurrence_keys))
    returning reservation.id
  )
  select count(*)::integer into cancelled_count from cancelled;

  update public.notification_events event
  set status = 'skipped',
      skip_reason = 'calendar_reservation_cancelled',
      failed_at = now(),
      claim_expires_at = null,
      claim_token = null,
      updated_at = now()
  where event.recipient_user_id = viewer_id
    and event.source = 'calendar_reservation'
    and event.status in ('pending', 'claimed')
    and exists (
      select 1 from public.calendar_reservations reservation
      where reservation.user_id = viewer_id
        and reservation.cancelled_at is not null
        and event.conflict_group = 'calendar_reservation:' || reservation.id
    );

  return jsonb_build_object(
    'synced_count', synced_count,
    'queued_count', queued_count,
    'cancelled_count', cancelled_count
  );
end;
$$;

create or replace function public.get_calendar_reservation(input_reservation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  reservation_row public.calendar_reservations;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into reservation_row
  from public.calendar_reservations
  where id = input_reservation_id
    and user_id = viewer_id;
  if reservation_row.id is null then return null; end if;

  return jsonb_build_object(
    'id', reservation_row.id,
    'canonical_name', reservation_row.canonical_name,
    'locality', reservation_row.locality,
    'source_provider', reservation_row.source_provider,
    'source_provider_place_id', reservation_row.source_provider_place_id,
    'start_at', reservation_row.start_at,
    'end_at', reservation_row.end_at,
    'event_timezone', reservation_row.event_timezone,
    'resolved_place_id', reservation_row.resolved_place_id,
    'is_completed', reservation_row.completed_at is not null,
    'is_cancelled', reservation_row.cancelled_at is not null
  );
end;
$$;

create or replace function app.finish_calendar_reservation(
  input_reservation_id uuid,
  input_user_id text,
  input_reason text
)
returns boolean
language plpgsql
security definer
set search_path = public, app
as $$
declare
  did_complete boolean;
begin
  update public.calendar_reservations
  set completed_at = coalesce(completed_at, now()),
      cancelled_at = null,
      updated_at = now()
  where id = input_reservation_id
    and user_id = input_user_id
    and completed_at is null
  returning true into did_complete;

  update public.notification_events
  set status = 'skipped',
      skip_reason = left(coalesce(nullif(trim(input_reason), ''), 'calendar_reservation_completed'), 160),
      failed_at = now(),
      claim_expires_at = null,
      claim_token = null,
      updated_at = now()
  where recipient_user_id = input_user_id
    and conflict_group = 'calendar_reservation:' || input_reservation_id
    and status in ('pending', 'claimed');

  return coalesce(did_complete, false);
end;
$$;

create or replace function public.complete_calendar_reservation(input_reservation_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  return app.finish_calendar_reservation(
    input_reservation_id,
    viewer_id,
    'calendar_reservation_completed'
  );
end;
$$;

create or replace function app.complete_calendar_reservation_from_visit()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  visit_owner_id text;
  visit_place_id uuid;
  visit_provider text;
  visit_provider_place_id text;
  reservation_id uuid;
begin
  if new.deleted_at is not null or new.backfilled_from_user_place then return new; end if;

  select user_place.user_id, place.id, place.source_provider, place.source_provider_place_id
  into visit_owner_id, visit_place_id, visit_provider, visit_provider_place_id
  from public.user_places user_place
  join public.places place on place.id = user_place.place_id
  where user_place.id = new.user_place_id
    and user_place.deleted_at is null;

  if visit_owner_id is null then return new; end if;
  for reservation_id in
    select reservation.id
    from public.calendar_reservations reservation
    where reservation.user_id = visit_owner_id
      and reservation.completed_at is null
      and reservation.cancelled_at is null
      and reservation.start_at between new.visited_at - interval '18 hours'
        and new.visited_at + interval '18 hours'
      and (
        reservation.resolved_place_id = visit_place_id
        or (
          reservation.source_provider = visit_provider
          and reservation.source_provider_place_id = visit_provider_place_id
        )
      )
  loop
    perform app.finish_calendar_reservation(
      reservation_id,
      visit_owner_id,
      'calendar_reservation_matching_check_in'
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists complete_calendar_reservation_after_visit
  on public.place_visits;
create trigger complete_calendar_reservation_after_visit
  after insert or update of deleted_at, visited_at on public.place_visits
  for each row execute function app.complete_calendar_reservation_from_visit();

-- Central claim-time governance. Existing events are rechecked against current
-- consent; reservation prompts are also suppressed when their derived intent
-- has completed or been cancelled. Future spacing and quiet-hour rules plug in
-- here without changing product producers.
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
  with disabled_events as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'notification_preference_disabled', error_message = null
    where event.status in ('pending', 'claimed')
      and exists (
        select 1 from public.notification_preferences preferences
        where preferences.user_id = event.recipient_user_id
          and not app.notification_type_enabled(preferences, event.notification_type)
      )
    returning event.id
  ), unavailable_reservations as (
    update public.notification_events event
    set status = 'skipped', failed_at = now(), claim_expires_at = null,
        claim_token = null, skip_reason = 'calendar_reservation_unavailable', error_message = null
    where event.status in ('pending', 'claimed')
      and event.source = 'calendar_reservation'
      and not exists (
        select 1 from public.calendar_reservations reservation
        where reservation.user_id = event.recipient_user_id
          and reservation.completed_at is null
          and reservation.cancelled_at is null
          and event.conflict_group = 'calendar_reservation:' || reservation.id
      )
    returning event.id
  ), muted_events as (
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
    where event.status in ('pending', 'claimed')
      and least(event.expires_at, event.latest_at) <= now()
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
      and least(event.expires_at, event.latest_at) > now()
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
    order by event.priority desc, event.not_before, event.created_at
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
  ) order by updated.priority desc, updated.not_before, updated.created_at), '[]'::jsonb)
  into output_payload
  from updated;

  return output_payload;
end;
$$;

comment on table public.calendar_reservations is
  'Privacy-minimal calendar reservation intents. Raw EventKit title, notes, attendees, URLs, and addresses are never stored.';
comment on column public.notification_events.source is
  'Producer family used by the central delivery governor for reconciliation and future conflict policy.';
comment on column public.notification_events.latest_at is
  'Product delivery deadline. Claim-time governance skips an intent after this instant.';
comment on function public.reconcile_client_notification_intents(text, jsonb) is
  'Reconciles authenticated self-reminders into the central push governor with strict per-source payload allowlists.';
comment on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz) is
  'Syncs locally detected, resolved calendar reservations without accepting raw calendar content and queues the two-stage prompt waterfall.';

revoke all on function app.notification_type_enabled(public.notification_preferences, text)
  from public, anon, authenticated;
revoke all on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz)
  from public, anon, authenticated;
revoke all on function app.queue_notification_intent(text, text, text, text, text, jsonb, text, timestamptz, timestamptz, text, smallint, text, text)
  from public, anon, authenticated;
revoke all on function app.finish_calendar_reservation(uuid, text, text)
  from public, anon, authenticated;
revoke all on function app.complete_calendar_reservation_from_visit()
  from public, anon, authenticated;
revoke all on function app.claim_pending_push_notifications(integer)
  from public, anon, authenticated;

revoke all on function public.reconcile_client_notification_intents(text, jsonb)
  from public, anon, authenticated;
grant execute on function public.reconcile_client_notification_intents(text, jsonb)
  to authenticated;
revoke all on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  to authenticated;
revoke all on function public.get_calendar_reservation(uuid)
  from public, anon, authenticated;
grant execute on function public.get_calendar_reservation(uuid)
  to authenticated;
revoke all on function public.complete_calendar_reservation(uuid)
  from public, anon, authenticated;
grant execute on function public.complete_calendar_reservation(uuid)
  to authenticated;

grant execute on function app.queue_notification_event(text, text, text, text, text, text, jsonb, text, timestamptz)
  to service_role;
grant execute on function app.queue_notification_intent(text, text, text, text, text, jsonb, text, timestamptz, timestamptz, text, smallint, text, text)
  to service_role;
grant execute on function app.claim_pending_push_notifications(integer)
  to service_role;

commit;
