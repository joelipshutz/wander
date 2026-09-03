begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(40);

select is(
  (
    select pg_get_expr(attribute_default.adbin, attribute_default.adrelid)
    from pg_attribute attribute
    join pg_attrdef attribute_default
      on attribute_default.adrelid = attribute.attrelid
     and attribute_default.adnum = attribute.attnum
    where attribute.attrelid = 'public.notification_preferences'::regclass
      and attribute.attname = 'reservation_reminders_enabled'
  ),
  'false',
  'reservation reminders require explicit notification enrollment'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notification_events'
      and column_name = 'source'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'notification_events'
      and column_name = 'latest_at'
  ),
  'notification events carry producer and delivery-window governance fields'
);

select is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'calendar_reservations'
      and column_name in (
        'calendar_event_id', 'title', 'notes', 'attendees', 'url', 'address',
        'raw_location'
      )
  ),
  0,
  'calendar reservation storage has no raw EventKit content columns'
);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.sync_calendar_reservations(jsonb,timestamp with time zone,timestamp with time zone)'::regprocedure
  ),
  'calendar sync is a security-definer RPC with a pinned search path'
);

select ok(
  (
    select not prosecdef
      and provolatile = 's'
      and 'search_path=pg_catalog, extensions' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.calendar_reservation_group_key(text,text,text,timestamp with time zone,text)'::regprocedure
  )
  and not has_function_privilege(
    'authenticated',
    'app.calendar_reservation_group_key(text,text,text,timestamp with time zone,text)',
    'execute'
  ),
  'calendar grouping is a stable internal helper with a pinned search path'
);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.get_calendar_reservation(uuid)'::regprocedure
  ),
  'calendar prompt lookup is a security-definer RPC with a pinned search path'
);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.complete_calendar_reservation(uuid)'::regprocedure
  ),
  'calendar completion is a security-definer RPC with a pinned search path'
);

select ok(
  (
    select prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.reconcile_client_notification_intents(text,jsonb)'::regprocedure
  ),
  'client intent reconciliation is a security-definer RPC with a pinned search path'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.sync_calendar_reservations(jsonb,timestamp with time zone,timestamp with time zone)',
    'execute'
  )
  and not has_function_privilege(
    'anon',
    'public.sync_calendar_reservations(jsonb,timestamp with time zone,timestamp with time zone)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_calendar_reservation(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.complete_calendar_reservation(uuid)',
    'execute'
  )
  and has_function_privilege(
    'authenticated',
    'public.reconcile_client_notification_intents(text,jsonb)',
    'execute'
  ),
  'authenticated owns the public reservation boundary and anon is denied'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'app.queue_notification_intent(text,text,text,text,text,jsonb,text,timestamp with time zone,timestamp with time zone,text,smallint,text,text)',
    'execute'
  )
  and has_function_privilege(
    'service_role',
    'app.queue_notification_intent(text,text,text,text,text,jsonb,text,timestamp with time zone,timestamp with time zone,text,smallint,text,text)',
    'execute'
  ),
  'the generic notification intent writer is not exposed to app clients'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.calendar_reservations'::regclass),
  'calendar reservations enforce RLS'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_calendar_owner', 'calendarowner', 'Calendar Owner'),
  ('user_calendar_stranger', 'calendarstranger', 'Calendar Stranger'),
  ('user_calendar_repeat', 'calendarrepeat', 'Calendar Repeat'),
  ('user_calendar_parallel', 'calendarparallel', 'Calendar Parallel');

insert into public.places (
  canonical_name, category, primary_category, latitude, longitude,
  source_provider, source_provider_place_id, confidence
)
values (
  'Elephante', 'restaurants_food', 'restaurants_food', 34.0141, -118.4976,
  'mapkit', 'calendar-elephante', 1
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_calendar_owner', true);

select is(
  (
    public.update_notification_preferences(
      '{"push_enabled":true,"reservation_reminders_enabled":true,"wanna_go_reminders_enabled":true,"capture_enabled":true}'::jsonb
    )
  ).reservation_reminders_enabled,
  true,
  'the owner can explicitly enable reservation reminders'
);

create temporary table calendar_sync_result as
select public.sync_calendar_reservations(
  jsonb_build_array(jsonb_build_object(
    'occurrence_key', repeat('a', 64),
    'canonical_name', 'Elephante',
    'locality', 'Santa Monica',
    'source_provider', 'mapkit',
    'source_provider_place_id', 'calendar-elephante',
    'start_at', now() + interval '1 day',
    'end_at', now() + interval '1 day 2 hours',
    'event_timezone', 'UTC'
  )),
  now(),
  now() + interval '7 days'
) as payload;

select is(
  (select (payload->>'synced_count')::integer from calendar_sync_result),
  1,
  'calendar sync persists one derived reservation'
);

select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'user_calendar_owner'
      and source = 'calendar_reservation'
      and status = 'pending'
  ),
  2,
  'calendar sync queues both waterfall stages in the central platform'
);

select ok(
  (
    select abs(extract(epoch from (event.not_before - (reservation.start_at + interval '1 hour')))) < 2
    from public.notification_events event
    join public.calendar_reservations reservation
      on event.conflict_group = 'calendar_reservation:' || reservation.id
    where event.notification_type = 'calendar_reservation_live'
      and reservation.user_id = 'user_calendar_owner'
  ),
  'the live prompt begins one hour after the reservation starts'
);

select ok(
  (
    select extract(hour from event.not_before at time zone reservation.event_timezone) = 8
      and (event.not_before at time zone reservation.event_timezone)::date
        = (reservation.start_at at time zone reservation.event_timezone)::date + 1
    from public.notification_events event
    join public.calendar_reservations reservation
      on event.conflict_group = 'calendar_reservation:' || reservation.id
    where event.notification_type = 'calendar_reservation_follow_up'
      and reservation.user_id = 'user_calendar_owner'
  ),
  'the follow-up is scheduled for 8 AM the next reservation-local morning'
);

select ok(
  (
    select event.data ? 'reservation_id'
      and event.data ? 'prompt_stage'
      and (event.data - array['reservation_id', 'prompt_stage']) = '{}'::jsonb
    from public.notification_events event
    where event.notification_type = 'calendar_reservation_live'
      and event.recipient_user_id = 'user_calendar_owner'
  ),
  'calendar notification data contains only the routing id and prompt stage'
);

select ok(
  (
    select event.deeplink_url = 'recme://add/reservations/' || reservation.id
    from public.notification_events event
    join public.calendar_reservations reservation
      on event.conflict_group = 'calendar_reservation:' || reservation.id
    where event.notification_type = 'calendar_reservation_live'
      and reservation.user_id = 'user_calendar_owner'
  ),
  'calendar notification deep links to the owner-scoped prefilled Add route'
);

select is(
  (
    public.get_calendar_reservation(
      (select id from public.calendar_reservations where user_id = 'user_calendar_owner')
    )->>'canonical_name'
  ),
  'Elephante',
  'the owner can resolve the derived reservation prompt'
);

select set_config('request.jwt.claim.sub', 'user_calendar_stranger', true);

select is(
  public.get_calendar_reservation(
    (select id from public.calendar_reservations where user_id = 'user_calendar_owner')
  ),
  null::jsonb,
  'another authenticated account cannot resolve the owner prompt'
);

select is_empty(
  $$ select * from public.calendar_reservations $$,
  'calendar reservation RLS hides another account rows'
);

select set_config('request.jwt.claim.sub', 'user_calendar_owner', true);

select is(
  public.complete_calendar_reservation(
    (select id from public.calendar_reservations where user_id = 'user_calendar_owner')
  ),
  true,
  'the owner can complete a reservation after saving a check-in'
);

select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'user_calendar_owner'
      and source = 'calendar_reservation'
      and status = 'skipped'
  ),
  2,
  'completion suppresses every remaining reservation prompt'
);

select is(
  (
    public.get_calendar_reservation(
      (select id from public.calendar_reservations where user_id = 'user_calendar_owner')
    )->>'is_completed'
  )::boolean,
  true,
  'the prompt lookup reports completion'
);

select is(
  public.complete_calendar_reservation(
    (select id from public.calendar_reservations where user_id = 'user_calendar_owner')
  ),
  false,
  'calendar completion is idempotent'
);

select set_config('request.jwt.claim.sub', 'user_calendar_repeat', true);

select is(
  (
    public.update_notification_preferences(
      '{"push_enabled":true,"reservation_reminders_enabled":true}'::jsonb
    )
  ).reservation_reminders_enabled,
  true,
  'the repeat-sync fixture can receive reservation reminders'
);

create temporary table duplicate_calendar_sync_result as
select public.sync_calendar_reservations(
  jsonb_build_array(
    jsonb_build_object(
      'occurrence_key', repeat('c', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 12 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 14 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    ),
    jsonb_build_object(
      'occurrence_key', repeat('d', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 13 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 15 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    )
  ),
  now(),
  now() + interval '7 days'
) as payload;

select is(
  (
    select (payload->>'synced_count')::integer = 2
      and (payload->>'queued_count')::integer = 2
    from duplicate_calendar_sync_result
  ),
  true,
  'two same-place same-day reservations queue one shared two-stage waterfall'
);

select is(
  (
    select count(*)::integer
    from public.calendar_reservations
    where user_id = 'user_calendar_repeat'
  ),
  2,
  'same-place grouping preserves both privacy-minimal reservation rows'
);

select ok(
  (
    select count(*) = 2
      and count(distinct dedupe_key) = 2
      and bool_and(dedupe_key like 'calendar_reservation:%:group:%')
    from public.notification_events
    where recipient_user_id = 'user_calendar_repeat'
      and source = 'calendar_reservation'
  ),
  'same-place grouping emits only one lifetime key for each prompt stage'
);

select set_config('request.jwt.claim.sub', 'user_calendar_parallel', true);
select public.update_notification_preferences(
  '{"push_enabled":true,"reservation_reminders_enabled":true}'::jsonb
);
select public.sync_calendar_reservations(
  jsonb_build_array(
    jsonb_build_object(
      'occurrence_key', repeat('c', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 12 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 14 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    ),
    jsonb_build_object(
      'occurrence_key', repeat('d', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 13 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 15 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    )
  ),
  now(),
  now() + interval '7 days'
);

reset role;
select ok(
  (
    select count(*) = 4
      and count(distinct dedupe_key) = 4
      and count(*) filter (where recipient_user_id = 'user_calendar_repeat') = 2
      and count(*) filter (where recipient_user_id = 'user_calendar_parallel') = 2
    from public.notification_events
    where recipient_user_id in ('user_calendar_repeat', 'user_calendar_parallel')
      and source = 'calendar_reservation'
  ),
  'same-place same-day waterfalls remain isolated between recipient accounts'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_calendar_repeat', true);

create temporary table calendar_group_rehome_result as
select public.sync_calendar_reservations(
  jsonb_build_array(jsonb_build_object(
    'occurrence_key', repeat('d', 64),
    'canonical_name', 'Elephante',
    'locality', 'Santa Monica',
    'source_provider', 'mapkit',
    'source_provider_place_id', 'calendar-elephante',
    'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 13 hours') at time zone 'UTC',
    'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 15 hours') at time zone 'UTC',
    'event_timezone', 'UTC'
  )),
  now(),
  now() + interval '7 days'
) as payload;

select is(
  (select (payload->>'cancelled_count')::integer from calendar_group_rehome_result),
  1,
  'removing one duplicate occurrence cancels only that reservation row'
);

select ok(
  (
    select count(*) = 2
      and bool_and(
        conflict_group = 'calendar_reservation:' || (
          select id
          from public.calendar_reservations
          where user_id = 'user_calendar_repeat'
            and occurrence_key = repeat('d', 64)
        )
      )
    from public.notification_events
    where recipient_user_id = 'user_calendar_repeat'
      and source = 'calendar_reservation'
      and status = 'pending'
  ),
  'the shared prompts remain pending and route through the active duplicate'
);

reset role;
update public.notification_events
set status = 'sent',
    delivered_at = now(),
    claim_expires_at = null,
    claim_token = null,
    updated_at = now()
where recipient_user_id = 'user_calendar_repeat'
  and source = 'calendar_reservation';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_calendar_repeat', true);

create temporary table terminal_calendar_resync_result as
select public.sync_calendar_reservations(
  jsonb_build_array(jsonb_build_object(
    'occurrence_key', repeat('d', 64),
    'canonical_name', 'Elephante',
    'locality', 'Santa Monica',
    'source_provider', 'mapkit',
    'source_provider_place_id', 'calendar-elephante',
    'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 13 hours') at time zone 'UTC',
    'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 15 hours') at time zone 'UTC',
    'event_timezone', 'UTC'
  )),
  now(),
  now() + interval '7 days'
) as payload;

select is(
  (
    select (payload->>'queued_count')::integer = 0
      and (
        select count(*)
        from public.notification_events
        where recipient_user_id = 'user_calendar_repeat'
          and source = 'calendar_reservation'
      ) = 2
    from terminal_calendar_resync_result
  ),
  true,
  'a foreground sync cannot recreate stages after their events are sent'
);

select public.sync_calendar_reservations(
  jsonb_build_array(
    jsonb_build_object(
      'occurrence_key', repeat('d', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 13 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '2 days 15 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    ),
    jsonb_build_object(
      'occurrence_key', repeat('e', 64),
      'canonical_name', 'Elephante',
      'locality', 'Santa Monica',
      'source_provider', 'mapkit',
      'source_provider_place_id', 'calendar-elephante',
      'start_at', (date_trunc('day', now() at time zone 'UTC') + interval '3 days 12 hours') at time zone 'UTC',
      'end_at', (date_trunc('day', now() at time zone 'UTC') + interval '3 days 14 hours') at time zone 'UTC',
      'event_timezone', 'UTC'
    )
  ),
  now(),
  now() + interval '7 days'
);

select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'user_calendar_repeat'
      and source = 'calendar_reservation'
  ),
  4,
  'the same place on a different local date receives its own two-stage waterfall'
);

select set_config('request.jwt.claim.sub', 'user_calendar_owner', true);

select public.reconcile_client_notification_intents(
  'wanna_go_reminder',
  jsonb_build_array(jsonb_build_object(
    'intent_key', 'wanna-1',
    'title', 'Still wanna go?',
    'body', 'Bavel is on your list.',
    'deeplink_url', 'recme://places/40000000-0000-0000-0000-000000000001',
    'data', jsonb_build_object(
      'place_id', '40000000-0000-0000-0000-000000000001',
      'user_place_id', '50000000-0000-0000-0000-000000000001',
      'planned_date', '2026-09-01'
    ),
    'earliest_at', now() + interval '1 hour',
    'latest_at', now() + interval '25 hours',
    'priority', 40
  ))
);

select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'user_calendar_owner'
      and source = 'wanna_go_reminder'
      and status = 'pending'
  ),
  1,
  'device-owned Wanna reminders reconcile into the central queue'
);

select is(
  (
    select (event.data - array['place_id', 'user_place_id', 'planned_date'])
    from public.notification_events event
    where event.recipient_user_id = 'user_calendar_owner'
      and event.source = 'wanna_go_reminder'
  ),
  '{}'::jsonb,
  'Wanna reconciliation preserves its strict data allowlist'
);

select public.reconcile_client_notification_intents('wanna_go_reminder', '[]'::jsonb);

select is(
  (
    select status
    from public.notification_events
    where recipient_user_id = 'user_calendar_owner'
      and source = 'wanna_go_reminder'
  ),
  'skipped',
  'reconciling an empty plan cancels the stale client intent'
);

select throws_ok(
  $$
    select public.reconcile_client_notification_intents(
      'import_finished',
      '[{
        "intent_key":"import-1",
        "title":"Import ready",
        "body":"Review it",
        "deeplink_url":"https://example.com/private",
        "data":{"batch_ids":[]}
      }]'::jsonb
    )
  $$,
  'P0001',
  'invalid_import_notification_intent',
  'client intent reconciliation rejects an unapproved import deep link'
);

select set_config('request.jwt.claim.sub', 'user_calendar_stranger', true);
select public.update_notification_preferences(
  '{"push_enabled":true,"reservation_reminders_enabled":true}'::jsonb
);
select public.sync_calendar_reservations(
  jsonb_build_array(jsonb_build_object(
    'occurrence_key', repeat('b', 64),
    'canonical_name', 'Elephante',
    'locality', 'Santa Monica',
    'source_provider', 'mapkit',
    'source_provider_place_id', 'calendar-elephante',
    'start_at', now() - interval '2 hours',
    'end_at', now() - interval '1 hour',
    'event_timezone', 'UTC'
  )),
  now() - interval '1 day',
  now() + interval '7 days'
);
select public.update_notification_preferences(
  '{"reservation_reminders_enabled":false}'::jsonb
);

reset role;
set local role service_role;
select public.claim_pending_push_notifications(10);

select is(
  (
    select count(*)::integer
    from public.notification_events
    where recipient_user_id = 'user_calendar_stranger'
      and source = 'calendar_reservation'
      and status = 'skipped'
      and skip_reason = 'notification_preference_disabled'
  ),
  2,
  'claim-time governance rechecks current reservation consent'
);

select is(
  jsonb_array_length(public.claim_pending_push_notifications(10)),
  0,
  'disabled reservation intents are not claimable'
);

select * from finish();

rollback;
