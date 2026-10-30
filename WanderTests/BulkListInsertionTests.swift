import Foundation
import XCTest
@testable import Wander

@MainActor
final class BulkListInsertionTests: XCTestCase {
    func testBatchMatchesSequentialInsertionsAcrossNewAliasBridgesAndTombstoneEdits() throws {
        let sequential = try runBridgeScenario(batched: false)
        let batched = try runBridgeScenario(batched: true)
        XCTAssertEqual(batched.outcomes, sequential.outcomes)
        XCTAssertEqual(batched.memberships, sequential.memberships)
        XCTAssertEqual(batched.count, sequential.count)
        XCTAssertEqual(batched.revisions, sequential.revisions)
        XCTAssertEqual(batched.snapshotCount, 1)
        XCTAssertEqual(sequential.snapshotCount, 1)
        XCTAssertEqual(batched.outcomes.first, .added)
        XCTAssertEqual(batched.outcomes.dropFirst().first, .alreadyInList,
            "The place created between insertions bridges the two prior groups")
    }

    func testBulkPreservesAliasFirstMatchAndOwnerSourceFallbacks() {
        for scenario in 0..<5 {
            let sequential = aliasFixture(scenario: scenario)
            let batched = aliasFixture(scenario: scenario)
            let expected = sequential.store.addCurrentUserPlace(userPlaceID: sequential.save.id,
                to: sequential.list, senderNotificationPolicy: .silent)
            let actual = batched.store.addCurrentUserPlaces(userPlaceIDs: [batched.save.id],
                to: batched.list, senderNotificationPolicy: .silent)
            XCTAssertEqual(actual, [expected], "scenario \(scenario)")
            XCTAssertEqual(memberships(batched.store), memberships(sequential.store), "scenario \(scenario)")
            XCTAssertEqual(batched.store.placeLists.first?.cachedItemCount,
                sequential.store.placeLists.first?.cachedItemCount, "scenario \(scenario)")
        }
    }

    func testBatchRevalidatesOwnerAfterAccountChange() {
        let fixture = library(count: 2)
        fixture.store.withBatchedCurrentUserPlaceListInsertions(to: fixture.list) { insert in
            XCTAssertEqual(insert(fixture.ids[0]).outcome, .added)
            fixture.store.apply(authState: .signedIn(AuthSession(userID: "different-owner", displayName: "Other", handle: "other")))
            XCTAssertEqual(insert(fixture.ids[1]).outcome, .permissionDenied)
        }
    }

    /// Both paths insert the same already-owned saves, preserving row order and
    /// one deferred snapshot. Only the operation-scoped list projection differs.
    func testPerformanceSequentialAndBulkListInsertionWith500OwnedSaves() {
        let count = 500
        var sequentialSamples: [Double] = []
        var bulkSamples: [Double] = []
        for _ in 0..<3 {
            let sequential = library(count: count)
            let bulk = library(count: count)
            var expected: [ListPlaceAddResult] = []
            var started = ProcessInfo.processInfo.systemUptime
            sequential.store.performBatchedLocalMutations {
                expected = sequential.ids.map {
                    sequential.store.addCurrentUserPlace(userPlaceID: $0, to: sequential.list,
                        senderNotificationPolicy: .silent)
                }
            }
            sequentialSamples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            started = ProcessInfo.processInfo.systemUptime
            let actual = bulk.store.addCurrentUserPlaces(userPlaceIDs: bulk.ids, to: bulk.list,
                senderNotificationPolicy: .silent)
            bulkSamples.append((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            XCTAssertEqual(actual, expected)
            XCTAssertTrue(actual.allSatisfy { $0.outcome == .added })
            XCTAssertEqual(memberships(bulk.store), memberships(sequential.store))
            XCTAssertEqual(bulk.store.placeLists.first?.cachedItemCount, count)
            XCTAssertEqual(sequential.store.placeLists.first?.cachedItemCount, count)
        }
        let attachment = XCTAttachment(string:
            "REC675 list_insertion rows=\(count) sequential_samples_ms=\(sequentialSamples) sequential_median_ms=\(sequentialSamples.sorted()[1]) bulk_samples_ms=\(bulkSamples) bulk_median_ms=\(bulkSamples.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct Membership: Equatable {
        let id: String
        let placeID: String
        let ownerID: String?
        let sourceID: String?
        let deleted: Bool
        let state: SyncState
        let policy: SenderNotificationPolicy
    }

    private func memberships(_ store: WanderStore) -> [Membership] {
        store.placeListItems.map {
            Membership(id: $0.id, placeID: $0.placeID, ownerID: $0.ownerUserPlaceID,
                sourceID: $0.sourceUserPlaceID, deleted: $0.deletedAt != nil,
                state: $0.syncState, policy: $0.senderNotificationPolicy)
        }
    }

    private func runBridgeScenario(batched: Bool) throws ->
        (outcomes: [ListPlaceAddResult.Outcome], memberships: [Membership], count: Int?, revisions: UInt64, snapshotCount: Int) {
        let a = LocalPlace(localID: "a", canonicalName: "Shared name", category: "park",
            address: "10 Main Street", latitude: 34, longitude: -118,
            sourceProvider: "fixture", sourceProviderPlaceID: "provider-a")
        let b = LocalPlace(localID: "b", canonicalName: "Shared name", category: "park",
            address: "20 Other Street", latitude: 35, longitude: -119,
            sourceProvider: "fixture", sourceProviderPlaceID: "provider-b")
        var snapshotCount = 0
        let fixture = makeStore(places: [a, b], membershipPlaceID: a.id,
            persistence: WanderStorePersistence(load: { nil }, save: { _ in snapshotCount += 1 }))
        snapshotCount = 0
        let before = fixture.store.presentationRevision
        var outcomes: [ListPlaceAddResult.Outcome] = []
        func operation(_ insert: (String) -> ListPlaceAddResult) {
            outcomes.append(insert(fixture.ids[1]).outcome)
            let bridge = fixture.store.saveImportedCandidate(PlaceCandidate(id: "bridge", name: "Shared name",
                category: "park", address: "10 Main Street", latitude: 35, longitude: -119,
                sourceProvider: "fixture", sourceProviderPlaceID: "provider-bridge", confidence: 1),
                status: .wannaGo, visibility: .selfOnly, note: nil, sourceType: .manual)
            outcomes.append(insert(bridge.userPlaceID).outcome)
            XCTAssertTrue(fixture.store.removePlace(placeID: b.id, from: fixture.list))
            outcomes.append(insert(fixture.ids[1]).outcome)
            // Direct mutation bypasses presentation revision; the operation's
            // fingerprint must still re-read grouping fields before the next row.
            b.sourceProviderPlaceID = "mutated-provider"
            b.canonicalName = "Changed direct model name"
            outcomes.append(insert(fixture.ids[1]).outcome)
            // A fresh unrelated place is created after the projection exists.
            let fresh = fixture.store.saveImportedCandidate(PlaceCandidate(id: "fresh", name: "Fresh place",
                category: "park", latitude: 36, longitude: -120, sourceProvider: "fixture",
                sourceProviderPlaceID: "provider-fresh", confidence: 1),
                status: .wannaGo, visibility: .selfOnly, note: nil, sourceType: .manual)
            outcomes.append(insert(fresh.userPlaceID).outcome)
        }
        if batched {
            fixture.store.withBatchedCurrentUserPlaceListInsertions(to: fixture.list,
                senderNotificationPolicy: .silent, operation)
        } else {
            fixture.store.performBatchedLocalMutations {
                operation { fixture.store.addCurrentUserPlace(userPlaceID: $0, to: fixture.list,
                    senderNotificationPolicy: .silent) }
            }
        }
        return (outcomes, memberships(fixture.store), fixture.store.placeLists.first?.cachedItemCount,
            fixture.store.presentationRevision - before, snapshotCount)
    }

    private func aliasFixture(scenario: Int) -> (store: WanderStore, list: LocalPlaceList, save: LocalUserPlace) {
        let first = LocalPlace(localID: "collision", serverID: "first-server", canonicalName: "First",
            category: "park", latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: "first")
        let second = LocalPlace(localID: "second", serverID: "collision", canonicalName: "Second",
            category: "park", latitude: 35, longitude: -119, sourceProvider: "fixture", sourceProviderPlaceID: "second")
        let peer = LocalPlace(localID: "peer", canonicalName: "Peer", category: "park",
            latitude: 36, longitude: -120, sourceProvider: "fixture", sourceProviderPlaceID: "second")
        let target = scenario == 1 ? peer.id : "collision"
        let member = scenario == 0 ? peer.id : (scenario == 1 ? "collision" : "unresolved")
        let fixture = makeStore(places: [first, second, peer], membershipPlaceID: member,
            targetReference: target, ownerReference: scenario == 2, sourceReference: scenario == 3,
            deleted: scenario == 4)
        return (fixture.store, fixture.list, fixture.store.userPlaces[0])
    }

    private func library(count: Int) -> (store: WanderStore, list: LocalPlaceList, ids: [String]) {
        let places = (0..<count).map {
            LocalPlace(localID: "owned-place-\($0)", canonicalName: "Owned place \($0)", category: "park",
                latitude: 34 + Double($0 / 50) * 0.01, longitude: -118 + Double($0 % 50) * 0.01,
                sourceProvider: "fixture", sourceProviderPlaceID: "owned-provider-\($0)")
        }
        return makeStore(places: places)
    }

    private func makeStore(places: [LocalPlace], membershipPlaceID: String? = nil,
                           targetReference: String? = nil, ownerReference: Bool = false,
                           sourceReference: Bool = false, deleted: Bool = false,
                           persistence: WanderStorePersistence? = nil)
        -> (store: WanderStore, list: LocalPlaceList, ids: [String]) {
        let user = LocalProfile(localID: "bulk-owner", handle: "bulk", displayName: "Fixture")
        let saves = places.enumerated().map { index, place in
            LocalUserPlace(localID: "owned-save-\(index)", userID: user.id,
                placeID: index == 0 ? (targetReference ?? place.id) : place.id,
                status: .wannaGo, visibility: .selfOnly, sourceType: "manual")
        }
        let list = LocalPlaceList(localID: "bulk-list", serverID: "bulk-list-server", ownerUserID: user.id,
            name: "Bulk list", description: "", visibility: .stealth, cachedItemCount: membershipPlaceID == nil || deleted ? 0 : 1)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let members = membershipPlaceID.map { placeID in
            [LocalPlaceListItem(localID: "initial-member", listID: list.localID, placeID: placeID,
                ownerUserPlaceID: ownerReference ? saves[0].id : nil,
                sourceUserPlaceID: sourceReference ? saves[0].id : nil, addedByUserID: user.id,
                syncState: .synced, createdAt: date, updatedAt: date, deletedAt: deleted ? date : nil)]
        } ?? []
        let fixtures = WanderFixtures(currentUser: user, profiles: [user], places: places, userPlaces: saves,
            placeAttributes: [], follows: [], blocks: [], placeLists: [list], placeListMembers: [],
            placeListItems: members, contactProvider: FakeContactProvider(seededMatches: []))
        return (WanderStore(fixtures: fixtures, persistence: persistence), list, saves.map(\.id))
    }
}
