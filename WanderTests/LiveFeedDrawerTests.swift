import XCTest
@testable import Wander

final class LiveFeedDrawerTests: XCTestCase {
    func testHeightTracksEveryDragSampleInBothDirections() {
        let upward: [CGFloat] = [0, -1, -12, -40, -100]
        XCTAssertEqual(upward.map { LiveDrawerDragPolicy.height(base: 300, translation: $0, minimum: 80, maximum: 700) },
                       [300, 301, 312, 340, 400])
        let downward: [CGFloat] = [0, 1, 12, 40, 100]
        XCTAssertEqual(downward.map { LiveDrawerDragPolicy.height(base: 300, translation: $0, minimum: 80, maximum: 700) },
                       [300, 299, 288, 260, 200])
    }

    func testHeightClampsAtBothEndsWithoutOvershooting() {
        XCTAssertEqual(LiveDrawerDragPolicy.height(base: 300, translation: 1_000, minimum: 80, maximum: 700), 80)
        XCTAssertEqual(LiveDrawerDragPolicy.height(base: 300, translation: -1_000, minimum: 80, maximum: 700), 700)
        XCTAssertEqual(LiveDrawerDragPolicy.height(base: 80, translation: -10, minimum: 80, maximum: 700), 90)
        XCTAssertEqual(LiveDrawerDragPolicy.height(base: 700, translation: 10, minimum: 80, maximum: 700), 690)
    }

    func testReleaseAdvancesOneDetentInEitherDirectionAndClamps() {
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -80, predicted: -120), 1)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -80, predicted: -120), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: -80, predicted: -120), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 80, predicted: 120), 1)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 80, predicted: 120), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: 80, predicted: 120), 0)
    }

    func testShortDragsStayPutWhileIntentionalFlickUsesProjectedTravel() {
        for start in 0...2 {
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: start, translation: 23, predicted: 10), start)
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: start, translation: -23, predicted: -10), start)
        }
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -4, predicted: -24), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 4, predicted: 24), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -30, predicted: -5), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 30, predicted: 5), 0)
    }
}
