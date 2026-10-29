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

    func testExhaustedWindowExpandsOlderThenOutsideFiltersWithoutReorderingOrDuplicates() async {
        let store = WanderStore(fixtures: .seed())
        let own = store.shell(for: store.currentUser)
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 100),
                                  occurredBefore: Date(timeIntervalSince1970: 200), activityType: .checkIns)
        let recent = FeedActivity(id: "recent-check", kind: .placeBeen, actor: own,
                                  occurredAt: Date(timeIntervalSince1970: 150))
        let older = FeedActivity(id: "older-check", kind: .placeBeen, actor: own,
                                 occurredAt: Date(timeIntervalSince1970: 50))
        let outside = FeedActivity(id: "outside-wanna", kind: .placeWannaGo, actor: own,
                                   occurredAt: Date(timeIntervalSince1970: 190))
        func page(_ activity: [FeedActivity]) -> FollowedFeedPage {
            FollowedFeedPage(activity: activity, featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        }
        let repository = LiveStoreRepository(pages: [page([recent]), page([older]), page([outside, recent, older])])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(query)
        _ = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(store.hasMoreFeed, "A terminal selected-window cursor must allow older matching activity")
        let loadedOlder = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(loadedOlder)
        XCTAssertEqual(store.liveFeedExpansionStage, .older)
        XCTAssertEqual(repository.queries[1], query.expandedQuery(for: .older))
        XCTAssertNil(repository.cursors[1], "A changed query must never reuse the preceding query's cursor")
        let loadedAll = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(loadedAll)
        XCTAssertEqual(store.liveFeedExpansionStage, .allActivity)
        XCTAssertEqual(repository.queries[2], query.expandedQuery(for: .allActivity))
        XCTAssertEqual(store.visibleLiveFeedSections.map(\.stage), [.selected, .older, .allActivity])
        XCTAssertEqual(store.visibleFeedActivityGroups.flatMap(\.activities).map(\.id),
                       ["recent-check", "older-check", "outside-wanna"],
                       "The newer outside-filter post stays below its disclosure")
        XCTAssertEqual(store.followedFeedPage?.activity.count, 3)
        XCTAssertFalse(store.hasMoreFeed)
        XCTAssertEqual(store.liveFeedQuery, query, "The map's committed filters do not broaden with the Feed")
    }

    func testExpansionFailurePreservesStageAndRetriesSameNewQuery() async {
        let store = WanderStore(fixtures: .seed())
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 100), activityType: .wannas)
        let repository = LiveStoreRepository(pages: [emptyPage(1), emptyPage(2), emptyPage(3)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(query)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.failureOnCalls = [2]
        let failed = await store.loadMoreFeed(backend: backend)
        XCTAssertFalse(failed)
        XCTAssertEqual(store.liveFeedExpansionStage, .selected)
        XCTAssertTrue(store.feedPaginationFailed)
        repository.failureOnCalls = []
        let retried = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(retried)
        XCTAssertEqual(repository.queries[1], repository.queries[2])
        XCTAssertEqual(repository.cursors, [nil, nil, nil])
        XCTAssertEqual(store.liveFeedExpansionStage, .older)
    }

    func testTimeOnlyExpansionFinishesWithoutRefetchingAllActivity() async {
        let store = WanderStore(fixtures: .seed())
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 100))
        let repository = LiveStoreRepository(pages: [emptyPage(1), emptyPage(2)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(query)
        _ = await store.refreshFollowedFeed(backend: backend)
        _ = await store.loadMoreFeed(backend: backend)
        XCTAssertEqual(store.liveFeedExpansionStage, .older)
        XCTAssertFalse(store.hasMoreFeed, "The older stage already contains all activity when no discovery filters exist")
        XCTAssertEqual(repository.queries.count, 2)
    }

    func testLiveCursorCycleStopsAndKeepsPreviouslyLoadedRows() async {
        let store = WanderStore(fixtures: .seed())
        func page(_ cursor: String) -> FollowedFeedPage {
            FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
        }
        let repository = LiveStoreRepository(pages: [page("first"), page("second"), page("first")])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: backend)
        let loaded = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(loaded)
        let cycled = await store.loadMoreFeed(backend: backend)
        XCTAssertFalse(cycled)
        XCTAssertTrue(store.feedPaginationFailed)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "second")
        XCTAssertEqual(repository.cursors, [nil, "first", "second"])
    }

    func testLateExpansionCannotCrossAChangedFilter() async {
        let store = WanderStore(fixtures: .seed())
        let first = LiveFeedQuery(activityType: .wannas)
        let second = LiveFeedQuery(activityType: .checkIns)
        let repository = LiveStoreRepository(pages: [emptyPage(1), emptyPage(2), emptyPage(3)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(first)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspendedCall = 2
        let broadening = Task { await store.loadMoreFeed(backend: backend) }
        await waitFor(repository, calls: 2)
        store.selectLiveFeedQuery(second)
        _ = await store.refreshFollowedFeed(backend: backend)
        repository.suspendedCall = nil
        let accepted = await broadening.value
        XCTAssertFalse(accepted)
        XCTAssertEqual(store.liveFeedExpansionStage, .selected)
        XCTAssertEqual(store.liveFeedQuery, second)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, Date(timeIntervalSince1970: 3))
    }

    func testProfileBookkeepingDoesNotInvalidateWarmFeedOrPagination() async {
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(.init())
        let repository = LiveStoreRepository(pages: [emptyPage(1)])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        let revision = store.liveContentRevision
        let presentation = store.presentationRevision
        store.updateCurrentUserProfile(bio: "Warm resume fixture")
        XCTAssertGreaterThan(store.presentationRevision, presentation)
        XCTAssertEqual(store.liveContentRevision, revision)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(repository.queries.count, 1)
        store.setPrivateProfile(!store.currentUser.isPrivateProfile)
        XCTAssertNotEqual(store.liveContentRevision, revision)
    }

    func testWarmQueryAdvancePreservesScrollWhileExplicitBrowseAndAccountChangesResetIt() {
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 100)))
        let initial = store.liveFeedScrollResetRevision
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 220)), preservingMatchingContent: true)
        XCTAssertEqual(store.liveFeedScrollResetRevision, initial)
        store.selectLiveFeedQuery(.init(activityType: .wannas))
        XCTAssertGreaterThan(store.liveFeedScrollResetRevision, initial)
        let filtered = store.liveFeedScrollResetRevision
        store.apply(authState: .signedIn(AuthSession(userID: "scroll-new-account", displayName: "Fixture", handle: "fixture")))
        XCTAssertGreaterThan(store.liveFeedScrollResetRevision, filtered)
    }

    func testAutomaticMovementKeepsMatchingRowsButNeverOldCursorOrExpiredAuthorization() async {
        let start = ContinuousClock.now
        var instant = start
        let store = WanderStore(fixtures: .seed(), liveFeedClock: { instant })
        let actor = ProfileShell(id: "friend", handle: "friend", displayName: "Friend", avatarURL: nil, bio: nil, relationship: .follower)
        let row = FeedActivity(id: "retained", kind: .listCreated, actor: actor, occurredAt: Date(timeIntervalSince1970: 100))
        let repository = LiveStoreRepository(pages: [.init(activity: [row], featuredPlaces: [], nextCursor: "old-cursor", fetchedAt: .now)])
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 200)))
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 300)), preservingMatchingContent: true)
        XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), [row.id])
        XCTAssertNil(store.followedFeedPage?.nextCursor)
        instant = start.advanced(by: .seconds(900))
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 400)), preservingMatchingContent: true)
        XCTAssertTrue(store.followedFeedPage?.activity.isEmpty == true)
    }

    func testBackgroundRefreshKeepsPaginatedTailWhileManualRefreshResetsIt() async throws {
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(.init())
        let actor = store.shell(for: store.currentUser)
        func row(_ number: Int) -> FeedActivity {
            .init(id: "tail-\(number)", kind: .listCreated, actor: actor,
                  occurredAt: Date(timeIntervalSince1970: Double(1000-number)))
        }
        func page(_ range: Range<Int>, cursor: String?) -> FollowedFeedPage {
            .init(activity: range.map(row), featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
        }
        let repository = LiveStoreRepository(pages: [page(0..<20, cursor: "second"), page(20..<40, cursor: "third"),
            page(0..<20, cursor: "second"), page(0..<20, cursor: "second")])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        _ = await store.loadMoreFeed(backend: backend)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 40)
        // A real access/content mutation bypasses freshness, but automatic
        // refresh must keep the reader's older page and visible window.
        store.setPrivateProfile(!store.currentUser.isPrivateProfile)
        let limit = store.feedVisibleTileLimit
        repository.suspendedCall = 3
        let task = Task { await store.refreshFollowedFeed(backend: backend, force: false) }
        await waitFor(repository, calls: 3)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 40)
        repository.suspendedCall = nil
        _ = await task.value
        XCTAssertEqual(store.followedFeedPage?.activity.count, 40)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "third")
        XCTAssertEqual(store.feedVisibleTileLimit, limit)
        _ = await store.refreshFollowedFeed(backend: backend, force: true)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 20)
        XCTAssertEqual(store.feedVisibleTileLimit, FeedPagination.pageSize)
    }

    func testWarmTimeWindowAdvancePreservesVisibleLimitAndAdoptsNewQueryCursor() async {
        let store = WanderStore(fixtures: .seed())
        let actor = store.shell(for: store.currentUser)
        func page(_ range: Range<Int>, cursor: String?) -> FollowedFeedPage {
            .init(activity: range.map { .init(id: "warm-window-\($0)", kind: .listCreated, actor: actor,
                occurredAt: Date(timeIntervalSince1970: Double(1000-$0))) }, featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
        }
        let repository = LiveStoreRepository(pages: [page(0..<20, cursor: "old-second"), page(20..<40, cursor: "old-third"),
            page(0..<20, cursor: "new-second"), page(20..<40, cursor: "new-third"), page(40..<60, cursor: nil)])
        let backend = WanderBackend(feedRepository: repository)
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 1100)))
        _ = await store.refreshFollowedFeed(backend: backend)
        _ = await store.loadMoreFeed(backend: backend)
        let limit = store.feedVisibleTileLimit
        store.selectLiveFeedQuery(.init(occurredBefore: Date(timeIntervalSince1970: 1220)), preservingMatchingContent: true)
        XCTAssertEqual(store.feedVisibleTileLimit, limit)
        XCTAssertNil(store.followedFeedPage?.nextCursor, "Never reuse a cursor bound to the old query")
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(store.feedVisibleTileLimit, limit)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 40)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "new-second")
        _ = await store.loadMoreFeed(backend: backend)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "new-third")
        // The embedded Feed automatically continues duplicate-only pages while
        // its bottom remains visible, one bounded server read per request.
        _ = await store.loadMoreFeed(backend: backend)
        XCTAssertEqual(store.followedFeedPage?.activity.count, 60)
        XCTAssertEqual(repository.cursors.compactMap { $0 }, ["old-second", "new-second", "new-third"])
    }

    func testWarmRefreshRetainsTimestampTiesAcrossPageBoundary() async {
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(.init())
        let actor = store.shell(for: store.currentUser)
        func page(_ numbers: [Int], cursor: String?) -> FollowedFeedPage {
            .init(activity: numbers.map { .init(id: "tie-\($0)", kind: .listCreated, actor: actor,
                occurredAt: Date(timeIntervalSince1970: $0 >= 30 ? 500 : 400)) },
                featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
        }
        let first = page(Array((41...60).reversed()), cursor: "second")
        let second = page(Array((21...40).reversed()), cursor: "third")
        let repository = LiveStoreRepository(pages: [first, second, first])
        let backend = WanderBackend(feedRepository: repository)
        _ = await store.refreshFollowedFeed(backend: backend)
        _ = await store.loadMoreFeed(backend: backend)
        store.setPrivateProfile(!store.currentUser.isPrivateProfile)
        _ = await store.refreshFollowedFeed(backend: backend, force: false)
        XCTAssertEqual(Set(store.followedFeedPage?.activity.map(\.id) ?? []), Set((21...60).map { "tie-\($0)" }))
        XCTAssertEqual(store.followedFeedPage?.nextCursor, "third")
    }

    func testAutomaticRefreshKeepsExpandedSectionsAndTheirOwnCursor() async {
        for includeAll in [false, true] {
            let store = WanderStore(fixtures: .seed())
            let actor = store.shell(for: store.currentUser)
            let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 100),
                occurredBefore: Date(timeIntervalSince1970: 200), activityType: .checkIns)
            let recent = FeedActivity(id: "warm-recent", kind: .placeBeen, actor: actor, occurredAt: Date(timeIntervalSince1970: 150))
            let older = FeedActivity(id: "warm-older", kind: .placeBeen, actor: actor, occurredAt: Date(timeIntervalSince1970: 50))
            let outside = FeedActivity(id: "warm-outside", kind: .placeWannaGo, actor: actor, occurredAt: Date(timeIntervalSince1970: 190))
            func page(_ rows: [FeedActivity], cursor: String? = nil) -> FollowedFeedPage {
                .init(activity: rows, featuredPlaces: [], nextCursor: cursor, fetchedAt: .now)
            }
            var pages = [page([recent]), page([older])]
            if includeAll { pages.append(page([outside])) }
            pages.append(page([recent], cursor: "selected-query-cursor"))
            let repository = LiveStoreRepository(pages: pages), backend = WanderBackend(feedRepository: repository)
            store.selectLiveFeedQuery(query)
            _ = await store.refreshFollowedFeed(backend: backend)
            _ = await store.loadMoreFeed(backend: backend)
            if includeAll { _ = await store.loadMoreFeed(backend: backend) }
            let limit = store.feedVisibleTileLimit
            store.setPrivateProfile(!store.currentUser.isPrivateProfile)
            _ = await store.refreshFollowedFeed(backend: backend, force: false)
            XCTAssertEqual(store.liveFeedExpansionStage, includeAll ? .allActivity : .older)
            XCTAssertEqual(store.feedVisibleTileLimit, limit)
            XCTAssertEqual(store.followedFeedPage?.activity.count, includeAll ? 3 : 2)
            XCTAssertNil(store.followedFeedPage?.nextCursor, "A selected-query cursor cannot replace an expanded query cursor")
        }
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
