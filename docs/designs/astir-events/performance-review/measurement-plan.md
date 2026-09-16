# Astir Events — performance measurement plan

Prepared September 15, 2026 under D18A. **Planning only: no Events timing, memory, database-load or delivery benchmark has run.** The implementation does not yet exist. Targets below are provisional engineering checks for calibration in the foundations, not approved attendee limits, upload limits, operating promises or measured service levels.

## Existing measurement tools

- `WanderUITests/MapFilterInteractionUITests.swift:242` uses the actual app and map performance fixture; `:274` measures clock/CPU. Extend the fixture with event annotations without replacing ordinary pins.
- `WanderTests/WanderStoreTests.swift:6655` checks coalesced feed refreshes and warm-content reuse. Apply the pattern to Events request counts with its stricter protected-state contract.
- `scripts/benchmark-map-projection-cache.py:1` extracts the real Swift cache implementation for a host microbenchmark. It explicitly does not measure MapKit frame pacing, cold launch or physical-device memory.
- `docs/reviews/rec-441-performance.md` records earlier controlled progressive-loading and map measurements. They are historical results for another change, not Events baselines or proof that the latest app passes. Reuse the measurement methods and preserve the implemented optimizations.

No new benchmarking service is needed. Extend existing native test fixtures, add an isolated database/browser/worker fixture runner, and use physical-device traces for the platform paths that a host microbenchmark cannot represent.

## Fixture ladder

Run the same permission, identity and state invariants at each size. Use synthetic identities and inert message recipients.

| Fixture | Purpose |
| --- | --- |
| 30 guests, a small gallery, one active event | Reflect the roadmap's 30-friend beta scale; this is a test size, not the event capacity decision. |
| 300 guests, 1,000 media metadata entries, concurrent events at a place | Detect per-row network work, unbounded image decoding, background contention and ordering problems. |
| 3,000 synthetic guest records; long history across multiple events | Stress query plans, pagination, roster preparation and graceful failure. Passing is not a promise to support that event size. Failure identifies a limit to resolve or explicitly document before selling that scale. |
| Existing dense map plus Events annotations | Retain the repository's 1,500-pin measurement fixture and add events at shared/distinct places, long titles and varying visibility. |

Content fixtures include large source photos, portrait/landscape media, and video files large enough to expose whole-file memory loading. The selected product upload-size/duration policy remains separate; do not silently impose a cap in the test plan. Keep byte throughput separate from metadata latency.

Use the eventual supported-device matrix: at least the oldest supported physical-device class available for release validation and a typical current device. Record exact model, OS, browser, build configuration and cold/warm state. A simulator run cannot certify the physical device.

## Measurements and provisional gates

The implementation owner must record an environment-specific baseline and calibrate numeric targets at the early integration checkpoint. Correctness/privacy gates are mandatory independent of speed; a deadline or fast response never justifies incorrect admission, extra capacity or stale protected data.

| Path | Measure | Provisional target or invariant |
| --- | --- | --- |
| Public event entry | Invocation/download/OS launch, first permitted event content and actionable sign-in separately | Event content must not wait for full guest-list/gallery/ordinary app hydration. Record public invocation separately from local and TestFlight runs. Set an absolute cold-entry target only after the actual Clip is built. |
| Event/guest-list/gallery page | Server duration, API payload, network request count and first useful content | In a stated test network, aim for p95 warm metadata read within 1 second. Request count for one page stays bounded as total record count grows. Media download and auth UI are separate intervals. |
| RSVP/offer/cancel | Validated submit to authoritative outcome, lock wait, transaction duration and retry outcome | Aim for p95 within 2 seconds under the chosen 300-guest burst fixture. Exclude human/provider phone verification time; record it separately. No provider send/upload occurs while a capacity lock is held. |
| Online door | QR decoded to authoritative admission result, independent of camera acquisition | Aim for p95 within 1 second on the declared network with two and ten simulated operators. Full scan-to-result also reported; do not hide camera or connection delays behind this metric. |
| Offline door | Roster preparation bytes/time; indexed lookup; durable queue acknowledgement; reload and sync | Aim for p95 local lookup plus durable write within 250 ms on intended staff hardware. Never show success before persistence. Report complete-roster readiness and storage errors explicitly. |
| Message burst | Commit-to-enqueue, due-to-claim, claim-to-provider acceptance, provider receipt where available | Capture p50/p95 and oldest queue age for 30/300 recipients, partial failures and retry backlog. Preserve recipient consent/current event state. Delivery target awaits the provider proof; do not infer physical SMS receipt from accepted jobs. |
| Media scrolling/playback | Decoded images, encoded buffers, active transfers/players, memory high-water mark, growth across repeated visits | Bound in-flight work and cache bytes. After leaving/repeating the flow, memory must settle rather than grow with total gallery size. First-page request must not download all originals or videos. Establish a device budget from actual traces before release. |
| Event map | Projection rebuilds, annotation changes, query count, frame gaps and panning during delayed loading | Preserve stable-cache hits and viewport behavior. Compare Events off/on on the same device and fixture. Treat repeatable degradation greater than 20% as an investigation trigger, not as permission to regress by 19%. |

Numeric targets are hypotheses to make failures visible. If baseline results require a different budget, record the evidence and the user-visible consequence; revisit product expectations when the compromise materially affects the journey.

## Load and query procedure

1. Build isolated synthetic fixtures and run authorization/correctness checks first. Never benchmark by sending real guest messages or inserting live bookings.
2. Measure cold and warm separately. Report cache hits, misses and permission-invalidated reads. No warm-cache benchmark may skip current access validation.
3. Run one-page reads against increasing total history and count actual database/API work. Add account/state/time filters and stable cursor traversal to the plan before choosing concrete indexes; verify candidate indexes with query plans under representative permitted roles, not only a privileged session.
4. Use multiple database sessions with controlled contention for last-seat/code/offer races. Record lock wait and transaction time separately; provider calls must not hold those transactions open. Performance failures never weaken atomic allocation.
5. Keep message claims, media processing and roster preparation bounded per batch. Measure oldest pending job, retry distribution and shared-pool pressure while RSVP/scanning proceeds; a fast enqueue hiding a growing queue is not a delivery pass.
6. Run browser/native memory and network traces during scrolling, opening/closing, account changes, cancellation and delayed responses. Validate stale requests cannot publish or repopulate a protected cache.
7. Capture raw sample count, p50/p95, failure/timeout rate, payload/query counts and exact fixture/build/environment. A timeout is a failure, not a sample to discard. Compare enough repetitions to separate a repeatable regression from device/network noise.

## Planned test and evidence locations

Proposed files, not created application tests:

- `WanderTests/Events/EventLoadingPerformanceTests.swift`: first-content gating, bounded request counts, cancellation and account-fenced coalescing.
- `WanderTests/Events/EventMapPerformanceTests.swift`: Events projection/cache invalidation and ordinary-map regression fixtures.
- `WanderUITests/Events/EventMediaPerformanceUITests.swift`: long gallery/large media fixtures, interaction and lifecycle measurements.
- `scripts/events/performance-load.mjs`: isolated query, concurrent transaction, API payload and worker-queue measurements; no live recipients.
- `events-web/tests/console/offline-performance.spec.ts`: complete roster preparation, local lookup/write, reload and reconciliation.
- `docs/testing/astir-events-performance.md`: exact device/provider setup, results and unresolved gaps.

Existing 121-case mapping remains the functional source. These measurements supplement I07, B05/B10–B15, M09–M14, A07–A11, P05/P13–P15, V01–V08 and technical risk groups; a fast test cannot replace them.
