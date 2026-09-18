# Native verification and restart

## Current evidence — September 17–18, 2026

The native review builds on `codex/rec-529-nux-playthrough` in
`/private/tmp/wander-pr663`. Xcode's Branch Chooser was verified on that branch.
This is a draft design review, not a production release gate.

- `xcodegen generate` and the revised Simulator build passed.
- The complete unit target ran: **2,050 of 2,052 tests passed**. The two existing
  performance gates remain failed: trusted search p95 **53.45 ms** against
  **50 ms**, and the high-data fixture **0.834 s** against **0.750 s**. No
  threshold was relaxed and no clean baseline comparison is claimed.
- **35 walkthrough unit tests passed**, including account-scoped one-time
  consumption after the new profile introduction and the selected five-second
  original-quote finale.
- All **seven revised focused UI checks passed across runs**: real Check In
  during focus, automatic focus completion without repeat on reopening, full/
  automatic Map tour, More selection/scroll, and Feed dismissal. The final run
  passed all three repeat-visit and More checks. The first repeat-visit test
  incorrectly expected the Map-hosted editor to close into the full profile;
  it now follows the actual compact-card return and reopens that profile before
  verifying the lesson stays consumed.
- The earlier review's ten NUX checks passed across focused runs. These results
  do not replace the remaining broad UI gate. **No complete UI-suite pass is
  claimed.**

Only iOS **26.5** was installed here. The repository's iPhone 16 Plus / iOS 18.6
command could not be used. Dedicated iPhone 17 Pro and smaller iPhone 17e devices
were used, without changing other tasks' devices. Native light/dark captures,
compact captures, and a large-text C04 spot check are available. Full physical
VoiceOver/Reduce Motion and device-feature acceptance remain open.

## Review media

The local package is
`/Users/ryanlieblein/Developer/wander/outputs/pr663-native-nux/`:

- `REVIEW.md`: scene-by-scene capture index and review choices.
- `revision-2/videos/map-tour-approved.mp4`: selected slide/fade Map tour,
  dropdown-only More trim and five-second original quote with Enjoy.
- `revision-2/videos/place-focus-glimmer-light.mp4`: real profile arrival,
  three-second moderate blur with static annotations, one diagonal sweep across
  both sharp floating controls, then normal profile.
- `revision-2/videos/optional-feed-reveal.mp4`: the optional reveal through
  available fixture activity, return to the top, explanation and usable Feed.
- `revision-2/screens/`: light/dark profile focus and current/compact native stills.
  The earlier videos/stills remain as explicitly superseded review history.

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
  -only-testing:WanderUITests/OnboardingUITests/testPlaceIntroductionAutomaticallyFinishesAndDoesNotReturnAfterEditor \
  -only-testing:WanderUITests/OnboardingUITests/testRetiredImportLaunchArgumentDoesNotPresentN26
```

To run the complete unit target, use `-only-testing:WanderTests`. For the full
project gate, remove all `-only-testing` arguments. Before production merge,
reconcile latest `origin/main`, rerun the complete gate, and resolve the two
performance failures or establish and document their cause.

Latest evidence: `/private/tmp/pr663-r2-tests.xcresult` (complete unit target and
seven revised UI checks) and `/private/tmp/pr663-r2-final-ui.xcresult` (final
More trim and repeat-visit checks). Earlier evidence remains in the
`/private/tmp/pr663-*-tests.xcresult` and `pr663-final-ui.xcresult` bundles.
Earlier failure attachments are retained; screenshots alone are not test passes.

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

Slide/fade, the original quote and five seconds are now the defaults. Old motion,
quote and duration forcing arguments no longer change them. The Playback menu
retains manual advancement for inspection. C04 has no Next/Skip; hold mode is
only for deterministic capture, and the real floating actions still work.

For a clean C04 recording without review controls, use the fixture launch args,
`-WanderWalkthroughTarget placeSaveActions -WanderMapPlace 'Bar Nido'
-WanderMapSheetExpanded`; omit `-WanderNUXReview` and the hold argument.
For the optional Feed reveal, use `-WanderNUXFeedReveal
-WanderWalkthroughTarget feedActivity` without hold. `-WanderDisableFeedReveal`
disables that experiment.

Next review action: inspect the revised focus/glimmer and optional Feed recording.
Starter lists will be entered later. N27 device motion and N28/N29 notification
policy remain separate follow-ups described in the brief.
