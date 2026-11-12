import SwiftUI
import UIKit
import XCTest
@testable import Wander

final class PlaceRatingSummariesTests: XCTestCase {
    @MainActor
    func testRatingInputsIgnoreUnrelatedPersistenceAndMetadataButTrackScoresAndSyncAcknowledgments() {
        let (store, place, save, visit) = ratingFixture()
        let backend = WanderBackend()
        func key() -> PlaceRatingsRequestKey { ratingKey(store, place, backend) }
        let original = key()
        let revision = store.presentationRevision
        _ = store.createUnresolvedDraft(sourceType: .manual)
        save.note = "Changed note"
        save.updatedAt = .now
        store.places[0].category = "restaurant"
        visit.note = "Changed visit note"
        visit.updatedAt = .now
        XCTAssertNotEqual(store.presentationRevision, revision)
        XCTAssertEqual(key(), original)
        visit.ratingScore = 2
        let edited = key()
        XCTAssertNotEqual(edited, original)
        XCTAssertTrue(original.canRetainValues(for: edited))
        visit.syncStateRaw = SyncState.pendingUpdate.rawValue
        XCTAssertNotEqual(key(), edited)
        XCTAssertTrue(edited.canRetainValues(for: key()))
    }

    @MainActor
    func testRatingAccessInputsClearOnVisibilityDeletionGraphAccountAndBackgroundChanges() {
        let (store, place, save, visit) = ratingFixture()
        let backend = WanderBackend()
        let original = ratingKey(store, place, backend)
        save.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        XCTAssertFalse(original.canRetainValues(for: ratingKey(store, place, backend)))
        save.visibilityRaw = PlaceVisibility.followers.rawValue
        visit.deletedAt = .now
        XCTAssertFalse(original.canRetainValues(for: ratingKey(store, place, backend)))
        visit.deletedAt = nil
        store.follow(userID: "friend")
        XCTAssertFalse(original.canRetainValues(for: ratingKey(store, place, backend)))
        store.unfollow(userID: "friend")
        store.block(userID: "stranger")
        XCTAssertFalse(original.canRetainValues(for: ratingKey(store, place, backend)))
        let (other, otherPlace, _, _) = ratingFixture(viewerID: "second-account")
        XCTAssertFalse(original.canRetainValues(for: ratingKey(other, otherPlace, backend)))
        XCTAssertFalse(original.canRetainValues(for: ratingKey(store, place, backend, active: false)))
    }

    @MainActor
    func testRatingsStayVisibleDuringRefreshAndObsoleteResponsesCannotReplaceNewerResults() async throws {
        let (store, place, _, visit) = ratingFixture()
        let backend = WanderBackend()
        let loader = PlaceRatingsLoader()
        let original = ratingKey(store, place, backend)
        let first = try summaries(own: 4, astir: 2.8)
        await loader.refresh(key: original) { first }
        visit.ratingScore = 3
        let next = ratingKey(store, place, backend)
        let repository = DelayedRatingsRepository()
        let slow = Task { await loader.refresh(key: next) { try await repository.ratingSummaries(for: next.lookup) } }
        try await waitFor { repository.pending != nil }
        XCTAssertEqual(loader.state(for: next), .loaded(first))
        visit.ratingScore = 5
        let newest = ratingKey(store, place, backend)
        let latest = try summaries(own: 5, astir: 3.1)
        await loader.refresh(key: newest) { latest }
        repository.finish(try summaries(own: 3, astir: 2.9))
        await slow.value
        XCTAssertEqual(loader.state(for: newest), .loaded(latest))
        store.block(userID: "friend")
        let restricted = ratingKey(store, place, backend)
        XCTAssertEqual(loader.state(for: restricted), .loading, "Clear before the next task begins.")
        await loader.refresh(key: restricted) { throw URLError(.userAuthenticationRequired) }
        XCTAssertEqual(loader.state(for: restricted), .unavailable)
        await loader.refresh(key: restricted) { latest }
        XCTAssertEqual(loader.state(for: restricted), .loaded(latest))
    }

    @MainActor
    func testRatingsClearImmediatelyAfterBackendSessionSignOut() async throws {
        let (store, place, _, _) = ratingFixture()
        let session = PreviewAuthSessionProvider(state: .signedIn(AuthSession(userID: "viewer", displayName: nil, handle: nil)))
        let backend = WanderBackend(photoAuthSession: session)
        let key = ratingKey(store, place, backend)
        let loader = PlaceRatingsLoader()
        let value = try summaries(own: 4, astir: 2.8)
        await loader.refresh(key: key) { value }
        try await session.signOut()
        XCTAssertEqual(loader.state(for: ratingKey(store, place, backend)), .loading)
    }

    @MainActor
    func testAdditiveHistoryCanRefreshInPlaceButPrivacyChangesCannot() {
        let (store, place, save, _) = ratingFixture()
        let backend = WanderBackend()
        let original = ratingKey(store, place, backend)
        // A newly hydrated check-in changes the rating inputs, not access to
        // existing check-ins. Mutations of already loaded permissions clear.
        store.saveCandidate(place.saveCandidate, status: .been, visibility: .followers,
            note: nil, sourceType: .manual, ratingScore: 5)
        let added = ratingKey(store, place, backend)
        XCTAssertNotEqual(original, added)
        XCTAssertTrue(original.canRetainValues(for: added))
        store.currentUser.isPrivateProfile = true
        XCTAssertFalse(added.canRetainValues(for: ratingKey(store, place, backend)))
        store.currentUser.isPrivateProfile = false
        save.deletedAt = .now
        XCTAssertFalse(added.canRetainValues(for: ratingKey(store, place, backend)))
    }

    @MainActor
    func testClearingOrCancellingRatingsRejectsAnOutstandingResult() async throws {
        let (store, place, _, _) = ratingFixture()
        let key = ratingKey(store, place, WanderBackend())
        let loader = PlaceRatingsLoader()
        let repository = DelayedRatingsRepository()
        let pending = Task { await loader.refresh(key: key) { try await repository.ratingSummaries(for: key.lookup) } }
        try await waitFor { repository.pending != nil }
        loader.clear()
        repository.finish(try summaries(own: 4, astir: 2.8))
        await pending.value
        XCTAssertEqual(loader.state(for: key), .loading)
        let cancelled = Task { await loader.refresh(key: key) { try await repository.ratingSummaries(for: key.lookup) } }
        try await waitFor { repository.pending != nil }
        cancelled.cancel()
        repository.finish(try summaries(own: 4, astir: 2.8))
        await cancelled.value
        XCTAssertEqual(loader.state(for: key), .loading)
    }

    @MainActor
    func testMountedRatingsDoNotRefetchForUnrelatedPublicationsButRefreshAfterRatingEdits() async throws {
        let (store, place, _, visit) = ratingFixture()
        let repository = DelayedRatingsRepository()
        repository.immediate = try summaries(own: 4, astir: 2.8)
        let backend = WanderBackend(placeRepository: repository)
        let root = PlaceProfileRatingsRail(presentation: PlaceProfilePresentation(overallRating: nil,
            ownRating: nil, fitRating: nil, commonTags: [], isUnratedFeatured: false), place: place)
            .environmentObject(store).environmentObject(backend).environment(\.scenePhase, .active)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = UIScreen.main.bounds
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await waitFor { repository.calls == 1 }
        for _ in 0..<5 { _ = store.createUnresolvedDraft(sourceType: .manual) }
        visit.note = "Only a note changed"
        store.objectWillChange.send()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(repository.calls, 1)
        visit.ratingScore = 2
        store.objectWillChange.send()
        try await waitFor { repository.calls == 2 }
        XCTAssertEqual(repository.calls, 2)
    }

    @MainActor
    private func ratingFixture(viewerID: String = "viewer") -> (WanderStore, PlaceSheetPlace, LocalUserPlace, LocalPlaceVisit) {
        let user = LocalProfile(localID: viewerID, handle: "fixture", displayName: "Fixture")
        let id = "11111111-1111-4111-8111-111111111111"
        let local = LocalPlace(localID: id, serverID: id, canonicalName: "Cafe", category: "cafe", latitude: 0, longitude: 0)
        let save = LocalUserPlace(localID: "save", serverID: "22222222-2222-4222-8222-222222222222", userID: user.id,
            placeID: id, status: .been, visibility: .followers, ratingScore: 4, sourceType: "manual", syncState: .synced)
        let visit = LocalPlaceVisit(localID: "visit", userPlaceID: save.id, ratingScore: 4, syncState: .synced)
        let fixtures = WanderFixtures(currentUser: user, profiles: [user], places: [local], userPlaces: [save],
            placeAttributes: [], placeVisits: [visit], follows: [], blocks: [], placeLists: [], placeListMembers: [],
            placeListItems: [], contactProvider: FakeContactProvider(seededMatches: []))
        let place = PlaceSheetPlace(candidate: PlaceCandidate(id: id, name: "Cafe", category: "cafe",
            latitude: 0, longitude: 0, sourceProvider: "mapkit", confidence: 1))
        return (WanderStore(fixtures: fixtures), place, save, visit)
    }

    @MainActor
    private func ratingKey(_ store: WanderStore, _ place: PlaceSheetPlace, _ backend: WanderBackend,
                           active: Bool = true) -> PlaceRatingsRequestKey {
        PlaceRatingsRequestKey(store: store, place: place, backend: backend, active: active, retry: 0, ownRating: nil)
    }

    private func summaries(own: Double, astir: Double) throws -> PlaceRatingSummaries {
        try PlaceRatingSummaries(own: PlaceRatingAggregate(score: own, count: 1), friends: .empty,
            astir: PlaceRatingAggregate(score: astir, count: 10))
    }

    @MainActor
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the controlled rating request")
        throw URLError(.timedOut)
    }

    @MainActor
    func testSearchRatingLookupDoesNotRequireAnyVisibleSavedActivity() {
        let candidate = PlaceCandidate(id: "provider-search-result", name: "Coffee", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "mapkit", sourceProviderPlaceID: "coffee-123", confidence: 1)
        let lookup = PlaceRatingLookup(candidate: candidate, knownPlaces: [])
        XCTAssertTrue(lookup.canQuery)
        XCTAssertNil(lookup.placeID)
        XCTAssertEqual(lookup.sourceProvider, "mapkit")
        XCTAssertEqual(lookup.sourceProviderPlaceID, "coffee-123")
    }

    @MainActor
    func testRatingsUseSyncedIdentityAndDoNotTreatLocalUUIDAsServerIdentity() {
        let localID = "11111111-1111-4111-8111-111111111111"
        let serverID = "22222222-2222-4222-8222-222222222222"
        let local = LocalPlace(localID: localID, canonicalName: "Coffee", category: "coffee", latitude: 34, longitude: -118)
        let candidate = PlaceCandidate(id: localID, name: "Coffee", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "mapkit", confidence: 1)
        XCTAssertFalse(PlaceRatingLookup(candidate: candidate, knownPlaces: [local]).canQuery)
        local.serverID = serverID
        XCTAssertEqual(PlaceRatingLookup(candidate: candidate, knownPlaces: [local]).placeID, serverID)
    }

    func testRailAlwaysKeepsYourFriendsAndAstirSlotsWithoutFitOrFakeFive() throws {
        let empty = PlaceRatingsState.loaded(.init(own: .empty, friends: .empty, astir: .empty)).metrics
        XCTAssertEqual(empty.map(\.title), ["Your rating", "Friends rating", "Astir rating"])
        XCTAssertEqual(empty.map { $0.value + $0.suffix }, ["—/5", "—/5", "—/5"])
        let hiddenOnly = PlaceRatingsState.loaded(.init(
            own: .empty, friends: .empty, astir: try PlaceRatingAggregate(score: 4.5, count: 1)
        )).metrics
        XCTAssertEqual(hiddenOnly.map(\.value), ["—", "—", "4.5"])
        XCTAssertEqual(hiddenOnly[1].subtitle, "No visible ratings yet")
        XCTAssertEqual(hiddenOnly[2].subtitle, "1 rating")
    }

    func testFailedAndLoadingRatingsAreNotPresentedAsAnEmptySuccessfulResponse() {
        XCTAssertTrue(PlaceRatingsState.loading.metrics.allSatisfy { $0.subtitle == "Loading…" })
        XCTAssertTrue(PlaceRatingsState.unavailable.metrics.allSatisfy { $0.subtitle == "Unavailable" })
    }

    func testHiddenOnlyFriendsContributionCanRemainInAstir() throws {
        let result = try decode("""
        {"own":{"score":null,"count":0},"friends":{"score":null,"count":0},"astir":{"score":4.5,"count":1}}
        """)
        XCTAssertNil(result.friends.score)
        XCTAssertEqual(result.friends.count, 0)
        XCTAssertEqual(result.astir.score, 4.5)
        XCTAssertEqual(result.astir.count, 1)
    }

    func testFriendsAndAstirKeepIndependentScoresAndDenominators() throws {
        let result = try decode("""
        {"own":{"score":3.5,"count":2},"friends":{"score":4,"count":1},"astir":{"score":2.8,"count":10}}
        """)
        XCTAssertEqual(result.own.count, 2)
        XCTAssertEqual(result.friends.score, 4)
        XCTAssertEqual(result.friends.count, 1)
        XCTAssertEqual(result.astir.score, 2.8)
        XCTAssertEqual(result.astir.count, 10)
        XCTAssertEqual(try JSONDecoder().decode(PlaceRatingSummaries.self, from: JSONEncoder().encode(result)), result)
    }

    func testEmptyRatingsDoNotInventAScore() throws {
        let empty = try PlaceRatingAggregate(score: nil, count: 0)
        XCTAssertNil(empty.score)
        XCTAssertEqual(empty.count, 0)
    }

    func testMalformedPairsAndNonFiniteScoresAreRejected() {
        for (score, count) in [(nil, 1), (nil, -1), (5.0, 0), (0.0, 1), (5.1, 1), (.infinity, 1), (.nan, 1)] as [(Double?, Int)] {
            XCTAssertThrowsError(try PlaceRatingAggregate(score: score, count: count))
        }
        for value in ["{\"score\":5,\"count\":0}", "{\"score\":null,\"count\":1}", "{\"score\":6,\"count\":1}", "{\"score\":3}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlaceRatingAggregate.self, from: Data(value.utf8)))
        }
    }

    func testMissingGlobalSummaryIsNotReplacedByFriends() {
        XCTAssertThrowsError(try decode("""
        {"own":{"score":null,"count":0},"friends":{"score":4,"count":1}}
        """))
    }

    private func decode(_ json: String) throws -> PlaceRatingSummaries {
        try JSONDecoder().decode(PlaceRatingSummaries.self, from: Data(json.utf8))
    }
}

@MainActor
private final class DelayedRatingsRepository: PlaceRepository {
    var calls = 0
    var pending: CheckedContinuation<PlaceRatingSummaries, Error>?
    var immediate: PlaceRatingSummaries?
    func ratingSummaries(for lookup: PlaceRatingLookup) async throws -> PlaceRatingSummaries {
        calls += 1
        if let immediate { return immediate }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func finish(_ value: PlaceRatingSummaries) { pending?.resume(returning: value); pending = nil }
    func places(in viewport: MapViewport) async throws -> [VisiblePlace] { [] }
    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { [] }
}
