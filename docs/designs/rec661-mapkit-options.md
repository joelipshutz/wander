# REC-661: Grayscale main map

Ryan selected grayscale for both light and dark modes on October 28, 2026.
The existing colored pins stay unchanged. Settings → Map → **Colored map**
returns the main map to native muted colors: Paper in light mode and Ink in
dark mode. Grayscale is the default for new installations and older snapshots
without the setting.

## Scope and behavior

The preference applies to the primary Live map and the legacy Map tab. Profile,
list, place-detail, onboarding and import preview maps retain their existing
appearance. It follows the scope of the Map settings, rather than changing the
whole app's color palette.

The existing Dark mode switch also applies to Live. System dark appearance still
works when that override is off. Colored map applies immediately and survives a
restart, following the existing local appearance preference lifetime: sign-out
and account switching preserve it, while deleting the account resets it.

Both options use Apple's standard, flat, muted map with all native POI categories
and traffic off. Grayscale adds one world-sized polygon at `aboveLabels`, filled
with neutral gray using the public `MKOverlayRenderer.blendMode = .saturation`.
MapKit renders annotation views above that overlay, retaining their colors. Drawn
areas and nearby-radius overlays follow it, retaining their existing accent.
No alternate tile service, custom tile download or private MapKit API is used.

## Integration

`MapBasemapAppearance` owns the configuration and only its grayscale overlay.
Toggling it does not replace the map, move the camera, rebuild annotations, or
remove other overlays. The legacy map uses its existing owned native renderer.

Live hosts an owned `MKMapView` in SwiftUI so its public overlay renderer can
apply grayscale below annotations. The existing `LiveTotemPinView` supplies the
same pin appearance, selection, viewed state and density reduction. Existing
Live filtering, place previews, saves, sharing, navigation and access policies
remain above this adapter. Native Apple POIs still resolve through
`MKMapItemRequest` into the existing unsaved-place preview.

Camera requests have an explicit revision so a repeated request remains valid
after user movement. The adapter reports observed camera geometry separately
from programmatic requests, preserving Search this area behavior. Native
coordinate conversion supplies area drawing and preview camera adjustments.
Camera fitting uses the full map bounds; control margins position Apple's
attribution and compass without fitting the same region a second time. Observed
regions also use full-bounds conversion because MapKit's `region` reflects its
inset content area when margins are present.
Fitting commands supply the geographic subrectangle corresponding to those
insets while keeping margins stable during animation. Preview reveals use the
native camera's projected anchor, preserving the requested pin position even
with a tall preview.
The native selection-clear revision is separate from async place lookup tokens,
so beginning a lookup does not dismiss the selected POI.

## Validation

The regression suite covers preference migration/persistence, overlay isolation,
camera and annotation preservation, repeated camera commands, and native map
selection/conversion. UI checks exercise the real Settings controls and primary
Live map in grayscale and colored light/dark states. Final test and screenshot
results are recorded in REC-661 and the implementation PR.

The simulator design gallery is retained as local review evidence. Its earlier
five-style and isolated grayscale captures predate production integration; they
are not evidence for the final adapter's complete behavior. The experimental
launch-argument lab and isolated preview have been removed from app code.
Screenshots and result bundles stay outside Git; `scripts/mapkit-style-gallery.py`
can rebuild the earlier comparison from exported XCTest attachments.

## Apple references

- [Map configurations and overlay blend modes](https://developer.apple.com/videos/play/wwdc2022/10035/)
- [MKOverlayRenderer](https://developer.apple.com/documentation/mapkit/mkoverlayrenderer)
- [MKMapItemRequest](https://developer.apple.com/documentation/mapkit/mkmapitemrequest)
- [Map design guidance](https://developer.apple.com/design/human-interface-guidelines/maps)

MapKit has no built-in black-and-white SwiftUI Map style. A SwiftUI shape-style
blend on MapPolygon did not produce this treatment in the native renderer;
the implementation therefore uses the documented native overlay API.
