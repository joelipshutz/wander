import XCTest
@testable import Wander

final class FullPageBackSwipeTests: XCTestCase {
    func testOnlyRightwardHorizontalIntentBegins() {
        XCTAssertTrue(FullPageBackSwipePolicy.canBegin(velocity: CGPoint(x: 300, y: 80)))
        for velocity in [CGPoint.zero, CGPoint(x: -200, y: 0), CGPoint(x: 80, y: 300), CGPoint(x: 100, y: -100)] {
            XCTAssertFalse(FullPageBackSwipePolicy.canBegin(velocity: velocity))
        }
    }

    func testCompletionScalesToThePageAndAllowsDeliberateFlicks() {
        for width in [CGFloat(375), CGFloat(430)] {
            XCTAssertFalse(FullPageBackSwipePolicy.shouldComplete(translation: width * 0.2, velocity: 0, width: width))
            XCTAssertTrue(FullPageBackSwipePolicy.shouldComplete(translation: width * 0.31, velocity: 0, width: width))
            XCTAssertTrue(FullPageBackSwipePolicy.shouldComplete(translation: 30, velocity: 700, width: width))
        }
        XCTAssertFalse(FullPageBackSwipePolicy.shouldComplete(translation: 10, velocity: 900, width: 430))
        XCTAssertFalse(FullPageBackSwipePolicy.shouldComplete(translation: -30, velocity: 900, width: 430))
        XCTAssertFalse(FullPageBackSwipePolicy.shouldComplete(translation: 200, velocity: 0, width: 0))
    }
}
