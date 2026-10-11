# REC-636 integrated validation

October 11, 2026 · Integrated `Wander` app · **Draft; Live remains off**

**Final candidate V12 large passed all 2,807 unit tests and all 11 Live UI journeys: 2,818 tests passed.** Isolated replay is excluded from that run. **The same built app also passed all 11 compact Live UI journeys, with no failures or skips.** The broader native gate remains incomplete: Map accessibility, inbox switcher capture and private-message replay freshness are still open.

This report is the candidate/results authority for the [review guide](../review-guide.md) and [capture gallery](integrated-captures.md). A focused pass establishes the named check, not a passing full suite or hosted readiness.

## Candidate and current checks

- Branch: `codex/live-experience-review`; integration base `d9f827353648bab91a17187721b5ea41e65e1a42`.
- Worktree: `/private/tmp/wander-live-review`; raw evidence: `/private/tmp/rec636-evidence/`.
- V12 source: **392 Swift files and six build inputs** match across both runs, recorded in `v12-source-hashes.json` and `v12-build-inputs.json`. Later source changes require a new candidate record.
- Xcode 26.6 / iOS 26.5; iPhone 17 Pro and iPhone SE (3rd generation).

| Check | Result | Evidence and scope |
|---|---|---|
| V12 large | **2,818 passed: 2,807 units + 11 Live UI** | `live-v12-final-large.xcresult`; units exclude isolated `ReplayMaskingTests`. Includes final query/store/lease, messaging, recovery and first-entry search-focus source. |
| V12 compact | **11/11 passed; no failures or skips** | `live-v12-final-compact.xcresult`; all 11 Live UI journeys using the same built app as large. |
| Original Feed return regressions | **2/2 passed** | `live-v11-search-return.xcresult`; original automatic-focus back-button and swipe-back paths pass after restricting Discover autofocus to a new search entry. Temporary manual-focus diagnostic removed from V12. |
| Credential replay | **Passed alone in a fresh process** | `live-v8-credential-isolated.xcresult`; does not establish private-message replay freshness. |
| Analytics/tooling | **Contract check and 12 dashboard tests passed** | No subsequent analytics event/property changes. Demo sends suppress analytics; message-success properties are aggregate-only. |
| SQL preparation | **Smoke-runner syntax and both rollback-preview generation checks rerun successfully; static review completed** | Both drafts remain **unpackaged, undeployed and unexecuted**. Generating rollback SQL is not database execution. |

Native units cover query/account/page fencing, accepted filter dimensions, monotonic per-row receipts before media work, lease expiry and filtered-empty-page continuation. Messaging tests use synthetic responses for retry identity, refresh/context loss, account/cancellation fences, one 401 refresh and disabled HTTP cache/cookies. They do not establish server authorization or real delivery.

The **Live Experience Review** scheme uses the production Live shell and existing Feed/Profile with isolated authenticated fixtures. Demo replies acknowledge **Simulated** and deliver nothing. Invitation rehearsal uses a detached Wanna, without sending an invitation or writing to the shared store; the dated received-invitation fixture exercises the existing recipient route. The [V12 gallery](integrated-captures.md) presents fourteen selected large/compact captures with candidate provenance. Original captures remain outside Git; the selected images do not prove hosted delivery or replay freshness.

## Full-run failure reconciliation

V6 full completed **3,059/3,070 passed**: all **2,788 units** and **271/282 UI**. The table accounts for all eleven failures. Ten have subsequent focused passing rechecks; Map accessibility remains open. This is not a rerun of the whole UI suite on V12.

| V6 failing test | Later result |
|---|---|
| `AccountContactDetailsUITests/testNormalAppLaunchReachesLiveAuthentication` | **Closed — V7 signed pass.** |
| `ImportFormRefinementUITests/testShareExtensionAutomaticallyCapturesExactlyOnce` | **Closed — V7 signed pass.** |
| `LiveMigrationAndPrivacyUITests/testDeferredCalendarRecoverySurvivesRelaunchAndExplicitOffRollback` | **Closed — V7 and V9 pass.** |
| `LiveMigrationAndPrivacyUITests/testPartialGuideAcknowledgementsPersistAcrossRelaunchAndRollback` | **Closed — V7 and V9 pass.** |
| `MapFilterInteractionUITests/testMoreFiltersHidesMapDockAndBottomNavigationDismissesWithoutResetting` | **Open — V7 and V9 still fail.** XCTest reports the disabled hidden field as hittable; the semantic accessibility regression remains open. This is not evidence of a VoiceOver privacy leak. |
| `MapPlaceCardUITests/testREC386ShowsMemberPhotoThenDeletesDisposableCheckIn` | **Closed — V7 signed pass.** |
| `OnboardingUITests/testFeedInlineSearchCoversEntryEmptyResultsNavigationAndBack` | **Closed — V11 original swipe-back pass**, alongside the original automatic-focus back-button test. |
| `OnboardingUITests/testLoggedOutCarouselAutoAdvancesAndKeepsActionsVisible` | **Closed — V9 pass** with fresh page-value queries. |
| `OnboardingUITests/testMapWannaAndSaveRespondToSinglePhysicalTap` | **Closed — V7 pass.** |
| `OnboardingUITests/testReturningUserColdStartAndOrdinaryForegroundOpenFeed` | **Closed — V9 pass** with deterministic stale-checkpoint coverage; the new explicit-Profile destination check also passes. |
| `PersonTypeaheadUITests/testCheckInAndWannaNotesUseTheSamePicker` | **Closed — V7 and V9 pass.** All seven people-picker checks passed V7. |

Recheck bundles: `live-v7-signed-recheck.xcresult` (**2,828/2,834 passed**), `live-v9-focused.xcresult` (**49/53 passed**) and `live-v11-search-return.xcresult` (**2/2 passed**). V7's stale unit source assertion was corrected; V12 all-unit verification passes. V9 passed all 41 walkthrough units, three D9 recovery checks, thread switcher privacy, carousel, both stale-checkpoint destinations and notes. Its four failures were Map accessibility, inbox switcher capture, private-message replay and Feed back-button return; V11 closes the Feed failure.

## Remaining gates

1. **Map accessibility:** resolve the hidden input's XCTest hittability while More Filters is open, then pass `testMoreFiltersHidesMapDockAndBottomNavigationDismissesWithoutResetting`. The disabled field's reported semantics remain a regression gate, not a proven VoiceOver privacy leak.
2. **Inbox switcher capture:** establish the required privacy-cover observation with the Astir card fully visible. V9's card was cropped on the right with map background and no private content visible; its thread switcher check passed. The inbox capture remains unverified.
3. **Private-message replay:** obtain a fresh post-load SDK control frame and verify private content is absent. In V10 the new public label passed native OCR, but all 18 SDK frames retained the old public “Ready” label with the private area black. No private-content leak assertion failed; stale frames cannot validate privacy. Preserve the strengthened post-load control assertion. These three open checks leave the broad native gate incomplete.
4. **Database:** package messaging then Live-query SQL as ordered CLI-generated migrations, reconcile target/history, execute regression and metadata checks and pass rollback-only hosted smoke. Follow the [packaging instructions](../implementation-drafts/README.md). Missing RPC/schema must fail verification.
5. **Real messaging:** verify delivery between two mutual accounts, both explicit server account flags, revocation/restoration, hard blocks, context access and same-ID retries before internal activation. Global/device flags cannot enroll participants. Reporting and soft-delete retention/export remain broader-rollout gates.
6. **Handoff and device review:** open this isolated worktree's `Wander.xcodeproj`, verify the branch chooser and **Live Experience Review** scheme, and complete outstanding hardware drawing, spoken VoiceOver and production-volume review before claiming those properties.

D11 is settled: **15 minutes per social activity, measured from its monotonic authorized-response receipt**; owner rows are exempt and Profile/legacy cache policy is unchanged. Initial messaging rollout is **internal-only**. Current device-location centering is not implemented; selected-city centers work. Keep `unified_live_v1` default off and the PR in draft. Native fixtures do not establish hosted activation, real delivery or TestFlight readiness.

## Resume commands

Run from `/private/tmp/wander-live-review`. Both V12 result bundles are closed. Use fresh result-bundle paths for any further native run and record source identity. Run replay by itself after addressing its freshness failure; repeating the unchanged diagnostic is not a fix.

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
