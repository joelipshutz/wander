# Native verification

## Candidate

PR #663, branch `codex/rec-529-nux-playthrough`, worktree
`/private/tmp/wander-pr663`. Main at `f3d9cb6e96b775a46a41d593200037385439fad0`
is integrated. The requested outcome is a squash merge; no TestFlight build or
upload is part of this change.

The integration preserves main's September 18 Signal/slide welcome sequence,
Feed presentation callbacks, current place editor, and build 176. The obsolete
split-flap implementation is removed. The branch also retains its earlier native
identity/photo, per-person following, permission-primer and preview work.

## Latest behavior and visual evidence

- Feed holds each annotation for 2.7 seconds, with 6.6 seconds total once real
  targets are ready. It centers the whole latest activity card and returns to
  the top after Next or automatic completion.
- Add waits for nearby loading and a stable measured sheet. It stays unblurred,
  outlines the complete Nearby section through See more, or only the search
  field without location/results, then outlines Import. The two reading windows
  total eight seconds. The lesson does not request location permission.
- First profile retains its 3.5-second moderate focus, revised Wanna copy and
  1.4-second glimmer. Later visits do not repeat the completed hints.

Native screenshots were inspected on iPhone 17 Pro and smaller iPhone 17e,
including dark appearance, complete Nearby/Import bounds, no-location fallback,
and the entire latest Feed card with attribution and engagement actions. The
current local index is
`/Users/ryanlieblein/Developer/wander/outputs/pr663-native-nux/REVIEW.md`.

Revision 5 includes untrimmed native recordings:

- `revision-5/videos/map-to-feed-raw.mp4`
- `revision-5/videos/add-nearby-import-raw.mp4`
- `revision-5/screens/`: final light/dark/compact Feed and Add stills.

The unchanged profile recording remains
`revision-4/videos/place-wanna-light.mp4`. Earlier revisions are historical.
The recordings use explicit DEBUG fixtures in the production SwiftUI views.
Ordinary accounts use their current available Feed; no live account activity
was created for capture. Media remains outside Git. Frame-by-frame playback of
the new MP4s is not claimed; the final stills and native interaction tests are
the inspected evidence.

## Validation

XcodeGen and Simulator build/build-for-testing passed on Xcode 26.6 / iOS 26.5.
The usual iPhone 16 Plus / iOS 18.6 runtime is not installed locally. The analytics
dashboard contract check and its Node tests passed.

The integrated full run passed **2,284 unit tests**. Its UI target reported
155 passing cases, 33 failures and one unsigned App Group skip. The first main
comparison reproduced 12 of 15 broader failures on unchanged main; remaining
comparisons and serial reruns are in progress. Final focused checks passed all
39 walkthrough and 153 navigation contracts. Native Add's whole-section/Import
flow, first-Add Next/reopen/no-repeat, actual Contacts denial/recovery, and the
complete welcome → login → OTP background/restore → identity flow passed across
focused runs. Final totals and the baseline comparison will be recorded in the
PR before merging.

Verification caught and corrected parent accessibility metadata overriding
native Add control identifiers and the welcome benefit copy. More filtering is
checked with a physical tap and resulting selection. Its explanatory text is
checked against the dropdown's visible bounds after a real drag, rather than
requiring reading copy to expose a tappable accessibility point.

No physical-device, VoiceOver or Reduce Motion acceptance is claimed. Those
remain explicit device checks for the next manually requested TestFlight batch.

## Reproduce

Use an installed Simulator equivalent and a fresh result-bundle path:

```sh
cd /private/tmp/wander-pr663
xcodebuild test -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=0D221A8D-45A5-4A87-840C-6B52E5DA22B9' \
  -derivedDataPath /private/tmp/pr663-build \
  -clonedSourcePackagesDirPath /Users/ryanlieblein/Developer/wander/DerivedData-sim/SourcePackages \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -jobs 4
```

For focused regression checks, add `-parallel-testing-enabled NO` and select
`WanderTests/FirstVisitWalkthroughTests`, `WanderTests/NavigationContractTests`,
or the affected cases in `WanderUITests/OnboardingUITests` and
`WanderUITests/NativeOnboardingFlowUITests`.

For native replay, install the built app and launch with
`-WanderAuthenticatedUITest -WanderMapCapture -WanderEnableWalkthroughs
-WanderResetWalkthroughs`, plus:

- Map → Feed: `-WanderUseDemoFixtures -WanderNUXFeedFixture
  -WanderWalkthroughTarget mapFeatured`.
- Feed: the same fixture arguments with target `feedActivity`.
- Add with nearby results: `-WanderUseStorefrontFixtures -WanderOpenAdd
  -WanderWalkthroughTarget addNearby`.
- No-location Add: use `-WanderUseDemoFixtures` instead of Storefront fixtures
  on a review simulator without location permission.
- Place profile: `-WanderUseDemoFixtures -WanderPlaceProfileSaveTrayV1
  -WanderWalkthroughTarget placeSaveActions -WanderMapPlace 'Bar Nido'
  -WanderMapSheetExpanded`.

Add `-WanderHoldWalkthroughStep` for stills. A recent-card still also uses
`-WanderNUXFeedRecent`; Import uses target `addImport`. Held blur scenes can
cause XCTest's animation-idleness wait; automatic-flow tests separately cover
ordinary playback timing. Optional `-WanderNUXReview` exposes the native scene
menu. No quote or Lists scene remains; starter lists are deferred.
