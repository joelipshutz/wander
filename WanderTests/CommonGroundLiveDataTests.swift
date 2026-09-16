#if DEBUG
import XCTest
@testable import Wander

@MainActor
final class CommonGroundLiveDataTests: XCTestCase {
    func testCanonicalAliasesPreserveSeparateWannaAndBeenRows() throws {
        let viewer = profile("viewer"), partner = profile("partner")
        let been = row("viewer-been", owner: viewer, status: .been, rating: 4)
        been.userPlace.historicalWantedAt = Date(timeIntervalSince1970: 100)
        let wanna = row("viewer-wanna", owner: viewer, status: .wannaGo, name: "A differently named cafe")
        let theirs = row("partner-wanna", owner: partner, status: .wannaGo)
        let checkIn = visit("visit", parent: been, rating: 4)
        let snapshot = project(viewer, partner, rows: [been, wanna, theirs], visits: [checkIn])
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(snapshot.places.count, 1)
        XCTAssertTrue(place.youWanna)
        XCTAssertTrue(place.joeWanna)
        XCTAssertEqual(place.youVisits, 1)
        XCTAssertEqual(place.joeVisits, 0)
        XCTAssertEqual(place.youRating, 4)
        XCTAssertNil(place.joeRating)
        XCTAssertEqual(place.kind, .mutualWanna)
        XCTAssertEqual(place.youEvidence.wannaCount, 1)
        XCTAssertEqual(place.viewer.id, viewer.id)
        XCTAssertEqual(place.partner.id, partner.id)
        XCTAssertTrue([been.id, wanna.id].contains(try XCTUnwrap(place.sourcePlaceID)))
    }

    func testEligibleEventSeamKeepsRepeatedWannasOnBeenParent() throws {
        let viewer = profile("viewer"), partner = profile("partner")
        let been = row("viewer-been", owner: viewer, status: .been)
        let theirs = row("partner-wanna", owner: partner, status: .wannaGo)
        let checkIn = visit("visit", parent: been)
        let snapshot = CommonGroundLiveData.snapshot(
            viewerProfile: viewer, partnerProfile: partner,
            authorizedPlaces: [been, theirs],
            visitsForUserPlace: { $0 == been.userPlace.id ? [checkIn] : [] },
            shouldShowLegacyCheckInSummary: { _ in false },
            eligibleWannaEventIDs: { $0.id == been.userPlace.id ? ["wanna-1", "wanna-2", "wanna-1"] : [] }
        )
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(place.youVisits, 1)
        XCTAssertEqual(place.youEvidence.wannaRecordIDs, ["wanna-1", "wanna-2"])
        XCTAssertEqual(place.kind, .mutualWanna)
    }

    func testLiveStoreProjectionIncludesRepeatWannasOnBeenParent() async throws {
        let store = WanderStore(fixtures: .seed())
        let partnerPlace = try XCTUnwrap(store.placesInCommon(with: "user_maya").first)
        let ownPlace = try XCTUnwrap(store.currentUserVisiblePlaces.first {
            VisiblePlaceGrouping.matches($0, partnerPlace)
        })
        let candidate = PlaceCandidate(
            id: ownPlace.place.id,
            name: ownPlace.place.canonicalName,
            category: ownPlace.place.category,
            address: ownPlace.place.address,
            locality: ownPlace.place.locality,
            region: ownPlace.place.region,
            country: ownPlace.place.country,
            latitude: ownPlace.place.latitude,
            longitude: ownPlace.place.longitude,
            sourceProvider: ownPlace.place.sourceProvider,
            sourceProviderPlaceID: ownPlace.place.sourceProviderPlaceID,
            confidence: 1
        )
        _ = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "Still a Been place",
            sourceType: .manual,
            ratingScore: 5
        )
        let firstID = "11111111-1111-4111-8111-111111111111"
        let secondID = "22222222-2222-4222-8222-222222222222"
        _ = await store.saveNewWanna(
            candidate,
            operationID: firstID,
            visibility: .followers,
            note: "Go again",
            plannedDate: nil,
            attributes: [],
            backend: nil
        )
        _ = await store.saveNewWanna(
            candidate,
            operationID: secondID,
            visibility: .followers,
            note: "Another time",
            plannedDate: nil,
            attributes: [],
            backend: nil
        )

        let projected = try XCTUnwrap(
            CommonGroundLiveData.places(store: store, profileID: "user_maya")
                .first { $0.sourcePlaceID == ownPlace.id }
        )
        XCTAssertEqual(projected.youEvidence.wannaRecordIDs, [firstID, secondID])
        XCTAssertGreaterThan(projected.youVisits, 0)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first { VisiblePlaceGrouping.matches($0, ownPlace) }?.userPlace.status,
            .been,
            "Repeat Wanna events must not replace the checked-in place summary."
        )
    }

    func testVisitAliasesDeduplicateAndRatingsRemainPersonSpecific() throws {
        let viewer = profile("viewer"), partner = profile("partner")
        let mine = row("viewer-been", owner: viewer, status: .been, rating: 5)
        let theirs = row("partner-been", owner: partner, status: .been, rating: 5)
        mine.userPlace.recommendedScore = 5
        mine.userPlace.recommendedCount = 100
        let early = visit("local-visit", parent: mine, rating: 5)
        early.updatedAt = Date(timeIntervalSince1970: 100)
        let synced = visit("local-visit", parent: mine, rating: 3)
        synced.serverID = "server-visit"
        synced.updatedAt = Date(timeIntervalSince1970: 200)
        let partnerVisit = visit("partner-visit", parent: theirs, rating: nil)
        let snapshot = project(viewer, partner, rows: [mine, theirs], visits: [early, synced, synced, partnerVisit])
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(place.youEvidence.visitRecordIDs, ["server-visit"])
        XCTAssertEqual(place.youRating, 3)
        XCTAssertEqual(place.joeVisits, 1)
        XCTAssertNil(place.joeRating, "An unrated explicit history must not inherit a stale summary or community score.")
        XCTAssertFalse(place.bothLoved)
        XCTAssertFalse(place.bothRegulars)
    }

    func testAuthoritativeEmptyHistoryDoesNotRecreateCheckInsRatingsOrWannas() throws {
        let viewer = profile("viewer"), partner = profile("partner")
        let mine = row("viewer-been", owner: viewer, status: .been, rating: 5)
        let theirs = row("partner-been", owner: partner, status: .been, rating: 5)
        mine.userPlace.historicalWantedAt = Date(timeIntervalSince1970: 100)
        let snapshot = project(viewer, partner, rows: [mine, theirs], legacyFallback: false)
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(place.totalVisits, 0)
        XCTAssertNil(place.youRating)
        XCTAssertNil(place.joeRating)
        XCTAssertFalse(place.youWanna)
        XCTAssertEqual(place.kind, .history)
        XCTAssertTrue(snapshot.availableCities.isEmpty)

        let legacy = project(viewer, partner, rows: [mine, theirs], legacyFallback: true)
        XCTAssertEqual(legacy.places.first?.totalVisits, 2)
        XCTAssertEqual(legacy.availableCities, ["Los Angeles"])
    }

    func testCitiesIncludeEitherPersonsNonsharedVisitsButExcludeWannaOnlyCities() {
        let viewer = profile("viewer"), partner = profile("partner")
        let london = row("viewer-london", owner: viewer, canonicalID: "london", status: .been, city: "London")
        let la = row("partner-la", owner: partner, canonicalID: "la", status: .been)
        let kyotoMine = row("viewer-kyoto", owner: viewer, canonicalID: "kyoto", status: .wannaGo, city: "Kyoto")
        let kyotoTheirs = row("partner-kyoto", owner: partner, canonicalID: "kyoto", status: .wannaGo, city: "Kyoto")
        let snapshot = project(viewer, partner, rows: [london, la, kyotoMine, kyotoTheirs], legacyFallback: true)

        XCTAssertEqual(snapshot.availableCities, ["London", "Los Angeles"])
        XCTAssertEqual(snapshot.places.count, 1)
        XCTAssertEqual(snapshot.places.first?.city, "Kyoto")
    }

    func testDeletedRowsVisitsAndOtherOwnersCannotContributeEvidence() throws {
        let viewer = profile("viewer"), partner = profile("partner"), stranger = profile("stranger")
        let mine = row("viewer-been", owner: viewer, status: .been)
        let theirs = row("partner-wanna", owner: partner, status: .wannaGo)
        let deletedWanna = row("viewer-deleted-wanna", owner: viewer, status: .wannaGo)
        deletedWanna.userPlace.deletedAt = .now
        let otherWanna = row("stranger-wanna", owner: stranger, status: .wannaGo)
        let deletedVisit = visit("deleted-visit", parent: mine, rating: 5)
        deletedVisit.deletedAt = .now
        let snapshot = project(
            viewer, partner, rows: [mine, theirs, deletedWanna, otherWanna],
            visits: [deletedVisit], legacyFallback: false
        )
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertFalse(place.youWanna)
        XCTAssertEqual(place.youVisits, 0)
        XCTAssertNil(place.youRating)
        theirs.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        XCTAssertTrue(project(viewer, partner, rows: [mine, theirs]).places.isEmpty)
    }

    func testStoreProjectionUsesVisibilityAndDropsBlockedPartner() {
        let store = WanderStore(fixtures: .seed())
        XCTAssertFalse(CommonGroundLiveData.places(store: store, profileID: "user_maya").isEmpty)
        XCTAssertTrue(CommonGroundLiveData.places(store: store, profileID: store.currentUser.id).isEmpty)

        store.block(userID: "user_maya")

        XCTAssertTrue(CommonGroundLiveData.places(store: store, profileID: "user_maya").isEmpty)
        XCTAssertTrue(CommonGroundLiveData.places(store: store, profileID: "missing").isEmpty)
    }

    func testInvitationShareUsesCanonicalPlaceAndActualPeopleWithTheDraftIntact() throws {
        let viewer = profile("alex"), partner = profile("sam")
        viewer.displayName = "Alex Morgan"
        partner.displayName = "Sam Chen"
        let mine = row("viewer-been", owner: viewer, status: .been)
        let theirs = row("partner-been", owner: partner, status: .been)
        let canonicalID = "B40C44A6-1D20-4AA5-B97E-A09D1A8E68D9"
        mine.place.serverID = canonicalID
        mine.userPlace.placeID = canonicalID
        let place = try XCTUnwrap(project(viewer, partner, rows: [mine, theirs], legacyFallback: true).places.first)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = CommonGroundInvitationDraft(place: place, note: "Meet by the window?", suggestedDate: date)
        let share = try XCTUnwrap(draft.shareContent)

        XCTAssertEqual(share.item, WanderDeepLinkRoute.sharedPlace(placeID: canonicalID).url)
        XCTAssertEqual(draft.suggestedDate, date)
        XCTAssertTrue(share.message.contains("Meet by the window?"))
        XCTAssertTrue(share.message.contains(try XCTUnwrap(draft.whenText)))
        XCTAssertTrue(share.message.contains("Alex"))
        XCTAssertTrue(share.message.contains("Sam"))
        XCTAssertFalse(share.message.contains("Ryan"))
        XCTAssertFalse(share.message.contains("Joe"))

        mine.place.serverID = nil
        let unsynced = try XCTUnwrap(project(viewer, partner, rows: [mine, theirs], legacyFallback: true).places.first)
        XCTAssertNil(CommonGroundInvitationDraft(place: unsynced).shareContent)
        XCTAssertNil(CommonGroundInvitationDraft.preview.shareContent)
    }

    private func project(
        _ viewer: LocalProfile,
        _ partner: LocalProfile,
        rows: [VisiblePlace],
        visits: [LocalPlaceVisit] = [],
        legacyFallback: Bool = false
    ) -> CommonGroundLiveData.Snapshot {
        CommonGroundLiveData.snapshot(
            viewerProfile: viewer, partnerProfile: partner,
            authorizedPlaces: rows,
            visitsForUserPlace: { id in visits.filter { $0.userPlaceID == id } },
            shouldShowLegacyCheckInSummary: { _ in legacyFallback }
        )
    }

    private func profile(_ id: String) -> LocalProfile {
        LocalProfile(localID: "local-\(id)", serverID: id, handle: id, displayName: id.capitalized)
    }

    private func row(
        _ id: String,
        owner: LocalProfile,
        canonicalID: String = "shared-cafe",
        status: PlaceStatus,
        rating: Double? = nil,
        name: String? = nil,
        city: String = "Los Angeles"
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "local-place-\(id)", serverID: "place-\(id)", canonicalName: name ?? "\(canonicalID) Cafe",
            category: "coffee", address: "\(canonicalID) street", locality: city,
            latitude: 34, longitude: -118,
            sourceProvider: "google", sourceProviderPlaceID: canonicalID
        )
        let userPlace = LocalUserPlace(
            localID: "local-save-\(id)", serverID: id, userID: owner.id, placeID: place.id,
            status: status, visibility: .followers, ratingScore: rating, sourceType: "test"
        )
        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }

    private func visit(_ id: String, parent: VisiblePlace, rating: Double? = nil) -> LocalPlaceVisit {
        LocalPlaceVisit(localID: id, userPlaceID: parent.userPlace.id, ratingScore: rating)
    }
}
#endif
