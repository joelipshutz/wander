# rec.me App Icon Contract

This file is the source of truth for the production rec.me app icon.

## Canonical Asset

- Master: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- Manifest: `Wander/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Master generator: `scripts/generate-app-icon-master.swift`
- Rendition generator: `scripts/generate-app-icon-renditions.sh`
- Regression coverage: `WanderTests/BuildConfigurationTests.swift`

Do not treat an image in chat, a generated-images directory, or a simulator
screenshot as the canonical asset. Once approved, the project-bound 1024 px
master above owns the design.

## Visual Contract

The app icon is the loading treatment from `OnboardingLaunchView`, scaled for
small-icon legibility:

- full-bleed warm canvas `#F3DFCA`;
- native SF Symbol `mappin.and.ellipse`, bold, in terracotta `#D46F4D`;
- lowercase wordmark `rec.me`, verbatim, in the native system serif at black
  weight and solid black;
- approved option B uses a slight `-2.5` optical kern at the 1024 px master;
  this is an app-icon wordmark exception to the UI's no-negative-tracking rule;
- icon above wordmark in one centered vertical lockup;
- generous negative space, with no shadows, gradients, borders, textures, or
  additional objects.

The PNG must be square and opaque. Do not bake rounded corners into the asset;
iOS applies the platform mask. Do not substitute another map pin, typeface,
wordmark spelling, palette, model-generated artwork, or decorative element.

## Editing Workflow

1. Keep `OnboardingLaunchView` and this contract aligned if the loading mark
   changes.
2. Run `scripts/generate-app-icon-master.swift` to replace the canonical master
   deterministically from the native symbol, typeface, and palette.
3. Run `scripts/generate-app-icon-renditions.sh`.
4. Run `BuildConfigurationTests` and inspect at least one 180 px and one 87 px
   rendition before approval.

The tracked Swift generator is the lossless source recipe. Image generation is
not part of this workflow because the production mark is already defined by
native SwiftUI/SF Symbol primitives.
