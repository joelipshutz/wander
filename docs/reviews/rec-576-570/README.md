# REC-576 / REC-570 validation

Implementation candidate for [REC-576](https://linear.app/recme/issue/REC-576)
and [REC-570](https://linear.app/recme/issue/REC-570), based on main `d6dd423`.
**Draft: neither reported bug is verified fixed.**

## Findings and proposed corrections

- The place gallery, comment-photo viewer, and profile-photo viewer declare
  `preferredColorScheme(.dark)`. That preference operates at the presentation
  boundary. Use a local dark environment instead, so photo chrome does not
  request an appearance change from its presenter. The place gallery also
  uses its own dark Astir palette for attribution text. Contributor-profile
  and report presentations stay outside those local overrides.
- The shared place-profile scroll surface pins its height to an enclosing
  geometry measurement before applying a top safe-area override. Replace the
  fixed frame with a flexible frame; keep the existing bottom safe-area inset
  for floating actions. This addresses a plausible source of the short
  viewport, but runtime reproduction and before/after comparison remain
  necessary to establish REC-570's root cause.
- Inspected the overlapping REC-532 / PR 651 route/save-flow work without
  importing it. Existing routes already share `PlaceProfileFullScreen`.

Apple's [preferredColorScheme documentation](https://developer.apple.com/documentation/SwiftUI/View/preferredColorScheme(_:))
describes its presentation-level scope. The reported transition flash has not
been independently established from the baseline recording.

## Baseline evidence

Captured from the already-installed Astir build 178 (version 1.0.01), iOS 26.3,
iPhone 16e. The installed binary's exact source commit was not established.
The app was launched with fictional REC-386 photo fixtures; this is the shared
place gallery reached from Map, not proof of the precise Your Map entry point.

| Before capture | Observation |
| --- | --- |
| [Light place profile](evidence/before/iphone-16e-light-place-profile.png) | Presenter uses the light palette. |
| [Photo viewer](evidence/before/iphone-16e-light-photo-viewer.png) | Black photo backdrop; contributor name has insufficient contrast against the dark attribution card. |
| [After photo dismissal, baseline](evidence/before/iphone-16e-after-photo-dismissal.png) | Presenter returns to light; a persistent global theme change was not observed. |
| [Baseline transition recording](evidence/before/iphone-16e-photo-transition.mp4) | Preserved for frame-by-frame review of opening and dismissal. |

All captures are **before implementation**, including the file named
`after-photo-dismissal`. There are no after-fix captures yet. Native manual
scroll attempts did not establish a reproducible history cutoff; this is not
evidence of a confirmed scroll defect. The exact Your Map photo entry point
still needs reproduction, especially because REC-575 separately tracks its
untappable place card.

## Validation

- XcodeGen generation passed. Its unrelated target-order-only diff was discarded.
- Swift frontend syntax parsing passed for all five changed Swift files.
  This does not typecheck, build, or execute the application or tests.
- `git diff --check` passed.
- Full test invocation through `ios-work.py` refused before Xcode started:
  **4.7 GiB free; 50 GiB required.** Weekly cleanup preview reported no eligible
  reclaimable storage. No build-limit bypass or arbitrary deletion was attempted.
- Added runtime UI tests for the history viewport/last row with floating actions
  disabled, repeated photo open/dismiss in light and dark, and changing system
  appearance while a photo is open. Strengthened the existing Feed/floating-actions
  test to check that the scroll viewport reaches the action rail.
- These tests have **not run**. Steady-state pixel checks cannot establish the
  absence of a transient opening flash; native transition video is still required.

## Test plan

Once at least 50 GiB is free, run from this worktree:

```sh
python3 ../.tools/ios-work.py build -- xcodebuild test \
  -project Wander.xcodeproj -scheme Wander \
  -destination 'platform=iOS Simulator,id=6CB5D49F-FA87-4D3E-9C2E-F9A1296F257C' \
  CODE_SIGNING_ALLOWED=NO
```

Run the focused `MapPlaceCardUITests` and `FeedPostcardInteractionUITests`
on the current iPhone 17 Pro as well, when it is available; the existing booted
device was not owned by this task and was left untouched. Select the existing
device using `xcrun simctl list devices --json`, then use the same build helper.

| Route / condition | Required evidence |
| --- | --- |
| Profile → Your Map → Explore → source photo | Identify exact entry point; compare baseline and candidate opening/dismissal videos. |
| Shared place gallery in Light, Dark, System | Repeated open/close preserves presenter theme and context; attribution remains readable; switch system theme while covered. |
| Gallery → contributor profile / report sheet → back | Nested presentation follows app appearance and returns to the same photo. |
| Comment-photo viewer and profile avatar viewer | Open/close from light and dark presenters; check controls and transition video. |
| Place history via Map, Feed, Profile and Lists | Full available height, final history row and engagement controls reachable; back navigation works. |
| Place history with floating save tray on and off | No extra bottom strip or clipped actions; final row can clear the rail/home indicator. |
| History → comments keyboard → dismiss | Keyboard and dismissal leave viewport and actions usable. |

Capture matching before/after screenshots and transition videos on current and
compact phones. Validate the new layout assertions against both baseline and
candidate so a no-op change cannot be mistaken for a regression fix. If the
cutoff remains, inspect the exact route's hosting bounds rather than widening
the patch to unrelated save flows. Do not mark the tickets Done before these
checks pass.

## Engineering review

Scope accepted: reuse the three existing viewers and shared place-profile
layout. No new model, backend request, persistence, analytics event, or feature
flag rollout. Local appearance modifiers avoid a new global appearance manager.
No new allocation-heavy work or additional queries in production paths.

What already exists: adaptive Astir palettes, shared full place profile,
floating-action safe-area inset, REC-386 fictional photo fixture, native UI
test screenshot attachments, and the existing Feed save-tray interaction test.

NOT in scope: REC-564–569 and REC-571–575 remain ticket-only; no remote flag
change, shared check-in grouping, map gesture overhaul, merge, or release.

```text
Photo presentation
  + place gallery local dark chrome
  |   + light/dark repeated dismissal: UI test added, execution pending
  |   + system appearance change: UI test added, execution pending
  |   + opening flash / nested screens: manual video pending
  + comment and avatar photo viewers: manual validation pending
History presentation
  + no floating actions: viewport + last-row UI test added, pending
  + floating actions: existing route test strengthened, pending
  + entry routes / keyboard / both phone sizes: manual validation pending
```

Architecture, code-quality and performance review: no additional changes
identified. Test review: two blocking evidence gaps — executable candidate
validation and reproduction/comparison of the exact reported routes. No new
product decisions or TODO proposals. One sequential implementation lane;
independent nested review skipped because this session runs under Codex.
Review result: issues open until the evidence gaps are resolved.
