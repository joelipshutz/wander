import Combine
import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportCheckpointFingerprintTests: XCTestCase {
    func testSnapshotFingerprintKeepsOriginalAuthorityRulesForEveryRecordKind() async throws {
        for mutation in FingerprintMutation.allCases {
            for asynchronous in [false, true] {
                let fixture = FingerprintFixture()
                try await fixture.hydrate()
                XCTAssertTrue(fixture.store.currentUserCalendarProjection.isAuthoritative)
                try fixture.mutate(mutation)
                let observer = FingerprintObserver()
                let token = fixture.store.objectWillChange.sink { _ in
                    MainActor.assumeIsolated { observer.receive() }
                }
                defer { token.cancel() }
                let before = fixture.store.currentUserCalendarFingerprintBuildCount
                let operation = {
                    fixture.store.recordAutomaticImportCheckpoint(fixture.journal())
                    observer.isArmed = true
                }
                if asynchronous {
                    try await fixture.store.performCheckpointedImportMutationsAsync(operation)
                } else {
                    try fixture.store.performCheckpointedImportMutations(operation)
                }
                observer.isArmed = false
                let detail = "mutation=\(mutation) asynchronous=\(asynchronous)"
                XCTAssertEqual(fixture.store.currentUserCalendarFingerprintBuildCount - before, 1, detail)
                XCTAssertEqual(observer.count, mutation.changesAuthority ? 1 : 0, detail)
                XCTAssertEqual(fixture.store.currentUserCalendarProjection.isAuthoritative,
                    !mutation.changesAuthority, detail)
                let written = try XCTUnwrap(fixture.probe.checkpoints.last)
                XCTAssertEqual(written.userPlaces, fixture.store.userPlaces.map(WanderStoreSnapshot.UserPlaceRecord.init), detail)
                XCTAssertEqual(written.placeAttributes, fixture.store.placeAttributes.map(WanderStoreSnapshot.PlaceAttributeRecord.init), detail)
                XCTAssertEqual(written.placeVisits, fixture.store.placeVisits.map(WanderStoreSnapshot.PlaceVisitRecord.init), detail)
            }
        }
    }

    func testAuthorityNotificationRawMutationsAreCapturedAfterObserversReturn() async throws {
        for asynchronous in [false, true] {
            let fixture = FingerprintFixture()
            try await fixture.hydrate()
            fixture.store.userPlaces[0].note = "Triggers authority loss"
            let observer = FingerprintObserver()
            observer.onPublication = {
                fixture.store.userPlaces[0].note = "Observer note"
                fixture.store.userPlaces[0].statusRaw = PlaceStatus.been.rawValue
                fixture.store.userPlaces[0].serverID = "observer-parent-alias"
                fixture.store.places[0].canonicalName = "Observer place"
            }
            let token = fixture.store.objectWillChange.sink { _ in
                MainActor.assumeIsolated { observer.receive() }
            }
            defer { token.cancel() }
            let operation = {
                fixture.store.recordAutomaticImportCheckpoint(fixture.journal())
                observer.isArmed = true
            }
            if asynchronous { try await fixture.store.performCheckpointedImportMutationsAsync(operation) }
            else { try fixture.store.performCheckpointedImportMutations(operation) }
            let written = try XCTUnwrap(fixture.probe.checkpoints.last)
            XCTAssertEqual(observer.count, 1)
            XCTAssertEqual(written.userPlaces.first?.note, "Observer note")
            XCTAssertEqual(written.userPlaces.first?.statusRaw, PlaceStatus.been.rawValue)
            XCTAssertEqual(written.userPlaces.first?.serverID, "observer-parent-alias")
            XCTAssertEqual(written.places.first?.canonicalName, "Observer place")
            XCTAssertFalse(fixture.store.currentUserCalendarProjection.isAuthoritative)
        }
    }

    func testAuthorityObserverAccountSwitchUsesFreshOwnerInAcknowledgedSnapshot() async throws {
        for asynchronous in [false, true] {
            let fixture = FingerprintFixture()
            try await fixture.hydrate()
            fixture.store.userPlaces[0].note = "Triggers authority loss"
            let observer = FingerprintObserver()
            observer.onPublication = {
                fixture.store.apply(authState: .signedIn(AuthSession(userID: "observer-account",
                    displayName: "Observer", handle: "observer")))
            }
            let token = fixture.store.objectWillChange.sink { _ in
                MainActor.assumeIsolated { observer.receive() }
            }
            defer { token.cancel() }
            let operation = {
                fixture.store.recordAutomaticImportCheckpoint(fixture.journal())
                observer.isArmed = true
            }
            if asynchronous { try await fixture.store.performCheckpointedImportMutationsAsync(operation) }
            else { try fixture.store.performCheckpointedImportMutations(operation) }
            XCTAssertEqual(observer.count, 1)
            XCTAssertEqual(fixture.store.currentUser.id, "observer-account")
            XCTAssertEqual(fixture.probe.checkpoints.last?.currentUser.serverID, "observer-account")
        }
    }

    func testMemoryOnlyCheckpointStillReconcilesAuthorityAndNotifiesOnce() async throws {
        let fixture = FingerprintFixture(memoryOnly: true)
        try await fixture.hydrate()
        let observer = FingerprintObserver()
        let token = fixture.store.objectWillChange.sink { _ in
            MainActor.assumeIsolated { observer.receive() }
        }
        defer { token.cancel() }
        fixture.store.userPlaces[0].note = "Memory-only change"
        let before = fixture.store.currentUserCalendarFingerprintBuildCount
        try await fixture.store.performCheckpointedImportMutationsAsync {
            fixture.store.recordAutomaticImportCheckpoint(fixture.journal())
            observer.isArmed = true
        }
        XCTAssertEqual(observer.count, 1)
        XCTAssertEqual(fixture.store.currentUserCalendarFingerprintBuildCount - before, 1)
        XCTAssertFalse(fixture.store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertTrue(fixture.probe.checkpoints.isEmpty)
    }
}

private enum FingerprintMutation: CaseIterable, Hashable {
    case unchanged, parentNote, parentAlias, parentStatus, deletedParentNote, otherParentNote
    case localAliasAttribute, serverAliasAttribute, remoteAttribute, duplicateAttributeOrder
    case localVisit, deletedVisit, cleanSyntheticVisit, dirtySyntheticVisit, invalidSyntheticSync, otherVisit

    var changesAuthority: Bool {
        switch self {
        case .unchanged, .otherParentNote, .remoteAttribute, .cleanSyntheticVisit, .otherVisit: false
        default: true
        }
    }
}

@MainActor
private final class FingerprintObserver {
    var isArmed = false
    var count = 0
    var onPublication: (@MainActor @Sendable () -> Void)?
    func receive() {
        guard isArmed else { return }
        isArmed = false
        count += 1
        onPublication?()
    }
}

@MainActor
private final class FingerprintCheckpointProbe {
    var checkpoints: [WanderStoreSnapshot] = []
    var persistence: WanderStorePersistence {
        WanderStorePersistence(load: { nil }, save: { _ in },
            checkpoint: { [self] in checkpoints.append($0) },
            checkpointAsync: { [self] in checkpoints.append($0) })
    }
}

@MainActor
private final class FingerprintFixture {
    let probe: FingerprintCheckpointProbe
    let store: WanderStore
    let remoteAttribute: LocalPlaceAttribute

    init(memoryOnly: Bool = false) {
        let probe = FingerprintCheckpointProbe()
        self.probe = probe
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let owner = LocalProfile(localID: "fingerprint-owner-local", serverID: "fingerprint-owner",
            handle: "fixture", displayName: "Fixture")
        let place = LocalPlace(localID: "fingerprint-place", canonicalName: "Fixture", category: "park",
            latitude: 34, longitude: -118)
        let owned = LocalUserPlace(localID: "owned-local", serverID: "owned-server", userID: owner.id,
            placeID: place.id, status: .wannaGo, visibility: .selfOnly, sourceType: "manual")
        let deleted = LocalUserPlace(localID: "deleted-parent", userID: owner.id,
            placeID: "deleted-place", status: .wannaGo, visibility: .selfOnly, sourceType: "manual", deletedAt: date)
        let other = LocalUserPlace(localID: "other-parent", userID: "another-owner",
            placeID: "other-place", status: .wannaGo, visibility: .selfOnly, sourceType: "manual")
        func attribute(_ id: String, parent: String, value: String) -> LocalPlaceAttribute {
            LocalPlaceAttribute(localID: id, userPlaceID: parent, questionKey: id,
                valueType: "text", valueJSON: value)
        }
        remoteAttribute = attribute("remote_attr_fixture", parent: owned.id, value: "\"remote\"")
        let attributes = [attribute("local-attribute", parent: owned.localID, value: "\"local\""),
            attribute("server-attribute", parent: owned.id, value: "\"server\""),
            attribute("same-attribute-id", parent: owned.id, value: "\"first\""),
            attribute("same-attribute-id", parent: owned.id, value: "\"second\"")]
        func visit(_ id: String, parent: String, sync: SyncState, deletedAt: Date? = nil) -> LocalPlaceVisit {
            LocalPlaceVisit(localID: id, userPlaceID: parent, visitedAt: date, note: id,
                syncState: sync, deletedAt: deletedAt)
        }
        let visits = [visit("local-visit", parent: owned.localID, sync: .pendingCreate),
            visit("deleted-visit", parent: owned.id, sync: .pendingDelete, deletedAt: date),
            visit("remote_profile_visit_clean", parent: owned.id, sync: .synced),
            visit("remote_profile_visit_dirty", parent: owned.localID, sync: .pendingUpdate),
            visit("remote_profile_visit_invalid", parent: owned.id, sync: .pendingUpdate),
            visit("other-visit", parent: other.id, sync: .pendingCreate)]
        visits[4].syncStateRaw = "unknown-fixture-state"
        let fixtures = WanderFixtures(currentUser: owner, profiles: [owner], places: [place],
            userPlaces: [owned, deleted, other], placeAttributes: attributes, placeVisits: visits,
            follows: [], blocks: [], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: []))
        store = WanderStore(fixtures: fixtures, persistence: memoryOnly ? nil : probe.persistence)
    }

    func hydrate() async throws {
        let visible = VisiblePlace(id: store.userPlaces[0].id, place: store.places[0],
            userPlace: store.userPlaces[0], owner: store.currentUser, attributes: [remoteAttribute])
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(userPlaceRepository: FingerprintCalendarRepository(visible: visible)))
        XCTAssertTrue(hydrated)
        XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
        probe.checkpoints.removeAll()
    }

    func journal() -> PlaceImportAutoSaveCheckpoint {
        let batch = PlaceImportBatch(id: "fingerprint-batch", source: .googleMaps, sourceName: "Fixture",
            totalCount: 0, automaticSaveRequested: true)
        return PlaceImportAutoSaveCheckpoint(ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: [])
    }

    func mutate(_ mutation: FingerprintMutation) throws {
        switch mutation {
        case .unchanged: break
        case .parentNote: store.userPlaces[0].note = "Changed"
        case .parentAlias: store.userPlaces[0].serverID = "changed-alias"
        case .parentStatus: store.userPlaces[0].statusRaw = "unrecognized-status"
        case .deletedParentNote: try XCTUnwrap(store.userPlaces.first { $0.localID == "deleted-parent" }).note = "Changed"
        case .otherParentNote: try XCTUnwrap(store.userPlaces.first { $0.localID == "other-parent" }).note = "Changed"
        case .localAliasAttribute, .serverAliasAttribute, .remoteAttribute:
            let id = mutation == .localAliasAttribute ? "local-attribute"
                : (mutation == .serverAliasAttribute ? "server-attribute" : "remote_attr_fixture")
            try XCTUnwrap(store.placeAttributes.first { $0.localID == id }).valueJSON = "\"Changed\""
        case .duplicateAttributeOrder:
            let duplicates = store.placeAttributes.filter { $0.localID == "same-attribute-id" }
            XCTAssertEqual(duplicates.count, 2)
            let first = duplicates[0].valueJSON
            duplicates[0].valueJSON = duplicates[1].valueJSON
            duplicates[1].valueJSON = first
        case .localVisit, .deletedVisit, .cleanSyntheticVisit, .dirtySyntheticVisit, .invalidSyntheticSync, .otherVisit:
            let ids: [FingerprintMutation: String] = [.localVisit: "local-visit", .deletedVisit: "deleted-visit",
                .cleanSyntheticVisit: "remote_profile_visit_clean", .dirtySyntheticVisit: "remote_profile_visit_dirty",
                .invalidSyntheticSync: "remote_profile_visit_invalid", .otherVisit: "other-visit"]
            let id = try XCTUnwrap(ids[mutation])
            try XCTUnwrap(store.placeVisits.first { $0.localID == id }).note = "Changed"
        }
    }
}

@MainActor
private final class FingerprintCalendarRepository: UserPlaceRepository {
    let visible: VisiblePlace
    init(visible: VisiblePlace) { self.visible = visible }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { [visible] }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws { throw URLError(.unsupportedURL) }
    func delete(userPlaceID: String) async throws { throw URLError(.unsupportedURL) }
}
