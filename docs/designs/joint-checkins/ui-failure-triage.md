# Broad UI failure triage

REC-566 · September 22, 2026

**All 27 residual failures are triaged. Eighteen reproduce the same first failure on the unchanged baseline, six pass in the candidate rerun, and three fail at different points and retain explicit follow-ups. No application or test source was changed, and no failing assertion was waived.**

The original full run remains **2,604 passed / 29 failed**. Its two failures in the changed area were fixed previously. This report covers the other 27; it does not turn that full run into a pass or complete the separate joint-check-in rollout gates.

## Controlled comparison

| Run | Revision | Passed | Failed | Skipped |
| --- | --- | ---: | ---: | ---: |
| Candidate | `00bc55ec8e047c50afa2802e0aa092042af0a62d` | 6 | 21 | 0 |
| Integrated main baseline | `6dd9b4fb89d40966e8a9644e728902fec166a310` | 4 | 23 | 0 |

Both runs select the same 27 byte-identical test method bodies on the same iPhone 16e, iOS 26.3.1 (`6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C`). They use the same unsigned configuration, 180-second per-test allowance and serial execution through the workspace `ios-work.py` helper. Optional diagnostic collection is disabled; assertions, logs, videos, hierarchies and result bundles are retained. Neither checkout has optional `LocalAuth.xcconfig` configuration.

The baseline is the main revision already integrated into this PR. Later changes on main are outside this comparison and must be checked before implementing follow-ups. Baseline attempts 01/02 were refused by the storage floor before tests ran; only attempt 03 is counted. Its import case crashed with signal term during launch, which is an inconclusive behavioral comparison.

Every candidate-failing test also fails in the baseline run, but matching test names do not establish matching causes. The three different first failures are called out below. Four of the six candidate passes also pass on baseline; Feedback and dense-map probe readiness fail only on baseline. A single successful rerun is recorded as not reproduced, not fixed or proven flaky.

## Disposition and ownership

| Group | Tests | Follow-up |
| --- | ---: | --- |
| Obsolete UI expectations on both revisions | 13 | [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| Settings selector and geography visibility/geometry problems | 2 | [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| Walkthrough animation-idle timeout | 1 | [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| Native tab identity / rendered appearance | 2 | [REC-603](https://linear.app/recme/issue/REC-603/restore-reliable-tab-bar-appearance-acceptance-on-compact-iphone) |
| Physical Map tap-away does not dismiss selection | 2 | [REC-604](https://linear.app/recme/issue/REC-604/fix-compact-map-tap-away-dismissal-in-the-dense-place-fixture) |
| Saved-import physical-tap behavior still unresolved | 1 | [REC-605](https://linear.app/recme/issue/REC-605/verify-saved-import-navigation-from-partially-visible-rows) |
| Not reproduced on candidate | 6 | Retain coverage; REC-566, existing [REC-378](https://linear.app/recme/issue/REC-378/make-physical-map-and-feed-hitch-tests-enforce-stable-regression-thresholds) / [REC-536](https://linear.app/recme/issue/REC-536/resolve-existing-search-result-and-legacy-rating-editor-ui-acceptance) |

The first group means the tests contain obsolete expectations, not that replacing strings proves every later assertion. In particular, the first-Wanna case has an additional initial-tap failure in the candidate run.

### Source-confirmed obsolete contracts

- Two share tests expect `ActivityListView` directly; `PlaceProfileMapSurface.swift:876` opens the branded preview first. Both result hierarchies show `Close share preview`, not the old `Close` control.
- Five permission tests expect old Contacts purpose text, the removed location headline or a Continue-only contact step. The current flow uses Find friends / Not now. Preserve consent and denial recovery when updating these tests.
- Five editor tests assume tags are already expanded or use removed note headings/placeholders. `MapScreen.swift:13404` starts optional details collapsed; `noteSection` uses current status-specific copy. Preserve draft retention/isolation, calendar and scroll assertions.
- The extension test selects an Astir cell while the extension display name is Save to Astir (`project.yml:193`). Signed App Group exactly-once capture still needs verification after discovery is corrected.

### Runtime findings and limits

- **Settings:** the test’s global Notifications-prefix locator chooses background `profile.checkInInvitations`, not the Settings row. The log names that target and a (-1,-1) hit point. Scope the selector and recheck hidden-screen accessibility; preserve both navigation rounds.
- **Geography:** expansion pushes the month section offscreen, yielding an infinite frame. Both runs then fail to collapse, leaving ten rows and the expanded height. Correct viewport assumptions first, then verify the collapse interaction; do not remove the row-count or spacing assertions.
- **Walkthrough:** both runs spend repeated 60-second waits on animation-idle notifications and reach the 180-second deadline. The next coach mark is already visible. Identify the recurring animation/readiness cause; do not merely increase the timeout.
- **Map dismissal:** both runs retain the selected card and active pin after the physical empty-map tap. Candidate hierarchy places the tap at (31.2, 388.24), above the card and away from the active pin. Other annotation hit testing and delayed dismissal state checks remain to be traced. Do not substitute a debug dismissal action.

### Three different first failures

1. **Light tab bar:** candidate fails `main.tabBar` identity at line 105; baseline reaches the inactive-icon contrast assertion at line 119 and reports zero dark pixels. Baseline Dark independently reproduces the candidate identity failure. Both lifecycle and rendered appearance need investigation; preserve existing pixel thresholds.
2. **First Wanna:** candidate fails initial attached-tray presentation at line 1752; baseline opens it and reaches obsolete options/copy assertions beginning at line 1762. A fresh physical tap in the exact tested candidate binary opens the editor with current controls. This is one successful manual check, not a repair or proof of reliable first-tap timing.
3. **Saved import:** candidate remains on Import report after tapping a partially visible row, then fails line 383. Baseline’s automated attempt crashes with signal term before reaching navigation. Fresh accessibility activation of the saved row opens the correct full profile with `place-profile.back` on both binaries. Physical scrolling/tapping parity remains unverified; accessibility activation is not counted as the physical-tap test passing.

Manual captures: [candidate Wanna physical tap](native-evidence/triage/candidate-wanna-physical-tap.png), [baseline import accessibility activation](native-evidence/triage/baseline-import-accessibility-activation.png), [candidate import accessibility activation](native-evidence/triage/candidate-import-accessibility-activation.png). These use fictional fixtures and unmodified tested binaries.

## Per-test matrix

Full first-line assertion lists and durations are recorded in [ui-failure-results.json](ui-failure-results.json). Failing automated results remain failing even when a separate manual check succeeds.

| Test | Baseline | Candidate | Disposition / next action |
| --- | --- | --- | --- |
| `ContactDiscoveryUITests/testFollowingScreenEnableDisableAndExistingFollowSurvives` | Passed | Passed | Not reproduced on candidate. Candidate passed; retain existing assertions. [REC-566](https://linear.app/recme/issue/REC-566/combine-invited-participants-in-one-shared-check-in-feed-card) |
| `EventsComingSoonUITests/testDarkTabBarStaysDarkAcrossEventsVisits` | Failed | Failed | Native tab identity. Candidate and baseline fail the main.tabBar identifier assertion (line 105). [REC-603](https://linear.app/recme/issue/REC-603/restore-reliable-tab-bar-appearance-acceptance-on-compact-iphone) |
| `EventsComingSoonUITests/testLightTabBarStaysLightAcrossEventsVisits` | Failed | Failed | Native tab identity / appearance. Candidate fails identity at line 105; baseline reaches inactive icon contrast and fails at line 119. Preserve both signatures. [REC-603](https://linear.app/recme/issue/REC-603/restore-reliable-tab-bar-appearance-acceptance-on-compact-iphone) |
| `FeedbackUITests/testVoicePlaybackAndReplacementKeepsTextDraft` | Failed | Passed | Not reproduced on candidate. Candidate passed; baseline fails playback control existence after switching back to Voice (line 88). Cause of varying result remains open. [REC-566](https://linear.app/recme/issue/REC-566/combine-invited-participants-in-one-shared-check-in-feed-card) |
| `ImportFormRefinementUITests/testInlineImportDetailsUseTheCardSurface` | Failed | Failed | Obsolete expectation present. Searches for expanded tags without opening optional details. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `ImportFormRefinementUITests/testSavedImportPlaceOpensItsProfile` | Failed | Failed | Import physical tap: unresolved. Candidate physical tap leaves the report open; baseline test crashes with signal term before the assertion. Fresh accessibility activation opens the correct profile on both binaries; physical-tap parity remains unverified. [REC-605](https://linear.app/recme/issue/REC-605/verify-saved-import-navigation-from-partially-visible-rows) |
| `ImportFormRefinementUITests/testShareExtensionAutomaticallyCapturesExactlyOnce` | Failed | Failed | Obsolete expectation present. The extension display name is Save to Astir on both revisions; the fresh branch run cannot find the obsolete Astir cell (lines 18–19). Signed App Group capture remains a separate gate. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `MapFilterInteractionUITests/testPerformanceFixtureMeasuresPlaceSelectionAndTapAwayDismissalHitches` | Failed | Failed | Map dismissal behavior. Card and active pin remain after the same physical tap on both revisions (lines 204/205/229). [REC-604](https://linear.app/recme/issue/REC-604/fix-compact-map-tap-away-dismissal-in-the-dense-place-fixture) |
| `MapFilterInteractionUITests/testPerformanceFixtureSelectsPinAndDismissesCardOnEmptyMapTap` | Failed | Failed | Map dismissal behavior. Card and active pin remain after the same physical tap on both revisions (lines 262/263). [REC-604](https://linear.app/recme/issue/REC-604/fix-compact-map-tap-away-dismissal-in-the-dense-place-fixture) |
| `MapFilterInteractionUITests/testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins` | Failed | Passed | Not reproduced on candidate. Candidate passed; baseline probe readiness timed out at line 374. Original broad-run frame-gap failure is a different signature. [REC-378](https://linear.app/recme/issue/REC-378/make-physical-map-and-feed-hitch-tests-enforce-stable-regression-thresholds) |
| `MapPlaceCardActionInteractionUITests/testActionButtonsCancelAfterDraggingAwayAndStillRespondToTaps` | Failed | Failed | Obsolete expectation present. Share opens the branded preview before any system share sheet. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `MapPlaceCardUITests/testSelectedPlaceCardAndVerticalPlacePageRoundTrip` | Failed | Failed | Obsolete expectation present. Same obsolete direct system-sheet expectation. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `NativeAccountSetupUITests/testNativeDarkSetupCaptureInventory` | Failed | Failed | Obsolete expectation present. Contacts route exposes Find friends and Not now, not Continue. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `NativeAccountSetupUITests/testNativeLocationAndContactsDenialsPreserveRecovery` | Failed | Failed | Obsolete expectation present. Contacts step uses obsolete Continue locator; appears in two test classes. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `NativeOnboardingFlowUITests/testNativeLocationAndContactsDenialsPreserveRecovery` | Failed | Failed | Obsolete expectation present. Contacts step uses obsolete Continue locator; appears in two test classes. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testActualFeedContactInvitePrimerUsesSingleNeutralAction` | Failed | Failed | Obsolete expectation present. Contacts purpose text changed in REC-560; test uses obsolete exact text. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testActualOnboardingPermissionScreensUseSingleNeutralAction` | Failed | Failed | Obsolete expectation present. Location heading changed; contacts section also expects obsolete Continue-only UI. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testCheckInCalendarTrayPresentationLatency` | Failed | Failed | Obsolete expectation present. New forms start with tags collapsed; this test requires them already expanded. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testCompactWannaFormScrollsWithoutPullingTheSheet` | Failed | Failed | Obsolete expectation present. Measures the frame of a removed label; original failure explicitly names it. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testFirstMapCheckInUsesAttachedEditorAndRestoresItsDraft` | Failed | Failed | Obsolete expectation present. Obsolete expanded-tags assertion, followed by removed heading. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testFirstMapWannaOpensAFreshDraftEachTime` | Failed | Failed | Obsolete expectation present. Both revisions contain obsolete tags/heading/placeholder assertions. Candidate initially fails to open the tray, while baseline reaches the obsolete assertions. A fresh physical tap opens the candidate tray with current controls; automated first-tap reliability is still open. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testMapWannaAndSaveRespondToSinglePhysicalTap` | Passed | Passed | Not reproduced on candidate. Candidate passed; preserve physical single-tap coverage. [REC-566](https://linear.app/recme/issue/REC-566/combine-invited-participants-in-one-shared-check-in-feed-card) |
| `OnboardingUITests/testNativeMapOverviewUsesRealControlsAndEndsWithoutSaving` | Failed | Failed | Automation quiescence timeout. Candidate spends repeated 60-second waits on animation-idle notifications before reaching the 180-second limit; exact animation still to isolate. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `OnboardingUITests/testRatingSliderRespondsThroughoutContinuousDrag` | Passed | Passed | Not reproduced on candidate. Candidate passed; prior baseline rating failures also tracked in REC-536. [REC-536](https://linear.app/recme/issue/REC-536/resolve-existing-search-result-and-legacy-rating-editor-ui-acceptance) |
| `OnboardingUITests/testReturningUserColdStartOpensFeedAndForegroundKeepsSelectedTab` | Passed | Passed | Not reproduced on candidate. Candidate passed; do not label one successful rerun a permanent repair. [REC-566](https://linear.app/recme/issue/REC-566/combine-invited-participants-in-one-shared-check-in-feed-card) |
| `ProfileResponsivenessUITests/testSettingsDestinationsAndReturnToScrolledProfile` | Failed | Failed | Ambiguous selector. Global Notifications prefix query taps underlying profile.checkInInvitations instead of the Settings row. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |
| `YourMapPrototypeUITests/testGeographyExpandsAndCollapsesInPlaceWithoutUnknowns` | Failed | Failed | Offscreen geometry assertion. Expanded geography pushes the month section offscreen; its accessibility frame becomes infinite. The subsequent collapse tap also leaves 10 rows and the expanded height on both revisions; preserve and recheck that interaction after correcting visibility. [REC-602](https://linear.app/recme/issue/REC-602/repair-stale-ui-test-contracts-and-compact-device-automation) |

## Evidence and reproduction

Local raw evidence is retained outside the checkout in `../joint-checkin-implementation-evidence/`: `ui-triage-branch-01.xcresult`, `ui-triage-baseline-03.xcresult`, matching logs/invocations/summaries/test-details, source/method equality audits, exported screenshots/hierarchies/videos and `ui-triage-manual-checks.json`. The original broad result bundle is no longer at its old cache path; its summary and log remain, so that run cannot supply additional screenshots retrospectively.

`ui-triage-run.py CHECKOUT LABEL` reproduces the selected set through the required helper; its selector list is `ui-triage-selectors.json`. `triage-comparison.py` mechanically compares both result trees. Use a new evidence label while reusing the helper cache and existing simulator. Never overwrite retained result bundles or bypass the 50 GiB pre-build floor.

For a bounded follow-up, use the workspace helper with the exact test identifier from the matrix and the same device. Recheck current upstream before changing implementation. Native source is unchanged by this documentation commit, so the earlier passing joint-specific/unit evidence remains associated with app revision `00bc55e`.

**Release disposition:** keep PR #702 draft and v2 creation disabled. Complete the follow-ups and the separate live-backend, legacy-client, accessibility and operational gates in [implementation-validation.md](implementation-validation.md) before enablement. Historical check-ins and discussions remain unchanged; this triage performs no migration or deployment.
