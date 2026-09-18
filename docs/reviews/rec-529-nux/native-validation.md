# Native verification and restart

Run from the checkout. On Joe's Mac, use the workspace helper; it reserves three machine-wide slots, supplies the shared cache and compiler/test limits, and waits when busy. Do not start a duplicate job or interfere with another task's simulator. Pick the existing device appropriate to the machine; Joe's current iPhone 17 Pro is `FD6770B4-AF24-4435-BD3F-301C706D51E2`.

```sh
python3 '../.tools/ios-work.py' build -- \
  -project Wander.xcodeproj -scheme Wander -configuration Debug \
  -destination 'platform=iOS Simulator,id=FD6770B4-AF24-4435-BD3F-301C706D51E2' \
  CODE_SIGNING_ALLOWED=NO GENERATE_INFOPLIST_FILE=YES test \
  -only-testing:WanderTests/FirstVisitWalkthroughTests \
  -only-testing:WanderTests/OnboardingIdentitySubmissionTests \
  -only-testing:WanderTests/OnboardingStateTests \
  -only-testing:WanderUITests/OnboardingUITests/testNativeMapOverviewUsesRealControlsAndEndsWithoutSaving \
  -only-testing:WanderUITests/OnboardingUITests/testNativeFinaleAutomaticallyReturnsToUsableMap \
  -only-testing:WanderUITests/OnboardingUITests/testRealMapFilterActionCanExitOverviewImmediately \
  -only-testing:WanderUITests/OnboardingUITests/testPlusRemainsVoluntaryAndDoesNotStartForcedSave \
  -only-testing:WanderUITests/OnboardingUITests/testFeedHintEndsOnFeedWithoutOpeningDiscoverOrInvites \
  -only-testing:WanderUITests/OnboardingUITests/testListsHintEndsOnListsWithoutStartingAnotherTour \
  -only-testing:WanderUITests/OnboardingUITests/testNativeCheckInWannaAnnotationLeavesActionsUsable \
  -only-testing:WanderUITests/OnboardingUITests/testRetiredImportLaunchArgumentDoesNotPresentN26
```

The latest queued command used the same selection and `-resultBundlePath '../onboarding-copy-review/session-2026-09-16/nux-native/verified-tests.xcresult'`; it was cancelled before admission. Choose an unused result-bundle path for a new run. Do not overwrite the earlier failure evidence.

After a successful build, install the helper cache's `Build/Products/Debug-iphonesimulator/Wander.app` onto the existing simulator. Launch arguments for the native review:

```text
-WanderAuthenticatedUITest -WanderMapCapture -WanderUseDemoFixtures
-WanderEnableWalkthroughs -WanderResetWalkthroughs
-WanderPlaceProfileSaveTrayV1 -WanderNUXReview
```

The review uses local fixtures and no live backend. Open **Scenes** to choose a lesson. For a deterministic still, add `-WanderHoldWalkthroughStep -WanderWalkthroughTarget TARGET`. Targets: `mapFeatured`, `mapFriends`, `mapMoreFilters`, `mapSearch`, `mapAdd`, `mapPinLegend`, `mapSendoff`, `addNearby`, `feedActivity`, `listsScope`, `placeSaveActions`.

`-WanderNUXSlide` forces the alternate coach motion. `-WanderNUXOriginalFinale` forces the original quote; `-WanderNUXFinaleFourSeconds` forces four seconds. The latest Scenes menu offers the corresponding choices, plus manual playback, but that menu still needs verification. Settings apply on replay. `-WanderDisableFeedReveal` disables the Feed experiment.
