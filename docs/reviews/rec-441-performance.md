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
- Final focused result: `wander-rec-441-redesign-check/DerivedData/Logs/Test/Test-Wander-2026.09.04_17-58-39--0700.xcresult`.
- Full suite started on iPhone 17 Pro / iOS 26.3.1 and remains in progress at this checkpoint; it is not counted as a pass.
- Swift parsing and `git diff --check`: passed. XcodeGen 2.46.0 regeneration produced only target-order churn, excluded from the change.

To repeat focused checks, run the `WanderTests/FeedModelsTests` suite plus the new `testPerformance*`, `testConcurrentFeedRefreshesForDifferentCommentRoutesStaySerialized`, `testFollowChangeInvalidatesWarmFeedAndDoesNotJoinAnOlderRefresh`, `testFailedWarmFeedRefreshRetainsContentAndCanRetryImmediately`, and `testRetiredFeedRequestCannotRestoreContentAfterReturningToSameAccount` tests on the installed iOS 26.3.1 Simulator. Existing Feed repository/auth/account-switch and Map projection-cache tests were also included. Export XCTest attachments to inspect the measurements.
