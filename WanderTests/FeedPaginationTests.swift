import XCTest
@testable import Wander

@MainActor
final class FeedPaginationTests: XCTestCase {
    func testTwentyTilesThenTwoMorePagesWithoutDuplicates() async throws {
        let store = WanderStore(fixtures: .seed())
        let repository = PagingRepository(pages: [
            page(store, 0..<20, cursor: "20"),
            page(store, 19..<39, cursor: "39"),
            page(store, 39..<59, cursor: "59"),
            page(store, 59..<65)
        ])
        let backend = WanderBackend(feedRepository: repository)
        let first = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(first)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
        XCTAssertEqual(repository.cursors, [nil])
        XCTAssertTrue(store.hasMoreFeed)
        let second = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(second)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 40)
        XCTAssertEqual(repository.cursors, [nil, "20", "39"])
        let third = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(third)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 60)
        XCTAssertTrue(store.hasMoreFeed, "Five buffered tiles remain after the server is exhausted")
        let last = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(last)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 65)
        XCTAssertFalse(store.hasMoreFeed)
        XCTAssertEqual(repository.limits, [20, 20, 20, 20])
        XCTAssertEqual(Set(store.followedFeedPage!.activity.map(\.id)).count, 65)
        let exhausted = await store.loadMoreFeed(backend: backend)
        XCTAssertFalse(exhausted)
        XCTAssertEqual(repository.cursors.count, 4)
    }

    func testGroupingFillsTwentyVisibleTilesAndKeepsOverflowBuffered() async throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let actor = store.shell(for: store.currentUser)
        let events = (0..<20).map { index in
            FeedActivity(id: "group-\(index)", kind: .listItemAdded, actor: actor,
                         place: place, occurredAt: Date.now.addingTimeInterval(Double(-index)))
        }
        let repository = PagingRepository(pages: [
            FollowedFeedPage(activity: events, featuredPlaces: [], nextCursor: "next", fetchedAt: .now),
            page(store, 20..<40)
        ])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
        XCTAssertEqual(repository.cursors, [nil, "next"])
        XCTAssertTrue(store.hasMoreFeed)
        _ = await store.loadMoreFeed(backend: backend)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 21)
        XCTAssertFalse(store.hasMoreFeed)
        XCTAssertEqual(repository.cursors.count, 2)
    }

    func testFailureKeepsLoadedTilesAndRetriesSameCursor() async {
        let store = WanderStore(fixtures: .seed())
        let repository = PagingRepository(pages: [page(store, 0..<20, cursor: "next"), page(store, 20..<40)])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.failNext = true
        let failed = await store.loadMoreFeed(backend: backend)
        XCTAssertFalse(failed)
        XCTAssertTrue(store.feedPaginationFailed)
        XCTAssertFalse(store.isLoadingMoreFeed)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
        let retried = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(retried)
        XCTAssertFalse(store.feedPaginationFailed)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 40)
        XCTAssertEqual(repository.cursors, [nil, "next", "next"])
    }

    func testConcurrentRequestsShareOnePageLoad() async {
        let store = WanderStore(fixtures: .seed())
        let repository = PagingRepository(pages: [page(store, 0..<20, cursor: "next"), page(store, 20..<40)])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspend = true
        let first = Task { await store.loadMoreFeed(backend: backend) }
        await waitForRequest(repository, count: 2)
        let second = Task { await store.loadMoreFeed(backend: backend) }
        await Task.yield()
        XCTAssertTrue(store.isLoadingMoreFeed)
        XCTAssertEqual(repository.cursors.count, 2)
        repository.suspend = false
        let results = await [first.value, second.value]
        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 40)
    }

    func testLatePageCannotReplaceAudienceRefreshOrAccount() async {
        for change in 0..<3 {
            let store = WanderStore(fixtures: .seed())
            let repository = PagingRepository(pages: [page(store, 0..<20, cursor: "next"), page(store, 20..<40)])
            let backend = WanderBackend(feedRepository: repository)
            _ = await store.refreshFollowedFeed(backend: backend)
            repository.suspend = true
            let pending = Task { await store.loadMoreFeed(backend: backend) }
            await waitForRequest(repository, count: 2)
            if change == 0 { store.selectFeedAudience(.onlyMe) }
            if change == 1 { store.apply(authState: .signedOut) }
            if change == 2 {
                repository.suspend = false
                repository.pages.append(page(store, 100..<120))
                _ = await store.refreshFollowedFeed(backend: backend)
            }
            repository.suspend = false
            let accepted = await pending.value
            XCTAssertFalse(accepted)
            XCTAssertFalse(store.isLoadingMoreFeed)
            XCTAssertFalse(store.followedFeedPage?.activity.contains { $0.id == "event-20" } ?? false)
            XCTAssertEqual(store.feedVisibleTileLimit, 20)
        }
    }

    func testRepeatedCursorIsRetryableWithoutLooping() async {
        let store = WanderStore(fixtures: .seed())
        let repository = PagingRepository(pages: [
            page(store, 0..<20, cursor: "same"), page(store, 0..<20, cursor: "same")
        ])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        let result = await store.loadMoreFeed(backend: backend)
        XCTAssertFalse(result)
        XCTAssertTrue(store.feedPaginationFailed)
        XCTAssertEqual(repository.cursors.count, 2)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
    }

    func testOlderFocusedActivityCanBeRevealedWithoutFetchingAnotherPage() async {
        let store = WanderStore(fixtures: .seed())
        let repository = PagingRepository(pages: [page(store, 0..<45)])
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
        store.revealFeedActivity("event-42")
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 43)
        XCTAssertTrue(store.visibleFeedActivityGroups.contains { $0.activities.contains { $0.id == "event-42" } })
        XCTAssertEqual(repository.cursors.count, 1)
    }

    func testRevocationCancelsPendingInitialRefreshForColdAndWarmFeed() async {
        for startsWarm in [false, true] {
            let store = WanderStore(fixtures: .seed())
            let revokedID = UUID().uuidString
            let revoked = FeedActivity(id: revokedID, kind: .placeBeen,
                                       actor: store.shell(for: store.currentUser), occurredAt: .now)
            let stalePage = FollowedFeedPage(activity: [revoked] + page(store, 1..<20).activity,
                                            featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
            let recoveryPage = page(store, 1..<20)
            let repository = PagingRepository(pages: startsWarm
                ? [stalePage, stalePage, recoveryPage] : [stalePage, recoveryPage])
            let engagement = ActivityEngagementRepositoryStub(activityResponses: [
                .failure(WanderRemoteError.invalidResponse("activity_not_visible"))
            ])
            let backend = WanderBackend(feedRepository: repository, activityEngagementRepository: engagement)
            if startsWarm { _ = await store.refreshFollowedFeed(backend: backend) }
            repository.suspend = true
            let pending = Task { await store.refreshFollowedFeed(backend: backend) }
            await waitForRequest(repository, count: startsWarm ? 2 : 1)

            let denied = await store.activity(id: revokedID, backend: backend)
            XCTAssertNil(denied)
            repository.suspend = false
            let accepted = await pending.value
            XCTAssertFalse(accepted)
            XCTAssertFalse(store.followedFeedPage?.activity.contains { $0.id == revokedID } ?? false)
            XCTAssertFalse(store.visibleFeedActivityGroups.contains { $0.activities.contains { $0.id == revokedID } })

            let recovered = await store.refreshFollowedFeed(backend: backend, force: false)
            XCTAssertTrue(recovered, "Revocation must not prevent a newly authorized refresh")
            XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), recoveryPage.activity.map(\.id))
        }
    }

    func testRevocationCancelsPendingPageWithoutRestoringRemovedActivity() async {
        let store = WanderStore(fixtures: .seed())
        let revokedID = UUID().uuidString
        let revoked = FeedActivity(id: revokedID, kind: .placeBeen,
                                   actor: store.shell(for: store.currentUser), occurredAt: .now)
        let initial = FollowedFeedPage(activity: [revoked] + page(store, 1..<20).activity,
                                      featuredPlaces: [], nextCursor: "next", fetchedAt: .now)
        let repository = PagingRepository(pages: [initial, page(store, 20..<40)])
        let engagement = ActivityEngagementRepositoryStub(activityResponses: [
            .failure(WanderRemoteError.invalidResponse("activity_not_visible"))
        ])
        let backend = WanderBackend(feedRepository: repository, activityEngagementRepository: engagement)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspend = true
        let pending = Task { await store.loadMoreFeed(backend: backend) }
        await waitForRequest(repository, count: 2)
        let denied = await store.activity(id: revokedID, backend: backend)
        XCTAssertNil(denied)
        repository.suspend = false
        let accepted = await pending.value
        XCTAssertFalse(accepted)
        XCTAssertFalse(store.followedFeedPage!.activity.contains { $0.id == revokedID })
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 19)
        XCTAssertFalse(store.isLoadingMoreFeed)
    }

    func testGroupAcrossCursorPagesRetainsOrderingAndBatchesEngagement() async throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let now = Date.now
        let groupedEvents = (0..<120).map { index in
            FeedActivity(id: UUID().uuidString, kind: .listItemAdded,
                         actor: store.shell(for: store.currentUser), place: place,
                         occurredAt: now.addingTimeInterval(Double(-index)))
        }
        var pages = stride(from: 0, to: 120, by: 20).map { start in
            FollowedFeedPage(activity: Array(groupedEvents[start..<start + 20]), featuredPlaces: [],
                             nextCursor: "cursor-\(start + 20)", fetchedAt: now)
        }
        pages.append(page(store, 1..<20))
        let repository = PagingRepository(pages: pages)
        let engagement = ActivityEngagementRepositoryStub()
        let backend = WanderBackend(feedRepository: repository, activityEngagementRepository: engagement)
        let loaded = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(loaded)
        XCTAssertEqual(store.visibleFeedActivityGroups.count, 20)
        XCTAssertEqual(store.visibleFeedActivityGroups.first?.activities.count, 120)
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.first!.activities.map(\.id)), Set(groupedEvents.map(\.id)))
        XCTAssertEqual(store.visibleFeedActivityGroups.first?.id,
                       FeedPresentation.groupedActivity(groupedEvents).first?.id)
        XCTAssertEqual(engagement.summariesRequests.map(\.count), [100, 20])
        XCTAssertTrue(groupedEvents.allSatisfy { store.activityEngagementByID[$0.id] != nil })
        XCTAssertTrue(store.activityEngagementErrorByID.isEmpty)
        XCTAssertEqual(repository.limits, Array(repeating: 20, count: 7))
    }

    func testOnlyDownwardArrivalAtActualBottomTriggersLoading() {
        func metrics(_ offset: CGFloat, height: CGFloat = 2_000) -> FeedScrollMetrics {
            FeedScrollMetrics(offset: offset, contentHeight: height, viewportHeight: 800)
        }
        XCTAssertFalse(metrics(1_150).reachedBottom(after: metrics(1_000)), "Near the bottom is too early")
        XCTAssertTrue(metrics(1_200).reachedBottom(after: metrics(1_150)))
        XCTAssertFalse(metrics(1_201).reachedBottom(after: metrics(1_200)), "No repeated request while bouncing")
        XCTAssertFalse(metrics(1_200).reachedBottom(after: nil), "Appearance is not scrolling")
        XCTAssertFalse(metrics(1_200).reachedBottom(after: metrics(1_250)), "Upward scrolling")
        XCTAssertFalse(metrics(1_200, height: 1_900).reachedBottom(after: metrics(1_200)), "Layout changes")
        XCTAssertFalse(metrics(0, height: 400).reachedBottom(after: metrics(0, height: 400)))
    }

    private func page(_ store: WanderStore, _ range: Range<Int>, cursor: String? = nil) -> FollowedFeedPage {
        FollowedFeedPage(activity: range.map { index in
            FeedActivity(id: "event-\(index)", kind: .placeBeen, actor: store.shell(for: store.currentUser),
                         occurredAt: Date.now.addingTimeInterval(Double(-index * 3_600)))
        }, featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
    }

    private func waitForRequest(_ repository: PagingRepository, count: Int) async {
        for _ in 0..<1_000 where repository.cursors.count < count { await Task.yield() }
        XCTAssertEqual(repository.cursors.count, count)
    }
}

@MainActor
private final class PagingRepository: FeedRepository {
    var pages: [FollowedFeedPage]
    var cursors: [String?] = []
    var limits: [Int] = []
    var suspend = false
    var failNext = false

    init(pages: [FollowedFeedPage]) { self.pages = pages }

    func activityFeed(audience: FeedAudience, before: String?, limit: Int,
                      onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        cursors.append(before)
        limits.append(limit)
        if failNext { failNext = false; throw URLError(.notConnectedToInternet) }
        guard !pages.isEmpty else { throw URLError(.badServerResponse) }
        let result = pages.removeFirst()
        while suspend { await Task.yield() } // Intentionally ignores cancellation.
        onContent(result)
        return result
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        XCTFail("Must preserve the selected audience")
        throw URLError(.unsupportedURL)
    }
}
