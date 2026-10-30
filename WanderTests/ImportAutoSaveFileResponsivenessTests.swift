import Foundation
import XCTest
@testable import Wander

/// Portable baseline/candidate workload. Uses production file writers and the
/// public coordinator; no checkpoint, lease, or chunk-specific API is required.
@MainActor
final class ImportAutoSaveFileResponsivenessTests: XCTestCase {
    func testPerformanceFileAutoSaveWith500ResolvedRowsAndList() async throws {
        executionTimeAllowance = 3_600
        try await measureAutoSave(rowCount: 500)
    }

    func testPerformanceFileAutoSaveWith1500ResolvedRowsAndList() async throws {
        executionTimeAllowance = 3_600
        try await measureAutoSave(rowCount: 1_500)
    }

    private func measureAutoSave(rowCount: Int) async throws {
        let existingCount = 100
        let overlappingCount = 20
        let batchID = "autosave-performance-batch"
        let expectedItemIDs = (0..<rowCount).map { "autosave-item-\($0)" }
        var wallSamples: [Double] = []
        var maximumGapSamples: [Double] = []
        var heartbeatCounts: [Int] = []
        var storeByteCounts: [Int] = []
        var importByteCounts: [Int] = []
        var decodedSaveCounts: [Int] = []
        var decodedMembershipCounts: [Int] = []
        var decodedReceiptCounts: [Int] = []
        var decodedAddedCounts: [Int] = []
        var decodedExistingCounts: [Int] = []
        var decodedSavedItemCounts: [Int] = []

        for _ in 0..<3 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("autosave-file-responsiveness-\(UUID().uuidString)", isDirectory: true)
            let storeURL = directory.appendingPathComponent("wander-store.json")
            let importURL = directory.appendingPathComponent("place-imports.json")
            let storePersistence = WanderStorePersistence.coalescingFile(url: storeURL)
            defer {
                storePersistence.flush()
                try? FileManager.default.removeItem(at: directory)
            }
            let store = WanderStore(fixtures: libraryFixture(count: existingCount), persistence: storePersistence)
            let ownerID = store.currentUser.id
            let importPersistence = FilePlaceImportPersistence(fileURL: importURL)
            try importPersistence.save(importFixture(rowCount: rowCount, overlappingCount: overlappingCount,
                batchID: batchID, ownerUserID: ownerID))
            let importStore = PlaceImportStore(persistence: importPersistence, resolver: FileAutoSavePerformanceResolver())
            XCTAssertEqual(store.currentUserVisiblePlaces.count, existingCount)
            XCTAssertNil(importStore.persistenceError)
            // Fixture encoding and the initial store write are outside timing.
            storePersistence.flush()

            let heartbeat = AutoSaveFileHeartbeat()
            let heartbeatTask = Task { @MainActor in
                while !Task.isCancelled {
                    heartbeat.tick()
                    do { try await Task.sleep(for: .milliseconds(1)) }
                    catch { return }
                }
            }
            defer { heartbeatTask.cancel() }
            await heartbeat.waitForTick(after: 0)
            XCTAssertGreaterThan(heartbeat.tickCount, 0)

            let startedAt = ProcessInfo.processInfo.systemUptime
            let result = await PlaceImportAutoSaveCoordinator.process(
                batchIDs: [batchID], importStore: importStore, store: store,
                expectedUserID: ownerID, isAuthorized: { true }
            )
            // Include the production writer's durability barrier. Import-file
            // saves are synchronous; this flush drains the store's queued file.
            storePersistence.flush()
            let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            let ticksAtCompletion = heartbeat.tickCount
            // A real heartbeat tick after processing captures even a coordinator
            // that blocks the main actor for its entire single transaction.
            await heartbeat.waitForTick(after: ticksAtCompletion)
            heartbeatTask.cancel()
            await heartbeatTask.value
            XCTAssertGreaterThan(heartbeat.tickCount, ticksAtCompletion)
            XCTAssertGreaterThanOrEqual(heartbeat.tickCount, 2)
            XCTAssertGreaterThan(heartbeat.maximumGapMilliseconds, 0)

            wallSamples.append(elapsedMilliseconds)
            maximumGapSamples.append(heartbeat.maximumGapMilliseconds)
            heartbeatCounts.append(heartbeat.tickCount)

            XCTAssertEqual(result.batchIDs, [batchID])
            XCTAssertEqual(result.addedCount, rowCount - overlappingCount)
            XCTAssertEqual(result.existingCount, overlappingCount)
            XCTAssertEqual(result.savedCount, rowCount)
            XCTAssertEqual(result.needsReviewCount, 0)
            XCTAssertEqual(result.sourceRetryCount, 0)
            XCTAssertEqual(store.currentUser.id, ownerID)
            XCTAssertEqual(store.userPlaces.filter { $0.deletedAt == nil }.count,
                existingCount + rowCount - overlappingCount)
            XCTAssertTrue(store.userPlaces.allSatisfy { $0.status == .wannaGo })
            XCTAssertTrue(store.placeVisits.isEmpty)

            let batch = try XCTUnwrap(importStore.batches.first)
            let receipt = try XCTUnwrap(batch.receipt)
            XCTAssertEqual(importStore.batches.count, 1)
            XCTAssertEqual(batch.state, .complete)
            XCTAssertEqual(batch.totalCount, rowCount)
            XCTAssertEqual(batch.processedCount, rowCount)
            XCTAssertNotNil(batch.automaticSaveCompletedAt)
            XCTAssertEqual(receipt.entries.map(\.itemID), expectedItemIDs,
                "Reversed storage order must not alter receipt source order")
            XCTAssertEqual(Array(receipt.entries.prefix(overlappingCount)).map(\.outcome),
                Array(repeating: .existing, count: overlappingCount))
            XCTAssertTrue(receipt.entries.dropFirst(overlappingCount).allSatisfy { $0.outcome == .added })
            XCTAssertTrue(receipt.entries.allSatisfy { $0.status == .wannaGo })
            XCTAssertEqual(importStore.items.count, rowCount)
            XCTAssertTrue(importStore.items.allSatisfy { $0.state == .saved && $0.savedUserPlaceID != nil })
            XCTAssertEqual(importStore.items(for: batchID).map(\.id), expectedItemIDs)
            XCTAssertNil(importStore.persistenceError)

            let listID = try XCTUnwrap(batch.destinationListID)
            let list = try XCTUnwrap(store.placeLists.first { $0.id == listID })
            XCTAssertEqual(list.name, "Autosave performance list")
            XCTAssertEqual(list.cachedItemCount, rowCount)
            XCTAssertEqual(receipt.destinationListID, listID)
            let memberships = store.placeListItems.filter { $0.listID == listID && $0.deletedAt == nil }
            let savedIDs = Set(receipt.entries.compactMap(\.userPlaceID))
            XCTAssertEqual(memberships.count, rowCount)
            XCTAssertEqual(savedIDs.count, rowCount)
            XCTAssertEqual(Set(memberships.compactMap(\.ownerUserPlaceID)), savedIDs)
            XCTAssertTrue(memberships.allSatisfy { $0.senderNotificationPolicy == .silent })
            let newSaves = store.userPlaces.filter { !$0.localID.hasPrefix("autosave-existing-save-") }
            XCTAssertTrue(newSaves.allSatisfy {
                SenderNotificationPolicy.restored(from: $0.senderNotificationJSON) == .silent
            })
            let notificationCommit = try XCTUnwrap(store.importNotificationCommits.first)
            XCTAssertEqual(store.importNotificationCommits.count, 1)
            XCTAssertTrue(notificationCommit.silent)
            XCTAssertTrue(notificationCommit.locallyComplete)
            XCTAssertEqual(notificationCommit.selectedItemIDs, Set(expectedItemIDs))

            // Decode the actual final files after timing and heartbeat shutdown,
            // so validation's JSON/collection work cannot become a measured gap.
            let storeBytes = try Data(contentsOf: storeURL)
            let importBytes = try Data(contentsOf: importURL)
            let persistedStore = try JSONDecoder().decode(WanderStoreSnapshot.self, from: storeBytes)
            let persistedImport = try FilePlaceImportPersistence(fileURL: importURL).load()
            XCTAssertEqual(persistedStore.userPlaces.count, existingCount + rowCount - overlappingCount)
            XCTAssertEqual(persistedStore.placeListItems?.count, rowCount)
            XCTAssertEqual(persistedStore.importNotificationCommits, store.importNotificationCommits)
            let memorySnapshot = WanderStoreSnapshot(store: store)
            XCTAssertEqual(persistedStore.currentUser, memorySnapshot.currentUser)
            XCTAssertEqual(persistedStore.places, memorySnapshot.places)
            XCTAssertEqual(persistedStore.userPlaces, memorySnapshot.userPlaces)
            XCTAssertEqual(persistedStore.placeListItems, memorySnapshot.placeListItems)
            XCTAssertEqual(persistedStore.placeLists, memorySnapshot.placeLists)
            XCTAssertEqual(persistedImport.ownerUserID, ownerID)
            XCTAssertEqual(persistedImport.items.count, rowCount)
            let persistedBatch = try XCTUnwrap(persistedImport.batches.first)
            XCTAssertEqual(persistedBatch.receipt?.entries.map(\.itemID), expectedItemIDs)
            XCTAssertEqual(persistedBatch.state, .complete)
            // The existing import-file format stores dates at ISO8601 second
            // precision. Compare every field after that same documented codec.
            let expectedImport = PlaceImportSnapshot(ownerUserID: ownerID,
                batches: importStore.batches, items: importStore.items)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            XCTAssertEqual(persistedImport,
                try decoder.decode(PlaceImportSnapshot.self, from: encoder.encode(expectedImport)))

            storeByteCounts.append(storeBytes.count)
            importByteCounts.append(importBytes.count)
            decodedSaveCounts.append(persistedStore.userPlaces.count)
            decodedMembershipCounts.append(persistedStore.placeListItems?.count ?? 0)
            decodedReceiptCounts.append(persistedBatch.receipt?.entries.count ?? 0)
            decodedAddedCounts.append(persistedBatch.receipt?.entries.filter { $0.outcome == .added }.count ?? 0)
            decodedExistingCounts.append(persistedBatch.receipt?.entries.filter { $0.outcome == .existing }.count ?? 0)
            decodedSavedItemCounts.append(persistedImport.items.filter { $0.state == .saved }.count)
        }

        let attachment = XCTAttachment(string:
            "REC675 import_autosave_actual_file rows=\(rowCount) existing=\(existingCount) overlaps=\(overlappingCount) samples=3 heartbeat_sleep_ms=1 wall_samples_ms=\(wallSamples) wall_median_ms=\(wallSamples.sorted()[1]) rows_per_second=\(wallSamples.map { Double(rowCount) * 1_000 / $0 }) heartbeat_max_gap_samples_ms=\(maximumGapSamples) heartbeat_max_gap_median_ms=\(maximumGapSamples.sorted()[1]) heartbeat_counts=\(heartbeatCounts) decoded_save_counts=\(decodedSaveCounts) decoded_membership_counts=\(decodedMembershipCounts) decoded_receipt_counts=\(decodedReceiptCounts) decoded_added_counts=\(decodedAddedCounts) decoded_existing_counts=\(decodedExistingCounts) decoded_saved_item_counts=\(decodedSavedItemCounts) store_final_bytes=\(storeByteCounts) import_final_bytes=\(importByteCounts)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func libraryFixture(count: Int) -> WanderFixtures {
        let user = LocalProfile(localID: "autosave-owner-local", serverID: "autosave-owner",
            handle: "autosave-fixture", displayName: "Autosave fixture", syncState: .synced)
        let places = (0..<count).map { index in
            let candidate = candidate(index: index, existing: true)
            return LocalPlace(localID: "autosave-existing-place-\(index)",
                serverID: "autosave-existing-server-place-\(index)", canonicalName: candidate.name,
                category: "park", latitude: candidate.latitude!, longitude: candidate.longitude!,
                sourceProvider: candidate.sourceProvider, sourceProviderPlaceID: candidate.sourceProviderPlaceID,
                syncState: .synced)
        }
        let saves = places.enumerated().map { index, place in
            LocalUserPlace(localID: "autosave-existing-save-\(index)",
                serverID: "autosave-existing-server-save-\(index)", userID: user.id, placeID: place.id,
                status: .wannaGo, visibility: .selfOnly,
                savedAt: Date(timeIntervalSince1970: 1_735_689_600 + Double(index) * 86_400),
                sourceType: "manual", syncState: .synced)
        }
        return WanderFixtures(currentUser: user, profiles: [user], places: places,
            userPlaces: saves, placeAttributes: [], follows: [], blocks: [],
            placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: []))
    }

    private func importFixture(rowCount: Int, overlappingCount: Int,
                               batchID: String, ownerUserID: String) -> PlaceImportSnapshot {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<rowCount).map { index in
            let candidate = candidate(index: index, existing: index < overlappingCount)
            return PlaceImportItem(id: "autosave-item-\(index)", batchID: batchID, source: .googleMaps,
                seed: PlaceImportSeed(id: "autosave-seed-\(index)", rawText: candidate.name,
                    nameHint: candidate.name, areaHint: nil, sourceURLString: nil, sourceLine: index),
                state: .ready, candidates: [candidate], selectedCandidateID: candidate.id,
                createdAt: timestamp, updatedAt: timestamp)
        }
        let batch = PlaceImportBatch(id: batchID, source: .googleMaps,
            sourceName: "Autosave fixture", sourceListName: "Autosave performance list",
            createdAt: timestamp, updatedAt: timestamp, state: .ready,
            totalCount: rowCount, processedCount: rowCount,
            automaticSaveRequested: true, requestedStatus: .wannaGo)
        return PlaceImportSnapshot(ownerUserID: ownerUserID, batches: [batch], items: Array(items.reversed()))
    }

    private func candidate(index: Int, existing: Bool) -> PlaceCandidate {
        let identity = "\(existing ? "existing" : "imported")-\(index)"
        return PlaceCandidate(id: "autosave-candidate-\(identity)", name: "Autosave fixture \(identity)",
            category: "park", latitude: (existing ? 37.7 : 34.0) + Double(index / 50) * 0.01,
            longitude: -118.0 + Double(index % 50) * 0.01,
            sourceProvider: "fixture", sourceProviderPlaceID: "autosave-provider-\(identity)", confidence: 1)
    }
}

@MainActor
private final class AutoSaveFileHeartbeat {
    private var previousTick: Double?
    private var waiter: (after: Int, continuation: CheckedContinuation<Void, Never>)?
    private(set) var tickCount = 0
    private(set) var maximumGapMilliseconds = 0.0

    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        if let previousTick {
            maximumGapMilliseconds = max(maximumGapMilliseconds, (now - previousTick) * 1_000)
        }
        previousTick = now
        tickCount += 1
        if let waiter, tickCount > waiter.after {
            self.waiter = nil
            waiter.continuation.resume()
        }
    }

    func waitForTick(after count: Int) async {
        guard tickCount <= count else { return }
        await withCheckedContinuation { continuation in
            precondition(waiter == nil)
            waiter = (count, continuation)
        }
    }
}

@MainActor
private struct FileAutoSavePerformanceResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Pre-resolved autosave fixtures must not invoke a network resolver")
        return .needsHelp("Unexpected fixture resolution")
    }
}
