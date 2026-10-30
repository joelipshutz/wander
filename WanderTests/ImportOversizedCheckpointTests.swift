import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportOversizedCheckpointTests: XCTestCase {
    func testOversizedHistoryUsesDurableWavesAndPreservesSourceMetadataOrder() async throws {
        var snapshot = fixture(historyCount: 4_096, pendingCount: 12)
        for index in 0..<2 {
            snapshot.items[index].seed = seed(index, name: nil)
        }
        let (directory, file, writes) = try persistence(snapshot)
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = OversizedCheckpointResolver()
        let store = PlaceImportStore(persistence: file, resolver: resolver)
        defer { store.cancel(batchID: "active"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.started.count == 6 }
        XCTAssertTrue(file.prefersGroupedProcessingCheckpoints)
        resolver.finish("seed-1:1", result: expansion(1, name: "Second source"))
        for index in 2..<6 { resolver.finish("seed-\(index):1") }
        try await waitUntil { resolver.finished.count == 5 }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(resolver.started.count, 6, "Uncacheable history retains the original bounded wave")
        XCTAssertEqual(writes.count, 1, "Only the initial claims are durable while a wave remains active")
        XCTAssertEqual(store.item(id: "item-2")?.state, .resolving)
        XCTAssertEqual(try file.load().items.first { $0.id == "item-2" }?.state, .resolving)

        resolver.finish("seed-0:1", result: expansion(0, name: "First source"))
        try await waitUntil { resolver.started.count == 12 }
        XCTAssertEqual(store.batches.first { $0.id == "active" }?.sourceName, "Second source")
        XCTAssertEqual(try file.load().batches.first { $0.id == "active" }?.sourceName, "Second source")
        resolver.openAll()
        await store.waitForProcessing(batchID: "active")
        XCTAssertTrue(store.items(for: "active").allSatisfy { $0.state == .ready })
        XCTAssertEqual(store.items(for: "active").map(\.seed.sourceLine), Array(0..<12))
        XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
        XCTAssertLessThanOrEqual(writes.count, 5, "Two waves must not turn into twelve full-document completion writes")
        let restored = try FilePlaceImportPersistence(fileURL: directory.appendingPathComponent("snapshot.json")).load()
        XCTAssertEqual(restored.items.map(\.id), store.items.map(\.id))
        XCTAssertEqual(restored.items.map(\.state), store.items.map(\.state))
        XCTAssertEqual(restored.items.map(\.candidates), store.items.map(\.candidates))
        XCTAssertEqual(restored.items.map(\.selectedCandidateID), store.items.map(\.selectedCandidateID))
        XCTAssertNil(store.persistenceError)
    }

    func testCrossingByteLimitSwitchesToWavesAndRetryRestoresRollingWithoutOldRunCleanup() async throws {
        let (directory, file, writes) = try persistence(fixture(pendingCount: 18))
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = OversizedCheckpointResolver()
        let store = PlaceImportStore(persistence: file, resolver: resolver)
        defer { store.cancel(batchID: "active"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.started.count == 6 }
        XCTAssertFalse(file.prefersGroupedProcessingCheckpoints)
        var large = oversizedCheckpointCandidate(seed(1))
        large.address = String(repeating: "x", count: 8 * 1_024 * 1_024 + 1)
        resolver.finish("seed-1:1", result: .candidates([large], selectedCandidateID: large.id))
        try await waitUntil { store.item(id: "item-1")?.state == .ready && resolver.started.count == 7 }
        XCTAssertTrue(file.prefersGroupedProcessingCheckpoints)
        XCTAssertEqual(writes.count, 2, "The crossing result is the only individual completion checkpoint")
        for index in 2..<7 { resolver.finish("seed-\(index):1") }
        try await waitUntil { resolver.finished.count == 6 }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(resolver.started.count, 7)
        XCTAssertEqual(store.items(for: "active").filter { $0.state == .ready }.count, 1)
        XCTAssertEqual(writes.count, 2, "Subsequent siblings wait for the outstanding wave member")

        store.cancel(batchID: "active")
        store.retry(itemID: "item-1") // Removes the oversized candidate and starts a replacement run.
        try await waitUntil { resolver.started.contains("seed-1:2") }
        XCTAssertFalse(file.prefersGroupedProcessingCheckpoints)
        resolver.finish("seed-0:1")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.item(id: "item-0")?.state, .dismissed)
        XCTAssertEqual(store.item(id: "item-1")?.state, .resolving)
        store.retry(itemID: "item-2")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(resolver.started.contains("seed-2:2"), "Old wave cleanup must not erase the replacement run")
        resolver.finish("seed-1:2")
        try await waitUntil { resolver.started.contains("seed-2:2") }
        resolver.openAll()
        await store.waitForProcessing(batchID: "active")
        XCTAssertEqual(store.item(id: "item-1")?.state, .ready)
        XCTAssertEqual(store.item(id: "item-2")?.state, .ready)
        XCTAssertEqual(try file.load().items.first { $0.id == "item-0" }?.state, .dismissed)
        XCTAssertFalse(file.prefersGroupedProcessingCheckpoints)
    }

    func testPauseAndDeleteRejectLateCompletionsWhileOversizedWaveIsBuffered() async throws {
        let (directory, file, _) = try persistence(fixture(historyCount: 4_096, pendingCount: 12))
        defer { try? FileManager.default.removeItem(at: directory) }
        let resolver = OversizedCheckpointResolver()
        let store = PlaceImportStore(persistence: file, resolver: resolver)
        defer { store.deleteBatch(batchID: "active"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.started.count == 6 }
        for index in 1..<6 { resolver.finish("seed-\(index):1") }
        try await waitUntil { resolver.finished.count == 5 }
        store.pauseProcessing(batchIDs: ["active"])
        XCTAssertTrue(store.items(for: "active").allSatisfy { $0.state == .queued })
        XCTAssertTrue(try file.load().items.filter { $0.batchID == "active" }.allSatisfy { $0.state == .queued })
        store.deleteBatch(batchID: "active")
        resolver.openAll()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(store.items(for: "active").isEmpty)
        XCTAssertTrue(store.matchingProgressByItemID.isEmpty)
        XCTAssertFalse(try file.load().items.contains { $0.batchID == "active" })
        XCTAssertEqual(store.items(for: "history").count, 4_096)
    }

    private func expansion(_ index: Int, name: String) -> PlaceImportResolution {
        let child = seed(index, name: "Child \(index)")
        let candidate = oversizedCheckpointCandidate(child)
        return .expandedResolved([PlaceImportResolvedEntry(seed: child, candidates: [candidate],
            selectedCandidateID: candidate.id, helpMessage: nil)], sourceName: name)
    }

    private func seed(_ index: Int, name: String? = "Fictional place") -> PlaceImportSeed {
        PlaceImportSeed(id: "seed-\(index)", rawText: "Fixture \(index)", nameHint: name,
            areaHint: nil, sourceURLString: nil, sourceLine: index)
    }

    private func fixture(historyCount: Int = 0, pendingCount: Int) -> PlaceImportSnapshot {
        var items = (0..<pendingCount).map { index in
            PlaceImportItem(id: "item-\(index)", batchID: "active", source: .googleMaps, seed: seed(index))
        }
        items += (0..<historyCount).map { index in
            PlaceImportItem(id: "history-\(index)", batchID: "history", source: .googleMaps,
                seed: seed(index + pendingCount), state: .dismissed)
        }
        var batches = [PlaceImportBatch(id: "active", source: .googleMaps,
            sourceName: "Fixture", totalCount: pendingCount)]
        if historyCount > 0 {
            batches.append(PlaceImportBatch(id: "history", source: .googleMaps,
                sourceName: "Old fixture", totalCount: historyCount))
        }
        return PlaceImportSnapshot(ownerUserID: "fixture-owner", batches: batches, items: items)
    }

    private func persistence(_ snapshot: PlaceImportSnapshot) throws -> (URL, FilePlaceImportPersistence, OversizedCheckpointWrites) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rec675-oversized-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("snapshot.json")
        try FilePlaceImportPersistence(fileURL: url).save(snapshot)
        let writes = OversizedCheckpointWrites()
        return (directory, FilePlaceImportPersistence(fileURL: url, writeData: writes.write), writes)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        if !condition() { XCTFail("Oversized checkpoint fixture did not progress"); throw WaitFailure.timedOut }
    }
    private enum WaitFailure: Error { case timedOut }
}

private func oversizedCheckpointCandidate(_ seed: PlaceImportSeed) -> PlaceCandidate {
    PlaceCandidate(id: "candidate-\(seed.id)", name: seed.nameHint ?? seed.id, category: "park",
        latitude: nil, longitude: nil, sourceProvider: "fixture", sourceProviderPlaceID: seed.id, confidence: 1)
}

private final class OversizedCheckpointWrites {
    private(set) var count = 0
    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        count += 1
    }
}

@MainActor
private final class OversizedCheckpointResolver: PlaceImportResolving {
    private(set) var started: [String] = []
    private(set) var finished: [String] = []
    private(set) var maximumActive = 0
    private var active = 0
    private var attempts: [String: Int] = [:]
    private var pending: [String: (PlaceImportSeed, CheckedContinuation<PlaceImportResolution, Never>)] = [:]
    private var isOpen = false
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        attempts[seed.id, default: 0] += 1
        let id = "\(seed.id):\(attempts[seed.id, default: 0])"
        started.append(id)
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1; finished.append(id) }
        if isOpen { return resolution(seed) }
        // Deliberately ignores cancellation to prove late provider callbacks are fenced.
        return await withCheckedContinuation { pending[id] = (seed, $0) }
    }
    func finish(_ id: String, result: PlaceImportResolution? = nil) {
        guard let (seed, continuation) = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: result ?? resolution(seed))
    }
    func openAll() {
        isOpen = true
        for id in Array(pending.keys) { finish(id) }
    }
    private func resolution(_ seed: PlaceImportSeed) -> PlaceImportResolution {
        let candidate = oversizedCheckpointCandidate(seed)
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }
}
