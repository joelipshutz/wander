# REC-657: Totem Live pins and native map design lab

Totem is the accepted pin family for Live. The ten-family native Map exploration
below is retained as design history. Its simulator-only switches remain separate
from the Live implementation and are excluded from Release and device builds.
Live availability continues to follow the existing Live rollout gate; this work
does not replace Profile's Your Map renderer.

## Accepted Live contract, October 28

Totem uses a monochrome category pictogram, compact ownership/status rails, and an
11pt circular list badge at the upper-right corner of full pins only.
The category pictogram fits
inside the cream body above the black footing, with its own clipped bounds.
Solid and dotted status rails share centered visible bounds and equal side
insets; dots are placed symmetrically rather than relying on a dashed stroke.
Own status is coral; readable social status is blue. Been is
solid and Wanna dotted. The Wanna segment in a mixed social Been/Wanna rail has
three dots. Own Been retains precedence when both match, while the Wanna filter can show the remaining Wanna.
Unknown categories use a neutral place pictogram. A selected pin expands above
its neighbors; density and viewed treatment retain the same place identity.

Dense circles summarize the displayed status colors: coral means the viewer's
save, blue means readable social saves, and green means proven Featured-only
state. A coral/blue split means both ownerships are represented. Black is neutral:
there is no displayed Been/Wanna/Featured rail, for example for a list-only place,
filtered-out status or unknown remote state. It is not a visit, person or count.
Dense circles never show a list badge or reserve space for one. Selecting the
place expands the full pin, where the 11pt badge appears if current membership
qualifies; hiding it at density does not change membership or Featured precedence.

| Current authorized place state | Pin state |
| --- | --- |
| Any own or social Been/Wanna | Matching coral/blue rails; no green Featured |
| Saved state plus current readable list membership | Saved rails plus the list badge on full pins |
| Current readable list membership without a saved status | Full-pin list badge with neutral footing; no Featured |
| Active own save awaiting sync or retry, absent from server state | Matching coral Been/Wanna rail under People/Activity filters; never green Featured |
| Viewer-added active entry awaiting sync or retry in a currently readable list | Full-pin list badge remains visible; never green Featured |
| Featured candidate with proven absence of both saves and list membership | Solid green Featured (`#6FB985`) |
| Current remote state unknown, incomplete, revoked or expired | Neutral except for trusted own pending writes; never green Featured |

Membership is resolved from current readable list items, including canonical
aliases and removal tombstones. The badge survives the activity time window and
does not imply that the viewer saved the place or that a list-add event is recent.
An event's required place container cannot manufacture a Been or Wanna save.
Multiple readable lists still produce one badge and one canonical place pin.
A bare private-list companion summary supplies no Wanna rail. The marker survives
later real saves, so explicit Wanna events/history and actual visits remain valid
evidence rather than being discarded with the container.

Activity now includes **Lists** for list-created and place-added-to-list events.
It applies before pagination with the other Live filters. A list creation without
a place remains a Feed event. The map renders at most one pin for each matching
canonical place across people, activities, dates and aliases. Persistent state
decorates those results; it does not insert outside-filter places or synthetic
events. People/Activity choices refine displayed rails, but excluded saved status
still prevents Featured. The People and Scope dropdowns use coral **Only Me**,
blue **Only Friends**, green **Featured**, and neutral **Everyone**, with readable
Light/Dark text variants and explicit selection marks.

Authenticated Live reads a complete per-place current-state snapshot, independent
of the selected event window. Exact requested-identity coverage is required before
absence can be inferred. Current server facts replace stale cached saves, list
items and prior own check-in evidence. Active own saves awaiting sync or retry
immediately show matching coral rails under People/Activity filters. Viewer-added
active entries in currently readable lists retain their badge while pending or
retrying. These trusted local writes prevent green even before server confirmation;
synced stale, other-user, deleted, removing and server-denied records do not receive
that exception. Account/query/authorization changes discard
the snapshot; the existing 15-minute social lease is measured from its oldest
response batch. Foreground and Live-tab re-entry synchronously revalidate expiry,
including when a suspended timer has not resumed. Failure, partial coverage or
expiry keeps the map and authorized events usable but restores no stale/social
cached status or list badge. Trusted own pending writes remain visible. Snapshots are not
persisted. Backend installation remains a release operation after the passing
rollback-only hosted validation described below.

## Live validation and review status

Before final main integration, the dense-dot badge removal and three-dot mixed social rail passed all
3,194 native tests (zero failed/skipped) on iPhone 17e, iOS 26.5. Pixel coverage
verifies one solid social segment plus three distinct Wanna dots and identical
dense-dot pixels with/without list membership. The focused native capture passed
on iPhone 17 Pro and iPhone 17e; four original screenshots are in
`outputs/rec657/live-totem/social-dot-refinement/index.html`.

The previous corner-badge and pin geometry passed all 3,193 native tests on
iPhone 17e (iOS 26.5), with zero failures or skips. Pixel regressions verify every
category silhouette stays inside the body, solid/dotted/mixed rails share
symmetric visible endpoints, the circle overlaps the upper-right corner, and
the 44pt interaction canvas remains unchanged. Light/Dark, selection, viewed
and compact treatments are covered. The focused native eight-state capture
passed on iPhone 17 Pro and iPhone 17e, exporting 20 original screenshots to
`outputs/rec657/live-totem/refined-pins/index.html`. Those screenshots show the
previous geometry. The results below describe the preceding functional pass;
its video retains the earlier badge geometry.

App implementation `15197e3` passed all 3,191 native tests on iPhone 17e (iOS 26.5),
with zero failures or skips, including immediate pending-own save/list feedback.
The final v7 native UI journey passed on iPhone 17 Pro and iPhone 17e, both on
iOS 26.5. It captured 22 original screenshots per device and a simulator video
covering all eight states, colored filters, Lists, persistent membership under
a 24-hour window, place navigation and Featured changing to Wanna. Final media
and the local gallery are in the shared `outputs/rec657/live-totem` directory
outside this worktree and Git.
Earlier lab results below do not validate the integrated Live change.

Hosted validation passed for both focused migration suites and the complete
checked-in smoke suite, with both migrations previewed inside rolled-back
transactions. The deletion fixtures use the authenticated app RPCs: deleting a
save removes its Lists event, while deleting its final check-in preserves a
list-only companion without Been/Wanna status. A read-only postcheck confirmed
zero remaining fixture profiles/places and no installed migration changes.
Neither migration has been deployed; apply both before releasing this behavior.

The current tests cover status/list precedence, authoritative deletion, incomplete
state, query/audience filtering, canonical uniqueness, expiry and account races.
The native review fixture uses the real Live map, drawer, filters and place routes;
its list-only place has a current list item and no persisted companion save.
Its 90-day-old membership remains visible beside an in-window activity.

Reproduce that isolated review with all four launch arguments:

```text
-WanderLiveTotemUITest -WanderAuthenticatedUITest
-WanderUseDemoFixtures -WanderUnifiedLiveUITest
```

The following lab rounds predate the Live selection. Their configuration and
validation records apply to the original native Map comparison only.

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

Approved status refinement: Featured-only marks use solid green (`#6FB985`) in
the second-pass mockups. Green is a fallback only when the viewer and visible
social graph have no active Been or Wanna save for that place. The existing
outline builder already enforces this precedence; personal coral and social blue
replace Featured completely. Green is never dotted. At this stage the refinement
applied only to the mockups; the accepted Live contract above adds current list
membership and authoritative absence requirements.
Historical validation for this refinement: 3,118 native tests passed, with no failures or
skips, including the existing Featured/save precedence coverage and a rendered
Totem color regression in Light and Dark. Featured-only selected captures were
reviewed on iPhone 17 Pro and iPhone 17e.

Capture this round with `scripts/capture-map-design-lab.py --second-pass` and the
same device/app/output arguments. Add `--compact` for all five smaller-phone
overviews. Generate the local comparison with
`scripts/map-pin-second-pass-gallery.py`. All captures are real simulator output
from the existing Map screen and predate Totem's selection for Live.

Use `--featured-totem` with the capture script for the green Featured-only
selected pin; combine with `--compact` for the smaller phone. This uses the
existing anonymous Featured fixture and does not fabricate a personal save.

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
