import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class CoreLocationProviderTests: XCTestCase {
    func testFirstAttemptSuccessStopsLocationWork() async throws {
        let harness = Harness()
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
        let harness = Harness()
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
        let harness = Harness()
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
        let harness = Harness()
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
        let harness = Harness()
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
            let harness = Harness(status: status)
            let task = Task { try await harness.provider.currentLocation() }
            await assertFailure(task, .locationDenied)
            XCTAssertEqual(harness.manager.requestCount, 0)
            XCTAssertTrue(harness.clock.durations.isEmpty)
        }
    }

    func testAuthorizationStartsBudgetOnlyAfterGrantAndIgnoresDuplicateCallbacks() async throws {
        let harness = Harness(status: .notDetermined)
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
        let harness = Harness()
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.changeAuthorization(to: .denied)
        await assertFailure(task, .locationDenied)
        XCTAssertEqual(harness.manager.requestCount, 1)
    }

    func testDeniedCallbackEndsImmediatelyWithoutRetry() async {
        let harness = Harness()
        let task = Task { try await harness.provider.currentLocation() }
        await waitForTimer(harness.clock)
        harness.manager.fail(.denied)
        await assertFailure(task, .locationDenied)
        XCTAssertEqual(harness.manager.requestCount, 1)
    }

    func testCancellationDuringEitherAttemptStopsRequest() async {
        for cancelDuringRetry in [false, true] {
            let harness = Harness()
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
        let harness = Harness(status: .notDetermined)
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
        let provider = CoreLocationProvider(makeManager: {
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
    lazy var provider = CoreLocationProvider(
        makeManager: { [manager] in manager },
        sleep: { [clock] in try await clock.sleep($0) }
    )

    init(status: CLAuthorizationStatus = .authorizedWhenInUse) {
        manager = FakeLocationManager()
        manager.authorizationStatus = status
    }
}

@MainActor
private final class FakeLocationManager: CurrentLocationManaging {
    weak var delegate: (any CLLocationManagerDelegate)?
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var desiredAccuracy: CLLocationAccuracy = 0
    var requestCount = 0
    var stopCount = 0
    var onRequest: (() -> Void)?
    var onAuthorizationRequest: (() -> Void)?
    // Only supplies the delegate signature; never requests device location.
    private lazy var callbackManager = CLLocationManager()

    func requestWhenInUseAuthorization() { onAuthorizationRequest?() }
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
