import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportPerformanceTests: XCTestCase {
    func testPerformanceSinglePassImportCompletionWith1500Rows() {
        var samples: [Double] = []
        for _ in 0..<3 {
            let persistence = ImportPerformancePersistence(snapshot: fixture(rowCount: 1_500))
            let store = PlaceImportStore(persistence: persistence, resolver: ImportPerformanceResolver())
            let savedIDs = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, "saved-\($0.id)") })
            let startedAt = ProcessInfo.processInfo.systemUptime
            store.performBatchedMutations { store.markSavedItems(savedIDs) }
            samples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            XCTAssertEqual(store.items.filter { $0.state == .saved }.count, 1_500)
            XCTAssertTrue(store.items.allSatisfy { $0.savedUserPlaceID == savedIDs[$0.id] })
            XCTAssertEqual(store.batches.first?.state, .complete)
            XCTAssertEqual(store.batches.first?.processedCount, 1_500)
            XCTAssertEqual(persistence.saveCount, 1)
            XCTAssertEqual(persistence.snapshot.items, store.items)
            XCTAssertEqual(persistence.snapshot.batches, store.batches)
        }
        let attachment = XCTAttachment(string:
            "REC675 import_single_pass_completion rows=1500 samples_ms=\(samples) median_ms=\(samples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSinglePassCompletionPreservesOtherRowsSourceRetriesAndSingleRowSemantics() throws {
        var snapshot = fixture(rowCount: 6, batchCount: 2)
        snapshot.items[0].pendingManualSearch = true
        snapshot.items[0].duplicateUserPlaceID = "old-duplicate"
        snapshot.items[0].helpMessage = "Old review message"
        snapshot.items.append(PlaceImportItem(id: "retry", batchID: "batch-1", source: .googleMaps,
            kind: .sourceRetry, seed: PlaceImportSeed(rawText: "Retry", nameHint: nil, areaHint: nil,
                sourceURLString: nil, sourceLine: 100), state: .needsHelp))
        let persistence = ImportPerformancePersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: ImportPerformanceResolver())
        let reference = PlaceImportStore(persistence: ImportPerformancePersistence(snapshot: snapshot),
                                         resolver: ImportPerformanceResolver())
        let originalRows = store.items
        store.markSavedItems([:])
        store.markSavedItems(["absent": "absent-save"])
        XCTAssertEqual(persistence.saveCount, 0)
        let savedIDs = ["item-0": "saved-0", "item-1": "saved-1", "item-2": "saved-2", "absent": "absent-save"]
        store.performBatchedMutations {
            store.markSavedItems(savedIDs)
            XCTAssertEqual(persistence.saveCount, 0)
            XCTAssertEqual(store.batches.first { $0.id == "batch-0" }?.processedCount, 3)
            XCTAssertEqual(store.item(id: "item-0")?.savedUserPlaceID, "saved-0")
        }
        for (id, saveID) in savedIDs { reference.markSaved(itemID: id, userPlaceID: saveID) }
        var actualItems = store.items
        var expectedItems = reference.items
        for index in actualItems.indices {
            actualItems[index].updatedAt = .distantPast
            expectedItems[index].updatedAt = .distantPast
        }
        XCTAssertEqual(actualItems, expectedItems)
        XCTAssertEqual(store.items.map(\.id), originalRows.map(\.id))
        for index in [3, 4, 5, 6] { XCTAssertEqual(store.items[index], originalRows[index]) }
        XCTAssertEqual(store.batches.map(\.state), reference.batches.map(\.state))
        XCTAssertEqual(store.batches.map(\.totalCount), reference.batches.map(\.totalCount))
        XCTAssertEqual(store.batches.map(\.processedCount), reference.batches.map(\.processedCount))
        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(persistence.snapshot.items, store.items)
        XCTAssertEqual(persistence.snapshot.batches, store.batches)
    }

    /// Uses the real import store and excludes fixture construction and disk I/O.
    /// Keep the workload unchanged when collecting the baseline and candidate.
    func testPerformanceBulkImportCompletionWith1500Rows() {
        let rowCount = 1_500
        var samples: [Double] = []
        for _ in 0..<3 {
            let persistence = ImportPerformancePersistence(snapshot: fixture(rowCount: rowCount))
            let store = PlaceImportStore(persistence: persistence, resolver: ImportPerformanceResolver())
            let ids = store.items.map(\.id)
            let startedAt = ProcessInfo.processInfo.systemUptime
            store.performBatchedMutations {
                for id in ids { store.markSaved(itemID: id, userPlaceID: "saved-\(id)") }
            }
            samples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
            XCTAssertEqual(store.items.filter { $0.state == .saved }.count, rowCount)
            XCTAssertEqual(store.batches.first?.state, .complete)
            XCTAssertEqual(store.batches.first?.processedCount, rowCount)
            XCTAssertEqual(persistence.saveCount, 1)
            XCTAssertEqual(persistence.snapshot.items, store.items)
            XCTAssertEqual(persistence.snapshot.batches, store.batches)
        }
        let attachment = XCTAttachment(string:
            "REC675 import_bulk_completion rows=\(rowCount) samples_ms=\(samples) median_ms=\(samples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNestedImportCompletionPersistsFinalSummariesAndKeepsSourceRetryActive() throws {
        var snapshot = fixture(rowCount: 4, batchCount: 2)
        snapshot.items.append(PlaceImportItem(
            id: "retry", batchID: "batch-1", source: .googleMaps, kind: .sourceRetry,
            seed: PlaceImportSeed(rawText: "Retry source", nameHint: nil, areaHint: nil,
                                  sourceURLString: nil, sourceLine: 100), state: .needsHelp
        ))
        let persistence = ImportPerformancePersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: ImportPerformanceResolver())

        store.performBatchedMutations {
            store.markSaved(itemID: "item-0", userPlaceID: "saved-0")
            store.performBatchedMutations {
                for index in 1..<4 { store.markSaved(itemID: "item-\(index)", userPlaceID: "saved-\(index)") }
                XCTAssertEqual(store.batches.first { $0.id == "batch-0" }?.state, .complete,
                    "Batch summaries remain current even before deferred persistence finishes")
                XCTAssertEqual(store.batches.first { $0.id == "batch-1" }?.state, .ready)
            }
            XCTAssertEqual(persistence.saveCount, 0)
        }

        XCTAssertEqual(persistence.saveCount, 1)
        let complete = try XCTUnwrap(store.batches.first { $0.id == "batch-0" })
        let review = try XCTUnwrap(store.batches.first { $0.id == "batch-1" })
        XCTAssertEqual(complete.state, .complete)
        XCTAssertEqual(review.state, .ready)
        XCTAssertEqual(complete.totalCount, 2)
        XCTAssertEqual(review.totalCount, 2)
        XCTAssertEqual(complete.processedCount, 2)
        XCTAssertEqual(review.processedCount, 2)
        XCTAssertEqual(persistence.snapshot.batches, store.batches)
        XCTAssertEqual(store.items(for: "batch-1").map(\.id), ["item-1", "item-3", "retry"])
    }

    func testThrowingImportMutationFlushesCompletedRowsWithoutCompletingUnchangedRows() throws {
        enum Stop: Error { case requested }
        let persistence = ImportPerformancePersistence(snapshot: fixture(rowCount: 3))
        let store = PlaceImportStore(persistence: persistence, resolver: ImportPerformanceResolver())
        XCTAssertThrowsError(try store.performBatchedMutations {
            store.markSaved(itemID: "item-0", userPlaceID: "saved-0")
            throw Stop.requested
        })
        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertEqual(store.items.map(\.state), [.saved, .ready, .ready])
        XCTAssertEqual(store.batches.first?.state, .ready)
        XCTAssertEqual(persistence.snapshot.items, store.items)
        XCTAssertEqual(persistence.snapshot.batches, store.batches)
    }

    private func fixture(rowCount: Int, batchCount: Int = 1) -> PlaceImportSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<rowCount).map { index in
            let candidate = PlaceCandidate(id: "candidate-\(index)", name: "Fixture \(index)",
                category: "park", latitude: 34, longitude: -118,
                sourceProvider: "fixture", sourceProviderPlaceID: "provider-\(index)", confidence: 1)
            return PlaceImportItem(id: "item-\(index)", batchID: "batch-\(index % batchCount)",
                source: .googleMaps,
                seed: PlaceImportSeed(id: "seed-\(index)", rawText: "Fixture \(index)",
                    nameHint: candidate.name, areaHint: nil, sourceURLString: nil, sourceLine: index),
                state: .ready, candidates: [candidate], selectedCandidateID: candidate.id,
                createdAt: timestamp, updatedAt: timestamp)
        }
        let batches = (0..<batchCount).map { index in
            PlaceImportBatch(id: "batch-\(index)", source: .googleMaps, sourceName: "Fixture import",
                createdAt: timestamp, updatedAt: timestamp, state: .ready,
                totalCount: items.filter { $0.batchID == "batch-\(index)" }.count)
        }
        return PlaceImportSnapshot(batches: batches, items: items)
    }
}

private final class ImportPerformancePersistence: PlaceImportPersisting {
    var snapshot: PlaceImportSnapshot
    private(set) var saveCount = 0
    init(snapshot: PlaceImportSnapshot) { self.snapshot = snapshot }
    func load() throws -> PlaceImportSnapshot { snapshot }
    func save(_ snapshot: PlaceImportSnapshot) throws {
        self.snapshot = snapshot
        saveCount += 1
    }
}

@MainActor
private struct ImportPerformanceResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Prepared import fixtures must not perform network resolution")
        return .needsHelp("Unexpected fixture resolution")
    }
}
