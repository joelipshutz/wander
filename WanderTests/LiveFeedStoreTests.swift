import XCTest
@testable import Wander

@MainActor
final class LiveFeedStoreTests: XCTestCase {
    func testLateContentAndCompletionCannotCrossCommittedQuery() async {
        let store = WanderStore(fixtures: .seed())
        let first = LiveFeedQuery(activityType: .checkIns)
        let second = LiveFeedQuery(activityType: .wannas)
        let repository = LiveStoreRepository(pages: [emptyPage(1), emptyPage(2)])
        let backend = WanderBackend(feedRepository: repository)
        repository.suspendedCall = 1
        store.selectLiveFeedQuery(first)
        let old = Task { await store.refreshFollowedFeed(backend: backend) }
        await waitFor(repository, calls: 1)
        store.selectLiveFeedQuery(second)
        XCTAssertNil(store.followedFeedPage)
        XCTAssertEqual(store.feedLoadState, .idle)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspendedCall = nil
        let accepted = await old.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.liveFeedQuery, second)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(repository.queries, [first, second])
    }

    func testLiveLoadsExactlyOneServerPageEvenWhenActivitiesGroup() async throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let actor = store.shell(for: store.currentUser)
        func page(_ start: Int, cursor: String) -> FollowedFeedPage {
            FollowedFeedPage(activity: (start..<(start+20)).map {
                FeedActivity(id: "live-group-\($0)", kind: .listItemAdded, actor: actor,
                             place: place, occurredAt: Date(timeIntervalSince1970: Double(1000-$0)))
            }, featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
        }
        let repository = LiveStoreRepository(pages: [page(0,cursor:"second"),page(20,cursor:"third")])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        let refreshed = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(repository.cursors, [nil])
        XCTAssertEqual(store.followedFeedPage?.activity.count, 20)
        let appended = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(appended)
        XCTAssertEqual(repository.cursors, [nil,"second"])
        XCTAssertEqual(store.followedFeedPage?.activity.count, 40)
        XCTAssertTrue(store.hasMoreFeed)
    }

    func testPendingPageCannotAppendAfterQuerySwitch() async {
        let store = WanderStore(fixtures: .seed())
        let firstPage = FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: "next", fetchedAt: Date(timeIntervalSince1970: 1))
        let repository = LiveStoreRepository(pages: [firstPage, emptyPage(2), emptyPage(3)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspendedCall = 2
        let old = Task { await store.loadMoreFeed(backend: backend) }
        await waitFor(repository, calls: 2)
        store.selectLiveFeedQuery(LiveFeedQuery(activityType: .wannas))
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspendedCall = nil
        let accepted = await old.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, Date(timeIntervalSince1970: 3))
        XCTAssertFalse(store.isLoadingMoreFeed)
        XCTAssertFalse(store.feedPaginationFailed)
    }

    func testPagedPolygonChangeRestartsCursorAndRejectsOldPolygonPage() async {
        let store = WanderStore(fixtures: .seed())
        let polygonA = LiveFeedQuery(polygon: [
            .init(latitude: 0, longitude: 0), .init(latitude: 0, longitude: 1),
            .init(latitude: 1, longitude: 1), .init(latitude: 1, longitude: 0)])
        let polygonB = LiveFeedQuery(polygon: [
            .init(latitude: 10, longitude: 10), .init(latitude: 10, longitude: 11),
            .init(latitude: 11, longitude: 11), .init(latitude: 11, longitude: 10)])
        XCTAssertTrue(polygonA.isValid && polygonB.isValid)
        func page(_ timestamp: TimeInterval, cursor: String?) -> FollowedFeedPage {
            FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: cursor,
                            fetchedAt: Date(timeIntervalSince1970: timestamp))
        }
        let repository = LiveStoreRepository(pages: [
            page(1, cursor: "a-next"), page(2, cursor: "a-stale"),
            page(3, cursor: "a-after-stale"), page(4, cursor: "b-next")])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(polygonA)
        let initial = await store.refreshFollowedFeed(backend: backend)
        let paged = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(initial && paged)
        XCTAssertEqual(repository.cursors, [nil, "a-next"])
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "a-stale")
        repository.suspendedCall = 3
        let oldPage = Task { await store.loadMoreFeed(backend: backend) }
        await waitFor(repository, calls: 3)
        store.selectLiveFeedQuery(polygonB)
        XCTAssertNil(store.followedFeedPage)
        XCTAssertEqual(store.feedVisibleTileLimit, FeedPagination.pageSize)
        let refreshed = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(repository.queries, [polygonA, polygonA, polygonA, polygonB])
        XCTAssertEqual(repository.cursors, [nil, "a-next", "a-stale", nil])
        repository.suspendedCall = nil
        let accepted = await oldPage.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.liveFeedQuery, polygonB)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, Date(timeIntervalSince1970: 4))
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "b-next")
        XCTAssertFalse(store.isLoadingMoreFeed)
        XCTAssertFalse(store.feedPaginationFailed)
    }

    func testNilRestoresLegacyAndAccountResetClearsQueryBeforeLoad() async {
        let store = WanderStore(fixtures: .seed())
        let repository = LiveStoreRepository(pages: [emptyPage(1)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        store.selectLiveFeedQuery(nil)
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertEqual(repository.legacyCalls, 1)
        let emptyStore = WanderStore(fixtures: .empty())
        emptyStore.selectLiveFeedQuery(LiveFeedQuery(activityType: .wannas))
        emptyStore.apply(authState: .signedOut)
        XCTAssertNil(emptyStore.liveFeedQuery)
    }

    func testDemoFixtureUsesCommittedQuery() async {
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(LiveFeedQuery(occurredAfter: Date.now.addingTimeInterval(365*86_400)))
        let loaded = await store.refreshFollowedFeed(backend: nil)
        XCTAssertTrue(loaded)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 0)
        XCTAssertNil(store.followedFeedPage?.nextCursor)
    }

    func testFailedRefreshAndPaginationCannotExtendUnrelatedSocialRows() async {
        var clock = ContinuousClock.now
        let store = WanderStore(fixtures: .seed(), liveFeedClock: { clock })
        let other = ProfileShell(id: "lease-friend", handle: "friend", displayName: "Friend",
                                 avatarURL: nil, bio: nil, relationship: .follower)
        let own = store.shell(for: store.currentUser)
        func event(_ id: String, actor: ProfileShell) -> FeedActivity {
            FeedActivity(id: id, kind: .listCreated, actor: actor, occurredAt: Date(timeIntervalSince1970: 100))
        }
        let first = FollowedFeedPage(activity: [event("friend-first", actor: other), event("own", actor: own)],
            featuredPlaces: [], nextCursor: "next", fetchedAt: Date.distantFuture)
        let next = FollowedFeedPage(activity: [event("friend-next", actor: other)],
            featuredPlaces: [], nextCursor: nil, fetchedAt: Date.distantFuture)
        let repository = LiveStoreRepository(pages: [first, next, first])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["friend-first", "own"])
        clock = clock.advanced(by: .seconds(800))
        _ = await store.loadMoreFeed(backend: backend)
        clock = clock.advanced(by: .seconds(100))
        store.refreshLiveFeedDisplayLease()
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["friend-next", "own"])
        XCTAssertTrue(store.liveFeedSocialExpired)
        repository.failureOnCalls = [3]
        let refreshed = await store.refreshFollowedFeed(backend: backend)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["friend-next", "own"])
        clock = clock.advanced(by: .seconds(800))
        store.refreshLiveFeedDisplayLease()
        XCTAssertEqual(store.visibleFeedActivityGroups.map(\.id), ["own"])
        XCTAssertEqual(store.followedFeedPage?.activity.count, 3, "Expiry hides Live rows without mutating Profile or source history")
        repository.failureOnCalls = []
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertFalse(store.liveFeedSocialExpired)
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["friend-first", "own"])
        store.selectLiveFeedQuery(nil)
        XCTAssertFalse(store.liveFeedSocialExpired)
    }

    func testInvalidQueryDoesNotMakeRemoteRequest() async {
        let store = WanderStore(fixtures: .seed())
        let repository = LiveStoreRepository(pages: [emptyPage(1)])
        store.selectLiveFeedQuery(LiveFeedQuery(radiusMeters: 5_000))
        let loaded = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertFalse(loaded)
        XCTAssertEqual(store.feedLoadState, .failed)
        XCTAssertTrue(repository.queries.isEmpty)
    }

    func testAccountChangeFencesLateLiveContentAndClearsLeaseAndQuery() async {
        let store = WanderStore(fixtures: .seed())
        let repository = LiveStoreRepository(pages: [emptyPage(1)])
        repository.suspendedCall = 1
        store.selectLiveFeedQuery(LiveFeedQuery())
        let old = Task { await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository)) }
        await waitFor(repository, calls: 1)
        store.apply(authState: .signedIn(AuthSession(userID: "new-live-account", displayName: "New", handle: "new")))
        repository.suspendedCall = nil
        let accepted = await old.value
        XCTAssertFalse(accepted)
        XCTAssertNil(store.liveFeedQuery)
        XCTAssertNil(store.followedFeedPage)
        XCTAssertFalse(store.liveFeedSocialExpired)
        XCTAssertTrue(store.visibleFeedActivityGroups.isEmpty)
    }

    func testWarmRefreshUsesAuthorizationReceiptBeforeDelayedMedia() async {
        await assertDelayedMediaDoesNotRenewLease(paging: false)
    }

    func testPaginationUsesAuthorizationReceiptBeforeDelayedMedia() async {
        await assertDelayedMediaDoesNotRenewLease(paging: true)
    }

    func testEmptyFilteredLivePageKeepsCursorAndCanReachLaterAuthorizedRows() async {
        let store = WanderStore(fixtures: .seed())
        let privateActor = ProfileShell(id: "now-private", handle: "private", displayName: "Private",
            avatarURL: nil, bio: nil, isPrivateProfile: true, relationship: .follower)
        let hidden = FeedActivity(id: "hidden", kind: .listCreated, actor: privateActor, occurredAt: .now)
        let own = FeedActivity(id: "own-next", kind: .listCreated, actor: store.shell(for: store.currentUser), occurredAt: .now)
        let first = FollowedFeedPage(activity: [hidden], featuredPlaces: [], nextCursor: "next", fetchedAt: .now)
        let second = FollowedFeedPage(activity: [own], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        let repository = LiveStoreRepository(pages: [first, second])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(store.followedFeedPage?.activity.isEmpty == true)
        XCTAssertTrue(store.hasMoreFeed)
        XCTAssertEqual(repository.cursors, [nil], "An empty page must not cause an unbounded server scan")
        let loaded = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(loaded)
        XCTAssertEqual(repository.cursors, [nil, "next"])
        XCTAssertEqual(store.visibleFeedActivityGroups.map(\.id), ["own-next"])
        XCTAssertFalse(store.hasMoreFeed)
    }

    private func assertDelayedMediaDoesNotRenewLease(paging: Bool) async {
        var clock = ContinuousClock.now
        let store = WanderStore(fixtures: .seed(), liveFeedClock: { clock })
        let other = ProfileShell(id: "media-friend", handle: "friend", displayName: "Friend",
                                 avatarURL: nil, bio: nil, relationship: .follower)
        let own = FeedActivity(id: "own", kind: .listCreated, actor: store.shell(for: store.currentUser), occurredAt: .now)
        let friend = FeedActivity(id: "friend-next", kind: .listCreated, actor: other, occurredAt: .now)
        let first = FollowedFeedPage(activity: [own], featuredPlaces: [], nextCursor: "next", fetchedAt: .distantFuture)
        let next = FollowedFeedPage(activity: [own, friend], featuredPlaces: [], nextCursor: nil, fetchedAt: .distantFuture)
        let repository = LiveStoreRepository(pages: [first, next])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        clock = clock.advanced(by: .seconds(100))
        repository.suspendedCompletionCall = 2
        let pending = Task {
            if paging { return await store.loadMoreFeed(backend: backend) }
            return await store.refreshFollowedFeed(backend: backend)
        }
        for _ in 0..<200 where repository.contentCalls < 2 { await Task.yield() }
        XCTAssertEqual(repository.contentCalls, 2)
        clock = clock.advanced(by: .seconds(900))
        repository.suspendedCompletionCall = nil
        let loaded = await pending.value
        XCTAssertTrue(loaded)
        XCTAssertEqual(store.visibleFeedActivityGroups.map(\.id), ["own"],
                       "Delayed media cannot renew the earlier text authorization")
        XCTAssertTrue(store.liveFeedSocialExpired)
    }

    private func emptyPage(_ timestamp: TimeInterval) -> FollowedFeedPage {
        FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: nil, fetchedAt: Date(timeIntervalSince1970: timestamp))
    }
    private func waitFor(_ repository: LiveStoreRepository, calls: Int) async {
        for _ in 0..<200 where repository.queries.count < calls { await Task.yield() }
        XCTAssertEqual(repository.queries.count, calls)
    }
}

@MainActor private final class LiveStoreRepository: FeedRepository {
    var queries: [LiveFeedQuery] = []
    var cursors: [String?] = []
    var suspendedCall: Int?
    var suspendedCompletionCall: Int?
    var contentCalls = 0
    var legacyCalls = 0
    var failureOnCalls: Set<Int> = []
    let pages: [FollowedFeedPage]
    init(pages: [FollowedFeedPage]) { self.pages = pages }
    func liveFeed(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int,
                  onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        queries.append(query); cursors.append(before)
        let call = queries.count
        let page = pages[min(call-1,pages.count-1)]
        // Intentionally ignore cancellation to verify the store's scope fence.
        while suspendedCall == call { await Task.yield() }
        if failureOnCalls.contains(call) { throw URLError(.notConnectedToInternet) }
        onContent(page)
        contentCalls += 1
        while suspendedCompletionCall == call { await Task.yield() }
        return page
    }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        legacyCalls += 1
        return FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
    }
}
