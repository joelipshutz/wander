import Foundation
import XCTest
@testable import Wander

@MainActor
final class ListInsertionProjectionTests: XCTestCase {
    func testInsertionPreservesFirstAliasMatchForBothTargetAndMember() throws {
        for targetUsesCollision in [true, false] {
            let first = place("collision", serverID: "first-server", providerID: "first")
            let second = place("second-local", serverID: "collision", providerID: "second")
            let peer = place("peer-local", serverID: "peer-server", providerID: "second")
            let targetID = targetUsesCollision ? "collision" : peer.id
            let memberID = targetUsesCollision ? peer.id : "collision"
            let fixture = makeStore(places: [first, second, peer], targetPlaceID: targetID,
                memberPlaceID: memberID)
            let members = fixture.store.placeListItems

            XCTAssertFalse(originalDuplicateCheck(store: fixture.store, target: fixture.save, members: members))
            XCTAssertEqual(fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.id,
                to: fixture.list).outcome, .added)
            XCTAssertEqual(fixture.store.placeListItems.count, 2,
                "The original array-first resolver allows this raw membership")
            XCTAssertEqual(fixture.store.placeLists.first?.cachedItemCount, 1,
                "The transitive physical group still collapses both raw memberships")
        }
    }

    func testInsertionMatchesOriginalPhysicalAliasOwnerSourceAndUnresolvedChecks() throws {
        for scenario in ["physical-alias", "owner", "source", "unresolved-target"] {
            let target = place("target-local", serverID: "target-server", providerID: "same-physical-place")
            let peer = place("peer-local", serverID: "peer-server", providerID: "same-physical-place")
            let targetID = scenario == "unresolved-target" ? "unresolved" : target.localID
            let memberID = scenario == "physical-alias" ? peer.localID : "unresolved"
            let fixture = makeStore(places: [target, peer], targetPlaceID: targetID,
                memberPlaceID: memberID, ownerReference: scenario == "owner",
                sourceReference: scenario == "source")
            let members = fixture.store.placeListItems
            let revision = fixture.store.presentationRevision

            XCTAssertTrue(originalDuplicateCheck(store: fixture.store, target: fixture.save, members: members), scenario)
            XCTAssertEqual(fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.localID,
                to: fixture.list).outcome, .alreadyInList, scenario)
            XCTAssertEqual(fixture.store.placeListItems, members, scenario)
            XCTAssertEqual(fixture.store.presentationRevision, revision,
                "Duplicate detection must not publish or persist another membership")
        }
    }

    func testDeletedMembershipRestoresOnceWithUnchangedPublicationAndPersistence() throws {
        let target = place("target-local", serverID: "target-server", providerID: "target")
        var snapshots: [WanderStoreSnapshot] = []
        let fixture = makeStore(places: [target], targetPlaceID: target.id,
            memberPlaceID: target.localID, deleted: true,
            persistence: WanderStorePersistence(load: { nil }, save: { snapshots.append($0) }))
        snapshots.removeAll()
        let tombstone = try XCTUnwrap(fixture.store.placeListItems.first)
        let revision = fixture.store.presentationRevision

        XCTAssertFalse(originalDuplicateCheck(store: fixture.store, target: fixture.save, members: []))
        let result = fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.id,
            to: fixture.list, senderNotificationPolicy: .silent)
        XCTAssertEqual(result.outcome, .added)
        XCTAssertEqual(fixture.store.placeListItems.first, tombstone)
        XCTAssertEqual(fixture.store.placeListItems.count, 2)
        XCTAssertEqual(fixture.store.placeLists.first?.cachedItemCount, 1)
        XCTAssertEqual(fixture.store.placeListItems.last?.senderNotificationPolicy, .silent)
        XCTAssertEqual(fixture.store.presentationRevision, revision + 1)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.placeListItems?.count, 2)

        XCTAssertEqual(fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.id,
            to: fixture.list).outcome, .alreadyInList)
        XCTAssertEqual(fixture.store.placeListItems.count, 2)
        XCTAssertEqual(fixture.store.presentationRevision, revision + 1)
        XCTAssertEqual(snapshots.count, 1)
    }

    func testInsertionLookupReadsDirectlyMutatedPlaceAliasesOnEveryCall() {
        let target = place("target-local", serverID: "target-server", providerID: "same")
        let peer = place("peer-local", serverID: "peer-server", providerID: "same")
        let fixture = makeStore(places: [target, peer], targetPlaceID: target.id, memberPlaceID: peer.id)
        XCTAssertEqual(fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.id,
            to: fixture.list).outcome, .alreadyInList)

        peer.sourceProviderPlaceID = "different-after-direct-mutation"
        XCTAssertFalse(originalDuplicateCheck(store: fixture.store, target: fixture.save,
            members: fixture.store.placeListItems))
        XCTAssertEqual(fixture.store.addCurrentUserPlace(userPlaceID: fixture.save.id,
            to: fixture.list).outcome, .added)
    }

    /// The pre-optimization duplicate predicate, using explicitly known active
    /// projected memberships so these cases do not duplicate the collapse code.
    private func originalDuplicateCheck(store: WanderStore, target: LocalUserPlace,
                                        members: [LocalPlaceListItem]) -> Bool {
        func resolve(_ id: String) -> LocalPlace? {
            store.places.first { $0.id == id || $0.localID == id || $0.serverID == id }
        }
        if let resolvedTarget = resolve(target.placeID) {
            return members.contains { item in
                let physicalMatch = resolve(item.placeID).map {
                    VisiblePlaceGrouping.matches($0, resolvedTarget)
                } ?? [resolvedTarget.id, resolvedTarget.localID, resolvedTarget.serverID]
                    .compactMap { $0 }.contains(item.placeID)
                return physicalMatch || item.ownerUserPlaceID == target.id || item.sourceUserPlaceID == target.id
            }
        }
        return members.contains {
            $0.placeID == target.placeID || $0.ownerUserPlaceID == target.id || $0.sourceUserPlaceID == target.id
        }
    }

    private func place(_ localID: String, serverID: String, providerID: String) -> LocalPlace {
        LocalPlace(localID: localID, serverID: serverID, canonicalName: localID, category: "park",
            latitude: 34, longitude: -118, sourceProvider: "fixture",
            sourceProviderPlaceID: providerID, syncState: .synced)
    }

    private func makeStore(places: [LocalPlace], targetPlaceID: String, memberPlaceID: String,
                           ownerReference: Bool = false, sourceReference: Bool = false,
                           deleted: Bool = false, persistence: WanderStorePersistence? = nil)
        -> (store: WanderStore, list: LocalPlaceList, save: LocalUserPlace) {
        let user = LocalProfile(localID: "insertion-owner", handle: "insertion", displayName: "Fixture")
        let save = LocalUserPlace(localID: "save-local", serverID: "save-server", userID: user.id,
            placeID: targetPlaceID, status: .wannaGo, visibility: .selfOnly,
            sourceType: "manual", syncState: .synced)
        let list = LocalPlaceList(localID: "list-local", serverID: "list-server", ownerUserID: user.id,
            name: "Insertion fixture", description: "", visibility: .stealth, syncState: .synced,
            cachedItemCount: deleted ? 0 : 1)
        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let member = LocalPlaceListItem(localID: "member-local", listID: list.localID,
            placeID: memberPlaceID, ownerUserPlaceID: ownerReference ? save.id : nil,
            sourceUserPlaceID: sourceReference ? save.id : nil, addedByUserID: user.id,
            syncState: .synced, createdAt: oldDate, updatedAt: oldDate,
            deletedAt: deleted ? oldDate : nil)
        let fixtures = WanderFixtures(currentUser: user, profiles: [user], places: places,
            userPlaces: [save], placeAttributes: [], follows: [], blocks: [], placeLists: [list],
            placeListMembers: [], placeListItems: [member], contactProvider: FakeContactProvider(seededMatches: []))
        return (WanderStore(fixtures: fixtures, persistence: persistence), list, save)
    }
}
