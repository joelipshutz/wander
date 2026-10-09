# Astir Live review prototype

An isolated native SwiftUI review app for iOS 17 and later. Its bundle identifier is `com.grayline.astirlivereview`. It has no package dependencies and does not modify, link to, or connect with the production Wander app.

## Opening the prototype

From this directory, run `xcodegen generate`, then open `AstirLiveReview.xcodeproj`. Select the `AstirLiveReview` scheme and an iPhone simulator. The project disables signing for review builds; installing it on a physical device requires the owner to configure a signing team and enable signing separately.

This revision preserves Profile continuity and includes standalone UI capture tests. The native app builds cleanly with Swift 6 and an iOS 17 deployment target; all 40 deterministic model checks pass. All 16 UI cases have passed on each simulator size across the full run and focused reruns. See the [validation record](../../docs/designs/astir-live/review/validation.md) for final simulator results, reviewed captures, and the distinction between prototype validation and production gates.

```sh
xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library -swift-version 6 \
  -target arm64-apple-ios17.0-simulator \
  -sdk /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator26.5.sdk \
  -module-cache-path /private/tmp/rec636-swift-module-cache Sources/*.swift
```

The model checks use only the shared model and local fixtures; they do not start the SwiftUI app or a simulator:

```sh
xcrun --sdk macosx swiftc -parse-as-library -swift-version 6 \
  -target arm64-apple-macos14.0 \
  -module-cache-path /private/tmp/rec636-swift-module-cache-macos \
  Sources/ReviewModel.swift Checks/ModelChecks.swift -o /private/tmp/rec636-model-checks
/private/tmp/rec636-model-checks
```

Checks cover Following/Nearby visibility, rolling windows, shared search/kind filtering, draft preview isolation, Profile/Your Map continuity, selective one-place exploration and restoration including geography and camera, geographic circle membership, owner place deduplication/history, future plan labels, deterministic launch state, and sparse/empty/offline scenarios. These are model checks, not a replacement for native UI or production app tests.

## Review journeys

- **Live:** The actual MapKit map and activity drawer share `ReviewStore.filtered`. The drawer has map peek, map + activity, and full activity positions. Drag its header, use the accessible arrow menu, or swipe upward on half-height activity to expand. Full-height content scrolls normally; a deliberate downward pull begun at the content top returns to half. Within Live, bottom tabs hide only at map peek. Full activity has a floating Map button. Recent memories precede upcoming plans and Events. The optional transition appears after the first recent memory.
- **Scopes:** Following includes the viewer and followed people and defaults to the past seven days. Nearby keeps that same trusted-person visibility and is explicitly centered on the sample Ocean Park neighborhood, within 5 km; Filters offers deliberate expansion to 15 km or 25 km. Your places defaults to all time and shows unique places using the newest matching owner memory; detail retains the owner's full local place history. Activity kind, time, text, and circle filters apply to both map and activity. Filter edits are staged until Show memories; Cancel or interactive dismissal discards them.
- **Area:** Choose Draw area, drag on the actual map to define a circle, then Apply. Coordinates come from `MapProxy.convert`; radius is geodesic distance between the converted start and end points, clamped to 100 m–25 km. Accessible 500 m, 1 km, and 2.5 km alternatives use the current map center. Cancel retains the applied area. Clear removes it. Pan the map before drawing to choose a different center.
- **People first:** Activity opens with the person and their place memory. A Wanna opens Make a plan. A reply retains its person/place context in a clearly labeled local demo inbox.
- **Add:** The coral header plus opens a Been/Wanna composer with sample place selection and a note. Saves create local owner activities. The bottom bar has only Live, Lists, and Profile.
- **Events:** Astir gatherings in Live opens a coming-soon concept with optional local demo interest. It is explicitly not a real event or RSVP.
- **Profile continuity:** Identity/social → owner save streak → recent activity → Your Map preview/Explore → calendar. Explore opens Your Map within Profile, with a Map/Patterns bottom switch and the global tabs hidden, matching its existing subdestination structure. This is a faithful structural representation using fictional data, not a proposal to redesign Profile. Snapshot/status filtering, place detail, map panning, and an explanatory Share affordance are represented; existing production map filters and lenses are not removed.
- **Selective Live exploration:** Only a selected owner place detail offers “Explore this place in Live,” explicitly labeled a review idea. This narrows Live to that place and supplies Back to Profile; returning restores the earlier Live filters, camera, viewport, radius, and drawer and reopens the prior Profile destination. The full Your Map and Patterns are not relocated to Live.
- **Lists:** Sample saved collections open the same activity detail. Collection selection persists across tab changes.
- **Returning users:** The optional “Your Feed now has a map” card says Your Map stays in Profile and has Show me and Not now. Dismissal persists using app-local UserDefaults. Review options can show it again.
- **Scenarios:** The top-right Review options menu switches between a busy week, a quiet week, no activity yet, and simulated offline saved activity. It also opens the demo inbox and the prototype guide.

Launch arguments: `--ui-testing` (suppresses persisted transition state without writing preferences), `--scenario-sparse`, `--scenario-empty`, `--scenario-offline`, `--show-transition`, `--hide-transition`, `--feed`, `--map`, `--profile`, `--lists`, `--your-map`, `--patterns`, `--fixture-wanna`, `--fixture-reply`, `--fixture-plan`, `--fixture-draw`, `--large-text` (accessibility size 2), `--reduce-motion`, `--light`, and `--dark`. Appearance arguments remain within the adaptive editorial scheme. With no arguments, the app starts at map + activity, Following, past seven days.

## Data and simulation boundaries

All people, handles, relationships, places, notes, histories, and coordinates are fictional fixture data around the real Ocean Park map. Apple MapKit supplies the geographic basemap and may request map tiles when the app runs. No location permission, current-location lookup, contact access, photos, authentication, analytics, social APIs, or Astir backend services are used.

Plans, check-ins, Wannas, replies, and event interest only mutate in-memory state for the current app session. No invitations, replies, or notifications are sent. Switching tabs and map/feed modes preserves filters, query, camera, collections, and local interactions. App restart clears session changes. Only transition-card dismissal persists.

Offline is a review scenario showing the local fixtures; it does not disable device networking or guarantee basemap availability offline. Empty activity still allows creation, and newly created owner activities are found under Your places.

## Intentional prototype limits

- No production auth, RLS/visibility enforcement, block/follow behavior, cache/sync, durable plans/messages, notifications, place search, or real social delivery.
- Upcoming plans are visually separated from recent activity and display their planned timing, but use illustrative schedules rather than a complete date/time-zone/expiry model. Time-window filtering measures fixture activity age.
- A fictional non-followed fixture is included only to verify exclusion from Following and Nearby; it does not appear in those projections. Choosing a different city is not implemented.
- Area filtering is a geographic circle. Polygon/freehand geometry, saved-area lists, server spatial queries, pin clustering, and conflict handling are not implemented. Pins at the same coordinates can overlap.
- Lists are sample collections only. Create/edit/delete list and save-area-as-list owner actions are not implemented.
- Patterns is illustrative copy, not computed analytics, and remains associated with Your Map. The drawer supports an initial vertical swipe handoff as well as handle/menu/button controls. The gesture thresholds, top-of-scroll collapse, keyboard behavior, and changes during an active drag need native device verification; this is not a claim of production-grade nested-scroll physics. Header scroll-direction hiding and performance tuning remain out of scope.
- Light/dark adaptive colors, Dynamic Type fonts, scrollable surfaces, labeled controls, 44-point button targets, button alternatives to dragging, and Reduce Motion-aware drawer transitions are included. Large text, keyboard, light/dark and small-device layouts have simulator evidence in the validation record. Spoken VoiceOver, system Reduce Motion and real-device gesture behavior remain hands-on implementation gates. The map basemap remains an Apple-provided surface.
- No approved production icon, splash artwork, or identity assets have been copied into this prototype.

## Source map

- `Sources/ReviewModel.swift`: fictional fixtures, shared filtering, session state and simulated mutations.
- `Sources/Design.swift`: adaptive Astir colors, editorial/body fonts, common components.
- `Sources/AstirLiveReviewApp.swift`: isolated app entry, navigation, presentation.
- `Sources/LiveView.swift`: MapKit map, geographic drawing, persistent drawer, activity.
- `Sources/SecondaryViews.swift`: filters, detail, plan/reply/add composers, demo inbox and guide.
- `Sources/ProfileAndLists.swift`: familiar Profile structure, its Your Map/Patterns subdestination, and sample Lists.
- `project.yml`: standalone app and UI-testing targets.
- `Checks/ModelChecks.swift`: deterministic shared-state regression checks, excluded from the app target.


## Standalone simulator capture and interaction tests

The `AstirLiveReviewUITests` target depends only on this standalone app. Run `xcodegen generate` after updating `project.yml`. Run from this directory. Choose fresh result-bundle paths if a previous bundle already exists.

```sh
xcodebuild test -project AstirLiveReview.xcodeproj -scheme AstirLiveReview \
  -destination 'platform=iOS Simulator,id=21FFD105-FF94-44D6-82F0-2DF1DF4A6724' \
  -derivedDataPath /private/tmp/rec636-review-derived \
  -resultBundlePath /private/tmp/rec636-review-large.xcresult \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:AstirLiveReviewUITests

xcodebuild test -project AstirLiveReview.xcodeproj -scheme AstirLiveReview \
  -destination 'platform=iOS Simulator,id=6B09D343-A62A-49CE-9F44-81754B6DBE5F' \
  -derivedDataPath /private/tmp/rec636-review-derived \
  -resultBundlePath /private/tmp/rec636-review-compact.xcresult \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:AstirLiveReviewUITests
```

These review devices are iPhone 17 Pro (large) and iPhone SE 3 (compact), on iOS 26.5. Every test is under `AstirLiveReviewUITests/AstirLiveReviewUITests`. Add `/<testName>` to `-only-testing:` for a focused rerun.

Capture tests attach whole-screen PNG screenshots including status-bar and safe-area context:

- `testCaptureLiveHalf`
- `testCaptureLiveFeed`
- `testCaptureProfileContinuity` (top plus Your Map/calendar)
- `testCaptureYourMapAndPatterns`
- `testCaptureTransition`
- `testCaptureOfflineAndEmpty`
- `testCaptureAccessibleText`
- `testCaptureDarkPeekAndDrawingWithReducedMotion`
- `testCaptureSparseActivity`

Interaction tests:

- `testDrawerScrollAndMapReturn`
- `testProfileYourMapAndPatternsRemainTogether`
- `testSelectivePlaceExplorationReturnsToYourMap`
- `testFiltersCancelAndApply`
- `testWannaPlanCreation`
- `testContextualReplyStaysLocal`
- `testGeographicPresetApplies`

The tests exercise local fixtures and simulated writes only. MapKit may fetch public basemap tiles during app execution. Screenshot attachment is evidence capture, not automated visual approval; inspect the large and compact images for safe areas, text wrapping, touch targets, state continuity, and top/bottom occlusion. Accessibility screenshots complement, rather than replace, VoiceOver and real Dynamic Type interaction checks.
