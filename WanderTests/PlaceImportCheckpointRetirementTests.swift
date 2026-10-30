import Foundation
import XCTest
@testable import Wander

@MainActor
final class PlaceImportCheckpointRetirementTests: XCTestCase {
    func testRetirementOnlyRemovesExactCompletedOwnedPlanAndKeepsPartialBatches() throws {
        var ordinarySnapshots: [WanderStoreSnapshot] = []
        let store = WanderStore(fixtures: .empty(), persistence: WanderStorePersistence(load: { nil },
            save: { ordinarySnapshots.append($0) }))
        let completed = checkpoint(store: store, batchID: "completed", complete: true)
        let partial = checkpoint(store: store, batchID: "partial", complete: false)
        XCTAssertTrue(store.recordAutomaticImportCheckpoint(completed))
        XCTAssertTrue(store.recordAutomaticImportCheckpoint(partial))
        ordinarySnapshots.removeAll()

        let wrongID = checkpoint(store: store, batchID: completed.batchID, complete: true)
        XCTAssertFalse(store.retireCompletedAutomaticImportCheckpoint(wrongID))
        XCTAssertFalse(store.retireCompletedAutomaticImportCheckpoint(partial))
        XCTAssertTrue(ordinarySnapshots.isEmpty)
        XCTAssertTrue(store.retireCompletedAutomaticImportCheckpoint(completed))
        XCTAssertEqual(store.automaticImportCheckpoints, [partial])
        XCTAssertEqual(ordinarySnapshots.count, 1)
        XCTAssertEqual(ordinarySnapshots.first?.automaticImportCheckpoints, [partial])
        XCTAssertFalse(store.retireCompletedAutomaticImportCheckpoint(completed))
        XCTAssertEqual(ordinarySnapshots.count, 1)
    }

    func testRetirementCannotCrossAccountOrAcceptChangedBatchIdentityWithSameJournalID() throws {
        let store = WanderStore(fixtures: .empty())
        let completed = checkpoint(store: store, batchID: "completed", complete: true)
        XCTAssertTrue(store.recordAutomaticImportCheckpoint(completed))
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(completed)) as? [String: Any])
        encoded["batchID"] = "another-batch"
        let changedBatch = try JSONDecoder().decode(PlaceImportAutoSaveCheckpoint.self,
            from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(changedBatch.id, completed.id)
        XCTAssertFalse(store.retireCompletedAutomaticImportCheckpoint(changedBatch))
        XCTAssertEqual(store.automaticImportCheckpoints, [completed])

        store.apply(authState: .signedIn(AuthSession(userID: "different-owner", displayName: "Different", handle: "different")))
        let retained = store.automaticImportCheckpoints
        XCTAssertFalse(store.retireCompletedAutomaticImportCheckpoint(completed))
        XCTAssertEqual(store.automaticImportCheckpoints, retained)
    }

    private func checkpoint(store: WanderStore, batchID: String, complete: Bool) -> PlaceImportAutoSaveCheckpoint {
        let batch = PlaceImportBatch(id: batchID, source: .googleMaps, sourceName: "Fixture",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), state: .ready, totalCount: 0,
            automaticSaveRequested: true, requestedStatus: .wannaGo)
        var checkpoint = PlaceImportAutoSaveCheckpoint(ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: [])
        checkpoint.isComplete = complete
        return checkpoint
    }
}
