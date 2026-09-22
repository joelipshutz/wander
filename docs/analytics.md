# Product Analytics

Owner: REC-170

Warehouse and dashboard surface: PostHog

Live project: [rec.me / ID 557259](https://us.posthog.com/project/557259)

Live dashboard: [Astir Launch — Product Behavior / ID 1994904](https://us.posthog.com/project/557259/dashboard/1994904)

Account/project registry: `/Users/joelipshutz/.config/project-secrets/inventory.json` (metadata); scoped access through `~/.local/bin/project-secrets`. Read its README before credentials or account selection.

Client contract version: `analytics_schema_version=3`

Launch audit and rollout gates: [September 19 audit](reviews/2026-09-19-launch-analytics.md).

## Why PostHog

The product dashboard lives in PostHog because its funnels, trends, retention drill-down, and event inspector operate directly on the same explicit client events. A second dashboard inside rec.me would duplicate metric logic and require an analytics backend. The dashboard is still code-reviewed and reproducible: `scripts/posthog-product-dashboard.mjs` owns every managed insight and tile.

PostHog autocapture, automatic screen/lifecycle capture, surveys, error autocapture, default person properties, and GeoIP enrichment remain disabled. Product metrics use explicit events. Session replay is configured separately with on-device masking (REC-582).

## iOS session replay

`PostHogAnalyticsClient.sdkConfiguration` enables replay and the swizzling it requires. SwiftUI uses screenshot mode with text, images, and sandboxed system views masked before upload. Logs and network telemetry remain disabled. Screenshots are throttled to at most one per second; experimental background capture stays off. Existing identify/reset behavior associates recordings with the same opaque user IDs as analytics.

MapKit tiles and pins can reveal locations even with text/image masking enabled. All SwiftUI maps use `sessionReplayMasked()`; the native main map and its container use PostHog's `ph-no-capture` accessibility identifier. Do not unmask private text, photos, maps, contacts, or authentication fields. Masked recordings are intended to show layout and interaction flow, not people's content. Simulator test sessions and native onboarding review fixtures retain their Noop analytics client.

The [project recording switch](https://us.posthog.com/project/557259/settings/project-replay) must also be enabled. Local `sampleRate` remains unset so Mobile recording conditions control sampling remotely; disabling **Record user sessions** is the server-side kill switch. On September 20, 2026, browser inspection confirmed the switch was **off**, with log/network capture configured on behind that disabled switch. Activation is pending native privacy validation; turn log/network capture off when activating replay. This change cannot record sessions from older app builds or recover past sessions.

Before enabling recording and distributing a build:

1. Run `BuildConfigurationTests` and the full native test suite through the shared iOS build helper.
2. With fictional data, verify replay on iOS 26 and an older supported OS. Inspect auth/onboarding, maps, profile, imports, lists, notes/comments, and system photo/contact pickers. Confirm text, images, map tiles/pins and location are concealed. The SDK cautions that manual SwiftUI masking can be inconsistent on iOS 26; configuration assertions alone do not prove visual masking.
3. In project 557259, enable **Record user sessions**, disable console/network capture, and inspect **Mobile** sampling/conditions. Keep the current retention/billing plan. Use a controlled test build first and disable recording again if any masking check fails.
4. Watch a synthetic session in [Session replay](https://us.posthog.com/project/557259/replay/home), verify interaction playback and identity reset on sign-out, and check scrolling/map responsiveness on a physical phone.
5. Reconcile the privacy policy and App Store privacy disclosures with the verified recording behavior before distributing the next app build. Record native build/OS, replay evidence, masking and performance results in REC-582.

## Metric tree

| Section | Question | Definition |
|---|---|---|
| Acquisition | Which channels reach the app? | Unique devices recording `app_first_opened` plus sanitized UTM properties on `acquisition_link_opened`. `direct_or_unknown` is an honest bucket. |
| Activation | Where does onboarding lose people? | Ordered funnel: first open → sign-up start/completion → onboarding start → identity → location → contacts → friends → notifications → completion. |
| Activation | Did a new user create value? | `onboarding_completed` → `core_action_performed` within 14 days. A Wanna or check-in qualifies; following is optional. Local completion is separate from server sync. |
| Engagement | Which human need is the app serving? | Unique users and action volume for `engagement_action_performed`, broken down by `need` and `action`. |
| Retention | Do people return and repeat the core behavior? | Separate weekly cohorts: onboarding → session return, and first observed core action → repeat core action. D1/D7/D14/D30 use elapsed-day windows and a distinct fully matured denominator at each horizon. |
| Referrals | Are users inviting others? | Invite sheet open → delivery start → successful Messages/share-sheet handoff. |
| Monetization | What is the revenue loop? | Intentionally blank until the product has a monetization decision and event contract. |
| Notification Operations | Are remote notifications healthy? | APNs-accepted volume, terminal notification acceptance rate, final device-token disposition, and aggregate remote taps. APNs acceptance is not proof of display. |
| Notification Operations | Are users being over- or under-notified? | Latest 30-day average, p50, p90, maximum, and histogram across notification-eligible recipients, including the zero-notification bucket. |

App Store impressions and downloads do not originate in the app. Reconcile those in App Store Connect when acquisition spend begins. Generic TestFlight links do not support deferred sender/campaign attribution, so referral install, signup, and activation are not claimed by this dashboard. Add those stages only after attributed links exist.

Historical rollout caveat: the schema-v2 release created the first-open marker for both new installs and existing installs the first time they launch that build. Establish the acquisition baseline with `build_number`/release-date filters; after that one-time migration, the marker is install-local and emits only once.

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
| Connect | `follow_created`, `activity_liked`, `activity_comment_liked`, `activity_commented`, `contact_invite_sent`, `shared_visit_invites_queued`, `trusted_profile_viewed`, `place_plan_shared` | Build and interact with a trusted people graph. |
| Expression | `place_saved`, `check_in_created`, `list_created`, `list_place_added`, `recommendation_shared` | Record and communicate personal taste and place memory. |
| Status | `save_streak_advanced`, `shared_visit_accepted`, `own_profile_viewed` | See progress, participation, and the identity created by one’s contributions. |

Status was the blank area in the original card. These are deliberately product-native status signals, not public follower counts or leaderboard mechanics.

## Event contract

Every event receives `analytics_schema_version`, `app_version`, `build_number`, `platform`, and `analytics_environment` from `ContextualAnalyticsClient`. Callers cannot override this context. Debug and simulator events are `development`; Release device builds are `production` (including TestFlight). Authenticated simulator fixtures and native review galleries use a Noop client. The SDK's opaque identify/reset behavior stays unchanged.

Behavioral dashboard queries require schema 3, production, exclusion from the existing Internal / Test users cohort 481950, and absence of a true `$internal_or_test_user` person marker. Native queries also retain the project test-account filter. SQL explicitly excludes the same cohort; update both if the project rule changes. The cohort had zero members on September 19: release staff/review accounts still need classification. Do not infer or assign internal status to unknown users. Existing schema-2 traffic remains available in Data Quality; it is not silently counted as verified launch traffic.

SQL tables use fixed 30-day operational windows and 90-day cohort windows; dashboard date selectors do not alter those SQL literals. Native trends/funnels support normal dashboard filtering. Retention uses merged `person_id`, not raw `distinct_id`. Exact D1 is `[start+24h, start+48h)`; users enter its denominator only at `start+48h`. D7/D14/D30 follow the same rule, return null without eligible users, and show both eligible and returned counts. Cohort weeks use the project's UTC time basis. First observed core action after rollout can belong to an existing user and is not a new-signup claim.

| Event | When it fires | Allowed product properties |
|---|---|---|
| `feedback_submitted` | The server confirms the feedback and attachments are durably queued, once per composer | `surface=profile`, aggregate `photo_count`, `has_voice_note`; never feedback text, attachment names/data, or email |
| `core_action_performed` | Derived once from `place_saved(status=wanna_go)` or `check_in_created`. A new Been save also emits raw `place_saved`; it does not produce a second core event. Edits/retries of an existing Wanna do not qualify. | `action`: `wanna_saved` or `check_in_created`; `completion=local` |
| `save_flow_opened` | Shared editor first appears once per mounted editor, including inline entry | coarse `mode` (`add`, `repeat_check_in`, `shared_visit`, `edit`); initial `status` |
| `save_flow_submitted` | Validated editor submission enters the save operation | `mode`, submitted `status` |
| `save_flow_completed` | Save callback returns in the same account | `mode`, submitted `status`; `outcome` (`synced`, `pending`, `failed`). Pending/local is not confirmed backend persistence. |
| `place_profile_viewed` | Full place profile opens, deduplicated across refreshes of the same mounted place | `surface=place_profile`; no place ID or content |
| `events_interest_submitted` | A non-duplicate Events registration request starts | none |
| `events_interest_result` | Registration returns in the same account | `outcome=confirmed` or `failed`; hydration/cached confirmation does not count as a signup |
| `place_plan_created` | Live In Common invitation creation succeeds and is still valid for the same draft/account | none; this is creation, not delivery |
| `place_plan_share_completed` | Native share completion for the invitation | `outcome=shared` or `not_shared`; the native Boolean completion cannot distinguish cancellation from failure |
| `place_plan_opened` | A recipient invitation successfully loads once per mounted screen | coarse `surface=link` or `notifications`; no invitation token, recipient, location, date, or message |
| `feedback_submitted` | Existing feedback composer successfully submits | `surface=profile`, `photo_count`, `has_voice_note` |
| `app_surface_viewed` | A native tab becomes selected, after yielding to its first render | coarse `surface`: `map`, `discover` (Feed), `events`, `lists`, or `profile`; Events remains a coming-soon teaser |
| `app_first_opened` | First launch after the install-local marker is introduced | `acquisition_source` |
| `app_session_started` | Cold launch or foreground return after the app refresh grace period | `session_source` |
| `acquisition_link_opened` | Universal/custom link enters the app | sanitized `utm_source`, `utm_medium`, `utm_campaign`, `utm_content`; coarse `route`; `has_campaign` |
| `onboarding_started` | Onboarding flow first appears | `initial_step`, `is_resumed` |
| `onboarding_step_viewed` | Each onboarding step appears | `step` |
| `onboarding_step_completed` | Each step advances successfully or is explicitly skipped | `step` |
| `onboarding_completed` | Local completion is persisted | `server_confirmed` |
| `onboarding_identity_submitted` | Required identity and any selected photo finish saving | `photo_selected` |
| `onboarding_identity_failed` | Identity or required-photo submission fails | coarse `reason`, including `photo_save_failed` |
| `onboarding_friend_suggestions_completed` | User continues after explicit per-person actions | aggregate `selected_count`, `followed_count`; both count successful follows in this visit |
| `native_social_auth_result` | A native Apple or Google auth attempt reaches a terminal client outcome | `provider`; `mode`; coarse `result`; `session_adoption`; optional coarse `failure_category` |
| `product_upsell_shown` | A centrally configured upsell becomes visible after its frequency and eligibility gates pass | allowlisted `campaign`, `trigger`, account-scoped `impression_number` |
| `product_upsell_actioned` | The visible upsell is enabled, declined, dismissed, or sends the user to Settings | allowlisted `campaign`, `trigger`, `action`, account-scoped `impression_number` |
| `follow_created` | Follow is created/queued/synced | `source`, `outcome`, optional aggregate `followed_count` |
| `place_import_started` | A pasted import is durably enqueued and the app returns to Map | aggregate `batch_count`, `item_count`, `source_count` |
| `place_import_matching_completed` | Every item in that pasted import finishes local matching | aggregate `batch_count`, `matched_count`, `needs_review_count` |
| `place_saved` | A new place save or independent repeat Wanna is created; retries of the same Wanna do not emit again | `source_type`, `visibility`, `status` |
| `check_in_created` | A visit is created | `is_repeat`, `visibility`, `date_bucket` |
| `activity_like_changed` | Like state succeeds locally/remotely | `is_liked`, `outcome` |
| `activity_comment_like_changed` | Comment like/unlike succeeds locally/remotely | `is_liked`, `outcome`; no comment, activity, author IDs or content |
| `activity_comment_created` | Comment succeeds locally/remotely | `outcome` |
| `activity_share_opened` | Share preview opens | `ticket_kind` |
| `activity_share_completed` | A destination completes, hands off, saves, fails, or cancels | `destination`, `outcome` |
| `place_share_completed` | The native place share sheet completes or cancels | `surface`, `outcome` |
| `place_list_created` | A list is created | `visibility`, `collaborator_count` |
| `place_list_item_added` | A place is successfully added to a list from an instrumented surface (including `map_snapshot` capture and `import` report list actions) | coarse `surface`; `list_role` (`owner` or `collaborator`); `companion_save` (`none`, `created_wanna`, or `existing_wanna`) |
| `shared_visit_invites_queued` | Shared-visit invitees are queued | `invitee_count` |
| `shared_visit_accepted` | Shared visit becomes the recipient’s visit | `created_new_place`, `photo_count` |
| `contact_invite_sheet_opened` | Invite sheet opens | `surface` |
| `contact_invite_delivery_started` | Messages/share sheet begins | `surface`, `delivery_mode`, `recipient_count` |
| `contact_invite_completed` | Invite handoff sends, cancels, or fails | `surface`, `delivery_mode`, `outcome`, `sent_count` |
| `notification_opened` | A routable local/remote notification response is accepted, or a received plan successfully opens from Notifications | allowlisted `notification_type`; `delivery_channel` (`local`, `remote`, `in_app`, `unknown`); coarse `route` |
| `calendar_reservation_sync_completed` | An authorized Apple Calendar scan reconciles privacy-minimal reservation intents with the notification platform | coarse `reason`; detected, resolved, queued, and cancelled counts |
| `engagement_action_performed` | Any mapped engagement behavior succeeds | `need`, `action`, `surface`, coarse action-specific counts/outcome |

The shared add-to-lists picker attributes successful additions to its entry
surface: `map` for Map and place-profile actions, `discover` for Discover search
results, `check_in` for the Add to lists row below Friends in a check-in,
and `wanna` for the visible Add to lists row in a Wanna editor. List additions
from either editor emit once when membership is stored locally;
delivery retries and existing membership do not emit again. Only the existing
coarse properties are sent: `companion_save=none` when the owned place has a
check-in, or `existing_wanna` for an already saved Wanna. Both existing-list selection and new-list creation emit
`place_list_item_added` and the matching `list_place_added` engagement action.

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

Every new Wanna, including repeats at the same place, uses the existing save-streak celebration events. Retrying or editing that record does not emit another save or celebration.

Existing operational events for sync, discovery, permissions, extraction, visibility, and streak reminders remain valid. Never rename an event or property in place: add the replacement, dual-emit for one released build where feasible, update the dashboard, then remove the old event in a later schema version.

Discover place search keeps query text out of analytics. `trusted_place_search_remote_results`
may include `surface`, the allowlisted `provider` (`recme` or `mapkit`), aggregate
result-count and latency buckets, a versioned ranking policy, and rec.me provider
overlap/status counts. `trusted_place_search_result_selected` may include only
`surface`, allowlisted `provider` (`trusted`, `recme`, or `mapkit`), result stage,
and a coarse rank bucket. It must never include the query, place name, provider
place ID, address, coordinates, or contributor identity.

## Privacy rules

Published `/cards/...` links use the same coarse acquisition route as their
canonical entity URL. Their preview token and entity identifier never enter
analytics properties.

Analytics must never receive:

- place names, addresses, coordinates, notes, comments, messages, or raw searches;
- names, handles, emails, phone numbers, contact IDs, recipient IDs, invite tokens, or full URLs;
- auth tokens, backend payloads, photos, or private error messages.

Prefer enums, booleans, counts, lengths, coarse error categories, internal build metadata, and opaque authenticated user IDs. The sanitizer compares forbidden property keys case-insensitively and also blocks token/recipient/error-message aliases. `WanderAnalyticsSchema.sanitized` drops known forbidden property keys and truncates values, but that is defense in depth—not permission to create a sensitive property under a different name.

Apple Calendar analytics is aggregate-only. It must never include calendar event
identifiers, titles, notes, attendees, URLs, addresses, place names, provider
place IDs, reservation IDs, timestamps, or time zones.

Notification operations are stricter: never export recipient IDs, event IDs,
actor IDs, APNs IDs, device tokens, notification title/body, deep links, or
notification `data` from the server. Keep per-recipient frequency computation
inside Supabase and export only the aggregate summary and fixed histogram.

## Provision the dashboard

The script uses only rec.me-specific credentials. It intentionally does not fall back to generic `POSTHOG_*` variables, because this machine also has credentials for other products.

The live project belongs to the `Grayline Studio` PostHog organization under
Joe's `jolipshutz@gmail.com` Google login. Use only the scoped Astir credentials through the private project-secrets helper; never source the mixed-project compatibility env file. The metadata inventory records access scope and verification status. The current API key supports dashboard/insight read and write but not project-settings or direct query access. Saved insights can be refreshed/read through the supported Insights API; no key expansion is needed for that path.

```bash
cd scripts
npm run analytics:check

export WANDER_POSTHOG_PROJECT_ID='<rec.me project id>'
export WANDER_POSTHOG_PERSONAL_API_KEY='<project-scoped personal API key>'
npm run analytics:apply
npm run analytics:verify
# Optional SQL-only arithmetic fixture: creates then soft-deletes an unsaved insight.
npm run analytics:test-retention
```

Optional: set `WANDER_POSTHOG_API_HOST`; the management API defaults to `https://us.posthog.com`. The ingestion host in the iOS app remains `https://us.i.posthog.com`.

The apply command upserts resources tagged `recme:managed` and `recme:iac:*`. Edit the script, not managed PostHog tiles. The checked-in definition includes eight ordered sections: Acquisition, Activation, Engagement, Retention, Referrals, blank Monetization, Data Quality, and bottom-of-dashboard Notification Operations. Managed updates preserve unrelated tiles and existing insight memberships in other dashboards.

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

Place invitation opens from Notifications use `notification_type=place_plan_invitation`, `delivery_channel=in_app`, and `route=place_plan`. Emit only after the recipient resolver succeeds. Reopening is a new open; refreshes and failed/unavailable requests emit nothing. No invitation ID, token, sender, place, date, message, or artwork URL is sent. These in-app opens are excluded from the existing remote push-delivery funnel.
