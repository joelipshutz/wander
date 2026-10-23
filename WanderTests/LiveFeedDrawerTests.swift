import XCTest
@testable import Wander

final class LiveFeedDrawerTests: XCTestCase {
    private let heights: [CGFloat] = [80, 390, 780]
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
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -80, predicted: -120, heights: heights), 1)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -80, predicted: -120, heights: heights), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: -80, predicted: -120, heights: heights), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 80, predicted: 120, heights: heights), 1)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 80, predicted: 120, heights: heights), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: 80, predicted: 120, heights: heights), 0)
    }

    func testShortDragsStayPutWhileIntentionalFlickUsesProjectedTravel() {
        for start in 0...2 {
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: start, translation: 23, predicted: 10, heights: heights), start)
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: start, translation: -23, predicted: -10, heights: heights), start)
        }
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -4, predicted: -24, heights: heights), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 4, predicted: 24, heights: heights), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -30, predicted: -5, heights: heights), 1)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 30, predicted: 5, heights: heights), 1)
    }

    func testShortHighVelocityFlickNeverSkipsTheNextDetent() {
        for projected: CGFloat in [300, 900, 5_000] {
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -56, predicted: -projected, heights: heights), 1)
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 56, predicted: projected, heights: heights), 1)
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -56, predicted: -projected, heights: heights), 2)
            XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 56, predicted: projected, heights: heights), 0)
        }
    }

    func testLongDragChoosesADetentBeyondTheFingerInsteadOfReturningTowardItsStart() {
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -600, predicted: -650, heights: heights), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 600, predicted: 650, heights: heights), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -250, predicted: -280,
                                                  heights: [100, 300, 500]), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 250, predicted: 280,
                                                  heights: [100, 300, 500]), 0)
    }

    func testReleaseFlickWinsAgainstAnEarlierLongDragInTheOtherDirection() {
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: 160, predicted: 80, heights: heights), 1,
                       "An upward release expands even when the drag started downward.")
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -160, predicted: -80, heights: heights), 1,
                       "A downward release collapses even when the drag started upward.")
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 2, translation: 160, predicted: 80, heights: heights), 2)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 0, translation: -160, predicted: -80, heights: heights), 0)
        XCTAssertEqual(LiveDrawerDragPolicy.target(start: 1, translation: -80, predicted: -75, heights: heights), 2,
                       "A small release wobble must not overturn a deliberate drag.")
    }
}
