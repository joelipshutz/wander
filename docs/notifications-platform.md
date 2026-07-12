# Notifications Platform

REC-60 establishes the first rec.me push notification pipeline. The immediate contract is intentionally small: app devices register APNs tokens, product code queues notification events, and the Supabase Edge Function claims and sends those events.

## Current Pipeline

1. A signed-in iOS device registers with `public.register_push_token`.
2. Product-side Supabase triggers or service-role jobs call `app.queue_notification_event`.
3. `app.queue_notification_event` checks the recipient profile, self-actions, blocks, active device tokens, preference buckets, and pending dedupe keys.
4. `push-notification-worker` claims events with `public.claim_pending_push_notifications`, sends APNs payloads, and calls `public.mark_push_notification_result`.
5. Retryable worker failures return events to `pending` with backoff. Expired claims are reclaimable, and exhausted claims fail.
6. Supabase Cron invokes the worker once per minute. The cron command reads `recme_project_url` and `recme_push_worker_secret` from Supabase Vault, so no runtime secret is committed to Git.

## Hosted Runtime Configuration

The worker requires these hosted Edge Function secrets:

- `WANDER_WORKER_SECRET`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`
- `APNS_TOPIC` (`com.grayline.wander`)

Supabase Vault must contain `recme_project_url` and `recme_push_worker_secret`. The worker secret in Vault must match `WANDER_WORKER_SECRET`. Migration `20260712112000_schedule_push_notification_worker.sql` installs the once-per-minute cron job; it does not make an HTTP request until both Vault values exist.

## Testing Baseline

Before relying on a new notification in TestFlight:

- Run the SQL notification tests or hosted rollback harness for `supabase/tests/notifications.sql`.
- Run `deno check` for `supabase/functions/push-notification-worker/index.ts`.
- Run an iOS build after `xcodegen generate`.
- On a physical iPhone, sign in, open Profile -> Settings -> Notifications, allow notifications, and verify an active `notification_device_tokens` row for the account and APNs environment.
- Trigger one real event, invoke `push-notification-worker`, and confirm the event reaches `sent`.
- Repeat with the relevant preference bucket disabled and confirm no event is queued.

## Followed Place Activity

`followed_place_visit` is queued when a new `place_visits` row represents either an initial visited-place save or a later check-in. It is controlled by the default-on `followed_activity_enabled` preference shown as **People you follow** in Settings.

The producer sends only to followers who can read the associated `user_places` row under its current visibility and block rules. Its copy is `<display name> saved a place` with the canonical place name as the body. The routing payload contains only visit, user-place, place, and actor IDs.

## Permission And Routing

Notification setup is one action in Profile -> Settings -> Notifications. Before setup, every category is shown off and disabled. **Allow notifications** requests iOS permission, enables every category, requests an APNs token, and registers any available stored token. **Disable notifications** turns off every backend category before deactivating the device token; iOS permission may remain granted because apps cannot revoke system permission themselves.

Notification taps resolve as follows:

| Type | Destination |
| --- | --- |
| `followed_you` | Profile -> people -> followers |
| `mutual_follow` | Profile -> people -> friends |
| `list_collaborator_added` | The referenced list detail |
| `list_place_added` | The referenced list detail |
| `place_saved_from_your_map` | The referenced place card on Map |
| `followed_place_visit` | The referenced place card on Map |
| `capture_ready` | The matching Profile draft, or the drafts section |
| `followed_activity_digest` | Discover |

The app parses `recme.deeplink_url` first and falls back to `notification_type` plus safe routing IDs in `recme.data`. This keeps older queued notifications routable if their URL format changes.

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
- Automatic delivery cadence: once per minute, up to 100 claimed events per run.
- The worker response includes `claimed_count`, a `summary`, and per-event processing results.
- Permanent APNs token failures deactivate tokens. Retryable APNs/transport failures are rescheduled until `max_attempts`.
