import XCTest
@testable import Wander

@MainActor
final class FeedIntegrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testNoMapFilterPreservesExistingGroupedFeedCards() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let events = [
            activity("wanna", kind: .placeWannaGo, store: store, place: place, offset: -120),
            activity("check-in", kind: .placeBeen, store: store, place: place, offset: -60),
            activity("other", kind: .listCreated, store: store, offset: -30)
        ]
        let groups = FeedPresentation.groupedActivity(events, relativeTo: now)
        XCTAssertEqual(groups.count, 2)

        let embedded = FeedEmbeddedProjection.groups(from: groups, matching: nil, relativeTo: now)
        XCTAssertEqual(embedded.map(\.id), groups.map(\.id))
        XCTAssertEqual(embedded.map { $0.activities.map(\.id) }, groups.map { $0.activities.map(\.id) })
        XCTAssertEqual(embedded.map(\.primaryActivity.id), groups.map(\.primaryActivity.id))
    }

    func testMapFilterRemovesExcludedEventsBeforeRebuildingCombinedCard() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let list = LocalPlaceList(localID: "list", ownerUserID: store.currentUser.id,
                                  name: "Weekend", description: "")
        let events = [
            activity("wanna", kind: .placeWannaGo, store: store, place: place, offset: -180),
            activity("check-in", kind: .placeBeen, store: store, place: place, offset: -120),
            FeedActivity(id: "list-add", kind: .listItemAdded, actor: store.shell(for: store.currentUser),
                         place: place, list: list, occurredAt: now.addingTimeInterval(-60))
        ]
        let groups = FeedPresentation.groupedActivity(events, relativeTo: now)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.primaryActivity.id, "check-in")
        XCTAssertEqual(groups.first?.lists.count, 1)

        let filtered = FeedEmbeddedProjection.groups(from: groups, matching: ["wanna"], relativeTo: now)
        let card = try XCTUnwrap(filtered.first)
        XCTAssertEqual(card.primaryActivity.id, "wanna")
        XCTAssertEqual(card.activities.map(\.id), ["wanna"])
        XCTAssertTrue(card.lists.isEmpty)
        XCTAssertFalse(card.isCombined)
    }

    func testExplicitEmptyOrUnavailableMapSelectionCannotRestoreFeedContent() {
        let store = WanderStore(fixtures: .seed())
        let group = FeedActivityGroup(activity("visible", kind: .placeBeen, store: store))
        XCTAssertTrue(FeedEmbeddedProjection.groups(from: [group], matching: []).isEmpty)
        XCTAssertTrue(FeedEmbeddedProjection.groups(from: [group], matching: ["not-authorized"]).isEmpty)
    }

    func testMapIDsCannotReintroduceBlockedActivityFromRepository() async throws {
        let store = WanderStore(fixtures: .seed())
        let profile = try XCTUnwrap(store.profile(for: "user_maya"))
        let blockedActivity = FeedActivity(id: "blocked", kind: .listCreated, actor: store.shell(for: profile),
                                           occurredAt: now)
        let ownActivity = activity("own", kind: .placeBeen, store: store)
        store.block(userID: profile.id)
        let repository = EmbeddedFeedRepository(activity: [blockedActivity, ownActivity])
        let loaded = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertTrue(loaded)

        let filtered = FeedEmbeddedProjection.groups(
            from: store.visibleFeedActivityGroups, matching: ["blocked", "own"], relativeTo: now
        )
        XCTAssertEqual(filtered.flatMap(\.activities).map(\.id), ["own"])
    }

    func testMapFocusCanRevealBufferedActivityThroughExistingFeedPagination() async throws {
        let store = WanderStore(fixtures: .seed())
        let events = (0..<25).map {
            activity("event-\($0)", kind: .placeBeen, store: store, offset: Double(-$0 * 3_600))
        }
        let repository = EmbeddedFeedRepository(activity: events)
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertTrue(FeedEmbeddedProjection.groups(
            from: store.visibleFeedActivityGroups, matching: ["event-24"], relativeTo: now
        ).isEmpty)

        store.revealFeedActivity("event-24")

        let filtered = FeedEmbeddedProjection.groups(
            from: store.visibleFeedActivityGroups, matching: ["event-24"], relativeTo: now
        )
        XCTAssertEqual(filtered.flatMap(\.activities).map(\.id), ["event-24"])
    }

    private func activity(
        _ id: String, kind: FeedActivityKind, store: WanderStore,
        place: VisiblePlace? = nil, offset: TimeInterval = 0
    ) -> FeedActivity {
        FeedActivity(id: id, kind: kind, actor: store.shell(for: store.currentUser), place: place,
                     occurredAt: now.addingTimeInterval(offset))
    }
}

@MainActor
private final class EmbeddedFeedRepository: FeedRepository {
    let activity: [FeedActivity]
    init(activity: [FeedActivity]) { self.activity = activity }

    func activityFeed(audience: FeedAudience, before: String?, limit: Int,
                      onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        let page = FollowedFeedPage(activity: activity, featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        onContent(page)
        return page
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("The existing Feed audience contract must be retained")
        throw URLError(.unsupportedURL)
    }
}
