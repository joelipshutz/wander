import XCTest
@testable import Wander

final class CheckInCopyTests: XCTestCase {
    func testCheckInVocabularyIsConsistent() {
        XCTAssertEqual(CheckInCopy.verb, "check in")
        XCTAssertEqual(CheckInCopy.noun, "check-in")
        XCTAssertEqual(CheckInCopy.pluralNoun, "check-ins")
        XCTAssertEqual(CheckInCopy.pastTense, "checked in")
        XCTAssertEqual(CheckInCopy.count(1), "1 check-in")
        XCTAssertEqual(CheckInCopy.count(2), "2 check-ins")
        XCTAssertEqual(PlaceStatus.been.displayTitle, "check-in")
    }

    func testBeenRemainsThePersistenceValue() {
        XCTAssertEqual(PlaceStatus.been.rawValue, "been")
        XCTAssertEqual(try? JSONEncoder().encode(PlaceStatus.been), Data(#""been""#.utf8))
    }
}
