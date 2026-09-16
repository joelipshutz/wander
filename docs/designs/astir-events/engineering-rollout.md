# Astir Events — integration, distribution and rollback plan

September 15, 2026. **Future implementation plan only.** No migrations, flags, providers, public links, app builds or live events are changed by this document. The whole approved loop remains the release objective. The engineering stages are dependency/integration stages, not a decision to launch only RSVP and defer recap.

## Build and proof sequence

| Gate | Required evidence | Stop / recovery |
| --- | --- | --- |
| 0. Contract and authority | Shared state/result fixtures, explicit account/place/booking/admission/completion identities, open-choice dependency list, one owner for shared seams | Do not implement a disputed policy by guessing. Unblocked contract and feasibility work may proceed when implementation is separately authorized. |
| 1. Two foundations | Data/rules transaction + history proof in parallel with actual app/Clip/browser identity and invocation proof; compile each native host with only its selected dependencies | If the Clip/provider/install path cannot support the approved journey, bring back the demonstrated alternative before expanding feature work around it. A simulator screen is not this gate. |
| 2. First real integration | One controlled guest performs verified RSVP through an actual supported surface; all hosts resolve the same account and booking; lost-response retry returns that operation | No fully mocked integration milestone. Record which public/provider variants remain unverified and make them release blockers. |
| 3. Parallel journey packages | Before-event/door and after-event/map complete their cross-surface paths and tests, integrating through the shared contracts | Serialize shared migrations, app root/project/auth/history seams; rebase/merge small slices rather than one late combined branch. |
| 4. Joined candidate | E01–E12 with one set of real test records, security/regression suites, performance baselines and real staff-device offline proof | No screenshot-only or stitched-mock pass. Failed or blocked approved cases remain visible and keep activation closed. |
| 5. Compatible distribution | App, Clip, web, console, backend, domain association and worker/provider configurations agree on contract and access behavior | Public main-app availability alone is insufficient. Keep public Events entry inactive until its own compatible Clip/app/web path passes. |
| 6. First event readiness | Staff rehearse roster download, scanning, manual fallback, outage and reconciliation; test reminder/recap delivery to controlled phones; confirm venue consent/location schedule | Name an event operator and a technical incident owner. No fabricated admissions or loss of offline queue work when connectivity fails. |

The existing App Store release work is separate. The dated September 14 checkpoint says build 173 was waiting for review with manual release; verify its current public status before any Events activation rather than assuming that checkpoint is current or that Events exists in that build.

## Distribution inventory

- **Database:** additive Events schema/RPCs and current grants/RLS, applied in a serialized order; old app contracts remain valid. Verify exact hosted migration state and extend required rollback-only smoke coverage for every changed client RPC. Run independent-session contention tests in isolated disposable data separately.
- **Workers and storage:** provider-specific settings, callback verification, lease/retry settlement, due-work scheduling, protected media/range delivery and derivative cleanup. Configure credentials in the intended service environment; never ship service-role/provider secrets in native, Clip or browser bundles. Provider selection and exact supported behavior require proof, not a guessed SDK capability.
- **Guest web and console:** separate guest/admin routes and bundles against compatible backend contracts; domain/hosting choice is implementation setup, not permission to create a new independent Events backend. Console authorization is backend-enforced Team admin membership, not URL secrecy. Test actual supported staff browser storage/camera behavior.
- **Full app and App Clip:** XcodeGen-owned targets, selected shared sources, actual SDK compatibility, app/Clip association, entitlements, registered identifiers, signing and archive configuration. Record release-candidate identities and compatible versions. Do not transplant full-app store/map/import dependencies into the Clip to get a build to compile.
- **Canonical link and public invocation:** choose/configure the real event domain, serve its required association data, register the Clip experience and verify installed-app routing, no-app Clip invocation and browser fallback using real links. `{event_link_domain}` is still a placeholder. Verify current Apple/provider requirements at implementation time.
- **Identity and messaging:** same canonical account on each surface; authoritative current-phone proof; Apple/Google credentials and redirect configuration; event SMS and optional marketing consent kept separate. Record actual controlled delivery versus provider acceptance and mere outbox enqueue.

## Activation controls and compatible rollout

The native app already has a typed feature-flag registry in `Wander/App/FeatureFlags.swift` and `docs/feature-flags.md`. Use that platform for Events client rollout if flags are added: registered bounded definitions, corresponding hosted rows/constraints, standard backend reads and next-launch account-scoped device overrides. Never add an unrelated preference or unregistered remote key. The exact flag names belong in the shared contract implementation.

Native flags control presentation/rollout; they are not security checks or instantaneous emergency stops. A running app may retain its launch snapshot. The server independently enforces identity, booking, admission, publication and authorization on every relevant command/read. Browser and Clip eligibility likewise cannot be inferred from a client toggle.

Plan additive compatibility first, controlled tester activation second, and public activation last. Use an explicit deployment manifest listing the compatible backend contract, full-app/Clip builds, web/console revisions, association configuration, worker revision and enabled capabilities. An older client must not turn an unknown response into confirmation or expose private data.

For incident control, separate **stopping new work** from **preserving existing commitments**. An operator can stop intake where the selected console policy permits it; stopping new registrations must not erase existing confirmations, valid offers or unresolved offline admissions. If a specific mutation/delivery/media path must be unavailable, return an explicit retryable state and preserve durable records. The exact business consequences of event cancellation, issued-offer edits and media unpublication remain the open product choices; a technical disable switch does not settle them.

## Rollback and recovery

| Failure | Recovery contract |
| --- | --- |
| New app/Clip distribution fails | Keep public activation closed; retain the last compatible released clients. No backend data removal is necessary. Existing installed users retain their previous ordinary app experience. |
| Web/console deploy regresses | Restore the previous compatible bundle. Preserve versioned offline storage/queues across refresh and rollback; do not force-clear browser data or overwrite pending admissions. |
| Additive backend change fails before use | Stop deployment, inspect the exact schema/grants state and use a reviewed forward correction or safe rollback. Do not blindly reverse shared migrations. |
| Backend change fails after real bookings/admissions exist | Disable affected new work as narrowly as possible, preserve event/account/place/booking/admission/completion records and operation history, and forward-fix compatible access. Never delete the event tables or reset attendee data to “roll back.” |
| Provider outage or uncertain send | Retain durable intents and per-delivery accepted/unknown/retryable/terminal results. Resume through the selected provider-safe reconciliation contract. Do not replay the entire batch or claim receipt from enqueue success. |
| Media or permission defect | Suspend the affected delivery path, invalidate product-managed protected caches as applicable, preserve metadata/tombstones and investigate the authorization boundary. Do not make a private storage bucket public to recover speed. Already exported copies cannot be recalled. |
| Door connectivity disappears | Use only a previously prepared qualifying roster and installed-app guest checks under D9; persist pending admissions before acknowledgement. Preserve unavailable/no-match/help states when prerequisites are absent. |
| Offline reconciliation conflicts | Keep per-row conflict/unknown work; an authorized Team admin resolves it using current server facts and the reviewed procedure. No local row independently unlocks recap. Never delete unresolved rows to make the queue look clean. |
| New client rewrites old local data | Prevent through versioned migration/older-fixture tests; preserve a recoverable compatible snapshot and avoid unreviewed destructive migrations. Restoring a binary cannot reverse arbitrary data loss. |

Backups and restore procedures must be verified for the actual environment before the first live event. Capture recovery ownership and last known compatible versions; do not make an untested recovery-time promise. No production backup, deletion or reset is performed by this planning review.

## CI and merge gates

Each implementation slice includes its targeted native/database/worker/browser assertions. Run the repo-required native suite and hosted RPC smoke where applicable; record environmental blockers as blockers. Extend build/test jobs for the new Clip/web/console surfaces. The existing TestFlight-manifest workflow only classifies changes; it does not replace build/runtime or security tests.

Public activation requires the joined functional/device/provider evidence and performance baselines from the test/measurement plans. Resolve the applicable open product clauses before asserting their exact behavior. Prioritize failures that violate account ownership, privacy, seat/code invariants, truthful delivery, durable admission or canonical history regardless of latency.

Use a short-lived branch and PR for each bounded slice. A documentation merge does not start implementation, and an implementation merge does not authorize a TestFlight/App Store release. Follow the repository's explicit release workflow when the user requests those operations.

## Operational evidence

Before a live event, record the event's current schedule/time zone/cutoffs; venue permission/reveal configuration; staff accounts and actual hardware; prepared-roster status; QR/manual fallback rehearsal; message-program configuration and controlled delivery proof; current outbox/reconciliation backlog; recap publication/upload/removal rehearsal; and the incident owner.

Operational dashboards may show counts, coarse outcomes, oldest pending age, timing and compatible build versions. Keep phone values, precise home coordinates, auth tokens, private feedback and protected message/media contents out of shared logs. Put exact test evidence in the authorized test store, not a public analytics payload.
