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

The app icon is the approved dark matte liquid-glass map artwork:

- full-bleed charcoal/navy aerial neighborhood map with outlined buildings and
  one softly illuminated sage-green park;
- lowercase `rec.me` wordmark, verbatim, centered in dimensional white glass;
- restrained frosted depth, soft refraction, and fine edge highlights with a
  matte finish, never glossy, metallic, neon, or prismatic;
- subtle cool-blue undertones that preserve strong contrast at small sizes;
- the selected full-frame square composition with no crop or directional
  reframe.

The PNG must be square and opaque. Do not bake rounded corners into the asset;
iOS applies the platform mask. Do not alter the wordmark, map geometry, matte
finish, or selected framing without explicit approval.

## Editing Workflow

1. Treat the Icon Composer PNG as the canonical pixel source. The approved
   framing is the selected full-frame 1024 px composition with no baked
   platform mask.
2. Run `scripts/generate-app-icon-master.swift` to validate the source and copy
   it byte-for-byte to the fallback app-icon master.
3. Run `scripts/generate-app-icon-renditions.sh`.
4. Run `BuildConfigurationTests` and inspect at least one 180 px and one 87 px
   rendition before approval.

The tracked source PNG is the lossless visual recipe. The Swift generator keeps
the fallback asset catalog synchronized without regenerating or restyling the
approved artwork.
