import Foundation
import Observation
import XCTest
@testable import Wander

@MainActor
final class ActivityBookmarkProjectionTests: XCTestCase {
    func testLightweightProjectionMatchesFullPerformanceFixtureWithoutBuildingVisitProjection() {
        let store = WanderStore(fixtures: .performanceScale())
        let targets = store.visiblePlaces()
        revise(store)
        #if DEBUG
        let before = store.visiblePlaceProjectionBuildCount
        #endif
        let actual = targets.map(store.activityBookmarkState(for:))
        #if DEBUG
        XCTAssertEqual(store.visiblePlaceProjectionBuildCount, before)
        #endif
        XCTAssertEqual(actual, oracle(for: targets, store: store))
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, 1)
    }

    func testAliasStatusTombstoneAndOwnerChangesMatchFullOracleAfterEachRevision() {
        let fixture = BookmarkFixture()
        let store = fixture.store
        assertParity(fixture.targets, store: store)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[0]), .checkedIn,
            "Been must win across provider aliases")
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[1]), .wanna,
            "The first duplicate save ID must win before alias aggregation")
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[2]), .notSaved)
        for change in [
            { fixture.aliasSave.deletedAt = Date(timeIntervalSince1970: 1_800_000_000) },
            { fixture.primarySave.statusRaw = PlaceStatus.been.rawValue },
            { fixture.primaryPlace.sourceProviderPlaceID = "changed-provider"; fixture.primaryPlace.canonicalName = "Changed place" },
            { fixture.primarySave.userID = fixture.other.id },
            { fixture.block.blockedUserID = fixture.owner.id }
        ] {
            change()
            revise(store)
            assertParity(fixture.targets, store: store)
        }
        store.apply(authState: .signedIn(AuthSession(userID: fixture.other.id,
            displayName: fixture.other.displayName, handle: fixture.other.handle)))
        assertParity(fixture.targets, store: store)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[2]), .checkedIn)
    }

    func testRemoteMergeAndPermissionRulesMatchFullProjection() async {
        let fixture = BookmarkFixture()
        let store = fixture.store
        let localWins = fixture.remote(id: "local-first", place: fixture.secondPlace, status: .been)
        let remoteOnlyPlace = fixture.place("remote-only", name: "Remote only", providerID: "remote-only")
        let remoteOnly = fixture.remote(id: "remote-only-save", place: remoteOnlyPlace, status: .been)
        let deleted = fixture.remote(id: "remote-deleted", place: fixture.foreignPlace, status: .been)
        deleted.userPlace.deletedAt = .now
        let stealthForeignPayload = fixture.remote(id: "malformed-owner", place: fixture.foreignPlace, status: .been)
        stealthForeignPayload.userPlace.userID = fixture.other.id
        let repository = BookmarkProjectionRepository(rows: [localWins, remoteOnly, deleted, stealthForeignPayload])
        await store.refreshRemoteProfileVisiblePlaces(profileID: fixture.owner.id,
            backend: WanderBackend(userPlaceRepository: repository))
        let targets = fixture.targets + [remoteOnly]
        assertParity(targets, store: store)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[1]), .wanna,
            "A remote Been with the same visible ID cannot replace the first local Wanna")
        XCTAssertEqual(store.activityBookmarkState(for: remoteOnly), .checkedIn)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.targets[2]), .notSaved,
            "A current-owner shell cannot authorize another owner's stealth payload")
        remoteOnly.userPlace.deletedAt = .now
        revise(store)
        assertParity(targets, store: store)
        XCTAssertEqual(store.activityBookmarkState(for: remoteOnly), .notSaved)
    }

    func testOwnerOnlyQueryRetainsFullAttributesAndDefaultListProjection() throws {
        let fixture = BookmarkFixture()
        let owned = fixture.store.currentUserVisiblePlaces
        XCTAssertTrue(owned.allSatisfy { $0.owner.id == fixture.owner.id })
        XCTAssertTrue(owned.allSatisfy { $0.owner === fixture.firstOwnerProfile })
        let primary = try XCTUnwrap(owned.first { $0.userPlace === fixture.primarySave })
        XCTAssertEqual(primary.attributes.map(\.questionKey), ["fixture-question"])
        // Filtered reads must not install an incomplete default list lookup.
        let all = fixture.store.visiblePlaces()
        XCTAssertTrue(all.contains { $0.userPlace.userID == fixture.other.id })
        XCTAssertEqual(fixture.store.currentUserVisiblePlaces.map(\.id), owned.map(\.id))
    }

    func testBookmarkObservationTracksOwnedStatusIdentityAndDeletionWithoutForeignContent() {
        for mutation in 0..<4 {
            let fixture = BookmarkFixture()
            let flag = BookmarkObservationFlag()
            _ = withObservationTracking {
                fixture.store.activityBookmarkState(for: fixture.targets[0])
            } onChange: { flag.invalidate() }
            XCTAssertFalse(flag.changed)
            switch mutation {
            case 0:
                fixture.foreignSave.note = "Unrelated content"
                fixture.foreignSave.statusRaw = PlaceStatus.wannaGo.rawValue
                fixture.foreignSave.visibilityRaw = PlaceVisibility.mutuals.rawValue
                fixture.foreignSave.localID = "unrelated-save-identity"
                fixture.foreignSave.placeID = "unrelated-place-reference"
                fixture.foreignSave.deletedAt = .now
                fixture.foreignPlace.canonicalName = "Unrelated place content"
                fixture.foreignPlace.latitude = 35
                fixture.foreignPlace.longitude = -117
                XCTAssertFalse(flag.changed,
                    "An owner bookmark no longer observes foreign save identity, deletion, location, visibility, status, or content")
                // Consume the remaining one-shot registration before fixture teardown.
                fixture.primarySave.statusRaw = PlaceStatus.been.rawValue
            case 1: fixture.primarySave.statusRaw = PlaceStatus.been.rawValue
            case 2: fixture.primaryPlace.sourceProviderPlaceID = "changed-owner-alias"
            default: fixture.primarySave.deletedAt = .now
            }
            XCTAssertTrue(flag.changed, "Relevant own inputs must invalidate the observing view")
        }
    }

    private func assertParity(_ targets: [VisiblePlace], store: WanderStore,
                              file: StaticString = #filePath, line: UInt = #line) {
        // Read the optimized path first so the full-projection oracle cannot prime it.
        let actual = targets.map(store.activityBookmarkState(for:))
        XCTAssertEqual(actual, oracle(for: targets, store: store), file: file, line: line)
    }

    private func oracle(for targets: [VisiblePlace], store: WanderStore) -> [ActivityBookmarkState] {
        var states: [String: ActivityBookmarkState] = [:]
        for visible in store.currentUserVisiblePlaces {
            let state: ActivityBookmarkState = visible.userPlace.status == .wannaGo ? .wanna : .checkedIn
            for alias in VisiblePlaceGrouping.groupingAliases(for: visible.place) where states[alias] != .checkedIn {
                states[alias] = state
            }
        }
        return targets.map { target in
            let matches = VisiblePlaceGrouping.groupingAliases(for: target.place).compactMap { states[$0] }
            if matches.contains(.checkedIn) { return .checkedIn }
            if matches.contains(.wanna) { return .wanna }
            return .notSaved
        }
    }

    private func revise(_ store: WanderStore) {
        let batch = PlaceImportBatch(id: "bookmark-revision", source: .googleMaps, sourceName: "Fixture",
            totalCount: 0, automaticSaveRequested: true)
        store.recordAutomaticImportCheckpoint(PlaceImportAutoSaveCheckpoint(
            ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: []))
    }
}

@MainActor
private final class BookmarkFixture {
    let owner: LocalProfile
    let firstOwnerProfile: LocalProfile
    let other: LocalProfile
    let primaryPlace: LocalPlace
    let secondPlace: LocalPlace
    let foreignPlace: LocalPlace
    let primarySave: LocalUserPlace
    let aliasSave: LocalUserPlace
    let foreignSave: LocalUserPlace
    let block: LocalBlock
    let store: WanderStore
    let targets: [VisiblePlace]

    init() {
        let owner = LocalProfile(localID: "bookmark-owner", handle: "owner", displayName: "Owner")
        self.owner = owner
        let first = LocalProfile(localID: owner.id, handle: "first-owner", displayName: "First owner")
        firstOwnerProfile = first
        let other = LocalProfile(localID: "bookmark-other", handle: "other", displayName: "Other")
        self.other = other
        func place(_ id: String, _ name: String, _ provider: String) -> LocalPlace {
            LocalPlace(localID: id, canonicalName: name, category: "park", latitude: 34, longitude: -118,
                sourceProvider: "fixture", sourceProviderPlaceID: provider)
        }
        let primary = place("primary", "Primary", "shared")
        primaryPlace = primary
        let alias = place("alias", "Alias", "shared")
        let second = place("second", "Second", "second")
        secondPlace = second
        let foreign = place("foreign", "Foreign", "foreign")
        foreignPlace = foreign
        func save(_ id: String, _ place: LocalPlace, _ user: LocalProfile, _ status: PlaceStatus) -> LocalUserPlace {
            LocalUserPlace(localID: id, userID: user.id, placeID: place.id, status: status,
                visibility: user.id == owner.id ? .selfOnly : .followers, sourceType: "manual")
        }
        let primarySave = save("primary-save", primary, owner, .wannaGo)
        self.primarySave = primarySave
        let aliasSave = save("alias-save", alias, owner, .been)
        self.aliasSave = aliasSave
        let firstSave = save("local-first", second, owner, .wannaGo)
        let duplicateSave = save("local-first", second, owner, .been)
        let foreignSave = save("foreign-save", foreign, other, .been)
        self.foreignSave = foreignSave
        let block = LocalBlock(localID: "unrelated-block", blockerUserID: owner.id, blockedUserID: "unrelated")
        self.block = block
        let attribute = LocalPlaceAttribute(localID: "fixture-attribute", userPlaceID: primarySave.id,
            questionKey: "fixture-question", valueType: "text", valueJSON: "\"Fixture\"")
        store = WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [first, owner, other],
            places: [primary, alias, second, foreign],
            userPlaces: [primarySave, aliasSave, firstSave, duplicateSave, foreignSave], placeAttributes: [attribute],
            follows: [LocalFollow(localID: "follow", followerUserID: owner.id, followedUserID: other.id, source: .profile)],
            blocks: [block], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])))
        targets = [VisiblePlace(id: primarySave.id, place: primary, userPlace: primarySave, owner: owner),
            VisiblePlace(id: firstSave.id, place: second, userPlace: firstSave, owner: owner),
            VisiblePlace(id: foreignSave.id, place: foreign, userPlace: foreignSave, owner: other)]
    }

    func place(_ id: String, name: String, providerID: String) -> LocalPlace {
        LocalPlace(localID: id, canonicalName: name, category: "park", latitude: 35, longitude: -117,
            sourceProvider: "fixture", sourceProviderPlaceID: providerID)
    }
    func remote(id: String, place: LocalPlace, status: PlaceStatus) -> VisiblePlace {
        let save = LocalUserPlace(localID: id, userID: owner.id, placeID: place.id, status: status,
            visibility: .selfOnly, sourceType: "manual", syncState: .synced)
        return VisiblePlace(id: id, place: place, userPlace: save, owner: owner)
    }
}

@MainActor
private final class BookmarkProjectionRepository: UserPlaceRepository {
    let rows: [VisiblePlace]
    init(rows: [VisiblePlace]) { self.rows = rows }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { rows }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

private final class BookmarkObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var changed: Bool { lock.withLock { value } }
    func invalidate() { lock.withLock { value = true } }
}
