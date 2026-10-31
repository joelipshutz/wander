import Combine
import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportExistingPlacesProjectionTests: XCTestCase {
    func testColdScaleProjectionMatchesEnrichedOracleWithoutBuildingIt() {
        let store = WanderStore(fixtures: .performanceScale())
        #if DEBUG
        let before = store.visiblePlaceProjectionBuildCount
        #endif
        let actual = store.currentUserImportExistingPlaces
        #if DEBUG
        XCTAssertEqual(store.visiblePlaceProjectionBuildCount, before)
        #endif
        XCTAssertFalse(actual.isEmpty)
        XCTAssertEqual(actual, oracle(store))
    }

    func testFreshRawIdentityStatusTombstoneAndOwnerChangesMatchColdOracle() throws {
        let store = WanderStore(fixtures: .seed())
        let parent = try XCTUnwrap(store.userPlaces.first { $0.userID == store.currentUser.id })
        let place = try XCTUnwrap(store.places.first { $0.id == parent.placeID })
        let other = try XCTUnwrap(store.profiles.first { $0.id != store.currentUser.id })
        assertParity(store)
        for mutation in [
            { place.canonicalName = "Fresh fictional name"; place.latitude = 35; place.longitude = -117 },
            { place.sourceProvider = "fixture"; place.sourceProviderPlaceID = "fresh-provider" },
            { parent.serverID = "hydrated-save"; parent.statusRaw = PlaceStatus.wannaGo.rawValue },
            { parent.deletedAt = Date(timeIntervalSince1970: 1_800_000_000) },
            { parent.deletedAt = nil; parent.userID = other.id }
        ] {
            mutation()
            // The dedicated input projection is fresh even before an ordinary
            // revision invalidates the full UI projection's membership cache.
            let actual = store.currentUserImportExistingPlaces
            revise(store)
            XCTAssertEqual(actual, oracle(store))
        }
        store.apply(authState: .signedIn(AuthSession(userID: other.id,
            displayName: other.displayName, handle: other.handle)))
        assertParity(store)
        XCTAssertTrue(store.currentUserImportExistingPlaces.contains { $0.userPlaceID == parent.id })
    }

    func testLocalFirstRemoteOrderPermissionsAndEnrichmentMatchOracle() async throws {
        let fixtures = WanderFixtures.seed()
        let store = WanderStore(fixtures: fixtures)
        let local = try XCTUnwrap(fixtures.userPlaces.first { $0.userID == fixtures.currentUser.id })
        let other = try XCTUnwrap(fixtures.profiles.first { $0.id != fixtures.currentUser.id })
        func row(_ id: String, name: String, ownerID: String? = nil) -> VisiblePlace {
            let place = LocalPlace(localID: "remote-place-\(id)", canonicalName: name,
                category: "park", latitude: 33, longitude: -116,
                sourceProvider: "fixture", sourceProviderPlaceID: id)
            let parent = LocalUserPlace(localID: id, userID: ownerID ?? fixtures.currentUser.id,
                placeID: place.id, status: .been, visibility: .selfOnly, sourceType: "manual", syncState: .synced)
            return VisiblePlace(id: id, place: place, userPlace: parent, owner: fixtures.currentUser)
        }
        let collision = row(local.id, name: "Remote cannot replace first local ID")
        let remote = row("remote-only-save", name: "Remote only")
        let deleted = row("remote-deleted", name: "Deleted remote")
        deleted.userPlace.deletedAt = .now
        let unauthorized = row("remote-wrong-owner", name: "Hidden payload", ownerID: other.id)
        await store.refreshRemoteProfileVisiblePlaces(profileID: fixtures.currentUser.id,
            backend: WanderBackend(userPlaceRepository: ImportExistingPlacesRepository(
                rows: [collision, remote, deleted, unauthorized])))
        let actual = store.currentUserImportExistingPlaces
        XCTAssertEqual(actual, oracle(store))
        XCTAssertEqual(actual.last?.userPlaceID, remote.userPlace.id)
        XCTAssertNotEqual(actual.first { $0.userPlaceID == local.id }?.name, collision.place.canonicalName)
        XCTAssertFalse(actual.contains { $0.userPlaceID == deleted.id || $0.userPlaceID == unauthorized.id })
        // Enrichment changes observation attributes only, never duplicate inputs.
        for attribute in store.placeAttributes { attribute.valueJSON = "\"Changed detail\"" }
        for visit in store.placeVisits {
            visit.attributeAnswersAreComplete = true
            visit.attributeAnswersJSON = "[]"
        }
        remote.place.sourceProviderPlaceID = "updated-remote-provider"
        let updated = store.currentUserImportExistingPlaces
        revise(store)
        XCTAssertEqual(updated, oracle(store))
        XCTAssertEqual(updated.last?.sourceProviderPlaceID, "updated-remote-provider")
    }

    func testSharedReconciliationMatchesOriginalMatcherAndPublishesOnlyChanges() throws {
        let store = WanderStore(fixtures: .seed())
        let owner = store.currentUser.id
        let local = try XCTUnwrap(store.userPlaces.first { $0.userID == owner })
        let place = try XCTUnwrap(store.places.first { $0.id == local.placeID })
        let candidate = PlaceCandidate(id: "matching-candidate", name: place.canonicalName,
            category: place.category, latitude: place.latitude, longitude: place.longitude,
            sourceProvider: place.sourceProvider, sourceProviderPlaceID: place.sourceProviderPlaceID, confidence: 1)
        let missing = PlaceCandidate(id: "missing-candidate", name: "A different fictional place",
            category: "park", latitude: 0, longitude: 0, confidence: 1)
        let items = [candidate, missing].enumerated().map { offset, candidate in
            PlaceImportItem(id: "projection-item-\(offset)", batchID: "projection-batch", source: .googleMaps,
                seed: PlaceImportSeed(rawText: candidate.name, nameHint: candidate.name, areaHint: nil,
                    sourceURLString: nil, sourceLine: offset), state: .ready, candidates: [candidate],
                selectedCandidateID: candidate.id)
        }
        let snapshot = PlaceImportSnapshot(ownerUserID: owner,
            batches: [PlaceImportBatch(id: "projection-batch", source: .googleMaps, sourceName: nil, totalCount: items.count)], items: items)
        func imports() throws -> PlaceImportStore {
            let persistence = EphemeralPlaceImportPersistence()
            try persistence.save(snapshot)
            return PlaceImportStore(persistence: persistence, resolver: ImportExistingPlacesResolver())
        }
        let actual = try imports()
        let reference = try imports()
        var publications = 0
        let subscription = actual.$items.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        store.reconcilePlaceImportDuplicates(in: actual)
        reference.reconcileDuplicates(with: oracle(store))
        XCTAssertEqual(actual.items.map(\.state), reference.items.map(\.state))
        XCTAssertEqual(actual.items.map(\.duplicateUserPlaceID), reference.items.map(\.duplicateUserPlaceID))
        XCTAssertEqual(actual.items.map(\.selectedCandidateIDsRaw), reference.items.map(\.selectedCandidateIDsRaw))
        XCTAssertEqual(actual.items.map(\.state), [.duplicate, .ready])
        XCTAssertEqual(publications, 1)
        store.reconcilePlaceImportDuplicates(in: actual)
        XCTAssertEqual(publications, 1)
        local.deletedAt = .now
        store.reconcilePlaceImportDuplicates(in: actual)
        XCTAssertEqual(actual.items.map(\.state), [.ready, .ready])
        XCTAssertEqual(publications, 2)
    }

    private func assertParity(_ store: WanderStore, file: StaticString = #filePath, line: UInt = #line) {
        let actual = store.currentUserImportExistingPlaces
        XCTAssertEqual(actual, oracle(store), file: file, line: line)
    }

    private func oracle(_ store: WanderStore) -> [PlaceImportExistingPlace] {
        store.currentUserVisiblePlaces.map {
            PlaceImportExistingPlace(userPlaceID: $0.userPlace.id, name: $0.place.canonicalName,
                latitude: $0.place.latitude, longitude: $0.place.longitude,
                sourceProvider: $0.place.sourceProvider, sourceProviderPlaceID: $0.place.sourceProviderPlaceID)
        }
    }

    private func revise(_ store: WanderStore) {
        let batch = PlaceImportBatch(id: "projection-revision", source: .googleMaps, sourceName: nil, totalCount: 0)
        store.recordAutomaticImportCheckpoint(PlaceImportAutoSaveCheckpoint(
            ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: []))
    }
}

@MainActor
private final class ImportExistingPlacesRepository: UserPlaceRepository {
    let rows: [VisiblePlace]
    init(rows: [VisiblePlace]) { self.rows = rows }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { rows }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

@MainActor
private struct ImportExistingPlacesResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        XCTFail("Ready duplicate-projection fixtures must not invoke a resolver")
        return .needsHelp("Unexpected fixture resolution")
    }
}
