# Native verification and restart

## Current evidence — September 18, Map → live Feed revision

Branch `codex/rec-529-nux-playthrough`, worktree `/private/tmp/wander-pr663`.
PR #663 remains a design-review draft; reconcile newer main before production merge.

- XcodeGen and Simulator compilation passed on Xcode 26.6 / iOS 26.5.
- The complete unit target passed **2,055 / 2,055 tests**, including its existing
  performance gates. No clean-baseline performance comparison is claimed.
- The final **38 walkthrough tests passed**, including Map → Feed routing,
  retired quote checkpoint migration, complete-card geometry, two Add beats,
  repeated Add activation, account-scoped consumption and no later scheduled NUX.
- Four affected UI scenarios passed across focused runs: the complete Map tour
  followed by both Feed Next buttons; automatic rings → Feed completion; Feed
  centering, return to top and no repeat; and both first-Add annotations followed
  by reopening without a repeat or forced save.
- The initial Feed UI run caught an inactive-at-mount lifecycle issue that
  consumed the lesson early. It was fixed and the automatic Feed and rings
  tests both passed on rerun. The final focused run also passed after preserving
  an active Add beat across repeated sheet activation.
- The full unit run preceded those final localized corrections; the final
  walkthrough tests and affected Feed UI checks cover them. **No complete UI
  suite or physical-device pass is claimed.** Full integration tests, device
  VoiceOver/Reduce Motion acceptance and newer-main reconciliation remain merge
  gates. The retired Lists UI check was updated but not run in this revision.

Held native blur scenes can cause XCTest to wait for its 60-second animation
idle timeout. The automatic Feed sequence passed in ordinary playback; the
held Next test's longer wall time is test synchronization, not tutorial length.
The nominal Feed flow is 5.6 seconds, with short bounded waits for real targets.
A missing people/activity target is skipped; no example card is substituted.

## Visual evidence

Current iPhone 17 Pro and smaller iPhone 17e use iOS 26.5. The repository's
usual iPhone 16 Plus / iOS 18.6 runtime is not installed on this machine.
The current local package is
`/Users/ryanlieblein/Developer/wander/outputs/pr663-native-nux/`:

- `REVIEW.md`: current scenes first; previous revisions explicitly historical.
- `revision-4/videos/map-to-feed-light.mp4`: continuous Map tour, rings → Feed,
  people focus, complete latest-card focus, clear and return to Feed top.
- `revision-4/videos/add-search-import-light.mp4`: both first-+ annotations.
- `revision-4/videos/place-wanna-light.mp4`: revised Wanna copy with the retained
  3.5-second focus and 1.4-second diagonal glimmer.
- `revision-4/screens/`: whole latest card in light/dark and on the smaller
  phone, both Add annotations, and profile Wanna copy.

These are recordings of the real SwiftUI views with explicit local test
fixtures. Production reads the current account's Feed page. Capture fixtures
are DEBUG-only; no live account activity was created. Only launch wait and idle
ends were trimmed, with no synthesized or accelerated transitions. Media stays
outside Git. Simulator recording is not a physical-device performance benchmark.

## Validation commands and results

Use a new result-bundle path for each run. The dedicated smaller simulator is
`0D221A8D-45A5-4A87-840C-6B52E5DA22B9`; the review simulator is
`21F0051B-9DD1-42C7-ADC1-26D4E694BC05`. Choose an installed equivalent elsewhere.

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
  -only-testing:WanderUITests/OnboardingUITests/testMapRingsAutomaticallyContinueIntoFeedAndFinishAtTop \
  -only-testing:WanderUITests/OnboardingUITests/testFeedIntroductionCentersWholeLatestTileThenReturnsToTopWithoutRepeating \
  -only-testing:WanderUITests/OnboardingUITests/testPlusRemainsVoluntaryAndDoesNotStartForcedSave
```

Use `-only-testing:WanderTests` for the complete unit target. Remove all
`-only-testing` arguments for the complete integration gate after reconciling
main. Keep existing performance thresholds.

Result bundles:

- `/private/tmp/pr663-r4-main-tests.xcresult`: 2,055 passing unit tests, passing
  Add/rings UI scenarios, and the initial Feed lifecycle failure.
- `/private/tmp/pr663-r4-lifecycle-tests.xcresult`: 38 passing walkthrough tests
  plus passing automatic Feed and rings UI scenarios after the lifecycle fix.
- `/private/tmp/pr663-r4-next-tests.xcresult`: final 38 passing walkthrough tests
  and the complete held Map → both Feed Next controls → top scenario.

## Replay the native review

Install `/private/tmp/pr663-build/Build/Products/Debug-iphonesimulator/Wander.app`
on a review simulator. Common local-fixture arguments:

```text
-WanderAuthenticatedUITest -WanderMapCapture -WanderUseDemoFixtures
-WanderEnableWalkthroughs -WanderResetWalkthroughs
```

Add the relevant arguments:

- Full Map → Feed: `-WanderNUXFeedFixture -WanderWalkthroughTarget mapFeatured`.
- Feed only: `-WanderNUXFeedFixture -WanderWalkthroughTarget feedActivity`.
- First +: `-WanderOpenAdd -WanderWalkthroughTarget addNearby`.
- Profile: `-WanderPlaceProfileSaveTrayV1 -WanderWalkthroughTarget placeSaveActions
  -WanderMapPlace 'Bar Nido' -WanderMapSheetExpanded`.

For a still, add `-WanderHoldWalkthroughStep`. Feed's recent-card still also
needs `-WanderNUXFeedRecent`. Add's second-beat still uses target `addImport`.
The profile hold has no Next/Skip and leaves the real floating actions usable.

Optional `-WanderNUXReview` exposes native playback and scene menus. No quote
scene or Lists scene remains. Starter lists remain deferred. The next production
step is to reconcile main and run the complete integration/device acceptance
on that candidate; do not merge or upload TestFlight as part of this revision.
