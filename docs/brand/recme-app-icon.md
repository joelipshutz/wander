# rec.me App Icon Contract

This file is the source of truth for the production rec.me app icon.

## Canonical Asset

- Master: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- Icon Composer source: `Wander/Resources/AppIcon.icon/Assets/recme-liquid-glass-map-original.png`
- Icon Composer document: `Wander/Resources/AppIcon.icon/icon.json`
- Manifest: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Master generator: `scripts/generate-app-icon-master.swift`
- Rendition generator: `scripts/generate-app-icon-renditions.sh`
- Regression coverage: `WanderTests/BuildConfigurationTests.swift`

Do not treat an image in chat, a generated-images directory, or a simulator
screenshot as the canonical asset. Once approved, the project-bound 1024 px
master above owns the design.

## Visual Contract

The app icon is the approved matte liquid-glass map artwork:

- full-bleed warm neighborhood map with pale buildings and sage parks;
- four terracotta map pins containing crisp Apple-style plate-and-cutlery,
  tree, volleyball, and books symbols;
- lowercase `rec.me` wordmark, verbatim, centered in a heavy black serif;
- restrained frosted depth with a matte finish, never glossy or shiny;
- a very subtle cool-blue gradient toward the bottom;
- the original full-frame composition, with its bottom-left blue ocean accent
  left at the canvas edge and no top/right crop or directional reframe.

The PNG must be square and opaque. Do not bake rounded corners into the asset;
iOS applies the platform mask. Do not alter the wordmark, pin count, emoji
meanings, matte finish, or original framing without explicit approval.

## Editing Workflow

1. Treat the Icon Composer PNG as the canonical pixel source. The approved
   framing is the original full-frame 1024 px composition with no baked
   platform mask.
2. Run `scripts/generate-app-icon-master.swift` to validate the source and copy
   it byte-for-byte to the fallback app-icon master.
3. Run `scripts/generate-app-icon-renditions.sh`.
4. Run `BuildConfigurationTests` and inspect at least one 180 px and one 87 px
   rendition before approval.

The tracked source PNG is the lossless visual recipe. The Swift generator keeps
the fallback asset catalog synchronized without regenerating or restyling the
approved artwork.
