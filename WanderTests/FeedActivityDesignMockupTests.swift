#if DEBUG
import XCTest
@testable import Wander

final class FeedActivityDesignMockupTests: XCTestCase {
    func testLaunchArgumentRoutesToEveryFeedDesignDirection() {
        for page in FeedActivityDesignMockupPage.allCases {
            XCTAssertEqual(
                FeedActivityDesignMockupPage.resolved(
                    from: ["Wander", "-WanderFeedDesignMockup", page.rawValue]
                ),
                page
            )
        }
    }

    func testLaunchArgumentFallsBackToControlForMissingOrUnknownDirection() {
        XCTAssertNil(FeedActivityDesignMockupPage.resolved(from: ["Wander"]))
        XCTAssertEqual(
            FeedActivityDesignMockupPage.resolved(
                from: ["Wander", "-WanderFeedDesignMockup"]
            ),
            .control
        )
        XCTAssertEqual(
            FeedActivityDesignMockupPage.resolved(
                from: ["Wander", "-WanderFeedDesignMockup", "unknown"]
            ),
            .control
        )
    }
}
#endif
