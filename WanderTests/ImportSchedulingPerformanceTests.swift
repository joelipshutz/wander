import Combine
import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportSchedulingPerformanceTests: XCTestCase {
    /// Run unchanged against both schedulers. Three slow lookups are separated
    /// by fast siblings, as in a provider list with a few slow place requests.
    func testPerformanceGoogleImportWithUnevenLookupLatency() async {
        let rowCount = 18
        var completionSamples: [Double] = []
        var firstReadySamples: [Double] = []
        for _ in 0..<3 {
            let resolver = DelayedSchedulingResolver()
            let store = PlaceImportStore(persistence: SchedulingPersistence(
                snapshot: schedulingSnapshot(count: rowCount)), resolver: resolver)
            var firstReadyMilliseconds: Double?
            let startedAt = ProcessInfo.processInfo.systemUptime
            let subscription = store.$items.sink { items in
                if firstReadyMilliseconds == nil, items.contains(where: { $0.state == .ready }) {
                    firstReadyMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                }
            }
            store.resumePendingImports()
            await store.waitForProcessing(batchID: "scheduling-batch")
            completionSamples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            firstReadySamples.append(firstReadyMilliseconds ?? -1)
            subscription.cancel()
            XCTAssertEqual(store.items(for: "scheduling-batch").map(\.id), (0..<rowCount).map { "item-\($0)" })
            XCTAssertTrue(store.items.allSatisfy { $0.state == .ready })
            XCTAssertEqual(resolver.startedCount, rowCount)
            XCTAssertGreaterThan(resolver.maximumActive, 1)
            XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
            XCTAssertNotNil(firstReadyMilliseconds)
        }
        let attachment = XCTAttachment(string:
            "REC675 google_import_uneven_latency rows=18 slow_ms=180 fast_ms=10 completion_samples_ms=\(completionSamples) completion_median_ms=\(completionSamples.sorted()[1]) first_ready_samples_ms=\(firstReadySamples) first_ready_median_ms=\(firstReadySamples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
final class ImportSchedulingTests: XCTestCase {
    func testSourceExpansionsKeepSourceMetadataOrderWithoutHoldingOrdinaryPlaceResults() async throws {
        var snapshot = schedulingSnapshot(count: 12)
        for index in 0..<2 {
            snapshot.items[index].seed = PlaceImportSeed(id: "seed-\(index)", rawText: "Source \(index)",
                nameHint: nil, areaHint: nil, sourceURLString: nil, sourceLine: index)
        }
        let resolver = GatedSchedulingResolver()
        let persistence = SchedulingPersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)
        defer { store.cancel(batchID: "scheduling-batch"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.startedIDs.count == 6 }
        let firstChild = PlaceImportSeed(id: "child-first", rawText: "First child", nameHint: "First child",
            areaHint: nil, sourceURLString: nil, sourceLine: 0)
        let secondChild = PlaceImportSeed(id: "child-second", rawText: "Second child", nameHint: "Second child",
            areaHint: nil, sourceURLString: nil, sourceLine: 1)
        resolver.finish("seed-1:1", resolution: .expanded([secondChild], sourceName: "Second list"))
        resolver.finish("seed-2:1")
        try await waitUntil { store.item(id: "item-2")?.state == .ready }
        XCTAssertEqual(store.batches.first?.sourceName, "Fixture import")
        XCTAssertEqual(store.item(id: "item-1")?.state, .resolving,
            "Only source expansion effects wait for an earlier source")
        XCTAssertEqual(persistence.snapshot.items.first { $0.id == "item-1" }?.state, .resolving,
            "A restart must retain the source row until its ordered metadata is applied")
        resolver.finish("seed-0:1", resolution: .expanded([firstChild], sourceName: "First list"))
        resolver.openAll()
        await store.waitForProcessing(batchID: "scheduling-batch")
        XCTAssertEqual(store.batches.first?.sourceName, "Second list")
        XCTAssertEqual(store.batches.first?.sourceListName, "Second list")
        XCTAssertEqual(Array(store.items(for: "scheduling-batch").prefix(2)).map(\.seed.id),
            ["child-first", "child-second"])
        XCTAssertEqual(persistence.snapshot.batches.first?.sourceName, "Second list")
        XCTAssertTrue(store.items.allSatisfy { $0.state == .ready })
        XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
    }

    func testCancelledImportDoesNotAutomaticallySaveItsAlreadyReadySiblings() async throws {
        let resolver = GatedSchedulingResolver()
        let importStore = PlaceImportStore(persistence: SchedulingPersistence(
            snapshot: schedulingSnapshot(count: 18, automatic: true)), resolver: resolver)
        let store = WanderStore(fixtures: .empty())
        importStore.resumePendingImports()
        let automaticSave = Task { @MainActor in
            await PlaceImportAutoSaveCoordinator.process(batchIDs: ["scheduling-batch"],
                importStore: importStore, store: store, expectedUserID: store.currentUser.id,
                isAuthorized: { true })
        }
        defer {
            automaticSave.cancel()
            importStore.cancel(batchID: "scheduling-batch")
            resolver.openAll()
        }
        try await waitUntil { resolver.startedIDs.count == 6 }
        resolver.openAll(except: "seed-0:1")
        try await waitUntil { importStore.items.filter { $0.state == .ready }.count == 17 }
        importStore.cancel(batchID: "scheduling-batch")
        let batch = try XCTUnwrap(importStore.batches.first)
        XCTAssertTrue(PlaceImportAutoSavePolicy.committableItemIDs(
            batchItems: [(batch, importStore.items)]).isEmpty)
        resolver.finish("seed-0:1")
        let result = await automaticSave.value
        XCTAssertEqual(result.addedCount, 0)
        XCTAssertTrue(result.batchIDs.isEmpty)
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty)
        XCTAssertFalse(importStore.items.contains { $0.state == .saved })
        XCTAssertNil(importStore.batches.first?.automaticSaveCompletedAt)
        XCTAssertNil(importStore.batches.first?.receipt)
    }

    func testReadySiblingsPublishAndRefillWithoutCommittingWhileSlowLookupIsActive() async throws {
        let resolver = GatedSchedulingResolver()
        let importStore = PlaceImportStore(persistence: SchedulingPersistence(
            snapshot: schedulingSnapshot(count: 18, automatic: true)), resolver: resolver)
        let store = WanderStore(fixtures: .empty())
        importStore.resumePendingImports()
        let automaticSave = Task { @MainActor in
            await PlaceImportAutoSaveCoordinator.process(batchIDs: ["scheduling-batch"],
                importStore: importStore, store: store, expectedUserID: store.currentUser.id,
                isAuthorized: { true })
        }
        defer {
            automaticSave.cancel()
            importStore.cancel(batchID: "scheduling-batch")
            resolver.openAll()
        }
        try await waitUntil { resolver.startedIDs.count == 6 }
        resolver.openAll(except: "seed-0:1")
        try await waitUntil {
            importStore.items.filter { $0.state == .ready }.count == 17
        }
        XCTAssertEqual(resolver.startedIDs.count, 18, "A completed lookup must refill its slot immediately")
        XCTAssertEqual(importStore.item(id: "item-0")?.state, .resolving)
        XCTAssertEqual(importStore.batches.first?.state, .processing)
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty, "Automatic saving waits for every active lookup")
        XCTAssertFalse(importStore.items.contains { $0.state == .saved })
        XCTAssertEqual(importStore.items(for: "scheduling-batch").map(\.id), (0..<18).map { "item-\($0)" })
        resolver.finish("seed-0:1")
        let result = await automaticSave.value
        XCTAssertEqual(result.addedCount, 18)
        XCTAssertTrue(importStore.items.allSatisfy { $0.state == .saved })
        XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
    }

    func testSmallGoogleAndSocialImportsKeepSerialResolution() async throws {
        for (source, count) in [(PlaceImportSource.googleMaps, 9), (.instagram, 12)] {
            let resolver = GatedSchedulingResolver()
            let store = PlaceImportStore(persistence: SchedulingPersistence(
                snapshot: schedulingSnapshot(count: count, source: source)), resolver: resolver)
            defer { store.cancel(batchID: "scheduling-batch"); resolver.openAll() }
            store.resumePendingImports()
            try await waitUntil { resolver.startedIDs.count == 1 }
            for _ in 0..<5 { await Task.yield() }
            XCTAssertEqual(resolver.startedIDs.count, 1)
            resolver.openAll()
            await store.waitForProcessing(batchID: "scheduling-batch")
            XCTAssertEqual(resolver.maximumActive, 1)
            XCTAssertTrue(store.items.allSatisfy { $0.state == .ready })
        }
    }

    func testLateResolverCallbacksAfterPauseAndDeleteCannotPublish() async throws {
        let resolver = GatedSchedulingResolver()
        let persistence = SchedulingPersistence(snapshot: schedulingSnapshot(count: 12))
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)
        defer { store.deleteBatch(batchID: "scheduling-batch"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.startedIDs.count == 6 }
        store.pauseProcessing(batchIDs: ["scheduling-batch"])
        resolver.emitProgress("seed-0:1")
        XCTAssertTrue(store.matchingProgressByItemID.isEmpty)
        XCTAssertTrue(store.items.allSatisfy { $0.state == .queued })
        XCTAssertTrue(persistence.snapshot.items.allSatisfy { $0.state == .queued })
        store.deleteBatch(batchID: "scheduling-batch")
        resolver.openAll()
        for _ in 0..<20 { await Task.yield() }
        resolver.emitProgress("seed-0:1")
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(store.batches.isEmpty)
        XCTAssertTrue(store.matchingProgressByItemID.isEmpty)
        XCTAssertTrue(persistence.snapshot.items.isEmpty)
    }

    func testCancelledRunCannotClearOrPublishIntoReplacementForTheSameBatch() async throws {
        let resolver = GatedSchedulingResolver()
        let store = PlaceImportStore(persistence: SchedulingPersistence(
            snapshot: schedulingSnapshot(count: 12)), resolver: resolver)
        defer { store.cancel(batchID: "scheduling-batch"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.startedIDs.count == 6 }
        store.cancel(batchID: "scheduling-batch")
        store.retry(itemID: "item-0")
        try await waitUntil { resolver.startedIDs.contains("seed-0:2") }
        // Deliver an old callback from outside its cancelled task, as a provider
        // completion can do. Item identity and seed alone cannot reject it.
        resolver.emitProgress("seed-0:1")
        XCTAssertNil(store.matchingProgressByItemID["item-0"])
        for index in 0..<6 { resolver.finish("seed-\(index):1") }
        for _ in 0..<20 { await Task.yield() }
        store.retry(itemID: "item-1")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(resolver.startedIDs.contains("seed-1:2"),
            "Old cleanup must not erase the active replacement task and start a competing run")
        resolver.openAll()
        await store.waitForProcessing(batchID: "scheduling-batch")
        XCTAssertEqual(store.item(id: "item-0")?.state, .ready)
        XCTAssertEqual(store.item(id: "item-1")?.state, .ready)
        XCTAssertEqual(resolver.startedIDs.filter { $0 == "seed-0:2" }.count, 1)
    }

    func testSameSeedRetryRejectsOldResultAndKeepsReplacementProgress() async throws {
        let resolver = GatedSchedulingResolver()
        let store = PlaceImportStore(persistence: SchedulingPersistence(
            snapshot: schedulingSnapshot(count: 12)), resolver: resolver)
        defer { store.cancel(batchID: "scheduling-batch"); resolver.openAll() }
        store.resumePendingImports()
        try await waitUntil { resolver.startedIDs.count == 6 }
        store.resumePendingImports()
        XCTAssertEqual(store.items.filter { $0.state == .resolving }.count, 6,
            "Resuming an already active import must not requeue its live claims")
        store.retry(itemID: "item-0")
        resolver.finish("seed-1:1")
        try await waitUntil { resolver.startedIDs.contains("seed-0:2") }
        resolver.emitProgress("seed-0:1")
        XCTAssertNil(store.matchingProgressByItemID["item-0"])
        resolver.emitProgress("seed-0:2")
        let replacementProgress = try XCTUnwrap(store.matchingProgressByItemID["item-0"])
        resolver.finish("seed-0:1")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.item(id: "item-0")?.state, .resolving,
            "The old result must not complete a newly claimed retry with the same seed")
        XCTAssertEqual(store.matchingProgressByItemID["item-0"], replacementProgress,
            "Discarding an old result must not clear replacement progress")
        resolver.openAll()
        await store.waitForProcessing(batchID: "scheduling-batch")
        XCTAssertTrue(store.items.allSatisfy { $0.state == .ready })
        XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        if !condition() {
            XCTFail("Import scheduler did not reach the expected state")
            throw SchedulingWaitError.timedOut
        }
    }
}

private enum SchedulingWaitError: Error { case timedOut }

@MainActor
private func schedulingSnapshot(count: Int, source: PlaceImportSource = .googleMaps,
                                automatic: Bool = false) -> PlaceImportSnapshot {
    let items = (0..<count).map { index in
        PlaceImportItem(id: "item-\(index)", batchID: "scheduling-batch", source: source,
            seed: PlaceImportSeed(id: "seed-\(index)", rawText: "Fixture \(index)",
                nameHint: "Fixture \(index)", areaHint: nil, sourceURLString: nil, sourceLine: index))
    }
    return PlaceImportSnapshot(batches: [PlaceImportBatch(id: "scheduling-batch", source: source,
        sourceName: "Fixture import", totalCount: count, automaticSaveRequested: automatic,
        requestedStatus: .wannaGo)], items: items)
}

private func schedulingResolution(_ seed: PlaceImportSeed) -> PlaceImportResolution {
    let candidate = PlaceCandidate(id: "candidate-\(seed.id)", name: seed.nameHint ?? seed.id,
        category: "park", latitude: 34 + Double(seed.sourceLine) * 0.01, longitude: -118,
        sourceProvider: "fixture", sourceProviderPlaceID: seed.id, confidence: 1)
    return .candidates([candidate], selectedCandidateID: candidate.id)
}

@MainActor
private final class DelayedSchedulingResolver: PlaceImportResolving {
    private(set) var startedCount = 0
    private(set) var maximumActive = 0
    private var active = 0

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        startedCount += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(seed.sourceLine.isMultiple(of: 6) ? 180 : 10))
        return schedulingResolution(seed)
    }
}

@MainActor
private final class GatedSchedulingResolver: PlaceImportResolving {
    private(set) var startedIDs: [String] = []
    private(set) var maximumActive = 0
    private var active = 0
    private var attempts: [String: Int] = [:]
    private var pending: [String: (PlaceImportSeed, CheckedContinuation<PlaceImportResolution, Never>)] = [:]
    private var progress: [String: @MainActor (PlaceImportMatchingProgress) -> Void] = [:]
    private var isOpen = false
    private var heldID: String?

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await resolve(seed: seed, source: source, onProgress: { _ in })
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource,
                 onProgress: @escaping @MainActor (PlaceImportMatchingProgress) -> Void) async throws -> PlaceImportResolution {
        attempts[seed.id, default: 0] += 1
        let id = "\(seed.id):\(attempts[seed.id, default: 0])"
        startedIDs.append(id)
        progress[id] = onProgress
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if isOpen, id != heldID { return schedulingResolution(seed) }
        // Intentionally ignores cancellation to model a late provider callback.
        return await withCheckedContinuation { pending[id] = (seed, $0) }
    }

    func emitProgress(_ id: String) {
        progress[id]?(.init(totalCount: 1, completedCount: 1, resolvedCount: 1))
    }

    func finish(_ id: String, resolution: PlaceImportResolution? = nil) {
        guard let (seed, continuation) = pending.removeValue(forKey: id) else { return }
        continuation.resume(returning: resolution ?? schedulingResolution(seed))
    }

    func openAll(except id: String? = nil) {
        isOpen = true
        heldID = id
        for pendingID in Array(pending.keys) where pendingID != id { finish(pendingID) }
    }
}

private final class SchedulingPersistence: PlaceImportPersisting {
    private(set) var snapshot: PlaceImportSnapshot
    init(snapshot: PlaceImportSnapshot) { self.snapshot = snapshot }
    func load() throws -> PlaceImportSnapshot { snapshot }
    func save(_ snapshot: PlaceImportSnapshot) throws { self.snapshot = snapshot }
}
