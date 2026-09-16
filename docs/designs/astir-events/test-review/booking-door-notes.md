# Booking, messages, admission and console test review

**Planning artifact only.** All 48 assigned cases are mapped; no Events tests have been implemented or executed, no hosted requests were made, and no real SMS, push, or console changes were performed. Source: `events-exit-criteria.md` B01–B16, M01–M14, A01–A11 and C01–C07. The JSON contains 10 additional technical risk groups (TB01–TB10), not 10 completed tests or an exhaustive Cartesian product.

## Baseline and harness evidence

The inspected worktree is `wander-events-flowchart-review` at `f8d258e869503a28d70518a050dff36a344134c6`, containing reviewed code `a0117cff6ed55a967f4212b45bb28d8c39ca1488`. The observed `origin/main` is `0d29d776f42132a28548355ae4e18302cdc3857a`; its delta from the reviewed code is only Events design documentation. Scripts, Supabase code/tests and project configuration inspected here are unchanged.

| Layer | Existing evidence | Planned Events use and limitation |
| --- | --- | --- |
| Local pgTAP | `supabase/tests/notifications.sql:6`, `clerk_identity_continuity.sql:7`, `rls_visibility.sql:7` | Booking/code/offer/admission invariants, RLS, RPC metadata/grants and message eligibility. Existing adjacent assertions are not Events coverage. |
| Hosted rollback smoke | `scripts/supabase-smoke-test.mjs:1110`, `:1119`, `:1182` | Future schema compatibility and selected strict pgTAP; no migration history applied. One rollback transaction cannot prove races or external delivery. Not run. |
| Independent-session races | `scripts/package.json:24` pins `pg`; `scripts/clerk-account-continuity-audit.test.mjs:2` uses Node's runner | New planned `scripts/events-concurrency.test.mjs`: isolated disposable database, separate sessions/barriers and committed fixture cleanup. No existing Events race harness. |
| Deno delivery tests | `supabase/functions/push-notification-worker/index.test.ts:23,50,92,119` | Inject clock/provider/network; inspect payloads, per-message results, unknown outcomes and privacy. Existing APNs classifications do not cover Events SMS. |
| Delivery settlement | `supabase/tests/notifications.sql:837,877,892` | Extend patterns for partial success, excluding accepted token retries and stale claims. Door batches and SMS require separate tests. |
| Browser UI + API integration | No existing tracked Playwright config/web package identified | Proposed `events-web/tests/guest` and `/console`; test both fake-response recovery and actual role-scoped API behavior in an isolated backend. Framework not chosen/installed here. |
| Native/device | `project.yml:45` includes XCTest/UI test targets | Planned native fixtures and physical Clip/app/camera/offline checks. HTML/browser mocks cannot prove native invocation, OS permissions or durable staff-device storage. |
| History regression | `supabase/tests/checkin_history_engagement.sql:68,101` | Extend canonical visit, audience, existing-rating/save preservation and deletion tests. Existing history tests do not cover event-linked visits. |

All paths in the JSON are **planned repository-relative locations**, including proposed new paths and future additions to existing harnesses. Worker naming does not select a second backend or independently owned delivery system.

## Release-critical assertions

1. **Real contention, not sequential calls.** B05/B06/B07/B08/B10/B12/B13/B15/A05/A10 require independent database sessions. Coordinate locks with barriers and inspect committed state from another connection. Include code allowance, seat capacity, protected waitlist inventory, operation-generation retries and message uniqueness. Run on an isolated disposable database, never by committing test fixtures to production.
2. **Read the clock after the lock.** A request can begin before a deadline yet acquire the capacity lock after it. `now()` is transaction-start time in PostgreSQL. B12/TB02 must deliberately hold a lock through expiry and prove fresh authoritative deadline evaluation after acquisition. Previously committed successful operations still resolve their current result.
3. **Unknown is not failed or delivered.** Simulate provider acceptance with a lost response, commit with a lost response, partial batch acknowledgement and stale worker leases. Persist stable operation/message IDs and per-item outcomes. An external SMS cannot be promised exactly once merely because an outbox has a uniqueness key. Selected provider dedupe/status/callback behavior must be validated before automatic retry rules are asserted.
4. **Offline is pending server validation.** A08–A11 use versioned account/event rosters, durable writes before acknowledgement, mixed-batch recovery and real staff-device reload/storage eviction. No local queued row unlocks check-in or protected recap. Current server authorization/booking state governs reconciliation; another account cannot see the prior roster. Remote revocation cannot instantly erase or update a fully disconnected device.
5. **Enforce privacy at API and payload boundaries.** C01/M08/M12/TB06/TB07 inspect direct RPC/table/storage calls, guest previews, outgoing messages, analytics and cached rosters. Test ordinary, anonymous, wrong-account, blocked and revoked roles. Do not expose precise home location, phone lists, private comments or feedback through previews or delivery metadata. Roster data includes only what is necessary for the approved door operation.
6. **Use actual backend joins as well as UI fixtures.** Browser cases must verify resulting records from a separate role-scoped session. Physical devices separately prove Clip/full-app handoff, account setup before QR, camera scan, uninstall/reinstall and supported offline storage. No production messages or admin setting changes are needed to build these tests.

## Policy conditions preserved

The mapping does not convert proposals into approvals. P03 cancellation presentation; P04/P11 approval-mode, issued-deadline and waitlist lifecycle edits; P05 event-wide cancellation/venue/completed-event edits; P09/P19 publishing mechanics; P10 exact push/fallback/retry/late-reminder/opt-out mechanics; P15 detailed revocation/reentry; P18 code-edit/UI details; and P20 calendar payload remain explicitly conditional. Activate the relevant expected results only after a reviewed choice. Their pending assertions cannot count as passing coverage.

Approved D14 behavior is new online RSVP until event end by default, with an earlier console close; self-cancellation still closes at event start. Cutoff/offer interactions must preserve existing promised offers; this mapping does not silently choose a new deadline-edit policy.

## Ownership and evidence at handoff

Common schema, lock ordering and RLS belong to the Events data/rules foundation. Native host/auth seams belong to entry/identity. Before-event/door owns booking and admissions; after-event/map owns recap publication and canonical history. The messaging foundation has one owner, with journey packages adding triggers to the shared enqueue contract. C05 crosses media ownership and requires a joined test, not a second media implementation.

A later acceptance report must identify exact commit, command, environment and actual result for each runtime layer; device checks also need model, OS/browser and build. Keep passed, failed, blocked and not-run separate. The mapping and its JSON membership validation establish only that all 48 assigned source IDs have planned tests.
