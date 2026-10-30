import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportAutoSaveWithoutListPerformanceTests: XCTestCase {
    /// Companion diagnostic for ImportAutoSavePerformanceTests: identical
    /// 1,500-row input, 100 existing saves, and 20 overlaps, except that the
    /// source has no list name. This isolates destination-list overhead while
    /// exercising the same production saves, receipts, and silent commit.
    /// Fixture construction, JSON encoding, disk I/O, and network are excluded.
    /// Keep this workload unchanged on the baseline and candidate revisions.
    func testPerformanceGoogleWannaAutoSaveWithoutListWith1500ResolvedRows() async throws {
        let rowCount = 1_500
        let existingCount = 100
        let overlappingCount = 20
        let batchID = "autosave-performance-batch"
        let expectedItemIDs = (0..<rowCount).map { "autosave-item-\($0)" }
        var samples: [Double] = []

        for _ in 0..<3 {
            let storePersistence = AutoSaveWithoutListStorePersistence()
            let fixtures = libraryFixture(count: existingCount)
            let store = WanderStore(fixtures: fixtures, persistence: storePersistence.persistence)
            let importPersistence = AutoSaveWithoutListImportPersistence(snapshot: importFixture(
                rowCount: rowCount, overlappingCount: overlappingCount,
                batchID: batchID, ownerUserID: store.currentUser.id
            ))
            let importStore = PlaceImportStore(
                persistence: importPersistence, resolver: AutoSaveWithoutListResolver()
            )
            XCTAssertEqual(store.currentUserVisiblePlaces.count, existingCount)
            storePersistence.reset()
            importPersistence.reset()

            let startedAt = ProcessInfo.processInfo.systemUptime
            let result = await PlaceImportAutoSaveCoordinator.process(
                batchIDs: [batchID], importStore: importStore, store: store,
                expectedUserID: store.currentUser.id, isAuthorized: { true }
            )
            samples.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)

            XCTAssertEqual(result.batchIDs, [batchID])
            XCTAssertEqual(result.addedCount, rowCount - overlappingCount)
            XCTAssertEqual(result.existingCount, overlappingCount)
            XCTAssertEqual(result.savedCount, rowCount)
            XCTAssertEqual(result.needsReviewCount, 0)
            XCTAssertEqual(result.sourceRetryCount, 0)
            XCTAssertEqual(store.userPlaces.filter { $0.deletedAt == nil }.count,
                existingCount + rowCount - overlappingCount)
            XCTAssertTrue(store.userPlaces.allSatisfy { $0.status == .wannaGo })
            XCTAssertTrue(store.placeVisits.isEmpty)

            let batch = try XCTUnwrap(importStore.batches.first)
            let receipt = try XCTUnwrap(batch.receipt)
            XCTAssertEqual(batch.state, .complete)
            XCTAssertEqual(batch.totalCount, rowCount)
            XCTAssertEqual(batch.processedCount, rowCount)
            XCTAssertNotNil(batch.automaticSaveCompletedAt)
            XCTAssertEqual(receipt.entries.map(\.itemID), expectedItemIDs,
                "Storage order differs from source order; receipts must retain source order")
            XCTAssertEqual(Array(receipt.entries.prefix(overlappingCount)).map(\.outcome),
                Array(repeating: .existing, count: overlappingCount))
            XCTAssertTrue(receipt.entries.dropFirst(overlappingCount).allSatisfy { $0.outcome == .added })
            XCTAssertTrue(receipt.entries.allSatisfy { $0.status == .wannaGo })
            XCTAssertTrue(importStore.items.allSatisfy { $0.state == .saved && $0.savedUserPlaceID != nil })
            XCTAssertEqual(importStore.items(for: batchID).map(\.id), expectedItemIDs)

            XCTAssertNil(batch.destinationListID)
            XCTAssertNil(receipt.destinationListID)
            XCTAssertTrue(store.placeLists.isEmpty)
            XCTAssertTrue(store.placeListItems.isEmpty)
            let savedIDs = Set(receipt.entries.compactMap(\.userPlaceID))
            XCTAssertEqual(savedIDs.count, rowCount)
            let newSaves = store.userPlaces.filter { !$0.localID.hasPrefix("autosave-existing-save-") }
            XCTAssertTrue(newSaves.allSatisfy {
                SenderNotificationPolicy.restored(from: $0.senderNotificationJSON) == .silent
            })
            let notificationCommit = try XCTUnwrap(store.importNotificationCommits.first)
            XCTAssertEqual(store.importNotificationCommits.count, 1)
            XCTAssertTrue(notificationCommit.silent)
            XCTAssertTrue(notificationCommit.locallyComplete)
            XCTAssertEqual(notificationCommit.selectedItemIDs, Set(expectedItemIDs))

            XCTAssertEqual(storePersistence.saveCount, 1)
            XCTAssertEqual(importPersistence.saveCount, 1)
            let persistedStore = try XCTUnwrap(storePersistence.snapshot)
            XCTAssertEqual(persistedStore.userPlaces.count, existingCount + rowCount - overlappingCount)
            XCTAssertEqual(persistedStore.placeListItems?.count, 0)
            XCTAssertEqual(persistedStore.importNotificationCommits, store.importNotificationCommits)
            XCTAssertEqual(importPersistence.snapshot.items, importStore.items)
            XCTAssertEqual(importPersistence.snapshot.batches, importStore.batches)
        }

        let attachment = XCTAttachment(string:
            "REC675 import_autosave_without_list_coordinator rows=\(rowCount) existing=\(existingCount) overlaps=\(overlappingCount) list_memberships=0 samples_ms=\(samples) median_ms=\(samples.sorted()[1])")
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
            sourceName: "Autosave fixture", sourceListName: nil,
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
private final class AutoSaveWithoutListStorePersistence {
    private(set) var snapshot: WanderStoreSnapshot?
    private(set) var saveCount = 0
    var persistence: WanderStorePersistence {
        WanderStorePersistence(load: { nil }, save: { [self] snapshot in
            self.snapshot = snapshot
            saveCount += 1
        })
    }
    func reset() { snapshot = nil; saveCount = 0 }
}

private final class AutoSaveWithoutListImportPersistence: PlaceImportPersisting {
    private(set) var snapshot: PlaceImportSnapshot
    private(set) var saveCount = 0
    init(snapshot: PlaceImportSnapshot) { self.snapshot = snapshot }
    func load() throws -> PlaceImportSnapshot { snapshot }
    func save(_ snapshot: PlaceImportSnapshot) throws { self.snapshot = snapshot; saveCount += 1 }
    func reset() { saveCount = 0 }
}

@MainActor
private struct AutoSaveWithoutListResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Pre-resolved autosave fixtures must not invoke a network resolver")
        return .needsHelp("Unexpected fixture resolution")
    }
}
