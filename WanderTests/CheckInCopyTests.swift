import XCTest
@testable import Wander

final class CheckInCopyTests: XCTestCase {
    func testCheckInVocabularyIsConsistent() {
        XCTAssertEqual(CheckInCopy.verb, "Check In")
        XCTAssertEqual(CheckInCopy.action, "Check In")
        XCTAssertEqual(CheckInCopy.pluralTitle, "Check-Ins")
        XCTAssertEqual(CheckInCopy.noun, "Check-In")
        XCTAssertEqual(CheckInCopy.pluralNoun, "Check-Ins")
        XCTAssertEqual(CheckInCopy.pastTense, "Checked In")
        XCTAssertEqual(CheckInCopy.count(1), "1 Check-In")
        XCTAssertEqual(CheckInCopy.count(2), "2 Check-Ins")
        XCTAssertEqual(PlaceStatus.been.displayTitle, "Check-In")
    }

    func testBeenRemainsThePersistenceValue() {
        XCTAssertEqual(PlaceStatus.been.rawValue, "been")
        XCTAssertEqual(try? JSONEncoder().encode(PlaceStatus.been), Data(#""been""#.utf8))
    }
}
