# Native compositions for directions 46–53

`compose.cjs` builds the lockups and black square icons with native SVG geometry, then renders PNGs with Sharp/librsvg. It does not launch a browser. The source A sculptures are unchanged local photograph pixels, cropped by nested SVG viewBoxes. The three source PNGs are byte-identical to round06.

Run `type-paths.swift` on macOS to export the native New York Medium and Bodoni 72 Book outlines. `type-paths.json` preserves the resulting glyph paths, so rendering does not require either font. Directions46/47 use current serif spacing,50 uses tighter spacing, and51 uses Bodoni. All glyphs are scaled uniformly; none are horizontally compressed. The generated letter inserts for48/49/52/53 are independently preserved as source images and transparent cutouts.

Every direction has equal-height and 1.25× statue-A settings; signal, monochrome, and oxide foundations; and ink/light material treatments. The SVG artboard is2200×1050 and PNG exports are1600×764. The light treatment tonally maps the photographed sculpture and stone letters to charcoal while preserving relief and alpha; flat letters use#141714. This is a material-color exploration, not a new photograph of charcoal stone.

The foundation is one continuous crop of source35, with tonal mapping toward the selected palette. It is not made from repeated or reflected stone strips. ONENESS is the hand-traced centerline recreation supplied in `oneness-original-paths.json`, based on the original photographed inscription. It is not New York lettering and is not an exact pixel extraction.

Six black icons and six corresponding social square originals are1024×1024 with opaque backgrounds. Statue silhouettes and foundations stay inside the centered circular profile-photo crop. The social originals match the icon compositions and are suitable for Instagram/TikTok preview and download; rounded/circular crops belong to the preview UI.

Editable SVGs use relative references to the PNGs beside them, reducing archive duplication. Some browsers restrict external photographs when these SVGs are displayed through an image tag; use the PNG exports for the review board. To create a fully embedded standalone SVG, run `node build/export-standalone.cjs assets/46-equal-signal.svg output.svg` from the round folder. The helper embeds only the referenced photographs and preserves vector typography/composition.

Set `SHARP_MODULE` to the path of an installed Sharp module if the bundled workstation dependency path is unavailable. `validate-assets.cjs` checks source hashes, PNG dimensions/alpha and local SVG references. The contact sheets are native raster compositions for visual inspection, not screenshots of a running app or an interactively tested review page.
