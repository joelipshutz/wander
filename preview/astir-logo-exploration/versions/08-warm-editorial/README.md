# Astir · Exploration 08 · Warm editorial

Open `index.html` directly in a browser. This is a saved identity comparison with local artwork and editable SVG compositions. It does not change the production app or require a preview server.

## What this round compares

The starting point is direction 46: its flat serif, spacing and warm letter color, paired with the chosen statue from 36. The two new directions isolate the statue treatment while keeping that typography stable.

| Direction | Statue | Lettering and proportions |
| --- | --- | --- |
| 46 · Saved reference | The earlier statue 34 treatment | Exact copies of the round 07 tall signal and oxide lockups |
| 54 · Original stone | Statue 36 in its preserved source color | Direction 46's flat serif outlines, spacing and color |
| 55 · Warm stone | The same statue 36 with a native SVG tonal adjustment toward the warmth of 46 | The same flat serif outlines, spacing and color as 54 |

Both new directions use only the taller statue layout: a 525-unit statue height against a 420-unit letter cap height. Signal and oxide foundations run beneath the whole wordmark. There are no new equal-height layouts or stone-letter fonts in this round.

The earlier 46 and 50 flat letters were already the same color, **#E6DDCD**. Their source statue and spacing differed. This round does not describe their previous difference as a letter-color change.

## Black app icons and social profiles

There are 15 icon configurations: three statue families—34 in its source color, 36 in its source color, and warmed 36—each with five foundation choices. Those choices are long signal, long oxide, compact signal, compact oxide, or no foundation. The compact foundation is the same width as the statue. The statue remains 610 units tall across the foundation options, so a base change does not also change the symbol's scale.

App icons and social exports are 1024 × 1024 square images on black, with the same centered composition and clearance for a circular profile crop. Instagram and TikTok previews are identity mockups; no profile or account is changed. The social files carry the same artwork as the corresponding app-icon configuration.

## Material and type provenance

The family statue comes from the preserved 34/36 artwork. Direction 54 retains 36's source appearance; direction 55 changes its tone through native SVG processing. The statue's shape, faces and openings are not redrawn. **No new AI image generation is used in round 08.** The selected statue sources were established in earlier explorations; this claim concerns how the current round was made.

The STIR lettering uses the existing flat serif paths and #E6DDCD color from 46. It is not a generated stone alphabet or a texture fill. The full-width foundation and right-aligned ONENESS treatment carry forward from the saved identity work. ONENESS remains the earlier hand-traced interpretation of the photographed inscription, rather than a new font or a claimed pixel-exact extraction.

Signal **#F05A3C** and oxide **#A45B42** are the foundation comparisons. The warmer statue is a color calibration of existing artwork, not a new sculptural interpretation. These comparisons do not update Astir's app palette, code, map pins or infrastructure.

`assets/metadata.json` records the final asset names, statue families, geometry and provenance. The source and composition checks under `build/` describe the actual processing and verification performed.

## Saved comparison sheets

- [Splash comparison](qa/splash-comparison.png): 46, 54 and 55 in the iPhone launch composition.
- [Signal icon comparison](qa/icon-comparison-signal.png): the three statue treatments and standalone base choices.
- [Oxide icon comparison](qa/icon-comparison-oxide.png): the same icon choices with the oxide foundation.

These are native-rendered design sheets assembled from the exported artwork. They were visually reviewed as composition references; they are not browser screenshots, screenshots of a running iOS app, or evidence that the page's interactions were tested.

## Files and offline use

The six wordmark PNGs are transparent 1600 × 764 exports. Their matching SVGs are editable compositions. App icons and social profile files are opaque 1024 × 1024 PNGs with corresponding SVG files. Keep the folder together so any local image references in an SVG remain available; use a PNG for a single flattened portable image. No proprietary font files are bundled.

The bundle opens from `START-HERE.html` and contains this round at `versions/08-warm-editorial/`. Inside that portable copy, the archive link returns to its local hub and the bundle-download links become explanatory text, avoiding a link to a ZIP nested inside itself. The return link to round 07 also becomes a note that earlier rounds remain in the full local archive; those earlier files are not duplicated in this bundle.

## Preservation and validation

Rounds 01–07 are preserved. `qa/prior-versions-before.json` records a SHA-256 baseline of every file in those numbered folders before work on this round. Once this round is saved, further explorations belong in round **09**, continuing with direction **56**. Preserve round 08's pages, source assets, comparisons and validation records rather than replacing them.

Run `python3 build/validate-page.py` after the page and assets are complete. It checks local page/CSS/SVG references, the expected wordmark/icon/social combinations, PNG dimensions and channel declarations, reference 46 copies, literal script selectors, and all earlier-round hashes. It writes `qa/page-validation.json`. These are static file checks, not proof of browser interaction or visual quality; separate review records should be read for those claims.

Run `python3 build/package.py` only after the round is ready. It writes `ARCHIVE-MANIFEST.json`, creates `ASTIR-exploration-08.zip`, verifies ZIP integrity and the saved content hashes, and records the result in `qa/package-validation.json`. The manifest inside the ZIP describes its portable HTML version, whose bundle-download and previous-round links become explanatory text.
