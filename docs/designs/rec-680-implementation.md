# Quick Check-in and Wanna implementation (REC-680)

The approved [native design proposal](https://github.com/joelipshutz/wander/pull/781)
is implemented in the production editor, store and repository paths. The
simulator review route supplies fictional data to those same screens and save
functions; it is restricted to Debug simulator builds and uses Noop analytics.

## Behavior

- Check-in can save a date and visibility in a few taps. Add details retains all
  existing fields. Expanding removes the compact date row without changing its value.
- No rating is stored until the slider is touched; touching 3 explicitly stores 3.
  Remove rating writes null. Existing saved scores remain unchanged.
- Wanna starts compact with optional details and creates no visit or rating.
- The map invitation, history pencil, history Add details and reminder all open
  the same visit editor. Enrichment updates its original identity.
- Local quick saves flush before dismissal, then use the existing retry/outbox
  path. Per-visit synchronization coalesces callers and preserves newer edits.
- Check-in reminders are an independent Push type, default on under the existing
  master push setting. Eligibility, three-hour delay, quiet hours, 48-hour expiry,
  one-per-day cap and cancellation are enforced on the server.

## Release requirements

Apply `20261110193000_quick_check_in_details.sql` before releasing the app. Deploy
the updated push-notification worker to retain the reminder category in aggregate
analytics. No migration or worker deployment is included in this review package.
Existing saved ratings are not backfilled or changed. Only newly pending visits
are enrolled; old app versions remain compatible with the additive server fields.
An offline dismissal cancels an unsent reminder after synchronization. A push
already accepted by APNs cannot be recalled.

## Reproduce native review

Build the `Wander` Debug scheme, install it on a dedicated iPhone simulator, and
launch with `-WanderQuickCaptureUITest <route>`. Routes `quick`, `wanna`, `details`,
`edit`, `invitation` and `reminders` render the corresponding production screens.
The review fixture performs local saves only. It does not send push notifications.

Run all `WanderTests` and `WanderUITests/QuickCaptureUITests`. The UI tests verify
unrated quick saves, explicit midpoint selection, expanded-but-untouched saves,
Wanna expansion, and the native date picker's value carrying into the full editor.
Unit coverage exercises persistence, exact backdated visit identity, concurrent
save/edit/dismiss synchronization, account switching, draft recovery, reminder
routing and analytics privacy.

The shared `scripts/supabase-smoke-test.mjs` includes the new SQL contract checks.
For pre-deployment verification, its `--print-sql --migration-preview
supabase/migrations/20261110193000_quick_check_in_details.sql` output previews the
migration inside the existing rollback-only smoke transaction. Run it only with
explicit authorization for the hosted target. It covers unrated/explicit/cleared
ratings, idempotency, ownership, exact enrichment, invitation hydration, delayed
queueing, quiet hours, expiry, daily limits, final delivery authorization and RPC
security metadata. Validation outcomes and outstanding gates are recorded in the
implementation PR and Linear issue.

## Validation record

- Full native run: 3,631 tests exercised; 3,629 passed. The two failures were
  legacy SaveResult equality assertions that predated the returned visit ID.
  Their assertions now verify each result against its actual created visit.
  The final focused rerun passed all 26 tests, including both corrected tests,
  quick-capture regressions and all five production UI flows. No tests skipped.
- Full hosted rollback-only smoke passed with this migration preview. A follow-up
  query confirmed that both the added schema and synthetic fixture rows rolled back.
  The existing repeat-Wanna fixture now creates a fresh check-in by provider identity
  after deletion, preserving the repository's active-parent edit guard. That older
  parent-identity migration is not recorded on the hosted project; this migration
  explicitly retains its contract. Reconcile migration history before rollout.
- Push notification worker: type check and all 9 Deno tests passed.
- Analytics dashboard contract: all 12 tests passed; 8 sections and 36 insights.
- Actual app captures inspected on iPhone 17 Pro and smaller iPhone 17e (iOS 26.5).
  The settings fixture has OS notifications disabled; this does not represent the
  default preference for users who already enabled push.

| Production screen | iPhone 17 Pro | iPhone 17e |
| --- | --- | --- |
| Quick Check-in | [Capture](rec-680-implementation/large/quick.jpg) | [Capture](rec-680-implementation/compact/quick.jpg) |
| Quick Wanna | [Capture](rec-680-implementation/large/wanna.jpg) | [Capture](rec-680-implementation/compact/wanna.jpg) |
| Expanded details | [Capture](rec-680-implementation/large/details.jpg) | [Capture](rec-680-implementation/compact/details.jpg) |
| Contextual invitation | [Capture](rec-680-implementation/large/invitation.jpg) | [Capture](rec-680-implementation/compact/invitation.jpg) |
| Push types | [Capture](rec-680-implementation/large/reminders.jpg) | [Capture](rec-680-implementation/compact/reminders.jpg) |

[Exact-visit editor](rec-680-implementation/large/edit.jpg) opens with the existing
visit's stored details and an Update check-in action.
