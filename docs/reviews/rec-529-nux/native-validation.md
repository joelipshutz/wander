# Native verification and restart

## Current evidence — September 18, stationary Feed revision

Branch `codex/rec-529-nux-playthrough`, worktree `/private/tmp/wander-pr663`.
The temporary worktree was restored from its pushed commit before this revision.

- XcodeGen and Simulator build passed on Xcode 26.6 / iOS 26.5.
- The complete unit target passed **2,054 / 2,054 tests**, including both prior
  performance gates, without relaxed thresholds. No clean baseline comparison
  is claimed; these results describe this run.
- **37 walkthrough unit tests passed**. New coverage checks the single Feed
  lesson's persisted consumption, 5.65–6-second budget, and missing/offscreen/tall
  card handling. C04 now asserts 3.5-second focus and a 1.4-second glimmer.
- All **four affected UI checks passed**: Feed focus sequence without scrolling,
  Feed departure/re-entry without a repeat, real Check In during held focus,
  and automatic place focus completion with no repeat after reopening.
- The first run found a source-contract assertion tied to the former Feed
  anchor. It was updated to the actual recent-card focus target; the complete
  unit rerun above passed. Visual review rejected an attempted UIKit animation
  cleanup that cleared the blur. The final implementation retains the moderate
  interpolation only while a spotlight is mounted and releases it on removal.
  The final 38 focused unit/contract checks and two-beat Feed UI test passed.
  A cold-launch end-state test initially missed the short first beat before
  XCTest attached; it now checks the usable final state, while the sequence
  test verifies both beats and unchanged scroll position. Its rerun passed.
- Earlier Map and other contextual checks remain recorded in prior commits.
  **No complete UI-suite pass is claimed.** Before production merge, reconcile
  latest main and run the full integration/device gate.

The dedicated current iPhone 17 Pro and smaller iPhone 17e use iOS 26.5. The
repository's iPhone 16 Plus / iOS 18.6 runtime is not installed. Light/dark and
compact captures are reviewed separately; a full physical VoiceOver/Reduce
Motion and device-feature acceptance pass remains open.

## Review media

The local package is
`/Users/ryanlieblein/Developer/wander/outputs/pr663-native-nux/`:

- `REVIEW.md`: scene-by-scene capture index and review choices.
- `revision-3/videos/feed-focus-light.mp4`: stationary people focus, brief clear
  interval, recent activity focus, then normal Feed. The old scroll is removed.
- `revision-3/videos/place-focus-glimmer-light.mp4`: 3.5-second profile focus and
  one 1.4-second diagonal glimmer on each real floating button.
- `revision-3/screens/`: current light/dark and smaller-phone Feed focus stills.
- `revision-2/videos/map-tour-approved.mp4`: unchanged selected Map tour,
  dropdown-only More trim and five-second original quote with Enjoy.
- Earlier Feed scroll and shorter profile captures are explicitly historical.

These are recordings of the running SwiftUI app using local fixtures. Only
launch wait and idle tail were trimmed. Simulator timing is not a physical
performance benchmark. Some compact XCTest shots capture a coach entering or
MapKit tiles loading; settled stills are identified in the capture index.
The explicit Feed review fixture uses the existing local Ryan/Maya profiles in
the real recommendation cards. Ordinary accounts use available real tiles.
Missing/offscreen targets are skipped, with no automatic scrolling or fake activity.
The displayed fixture lists do not define the proposed starter-list policy.
Media stays outside Git to keep the code review small.

## Build and focused validation

Use an unused result bundle path for every run. This machine's dedicated
compact device is `0D221A8D-45A5-4A87-840C-6B52E5DA22B9`; the review device is
`21F0051B-9DD1-42C7-ADC1-26D4E694BC05`. Select an installed equivalent on another
machine. Do not start duplicate jobs or use another task's simulator.

```sh
cd /private/tmp/wander-pr663
xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=0D221A8D-45A5-4A87-840C-6B52E5DA22B9' \
  -derivedDataPath /private/tmp/pr663-build \
  -clonedSourcePackagesDirPath /Users/ryanlieblein/Developer/wander/DerivedData-sim/SourcePackages \
  -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO -jobs 4 -parallel-testing-enabled NO \
  -only-testing:WanderTests/FirstVisitWalkthroughTests \
  -only-testing:WanderUITests/OnboardingUITests/testNativeMapOverviewUsesRealControlsAndEndsWithoutSaving \
  -only-testing:WanderUITests/OnboardingUITests/testNativeFinaleAutomaticallyReturnsToUsableMap \
  -only-testing:WanderUITests/OnboardingUITests/testRealMapFilterActionCanExitOverviewImmediately \
  -only-testing:WanderUITests/OnboardingUITests/testMorePanelScrollReachesExplanationAndNextClosesIt \
  -only-testing:WanderUITests/OnboardingUITests/testMoreFilterInteractionExitsDemoAndKeepsTheChoice \
  -only-testing:WanderUITests/OnboardingUITests/testPlusRemainsVoluntaryAndDoesNotStartForcedSave \
  -only-testing:WanderUITests/OnboardingUITests/testFeedHintEndsOnFeedWithoutOpeningDiscoverOrInvites \
  -only-testing:WanderUITests/OnboardingUITests/testFeedIntroductionFocusesTwoTilesWithoutScrollingAndDoesNotRepeat \
  -only-testing:WanderUITests/OnboardingUITests/testListsHintEndsOnListsWithoutStartingAnotherTour \
  -only-testing:WanderUITests/OnboardingUITests/testNativeCheckInWannaAnnotationLeavesActionsUsable \
  -only-testing:WanderUITests/OnboardingUITests/testPlaceIntroductionAutomaticallyFinishesAndDoesNotReturnAfterEditor \
  -only-testing:WanderUITests/OnboardingUITests/testRetiredImportLaunchArgumentDoesNotPresentN26
```

To run the complete unit target, use `-only-testing:WanderTests`. For the full
project gate, remove all `-only-testing` arguments. Before production merge,
reconcile latest `origin/main` and rerun the complete gate, including the
performance budgets on that integrated candidate.

Latest evidence: `/private/tmp/pr663-r3-final-tests.xcresult` (2,054 unit tests
and four affected UI checks), `/private/tmp/pr663-r3-delivery-tests.xcresult`
(final 38 unit/contract checks and Feed sequence), and
`/private/tmp/pr663-r3-endstate-tests.xcresult` (cold-launch end-state check). `/private/tmp/pr663-r3-tests.xcresult` retains the
initial obsolete source-contract failure; it is not counted as a passing run.

## Launch the native review

Install `/private/tmp/pr663-build/Build/Products/Debug-iphonesimulator/Wander.app`
on the review device, then launch with:

```text
-WanderAuthenticatedUITest -WanderMapCapture -WanderUseDemoFixtures
-WanderEnableWalkthroughs -WanderResetWalkthroughs
-WanderPlaceProfileSaveTrayV1 -WanderNUXReview -WanderNUXFeedFixture
```

This mode uses local fixtures and no live account. The native **Scenes** menu
contains **Playback**, **Map tour**, and **First voluntary visits** submenus.
Choose manual playback for close inspection or replay M01 for the full tour.
Choices apply on replay. C04 opens an existing fixture place and leaves its real
Check In/Wanna controls usable; do not save just to inspect the annotation.

For a deterministic still, add `-WanderHoldWalkthroughStep
-WanderWalkthroughTarget TARGET`. Targets: `mapFeatured`, `mapFriends`,
`mapMoreFilters`, `mapSearch`, `mapAdd`, `mapPinLegend`, `mapSendoff`, `addNearby`,
`feedActivity`, `listsScope`, `placeSaveActions`.

Slide/fade, the original quote and five seconds are now the defaults. Old motion,
quote and duration forcing arguments no longer change them. The Playback menu
retains manual advancement for inspection. C04 has no Next/Skip; hold mode is
only for deterministic capture, and the real floating actions still work.

For a clean C04 recording without review controls, use the fixture launch args,
`-WanderWalkthroughTarget placeSaveActions -WanderMapPlace 'Bar Nido'
-WanderMapSheetExpanded`; omit `-WanderNUXReview` and the hold argument.
For the stationary Feed recording, use `-WanderNUXFeedFixture
-WanderWalkthroughTarget feedActivity` without hold or review controls. For a
still of the second beat, add `-WanderHoldWalkthroughStep -WanderNUXFeedRecent`.
The former Feed-reveal forcing/disable arguments no longer control behavior.

Next review action: inspect the two-stage Feed focus and longer C04 recording.
Starter lists will be entered later. N27 device motion and N28/N29 notification
policy remain separate follow-ups described in the brief.
