begin;

-- Reservation prompts are intentionally grouped by account, resolved provider
-- place, and reservation-local calendar date. The hash keeps queue identifiers
-- bounded without exposing either identifier in operational metadata and keeps
-- the queue's globally unique dedupe key isolated between accounts.
create or replace function app.calendar_reservation_group_key(
  input_recipient_user_id text,
  input_source_provider text,
  input_source_provider_place_id text,
  input_start_at timestamptz,
  input_event_timezone text
)
returns text
language sql
stable
security invoker
set search_path = pg_catalog, extensions
as $$
  select encode(
    extensions.digest(
      trim(coalesce(input_recipient_user_id, ''))
        || chr(31)
        || lower(trim(coalesce(input_source_provider, '')))
        || chr(31)
        || trim(coalesce(input_source_provider_place_id, ''))
        || chr(31)
        || ((input_start_at at time zone input_event_timezone)::date)::text,
      'sha256'
    ),
    'hex'
  )
$$;

comment on function app.calendar_reservation_group_key(text, text, text, timestamptz, text) is
  'Returns an opaque grouping key for one account, provider place, and reservation-local calendar date.';

revoke all on function app.calendar_reservation_group_key(text, text, text, timestamptz, text)
  from public, anon, authenticated;

-- Fold any still-deliverable legacy duplicates before switching the producer to
-- the group key. Terminal history consumes the stage; otherwise the earliest
-- claimed/pending event survives. Rows remain available for delivery audits.
with reservation_events as (
  select
    event.id,
    event.recipient_user_id,
    event.notification_type,
    event.status,
    event.not_before,
    event.created_at,
    app.calendar_reservation_group_key(
      event.recipient_user_id,
      reservation.source_provider,
      reservation.source_provider_place_id,
      reservation.start_at,
      reservation.event_timezone
    ) as reminder_group_key
  from public.notification_events event
  join public.calendar_reservations reservation
    on reservation.user_id = event.recipient_user_id
   and event.data->>'reservation_id' = reservation.id::text
  where event.source = 'calendar_reservation'
    and event.notification_type in (
      'calendar_reservation_live',
      'calendar_reservation_follow_up'
    )
), ranked_events as (
  select
    reservation_events.*,
    bool_or(status not in ('pending', 'claimed')) over (
      partition by recipient_user_id, notification_type, reminder_group_key
    ) as terminal_stage_exists,
    row_number() over (
      partition by recipient_user_id, notification_type, reminder_group_key
      order by
        case status when 'claimed' then 0 when 'pending' then 1 else 2 end,
        not_before,
        created_at,
        id
    ) as stage_rank
  from reservation_events
)
update public.notification_events event
set status = 'skipped',
    skip_reason = case
      when ranked.terminal_stage_exists then 'calendar_reservation_stage_already_consumed'
      else 'calendar_reservation_group_coalesced'
    end,
    failed_at = now(),
    claim_expires_at = null,
    claim_token = null,
    updated_at = now()
from ranked_events ranked
where event.id = ranked.id
  and ranked.status in ('pending', 'claimed')
  and (ranked.terminal_stage_exists or ranked.stage_rank > 1);

-- Point each surviving open legacy event at the earliest active reservation in
-- its group so cancellation of a duplicate occurrence does not invalidate the
-- shared prompt.
with open_events as (
  select
    event.id,
    event.recipient_user_id,
    event.notification_type,
    app.calendar_reservation_group_key(
      event.recipient_user_id,
      reservation.source_provider,
      reservation.source_provider_place_id,
      reservation.start_at,
      reservation.event_timezone
    ) as reminder_group_key
  from public.notification_events event
  join public.calendar_reservations reservation
    on reservation.user_id = event.recipient_user_id
   and event.data->>'reservation_id' = reservation.id::text
  where event.source = 'calendar_reservation'
    and event.status in ('pending', 'claimed')
    and event.notification_type in (
      'calendar_reservation_live',
      'calendar_reservation_follow_up'
    )
), representative_events as (
  select
    open_event.id as event_id,
    open_event.notification_type,
    open_event.reminder_group_key,
    representative.id as reservation_id,
    representative.event_timezone
  from open_events open_event
  join lateral (
    select reservation.id, reservation.event_timezone
    from public.calendar_reservations reservation
    where reservation.user_id = open_event.recipient_user_id
      and reservation.completed_at is null
      and reservation.cancelled_at is null
      and app.calendar_reservation_group_key(
        open_event.recipient_user_id,
        reservation.source_provider,
        reservation.source_provider_place_id,
        reservation.start_at,
        reservation.event_timezone
      ) = open_event.reminder_group_key
    order by reservation.start_at, reservation.id
    limit 1
  ) representative on true
)
update public.notification_events event
set deeplink_url = 'recme://add/reservations/' || representative.reservation_id,
    data = jsonb_build_object(
      'reservation_id', representative.reservation_id,
      'prompt_stage', case representative.notification_type
        when 'calendar_reservation_live' then 'live'
        else 'follow_up'
      end
    ),
    dedupe_key = 'calendar_reservation:'
      || case representative.notification_type
        when 'calendar_reservation_live' then 'live'
        else 'follow_up'
      end
      || ':group:' || representative.reminder_group_key,
    conflict_group = 'calendar_reservation:' || representative.reservation_id,
    recipient_timezone = representative.event_timezone,
    updated_at = now()
from representative_events representative
where event.id = representative.event_id;

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
  reminder_group record;
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
  live_dedupe_key text;
  follow_up_dedupe_key text;
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

  -- Persist the complete input first so grouping is independent of payload order.
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
      cancelled_at = null;
    synced_count := synced_count + 1;
  end loop;

  -- Reconcile removed occurrences before choosing each group's representative.
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

  for reminder_group in
    select distinct app.calendar_reservation_group_key(
      viewer_id,
      reservation.source_provider,
      reservation.source_provider_place_id,
      reservation.start_at,
      reservation.event_timezone
    ) as reminder_group_key
    from public.calendar_reservations reservation
    where reservation.user_id = viewer_id
      and reservation.occurrence_key = any(occurrence_keys)
  loop
    -- Serialize producer runs from multiple devices before inspecting lifetime
    -- history. The first transaction commits the stage before the next checks.
    perform pg_advisory_xact_lock(hashtextextended(
      'calendar-reservation:' || viewer_id || ':' || reminder_group.reminder_group_key,
      0
    ));

    select reservation.* into reservation_row
    from public.calendar_reservations reservation
    where reservation.user_id = viewer_id
      and reservation.completed_at is null
      and reservation.cancelled_at is null
      and app.calendar_reservation_group_key(
        viewer_id,
        reservation.source_provider,
        reservation.source_provider_place_id,
        reservation.start_at,
        reservation.event_timezone
      ) = reminder_group.reminder_group_key
    order by reservation.start_at, reservation.id
    limit 1;

    if reservation_row.id is null then
      continue;
    end if;

    first_prompt_at := reservation_row.start_at + interval '1 hour';
    follow_up_at := (
      date_trunc('day', reservation_row.start_at at time zone reservation_row.event_timezone)
        + interval '1 day 8 hours'
    ) at time zone reservation_row.event_timezone;
    live_dedupe_key := 'calendar_reservation:live:group:'
      || reminder_group.reminder_group_key;
    follow_up_dedupe_key := 'calendar_reservation:follow_up:group:'
      || reminder_group.reminder_group_key;

    -- Keep a surviving open legacy event routable if its original occurrence was
    -- removed while another occurrence in the same group remains.
    update public.notification_events event
    set deeplink_url = 'recme://add/reservations/' || reservation_row.id,
        data = jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'live'
        ),
        dedupe_key = live_dedupe_key,
        conflict_group = 'calendar_reservation:' || reservation_row.id,
        recipient_timezone = reservation_row.event_timezone,
        updated_at = now()
    where event.recipient_user_id = viewer_id
      and event.source = 'calendar_reservation'
      and event.notification_type = 'calendar_reservation_live'
      and event.status in ('pending', 'claimed')
      and (
        event.dedupe_key = live_dedupe_key
        or exists (
          select 1
          from public.calendar_reservations member
          where member.user_id = viewer_id
            and app.calendar_reservation_group_key(
              viewer_id,
              member.source_provider,
              member.source_provider_place_id,
              member.start_at,
              member.event_timezone
            ) = reminder_group.reminder_group_key
            and event.data->>'reservation_id' = member.id::text
        )
      );

    if now() < follow_up_at
       and not exists (
        select 1
        from public.notification_events event
        where event.recipient_user_id = viewer_id
          and event.source = 'calendar_reservation'
          and event.notification_type = 'calendar_reservation_live'
          and (
            event.dedupe_key = live_dedupe_key
            or exists (
              select 1
              from public.calendar_reservations member
              where member.user_id = viewer_id
                and app.calendar_reservation_group_key(
                  viewer_id,
                  member.source_provider,
                  member.source_provider_place_id,
                  member.start_at,
                  member.event_timezone
                ) = reminder_group.reminder_group_key
                and event.data->>'reservation_id' = member.id::text
            )
          )
       )
       and app.queue_notification_intent(
        input_recipient_user_id := viewer_id,
        input_notification_type := 'calendar_reservation_live',
        input_title := 'How’s ' || reservation_row.canonical_name || '?',
        input_body := 'Your take helps friends know if it fits. Check in on rec.me.',
        input_deeplink_url := 'recme://add/reservations/' || reservation_row.id,
        input_data := jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'live'
        ),
        input_dedupe_key := live_dedupe_key,
        input_earliest_at := greatest(first_prompt_at, now()),
        input_latest_at := follow_up_at,
        input_source := 'calendar_reservation',
        input_priority := 70::smallint,
        input_conflict_group := 'calendar_reservation:' || reservation_row.id,
        input_recipient_timezone := reservation_row.event_timezone
      ) is not null then
      queued_count := queued_count + 1;
    end if;

    update public.notification_events event
    set deeplink_url = 'recme://add/reservations/' || reservation_row.id,
        data = jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'follow_up'
        ),
        dedupe_key = follow_up_dedupe_key,
        conflict_group = 'calendar_reservation:' || reservation_row.id,
        recipient_timezone = reservation_row.event_timezone,
        updated_at = now()
    where event.recipient_user_id = viewer_id
      and event.source = 'calendar_reservation'
      and event.notification_type = 'calendar_reservation_follow_up'
      and event.status in ('pending', 'claimed')
      and (
        event.dedupe_key = follow_up_dedupe_key
        or exists (
          select 1
          from public.calendar_reservations member
          where member.user_id = viewer_id
            and app.calendar_reservation_group_key(
              viewer_id,
              member.source_provider,
              member.source_provider_place_id,
              member.start_at,
              member.event_timezone
            ) = reminder_group.reminder_group_key
            and event.data->>'reservation_id' = member.id::text
        )
      );

    if now() < follow_up_at + interval '12 hours'
       and not exists (
        select 1
        from public.notification_events event
        where event.recipient_user_id = viewer_id
          and event.source = 'calendar_reservation'
          and event.notification_type = 'calendar_reservation_follow_up'
          and (
            event.dedupe_key = follow_up_dedupe_key
            or exists (
              select 1
              from public.calendar_reservations member
              where member.user_id = viewer_id
                and app.calendar_reservation_group_key(
                  viewer_id,
                  member.source_provider,
                  member.source_provider_place_id,
                  member.start_at,
                  member.event_timezone
                ) = reminder_group.reminder_group_key
                and event.data->>'reservation_id' = member.id::text
            )
          )
       )
       and app.queue_notification_intent(
        input_recipient_user_id := viewer_id,
        input_notification_type := 'calendar_reservation_follow_up',
        input_title := 'How was ' || reservation_row.canonical_name || '?',
        input_body := 'Save the details while they’re fresh and help your friends know if it fits.',
        input_deeplink_url := 'recme://add/reservations/' || reservation_row.id,
        input_data := jsonb_build_object(
          'reservation_id', reservation_row.id,
          'prompt_stage', 'follow_up'
        ),
        input_dedupe_key := follow_up_dedupe_key,
        input_earliest_at := greatest(follow_up_at, now()),
        input_latest_at := follow_up_at + interval '12 hours',
        input_source := 'calendar_reservation',
        input_priority := 60::smallint,
        input_conflict_group := 'calendar_reservation:' || reservation_row.id,
        input_recipient_timezone := reservation_row.event_timezone
      ) is not null then
      queued_count := queued_count + 1;
    end if;
  end loop;

  -- Any open prompt that was not re-homed to an active representative is no
  -- longer deliverable after this reconciliation.
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
    and not exists (
      select 1
      from public.calendar_reservations reservation
      where reservation.user_id = viewer_id
        and reservation.completed_at is null
        and reservation.cancelled_at is null
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
  'Syncs privacy-minimal calendar reservations and queues each prompt stage at most once per provider place and reservation-local date.';

revoke all on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  to authenticated;

commit;
