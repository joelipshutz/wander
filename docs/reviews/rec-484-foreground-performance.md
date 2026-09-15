# REC-484: Foreground and cold-start responsiveness

Issue: [REC-484](https://linear.app/recme/issue/REC-484/eliminate-prolonged-foreground-and-cold-start-stalls).
Profiled baseline: `1666093fb`. Integrated base: `042f804d6`.
Branch: `codex/rec-484-foreground-performance`.

## Device evidence

Two Time Profiler recordings captured repeated stalls on an iPhone 15 Pro,
iOS 26.5, app version 1.0/build 171. The attached process used
`Wander.debug.dylib`: these are Debug development-build measurements, not
optimized TestFlight measurements. Raw traces remain local.

| Measurement | First capture | Follow-up capture |
| --- | ---: | ---: |
| Recording duration | 181.75 s | 103.23 s |
| Instruments hang intervals | 56 | 29 |
| Total time in hang intervals | 45.91 s | 28.48 s |
| Longest hang interval | 1.73 s | 2.13 s |
| Sampled main-thread CPU | 54.92 s | 31.95 s |
| Inclusive root initialization CPU | 15.58 s | 11.10 s |

The first capture also attributed about 15.26 seconds of inclusive main-thread
CPU to `MapScreen.visiblePlaceGroups`. Category normalization appears inside
store restoration and other callers. These inclusive measurements overlap and
must not be added together.

The captured background intervals were approximately 1.7 seconds and 1.0
seconds. This establishes a short-return reproduction; it does not establish
the originally proposed long-background or cold-launch baseline. The first
recording started at nominal thermal state, with hangs preceding the change
to fair. The follow-up remained at fair.

Persistence signposts reached about 73 ms and list application about 0.91 s.
Signed-in maintenance lasted 16.7–25.6 seconds including suspension and network
waits. That elapsed duration is not evidence that it blocked the main thread
for the whole interval.

## Changes and invariants

- `WanderRootView` passes construction expressions directly to `StateObject`.
  Previously, eager locals restored both the app store and import history on
  parent updates even when SwiftUI retained their existing instances. The
  account identity boundary remains in `AppEntryView`. The Add sheet derives
  its initial height from the mounted import store rather than forcing a load
  during view initialization.
- Map retained-selection authorization and merging share a bounded projection
  cache. Its key includes the existing map inputs, account, presentation
  revision, routed save, and retained/submitted group membership. A missing
  routed group uses the store's authorized grouping cache. Empty submitted
  groups skip dictionary construction. Revoked or deleted members continue to
  be removed using current authorized rows.
- Immutable taxonomy indexes replace repeated normalization of constant IDs,
  group names, aliases, and subcategories. First-match ordering and all
  classification/source semantics are retained. No user-content cache or
  persistence-format change is introduced.
- Instruments intervals identify root/import store construction and retained
  map projection rebuilds. They carry no account or place content.

## Controlled comparison

Run `python3 scripts/benchmark-category-resolution.py --baseline 1666093fb`.
The harness compiles the actual before/after classifier code with Swift `-O`
on macOS. Unrelated UI/model convenience methods are excluded. It compares
31,864 classification results across taxonomy values, case/whitespace variants,
provider types, Unicode inputs, and eight category sources. All results match.

For five samples of 1,500 category assignments, the median fell from
1,428.7 ms to 272.9 ms, an 80.9% reduction. The first assignment in each fresh
process took 29.9 ms before and 34.8 ms after; the index has a one-time setup
cost. These figures do not measure iOS snapshot restore, cold launch, FPS,
MapKit rendering, or network performance.

## Validation status

The first focused simulator run passed all 299 `WanderStoreTests` and
`ForegroundPerformanceTests`, including the seven new store regressions and
eight initial root/map/category tests. It used a dedicated iPhone 17 simulator
running iOS 26.5.

Two new regressions were also executed against the previous store implementation
and failed for the expected repeated-work assertions:

| Work per refresh | Previous snapshot path | Previous fallback path | Patched paths |
| --- | ---: | ---: | ---: |
| Calendar fingerprints | 18 | 17 | 1 |
| Place-grouping indexes | 13 | 12 | 1 |

The snapshot fixture repeats one of its 12 list details. Both paths retain the
same collapsed membership and persisted counts. Nested batches built four
fingerprints before, versus one after. These counts establish the regression
mechanism; they do not measure device frame pacing.

The combined branch compiled the app and both test targets successfully. Its
unit suite completed with 1,964 passes and three timing failures. All nine
foreground tests and seven new store regressions passed. The ninth foreground
test covers REC-489 integration: Featured authorization changes invalidate
retained selection under an unchanged Friends/You filter, and the expanded
authorization corpus cannot use an incomplete social-only index.

The remaining unit failures need a controlled recheck with unchanged thresholds:

- Trusted search: p95 54.17 ms against a 50 ms budget.
- High-data fixture: warm visible-place reads 110.48 ms against 100 ms;
  grouping 204.70 ms against 150 ms.
- Feed photo fallback: the expected image load exceeded its 2-second wait.

Three initial UI checks passed. The place-detail UI test failed because its
snapshot query timed out; the next Add-sheet test was canceled when the full
run was interrupted. The final result bundle reports 1,967 passes and five
failed/canceled cases across both targets. The host was under heavy memory
pressure, which may explain the timing failures, but that remains an unverified
explanation. This is not a passing full-suite result.

- Passed: classification equivalence benchmark, Swift parsing, XcodeGen
  regeneration, and `git diff --check`. The Debug device build also succeeded
  in Xcode on September 11 at 1:54 PM, with warnings and no build errors.
  Xcode's Branch Chooser was verified on `codex/rec-484-foreground-performance`
  for that first device pass. That build predates the store batching follow-up;
  building alone does not verify frame pacing.
- Passed in the focused run: eight initial `ForegroundPerformanceTests`, covering
  unmounted factory deferral, actual SwiftUI mounting and parent redraws,
  account identity replacement, revision/account invalidation, retained group
  membership, lazy reuse of authorized grouping, revocation, taxonomy
  equivalence, and a 1,500-save retained-map measurement.
- Pending: a controlled recheck of the three unit timing failures, completion
  of the full UI suite, and device profiling in matching build configurations.

The repository-prescribed iOS 18.6 simulator is unavailable on this machine.
Use an installed runtime for execution and record that deviation with results.
Next device checks must include cold launch through the first 30 seconds of
interaction, short returns, returns after the 30-second session-refresh grace
period, repeated cycles, selected pins/search results, and ongoing sync.
Check an optimized build as well as the matching Debug comparison. No splash
extension or end-to-end performance improvement is claimed yet.

## Store batching follow-up

The deferred-persistence helper previously deferred only snapshot serialization.
Every nested persistence request still compared the complete current-user
calendar fingerprint and invalidated the grouping cache. Remote list detail
application then calculated each list's count using that invalidated index.

The store now marks calendar reconciliation as pending and performs it once at
the outermost synchronous batch boundary. A calendar-dependent read inside a
batch reconciles first, preserving current authority and local visit visibility.
Later mutations mark it pending again. Presentation caches are still invalidated
at each mutation so membership and authorization reads remain current.

Both remote list refresh paths apply all eligible details before calculating
counts with the existing batched membership projection. Pending owner changes
are excluded from count reconciliation. Duplicate memberships retain the
existing collapse and tombstone rules. The final persistence request includes
the reconciled counts in the saved snapshot.

Seven added regression tests cover the two refresh paths, repeated detail IDs,
duplicate memberships, persisted counts, protected owner edits, nested and
throwing batches, absent persistence, empty batches, and calendar reads before
and after further mutations. Existing calendar hydration, stale-response,
account-switch, list deletion, and authorization tests remain part of the
required validation. No schema, analytics event, or splash behavior changes.

Keep the implementation PR in draft while validation is incomplete. The focused
checks and failing previous-store comparison are complete. Resume with the three
failed unit tests against the already-built candidate on a quiet host, then
finish the UI suite. A matching device capture is still required to quantify
the remaining hangs and decide whether the next pass should address
presentation work or launch readiness.
