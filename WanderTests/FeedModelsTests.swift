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

    func testFeaturedPlacesRollUpDistinctPeopleWithoutChangingNewestLead() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let maya = makeActor(id: "user_maya", name: "Maya Chen")
        let ryan = makeActor(id: "user_ryan", name: "Ryan Lee")
        let place = makeVisiblePlace()
        let activity = [
            FeedActivity(
                id: "maya-first",
                kind: .placeSaved,
                actor: maya,
                place: place,
                occurredAt: now.addingTimeInterval(-120)
            ),
            FeedActivity(
                id: "maya-repeat",
                kind: .placeBeen,
                actor: maya,
                place: place,
                occurredAt: now.addingTimeInterval(-60)
            ),
            FeedActivity(
                id: "ryan-newest",
                kind: .placeSaved,
                actor: ryan,
                place: place,
                occurredAt: now.addingTimeInterval(-30)
            )
        ]

        let featured = FeedPresentation.featuredPlaces(
            from: activity,
            currentUserPlaceIDs: [],
            relativeTo: now
        )

        XCTAssertEqual(featured.map(\.visiblePlace.place.id), [place.place.id])
        XCTAssertEqual(featured.first?.reason, "Saved by Ryan Lee and 1 other")
    }

    private var actor: ProfileShell {
        makeActor(id: "user_maya", name: "Maya Chen")
    }

    private func makeActor(id: String, name: String) -> ProfileShell {
        ProfileShell(
            id: id,
            handle: id.replacingOccurrences(of: "user_", with: ""),
            displayName: name,
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
    }

    private func makeVisiblePlace() -> VisiblePlace {
        let owner = LocalProfile(
            localID: "local_owner",
            serverID: "user_owner",
            handle: "owner",
            displayName: "Place Owner",
            syncState: .synced
        )
        let place = LocalPlace(
            localID: "local_featured_place",
            serverID: "place_featured",
            canonicalName: "Featured Coffee",
            category: "coffee",
            locality: "Santa Monica",
            latitude: 34.02,
            longitude: -118.49,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_featured_user_place",
            serverID: "user_place_featured",
            userID: owner.id,
            placeID: place.id,
            status: .been,
            visibility: .followers,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }

    private func makeActivity(id: String, occurredAt: Date) -> FeedActivity {
        FeedActivity(
            id: id,
            kind: .placeSaved,
            actor: actor,
            occurredAt: occurredAt
        )
    }
}
