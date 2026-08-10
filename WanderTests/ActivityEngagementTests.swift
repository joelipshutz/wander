import XCTest
@testable import Wander

@MainActor
final class ActivityEngagementTests: XCTestCase {
    func testLikeMutationUpdatesTheVisibleCountAndCanUndo() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "local-activity"

        let didLike = await store.toggleActivityLike(activityID: activityID, backend: nil)
        XCTAssertTrue(didLike)
        XCTAssertEqual(
            store.activityEngagement(for: activityID),
            ActivityEngagementSummary(
                activityID: activityID,
                likeCount: 1,
                viewerHasLiked: true
            )
        )

        let didUnlike = await store.toggleActivityLike(activityID: activityID, backend: nil)
        XCTAssertTrue(didUnlike)
        XCTAssertEqual(store.activityEngagement(for: activityID), .empty(activityID: activityID))
    }

    func testFailedRemoteLikeRollsBackTheOptimisticCount() async {
        let activityID = "1efed494-8157-4ae9-9788-c605c3138214"
        let repository = ActivityEngagementRepositoryStub(setLikeError: ActivityEngagementTestError.expected)
        let store = WanderStore(fixtures: .empty())

        let succeeded = await store.toggleActivityLike(
            activityID: activityID,
            backend: WanderBackend(activityEngagementRepository: repository)
        )

        XCTAssertFalse(succeeded)
        XCTAssertEqual(store.activityEngagement(for: activityID), .empty(activityID: activityID))
        XCTAssertNotNil(store.activityEngagementError(for: activityID))
    }

    func testLocalCommentAddsOneCommentAndOneVisibleCount() async {
        let store = WanderStore(fixtures: .empty())
        let activityID = "local-comment-activity"

        let didAddComment = await store.addActivityComment(
            activityID: activityID,
            body: "  Meet me on the patio.  ",
            backend: nil
        )
        XCTAssertTrue(didAddComment)

        XCTAssertEqual(store.activityComments(for: activityID).map(\.body), ["Meet me on the patio."])
        XCTAssertEqual(store.activityEngagement(for: activityID).commentCount, 1)
        XCTAssertFalse(try XCTUnwrap(store.activityComments(for: activityID).first).isPending)
    }

    func testPlaceHistoryResolvesExplicitVisitBeforeParentEvent() async {
        let userPlaceID = "a0959fde-2e2b-40ae-9969-88d0983a5bc8"
        let visitID = "a940b2a4-605d-48d3-a5cd-b23d230b00ce"
        let parentActivity = PlaceActivityEngagementMatch(
            activityID: "a8778202-9fc3-4819-a66a-70bec42cd038",
            userPlaceID: userPlaceID,
            visitID: nil,
            kind: .placeBeen,
            occurredAt: Date(timeIntervalSince1970: 100),
            engagement: .empty(activityID: "a8778202-9fc3-4819-a66a-70bec42cd038")
        )
        let visitActivity = PlaceActivityEngagementMatch(
            activityID: "3223700f-cefc-4593-867e-d97f5830f428",
            userPlaceID: userPlaceID,
            visitID: visitID,
            kind: .placeBeen,
            occurredAt: Date(timeIntervalSince1970: 200),
            engagement: ActivityEngagementSummary(
                activityID: "3223700f-cefc-4593-867e-d97f5830f428",
                likeCount: 5,
                commentCount: 2
            )
        )
        let repository = ActivityEngagementRepositoryStub(
            placeMatches: [parentActivity, visitActivity]
        )
        let store = WanderStore(fixtures: .empty())

        await store.refreshPlaceActivityEngagement(
            userPlaceIDs: [userPlaceID],
            backend: WanderBackend(activityEngagementRepository: repository)
        )

        let resolved = store.placeActivityEngagementMatch(
            userPlaceID: userPlaceID,
            visitID: visitID,
            preferredKinds: [.placeBeen]
        )
        XCTAssertEqual(resolved, visitActivity)
        XCTAssertEqual(store.activityEngagement(for: visitActivity.activityID).likeCount, 5)
        XCTAssertEqual(store.activityEngagement(for: visitActivity.activityID).commentCount, 2)

        let resolvedWithoutMaterializedVisit = store.placeActivityEngagementMatch(
            userPlaceID: userPlaceID,
            visitID: nil,
            preferredKinds: [.placeBeen]
        )
        XCTAssertEqual(resolvedWithoutMaterializedVisit, visitActivity)
    }

    func testEngagementContextUsesCheckInAndWannaLanguage() {
        let actor = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Judy",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let checkIn = ActivityEngagementContext(
            activityID: "check-in",
            actor: actor,
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            status: .been,
            occurredAt: .now
        )
        let wanna = ActivityEngagementContext(
            activityID: "wanna",
            actor: actor,
            placeName: "Ada Street",
            placeServerID: nil,
            placeDetail: "Restaurant · Chicago, IL",
            status: .wannaGo,
            occurredAt: .now
        )

        XCTAssertEqual(checkIn.actionTitle, "checked in at")
        XCTAssertEqual(wanna.actionTitle, "added to Wanna")
        XCTAssertTrue(checkIn.shareMessage.contains("Judy's check-in at Ada Street"))
        XCTAssertTrue(wanna.shareMessage.contains("Judy's Wanna pick Ada Street"))

        let list = ActivityEngagementContext(
            activityID: "list",
            actor: actor,
            placeName: "Best of Chicago",
            placeServerID: nil,
            placeDetail: "12 places",
            ticketKind: .list,
            occurredAt: .now
        )
        XCTAssertEqual(list.actionTitle, "saved to")
        XCTAssertTrue(list.shareMessage.contains("list activity"))
    }

    func testActivityNavigationKeepsExactTicketIdentityUntilDismissal() {
        let coordinator = ActivityNavigationCoordinator()
        let activityID = "40000000-0000-0000-0000-000000000001"

        coordinator.openComments(activityID: activityID)
        let requestID = coordinator.commentsRoute?.id
        XCTAssertEqual(coordinator.commentsRoute?.activityID, activityID)
        XCTAssertNil(coordinator.commentsRoute?.context)

        coordinator.dismiss(requestID: try! XCTUnwrap(requestID))
        XCTAssertNil(coordinator.commentsRoute)
    }
}

private enum ActivityEngagementTestError: Error {
    case expected
}

@MainActor
private final class ActivityEngagementRepositoryStub: ActivityEngagementRepository {
    let placeMatches: [PlaceActivityEngagementMatch]
    let setLikeError: Error?

    init(
        placeMatches: [PlaceActivityEngagementMatch] = [],
        setLikeError: Error? = nil
    ) {
        self.placeMatches = placeMatches
        self.setLikeError = setLikeError
    }

    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] {
        activityIDs.map(ActivityEngagementSummary.empty(activityID:))
    }

    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] {
        placeMatches.filter { userPlaceIDs.contains($0.userPlaceID) }
    }

    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary {
        if let setLikeError { throw setLikeError }
        return ActivityEngagementSummary(
            activityID: activityID,
            likeCount: isLiked ? 1 : 0,
            viewerHasLiked: isLiked
        )
    }

    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        ActivityCommentsPage(
            comments: [],
            nextCursor: nil,
            engagement: .empty(activityID: activityID)
        )
    }

    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        let comment = ActivityComment(
            id: UUID().uuidString.lowercased(),
            activityID: activityID,
            author: ProfileShell(
                id: "user_current",
                handle: "current",
                displayName: "Current",
                avatarURL: nil,
                bio: nil,
                relationship: .owner
            ),
            body: body,
            createdAt: .now
        )
        return ActivityCommentPostResult(
            comment: comment,
            engagement: ActivityEngagementSummary(activityID: activityID, commentCount: 1)
        )
    }
}
