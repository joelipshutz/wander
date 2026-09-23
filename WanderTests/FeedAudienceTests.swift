import XCTest
@testable import Wander

@MainActor
final class FeedAudienceTests: XCTestCase {
    func testAudienceUsesActorIdentityAndMutualFollows() {
        for relationship in [ViewerRelationship.owner, .mutual, .follower, .nonFollower] {
            XCTAssertTrue(FeedAudience.everyone.includes(actorID: "other", currentUserID: "me", relationship: relationship))
            XCTAssertTrue(FeedAudience.onlyMe.includes(actorID: "me", currentUserID: "me", relationship: relationship))
            XCTAssertFalse(FeedAudience.onlyMe.includes(actorID: "other", currentUserID: "me", relationship: relationship))
            XCTAssertFalse(FeedAudience.onlyFriends.includes(actorID: "me", currentUserID: "me", relationship: relationship))
            XCTAssertEqual(FeedAudience.onlyFriends.includes(actorID: "other", currentUserID: "me", relationship: relationship), relationship == .mutual)
        }
    }

    func testSelectionClearsPreviousPageAndRefreshKeepsSelection() async {
        let store = WanderStore(fixtures: .seed())
        let repository = AudienceRepository()
        let backend = WanderBackend(feedRepository: repository)
        XCTAssertEqual(store.feedAudience, .everyone)
        _ = await store.refreshFollowedFeed(backend: backend)
        store.selectFeedAudience(.onlyMe)
        XCTAssertNil(store.followedFeedPage)
        XCTAssertEqual(store.feedLoadState, .idle)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(repository.audiences, [.everyone, .onlyMe])
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertEqual(store.feedAudience, .onlyMe)
        XCTAssertEqual(repository.audiences, [.everyone, .onlyMe, .onlyMe])
        store.selectFeedAudience(.everyone)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(repository.audiences.last, .everyone)
    }

    func testAccountChangeResetsAudienceEvenBeforeAnyFeedLoad() {
        let store = WanderStore(fixtures: .empty())
        store.selectFeedAudience(.onlyFriends)
        store.apply(authState: .signedOut)
        XCTAssertEqual(store.feedAudience, .everyone)
    }

    func testLateContentAndCompletionCannotOverwriteNewAudience() async {
        let store = WanderStore(fixtures: .seed())
        let repository = AudienceRepository()
        repository.suspendEveryone = true
        let backend = WanderBackend(feedRepository: repository)
        let old = Task { await store.refreshFollowedFeed(backend: backend) }
        for _ in 0..<100 where repository.audiences.isEmpty { await Task.yield() }
        XCTAssertEqual(repository.audiences, [.everyone])
        store.selectFeedAudience(.onlyMe)
        _ = await store.refreshFollowedFeed(backend: backend)
        let currentDate = store.followedFeedPage?.fetchedAt
        repository.suspendEveryone = false
        let oldResult = await old.value
        XCTAssertFalse(oldResult)
        XCTAssertEqual(store.feedAudience, .onlyMe)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, currentDate)
        XCTAssertEqual(store.feedLoadState, .loaded)
    }
}

@MainActor
private final class AudienceRepository: FeedRepository {
    var audiences: [FeedAudience] = []
    var suspendEveryone = false

    func activityFeed(
        audience: FeedAudience, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void
    ) async throws -> FollowedFeedPage {
        audiences.append(audience)
        // Deliberately ignore cancellation to exercise the store's generation guard.
        while audience == .everyone && suspendEveryone { await Task.yield() }
        let page = FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: nil,
                                    fetchedAt: Date(timeIntervalSince1970: audience == .everyone ? 1 : 2))
        onContent(page)
        return page
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("The audience-aware path must be used")
        throw URLError(.unsupportedURL)
    }
}
