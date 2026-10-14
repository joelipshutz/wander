# REC-636 integrated validation

October 13, 2026 · Integrated `Wander` app · **Draft; Live remains off**

**Current native candidate: V15, source commit `362f9418dd0e097d6ab0063017c79cebba34ea50`, integrated with main `bc2fa4d585ceb6fb97858e1c157a2cc43019e982` (build 181).** Current full-suite, CI and backend gate results are maintained in [PR #736](https://github.com/joelipshutz/wander/pull/736) and [REC-636](https://linear.app/recme/issue/REC-636/specify-and-prototype-the-unified-live-map-feed-and-user-journey). The V16 checks below use the frozen V15 binary. This file also preserves completed V12/V13 evidence and its limits; a newer status in the PR does not relabel these historical binaries.

**The frozen V13 full run completed with 3,082 of 3,092 tests passing: all 2,808 units and 274 of 284 UI tests, with ten UI failures and no skips. All ten original failures subsequently passed against the unchanged built app.** The failed full result remains part of the record; later focused passes do not replace it. All Live journeys, recovery/privacy, Map input and Feed paging cases passed within the full run. Final focused V13 checks also pass Map accessibility on both sizes, compact Feed paging and both large inbox/thread switcher captures. Actual private-message replay passed separately on both sizes. Consult the PR for the final integrated full-suite and CI results.

This report records candidate provenance for the [review guide](../review-guide.md) and [capture gallery](integrated-captures.md); the linked PR carries the current review gate status. A focused pass establishes the named check, not a passing full suite or hosted readiness.

## Current V15/V16 evidence

- V15 changes only three test files after V14: replay layout/OCR scheduling, switcher screenshot/OCR timing, and separately asserted mention deletion steps. App source, performance budgets and all 21 tracked build inputs remain unchanged. The 403-source/21-input manifests match after the V16 focused runs.
- [V15 Privacy CI](https://github.com/joelipshutz/wander/actions/runs/38478621783) passed 2,813 unit/large-UI tests and four compact tests, zero skips. Inbox/thread switcher checks passed on both sizes. Private SDK replay and credential replay each passed in separate processes.
- [V15 Feed CI](https://github.com/joelipshutz/wander/actions/runs/38478621773) failed two unit checks: list projection 138.927 ms against the unchanged 120 ms budget, and a two-second share-loader callback wait. The same share test passed in Privacy at the same head. Feed compact scrolling, generic build and both isolated replay scenarios passed. Preserve this failed workflow result.
- Both V15 private SDK replay runs observed the fresh **Replay loaded** control and checked all collected frames for forbidden text: five frames in Privacy, seven in Feed. Zero failed native draws were reported. These close the V14 stale-frame observation; they do not alter the earlier failed evidence.
- V16 same-host diagnostics passed all five checks across baseline, candidate and isolated share-loader runs. Search p95 was 22.103 ms on frozen main and 24.322 ms on the candidate, both under 50 ms. Both high-data tests passed their unchanged 120 ms list/500 ms cold assertions. Logged list stage subtotals were 62.959 ms and 55.788 ms, respectively; these exclude final logging/return overhead and are not the exact asserted total. The isolated share loader passed in 0.209 seconds.
- V16 evidence: `v16-benchmark-baseline`, `v16-benchmark-candidate` and `v16-share-loader-candidate`, each with `.log` and `.xcresult` in the shared evidence directory. This single iPhone 17 Pro/iOS 26.5 comparison does not demonstrate a budget regression; it does not establish the documented iPhone 16 Plus/iOS 18.6 reference-device signoff. That runtime is unavailable locally.
- The ordered [SQL migrations](../implementation-drafts/README.md) are packaged with executable bodies matching the reviewed drafts. The full rollback-only linked smoke export generates successfully. Database execution is still outstanding; generation is not a database pass.
- Xcode handoff is verified: the isolated worktree project is open, Branch Chooser shows `codex/live-experience-review`, and the selected scheme is **Live Experience Review**. No app was launched by this handoff.
- V14 full native was interrupted after all 2,808 units passed, during UI timeouts, and result finalization was incomplete. V14 Feed and Privacy CI failed. V15 compilation passed; final full-suite completion and current gate status remain in PR #736 and REC-636.

## Historical candidate checks

- Branch: `codex/live-experience-review`; integration base `d9f827353648bab91a17187721b5ea41e65e1a42`.
- Worktree: `/private/tmp/wander-live-review`; raw evidence: `/private/tmp/rec636-evidence/`.
- V12 source: **392 Swift files and six build inputs** match across both runs, recorded in `v12-source-hashes.json` and `v12-build-inputs.json`. Later source changes require a new candidate record.
- V13 source is frozen in `v13-source-hashes.json` and `v13-build-inputs.json`: **403 native Swift files and 21 tracked build inputs**. All hashes and the native source path set were verified unchanged after the full run. This expands the manifest to existing extension/shared source and tracked configurations; it does not imply new source files. XcodeGen produced no project or generated-file diff before the freeze.
- V14 retains the same **403 native source files and 21 tracked build inputs**, recorded in `v14-source-hashes.json` and `v14-build-inputs.json`. Main contributes only build 181 metadata and the people-picker spacing test assertions. XcodeGen produces no further diff; independent merge review confirms the Live tests and imported assertions are preserved.
- Xcode 26.6 / iOS 26.5; iPhone 17 Pro and iPhone SE (3rd generation).

| Check | Result | Evidence and scope |
|---|---|---|
| V12 large | **2,818 passed: 2,807 units + 11 Live UI** | `live-v12-final-large.xcresult`; units exclude isolated `ReplayMaskingTests`. Includes final query/store/lease, messaging, recovery and first-entry search-focus source. |
| V12 compact | **11/11 passed; no failures or skips** | `live-v12-final-compact.xcresult`; all 11 Live UI journeys using the same built app as large. |
| Original Feed return regressions | **2/2 passed** | `live-v11-search-return.xcresult`; original automatic-focus back-button and swipe-back paths pass after restricting Discover autofocus to a new search entry. Temporary manual-focus diagnostic removed from V12. |
| Credential replay | **Passed alone in a fresh process** | `live-v8-credential-isolated.xcresult`; does not establish private-message replay freshness. |
| Analytics/tooling | **Contract check and 12 dashboard tests passed** | No subsequent analytics event/property changes. Demo sends suppress analytics; message-success properties are aggregate-only. |
| SQL preparation | **Smoke-runner syntax and both rollback-preview generation checks rerun successfully; static review completed** | At this historical check both drafts were **unpackaged, undeployed and unexecuted**; current packaging is recorded above. Generating rollback SQL is not database execution. |
| V13 private replay | **Passed on large and compact** | `replay-v13-private-opaque-large.xcresult` and `replay-v13-private-opaque-compact.xcresult`; exact post-load SDK control plus forbidden-text checks across every collected frame. |
| V13 credential replay | **Passed in its own process on compact** | `replay-v13-credential-bounded-cadence.xcresult`; credential assertions retained. |
| V13 switcher privacy | **Inbox and thread focused checks passed on large** | `ui-v13-inbox-isolated.xcresult` and the thread case in `ui-v13-large-map-privacy-baseline.xcresult`; active fictional content, centered inactive cover and return behavior checked. See the startup-tap limitation below. |
| V13 compact Feed | **Passed with fresh accessibility count queries** | `ui-v13-feed-fresh-query.xcresult`; original counts, pagination/end assertions and 15-second wait retained. No Feed implementation change. Hosted CI confirmation remains pending. |
| Final V13 compact focus | **38/38 passed** | `ui-v13-final-focused-compact.xcresult`; 36 shared-input contracts, expanded Map regression and Feed paging. |
| Final V13 large focus | **39/39 passed** | `ui-v13-final-focused-large.xcresult`; the same 36 shared-input contracts, expanded Map regression and both private inbox/thread switcher checks. |
| V13 full native | **3,082/3,092 passed; ten UI failures, no skips** | `live-v13-full-native.xcresult`; all 2,808 units and 274/284 UI passed. Isolated replay is excluded. See the late-run failures below. |
| V13 late-failure rechecks | **All ten original failures passed unchanged** | `ui-v13-awake-failure-recheck.xcresult` passed nine cases; its appearance case exceeded an insufficient 300-second command limit. `ui-v13-awake-appearance-recheck.xcresult` then passed that case in 431.322 seconds with a 600-second allowance. No app/test source or assertion changes. |

Native units cover query/account/page fencing, accepted filter dimensions, monotonic per-row receipts before media work, lease expiry and filtered-empty-page continuation. Messaging tests use synthetic responses for retry identity, refresh/context loss, account/cancellation fences, one 401 refresh and disabled HTTP cache/cookies. They do not establish server authorization or real delivery.

The **Live Experience Review** scheme uses the production Live shell and existing Feed/Profile with isolated authenticated fixtures. Demo replies acknowledge **Simulated** and deliver nothing. Invitation rehearsal uses a detached Wanna, without sending an invitation or writing to the shared store; the dated received-invitation fixture exercises the existing recipient route. The [V12 gallery](integrated-captures.md) presents fourteen selected large/compact captures with candidate provenance. Original captures remain outside Git; the selected images do not prove hosted delivery or replay freshness.

## Focused V13 privacy evidence

The replay fixture now uses the production configuration's one-second capture cadence. Its former 0.1-second override could queue screenshots faster than the SDK's serial image encoder delivered them. The test waits for exact public controls before and after loading the private view, inspects only newly delivered images while waiting, then checks every collected image for forbidden private text. Each replay scenario runs in a separate process in CI. Events are dropped before upload and the fixture transport is offline.

The native fixture independently renders readable fictional participant/message content. The actual SDK output then shows the new public **Replay loaded** control with the private SwiftUI surface masked. The final large run collected eight SDK images and reported 23 successful native draws with zero incomplete draws. Compact collected ten images and reported nine successful and two incomplete native draws; the SDK does not attach draw-success metadata to individual images. Compact's freshness/privacy checks still passed, but it is not proof that every native capture was complete. No production masking behavior was changed to obtain these results.

| Large native fixture | Large actual SDK frame | Compact actual SDK frame |
|---|---|---|
| ![Readable fictional private fixture](privacy/private-fixture-large.png) | ![Fresh large SDK frame with private content masked](privacy/private-replay-large.png) | ![Fresh compact SDK frame with private content masked](privacy/private-replay-compact.png) |

These are original PNGs copied without visual edits from the two final opaque-fixture result bundles. Frozen replay test SHA-256: `feecbe2bab22f8c2fd22b7c5b996ccf41b1c5f06a58c7f1c8c3aa3ac455acaad`.

The switcher test now waits for the privacy-cover label to be centered and stable before accepting the card framing; full-screen forbidden-content assertions remain. Both final large captures visibly show the centered Astir card with the opaque cover. Full-resolution recordings and switcher PNGs stay with the result bundles outside Git. In the first V13 combined run, the inbox case failed earlier: a highlighted Messages tap did not open the sheet. The exact isolated case and both switcher cases in the full run subsequently passed without a retry or navigation delay. Source review did not establish a startup reset cause; this history is not a claimed navigation fix.

The messaging draft also rechecks context after both the sender-lock wait and a possible reciprocal-pair insert wait. Rollback regressions now cover the 50-conversation daily boundary, existing-thread reuse, another sender's quota, window expiry and revoked-context restoration. Swift/SQL RPC argument, response and cursor contracts were independently reviewed without a blocking mismatch. These remain preparation results, not database execution or real-client authentication evidence.

## Final V13 Map accessibility repair

The Map host exported a directly represented text editor even when its native hidden, interaction and accessibility flags excluded it. A plain represented container now retains the same native editor and controls its accessibility children. Native/hosted tests preserve text, mentions, selection, composition, sizing and parent-level hit testing through hide/show. The hidden search icon and Clear action are omitted while the editor remains mounted.

The expanded nonempty-query check independently found that the search row's inherited interaction shape made Clear claim the entire capsule in accessibility. Removing that row-level shape and giving Clear its own 44-point plain target restores distinct, nonoverlapping editor/button bounds. The original glass surface is unchanged. Testing the original represented editor with this shape fix still failed hidden accessibility, establishing that the container is also required.

Both final phone runs verify no hidden editor, placeholder, icon, Clear, Add or Cancel; after dismissal, exactly one hittable editor retains `coffee`, Clear has separate bounds, and a physical tap opens the keyboard. Original navigation/filter assertions remain. Failed intermediate experiments are not retained in production code.

## Full-run failure reconciliation

V13 completed all scheduled tests, but its ten late UI failures keep that full result red. One appearance test, one Profile alignment test, one Profile header test, all three Profile responsiveness tests, two Share Card tests and two Your Map tests failed. Several nominally short actions took hundreds of seconds, including actions in passing neighboring tests. The adaptive Your Map test additionally reused a pin whose unobstructed gesture frame shrank after zoom. All ten passed unchanged on the same built app in the separate rechecks above. No production or test fix is claimed for these ten cases.

The first recheck's 300-second command-level limit was shorter than the appearance test's earlier passing V6 baseline of 362.647 seconds. Its separate 600-second recheck passed without changing the original five-second appearance assertions. Keep that harness-limit failure distinct from the original full-run failures. The final integration candidate still needs its own full run and CI confirmation.

V6 full completed **3,059/3,070 passed**: all **2,788 units** and **271/282 UI**. The table accounts for all eleven failures. All eleven have subsequent focused passing rechecks and also passed within V13's full run. This is not a passing full-suite result on V12 or V13.

| V6 failing test | Later result |
|---|---|
| `AccountContactDetailsUITests/testNormalAppLaunchReachesLiveAuthentication` | **Closed — V7 signed pass.** |
| `ImportFormRefinementUITests/testShareExtensionAutomaticallyCapturesExactlyOnce` | **Closed — V7 signed pass.** |
| `LiveMigrationAndPrivacyUITests/testDeferredCalendarRecoverySurvivesRelaunchAndExplicitOffRollback` | **Closed — V7 and V9 pass.** |
| `LiveMigrationAndPrivacyUITests/testPartialGuideAcknowledgementsPersistAcrossRelaunchAndRollback` | **Closed — V7 and V9 pass.** |
| `MapFilterInteractionUITests/testMoreFiltersHidesMapDockAndBottomNavigationDismissesWithoutResetting` | **Closed — final V13 passes on both sizes.** Hidden AX absence, original navigation/filter behavior, retained nonempty query, distinct Clear bounds and restored physical input are checked. |
| `MapPlaceCardUITests/testREC386ShowsMemberPhotoThenDeletesDisposableCheckIn` | **Closed — V7 signed pass.** |
| `OnboardingUITests/testFeedInlineSearchCoversEntryEmptyResultsNavigationAndBack` | **Closed — V11 original swipe-back pass**, alongside the original automatic-focus back-button test. |
| `OnboardingUITests/testLoggedOutCarouselAutoAdvancesAndKeepsActionsVisible` | **Closed — V9 pass** with fresh page-value queries. |
| `OnboardingUITests/testMapWannaAndSaveRespondToSinglePhysicalTap` | **Closed — V7 pass.** |
| `OnboardingUITests/testReturningUserColdStartAndOrdinaryForegroundOpenFeed` | **Closed — V9 pass** with deterministic stale-checkpoint coverage; the new explicit-Profile destination check also passes. |
| `PersonTypeaheadUITests/testCheckInAndWannaNotesUseTheSamePicker` | **Closed — V7 and V9 pass.** All seven people-picker checks passed V7. |

Recheck bundles: `live-v7-signed-recheck.xcresult` (**2,828/2,834 passed**), `live-v9-focused.xcresult` (**49/53 passed**) and `live-v11-search-return.xcresult` (**2/2 passed**). V7's stale unit source assertion was corrected; V12 all-unit verification passes. V9 passed all 41 walkthrough units, three D9 recovery checks, thread switcher privacy, carousel, both stale-checkpoint destinations and notes. Its four failures were Map accessibility, inbox switcher capture, private-message replay and Feed back-button return; V11 closes the Feed failure.

## Review gates

1. **Final native/CI confirmation:** use the frozen V15 candidate and V16 full-suite results recorded in the linked PR. All ten late V13 failures passed unchanged in focused rechecks. Both switcher cases passed in the V13 full run; retain the earlier unexplained first inbox tap in the failure history instead of claiming a navigation fix. Do not infer a passing final gate solely from this historical report.
2. **Candidate record:** frozen V15 manifests match after the V16 focused checks; verify them again before commit. Any further source or integration change requires a new candidate record. V12 captures retain their original provenance; new focused passes do not silently relabel that earlier binary.
3. **Source/CI handoff:** verify the published candidate and required workflow results in the PR before calling step 1 complete.
4. **Database:** the ordered CLI-generated messaging and Live-query migrations are packaged; reconcile target/history, execute regression and metadata checks and pass rollback-only hosted smoke. Follow the [packaging instructions](../implementation-drafts/README.md). Missing RPC/schema must fail verification.
5. **Real messaging:** verify delivery between two mutual accounts, both explicit server account flags, revocation/restoration, hard blocks, context access and same-ID retries before internal activation. Global/device flags cannot enroll participants. Reporting and soft-delete retention/export remain broader-rollout gates.
6. **Handoff and device review:** the isolated project, branch chooser and **Live Experience Review** scheme are verified; complete outstanding hardware drawing, spoken VoiceOver and production-volume review before claiming those properties.

D11 is settled: **15 minutes per social activity, measured from its monotonic authorized-response receipt**; owner rows are exempt and Profile/legacy cache policy is unchanged. Initial messaging rollout is **internal-only**. Current device-location centering is not implemented; selected-city centers work. Keep `unified_live_v1` default off and the PR in draft. Native fixtures do not establish hosted activation, real delivery or TestFlight readiness.

## Resume commands

Run from `/private/tmp/wander-live-review`. Both V12 result bundles and the named V13 replay bundles are closed. Use fresh result-bundle paths for any further native run and record source identity. Replay scenarios must remain in separate test processes; their focused passes above are complete and need repetition only when a relevant change or new failure requires it.

```sh
xcrun xcresulttool get test-results summary --path /private/tmp/rec636-evidence/live-v12-final-compact.xcresult

xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=21FFD105-FF94-44D6-82F0-2DF1DF4A6724' \
  -derivedDataPath /private/tmp/rec636-evidence/FinalDerivedData \
  -resultBundlePath /private/tmp/rec636-evidence/live-next-private-replay.xcresult \
  -jobs 2 -parallel-testing-enabled NO \
  -only-testing:WanderTests/ReplayMaskingTests/testPrivateMessageContentIsMaskedInActualReplayImage \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- GENERATE_INFOPLIST_FILE=YES

# After reviewed migrations are installed on the confirmed target:
supabase migration list --linked
npm --prefix scripts ci --ignore-scripts
node scripts/supabase-smoke-test.mjs
```
