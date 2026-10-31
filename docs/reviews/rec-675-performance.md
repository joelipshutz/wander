# REC-675: Performance review

Issue: [REC-675](https://linear.app/recme/issue/REC-675/reduce-app-wide-interaction-latency-by-at-least-50percent-without).
Baseline: `2bb08f8e47`. Branch: `codex/rec-675-app-performance`.

## Acceptance and current validation

**Draft: the real Live ≥50% latency target remains unmet.** Component gains and
responsive import checkpoints do not establish a 50% improvement in complete
launch, Feed, or map gestures. The reported device is iPhone 15 Pro / iOS 26.5 /
TestFlight 185. Development-signed baseline and candidate Release apps have now
been installed sequentially on that phone with app data preserved. The completed
three-run physical journeys remain below target and predate the latest import
bridge. Uniform 50% improvement and smooth 60 FPS remain unestablished.

Validation at pushed implementation head `699f0fd14f`, with follow-up status below:

- Local native unit gate: **3,542/3,542 passed**, zero failures or skips. This
  includes all three 1,500-row stress cases, deferred-tab hosting, owner/manual
  recovery, both snapshot memo field matrices and the mounted scrolling/import
  workload. The four process-global SDK cases are required separate runs.
- Local optimized Release gate: **11/11 passed**, zero failures or skips.
- AstirClip retains its prior **33/33 passes**. All 16 Clip Swift sources,
  its two test targets, resources/configuration references, target settings and
  package pins are unchanged since `699f0fd14f`; follow-up app changes do not
  enter the Clip target. No additional Clip run is required for this delta.
- Focused route/tab/launch UI: six journeys passed. Compact unprimed manual-edit
  and filter-edge gate: **3/3 passed**. Earlier compact drawer/zoom checks passed
  **2/2**; those checks are distinct from the full unit run.
- Fresh-host replay validation at that source: **4/4 passed**, retaining exact
  host admission, compiler receipts, capture and privacy assertions.
- Follow-up pure-model host isolation: **4/4 lifecycle tests passed**, followed
  by both 500-row file/coordinator cases under the unchanged 120-second default /
  180-second maximum policy, zero failures or skips. The final full unit gate
  passed **3,566/3,566 exact methods**, zero failures or skips, including all three
  1,500-row cases and 24 additions to the prior 3,542-case inventory. Its source
  fingerprint was unchanged from launch through completion.
- Latest production bridge / eight-row, 40 ms policy: **75/75 focused tests
  passed**, zero failures or skips. The new Release build, original mounted
  Feed/import case and separately invoked actual masked-scroll SDK case passed.
  The current selected Release inventory passed **11/11**: ten ordinary cases
  plus one separately invoked actual SDK case, zero failures/skips/expected
  failures, on unchanged source and products. The initial mounted-only pass is a
  distinct extra run. Final Debug replay validation also passed **4/4**, each in
  its own exact one-case invocation, with native exit zero, host admission,
  configuration restoration, unchanged source/products and capture/privacy checks.
- CI routing/receipt tooling: **91/91 tests passed across seven modules** after
  the final two-path trigger addition.
  Required SDK isolation and separate long 1,500-row stress dispatches retain
  exact test/device/result checks.
  Stress dispatches use the existing 600-second default / 900-second maximum
  performance allowances; ordinary unit deadlines and assertions are unchanged.
- The matched original-build mounted Feed/import comparison completed: its one
  test failed six responsiveness assertions; content and durable-file parity
  checks passed. The candidate passed the same workload. Details below.
- Review-storage and diff whitespace checks pass. **CI at `699f0fd14f` is not
  green**; local passing gates do not supersede its failures.

The native gate is complete: **3,566 unit methods + 11 selected Release methods
+ four isolated Debug SDK cases**. The only subsequent CI change adds Feed
workflow trigger paths for the bookmark-observation helper and its regression
file. Removing exactly those two lines reconstructs the native gate's input
fingerprint; app/test source, project membership and compiler inputs are
unchanged. Native receipts are preserved, and final-head CI is still required.

At that CI head, Feed passed its ordinary unit/native Feed checks, all three
stress runs and all four Replay cases, then reached the 100-minute job limit
during compact scrolling. Privacy also passed all stress/Replay cases, but had a
separate Pro native failure and reached its job limit during compact UI. Contact
passed 3,551 checks before its 60-minute job limit interrupted the first stress
run. Prepared workflow changes give compact UI independent bounded jobs and keep
the existing `native` check as an aggregate that requires every selected worker
to succeed. Contact uses a 100-minute job budget. Explicit recovery modes retain
their original selections; no assertion or per-test time limit was relaxed.
Scheduling corrections do not resolve assertion failures. All 16 distinct UI
methods that failed at that CI head have now passed locally: seven earlier
corrected cases (Photos, two Favorites, two YourMap and two notification cases),
three unchanged cases (map zoom, native overview and sender), and six latest
cases (private reply, Map More, drawer, Dark/Light appearance and Person). The
three popup/edge cases passed separately and are not part of those 16. The latest
focused follow-up passed **6/6**, zero failures or skips, including the one-line production
fix preserving the Profile Messages route across foreground entry. This focused
closure does not replace final-head CI. The final unit rerun covers the latest
production fixes; the current selected Release inventory also passed 11/11. The two appearance tests passed in
about 231 seconds (Dark) and 218 seconds (Light), near their unchanged 240-second
allowance. The test-only AX-query consolidation rerun passed both cases, at
about 222 seconds (Dark) and 213 seconds (Light). This is a test-driver gain,
not app performance evidence; that CI head remains unverified by a new full run.

The Parent CI 1,500-row actual-file case exceeded its unchanged 900-second test
limit. The same case passed in Feed CI in 776.868 seconds, with three timed import
samples of 340.929, 200.247 and 233.237 seconds: 99.68% of the test duration was
inside measured import work. Import throughput remains a material concern;
other work within the passing test accounts for only a small share. These CI runs are
not matched performance comparisons with the local reference results below. The
Parent timeout's endpoint stack includes journal encoding on a utility thread
(317 samples; 9 ms CPU over 4.99 seconds); this endpoint does not explain the
whole 900-second failure.

Physical checks with Do Not Disturb enabled completed fresh baseline launch
measurements and three successful journeys each for Feed, map/place-profile,
and Profile. Seven cooled candidate journey runs then passed at Nominal thermal
state, completing three admissible runs per journey together with the earlier
Fair Feed/map runs. Native launch medians each contain three samples; journey
CPU medians compare three baseline and three candidate runs.

| Physical measurement | Baseline | Candidate | Interpretation |
| --- | ---: | ---: | --- |
| Native first frame | 0.217542 s | 0.216703 s | About 0.4% lower; below target |
| Native first responsive frame | 0.241956 s | 0.232577 s | About 3.9% lower; below target |
| Feed journey app CPU | 6.5153 s | 4.0265 s | 38.2% lower; below target |
| Map/place-profile journey app CPU | 23.4200 s | 16.5251 s | 29.4% lower; below target |
| Profile-tab journey app CPU | 12.0296 s | 8.5254 s | 29.1% lower; below target |

Baseline launch thermal state was Nominal; candidate launch state was Fair, so
these are not thermally matched acceptance results. Journey samples span Nominal
and Fair, except candidate Profile, which is entirely Nominal. Earlier elevated
baseline launches, two notification-interrupted map runs, the Serious candidate
journeys, and the map run interrupted for cooling remain excluded.

These are normal-account, cache-warm read-only journeys, not the 600-event
Simulator fixture or a controlled network/data snapshot. Feed used two gestures
with three known postcards and one initially visible card. Map used two pans and
a verified place-profile route; initial pin counts varied from 94–99 on baseline
and 79–94 on candidate. Automation-inclusive journey wall medians were
9.783→7.696 s (Feed), 30.336→25.502 s (map/profile), and 13.522→11.028 s (Profile),
or 21.3%, 15.9%, and 18.4% lower. These include AX/navigation overhead and are not
app CPU. Automation-inclusive launch clocks increased from 2.780→3.652 s and
3.295→4.112 s, despite the small native first-frame improvements. The baseline
will not be reinstalled over candidate data. The PR stays draft pending final CI
validation and the unmet whole-journey performance target; these phone results
also predate the latest Profile Messages correction.

The candidate-only quiet-stage profiling test compiled successfully, but its
device preflight stopped on disconnection before runner installation, app launch,
or trace recording. Reconnection is pending; no profiling result is claimed.
The separate fixed-workload checkpoint diagnostic passed three correctness tests
and all 12 trials: 24 complete atomic writes per trial, 2,011,778 bytes per
snapshot, with full content and graphics-control parity. Verified queue-priority
promotion provided no wall-time gain: static medians were 633.5 → 653.4 ms;
animated medians were 2,536.3 → 2,595.0 ms. In the animated control, waiting for
MainActor to resume after completed writes dominated elapsed time; queue delay
was only about 1–3 ms per trial. Production priority remains unchanged. This
local fixed-snapshot diagnostic does not establish the cause of the full CI
timeout. Test-only isolation of the unrelated host UI is now applied to the
three pure-model import benchmark classes. All four restoration/lifetime tests
and both strict 500-row cases passed on identical verified test products.
Workloads, three samples, file/receipt checks and deadlines are unchanged;
isolated results describe a controlled model boundary, not an app speedup over
the earlier animated-host measurements. The final broad gate passed all three
unchanged 1,500-row cases. Serialization reuse remains an external proposal.

The independent flush-ordering race is now reproduced and fixed. With the first
save paused just after its scheduling lock was released, a second save could
return before the drain was enqueued; a subsequent flush then returned before
the writer had received the second snapshot. The old-order experiment produced exactly the
intended nil-versus-second-snapshot assertion. Submitting the drain before
unlocking passed the same regression plus all 12 existing checkpoint contracts
(**13/13**, zero failures or skips). That narrow writer correction and regression
are applied; this correctness result makes no performance claim and does not
change queue priority or durable acknowledgment semantics.

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

A separate 25-second Release profile attributed 39.0% of main-thread stack observations
to snapshot capture, 18.1% to SwiftUI Observation dependency replacement, and 7.5%
to bookmarks. These are observation shares, not CPU or elapsed-time percentages. A
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

A later phase-contained diagnostic sampled that unchanged Release host during
the stronger mounted workload; the native fixture passed. The five-second stack
capture and its complete 10.944-second invocation, including symbolication, fit
inside the 27.764-second import interval with verified process/build identity.
Of **3,003 main-thread stack observations**, disjoint caller paths attributed
31.2% to SwiftUI Observation invalidation outside the display driver, 17.7% to
other SwiftUI graph/layout/body work, 16.3% to the import coordinator, 14.2% to
Root reconciliation, 7.0% to bookmarks, 6.5% to the display driver including its
forced layout, and 6.4% to Feed projection. Snapshot capture was only 55 nested
observations (1.8%); it must not be added again to the coordinator share.
The separate writer population contained 1,077 observations, chiefly Foundation
value traversal (730) and final JSON serialization (306), with 39 in atomic file
writing. These populations are **stack observations, not CPU time or latency**.
Generic SwiftUI frames do not identify the concrete view owning invalidation;
no onboarding-film frame appeared in this mounted slice. Sampling perturbs
execution and covers only part of the import, so this is attribution evidence,
not a comparative acceptance result or proof of the 1,500-row CI timeout cause.
Both earlier incomplete Instruments attempts remain unusable for attribution.

Three later matched diagnostics used that same unchanged Release app and the full
200-row / 600-event / 1,620-save workload. Each variant ran once in a fresh
process, passed its exact native test, and retained content, receipt, file,
scrolling and rendered-progress checks. These are separate ordered single pairs,
not repeated estimates or whole-app acceptance results.

| Test-only treatment | Import elapsed, control → treatment | Display p95 gap | Maximum display gap |
| --- | ---: | ---: | ---: |
| Bookmark index prewarm before the unchanged checkpoint | 24.447 → 19.876 s (18.7% lower) | 134.20 → 98.88 ms | 224.00 → 215.86 ms |
| Chunk time budget 10 → 40 ms, same eight-row ceiling, no prewarm | 24.525 → 8.240 s (66.4% lower) | 136.96 → 156.16 ms | 236.07 → 244.67 ms |
| Combined 40 ms budget and bookmark prewarm | 24.523 → 7.354 s (70.0% lower) | 142.45 → 131.52 ms | 224.43 → 226.49 ms |

Prewarming retained 201 index builds, 200 acknowledgments and 201/400 Root
revision/item callbacks. Its 200 prewarm reads took 1,517.96 ms in total;
heartbeat p95/max gaps changed from 105.93/225.43 to 66.61/211.45 ms. This moves
index construction outside the rendering read; it does not establish safe
production observation semantics. The test-only prewarm is not a production fix;
the subsequent production implementation is measured separately below.

The 40 ms budget reduced acknowledgments from 200 one-row chunks to 55 chunks
(two of two rows, 16 of three and 37 of four), still totaling all 200 rows.
Heartbeat p95/max gaps worsened from 107.46/225.55 to 122.93/246.93 ms, alongside
the worse display p95/max. That throughput gain therefore does not establish
better responsiveness and did not justify a policy change on its own.

The combined treatment retained all 200 rows in 52 acknowledged chunks
(histogram: one of one row, one of two, three of three and 47 of four). It made
53 index builds and 52 prewarm reads totaling 401.56 ms, with 53 revision / 104
item callbacks and 51 intermediate renders. Display p50 fell from 85.90 to
27.78 ms, but p95 improved only 7.7% and the maximum stayed about 226 ms.
Heartbeat p95/max changed from 111.00/208.80 to 100.91/189.17 ms. This compound
single-pair result supports further evaluation, not a 50% responsiveness claim
or production adoption. Its first treatment selection executed zero tests and
is excluded. Enumeration confirmed both compiled methods; one bounded retry
using the exact enumerated `()` suffix passed with the same source, app and unit
binary. That selection outcome does not establish a general importer defect.

The production run-scoped observation bridge and eight-row / 40 ms policy passed
**75/75 focused tests**, zero failures or skips, including 17 bookmark-observation
and two multirow recovery/account-boundary tests. The separate optimized Release
build then passed the unchanged original mounted test with no test-only prewarm
wrapper. Its one sample retained all 200 imports, 600 Feed events, 1,620 initial
saves, source order, notification policy and complete durable-file assertions.

| Actual production Release mounted import | Result |
| --- | ---: |
| Complete import elapsed | 6,972.695 ms |
| Display-link gap p50 / p95 / maximum | 99.427 / 129.819 / 230.529 ms |
| Main-actor heartbeat gap p50 / p95 / maximum | 2.050 / 99.495 / 229.023 ms |
| Forced native layout work | 255.377 ms |

It produced 52 acknowledged library checkpoints, 53 revision and 104 item
callbacks, 51 intermediate rendered save counts, 99 moving display ticks and
381 heartbeat ticks during import, with a 5,760-point scroll span. Gap statistics
include the post-completion delivery. This is one production observation, not a
repeated paired estimate; roughly 230 ms tails remain and do not demonstrate
smooth 60 FPS or uniform 50% responsiveness improvement.

A final fresh-process pair on that same immutable Release app compared the
production 40 ms budget with an explicit 20 ms budget, both retaining the
eight-row ceiling and real production bridge. Neither used a test-only prewarm.

| Budget diagnostic, one sample each | 40 ms control | 20 ms treatment |
| --- | ---: | ---: |
| Complete import elapsed | 7,290.452 ms | 12,128.949 ms |
| Display gap p50 / p95 / maximum | 96.158 / 131.348 / 242.136 ms | 32.353 / 112.213 / 269.588 ms |
| Heartbeat gap p50 / p95 / maximum | 2.052 / 100.370 / 243.432 ms | 2.054 / 80.877 / 273.301 ms |
| Acknowledged checkpoints | 54 | 101 |
| Revision / item callbacks | 55 / 108 | 102 / 202 |

The 40 ms histogram was one two-row, 14 three-row and 39 four-row chunks; the
20 ms histogram was two one-row and 99 two-row chunks. Both totaled 200 rows,
passed every original assertion and scrolled 5,760 points. The 20 ms trial
improved display p95 by 14.6% and heartbeat p95 by 19.4%, but took 66.4% longer
and worsened maximum gaps by 11–12%. It was rejected; 40 ms remains selected.
One ordered pair does not establish causality or a general optimum.

The actual masked-scroll SDK case also passed **1/1** in a separate Release
invocation on the same verified products, retaining real window isolation,
native-draw and decoded-frame checks. Release does not compile the Debug inert-host
admission policy; the four separate Debug SDK gates subsequently passed with
actual inert-host admission and exact configuration restoration.
The subsequent ordinary Release run passed 10/10 with zero failures, skips or
expected failures, completing the current 11-case inventory on identical source,
app and products. Its repeat mounted case is validation only; the timing above
remains the initial separate mounted observation.
The final unit gate passed **3,566/3,566 exact methods** (prior 3,542 plus four
host-lifecycle, one flush, 17 bookmark and two multirow methods), with zero failures
or skips, unchanged selectors/time limits and identical source fingerprints at
launch and completion. All three 1,500-row cases were included; the four global
SDK cases passed in their required separate Debug runs.

## Implementation and preserved contracts

- Lists and Profile defer first construction until selected, then retain their
  normal identity and navigation state. Selection constructs content in the same
  render. Existing pending notification/calendar consumers are unchanged; six
  actual route/tab/launch journeys and four hosting regressions passed.
- Bookmark state uses the existing authorized local/remote merge with only the
  required owner, identity, and status fields. Foreign content, attributes, visit
  enrichment, and unused filtered list indices are not prepared for this icon.
  Five cold-path oracle/Observation tests retain first-match, alias, Been/Wanna,
  tombstone, account, permission, and relevant-mutation behavior. During a demanded
  automatic-import run, stable model watches expose a lightweight revision to
  rendering; raw mutations, replacement, account changes and pending willSet
  handoffs retain fresh reads. The run ends and releases its registrations.
- Automatic saving now performs bounded synchronous chunks, then closes every
  persistence/projection scope before awaiting an ordered atomic library write.
  The default row-work budget is eight rows / 40 ms. Snapshot capture and import
  JSON publication remain synchronous and are outside that budget: **40 ms is
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
below predates the latest bookmark-observation bridge and 40 ms policy. It includes
durable import chunks and observed snapshot-record reuse against the original
portable baseline workloads. These are
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

| Pre-bridge Release workload | Baseline | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| 500-row autosave + list, excluding disk I/O | 44013.18 | 2783.46 | 93.7% |
| File-backed 1,500-row snapshot / 18 uneven resolver requests | 802.87 | 262.03 | 67.4% |
| Same resolver workload, first ready | 217.00 | 39.31 | 81.9% |
| Mounted profile, 1,500 saves | 3604.69 | 561.37 | 84.4% |
| Widget publication, 1,500 visits | 145.16 | 39.03 | 73.1% |
| Unchanged repeated widget publication | 115.25 | 15.41 | 86.6% |
| SDK callbacks, 20,000 enqueues only | 37.905 | 1.334 | 96.5% |

Release used standard optimization with `ENABLE_TESTABILITY=YES` and a unit-only
benchmark scheme: six selected cases on baseline and eleven on that candidate,
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

Before acceptance: verify corrected UI cases, independent CI workers and prior
timeout failures on the final pushed head. Local native validation is complete:
3,566 unit methods, the selected 11-case Release inventory and four separately
invoked Debug SDK cases. The unit gate includes the Profile Messages, flush-order
and observation-bridge changes plus all three unchanged 1,500-row cases under
600/900-second limits. The appearance
query-consolidation rerun is already complete. Further physical work must cover
the remaining auth/bootstrap and import scenarios with comparable thermal and
interruption conditions; completed phone journeys remain below the requested
whole-app target. Neither those observations nor the stack diagnostic establishes
≥50% complete Live improvement. Atomic-write tests do not simulate power loss
beyond the platform's atomic file-write contract.

Raw traces, result bundles, screenshots, and replay captures stay outside Git in
the issue evidence directory. This report keeps aggregate results and exclusions:
unmounted/misconfigured profile fixtures, incomplete widget counts, and unsettled
map/identity harness attempts are not accepted measurements. The worktree project
was opened in Xcode and its branch verified; this does not change draft status.
