# REC-529 · Native NUX handoff for Ryan

Joe asked to pause implementation and commit the current work to a PR. This is an unfinished native Swift review, not a release candidate. The pending verification job was cancelled while it was still waiting for a build slot; no work is left running from this task.

Start with the [brief](brief.md), [screen-by-screen plan and archive mapping](screen-plan.md), and the **full [T05](transcripts/T05.txt) / [T04](transcripts/T04.txt) transcripts**. [Wispr provenance](transcripts/README.md) identifies the exact recordings.

## Branch and dependency

- Branch: `codex/rec-529-nux-playthrough`.
- Joe's isolated checkout: `/Users/joelipshutz/Documents/ChatGPT/New project/wander-nux-playthrough`.
- Integration baseline: `92ecb88`, combining main `ab44186` with the saved native onboarding review checkpoint `4ddddfb`.
- Depends on the native onboarding foundation in [PR #648](https://github.com/joelipshutz/wander/pull/648). That task continued independently: its remote head was `2c10e7c` at handoff. This branch does **not** include those later opening-screen changes. Reconcile that dependency before merging; do not overwrite its active checkout.
- The integration preserved main's Apple username-only onboarding behavior and optional Apple photo while retaining the review branch's required identity/resume behavior for other signups. Focused identity and onboarding-state tests passed on the earlier build.

## Implemented here

- M01–M06: native, undimmed Map tour with detached example pins; Featured/Friends change, real More panel expansion/scroll/collapse, Search, Plus and the solid/dotted pin legend. Demo pins never enter the persistent store. A fresh authorized cached location is used when available; Ocean Park is the fallback.
- Top-right Next, automatic readable holds, native pop/slide transitions, and one target emphasis. VoiceOver and Reduce Motion use manual advancement.
- N25: subtle material over the same Map, Skip and Enjoy. Connection copy is a proposal. The latest unverified review controls offer the original quote and four/six-second alternatives.
- C01: handwritten circle/arrow on Nearby Places, not imports. C04: handwritten marks on actual Check In/Wanna controls, not Directions/Website. Both remain stationary and allow real actions, Next or a five-second timeout.
- C02: cancellable native Feed reveal through up to twenty available activity groups, followed by the normal Feed. Latest source keeps this experiment debug-opt-in with `-WanderNUXReview` or `-WanderNUXFeedReveal`; `-WanderDisableFeedReveal` disables it.
- C03: one explanation of sharing recommendations, organizing personal places and keeping imports together.
- Debug Scenes menu: replay/jump to all eleven screens. Latest source adds manual playback, pop/slide, quote and finale timing settings; choose settings, then replay a scene.
- The existing review foundation retires N13–N24 and N26 while preserving the actual app features and contextual enrollment. N27's real device guide remains; device motion demos and the separate N28/N29 permission decision remain open.

## Validation and exact stopping point

**The latest committed source has not been built or tested.** The last successful build was before the final review options, annotation layout adjustments, C04 sample selection, and interaction-test adjustments. A new build/test job was queued and then cancelled at Joe's pause request.

The earlier build passed `build-for-testing` on iPhone 17 Pro, iOS 26.3. Focused results: **87 unit tests passed; 7 of 8 UI tests passed**.

Passed UI coverage: M01–M06 → N25 → usable Map, automatic finale exit, voluntary Plus, Feed and Lists, C04 Next dismissal, and retired N26 suppression. The C04 test now taps the actual Check In action instead of Next; that latest assertion is unverified.

The failing UI test was `OnboardingUITests/testRealMapFilterActionCanExitOverviewImmediately`: the immediate `you.isHittable` assertion failed. The subsequent tap, coach disappearance and selected-filter assertions passed. The latest test waits up to four seconds for hittability; do not assume that resolves the underlying issue until rerun.

The earlier screenshots also showed C01 handwriting crossing the search field, C04 labels too close together, and review chrome near the C04 marks. Latest edits move the C01 note beside its heading, separate C04 labels, move C04 Next below the native toolbar, hide Scenes during that annotation, and use the Bar Nido fixture when available. These changes need visual inspection, especially on compact screens and large text.

No compact-phone, light-mode, final motion comparison, final recording, physical-device, or complete accessibility acceptance pass is claimed. No merge, release, or TestFlight upload was performed.

## Ryan's next actions

1. Read T05 and T04, especially T04's handwritten-annotation section. Keep the product's settled details separate from the open decisions.
2. Reconcile this draft with the latest PR #648 foundation and main before preparing it for merge.
3. Build and run the focused commands in [native-validation.md](native-validation.md). Inspect the You-filter hit test and confirm actual controls stay usable under the overlays.
4. Inspect C01 and C04 on current/compact phones, light/dark and large text. Verify the Feed reveal interrupts and can replay; verify More scroll, automatic/Next transitions and demo cleanup. Fix layout and behavior from actual captures.
5. Capture a continuous native Map playthrough and refreshed per-screen stills. The local review page is scaffolded but is not a completed deliverable.
6. Finish the remaining product review: exact Map order/pace, the N25 quote/action/duration, four location-aware starter Lists (names/content/ownership still undefined), and N27 device demonstrations. N28/N29 are conditional permission requests, not success confirmations; they need a separate decision.

## Local evidence on Joe's machine

Base folder: `/Users/joelipshutz/Documents/ChatGPT/New project/onboarding-copy-review/session-2026-09-16/nux-native/`.

- `native-tests.xcresult`: 87 unit tests and the 7/8 UI result described above.
- `screens/`: eleven native stills from that earlier build, **before the final layout fixes**.
- `attachments/`: exported XCTest screenshots and manifest.
- `index.html`: scaffolded screen-by-screen review; stills are from the earlier build, and `map-tour.mp4` has not been recorded.
- `/tmp/nux-native-build.log`: successful earlier compile; `/tmp/nux-native-tests.log`: earlier test run; `/tmp/nux-verified-tests.log`: cancelled queue, no final test result.

These local evidence paths are not portable GitHub links. The brief, screen mapping, full transcripts and current Swift source are all included in this PR.
