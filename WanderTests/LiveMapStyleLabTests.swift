#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import Wander

final class LiveMapStyleLabTests: XCTestCase {
    private let fixture = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
                           "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture"]

    func testEveryVariantRequiresAllFixtureGuards() {
        for style in LiveMapStyleLab.allCases {
            let option = ["-WanderLiveMapStyle", style.rawValue]
            XCTAssertEqual(LiveMapStyleLab.resolve(arguments: fixture + option), style)
            for missing in fixture {
                XCTAssertNil(LiveMapStyleLab.resolve(arguments: fixture.filter { $0 != missing } + option))
            }
            XCTAssertNil(LiveMapStyleLab.resolve(arguments: option))
            XCTAssertNil(LiveMapStyleLab.resolve(arguments: fixture + option + ["-WanderUseLiveAuth"]))
        }
    }

    func testNormalAndMalformedLaunchesKeepProductionDefault() {
        XCTAssertNil(LiveMapStyleLab.resolve(arguments: []))
        XCTAssertNil(LiveMapStyleLab.resolve(arguments: fixture))
        XCTAssertNil(LiveMapStyleLab.resolve(arguments: fixture + ["-WanderLiveMapStyle"]))
        XCTAssertNil(LiveMapStyleLab.resolve(arguments: fixture + ["-WanderLiveMapStyle", "unknown"]))
    }
}
#endif
