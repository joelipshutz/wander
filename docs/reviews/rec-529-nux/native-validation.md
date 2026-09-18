# Native verification and restart

## Current evidence — September 17–18, 2026

The native review builds on `codex/rec-529-nux-playthrough` in
`/private/tmp/wander-pr663`. Xcode's Branch Chooser was verified on that branch.
This is a draft design review, not a production release gate.

- `xcodegen generate` and Simulator build-for-testing passed.
- The complete unit target ran: **2,048 of 2,050 tests passed**. The two failures
  were performance budgets: trusted search p95 **82.81 ms** against **50 ms**,
  and the high-data fixture **0.898 s** against **0.750 s**. Neither threshold
  was relaxed. A clean baseline comparison has not been established, so these
  are unresolved validation failures, not claimed unrelated failures.
- After the last coordinator change, **34 walkthrough unit tests passed**,
  including the regression for a late callback skipping a later beat.
- All **ten focused NUX UI checks passed across the verification runs**: the
  native tour, automatic return to Map, immediate You-filter takeover,
  voluntary Plus, Feed and Lists dismissal, real Check In editor, retired N26,
  and real More scroll/Next checks passed across focused runs. The existing
  More sections/reset test also passed after the selection-handler change.
- The final More-selection regression rerun **passed**. It verifies dismissal,
  the selected-filter count, and the actual selected category after reopening
  the native panel. SwiftUI repeats the chip's accessibility value on this OS,
  so selection is verified directly rather than by exact combined AX text.
- The broad run reached the full unit target, then was stopped during unrelated
  UI coverage to rebuild native inspection fixes. **The complete UI suite has
  not finished; no full-suite pass is claimed.**

Only iOS **26.5** was installed here. The repository's iPhone 16 Plus / iOS 18.6
command could not be used. Dedicated iPhone 17 Pro and smaller iPhone 17e devices
were used, without changing other tasks' devices. Native light/dark captures,
compact captures, and a large-text C04 spot check are available. Full physical
VoiceOver/Reduce Motion and device-feature acceptance remain open.

## Review media

The local package is
`/Users/ryanlieblein/Developer/wander/outputs/pr663-native-nux/`:

- `REVIEW.md`: scene-by-scene capture index and review choices.
- `videos/map-tour-automatic-dark.mp4`: complete automatic pop tour with the
  six-second connection ending, then usable Map.
- `videos/map-tour-slide-light-original.mp4`: complete slide tour with the
  four-second original quote, then usable Map.
- `videos/place-action-light.mp4`: stationary handwritten hint through the
  actual Check In action into the native editor.
- `screens/`: M01–M06, N25 and C01–C04 captures on the review devices.

These are recordings of the running SwiftUI app using local fixtures. Only
launch wait and idle tail were trimmed. Simulator timing is not a physical
performance benchmark. Some compact XCTest shots capture a coach entering or
MapKit tiles loading; settled stills are identified in the capture index.
Feed uses the available fixture groups and retains native loading states.
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
  -only-testing:WanderUITests/OnboardingUITests/testListsHintEndsOnListsWithoutStartingAnotherTour \
  -only-testing:WanderUITests/OnboardingUITests/testNativeCheckInWannaAnnotationLeavesActionsUsable \
  -only-testing:WanderUITests/OnboardingUITests/testRetiredImportLaunchArgumentDoesNotPresentN26
```

To run the complete unit target, use `-only-testing:WanderTests`. For the full
project gate, remove all `-only-testing` arguments. Before production merge,
reconcile latest `origin/main`, rerun the complete gate, and resolve the two
performance failures or establish and document their cause.

Local evidence bundles: `/private/tmp/pr663-verified-tests.xcresult` (complete
unit target and first UI run), `/private/tmp/pr663-final-ui.xcresult` (eight
passing NUX checks), `/private/tmp/pr663-interaction-fixes.xcresult` (34 units,
full Map tour and More sections/reset), and
`/private/tmp/pr663-more-selection.xcresult` (final selection check).
Earlier failures are retained; screenshots alone are not treated as test passes.

## Launch the native review

Install `/private/tmp/pr663-build/Build/Products/Debug-iphonesimulator/Wander.app`
on the review device, then launch with:

```text
-WanderAuthenticatedUITest -WanderMapCapture -WanderUseDemoFixtures
-WanderEnableWalkthroughs -WanderResetWalkthroughs
-WanderPlaceProfileSaveTrayV1 -WanderNUXReview -WanderNUXFeedReveal
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

`-WanderNUXSlide` forces the alternate coach motion.
`-WanderNUXOriginalFinale` forces the original quote;
`-WanderNUXFinaleFourSeconds` forces four seconds.
`-WanderDisableFeedReveal` disables the Feed experiment. Leave these forcing
arguments out when comparing choices through the native Playback menu.

Next review action: choose motion/finale/Feed treatment from the native captures.
Starter-list contents and ownership, N27 device motion demonstrations, and
N28/N29 notification policy remain explicit follow-ups described in the brief.
