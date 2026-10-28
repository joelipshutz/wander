import MapKit

/// Owns only the basemap presentation. App annotations and later overlays keep
/// their original colors, and changing appearance never issues a camera command.
@MainActor
final class MapBasemapAppearance {
    private weak var configuredMapView: MKMapView?
    private let grayscaleOverlay: MKPolygon = {
        let world = MKMapRect.world
        let corners = [MKMapPoint(x: world.minX, y: world.minY),
                       MKMapPoint(x: world.maxX, y: world.minY),
                       MKMapPoint(x: world.maxX, y: world.maxY),
                       MKMapPoint(x: world.minX, y: world.maxY)]
        return MKPolygon(points: corners, count: corners.count)
    }()

    func update(mapView: MKMapView, coloredMap: Bool, isDark: Bool) {
        if configuredMapView !== mapView {
            let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            configuration.pointOfInterestFilter = .includingAll
            configuration.showsTraffic = false
            mapView.preferredConfiguration = configuration
            configuredMapView = mapView
        }
        let style: UIUserInterfaceStyle = isDark ? .dark : .light
        if mapView.overrideUserInterfaceStyle != style { mapView.overrideUserInterfaceStyle = style }
        let installed = mapView.overlays.contains { ($0 as AnyObject) === grayscaleOverlay }
        if coloredMap, installed {
            mapView.removeOverlay(grayscaleOverlay)
        } else if !coloredMap, !installed {
            // App area/radius overlays follow this one at the same level.
            mapView.insertOverlay(grayscaleOverlay, at: 0, level: .aboveLabels)
        }
    }

    func renderer(for overlay: any MKOverlay) -> MKOverlayRenderer? {
        guard (overlay as AnyObject) === grayscaleOverlay else { return nil }
        let renderer = MKPolygonRenderer(polygon: grayscaleOverlay)
        renderer.fillColor = .gray
        renderer.blendMode = .saturation
        return renderer
    }
}
