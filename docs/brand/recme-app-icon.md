# Astir App Icon Contract

This file is the source of truth for the production Astir app icon. The filename
retains the former rec.me name for existing references.

## Canonical Asset

- Master: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- Icon Composer source: `Wander/Resources/AppIcon.icon/Assets/astir-statue-55-signal.png`
- Approved export: `docs/brand/approved/astir-55/Astir-App-Icon-55-signal-1024.png`
- Instagram export: `docs/brand/approved/astir-55/Astir-Instagram-55-signal-1024.png`
- Provenance: `docs/brand/approved/astir-55/provenance.json`
- Icon Composer document: `Wander/Resources/AppIcon.icon/icon.json`
- Manifest: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Master generator: `scripts/generate-app-icon-master.swift`
- Rendition generator: `scripts/generate-app-icon-renditions.sh`
- Regression coverage: `WanderTests/BuildConfigurationTests.swift`

The approved export, Icon Composer source, and 1024 px master must be
byte-identical. The PNG is opaque RGB; its RGB pixels exactly match the selected
review export. Do not treat an image in chat or a screenshot as the canonical asset.

## Visual Contract

Joe approved direction 55 and selected **Signal** on September 10, 2026 (REC-475):

- a warm family statue with recognizable embracing adults and child;
- the statue's A-shaped openings and weathered stone texture;
- a matte ink-black background and the selected full-frame square composition;
- a full-width detached Signal coral foundation, preserving its narrow air gap;
- the existing `ONENESS` inscription at the right of the textured base;
- the original framing, proportions, light, and pixels, with no crop or reframe;
- no added gloss, material blur, specular light, shadow, or translucency.

The PNG must be square and opaque, with no alpha channel or baked rounded
corners; iOS applies the platform mask. Do not alter the statue, base, inscription,
matte finish, or framing without explicit approval. The unselected Oxide export
and historical map artwork are retained for provenance, not used by the icon layer.

The separately approved splash screen is handled in its own change. This
app-icon change does not include a splash update or a TestFlight upload.

## Editing Workflow

1. Treat the selected Icon Composer PNG as the canonical pixel source.
2. Run `scripts/generate-app-icon-master.swift` to validate the source and copy
   it byte-for-byte to the fallback app-icon master.
3. Run `scripts/generate-app-icon-renditions.sh`; it preserves the 1024 px master
   and resizes only the smaller platform renditions.
4. Run `BuildConfigurationTests`, verify source/export/master identity, and
   inspect at least one 180 px and one 87 px rendition.

The tracked source PNG is the lossless visual recipe. The generators synchronize
the asset catalog without regenerating or restyling the approved artwork.
