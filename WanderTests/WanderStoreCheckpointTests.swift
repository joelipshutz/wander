import Foundation
import UIKit
import XCTest
@testable import Wander

@MainActor
final class WanderStoreCheckpointTests: XCTestCase {
    func testLegacyCustomWriterKeepsSaveAndFlushButCannotClaimDurability() {
        let snapshot = snapshots(count: 1)[0]
        var saves = 0
        var flushes = 0
        let persistence = WanderStorePersistence(load: { nil }, save: { _ in saves += 1 },
            flush: { flushes += 1 })

        persistence.save(snapshot)
        persistence.flush()
        XCTAssertThrowsError(try persistence.checkpoint(snapshot)) {
            XCTAssertEqual($0 as? WanderStorePersistenceError, .checkpointUnsupported)
        }
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(flushes, 1)
    }

    func testCustomCheckpointUsesExplicitSuccessAndFailureContract() throws {
        let values = snapshots(count: 2)
        var persisted: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { persisted }, save: { persisted = $0 },
            checkpoint: { snapshot in
                guard snapshot == values[0] else { throw CheckpointTestError.writeFailed }
                persisted = snapshot
            })

        try persistence.checkpoint(values[0])
        XCTAssertEqual(persistence.load(), values[0])
        XCTAssertThrowsError(try persistence.checkpoint(values[1])) {
            XCTAssertEqual($0 as? CheckpointTestError, .writeFailed)
        }
        XCTAssertEqual(persistence.load(), values[0])
    }

    func testFileCheckpointsRoundTripAndReportWriteFailure() throws {
        let values = snapshots(count: 2)
        for coalesced in [false, true] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("store.json")
            let persistence = coalesced ? WanderStorePersistence.coalescingFile(url: url)
                : WanderStorePersistence.file(url: url)
            persistence.save(values[0])
            try persistence.checkpoint(values[1])
            XCTAssertEqual(try readSnapshot(url), values[1], "Checkpoint must finish its exact write")

            // A regular file where a parent directory is required is a deterministic
            // filesystem failure, independent of simulator permissions or capacity.
            let blockedURL = url.appendingPathComponent("child.json")
            let blocked = coalesced ? WanderStorePersistence.coalescingFile(url: blockedURL)
                : WanderStorePersistence.file(url: blockedURL)
            XCTAssertThrowsError(try blocked.checkpoint(values[0]))
            XCTAssertEqual(try readSnapshot(url), values[1])
        }
    }

    func testEncodingFailureLeavesPreviousAtomicSnapshotIntact() throws {
        let store = WanderStore(fixtures: .seed())
        let good = WanderStoreSnapshot(store: store)
        let place = try XCTUnwrap(store.places.first)
        place.latitude = .infinity
        let invalid = WanderStoreSnapshot(store: store)
        for coalesced in [false, true] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("store.json")
            let persistence = coalesced ? WanderStorePersistence.coalescingFile(url: url)
                : WanderStorePersistence.file(url: url)
            try persistence.checkpoint(good)
            let originalBytes = try Data(contentsOf: url)
            XCTAssertThrowsError(try persistence.checkpoint(invalid))
            XCTAssertEqual(try Data(contentsOf: url), originalBytes)
            XCTAssertEqual(persistence.load(), good)
        }
    }

    func testCheckpointIsAnOrderedBarrierBetweenCoalescedWrites() throws {
        let values = snapshots(count: 6)
        let probe = CheckpointWriteProbe(blockWrites: true)
        let persistence = WanderStorePersistence.coalescing(load: { nil }, write: probe.write,
            checkpointWrite: probe.checkpoint)
        let laterWork = LaterCheckpointWrites(persistence: persistence, snapshots: Array(values[4...5]))
        defer { probe.releaseAll() }

        persistence.save(values[0])
        XCTAssertEqual(probe.firstNormalStarted.wait(timeout: .now() + 5), .success)
        persistence.save(values[1])
        persistence.save(values[2])
        let laterWorkFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            probe.releaseFirstNormal.signal()
            guard probe.checkpointStarted.wait(timeout: .now() + 5) == .success else {
                probe.recordTimeout()
                probe.releaseCheckpoint.signal()
                laterWorkFinished.signal()
                return
            }
            laterWork.save()
            probe.releaseCheckpoint.signal()
            laterWorkFinished.signal()
        }

        try persistence.checkpoint(values[3])
        XCTAssertEqual(laterWorkFinished.wait(timeout: .now() + 5), .success)
        persistence.flush()
        XCTAssertEqual(probe.completed, [values[0], values[2], values[3], values[5]])
        XCTAssertEqual(probe.checkpointSnapshots, [values[3]])
        XCTAssertFalse(probe.timedOut)
        XCTAssertFalse(probe.wroteOnMainThread)
    }

    func testFailedCheckpointReportsFailureAndDoesNotPoisonLaterWritesOrRetry() throws {
        let values = snapshots(count: 3)
        let probe = CheckpointWriteProbe(failFirstCheckpoint: true)
        let persistence = WanderStorePersistence.coalescing(load: { probe.completed.last },
            write: probe.write, checkpointWrite: probe.checkpoint)
        persistence.save(values[0])
        persistence.flush()

        XCTAssertThrowsError(try persistence.checkpoint(values[1])) {
            XCTAssertEqual($0 as? CheckpointTestError, .writeFailed)
        }
        XCTAssertEqual(persistence.load(), values[0])
        try persistence.checkpoint(values[1])
        XCTAssertEqual(persistence.load(), values[1])
        persistence.save(values[2])
        persistence.flush()
        XCTAssertEqual(persistence.load(), values[2])
        XCTAssertEqual(probe.checkpointSnapshots, [values[1], values[1]])
    }

    func testLegacyCoalescingWriterDoesNotInferCheckpointSuccess() {
        let value = snapshots(count: 1)[0]
        let probe = CheckpointWriteProbe()
        let persistence = WanderStorePersistence.coalescing(load: { nil }, write: probe.write)
        persistence.save(value)
        persistence.flush()
        XCTAssertThrowsError(try persistence.checkpoint(value)) {
            XCTAssertEqual($0 as? WanderStorePersistenceError, .checkpointUnsupported)
        }
        XCTAssertEqual(probe.completed, [value])
    }

    func testLifecycleNotificationsStillFlushOrdinaryWritesAfterCheckpoint() throws {
        let values = snapshots(count: 3)
        let probe = CheckpointWriteProbe()
        let persistence = WanderStorePersistence.coalescing(load: { probe.completed.last },
            write: probe.write, checkpointWrite: probe.checkpoint, flushOnAppLifecycle: true)
        try persistence.checkpoint(values[0])
        persistence.save(values[1])
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(probe.completed.last, values[1])
        persistence.save(values[2])
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertEqual(probe.completed.last, values[2])
    }

    func testAsyncFileCheckpointsAcknowledgeExactSnapshotAndPropagateErrors() async throws {
        let values = snapshots(count: 2)
        for coalesced in [false, true] {
            let directory = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("store.json")
            let persistence = coalesced ? WanderStorePersistence.coalescingFile(url: url)
                : WanderStorePersistence.file(url: url)
            persistence.save(values[0])
            try await persistence.checkpointAsync(values[1])
            XCTAssertEqual(try readSnapshot(url), values[1])
            XCTAssertEqual(persistence.load(), values[1])

            let blockedURL = url.appendingPathComponent("child.json")
            let blocked = coalesced ? WanderStorePersistence.coalescingFile(url: blockedURL)
                : WanderStorePersistence.file(url: blockedURL)
            do {
                try await blocked.checkpointAsync(values[0])
                XCTFail("Async checkpoint must not acknowledge a failed file write")
            } catch { }
            XCTAssertEqual(try readSnapshot(url), values[1])
        }
    }

    func testAsyncCheckpointSuspendsMainActorAndCancellationCannotSkipAnEnqueuedWrite() async throws {
        let values = snapshots(count: 3)
        let probe = CheckpointWriteProbe(blockWrites: true)
        let persistence = WanderStorePersistence.coalescing(load: { nil }, write: probe.write,
            checkpointWrite: probe.checkpoint)
        defer { probe.releaseAll() }
        var acknowledged = false
        let checkpoint = Task { @MainActor in
            try await persistence.checkpointAsync(values[0])
            acknowledged = true
        }
        let started = await probe.waitForCheckpointStart()
        XCTAssertTrue(started, "Main actor must remain available while the writer is blocked")
        XCTAssertFalse(acknowledged)
        XCTAssertTrue(probe.completed.isEmpty)
        checkpoint.cancel()
        persistence.save(values[1])
        persistence.save(values[2])
        XCTAssertFalse(acknowledged, "Cancellation cannot claim that queued bytes are durable")
        probe.releaseAll()
        try await checkpoint.value
        persistence.flush()
        XCTAssertTrue(acknowledged)
        XCTAssertEqual(probe.completed, [values[0], values[2]])
        XCTAssertFalse(probe.wroteOnMainThread)
        XCTAssertFalse(probe.timedOut)
    }

    func testAsyncFailureReachesCallerAndRetryUsesTheSameOrderedWriter() async throws {
        let values = snapshots(count: 2)
        let probe = CheckpointWriteProbe(failFirstCheckpoint: true)
        let persistence = WanderStorePersistence.coalescing(load: { probe.completed.last },
            write: probe.write, checkpointWrite: probe.checkpoint)
        persistence.save(values[0])
        do {
            try await persistence.checkpointAsync(values[1])
            XCTFail("Injected write failure must reach the awaiting caller")
        } catch {
            XCTAssertEqual(error as? CheckpointTestError, .writeFailed)
        }
        XCTAssertEqual(persistence.load(), values[0])
        try await persistence.checkpointAsync(values[1])
        XCTAssertEqual(persistence.load(), values[1])
        XCTAssertEqual(probe.checkpointSnapshots, [values[1], values[1]])
    }

    func testAsyncDefaultDoesNotInferDurabilityFromLegacySynchronousCallbacks() async {
        let value = snapshots(count: 1)[0]
        var synchronousCheckpoints = 0
        let persistence = WanderStorePersistence(load: { nil }, save: { _ in },
            checkpoint: { _ in synchronousCheckpoints += 1 })
        do {
            try await persistence.checkpointAsync(value)
            XCTFail("An unconfigured async checkpoint must report unsupported")
        } catch {
            XCTAssertEqual(error as? WanderStorePersistenceError, .checkpointUnsupported)
        }
        XCTAssertEqual(synchronousCheckpoints, 0)
    }

    private func snapshots(count: Int) -> [WanderStoreSnapshot] {
        let store = WanderStore(fixtures: .empty())
        return (0..<count).map { index in
            store.currentUser.displayName = "Checkpoint fixture \(index)"
            return WanderStoreSnapshot(store: store)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-checkpoint-\(UUID().uuidString)", isDirectory: true)
    }

    private func readSnapshot(_ url: URL) throws -> WanderStoreSnapshot {
        try JSONDecoder().decode(WanderStoreSnapshot.self, from: Data(contentsOf: url))
    }
}

private enum CheckpointTestError: Error, Equatable { case writeFailed }

private final class LaterCheckpointWrites: @unchecked Sendable {
    let persistence: WanderStorePersistence
    let snapshots: [WanderStoreSnapshot]

    init(persistence: WanderStorePersistence, snapshots: [WanderStoreSnapshot]) {
        self.persistence = persistence
        self.snapshots = snapshots
    }

    func save() { snapshots.forEach(persistence.save) }
}

private final class CheckpointWriteProbe: @unchecked Sendable {
    let firstNormalStarted = DispatchSemaphore(value: 0)
    let releaseFirstNormal = DispatchSemaphore(value: 0)
    let checkpointStarted = DispatchSemaphore(value: 0)
    let releaseCheckpoint = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private let blockWrites: Bool
    private let failFirstCheckpoint: Bool
    private var normalCount = 0
    private var storedCompleted: [WanderStoreSnapshot] = []
    private var storedCheckpoints: [WanderStoreSnapshot] = []
    private var storedTimedOut = false
    private var storedMainThread = false

    init(blockWrites: Bool = false, failFirstCheckpoint: Bool = false) {
        self.blockWrites = blockWrites
        self.failFirstCheckpoint = failFirstCheckpoint
    }

    func write(_ snapshot: WanderStoreSnapshot) {
        lock.lock()
        normalCount += 1
        let block = blockWrites && normalCount == 1
        storedMainThread = storedMainThread || Thread.isMainThread
        lock.unlock()
        if block {
            firstNormalStarted.signal()
            if releaseFirstNormal.wait(timeout: .now() + 5) != .success { recordTimeout() }
        }
        appendCompleted(snapshot)
    }

    func checkpoint(_ snapshot: WanderStoreSnapshot) throws {
        lock.lock()
        storedCheckpoints.append(snapshot)
        let fail = failFirstCheckpoint && storedCheckpoints.count == 1
        storedMainThread = storedMainThread || Thread.isMainThread
        lock.unlock()
        if blockWrites {
            checkpointStarted.signal()
            if releaseCheckpoint.wait(timeout: .now() + 5) != .success { recordTimeout() }
        }
        if fail { throw CheckpointTestError.writeFailed }
        appendCompleted(snapshot)
    }

    func releaseAll() {
        releaseFirstNormal.signal()
        releaseCheckpoint.signal()
    }

    func waitForCheckpointStart() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [self] in
                continuation.resume(returning: checkpointStarted.wait(timeout: .now() + 5) == .success)
            }
        }
    }

    func recordTimeout() {
        lock.lock()
        storedTimedOut = true
        lock.unlock()
    }

    private func appendCompleted(_ snapshot: WanderStoreSnapshot) {
        lock.lock()
        storedCompleted.append(snapshot)
        lock.unlock()
    }

    var completed: [WanderStoreSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return storedCompleted
    }

    var checkpointSnapshots: [WanderStoreSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return storedCheckpoints
    }

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedTimedOut
    }

    var wroteOnMainThread: Bool {
        lock.lock(); defer { lock.unlock() }
        return storedMainThread
    }
}
