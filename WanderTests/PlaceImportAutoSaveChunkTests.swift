import Foundation
import XCTest
@testable import Wander

@MainActor
final class PlaceImportAutoSaveChunkTests: XCTestCase {
    func testFourRowCrashCheckpointReplaysIntraChunkDuplicateAndOriginalReceiptEntries() async throws {
        let fixture = try ChunkFixture(count: 9, duplicateFirstPair: true)
        defer { fixture.removeFiles() }
        let stopped = await fixture.process(maximumRows: 4,
            afterLibraryCheckpoint: { throw ChunkFailure.requested })
        XCTAssertFalse(stopped.hasResult)
        let durable = try XCTUnwrap(fixture.libraryPersistence.load())
        let checkpoint = try XCTUnwrap(durable.automaticImportCheckpoints?.first)
        let originalEntries = checkpoint.completedItems.map(\.entry)
        XCTAssertEqual(checkpoint.completedItems.map(\.itemID), (0..<4).map { "item-\($0)" })
        XCTAssertEqual(originalEntries.map(\.outcome), [.added, .existing, .added, .added])
        let firstSaveID = try XCTUnwrap(originalEntries.first?.userPlaceID)
        XCTAssertEqual(Array(originalEntries.prefix(2)).compactMap(\.userPlaceID), [firstSaveID, firstSaveID])
        XCTAssertEqual(durable.userPlaces.count, 3)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
        XCTAssertEqual(fixture.store.placeListItems.filter { $0.deletedAt == nil }.count, 3)
        XCTAssertFalse(checkpoint.isComplete)
        let unadvanced = try fixture.importPersistence.load()
        XCTAssertEqual(unadvanced.items.count, 9)
        XCTAssertTrue(unadvanced.items.allSatisfy { $0.state != .saved })
        XCTAssertNil(unadvanced.batches.first?.receipt)
        XCTAssertNil(unadvanced.batches.first?.automaticSaveCompletedAt)

        fixture.restoreBothStores()
        let recovered = await fixture.process(maximumRows: 4)
        XCTAssertEqual(recovered.addedCount, 8)
        XCTAssertEqual(recovered.existingCount, 1)
        let receipt = try XCTUnwrap(fixture.importStore.batches.first?.receipt)
        XCTAssertEqual(receipt.id, checkpoint.receiptID)
        XCTAssertEqual(receipt.entries.map(\.itemID), (0..<9).map { "item-\($0)" })
        XCTAssertEqual(Array(receipt.entries.prefix(4)), originalEntries,
            "Replay must preserve all four entry IDs, outcomes and original saved parents")
        XCTAssertEqual(fixture.store.userPlaces.count, 8)
        XCTAssertEqual(Set(fixture.store.userPlaces.map(\.id)).count, 8)
        XCTAssertTrue(Set(originalEntries.compactMap(\.userPlaceID))
            .isSubset(of: Set(fixture.store.userPlaces.map(\.id))))
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
        XCTAssertEqual(fixture.store.placeListItems.filter { $0.deletedAt == nil }.count, 8)
        XCTAssertTrue(fixture.store.importNotificationCommits.allSatisfy { $0.silent && $0.locallyComplete })
        XCTAssertEqual(try fixture.importPersistence.load().batches.first?.receipt, receipt)
        let completedLibrary = try XCTUnwrap(fixture.libraryPersistence.load())
        XCTAssertEqual(completedLibrary.userPlaces.count, 8)
        XCTAssertEqual(completedLibrary.automaticImportCheckpoints, [])
    }

    func testHeldFourRowAcknowledgmentCannotPublishAfterCancellationOrAccountChange() async throws {
        for changesAccount in [false, true] {
            let fixture = try ChunkFixture(count: 9)
            defer { fixture.removeFiles() }
            let gate = ChunkGate()
            fixture.afterLibraryWrite = { await gate.suspend() }
            let task = Task { @MainActor in await fixture.process(maximumRows: 4) }
            defer { task.cancel(); gate.release() }
            await gate.waitUntilArrived()
            let durable = try XCTUnwrap(fixture.libraryPersistence.load())
            let checkpoint = try XCTUnwrap(durable.automaticImportCheckpoints?.first)
            let originalEntries = checkpoint.completedItems.map(\.entry)
            XCTAssertEqual(originalEntries.map(\.itemID), (0..<4).map { "item-\($0)" })
            XCTAssertEqual(originalEntries.map(\.outcome), Array(repeating: .added, count: 4))
            XCTAssertEqual(durable.userPlaces.count, 4)
            let savedIDs = Set(fixture.store.userPlaces.map(\.id))
            XCTAssertEqual(savedIDs.count, 4)
            XCTAssertTrue(try fixture.importPersistence.load().items.allSatisfy { $0.state != .saved })
            XCTAssertNil(fixture.importStore.batches.first?.receipt)
            if changesAccount {
                fixture.store.apply(authState: .signedIn(AuthSession(userID: "other-owner",
                    displayName: "Other", handle: "other")))
                fixture.importStore.bind(to: "other-owner")
            } else {
                task.cancel()
            }
            gate.release()
            let result = await task.value
            XCTAssertFalse(result.hasResult)
            XCTAssertTrue(result.retryBatchIDs.isEmpty)
            XCTAssertEqual(Set(fixture.store.userPlaces.map(\.id)), savedIDs,
                "The stale task cannot save any of the five remaining rows")
            XCTAssertTrue(fixture.store.userPlaces.allSatisfy { $0.userID == fixture.ownerID })
            XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state != .saved })
            XCTAssertTrue(fixture.importStore.batches.allSatisfy {
                $0.receipt == nil && $0.automaticSaveCompletedAt == nil
            })
            let metadata = try fixture.importPersistence.load()
            XCTAssertTrue(metadata.items.allSatisfy { $0.state != .saved })
            XCTAssertTrue(metadata.batches.allSatisfy { $0.receipt == nil && $0.automaticSaveCompletedAt == nil })
            fixture.afterLibraryWrite = nil
            if changesAccount {
                XCTAssertEqual(metadata.ownerUserID, "other-owner")
                XCTAssertTrue(metadata.items.isEmpty)
                XCTAssertTrue(metadata.batches.isEmpty)
            } else {
                XCTAssertEqual(metadata.items.count, 9)
                fixture.restoreBothStores()
                let recovered = await fixture.process(maximumRows: 4)
                XCTAssertEqual(recovered.addedCount, 9)
                XCTAssertEqual(recovered.existingCount, 0)
                XCTAssertEqual(fixture.store.userPlaces.count, 9)
                let receipt = try XCTUnwrap(fixture.importStore.batches.first?.receipt)
                XCTAssertEqual(receipt.id, checkpoint.receiptID)
                XCTAssertEqual(Array(receipt.entries.prefix(4)), originalEntries)
                XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
            }
        }
    }

    func testActualFileCrashBetweenLibraryAndImportCheckpointReplaysOriginalOutcomes() async throws {
        let fixture = try ChunkFixture(count: 5, duplicateFirstPair: true)
        defer { fixture.removeFiles() }
        var stopped = false
        let first = await fixture.process(maximumRows: 1, afterLibraryCheckpoint: {
            if !stopped { stopped = true; throw ChunkFailure.requested }
        })
        XCTAssertFalse(first.hasResult)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
        let saveID = try XCTUnwrap(fixture.store.userPlaces.first?.id)
        let durableLibrary = try XCTUnwrap(fixture.libraryPersistence.load())
        XCTAssertEqual(durableLibrary.userPlaces.count, 1)
        XCTAssertEqual(try fixture.importPersistence.load().items.filter { $0.state == .saved }.count, 0)

        fixture.restoreBothStores()
        let result = await fixture.process(maximumRows: 1)
        XCTAssertEqual(result.addedCount, 4)
        XCTAssertEqual(result.existingCount, 1)
        let receipt = try XCTUnwrap(fixture.importStore.batches.first?.receipt)
        XCTAssertEqual(receipt.entries.map(\.itemID), (0..<5).map { "item-\($0)" })
        XCTAssertEqual(Array(receipt.entries.prefix(2)).map(\.outcome), [.added, .existing])
        XCTAssertEqual(Array(receipt.entries.prefix(2)).compactMap(\.userPlaceID), [saveID, saveID])
        XCTAssertEqual(fixture.store.userPlaces.count, 4)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
        XCTAssertEqual(fixture.store.placeListItems.filter { $0.deletedAt == nil }.count, 4)
        XCTAssertTrue(fixture.store.importNotificationCommits.allSatisfy { $0.silent && $0.locallyComplete })
        XCTAssertEqual(try fixture.importPersistence.load().batches.first?.receipt?.id, receipt.id)
    }

    func testFailedLibraryWriteCannotAdvanceImportAndSameMemoryRetryDoesNotResave() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        fixture.failLibrary = true
        let failed = await fixture.process(maximumRows: 1)
        XCTAssertFalse(failed.hasResult)
        XCTAssertTrue(failed.retryBatchIDs.isEmpty)
        XCTAssertNotNil(fixture.importStore.persistenceError)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
        let savedID = try XCTUnwrap(fixture.store.userPlaces.first?.id)
        XCTAssertTrue(try XCTUnwrap(fixture.libraryPersistence.load()).userPlaces.isEmpty)
        XCTAssertTrue(try fixture.importPersistence.load().items.allSatisfy { $0.state != .saved })
        fixture.failLibrary = false
        let result = await fixture.process(maximumRows: 1)
        XCTAssertEqual(result.addedCount, 3)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries.first?.userPlaceID, savedID)
    }

    func testFailedImportWriteRollsBackOnlyMetadataAndRestoredLibraryJournalRepairsIt() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        fixture.failImport = true
        let failed = await fixture.process(maximumRows: 1)
        XCTAssertFalse(failed.hasResult)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state != .saved })
        XCTAssertNil(fixture.importStore.batches.first?.automaticSaveCompletedAt)
        let savedID = try XCTUnwrap(fixture.store.userPlaces.first?.id)
        fixture.failImport = false
        fixture.restoreBothStores()
        let result = await fixture.process(maximumRows: 1)
        XCTAssertEqual(result.addedCount, 3)
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries.first?.userPlaceID, savedID)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
    }

    func testPauseAfterCheckpointStopsFurtherRowsAndResumeRetainsStableReceipt() async throws {
        let fixture = try ChunkFixture(count: 5)
        defer { fixture.removeFiles() }
        var paused = false
        let first = await fixture.process(maximumRows: 2, betweenChunks: {
            if !paused { paused = true; fixture.importStore.pauseProcessing(batchIDs: [fixture.batchID]) }
        })
        XCTAssertFalse(first.hasResult)
        XCTAssertEqual(fixture.store.userPlaces.count, 2)
        let receiptID = try XCTUnwrap(fixture.importStore.batches.first?.receipt?.id)
        XCTAssertNil(fixture.importStore.batches.first?.automaticSaveCompletedAt)
        fixture.restoreBothStores()
        let finished = await fixture.process(maximumRows: 2)
        XCTAssertEqual(finished.addedCount, 5)
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.id, receiptID)
        XCTAssertEqual(fixture.store.userPlaces.count, 5)
    }

    func testEditedUncommittedInputsRemainForReviewAfterStopAndRestart() async throws {
        for edit in 0..<3 {
            let fixture = try ChunkFixture(count: 3)
            defer { fixture.removeFiles() }
            var stopped = false
            _ = await fixture.process(maximumRows: 1, betweenChunks: {
                guard !stopped else { return }; stopped = true
                switch edit {
                case 0: fixture.importStore.setStagedNote("User changed this", itemID: "item-1")
                case 1: fixture.importStore.setStagedStatus(.been, itemID: "item-1")
                default: fixture.importStore.setIncludedInImport(false, itemID: "item-1")
                }
            })
            XCTAssertEqual(fixture.store.userPlaces.count, 1)
            fixture.restoreBothStores()
            let result = await fixture.process(maximumRows: 1)
            XCTAssertEqual(result.addedCount, 2)
            XCTAssertEqual(result.needsReviewCount, 1)
            XCTAssertEqual(fixture.importStore.item(id: "item-1")?.state, .ready)
            XCTAssertEqual(fixture.store.userPlaces.count, 2)
            XCTAssertTrue(fixture.store.placeVisits.isEmpty)
        }
    }

    func testCancelDeleteAndAccountSwitchBetweenChunksCannotCommitRemainingRows() async throws {
        for action in 0..<3 {
            let fixture = try ChunkFixture(count: 4)
            defer { fixture.removeFiles() }
            var stopped = false
            let result = await fixture.process(maximumRows: 1, betweenChunks: {
                guard !stopped else { return }; stopped = true
                switch action {
                case 0: fixture.importStore.cancel(batchID: fixture.batchID)
                case 1: fixture.importStore.deleteBatch(batchID: fixture.batchID)
                default:
                    fixture.store.apply(authState: .signedIn(AuthSession(userID: "other-owner", displayName: "Other", handle: "other")))
                    fixture.importStore.bind(to: "other-owner")
                }
            })
            XCTAssertFalse(result.hasResult)
            XCTAssertTrue(result.retryBatchIDs.isEmpty)
            XCTAssertEqual(fixture.store.userPlaces.count, 1)
            XCTAssertEqual(fixture.store.userPlaces.first?.userID, fixture.ownerID)
            XCTAssertFalse(fixture.importStore.batches.contains { $0.automaticSaveCompletedAt != nil })
        }
    }

    func testOldRunCleanupCannotClearSameAccountReplacementLease() async throws {
        let fixture = try ChunkFixture(count: 5)
        defer { fixture.removeFiles() }
        let gate = ChunkGate()
        var replacement: Task<PlaceImportAutoSaveResult, Never>?
        var startedReplacement = false
        let original = Task { @MainActor in
            await fixture.process(maximumRows: 1, betweenChunks: {
                guard !startedReplacement else { return }; startedReplacement = true
                replacement = Task { @MainActor in
                    await fixture.process(maximumRows: 1, betweenChunks: { await gate.suspend() })
                }
                await gate.waitUntilArrived()
            })
        }
        defer { original.cancel(); replacement?.cancel(); gate.release() }
        let oldResult = await original.value
        XCTAssertFalse(oldResult.hasResult)
        XCTAssertTrue(oldResult.retryBatchIDs.isEmpty)
        XCTAssertEqual(fixture.store.userPlaces.count, 2)
        gate.release()
        let completed = await replacement?.value
        XCTAssertEqual(completed?.addedCount, 5)
        XCTAssertEqual(fixture.store.userPlaces.count, 5)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
    }

    func testCancellationWhileLibraryAckIsPendingCannotPublishImportProgress() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        let gate = ChunkGate()
        fixture.afterLibraryWrite = { await gate.suspend() }
        let task = Task { @MainActor in await fixture.process(maximumRows: 1) }
        defer { task.cancel(); gate.release() }
        await gate.waitUntilArrived()
        XCTAssertEqual(try XCTUnwrap(fixture.libraryPersistence.load()).userPlaces.count, 1)
        XCTAssertTrue(try fixture.importPersistence.load().items.allSatisfy { $0.state != .saved })
        task.cancel()
        fixture.importStore.pauseProcessing(batchIDs: [fixture.batchID])
        gate.release()
        let result = await task.value
        XCTAssertFalse(result.hasResult)
        XCTAssertTrue(result.retryBatchIDs.isEmpty)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state != .saved })
        fixture.afterLibraryWrite = nil
        let resumed = await fixture.process(maximumRows: 1)
        XCTAssertEqual(resumed.addedCount, 3)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
    }

    func testLateFailedAcknowledgementCannotPublishIntoReplacementLeaseOrAccount() async throws {
        for recovering in [false, true] {
            for changesAccount in [false, true] {
                let fixture = try ChunkFixture(count: 3)
                defer { fixture.removeFiles() }
                if recovering {
                    _ = await fixture.process(maximumRows: 1, afterLibraryCheckpoint: { throw ChunkFailure.requested })
                    fixture.restoreBothStores()
                }
                let gate = ChunkGate()
                fixture.failLibrary = true
                fixture.beforeLibraryWrite = { await gate.suspend() }
                let task = Task { @MainActor in await fixture.process(maximumRows: 1) }
                defer { task.cancel(); gate.release() }
                await gate.waitUntilArrived()
                var replacement: PlaceImportAutoSaveLease?
                if changesAccount {
                    fixture.store.apply(authState: .signedIn(AuthSession(userID: "replacement-owner",
                        displayName: "Replacement", handle: "replacement")))
                    fixture.importStore.bind(to: "replacement-owner")
                } else {
                    replacement = try XCTUnwrap(fixture.importStore.beginAutomaticSaveLease(
                        batchID: fixture.batchID, ownerUserID: fixture.ownerID))
                }
                XCTAssertNil(fixture.importStore.persistenceError)
                gate.release()
                let result = await task.value
                XCTAssertFalse(result.hasResult)
                XCTAssertNil(fixture.importStore.persistenceError)
                if let replacement { XCTAssertTrue(fixture.importStore.ownsAutomaticSaveLease(replacement)) }
                XCTAssertFalse(fixture.importStore.batches.contains { $0.automaticSaveCompletedAt != nil })
            }
        }
    }

    func testUnownedImportFileCannotAcquireAutomaticLeaseOrWriteLibrary() async throws {
        let fixture = try ChunkFixture(count: 2)
        defer { fixture.removeFiles() }
        let owned = try fixture.importPersistence.load()
        try fixture.importPersistence.save(PlaceImportSnapshot(batches: owned.batches, items: owned.items))
        fixture.restoreBothStores()
        XCTAssertNil(fixture.importStore.beginAutomaticSaveLease(batchID: fixture.batchID, ownerUserID: fixture.ownerID))
        let result = await fixture.process(maximumRows: 1)
        XCTAssertFalse(result.hasResult)
        XCTAssertTrue(fixture.store.userPlaces.isEmpty)
        XCTAssertTrue(fixture.store.automaticImportCheckpoints.isEmpty)
        XCTAssertNil(try fixture.importPersistence.load().ownerUserID)
    }

    func testCheckpointDateIdentityMatchesISO8601WireForFractionalAndPreEpochDates() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for seconds in [-1_800_000_000.875, -1.001, -0.875, 0, 0.875, 1_800_000_000.123456] {
            let date = Date(timeIntervalSince1970: seconds)
            let actual = try decoder.decode(Date.self, from: encoder.encode(date))
            XCTAssertEqual(PlaceImportAutoSaveWireDate.normalized(date), actual)
        }
    }

    func testLateSourcePreviewAndDuplicateReconciliationDoNotChangeFrozenSaveIntent() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        let gate = ChunkGate()
        fixture.afterLibraryWrite = { await gate.suspend() }
        let task = Task { @MainActor in await fixture.process(maximumRows: 1) }
        defer { task.cancel(); gate.release() }
        await gate.waitUntilArrived()
        let candidate = try XCTUnwrap(fixture.importStore.item(id: "item-0")?.selectedCandidate)
        let savedID = try XCTUnwrap(fixture.store.userPlaces.first?.id)
        fixture.importStore.updateSourcePreview(batchID: fixture.batchID, title: "Display only",
            thumbnail: "https://example.invalid/fictional-preview.jpg")
        fixture.importStore.reconcileDuplicates(with: [PlaceImportExistingPlace(userPlaceID: savedID,
            name: candidate.name, latitude: candidate.latitude, longitude: candidate.longitude,
            sourceProvider: candidate.sourceProvider, sourceProviderPlaceID: candidate.sourceProviderPlaceID)])
        XCTAssertEqual(fixture.importStore.item(id: "item-0")?.state, .duplicate)
        gate.release()
        let result = await task.value
        XCTAssertEqual(result.addedCount, 3)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertTrue(fixture.importStore.items.allSatisfy { $0.state == .saved })
        XCTAssertEqual(fixture.importStore.batches.first?.receipt?.entries.first?.userPlaceID, savedID)
        XCTAssertTrue(fixture.importStore.items.allSatisfy {
            $0.seed.sourceThumbnailURLString == "https://example.invalid/fictional-preview.jpg"
        })
    }

    func testDestinationDeletedBetweenChunksIsNotRecreatedAndRemainingRowsNeedReview() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        var deleted = false
        let result = await fixture.process(maximumRows: 1, betweenChunks: {
            guard !deleted else { return }; deleted = true
            if let listID = fixture.importStore.batches.first?.destinationListID {
                XCTAssertTrue(fixture.store.deletePlaceList(id: listID))
            } else {
                XCTFail("First durable chunk must publish its destination")
            }
        })
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.needsReviewCount, 2)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
        XCTAssertTrue(fixture.store.visiblePlaceLists.isEmpty)
        XCTAssertEqual(fixture.store.placeLists.count, 1)
        XCTAssertNotNil(fixture.store.placeLists.first?.deletedAt)
    }

    func testCaptureWideBeenEligibilityCannotShrinkIntoAnAutomaticCheckInAfterRestart() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        let sourceRows = fixture.importStore.items(for: fixture.batchID)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let batchIDs = ["capture-wanna", "capture-been-1", "capture-been-2"]
        let batches = batchIDs.enumerated().map { index, id in
            PlaceImportBatch(id: id, source: .googleMaps, sourceName: "Capture",
                captureDeliveryID: "shared-capture:\(index)", createdAt: createdAt.addingTimeInterval(Double(index)),
                state: .ready, totalCount: 1, processedCount: 1, automaticSaveRequested: true,
                requestedStatus: index == 0 ? .wannaGo : .been)
        }
        let rows = sourceRows.enumerated().map { index, item in
            PlaceImportItem(id: item.id, batchID: batchIDs[index], source: item.source, seed: item.seed,
                state: .ready, candidates: item.candidates, selectedCandidateID: item.selectedCandidateID,
                stagedStatus: index == 0 ? .wannaGo : .been)
        }
        try fixture.importPersistence.save(PlaceImportSnapshot(ownerUserID: fixture.ownerID, batches: batches, items: rows))
        fixture.restoreBothStores()
        _ = await PlaceImportAutoSaveCoordinator.process(batchIDs: batchIDs, importStore: fixture.importStore,
            store: fixture.store, expectedUserID: fixture.ownerID,
            chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600),
            afterLibraryCheckpoint: { throw ChunkFailure.requested }, isAuthorized: { true })
        XCTAssertEqual(fixture.store.automaticImportCheckpoints.count, 3)
        XCTAssertTrue(fixture.store.automaticImportCheckpoints.filter { $0.requestedStatus == .been }
            .allSatisfy { $0.eligibleItemIDs.isEmpty })
        fixture.restoreBothStores()
        fixture.importStore.dismiss(itemID: "item-1")
        let result = await PlaceImportAutoSaveCoordinator.process(batchIDs: batchIDs,
            importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
            chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600), isAuthorized: { true })
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.needsReviewCount, 1)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
        XCTAssertTrue(fixture.store.placeVisits.isEmpty)
        XCTAssertEqual(fixture.importStore.item(id: "item-2")?.state, .ready)
    }

    func testManualActionAndListChangesSurvivePendingStrictDuplicatesButNotProviderConflicts() async throws {
        for edit in ChunkManualEdit.allCases {
            for providerConflict in [false, true] {
                let fixture = try ChunkFixture(count: 3, duplicateFirstPair: true,
                    secondCandidateSharesNameOnly: providerConflict)
                defer { fixture.removeFiles() }
                var edited = false
                let interrupted = await fixture.process(maximumRows: 1, betweenChunks: {
                    guard !edited else { return }; edited = true
                    do { try fixture.reviewFirstSavedItem(edit: edit) }
                    catch { XCTFail("Manual fixture edit failed: \(error)") }
                })
                XCTAssertEqual(interrupted.retryBatchIDs, [fixture.batchID])
                XCTAssertFalse(interrupted.hasResult)
                let activeParentsBeforeResume = fixture.store.userPlaces.filter { $0.deletedAt == nil }.count
                if edit == .removeAction {
                    XCTAssertEqual(activeParentsBeforeResume, 0,
                        "edit=\(edit) providerConflict=\(providerConflict)")
                }
                // Do not prime a visibility or calendar projection before
                // resuming: the coordinator must read fresh state itself.
                let final = await PlaceImportAutoSaveCoordinator.process(batchIDs: interrupted.retryBatchIDs,
                    importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
                    chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600), isAuthorized: { true })
                let detail = "edit=\(edit) providerConflict=\(providerConflict) "
                    + "activeParentsBefore=\(activeParentsBeforeResume) "
                    + "visibleAfter=\(fixture.store.currentUserVisiblePlaces.count) "
                    + "activeParentsAfter=\(fixture.store.userPlaces.filter { $0.deletedAt == nil }.count)"
                XCTAssertEqual(final.batchIDs, [fixture.batchID])
                XCTAssertTrue(final.retryBatchIDs.isEmpty)
                let needsReview = !providerConflict && edit != .removeList
                XCTAssertEqual(final.needsReviewCount, needsReview ? 1 : 0, detail)
                let expectedState: PlaceImportItemState = !needsReview ? .saved
                    : (edit == .replaceStatus ? .duplicate : .ready)
                XCTAssertEqual(fixture.importStore.item(id: "item-1")?.state, expectedState, detail)
                if edit == .removeList {
                    XCTAssertEqual(fixture.store.placeListItems.filter { $0.deletedAt == nil }.count,
                        providerConflict ? 2 : 1)
                }
                if edit == .removeAction && !providerConflict {
                    XCTAssertNil(fixture.store.existingImportSave(matching:
                        try XCTUnwrap(fixture.importStore.item(id: "item-1")?.selectedCandidate)))
                }
                XCTAssertEqual(fixture.store.placeVisits.filter { $0.deletedAt == nil }.count,
                    edit == .replaceStatus ? 1 : 0)
            }
        }
    }

    func testSeparateBatchRetainsIndependentIntentAfterPriorBatchManualRemoval() async throws {
        let fixture = try ChunkFixture(count: 3, duplicateFirstPair: true)
        defer { fixture.removeFiles() }
        var edited = false
        _ = await fixture.process(maximumRows: 1, betweenChunks: {
            guard !edited else { return }; edited = true
            do { try fixture.reviewFirstSavedItem(edit: .removeAction) }
            catch { XCTFail("Manual fixture edit failed: \(error)") }
        })
        _ = await fixture.process(maximumRows: 1)
        var snapshot = try fixture.importPersistence.load()
        let original = try XCTUnwrap(fixture.importStore.item(id: "item-1"))
        let separate = PlaceImportBatch(id: "separate-intent", source: .googleMaps, sourceName: "Separate",
            state: .ready, totalCount: 1, processedCount: 1, automaticSaveRequested: true, requestedStatus: .wannaGo)
        snapshot.batches.append(separate)
        snapshot.items.append(PlaceImportItem(id: "separate-item", batchID: separate.id, source: original.source,
            seed: original.seed, state: .ready, candidates: original.candidates,
            selectedCandidateID: original.selectedCandidateID))
        try fixture.importPersistence.save(snapshot)
        fixture.restoreBothStores()
        let result = await PlaceImportAutoSaveCoordinator.process(batchIDs: [separate.id],
            importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
            isAuthorized: { true })
        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertEqual(fixture.importStore.item(id: "separate-item")?.state, .saved)
        XCTAssertEqual(fixture.importStore.item(id: "item-1")?.state, .ready)
    }

    func testDestinationAliasHydrationDuringAcknowledgementKeepsOriginalList() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        let gate = ChunkGate()
        fixture.afterLibraryWrite = { await gate.suspend() }
        let task = Task { @MainActor in await fixture.process(maximumRows: 1) }
        defer { task.cancel(); gate.release() }
        await gate.waitUntilArrived()
        let list = try XCTUnwrap(fixture.store.placeLists.first)
        let localID = list.localID
        let repository = ChunkListRepository()
        let syncedCount = await fixture.store.syncPendingPlaceLists(backend: WanderBackend(placeListRepository: repository))
        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(fixture.store.placeLists.first?.serverID, repository.serverID)
        gate.release()
        let result = await task.value
        XCTAssertEqual(result.addedCount, 3)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertEqual(fixture.store.placeLists.count, 1)
        XCTAssertEqual(fixture.store.placeLists.first?.localID, localID)
        XCTAssertEqual(fixture.importStore.batches.first?.destinationListID, repository.serverID)
        XCTAssertEqual(fixture.store.placeListItems.filter { $0.deletedAt == nil }.count, 3)
    }

    func testRunAuthorizationLossPreventsRetryAfterManualLeaseInvalidation() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        var authorized = true
        let result = await PlaceImportAutoSaveCoordinator.process(batchIDs: [fixture.batchID],
            importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
            chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600),
            betweenChunks: {
                do { try fixture.reviewFirstSavedItem(edit: .removeList) }
                catch { XCTFail("Manual fixture edit failed: \(error)") }
                authorized = false
            }, isAuthorized: { authorized })
        XCTAssertFalse(result.hasResult)
        XCTAssertTrue(result.retryBatchIDs.isEmpty)
        XCTAssertEqual(fixture.store.userPlaces.count, 1)
    }

    func testFinalMetadataFailureRetainsJournalUntilReceiptAcknowledgementThenRetiresIt() async throws {
        let fixture = try ChunkFixture(count: 1)
        defer { fixture.removeFiles() }
        fixture.failImport = true
        let failed = await fixture.process(maximumRows: 1)
        XCTAssertFalse(failed.hasResult)
        let journal = try XCTUnwrap(fixture.store.automaticImportCheckpoints.first)
        XCTAssertTrue(journal.isComplete)
        XCTAssertEqual(try XCTUnwrap(fixture.libraryPersistence.load()).automaticImportCheckpoints?.map(\.id), [journal.id])
        XCTAssertNil(try fixture.importPersistence.load().batches.first?.automaticSaveCompletedAt)
        fixture.failImport = false
        fixture.restoreBothStores()
        let completed = await fixture.process(maximumRows: 1)
        fixture.libraryPersistence.flush()
        XCTAssertEqual(completed.addedCount, 1)
        XCTAssertTrue(fixture.store.automaticImportCheckpoints.isEmpty)
        XCTAssertEqual(try XCTUnwrap(fixture.libraryPersistence.load()).automaticImportCheckpoints, [])
        let receipt = try XCTUnwrap(try fixture.importPersistence.load().batches.first?.receipt)
        XCTAssertEqual(receipt.id, journal.receiptID)
        XCTAssertEqual(receipt.entries, journal.completedItems.map(\.entry))
    }

    func testUndurableCleanupMayRetainJournalButCompletedFileCannotReplaySaves() async throws {
        let fixture = try ChunkFixture(count: 2)
        defer { fixture.removeFiles() }
        fixture.skipOrdinaryLibraryWrites = true
        let completed = await fixture.process(maximumRows: 1)
        XCTAssertEqual(completed.addedCount, 2)
        XCTAssertTrue(fixture.store.automaticImportCheckpoints.isEmpty)
        XCTAssertEqual(try XCTUnwrap(fixture.libraryPersistence.load()).automaticImportCheckpoints?.count, 1)
        let receipt = try XCTUnwrap(try fixture.importPersistence.load().batches.first?.receipt)
        let saveIDs = Set(fixture.store.userPlaces.map(\.id))
        fixture.restoreBothStores()
        let replay = await fixture.process(maximumRows: 1)
        XCTAssertFalse(replay.hasResult)
        XCTAssertTrue(replay.retryBatchIDs.isEmpty)
        XCTAssertEqual(Set(fixture.store.userPlaces.map(\.id)), saveIDs)
        XCTAssertEqual(fixture.importStore.batches.first?.receipt, receipt)
    }

    func testFinishingOneBatchDoesNotReinstallItsPlanWhileAnotherBatchRemainsPartial() async throws {
        let fixture = try ChunkFixture(count: 3)
        defer { fixture.removeFiles() }
        let original = try fixture.importPersistence.load()
        let firstBatch = try XCTUnwrap(original.batches.first)
        let secondBatch = PlaceImportBatch(id: "second-batch", source: .googleMaps, sourceName: "Second",
            createdAt: firstBatch.createdAt.addingTimeInterval(1), state: .ready, totalCount: 2, processedCount: 2,
            automaticSaveRequested: true, requestedStatus: .wannaGo)
        let secondRows = fixture.importStore.items(for: fixture.batchID).dropFirst().map { row in
            PlaceImportItem(id: row.id, batchID: secondBatch.id, source: row.source, seed: row.seed,
                state: .ready, candidates: row.candidates, selectedCandidateID: row.selectedCandidateID)
        }
        var first = firstBatch
        first.totalCount = 1
        first.processedCount = 1
        try fixture.importPersistence.save(PlaceImportSnapshot(ownerUserID: fixture.ownerID,
            batches: [first, secondBatch], items: [try XCTUnwrap(fixture.importStore.item(id: "item-0"))] + secondRows))
        fixture.restoreBothStores()
        var paused = false
        let result = await PlaceImportAutoSaveCoordinator.process(batchIDs: [first.id, secondBatch.id],
            importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
            chunkPolicy: .init(maximumRows: 1, budgetSeconds: 3_600), betweenChunks: {
                if !paused && fixture.store.userPlaces.count == 2 {
                    paused = true
                    fixture.importStore.pauseProcessing(batchIDs: [secondBatch.id])
                }
            }, isAuthorized: { true })
        XCTAssertEqual(result.batchIDs, [first.id])
        XCTAssertEqual(fixture.store.automaticImportCheckpoints.map(\.batchID), [secondBatch.id])
        XCTAssertEqual(fixture.store.automaticImportCheckpoints.first?.completedItems.count, 1)
        let final = await PlaceImportAutoSaveCoordinator.process(batchIDs: [secondBatch.id],
            importStore: fixture.importStore, store: fixture.store, expectedUserID: fixture.ownerID,
            isAuthorized: { true })
        XCTAssertEqual(final.addedCount, 2)
        XCTAssertTrue(fixture.store.automaticImportCheckpoints.isEmpty)
        XCTAssertEqual(fixture.store.userPlaces.count, 3)
    }

    func testReviewReusesPendingDestinationAndExplicitReplacementSurvivesRestart() async throws {
        for sameListThroughHydratedAlias in [false, true] {
            let fixture = try ChunkFixture(count: 3)
            defer { fixture.removeFiles() }
            let gate = ChunkGate()
            fixture.afterLibraryWrite = { await gate.suspend() }
            let task = Task { @MainActor in await fixture.process(maximumRows: 1) }
            defer { task.cancel(); gate.release() }
            await gate.waitUntilArrived()
            let batch = try XCTUnwrap(fixture.importStore.batches.first)
            XCTAssertNil(batch.destinationListID)
            XCTAssertNil(batch.receipt)
            let pending = try XCTUnwrap(fixture.store.existingImportDestinationList(for: batch))
            XCTAssertEqual(pending.id, fixture.store.placeLists.first?.id)
            XCTAssertEqual(fixture.store.placeLists.count, 1)
            XCTAssertNil(fixture.importStore.batches.first?.destinationListID,
                "Reading the shared pending destination cannot publish import progress")

            let chosenID: String
            if sameListThroughHydratedAlias {
                let repository = ChunkListRepository()
                let syncedCount = await fixture.store.syncPendingPlaceLists(backend: WanderBackend(placeListRepository: repository))
                XCTAssertEqual(syncedCount, 1)
                chosenID = repository.serverID
            } else {
                chosenID = try XCTUnwrap(fixture.store.createPlaceList(name: "Manual destination",
                    description: "Fixture", visibility: .stealth)).id
            }
            fixture.importStore.setDestinationListID(chosenID, batchID: batch.id)
            XCTAssertEqual(fixture.store.existingImportDestinationList(for:
                try XCTUnwrap(fixture.importStore.batches.first))?.id, chosenID)
            gate.release()
            let interrupted = await task.value
            XCTAssertEqual(interrupted.retryBatchIDs, [fixture.batchID])
            fixture.libraryPersistence.flush()
            fixture.afterLibraryWrite = nil
            fixture.restoreBothStores()
            let result = await fixture.process(maximumRows: 1)
            XCTAssertEqual(result.addedCount, sameListThroughHydratedAlias ? 3 : 1)
            XCTAssertEqual(result.needsReviewCount, sameListThroughHydratedAlias ? 0 : 2)
            XCTAssertEqual(fixture.store.placeLists.count, sameListThroughHydratedAlias ? 1 : 2)
            XCTAssertEqual(fixture.importStore.batches.first?.destinationListID, chosenID)
            XCTAssertEqual(fixture.importStore.batches.first?.receipt?.destinationListID, chosenID)
            XCTAssertEqual(try fixture.importPersistence.load().batches.first?.automaticSaveDestinationOverrideID, chosenID)
        }
    }
}

private enum ChunkFailure: Error { case requested }
private enum ChunkManualEdit: CaseIterable { case removeAction, removeList, replaceStatus }

@MainActor
private final class ChunkListRepository: PlaceListRepository {
    let serverID = "11111111-1111-4111-8111-111111111111"
    func visibleLists() async throws -> [RemotePlaceListSummary] { [] }
    func detail(listID: String) async throws -> RemotePlaceListDetail? { nil }
    func upsert(_ draft: PlaceListUpsertDraft) async throws -> String { serverID }
    func delete(listID: String) async throws {}
    func setCollaborators(listID: String, userIDs: [String]) async throws {}
    func addItem(_ draft: PlaceListItemDraft) async throws -> String { "22222222-2222-4222-8222-222222222222" }
    func removeItem(listID: String, itemID: String) async throws {}
}

@MainActor
private final class ChunkFixture {
    let ownerID = "chunk-owner"
    let batchID = "chunk-batch"
    let directory: URL
    let libraryPersistence: WanderStorePersistence
    let importPersistence: FilePlaceImportPersistence
    var store: WanderStore
    var importStore: PlaceImportStore
    var failLibrary = false
    var failImport = false
    var skipOrdinaryLibraryWrites = false
    var beforeLibraryWrite: (@MainActor () async -> Void)?
    var afterLibraryWrite: (@MainActor () async -> Void)?

    init(count: Int, duplicateFirstPair: Bool = false, secondCandidateSharesNameOnly: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ImportChunks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        libraryPersistence = .coalescingFile(url: directory.appendingPathComponent("library.json"))
        importPersistence = FilePlaceImportPersistence(fileURL: directory.appendingPathComponent("imports.json"))
        let owner = LocalProfile(localID: "chunk-owner-local", serverID: ownerID, handle: "chunk", displayName: "Chunk")
        let fixtures = WanderFixtures(currentUser: owner, profiles: [owner], places: [], userPlaces: [],
            placeAttributes: [], follows: [], blocks: [], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: []))
        store = WanderStore(fixtures: fixtures)
        try libraryPersistence.checkpoint(WanderStoreSnapshot(store: store))
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000.123456)
        let localBatchID = batchID
        let rows = (0..<count).map { index -> PlaceImportItem in
            let identity = duplicateFirstPair && index == 1 && !secondCandidateSharesNameOnly ? 0 : index
            let displayIdentity = secondCandidateSharesNameOnly && index == 1 ? 0 : identity
            let candidate = PlaceCandidate(id: "candidate-\(identity)", name: "Fixture \(displayIdentity)", category: "park",
                latitude: 34 + Double(displayIdentity) * 0.01, longitude: -118, sourceProvider: "fixture",
                sourceProviderPlaceID: "provider-\(identity)", confidence: 1)
            return PlaceImportItem(id: "item-\(index)", batchID: localBatchID, source: .googleMaps,
                seed: PlaceImportSeed(id: "seed-\(index)", rawText: candidate.name, nameHint: candidate.name,
                    areaHint: nil, sourceURLString: nil, sourceLine: index), state: .ready,
                candidates: [candidate], selectedCandidateID: candidate.id,
                stagedVisitedAt: createdAt, createdAt: createdAt, updatedAt: createdAt)
        }
        let snapshot = PlaceImportSnapshot(ownerUserID: ownerID, batches: [PlaceImportBatch(
            id: batchID, source: .googleMaps, sourceName: "Fixture import", sourceListName: "Fixture list",
            createdAt: createdAt, state: .ready, totalCount: count, processedCount: count,
            automaticSaveRequested: true, requestedStatus: .wannaGo)], items: Array(rows.reversed()))
        try importPersistence.save(snapshot)
        importStore = PlaceImportStore(persistence: importPersistence, resolver: ChunkResolver())
        restoreBothStores()
        // Match a freshly enqueued batch: memory retains subsecond dates while
        // its already-written import file uses the ISO8601 wire precision.
        importStore = PlaceImportStore(persistence: ChunkImportWriter(backing: importPersistence,
            initialSnapshot: snapshot, shouldFail: { [weak self] in self?.failImport == true }), resolver: ChunkResolver())
    }

    func restoreBothStores() {
        let backing = libraryPersistence
        let persistence = WanderStorePersistence(load: backing.load, save: { [weak self] snapshot in
            if self?.skipOrdinaryLibraryWrites != true { backing.save(snapshot) }
        }, flush: backing.flush,
            checkpoint: backing.checkpoint, checkpointAsync: { [weak self] snapshot in
                await self?.beforeLibraryWrite?()
                if self?.failLibrary == true { throw ChunkFailure.requested }
                try await backing.checkpointAsync(snapshot)
                await self?.afterLibraryWrite?()
            })
        store = WanderStore(fixtures: .empty(), persistence: persistence)
        importStore = PlaceImportStore(persistence: ChunkImportWriter(backing: importPersistence, shouldFail: { [weak self] in
            self?.failImport == true
        }), resolver: ChunkResolver())
    }

    func process(maximumRows: Int, afterLibraryCheckpoint: (@MainActor () throws -> Void)? = nil,
                 betweenChunks: (@MainActor () async -> Void)? = nil) async -> PlaceImportAutoSaveResult {
        await PlaceImportAutoSaveCoordinator.process(batchIDs: [batchID], importStore: importStore, store: store,
            expectedUserID: ownerID, chunkPolicy: .init(maximumRows: maximumRows, budgetSeconds: 3_600),
            afterLibraryCheckpoint: afterLibraryCheckpoint, betweenChunks: betweenChunks, isAuthorized: { true })
    }

    func reviewFirstSavedItem(edit: ChunkManualEdit) throws {
        let batch = try XCTUnwrap(importStore.batches.first { $0.id == batchID })
        let receipt = try XCTUnwrap(batch.receipt)
        let entry = try XCTUnwrap(receipt.entries.first { $0.itemID == "item-0" })
        let item = try XCTUnwrap(importStore.item(id: entry.itemID))
        let saveID = try XCTUnwrap(entry.userPlaceID)
        var selection = store.importSelection(for: entry, item: item)
        switch edit {
        case .removeAction, .removeList:
            XCTAssertTrue(store.removeImportedSelection(PlaceImportSavedSelectionRemoval(itemID: item.id,
                status: edit == .removeAction ? .wannaGo : nil, visitID: nil,
                wannaID: selection.wannaID, wannaIsOriginal: selection.wannaIsOriginal,
                listIDs: selection.listIDs), entry: entry, item: item))
            selection.listIDs = []
            if edit == .removeAction { selection.status = nil }
        case .replaceStatus:
            XCTAssertNotNil(store.changeImportedSaveStatus(userPlaceID: saveID, to: .been))
            selection.status = .been
            selection.visitID = try XCTUnwrap(store.visits(for: saveID).first?.id)
        }
        let changed = PlaceImportReceiptEntry(id: entry.id, itemID: item.id, displayName: entry.displayName,
            displayArea: entry.displayArea, status: selection.status, outcome: entry.outcome,
            userPlaceID: saveID, savedSelection: selection)
        importStore.recordReceipt(batchID: batchID,
            entries: receipt.entries.map { $0.id == entry.id ? changed : $0 }, destinationListID: batch.destinationListID)
    }

    func removeFiles() { libraryPersistence.flush(); try? FileManager.default.removeItem(at: directory) }
}

private final class ChunkImportWriter: PlaceImportPersisting {
    let backing: FilePlaceImportPersistence
    let shouldFail: @MainActor @Sendable () -> Bool
    private var initialSnapshot: PlaceImportSnapshot?
    init(backing: FilePlaceImportPersistence, initialSnapshot: PlaceImportSnapshot? = nil,
         shouldFail: @escaping @MainActor @Sendable () -> Bool) {
        self.backing = backing; self.initialSnapshot = initialSnapshot; self.shouldFail = shouldFail
    }
    func load() throws -> PlaceImportSnapshot {
        if let snapshot = initialSnapshot { initialSnapshot = nil; return snapshot }
        return try backing.load()
    }
    func save(_ snapshot: PlaceImportSnapshot) throws {
        let shouldFail = self.shouldFail
        if MainActor.assumeIsolated({ shouldFail() }) { throw ChunkFailure.requested }
        try backing.save(snapshot)
    }
}

@MainActor
private final class ChunkResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Ready checkpoint fixtures must not invoke the resolver")
        return .needsHelp("Unexpected lookup")
    }
}

@MainActor
private final class ChunkGate {
    private let arrived = XCTestExpectation(description: "Checkpoint boundary reached")
    private var hasArrived = false
    private var isReleased = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        if !hasArrived { hasArrived = true; arrived.fulfill() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuations.append($0) }
    }
    func waitUntilArrived() async {
        let result = await XCTWaiter.fulfillment(of: [arrived], timeout: 5)
        XCTAssertEqual(result, .completed)
    }
    func release() {
        isReleased = true
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
