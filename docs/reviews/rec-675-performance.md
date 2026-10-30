# REC-675: App-wide performance pass

Issue: [REC-675](https://linear.app/recme/issue/REC-675/reduce-app-wide-interaction-latency-by-at-least-50percent-without).
Baseline: `2bb08f8e47`. Branch: `codex/rec-675-app-performance`.

## Status and acceptance

**The real Live ≥50% performance target remains unmet; this change remains a
draft pending physical-device profiling and remaining validation.** The full
native gate completed **3,438 tests: 3,413 unit + 25 UI, with 3,433 passes and
five failures** (two unit source-contract failures and three UI failures).

The two source-contract failures were corrected and passed in the handoff
focused gate. All manual-pagination fixture regressions passed, and the corrected
drawer-stress test passed. That focused gate finished **165 passes and two
pagination UI timeouts**. All three original UI failures also reproduced on
unchanged baseline. The identical pagination-fixture corrections are now being
compared on baseline; **the two pagination cases remain unresolved**, and no
complete passing final gate is claimed. Latest Release, AstirClip, and compact-pin
validation remain pending.

Earlier checkpoints remain scoped evidence: v4 passed 3,370 unit tests; focused
v5 passed 86 tests including actual SDK capture and privacy/OCR checks; matched
optimized Release gates passed all six selected benchmarks on both builds.
Render-v10 passed all 29 tests, including compact-pin pixel/transition coverage
and the paired Feed benchmarks. Matched Live launch improved about 30%, while
complete Feed/map gestures did not establish the requested gain. Results below
identify their revision/configuration instead of treating earlier checkpoints
as measurements of later changes.

The target is at least 50% less latency on dominant reported slow paths without
losing content, ordering, authorization, durability, or interaction behavior.
The reported device is iPhone 15 Pro / iOS 26.5 / TestFlight 185; the fixes target
shared behavior across devices. Simulator improvements do not establish a
physical-device launch, frame-rate, or across-the-board interaction improvement.
Remaining long imports and the below-target paired UI results prevent claiming
that the complete acceptance target has been met. A matching physical device is connected,
but installation has not been authorized and no physical-device metrics exist.

## Implementation and preserved behavior

- Live identity matching probes the smaller membership collection against the
  other's existing alias index. One immutable display projection supplies pin,
  activity, and RPC-seed indices. Native annotations skip unchanged preparation;
  density work still responds to content, selection, geometry, and mounted-view
  changes, and visible views refresh viewed expiry and relative timestamps.
  Unchanged native interaction, POI-selection, and user-location settings are
  no longer rewritten. A setter-tracking regression covers both transition
  directions and camera/interaction provenance; this does not independently
  establish a fix for the map gesture issues encountered by the UI harness.
- Feed sections reuse grouping only after reevaluating leases and mutable
  filters. Ordered activity/place/ticket-kind/stage inputs protect model edits;
  account, audience, query, page, and limits invalidate reuse. Exact lease expiry
  remains authoritative, and future events retain time-dependent rebuilding.
- Remote visibility, omitted-calendar-row reconciliation, reminders, and legacy
  snapshot attributes use temporary indices that preserve the original alias,
  first-match, ownership, and ordering rules. Live, Feed, Discover, saved-place,
  and import-review views use bulk attributes and one history projection per
  render. Single-save APIs retain their existing behavior.
- Widget publication selects and deduplicates calendar parents/visits once for
  three months, avoiding unused profile map/category/city work. It preserves
  independent month interval endpoints, timezone rules, and mutable input reads.
  Snapshot format, freshness policy, atomic writes, and reload requests remain.
- Import completion updates rows in one pass. Strict candidate and list
  insertion projections exist only inside synchronous transactions; value
  checks preserve direct model edits, first matches, alias bridges, tombstones,
  membership order, and account isolation. Saves and list insertions remain in
  their original sequence. Receipts, silent notifications, per-save analytics,
  and durable transaction snapshots are retained.
- Import streak work memoizes only `Date` to calendar-day conversion inside the
  synchronous import scope, resetting for calendar changes. Every read still
  gathers live dates and runs the complete streak calculator. Ledger/recovery
  appends, celebrations, and events are unchanged. Wanna/deleted visit summaries
  skip a read-only history scan that their existing early return never uses.
- Google resolution refills available slots within the existing six-request
  limit; small and social imports remain serial. Source expansion commits in
  source order. Run/claim identities fence retries, cancellation, callbacks, and
  cleanup. File persistence reuses encodings only for unchanged row values and
  exact text/numeric representations; every write remains a complete synchronous
  atomic snapshot, with cache commit only after success. Row encoding retention
  is capped at 4,096 rows / 8 MiB of encoded bytes. Oversized histories revert to
  the original durable resolver waves rather than multiplying full-document
  writes for each finished sibling.
- PostHog is pinned to official
  [3.68.3](https://github.com/PostHog/posthog-ios/releases/tag/3.68.3), containing
  the [replay scheduling and SwiftUI mask fix](https://github.com/PostHog/posthog-ios/commit/910b82c).
  The prior linked benchmark SDK is 3.61.0. App configuration, one-second capture
  cadence, masks, sampling, and screenshot resolution are retained. The focused
  v5 gate passed actual SDK capture/encoding and included image-level privacy/OCR
  validation; matched optimized Release capture also passed. The completed full
  native gate and unresolved pagination cases are recorded above. Latest Release
  and AstirClip validation remain pending. A newer SDK with changed capture resolution
  was not substituted for an
  equivalent workload.

No backend schema, feature removal, or new production content limit is
introduced. The 300-place / 600-event Live UI fixture is opt-in, Debug Simulator
only, and leaves stored place coordinates unchanged. Synthetic SDK fixtures use
fictional views and offline collectors, with no production replay upload.
The same four-flag, compile-time Debug + Simulator policy selects both the large
Live feed and its matching fake auth user; ordinary simulator sessions and
production hydration/authorization checks retain their behavior.
Only under that policy, pin accessibility metadata exposes the actual native
camera distance for the UI zoom assertion. It preserves ordinary pin values,
uses a weak map reference, clears that reference on reuse, and is absent from
Release/device builds. This is measurement instrumentation, not a camera command.

Additional rendering work follows the paired UI shortfall: Feed paging history
no longer publishes decision-only state for each scroll sample; a render shares
one freshly authorized section projection; photo lookups construct the same
request without unrelated place-sheet fields; empty shared-discussion
invalidation avoids redundant publications. Formatter configuration reuse is
bounded and retains current calendar/locale/timezone inputs. Compact pins reuse
the existing artwork while retaining native hit targets and hosted interaction
transitions. Corrected rendering passed the v10 pixel/transition gate. Earlier
v4/v5/Release timings do not measure these later changes. The full native gate
completed with the five failures described above; two pagination UI cases remain
unresolved after focused corrections. Latest compact-pin validation is pending.

## Established v4 projections and component timings

Xcode 26.6, Debug arm64, iOS 26.5 Simulator, dedicated iPhone 17 Pro simulator.
Baseline and candidate run sequentially with identical fixtures and destination.
Times are medians in milliseconds, three samples unless stated. Setup and
reference-oracle assertions are outside timing. These are bounded component
workloads, not substitutes for launch or gesture measurements.

| Workload | Baseline ms | v4 ms | Reduction |
| --- | ---: | ---: | ---: |
| Live projection: 300 events, 1,000 own + 1,000 list histories, disjoint | 3316.38 | 151.91 | 95.4% |
| Same projection, overlapping identities | 2577.42 | 166.41 | 93.5% |
| Feed sections: 600 events, 20 reads | 104.58 | 38.16 | 63.5% |
| Remote visible places: 1,620 rows | 123.72 | 10.68 | 91.4% |
| Calendar reconciliation: 1,500 omitted rows | 829.24 | 34.82 | 95.8% |
| Mounted place-profile host: 1,500 saves | 4011.62 | 676.66 | 83.1% |
| Planned reminders: 1,500 saves, three reads | 6357.02 | 39.85 | 99.4% |
| Widget publisher: first publication, 1,500 visits | 230.56 | 59.12 | 74.4% |
| Widget publisher: unchanged repeated publication | 171.95 | 18.11 | 89.5% |
| Import completion: 1,500 individual row updates in a transaction | 11029.48 | 2289.83 | 79.2% |
| Legacy snapshot JSON decode + restore: 1,620 saves, five samples | 890.02 | 294.87 | 66.9% |
| Current snapshot JSON decode + restore, five samples | 222.24 | 219.45 | No material improvement established |
| Candidate matching: 600 calls, five alternatives each | 1547.14 | 1451.12 | 6.2%; below target |
| Original individual attributes-plus-visits API workload | 3927.68 | 3976.04 | No improvement |

The mounted-profile measurement includes real SwiftUI/UIKit view hosting and
layout, not network fetches or an end-to-end user tap. Widget timing includes
the store projection, disk snapshot save/load, and reload request, not widget
extension rendering. All 1,500 canonical visits are asserted: 500 in each month.
Restore timing includes JSON decoding and model reconstruction, not disk read,
authentication, the splash screen, or complete cold launch.

Native-map coordinator preparation for 30 unchanged updates with 1,000 pins
fell from 216.07 ms to 0.10654 ms (five samples, 99.95%). This verifies stable
annotation identity but does not mount annotation views or measure frame rate.
The same-process bulk-attribute comparison measured 1978.58 ms for individual
reads versus 9.49 ms for the bulk API (99.5%); this is evidence for migrated
consumers, not a speedup of unchanged selectors. Bulk completion itself measured
2.23 ms for 1,500 rows; it excludes the save/list/receipt work below.

## Actual import coordinator and durable scheduling

The coordinator benchmark exercises duplicate detection, real local saves,
optional list memberships, receipts, notification policy, and immutable store
snapshots. It starts with 100 existing saves and 20 overlaps, and checks final
counts, order, memberships, silent policies, and one coalesced save per store.
Fixture creation, network resolution, JSON encoding, and disk I/O are excluded
from this coordinator benchmark; file-backed scheduling is measured separately.

| Workload | Baseline | v4 | Status |
| --- | ---: | ---: | --- |
| Actual autosave coordinator, 500 resolved Wanna rows with list | 49.07 s | 5.54 s | 88.7% faster; still a visible synchronous pause |
| Actual autosave coordinator, 1,500 rows with list | No completed matching-main baseline | 39.64 s | Historical v4 diagnostic; final Debug result below |
| Actual autosave coordinator, 1,500 rows without list | Diagnostic | 27.26 s | Historical v4 diagnostic; final Debug result below |
| 18 uneven Google lookups, completion | 573.67 ms | 224.66 ms | 60.8% faster |
| Same lookup workload, first ready result | 192.68 ms | 15.30 ms | 92.1% faster |
| File-backed 1,500-row snapshot, 18 uneven lookups | 831.31 ms | 601.32 ms | 27.7%; superseded by focused v5 below |

The final candidate Debug coordinator measured **31.970 seconds for 1,500 rows
with a destination list** and **19.599 seconds without a list**. There is no
completed matching-main baseline for these final large-import workloads, so no
paired improvement percentage is claimed. These remain substantial synchronous
main-actor pauses and are not comparable to the 500-row optimized Release result.

The scheduler uses deterministic 10/180 ms resolver latency. The file-backed
test includes production JSON encoding and atomic checkpoints, records write
count and main-actor heartbeat gaps, and reloads the resulting file. Its result
cannot be inferred from the faster in-memory scheduler. Oversized fallback
tests verify persisted wave state, source naming/order, pause/delete/retry
fencing, threshold transitions, and recovery to rolling scheduling.

## Focused v5 Debug results

These measurements include the v5 production changes and PostHog 3.68.3, before
the subsequent rendering work.
The focused gate passed 86 tests with no failures or skips, before the subsequent
fixture-only auth alignment. This does not replace the final unit and UI gates.

| Workload | Debug baseline | Focused v5 | Reduction |
| --- | ---: | ---: | ---: |
| Actual autosave coordinator: 500 resolved Wanna rows with list | 49.07 s | 4.704 s | 90.4% |
| File-backed 1,500-row snapshot, 18 uneven lookups: completion | 831.31 ms | 363.13 ms | 56.3% |
| Actual SDK: 20,000 layout callbacks, enqueue CPU only | 38.155 ms | 6.411 ms | 83.2% |

The file-backed shortfall observed in v4 is resolved for this workload. First
ready was 48.05 ms; the complete 1,217,042-byte snapshot was preserved across
20 writes. Persistence time was 221.44 ms; maximum main-actor heartbeat gaps
were 65.47 / 32.45 / 33.02 ms across the three samples. These still measure real
atomic file writes, not an ephemeral persistence substitute.

The same-process exact-text check measured 65.703 ms for the reference byte
comparison versus 1.963 ms for the optimized comparison over 15,000 calls
(97.0%). Row encoding for 1,500 items measured 28.866 ms cold and 8.519 ms warm.
Those component timings do not replace the complete file-scheduler result.
The 500-row coordinator still blocks for seconds, and the 1,500-row coordinator
and no-list diagnostic have not yet been remeasured after the streak change.

## Actual UI and SDK replay evidence

Matched Live UI v4 passed all six tests per build: three fixture unit tests and
three actual Live UI tests, using 300 map places and 600 feed events. These
values supersede the earlier provisional UI measurements:

| Actual Live UI workload | Baseline | Candidate v4 | Result |
| --- | ---: | ---: | --- |
| Launch to Live ready | 16,802.68 ms | 11,980.25 ms | 28.7% faster; below target |
| XCTest native application launch | 6.183 s | 4.136 s | 33.1% faster; below target |
| Drawer expansion | 4589.11 ms | 4472.47 ms | 2.5% faster; below target |
| Feed swipes: CPU / wall time | 3.251 s / 12.690 s | 3.258 s / 12.702 s | No material improvement |
| Native pan and zoom: CPU / wall time | 9.148 s / 13.648 s | 9.133 s / 13.316 s | CPU unchanged; wall 2.4% faster |

In the baseline, pan moved the measured anchors 30 points; zoom reduced actual camera distance
from 33,683.956 m to 21,454.972 m. The drawer remained collapsed, and exact
preview activity plus profile/back assertions passed. The paired harness aligns
fixture/auth identities and reads live camera metadata from native pin nodes.
Both builds retained the functional journey. **The 50% actual Live latency
target has not been reached.** Simulator hitch metrics were unavailable; no FPS
or hitch-rate improvement is claimed. UI wall time includes event injection,
idle waits and accessibility queries; the application CPU figures also showed
no material gesture improvement. Earlier incomplete map runs remain excluded.

To separate rendering work from those harness costs, a portable benchmark
mounts the real embedded FeedScreen in a 393×852 host with all 600 events and
ordinary cards/photos. Each sample performs 180 native UIScrollView offset steps
on CADisplayLink frames, with no AX or store sampling inside the timed callback.
Both builds retain 179 moving frames, the −62 to 5,698-point range, and every
event/group identity in its original order.

The final matched class runs **no replay, then real replay** in the same order
on both builds, with three samples per workload. These medians supersede the
initial separate no-replay and replay-only measurements:

| Mounted real Feed workload | Baseline ms | Candidate v10 ms | Result |
| --- | ---: | ---: | --- |
| No replay: elapsed | 3019.665 | 3023.292 | No improvement |
| No replay: synchronous layout | 567.716 | 401.689 | 29.2% less work; below target |
| Actual replay: elapsed | 3061.437 | 3106.743 | No improvement |
| Actual replay: synchronous layout | 155.988 | 84.736 | 45.7% less work; below target |

At 60 Hz, 180 scheduled frames impose an approximately three-second elapsed
floor. Layout measures synchronous offset/layout work; elapsed and tick gaps
also include work between callbacks. Reaching that floor does not establish a
50% gesture improvement. The matched Feed measurements remain below target.

The v8 actual UI measurements also remain below target:

| Live UI workload | Candidate v8 | Interpretation versus matched baseline |
| --- | ---: | --- |
| Launch to Live ready | 11,819.75 ms | 29.7% faster |
| Native application launch | 4.099 s | 33.7% faster |
| Drawer expansion | 4534.90 ms | 1.2% faster |
| Feed swipes: CPU / wall | 3.079 s / 12.960 s | No 50% improvement |
| Native pan/zoom: CPU / wall | 9.873 s / 13.874 s | No improvement |

The 1,200-call older activity timestamp component measured 1.709 ms versus
82.851 ms (97.9% less work), without establishing the required Live improvement.
After the pixel/transition fixes, the v10 mounted-pin benchmark is accepted:

| Mounted 300-pin workload | Baseline ms | Candidate v10 ms | Reduction |
| --- | ---: | ---: | ---: |
| Initial mount | 311.195 | 108.049 | 65.3% |
| Six density redraws | 969.305 | 441.906 | 54.4% |
| Process CPU | 369.704 | 312.092 | 15.6% |

These measure mounted component work, not an equivalent reduction in complete
map-gesture CPU or physical-device frame rate. Failed intermediate compact-pin
results are superseded by the passing v10 gate and are not acceptance evidence.

The paired Feed replay variant uses the actual SDK (baseline 3.61.0, candidate
3.68.3), production one-second capture cadence, and an entirely offline collector.
Successful native draws and decoded fixture-window images are required in every
sample; raw events/frames are never retained or transmitted. Baseline samples
recorded 3 / 3 / 4 native draws and candidate samples 3 / 3 / 3, with one decoded
image delivered per sample on each build. Candidate sample 1 needed **4.864 s
of encoder drain after the timed scroll**; this is an explicit additional wait,
not included in the elapsed/layout medians or hidden as a performance win.

**The real 600-event Feed did not reproduce the pathological growth of the
synthetic 200 masked-row SDK fixture below.** That fixture proves the SDK defect
and its improvement under those inputs; it does not establish that replay caused
the reported Live lag or that the SDK update yields the same Live speedup.
Cross-workload layout differences do not establish that enabling replay makes
Feed faster. The original overall 50% Live acceptance remains unmet.

The actual PostHog 3.61.0 throttle benchmark measured 38.155 ms median for 20,000
layout callbacks (five samples). This is callback enqueue CPU only, not replay
capture or encoding. The separate valid masked-scroll baseline mounts 200
SwiftUI rows and drives 180 native scroll steps per sample at the production
one-second capture cadence:

| Baseline replay sample | Elapsed s | Layout s | Maximum tick gap ms | Encoded native frames |
| --- | ---: | ---: | ---: | ---: |
| 1 | 21.765 | 7.552 | 296 | 20 |
| 2 | 34.280 | 18.773 | 403 | 32 |
| 3 | 57.998 | 36.549 | 1332 | 50 |

These sequential samples expose growing work; reporting only a favorable
callback microbenchmark would miss it. Real successful native draws and decoded
SDK images are required for every sample. Image-encoding drain is checked after
freezing scroll timings. The focused v5 SDK 3.68.3 results are:

| Focused v5 replay sample | Elapsed ms | Layout ms | Maximum tick gap ms | Native / encoded frames |
| --- | ---: | ---: | ---: | ---: |
| 1 | 3707.90 | 379.72 | 55.485 | 4 / 3 |
| 2 | 3618.08 | 324.28 | 53.735 | 3 / 4 |
| 3 | 3644.47 | 338.49 | 54.662 | 4 / 3 |

Median elapsed time fell from 34.280 s to 3.644 s (89.4%); median layout time
fell from 18.773 s to 0.338 s (98.2%). The included privacy/OCR screenshot gate
passed. Capture cadence and resolution remain unchanged. Individual native
draws were approximately 27–49 ms versus 23–28 ms before, so this is a reduction
in repeated aggregate work and long gaps, not a claim that every draw is faster.
Encoding is asynchronous, so a frame may arrive in the following sample; each
sample still requires native draws and encoded-image delivery. Frame counts
are not rendering FPS. The full native gate and focused corrections are reported
above; remaining validation is incomplete. The earlier matched optimized Release
results follow.

## Matched optimized Release results

All six selected benchmarks passed on both builds using standard **Release**
with `ENABLE_TESTABILITY=YES`, with zero failures or skips. These optimized,
matched results remain valid for the pre-rendering-change candidate and supplement
the Debug evidence. Times are median milliseconds.

| Release workload | Baseline ms | Candidate ms | Reduction |
| --- | ---: | ---: | ---: |
| Actual autosave coordinator: 500 resolved Wanna rows with list | 44013.18 | 3928.22 | 91.1% |
| File-backed 1,500-row snapshot, 18 uneven lookups: completion | 802.87 | 261.25 | 67.5% |
| Same file-backed workload: first ready result | 217.00 | 39.68 | 81.7% |
| Mounted place-profile host: 1,500 saves | 3604.69 | 538.70 | 85.1% |
| Widget publisher: first publication, 1,500 visits | 145.16 | 42.36 | 70.8% |
| Widget publisher: unchanged repeated publication | 115.25 | 14.39 | 87.5% |
| Actual SDK: 20,000 layout callbacks, enqueue CPU only | 37.905 | 1.611 | 95.7% |

The candidate file-backed workload preserved the full 1,217,042-byte snapshot
across 20 rolling checkpoints, compared with seven baseline wave checkpoints.
Persistence time was 62.95 / 55.94 / 51.98 ms; maximum main-actor heartbeat gaps
were 77.60 / 26.15 / 24.83 ms. The 500-row coordinator still takes 3.93 seconds
of synchronous work. The final 1,500-row Debug coordinator measured 31.970 s
with a list / 19.599 s without a list, without a completed matching-main baseline;
those different configuration/workload results are not a Release speedup claim.

The actual SDK masked-scroll benchmark passed with successful native captures
and encoded images in every sample, retaining the production one-second cadence:

| Release replay build / sample | Elapsed ms | Layout ms | Maximum tick gap ms | Native / encoded frames |
| --- | ---: | ---: | ---: | ---: |
| SDK 3.61.0 / 1 | 13733.22 | 7448.00 | 196.438 | 13 / 13 |
| SDK 3.61.0 / 2 | 25388.56 | 18488.47 | 318.746 | 24 / 24 |
| SDK 3.61.0 / 3 | 45702.88 | 36127.10 | 983.386 | 42 / 41 |
| SDK 3.68.3 / 1 | 3789.54 | 497.15 | 56.692 | 3 / 3 |
| SDK 3.68.3 / 2 | 3833.20 | 506.44 | 53.809 | 4 / 4 |
| SDK 3.68.3 / 3 | 3890.05 | 564.76 | 61.565 | 4 / 4 |

Median elapsed time fell 84.9%, from 25.389 s to 3.833 s; median layout time
fell 97.3%, from 18.488 s to 0.506 s. Faster completion produces fewer captures
at the unchanged cadence. Frame counts are not rendering FPS, and neither this
fixture nor callback timing measures physical-device interaction latency.

This was a temporary unit-only scheme compiling the self-contained benchmark
test sources. Unselected unit-test sources were excluded because some existing
tests require Debug-only helpers; production app sources retained the standard
Release configuration. This is a six-benchmark gate, not a full Release unit
suite. The full Debug unit target remains a separate gate alongside the
enumerated relevant UI checks.
The baseline built universal simulator architectures; the paired candidate
adds `ONLY_ACTIVE_ARCH=YES`. Both run the arm64 simulator binary on the same
destination, with identical selected benchmark sources.

Earlier setup failures are excluded: globally forcing `SWIFT_OPTIMIZATION_LEVEL=-O`
into Debug hit a Swift 6.3.3 IRGen compiler crash in existing IssueReporting
`_recordIssue`; the first ordinary Release attempt failed UI-test concurrency
compilation, and an all-unit Release attempt encountered Debug-only helpers.
None reached the selected benchmarks, and none is recorded as an app test
failure or a successful performance run.

## Validation, exclusions, and remaining gate

- Full native gate: 3,438 tests (3,413 unit + 25 UI), 3,433 passes and five
  failures. Two unit failures were stale source contracts; three were UI cases.
  The source contracts were corrected and passed in the handoff focused gate.
- Handoff focused gate: 165 passes and two pagination UI timeouts. All manual
  fixture regressions and the corrected drawer-stress test passed. All three
  original UI failures reproduced on unchanged baseline. Identical corrected
  pagination fixtures are now being compared on baseline; both pagination UI
  cases remain unresolved. No complete passing final gate is claimed.
- Earlier native checkpoints: v4 passed all 3,370 unit tests; focused v5 passed
  86 tests, zero failures/skips, including actual SDK capture and privacy/OCR.
  These checkpoints do not substitute for the remaining gates.
- Optimized Release gate: six selected benchmarks passed on both baseline and
  candidate, with zero failures or skips and the source-isolation scope above.
- Matched Live UI v4: all six tests passed on both builds, comprising three
  fixture unit tests and three Live UI tests. Pan, zoom, drawer, preview and
  profile behavior passed, but the measured improvements remain below target.
- Render-v10: all 29 tests passed, zero failures/skips, including corrected
  native pixel/transition tests and mounted component benchmarks. Earlier failed
  intermediate rendering measurements are superseded by that passing gate.
  Latest Release, AstirClip, and compact-pin validation remain pending.
- Final paired mounted Feed class: both builds ran no replay then replay with
  identical sources/order, all 600 events, movement checks, and native/decoded
  frame gates retained. Neither workload reached the 50% target; the real Feed
  did not reproduce the separate synthetic masked-row slowdown.
- Analytics checks passed using the bundled Node runtime: dashboard `--check`
  plus 12 tests. `npm` was unavailable; an `npm` invocation is not reported as a
  pass. There are no new product event names or properties in this change.
- Regression coverage includes alias collisions, first/last winner ordering,
  direct mutable-model changes, account/block boundaries, exact lease expiry,
  future event/timezone/month edges, tombstones, list alias bridges, recovery
  ledgers/events, full persistence schema, Unicode/signed-zero fidelity, atomic
  write failure and retry, and cancellation/replacement-run ownership.
- Excluded attempts: an unmounted profile harness; a later profile host missing
  an environment object; the widget fixture that produced only 250 visits per
  month despite intending 500; unsettled map gesture/selection runs; the map v11
  preview failure from mismatched fixture/auth identities; and the later
  five-pass/one-fail baseline UI run where the map container did not export its
  camera accessibility value. The passing paired harness now reads camera
  metadata from native pin nodes. These prior attempts
  are invalid measurements or harness failures, not passing performance results.
  The corrected widget baseline is the canonical 1,500-visit workload above.
- Remaining gate requires closing the two pagination UI timeouts with identical
  baseline/candidate fixtures, latest Release/AstirClip/compact validation, and
  complete native validation after any further changes, followed by a physical
  device run on the reported iPhone/iOS combination or a documented comparable
  device. Include cold launch/auth/bootstrap, large map/feed gestures, profile
  entry, and large import completion under real disk/network conditions before
  claiming the reported experience is fixed everywhere. The next acceptance
  step is profiling the matching physical device and representative user data
  to identify the remaining launch/feed/map critical path. Further isolated
  micro-optimizations without that attribution cannot establish the missing
  50% Live improvement.

## Reproduction and evidence storage

Checked-in tests create fictional data and assert identities, ordering, counts,
and durability alongside timing. Run identical baseline-compatible performance
sources on `2bb08f8e47`; keep candidate-only API tests separate. The Live fixture
helper/UI tests and offline SDK fixtures must be identical in paired builds.
SDK comparisons must verify the linked version and preserve capture cadence,
resolution, masking, and sampling.

Regenerate with XcodeGen, then run native builds/tests serially on the same
simulator destination with `-parallel-testing-enabled NO`, separate derived data
per revision, and no competing builds. Preserve the warm-up/sample rules in each
test. Result bundles, screenshots, and replay captures remain outside Git;
this report retains aggregate measurements and explicit exclusions only.
