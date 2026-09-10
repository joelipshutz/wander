# Approved 56 Signal splash assets

This native splash preview uses the exact approved round09 direction `56-signal-glimmer.png`. The warm statue, letter placement, restrained stationary letter glimmer, full-width Signal foundation, and ONENESS inscription are unchanged. No new image generation, photograph redraw, font substitution, or old-round edits were used.

The preview remains subject to user review before opening or landing a splash PR. These assets do not change the existing launch-readiness timing.

## Files and placement

- `56-signal-glimmer.png` is the preserved approved source. Its bytes are copied directly into `Wander/Resources/Assets.xcassets/AstirLaunchWordmark.imageset/AstirLaunchWordmark.png`.
- `STIR-mask.svg` contains only the four preserved glyph outlines and their exact original transform. It embeds no font, image, network link, or statue geometry.
- `source-type.json` retains those outlines and the original 2200×1050 geometry. The type came from the approved `.NewYork-Medium` outline source with tracking 26; the renderer does not need that font installed.
- `AstirLaunchSTIRMask.imageset/AstirLaunchSTIRMask.png` is a white, transparent mask on the same 1600×764 canvas as the still. Place both assets in the identical fitted rectangle. Do not crop the mask to its visible bounds.
- `provenance.json` records source paths and SHA256 hashes. `validation.json` records actual native rendering and pixel checks. Neither file claims browser or device testing.

The native moving light belongs inside this STIR-only mask. Keep the complete approved still visible beneath it, and keep the statue, pedestal, and inscription stationary. Reduced Motion should use the still without a moving overlay.

## Reproduce and validate

Run `node scripts/generate-astir-splash-56-assets.cjs` from the repository, with Sharp 0.35.4 available to Node. An explicit installation may be selected with `SHARP_MODULE=/absolute/path/to/sharp/dist/index.cjs`. No remote request or archived exploration checkout is needed: all source material is retained here.

The generator copies the still byte for byte, rebuilds the SVG from the preserved outlines, renders the mask at 1600 pixels wide through the original Sharp SVG pipeline, and writes the two asset catalogs plus validation report. The recorded rendering environment is Sharp 0.35.4, libvips 8.18.6, and librsvg 2.62.91. Different native library versions may change edge rasterization; the exact-alpha assertions will stop the run if that happens.

Validation confirms both canvases are 1600×764; every alpha value across the STIR region equals the approved still; all visible mask pixels are white; the mask contains four separate glyphs and one transparent R counter; and no mask pixel lies in the statue or foundation region. The mask’s visible bounds are `(518, 225, 864, 307)`, with 88,761 nonzero-alpha pixels. Its full artboard remains intact.

Approved still SHA256: `ca42b250579fcd9571ba05520a4940ef8148a199e97aa6aeb16e918ec67e9ae8`.

Native STIR mask SHA256: `d4ae1b2de60931de5f1531d76cdbab05b94ad1df8c98a5b49a11ed655f821900`.
