import Combine
import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportFileSchedulingPerformanceTests: XCTestCase {
    /// Keep unchanged on both revisions. Eighteen uneven lookups update a
    /// realistic 1,500-row snapshot through the production atomic file writer.
    /// Initial fixture creation/load is excluded; all processing writes count.
    func testPerformanceFileBackedGoogleImportWithUnevenLookupLatency() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec675-import-file-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let rowCount = 1_500
        let resolvingCount = 18
        var completionSamples: [Double] = []
        var firstReadySamples: [Double] = []
        var persistenceSamples: [Double] = []
        var writeCounts: [Int] = []
        var heartbeatGaps: [Double] = []
        var finalByteCounts: [Int] = []

        for sample in 0..<3 {
            let fileURL = directory.appendingPathComponent("sample-\(sample).json")
            try FilePlaceImportPersistence(fileURL: fileURL).save(
                fileSchedulingSnapshot(rowCount: rowCount, resolvingCount: resolvingCount))
            let persistence = MeasuredImportFilePersistence(fileURL: fileURL)
            let resolver = FileSchedulingResolver()
            let store = PlaceImportStore(persistence: persistence, resolver: resolver)
            XCTAssertEqual(store.items.filter { $0.state == .ready }.count, rowCount - resolvingCount)
            persistence.resetMeasurements()

            let heartbeat = FileSchedulingHeartbeat()
            let heartbeatTask = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeat.tick()
                    do { try await Task.sleep(for: .milliseconds(5)) }
                    catch { return }
                }
            }
            await Task.yield()
            heartbeat.reset()
            var firstReadyMilliseconds: Double?
            let startedAt = ProcessInfo.processInfo.systemUptime
            let subscription = store.$items.sink { items in
                if firstReadyMilliseconds == nil,
                   items.contains(where: { $0.seed.sourceLine < resolvingCount && $0.state == .ready }) {
                    firstReadyMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                }
            }
            store.resumePendingImports()
            await store.waitForProcessing(batchID: "file-scheduling-batch")
            completionSamples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            heartbeat.tick()
            heartbeatTask.cancel()
            await heartbeatTask.value
            subscription.cancel()
            firstReadySamples.append(firstReadyMilliseconds ?? -1)
            persistenceSamples.append(persistence.saveMilliseconds)
            writeCounts.append(persistence.saveCount)
            heartbeatGaps.append(heartbeat.maximumGapMilliseconds)

            let restored = try FilePlaceImportPersistence(fileURL: fileURL).load()
            finalByteCounts.append(try Data(contentsOf: fileURL).count)
            XCTAssertEqual(resolver.startedCount, resolvingCount)
            XCTAssertGreaterThan(resolver.maximumActive, 1)
            XCTAssertLessThanOrEqual(resolver.maximumActive, 6)
            XCTAssertNotNil(firstReadyMilliseconds)
            XCTAssertEqual(store.items(for: "file-scheduling-batch").map(\.id), (0..<rowCount).map { "file-item-\($0)" })
            XCTAssertTrue(store.items.allSatisfy { $0.state == .ready })
            XCTAssertEqual(restored.items.map(\.id), store.items.map(\.id))
            XCTAssertEqual(restored.items.map(\.state), store.items.map(\.state))
            XCTAssertEqual(restored.items.map(\.selectedCandidateID), store.items.map(\.selectedCandidateID))
            XCTAssertEqual(restored.ownerUserID, "file-scheduling-owner")
            let batch = try XCTUnwrap(restored.batches.first)
            XCTAssertEqual(batch.totalCount, rowCount)
            XCTAssertEqual(batch.processedCount, rowCount)
            XCTAssertEqual(batch.state, .ready)
            XCTAssertEqual(batch.sourceName, "File scheduling fixture")
            XCTAssertNil(store.persistenceError)
        }

        report("REC675 import_file_scheduler rows=\(rowCount) resolving=\(resolvingCount) slow_ms=180 fast_ms=10 completion_samples_ms=\(completionSamples) completion_median_ms=\(completionSamples.sorted()[1]) first_ready_samples_ms=\(firstReadySamples) first_ready_median_ms=\(firstReadySamples.sorted()[1]) persistence_samples_ms=\(persistenceSamples) write_counts=\(writeCounts) heartbeat_max_gap_ms=\(heartbeatGaps) final_bytes=\(finalByteCounts)")
    }

    /// Diagnostic only: both encodings decode to identical values. This shows
    /// how much deterministic key sorting costs before changing the file writer.
    func testPerformanceImportSnapshotJSONKeySorting() throws {
        let snapshot = fileSchedulingSnapshot(rowCount: 1_500, resolvingCount: 0)
        var sortedSamples: [Double] = []
        var unsortedSamples: [Double] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for sample in 0..<3 {
            for sorted in (sample.isMultiple(of: 2) ? [true, false] : [false, true]) {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                if sorted { encoder.outputFormatting = [.sortedKeys] }
                let startedAt = ProcessInfo.processInfo.systemUptime
                let data = try encoder.encode(snapshot)
                let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                if sorted { sortedSamples.append(elapsed) } else { unsortedSamples.append(elapsed) }
                XCTAssertEqual(try decoder.decode(PlaceImportSnapshot.self, from: data), snapshot)
            }
        }
        report("REC675 import_snapshot_key_sorting rows=1500 sorted_samples_ms=\(sortedSamples) sorted_median_ms=\(sortedSamples.sorted()[1]) unsorted_samples_ms=\(unsortedSamples) unsorted_median_ms=\(unsortedSamples.sorted()[1])")
    }

    private func report(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private func fileSchedulingSnapshot(rowCount: Int, resolvingCount: Int) -> PlaceImportSnapshot {
    let timestamp = Date(timeIntervalSince1970: 1_735_689_600)
    let items = (0..<rowCount).map { index in
        let seed = PlaceImportSeed(id: "file-seed-\(index)", rawText: "File fixture \(index)",
            nameHint: "File fixture \(index)", areaHint: "Fixture region", sourceURLString: nil, sourceLine: index)
        let candidate = fileSchedulingCandidate(seed)
        return PlaceImportItem(id: "file-item-\(index)", batchID: "file-scheduling-batch", source: .googleMaps,
            seed: seed, state: index < resolvingCount ? .queued : .ready,
            candidates: index < resolvingCount ? [] : [candidate],
            selectedCandidateID: index < resolvingCount ? nil : candidate.id,
            resolverVersion: PlaceImportItem.currentResolverVersion,
            createdAt: timestamp, updatedAt: timestamp)
    }
    return PlaceImportSnapshot(ownerUserID: "file-scheduling-owner", batches: [PlaceImportBatch(
        id: "file-scheduling-batch", source: .googleMaps, sourceName: "File scheduling fixture",
        createdAt: timestamp, updatedAt: timestamp, state: .processing,
        totalCount: rowCount, processedCount: rowCount - resolvingCount)], items: items)
}

private func fileSchedulingCandidate(_ seed: PlaceImportSeed) -> PlaceCandidate {
    PlaceCandidate(id: "candidate-\(seed.id)", name: seed.nameHint ?? seed.id, category: "park",
        address: "\(seed.sourceLine + 1) Fixture Street", locality: "Fixture city", region: "CA", country: "US",
        latitude: 34 + Double(seed.sourceLine) * 0.001, longitude: -118,
        sourceProvider: "fixture", sourceProviderPlaceID: seed.id, confidence: 1)
}

@MainActor
private final class FileSchedulingResolver: PlaceImportResolving {
    private(set) var startedCount = 0
    private(set) var maximumActive = 0
    private var active = 0

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        startedCount += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(seed.sourceLine.isMultiple(of: 6) ? 180 : 10))
        let candidate = fileSchedulingCandidate(seed)
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }
}

private final class MeasuredImportFilePersistence: PlaceImportPersisting {
    private let file: FilePlaceImportPersistence
    private(set) var saveCount = 0
    private(set) var saveMilliseconds = 0.0

    init(fileURL: URL) { file = FilePlaceImportPersistence(fileURL: fileURL) }
    func load() throws -> PlaceImportSnapshot { try file.load() }
    func save(_ snapshot: PlaceImportSnapshot) throws {
        let startedAt = ProcessInfo.processInfo.systemUptime
        try file.save(snapshot)
        saveMilliseconds += (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        saveCount += 1
    }
    func resetMeasurements() { saveCount = 0; saveMilliseconds = 0 }
}

@MainActor
private final class FileSchedulingHeartbeat {
    private var previousTick = ProcessInfo.processInfo.systemUptime
    private(set) var maximumGapMilliseconds = 0.0

    func reset() {
        previousTick = ProcessInfo.processInfo.systemUptime
        maximumGapMilliseconds = 0
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        maximumGapMilliseconds = max(maximumGapMilliseconds, (now - previousTick) * 1_000)
        previousTick = now
    }
}
