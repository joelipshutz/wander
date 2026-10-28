#if DEBUG && targetEnvironment(simulator)
import MapKit
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

    @MainActor func testGrayscaleOverlayIsLimitedToExplicitReviewVariants() {
        XCTAssertEqual(Set(LiveMapStyleLab.allCases.filter(\.usesGrayscaleOverlay)),
                       Set([.graphite, .graphiteDark]))
        XCTAssertEqual(LiveMapStyleLab.graphite.colorScheme, .light)
        XCTAssertEqual(LiveMapStyleLab.graphiteDark.colorScheme, .dark)
        let bounds = LiveMapStyleLab.grayscalePolygon.boundingMapRect
        XCTAssertEqual(bounds.origin.x, MKMapRect.world.origin.x)
        XCTAssertEqual(bounds.origin.y, MKMapRect.world.origin.y)
        XCTAssertEqual(bounds.size.width, MKMapRect.world.size.width)
        XCTAssertEqual(bounds.size.height, MKMapRect.world.size.height)
    }
}
#endif
