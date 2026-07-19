# rec.me App Icon Contract

This file is the source of truth for the production rec.me app icon.

## Canonical Asset

- Master: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- Manifest: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Rendition generator: `scripts/generate-app-icon-renditions.sh`
- Regression coverage: `WanderTests/BuildConfigurationTests.swift`

Do not treat an image in chat, a generated-images directory, or a simulator
screenshot as the canonical asset. Once approved, the project-bound 1024 px
master above owns the design.

## Visual Contract

The icon is a full-bleed terracotta field with:

- a dominant cream location pin;
- an espresso bookmark inside the pin;
- cream orbit strokes around the pin;
- one small sky-blue social dot.

The lower-right area remains clear terracotta. Do not add a folded map/page corner,
folded sheet, pencil, road lines, extra object, text, letters, people,
watermarks, transparency, alpha, or baked rounded corners.

## Editing Workflow

1. Start from the canonical 1024 px master or an approved lossless source.
2. Preserve the pin, bookmark, orbit, dot, palette, and their proportions.
3. Keep the lower-right field clear.
4. Replace the canonical master with a square, opaque PNG.
5. Run `scripts/generate-app-icon-renditions.sh`.
6. Run `BuildConfigurationTests` and inspect at least one 180 px and one 87 px
   rendition before approval.

The current master was produced with built-in image editing using this direction:

> Remove the entire cream folded-map/pencil-like object from the lower-right
> corner and replace that whole object and internal lines with a seamless
> continuation of terracotta. Preserve the central cream location pin, espresso
> bookmark, oval, cream orbit strokes, blue social dot, exact positions,
> proportions, colors, and style. Add nothing new.
