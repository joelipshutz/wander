# Map, Feed, and Lists terracotta add controls

Native SwiftUI approval mockups for REC-460 / REC-452. The render script compiles production color tokens, glass modifiers, icon buttons, segmented controls, and the unchanged place-card action style. Screen layouts contain sample content; these are mockups, not screenshots of the full application.

| Location | Change |
| --- | --- |
| Map search dock | Neon-terracotta `#F05A3C` add button with an ink glyph; a native glass container groups the search field, add button, and nearby recenter control. |
| Feed header | The same terracotta add button; header search and Places/People switch participate in native interactive glass. |
| Lists header | The same terracotta add button; My lists/Shared switch and add button share native interactive glass. |

The selected-place card action +, Map top filters, secondary list actions, Discover, save forms, onboarding, and full place profile retain their existing appearance and behavior. Shared modifiers default to their existing behavior; only the three approved callers opt in.

Glass containers preserve individual component surfaces, without adding a full-width material panel. Native buttons preserve their action handlers and hit areas. iOS 26 uses interactive Liquid Glass; earlier versions retain material fallbacks with opaque terracotta add buttons. Reduce Transparency uses opaque surfaces.

## Render

Run `python3 preview/rec-460-452-approved/render-build.py` from the checkout. Install the resulting preview app on an arm64 iOS Simulator and launch with `--scene map`, `feed`, or `lists`; add `--light` for light appearance. The preview action counter is a local interaction test aid.

PNG files show light and dark appearance at rest. A still screenshot does not establish the press/movement animation. Review presses toward and away from neighboring controls, cancellation, and single action dispatch on iOS 26 before marking motion QA complete.

## Verification record

Light and dark screenshots cover iPhone 17 Pro and iPhone 17e on iOS 26.5. They use the production component definitions and preserve the white place-card + in both appearances.

Current build, test, review, and remaining device-QA evidence is maintained in [PR #614](https://github.com/joelipshutz/wander/pull/614) and REC-460 / REC-452.
