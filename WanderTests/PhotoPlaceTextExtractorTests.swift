import XCTest
@testable import Wander

final class PhotoPlaceTextExtractorTests: XCTestCase {
    func testPrefersPlaceLikeLineOverReceiptNoise() {
        let query = PhotoPlaceTextExtractor.searchQuery(
            from: """
            Receipt
            ORDER 1042
            Lake Shrine
            Total $12.44
            """
        )

        XCTAssertEqual(query, "Lake Shrine")
    }

    func testBuildsRankedQueriesWithNearbyAddressContext() {
        let queries = PhotoPlaceTextExtractor.searchQueries(
            from: """
            Photos
            Directions
            Heavy Handed
            2912 Main St
            Santa Monica, CA
            4.6 (321)
            Open now
            """
        )

        XCTAssertEqual(queries.first, "Heavy Handed")
        XCTAssertTrue(queries.contains("Heavy Handed 2912 Main St"))
        XCTAssertFalse(queries.contains("Directions"))
        XCTAssertFalse(queries.contains("4.6 (321)"))
    }

    func testTriesMoreThanOneLikelyPlaceLine() {
        let queries = PhotoPlaceTextExtractor.searchQueries(
            from: """
            Apple Maps
            Search
            Top result
            Botanica Restaurant
            El Matador State Beach
            Malibu, CA
            Share
            """
        )

        XCTAssertTrue(queries.contains("Botanica Restaurant"))
        XCTAssertTrue(queries.contains("El Matador State Beach"))
        XCTAssertTrue(queries.contains("El Matador State Beach Malibu, CA"))
        XCTAssertFalse(queries.contains("Search"))
        XCTAssertFalse(queries.contains("Share"))
    }

    func testRejectsPureReceiptLines() {
        let query = PhotoPlaceTextExtractor.searchQuery(
            from: """
            Receipt
            Total $12.44
            VISA 4242
            """
        )

        XCTAssertNil(query)
    }
}
