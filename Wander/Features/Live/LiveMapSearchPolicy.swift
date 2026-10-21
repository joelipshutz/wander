import MapKit

/// Geographic queries are explicit, session-only choices. A rectangular map
/// search must not masquerade as a freehand drawing in the controls or summary.
enum LiveSelectedArea: Equatable {
    case drawn(LiveDrawnArea)
    case mapViewport(LiveDrawnArea)

    var boundary: LiveDrawnArea {
        switch self { case .drawn(let area), .mapViewport(let area): area }
    }
    var isMapViewport: Bool {
        if case .mapViewport = self { return true }
        return false
    }
    var summary: String { isMapViewport ? "Map area" : "Drawn area" }
    var drawActionTitle: String { isMapViewport ? "Draw area" : "Redraw" }
}

/// The exposed rectangle is in the outer layout's coordinates. MapKit's local
/// content origin already follows its safe-area insets; geographic projection
/// uses this rectangle's size without adding its outer origin a second time.
struct LiveMapSearchLayout: Equatable {
    let size: CGSize
    let controlsHeight: CGFloat
    let drawerHeight: CGFloat

    var visibleRect: CGRect? {
        guard size.width.isFinite, size.height.isFinite,
              controlsHeight.isFinite, drawerHeight.isFinite,
              controlsHeight >= 0, drawerHeight >= 0 else { return nil }
        let exposedHeight = size.height - controlsHeight - drawerHeight
        // CGRect's geometric dimensions standardize negative sizes. Reject
        // an occluded map before constructing a potentially inverted rectangle.
        guard size.width >= 44, exposedHeight.isFinite, exposedHeight >= 44 else { return nil }
        return CGRect(x: 0, y: controlsHeight, width: size.width, height: exposedHeight)
    }

    func matches(_ other: Self) -> Bool {
        abs(size.width - other.size.width) < 0.5
            && abs(size.height - other.size.height) < 0.5
            && abs(controlsHeight - other.controlsHeight) < 0.5
            && abs(drawerHeight - other.drawerHeight) < 0.5
    }
}

enum LiveMapSearchGeometry {
    static func area(layout: LiveMapSearchLayout, longitudeSpan: Double,
                     convert: (CGPoint) -> CLLocationCoordinate2D?) -> LiveDrawnArea? {
        // At world scale, projected corners can wrap into a plausible-looking
        // polygon on the opposite side of the world. Reject before projection.
        guard longitudeSpan.isFinite, longitudeSpan > 0, longitudeSpan < 180,
              let visibleRect = layout.visibleRect else { return nil }
        // MapProxy .local starts at the inset Map content, below the controls.
        // Keep the outer rectangle for layout; convert zero-origin content points.
        let rect = CGRect(origin: .zero, size: visibleRect.size)
        let points = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                      CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        let coordinates = points.compactMap(convert)
        guard coordinates.count == points.count else { return nil }
        return LiveDrawnArea(coordinates: coordinates)
    }
}

/// Camera pose, rather than the enclosing coordinate region, distinguishes a
/// pan/zoom from a drawer changing how much of an unchanged camera is visible.
struct LiveMapSearchCamera: Equatable {
    let latitude: Double
    let longitude: Double
    let distance: Double
    let heading: Double
    let pitch: Double

    var isValid: Bool {
        CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude))
            && distance.isFinite && distance > 0 && heading.isFinite && pitch.isFinite
    }

    func differs(from other: Self) -> Bool {
        let displacement = CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
        let headingDifference = abs((heading - other.heading).truncatingRemainder(dividingBy: 360))
        // Ignore subpixel settling and numeric drift, while retaining normal
        // small intentional pans, pinches and rotations.
        return displacement > max(3, min(distance, other.distance) * 0.002)
            || abs(log(distance / other.distance)) > 0.005
            || min(headingDifference, 360 - headingDifference) > 0.5
            || abs(pitch - other.pitch) > 0.5
    }
}

struct LiveMapSearchState: Equatable {
    private(set) var shouldOfferSearch = false
    private var referenceCamera: LiveMapSearchCamera?
    private(set) var latestCamera: LiveMapSearchCamera?
    private var pendingBeforePresentationChange = false
    private var lastLayout: LiveMapSearchLayout?

    /// Returns true when the caller must write this exact pose back as a
    /// programmatic camera position. MapKit's positionedByUser flag describes
    /// retained provenance; later inset/return callbacks can retain that flag.
    @discardableResult
    mutating func observe(camera: LiveMapSearchCamera, layout: LiveMapSearchLayout,
                          positionedByUser: Bool) -> Bool {
        guard camera.isValid else { return false }
        defer { latestCamera = camera; lastLayout = layout }
        guard positionedByUser, let referenceCamera else {
            self.referenceCamera = camera
            shouldOfferSearch = pendingBeforePresentationChange
            return false
        }
        if let lastLayout, !layout.matches(lastLayout) {
            // An animated inset can emit several different poses with the same
            // final SwiftUI layout. Clear its retained user provenance as well
            // as rebasing this first callback; one skipped callback is not enough.
            rebaseForPresentationChange()
            self.referenceCamera = camera
            return true
        }
        shouldOfferSearch = pendingBeforePresentationChange || camera.differs(from: referenceCamera)
        return false
    }

    /// Preserve a staged search across layout/visibility changes. Subsequent
    /// programmatic poses rebase the camera comparison, never the committed query.
    mutating func rebaseForPresentationChange() {
        pendingBeforePresentationChange = shouldOfferSearch
        referenceCamera = latestCamera
    }

    mutating func didCommit() {
        referenceCamera = latestCamera
        shouldOfferSearch = false
        pendingBeforePresentationChange = false
    }

    mutating func willMoveProgrammatically() { self = Self() }
}
