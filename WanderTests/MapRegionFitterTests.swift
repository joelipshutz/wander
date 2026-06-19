import CoreLocation
import XCTest
@testable import Wander

final class MapRegionFitterTests: XCTestCase {
    func testFitsMultipleCoordinatesWithPadding() {
        let region = MapRegionFitter.region(
            fitting: [
                CLLocationCoordinate2D(latitude: 34.0, longitude: -118.3),
                CLLocationCoordinate2D(latitude: 34.1, longitude: -118.1)
            ]
        )

        XCTAssertEqual(region?.center.latitude ?? 0, 34.05, accuracy: 0.0001)
        XCTAssertEqual(region?.center.longitude ?? 0, -118.2, accuracy: 0.0001)
        XCTAssertGreaterThan(region?.span.latitudeDelta ?? 0, 0.1)
        XCTAssertGreaterThan(region?.span.longitudeDelta ?? 0, 0.2)
    }

    func testSingleCoordinateUsesMinimumSpan() {
        let region = MapRegionFitter.region(
            fitting: [CLLocationCoordinate2D(latitude: 34.0, longitude: -118.3)]
        )

        XCTAssertEqual(region?.span.latitudeDelta, 0.025)
        XCTAssertEqual(region?.span.longitudeDelta, 0.025)
    }
}
