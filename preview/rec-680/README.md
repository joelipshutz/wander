# REC-680 — actual app review routes

The mockups now run inside the **Wander app target**, using its existing screens
and components. The previous standalone app is superseded. The explicit
`-WanderQuickCaptureReview` route only resolves in Debug simulator builds.
Fixtures, auth, analytics and save callbacks are isolated; no real account is used.

## Build and capture

Run from the repository root with a dedicated, booted simulator:

```sh
bash preview/rec-680/render-build.sh <simulator-uuid> <derived-data-path> <optional-package-cache>
python3 preview/rec-680/capture.py <simulator-uuid> <capture-root>/large
python3 preview/rec-680/capture.py <small-simulator-uuid> <capture-root>/compact --only quick,details,history,reminders,wanna
swift preview/rec-680/compose.swift <capture-root> <board-output>
```

Install the same built app on both devices before capture. Do not reuse another
active task's simulator. Raw captures belong outside individual worktrees.
`capture.py --only quick,details --delay 12` supports focused reruns.

## Routes

| Area | Route |
|---|---|
| Existing UI comparison | `baselineMap`, `baselineEditor` |
| Compact and full capture | `quick`, `past`, `details`, `options` |
| Wanna | `wanna`, `wannaDetails` |
| Return | `saved`, `invitation`, `history`, `placeHistory`, `edit` |
| Existing notification settings | `reminders` |

Manual launch:

```sh
xcrun simctl launch <simulator-uuid> com.grayline.wander \
  -WanderQuickCaptureReview quick -WanderAuthenticatedUITest \
  -WanderUseDemoFixtures -WanderDisableWalkthroughs -WanderUnifiedLiveUITest
```

The compact sheet expands the **same real editor**. The rating's neutral thumb
is not a value: untouched saves submit nil; a deliberate midpoint tap counts;
Remove rating restores nil. Existing explicit ratings are preserved on edit.
The review save callback updates the sample visit only. Production create/edit,
remote sync, durable drafts and notification scheduling are not implemented.

Profile Activity and the place's Check-in history are existing app screens.
The added ticket action and contextual invitation open the exact sample visit.
Reminder copy appears within the actual Notifications sheet; it is not a
screenshot of an OS push notification, and no push is sent or scheduled.

Focused interaction coverage is in `WanderUITests/QuickCaptureReviewUITests.swift`.
Run it on a dedicated simulator with the same build/package paths:

```sh
xcodebuild test -project Wander.xcodeproj -scheme Wander -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-uuid>' \
  -derivedDataPath <derived-data-path> \
  -only-testing:WanderUITests/QuickCaptureReviewUITests \
  -only-testing:WanderTests/PlaceRatingReactionTests \
  -only-testing:WanderTests/PlaceRatingSummariesTests \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

Final validation and visual boards: [proposal](../../docs/designs/rec-680-quick-capture.md).
