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
