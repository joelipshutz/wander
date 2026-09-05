# REC-441: Login, Feed, and Map performance

Base: `c520292` (main). Branch: `codex/rec-441-app-performance`.

## Changes

- Feed publishes server-authorized cards after `followed_feed`, before `activity_media` and private photo URL signing complete. Photos and engagement still hydrate through the existing repositories. Existing warm content remains on screen during refresh.
- Concurrent refreshes for the same account and pinned activity share one task. Automatic Feed remounts reuse a successful in-memory result for 60 seconds. Pull-to-refresh and mutation refreshes still force a request. Failure retains content and allows immediate retry. Local presentation revisions invalidate freshness; refreshes after follow/data changes cannot reuse an earlier in-flight result. Different pinned comment routes serialize their preservation passes. Sign-out and account changes retire requests and clear the freshness state. No private Feed content is persisted to disk.
- Signed-in maintenance hydrates the profile before notification preferences, push registration, calendar maintenance, pending saves, photo uploads, and shared-visit retries. The remaining dependency order is preserved, including continuing those maintenance jobs after profile failure. This changes scheduling; no end-to-end login time claim is made.
- Stable Map projection cache hits no longer copy/mutate the LRU array and dictionary. Pin rendering resolves its shared catalog once per pass. Native annotation updates compare the ordered descriptors directly instead of rebuilding a dictionary on every update.

## Results

| Controlled measurement | Before | After | Change |
| --- | ---: | ---: | ---: |
| Feed first content (100 ms Feed RPC + 400 ms media RPC) | 504.65 ms | 100.59 ms | 80.07% sooner |
| Five concurrent same-context Feed refreshes | 5 Feed requests by the previous per-call path | 1 measured request | 80% fewer |
| Successful warm automatic Feed read, within 60 seconds | 1 request by the previous unconditional path | 0 requests; 0.011 ms return | No network wait |
| Stable 1,500-pin comparison, mean of 100 passes on Simulator | 1.257 ms | 0.764 ms | 39.23% less time |
| Optimized host cache, median per 1M stable reads (5 samples) | 138.248 ms | 9.015 ms | 93.48% less time |
| Background stages scheduled before profile hydration | 6 stages | 0 stages | Scheduling change, not a timed login benchmark |

Simulator numbers above come from the combined REC-397 + REC-441 snapshot on iPhone 17 / iOS 26.3.1. XCTest attachments retain each measurement. The request-count baselines are determined by the previous unconditional/per-call request paths; the after counts are exercised through the actual store with a fake repository.

## Measurement method

The network benchmark uses the real Supabase Feed repository with a synthetic RPC: 100 ms for `followed_feed`, 400 ms for `activity_media`, and a fake private-storage signer. The old visibility point is completion of media hydration; the new visibility point is the early content callback. This measures a controlled request waterfall, not a real cellular connection or download throughput.

`python3 scripts/benchmark-map-projection-cache.py --baseline c520292` extracts the actual old/current cache implementations, compiles both with Swift `-O`, and measures five samples of 1,000,000 stable reads each on this Mac. Median: 138.248 ms before, 9.015 ms after (93.48% less time). This does not measure MapKit rendering, FPS, thermal behavior, or physical-device interaction latency.

The simulator benchmarks also exercise 1,500 native annotation descriptors and compare the previous dictionary reconstruction with direct array comparison. Concurrent Feed refresh and warm re-entry tests count requests, alongside account-switch and stale-content regressions.

## Redesign compatibility

All 11 changed Swift source/test files merged cleanly with the active REC-397 working tree (commit `d30f298`, with its in-progress merge of `c520292`). An isolated combined snapshot is at `wander-rec-441-redesign-check`; the original redesign checkout was not changed. The combined app build passed for the iOS Simulator.

## Validation limitations

The repository-prescribed iPhone 16 Plus / iOS 18.6 simulator is unavailable. Validation uses the installed iPhone 17 Pro / iOS 26.3.1. Real-device frame pacing and live low-bandwidth login measurements remain outside these controlled results.

## Completed checks

- Combined redesign + performance app build: passed, iOS Simulator.
- Final focused combined-version run: 22 tests passed, zero failures. Covers progressive content and signed media, transient auth retry, stale/offline retry, freshness expiry and clock rollback, account switch and sign-out/return, concurrent request sharing, follow-change invalidation, comment-route serialization, and Map cache partition/rebuild behavior.
- Final targeted Map UI run on the combined redesign: three tests passed, zero failures. Covers warm source switching, usable Map during a stalled initial refresh, and selected-pin panning/annotation work. Result: `wander-rec-441-redesign-check/DerivedData/Logs/Test/Test-Wander-2026.09.04_18-22-46--0700.xcresult`.
- Final focused result: `wander-rec-441-redesign-check/DerivedData/Logs/Test/Test-Wander-2026.09.04_17-58-39--0700.xcresult`.
- Broad combined unit suite: 1,843 passed, nine failed. One failure was a source-contract assertion that still expected the removed annotation dictionary; it has been updated to require direct descriptor comparison. The other eight failures were reproduced after reversing all REC-441 Swift changes in the isolated combined snapshot. They predate this pass: two import terminal/OCR cases, two social-candidate locality cases, two import request-timeout expectations (125 seconds vs the existing 145-second implementation), one list-ordering check, and one calendar NOW-badge layout check.
- Baseline reproduction: eight selected tests, eight failures, with all REC-441 changes removed. Result: `wander-rec-441-redesign-check/DerivedData/Logs/Test/Test-Wander-2026.09.04_18-13-09--0700.xcresult`. Performance source was restored immediately afterward.
- Final complete combined unit suite after correcting that assertion: 1,844 passed and the same eight baseline failures, with no additional failures. Result: `wander-rec-441-redesign-check/DerivedData/Logs/Test/Test-Wander-2026.09.04_18-17-07--0700.xcresult`.
- The earlier full main-based run completed before the attempted stop: 1,914 passed, 39 failed, one skipped. It included stale source-contract expectations, UI assertion/time-out failures, and several test-process SIGKILLs. This is not a clean UI certification; only the eight failures reproduced in the stripped combined baseline are classified as confirmed pre-existing here. Result: `wander-rec-441/DerivedData/Logs/Test/Test-Wander-2026.09.04_17-39-31--0700.xcresult`.
- Swift parsing and `git diff --check`: passed. XcodeGen 2.46.0 regeneration produced only target-order churn, excluded from the change.

To repeat focused checks, run the `WanderTests/FeedModelsTests` suite plus the new `testPerformance*`, `testConcurrentFeedRefreshesForDifferentCommentRoutesStaySerialized`, `testFollowChangeInvalidatesWarmFeedAndDoesNotJoinAnOlderRefresh`, `testFailedWarmFeedRefreshRetainsContentAndCanRetryImmediately`, and `testRetiredFeedRequestCannotRestoreContentAfterReturningToSameAccount` tests on the installed iOS 26.3.1 Simulator. Existing Feed repository/auth/account-switch and Map projection-cache tests were also included. Export XCTest attachments to inspect the measurements.


## Additional Map pass — September 5

This follow-up builds on `b441550`, the first measured pass. The isolated redesign verification checkout combines these changes with REC-397 at `ed5b5d6`; both changed Swift files merge cleanly. The original redesign checkout remains untouched.

- Featured results publish as soon as the Featured request succeeds, independently of social hydration. Social refresh still completes as structured child work. Failed Featured loads retain the local/social fallback and do not incorrectly mark the failed area as loaded.
- Nearby pans reuse a pending Featured request if its prefetched viewport covers the new visible region. Pans outside that area replace it. Request identity and account checks prevent cancelled/replaced responses from publishing or clearing newer work.
- Native annotation viewport selection uses a coordinate index. It preserves original ordering, keeps the selected pin even outside the viewport, updates after coordinate/selection/removal changes, and uses a linear fallback for broad views. All individual pins remain available. No persistent location or account data cache was added.

| Controlled measurement | Before follow-up | After follow-up | Change |
| --- | ---: | ---: | ---: |
| Featured first-content visibility, 100 ms Featured / 500 ms social delay | 505.387 ms | 100.072 ms | 80.20% sooner |
| Five nearby pan completions during one pending request | Previous path cancels/restarts work at every completion | One request, one delivery observed | Useful pending work is retained |
| 1,500-pin viewport selection, total over 200 queries | 27.489 ms | 9.921 ms | 63.91% less lookup time |
| Same viewport selection, mean per query | 0.137 ms | 0.050 ms | About 0.088 ms saved per query |

The pan test counts the new loader’s requests while one response is held pending. It does not claim an 80% reduction in network traffic: the old debounce timing and network cancellation determine how many abandoned attempts actually reach the server.

The coordinate index took 0.640 ms to build for this fixture. That setup cost is recovered after roughly eight such viewport queries with unchanged coordinates. Results depend on pin distribution and viewport size; broad views use a scan instead. These are Simulator Debug measurements of the production loading coordinator/index with synthetic content and delays, not a real-device FPS, MapKit tile-download, or production latency claim. The existing 350 ms reveal and 250 ms post-reveal staging are unchanged and are outside the Featured request timing above.

Focused validation: 57 map tests passed, zero failures on iPhone 17 / iOS 26.3.1. Includes 12 new loading/index/measurement tests and comparison with the previous scan across 100 viewports, coordinate boundaries, selection changes, invalid locations, removal and an empty catalog. Result: `wander-rec-441/DerivedData/Logs/Test/Test-Wander-2026.09.05_10-33-41--0700.xcresult`. Measurement attachments were exported to `/private/tmp/rec441-map-followup-attachments`.

Combined validation and failure triage:

- The complete combined unit portion finished with **1,856 passes and the same eight baseline failures** documented above. The full UI run was stopped at map failures for targeted comparison; its partial bundle reported 1,901 passes / 17 failures, including one cancelled test. This is not a completed or clean full-suite result. Summary, test tree, and metrics were saved under `/private/tmp/rec441-map-followup-full-*.json` before Xcode pruned older bundles.
- A first full attempt was interrupted because another task was using the same iPhone 17 Simulator. Subsequent validation used a dedicated iPhone 17 / iOS 26.3.1 Simulator named **REC-441 Map Validation**, ID `DFDB998F-AD5A-49AD-AD29-EFB2A3091606`.
- The comparison build exposed an existing Swift 6 error: shared-visit inbox tasks return value types without declared `Sendable` conformance. Added compiler-checked conformances to `SharedVisitInvitation`, its nested status/photo/answer values, and `JSONValue`, identically in both compared versions. No unchecked conformance or wire-format/runtime behavior change was introduced.
- With the map follow-up removed, the same two search UI failures reproduced: `testSearchNearbyAndBottomNavigationDismissWithoutResettingMoreFilters` and `testSelectedTicketClearsSearchDockWithoutRedundantResultMessage`. The dense-zoom check passed on this baseline run. Result: `Test-Wander-2026.09.05_11-02-53--0700.xcresult`; summary `/private/tmp/rec441-map-followup-baseline-ui-summary.json`.
- Restored final source then passed **102 map unit/selection tests** and the three UI checks for warm source switching, selected-pin panning, and usable Map during stalled refresh. The two baseline search failures remained. Dense zoom timed out because two completed gestures produced identical rounded counter readouts (`camera=61`, `frames=59`, `maxFrameGapMs=17`), so the UI test could not detect the second completion. Added a monotonically increasing completion field to the Debug-only probe; the frame-gap threshold and rendering behavior are unchanged. Result before this instrumentation correction: `Test-Wander-2026.09.05_11-05-34--0700.xcresult` (105 passes, three failures).
- The earlier broad run also recorded one 549 ms first-zoom frame gap. This pass does not claim to eliminate all MapKit/frame-pacing stalls, and a single subsequent successful run would not establish a real-device FPS improvement.
- Final probe-correction verification: **103 passed, zero failures** (102 map unit/selection tests plus the dense-zoom UI check), with its unchanged 100 ms frame-gap limit. Result: `Test-Wander-2026.09.05_11-11-59--0700.xcresult`; summary `/private/tmp/rec441-map-followup-final-zoom-summary.json`. Together with the immediately preceding run, all four targeted loading/panning/zoom UI checks passed. The combined checkout has the final performance implementation restored. Swift parsing, project regeneration, and `git diff --check` passed; generated target-order-only churn is excluded.

Publication: GitHub write access remains the blocker from the first pass. Automatic approval review also rejected the external Linear checkpoint update because of internal project details. A short, explicit summary was prepared and user approval requested; no further Linear write will occur without that approval. The updated code, measurements, and patch remain local.
