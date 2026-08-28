-- Keep the public reservation-sync RPC's security posture and grants intact while
-- avoiding a PL/pgSQL variable/column collision in the INSERT conflict target.

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
  occurrence_key_value text;
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
    occurrence_key_value := lower(trim(coalesce(reservation_input->>'occurrence_key', '')));
    provider := lower(trim(coalesce(reservation_input->>'source_provider', '')));
    provider_place_id := trim(coalesce(reservation_input->>'source_provider_place_id', ''));
    canonical_name := trim(coalesce(reservation_input->>'canonical_name', ''));
    event_timezone := trim(coalesce(reservation_input->>'event_timezone', ''));
    reservation_start := (reservation_input->>'start_at')::timestamptz;
    reservation_end := (reservation_input->>'end_at')::timestamptz;

    if occurrence_key_value !~ '^[a-f0-9]{64}$'
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

    occurrence_keys := array_append(occurrence_keys, occurrence_key_value);
    insert into public.calendar_reservations(
      user_id, occurrence_key, source_provider, source_provider_place_id,
      canonical_name, locality, start_at, end_at, event_timezone,
      resolved_place_id, last_seen_at, cancelled_at
    ) values (
      viewer_id, occurrence_key_value, provider, provider_place_id,
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

comment on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz) is
  'Syncs locally detected, resolved calendar reservations without accepting raw calendar content and queues the two-stage prompt waterfall.';

revoke all on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  to authenticated;
