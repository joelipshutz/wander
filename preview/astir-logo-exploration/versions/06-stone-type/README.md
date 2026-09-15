# Astir · Exploration 06 · Stone & type

Saved September 9, 2026. Open `index.html` directly in a browser. No preview server, build step, account, or internet connection is needed.

This round preserves studies **34 and 36** and explores their statue-shaped A with Astir's current serif direction, stone lettering, a continuous coral foundation, and ONENESS engraved near the right edge. The page includes paper and ink splash studies, four app icons, actual 60/40/32 px icon comparisons, downloadable artwork, and a local shortlist with exportable notes.

| Direction | Statue A | Lettering | Icon |
| --- | --- | --- | --- |
| 42 | 34, warm and broad | New York Medium, stone face | Paper with signal base |
| 43 | 36, more tapered | New York Medium, stone face | Ink, statue alone |
| 44 | 34, warm and broad | New York Bold, stone face | Signal field, statue alone |
| 45 | 36, more tapered | New York Bold, stone face | Ink with signal base |

43 is the initial comparison view because it carries forward the more tapered A. This is a viewing default, not a final brand decision. No new direction is automatically shortlisted.

## Preserved references and construction

`assets/source34.png` and `assets/source36.png` are byte-identical copies of the original round02 transparent artwork. These were generated studies based on DSCF2954; they are not the unaltered source photograph. This round retains their exact sculpture pixels through SVG crops, including the existing heads, embrace, child, and openings. The original round02 pages, generations, drafts, and numbering remain intact in the complete local exploration archive.

The new STIR lettering uses exact native New York Medium and Bold outlines retained from round05. Stone texture is sampled from each selected study and clipped inside those letter outlines, with shallow SVG edge relief. The continuous foundation uses study35's textured base, tinted toward the app's signal color. ONENESS uses outlined serif lettering at the far right. No new AI image generation was used in this round. The earlier source-generation prompts are preserved in `source-prompts.json`.

Wordmark exports are transparent **2200 × 1050** PNGs and editable SVG compositions. Icons are opaque **1024 × 1024** square PNGs and SVGs. Rounded corners are a preview mask. SVGs embed their photographs and glyph outlines; no proprietary font binaries or external image URLs are required. Photographic textures remain raster content inside the editable SVG.

## App references

The repository's `Wander/DesignSystem/AstirVisualSystem.swift` defines signal **#F05A3C**, paper **#F2E9DB**, raised paper **#FBF6ED**, and ink **#141714**. Its wordmark uses the native system serif at medium weight; the standard masthead is 22 pt with tracking 5.2. These explorations use that serif family with optical spacing suited to the sculptural A.

`Wander/Features/Onboarding/LoggedOutCarouselView.swift` contains the existing `OnboardingLaunchView`. The two splash previews here are proposed logo applications, not captures of a changed running app. OCEAN PARK is retained as a contextual line from the brand exploration; it is separate from the core wordmark.

Astir was previously called rec.me and Wander; existing repository and source identifiers retain those historical names. This round changes preview artifacts only. No production app icon, splash, feature flag, or runtime code is changed.

## Versioning

Preserve this folder, all numbered images, and the selected originals. Future iterations belong in a new round07 folder and continue from direction46. Do not replace an older export or reuse its number. The complete local archive retains rounds01–05; a repository copy of this round also includes the two selected original references and source35 used for the foundation.

The shortlist is stored in the browser when available. Download the notes JSON to carry it between computers or browser profiles. `ASTIR-exploration-06.zip` is a portable copy of this round with its own START-HERE page.

## Validation

The assets were visually inspected in a rendered contact sheet. Source-image hashes, PNG dimensions and alpha, local file references, JavaScript syntax, and preservation of rounds01–05 are checked in `build/` and `qa/`. Direct file-page navigation was blocked by the browser automation URL policy in this session, so interactive desktop/mobile rendering of the review itself was not verified through that tool. The saved page uses ordinary local HTML, CSS, images, and a classic script with no server calls.
