import XCTest
@testable import Wander

@MainActor
final class LivePlanPeoplePolicyTests: XCTestCase {
    func testOwnWannaMatchesSharedProviderAliasAcrossDifferentLocalRows() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        XCTAssertNotEqual(mine.place.id, theirs.place.id)
        let candidate = try XCTUnwrap(match(mine, viewer: viewer, partner: partner, rows: [theirs, mine]))
        XCTAssertEqual(candidate.partner.id, partner.id)
        XCTAssertTrue(candidate.youWanna)
    }

    func testOneWayFollowingAndSelfCannotBeInvited() {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs], relationship: .follower))
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs], relationship: .nonFollower))
        XCTAssertNil(match(mine, viewer: viewer, partner: viewer, rows: [mine], relationship: .owner))
    }

    func testDifferentPlaceAndUnrelatedOwnersWannaCannotBorrowEligibleMapping() {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        let other = row("other", owner: viewer, providerID: "different-cafe")
        XCTAssertNil(match(other, viewer: viewer, partner: partner, rows: [mine, theirs]))
        let unrelated = row("unrelated", owner: profile("someone-else"))
        XCTAssertNil(match(unrelated, viewer: viewer, partner: partner, rows: [mine, theirs]))
    }

    func testFriendWannaUsesTargetedFriendMappingAfterHydration() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        XCTAssertNil(match(theirs, viewer: viewer, partner: partner, rows: [mine]))
        let hydrated = try XCTUnwrap(match(theirs, viewer: viewer, partner: partner, rows: [mine, theirs]))
        XCTAssertEqual(hydrated.partner.id, partner.id)
        XCTAssertTrue(hydrated.joeWanna)
    }

    func testFriendWannaAllowsExistingViewerBeenWithoutInventingViewerWanna() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        mine.userPlace.statusRaw = PlaceStatus.been.rawValue
        let candidate = try XCTUnwrap(match(theirs, viewer: viewer, partner: partner, rows: [mine, theirs]))
        XCTAssertFalse(candidate.youWanna)
        XCTAssertTrue(candidate.joeWanna)
    }

    func testFriendWannaWithoutViewerSaveNeedsExplicitSaveBeforePlan() {
        let viewer = profile("viewer"), partner = profile("friend")
        let theirs = row("theirs", owner: partner)
        XCTAssertNil(match(theirs, viewer: viewer, partner: partner, rows: [theirs]))
        XCTAssertFalse(LivePlanPeoplePolicy.hasViewerSave(for: theirs, authorizedPlaces: [theirs], viewerID: viewer.id))
        let mine = row("mine", owner: viewer)
        XCTAssertTrue(LivePlanPeoplePolicy.hasViewerSave(for: theirs, authorizedPlaces: [mine], viewerID: viewer.id))
        mine.userPlace.deletedAt = .now
        XCTAssertFalse(LivePlanPeoplePolicy.hasViewerSave(for: theirs, authorizedPlaces: [mine], viewerID: viewer.id))
    }

    func testFriendSourceCannotTargetAnotherFriendOrReuseRemovedWanna() {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        XCTAssertNil(match(theirs, viewer: viewer, partner: profile("different-friend"), rows: [mine, theirs]))
        theirs.userPlace.statusRaw = PlaceStatus.been.rawValue
        XCTAssertNil(match(theirs, viewer: viewer, partner: partner, rows: [mine, theirs]))
    }

    func testDeletedAndPrivatePartnerRowsCannotProduceAnInvitation() {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        theirs.userPlace.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs]))
        theirs.userPlace.visibilityRaw = PlaceVisibility.followers.rawValue
        mine.userPlace.deletedAt = .now
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs]))
    }

    #if DEBUG && targetEnvironment(simulator)
    func testDemoRequiresEveryExplicitFixtureArgumentAndRejectsLiveAuth() {
        let required = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderUnifiedLiveUITest"]
        XCTAssertTrue(LivePlanDemoPolicy.isEnabled(arguments: required, isDebugSimulator: true))
        for flag in required {
            XCTAssertFalse(LivePlanDemoPolicy.isEnabled(arguments: required.filter { $0 != flag }, isDebugSimulator: true))
        }
        XCTAssertFalse(LivePlanDemoPolicy.isEnabled(arguments: required, isDebugSimulator: false))
        for flag in ["-WanderUseLiveAuth", "-WanderForceSignedOut", "-WanderAuthUITest", "-WanderOnboardingUITestSignedOut"] {
            XCTAssertFalse(LivePlanDemoPolicy.isEnabled(arguments: required + [flag], isDebugSimulator: true))
        }
    }

    func testDemoWannaIsDetachedValueAndCannotWriteSourceOrInventNonmutualPlan() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let source = row("theirs", owner: partner)
        let originalOwner = source.userPlace.userID
        let originalStatus = source.userPlace.status
        let preview = try XCTUnwrap(LivePlanDemoPolicy.savedWannaPreview(source: source, viewer: viewer, relationship: .mutual))
        XCTAssertEqual(preview.kind, .mutualWanna)
        XCTAssertEqual(preview.name, source.place.canonicalName)
        XCTAssertEqual(source.userPlace.userID, originalOwner)
        XCTAssertEqual(source.userPlace.status, originalStatus)
        XCTAssertNil(preview.photoReference)
        XCTAssertNil(preview.sourcePlaceID)
        XCTAssertNil(preview.viewer.avatarURL)
        XCTAssertNil(preview.partner.avatarURL)
        XCTAssertFalse(CommonGroundInvitationDraft(place: preview).canCreateInvitation)
        XCTAssertNil(LivePlanDemoPolicy.savedWannaPreview(source: source, viewer: viewer, relationship: .follower))
        XCTAssertNil(LivePlanDemoPolicy.savedWannaPreview(source: source, viewer: partner, relationship: .owner))
    }

    func testExistingMappingDemoStripsRemoteMediaAndShareCapability() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        let mapping = try XCTUnwrap(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs]))
        XCTAssertNotNil(mapping.photoReference)
        let preview = LivePlanDemoPolicy.detachedPreview(mapping)
        XCTAssertEqual(preview.youEvidence, mapping.youEvidence)
        XCTAssertEqual(preview.joeEvidence, mapping.joeEvidence)
        XCTAssertNil(preview.photoReference)
        XCTAssertNil(preview.sourcePlaceID)
        XCTAssertNil(preview.viewer.avatarURL)
        XCTAssertNil(preview.partner.avatarURL)
        XCTAssertFalse(CommonGroundInvitationDraft(place: preview).canCreateInvitation)
    }
    #endif

    func testPlaceProfilePlanAcceptsSharedCheckInsWithoutInventingWanna() throws {
        let viewer = profile("viewer"), partner = profile("friend")
        let mine = row("mine", owner: viewer), theirs = row("theirs", owner: partner)
        mine.userPlace.statusRaw = PlaceStatus.been.rawValue
        theirs.userPlace.statusRaw = PlaceStatus.been.rawValue
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs]))
        let result = try XCTUnwrap(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs],
            sourceContext: .placeProfile))
        XCTAssertFalse(result.youWanna)
        XCTAssertFalse(result.joeWanna)
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine, theirs],
            relationship: .follower, sourceContext: .placeProfile))
        XCTAssertNil(match(mine, viewer: viewer, partner: partner, rows: [mine], sourceContext: .placeProfile))
    }

    func testSharedActivityRankingCountsAuthorizedEventsAndExcludesIntroductions() {
        func place(visits: Int, wanna: Bool, introduction: Bool = false) -> CommonGroundMockPlace {
            CommonGroundMockPlace(id: "p", name: "Cafe", category: "Coffee", area: "", city: "",
                systemImage: "cup.and.saucer", youRating: nil, joeRating: nil,
                youVisits: visits, joeVisits: 1, youWanna: wanna, joeWanna: false,
                reason: "", isOneSidedRecommendation: introduction)
        }
        XCTAssertGreaterThan(LivePlanPeoplePolicy.sharedActivityScore([place(visits: 4, wanna: true)]),
            LivePlanPeoplePolicy.sharedActivityScore([place(visits: 1, wanna: false)]))
        XCTAssertEqual(LivePlanPeoplePolicy.sharedActivityScore([place(visits: 100, wanna: true, introduction: true)]), 0)
    }

    private func match(_ requested: VisiblePlace, viewer: LocalProfile, partner: LocalProfile,
                       rows: [VisiblePlace], relationship: ViewerRelationship = .mutual,
                       sourceContext: LivePlanSourceContext = .wannaActivity) -> CommonGroundMockPlace? {
        let candidates = CommonGroundLiveData.snapshot(viewerProfile: viewer, partnerProfile: partner,
            authorizedPlaces: rows, visitsForUserPlace: { _ in [] }, shouldShowLegacyCheckInSummary: { _ in false }).places
        return LivePlanPeoplePolicy.matchingPlace(for: requested, candidates: candidates, authorizedPlaces: rows,
                                                viewerID: viewer.id, partnerID: partner.id, relationship: relationship, sourceContext: sourceContext)
    }

    private func profile(_ id: String) -> LocalProfile {
        LocalProfile(localID: "local-\(id)", serverID: id, handle: id, displayName: id.capitalized)
    }

    private func row(_ id: String, owner: LocalProfile, providerID: String = "shared-cafe") -> VisiblePlace {
        let place = LocalPlace(localID: "local-place-\(id)", serverID: "place-\(id)", canonicalName: providerID,
            category: "coffee", address: "\(providerID) street", locality: "Los Angeles", latitude: 34, longitude: -118,
            sourceProvider: "google", sourceProviderPlaceID: providerID)
        let userPlace = LocalUserPlace(localID: "local-save-\(id)", serverID: id, userID: owner.id, placeID: place.id,
                                      status: .wannaGo, visibility: .followers, sourceType: "test")
        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }
}
