import XCTest
@testable import Wander

final class ProfileMetadataTagParserTests: XCTestCase {
    func testParsesStringAndArrayTags() {
        XCTAssertEqual(ProfileMetadataTagParser.tags(from: "\"date night\""), ["date night"])
        XCTAssertEqual(ProfileMetadataTagParser.tags(from: "[\"workable cafe\", \"patio\"]"), ["patio", "workable cafe"])
        XCTAssertEqual(ProfileMetadataTagParser.uniqueTags([" Patio ", "patio", "date night"]), ["date night", "Patio"])
    }
}
