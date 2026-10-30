import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportResolvedPlaceSaveTests: XCTestCase {
    func testPendingDuplicateRemovalIdentityUsesFreshStrictFirstMatchAndOwnedTombstoneAliases() throws {
        let original = place("local-place", name: "Shared Cafe", providerID: "target")
        original.serverID = "server-place"
        let earlier = place("earlier", name: "Shared Cafe", providerID: "different-branch")
        let store = store(places: [earlier, original])
        let target = candidate("target", name: "Shared Cafe")
        let saved = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
            note: nil, sourceType: .link)
        let parent = try XCTUnwrap(store.userPlaces.first)
        parent.serverID = "server-save"
        parent.deletedAt = .now
        for saveID in [saved.userPlaceID, "server-save"] {
            XCTAssertTrue(store.importCandidate(target, matchesUserPlaceID: saveID))
            parent.placeID = original.localID
            XCTAssertTrue(store.importCandidate(target, matchesUserPlaceID: saveID))
            parent.placeID = original.serverID!
            XCTAssertTrue(store.importCandidate(target, matchesUserPlaceID: saveID))
        }
        earlier.sourceProvider = "legacy"
        earlier.sourceProviderPlaceID = nil
        XCTAssertTrue(VisiblePlaceGrouping.matches(earlier, candidate: target))
        XCTAssertFalse(store.importCandidate(target, matchesUserPlaceID: "server-save"),
            "An earlier strict winner must not be suppressed by another place's removed save")
        earlier.sourceProvider = target.sourceProvider
        earlier.sourceProviderPlaceID = "different-branch"
        XCTAssertTrue(store.importCandidate(target, matchesUserPlaceID: "server-save"))
        original.sourceProviderPlaceID = "changed"
        XCTAssertFalse(store.importCandidate(target, matchesUserPlaceID: "server-save"))
        original.sourceProviderPlaceID = "target"
        parent.userID = "other-owner"
        XCTAssertFalse(store.importCandidate(target, matchesUserPlaceID: "server-save"))
    }

    func testNewAndUnsavedMatchesPreserveOrdinarySaveResultsEffectsAndSnapshot() throws {
        for hasExistingPlace in [false, true] {
            for status in [PlaceStatus.wannaGo, .been] {
                let ordinaryRecord = ResolvedPlaceSaveRecorder()
                let importedRecord = ResolvedPlaceSaveRecorder()
                let ordinary = store(places: hasExistingPlace ? [place("existing", providerID: "target")] : [],
                    recorder: ordinaryRecord)
                let imported = store(places: hasExistingPlace ? [place("existing", providerID: "target")] : [],
                    recorder: importedRecord)
                let target = candidate("target")
                let visitedAt = Date(timeIntervalSince1970: 1_790_000_000)
                let expected = ordinary.performBatchedLocalMutations {
                    ordinary.saveCandidate(target, status: status, visibility: .selfOnly,
                        note: "Fixture note", sourceType: .link, ratingScore: 4, visitedAt: visitedAt,
                        requestsProductUpsell: false, senderNotificationPolicy: .silent)
                }
                let actual = imported.performBatchedImportMutations {
                    imported.saveImportedCandidate(target, status: status, visibility: .selfOnly,
                        note: "Fixture note", sourceType: .link, ratingScore: 4, visitedAt: visitedAt)
                }
                XCTAssertEqual(actual, expected)
                XCTAssertEqual(imported.places.count, ordinary.places.count)
                let actualSave = try XCTUnwrap(imported.userPlaces.first)
                let expectedSave = try XCTUnwrap(ordinary.userPlaces.first)
                XCTAssertEqual(actualSave.placeID, expectedSave.placeID)
                XCTAssertEqual(actualSave.status, expectedSave.status)
                XCTAssertEqual(actualSave.visibility, expectedSave.visibility)
                XCTAssertEqual(actualSave.note, expectedSave.note)
                XCTAssertEqual(actualSave.ratingScore, expectedSave.ratingScore)
                XCTAssertEqual(actualSave.senderNotificationJSON, expectedSave.senderNotificationJSON)
                XCTAssertEqual(imported.visits(for: actual.userPlaceID).count,
                    ordinary.visits(for: expected.userPlaceID).count)
                XCTAssertEqual(imported.visits(for: actual.userPlaceID).map(\.visitedAt),
                    ordinary.visits(for: expected.userPlaceID).map(\.visitedAt))
                XCTAssertEqual(importedRecord.events, ordinaryRecord.events)
                XCTAssertEqual(imported.saveStreakSummary, ordinary.saveStreakSummary)
                XCTAssertEqual(importedRecord.saveCount, 1)
                XCTAssertEqual(ordinaryRecord.saveCount, 1)
                let snapshot = try XCTUnwrap(importedRecord.snapshot)
                XCTAssertEqual(snapshot.userPlaces.map(\.localID), imported.userPlaces.map(\.localID))
                XCTAssertEqual(snapshot.userPlaces.map(\.senderNotificationJSON),
                    imported.userPlaces.map(\.senderNotificationJSON))
                XCTAssertEqual(snapshot.saveStreakDatesByUserID, imported.saveStreakDatesByUserID)
            }
        }
    }

    func testStrictFirstMatchAndProviderConflictStillControlWhichPlaceIsSaved() throws {
        for exactFirst in [false, true] {
            let fallback = place("fallback", name: "Shared Cafe", provider: "legacy", providerID: nil)
            let exact = place("exact", name: "Other", providerID: "target")
            let store = store(places: exactFirst ? [exact, fallback] : [fallback, exact])
            let target = candidate("target", name: "Shared Cafe")
            let oracle = try XCTUnwrap(store.places.first { VisiblePlaceGrouping.matches($0, candidate: target) })
            XCTAssertTrue(oracle === (exactFirst ? exact : fallback))
            let result = store.performBatchedImportMutations {
                store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                    note: nil, sourceType: .link)
            }
            XCTAssertEqual(store.userPlaces.first { $0.id == result.userPlaceID }?.placeID, oracle.id)
            XCTAssertEqual(store.places.count, 2)
        }

        let differentBranch = place("other-branch", name: "Shared Cafe", providerID: "other-provider-id")
        let store = store(places: [differentBranch])
        let target = candidate("target", name: "Shared Cafe")
        XCTAssertFalse(VisiblePlaceGrouping.matches(differentBranch, candidate: target))
        let result = store.performBatchedImportMutations {
            store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                note: nil, sourceType: .link)
        }
        XCTAssertEqual(store.places.count, 2)
        XCTAssertNotEqual(store.userPlaces.first { $0.id == result.userPlaceID }?.placeID, differentBranch.id)
    }

    func testAliasesExistingBeenAndUpgradeRemainIdempotent() throws {
        let existing = place("local-place", providerID: "provider")
        existing.serverID = "server-place"
        let store = store(places: [existing])
        let localAlias = candidate("unrelated", id: existing.localID, name: "Different name")
        let serverAlias = candidate("unrelated", id: existing.serverID!, name: "Different name")
        try store.performBatchedImportMutations {
            let first = store.saveImportedCandidate(localAlias, status: .wannaGo, visibility: .followers,
                note: "Original want", sourceType: .link)
            let parent = try XCTUnwrap(store.userPlaces.first { $0.id == first.userPlaceID })
            let repeated = store.saveImportedCandidate(serverAlias, status: .wannaGo, visibility: .selfOnly,
                note: "Must not replace", sourceType: .link)
            XCTAssertEqual(repeated.userPlaceID, first.userPlaceID)
            XCTAssertEqual(parent.note, "Original want")
            let visibility = parent.visibility
            let upgraded = store.saveImportedCandidate(serverAlias, status: .been, visibility: .selfOnly,
                note: "First visit", sourceType: .link, ratingScore: 4)
            XCTAssertEqual(upgraded.userPlaceID, first.userPlaceID)
            XCTAssertEqual(parent.visibility, visibility)
            XCTAssertEqual(parent.status, .been)
            let originalVisits = store.visits(for: first.userPlaceID)
            XCTAssertEqual(originalVisits.count, 1)
            for status in [PlaceStatus.wannaGo, .been] {
                let repeated = store.saveImportedCandidate(localAlias, status: status, visibility: .selfOnly,
                    note: "Must not overwrite", sourceType: .link, ratingScore: 1)
                XCTAssertEqual(repeated.userPlaceID, first.userPlaceID)
                XCTAssertEqual(store.visits(for: first.userPlaceID), originalVisits)
            }
            XCTAssertEqual(store.places.count, 1)
            XCTAssertEqual(store.userPlaces.count, 1)
        }
    }

    func testCompletedCallCannotRetainMissAcrossRawIdentityAndCoordinateMutations() throws {
        let edits: [(LocalPlace, PlaceCandidate) -> Void] = [
            { $0.localID = $1.id },
            { $0.serverID = $1.id },
            { $0.sourceProvider = $1.sourceProvider; $0.sourceProviderPlaceID = $1.sourceProviderPlaceID },
            { $0.canonicalName = $1.name; $0.sourceProvider = "legacy"; $0.sourceProviderPlaceID = nil },
            { $0.canonicalName = $1.name; $0.sourceProvider = "legacy"; $0.sourceProviderPlaceID = nil
                $0.address = $1.address },
            { $0.canonicalName = $1.name; $0.sourceProvider = "legacy"; $0.sourceProviderPlaceID = nil
                $0.address = nil; $0.latitude = $1.latitude!; $0.longitude = $1.longitude! }
        ]
        for (index, edit) in edits.enumerated() {
            let mutable = place("mutable", name: "Original", providerID: "original")
            if index >= 4 {
                mutable.address = "20 Old Road"
                mutable.latitude = 35
                mutable.longitude = -119
            }
            let store = store(places: [mutable])
            let target = candidate("target", name: "Changed")
            try store.performBatchedImportMutations {
                XCTAssertNil(store.existingImportSave(matching: target))
                _ = store.saveImportedCandidate(candidate("unrelated", name: "Unrelated"), status: .wannaGo,
                    visibility: .selfOnly, note: nil, sourceType: .link)
                edit(mutable, target)
                let oracle = try XCTUnwrap(store.places.first { VisiblePlaceGrouping.matches($0, candidate: target) })
                XCTAssertTrue(oracle === mutable)
                let result = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                    note: nil, sourceType: .link)
                XCTAssertEqual(store.userPlaces.first { $0.id == result.userPlaceID }?.placeID, mutable.id)
                XCTAssertEqual(store.places.count, 2)
            }
        }
    }

    func testSynchronousAnalyticsMutationAndNestedSavePerformTheirOwnFreshLookup() throws {
        let recorder = ResolvedPlaceSaveRecorder()
        let existing = place("nested-target", name: "Nested target", providerID: "old-provider")
        let store = store(places: [existing], recorder: recorder)
        let nestedCandidate = candidate("new-provider", name: "Nested target")
        recorder.onTrack = { [weak store, weak recorder] event in
            guard event.name == WanderAnalyticsEvents.placeSaved else { return }
            recorder?.onTrack = nil // One callback; the nested save emits its own events.
            MainActor.assumeIsolated {
                guard let store else { return }
                store.places.first { $0.localID == "nested-target" }?.sourceProviderPlaceID = "new-provider"
                _ = store.saveImportedCandidate(nestedCandidate, status: .wannaGo, visibility: .selfOnly,
                    note: "Nested", sourceType: .link)
            }
        }
        defer { recorder.onTrack = nil }
        try store.performBatchedImportMutations {
            _ = store.saveImportedCandidate(candidate("outer", name: "Outer"), status: .wannaGo,
                visibility: .selfOnly, note: "Outer", sourceType: .link)
            XCTAssertNil(recorder.onTrack)
            let nested = try XCTUnwrap(store.existingImportSave(matching: nestedCandidate))
            XCTAssertEqual(store.userPlaces.first { $0.id == nested.userPlaceID }?.placeID, existing.id)
            let repeatResult = store.saveImportedCandidate(nestedCandidate, status: .wannaGo, visibility: .selfOnly,
                note: "Do not replace", sourceType: .link)
            XCTAssertEqual(repeatResult.userPlaceID, nested.userPlaceID)
        }
        XCTAssertEqual(store.places.count, 2)
        XCTAssertEqual(store.userPlaces.count, 2)
        XCTAssertEqual(recorder.events.filter { $0.name == WanderAnalyticsEvents.placeSaved }.count, 2)
        XCTAssertEqual(recorder.saveCount, 1)
        XCTAssertEqual(recorder.snapshot?.userPlaces.count, 2)
    }

    func testTombstoneAndAccountChangesCannotReuseThePreviousOwnerSave() throws {
        let store = store(places: [])
        let target = candidate("target")
        try store.performBatchedImportMutations {
            let first = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                note: "First", sourceType: .link)
            let tombstone = try XCTUnwrap(store.userPlaces.first { $0.id == first.userPlaceID })
            tombstone.deletedAt = .now
            let replacement = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                note: "Replacement", sourceType: .link)
            XCTAssertNotEqual(replacement.userPlaceID, first.userPlaceID)
            XCTAssertNotNil(tombstone.deletedAt)
            let previousOwnerID = store.currentUser.id
            store.apply(authState: .signedIn(AuthSession(userID: "other-owner", displayName: "Other", handle: "other")))
            let newOwner = store.saveImportedCandidate(target, status: .wannaGo, visibility: .selfOnly,
                note: "Other owner", sourceType: .link)
            XCTAssertNotEqual(newOwner.userPlaceID, replacement.userPlaceID)
            XCTAssertEqual(store.userPlaces.first { $0.id == replacement.userPlaceID }?.userID, previousOwnerID)
            XCTAssertEqual(store.userPlaces.first { $0.id == newOwner.userPlaceID }?.userID, "other-owner")
            XCTAssertEqual(store.places.count, 1)
            XCTAssertEqual(store.userPlaces.count, 3)
        }
    }

    private func store(places: [LocalPlace], recorder: ResolvedPlaceSaveRecorder = ResolvedPlaceSaveRecorder()) -> WanderStore {
        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        return WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [owner], places: places,
            userPlaces: [], placeAttributes: [], follows: [], blocks: [], placeLists: [],
            placeListMembers: [], placeListItems: [], contactProvider: FakeContactProvider(seededMatches: [])),
            analytics: recorder, persistence: recorder.persistence)
    }

    private func place(_ id: String, name: String = "Target", provider: String = "mapkit", providerID: String?) -> LocalPlace {
        LocalPlace(localID: id, canonicalName: name, category: "coffee", address: "10 Fixture Street",
            locality: "Fixture City", region: "CA", country: "US", latitude: 34, longitude: -118,
            sourceProvider: provider, sourceProviderPlaceID: providerID)
    }

    private func candidate(_ providerID: String, id: String? = nil, name: String = "Target") -> PlaceCandidate {
        PlaceCandidate(id: id ?? "candidate-\(providerID)", name: name, category: "coffee", address: "10 Fixture Street",
            locality: "Fixture City", region: "CA", country: "US", latitude: 34, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: providerID, confidence: 1)
    }
}

private final class ResolvedPlaceSaveRecorder: AnalyticsClient {
    var onTrack: ((AnalyticsEvent) -> Void)?
    private(set) var events: [AnalyticsEvent] = []
    private(set) var snapshot: WanderStoreSnapshot?
    private(set) var saveCount = 0
    var persistence: WanderStorePersistence {
        WanderStorePersistence(load: { nil }, save: { [self] value in
            snapshot = value
            saveCount += 1
        })
    }
    func track(_ event: AnalyticsEvent) { events.append(event); onTrack?(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
