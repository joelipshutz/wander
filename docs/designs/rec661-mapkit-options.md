# REC-661: Native MapKit comparison

This review uses the current Live screen from main at `be8ef7d079`, with its
existing SwiftUI map, pins, filters, drawer and place navigation. It is separate
from the ongoing REC-657 Totem pin work. No basemap has been selected for production.

| Option | Native configuration | Design assessment |
| --- | --- | --- |
| Paper | Standard, flat, muted, light | Recommended daytime candidate: calmer roads give saved places more emphasis. |
| Atlas | Standard, flat, automatic emphasis, light | Stronger street and park context; closest to the current Live default. |
| Ink | Standard, flat, muted, dark | Recommended night counterpart: restrained geography and clear pin contrast. |
| Midnight | Standard, flat, automatic emphasis, dark | More legible geographic detail at night, with more background competition. |
| Aerial | Hybrid, flat, light chrome | Satellite imagery with road labels and POIs; useful for parks and coastal context, visually busiest. |

These are five combinations of Apple's supported styles and appearance, not
five custom tile palettes. MapKit does not expose arbitrary land/road recoloring.
All five include every native POI category and turn traffic off. All use the
same data and native double-tap framing procedure. No forced pitch, tile overlay, custom provider, tint layer,
annotation replacement, search narrowing or additional gesture recognizer is added.

The normal-launch and Release configuration remains exactly
`.standard(elevation: .flat, pointsOfInterest: .all)`. Review arguments are compiled
only for Debug simulators and require all four existing authenticated/demo/Live/NUX
fixture arguments. The fixture is synthetic and uses the existing Noop analytics
path. The appearance override intentionally includes native screen chrome so the
comparison shows coherent light and dark app states; it is not persisted.

## Functional boundaries

The native POI-selection modifier, custom annotation identities, selected-place
binding, user annotation, camera binding, map-reader coordinate conversion,
drawn polygon/radius overlays, interaction modes, search logic and filters remain
unchanged, including the native attribution configuration. The visual change does not
alter privacy, data fetching, saves, location permission or backend contracts.

Keeping POIs visible preserves direct map discovery as well as search. A cleaner
map made by hiding POIs would have removed that direct interaction. Realistic
terrain was excluded: it is less distinct without a pitched camera, coverage
varies, and Apple documents that ordinary overlays can flatten realistic terrain.
Hybrid uses imagery and is best treated as an optional view; simulator checks
do not establish real-device bandwidth, battery or rendering performance parity.

## Research

- [Apple Maps design guidance](https://developer.apple.com/design/human-interface-guidelines/maps)
- [SwiftUI MapStyle API](https://developer.apple.com/documentation/mapkit/mapstyle)
- [MapKit for SwiftUI, WWDC23](https://developer.apple.com/videos/play/wwdc2023/10043/)
- [Map configurations and overlay behavior, WWDC22](https://developer.apple.com/videos/play/wwdc2022/10035/)

The recommendations are design judgments, not measured performance claims.

## Validation

The full native suite passed: 3,114 tests, zero failures or skips. The simulator
build, gallery syntax check and review-storage check also passed.

All five styles on iPhone 17 Pro and iPhone 17e completed physical pin selection,
preview controls, close/reselect, full place-profile navigation, filter apply and
cancel, and physical panning. Those combined UI runs then failed a synthetic zoom
distance assertion, including Atlas (the existing basemap). Targeted double-tap
retries also failed. This remains an unresolved validation gap; the combined UI
runs are not passing, and the screenshots do not establish zoom correctness.
The final capture harness keeps pan coverage and tests area apply/clear separately
so the unproven zoom assertion cannot prevent other checks. No production gesture
or camera code was changed to accommodate the harness.

The independent area run captured all five polygon previews and applied each area,
but its Clear disappearance assertion also failed across the styles, including
Atlas. Retaining those failures is deliberate: this is a design review lab, not a
production-adoption approval. A zero-test discovery run is excluded from validation.

Native POI selection, device performance, battery and network usage have not been
validated by this comparison. A chosen production style needs those focused checks
before adoption. The simulator-only lab itself does not change normal app behavior.

## Reproduce

Build the Wander scheme in Debug for a simulator, then launch with:

```text
-WanderAuthenticatedUITest -WanderUseDemoFixtures -WanderDisableWalkthroughs
-WanderUnifiedLiveUITest -WanderNUXFeedFixture -WanderInitialTab discover
-WanderLiveMapStyle paper
-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1 3
```

Replace `paper` with `atlas`, `ink`, `midnight` or `aerial`. Relaunch between options.
Invalid or incomplete arguments keep the normal map configuration.

`LiveMapStyleLabUITests` captures overview and selected-place views while testing
the existing interaction paths. Run it on a current and compact iPhone. Export
the named XCTest screenshots and build the local gallery with:

```sh
python3 scripts/mapkit-style-gallery.py --large /path/to/large-attachments \
  --compact /path/to/compact-attachments --output /path/to/mapkit-options
```

The gallery contains overview, selected-place and area-overlay captures on each
phone. It displays original PNGs without compositing, retouching or generated map
art. Raw screenshots and result bundles stay outside Git; final validation and
evidence locations are recorded in the task handoff and Linear.
