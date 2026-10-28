import MapKit
import XCTest
@testable import Wander

@MainActor
final class NativeMapBasemapIntegrationTests: XCTestCase {
    func testPrimaryMapColorTogglePreservesCameraPinsAndOtherOverlays() throws {
        for isDark in [false, true] {
            let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            map.selectableMapFeatures = [.pointsOfInterest]
            let unrelatedOverlay = MKCircle(center: coordinate, radius: 100)
            map.addOverlay(unrelatedOverlay)
            var parent = makeMap(isDark: isDark, coloredMap: false)
            let coordinator = parent.makeCoordinator()
            coordinator.update(parent: parent, mapView: map)

            let originalPin = try XCTUnwrap(map.annotations.first { !($0 is MKUserLocation) })
            let originalCamera = map.camera.copy() as! MKMapCamera
            let grayscaleOverlay = try XCTUnwrap(map.overlays.first { $0 !== unrelatedOverlay })
            let renderer = try XCTUnwrap(
                coordinator.mapView(map, rendererFor: grayscaleOverlay) as? MKPolygonRenderer
            )
            XCTAssertEqual(renderer.blendMode, .saturation)
            XCTAssertEqual(map.overrideUserInterfaceStyle, isDark ? .dark : .light)

            // Repeated state updates must reuse the overlay and annotations.
            coordinator.update(parent: parent, mapView: map)
            XCTAssertEqual(map.overlays.count, 2)
            XCTAssertTrue(map.overlays.contains { $0 === grayscaleOverlay })

            parent.coloredMap = true
            coordinator.update(parent: parent, mapView: map)

            XCTAssertEqual(map.overlays.count, 1)
            XCTAssertTrue(map.overlays.first === unrelatedOverlay)
            let remainingPin = try XCTUnwrap(map.annotations.first { !($0 is MKUserLocation) })
            XCTAssertTrue(remainingPin === originalPin)
            XCTAssertEqual(map.camera.centerCoordinate.latitude, originalCamera.centerCoordinate.latitude, accuracy: 0.0000001)
            XCTAssertEqual(map.camera.centerCoordinate.longitude, originalCamera.centerCoordinate.longitude, accuracy: 0.0000001)
            XCTAssertEqual(map.camera.altitude, originalCamera.altitude, accuracy: 0.001)
            XCTAssertEqual(map.camera.heading, originalCamera.heading, accuracy: 0.001)
            XCTAssertEqual(map.camera.pitch, originalCamera.pitch, accuracy: 0.001)
            XCTAssertEqual(map.selectableMapFeatures, [.pointsOfInterest])
            XCTAssertTrue(map.isPitchEnabled)
            XCTAssertTrue(map.isRotateEnabled)
        }
    }

    func testUnrelatedNativeMapConsumerDoesNotAdoptBasemapPreference() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let existingConfiguration = map.preferredConfiguration
        let parent = makeMap(isDark: false)
        let coordinator = parent.makeCoordinator()

        coordinator.update(parent: parent, mapView: map)

        XCTAssertNil(parent.coloredMap)
        XCTAssertTrue(map.overlays.isEmpty)
        XCTAssertTrue(map.preferredConfiguration === existingConfiguration)
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 34.082, longitude: -118.267)
    }

    private func makeMap(isDark: Bool, coloredMap: Bool? = nil) -> NativeMapView {
        NativeMapView(
            attributionBottomClearance: 0,
            isInteractionEnabled: true,
            annotations: [NativeMapAnnotationDescriptor(
                id: "basemap-fixture", kind: .saved("basemap-fixture"), title: "Fixture place", emoji: "☕️",
                coordinate: coordinate, outlines: [], isSearchResult: false, isSelected: false,
                opacity: 1, animatesEntrance: false, entranceDelay: 0,
                accessibilityLabel: "Fixture place", bounceRevision: 0
            )],
            cameraRequest: NativeMapCameraRequest(
                region: MKCoordinateRegion(center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.04)),
                revision: 1, animated: false
            ),
            nativeFeatureClearRevision: 0,
            showsUserLocation: false,
            isDark: isDark,
            reduceMotion: true,
            onAnnotationTap: { _ in },
            onEmptyMapTap: {},
            onLongPress: { _ in },
            onNativeFeatureSelection: { _ in },
            onUserInteraction: {},
            onCameraChange: { _ in },
            onCameraInteractionEnd: { _, _ in },
            coloredMap: coloredMap
        )
    }
}
