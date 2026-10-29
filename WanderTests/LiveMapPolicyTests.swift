import XCTest
import MapKit
import SwiftUI
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
    func testColdStartWaitsForLiveFlagBeforeMountingTabs() async throws {
        for size in [CGSize(width: 393, height: 852), CGSize(width: 375, height: 812)] {
            try await verifyColdStart(size: size, remoteValue: true, capture: true)
        }
    }

    @MainActor
    func testColdStartOffAndFailedRequestOpenLegacyTabs() async throws {
        try await verifyColdStart(remoteValue: false)
        try await verifyColdStart(remoteValue: nil)
    }

    @MainActor
    func testOfflineLaunchDoesNotWaitForAFlagRequestItCannotStart() async throws {
        try await verifyColdStart(remoteValue: true, isSessionValidated: false)
    }

    @MainActor
    func testDeviceOverridesOpenImmediatelyWhileRemoteFlagIsPending() async throws {
        try await verifyColdStart(remoteValue: false, deviceValue: true)
        try await verifyColdStart(remoteValue: true, deviceValue: false)
    }

    func testResolvedLaunchDoesNotWaitAgainOrLeakItsChoiceToAnotherAccount() {
        var launch = LiveExperienceLaunchPolicy()
        launch.resolve(for: "a", flag: .init(isEnabled: true, source: .globalDefault), isolatedSimulatorReview: false)
        XCTAssertFalse(launch.isAwaitingResolution(for: "a", flag: nil, canRefresh: true, isolatedSimulatorReview: false))
        XCTAssertTrue(launch.isAwaitingResolution(for: "b", flag: nil, canRefresh: true, isolatedSimulatorReview: false))
        XCTAssertFalse(launch.isAwaitingResolution(for: "b", flag: nil, canRefresh: false, isolatedSimulatorReview: false))
        XCTAssertFalse(launch.isAwaitingResolution(for: "b", flag: nil, canRefresh: true, isolatedSimulatorReview: true))
    }

    @MainActor
    private func verifyColdStart(
        size: CGSize = CGSize(width: 393, height: 852),
        remoteValue: Bool?,
        deviceValue: Bool? = nil,
        isSessionValidated: Bool = true,
        capture: Bool = false
    ) async throws {
        // UI tests persist demo mode across launches. This fixture exercises the
        // real cold-start flag path, then restores the simulator's prior mode.
        let hadDemoSession = SimulatorTestSessionPolicy.isActive(arguments: [])
        _ = SimulatorTestSessionPolicy.isActive(arguments: [SimulatorTestSessionPolicy.liveAuthArgument])
        defer {
            if hadDemoSession {
                _ = SimulatorTestSessionPolicy.isActive(arguments: [SimulatorTestSessionPolicy.authenticatedFixtureArgument])
            }
        }
        XCTAssertEqual(WanderRootView.resolvedFixtureMode(), .empty)
        let flags = SuspendedLiveFlagRepository(value: remoteValue)
        let session = AuthSession(userID: "cold_start_test", displayName: nil, handle: nil)
        let authState: AuthState = isSessionValidated ? .signedIn(session) : .offline(session, message: "Offline")
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: authState))
        await auth.refreshSession()
        let overrides = deviceValue.map {
            [FeatureFlagOverrideStore.storageKey(for: .unifiedLiveV1, userID: session.userID): $0]
        } ?? [:]
        let backend = WanderBackend(featureFlagRepository: flags,
                                    featureFlagDeviceOverrides: FeatureFlagDeviceOverrideSnapshot(values: overrides))
        let store = WanderStore(fixtures: .seed())
        store.apply(authState: authState)
        let metros = HomeMetroSelectionStore()
        metros.remember("los-angeles", for: session.userID)
        defer { metros.remember(nil, for: session.userID) }
        let root = WanderRootView(
            initialTab: .discover, initialSession: session, isSessionValidated: isSessionValidated,
            storeFactory: { store },
            importStoreFactory: {
                PlaceImportStore(persistence: EphemeralPlaceImportPersistence(), resolver: DevicePlaceImportResolver())
            }
        )
        .environmentObject(auth)
        .environmentObject(backend)
        .environmentObject(PushNotificationManager())
        .environmentObject(ProductUpsellCoordinator())
        .environmentObject(CalendarReservationManager())
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.windowScene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            flags.complete()
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        if isSessionValidated {
            for _ in 0..<100 where flags.requestCount == 0 {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        XCTAssertEqual(flags.requestCount, isSessionValidated ? 1 : 0,
                       "The flag request must run while launch content is visible, but never while offline")
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        let legacyTabs = ["Map", "Feed", "Events", "Lists", "Profile"]
        if isSessionValidated && deviceValue == nil {
            XCTAssertNil(tabBar(in: host.view), "Pending is not Off: no legacy tabs may mount before resolution")
        } else {
            XCTAssertEqual(tabBar(in: host.view)?.items?.map(\.title),
                           deviceValue == true ? ["Live", "Lists", "Profile"] : legacyTabs)
        }
        if capture { attach(window, name: "cold-start-pending-\(Int(size.width))") }

        flags.complete()
        let enabled = deviceValue ?? (isSessionValidated && remoteValue == true)
        let expectedTabs = enabled ? ["Live", "Lists", "Profile"] : legacyTabs
        for _ in 0..<100 where tabBar(in: host.view)?.items?.map(\.title) != expectedTabs {
            try await Task.sleep(for: .milliseconds(50))
            host.view.layoutIfNeeded()
        }
        XCTAssertEqual(tabBar(in: host.view)?.items?.map(\.title), expectedTabs)
        if capture { attach(window, name: "cold-start-resolved-\(Int(size.width))") }
    }

    @MainActor
    private func tabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar { return tabBar }
        return view.subviews.lazy.compactMap { self.tabBar(in: $0) }.first
    }

    @MainActor
    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLiveActivityCopyKeepsPlaceBackedListUpdatesDistinctFromCheckIns() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.visiblePlaces().first { $0.userPlace.status == .been })
        let actor = store.shell(for: store.currentUser)
        let listUpdate = FeedActivity(id: "list-update", kind: .listItemAdded,
                                      actor: actor, place: place, occurredAt: .now)
        XCTAssertEqual(LiveActivityPresentation.title(for: listUpdate), "List update",
                       "Adding an already-visited place to a list is not another check-in.")
        let checkIn = FeedActivity(id: "check-in", kind: .placeBeen,
                                   actor: actor, place: place, occurredAt: .now)
        let wanna = FeedActivity(id: "wanna", kind: .placeWannaGo,
                                actor: actor, place: place, occurredAt: .now)
        XCTAssertEqual(LiveActivityPresentation.title(for: checkIn), "Check-in")
        XCTAssertEqual(LiveActivityPresentation.title(for: wanna), "Wanna")
    }

    func testLiveDrawerCountCopyUsesSingularOnlyForOneUpdate() {
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(0), "0 place updates")
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(1), "1 place update")
        XCTAssertEqual(LiveActivityPresentation.shownUpdateCount(2), "2 place updates")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(0), "0 loaded updates")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(1), "1 loaded update")
        XCTAssertEqual(LiveActivityPresentation.loadedUpdateCount(2), "2 loaded updates")
    }

    private func point(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

@MainActor
private final class SuspendedLiveFlagRepository: FeatureFlagRepository {
    private var continuation: CheckedContinuation<[FeatureFlagKey: ResolvedFeatureFlagValue], Error>?
    private let value: Bool?

    init(value: Bool?) { self.value = value }
    private(set) var requestCount = 0

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func complete() {
        if let value {
            continuation?.resume(returning: [.unifiedLiveV1: .init(isEnabled: value, source: .globalDefault)])
        } else {
            continuation?.resume(throwing: URLError(.notConnectedToInternet))
        }
        continuation = nil
    }
}
