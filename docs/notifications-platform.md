# Notifications Platform

REC-60 establishes the first rec.me push notification pipeline. The immediate contract is intentionally small: app devices register APNs tokens, product code queues notification events, and the Supabase Edge Function claims and sends those events.

## Current Pipeline

1. A signed-in iOS device registers with `public.register_push_token`.
2. Product-side Supabase triggers or service-role jobs call `app.queue_notification_event`.
3. `app.queue_notification_event` checks the recipient profile, self-actions, blocks, preference buckets, and pending dedupe keys. A consented event can wait up to 24 hours for an active token instead of being discarded during a transient registration gap.
4. `push-notification-worker` claims events with `public.claim_pending_push_notifications`, sends APNs payloads, and settles every device independently with `public.record_push_notification_delivery_results`.
5. Retryable device failures return only unfinished tokens to `pending` with backoff. Expired claims are reclaimable, stale claim results are ignored, and exhausted events fail.
6. Supabase Cron invokes the worker once per minute. The cron command reads `recme_project_url` and `recme_push_worker_secret` from Supabase Vault, so no runtime secret is committed to Git.
7. After database settlement, the worker sends only coarse delivery outcomes and
   aggregate 30-day frequency buckets to PostHog. Notification taps emit a
   separate allowlisted `notification_opened` event from iOS.

## Hosted Runtime Configuration

The worker requires these hosted Edge Function secrets:

- `WANDER_WORKER_SECRET`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`
- `APNS_TOPIC` (`com.grayline.wander`)
- `WANDER_POSTHOG_PROJECT_TOKEN` (the rec.me project token)
- `WANDER_POSTHOG_HOST` (`https://us.i.posthog.com`)

Supabase Vault must contain `recme_project_url` and `recme_push_worker_secret`. The worker secret in Vault must match `WANDER_WORKER_SECRET`. Migration `20260712112000_schedule_push_notification_worker.sql` installs the once-per-minute cron job; it does not make an HTTP request until both Vault values exist.

## Testing Baseline

Before relying on a new notification in TestFlight:

- Run the SQL notification tests or hosted rollback harness for `supabase/tests/notifications.sql`.
- Run `deno check` for `supabase/functions/push-notification-worker/index.ts`.
- Run `deno test supabase/functions/push-notification-worker/index.test.ts`.
- Run an iOS build after `xcodegen generate`.
- On a physical iPhone, sign in, open Profile -> Settings -> Notifications, allow notifications, and verify an active `notification_device_tokens` row for the account and APNs environment.
- Trigger one real event, invoke `push-notification-worker`, and confirm the event reaches `sent`.
- Confirm PostHog receives one terminal `notification_delivery_processed`
  event, the frequency summary, and all seven histogram buckets. Tap the push
  once and confirm one remote `notification_opened` event.
- Inspect those events for absence of recipient/event/actor/APNs IDs, device
  tokens, copy, deep links, and payload data.
- Repeat with the relevant preference bucket disabled and confirm no event is queued.

## Followed Place Activity

`followed_place_visit` is queued when a new `place_visits` row represents either an initial visited-place save or a later check-in. It is controlled by the `followed_activity_enabled` preference shown as **People you follow** in Settings. The category is enabled by the explicit one-tap enrollment flow, not by a server-side default.

The producer sends only to followers who can read the associated `user_places` row under its current visibility and block rules. Its copy is `<display name> saved a place` with the canonical place name as the body. The routing payload contains only visit, user-place, place, and actor IDs.

## Permission And Routing

Notification setup is one action in Profile -> Settings -> Notifications. Before setup, every category is shown off and disabled. **Allow notifications** requests iOS permission, enables every category, requests an APNs token, and registers any available stored token. **Disable notifications** turns off every backend category before deactivating the device token; iOS permission may remain granted because apps cannot revoke system permission themselves.

New backend preference rows default every category to off. Existing rows keep their explicit values during schema upgrades. A stored APNs token may be reassigned invisibly to the currently signed-in account to prevent cross-account delivery, but no product event can queue until that account completes **Allow notifications** and enables its categories.

On signed-in launch and foreground maintenance, the app asks APNs for the current environment's token again and upserts it only when both the backend account preference and iOS authorization still allow notifications. Token repair and the durable Shared Visit sender outbox run before profile hydration, so an unrelated profile refresh failure cannot suppress either recovery path. A pending Shared Visit outbox is shown on Map with a manual retry action until the server accepts the reconciliation.

Notification taps resolve as follows:

| Type | Destination |
| --- | --- |
| `followed_you` | Profile -> people -> followers |
| `mutual_follow` | Profile -> people -> friends |
| `list_collaborator_added` | The referenced list detail |
| `list_place_added` | The referenced list detail |
| `place_saved_from_your_map` | The referenced place card on Map |
| `followed_place_visit` | The referenced place card on Map |
| `shared_visit` | The exact pending invitation generation in Save This Place; accepted invitations resolve to the recipient visit and terminal invitations show an unavailable state |
| `capture_ready` | The matching Profile draft, or the drafts section |
| `followed_activity_digest` | Discover |

The app parses `recme.deeplink_url` first and falls back to `notification_type` plus safe routing IDs in `recme.data`. This keeps older queued notifications routable if their URL format changes.

## Shared Visits

`shared_visit` is queued when the owner of a persisted, non-stealth Been visit invites a mutual friend. It is controlled by the **Shared visits** setting, which is enabled with the rest of the categories during explicit notification enrollment. The title is `Shared visit`; the body is `<display name> saved <place> with you. Add your version of the visit.` The payload contains only participant, invitation-generation, group, source-visit, place, and actor IDs.

The deep link is generation-aware. A pending invitation opens a prefilled Save This Place flow; an accepted invitation resolves to the recipient-owned visit; stale, declined, cancelled, or otherwise terminal generations do not expose their old snapshot. Generic `followed_place_visit` delivery waits 30 seconds so a more specific Shared Visit event can supersede it without making the fallback wait multiple worker cycles.

Notification responses are synchronously buffered before the app delegate completion handler returns, drained after auth restoration, and deduplicated by event id. Shared Visit routing distinguishes a terminal missing invitation from a retryable auth/network failure, so a cold-launch tap remains pending and retries when the app becomes active instead of being silently consumed.

Invitation delivery and acceptance are separate guarantees. The sender keeps an account-scoped local outbox until the source visit and all selected source photos are remotely available. The recipient's acceptance uses deterministic client IDs plus a server operation ledger, so foreground retries cannot create duplicate saves or visits.

The local outbox survives app relaunch and retries immediately after the save under a short iOS background task, then again on signed-in launch/foreground. Force-quitting before the first server acknowledgement can still postpone the invitation until the sender next opens rec.me; the Map banner makes that state explicit rather than presenting the local save as fully delivered.

## Adding A Notification

Use this checklist for each new producer:

1. Choose a `notification_type` name and preference bucket.
2. Add the type to the `notification_events.notification_type` check and `app.queue_notification_event` validation.
3. Map the type in `app.notification_type_enabled`.
4. Add one producer function or service-role job that builds title, body, deeplink, safe `data`, and a stable `dedupe_key`.
5. Keep private notes, raw coordinates, auth data, email addresses, and raw private payloads out of `data`.
6. Make self-actions, blocks, missing recipients, and disabled preferences no-op before queueing. Missing active tokens remain pending only for the bounded 24-hour repair window.
7. Add pgTAP coverage for the positive path and at least one no-push path.
8. If the notification needs UI controls, add or reuse a Settings preference bucket.
9. Add the type to the fixed server and iOS analytics allowlists. Do not export
   a recipient identifier or per-recipient row to measure frequency; the
   service-role snapshot RPC must keep that computation inside Supabase.

## Operational Notes

- Default claim lease: 10 minutes.
- Default max attempts: 5.
- Retry backoff: 5 minutes per attempt, capped at 1 hour.
- Automatic delivery cadence: once per minute, up to 20 claimed events per run, processed concurrently with a five-second APNs timeout per device.
- The worker response includes `claimed_count`, a `summary`, and per-event processing results.
- `accepted_at` means APNs accepted the request; it does not prove the device displayed it. The worker stores Apple's `apns-id` for correlation.
- PostHog delivery volume uses the same APNs-acceptance definition. Frequency
  includes notification-enabled users with active tokens who received zero
  accepted notifications, but PostHog receives only summary statistics and
  fixed aggregate buckets.
- Permanent token failures (`BadDeviceToken`, `DeviceTokenNotForTopic`, `ExpiredToken`, or `Unregistered`) deactivate only that token. Payload/topic/provider errors fail the event without deactivating the device. Retryable APNs/transport failures are rescheduled until `max_attempts`.
- Every APNs request uses the notification event id as `apns-collapse-id`. This reduces duplicate presentation if APNs accepts a request but the worker crashes before database settlement; the transport remains at-least-once rather than claiming impossible end-to-end exactly-once delivery.
- Deploy the database migration before the updated worker so the new claim token and per-device settlement RPC exist when the worker starts using them.
