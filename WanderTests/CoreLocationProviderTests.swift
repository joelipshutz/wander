import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class CoreLocationProviderTests: XCTestCase {
    func testMapLaunchWithoutLocationHistoryUsesOceanParkWithoutPrompting() async throws {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            let history = makeHistory()
            let harness = Harness(status: status, history: history, purpose: .map)
            let resolver = MapLaunchLocationResolver(history: history, provider: harness.provider)
            let region = MapScreen.initialMapRegion(history: history, useFixtures: false)
            XCTAssertEqual(region.center.latitude, 34.0036, accuracy: 0.00001)
            XCTAssertEqual(region.center.longitude, -118.4808, accuracy: 0.00001)
            let result = try await resolver.location()
            XCTAssertEqual(result.coordinate.latitude, region.center.latitude)
            XCTAssertEqual(result.coordinate.longitude, region.center.longitude)
            XCTAssertEqual(harness.manager.authorizationRequestCount, 0)
            XCTAssertEqual(harness.manager.requestCount, 0)
            XCTAssertNil(history.location)
        }
    }

    func testAllowOnceFixSurvivesRelaunchAndExpiredOrDisabledPermission() async throws {
        let history = makeHistory()
        let harness = Harness(status: .notDetermined, history: history)
        let requested = expectation(description: "Explicit permission request")
        harness.manager.onAuthorizationRequest = { requested.fulfill() }
        let task = Task { try await harness.provider.currentLocation() }
        await fulfillment(of: [requested], timeout: 1)
        harness.manager.changeAuthorization(to: .authorizedWhenInUse)
        await waitForTimer(harness.clock)
        harness.manager.deliver([fix()])
        let shared = try await task.value

        // A new store/provider models a later process after Allow Once expires.
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            let relaunchedHistory = LastSharedLocationStore(defaults: history.defaults)
            let relaunched = Harness(status: status, history: relaunchedHistory, purpose: .map)
            let resolver = MapLaunchLocationResolver(history: relaunchedHistory, provider: relaunched.provider)
            let region = MapScreen.initialMapRegion(history: relaunchedHistory, useFixtures: false)
            XCTAssertEqual(region.center.latitude, shared.coordinate.latitude)
            XCTAssertEqual(region.center.longitude, shared.coordinate.longitude)
            let result = try await resolver.location()
            assertTimestamp(result.timestamp, equals: shared.timestamp)
            XCTAssertEqual(relaunched.manager.authorizationRequestCount, 0)
            XCTAssertEqual(relaunched.manager.requestCount, 0)
        }
    }

    func testAuthorizedCurrentLocationReplacesRememberedLocation() async throws {
        for status in [CLAuthorizationStatus.authorizedWhenInUse, .authorizedAlways] {
            let history = makeHistory()
            history.remember(CLLocation(latitude: 10, longitude: 20))
            let harness = Harness(status: status, history: history, purpose: .map)
            let resolver = MapLaunchLocationResolver(history: history, provider: harness.provider)
            let task = Task { try await resolver.location() }
            await waitForTimer(harness.clock)
            harness.manager.deliver([fix()])
            let result = try await task.value
            XCTAssertEqual(result.coordinate.latitude, 0)
            XCTAssertEqual(result.coordinate.longitude, 0)
            assertTimestamp(history.location?.timestamp, equals: result.timestamp)
            XCTAssertEqual(history.location?.coordinate.latitude, 0)
        }
    }

    func testMapAcquisitionTimeoutKeepsRememberedLocation() async throws {
        let history = makeHistory()
        let shared = fix(age: 86_400 * 365)
        history.remember(shared)
        let harness = Harness(history: history, purpose: .map)
        let resolver = MapLaunchLocationResolver(history: history, provider: harness.provider)
        let task = Task { try await resolver.location() }
        await waitForTimer(harness.clock)
        harness.clock.advance()
        await waitForTimer(harness.clock)
        harness.clock.advance()
        let result = try await task.value
        assertTimestamp(result.timestamp, equals: shared.timestamp)
        assertTimestamp(history.location?.timestamp, equals: shared.timestamp)
        XCTAssertEqual(harness.manager.requestCount, 2)

        let retry = Task { try await resolver.location() }
        await waitForTimer(harness.clock)
        harness.manager.deliver([fix()])
        let recovered = try await retry.value
        XCTAssertGreaterThan(recovered.timestamp, shared.timestamp)
        assertTimestamp(history.location?.timestamp, equals: recovered.timestamp)
    }

    func testMapCancellationDoesNotReturnFallbackOrReplaceHistory() async {
        let history = makeHistory()
        let shared = fix(age: 10)
        history.remember(shared)
        let harness = Harness(history: history, purpose: .map)
        let resolver = MapLaunchLocationResolver(history: history, provider: harness.provider)
        let task = Task { try await resolver.location() }
        await waitForTimer(harness.clock)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must not produce a camera location")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        assertTimestamp(history.location?.timestamp, equals: shared.timestamp)
        XCTAssertNil(harness.manager.delegate)
    }

    func testApproximateLocationCanCenterMapButCannotResolveNearbyPlace() async throws {
        let map = Harness(history: makeHistory(), purpose: .map)
        map.manager.accuracyAuthorization = .reducedAccuracy
        let mapTask = Task { try await map.provider.currentLocation() }
        await waitForTimer(map.clock)
        map.manager.deliver([fix(accuracy: 5_000)])
        let location = try await mapTask.value
        XCTAssertEqual(location.horizontalAccuracy, 5_000)
        XCTAssertEqual(map.history.location?.horizontalAccuracy, 5_000)

        let nearby = Harness(history: makeHistory())
        nearby.manager.accuracyAuthorization = .reducedAccuracy
        let nearbyTask = Task { try await nearby.provider.currentLocation() }
        await waitForTimer(nearby.clock)
        nearby.manager.deliver([fix(accuracy: 5_000)])
        nearby.clock.advance()
        await waitForTimer(nearby.clock)
        nearby.clock.advance()
        await assertFailure(nearbyTask, .locationUnavailable)
        XCTAssertEqual(nearby.history.location?.horizontalAccuracy, 5_000)
        let fallback = MapLaunchLocationResolver(history: nearby.history).fallbackLocation
        XCTAssertEqual(fallback.coordinate.latitude, location.coordinate.latitude)
        XCTAssertEqual(fallback.coordinate.longitude, location.coordinate.longitude)
    }

    func testMapStillRejectsCoarseFixWhenFullAccuracyIsAvailable() async {
        let harness = Harness(history: makeHistory(), purpose: .map)
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.deliver([fix(accuracy: 5_000)])
        XCTAssertNotNil(harness.manager.delegate)
        task.cancel()
        _ = await task.result
        XCTAssertNil(harness.history.location)
    }

    func testOlderConcurrentFixCannotReplaceNewerHistory() {
        let history = makeHistory()
        let newest = fix()
        history.remember(newest)
        history.remember(fix(age: 90))
        assertTimestamp(history.location?.timestamp, equals: newest.timestamp)
    }

    func testInvalidOrCorruptHistoryFallsBackWithoutTreatingZeroAsMissing() {
        let history = makeHistory()
        for record: [Double] in [
            [], [1, 2], [91, 0, 10, 1], [0, 181, 10, 1], [0, 0, -1, 1],
            [0, 0, 10, Date().addingTimeInterval(3_600).timeIntervalSince1970]
        ] {
            history.defaults.set(record, forKey: LastSharedLocationStore.storageKey)
            XCTAssertNil(history.location)
            XCTAssertEqual(MapLaunchLocationResolver(history: history).fallbackLocation.coordinate.latitude, 34.0036)
        }
        history.remember(fix())
        XCTAssertEqual(history.location?.coordinate.latitude, 0)
        XCTAssertEqual(history.location?.coordinate.longitude, 0)
        history.remember(CLLocation(latitude: 91, longitude: 0))
        XCTAssertEqual(history.location?.coordinate.latitude, 0)
    }

    func testAuthorizationExpiredDuringRequestCannotPersistALateFix() async {
        let harness = Harness(history: makeHistory(), purpose: .map)
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.changeAuthorization(to: .notDetermined)
        harness.manager.deliver([fix()])
        await assertFailure(task, .locationDenied)
        XCTAssertNil(harness.history.location)
        XCTAssertNil(harness.manager.delegate)
        XCTAssertEqual(harness.manager.authorizationRequestCount, 0)
    }

    func testCameraNavigationAndNewActivationRejectObsoleteLocationResults() {
        var state = MapInitialCameraState()
        let firstRequest = state.revision
        XCTAssertTrue(state.allowsLocationResult(for: firstRequest))
        state.resolve() // A selection, search, recenter, or gesture chose the camera.
        XCTAssertFalse(state.allowsLocationResult(for: firstRequest))
        state.reset() // Next app activation or authorization change.
        let newRequest = state.revision
        XCTAssertFalse(state.allowsLocationResult(for: firstRequest))
        XCTAssertTrue(state.allowsLocationResult(for: newRequest))
        state.resolve()
        XCTAssertFalse(state.allowsLocationResult(for: newRequest))
    }

    private func assertTimestamp(
        _ actual: Date?, equals expected: Date,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            actual?.timeIntervalSince1970 ?? .nan, expected.timeIntervalSince1970,
            accuracy: 0.000_001, file: file, line: line
        )
    }

    private func makeHistory() -> LastSharedLocationStore {
        let suite = "CoreLocationProviderTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return LastSharedLocationStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func testFirstAttemptSuccessStopsLocationWork() async throws {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.deliver([fix()])
        let result = try await task.value
        XCTAssertEqual(result.horizontalAccuracy, 20)
        XCTAssertEqual(harness.manager.requestCount, 1)
        XCTAssertEqual(harness.manager.stopCount, 1)
        XCTAssertNil(harness.manager.delegate)
    }

    func testNoFixRetriesAtSixSecondsAndFailsOnlyAfterSecondSixSeconds() async {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        XCTAssertEqual(harness.clock.durations, [.seconds(6)])
        XCTAssertEqual(harness.manager.requestCount, 1)
        harness.clock.advance()
        await waitForTimer(harness.clock)
        XCTAssertEqual(harness.clock.durations, [.seconds(6), .seconds(6)])
        XCTAssertEqual(harness.manager.requestCount, 2)
        XCTAssertEqual(harness.manager.stopCount, 1)
        XCTAssertNotNil(harness.manager.delegate)
        harness.clock.advance()
        await assertFailure(task, .locationUnavailable)
        XCTAssertEqual(harness.manager.requestCount, 2)
        XCTAssertEqual(harness.manager.stopCount, 2)
        XCTAssertNil(harness.manager.delegate)
    }

    func testTemporaryErrorWaitsForScheduledRetryThenSucceeds() async throws {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.fail(.locationUnknown)
        XCTAssertNotNil(harness.manager.delegate)
        XCTAssertEqual(harness.manager.requestCount, 1)
        harness.clock.advance()
        await waitForTimer(harness.clock)
        XCTAssertEqual(harness.manager.requestCount, 2)
        harness.manager.deliver([fix()])
        _ = try await task.value
        XCTAssertNil(harness.manager.delegate)
        XCTAssertEqual(harness.manager.requestCount, 2)
    }

    func testUnusableFirstReadingsDoNotFailEarlyAndFreshRetrySucceeds() async throws {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.deliver([
            fix(age: 180), fix(accuracy: 301), fix(accuracy: -1)
        ])
        XCTAssertNotNil(harness.manager.delegate)
        harness.clock.advance()
        await waitForTimer(harness.clock)
        harness.manager.deliver([fix(age: 180), fix()])
        _ = try await task.value
        XCTAssertEqual(harness.manager.requestCount, 2)
    }

    func testSecondAttemptErrorWaitsUntilItsDeadline() async {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.deliver([])
        harness.clock.advance()
        await waitForTimer(harness.clock)
        harness.manager.fail(.network)
        XCTAssertNotNil(harness.manager.delegate)
        harness.clock.advance()
        await assertFailure(task, .locationUnavailable)
    }

    func testDeniedAndRestrictedPermissionsDoNotStartAcquisition() async {
        for status in [CLAuthorizationStatus.denied, .restricted] {
            let harness = Harness(status: status, history: makeHistory())
            let task = Task { try await harness.provider.currentLocation() }
            await assertFailure(task, .locationDenied)
            XCTAssertEqual(harness.manager.requestCount, 0)
            XCTAssertTrue(harness.clock.durations.isEmpty)
        }
    }

    func testAuthorizationStartsBudgetOnlyAfterGrantAndIgnoresDuplicateCallbacks() async throws {
        let harness = Harness(status: .notDetermined, history: makeHistory())
        let requested = expectation(description: "Permission requested")
        harness.manager.onAuthorizationRequest = { requested.fulfill() }
        let task = Task { try await harness.provider.currentLocation() }
        await fulfillment(of: [requested], timeout: 1)
        harness.manager.changeAuthorization(to: .notDetermined)
        XCTAssertEqual(harness.manager.requestCount, 0)
        XCTAssertTrue(harness.clock.durations.isEmpty)
        harness.manager.changeAuthorization(to: .authorizedWhenInUse)
        await waitForTimer(harness.clock)
        harness.manager.changeAuthorization(to: .authorizedWhenInUse)
        XCTAssertEqual(harness.manager.requestCount, 1)
        harness.manager.deliver([fix()])
        _ = try await task.value
    }

    func testPermissionRevocationEndsImmediatelyWithoutRetry() async {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.changeAuthorization(to: .denied)
        await assertFailure(task, .locationDenied)
        XCTAssertEqual(harness.manager.requestCount, 1)
    }

    func testDeniedCallbackEndsImmediatelyWithoutRetry() async {
        let harness = Harness(history: makeHistory())
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.fail(.denied)
        await assertFailure(task, .locationDenied)
        XCTAssertEqual(harness.manager.requestCount, 1)
    }

    func testCancellationDuringEitherAttemptStopsRequest() async {
        for cancelDuringRetry in [false, true] {
            let harness = Harness(history: makeHistory())
            let task = Task { try await harness.provider.currentLocation() }
            await waitForTimer(harness.clock)
            if cancelDuringRetry {
                harness.clock.advance()
                await waitForTimer(harness.clock)
            }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Canceled request succeeded")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
            XCTAssertNil(harness.manager.delegate)
            XCTAssertEqual(harness.manager.requestCount, cancelDuringRetry ? 2 : 1)
        }
    }

    func testCancellationWhileAwaitingPermissionDoesNotStartAcquisition() async {
        let harness = Harness(status: .notDetermined, history: makeHistory())
        let requested = expectation(description: "Permission requested")
        harness.manager.onAuthorizationRequest = { requested.fulfill() }
        let task = Task { try await harness.provider.currentLocation() }
        await fulfillment(of: [requested], timeout: 1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Canceled request succeeded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(harness.manager.delegate)
        XCTAssertEqual(harness.manager.requestCount, 0)
    }

    func testAlreadyCanceledCallerNeverCreatesManager() async {
        var managerCount = 0
        let provider = CoreLocationProvider(history: makeHistory(), makeManager: {
            managerCount += 1
            return FakeLocationManager()
        })
        let task = Task { try await provider.currentLocation() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Canceled request succeeded")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(managerCount, 0)
    }

    func testOverlappingCallsOwnIndependentRequests() async throws {
        let first = FakeLocationManager()
        let second = FakeLocationManager()
        let clock = LocationTestClock()
        var managers = [first, second]
        let provider = CoreLocationProvider(
            history: makeHistory(),
            makeManager: { managers.removeFirst() },
            sleep: { try await clock.sleep($0) }
        )
        let firstStarted = expectation(description: "First request")
        first.onRequest = { firstStarted.fulfill() }
        let firstTask = Task { try await provider.currentLocation() }
        await fulfillment(of: [firstStarted], timeout: 1)
        let secondStarted = expectation(description: "Second request")
        second.onRequest = { secondStarted.fulfill() }
        let secondTask = Task { try await provider.currentLocation() }
        await fulfillment(of: [secondStarted], timeout: 1)
        firstTask.cancel()
        _ = await firstTask.result
        XCTAssertNil(first.delegate)
        XCTAssertNotNil(second.delegate)
        second.deliver([fix()])
        _ = try await secondTask.value
        XCTAssertEqual(first.requestCount, 1)
        XCTAssertEqual(second.requestCount, 1)
    }

    func testLocationUnavailableCopyOffersRetry() {
        XCTAssertEqual(
            PlaceResolutionError.locationUnavailable.errorDescription,
            "Couldn’t get your location. Tap to retry"
        )
    }

    private func waitForTimer(_ clock: LocationTestClock) async {
        guard clock.pending.isEmpty else { return }
        let scheduled = expectation(description: "Six-second timer scheduled")
        clock.onSleep = { scheduled.fulfill() }
        await fulfillment(of: [scheduled], timeout: 1)
        clock.onSleep = nil
    }

    private func assertFailure(_ task: Task<CLLocation, Error>, _ expected: PlaceResolutionError) async {
        do {
            _ = try await task.value
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? PlaceResolutionError, expected)
        }
    }

    private func fix(age: TimeInterval = 0, accuracy: CLLocationAccuracy = 20) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 0,
            timestamp: Date().addingTimeInterval(-age)
        )
    }
}

@MainActor
private final class Harness {
    let manager: FakeLocationManager
    let clock = LocationTestClock()
    let history: LastSharedLocationStore
    let purpose: CurrentLocationPurpose
    lazy var provider = CoreLocationProvider(
        purpose: purpose,
        history: history,
        makeManager: { [manager] in manager },
        sleep: { [clock] in try await clock.sleep($0) }
    )

    init(
        status: CLAuthorizationStatus = .authorizedWhenInUse,
        history: LastSharedLocationStore,
        purpose: CurrentLocationPurpose = .nearbyPlace
    ) {
        self.history = history
        self.purpose = purpose
        manager = FakeLocationManager()
        manager.authorizationStatus = status
    }
}

@MainActor
private final class FakeLocationManager: CurrentLocationManaging {
    weak var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var desiredAccuracy: CLLocationAccuracy = 0
    var requestCount = 0
    var authorizationRequestCount = 0
    var stopCount = 0
    var onRequest: (() -> Void)?
    var onAuthorizationRequest: (() -> Void)?
    // Only supplies the delegate signature; never requests device location.
    private lazy var callbackManager = CLLocationManager()

    func requestWhenInUseAuthorization() {
        authorizationRequestCount += 1
        onAuthorizationRequest?()
    }
    func requestLocation() { requestCount += 1; onRequest?() }
    func stopUpdatingLocation() { stopCount += 1 }
    func deliver(_ locations: [CLLocation]) {
        delegate?.locationManager?(callbackManager, didUpdateLocations: locations)
    }
    func fail(_ code: CLError.Code) {
        delegate?.locationManager?(callbackManager, didFailWithError: CLError(code))
    }
    func changeAuthorization(to status: CLAuthorizationStatus) {
        authorizationStatus = status
        delegate?.locationManagerDidChangeAuthorization?(callbackManager)
    }
}

/// Advances six-second deadlines explicitly; no wall-clock waits or GPS are needed.
@MainActor
private final class LocationTestClock {
    var durations: [Duration] = []
    var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    var onSleep: (() -> Void)?

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                durations.append(duration)
                pending[id] = continuation
                onSleep?()
            }
        } onCancel: {
            Task { @MainActor in
                self.pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func advance() {
        let current = pending.values
        pending.removeAll()
        for continuation in current { continuation.resume() }
    }
}
