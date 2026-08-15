# Product Analytics

Owner: REC-170

Warehouse and dashboard surface: PostHog

Live project: [rec.me / ID 557259](https://us.posthog.com/project/557259)

Live dashboard: [rec.me Product Funnel / ID 1994904](https://us.posthog.com/project/557259/dashboard/1994904)

Account/project registry: `/Users/joelipshutz/Developer/grayline/ops/service-account-registry.json`

Client contract version: `analytics_schema_version=2`

## Why PostHog

The product dashboard lives in PostHog because its funnels, trends, retention drill-down, and event inspector operate directly on the same explicit client events. A second dashboard inside rec.me would duplicate metric logic and require an analytics backend. The dashboard is still code-reviewed and reproducible: `scripts/posthog-product-dashboard.mjs` owns every managed insight and tile.

PostHog autocapture, automatic screen/lifecycle capture, session replay, surveys, error autocapture, default person properties, and GeoIP enrichment remain disabled. Product questions use explicit events only.

## Metric tree

| Section | Question | Definition |
|---|---|---|
| Acquisition | Which channels reach the app? | Unique devices recording `app_first_opened` plus sanitized UTM properties on `acquisition_link_opened`. `direct_or_unknown` is an honest bucket. |
| Activation | Where does onboarding lose people? | Ordered funnel: first open → sign-up start/completion → onboarding start → identity → location → contacts → friends → notifications → completion. |
| Activation | Did a new user reach trusted value? | `onboarding_started` → at least one `follow_created` (during or after onboarding) → `onboarding_completed` → at least one `place_saved`, within 14 days. |
| Engagement | Which human need is the app serving? | Unique users and action volume for `engagement_action_performed`, broken down by `need` and `action`. |
| Retention | Do activated users come back? | Exact D1, D7, D14, and D30 `app_session_started` return after `onboarding_completed`. |
| Referrals | Are users inviting others? | Invite sheet open → delivery start → successful Messages/share-sheet handoff. |
| Monetization | What is the revenue loop? | Intentionally blank until the product has a monetization decision and event contract. |
| Notification Operations | Are remote notifications healthy? | APNs-accepted volume, terminal notification acceptance rate, final device-token disposition, and aggregate remote taps. APNs acceptance is not proof of display. |
| Notification Operations | Are users being over- or under-notified? | Latest 30-day average, p50, p90, maximum, and histogram across notification-eligible recipients, including the zero-notification bucket. |

App Store impressions and downloads do not originate in the app. Reconcile those in App Store Connect when acquisition spend begins. Generic TestFlight links do not support deferred sender/campaign attribution, so referral install, signup, and activation are not claimed by this dashboard. Add those stages only after attributed links exist.

Rollout caveat: the schema-v2 release creates the first-open marker for both new installs and existing installs the first time they launch that build. Establish the acquisition baseline with `build_number`/release-date filters; after that one-time migration, the marker is install-local and emits only once.

## Engagement: human need → action

All engagement activity emits one normalized event:

```text
engagement_action_performed
  need: connect | expression | status
  action: allowlisted action below
  surface: coarse product surface
```

| Human need | Current action values | Product behavior |
|---|---|---|
| Connect | `follow_created`, `activity_liked`, `activity_commented`, `contact_invite_sent`, `shared_visit_invites_queued`, `trusted_profile_viewed` | Build and interact with a trusted people graph. |
| Expression | `place_saved`, `check_in_created`, `list_created`, `recommendation_shared` | Record and communicate personal taste and place memory. |
| Status | `save_streak_advanced`, `shared_visit_accepted`, `own_profile_viewed` | See progress, participation, and the identity created by one’s contributions. |

Status was the blank area in the original card. These are deliberately product-native status signals, not public follower counts or leaderboard mechanics.

## Event contract

Every event receives `analytics_schema_version`, `app_version`, `build_number`, and `platform` from `ContextualAnalyticsClient`.

| Event | When it fires | Allowed product properties |
|---|---|---|
| `app_first_opened` | First launch after the install-local marker is introduced | `acquisition_source` |
| `app_session_started` | Cold launch or foreground return after the app refresh grace period | `session_source` |
| `acquisition_link_opened` | Universal/custom link enters the app | sanitized `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`; coarse `route`; `has_campaign` |
| `onboarding_started` | Onboarding flow first appears | `initial_step`, `is_resumed` |
| `onboarding_step_viewed` | Each onboarding step appears | `step` |
| `onboarding_step_completed` | Each step advances successfully or is explicitly skipped | `step` |
| `onboarding_completed` | Local completion is persisted | `server_confirmed` |
| `follow_created` | Follow is created/queued/synced | `source`, `outcome`, optional aggregate `followed_count` |
| `place_saved` | A new place save is created | `source_type`, `visibility`, `status` |
| `check_in_created` | A visit is created | `is_repeat`, `visibility`, `date_bucket` |
| `activity_like_changed` | Like state succeeds locally/remotely | `is_liked`, `outcome` |
| `activity_comment_created` | Comment succeeds locally/remotely | `outcome` |
| `activity_share_opened` | Share preview opens | `ticket_kind` |
| `activity_share_completed` | A destination completes, hands off, saves, fails, or cancels | `destination`, `outcome` |
| `place_list_created` | A list is created | `visibility`, `collaborator_count` |
| `shared_visit_invites_queued` | Shared-visit invitees are queued | `invitee_count` |
| `shared_visit_accepted` | Shared visit becomes the recipient’s visit | `created_new_place`, `photo_count` |
| `contact_invite_sheet_opened` | Invite sheet opens | `surface` |
| `contact_invite_delivery_started` | Messages/share sheet begins | `surface`, `delivery_mode`, `recipient_count` |
| `contact_invite_completed` | Invite handoff sends, cancels, or fails | `surface`, `delivery_mode`, `outcome`, `sent_count` |
| `notification_opened` | A routable local or remote notification response is accepted once by the authenticated app session | allowlisted `notification_type`; `delivery_channel`; coarse `route` |
| `engagement_action_performed` | Any mapped engagement behavior succeeds | `need`, `action`, `surface`, coarse action-specific counts/outcome |

The push worker also emits three server-side operational events. They use
`platform=server`, `source=push_notification_worker`, and a constant
`distinct_id=notification_operations`; the server analytics path never exports
a recipient identifier.

| Server event | When it fires | Allowed properties |
|---|---|---|
| `notification_delivery_processed` | After the database safely settles one APNs worker pass | allowlisted `notification_type`; `delivery_outcome`; `is_terminal`; attempt number; aggregate accepted/retryable/permanent token counts; coarse `failure_category` |
| `notification_frequency_snapshot` | After a batch with at least one claimed notification | 30-day eligible-recipient count, accepted count, average, p50, p90, and maximum |
| `notification_frequency_bucket_snapshot` | Seven rows emitted with the frequency summary | allowlisted bucket (`0`, `1`, `2-3`, `4-7`, `8-14`, `15-29`, `30+`), bucket order, aggregate recipient count |

“Eligible recipient” means a profile that currently has push enabled and at
least one active device token. The zero bucket is therefore meaningful. The
snapshot RPC performs the per-recipient calculation inside Supabase and returns
only aggregates to the Edge Function/PostHog.

Existing operational events for sync, discovery, permissions, extraction, visibility, and streak reminders remain valid. Never rename an event or property in place: add the replacement, dual-emit for one released build where feasible, update the dashboard, then remove the old event in a later schema version.

## Privacy rules

Analytics must never receive:

- place names, addresses, coordinates, notes, comments, messages, or raw searches;
- names, handles, emails, phone numbers, contact IDs, recipient IDs, invite tokens, or full URLs;
- auth tokens, backend payloads, photos, or private error messages.

Prefer enums, booleans, counts, lengths, coarse error categories, internal build metadata, and opaque authenticated user IDs. `WanderAnalyticsSchema.sanitized` drops known forbidden property keys and truncates values, but that is defense in depth—not permission to create a sensitive property under a different name.

Notification operations are stricter: never export recipient IDs, event IDs,
actor IDs, APNs IDs, device tokens, notification title/body, deep links, or
notification `data` from the server. Keep per-recipient frequency computation
inside Supabase and export only the aggregate summary and fixed histogram.

## Provision the dashboard

The script uses only rec.me-specific credentials. It intentionally does not fall back to generic `POSTHOG_*` variables, because this machine also has credentials for other products.

The live project belongs to the `Grayline Studio` PostHog organization under
Joe's `jolipshutz@gmail.com` Google login. Secret values stay in
`/Users/joelipshutz/.openclaw/workspace/.env.keys`; the cross-project registry
records only env-var references and safe project identifiers.

```bash
cd scripts
npm run analytics:check

export WANDER_POSTHOG_PROJECT_ID='<rec.me project id>'
export WANDER_POSTHOG_PERSONAL_API_KEY='<project-scoped personal API key>'
npm run analytics:apply
```

Optional: set `WANDER_POSTHOG_API_HOST`; the management API defaults to `https://us.posthog.com`. The ingestion host in the iOS app remains `https://us.i.posthog.com`.

The apply command upserts resources tagged `recme:managed` and `recme:iac:*`. Edit the script, not managed PostHog tiles. The checked-in definition includes seven visibly ordered sections: Acquisition, Activation, Engagement, Retention, Referrals, blank Monetization, and bottom-of-dashboard Notification Operations.

## Validation checklist

For every analytics change:

1. Update this event table and the human-need mapping if behavior changes.
2. Add or update unit coverage for name, properties, privacy filtering, and lifecycle cardinality.
3. Run `npm --prefix scripts run analytics:check`.
4. Run the relevant iOS focused tests, then the full Wander test suite before merge.
5. In a non-production/test account, perform the changed action and inspect the PostHog live event. Confirm schema/build properties and confirm private payload values are absent.
6. Re-run `npm --prefix scripts run analytics:apply` if an insight or metric changed, then open every affected tile and verify it returns without a query error.
7. Check volumes after the next TestFlight release. Treat zero events, impossible conversion above 100%, duplicate bursts, or missing build numbers as release blockers for the affected metric.
8. Before uploading a release archive, resolve the app's `Info.plist` and verify
   `WANDER_POSTHOG_PROJECT_TOKEN` is non-empty without printing its value. A
   release worktree does not inherit the ignored `LocalAuth.xcconfig` from any
   other checkout.
9. For notification changes, also run the push-worker Deno tests and
   `supabase/tests/notifications.sql`. Confirm the hosted Edge Function has the
   rec.me-specific `WANDER_POSTHOG_PROJECT_TOKEN` and
   `WANDER_POSTHOG_HOST=https://us.i.posthog.com` secrets before deployment.
10. Trigger one test notification, then verify `notification_delivery_processed`
    and all seven frequency buckets arrive without recipient or content fields.
    Tap it and verify exactly one remote `notification_opened` event.

## Future-agent change rules

- Instrument successful state transitions in the domain/store layer where possible, not button taps that may fail.
- Raw operational events describe the behavior; `engagement_action_performed` answers the stable human-need question. Emit both for a new mapped engagement action.
- Count a share/invite as complete only after a native completion or provider handoff—not when its button is tapped.
- Keep acquisition attribution allowlisted and sanitized. Never capture an incoming URL wholesale.
- Do not fill Monetization speculatively.
- If a feature removes or changes a dashboard event, update the code, tests, this document, and `posthog-product-dashboard.mjs` in the same PR.
- When adding a notification type, update its iOS analytics allowlist and keep
  the server worker payload aggregate-only. Never solve frequency distribution
  by sending recipient IDs or per-recipient rows to PostHog.
