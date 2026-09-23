#if DEBUG
import XCTest
import UIKit
@testable import Wander

@MainActor
final class CommonGroundLiveDataTests: XCTestCase {
    func testEmptyViewerGetsPartnersLovedPlacesWithOneSidedInvitationCopy() throws {
        let viewer = profile("viewer"), partner = profile("brian")
        let favorite = row("brian-favorite", owner: partner, status: .been, name: "Canal Coffee")
        let snapshot = project(viewer, partner, rows: [favorite],
                               visits: [visit("check-in", parent: favorite, rating: 4.5)])
        let place = try XCTUnwrap(snapshot.places.first)

        XCTAssertEqual(snapshot.places.count, 1, "Do not invent extra picks to fill the limit.")
        XCTAssertTrue(place.isOneSidedRecommendation)
        XCTAssertEqual(place.linkage, .partnerLoves)
        XCTAssertEqual(place.narrativeTitle, "Brian loves Canal Coffee")
        XCTAssertEqual(place.narrativeDetail, "Brian rated it 4.5/5")
        XCTAssertEqual(place.reason, "You two should go together.")
        XCTAssertEqual(place.sourcePlaceID, favorite.id)
        XCTAssertEqual(place.youVisits, 0)
        XCTAssertFalse(place.youWanna)
        XCTAssertNil(place.youRating)
        let draft = CommonGroundInvitationDraft(place: place)
        XCTAssertEqual(draft.message, "You love Canal Coffee\nTake me next time?")
        XCTAssertEqual(draft.reasonTitle, "Brian loves this place")
        XCTAssertEqual(draft.recipientReasonTitle, "You love this place, show Viewer")
    }

    func testEmptyPartnerGetsViewersFavoritesIncludingOwnPrivatePlace() throws {
        let viewer = profile("viewer"), partner = profile("brian")
        let favorite = row("mine", owner: viewer, status: .been, rating: 5, name: "Canal Coffee")
        favorite.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        let place = try XCTUnwrap(project(viewer, partner, rows: [favorite], legacyFallback: true).places.first)

        XCTAssertTrue(place.isOneSidedRecommendation)
        XCTAssertEqual(place.linkage, .viewerLoves)
        XCTAssertEqual(place.sourcePlaceID, favorite.id)
        XCTAssertEqual(place.joeVisits, 0)
        XCTAssertFalse(place.joeWanna)
        XCTAssertEqual(CommonGroundInvitationDraft(place: place).message, "I love Canal Coffee\nLet me show you why")
        XCTAssertEqual(CommonGroundInvitationDraft(place: place).recipientReasonTitle, "Viewer loves this place")
    }

    func testDisjointSavesChooseThreeDistinctFavoritesByRatingVisitsAndName() {
        let viewer = profile("viewer"), partner = profile("partner")
        let frequent = row("frequent", owner: partner, canonicalID: "frequent", status: .been, name: "Zulu")
        let alpha = row("alpha", owner: viewer, canonicalID: "alpha", status: .been, name: "Alpha")
        let bravo = row("bravo", owner: partner, canonicalID: "bravo", status: .been, name: "Bravo")
        let charlie = row("charlie", owner: viewer, canonicalID: "charlie", status: .been, name: "Charlie")
        let lower = row("lower", owner: partner, canonicalID: "lower", status: .been, name: "Lower")
        let visits = [visit("f1", parent: frequent, rating: 5), visit("f2", parent: frequent, rating: 5),
                      visit("a1", parent: alpha, rating: 5), visit("b1", parent: bravo, rating: 5),
                      visit("c1", parent: charlie, rating: 5), visit("l1", parent: lower, rating: 4.5)]
        let rows = [lower, charlie, bravo, alpha, frequent, frequent]
        let result = project(viewer, partner, rows: rows, visits: visits).places

        XCTAssertEqual(result.map(\.name), ["Zulu", "Alpha", "Bravo"])
        XCTAssertTrue(result.allSatisfy(\.isOneSidedRecommendation))
        XCTAssertEqual(Set(result.map(\.id)).count, 3)
        XCTAssertEqual(result.first?.joeVisits, 2, "Duplicate rows must not inflate visit evidence.")
        XCTAssertEqual(project(viewer, partner, rows: rows.reversed(), visits: visits.reversed()).places, result)
    }

    func testAnySharedPlaceSuppressesFallbackEvenWhenSharedPlaceIsWannaOnlyElsewhere() {
        let viewer = profile("viewer"), partner = profile("partner")
        let favorite = row("favorite", owner: partner, canonicalID: "favorite", status: .been, rating: 5)
        let mine = row("mine", owner: viewer, status: .wannaGo, city: "Kyoto")
        let theirs = row("theirs", owner: partner, status: .wannaGo, city: "Kyoto")
        let result = project(viewer, partner, rows: [favorite, mine, theirs], legacyFallback: true)

        XCTAssertEqual(result.places.count, 1)
        XCTAssertEqual(result.places.first?.linkage, .mutualWanna)
        XCTAssertEqual(result.places.first?.isOneSidedRecommendation, false)
        XCTAssertTrue(result.places.filter { $0.city == "Los Angeles" }.isEmpty,
                      "A city with no overlap must not activate introductions when the pair shares another place.")
        XCTAssertTrue(project(viewer, partner, rows: [favorite], legacyFallback: true).places.first?.isOneSidedRecommendation == true)
    }

    func testTwoQualifyingPlacesReturnTwoSuggestionsWithoutUnratedFiller() {
        let viewer = profile("viewer"), partner = profile("partner")
        let first = row("first", owner: partner, canonicalID: "first", status: .been, rating: 5)
        let second = row("second", owner: partner, canonicalID: "second", status: .been, rating: 4.5)
        let unrated = row("unrated", owner: viewer, canonicalID: "unrated", status: .been)
        let result = project(viewer, partner, rows: [first, second, unrated], legacyFallback: true)
        XCTAssertEqual(result.places.map(\.sourcePlaceID), [first.id, second.id])
        XCTAssertTrue(result.places.allSatisfy(\.isOneSidedRecommendation))
    }

    func testFallbackRequiresVisiblePositiveCheckInEvidence() {
        let viewer = profile("viewer"), partner = profile("partner")
        let ratings: [Double?] = [nil, 4.49, -1, 5.1, .nan, .infinity]
        for rating in ratings {
            let saved = row("saved", owner: partner, status: .been, rating: 5)
            let checkIn = visit("visit", parent: saved)
            // The initializer rounds/clamps input. Exercise raw persisted values
            // at the projection boundary instead of normalized UI save values.
            checkIn.ratingScore = rating
            let result = project(viewer, partner, rows: [saved], visits: [checkIn])
            XCTAssertTrue(result.places.isEmpty, "Explicit history must not inherit the summary's 5-star rating.")
        }
        let stale = row("stale", owner: partner, status: .been, rating: 5)
        XCTAssertTrue(project(viewer, partner, rows: [stale]).places.isEmpty)
        let deletedVisit = visit("deleted", parent: stale, rating: 5)
        deletedVisit.deletedAt = .now
        XCTAssertTrue(project(viewer, partner, rows: [stale], visits: [deletedVisit], legacyFallback: true).places.isEmpty)
        let wanna = row("wanna", owner: partner, status: .wannaGo, rating: 5)
        XCTAssertTrue(project(viewer, partner, rows: [wanna], legacyFallback: true).places.isEmpty)
        XCTAssertTrue(project(viewer, partner, rows: []).places.isEmpty)
    }

    func testFallbackExcludesPrivateDeletedAndUnrelatedOwners() {
        let viewer = profile("viewer"), partner = profile("partner"), stranger = profile("stranger")
        let hidden = row("hidden", owner: partner, canonicalID: "hidden", status: .been, rating: 5)
        hidden.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        let deleted = row("deleted", owner: partner, canonicalID: "deleted", status: .been, rating: 5)
        deleted.userPlace.deletedAt = .now
        let unrelated = row("unrelated", owner: stranger, canonicalID: "unrelated", status: .been, rating: 5)
        let favorite = row("favorite", owner: partner, canonicalID: "favorite", status: .been, rating: 5)
        let result = project(viewer, partner, rows: [hidden, deleted, unrelated, favorite], legacyFallback: true)

        XCTAssertEqual(result.places.map(\.sourcePlaceID), [favorite.id])
        partner.deletedAt = .now
        XCTAssertTrue(project(viewer, partner, rows: [favorite], legacyFallback: true).places.isEmpty)
    }

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
        let token = String(repeating: "a", count: 48)
        let share = try XCTUnwrap(draft.shareContent(invitationToken: token))

        XCTAssertEqual(share.item.absoluteString, "https://astirmovement.com/plans/\(token)")
        XCTAssertTrue(draft.canCreateInvitation)
        XCTAssertEqual(draft.suggestedDate, date)
        XCTAssertTrue(share.message.contains("Meet by the window?"))
        XCTAssertEqual(share.message, "Meet by the window?\n\n\(try XCTUnwrap(draft.whenText))")
        XCTAssertFalse(share.message.contains("check-ins"))
        XCTAssertFalse(share.message.contains("Ryan"))
        XCTAssertFalse(share.message.contains("Joe"))

        mine.place.serverID = nil
        let unsynced = try XCTUnwrap(project(viewer, partner, rows: [mine, theirs], legacyFallback: true).places.first)
        XCTAssertFalse(CommonGroundInvitationDraft(place: unsynced).canCreateInvitation)
        XCTAssertFalse(CommonGroundInvitationDraft.preview.canCreateInvitation)
    }

    func testSingleUnratedCheckInAndPartnerWannaNeverBecomeBothBeen() throws {
        let viewer = profile("ryan"), partner = profile("rachel")
        let been = row("viewer-been", owner: viewer, status: .been, name: "Charleston Park")
        let wanna = row("partner-wanna", owner: partner, status: .wannaGo, name: "Charleston Park")
        let result = try XCTUnwrap(project(viewer, partner, rows: [been, wanna],
                                          visits: [visit("visit", parent: been)]).places.first)
        XCTAssertEqual(result.linkage, .viewerBeenPartnerWanna)
        XCTAssertEqual(result.narrativeTitle, "You’ve been to Charleston Park\nRachel wants to go")
        XCTAssertEqual(CommonGroundInvitationDraft(place: result).reasonTitle, "You’ve been and Rachel wants to go")
        XCTAssertEqual(result.joeVisits, 0)
        XCTAssertTrue(result.joeWanna)
    }

    func testPlanCreationPublishesOnlyAuthoredContentAndReturnsAnInvitationLink() async throws {
        let transport = PlanTransport()
        let repository = SupabasePlacePlanInvitationRepository(rpc: transport, storage: transport)
        let draft = try syncedDraft()
        let share = try await repository.create(draft: draft, previewPNG: Data([137,80,78,71]))
        XCTAssertEqual(transport.uploadedBuckets, ["place-plan-previews"])
        XCTAssertTrue(transport.uploadedPaths.first?.hasPrefix("ryan/") == true)
        XCTAssertEqual(transport.procedure, "create_place_plan_invitation")
        XCTAssertEqual(transport.params["input_recipient_id"] as? String, "rachel")
        XCTAssertEqual(transport.params["input_message"] as? String, draft.message)
        XCTAssertEqual(transport.params["input_title"] as? String, draft.linkTitle)
        XCTAssertEqual(transport.params["input_connection"] as? String, "Ryan’s been and you wanna go")
        XCTAssertNil(transport.params["visits"])
        XCTAssertNil(transport.params["note"])
        XCTAssertEqual(share.item.path, "/plans/" + String(repeating: "b", count: 48))
        XCTAssertTrue(transport.deletedPaths.isEmpty)
    }

    func testFailedPlanCreationCleansUpArtworkAndDoesNotFallBackToAPlaceLink() async throws {
        let transport = PlanTransport()
        transport.failsCreation = true
        let repository = SupabasePlacePlanInvitationRepository(rpc: transport, storage: transport)
        do {
            _ = try await repository.create(draft: syncedDraft(), previewPNG: Data([137,80,78,71]))
            XCTFail("Expected plan creation failure")
        } catch {
            XCTAssertEqual(transport.deletedPaths, transport.uploadedPaths)
            XCTAssertEqual(transport.deletedPaths.count, 1)
        }
    }

    private func syncedDraft() throws -> CommonGroundInvitationDraft {
        let viewer = profile("ryan"), partner = profile("rachel")
        let been = row("viewer-been", owner: viewer, status: .been)
        been.place.serverID = "B40C44A6-1D20-4AA5-B97E-A09D1A8E68D9"
        let wanna = row("partner-wanna", owner: partner, status: .wannaGo)
        let place = try XCTUnwrap(project(viewer, partner, rows: [been, wanna], legacyFallback: true).places.first)
        return CommonGroundInvitationDraft(place: place)
    }

    func testSharedArtworkRendersTheNativePreviewAtRetinaResolutionWithinTheUploadLimit() throws {
        let png = try CommonGroundInvitationSharing.renderArtwork(draft: .preview, photo: nil, brand: .editorialLight)
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size.width, 780)
        XCTAssertGreaterThan(image.size.height, 400)
        XCTAssertLessThan(png.count, 2_097_152)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "rec486-rendered-invitation-link-artwork"
        attachment.lifetime = .keepAlways
        add(attachment)
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

@MainActor
private final class PlanTransport: RemoteProcedureCalling, RemoteStorageCalling {
    var uploadedBuckets: [String] = []
    var uploadedPaths: [String] = []
    var deletedPaths: [String] = []
    var procedure = ""
    var params: [String: Any] = [:]
    var failsCreation = false
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        procedure = name
        self.params = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any] ?? [:]
        if failsCreation { throw WanderRemoteError.notAuthenticated }
        return try decoder.decode(Value.self, from: Data("{\"token\":\"\(String(repeating: "b", count: 48))\"}".utf8))
    }
    func uploadObject(bucket: String, path: String, data: Data, contentType: String, upsert: Bool) async throws {
        uploadedBuckets.append(bucket)
        uploadedPaths.append(path)
        XCTAssertEqual(contentType, "image/png")
        XCTAssertFalse(upsert)
    }
    func deleteObject(bucket: String, path: String) async throws { deletedPaths.append(path) }
    func downloadObject(bucket: String, path: String) async throws -> Data { throw WanderRemoteError.notConfigured }
    func publicObjectURL(bucket: String, path: String, cacheBust: String?) throws -> URL { throw WanderRemoteError.notConfigured }
}
#endif
