import Foundation
import XCTest
@testable import Wander

@MainActor
final class AutomaticImportCheckpointStoreTests: XCTestCase {
    private enum Failure: Error { case disk }

    func testRowsAndJournalShareOneAcknowledgedSnapshotWithoutAnExtraNormalWrite() throws {
        var ordinaryWrites = 0
        var checkpoints: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(load: { nil }, save: { _ in ordinaryWrites += 1 },
            checkpoint: { checkpoints.append($0) })
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        let journal = checkpoint(for: store)
        let saved = try store.performCheckpointedImportMutations {
            let result = save(in: store)
            XCTAssertTrue(store.recordAutomaticImportCheckpoint(journal))
            XCTAssertTrue(checkpoints.isEmpty)
            return result
        }
        XCTAssertEqual(ordinaryWrites, 0)
        XCTAssertEqual(checkpoints.count, 1)
        let snapshot = try XCTUnwrap(checkpoints.first)
        XCTAssertEqual(snapshot.automaticImportCheckpoints, [journal])
        XCTAssertTrue(snapshot.userPlaces.contains { $0.localID == saved.userPlaceID })
        XCTAssertEqual(snapshot.currentUser.localID, store.currentUser.localID)
    }

    func testFailedCheckpointRetainsRecoverableMemoryAndRetryAcknowledgesTheSameRows() throws {
        var fail = true
        var durable: WanderStoreSnapshot?
        var ordinaryWrites = 0
        let persistence = WanderStorePersistence(load: { durable }, save: { _ in ordinaryWrites += 1 },
            checkpoint: {
                if fail { throw Failure.disk }
                durable = $0
            })
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        let journal = checkpoint(for: store)
        var savedID: String?
        XCTAssertThrowsError(try store.performCheckpointedImportMutations {
            savedID = save(in: store).userPlaceID
            store.recordAutomaticImportCheckpoint(journal)
        })
        XCTAssertNil(durable)
        XCTAssertEqual(ordinaryWrites, 0)
        XCTAssertEqual(store.automaticImportCheckpoint(ownerUserID: store.currentUser.id,
            batchID: journal.batchID), journal)
        XCTAssertEqual(store.userPlaces.count, 1)
        fail = false
        try store.commitAutomaticImportCheckpointDurably()
        XCTAssertEqual(durable?.automaticImportCheckpoints, [journal])
        XCTAssertEqual(durable?.userPlaces.map(\.localID), [try XCTUnwrap(savedID)])
        XCTAssertEqual(store.userPlaces.count, 1, "Retry must write the journal, not save its rows again")
    }

    func testNestedCheckpointRejectsBeforeMutationAndDoesNotDamageTheOuterDeferral() throws {
        var writes = 0
        var checkpoints = 0
        let store = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(load: { nil },
            save: { _ in writes += 1 }, checkpoint: { _ in checkpoints += 1 }))
        var entered = false
        try store.performBatchedLocalMutations {
            XCTAssertThrowsError(try store.performCheckpointedImportMutations { entered = true })
            XCTAssertThrowsError(try store.commitAutomaticImportCheckpointDurably())
            _ = save(in: store)
            XCTAssertEqual(writes, 0)
        }
        XCTAssertFalse(entered)
        XCTAssertEqual(writes, 1)
        try store.commitAutomaticImportCheckpointDurably()
        XCTAssertEqual(checkpoints, 1)
    }

    func testAsyncCheckpointClosesMutationScopeAndWritesItsImmutableSnapshot() async throws {
        let gate = AutomaticImportCheckpointGate()
        var ordinary: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(load: { nil }, save: { ordinary.append($0) },
            checkpointAsync: { snapshot in await gate.write(snapshot) })
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        let journal = checkpoint(for: store)
        let task = Task { @MainActor in
            try await store.performCheckpointedImportMutationsAsync {
                let result = self.save(in: store)
                store.recordAutomaticImportCheckpoint(journal)
                return result
            }
        }
        await gate.waitUntilEntered()
        XCTAssertTrue(ordinary.isEmpty)
        // Unrelated UI work can run while disk acknowledgement is pending.
        // It must have its own normal persistence, not join the prior scope.
        _ = store.saveCandidate(PlaceCandidate(id: "later-place", name: "Later Cafe", category: "coffee",
            latitude: 35, longitude: -119, confidence: 1), status: .wannaGo,
            visibility: .selfOnly, note: nil, sourceType: .manual)
        XCTAssertEqual(ordinary.count, 1)
        XCTAssertEqual(ordinary.first?.userPlaces.count, 2)
        XCTAssertEqual(gate.snapshot?.userPlaces.count, 1)
        XCTAssertEqual(gate.snapshot?.automaticImportCheckpoints, [journal])
        gate.resume()
        let result = try await task.value
        XCTAssertEqual(gate.snapshot?.userPlaces.first?.localID, result.userPlaceID)
        XCTAssertEqual(store.userPlaces.count, 2)
    }

    func testJournalRoundTripLegacyDecodingResetAndOwnerIsolation() throws {
        let store = WanderStore(fixtures: .empty())
        let journal = checkpoint(for: store)
        try store.performCheckpointedImportMutations {
            _ = save(in: store)
            store.recordAutomaticImportCheckpoint(journal)
        }
        let snapshot = WanderStoreSnapshot(store: store)
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WanderStoreSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.automaticImportCheckpoints, [journal])
        let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(
            load: { decoded }, save: { _ in }))
        XCTAssertEqual(restored.automaticImportCheckpoint(ownerUserID: journal.ownerUserID,
            batchID: journal.batchID), journal)
        restored.apply(authState: .signedIn(AuthSession(userID: "other-owner", displayName: "Other", handle: "other")))
        XCTAssertNil(restored.automaticImportCheckpoint(ownerUserID: journal.ownerUserID, batchID: journal.batchID))
        XCTAssertFalse(restored.recordAutomaticImportCheckpoint(journal))

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "automaticImportCheckpoints")
        let legacySnapshot = try JSONDecoder().decode(WanderStoreSnapshot.self,
            from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(legacySnapshot.automaticImportCheckpoints)
        XCTAssertTrue(legacySnapshot.restoredState(contactProvider: FakeContactProvider(seededMatches: []))
            .automaticImportCheckpoints.isEmpty)
        var reset = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        reset["savedPlaceResetVersion"] = 0
        let resetSnapshot = try JSONDecoder().decode(WanderStoreSnapshot.self,
            from: JSONSerialization.data(withJSONObject: reset))
        let resetState = resetSnapshot.restoredState(contactProvider: FakeContactProvider(seededMatches: []))
        XCTAssertTrue(resetState.userPlaces.isEmpty)
        XCTAssertTrue(resetState.automaticImportCheckpoints.isEmpty,
            "A library reset must not replay journal entries for removed rows")
    }

    func testOwnedFallbackReadsCurrentAliasesAndCannotReviveTombstoneOrOtherOwner() throws {
        let store = WanderStore(fixtures: .empty())
        let saved = save(in: store)
        let parent = try XCTUnwrap(store.userPlaces.first)
        parent.serverID = "server-save"
        parent.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(store.existingImportSave(userPlaceID: saved.userPlaceID)?.status, .been)
        XCTAssertEqual(store.existingImportSave(userPlaceID: "server-save")?.userPlaceID, "server-save")
        parent.deletedAt = .now
        XCTAssertNil(store.existingImportSave(userPlaceID: saved.userPlaceID))
        parent.deletedAt = nil
        parent.userID = "other-owner"
        XCTAssertNil(store.existingImportSave(userPlaceID: "server-save"))
    }

    func testRemoteAlternateAliasCannotBypassALocalTombstone() throws {
        let store = WanderStore(fixtures: .empty())
        _ = save(in: store)
        let local = try XCTUnwrap(store.userPlaces.first)
        let place = try XCTUnwrap(store.places.first)
        local.serverID = "shared-server-save"
        local.deletedAt = .now
        let remote = LocalUserPlace(localID: "remote-local-save", serverID: "shared-server-save",
            userID: store.currentUser.id, placeID: place.id, status: .wannaGo,
            visibility: .selfOnly, sourceType: "link", syncState: .synced)
        let visible = VisiblePlace(id: remote.id, place: place, userPlace: remote, owner: store.currentUser)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(WanderStoreSnapshot(store: store))) as? [String: Any])
        payload["cachedCurrentUserVisiblePlaces"] = [try JSONSerialization.jsonObject(with:
            JSONEncoder().encode(WanderStoreSnapshot.VisiblePlaceRecord(visible)))]
        let snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self,
            from: JSONSerialization.data(withJSONObject: payload))
        let restored = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(
            load: { snapshot }, save: { _ in }))
        XCTAssertEqual(restored.remoteVisiblePlaceCache.count, 1)
        XCTAssertNil(restored.existingImportSave(userPlaceID: "remote-local-save"),
            "The requested alias differs, but the shared server ID identifies the same deleted save")
        restored.userPlaces.first?.deletedAt = nil
        XCTAssertEqual(restored.existingImportSave(userPlaceID: "remote-local-save")?.userPlaceID,
            "shared-server-save")
        restored.remoteVisiblePlaceCache.first?.userPlace.userID = "another-owner"
        XCTAssertNil(restored.existingImportSave(userPlaceID: "remote-local-save"))
    }

    private func checkpoint(for store: WanderStore) -> PlaceImportAutoSaveCheckpoint {
        let batch = PlaceImportBatch(id: "batch", source: .googleMaps, sourceName: "Fixture",
            totalCount: 1, automaticSaveRequested: true, requestedStatus: .wannaGo)
        return PlaceImportAutoSaveCheckpoint(ownerUserID: store.currentUser.id, batch: batch,
            eligibleItemIDs: ["item"])
    }

    private func save(in store: WanderStore) -> SaveResult {
        store.saveImportedCandidate(PlaceCandidate(id: "checkpoint-place", name: "Fixture Cafe",
            category: "coffee", latitude: 34, longitude: -118, sourceProvider: "mapkit", confidence: 1),
            status: .wannaGo, visibility: .selfOnly, note: nil, sourceType: .link)
    }
}

@MainActor
private final class AutomaticImportCheckpointGate {
    private(set) var snapshot: WanderStoreSnapshot?
    private var continuation: CheckedContinuation<Void, Never>?

    func write(_ snapshot: WanderStoreSnapshot) async {
        self.snapshot = snapshot
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        for _ in 0..<1_000 {
            if continuation != nil { return }
            await Task.yield()
        }
        XCTFail("Checkpoint did not reach the controlled write gate")
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
