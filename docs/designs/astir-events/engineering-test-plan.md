# Astir Events — engineering test plan

Prepared September 15, 2026 under engineering D17A. Repository inspected: `joelipshutz/wander`, review branch `codex/rec-467-events-flowchart`, HEAD `f8d258e869503a28d70518a050dff36a344134c6` (app-code baseline `a0117cff`). This is a plan for implementation, not a test execution report.

**Status: all 121 named acceptance scenarios mapped, plus 24 technical risk groups. No new Events production tests are implemented or passed by this review.** The [121 acceptance scenarios](events-exit-criteria.md) define intended behavior, including clauses explicitly still proposed. The [engineering plan](engineering-plan.md) records later approvals and constraints. A mapped assertion does not approve a proposed product behavior.

The [complete case-to-test map](test-review/coverage-map.md) records concrete planned files, layers, assertions and package ownership. Its [JSON](test-review/coverage-map.json) and [validation report](test-review/mapping-verification.json) verify unique membership, required fields, verbatim source authority and 78 existing source locations. These are planning-artifact checks, not application tests. Planned file names may be consolidated within their owning package during implementation; the 158 referenced paths are not 158 independent tasks or a requirement to create a separate file for each scenario.

## Coverage accounting

- Maintain one mapping for each of the 121 named scenarios, plus separately numbered technical risks. Count parameterized executions only when a runner actually executes them.
- Classify every entry as planned/not implemented/not run until implementation supplies concrete test evidence. Existing auth, place, media and notification tests are adjacent regression coverage, not proof that Events works.
- Keep the original scenario's authority trace in the generated coverage map. Where a row mixes approved behavior with a proposed detail, implement/assert the approved invariant now and resolve the remaining detail before its release-baseline test becomes authoritative.
- The review can verify 121/121 **mapping completeness**; it cannot claim 100% code, branch, device or platform coverage for code that does not exist. Unknown implementation branches must be added to this map during each feature PR.
- The final run report must distinguish passed, failed, blocked, skipped and not implemented; a missing runtime, device, credential, provider capability or hosted environment is not a pass.

## Detected test frameworks and missing harnesses

`CLAUDE.md` delegates to `AGENTS.md` and contains no independent test command. Repository evidence, rather than historical setup prose, determines the following inventory:

| Layer | Existing evidence | Events work to add |
| --- | --- | --- |
| Native unit/contracts | `WanderTests/AuthSessionTests.swift:8` uses XCTest; repository, store, onboarding, visibility and navigation tests exist | Events contract/state mapping, account fencing, operation results, entry routing, completion/history adapters and regression cases |
| Native UI | `WanderUITests/OnboardingUITests.swift` and other XCTest UI suites | Full-app Events UI flows and a new Clip-specific test target/host; fixture UI success remains separate from hosted auth proof |
| Database | `supabase/tests/checkin_history_engagement.sql:1–3` uses a transaction and pgTAP; RLS/identity/check-in/media suites exist | Events constraints, grants/RLS, state transitions, privacy, code/capacity and history/media tests |
| Hosted schema smoke | `scripts/supabase-smoke-test.mjs:64–85` opens a transaction and checks pgTAP results; repo rules require rollback-only checks for changed client RPCs | Extend the same reserved-identity smoke for all new/changed Events RPCs and protected projections; run against the actual migration target when authorized for implementation |
| Worker logic | `supabase/functions/push-notification-worker/index.test.ts` uses `Deno.test`, injected network calls and delivery classifications | Events outbox/worker timing, recipient eligibility, retry/callback, consent, publication and privacy tests |
| Node tools | `scripts/package.json` uses `node --test`; `pg` is an existing tool dependency | Isolated multi-session database race runner, fixture/evidence and compatibility checks where appropriate |
| Guest web/console | No existing Events browser app or browser test harness in this checkout | Add Playwright browser tests in planned `events-web/tests`; distinguish UI fixtures from tests hitting real test API/storage |
| Device/provider acceptance | Existing general release evidence does not prove Events invocation or handoff | Signed Clip/app, actual public invocation, Apple/Google, phone proof, install/icon launch, device camera/QR, SMS/push and staff-browser offline checks |
| CI | `.github/workflows/testflight-manifest.yml` validates release classification | Add Events build/test jobs; a green manifest check cannot substitute for runtime tests |

Commands below are existing repo conventions or planned entry points, **not commands run during this review**:

```text
xcodegen generate
xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,name=iPhone 16 Plus,OS=18.6' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO
npx supabase test db
npm --prefix scripts ci --ignore-scripts
node scripts/supabase-smoke-test.mjs
node --test <new Events tool tests>
deno test <new Events worker test files>
<new events-web package's browser-test command>
```

Verify runner/Xcode/simulator and local database availability at implementation kickoff; dated documentation saying a tool is unavailable is not a current environment check. The Clip target and web runner commands must be added with their actual configuration. Hosted smoke requires the intended environment and approved fixture isolation; do not run new migrations, live workers or messages merely to complete this planning review.

### Inspected adjacent-test quality

These ratings describe assertions read in source, not execution results or a rating of the entire repository. None counts as Events coverage.

| Inspected example | Source quality and limitation |
| --- | --- |
| `AuthSessionTests.swift:1441` | ★★★ behavior plus race/error protection: suspend refresh, switch accounts, complete stale work and verify the new validated account survives. The neighboring native-auth test covers unrelated session observations. Uses an injected provider. |
| `RemoteRepositoryTests.swift:1103` | ★★★ behavior plus edge/error: hold a private-photo response, change accounts and assert rejection of the old bytes with the expected error. Uses a mocked network; not proof of server media permissions. |
| `push-notification-worker/index.test.ts:23` | ★★★ explicit failure-category assertions for invalid tokens, invalid events and retryable outages. The request test at line 50 is ★★ happy-path header/result behavior with injected delivery. Neither proves actual SMS/APNs receipt. |

Every Events branch is currently a planned gap. The existing suite supplies useful patterns, but no code-coverage percentage or claim that these tests currently pass is made by this review.

## Deterministic fixtures and service boundaries

Use the fixtures from the acceptance document: public-place Event A, private-home Event H, another event at the same canonical public place, all booking/admission/completion states, consent and independent venue rights, and an older ordinary visit with distinct note/rating/audience/save intent. Add two distinct Team admins, a revoked admin, a nonadmin and an anonymous viewer. Keep actual phone numbers and provider secrets out of tracked fixtures.

Every clock-sensitive test covers immediately before, exactly at and immediately after the relevant threshold: registration close, offer expiry, reveal and location expiry. Include the event's time zone, a daylight-saving transition where applicable, and an admin schedule change. Inject a clock for deterministic application tests; database acceptance uses authoritative time inside the transaction after locks. A transaction-start timestamp alone cannot prove correct offer expiry after a long lock wait.

The schema fixture defines stable event, account, booking, admission, completion, visit, source-media and operation identifiers. Include separate IDs for two accounts using the same device. A sign-in Boolean, device identifier, supplied phone string or forwarded link is never identity evidence.

Use faithful fakes that implement the same command/results contract as the real repository. Expected business outcomes, auth expiry, permission denial, malformed responses and an unknown post-submit outcome must be injectable independently. A fake that always confirms or creates local attendance cannot pass an admission/permission test.

## Planned execution and user-flow coverage

All leaves below are **[PLANNED GAP]** until implemented and executed. File families are planned paths, not claims that functions already exist. `[E2E]` requires an integrated path; `[DEVICE]` requires actual platform evidence. The case map supplies concrete files and assertions for each leaf.

```text
ENTRY: canonical link / Events tab / direct ticket / message
  -> parse event and preserve intent [L01-L03,L11-L13]
     -> invalid / unavailable / unauthorized -> safe permitted state [L15]
     -> actual host: app | Clip | browser [L17] [DEVICE]
     -> public preview (no authenticated RPC assumed) [L04,L05,L11]
     -> session: validating | missing | expired | valid [L04,L10,I05,I06]
        -> account switch / stale reply -> discard wrong-account result [I06]
        -> lookup fails -> retry; never classify as no RSVP [L10]
        -> lookup succeeds -> none | pending | waitlisted | offered |
                              confirmed | canceled/expired [L05-L09]
        -> native/browser return and back preserve origin [L14,L16]

RSVP: identity -> name/phone -> phone proof -> submit [I01-I04,I11]
  -> cancel/fail auth -> preserve event, recover original account [I05,I06]
  -> wrong/expired/changed phone -> verify; no false confirmation [I03,I04]
  -> check registration clock / code / current approval/capacity [B01-B09]
     -> unreserved verification creates no hold [I03]
     -> pending/waitlisted creates no consumed code use [B04,B08,B09]
     -> direct confirmation atomically settles booking, seat and use [B04,B07]
     -> conflict/closed/error -> truthful state; no partial benefit [B05,B07]
  -> retry after commit/unknown -> same logical request/result [I12,B05]
  -> optional download; texts + management remain usable [L02,L03,L16]

OFFERS / CHANGE / CANCEL [E2E]
  -> operator selects -> atomically hold seat + required code allowance [B10]
  -> owner accepts: after lock, before deadline? [B11,B12]
     -> yes -> one confirmation; repeat finds current booking [B11]
     -> no/wrong account -> no ticket; no stolen hold [B12]
  -> decline/expire -> release unconsumed holds; no automatic promotion [B12]
  -> cancel confirmed -> once-only seat/use return; no repeat refund [B13,B14]
  -> canceled guest rebooks -> current code/capacity rules [B06,B13]
  -> disable code -> existing submitted eligibility vs new attempt [B06]
  -> reschedule -> same booking, current reminders/location, no reaccept [B16]

MESSAGES: committed event -> durable send intent -> worker -> provider [E2E]
  -> confirmation | reminder | change | published recap [M01-M06]
  -> current event/version/recipient/consent/due-time recheck [M02-M05,M08,M11]
  -> claim/retry/duplicate callback/ambiguous provider result [M09]
  -> invalid token | permanent failure | outage -> accurate result [M07,M10]
  -> no message transport -> canonical event remains usable [M10,E12]
  -> publish/correction replay -> no invented repeat invitation [M12-M14]

INSTALL / ENTRY [DEVICE] [E2E]
  -> Clip/browser -> install -> link OR app icon -> original RSVP [I07,E01,E02]
  -> missing name/username? collect only missing required values [I08]
  -> photo absent/failed or unrelated onboarding incomplete [I09,I10]
  -> full-app QR + server-confirmed eligible account [A01,A02]
  -> scan fails -> approved verified lookup fallback [A03]
  -> wrong event / no match / invalid / duplicate -> explicit outcome [A04,A05]
  -> admission correction/revocation -> current rights, no auto post [A06]

OFFLINE DOOR: prepare online -> snapshot + offline shell -> outage [DEVICE]
  -> missing/wrong roster, unauthorized viewer -> no fabricated entry [A07]
  -> confirmed snapshot match -> persist pending operation BEFORE success [A08]
  -> reload/kill/update/eviction/write failure/account switch [A11]
  -> reconnect -> revalidate event/booking/admin -> per-row reconcile [A09]
     -> accepted | duplicate | conflict | waiting [A09,A10]
     -> partial batch or lost reply -> retain/retry unresolved operation IDs [A10]
  -> only validated admission may contribute recap eligibility [A08-A10]

POST EVENT: publication + valid admission -> explicit check-in [P01,P07]
  -> no optional content OR own photos/tags/private feedback [P02-P04,P10]
  -> one atomic completion + canonical visit, no venue rating [P02,P05]
  -> upload fail / save fail / response lost -> recover without duplicate [P05]
  -> historical completion, even deleted post -> eligible recap [P06,P14]
  -> no app -> reinstallation recovers identity/facts [P08,E09] [DEVICE]
  -> protected comments/gallery/upload/reuse [P09,P11,P12]
  -> source removal -> remove all references/derivatives, retain rest [P13]
  -> revoke / block / cached bytes / video ranges -> no bypass [P15,E11]
  -> unavailable/restore/share/cancel -> preserve actual state [P16,P17]

MAP / HOME / HISTORY
  -> audience/filter/window -> permitted pin + collapsed card [V01-V06]
  -> one place, multiple events; one canonical visit/history identity [V07,V08]
  -> exact home entitlement? booking + clock + independent rights [H01-H04,H07]
     -> no -> approximate everywhere, including indirect/cache paths [H06]
     -> yes -> authorized projection until expiry [H02,H03]
  -> consent/publish and correct preview; no public private-data leak [H05,H06]
  -> ordinary saves/lists/ratings/privacy still work [C06] [CRITICAL REGRESSION GUARD]

CONSOLE / INTEGRATED LOOP
  -> membership guard (one Team admin role) on UI + direct API [C01]
  -> draft/change/preview/publish: success OR failed save [C02-C04]
  -> approval/selection/correction/removal affect the right domain [C05]
  -> navigation/deferred scope and independent ordinary features [C06,C07]
  -> real complete journeys E01-E12, no stitched screenshot evidence [E2E]
```

The planner cannot trace nonexistent function bodies line by line. During implementation, add the actual method/branch names and regression links for each changed file, and fail the mapping check if a new outcome has no assertion. This diagram covers known planned execution branches; it is not a proof that no additional branches will arise.

## Race, retry and side-effect verification

Run capacity, code allowance, cancellation/refund, deactivation/submission and offer-acceptance races against an **isolated disposable database with separate sessions** and a barrier-controlled start. A sequential unit test or the current single-transaction rollback smoke cannot prove concurrent behavior. Seed committed test rows before opening competing sessions, read committed final state from another connection, and remove the isolated fixture only after collecting evidence. Never run these destructive or external-side-effect tests against live attendees.

Assert final counts and identities, not which caller happens to win. Cover last seat/use, offer plus direct signup, competing manual approvals, cancellation vs rebooking, acceptance waiting past deadline, cleanup delayed after expiry, reschedule vs queued reminders and two staff devices admitting the same person. Acquire locks in consistent order and set test timeouts so a deadlock is a failure rather than a hung suite.

A timed-out mutation has an unknown result until reconciled. Repeat the same operation ID and assert one durable booking/admission/completion/refund/send intent. Do not claim the client can know the server rolled back merely because the response was lost. Distinguish app exactly-once logical intent from provider delivery behavior; verify provider-supported idempotency and ambiguous-send handling before promising no duplicate SMS after a provider timeout.

Hosted rollback smoke covers grants, RLS, authenticated identity scoping, operation payloads and required RPC metadata (`prosecdef`, pinned `search_path`, grants), including anon/member/admin/revoked admin. It does not test independent-session commit races, real delivery, storage byte deletion or iOS invocation. Add separate integration tests for those boundaries.

## Regression and privacy gates

**CRITICAL regression guards, not claims of an observed regression:** normal place save/check-in/delete, historical engagement/comment identity, rating/note/audience preservation, explicit save intent, lists, blocks, profile visibility, current login recovery, existing deep links/widgets and onboarding must still work after Events integrates. Start from older-version local snapshots and backend records, then exercise Events alongside them. Existing tests remain mandatory; do not replace them with Event-only green checks.

Authorization tests request protected data directly, bypassing screens. Cover event/place/map/history projections, comments/avatars, photo/video original bytes, thumbnails, range responses, temporary URLs, stale cached data, browser back/offline caches, calendar/share/notification previews and account switches. Blurred UI is not an access check. A permitted selected photo in a public personal post must not expose surrounding recap content; source removal must invalidate every reference without destroying other content.

Revocation tests distinguish subsequent authorized access and cache redisplay from material already seen, copied or exported. Fail closed before protected redisplay when current entitlement is uncertain, and invalidate affected local entries when changes are learned. Do not assert that the server can erase a disconnected device or a guest's previously exported copy. The D9 offline roster remains the explicit approved offline exception and follows its own pending-reconciliation contract.

No new LLM or prompt behavior is selected by this plan. Console-configured tag suggestions do not by themselves select an LLM integration. If implementation later adds generated tags or another critical model call, review its product scope, then add prompt/eval fixtures and baselines; do not label the current test plan as containing an executed model eval.

## Real-device and provider proof

Record separately: (1) simulated/local invocation, (2) signed development/TestFlight Clip and app behavior, and (3) public production invocation using the actual configured event domain, deployed association files, published Clip experience and compatible app build. A pass in one category does not automatically pass another. Public Events activation waits for the public invocation and release-candidate checks already required by the engineering plan.

For Apple and Google, verify actual sign-in with the chosen Clerk configuration, phone verification proof, canonical account/booking continuity, canceled/expired auth, original-account recovery and different-current-account behavior. Test Clip → app and browser → app, installation from a link followed by icon launch, full-app already installed, browser retention despite installation, uninstall/reinstall and expired sessions. Use controlled tester identities and phones, not real guest lists.

Test supported iPhone OS/browser combinations and intended staff hardware. The offline door proof must include two real staff browser sessions, full outage, ordinary reload/relaunch, queue-write failure, interrupted refresh, storage loss, sign-out/account switch and reconciliation conflicts. Browser simulation covers deterministic failures; physical hardware covers camera/scanner, actual storage lifecycle and device-specific offline shell behavior. Record any unsupported mode explicitly rather than silently falling back to anonymous admission.

Verify actual SMS and push receipt using controlled test destinations only, the correct provider environment/build, valid and invalid tokens, consent and opt-out handling, and server delivery evidence. A mocked provider response proves the worker branch, not receipt on a device. Recording a provider receipt does not prove the guest read it.

## Ownership and staged execution

| Stage | Test responsibility and stop condition |
| --- | --- |
| Shared contract | Both lanes review the same state/error/fixture definitions. Native/web decoders must agree before parallel feature work depends on them. |
| Two foundations | Data/rules owner proves transactional identity/history/permissions; entry owner proves actual authentication/link/Clip feasibility and each host's isolated build. Integrate a minimal real RSVP before expanding either lane. |
| Before-event/door | Own booking/code/capacity/message/QR/console/offline tests, including multiple-session races and staff hardware. |
| After-event/map | Own completion/history/media/conversation/location/map regression tests and publication-to-invitation integration. Fixtures permit parallel work, followed by a real admission-produced flow. |
| Joined journey | Both owners run E01–E12 against the same compatible candidate and test environment, then record independent observations and server assertions. |
| Release verification | Build/target configuration, old/new client compatibility, migrations, security posture, public invocation and rollback checks must be complete; manifest classification is additional release evidence. |

Run focused checks with each small implementation slice, then the repository-required full native suite before implementation commits/handoff. Add database/worker/browser jobs for the relevant change set, broaden when integration changes or failures justify it, and retain full joined release proof. Do not make every copy-only change repeat paid provider sends or the entire manual device matrix.

## QA artifact and evidence output

The human-facing [QA journey plan](events-qa-test-plan.md) is separate from this implementation mapping. It identifies surfaces/actions/expected outcomes for `/qa` and `/qa-only`. The machine-readable coverage map and agent audit fragments live in `test-review/`.

Each eventual run records: scenario/variant IDs; exact app/Clip/web/backend versions and contract version; environment; test fixture references; authenticated role; device/OS/browser; test clock/time zone; action; UI observation; authoritative server facts; operation/message IDs in a protected test evidence store; pass/fail/blocked/skipped result; and a concise failure explanation. Never put secrets, real phone numbers, addresses, private feedback or protected media in public logs/analytics.

The review must not mark a release ready while an active approved high-risk case is unexplained, waived without a decision, unimplemented or blocked. Resolve remaining proposed product details before asserting their exact behavior. A mapped test suite sets a verification boundary; it does not promise zero defects.
