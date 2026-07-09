# Notifications Platform

REC-60 establishes the first rec.me push notification pipeline. The immediate contract is intentionally small: app devices register APNs tokens, product code queues notification events, and the Supabase Edge Function claims and sends those events.

## Current Pipeline

1. A signed-in iOS device registers with `public.register_push_token`.
2. Product-side Supabase triggers or service-role jobs call `app.queue_notification_event`.
3. `app.queue_notification_event` checks the recipient profile, self-actions, blocks, active device tokens, preference buckets, and pending dedupe keys.
4. `push-notification-worker` claims events with `public.claim_pending_push_notifications`, sends APNs payloads, and calls `public.mark_push_notification_result`.
5. Retryable worker failures return events to `pending` with backoff. Expired claims are reclaimable, and exhausted claims fail.

## Testing Baseline

Before relying on a new notification in TestFlight:

- Run the SQL notification tests or hosted rollback harness for `supabase/tests/notifications.sql`.
- Run `deno check` for `supabase/functions/push-notification-worker/index.ts`.
- Run an iOS build after `xcodegen generate`.
- On a physical iPhone, sign in, open Profile -> Settings -> Notifications, allow notifications, and verify an active `notification_device_tokens` row for the account and APNs environment.
- Trigger one real event, invoke `push-notification-worker`, and confirm the event reaches `sent`.
- Repeat with the relevant preference bucket disabled and confirm no event is queued.

## Adding A Notification

Use this checklist for each new producer:

1. Choose a `notification_type` name and preference bucket.
2. Add the type to the `notification_events.notification_type` check and `app.queue_notification_event` validation.
3. Map the type in `app.notification_type_enabled`.
4. Add one producer function or service-role job that builds title, body, deeplink, safe `data`, and a stable `dedupe_key`.
5. Keep private notes, raw coordinates, auth data, email addresses, and raw private payloads out of `data`.
6. Make self-actions, blocks, missing recipients, missing active tokens, and disabled preferences no-op before queueing.
7. Add pgTAP coverage for the positive path and at least one no-push path.
8. If the notification needs UI controls, add or reuse a Settings preference bucket.

## Operational Notes

- Default claim lease: 10 minutes.
- Default max attempts: 5.
- Retry backoff: 5 minutes per attempt, capped at 1 hour.
- The worker response includes `claimed_count`, a `summary`, and per-event processing results.
- Permanent APNs token failures deactivate tokens. Retryable APNs/transport failures are rescheduled until `max_attempts`.
