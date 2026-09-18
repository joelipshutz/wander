# REC-484: Foreground and cold-start responsiveness

Issue: [REC-484](https://linear.app/recme/issue/REC-484/eliminate-prolonged-foreground-and-cold-start-stalls).
Initial profiled baseline: `1666093fb`. Current integrated base: `5bf0870da`.
Branch: `codex/rec-484-foreground-performance`.

## Launch preparation and refresh follow-up

This pass integrates `origin/main` through `5bf0870da`, including REC-534's
Profile responsiveness work. Earlier sections below describe historical
captures and candidates, not validation of this implementation.

The launch artwork now stays visible for a minimum of two seconds. Local map
content remains mounted and source hydration starts underneath the cover,
instead of starting after reveal. Slow or offline network requests do not
extend the cover indefinitely. The tab bar and native map interaction and
accessibility are unavailable while covered, then restored on reveal. Completed
initial source preparation is reused for the same signed-in account; returning
to Map does not repeat the splash or initial hydration. Account changes and
incomplete preparation cannot reuse a completed-account marker.

Concurrent current-profile and list refresh callers now share both fetch and
application work. Account changes cancel these tasks and stale completions
cannot apply. Identical profile and shared-inbox responses skip publication and
persistence. A bounded, immutable list snapshot comparison skips identical
application only while account and presentation revision also match. Local
edits, changed remote content, and access revocation still invalidate it.

Shared reads are also canceled when their owning app root disappears, while
completed same-account caches survive ordinary disappearance. Identity changes
clear those caches explicitly. A mounted-root regression first failed because
the profile refresh completed successfully after removal of its owning root;
the root now invokes the store's shared-read cancellation during teardown.

List item replacement publishes one updated array. Successful place/check-in
acknowledgements persist their related identities together. Import duplicate
reconciliation builds one name/provider index per input, preserving input-order
precedence and coordinate semantics, then publishes changed rows once. Empty
or unchanged reconciliation does not invalidate the app's other surfaces.
The retained-map projection also shares main's selection authorization cache.
No backend schema or analytics event contract changes are introduced.

Four regressions failed against the previous implementation for repeated
refresh application and stale-account application, then passed with the fixes.
Focused validation passed 81 unit tests, including all 18 foreground tests.
Four launch UI checks passed on both iPhone 17 and smaller iPhone 17e simulators
running iOS 26.5: covered interaction, usable reveal, bounded reveal with stalled
refresh, and returning from another tab without another splash. Both cover
screenshots were visually reviewed. XcodeGen and whitespace checks passed.

The first integrated full run completed with 2,204 passes, 21 failures, and two
skips: 2,070 unit passes plus one obsolete retained-map source assertion, and
134 UI passes plus 20 failures and two skips. This run predates the final splash
interaction correction and root-lifecycle cancellation. It is not a passing
full-suite result. The obsolete source assertion has been updated to follow the
shared authorized projection.

The UI run exposed conflicts between splash interaction gating and existing
map controls. The map canvas now owns an accessibility container so its launch
gate does not override descendant visibility. Tab-bar visibility follows the
existing full-profile blocking state and returns to automatic handling after
reveal. The interactive glass Add button is removed while More Filters is open,
with an inert placeholder preserving dock geometry; its regression verifies
that it leaves the accessibility tree and becomes usable again after returning.

Final validation:

- The corrected-source recheck passed all 2,072 unit tests, including all 18
  foreground regressions and root-removal cancellation. Its 39 UI cases passed
  35 and failed four: hidden Add interaction, warm Feed timing, check-in calendar
  timing, and pinned Profile-header navigation.
- After the final Add correction, all 115 focused checks passed: 107 map unit
  tests and eight UI tests covering More Filters, all four launch-cover paths,
  and place-profile round trips.
- A final run without rebuilding or concurrent REC-484 compilation passed the
  warm Feed and pinned Profile-header cases with unchanged assertions. The
  check-in calendar case still failed: 5.344 seconds against its 1.0-second
  end-to-end UI-test limit. This remains unresolved, is not established to be
  pre-existing, and must not be treated as a passing performance check.
- The full suite has not been rerun to green after these corrections. All
  failures from the original integrated full run have been rechecked; the
  calendar timing case is the remaining reproduced failure.
- The final signed Debug iPhone build succeeded and strict signature
  verification passed: version 1.0, build 175, arm64 debug UUID
  `7BC99740-932D-3A28-8EF3-8E8BFB0B9172`. XcodeGen and whitespace checks passed.

The PR remains a draft phone-test candidate. Next manual checks are cold launch,
first visits and returns to each tab, and a 35-second background return, watching
the first 30 seconds after reveal. Device profiling is not required for this
pass unless severe lag remains. These automated results do not prove sustained
physical-device responsiveness or establish that all hangs are resolved.

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

## Earlier validation

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

The implementation PR remains in draft. The following verified device captures
supersede the earlier request for a matching capture and identify the next
presentation work. Previous incomplete automated validation remains documented
above; it is not a passing full-suite result.

## Verified September 16 device comparison

The accepted cold, short-return, and long-return recordings all matched the
Debug binary built from `dc06bd73d` on the iPhone 15 Pro running iOS 26.5.
Two intervening recordings used another branch's binary and are excluded.
Every window below starts at Foreground-Active and lasts 30 seconds.

| Scenario | Actual background interval | Stalls over 250 ms | Time overlapping stalls | Longest stall | Sampled main-thread CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Cold launch | n/a | 17 | 5.896 s | 0.713 s | 12.709 s |
| Short return | 5.975 s | 9 | 3.698 s | 0.628 s | 11.483 s |
| Long return | 33.979 s | 11 | 3.892 s | 0.455 s | 13.781 s |

The cold window was thermally nominal; both returns were fair. On the long
return, the successive ten-second windows contained 7, 4, and 0 stalls over
250 ms, with 2.512, 1.380, and 0 seconds overlapping those stalls. This supports
the observation that interaction improves while the resumed app catches up.
It does not measure FPS or establish a controlled percentage improvement.

In the long-return window, inclusive application stacks attributed 3.000
seconds to grouping, 2.863 seconds to grouping-key work, 1.659 seconds to
available list suggestions, and 2.275 seconds to list-detail body work.
Profile body work remained visible in the cold and short-return samples.
These stacks overlap and must not be added together. The capture does not
establish whether the list-detail work was offscreen.

## Grouping and presentation follow-up

- Grouping now normalizes each distinct `LocalPlace` object once per invocation.
  The key array supplies the initial and primary group keys. It is discarded
  at the end of that call because SwiftData models are mutable. Transitive
  alias merging, primary selection, ordering, and group membership are unchanged.
- List-suggestion eligibility retains the candidate array and ID set for the
  four most recently read lists. Keys include presentation revision, viewer,
  and resolved local/server list references. Each presentation invalidation
  clears the cache immediately, including inside deferred persistence batches.
  Existing tombstone exclusions and displayed suggestion ordering are preserved.
- Both profile-map navigation destinations prepare their dataset and camera
  only while presented. Unchanged datasets are reused for the same store,
  viewer, profile, and revision. Returned datasets refresh the clock while
  sharing their prepared collections. Both profile caches also check the actual
  store instance, preventing reuse of models from a replaced store with matching
  IDs and revision numbers.

Seven new tests cover normalization work, mutation between grouping calls,
repeated suggestion reads, list add/remove, blocks, account changes, bounded
retention, profile-map date freshness, save removal, and store/profile identity.
Three were first run against instrumented pre-fix behavior. They failed only
their work-count assertions; membership, aliases, ordering, and updated data
assertions passed.

| Regression fixture | Pre-fix work | Required work |
| --- | ---: | ---: |
| Grouping repeated saves for 8 distinct place objects | 52 key builds | 8 |
| Initial suggestions plus 30 unchanged eligibility reads | 31 candidate builds | 1 |
| Initial profile map plus 20 unchanged reads | 21 dataset builds | 1 |

### Validation of the presentation follow-up

The complete simulator run finished with 2,091 passes, 20 failures, and two
skips: 1,973 unit tests passed and one failed; 118 UI tests passed and 19
failed. All 16 foreground regressions passed, including the seven new cases.
The profile-map navigation/sharing tests passed, as did the list lifecycle,
large-map selection/dismissal, selected-pin camera work, warm source switching,
launch-cover readiness, and first-feed-scroll checks. The previously failing
high-data projection timing and feed-photo fallback tests passed in this run.

The full run failed the trusted-search p95 budget at 55.72 ms against 50 ms,
the first dense-map zoom at a 672 ms maximum frame gap against 100 ms, and the
cold-list first-swipe movement assertion. Other failures involved map search
focus, pin selection, filter dismissal, import interactions, and place-sheet
navigation/latency. These failures are not established to be pre-existing.

Six relevant failures were rerun with the same built app and original limits,
after the signed build completed. Five passed: trusted-search timing, trusted
search UI, dense-map zoom, cold-list first swipe, and place-profile Back
navigation. The three zoom interactions measured maximum frame gaps of 79,
48, and 53 ms. `testVisiblePlacePinSelectsOnFirstTap` still failed the expected
selected-card label assertion after a coordinate tap. The other 14 failures
were not rerun. The full suite therefore remains non-green; isolated passes
do not establish why the initial runs failed.

XcodeGen and whitespace validation passed without generated-project changes.
The signed Debug build for physical iOS succeeded, and its signature verified.
Build 173 has arm64 debug UUID `79D7C703-3079-3DE0-89A3-F4DE0AE8DE05`.
Simulator validation used a dedicated iPhone 17 on iOS 26.5 because the
documented iOS 18.6 runtime is not installed.

This is a phone-test candidate, not a merge-ready performance claim. Keep the
PR in draft. Run the candidate from the REC-484 Xcode project, verify the binary
UUID, and capture cold launch plus 5-second and 35-second background returns.
Also open/reopen a list and the profile map, then check suggestion freshness
after a list edit. Investigate the persistent pin-selection assertion and
remaining full-suite failures before merge. The operation counts establish
avoided work; a new matching phone trace must establish the effect on stalls.
No splash duration, analytics contract, or backend behavior changes in this pass.
