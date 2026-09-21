# REC-576 / REC-570 validation

Implementation candidate for [REC-576](https://linear.app/recme/issue/REC-576)
and [REC-570](https://linear.app/recme/issue/REC-570), based on main `d6dd423`.
**Draft: compact-phone automated checks passed. Exact-route reproduction and
two-device before/after acceptance remain open for the consolidated profile task.**

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

All captures in the table above are **before implementation**, including its
file named `after-photo-dismissal`. Native manual
scroll attempts did not establish a reproducible history cutoff; this is not
evidence of a confirmed scroll defect. The exact Your Map photo entry point
still needs reproduction, especially because REC-575 separately tracks its
untappable place card.

## Candidate photo evidence

The tested app source is `a24c0c7`; subsequent edits only correct the test
harness and record validation. Native iPhone 16e captures use the same fictional
fixture in Light appearance:

- [Place before opening the photo](evidence/after/iphone-16e-light-place-profile.png)
- [Photo viewer with readable attribution](evidence/after/iphone-16e-light-photo-viewer.png)
- [Same light place after dismissal](evidence/after/iphone-16e-after-photo-dismissal.png)
- [Opening and dismissal recording](evidence/after/iphone-16e-photo-transition.mp4)

These verify the shared place gallery's steady appearance and readable controls.
Exact Your Map entry-point and current-phone comparisons still belong to the
consolidated profile task. The original baseline cutoff was not established;
REC-570's candidate now passes both runtime viewport assertions, but should not
be treated as a proven before/after fix for every route yet.

## Validation

- App, unit-test target and UI-test target compiled successfully on the branch.
- **2,356 unit tests passed, zero failures** (31.231 seconds).
- **Four focused UI tests passed, zero failures:** history viewport and final row
  without floating actions; Feed place profile with floating actions; repeated
  photo opening/dismissal in Light and Dark, including a system appearance
  change while the viewer is open.
- The first UI run exposed an invalid test assumption: a static heading is not
  a tappable accessibility target. The corrected test checks the photo and Back
  controls, while still checking rendered title pixels for appearance. Both
  corrected photo tests passed all three cycles.
- Xcode stalled in result finalization after the test runners completed. Passing
  results are established by the [test-log excerpts](test-results.txt); both
  completed runs had to be interrupted during finalization. There is no valid
  finalized `.xcresult` or successful CLI exit to claim. Logs and the partial bundles are preserved outside the repository
  at `../rec-576-570-validation/`. The first failed harness run is also retained.
- XcodeGen, Swift syntax parsing, `git diff --check`, and the PR payload check
  passed. Runtime compilation now supersedes the initial syntax-only evidence.
- The initial 50 GiB storage blocker was cleared after Joe authorized cleanup.
  Roughly 48 GiB was recovered through byte-identical APFS document clones and
  closed compiler caches. Every document remains independently editable;
  archives, dSYMs, final test results, source changes and simulator data were
  preserved. The audit is at `../storage-audit-2026-09-21-rec576/`.
- The full 213-case UI suite and current-phone route checks have not run here.
  They belong on the consolidated profile branch after integration. Steady-state
  pixel checks do not establish the absence of a transient opening flash.

## Test plan

For the remaining broad suite, run from the integrated worktree once at least
50 GiB is free:

```sh
python3 ../.tools/ios-work.py build -- test \
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
  |   + light/dark repeated dismissal: UI test added, passed on compact iPhone
  |   + system appearance change: UI test added, passed on compact iPhone
  |   + opening flash / nested screens: manual video pending
  + comment and avatar photo viewers: manual validation pending
History presentation
  + no floating actions: viewport + last-row UI test passed on compact iPhone
  + floating actions: existing route test strengthened and passed on compact iPhone
  + entry routes / keyboard / both phone sizes: manual validation pending
```

Architecture, code-quality and performance review: no additional changes
identified. Test review: two remaining evidence gaps — finalized result-bundle output
and reproduction/comparison of the exact reported routes on both phone sizes. No new
product decisions or TODO proposals. One sequential implementation lane;
independent nested review skipped because this session runs under Codex.
Review result: automated compact-phone assertions passed; exact-route visual
acceptance and finalized result-bundle evidence remain open.
