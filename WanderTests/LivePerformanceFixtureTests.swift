#if DEBUG && targetEnvironment(simulator)
import MapKit
import XCTest
@testable import Wander

@MainActor
final class LivePerformanceFixtureTests: XCTestCase {
    private let liveArguments = ["-WanderLivePerformanceUITest", "-WanderUsePerformanceFixtures",
        "-WanderAuthenticatedUITest", "-WanderUnifiedLiveUITest"]

    func testScaleFeedAndFakeAuthRequireEveryExplicitFlagAndSimulator() {
        XCTAssertTrue(LivePerformanceUITestPolicy.isEnabled(arguments: liveArguments, isSimulator: true))
        XCTAssertEqual(SimulatorTestSessionPolicy.authenticatedFixtureUserID(
            arguments: liveArguments, isSimulator: true), LivePerformanceUITestPolicy.currentUserID)
        for missing in liveArguments {
            let incomplete = liveArguments.filter { $0 != missing }
            XCTAssertFalse(LivePerformanceUITestPolicy.isEnabled(arguments: incomplete, isSimulator: true), missing)
            XCTAssertEqual(SimulatorTestSessionPolicy.authenticatedFixtureUserID(
                arguments: incomplete, isSimulator: true), "user_joe", missing)
        }
        XCTAssertFalse(LivePerformanceUITestPolicy.isEnabled(arguments: liveArguments, isSimulator: false))
        XCTAssertEqual(SimulatorTestSessionPolicy.authenticatedFixtureUserID(
            arguments: liveArguments, isSimulator: false), "user_joe")
        XCTAssertFalse(LivePerformanceUITestPolicy.isEnabled(arguments: [], isSimulator: true))
        XCTAssertEqual(SimulatorTestSessionPolicy.authenticatedFixtureUserID(
            arguments: [], isSimulator: true), "user_joe")
    }

    func testNativePinCameraAccessibilityPreservesBaseValueAndRequiresExactFixturePolicy() throws {
        let map = MKMapView(frame: .init(x: 0, y: 0, width: 390, height: 700))
        let pin = LiveNativePinView(annotation: nil, reuseIdentifier: nil)
        pin.performanceTestMap = map
        let center = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        for base in ["Category pin", "Map dot"] {
            pin.accessibilityValue = base
            XCTAssertEqual(pin.accessibilityValue, base)
            for missing in liveArguments {
                XCTAssertEqual(pin.performanceTestAccessibilityValue(
                    arguments: liveArguments.filter { $0 != missing }, isSimulator: true), base, missing)
            }
            XCTAssertEqual(pin.performanceTestAccessibilityValue(arguments: liveArguments, isSimulator: false), base)
            XCTAssertEqual(pin.performanceTestAccessibilityValue(arguments: [], isSimulator: true), base)
            let prefix = "\(base)|live.performance.cameraDistanceMeters="
            for distance in [6_000.0, 3_000.0] {
                map.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: distance, pitch: 0, heading: 0),
                    animated: false)
                let actualDistance = map.camera.centerCoordinateDistance
                let value = try XCTUnwrap(pin.performanceTestAccessibilityValue(
                    arguments: liveArguments, isSimulator: true))
                XCTAssertTrue(value.hasPrefix(prefix))
                XCTAssertEqual(Double(value.dropFirst(prefix.count)), actualDistance)
                XCTAssertEqual(map.camera.centerCoordinateDistance, actualDistance,
                    "Reading fixture evidence must not issue a camera command.")
            }
            XCTAssertEqual(pin.accessibilityValue, base)
        }
        pin.prepareForReuse()
        XCTAssertNil(pin.performanceTestMap)
        XCTAssertEqual(pin.performanceTestAccessibilityValue(arguments: liveArguments, isSimulator: true), pin.accessibilityValue)
    }

    func testLargeLiveFixtureHasSixHundredRecentEventsAtThreeHundredDistinctPlaces() {
        let store = WanderStore(fixtures: .performanceScale())
        XCTAssertEqual(SimulatorTestSessionPolicy.authenticatedFixtureUserID(
            arguments: liveArguments, isSimulator: true), store.currentUser.id,
            "Preview hydration must see the same authenticated user as the fixture store.")
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let source = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
        let originalCoordinates = source.map { [$0.place.latitude, $0.place.longitude] }
        let page = store.livePerformanceFixtureFeedPage(from: source, relativeTo: date)
        XCTAssertEqual(page.activity.count, 600)
        XCTAssertEqual(Set(page.activity.map(\.id)).count, 600)
        XCTAssertEqual(Set(page.activity.compactMap { $0.place?.place.id }).count, 300)
        XCTAssertEqual(FeedPresentation.groupedActivity(page.activity, relativeTo: date).count, 600)
        let query = LiveFeedQuery(occurredAfter: date.addingTimeInterval(-86_400), occurredBefore: date,
                                 center: .init(latitude: 34.075, longitude: -118.285), radiusMeters: 5_000)
        XCTAssertTrue(page.activity.allSatisfy(query.includes))
        XCTAssertTrue(page.activity.allSatisfy(store.canDisplayLiveMapActivity))
        let pins = LiveMapProjection.pins(activities: page.activity, featured: [])
        XCTAssertEqual(pins.count, 300)
        XCTAssertTrue(pins.allSatisfy { $0.activities.count == 2 })
        XCTAssertEqual(source.map { [$0.place.latitude, $0.place.longitude] }, originalCoordinates,
                       "Scale review must not rewrite account places or persisted coordinates.")
        XCTAssertNil(page.nextCursor)
    }
}
#endif
