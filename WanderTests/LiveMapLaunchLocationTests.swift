import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class LiveMapLaunchLocationTests: XCTestCase {
    func testCurrentLocationReplacesDistantHistoryAndStaysLocalWithoutActivity() async throws {
        let history = makeHistory()
        history.remember(CLLocation(latitude: 34.0522, longitude: -118.2437))
        let provider = DeferredLocation()
        let launch = LiveMapLaunchLocation(history: history, provider: provider, useFixtures: false)
        let task = Task { await launch.resolve() }
        await provider.waitUntilRequested()
        provider.deliver(CLLocation(latitude: 40.7128, longitude: -74.0060))
        let resolved = await task.value
        let region = try XCTUnwrap(resolved)
        XCTAssertEqual(region.center.latitude, 40.7128, accuracy: 0.00001)
        XCTAssertEqual(region.center.longitude, -74.0060, accuracy: 0.00001)
        XCTAssertLessThan(region.span.latitudeDelta, 0.15)
        let repeated = await launch.resolve()
        XCTAssertNil(repeated, "Repeated renders must not recenter the map")
    }

    func testFallbackIsHistoryThenOceanParkAndNeverALiveDot() async throws {
        let history = makeHistory()
        let missing = LiveMapLaunchLocation(history: history, provider: UnavailableLocation(), useFixtures: false)
        let missingRegion = await missing.resolve()
        XCTAssertEqual(try XCTUnwrap(missingRegion).center.latitude, MapLaunchLocationResolver.oceanPark.latitude)
        history.remember(CLLocation(latitude: 47.6062, longitude: -122.3321))
        let remembered = LiveMapLaunchLocation(history: history, provider: UnavailableLocation(), useFixtures: false)
        let rememberedRegion = await remembered.resolve()
        XCTAssertEqual(try XCTUnwrap(rememberedRegion).center.latitude, 47.6062)
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            XCTAssertFalse(LiveMapLaunchLocation.showsUserLocation(status))
        }
        for status in [CLAuthorizationStatus.authorizedAlways, .authorizedWhenInUse] {
            XCTAssertTrue(LiveMapLaunchLocation.showsUserLocation(status))
        }
    }

    func testInteractionAndForegroundResetRejectLateLocations() async {
        let provider = DeferredLocation()
        let launch = LiveMapLaunchLocation(history: makeHistory(), provider: provider, useFixtures: false)
        let first = Task { await launch.resolve() }
        await provider.waitUntilRequested()
        launch.userDidChooseCamera()
        provider.deliver(CLLocation(latitude: 40, longitude: -74))
        let afterInteraction = await first.value
        XCTAssertNil(afterInteraction)
        let repeated = await launch.resolve()
        XCTAssertNil(repeated)

        launch.reset()
        let second = Task { await launch.resolve() }
        await provider.waitUntilRequested()
        launch.reset()
        provider.deliver(CLLocation(latitude: 41, longitude: -73))
        let obsoleteActivation = await second.value
        XCTAssertNil(obsoleteActivation)
        let third = Task { await launch.resolve() }
        await provider.waitUntilRequested()
        provider.deliver(CLLocation(latitude: 42, longitude: -72))
        let nextActivation = await third.value
        XCTAssertEqual(nextActivation?.center.latitude, 42)
    }

    func testForegroundPreservesExplicitAreaOrNearbyScope() async {
        let launch = LiveMapLaunchLocation(history: makeHistory(), provider: UnavailableLocation(), useFixtures: false)
        _ = await launch.resolve()
        launch.userDidChooseCamera()
        launch.reset()
        let scoped = await launch.resolve(hasExplicitGeographicScope: true)
        XCTAssertNil(scoped, "A current-location camera must not replace a still-committed area or Nearby query")
        let unscoped = await launch.resolve(hasExplicitGeographicScope: false)
        XCTAssertNotNil(unscoped)
    }

    func testPermissionGrantRetriesFallbackAndCancellationCannotMoveCamera() async {
        let launch = LiveMapLaunchLocation(history: makeHistory(), provider: UnavailableLocation(), useFixtures: false)
        launch.updateAuthorization(.denied)
        let deniedFallback = await launch.resolve()
        XCTAssertNotNil(deniedFallback)
        launch.updateAuthorization(.denied)
        let unchangedPermission = await launch.resolve()
        XCTAssertNil(unchangedPermission)
        launch.updateAuthorization(.authorizedWhenInUse)
        let grantedRetry = await launch.resolve()
        XCTAssertNotNil(grantedRetry)

        let provider = DeferredLocation()
        let pending = LiveMapLaunchLocation(history: makeHistory(), provider: provider, useFixtures: false)
        let task = Task { await pending.resolve() }
        await provider.waitUntilRequested()
        task.cancel()
        provider.deliver(CLLocation(latitude: 40, longitude: -74))
        let cancelled = await task.value
        XCTAssertNil(cancelled)
    }

    private func makeHistory() -> LastSharedLocationStore {
        let suite = "LiveMapLaunchLocationTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return LastSharedLocationStore(defaults: UserDefaults(suiteName: suite)!)
    }
}

@MainActor
private final class DeferredLocation: CurrentLocationProviding {
    private var continuation: CheckedContinuation<CLLocation, Never>?
    private var requested = XCTestExpectation(description: "Location requested")
    func currentLocation() async throws -> CLLocation {
        await withCheckedContinuation {
            continuation = $0
            requested.fulfill()
        }
    }
    func waitUntilRequested() async {
        let result = await XCTWaiter.fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(result, .completed)
    }
    func deliver(_ location: CLLocation) {
        let pending = continuation
        continuation = nil
        requested = XCTestExpectation(description: "Location requested")
        pending?.resume(returning: location)
    }
}

@MainActor
private struct UnavailableLocation: CurrentLocationProviding {
    func currentLocation() async throws -> CLLocation { throw PlaceResolutionError.locationUnavailable }
}
