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
}
