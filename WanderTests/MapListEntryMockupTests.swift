#if DEBUG
import XCTest
@testable import Wander

final class MapListEntryMockupTests: XCTestCase {
    func testEveryMockupPageResolvesFromLaunchArguments() {
        for page in MapListEntryMockupPage.allCases {
            XCTAssertEqual(
                MapListEntryMockupPage.resolved(
                    from: ["Wander", "-WanderMapListEntryMockup", page.rawValue]
                ),
                page
            )
        }
    }

    func testMockupResolverFallsBackToCardEntryForMissingOrInvalidPage() {
        XCTAssertNil(MapListEntryMockupPage.resolved(from: ["Wander"]))
        XCTAssertEqual(
            MapListEntryMockupPage.resolved(from: ["Wander", "-WanderMapListEntryMockup"]),
            .cardEntry
        )
        XCTAssertEqual(
            MapListEntryMockupPage.resolved(
                from: ["Wander", "-WanderMapListEntryMockup", "not-a-page"]
            ),
            .cardEntry
        )
    }
}
#endif
