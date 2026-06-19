import XCTest
@testable import Wander

final class ProfileMetadataTagParserTests: XCTestCase {
    func testParsesStringAndArrayTags() {
        XCTAssertEqual(ProfileMetadataTagParser.tags(from: "\"date night\""), ["date night"])
        XCTAssertEqual(ProfileMetadataTagParser.tags(from: "[\"workable cafe\", \"patio\"]"), ["workable cafe", "patio"])
    }
}
