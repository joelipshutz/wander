import XCTest
@testable import Wander

@MainActor
final class SenderNotificationPolicyTests: XCTestCase {
    func testPolicyRoundTripAndCorruptionFailClosed() throws {
        let policy = SenderNotificationPolicy(silent: false, importID: "import", importCommitID: UUID().uuidString)
        XCTAssertTrue(policy.suppressesIndividualAlerts)
        XCTAssertEqual(SenderNotificationPolicy.restored(from: policy.persistedJSON), policy)
        XCTAssertEqual(SenderNotificationPolicy.restored(from: "broken"), .silent)
        XCTAssertFalse(SenderNotificationPolicy.standard.suppressesIndividualAlerts)
    }

    func testFirstThreeThenSevenRetainsExactlyFirstManifest() throws {
        let store = makeStore()
        let batch = batch()
        let first = store.beginImportNotificationCommit(batch, silent: false, selectedItemIDs: ["1", "2", "3"])
        for index in 1...3 { saveVisit(index, policy: first, store: store) }
        store.completeImportNotificationCommit(first)
        let firstIDs = try XCTUnwrap(store.importNotificationCommits.first).visitIDs
        XCTAssertEqual(firstIDs.count, 3)
        let later = store.beginImportNotificationCommit(batch, silent: false, selectedItemIDs: ["4"])
        for index in 4...10 { saveVisit(index, policy: later, store: store) }
        XCTAssertEqual(store.importNotificationCommits.count, 1)
        XCTAssertEqual(store.importNotificationCommits.first?.visitIDs, firstIDs)
        XCTAssertEqual(store.placeVisits.filter { !$0.backfilledFromUserPlace }.count, 10)
        XCTAssertTrue(store.placeVisits.filter { !$0.backfilledFromUserPlace }.allSatisfy { $0.senderNotificationPolicy.suppressesIndividualAlerts })
        XCTAssertFalse(store.importNeedsNotificationChoice(batch))
    }

    func testInterruptedSaveClosesDurableManifestBeforeAnyNewAction() throws {
        let store = makeStore()
        let policy = store.beginImportNotificationCommit(batch(), silent: false, selectedItemIDs: ["same-item"])
        saveVisit(1, policy: policy, store: store)
        let originalIDs = try XCTUnwrap(store.importNotificationCommits.first).visitIDs
        let retry = store.beginImportNotificationCommit(batch(), silent: false, selectedItemIDs: ["same-item"])
        saveVisit(2, policy: retry, store: store)
        XCTAssertEqual(store.importNotificationCommits.first?.visitIDs, originalIDs)
        XCTAssertTrue(try XCTUnwrap(store.importNotificationCommits.first).locallyComplete)
    }

    func testCrashRestoresClosedManifestAndPolicyWithoutExpandingIt() throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = makeStore(persistence: persistence)
        let policy = store.beginImportNotificationCommit(batch(), silent: false)
        saveVisit(1, policy: policy, store: store)
        store.flushPersistence()
        snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: JSONEncoder().encode(XCTUnwrap(snapshot)))
        let restored = makeStore(persistence: persistence)
        let oldIDs = try XCTUnwrap(restored.importNotificationCommits.first).visitIDs
        XCTAssertTrue(try XCTUnwrap(restored.importNotificationCommits.first).locallyComplete)
        saveVisit(2, policy: policy, store: restored)
        XCTAssertEqual(restored.importNotificationCommits.first?.visitIDs, oldIDs)
        XCTAssertEqual(restored.placeVisits.filter { !$0.backfilledFromUserPlace }.first?.senderNotificationPolicy, policy)
    }

    func testSilentFirstChoiceCannotBeChangedOnLaterSave() throws {
        let store = makeStore()
        let policy = store.beginImportNotificationCommit(batch(), silent: true)
        store.completeImportNotificationCommit(policy)
        XCTAssertEqual(store.beginImportNotificationCommit(batch(), silent: false), policy)
        XCTAssertTrue(try XCTUnwrap(store.importNotificationCommits.first).silent)
    }

    func testReviewOnlyReceiptDoesNotConsumeChoiceButActualLegacySaveDoes() {
        let store = makeStore()
        var importBatch = batch()
        importBatch.receipt = PlaceImportReceipt(batchID: importBatch.id, sourceName: nil, entries: [], destinationListID: nil)
        importBatch.automaticSaveCompletedAt = .now
        XCTAssertTrue(store.importNeedsNotificationChoice(importBatch))
        importBatch.receipt = PlaceImportReceipt(batchID: importBatch.id, sourceName: nil, entries: [PlaceImportReceiptEntry(itemID: "saved", displayName: "Saved", displayArea: nil,
            status: .been, outcome: .added, userPlaceID: "save-id")], destinationListID: nil)
        XCTAssertFalse(store.importNeedsNotificationChoice(importBatch))
        XCTAssertTrue(store.beginImportNotificationCommit(importBatch, silent: false).silent)
    }

    func testAccountSwitchDoesNotReuseAnotherOwnersImportChoice() {
        let store = makeStore()
        _ = store.beginImportNotificationCommit(batch(), silent: false)
        store.apply(authState: .signedIn(AuthSession(userID: "second", displayName: "Second", handle: "second")))
        XCTAssertTrue(store.importNeedsNotificationChoice(batch()))
        XCTAssertTrue(store.beginImportNotificationCommit(batch(), silent: true).silent)
        XCTAssertEqual(Set(store.importNotificationCommits.map(\.ownerID)).count, 2)
    }

    func testSilentSavePreservesVisibilityAndListIntent() throws {
        let store = makeStore()
        let result = store.saveCandidate(candidate(1), status: .been, visibility: .followers,
            note: nil, sourceType: .manual, senderNotificationPolicy: .silent)
        let saved = try XCTUnwrap(store.userPlaces.first { $0.id == result.userPlaceID })
        XCTAssertEqual(saved.visibility, .followers)
        XCTAssertEqual(saved.senderNotificationPolicy, .silent)
        XCTAssertEqual(store.visits(for: result.userPlaceID).first?.senderNotificationPolicy, .silent)
        let list = try XCTUnwrap(store.createPlaceList(name: "Test", description: "", visibility: .followers))
        _ = store.addCurrentUserPlace(userPlaceID: result.userPlaceID, to: list, senderNotificationPolicy: .silent)
        XCTAssertEqual(store.placeListItems.first?.senderNotificationPolicy, .silent)
    }

    func testLegacyQueuedActionsWithoutMetadataRestoreSilent() throws {
        let store = makeStore()
        saveVisit(1, policy: .standard, store: store)
        let snapshot = WanderStoreSnapshot(store: store)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        for key in ["userPlaces", "placeVisits"] {
            var records = try XCTUnwrap(json[key] as? [[String: Any]])
            for index in records.indices { records[index].removeValue(forKey: "senderNotificationJSON") }
            json[key] = records
        }
        let legacy = try JSONDecoder().decode(WanderStoreSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        let restored = makeStore(persistence: WanderStorePersistence(load: { legacy }, save: { _ in }))
        XCTAssertTrue(restored.placeVisits.filter { !$0.backfilledFromUserPlace }.allSatisfy { $0.senderNotificationPolicy.silent })
        XCTAssertTrue(restored.userPlaces.allSatisfy { $0.senderNotificationPolicy.silent })
    }

    func testDirectListAdditionKeepsCompanionSaveAndMembershipSilent() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(store.createPlaceList(name: "Try next", description: "", visibility: .followers))
        let result = await store.addCandidate(candidate(1), to: list, backend: nil,
            senderNotificationPolicy: .silent)
        XCTAssertEqual(result.outcome, .added)
        let saved = try XCTUnwrap(store.userPlaces.first)
        XCTAssertEqual(saved.status, .wannaGo)
        XCTAssertTrue(saved.senderNotificationPolicy.silent)
        XCTAssertTrue(try XCTUnwrap(store.placeListItems.first).senderNotificationPolicy.silent)
    }

    func testAccountDeletionRemovesImportIdentities() {
        let store = makeStore()
        _ = store.beginImportNotificationCommit(batch(), silent: true)
        store.resetAfterAccountDeletion()
        XCTAssertTrue(store.importNotificationCommits.isEmpty)
        XCTAssertTrue(WanderStoreSnapshot(store: store).importNotificationCommits?.isEmpty == true)
    }

    func testFinalizationWaitsForVisitsAndRetriesSameManifestAfterFailure() async throws {
        let store = makeStore()
        let repository = SenderImportTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let policy = store.beginImportNotificationCommit(batch(), silent: false)
        saveVisit(1, policy: policy, store: store)
        store.completeImportNotificationCommit(policy)
        await store.syncPendingImportNotifications(backend: backend)
        XCTAssertTrue(repository.calls.isEmpty)
        for visit in store.placeVisits { visit.syncStateRaw = SyncState.synced.rawValue }
        repository.shouldFail = true
        await store.syncPendingImportNotifications(backend: backend)
        XCTAssertFalse(try XCTUnwrap(store.importNotificationCommits.first).isSynced)
        repository.shouldFail = false
        await store.syncPendingImportNotifications(backend: backend)
        XCTAssertEqual(repository.calls.count, 2)
        XCTAssertEqual(repository.calls[0], repository.calls[1])
        XCTAssertTrue(try XCTUnwrap(store.importNotificationCommits.first).isSynced)
        await store.syncPendingImportNotifications(backend: backend)
        XCTAssertEqual(repository.calls.count, 2)
    }

    func testAccountChangeDuringFinalizeCannotAcknowledgeDifferentOwnersIntent() async throws {
        let store = makeStore()
        let repository = SenderImportTestRepository()
        let policy = store.beginImportNotificationCommit(batch(), silent: true)
        store.completeImportNotificationCommit(policy)
        repository.beforeReturn = {
            store.apply(authState: .signedIn(AuthSession(userID: "other", displayName: "Other", handle: "other")))
        }
        await store.syncPendingImportNotifications(backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertFalse(try XCTUnwrap(store.importNotificationCommits.first).isSynced)
    }

    private func makeStore(persistence: WanderStorePersistence? = nil) -> WanderStore {
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "sender", displayName: "Sender", handle: "sender")))
        store.setPrivateProfile(false)
        return store
    }

    private func batch() -> PlaceImportBatch {
        PlaceImportBatch(id: "import", source: .textNotes, sourceName: nil, state: .ready, totalCount: 10)
    }

    private func candidate(_ index: Int) -> PlaceCandidate {
        PlaceCandidate(id: "sender-\(index)", name: "Place \(index)", category: "coffee",
            latitude: 34 + Double(index) * 0.01, longitude: -118, confidence: 1)
    }

    private func saveVisit(_ index: Int, policy: SenderNotificationPolicy, store: WanderStore) {
        _ = store.saveCandidate(candidate(index), status: .been, visibility: .followers,
            note: nil, sourceType: .manual, senderNotificationPolicy: policy)
    }
}

@MainActor
private final class SenderImportTestRepository: UserPlaceRepository, ImportNotificationRepository {
    struct Call: Equatable { let id: String; let visits: [String] }
    var calls: [Call] = []
    var shouldFail = false
    var beforeReturn: (() -> Void)?
    func finalizeImportNotification(_ commit: ImportNotificationCommit, visitIDs: [String]) async throws {
        calls.append(Call(id: commit.id, visits: visitIDs))
        beforeReturn?()
        if shouldFail { throw URLError(.timedOut) }
    }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { [] }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}
