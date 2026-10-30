import MapKit
import SwiftUI
import XCTest
@testable import Wander

@MainActor
final class LiveNativeMapPerformanceTests: XCTestCase {
    func testUnchangedNativeMapUpdatesBenchmark() {
        let owner = LocalProfile(localID: "perf-owner", handle: "fixture", displayName: "Fixture")
        let pins = (0..<1_000).map { index in
            let place = LocalPlace(localID: "perf-place-\(index)", canonicalName: "Fixture \(index)",
                category: "coffee", latitude: 34.07 + Double(index % 30) * 0.001,
                longitude: -118.28 + Double(index / 30) * 0.001)
            let save = LocalUserPlace(localID: "perf-save-\(index)", userID: owner.id,
                placeID: place.id, status: .been, visibility: .selfOnly, sourceType: "manual")
            return LivePlacePin(id: place.id,
                place: VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner), activities: [])
        }
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let parent = makeParent(pins: pins)
        let coordinator = parent.makeCoordinator()
        coordinator.attach(to: map)
        defer { coordinator.detach(from: map) }
        coordinator.update(parent: parent, map: map, animated: false)
        map.layoutIfNeeded()
        let original = map.annotations.filter { !($0 is MKUserLocation) }
        XCTAssertEqual(original.count, pins.count)
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<30 { coordinator.update(parent: parent, map: map, animated: false) }
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
        XCTAssertEqual(map.annotations.filter { !($0 is MKUserLocation) }.count, pins.count)
        XCTAssertTrue(original.allSatisfy { old in map.annotations.contains { $0 === old } })
        let report = "REC675 native_map pins=1000 updates=30 samples_ms=\(samples) median_ms=\(samples.sorted()[2])"
        let attachment = XCTAttachment(string: report)
        attachment.name = "REC675-native-map-benchmark"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }

    private func makeParent(pins: [LivePlacePin]) -> LiveNativeMap {
        LiveNativeMap(position: .constant(.region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.085, longitude: -118.265),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))),
            positionRevision: 0, proxy: LiveNativeMapProxy(), pins: pins, pinsRevision: UUID(),
            selectedID: nil, viewedPins: [:], brand: .editorialLight, coloredMap: false,
            drawing: false, contentInsets: EdgeInsets(), showsUserLocation: false,
            boundary: nil, nearbyCenter: nil, nearbyRadius: nil, nativeSelectionRevision: UUID(),
            onSelectPin: { _ in }, onNativeFeature: { _ in }, onCameraEnd: { _, _, _ in }, onInteraction: {})
    }
}
