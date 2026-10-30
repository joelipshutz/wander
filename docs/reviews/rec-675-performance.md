# REC-675: Performance review

Issue: [REC-675](https://linear.app/recme/issue/REC-675/reduce-app-wide-interaction-latency-by-at-least-50percent-without).
Baseline: `2bb08f8e47`. Branch: `codex/rec-675-app-performance`.

## Acceptance and current validation

**Draft: the real Live ≥50% latency target remains unmet.** Component gains and
responsive import checkpoints do not establish a 50% improvement in complete
launch, Feed, or map gestures. The reported device is iPhone 15 Pro / iOS 26.5 /
TestFlight 185. Physical installation and profiling are newly authorized. The
paired phone has Developer Mode enabled, but the native connection is currently
unavailable. Physical comparison is pending a usable connection; no app has been
installed and no physical measurements have been collected.

Current validation status:

- Final native unit gate: **3,542/3,542 passed**, zero failures or skips. This
  includes all three 1,500-row stress cases, deferred-tab hosting, owner/manual
  recovery, both snapshot memo field matrices and the mounted scrolling/import
  workload. The four process-global SDK cases are required separate runs.
- Final optimized Release gate: **11/11 passed**, zero failures or skips.
- Focused route/tab/launch UI: six journeys passed. Compact unprimed manual-edit
  and filter-edge gate: **3/3 passed**. Earlier compact drawer/zoom checks passed
  **2/2**; those checks are distinct from the full unit run.
- Final-source fresh-host replay validation: **4/4 passed**, retaining exact
  host admission, compiler receipts, capture and privacy assertions.
- CI routing/receipt tooling: **67 tests passed**. Required SDK isolation and
  separate long 1,500-row stress dispatches retain exact test/device/result checks.
  Stress dispatches use the existing 600-second default / 900-second maximum
  performance allowances; ordinary unit deadlines and assertions are unchanged.
- The matched original-build mounted Feed/import comparison completed: its one
  test failed six responsiveness assertions; content and durable-file parity
  checks passed. The candidate passed the same workload. Details below.
- Review-storage and diff whitespace checks pass. Final-head CI remains pending.

At the previous pushed head, actual Feed replay drew native frames but did not
deliver a new decoded frame within its existing drain deadline in two broad CI
runs. A compact Filters first press also timed out once locally; the same harness
passed on baseline, and subsequent candidate combined-filter and edge checks
passed. Neither intermittent cause is established. The four final isolated local
passes do not explain the earlier broad-run failures; final-head CI remains open.

Historical validation at `434456ea51`, before the async import implementation:
3,438 total tests (3,413 unit + 25 UI), 3,433 passes / five failures. All five
subsequently passed focused checks: two source-contract corrections, drawer
stress, and both pagination paths. The intermediate focused gate had 165 passes /
two pagination timeouts; final manual pagination passed 8/8. Its fixture accepts
viewport polygons, selects Past 24 hours to exercise older/all stages, scrolls to
pagination controls, and awaits the final page within the existing 15-second
bound. This history is not a single green full-suite rerun. That revision also
passed six selected Release benchmarks, 33 AstirClip tests, two compact-phone
UI checks, and the 29-test pixel/transition rendering gate.

## Durable imports and startup

Times below are medians on the same iOS 26.5 Simulator. Final Debug imports use
three samples collected during the full unit gate; the original baseline used the
same portable fixture in a focused run. Startup includes deferred tabs. Fixture setup and final decoding assertions are outside timing.
Import timing includes the real coordinator, library/import file writers, and
final durability drain. The heartbeat runs on the main actor and samples every
1 ms; a reported gap is the median of each sample's maximum observed gap.

| Workload | Matched baseline | Candidate | Interpretation |
| --- | ---: | ---: | --- |
| 500 resolved Wanna rows + list, complete durable import | 49,928.479 ms | 7,488.458 ms | 85.0% less elapsed time |
| Same import, maximum main-actor heartbeat gap | 50,048.525 ms | 35.068 ms | Long single-transaction stall removed in this fixture |
| 1,500 resolved Wanna rows + list, complete durable import | No matching run | 95,955.223 ms | Absolute result only; throughput remains slow |
| Same 1,500-row import, maximum heartbeat gap | No matching run | 96.403 ms | Residual main-thread tails remain |
| Native launch / first frame | 6.183081 s | 2.858669 s | 53.8% faster |
| Launch to Live-ready accessibility state | 16,802.678 ms | 9,521.709 ms | 43.3% faster; below target |

The full AX readiness timer includes synchronous XCTest launch/idle handling and
subsequent accessibility queries. Existing activity timestamps show launch-call
medians of approximately 12.794 to 5.457 seconds, followed by approximately 4.028
and 4.065 seconds of readiness probing. Each launch passed its first pin-count
and snapshot attempt. This explains the metric boundaries; it does not redefine
the 43.3% AX result or attribute the remaining time entirely to test overhead.
Simulator startup uses a fictional signed-in fixture; it does not validate normal
configured-account authentication, backend bootstrap, or physical-device startup.

Import fixtures start with 100 existing saves and 20 overlaps, and verify all
500/1,500 source-ordered receipt entries, Added/Existing outcomes, saves, list
memberships, silent notification policies, and both decoded final files. The
500-row result has 580 saves and 500 memberships. The 1,500-row measurement has
no completed identical baseline, so no paired speedup is claimed. Its final disk-backed
96.0 seconds must not be compared as an improvement over older in-memory tests.

Earlier synchronous Debug coordinator diagnostics were 31.970 seconds with a
list and 19.599 seconds without a list at 1,500 rows. Those excluded disk work and
predate chunking; they are historical attribution evidence, not current latency.

A separate integrated diagnostic mounts the real 600-event Feed on a 1,620-save
library while importing 200 new places into actual files and scrolling natively.
Before narrowing bookmark projection it measured 39.744 seconds, maximum display
delivery gap 477.254 ms, and heartbeat gap 253.143 ms. The later single sample was
28.157 seconds, 307.034 ms, and 209.605 ms respectively. Both retained all events,
receipts, memberships and decoded files, and rendered partial progress. These are
single Debug diagnostics, not a matched baseline acceptance claim; substantial
pauses remain. The later harness verifies its private Release-compatible Feed
and photo fixtures against the original Debug helpers outside measurement;
photo byte parity runs afterward so it does not prewarm the measured workload.

The same mounted fixture in Release measured 25.631 seconds, maximum display gap
264.610 ms, and heartbeat gap 155.399 ms. This confirms residual pauses in optimized
code; it is still one diagnostic sample. Three-sample Release actual-file medians
were 6,928.020 ms / 30.894 ms maximum heartbeat for 500 rows, and 92,387.284 ms /
78.063 ms for 1,500 rows. There is no matching Release actual-file baseline.

A separate 25-second Release profile attributed 39.0% of sampled main-thread work
to snapshot capture, 18.1% to SwiftUI Observation dependency replacement, and 7.5%
to bookmarks. These are sampled CPU shares, not elapsed-time percentages. A
run-owned snapshot-record memo reduced the earlier Feed-only Release diagnostic
from 25.631 to 19.743 seconds and the maximum display gap from 264.610 to 211.988 ms;
the 500-row actual-file median fell from 6,928.020 to 5,465.537 ms. Twelve native
regressions passed for all 67 Place/UserPlace DTO fields, managed model changes,
exact representation, cancellation/account/lifetime boundaries and failed writes.

The stronger fixture now includes both production Root import reconciliation
callbacks, using the same fresh authorized six-field duplicate projection as the
app. Four cold/oracle regressions passed; the complete focused gate passed 30/30.
This changes the workload and must not be compared directly with older Feed-only
timings. Its default Release diagnostic took 29.217 seconds, with display gaps
of 110.884 ms p50, 163.149 ms p95 and 293.853 ms maximum. It observed 200 library
acknowledgements, 201 revision callbacks and 400 item callbacks. The latter reflect
ready-to-duplicate classification while the library write is pending, followed by
saved after acknowledgement; those visible transitions are preserved.

Diagnostic 1 ms and 10 ms post-acknowledgement suspensions did not materially
improve those display gaps. Neither pacing change is included. A separate profile
found attribute/visit snapshot construction at 1,487 of 13,745 sampled main-thread
samples (10.8%); a final extension reuses those records through the same observed
cache. The final optimized run passed 11/11. The stronger mounted workload measured
25.943 seconds with display gaps of 87.613 ms p50, 148.496 ms p95 and 243.353 ms
maximum. These remain visible pauses under simultaneous scrolling/import load.
Final actual-file Release medians were 5,264.291 ms (500 rows) and 67,261.120 ms
(1,500 rows), with median maximum heartbeat gaps of 28.439 and 76.364 ms. All eight new regressions for the 30 added fields passed in the final 3,542-test
native gate. The full memo covers 97 persisted fields across four record types.

The original build and final candidate also ran the **same stronger Release
mounted workload once each**: 200 imports, 600 Feed events, 1,620 initial saves,
real file writers, native scrolling and both original Root reconciliation triggers.
Only unavailable candidate APIs were adapted in the baseline test; its Root
callback uses the original full authorized projection. No pacing was added, and
no shared functional or responsiveness assertion was relaxed.

| Mounted Feed + import, one sample per build | Original baseline | Final candidate | Change |
| --- | ---: | ---: | --- |
| Complete import elapsed | 27,892.132 ms | 25,943 ms | Approximately 7.0% lower |
| Maximum display-link delivery gap | 27,975.592 ms | 243.353 ms | 99.13% lower |

Baseline's six failures were zero during-import display ticks, scroll movement,
partial renders, revision callbacks, item callbacks and offset span. Its maximum
heartbeat gap was 27,963.480 ms. Subsequent checks passed for all 600 Feed event
identities and order, 200 receipts in source order with matching saves and
memberships, silent notifications, unchanged visits, and both decoded files;
200 receipts were durable. Its
single display-gap observation arrived after completion, so its identical p50/p95
values do not describe a smoothness distribution. The candidate retained these
checks and showed live progress. This is evidence of removing the monolithic
freeze, **not** a 50% throughput gain or an FPS claim; candidate 243 ms tails remain.

## Implementation and preserved contracts

- Lists and Profile defer first construction until selected, then retain their
  normal identity and navigation state. Selection constructs content in the same
  render. Existing pending notification/calendar consumers are unchanged; six
  actual route/tab/launch journeys and four hosting regressions passed.
- Bookmark state uses the existing authorized local/remote merge with only the
  required owner, identity, and status fields. Foreign content, attributes, visit
  enrichment, and unused filtered list indices are not prepared for this icon.
  Five cold-path oracle/Observation tests retain first-match, alias, Been/Wanna,
  tombstone, account, permission, and relevant-mutation behavior.
- Automatic saving now performs bounded synchronous chunks, then closes every
  persistence/projection scope before awaiting an ordered atomic library write.
  The default row-work budget is eight rows / 10 ms. Snapshot capture and import
  JSON publication remain synchronous and are outside that budget: **10 ms is
  not a hard maximum hitch bound**, as the measured tails demonstrate.
- Each library checkpoint contains its saves and an immutable recovery journal.
  Only a successful acknowledgement permits the separate import file to advance
  saved rows, receipt outcomes, or completion. Failed writes preserve retry
  evidence. Recovery reuses original save IDs and Added/Existing outcomes instead
  of saving again. Completed journals retire only after final import-file success;
  a delayed cleanup write can leave redundant evidence without replaying a
  completed batch. No timer debounce weakens checkpoint durability.
- Run UUID, owner, batch identity, and lease checks fence cancellation, account
  changes, replacement tasks, and callbacks after awaits. Frozen input plans keep
  later user edits for review. Manual receipt removals/status/list changes and
  explicit destination choices survive recovery; local/server aliases preserve
  pending destinations through sync. Same-batch strict duplicates cannot undo a
  manual choice. Unrelated provider identities and separate batches remain independent.
- One run-owned context retains strict lookup, streak, and list projections.
  Snapshot records reuse the existing complete DTO initializers under Observation
  for places, saves, attributes and visits. Every capture walks current arrays in
  order, preserves duplicate object/ID behavior, rebuilds dirty records, and prunes
  removals. Ownership loss uses fresh records; finishing releases registrations.
  The memo records values, never write-success state.
  It installs ambient projections only inside synchronous scopes, restores them
  before suspension, and finishes observations at run exit. Fresh model identity,
  owner, permission, membership, locale, and observed grouping inputs invalidate
  reuse. Streak source inputs remain fresh; only identical calculator inputs
  reuse results. Async checkpoints reuse immutable snapshot records for calendar
  fingerprints and recapture after synchronous authority-loss observers mutate data.
- Google resolution refills the existing six-request limit; social work remains
  serial and source expansions preserve ordering. Exact per-item JSON encoding
  reuse retains synchronous full atomic import snapshots, including Unicode and
  signed-zero fidelity. Cache retention is bounded to 4,096 rows / 8 MiB; oversized
  histories use durable resolver waves to avoid per-completion write amplification.
- Live/Feed/profile/widget changes reuse authorized projections and bulk indices,
  avoid unchanged native setter/publication work, and retain ordering, alias
  precedence, mutable-model invalidation, calendar/timezone boundaries, and viewed
  expiry. Compact pins reuse existing artwork while preserving hosted interaction
  transitions and native hit targets. Date formatter configurations are bounded;
  rendered date strings remain uncached.
- Official PostHog [3.68.3](https://github.com/PostHog/posthog-ios/releases/tag/3.68.3)
  contains the [replay scheduling/mask fix](https://github.com/PostHog/posthog-ios/commit/910b82c).
  The paired baseline used 3.61.0. Production one-second replay cadence, masks,
  resolution, sampling, and app settings are unchanged. No backend schema,
  feature removal, production content limit, or product analytics event change is introduced.

## Historical matched performance evidence

Debug component/rendering rows are earlier staged checkpoints. The Release table
below uses the final implementation, including durable import chunks and observed
snapshot-record reuse, against the original portable baseline workloads. These are
scoped improvements, not complete Live acceptance. Medians are milliseconds unless noted.

| Historical Debug component | Baseline | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| Live projection, 300 events / 1,000 own + 1,000 list histories, disjoint | 3316.38 | 151.91 | 95.4% |
| Same projection, overlapping identities | 2577.42 | 166.41 | 93.5% |
| Feed sections, 600 events / 20 reads | 104.58 | 38.16 | 63.5% |
| Remote visibility, 1,620 rows | 123.72 | 10.68 | 91.4% |
| Calendar reconciliation, 1,500 omitted rows | 829.24 | 34.82 | 95.8% |
| Planned reminders, 1,500 saves / three reads | 6357.02 | 39.85 | 99.4% |
| Legacy JSON decode + restore, 1,620 saves | 890.02 | 294.87 | 66.9% |
| Candidate matching, 600 calls | 1547.14 | 1451.12 | 6.2%; below target |
| Mounted 300-pin initial mount | 311.195 | 108.049 | 65.3% |
| Mounted pins, six density redraws | 969.305 | 441.906 | 54.4% |
| Mounted pins, process CPU | 369.704 | 312.092 | 15.6%; below target |
| Older timestamps, 1,200 calls | 82.851 | 1.709 | 97.9% |

| Final Release workload | Baseline | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| 500-row autosave + list, excluding disk I/O | 44013.18 | 2783.46 | 93.7% |
| File-backed 1,500-row snapshot / 18 uneven resolver requests | 802.87 | 262.03 | 67.4% |
| Same resolver workload, first ready | 217.00 | 39.31 | 81.9% |
| Mounted profile, 1,500 saves | 3604.69 | 561.37 | 84.4% |
| Widget publication, 1,500 visits | 145.16 | 39.03 | 73.1% |
| Unchanged repeated widget publication | 115.25 | 15.41 | 86.6% |
| SDK callbacks, 20,000 enqueues only | 37.905 | 1.334 | 96.5% |

Release used standard optimization with `ENABLE_TESTABILITY=YES` and a unit-only
benchmark scheme: six selected cases on baseline and eleven on the final candidate,
including the common workloads plus candidate durability/stress diagnostics. It was
not a full Release test suite. Both revisions ran arm64 on the same destination.
The profile includes mounted UIKit/SwiftUI layout; widget timing includes
publication/disk/reload requests, not extension rendering. Current 1,500-row
coordinator medians excluding actual file I/O were 24.991 seconds with a list and
18.899 seconds without; there is no matching baseline for those sizes.

Historical complete Live gestures remained below target: Feed CPU 3.251→3.258 s
and map pan/zoom CPU 9.148→9.133 s showed no material improvement. The matched real
600-event Feed performs 180 native scroll frames: no-replay layout 567.716→401.689 ms
(29.2% less), replay layout 155.988→84.736 ms (45.7% less), with elapsed time near
three seconds on both builds. That frame floor is not a 50% interaction gain.

The separate synthetic 200-masked-row SDK fixture exposed growing baseline work.
Final Release elapsed median fell 25.389→3.798 s (85.0%) and layout
18.488→0.477 s (97.4%). Actual native draws and decoded fixture images were required.
**The real Feed did not reproduce that pathology.** One historical Feed sample
needed 4.864 seconds of encoder drain after timed scrolling. Callback enqueue
measurements exclude worker drain; encoded-frame counts are not FPS. The current
four fresh-host replay proofs passed with capture/privacy assertions retained.

## Reproduction and remaining gate

Use identical portable benchmark sources, fixture/auth identities, sample order,
and simulator destination for baseline and candidate. Xcode 26.6 / iOS 26.5
Simulator supplied these measurements. Run serially with no competing builds,
separate derived data per revision, and `-parallel-testing-enabled NO`.
After XcodeGen generation, focused import selection is
`-only-testing:WanderTests/ImportAutoSaveFileResponsivenessTests` on scheme `Wander`.
Keep candidate-only checkpoint/context tests separate from the baseline checkout.

Required fresh-process replay suites are `replay-private`, `replay-credentials`,
`replay-feed`, and `replay-masked-scroll` through `scripts/run-parent-regression.py`.
Explicit fixture-host requests must pass admission before constructing fictional
views; offline transport, production capture settings, decoded-frame proof, and
privacy/OCR checks remain. Diagnostic image capture is opt-in and excluded from
comparable timings. No assertions, masking, sampling, or capture fidelity were relaxed.

Before acceptance: verify final-head CI and obtain a usable native connection for
the approved physical comparison across launch/auth/bootstrap, large Feed/map
journeys, profile entry, and imports. No physical timing is available yet.
Attribute any remaining critical path before
claiming the requested ≥50% real Live improvement. Atomic-write tests do not
simulate power loss beyond the platform's atomic file-write contract.

Raw traces, result bundles, screenshots, and replay captures stay outside Git in
the issue evidence directory. This report keeps aggregate results and exclusions:
unmounted/misconfigured profile fixtures, incomplete widget counts, and unsettled
map/identity harness attempts are not accepted measurements. The worktree project
was opened in Xcode and its branch verified; this does not change draft status.
