import XCTest
import MapKit
@testable import Wander

final class LiveMapPolicyTests: XCTestCase {
    func testDrawnAreaIncludesBoundaryAndExcludesOutside() throws {
        let area = try XCTUnwrap(LiveDrawnArea(coordinates: [point(0, 0), point(0, 2), point(2, 2), point(2, 0)]))
        XCTAssertTrue(area.contains(point(1, 1)))
        XCTAssertTrue(area.contains(point(0, 1)))
        XCTAssertFalse(area.contains(point(3, 1)))
    }

    func testDateLineAreaDoesNotSelectOppositeSideOfWorld() throws {
        let area = try XCTUnwrap(LiveDrawnArea(coordinates: [point(0, 179), point(0, -179), point(2, -179), point(2, 179)]))
        XCTAssertTrue(area.contains(point(1, 179.5)))
        XCTAssertTrue(area.contains(point(1, -179.5)))
        XCTAssertFalse(area.contains(point(1, 0)))
    }

    func testInvalidDrawingRejectedAndConcaveDrawingPreserved() throws {
        XCTAssertNil(LiveDrawnArea(coordinates: [point(0, 0), point(0, 1)]))
        XCTAssertNil(LiveDrawnArea(coordinates: [point(0, 0), point(0, 1), point(0, 2)]))
        XCTAssertNil(LiveDrawnArea(coordinates: [point(91, 0), point(0, 1), point(1, 1)]))
        let area = try XCTUnwrap(LiveDrawnArea(coordinates: [point(0, 0), point(0, 3), point(1, 3), point(1, 1), point(3, 1), point(3, 0)]))
        XCTAssertTrue(area.contains(point(0.5, 2)))
        XCTAssertFalse(area.contains(point(2, 2)))
    }

    func testWideDrawingIsRejectedRegardlessOfStartingVertex() {
        let vertices = [point(-10, 0), point(-10, 120), point(10, -120)]
        for index in vertices.indices {
            XCTAssertNil(LiveDrawnArea(coordinates: Array(vertices[index...]) + Array(vertices[..<index])))
        }
    }

    func testSparseNetworkExpandsAndDenseNetworkIgnoresDistantOutlier() throws {
        let anchor = point(34, -118)
        let dense = (0..<9).map { point(34 + Double($0) * 0.001, -118) }
        let sparse = [anchor, point(35, -119)]
        let denseRegion = try XCTUnwrap(LiveMapCameraPolicy.region(coordinates: dense + [point(40, -74)], anchor: anchor))
        let sparseRegion = try XCTUnwrap(LiveMapCameraPolicy.region(coordinates: sparse, anchor: anchor))
        XCTAssertLessThan(denseRegion.span.latitudeDelta, sparseRegion.span.latitudeDelta)
        XCTAssertLessThan(denseRegion.span.latitudeDelta, 0.1)
        XCTAssertEqual(denseRegion.center.latitude, anchor.latitude, accuracy: 0.001)
    }

    func testNoActivityDoesNotInventLocation() {
        XCTAssertNil(LiveMapCameraPolicy.region(coordinates: [], anchor: nil))
    }

    func testThreeTabsAndLegacyDestinationMapping() {
        XCTAssertEqual(LiveNavigationPolicy.tabs, [.discover, .lists, .profile])
        XCTAssertEqual(LiveNavigationPolicy.tab(for: .map), .discover)
        XCTAssertEqual(LiveNavigationPolicy.tab(for: .events), .discover)
        XCTAssertEqual(LiveNavigationPolicy.tab(for: .profile), .profile)
        XCTAssertEqual(LiveNavigationPolicy.tab(for: .lists), .lists)
    }

    func testLiveConsumerRequiresEnablementAndReviewRespectsEveryExplicitOff() {
        XCTAssertFalse(LiveNavigationPolicy.isEnabled(nil, isolatedSimulatorReview: false))
        let bundled = ResolvedFeatureFlagValue(isEnabled: false, source: .bundledDefault)
        XCTAssertFalse(LiveNavigationPolicy.isEnabled(bundled, isolatedSimulatorReview: false))
        XCTAssertTrue(LiveNavigationPolicy.isEnabled(bundled, isolatedSimulatorReview: true))
        for source in [FeatureFlagValueSource.globalDefault, .accountOverride, .deviceOverride] {
            XCTAssertFalse(LiveNavigationPolicy.isEnabled(.init(isEnabled: false, source: source), isolatedSimulatorReview: true))
            XCTAssertTrue(LiveNavigationPolicy.isEnabled(.init(isEnabled: true, source: source), isolatedSimulatorReview: false))
        }
    }

    func testNavigationFlagWaitsForResolutionThenStaysFixedPerAccountUntilRelaunch() {
        var launch = LiveExperienceLaunchPolicy()
        launch.resolve(for: "a", flag: nil, isolatedSimulatorReview: false)
        XCTAssertNil(launch.value(for: "a"))
        launch.resolve(for: "a", flag: .init(isEnabled: true, source: .globalDefault), isolatedSimulatorReview: false)
        launch.resolve(for: "a", flag: .init(isEnabled: false, source: .globalDefault), isolatedSimulatorReview: false)
        XCTAssertEqual(launch.value(for: "a"), true)
        launch.resolve(for: "b", flag: .init(isEnabled: false, source: .deviceOverride), isolatedSimulatorReview: true)
        XCTAssertEqual(launch.value(for: "b"), false)
        var nextLaunch = LiveExperienceLaunchPolicy()
        nextLaunch.resolve(for: "a", flag: .init(isEnabled: false, source: .globalDefault), isolatedSimulatorReview: false)
        XCTAssertEqual(nextLaunch.value(for: "a"), false)
    }

    @MainActor
    func testLiveActivityCopyKeepsPlaceBackedListUpdatesDistinctFromCheckIns() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.visiblePlaces().first { $0.userPlace.status == .been })
        let actor = store.shell(for: store.currentUser)
        let listUpdate = FeedActivity(id: "list-update", kind: .listItemAdded,
                                      actor: actor, place: place, occurredAt: .now)
        XCTAssertEqual(LiveActivityPresentation.title(for: listUpdate), "List Update",
                       "Adding an already-visited place to a list is not another check-in.")
        let checkIn = FeedActivity(id: "check-in", kind: .placeBeen,
                                   actor: actor, place: place, occurredAt: .now)
        let wanna = FeedActivity(id: "wanna", kind: .placeWannaGo,
                                actor: actor, place: place, occurredAt: .now)
        XCTAssertEqual(LiveActivityPresentation.title(for: checkIn), "Check-In")
        XCTAssertEqual(LiveActivityPresentation.title(for: wanna), "Wanna")
    }

    func testLiveDrawerCountCopyUsesSingularOnlyForOneUpdate() {
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(0), "0 Place Updates")
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(1), "1 Place Update")
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(2), "2 Place Updates")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(0), "0 Loaded Updates")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(1), "1 Loaded Update")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(2), "2 Loaded Updates")
    }

    private func point(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
