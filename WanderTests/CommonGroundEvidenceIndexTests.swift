import XCTest
@testable import Wander

@MainActor
final class CommonGroundEvidenceIndexTests: XCTestCase {
    func testIndexedProjectionMatchesExistingStoreQueriesWithVisitsAndRepeatWanna() async throws {
        let store = WanderStore(fixtures: .seed())
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let candidate = PlaceSheetPlace(visiblePlace: own).saveCandidate
        _ = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                note: nil, sourceType: .manual, ratingScore: 4)
        _ = await store.saveNewWanna(candidate, visibility: .selfOnly, note: nil,
                                   plannedDate: nil, attributes: [], backend: nil)
        let index = CommonGroundEvidenceIndex(store: store)
        for partner in store.profiles where partner.id != store.currentUser.id {
            let old = CommonGroundLiveData.snapshot(viewerProfile: store.currentUser, partnerProfile: partner,
                authorizedPlaces: store.currentUserVisiblePlaces + store.visiblePlaces(for: partner.id),
                visitsForUserPlace: { store.visits(for: $0) },
                shouldShowLegacyCheckInSummary: { store.shouldShowLegacyCheckInSummary(for: $0) },
                eligibleWannaEventIDs: { store.wannaSaves(for: $0).map(\.id) })
            let indexed = CommonGroundLiveData.snapshot(store: store, profileID: partner.id, evidence: index)
            XCTAssertEqual(indexed.places, old.places)
            XCTAssertEqual(indexed.availableCities, old.availableCities)
        }
    }

    func testIndexPreservesParentAliasesAndFiltersWannaVisibilityOncePerOwner() {
        let parent = LocalUserPlace(localID: "local-parent", serverID: "parent", userID: "friend",
            placeID: "place", status: .been, visibility: .mutuals, sourceType: "test")
        let old = Date(timeIntervalSince1970: 1_000), recent = Date(timeIntervalSince1970: 2_000)
        let localVisit = LocalPlaceVisit(localID: "local-visit", userPlaceID: parent.localID, visitedAt: old)
        let serverVisit = LocalPlaceVisit(localID: "server-visit", userPlaceID: parent.id, visitedAt: recent)
        let removedVisit = LocalPlaceVisit(localID: "removed", userPlaceID: parent.id, deletedAt: .now)
        func wanna(_ id: String, parentID: String, visibility: PlaceVisibility, ownerID: String = "friend") -> PlaceWannaSave {
            PlaceWannaSave(id: id, ownerID: ownerID, userPlaceID: parentID, occurredAt: recent,
                note: nil, visibility: visibility, plannedDate: nil, attributeAnswersJSON: "[]")
        }
        var relationshipReads: [String: Int] = [:]
        let index = CommonGroundEvidenceIndex(userPlaces: [parent],
            visits: [localVisit, serverVisit, removedVisit],
            wannas: [wanna("allowed", parentID: parent.localID, visibility: .mutuals),
                     wanna("private", parentID: parent.id, visibility: .selfOnly),
                     wanna("wrong-owner", parentID: parent.id, visibility: .followers, ownerID: "other")],
            viewerID: "viewer", relationship: { owner in
                relationshipReads[owner, default: 0] += 1; return .mutual
            }, isBlocked: { _ in false })
        for reference in [parent.id, parent.localID] {
            XCTAssertEqual(index.visits(for: reference).map(\.id), [serverVisit.id, localVisit.id])
        }
        XCTAssertEqual(index.wannaIDs(for: parent), ["allowed"])
        XCTAssertEqual(relationshipReads, ["friend": 1, "other": 1])
        parent.deletedAt = .now
        XCTAssertTrue(index.wannaIDs(for: parent).isEmpty)
    }

    func testCachedPlanCandidateRechecksCurrentVisibilityAndRelationship() throws {
        let store = WanderStore(fixtures: .seed())
        let partnerID = "user_ryan"
        let cached = try XCTUnwrap(CommonGroundLiveData.places(store: store, profileID: partnerID)
            .first { !$0.isOneSidedRecommendation })
        let source = try XCTUnwrap((store.currentUserVisiblePlaces + store.visiblePlaces(for: partnerID))
            .first { $0.id == cached.sourcePlaceID })
        XCTAssertEqual(LivePlanPeoplePolicy.revalidatedCandidate(cached, source: source,
            store: store, sourceContext: .placeProfile), cached)
        XCTAssertTrue(LivePlanPeoplePolicy.canShare(cached, store: store))
        let foreign = store.visiblePlaces(for: partnerID).filter { VisiblePlaceGrouping.matches($0, source) }
        for row in foreign { row.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue }
        let ownOnly = try XCTUnwrap(LivePlanPeoplePolicy.revalidatedCandidate(cached, source: source,
            store: store, sourceContext: .placeProfile))
        XCTAssertTrue(ownOnly.isOneSidedRecommendation)
        XCTAssertEqual(ownOnly.joeEvidence.visitCount, 0)
        XCTAssertEqual(ownOnly.joeEvidence.wannaCount, 0)
        XCTAssertTrue(LivePlanPeoplePolicy.canShare(cached, store: store))
        for row in foreign { row.userPlace.visibilityRaw = PlaceVisibility.mutuals.rawValue }
        store.unfollow(userID: partnerID)
        XCTAssertNil(LivePlanPeoplePolicy.revalidatedCandidate(cached, source: source,
            store: store, sourceContext: .placeProfile))
        XCTAssertFalse(LivePlanPeoplePolicy.canShare(cached, store: store))
    }

    func testCachedPlanRemainsShareableAfterNoteAndRatingRefresh() throws {
        let store = WanderStore(fixtures: .seed())
        let partnerID = "user_ryan"
        let cached = try XCTUnwrap(CommonGroundLiveData.places(store: store, profileID: partnerID)
            .first { !$0.isOneSidedRecommendation && $0.youEvidence.visitCount > 0 })
        let source = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.id == cached.sourcePlaceID })
        let refreshedRating = cached.youRating == 1 ? 5.0 : 1.0
        source.userPlace.note = "Updated check-in note"
        source.userPlace.ratingScore = refreshedRating
        for visit in store.visits(for: source.userPlace.id) { visit.ratingScore = refreshedRating }

        let refreshed = try XCTUnwrap(LivePlanPeoplePolicy.revalidatedCandidate(cached, source: source,
            store: store, sourceContext: .placeProfile))
        XCTAssertNotEqual(refreshed.youRating, cached.youRating)
        XCTAssertTrue(LivePlanPeoplePolicy.canShare(cached, store: store))
    }

    func testCachedOwnOnlyPlanRejectsDeletedSource() throws {
        let store = WanderStore(fixtures: .seed())
        let partnerID = "user_ryan"
        let candidate = PlaceCandidate(id: "own-only-plan", name: "Own Only Plan Cafe", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "test", sourceProviderPlaceID: "own-only-plan", confidence: 1)
        let result = store.saveCandidate(candidate, status: .wannaGo, visibility: .selfOnly,
            note: nil, sourceType: .manual)
        let source = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })
        let cached = try XCTUnwrap(CommonGroundLiveData.snapshot(store: store, profileID: partnerID,
            evidence: CommonGroundEvidenceIndex(store: store), includeOneSidedPlaces: true).places
            .first { $0.sourcePlaceID == source.id })
        XCTAssertTrue(cached.isOneSidedRecommendation)
        XCTAssertTrue(LivePlanPeoplePolicy.canShare(cached, store: store))

        source.userPlace.deletedAt = .now
        XCTAssertNil(LivePlanPeoplePolicy.revalidatedCandidate(cached, source: source,
            store: store, sourceContext: .placeProfile))
        XCTAssertFalse(LivePlanPeoplePolicy.canShare(cached, store: store))
    }
}
