import XCTest
@testable import Wander

final class FeedModelsTests: XCTestCase {
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

    func testEveryFeedActivityMapsToTheCompactTicketFamily() {
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
