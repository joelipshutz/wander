import XCTest
@testable import Wander

final class FeedModelsTests: XCTestCase {
    private let groupingNow = Date(timeIntervalSince1970: 1_800_000_000)

    func testGroupsNearbyActionsChronologicallyWithCheckInAsHeadline() throws {
        let events = [groupingEvent("list", .listItemAdded, 240),
                      groupingEvent("wanna", .placeWannaGo, 0),
                      groupingEvent("visit", .placeBeen, 120)]
        let group = try XCTUnwrap(FeedPresentation.groupedActivity(events, relativeTo: groupingNow).first)
        XCTAssertEqual(FeedPresentation.groupedActivity(events, relativeTo: groupingNow).count, 1)
        XCTAssertEqual(group.activities.map(\.id), ["wanna", "visit", "list"])
        XCTAssertEqual(group.primaryActivity.id, "visit")
        XCTAssertEqual(group.id, "wanna")
        XCTAssertEqual(group.occurredAt, events[1].occurredAt)
    }

    func testGroupingWindowIncludesThirtyMinutesButDoesNotSlide() {
        let events = [groupingEvent("wanna", .placeWannaGo, 0),
                      groupingEvent("list-1", .listItemAdded, 1_800),
                      groupingEvent("list-2", .listItemAdded, 1_801)]
        let groups = FeedPresentation.groupedActivity(events, relativeTo: groupingNow)
        XCTAssertEqual(groups.map { $0.activities.map(\.id) }, [["list-2"], ["wanna", "list-1"]])
    }

    func testDistinctVisitsStartNewGroupsAndLaterAdditionsFollowTheNewVisit() {
        let events = [groupingEvent("visit-1", .placeBeen, 0),
                      groupingEvent("list-1", .listItemAdded, 60),
                      groupingEvent("visit-2", .placeBeen, 120),
                      groupingEvent("list-2", .listItemAdded, 180)]
        XCTAssertEqual(
            FeedPresentation.groupedActivity(events, relativeTo: groupingNow).map { $0.activities.map(\.id) },
            [["visit-2", "list-2"], ["visit-1", "list-1"]]
        )
    }

    func testGroupingUsesPersonAndPlaceIDsAndDoesNotRequireAdjacentEvents() {
        let events = [groupingEvent("wanna", .placeWannaGo, 0),
                      groupingEvent("other-person", .placeWannaGo, 60, actorID: "another"),
                      groupingEvent("other-place", .listItemAdded, 90, placeID: "another"),
                      groupingEvent("list", .listItemAdded, 120)]
        let groups = FeedPresentation.groupedActivity(events, relativeTo: groupingNow)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.last?.activities.map(\.id), ["wanna", "list"])
    }

    func testLaterListAdditionDoesNotBumpMomentAboveAnInterveningPost() {
        let first = groupingEvent("wanna", .placeWannaGo, 0)
        let other = groupingEvent("other", .placeBeen, 60, actorID: "another")
        let before = FeedPresentation.groupedActivity([other, first], relativeTo: groupingNow)
        let after = FeedPresentation.groupedActivity(
            [groupingEvent("list", .listItemAdded, 120), other, first], relativeTo: groupingNow
        )
        XCTAssertEqual(before.map(\.id), after.map(\.id))
    }

    func testDuplicateIDsAreNotCountedTwiceAndTimestampTiesAreDeterministic() {
        let a = groupingEvent("a", .listItemAdded, 0)
        let b = groupingEvent("b", .placeWannaGo, 0)
        let groups = FeedPresentation.groupedActivity([b, a, b], relativeTo: groupingNow)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.activities.map(\.id), ["a", "b"])
        XCTAssertEqual(groups.first?.primaryActivity.id, "b")
    }

    func testLegacySavesListCreationAndMissingPlacesRemainSeparate() {
        let missing = FeedActivity(id: "missing", kind: .placeWannaGo, actor: actor, occurredAt: groupingNow)
        let events = [groupingEvent("legacy", .placeSaved, 0),
                      groupingEvent("list-created", .listCreated, 10),
                      groupingEvent("visit", .placeBeen, 20), missing]
        XCTAssertEqual(FeedPresentation.groupedActivity(events, relativeTo: groupingNow).count, 4)
    }

    func testGroupingNeverReconstructsMissingEventsAndDeduplicatesVisibleLists() throws {
        let list = LocalPlaceList(localID: "list", ownerUserID: actor.id, name: "Weekend", description: "")
        let first = groupingEvent("first", .listItemAdded, 0, list: list)
        let second = groupingEvent("second", .listItemAdded, 120, list: list)
        let combined = try XCTUnwrap(FeedPresentation.groupedActivity([second, first], relativeTo: groupingNow).first)
        XCTAssertEqual(combined.lists.map(\.id), [list.id])
        XCTAssertEqual(combined.activities.count, 2)
        let refreshed = try XCTUnwrap(FeedPresentation.groupedActivity([first], relativeTo: groupingNow).first)
        XCTAssertFalse(refreshed.isCombined)
        XCTAssertEqual(refreshed.activities.map(\.id), ["first"])
        XCTAssertTrue(FeedPresentation.groupedActivity([], relativeTo: groupingNow).isEmpty)
    }

    func testFutureClockSkewEventsStaySeparateAndSortLast() {
        let future1 = groupingEvent("future-1", .placeWannaGo, 4_000)
        let future2 = groupingEvent("future-2", .listItemAdded, 4_060)
        let valid = groupingEvent("valid", .placeBeen, 0)
        let groups = FeedPresentation.groupedActivity([future2, valid, future1], relativeTo: groupingNow)
        XCTAssertEqual(groups.map(\.id), ["valid", "future-1", "future-2"])
        XCTAssertTrue(groups.allSatisfy { !$0.isCombined })
    }

    private func groupingEvent(
        _ id: String, _ kind: FeedActivityKind, _ seconds: TimeInterval,
        actorID: String = "user_maya", placeID: String = "place", list: LocalPlaceList? = nil
    ) -> FeedActivity {
        let eventActor = ProfileShell(id: actorID, handle: "maya", displayName: "Maya Chen", avatarURL: nil, bio: nil, relationship: .follower)
        let place = LocalPlace(localID: placeID, serverID: placeID, canonicalName: "Same name", category: "coffee", latitude: 34, longitude: -118)
        let save = LocalUserPlace(localID: "save-\(actorID)-\(placeID)", userID: actorID, placeID: placeID, status: .been, visibility: .followers, sourceType: "manual")
        let owner = LocalProfile(localID: actorID, handle: "maya", displayName: "Maya Chen")
        return FeedActivity(id: id, kind: kind, actor: eventActor,
                            place: VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner),
                            list: list, occurredAt: groupingNow.addingTimeInterval(-3_600 + seconds))
    }

    func testRefreshFreshnessExpiresAndDoesNotTrustClockRollback() {
        let completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(FeedRefreshPolicy.isFresh(completedAt: nil, now: completedAt))
        XCTAssertTrue(FeedRefreshPolicy.isFresh(completedAt: completedAt, now: completedAt))
        XCTAssertTrue(FeedRefreshPolicy.isFresh(completedAt: completedAt, now: completedAt.addingTimeInterval(59)))
        XCTAssertFalse(FeedRefreshPolicy.isFresh(completedAt: completedAt, now: completedAt.addingTimeInterval(60)))
        XCTAssertFalse(FeedRefreshPolicy.isFresh(completedAt: completedAt, now: completedAt.addingTimeInterval(-1)))
    }

    func testNewestFirstUsesStableIdentifierTieBreakAndPushesClockSkewToEnd() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let activity = [
            makeActivity(id: "b", occurredAt: now.addingTimeInterval(-60)),
            makeActivity(id: "a", occurredAt: now.addingTimeInterval(-60)),
            makeActivity(id: "future", occurredAt: now.addingTimeInterval(6 * 60))
        ]

        XCTAssertEqual(
            FeedPresentation.newestFirst(activity, relativeTo: now).map(\.id),
            ["a", "b", "future"]
        )
    }

    func testNonRatingActivityNeverLeakingAnOpinionIntoTheFeed() {
        let activity = FeedActivity(
            id: "want",
            kind: .placeWannaGo,
            actor: actor,
            occurredAt: .now,
            rating: 4.5
        )

        XCTAssertNil(activity.rating)
    }

    func testBeenActivityRetainsTheExplicitRating() {
        let activity = FeedActivity(
            id: "been",
            kind: .placeBeen,
            actor: actor,
            occurredAt: .now,
            rating: 4.5
        )

        XCTAssertEqual(activity.rating, 4.5)
    }

    func testEveryFeedActivityMapsToTheActivityKindFamily() {
        XCTAssertEqual(FeedActivityKind.placeBeen.ticketKind, .checkIn)
        XCTAssertEqual(FeedActivityKind.placeWannaGo.ticketKind, .wanna)
        XCTAssertEqual(FeedActivityKind.listCreated.ticketKind, .list)
        XCTAssertEqual(FeedActivityKind.listItemAdded.ticketKind, .list)
        XCTAssertEqual(FeedActivityKind.placeSaved.ticketKind, .saved)
    }

    func testLegacySocialSaveUsesTheResultingPlaceStatusForItsTicket() {
        XCTAssertEqual(
            socialSaveActivity(status: .been).resolvedTicketKind,
            .checkIn
        )
        XCTAssertEqual(
            socialSaveActivity(status: .wannaGo).resolvedTicketKind,
            .wanna
        )
    }

    func testLegacySocialSaveWithoutPlaceDataUsesAnHonestFallback() {
        let activity = FeedActivity(
            id: "missing-place",
            kind: .placeSaved,
            actor: actor,
            occurredAt: .now
        )

        XCTAssertEqual(activity.resolvedTicketKind, .saved)
    }

    func testFeaturedPlacesKeepTheActorProfilePhotoWhenThePlaceProjectionLacksIt() throws {
        let actorWithPhoto = ProfileShell(
            id: actor.id,
            handle: actor.handle,
            displayName: actor.displayName,
            avatarURL: "https://example.com/maya.jpg",
            bio: actor.bio,
            relationship: actor.relationship
        )
        let activity = socialSaveActivity(status: .wannaGo, actor: actorWithPhoto)

        let featured = try XCTUnwrap(
            FeedPresentation.featuredPlaces(
                from: [activity],
                currentUserPlaceIDs: []
            ).first
        )

        XCTAssertNil(featured.visiblePlace.owner.avatarURL)
        XCTAssertEqual(featured.actor, actorWithPhoto)
        XCTAssertEqual(featured.actor.avatarURL, "https://example.com/maya.jpg")
    }

    private var actor: ProfileShell {
        ProfileShell(
            id: "user_maya",
            handle: "maya",
            displayName: "Maya Chen",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
    }

    private func makeActivity(id: String, occurredAt: Date) -> FeedActivity {
        FeedActivity(
            id: id,
            kind: .placeSaved,
            actor: actor,
            occurredAt: occurredAt
        )
    }

    private func socialSaveActivity(status: PlaceStatus) -> FeedActivity {
        socialSaveActivity(status: status, actor: actor)
    }

    private func socialSaveActivity(status: PlaceStatus, actor: ProfileShell) -> FeedActivity {
        let place = LocalPlace(
            localID: "local_place",
            serverID: "place",
            canonicalName: "Fern Coffee",
            category: "coffee",
            latitude: 34,
            longitude: -118,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_user_place",
            serverID: "user_place",
            userID: actor.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            sourceType: AddSourceType.socialSave.rawValue,
            syncState: .synced
        )
        let owner = LocalProfile(
            localID: "local_owner",
            serverID: actor.id,
            handle: actor.handle,
            displayName: actor.displayName,
            syncState: .synced
        )

        return FeedActivity(
            id: "social-save-\(status.rawValue)",
            kind: .placeSaved,
            actor: actor,
            place: VisiblePlace(
                id: userPlace.id,
                place: place,
                userPlace: userPlace,
                owner: owner
            ),
            occurredAt: .now
        )
    }
}
