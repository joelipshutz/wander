import Foundation
import XCTest
@testable import Wander

@MainActor
final class PlaceImportManualReceiptCheckpointTests: XCTestCase {
    func testOnlyChangedReceiptItemsTakeManualOwnershipAndRemovalKeepsATombstone() throws {
        let fixture = try ManualReceiptFixture(count: 3)
        defer { fixture.removeFiles() }
        let original = fixture.entry(itemID: "item-0", id: "automatic-entry", status: .wannaGo)
        var batch = try XCTUnwrap(fixture.importStore.batches.first)
        batch.receipt = PlaceImportReceipt(batchID: batch.id, sourceName: batch.sourceName,
            entries: [original], destinationListID: nil)
        try fixture.importPersistence.save(PlaceImportSnapshot(ownerUserID: fixture.ownerID,
            batches: [batch], items: fixture.importStore.items))
        fixture.restore()

        let manual = fixture.entry(itemID: "item-1", id: "manual-entry", status: .been)
        fixture.importStore.recordReceipt(batchID: batch.id, entries: [original, manual], destinationListID: nil)
        XCTAssertEqual(fixture.importStore.batches.first?.automaticSaveReceiptOverrideItemIDs, ["item-1"])
        fixture.importStore.recordReceipt(batchID: batch.id, entries: [original, manual], destinationListID: nil)
        XCTAssertEqual(fixture.importStore.batches.first?.automaticSaveReceiptOverrideItemIDs, ["item-1"])
        fixture.importStore.recordReceipt(batchID: batch.id, entries: [original], destinationListID: nil)
        fixture.restore()
        XCTAssertEqual(fixture.importStore.batches.first?.automaticSaveReceiptOverrideItemIDs, ["item-1"])
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries, [original])

        let encoded = try JSONEncoder().encode(try XCTUnwrap(fixture.importStore.batches.first))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "automaticSaveReceiptOverrideItemIDs")
        let decoded = try JSONDecoder().decode(PlaceImportBatch.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.automaticSaveReceiptOverrideItemIDs)
    }

    func testReviewDuringLibraryAckKeepsRemovedSelectionAndOtherManualEntriesAfterRestart() async throws {
        let fixture = try ManualReceiptFixture(count: 3)
        defer { fixture.removeFiles() }
        var reviewed = false
        var manualEntries: [PlaceImportReceiptEntry] = []
        var manualReceiptID: String?
        var removedSaveID: String?
        let interrupted = await fixture.process(afterLibraryCheckpoint: {
            guard !reviewed else { return }
            reviewed = true
            let item = try XCTUnwrap(fixture.importStore.item(id: "item-0"))
            let existing = try XCTUnwrap(fixture.store.existingImportSave(matching: try XCTUnwrap(item.selectedCandidate)))
            removedSaveID = existing.userPlaceID
            // This is the review screen's reconcileListSaves path while the
            // library row exists but the automatic import metadata is still ready.
            let reconciled = fixture.entry(itemID: item.id, id: "review-generated-entry", status: .wannaGo,
                outcome: .existing, userPlaceID: existing.userPlaceID)
            fixture.importStore.markSaved(itemID: item.id, userPlaceID: existing.userPlaceID)
            fixture.importStore.recordReceipt(batchID: fixture.batchID, entries: [reconciled], destinationListID: nil)
            let selection = fixture.store.importSelection(for: reconciled, item: item)
            XCTAssertTrue(fixture.store.removeImportedSelection(
                PlaceImportSavedSelectionRemoval(itemID: item.id, status: .wannaGo,
                    visitID: nil, wannaID: selection.wannaID, wannaIsOriginal: selection.wannaIsOriginal),
                entry: reconciled, item: item))
            let removed = fixture.entry(itemID: item.id, id: reconciled.id, status: nil,
                outcome: .existing, userPlaceID: existing.userPlaceID,
                selection: PlaceImportSavedSelection(status: nil, visitID: nil, listIDs: []))

            // A separate ready item can be manually saved before automatic
            // work resumes. Its entry must not disappear from the later receipt.
            let third = try XCTUnwrap(fixture.importStore.item(id: "item-2"))
            let saved = fixture.store.saveImportedCandidate(try XCTUnwrap(third.selectedCandidate),
                status: .been, visibility: .selfOnly, note: "Reviewed details", sourceType: .link)
            fixture.importStore.markSaved(itemID: third.id, userPlaceID: saved.userPlaceID)
            let visitID = try XCTUnwrap(fixture.store.visits(for: saved.userPlaceID).first?.id)
            let added = fixture.entry(itemID: third.id, id: "manual-other-item", status: .been,
                userPlaceID: saved.userPlaceID,
                selection: PlaceImportSavedSelection(status: .been, visitID: visitID, listIDs: []))
            manualEntries = [removed, added]
            fixture.store.flushPersistence()
            fixture.importStore.recordReceipt(batchID: fixture.batchID, entries: manualEntries, destinationListID: nil)
            manualReceiptID = fixture.importStore.batches.first?.receipt?.id
            fixture.importStore.markReceiptPresented(receiptID: try XCTUnwrap(manualReceiptID))
        })
        XCTAssertFalse(interrupted.hasResult)
        XCTAssertEqual(fixture.importStore.batches.first?.automaticSaveReceiptOverrideItemIDs, ["item-0", "item-2"])
        fixture.restore()
        let result = await fixture.process()
        XCTAssertEqual(result.batchIDs, [fixture.batchID])
        let receipt = try XCTUnwrap(fixture.importStore.batches.first?.receipt)
        XCTAssertEqual(receipt.id, manualReceiptID)
        XCTAssertNotNil(receipt.presentedAt)
        XCTAssertEqual(receipt.entries.map(\.itemID), ["item-0", "item-1", "item-2"])
        XCTAssertEqual(receipt.entries.filter { $0.itemID != "item-1" }, manualEntries)
        XCTAssertEqual(receipt.entries[1].outcome, .added)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
        XCTAssertNotNil(fixture.store.userPlaces.first { $0.id == removedSaveID }?.deletedAt)
        XCTAssertEqual(fixture.store.currentUserVisiblePlaces.count, 2)
        XCTAssertEqual(fixture.store.placeVisits.filter { $0.deletedAt == nil }.count, 1)
        fixture.restore()
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries, receipt.entries)
    }

    func testExplicitlyRemovedReceiptEntryCannotReturnFromAnOlderJournal() async throws {
        let fixture = try ManualReceiptFixture(count: 3)
        defer { fixture.removeFiles() }
        var reviewed = false
        _ = await fixture.process(afterLibraryCheckpoint: {
            guard !reviewed else { return }
            reviewed = true
            let item = try XCTUnwrap(fixture.importStore.item(id: "item-0"))
            let saved = try XCTUnwrap(fixture.store.existingImportSave(matching: try XCTUnwrap(item.selectedCandidate)))
            fixture.importStore.markSaved(itemID: item.id, userPlaceID: saved.userPlaceID)
            let entry = fixture.entry(itemID: item.id, id: "removed-card", status: .wannaGo, userPlaceID: saved.userPlaceID)
            fixture.importStore.recordReceipt(batchID: fixture.batchID, entries: [entry], destinationListID: nil)
            fixture.importStore.recordReceipt(batchID: fixture.batchID, entries: [], destinationListID: nil)
        })
        fixture.restore()
        XCTAssertEqual(fixture.importStore.batches.first?.automaticSaveReceiptOverrideItemIDs, ["item-0"])
        let result = await fixture.process()
        XCTAssertEqual(result.batchIDs, [fixture.batchID])
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries.map(\.itemID), ["item-1", "item-2"])
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
    }
}

@MainActor
private final class ManualReceiptFixture {
    let batchID = "manual-receipt-batch"
    let ownerID: String
    let directory: URL
    let libraryPersistence: WanderStorePersistence
    let importPersistence: FilePlaceImportPersistence
    var store: WanderStore
    var importStore: PlaceImportStore

    init(count: Int) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("manual-receipt-checkpoint-\(UUID().uuidString)", isDirectory: true)
        libraryPersistence = .coalescingFile(url: directory.appendingPathComponent("library.json"))
        importPersistence = FilePlaceImportPersistence(fileURL: directory.appendingPathComponent("imports.json"))
        store = WanderStore(fixtures: .empty(), persistence: libraryPersistence)
        ownerID = store.currentUser.id
        try libraryPersistence.checkpoint(WanderStoreSnapshot(store: store))
        let batch = PlaceImportBatch(id: batchID, source: .googleMaps, sourceName: "Fixture",
            state: .ready, totalCount: count, processedCount: count,
            automaticSaveRequested: true, requestedStatus: .wannaGo)
        let rows = (0..<count).map { index -> PlaceImportItem in
            let candidate = PlaceCandidate(id: "manual-fixture-\(index)", name: "Fixture \(index)",
                category: "park", latitude: 34 + Double(index) * 0.01, longitude: -118,
                sourceProvider: "fixture", sourceProviderPlaceID: "provider-\(index)", confidence: 1)
            return PlaceImportItem(id: "item-\(index)", batchID: batch.id, source: .googleMaps,
                seed: PlaceImportSeed(id: "seed-\(index)", rawText: candidate.name, nameHint: candidate.name,
                    areaHint: nil, sourceURLString: nil, sourceLine: index),
                state: .ready, candidates: [candidate], selectedCandidateID: candidate.id)
        }
        try importPersistence.save(PlaceImportSnapshot(ownerUserID: ownerID, batches: [batch], items: Array(rows.reversed())))
        importStore = PlaceImportStore(persistence: importPersistence, resolver: ManualReceiptResolver())
    }

    func restore() {
        libraryPersistence.flush()
        store = WanderStore(fixtures: .empty(), persistence: libraryPersistence)
        importStore = PlaceImportStore(persistence: importPersistence, resolver: ManualReceiptResolver())
    }

    func process(afterLibraryCheckpoint: (@MainActor () throws -> Void)? = nil) async -> PlaceImportAutoSaveResult {
        await PlaceImportAutoSaveCoordinator.process(batchIDs: [batchID], importStore: importStore, store: store,
            expectedUserID: ownerID, chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600),
            afterLibraryCheckpoint: afterLibraryCheckpoint, isAuthorized: { true })
    }

    func entry(itemID: String, id: String, status: PlaceStatus?, outcome: PlaceImportReceiptOutcome = .added,
               userPlaceID: String? = nil, selection: PlaceImportSavedSelection? = nil) -> PlaceImportReceiptEntry {
        PlaceImportReceiptEntry(id: id, itemID: itemID, displayName: "Fixture", displayArea: nil,
            status: status, outcome: outcome, userPlaceID: userPlaceID, savedSelection: selection)
    }

    func removeFiles() {
        libraryPersistence.flush()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private struct ManualReceiptResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Ready fixture rows must not call a resolver")
        return .needsHelp("Unexpected fixture lookup")
    }
}
