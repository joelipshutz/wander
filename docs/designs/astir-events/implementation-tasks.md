# Astir Events — implementation tasks

**Planning handoff only. No task is started or approved for production execution by this document.** Each task derives from the reviewed findings and approved journey. Open policies remain task dependencies; default UI/mechanics are documented separately.

## Effort interpretation

Alternative active effort: **human-led 488–796 engineer-hours**, or **agent execution/iteration 252–490 hours**. These are rough bottom-up estimates, not additive totals, fixed AI compression ratios or calendar promises. The repo has no AI-compression table. Agent ranges include coding, tests and iteration; people still own product decisions, review, device/provider operations and release approval. External waits are excluded.

The 22 items are work packages, not necessarily one PR each. Write tests with each feature, integrate small PRs, and use the joined test tasks for cross-system evidence rather than deferring tests until then. Shared integration/migration ownership stays serialized. Assignment of Joe/Ryan to A/B happens at kickoff without assuming specialties.

## Dependency and ownership table

| Task | Lane / stage | Modules touched | Depends on | Agent active hours |
| --- | --- | --- | --- | --- |
| T01 — Define Events states, commands and shared response fixtures | shared / contract | `AstirEventsShared/Contracts`, `events-web/src/events`, `tests/fixtures/events` | — | 6–12 |
| T02 — Add canonical Events data and prove history preservation early | A / foundation | `supabase/migrations`, `supabase/tests`, `Wander/Services/Events`, `WanderTests/Events` | T01 | 12–24 |
| T03 — Build thin App Clip host and prove actual account continuity | B / foundation | `AstirEventsClip`, `AstirEventsShared/Transport`, `Wander/Services/Auth`, `Wander/Services/Remote`, `WanderWidgetShared`, `Wander/App`, `AstirEventsClipUITests` | T01 | 12–28 |
| T04 — Create guest web fallback and authenticated Team admin shell | B / foundation | `events-web/src/guest`, `events-web/src/auth`, `events-web/src/console`, `events-web/tests`, `supabase/tests` | T01 | 8–18 |
| T05 — Wire feature tests, isolated fixtures and compatibility jobs | shared / foundation | `.github/workflows`, `scripts/events`, `WanderTests/Events`, `events-web/tests/contracts`, `supabase/tests` | T01, T03, T04 | 6–12 |
| T06 — Prove signed-in event and booking retrieval across real hosts | joined / foundation | `scripts/events`, `docs/testing`, `WanderUITests/Events`, `events-web/tests/journeys` | T02, T03, T04, T05 | 6–12 |
| T07 — Implement event publishing, schedule and private-home controls | A / journey | `supabase/migrations`, `supabase/tests`, `events-web/src/console`, `events-web/tests/console` | T06 | 10–18 |
| T08 — Implement atomic RSVPs, invitation quotas, offers and cancellation | A / journey | `supabase/migrations`, `supabase/tests`, `scripts/events`, `events-web/src/console` | T06, T07 | 16–28 |
| T12 — Implement one durable SMS/push program and console controls | A / journey | `supabase/migrations`, `supabase/functions/events-notification-worker`, `supabase/tests`, `events-web/src/console`, `Wander/Features/Events` | T07, T08 | 16–30 |
| T09 — Complete app, Clip and browser RSVP, account setup and ticket routes | A / journey | `AstirEventsShared/Presentation`, `events-web/src/guest`, `Wander/Features/Events`, `WanderTests/Events` | T03, T04, T08 | 16–28 |
| T10 — Implement QR validation and verified manual admission in console | A / journey | `supabase/migrations`, `supabase/tests`, `events-web/src/console`, `events-web/tests/console` | T08, T09 | 10–18 |
| T11 — Add complete offline roster and durable admission reconciliation | A / journey | `events-web/src/console/offline`, `events-web/tests/console`, `supabase/migrations`, `supabase/tests` | T10 | 12–24 |
| T13 — Build event check-in, private feedback and canonical history adapter | B / journey | `Wander/Features/Events`, `Wander/Services/Events`, `supabase/migrations`, `supabase/tests`, `WanderTests/Events`, `events-web/src/console` | T06 | 12–24 |
| T14 — Implement shared photo/video uploads, reuse and source removal | B / journey | `Wander/Services/Events`, `Wander/Features/Events`, `supabase/functions/events-media`, `supabase/functions/events-media-worker`, `supabase/migrations`, `events-web/src/console`, `scripts/events` | T13 | 20–40 |
| T15 — Complete rich recap, publication, discussion and return invitation | B / journey | `Wander/Features/Events`, `Wander/Services/Events`, `events-web/src/guest`, `events-web/src/console`, `supabase/migrations`, `supabase/tests`, `WanderUITests/Events` | T12, T13, T14 | 12–24 |
| T16 — Integrate event pins and inline place/feed history without regressions | B / journey | `Wander/Services/Events`, `Wander/Features/Map`, `Wander/Features/Feed`, `Wander/Services`, `WanderTests/Events`, `supabase/tests` | T07, T13 | 12–24 |
| T17 — Prove current access across every projection and cache | A / integration | `supabase/tests`, `WanderTests/Events`, `events-web/tests/guest`, `scripts/events` | T09, T11, T14, T15, T16 | 10–20 |
| T18 — Run complete integrated journeys and ordinary-app regressions | A / integration | `scripts/events`, `events-web/tests/journeys`, `WanderUITests/Events`, `docs/testing` | T10, T11, T12, T15, T16, T17 | 20–32 |
| T19 — Measure entry, contention, delivery, media/map and offline scaling | B / integration | `WanderTests/Events`, `WanderUITests/Events`, `scripts/events`, `events-web/tests/console`, `docs/testing` | T11, T12, T14, T16, T17 | 10–20 |
| T20 — Verify exact release artifacts, public invocation and real provider delivery | A / release | `docs/testing`, `AstirEventsClip/Resources`, `events-web/public/.well-known`, `scripts/events` | T18, T19 | 14–28 |
| T21 — Rehearse additive rollout, feature controls and non-destructive rollback | B / release | `Wander/Services/Events`, `supabase/tests`, `events-web/src/console`, `events-web/tests/console`, `scripts/events`, `docs/testing` | T05, T17 | 6–14 |
| T22 — Close release evidence and run the controlled Events rollout | joined / release | `docs/testing`, `docs` | T20, T21 | 6–12 |

## Implementation Tasks

Synthesized from this review. Checkbox only when the stated exit criteria have actual evidence. Proposed repository paths may be refined within the approved module boundaries.

- [ ] **T01 (P1, human: ~12–20h / agent: ~6–12h)** — shared-contract — Define Events states, commands and shared response fixtures
  - Surfaced by: D2/D3/D7/D16; CQ1/CQ2; T1–T4; TR01/TR03/TR05. Inspected evidence remains anchored at f8d258e/a0117cff; reconcile implementation against latest main, including f8493c0 Feed grouping/profile-header drift.
  - Files: `AstirEventsShared/Contracts/EventContracts.swift`, `AstirEventsShared/Contracts/EventRepository.swift`, `events-web/src/events/contracts.ts`, `tests/fixtures/events/event-contracts.json`, `docs/decisions.md`
  - Owner/dependencies: lane shared; no predecessor.
  - Verify: Cross-review the minimum user/event/place/booking/admission/completion/visit/source/operation identifiers, typed outcomes and current permissions; ordinary data and guest/admin projections remain distinct.
  - Verify: Validate deterministic native/web fixtures for unknown, failed lookup, no booking, pending, offered, confirmed, admitted and completed-with-deleted-post; unknown states fail closed.
  - Verify: Record timestamp/cursor/version/error semantics, public-read seam, analytics allowlist and short compatibility contract; separate proposed product clauses from approved rules.
  - Verify: At kickoff verify current issue/worktree/main baseline and shared-file owners; one active editor for contract and migration sequencing. No project-wide framework rewrite.
  - Exit: Compact contract and fixture set reviewed by both lanes; TR01/TR03/TR05 have concrete response examples and ownership.
  - Exit: D2 one backend/canonical place, D7 one all-access Team admin role and D16 small shared-native boundary remain explicit; no implementation of deferred reconnection or expanded privacy.

- [ ] **T02 (P1, human: ~24–40h / agent: ~12–24h)** — data-foundation — Add canonical Events data and prove history preservation early
  - Surfaced by: D2/D4/D7/D16; CQ2; T3; TR02/TR04; existing ordinary-check-in rating/audience hazards.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_core.sql`, `supabase/tests/events_core.sql`, `supabase/tests/events_completion_history.sql`, `Wander/Services/Events/EventHistoryAdapter.swift`, `WanderTests/Events/EventHistoryAdapterTests.swift`
  - Owner/dependencies: lane A; T01.
  - Verify: Implement minimum event/canonical-place relationships, independently persisted booking/admission/completion identity and Team admin membership/authorization; include a narrow real verified-RSVP operation for the checkpoint.
  - Verify: Implement/prove the completion-to-canonical-visit seam with a faithful repository contract: null event venue rating, preserved old notes/ratings/audiences/save intent, idempotent operation and coherent rollback.
  - Verify: Run pgTAP grants/RLS/schema and ordinary-history regressions; extend reserved-identity hosted rollback smoke when the implementation environment is authorized.
  - Verify: A owns serialized migration allocation in foundation; the history adapter is handed to B after T06. Do not use the test/local sequential generic check-in fallback as atomic Events proof.
  - Exit: Early persisted event/account/booking and canonical-history proof supports T06 without waiting for all feature endpoints.
  - Exit: Foundation slice of P02/P05/P14/C06 and TR02/TR04 passes on isolated fixtures; complete user journeys remain T13/T18.

- [ ] **T03 (P1, human: ~24–48h / agent: ~12–28h)** — entry-identity-foundation — Build thin App Clip host and prove actual account continuity
  - Surfaced by: D3/D16; CQ1/CQ2; T2; PF1; TN01–TN04/TR06.
  - Files: `project.yml`, `Wander.xcodeproj/project.pbxproj`, `AstirEventsClip/AstirEventsClipApp.swift`, `AstirEventsShared/Transport/EventTransport.swift`, `Wander/Services/Auth/AuthSessionProviding.swift`, `Wander/Services/Auth/ClerkAuthService.swift`, `Wander/Services/Remote/WanderSupabaseClient.swift`, `WanderWidgetShared/WanderWidgetDeepLink.swift`, `Wander/App/AppEntryView.swift`, `AstirEventsClipUITests/EventClipLaunchTests.swift`
  - Owner/dependencies: lane B; T01.
  - Verify: B is the sole foundation editor for XcodeGen/generated membership, entitlements, shared-auth extraction and root link entry; extract only necessary contracts rather than importing full store/map into Clip.
  - Verify: Build selected full-app/Clip hosts, then use signed isolated devices/accounts for actual Apple and Google provider exchange, phone-verification mechanism and supported continuation; validate SDK/platform capabilities instead of assuming normal iOS docs prove Clip support.
  - Verify: Preserve canonical event intent through auth cancellation, account switch, install/icon launch and original-provider recovery; no silent linking/booking merge. Distinguish 403 permission denial, auth failure and uncertain operation outcome.
  - Verify: Measure cold invocation, auth and event-read dependency intervals separately. If approved Clip/auth continuity is infeasible, report the specific evidence and alternatives before changing the journey.
  - Exit: App and thin Clip compile independently with real required SDK/resources; TN01/TR06 build boundary proof recorded.
  - Exit: Signed development/test platform proof supports I01/I03/I05–I07 without claiming production public invocation; T06 joins server booking, T20 verifies public distribution.

- [ ] **T04 (P1, human: ~20–32h / agent: ~8–18h)** — web-console-foundation — Create guest web fallback and authenticated Team admin shell
  - Surfaced by: D3/D7/D16; CQ2; T2/T4; PF1; C-NOAPP.
  - Files: `events-web/package.json`, `events-web/src/guest/EventEntry.tsx`, `events-web/src/auth/AccountSession.ts`, `events-web/src/console/ConsoleShell.tsx`, `events-web/src/console/AdminGuard.ts`, `events-web/tests/guest/entry.spec.ts`, `events-web/tests/console/authorization.spec.ts`, `supabase/tests/events_console_authorization.sql`
  - Owner/dependencies: lane B; T01.
  - Verify: Implement public fallback and browser Apple/Google/phone/session adapters against the common contract; missing Clip is not missing RSVP. Real provider/backend continuity is the T06 acceptance gate.
  - Verify: Create a separate console shell with individual operator identity and Team admin contract/error handling; direct-API revoked/nonadmin enforcement must be proved with the real T02 backend at T06.
  - Verify: Add browser harness and shared contract fixtures. Keep full confirmed guest-list/RSVP management available without download; app-only QR/check-in/upload are explicit actions.
  - Verify: Web/native host shells and credentials remain separated; no service-role secret or admin payload is exposed to guest clients.
  - Verify: Scaffold shells against shared fixtures independently of pending provider proof; connect real identity/backend before T06 passes. Mock shells are not that proof.
  - Exit: Shell-level C01/L03/L04/L14/L15/L17 rendering, contract decoding and return behavior passes with explicitly labeled fixtures; detailed forms/panels follow journey tasks.
  - Exit: The browser and console shells are ready to connect to T02; real account-owned booking retrieval and server console authorization are T06 exit criteria, not proof claimed by T04.

- [ ] **T05 (P1, human: ~12–20h / agent: ~6–12h)** — test-ci-foundation — Wire feature tests, isolated fixtures and compatibility jobs
  - Surfaced by: D16; T1–T4; TR01–TR06; existing release-classification CI is not runtime verification.
  - Files: `.github/workflows/events-checks.yml`, `scripts/events/fixtures.mjs`, `scripts/events/concurrency.mjs`, `scripts/events/evidence.mjs`, `WanderTests/Events/EventWireContractTests.swift`, `events-web/tests/contracts/event-wire-contract.spec.ts`, `supabase/tests/events_contract_compatibility.sql`
  - Owner/dependencies: lane shared; T01, T03, T04.
  - Verify: Extend existing XCTest/XCUITest, pgTAP, Node and Deno runners; add the actual Clip/web build/test paths rather than using manifest CI as a substitute.
  - Verify: Implement reserved rollback SQL fixtures plus a separate committed isolated multi-session race fixture with cleanup; HTTP/storage/worker journeys must not depend on another connection’s uncommitted data.
  - Verify: Create common run IDs, controlled clock/recipient adapters and evidence statuses passed/failed/blocked/skipped; no real guest sends or secret-bearing logs.
  - Verify: Contract checks reject unknown rights, source leakage and old/new version incompatibility; coordinator serializes project/workflow/migration changes.
  - Exit: Feature PRs can run their actual unit/SQL/worker/browser checks and publish scoped evidence.
  - Exit: T1/T4 harness gaps and TR01/TR03/TR06 checks have working runners; this is infrastructure proof, not 121-case acceptance.

- [ ] **T06 (P1, human: ~12–20h / agent: ~6–12h)** — foundation-integration — Prove signed-in event and booking retrieval across real hosts
  - Surfaced by: D8 foundation checkpoint; D2/D3/D16; T2/T3; PF1/PF2.
  - Files: `scripts/events/foundation-checkpoint.mjs`, `docs/testing/astir-events-foundation-proof.md`, `WanderUITests/Events/EventFoundationTests.swift`, `events-web/tests/journeys/foundation.spec.ts`
  - Owner/dependencies: lane joined; T02, T03, T04, T05.
  - Verify: Use one isolated account/event through actual provider sign-in, current-number verification, minimal persisted RSVP, response-loss retry and same booking lookup in app/Clip/browser; do not seed the post-RSVP state.
  - Verify: Demonstrate the completion/history seam preserves a distinct prior rating/note/audience/save; prove failed visit write cannot leave committed completion.
  - Verify: Record exact signed builds, configuration, current account IDs and all unavailable capabilities; calibrate entry/query baselines without promising final SLOs.
  - Verify: Proceed to two journey packages once shared contracts are proven; if a real platform constraint breaks the approved experience, bring that concrete tradeoff back rather than building around a mock.
  - Verify: Prove T04 browser retrieval with a real account-owned booking and public projection against T02, plus direct-API denial for a nonadmin/revoked Team admin. Shell fixtures cannot satisfy this gate.
  - Exit: Real shared-state checkpoint is accepted by both lanes with precise limits; TN02/TN04 and foundation T2/T3 failures resolved.
  - Exit: No claim that TestFlight/local proof establishes public App Clip invocation, production phone delivery or full E01–E12 acceptance.

- [ ] **T07 (P1, human: ~20–32h / agent: ~10–18h)** — event-configuration — Implement event publishing, schedule and private-home controls
  - Surfaced by: D2/D7/D13/D14; T4; PF1; C02/C03/H01–H06.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_configuration.sql`, `events-web/src/console/EventEditor.tsx`, `events-web/src/console/HomeSettings.tsx`, `supabase/tests/events_home_projections.sql`, `supabase/tests/events_schedule.sql`, `events-web/tests/console/event-editor.spec.ts`
  - Owner/dependencies: lane A; T06.
  - Verify: Build event draft/configuration/publish controls for one canonical place, media cover, timing, approval/code settings, offer default/override, registration close and map styling window.
  - Verify: Enforce consent prerequisite and approximate/exact home projections by current booking/window independently of recap; prevent ordinary canonical-place queries, previews/calendar/nav from bypassing it.
  - Verify: Implement upcoming reschedule revision semantics: retain booking/seat/code/offer identity, recompute relative reveal/expiry, preserve explicit absolute override, persist change intent and invalidate obsolete scheduled work.
  - Verify: Serialize migrations through the designated data integrator; test before/at/after time boundaries and failed save. Event cancellation/completed-event edits remain excluded until their policies are approved.
  - Exit: C02/C03 and B16 approved reschedule portions pass; H01–H06 server projection/settings portions and TR05 pass.
  - Exit: Configuration is durable and server authoritative; failure never appears published or sends a change.
  - Conditional: Select the still-proposed draft/publish interaction and private-home consent capture workflow before treating their exact UI/procedure as release acceptance (P19 and H05).
  - Open groups (affected clauses only): OD01, OD02, OD05; see [decision inventory](engineering-open-decisions.md).

- [ ] **T08 (P1, human: ~32–48h / agent: ~16–28h)** — booking-rules — Implement atomic RSVPs, invitation quotas, offers and cancellation
  - Surfaced by: D4–D6/D10–D14; CQ2; T1; PF2; TB01/TB02/TB10.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_booking_transactions.sql`, `supabase/tests/events_capacity_codes.sql`, `supabase/tests/events_booking_transitions.sql`, `scripts/events/concurrency.mjs`, `events-web/src/console/GuestReview.tsx`, `events-web/src/console/InvitationCodes.tsx`
  - Owner/dependencies: lane A; T06, T07.
  - Verify: Implement short event-scoped transactions with stable operation/booking-generation identities and consistent event/code lock order; no provider work under lock.
  - Verify: Enforce no hold for unfinished verification/pending requests, offer holds for seat plus required code allowance, confirmation-only redemption, exactly-once cancellation refund, grandfathered committed requests after code deactivation and default registration through event end.
  - Verify: Use current server time after locks; late expiry worker and lost successful response cannot violate promise/current state. Reject capacity reduction below confirmations plus valid holds.
  - Verify: Run separate-session controlled races for last seat/code/offer, cancellation/new attempt and lock waits crossing deadlines; assert final allocation and message intents.
  - Exit: B01–B15 approved invariants and I03/I04/I12 allocation portions pass, including TB01/TB02/TB10.
  - Exit: Manual capacity failure remains pending; issued offers remain protected; stale retries never resurrect cancellation.
  - Conditional: Resolve the applicable OD01 rules for offer deadlines versus closing, active queues, approval-mode edits and individual/whole-event code changes, plus OD03 pending withdrawal, before implementing those clauses; preserve all approved allocation and promise invariants.
  - Open groups (affected clauses only): OD01, OD03; see [decision inventory](engineering-open-decisions.md).

- [ ] **T12 (P1, human: ~32–48h / agent: ~16–30h)** — event-delivery — Implement one durable SMS/push program and console controls
  - Surfaced by: D13; product D19/D26/D29; T4; PF3; TB03/TB06/TB09/TR03/TR05.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_delivery_intents.sql`, `supabase/functions/events-notification-worker/index.ts`, `supabase/functions/events-notification-worker/index.test.ts`, `events-web/src/console/EventMessages.tsx`, `Wander/Features/Events/EventNotificationRouter.swift`, `supabase/tests/events_delivery_intents.sql`
  - Owner/dependencies: lane A; T07, T08.
  - Verify: Build the single enqueue/claim/settlement contract shared by RSVP/reminder/change/offer and recap triggers; keep stable message identity, current event revision/recipient eligibility and per-channel consent.
  - Verify: Distinguish verified event phone, future marketing checkbox and event-SMS opt-out; canonical View event links and private-safe previews work without app. Console edits timing/content/preview with truthful save outcomes.
  - Verify: Use bounded claims/concurrency and explicit unknown-provider-result recovery; replayed callbacks or push failure do not duplicate intended SMS. Assess existing 20-job/minute scheduled path rather than inheriting it as Events throughput.
  - Verify: Test controlled sender/provider receipts, stale jobs, reschedule/cancel/permission changes, malformed callbacks, claim expiry and mixed success. Do not log recipient/private content or call accepted queued messages delivered.
  - Exit: M01–M05/M07–M12 approved portions and TB03/TB06/TB09/TR03/TR05 pass; proposed portions stay conditional until reviewed.
  - Exit: Recap publication/correction integrates through this same foundation in T15; no second messaging system or unbounded event burst.
  - Conditional: Select remaining P10 late-reminder/opt-out mechanics and extra push cadence/fallback, provider retry/unknown-outcome operating details, and exact publish semantics before their release-baseline assertions. Approved SMS cadence and state accuracy are not reopened.
  - Open groups (affected clauses only): OD02, OD04; see [decision inventory](engineering-open-decisions.md).

- [ ] **T09 (P1, human: ~32–48h / agent: ~16–28h)** — guest-journey — Complete app, Clip and browser RSVP, account setup and ticket routes
  - Surfaced by: D3/D6/D14/D16; CQ2; T2; PF1; C-NOAPP.
  - Files: `AstirEventsShared/Presentation/EventDetailView.swift`, `AstirEventsShared/Presentation/EventRSVPFlow.swift`, `AstirEventsShared/Presentation/EventGuestList.swift`, `events-web/src/guest/RSVPFlow.tsx`, `events-web/src/guest/GuestList.tsx`, `Wander/Features/Events/EventsScreen.swift`, `Wander/Features/Events/EventTicketView.swift`, `Wander/Features/Events/EventAccountSetupView.swift`, `WanderTests/Events/EventRoutingTests.swift`
  - Owner/dependencies: lane A; T03, T04, T08.
  - Verify: Wire nine event states, canonical link sources, actual lookup/loading/recovery, same-surface back navigation, verified phone, Apple/Google cancel/error, invitation code/pending/waitlist/offer/manage/cancel against real commands.
  - Verify: Keep optional install CTA dismissible and guest list/manage available to recognized confirmed Clip/web guests; unknown is distinct from successful no-booking lookup.
  - Verify: Full app Events tab shows confirmed/upcoming/past/empty states; QR uses only missing required name/username setup, optional photo and no general-tour/permission gate. Guest list pages follow-first/mutual counts under current visibility.
  - Verify: Run native/web parity, accessibility, malformed/stale response, account-switch and provider cancellation tests; do not duplicate transaction eligibility as a client authority.
  - Exit: L01–L17, I01–I12, A02 and C07 guest navigation/entry requirements pass in their implemented layers; physical/public proof remains T20.
  - Exit: No Tickets tab, pre-entry forced photo, early mandatory install or deferred attendee reconnection is introduced.
  - Conditional: Confirm exact remaining provider-dependent resend/recovery copy and optional general-onboarding deferral interaction for the release baseline; no extra QR gate may be added.
  - Open groups (affected clauses only): OD04, OD08, OD09; see [decision inventory](engineering-open-decisions.md).

- [ ] **T10 (P1, human: ~20–32h / agent: ~10–18h)** — online-door — Implement QR validation and verified manual admission in console
  - Surfaced by: D5 product admission separation; engineering D7/D9; CQ2; T3/T4; PF2.
  - Files: `supabase/migrations/YYYYMMDDHHMMSS_events_admission.sql`, `events-web/src/console/Scanner.tsx`, `events-web/src/console/GuestLookup.tsx`, `supabase/tests/events_admission.sql`, `events-web/tests/console/online-admission.spec.ts`
  - Owner/dependencies: lane A; T08, T09.
  - Verify: Validate actual event/booking/account/app-entry prerequisites; no browser-only unsupported-phone waiver. Handle scan duplicate, wrong event, canceled credential, ambiguity, QR failure and current Team admin authorization.
  - Verify: Manual lookup verifies the eligible booking/full-account requirement and records the same canonical admission command; correct/revoke attendance affects access without creating/deleting a personal post.
  - Verify: Keep lost-result operation identity and resolve before retrying; admission creates neither canonical place visit nor completed event check-in.
  - Verify: Test direct unauthorized API access and camera/lookup on intended staff hardware in addition to browser fixtures.
  - Exit: A01–A07, C01/C05 admission portions and TB07 pass.
  - Exit: Entry and post-event completion remain distinct; scanner is part of the all-access Team admin console.
  - Conditional: Resolve the still-proposed physical reentry procedure and any detailed revocation UI before representing those as approved operations; current admission/recap authorization remains mandatory.
  - Open groups (affected clauses only): OD03; see [decision inventory](engineering-open-decisions.md).

- [ ] **T11 (P1, human: ~24–40h / agent: ~12–24h)** — offline-door — Add complete offline roster and durable admission reconciliation
  - Surfaced by: D9B/D7/D13; T3/T4; PF5; TB04/TB05/TB08/TP03.
  - Files: `events-web/src/console/offline/RosterStore.ts`, `events-web/src/console/offline/AdmissionQueue.ts`, `events-web/src/console/offline/Reconcile.ts`, `events-web/tests/console/offline-admission.spec.ts`, `events-web/tests/console/offline-performance.spec.ts`, `supabase/migrations/YYYYMMDDHHMMSS_events_offline_reconciliation.sql`
  - Owner/dependencies: lane A; T10.
  - Verify: Download bounded versioned chunks and promote only a complete durable roster; show event, snapshot freshness and explicit offline status. Index local lookup; persist individual stable operations before acknowledging offline admission.
  - Verify: Preserve queued work through reload/update/network loss, separate original account/event ownership and handle quota/eviction/storage failure without false success. Do not include recap/private feedback/unnecessary exact-home data.
  - Verify: Reconcile bounded batches through current server membership/booking/admission uniqueness; duplicates and invalid/stale records have individual truthful outcomes and unresolved rows remain visible.
  - Verify: Test two disconnected devices, canceled booking/rescheduled event/revoked admin, response loss, partial batches and real staff browser lifecycle. Recap remains locked before successful server validation.
  - Exit: A08–A11 plus TB04/TB05/TB08/TP03 pass; no offline new RSVP or software admission waiver.
  - Exit: Offline-local counts never claim cross-device truth and no pending queue record is silently cleared, reassigned or reported synced.
  - Open groups (affected clauses only): OD03; see [decision inventory](engineering-open-decisions.md).

- [ ] **T13 (P1, human: ~24–40h / agent: ~12–24h)** — event-completion-history — Build event check-in, private feedback and canonical history adapter
  - Surfaced by: D2/D16; product D1–D4/D33/D34; CQ2; T3; PF4.
  - Files: `Wander/Features/Events/EventCheckInView.swift`, `Wander/Services/Events/EventHistoryAdapter.swift`, `Wander/Services/Events/EventCompletionRepository.swift`, `supabase/migrations/YYYYMMDDHHMMSS_events_completion.sql`, `events-web/src/console/EventFeedback.tsx`, `WanderTests/Events/EventCheckInTests.swift`, `supabase/tests/events_completion_history.sql`
  - Owner/dependencies: lane B; T06.
  - Verify: Own the history seam handed over from A: cohesive completion result creates exactly one event-labeled canonical-place visit, no public venue rating, and preserves independent old visit/note/rating/audience/save intent.
  - Verify: Implement existing-style composer with optional note/photos/event tags and independently optional private stars/comment; all-empty explicit submit is valid and routes to recap. Keep feedback restricted to authorized Team admin access.
  - Verify: Bind draft/result to account/event, retry stable operation after force-close/lost response, and retain historical completion after personal-post deletion; failed visit write rolls back completion.
  - Verify: Test generic ordinary check-ins/saves unchanged, original engagement identity preserved, deletion/retry/old snapshots do not duplicate or resurrect event visits. Selected-media pipeline completes in T14.
  - Exit: P01/P02/P04–P07/P10/P14 approved completion/history portions and C06 pass; full media assertions finish T14.
  - Exit: Admission does not itself complete check-in, and deleting a post does not force another check-in while admission remains valid.
  - Conditional: Select exact P06 failed-selected-media retry/explicit-omission interaction and any P07 editing details before claiming their proposed behavior; optional fields and empty-valid completion remain fixed.
  - Open groups (affected clauses only): OD06; see [decision inventory](engineering-open-decisions.md).

- [ ] **T14 (P1, human: ~40–64h / agent: ~20–40h)** — protected-event-media — Implement shared photo/video uploads, reuse and source removal
  - Surfaced by: D2/D16 protected-data requirements; product D6/D27/D28/D32; T4; PF4; TP01.
  - Files: `Wander/Services/Events/EventMediaRepository.swift`, `Wander/Services/Events/EventProtectedMediaCache.swift`, `Wander/Features/Events/EventGalleryView.swift`, `supabase/functions/events-media/handler.ts`, `supabase/functions/events-media-worker/index.ts`, `supabase/migrations/YYYYMMDDHHMMSS_events_media_references.sql`, `events-web/src/console/EventMedia.tsx`, `scripts/events/media-access-smoke.mjs`
  - Owner/dependencies: lane B; T13.
  - Verify: Implement attendee and first-party shared-gallery photos/videos, own-photo composer contribution, same-post gallery-photo references and no preapproval/reuse explanation. Finalized eligible uploads appear immediately.
  - Verify: Use paged authorized manifests, sized derivatives, file-backed bounded video upload/playback and stable retry/finalization IDs; do not hold all gallery/original/video bytes in memory.
  - Verify: Current admission/completion/source/post-audience governs JSON and actual original/thumbnail/HEAD/range bytes. Account/event/permission/source cache identity, old URL failure, invalidation and stale-response guards apply before redisplay.
  - Verify: Source removal retires all post/gallery references and derivatives while preserving other media/notes/visits/ratings; retry worker cleanup and delayed derivative completion cannot resurrect content. Test actual warm-cache delivery paths.
  - Exit: P03/P05/P11–P13/P15 and C04/C05 media portions plus TP01 pass with actual storage/delivery proof.
  - Exit: Private gallery entitlement does not transfer to public viewers merely because one selected photo appears in a permitted personal post.
  - Conditional: If measured platform limits require a new user-visible format/duration/size cap, processing delay or higher-cost service, obtain that concrete decision before changing scope. Personal-composer video remains proposed and is not included by inference.
  - Open groups (affected clauses only): OD06; see [decision inventory](engineering-open-decisions.md).

- [ ] **T15 (P1, human: ~24–40h / agent: ~12–24h)** — recap-conversation — Complete rich recap, publication, discussion and return invitation
  - Surfaced by: Product D1/D3/D5/D26–D28/D33; D7/D16; T3/T4; PF1/PF3.
  - Files: `Wander/Features/Events/EventRecapView.swift`, `Wander/Services/Events/EventConversationRepository.swift`, `events-web/src/guest/RecapPreview.tsx`, `events-web/src/console/RecapEditor.tsx`, `supabase/migrations/YYYYMMDDHHMMSS_events_recap_conversation.sql`, `supabase/tests/events_conversation.sql`, `WanderUITests/Events/EventRecapTests.swift`
  - Owner/dependencies: lane B; T12, T13, T14.
  - Verify: Build event-focused cover, comments near top, familiar comment/reply/like behavior, photos/videos plus, personal check-ins and upper-right share. Keep shared recap conversation distinct from personal-post engagement.
  - Verify: Publish through Team admin console before queuing eligible admitted-guest invitations in T12; no-show and preview-only callers receive no protected metadata/content behind blur.
  - Verify: Return from app deletion/reinstall recovers the same admission/completion; deleted personal post does not recreate it. Share uses canonical event link and only permitted preview, with no automatic external posting.
  - Verify: Test publication failure, repeated revision, stale/current access, source deletion, own/other-author actions and accessible preview/locked content; define only agreed editing/reporting behavior.
  - Exit: P06/P08/P09/P16/P17 and M06/M13/M14 approved portions plus C04/C05 recap controls pass.
  - Exit: No additional required post/check-in is introduced; full recap/gallery/conversation remains governed by current authoritative admission plus historical completion.
  - Conditional: Confirm temporary-unavailability restoration behavior (P14), late-corrected-admission invitation procedure (M14), and external share payload before asserting proposed details. No new operator unpublish/republish capability is authorized; retain publication-before-invite and current access invariants.
  - Open groups (affected clauses only): OD02, OD04, OD05, OD06; see [decision inventory](engineering-open-decisions.md).

- [ ] **T16 (P2, human: ~24–40h / agent: ~12–24h)** — map-place-feed — Integrate event pins and inline place/feed history without regressions
  - Surfaced by: D2/D16; product D4/D9–D13/D35; T3; PF1/PF4; latest-main drift f8493c0 adds REC-494 Feed grouping (#632) and REC-498 profile header (#636).
  - Files: `Wander/Services/Events/EventMapProjection.swift`, `Wander/Features/Map/MapScreen.swift`, `Wander/Features/Map/PlaceProfileMapSurface.swift`, `Wander/Services/FeedModels.swift`, `Wander/Features/Feed/FeedActivityDisclosure.swift`, `Wander/Services/Events/EventHistoryAdapter.swift`, `WanderTests/Events/EventMapPresentationTests.swift`, `supabase/tests/events_map_history.sql`
  - Owner/dependencies: lane B; T07, T13.
  - Verify: Implement permitted Featured/You/Friends event projections under console styling window, approximate private-home geometry and authoritative attendance; use coalesced viewport/page summaries rather than per-pin detail hydration.
  - Verify: Pin reveals collapsed event card over normal map with event at place hierarchy; expand event then canonical place. Add inline paged place event history and event-labeled feed/profile posts with audience eye.
  - Verify: Preserve current ordinary map caches/cancellation and stable selection, old ratings/notes/audiences/save intent and one event visit. At most one integrator edits shared MapScreen/store/feed seam at a time.
  - Verify: Against latest f8493c0-or-newer main, verify current display-only Feed grouping retains original activity/engagement/route IDs; distinct event check-ins are neither merged nor duplicated. Retain new profile-photo-header behavior.
  - Verify: Build summary/history/map integration against media manifests while T14 proceeds; complete actual-media permission integration before T17/T18.
  - Exit: V01–V08, C03/C06 map/history portions and H01/H03/H04 protected-map behavior pass.
  - Exit: P2 denotes relative implementation priority, not optional scope; complete Events release still requires this task.
  - Conditional: Select final pin visual treatment and any exact styling preset defaults before visual acceptance; second-degree Friends expansion and a separate event bookmark remain unselected; do not implement or treat omission as an approved scope cut until review.
  - Open groups (affected clauses only): OD05, OD07, OD09; see [decision inventory](engineering-open-decisions.md).

- [ ] **T17 (P1, human: ~20–32h / agent: ~10–20h)** — protected-integration — Prove current access across every projection and cache
  - Surfaced by: T4; D7/D9/D13 protected-data rules; TP01/TP02/TP03; TR02/TR03/TR04.
  - Files: `supabase/tests/events_recap_access.sql`, `supabase/tests/events_home_projections.sql`, `WanderTests/Events/EventProtectedCacheTests.swift`, `events-web/tests/guest/recap-privacy.spec.ts`, `events-web/tests/guest/home-privacy.spec.ts`, `scripts/events/media-access-smoke.mjs`
  - Owner/dependencies: lane A; T09, T11, T14, T15, T16.
  - Verify: Run access matrix across booking/admission/completion/post audience/home window/independent rights: direct SQL/RPC, raw JSON, DOM/native accessibility, media metadata, previews/calendar/nav and actual bytes.
  - Verify: Warm browser/CDN/native memory/disk caches, then revoke/remove/expire/switch account while requests run; no stale result may reauthorize or repopulate a protected cache.
  - Verify: Check D13 relative-window recalculation versus absolute overrides, independent rights and D9 offline operations before/after reconciliation. Preserve ordinary history and retained completion after deletion.
  - Verify: Exercise latest schema grants/RLS and real authenticated transport, including denied versus expired auth; privacy-safe logs and analytics are verified rather than presumed.
  - Exit: H01–H07, P07/P13–P15, A07 and TP01–TP03/TR02–TR04 access requirements pass; any proposed calendar/consent procedure remains explicitly conditional.
  - Exit: No visual-only privacy claim, signed-URL-TTL shortcut or stale cached fallback satisfies the access boundary.
  - Open groups (affected clauses only): OD05; see [decision inventory](engineering-open-decisions.md).

- [ ] **T18 (P1, human: ~32–48h / agent: ~20–32h)** — joined-acceptance — Run complete integrated journeys and ordinary-app regressions
  - Surfaced by: T1–T4; all 121 acceptance mappings plus 24 technical risks; D8 joined-release checkpoint.
  - Files: `scripts/events/integrated-journey.mjs`, `events-web/tests/journeys/events-integrated.spec.ts`, `WanderUITests/Events/EventsIntegratedJourneyTests.swift`, `docs/testing/events-device-matrix.md`, `docs/testing/astir-events-acceptance-results.md`
  - Owner/dependencies: lane A; T10, T11, T12, T15, T16, T17.
  - Verify: Execute E01–E12 continuously with same canonical account/event/booking/admission/completion/visit/media IDs, real app/Clip/browser/console APIs and workers; seed only starting state, not intermediate success.
  - Verify: Run full mapped native/SQL/browser/worker suites including controlled multi-session concurrency and ordinary check-in/save/list/rating/visibility/block/history/widget/auth/onboarding regressions against current main.
  - Verify: Record exact fixture/build/platform/time, server assertions, outbox/provider evidence and passed/failed/blocked/skipped status per case variant. Screenshots and stitched mocks cannot constitute an integrated pass.
  - Verify: Add new implementation branches to coverage map and resolve every high-risk approved failure; proposed details only become assertions after their recorded decision.
  - Exit: E01–E12 integrated outcomes pass with supported variants; all L01–L17/I01–I12/B01–B16/M01–M14/A01–A11/P01–P17/V01–V08/H01–H07/C01–C07 approved portions have execution evidence.
  - Exit: All TB01–TB10/TN01–TN05/TP01–TP03/TR01–TR06 are accounted for; a missing device/service/provider capability is a blocker, not a pass.
  - Open groups (affected clauses only): OD01, OD02, OD03, OD04, OD05, OD06, OD07, OD08, OD09; see [decision inventory](engineering-open-decisions.md).

- [ ] **T19 (P1, human: ~20–32h / agent: ~10–20h)** — performance-validation — Measure entry, contention, delivery, media/map and offline scaling
  - Surfaced by: PF1–PF5; T1/T4; D18 source-review hypotheses, not measured SLOs.
  - Files: `WanderTests/Events/EventLoadingPerformanceTests.swift`, `WanderTests/Events/EventMapPerformanceTests.swift`, `WanderUITests/Events/EventMediaPerformanceUITests.swift`, `scripts/events/performance-load.mjs`, `events-web/tests/console/offline-performance.spec.ts`, `docs/testing/astir-events-performance.md`
  - Owner/dependencies: lane B; T11, T12, T14, T16, T17.
  - Verify: Calibrate foundation baseline and run controlled 30/300/3000 records, mixed large media and existing 1500-pin map fixtures; report exact environment and cold/warm state.
  - Verify: Measure request counts/query plans, lock wait separately from operation latency, queue oldest age and due-to-provider intervals, memory/transfer/player high-water marks and durable offline lookup/write time.
  - Verify: Retain current authorization, no overselling and one canonical visit at every size; provider calls never hold allocation locks, page work stays bounded, roster readiness requires complete data.
  - Verify: Compare Events off/on on the same actual device/dataset; record p50/p95/failure rates with timeouts retained. Tune simple indexes/pages/concurrency from evidence without imposing new guest/upload caps.
  - Exit: PF1–PF5 have measured evidence and resolved material regressions; all provisional budget changes retain justification and user-visible effects.
  - Exit: Physical media/map traces complement host microbenchmarks; no arithmetic estimate or green metadata test is reported as actual end-user delivery/performance.
  - Conditional: If measurements require reduced media support, materially delayed approved messaging or a higher-cost service, obtain that specific tradeoff before release; provisional targets themselves are not preapproved promises.

- [ ] **T20 (P1, human: ~20–36h / agent: ~14–28h)** — distribution-provider-proof — Verify exact release artifacts, public invocation and real provider delivery
  - Surfaced by: T2/T4; TN03/TR06; app, Clip, browser, console and backend are one compatibility gate.
  - Files: `docs/testing/astir-events-release-compatibility.md`, `docs/testing/events-device-matrix.md`, `AstirEventsClip/Resources/AstirEventsClip.entitlements`, `events-web/public/.well-known/apple-app-site-association`, `scripts/events/release-compatibility.mjs`
  - Owner/dependencies: lane A; T18, T19.
  - Verify: Verify final app/Clip identifiers, association domain, entitlements, signed dependencies, supported OS, provider environments and compatible contract versions; release app and Clip as coordinated artifacts.
  - Verify: Exercise actual public invitation invocation on supported physical devices separately from local/TestFlight invocation; fresh install/icon launch, expired session, original Apple/Google recovery and browser fallback preserve one booking.
  - Verify: Use controlled test numbers/devices for actual current-number verification, event SMS and APNs delivery; record provider acceptance/receipt distinctions, denied notifications and opt-out.
  - Verify: Validate real staff camera/browser offline lifecycle, privacy controls and cleanup on the exact target hardware. Record store/provider/domain processing waits separately from active effort.
  - Exit: L01–L03/L13/I01/I07/P08 and TN03/TR06 physical/public distribution gates pass for release artifacts.
  - Exit: A TestFlight build, mocked callback or development provider configuration is not substituted for the production-shaped public-entry/delivery proof.
  - Conditional: Public publication/distribution and service/account configuration must be performed in the later authorized implementation/release phase using the correct Astir accounts; this planning task is not authorization to modify services now.

- [ ] **T21 (P1, human: ~12–20h / agent: ~6–14h)** — release-controls — Rehearse additive rollout, feature controls and non-destructive rollback
  - Surfaced by: D2/D7/D9/D16; TR02/TR04; compatible distribution and retained bookings/history/door work.
  - Files: `Wander/Services/Events/EventFeatureConfiguration.swift`, `supabase/tests/events_launch_permissions.sql`, `events-web/src/console/LaunchConfiguration.tsx`, `events-web/tests/console/launch-configuration.spec.ts`, `scripts/events/release-compatibility.mjs`, `docs/testing/astir-events-rollout-rollback.md`
  - Owner/dependencies: lane B; T05, T17.
  - Verify: Define staged additive schema/functions/web/app/Clip deployment and capability compatibility; separately control public discovery/new RSVP/sending rather than assuming UI visibility grants authorization.
  - Verify: Rehearse older app/new backend and newer app/preactivation. Unknown capabilities fail safely; safe guest management/ticket/console routes for existing commitments remain considered when disabling new acquisition.
  - Verify: Use forward repair/feature disable rather than destructive rollback of live bookings, admissions, completion/history or offline queues. Pause unnecessary sends while retaining truthful delivery state; rollback cannot silently discard pending staff work.
  - Verify: Name rollout owner, metrics/alerts and specific rollback triggers, restore steps and evidence; migration/project files have one editor at a time and feature tasks use separate short-lived worktrees.
  - Exit: TR02/TR04 compatibility/feature-disable scenarios pass with real preserved records and queued door operations.
  - Exit: A reviewed operational runbook states exact safe actions, unavailable limitations and ownership; flags never bypass Team admin/recap/home permissions.

- [ ] **T22 (P1, human: ~8–16h / agent: ~6–12h)** — release-handoff — Close release evidence and run the controlled Events rollout
  - Surfaced by: Full D1 scope; D8 two-lane integration; D19 final planning handoff does not authorize production implementation.
  - Files: `docs/testing/astir-events-acceptance-results.md`, `docs/testing/astir-events-rollout-rollback.md`, `docs/testing/astir-events-release-compatibility.md`, `docs/decisions.md`, `docs/open-questions.md`
  - Owner/dependencies: lane joined; T20, T21.
  - Verify: Review exact release revisions and all agreed acceptance/device/provider/performance results; explicitly list blocked/skipped/unimplemented cases and unresolved proposed details instead of claiming zero defects.
  - Verify: Resolve release-blocking product details with concrete reviewable interactions; deferred reconnection/expanded privacy, extra push cadence, second-degree Friends and personal-composer video do not enter by implication.
  - Verify: After separately authorized publication/activation, run controlled real-event smoke and monitor current booking/admission/media/delivery/queue health; exercise rollback triggers without exposing private guest data.
  - Verify: Update actual issue/PR/release handoff, compatible artifact versions, owners and operational access; measure completed work rather than presenting this planning estimate as a delivery date.
  - Exit: Compatible controlled rollout has evidence and a named operator; no active unexplained blocking acceptance failure or provider/distribution gap.
  - Exit: Published documentation distinguishes implemented/passed behavior, known limitations and deferred proposals; existing commitments and ordinary app history survive.
  - Conditional: Later explicit production release/activation authorization and approved release baseline are required; D19A authorizes this planning handoff only.
  - Conditional: Any unresolved proposed clause that affects the chosen release interaction must be decided or explicitly excluded without cutting approved full-loop scope.
  - Open groups (affected clauses only): OD01, OD02, OD03, OD04, OD05, OD06, OD07, OD08, OD09; see [decision inventory](engineering-open-decisions.md).

## Machine-readable handoff

[JSONL for gstack/autoplan](implementation-tasks.jsonl), [editable task source](implementation-tasks.source.json), and [DAG/estimate validation](implementation-task-verification.json). Dependency validation checks document consistency only; no implementation tests ran.
