# REC-657: native map design lab

Ten pin families across two rounds and five MapKit treatments, rendered in the existing Astir Map
with fictional storefront fixtures. This is an unselected design exploration.
Release and device builds exclude the lab. Ordinary simulator launches keep the
current map and pins.

## Second pass: five new visual systems

The first round was rejected. This round removes displayed emoji and the large
concentric status rings. Each family changes the visual language of the mark,
instead of changing only the container around the same category emoji.

| Family | Visual language | Assessment |
| --- | --- | --- |
| Cutout | Custom vector objects with a sticker edge | Most illustrative; assess category recognition at map scale |
| Wayfinder | Filled cartographic marker with a white native pictogram | Strong silhouette; assess density and category clarity |
| Letterpress | Editorial serif place initial on an ink stamp | Prioritizes place identity; initials can repeat |
| Totem | Upright pictogram tile with a separate status footing | Strong vertical rhythm; assess visual weight |
| Contour | Floating outline pictogram with a white keyline | Lightest footprint; assess legibility over detailed geography |

Ownership and Been/Wanna state move into compact solid/dotted rails, with split
segments for mixed state. Both ownerships remain visible when applicable.
Featured remains anonymous. No new person identities, counts, rankings, or live
location meanings are invented. Category lookup uses existing metadata; unknown
categories get a neutral place pictogram. Letterpress includes the title in the
review-only image and annotation reuse keys so unrelated places cannot share a
cached initial.

Capture this round with `scripts/capture-map-design-lab.py --second-pass` and the
same device/app/output arguments. Add `--compact` for all five smaller-phone
overviews. Generate the local comparison with
`scripts/map-pin-second-pass-gallery.py`. All captures are real simulator output
from the existing Map screen. No production family has been selected.

Second-pass validation on iOS 26.5: the final native suite passed 3,117 tests,
with no failures or skips, on iPhone 17e. The five-family physical tap,
selected-card, place-profile, and return scenarios also passed on iPhone 17e.
Fifteen screenshots cover overview and selected states on iPhone 17 Pro plus
five compact overviews. Actual captures prompted smaller pictograms in
Wayfinder/Totem and a lighter Contour outline. The initial full run caught an
emoji presentation selector being accepted as a Letterpress initial; explicit
Unicode letter/number categories fixed it, and the full suite was rerun.
The gallery includes CSS magnifications of the unchanged native screenshots.
Python/embedded JavaScript syntax, image references, diff whitespace, and review
storage checks pass. Browser interaction with the local HTML is not verified.

## First pass: retained for reference

| Family | Intent | Tradeoff |
| --- | --- | --- |
| Porcelain | Crisp category disc, restrained depth, semantic status rings | Closest to the current grammar; strongest starting point for dense maps |
| Signal | Dark enamel tile with a category center | Strong silhouette; more visually assertive |
| Bookmark | Place memory expressed as a small bookmark | Distinctive, but needs user testing for geographic readability |
| Ticket | Compact horizontal category capsule | Softer and more editorial; wider collision footprint |
| Compass | Diamond medallion around the category | Distinctive navigation character; may feel more like a waypoint |

All retain native category emoji, current-user/social ownership, solid Been and
dotted Wanna rings, mixed states, search distinction, and selected place labels.
Featured stays an anonymous place aggregate. There are no fabricated contributor
counts, live-person markers, or new clustering behavior.

## Map treatments

| Treatment | Actual native configuration | Intended use |
| --- | --- | --- |
| Quiet streets | Standard, flat, muted | Recommended everyday baseline; same cartography as current app |
| Street atlas | Standard, flat, default emphasis | Stronger roads and neighborhood context |
| After dark | Standard, flat, muted, system Dark appearance | Night counterpart with brighter annotation contrast |
| Terrain detail | Standard, realistic elevation, default emphasis; existing camera | Richer geography without forced perspective |
| Aerial context | Hybrid, flat | Optional landscape/coastline view; imagery adds visual noise |

Forced 40-degree perspective was evaluated and excluded because it reduced visible-pin density in the overview. The retained terrain option leaves all camera behavior unchanged.

Every configuration includes all native POIs and retains native POI selection.
Search, place resolution, visibility, camera delegates, map gestures, location,
attribution, and place navigation use the existing implementation. No tile tint,
opaque overlay, custom tile service, or search filter is introduced. Realistic
elevation and imagery detail depend on Apple's local coverage. Dark mode is a
supported appearance, not a new tile palette. Native MapKit does not expose
arbitrary road/land colors.

## Research

- [Apple's map guidance](https://developer.apple.com/design/human-interface-guidelines/maps)
  supports distinct selection and muted cartography when app information needs
  priority. Astir's existing no-clustering contract remains in force.
- [Google Maps category design](https://blog.google/products-and-platforms/products/maps/google-maps-gets-new-look/)
  combines category icon and color. Astir keeps glyphs and non-color status cues.
- [Airbnb's map search engineering](https://airbnb.tech/ai-ml/improving-search-ranking-for-maps/)
  and [2023 release](https://news.airbnb.com/product-releases/airbnb-2023-summer-release)
  demonstrate informative pins alongside smaller marks. The useful lesson here
  is selective detail and persistent identity while navigating.
- [Beli](https://beliapp.com/) centers visited, want-to-try, and friends' opinions.
  [Mapstr](https://en.mapstr.com/faq) separates categories/tags from tried/to-try
  state. Both reinforce place memory as the primary information.
- Native support: [MapKit configuration](https://developer.apple.com/videos/play/wwdc2022/10035/),
  [SwiftUI MapKit](https://developer.apple.com/videos/play/wwdc2023/10043/),
  [POI filters](https://developer.apple.com/documentation/mapkit/mkpointofinterestfilter).

These are documented patterns and design inferences, not measured performance
claims for the proposed designs.

## Reproduce

Build Debug for an iOS simulator. The lab requires all of these fixture flags:

```text
-WanderMapCapture -WanderUseStorefrontFixtures
-WanderAuthenticatedUITest -WanderDisableWalkthroughs
-WanderMapCaptureMode friends
-WanderPinDesign porcelain
-WanderMapDesign quiet
```

Pin values, second pass: `cutout`, `wayfinder`, `letterpress`, `totem`, `contour`.
Pin values, first pass: `porcelain`, `signal`, `bookmark`, `ticket`, `compass`.
Map values: `quiet`, `atlas`, `night`, `dimension`, `hybrid`.
Use simulator system Dark appearance for `night`.
Add `-WanderMapPlace "Hearthline Coffee"` for the selected place state.
Unknown or incomplete lab arguments leave production rendering unchanged.
Options are immutable for the process; relaunch between comparisons.

The renderer uses SwiftUI `ImageRenderer` within the existing native annotation
image cache. The visible glyph remains centered on its geographic coordinate;
the selected-title canvas uses a compensating offset. The lab shares production canvas dimensions so transparent padding does not change collision suppression. Existing accessibility
labels, activation, hit testing, reuse, visibility, and adaptive dots remain in
the native annotation implementation.

## First-pass validation

`MapDesignLabTests` covers fixture-only activation, native configuration/POI
contracts, rendering across semantic states, and coordinate anchoring.
`MapDesignLabUITests` physically taps a map pin and opens/returns from its place
profile for every pin family and every map treatment. Validation completed on iOS 26.5: the full native suite passed 3,112/3,112;
all ten physical selection/place-profile scenarios passed. The first full run
exposed an unhydrated Git LFS video; restoring the locally cached committed
object resolved it without a source or asset revision. Final retained map options
preserve native POIs and camera behavior. The final comparison includes 17
screenshots across iPhone 17 Pro and iPhone 17e. Evidence and restart commands
are recorded in the PR and Linear issue.
