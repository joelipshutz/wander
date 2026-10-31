import Foundation
import XCTest
@testable import Wander

@MainActor
final class AutomaticImportProjectionContextTests: XCTestCase {
    private enum Failure: Error { case requested }

    func testRetainedListProjectionObservesEachUnchangedPlaceOnceAcrossChunks() async throws {
        let fixture = library()
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        for id in fixture.saveIDs {
            try await store.performCheckpointedImportMutationsAsync(using: context) {
                XCTAssertTrue(context.isInstalled)
                XCTAssertEqual(insert(id, fixture: fixture, context: context).outcome, .added)
            }
            XCTAssertFalse(context.isInstalled)
            XCTAssertEqual(context.listFingerprintReadCount, 3,
                "Unchanged models must not rebuild the initial grouping index for each chunk")
            await Task.yield()
        }
        XCTAssertEqual(store.liveReadableListItems().count, 3)
        XCTAssertEqual(store.placeLists.first?.cachedItemCount, 3)
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.senderNotificationPolicy == .silent })
        context.finish()
        context.finish()
        XCTAssertTrue(context.isFinished)
        XCTAssertEqual(context.listFingerprintReadCount, 0)
        XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: context).outcome, .permissionDenied)
    }

    func testRawAliasBridgeAndRestorationBetweenChunksMatchFreshScopes() async throws {
        let retained = library()
        let fresh = library()
        let context = try XCTUnwrap(retained.store.makeAutomaticImportProjectionContext(
            ownerUserID: retained.store.currentUser.id))
        defer { context.finish() }
        let original = retained.store.places[1].sourceProviderPlaceID
        for step in 0..<3 {
            if step > 0 {
                for fixture in [retained, fresh] {
                    fixture.store.places[1].sourceProviderPlaceID = step == 1
                        ? fixture.store.places[0].sourceProviderPlaceID : original
                }
            }
            let index = step == 0 ? 0 : 1
            let expected = try await fresh.store.performCheckpointedImportMutationsAsync {
                insert(fresh.saveIDs[index], fixture: fresh, context: nil)
            }
            let actual = try await retained.store.performCheckpointedImportMutationsAsync(using: context) {
                insert(retained.saveIDs[index], fixture: retained, context: context)
            }
            XCTAssertEqual(actual, expected)
            XCTAssertEqual(actual.outcome, step == 1 ? .alreadyInList : .added)
        }
        XCTAssertEqual(memberships(retained.store), memberships(fresh.store))
        XCTAssertEqual(retained.store.placeLists.first?.cachedItemCount, 2)
        XCTAssertEqual(retained.store.placeLists.first?.cachedItemCount, fresh.store.placeLists.first?.cachedItemCount)
        XCTAssertGreaterThan(context.listFingerprintReadCount, 3, "Both raw edits must invalidate grouping")
    }

    func testStrictLookupRevalidatesRawIdentityEditsAndOrdinarySavesBetweenChunks() async throws {
        let fixture = library()
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        let target = candidate(0)
        try await store.performCheckpointedImportMutationsAsync(using: context) {
            XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, fixture.saveIDs[0])
        }
        store.places[0].sourceProviderPlaceID = "changed-provider"
        store.places[0].canonicalName = "Changed raw model"
        XCTAssertNil(store.existingImportSave(matching: target))
        let uiSave = store.saveCandidate(target, status: .wannaGo, visibility: .selfOnly,
            note: "Ordinary UI save", sourceType: .manual)
        XCTAssertFalse(context.isInstalled)
        try await store.performCheckpointedImportMutationsAsync(using: context) {
            XCTAssertEqual(store.existingImportSave(matching: target)?.userPlaceID, uiSave.userPlaceID)
            let imported = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                note: "Must not replace the UI note", sourceType: .link)
            XCTAssertEqual(imported.userPlaceID, uiSave.userPlaceID)
            XCTAssertEqual(insert(imported.userPlaceID, fixture: fixture, context: context).outcome, .added)
        }
        XCTAssertEqual(store.places.count, 4)
        XCTAssertEqual(store.userPlaces.first { $0.id == uiSave.userPlaceID }?.note, "Ordinary UI save")
        XCTAssertEqual(context.listFingerprintReadCount, 4)
    }

    func testSameCountMembershipTombstonesAndPermissionsStayFreshBetweenChunks() async throws {
        let retained = library()
        let fresh = library()
        let context = try XCTUnwrap(retained.store.makeAutomaticImportProjectionContext(
            ownerUserID: retained.store.currentUser.id))
        defer { context.finish() }
        for fixture in [retained, fresh] {
            let projection = fixture.store === retained.store ? context : nil
            try await fixture.store.performCheckpointedImportMutationsAsync(using: projection) {
                XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: projection).outcome, .added)
            }
            // Public removal replaces the member value without changing the
            // array count; the retained projection must observe its tombstone.
            XCTAssertTrue(fixture.store.removePlace(placeID: fixture.store.places[0].id, from: fixture.list))
            XCTAssertEqual(fixture.store.placeListItems.count, 1)
            XCTAssertNotNil(fixture.store.placeListItems[0].deletedAt)
            try await fixture.store.performCheckpointedImportMutationsAsync(using: projection) {
                XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: projection).outcome, .added)
            }
            var forbidden = fixture.list
            forbidden.ownerUserID = "another-owner"
            let denied = fixture.store.withBatchedCurrentUserPlaceListInsertions(to: forbidden,
                senderNotificationPolicy: .silent, using: projection) { $0(fixture.saveIDs[1]) }
            XCTAssertEqual(denied.outcome, .permissionDenied)
        }
        XCTAssertEqual(memberships(retained.store), memberships(fresh.store))
        XCTAssertEqual(retained.store.placeListItems.count, 2)
        XCTAssertEqual(retained.store.liveReadableListItems().count, fresh.store.liveReadableListItems().count)
        XCTAssertEqual(retained.store.liveReadableListItems().count, 1)
    }

    func testSameOwnerAuthRefreshIsValidButAccountRoundTripAndOtherStoreAreRejected() async throws {
        let fixture = library()
        let store = fixture.store
        let owner = store.currentUser.id
        let profile = store.currentUser
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: owner))
        defer { context.finish() }
        XCTAssertNil(store.makeAutomaticImportProjectionContext(ownerUserID: "another-owner"))
        store.apply(authState: .signedIn(AuthSession(userID: owner, displayName: "Refreshed", handle: "refreshed")))
        XCTAssertTrue(store.currentUser === profile)
        try await store.performCheckpointedImportMutationsAsync(using: context) {
            XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: context).outcome, .added)
        }
        let otherStore = library().store
        await assertRejected(context, by: otherStore)
        store.apply(authState: .signedIn(AuthSession(userID: "other-account", displayName: "Other", handle: "other")))
        await assertRejected(context, by: store)
        store.apply(authState: .signedIn(AuthSession(userID: owner, displayName: "Original", handle: "original")))
        XCTAssertFalse(store.currentUser === profile)
        await assertRejected(context, by: store)
        XCTAssertEqual(insert(fixture.saveIDs[1], fixture: fixture, context: context).outcome, .permissionDenied)
        let replacement = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: owner))
        defer { replacement.finish() }
        try await store.performCheckpointedImportMutationsAsync(using: replacement) {}
    }

    func testNestedOrdinaryAndThrowingListScopesRestoreTheOuterProjection() async throws {
        let fixture = library()
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        try await store.performCheckpointedImportMutationsAsync(using: context) {
            XCTAssertTrue(context.isInstalled)
            do {
                try store.performBatchedImportMutations {
                    XCTAssertFalse(context.isInstalled)
                    XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: nil).outcome, .added)
                    throw Failure.requested
                }
                XCTFail("Expected nested scope failure")
            } catch Failure.requested {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(context.isInstalled)
            do {
                try store.withBatchedCurrentUserPlaceListInsertions(to: fixture.list, using: context) { insert in
                    XCTAssertEqual(insert(fixture.saveIDs[1]).outcome, .added)
                    throw Failure.requested
                }
                XCTFail("Expected list scope failure")
            } catch Failure.requested {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(context.isInstalled)
        }
        XCTAssertFalse(context.isInstalled)
        try await store.performCheckpointedImportMutationsAsync(using: context) {
            XCTAssertEqual(insert(fixture.saveIDs[2], fixture: fixture, context: context).outcome, .added)
        }
        XCTAssertEqual(store.liveReadableListItems().count, 3)
        XCTAssertEqual(context.listFingerprintReadCount, 3)
    }

    func testCheckpointAwaitHasNoInstalledProjectionOrPersistenceDeferral() async throws {
        let gate = ProjectionCheckpointGate()
        var ordinary: [WanderStoreSnapshot] = []
        let fixture = library(persistence: WanderStorePersistence(load: { nil }, save: { ordinary.append($0) },
            checkpointAsync: { await gate.write($0) }))
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        defer { context.finish() }
        let task = Task { @MainActor in
            try await store.performCheckpointedImportMutationsAsync(using: context) {
                XCTAssertTrue(context.isInstalled)
                XCTAssertEqual(self.insert(fixture.saveIDs[0], fixture: fixture, context: context).outcome, .added)
            }
        }
        await gate.waitUntilEntered()
        XCTAssertFalse(context.isInstalled)
        XCTAssertTrue(ordinary.isEmpty)
        let uiSave = store.saveCandidate(candidate(8), status: .wannaGo, visibility: .selfOnly,
            note: nil, sourceType: .manual)
        XCTAssertEqual(ordinary.count, 1, "UI writes must not join the suspended import checkpoint")
        XCTAssertEqual(gate.snapshot?.userPlaces.count, 3)
        XCTAssertEqual(ordinary.last?.userPlaces.count, 4)
        gate.resume()
        try await task.value
        // Reuse the retained list after an unrelated UI append, without retaining
        // the import scope through the disk await or losing the appended model.
        XCTAssertEqual(insert(uiSave.userPlaceID, fixture: fixture, context: context).outcome, .added)
        XCTAssertEqual(context.listFingerprintReadCount, 4)
    }

    func testCancellationDuringAcknowledgementLeavesNoAmbientStateAndFinishesAtRunExit() async throws {
        let gate = ProjectionCheckpointGate()
        let fixture = library(persistence: WanderStorePersistence(load: { nil }, save: { _ in },
            checkpointAsync: { await gate.write($0) }))
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        let task = Task { @MainActor in
            defer { context.finish() }
            try await store.performCheckpointedImportMutationsAsync(using: context) {
                XCTAssertEqual(self.insert(fixture.saveIDs[0], fixture: fixture, context: context).outcome, .added)
            }
        }
        await gate.waitUntilEntered()
        task.cancel()
        XCTAssertFalse(context.isInstalled)
        XCTAssertFalse(context.isFinished, "Retained state is owned until the durable acknowledgement returns")
        gate.resume()
        try await task.value
        XCTAssertTrue(context.isFinished)
        XCTAssertEqual(context.listFingerprintReadCount, 0)
        XCTAssertEqual(gate.snapshot?.placeListItems?.count, 1)
        XCTAssertEqual(store.placeListItems.count, 1)
        await assertRejected(context, by: store)
    }

    func testFailedCheckpointRestoresScopesAndRunDeferFinishesRetainedState() async throws {
        let fixture = library(persistence: WanderStorePersistence(load: { nil }, save: { _ in },
            checkpointAsync: { _ in throw Failure.requested }))
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: store.currentUser.id))
        func run() async throws {
            defer { context.finish() }
            try await store.performCheckpointedImportMutationsAsync(using: context) {
                XCTAssertEqual(insert(fixture.saveIDs[0], fixture: fixture, context: context).outcome, .added)
            }
        }
        do {
            try await run()
            XCTFail("Expected checkpoint failure")
        } catch Failure.requested {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(context.isInstalled)
        XCTAssertTrue(context.isFinished)
        XCTAssertEqual(context.listFingerprintReadCount, 0)
        XCTAssertEqual(store.placeListItems.count, 1, "Failed durability acknowledgement must retain live rows")
        await assertRejected(context, by: store)
        XCTAssertEqual(store.addCurrentUserPlace(userPlaceID: fixture.saveIDs[1], to: fixture.list).outcome, .added)
    }

    private func assertRejected(_ context: WanderStore.AutomaticImportProjectionContext, by store: WanderStore,
                                file: StaticString = #filePath, line: UInt = #line) async {
        var entered = false
        do {
            try await store.performCheckpointedImportMutationsAsync(using: context) { entered = true }
            XCTFail("Expected invalid context rejection", file: file, line: line)
        } catch {}
        XCTAssertFalse(entered, file: file, line: line)
        XCTAssertFalse(context.isInstalled, file: file, line: line)
    }

    private struct Library {
        let store: WanderStore
        let list: LocalPlaceList
        let saveIDs: [String]
    }

    private func library(persistence: WanderStorePersistence? = nil) -> Library {
        let owner = LocalProfile(localID: "context-local-owner", serverID: "context-owner",
            handle: "context", displayName: "Context")
        let places = (0..<3).map {
            LocalPlace(localID: "context-place-\($0)", canonicalName: "Context place \($0)", category: "park",
                latitude: 34 + Double($0), longitude: -118, sourceProvider: "mapkit", sourceProviderPlaceID: "provider-\($0)")
        }
        let saves = places.enumerated().map {
            LocalUserPlace(localID: "context-save-\($0.offset)", userID: owner.id, placeID: $0.element.id,
                status: .wannaGo, visibility: .selfOnly, sourceType: "manual")
        }
        let list = LocalPlaceList(localID: "context-list", ownerUserID: owner.id,
            name: "Context list", description: "", visibility: .stealth)
        let fixtures = WanderFixtures(currentUser: owner, profiles: [owner], places: places, userPlaces: saves,
            placeAttributes: [], follows: [], blocks: [], placeLists: [list], placeListMembers: [],
            placeListItems: [], contactProvider: FakeContactProvider(seededMatches: []))
        return Library(store: WanderStore(fixtures: fixtures, persistence: persistence), list: list, saveIDs: saves.map(\.id))
    }

    private func insert(_ id: String, fixture: Library,
                        context: WanderStore.AutomaticImportProjectionContext?) -> ListPlaceAddResult {
        fixture.store.withBatchedCurrentUserPlaceListInsertions(to: fixture.list,
            senderNotificationPolicy: .silent, using: context) { $0(id) }
    }

    private func candidate(_ index: Int) -> PlaceCandidate {
        PlaceCandidate(id: "context-candidate-\(index)", name: "Context place \(index)", category: "park",
            latitude: 34 + Double(index), longitude: -118, sourceProvider: "mapkit",
            sourceProviderPlaceID: "provider-\(index)", confidence: 1)
    }

    private struct Membership: Equatable {
        let localID: String
        let listID: String
        let placeID: String
        let owner: String?
        let source: String?
        let deleted: Bool
        let policy: SenderNotificationPolicy
    }

    private func memberships(_ store: WanderStore) -> [Membership] {
        store.placeListItems.map { Membership(localID: $0.localID, listID: $0.listID, placeID: $0.placeID,
            owner: $0.ownerUserPlaceID, source: $0.sourceUserPlaceID, deleted: $0.deletedAt != nil,
            policy: $0.senderNotificationPolicy) }
    }
}

@MainActor
private final class ProjectionCheckpointGate {
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
        XCTFail("Checkpoint did not reach the controlled gate")
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
