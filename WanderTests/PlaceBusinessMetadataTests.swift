import XCTest
@testable import Wander

final class PlaceBusinessMetadataTests: XCTestCase {
    func testMatcherSelectsNearbyExactPlaceWithBusinessMetadata() throws {
        let request = PlaceBusinessMetadataRequest(
            placeID: "place_anajak",
            name: "Anajak Thai",
            address: "14704 Ventura Blvd",
            locality: "Sherman Oaks",
            region: "CA",
            latitude: 34.15182,
            longitude: -118.45363,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit_anajak_thai"
        )
        let candidates = [
            PlaceBusinessMetadataCandidate(
                name: "Anajak Thai",
                address: "14704 Ventura Blvd",
                locality: "Sherman Oaks",
                region: "CA",
                latitude: 34.15181,
                longitude: -118.45362,
                websiteURLString: "https://www.anajakthai.com",
                phoneNumber: "+1 (818) 501-4201",
                timeZoneIdentifier: "America/Los_Angeles"
            ),
            PlaceBusinessMetadataCandidate(
                name: "Anajak Thai",
                address: "1 Wrong Way",
                locality: "San Diego",
                region: "CA",
                latitude: 32.7157,
                longitude: -117.1611,
                websiteURLString: "https://wrong.example",
                phoneNumber: "+1 619 555 0100",
                timeZoneIdentifier: "America/Los_Angeles"
            )
        ]

        let match = try XCTUnwrap(PlaceBusinessMetadataMatcher.bestCandidate(for: request, from: candidates))

        XCTAssertEqual(match.websiteURLString, "https://www.anajakthai.com")
        XCTAssertEqual(match.phoneNumber, "+1 (818) 501-4201")
    }

    func testMatcherRejectsDifferentNearbyBusiness() {
        let request = PlaceBusinessMetadataRequest(
            placeID: "place_anajak",
            name: "Anajak Thai",
            address: "14704 Ventura Blvd",
            locality: "Sherman Oaks",
            region: "CA",
            latitude: 34.15182,
            longitude: -118.45363,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: nil
        )
        let candidates = [
            PlaceBusinessMetadataCandidate(
                name: "Nearby Thai Cafe",
                address: "14710 Ventura Blvd",
                locality: "Sherman Oaks",
                region: "CA",
                latitude: 34.15183,
                longitude: -118.45360,
                websiteURLString: "https://nearby.example",
                phoneNumber: "+1 818 555 0100",
                timeZoneIdentifier: "America/Los_Angeles"
            )
        ]

        XCTAssertNil(PlaceBusinessMetadataMatcher.bestCandidate(for: request, from: candidates))
    }

    func testRecoveredMetadataFillsOnlyMissingOrInvalidValues() {
        let stored = PlaceBusinessMetadata(
            websiteURLString: "not a website",
            phoneNumber: "+1 (310) 555-0199",
            timeZoneIdentifier: nil
        )
        let recovered = PlaceBusinessMetadata(
            websiteURLString: "https://www.anajakthai.com",
            phoneNumber: "+1 (818) 501-4201",
            timeZoneIdentifier: "America/Los_Angeles"
        )

        let merged = stored.mergingMissingValues(from: recovered)

        XCTAssertEqual(merged.websiteURLString, "https://www.anajakthai.com")
        XCTAssertEqual(merged.phoneNumber, "+1 (310) 555-0199")
        XCTAssertEqual(merged.timeZoneIdentifier, "America/Los_Angeles")
    }
}
