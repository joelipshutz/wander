#if DEBUG
import Foundation
import XCTest
@testable import Wander

@MainActor
final class WanderStoreFlushSchedulingTests: XCTestCase {
    func testFlushIncludesACompletedSecondSaveWhileFirstProducerIsPausedAfterUnlock() async {
        let store = WanderStore(fixtures: .empty())
        store.currentUser.displayName = "Flush scheduling first"
        let first = WanderStoreSnapshot(store: store)
        store.currentUser.displayName = "Flush scheduling second"
        let second = WanderStoreSnapshot(store: store)

        let scheduling = FlushSchedulingGate()
        let writes = FlushSchedulingWrites()
        let persistence = WanderStorePersistence.coalescingWithSchedulingGateForTesting(
            load: { writes.latest }, write: writes.write,
            afterSchedulingUnlock: scheduling.holdOnce
        )
        let workers = FlushSchedulingWorkers(persistence: persistence, first: first, writes: writes)
        defer {
            // Cleanup also runs after a failed assertion or synchronization.
            scheduling.release()
            writes.release()
            let joined = workers.joinSynchronously()
            XCTAssertTrue(joined, "Only this test's producers must finish before teardown")
            if joined { persistence.flush() }
        }

        workers.startFirstSave()
        let paused = await scheduling.waitUntilEntered()
        XCTAssertTrue(paused, "Producer A must be held immediately after releasing the scheduling lock")
        guard paused else { return }

        // This call has fully returned before the flush begins. Unlike A's
        // overlapping call, it is unambiguously covered by flush's contract.
        persistence.save(second)
        workers.startFlush()

        // Allow actual queued writes to complete, but keep producer A paused.
        // Correct code already submitted the drain. Old code still has an
        // empty queue, so its flush returns with no completed snapshot.
        writes.release()
        let flushed = await workers.waitUntilFlushed()
        XCTAssertTrue(flushed, "Flush must complete without requiring producer A to return")
        guard flushed else { return }
        XCTAssertFalse(scheduling.isReleased)
        XCTAssertFalse(scheduling.timedOut)
        XCTAssertFalse(writes.timedOut)
        XCTAssertEqual(workers.snapshotAtFlushReturn, second,
                       "Flush returned before the already-completed second save was written")

        scheduling.release()
        let joined = await workers.join()
        XCTAssertTrue(joined)
        guard joined else { return }
        persistence.flush()
        XCTAssertEqual(writes.latest, second)
        XCTAssertFalse(writes.wroteOnMainThread)
        // Ordinary writes may coalesce before consumption; no particular
        // number of ordinary writes is required to prove the flush contract.
        XCTAssertGreaterThanOrEqual(writes.completedCount, 1)
        XCTAssertLessThanOrEqual(writes.completedCount, 2)
    }
}

/// One gate per writer/test. No global scheduler or sleeps; timeouts only bound
/// failed coordination and are not the condition proving the race.
private final class FlushSchedulingGate: @unchecked Sendable {
    private let lock = NSLock()
    private let enteredSignal = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var entered = false
    private var released = false
    private var didTimeOut = false

    var isReleased: Bool { lock.withLock { released } }
    var timedOut: Bool { lock.withLock { didTimeOut } }

    func holdOnce() {
        let shouldWait = lock.withLock { () -> Bool in
            guard !entered else { return false }
            entered = true
            return true
        }
        guard shouldWait else { return }
        enteredSignal.signal()
        if releaseSignal.wait(timeout: .now() + 15) != .success {
            lock.withLock { didTimeOut = true }
        }
    }

    func release() {
        lock.withLock { released = true }
        releaseSignal.signal()
    }

    func waitUntilEntered() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: enteredSignal.wait(timeout: .now() + 5) == .success)
            }
        }
    }
}

private final class FlushSchedulingWrites: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = FlushSchedulingGate()
    private var completed: [WanderStoreSnapshot] = []
    private var observedMainThread = false

    var latest: WanderStoreSnapshot? { lock.withLock { completed.last } }
    var completedCount: Int { lock.withLock { completed.count } }
    var wroteOnMainThread: Bool { lock.withLock { observedMainThread } }
    var timedOut: Bool { gate.timedOut }

    func write(_ snapshot: WanderStoreSnapshot) {
        gate.holdOnce()
        lock.withLock {
            observedMainThread = observedMainThread || Thread.isMainThread
            completed.append(snapshot)
        }
    }

    func release() { gate.release() }
}

/// The wrapped callbacks are the writer's existing synchronized APIs. Snapshot
/// inputs are immutable, and result bookkeeping is protected by this lock.
private final class FlushSchedulingWorkers: @unchecked Sendable {
    private let persistence: WanderStorePersistence
    private let first: WanderStoreSnapshot
    private let writes: FlushSchedulingWrites
    private let all = DispatchGroup()
    private let flushFinished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var observedSnapshot: WanderStoreSnapshot?

    init(persistence: WanderStorePersistence, first: WanderStoreSnapshot, writes: FlushSchedulingWrites) {
        self.persistence = persistence
        self.first = first
        self.writes = writes
    }

    var snapshotAtFlushReturn: WanderStoreSnapshot? { lock.withLock { observedSnapshot } }

    func startFirstSave() {
        all.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { all.leave() }
            persistence.save(first)
        }
    }

    func startFlush() {
        all.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer { all.leave() }
            persistence.flush()
            let value = writes.latest
            lock.withLock { observedSnapshot = value }
            flushFinished.signal()
        }
    }

    func waitUntilFlushed() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: flushFinished.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    func join() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                continuation.resume(returning: joinSynchronously())
            }
        }
    }

    func joinSynchronously() -> Bool { all.wait(timeout: .now() + 5) == .success }
}
#endif
