import MapKit
import XCTest
@testable import Wander

@MainActor
final class LiveMapPlaceDiscoveryTests: XCTestCase {
    func testResolvedPlacePreservesProviderDetailsWithoutInventingSaveState() throws {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = "  Juniper Kitchen  "
        item.pointOfInterestCategory = .restaurant
        item.url = URL(string: "https://example.com/juniper")
        item.phoneNumber = "+1 555 0100"
        item.timeZone = TimeZone(identifier: "America/Los_Angeles")

        let candidate = try XCTUnwrap(LiveMapPlaceDiscovery.candidate(from: item))
        XCTAssertEqual(candidate.name, "Juniper Kitchen")
        XCTAssertEqual(candidate.rawProviderType, MKPointOfInterestCategory.restaurant.rawValue.lowercased())
        XCTAssertEqual(candidate.sourceProvider, "mapkit")
        XCTAssertEqual(candidate.sourceProviderPlaceID, candidate.id)
        XCTAssertEqual(candidate.latitude, coordinate.latitude)
        XCTAssertEqual(candidate.longitude, coordinate.longitude)
        XCTAssertEqual(candidate.websiteURLString, item.url?.absoluteString)
        XCTAssertEqual(candidate.phoneNumber, item.phoneNumber)
        XCTAssertEqual(candidate.timeZoneIdentifier, item.timeZone?.identifier)

        let presentation = PlaceSheetPlace(candidate: candidate)
        XCTAssertNil(presentation.status)
        XCTAssertNil(presentation.visibility)
        XCTAssertNil(presentation.noteOwnerID)
        XCTAssertNil(presentation.note)
    }

    func testFallbackAndResolvedPlaceUseExistingMapSearchIdentity() throws {
        let fallback = try XCTUnwrap(LiveMapPlaceDiscovery.candidate(title: "Juniper Kitchen",
            coordinate: coordinate, category: .restaurant))
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = "Juniper Kitchen"
        item.pointOfInterestCategory = .restaurant
        let resolved = try XCTUnwrap(LiveMapPlaceDiscovery.candidate(from: item))

        XCTAssertEqual(fallback.id, resolved.id)
        XCTAssertEqual(fallback.sourceProviderPlaceID, resolved.sourceProviderPlaceID)
        XCTAssertEqual(fallback.id, "mapkit_juniper_kitchen_3400000_-11800000")
        XCTAssertEqual(fallback.primaryCategory, resolved.primaryCategory)
    }

    func testFallbackRejectsMissingNamesAndInvalidCoordinates() {
        XCTAssertNil(LiveMapPlaceDiscovery.candidate(title: nil, coordinate: coordinate, category: nil))
        XCTAssertNil(LiveMapPlaceDiscovery.candidate(title: " \n ", coordinate: coordinate, category: nil))
        for invalid in [CLLocationCoordinate2D(latitude: 91, longitude: 0),
                        CLLocationCoordinate2D(latitude: 0, longitude: 181),
                        CLLocationCoordinate2D(latitude: .nan, longitude: 0),
                        CLLocationCoordinate2D(latitude: 0, longitude: .infinity)] {
            XCTAssertNil(LiveMapPlaceDiscovery.candidate(title: "Juniper Kitchen",
                coordinate: invalid, category: .restaurant))
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 34, longitude: -118)
    }
}
