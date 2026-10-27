#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import Wander

@MainActor
final class DiscoverRefinementUITestGateTests: XCTestCase {
    func testWaitRequiresExplicitReleaseAndRejectsDuplicateRelease() async throws {
        let gate = DiscoverRefinementUITestGate()
        XCTAssertFalse(gate.release(), "A release before any request must not arm a future request.")
        let task = Task { try await gate.waitForRelease() }
        defer { task.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(gate.stateDescription, "first=1:pending;started=1;cancelled=0;completed=0;pending=1")
        XCTAssertTrue(gate.release())
        XCTAssertFalse(gate.release(), "The same continuation must never be resumed twice.")
        try await task.value
        XCTAssertEqual(gate.stateDescription, "first=1:completed;started=1;cancelled=0;completed=1;pending=none")
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.release())
    }

    func testAlreadyCancelledTaskDoesNotInstallAContinuation() async {
        let gate = DiscoverRefinementUITestGate()
        let task = Task { try await gate.waitForRelease() }
        task.cancel()
        await assertCancelled(task)
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=1;cancelled=1;completed=0;pending=none")
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.release())
    }

    func testCancellationAfterSuspensionResumesAndRemovesWaiter() async throws {
        let gate = DiscoverRefinementUITestGate()
        let task = Task { try await gate.waitForRelease() }
        defer { task.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        task.cancel()
        await assertCancelled(task)
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=1;cancelled=1;completed=0;pending=none")
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.release())
    }

    func testCancellationBetweenReleaseAndConsumptionDoesNotCountCompletion() async throws {
        let gate = DiscoverRefinementUITestGate()
        let task = Task { try await gate.waitForRelease() }
        defer { task.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        XCTAssertTrue(gate.release())
        // No actor yield occurs between release and cancellation.
        task.cancel()
        await assertCancelled(task)
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=1;cancelled=1;completed=0;pending=none")
        XCTAssertFalse(gate.release())
    }

    func testHostUnmountCancelsWithoutCompletingAndIsIdempotent() async throws {
        let gate = DiscoverRefinementUITestGate()
        let first = Task { try await gate.waitForRelease() }
        defer { first.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        let second = Task { try await gate.waitForRelease() }
        defer { second.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate, count: 2)
        gate.cancelPending()
        gate.cancelPending()
        await assertCancelled(first)
        await assertCancelled(second)
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=2;cancelled=2;completed=0;pending=none")
        XCTAssertEqual(gate.state(of: 2), .cancelled)
        XCTAssertFalse(gate.isWaiting)
        XCTAssertFalse(gate.release())
    }

    func testOverlappingRequestCannotReplaceTheOriginalPendingOperation() async throws {
        let gate = DiscoverRefinementUITestGate()
        let first = Task { try await gate.waitForRelease() }
        defer { first.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        let second = Task { try await gate.waitForRelease() }
        defer { second.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate, count: 2)
        XCTAssertEqual(gate.stateDescription, "first=1:pending;started=2;cancelled=0;completed=0;pending=1,2")
        XCTAssertEqual(gate.state(of: 2), .pending)
        XCTAssertTrue(gate.release())
        XCTAssertFalse(gate.release())
        try await first.value
        try await second.value
        XCTAssertEqual(gate.stateDescription, "first=1:completed;started=2;cancelled=0;completed=2;pending=none")
        XCTAssertEqual(gate.state(of: 2), .completed)
    }

    func testSequentialOperationsHaveDistinctIDsAndExactCounts() async throws {
        let gate = DiscoverRefinementUITestGate()
        for id in 1...2 {
            let task = Task { try await gate.waitForRelease() }
            defer { task.cancel(); gate.cancelPending() }
            try await waitUntilSuspended(gate)
            XCTAssertEqual(gate.pendingOperationIDs, [id])
            XCTAssertEqual(gate.state(of: id), .pending)
            XCTAssertEqual(gate.startedCount, id)
            XCTAssertEqual(gate.completedCount, id - 1)
            XCTAssertEqual(gate.cancelledCount, 0)
            XCTAssertTrue(gate.release())
            try await task.value
            XCTAssertEqual(gate.state(of: id), .completed)
        }
        XCTAssertEqual(gate.stateDescription, "first=1:completed;started=2;cancelled=0;completed=2;pending=none")
    }

    func testCancelledOperationDoesNotCancelTheNextOperation() async throws {
        let gate = DiscoverRefinementUITestGate()
        let first = Task { try await gate.waitForRelease() }
        defer { first.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate)
        let second = Task { try await gate.waitForRelease() }
        defer { second.cancel(); gate.cancelPending() }
        try await waitUntilSuspended(gate, count: 2)
        first.cancel()
        await assertCancelled(first)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=2;cancelled=1;completed=0;pending=2")
        XCTAssertEqual(gate.state(of: 2), .pending)
        XCTAssertTrue(gate.isWaiting)
        XCTAssertTrue(gate.release())
        try await second.value
        XCTAssertEqual(gate.stateDescription, "first=1:cancelled;started=2;cancelled=1;completed=1;pending=none")
        XCTAssertEqual(gate.state(of: 2), .completed)
    }

    private func waitUntilSuspended(_ gate: DiscoverRefinementUITestGate, count: Int = 1) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !gate.isWaiting || gate.pendingOperationIDs.count != count {
            guard clock.now < deadline else {
                XCTFail("The fixture never installed its pending continuations.")
                throw CancellationError()
            }
            await Task.yield()
        }
    }

    private func assertCancelled(_ task: Task<Void, any Error>) async {
        do {
            try await task.value
            XCTFail("Cancellation must throw rather than supply refined results.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
#endif
