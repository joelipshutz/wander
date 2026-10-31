#if DEBUG && targetEnvironment(simulator)
import XCTest
@testable import Wander

@MainActor
final class LiveManualPaginationUITestRepositoryTests: XCTestCase {
    private let arguments = Array(LiveManualPaginationUITestRepository.requiredArguments)
    private let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 1_700_000_000),
                                      occurredBefore: Date(timeIntervalSince1970: 1_700_000_600))

    func testFactoryRequiresEveryIsolatedArgumentAndSyntheticAuthenticatedOwner() throws {
        XCTAssertNotNil(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: "user_joe"))
        for argument in arguments {
            XCTAssertNil(LiveManualPaginationUITestRepository.make(arguments: arguments.filter { $0 != argument },
                                                                    authenticatedUserID: "user_joe"))
        }
        XCTAssertNil(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: nil))
        XCTAssertNil(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: "another-user"))
    }

    func testEmptyAuthorizedPageContinuesOnceToOwnQueryMatchingActivityAndExhausts() async throws {
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: "user_joe"))
        var callbacks: [FollowedFeedPage] = []
        let first = try await repository.liveFeed(audience: .everyone, query: query, before: nil, limit: 20) { callbacks.append($0) }
        XCTAssertTrue(first.activity.isEmpty)
        XCTAssertTrue(first.featuredPlaces.isEmpty)
        XCTAssertEqual(first.nextCursor, LiveManualPaginationUITestRepository.nextCursor)
        XCTAssertEqual(callbacks.count, 1)
        XCTAssertTrue(callbacks[0].activity.isEmpty)
        XCTAssertEqual(callbacks[0].nextCursor, first.nextCursor)
        let second = try await repository.liveFeed(audience: .everyone, query: query, before: first.nextCursor, limit: 20) { callbacks.append($0) }
        XCTAssertEqual(callbacks.count, 2)
        XCTAssertEqual(second.activity.map(\.id), [LiveManualPaginationUITestRepository.activityID])
        XCTAssertEqual(callbacks[1].activity.map(\.id), second.activity.map(\.id))
        XCTAssertNil(second.nextCursor)
        let activity = try XCTUnwrap(second.activity.first)
        XCTAssertEqual(activity.actor.id, "user_joe")
        XCTAssertEqual(activity.actor.relationship, .owner)
        XCTAssertEqual(activity.kind, .listCreated)
        XCTAssertEqual(activity.list?.ownerUserID, activity.actor.id)
        XCTAssertTrue(query.includes(activity))
    }

    func testIndependentMapSnapshotDoesNotPrimeOrReplaceFeedCursorQuery() async throws {
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(
            arguments: arguments, authenticatedUserID: "user_joe"))
        let map = try await repository.liveMapActivity(audience: .everyone, query: query, before: nil, limit: 50)
        XCTAssertTrue(map.activity.isEmpty)
        XCTAssertTrue(map.featuredPlaces.isEmpty)
        XCTAssertNil(map.nextCursor)
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: self.query,
                before: LiveManualPaginationUITestRepository.nextCursor, limit: 20) { _ in XCTFail("Unexpected content") }
        }

        let first = try await repository.liveFeed(audience: .everyone, query: query, before: nil, limit: 20) { _ in }
        let differentMapQuery = LiveFeedQuery(activityType: .wannas)
        let refreshedMap = try await repository.liveMapActivity(
            audience: .everyone, query: differentMapQuery, before: nil, limit: 50)
        XCTAssertTrue(refreshedMap.activity.isEmpty)
        XCTAssertNil(refreshedMap.nextCursor)
        var callbackIDs: [String] = []
        let second = try await repository.liveFeed(audience: .everyone, query: query,
            before: first.nextCursor, limit: 20) { callbackIDs = $0.activity.map(\.id) }
        XCTAssertEqual(second.activity.map(\.id), [LiveManualPaginationUITestRepository.activityID])
        XCTAssertEqual(callbackIDs, second.activity.map(\.id))
        XCTAssertNil(second.nextCursor)
        XCTAssertNil(second.activity.first?.place)
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: self.query,
                before: nil, limit: 50) { _ in XCTFail("Map's limit must not be accepted by Feed") }
        }
    }

    func testViewportPolygonContinuesThroughProductionStoreAndDeduplicatesAllExpansionStages() async throws {
        let boundedQuery = LiveFeedQuery(occurredAfter: query.occurredAfter, occurredBefore: query.occurredBefore,
            polygon: [
                .init(latitude: 34.0, longitude: -118.4), .init(latitude: 34.1, longitude: -118.4),
                .init(latitude: 34.1, longitude: -118.2), .init(latitude: 34.0, longitude: -118.2)
            ])
        XCTAssertTrue(boundedQuery.isValid)
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(
            arguments: arguments, authenticatedUserID: "user_joe"))
        let backend = WanderBackend(feedRepository: repository)
        let store = WanderStore(fixtures: .seed())
        store.selectLiveFeedQuery(boundedQuery)
        let refreshed = await store.refreshFollowedFeed(backend: backend)
        XCTAssertTrue(refreshed)
        XCTAssertEqual(store.feedLoadState, .loaded)
        XCTAssertTrue(try XCTUnwrap(store.followedFeedPage).activity.isEmpty)
        XCTAssertEqual(store.followedFeedPage?.nextCursor, LiveManualPaginationUITestRepository.nextCursor)
        XCTAssertTrue(store.hasMoreFeed)

        let map = try await repository.liveMapActivity(audience: .everyone,
            query: LiveFeedQuery(activityType: .wannas), before: nil, limit: 50)
        XCTAssertTrue(map.activity.isEmpty)
        XCTAssertNil(map.nextCursor)
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: self.query,
                before: LiveManualPaginationUITestRepository.nextCursor, limit: 20) { _ in XCTFail("Mismatched query must fail") }
        }
        let continued = await store.loadMoreFeed(backend: backend)
        XCTAssertTrue(continued)
        let activity = try XCTUnwrap(store.followedFeedPage?.activity.first)
        XCTAssertEqual(activity.id, LiveManualPaginationUITestRepository.activityID)
        XCTAssertEqual(activity.kind, .listItemAdded)
        XCTAssertEqual(activity.list?.id, "fixture-live-manual-list")
        XCTAssertEqual(activity.actor.id, store.currentUser.id)
        XCTAssertEqual(activity.place?.userPlace.userID, store.currentUser.id)
        XCTAssertTrue(boundedQuery.includes(activity))

        var visitedStages: Set<LiveFeedExpansionStage> = [store.liveFeedExpansionStage]
        for _ in 0..<6 where store.hasMoreFeed {
            let loaded = await store.loadMoreFeed(backend: backend)
            XCTAssertTrue(loaded)
            XCTAssertFalse(store.feedPaginationFailed)
            visitedStages.insert(store.liveFeedExpansionStage)
            XCTAssertEqual(store.followedFeedPage?.activity.map(\.id), [LiveManualPaginationUITestRepository.activityID])
            XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id),
                           [LiveManualPaginationUITestRepository.activityID])
        }
        XCTAssertEqual(visitedStages, [.selected, .older, .allActivity])
        XCTAssertEqual(store.liveFeedExpansionStage, .allActivity)
        XCTAssertFalse(store.hasMoreFeed)
        XCTAssertNil(store.followedFeedPage?.nextCursor)
        XCTAssertEqual(store.followedFeedPage?.activity.first?.kind, .listItemAdded,
                       "Overlapping later copies must not replace the authorized original activity.")
    }

    func testIndependentMapRouteRejectsUnexpectedCursorAudienceAndLimit() async throws {
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(
            arguments: arguments, authenticatedUserID: "user_joe"))
        await assertRejected {
            _ = try await repository.liveMapActivity(audience: .everyone, query: self.query,
                before: LiveManualPaginationUITestRepository.nextCursor, limit: 50)
        }
        await assertRejected {
            _ = try await repository.liveMapActivity(audience: .onlyFriends, query: self.query, before: nil, limit: 50)
        }
        await assertRejected {
            _ = try await repository.liveMapActivity(audience: .everyone, query: self.query, before: nil, limit: 20)
        }
    }

    func testUnexpectedCursorQueryAudienceAndLimitFailWithoutContentCallback() async throws {
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: "user_joe"))
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: self.query,
                before: LiveManualPaginationUITestRepository.nextCursor, limit: 20) { _ in XCTFail("Unexpected content") }
        }
        _ = try await repository.liveFeed(audience: .everyone, query: query, before: nil, limit: 20) { _ in }
        for cursor in ["unexpected", LiveManualPaginationUITestRepository.nextCursor] {
            let requestedQuery = cursor == "unexpected" ? query : LiveFeedQuery()
            await assertRejected {
                _ = try await repository.liveFeed(audience: .everyone, query: requestedQuery, before: cursor, limit: 20) { _ in XCTFail("Unexpected content") }
            }
        }
        await assertRejected {
            _ = try await repository.liveFeed(audience: .onlyFriends, query: self.query, before: nil, limit: 20) { _ in XCTFail("Unexpected content") }
        }
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: self.query, before: nil, limit: 21) { _ in XCTFail("Unexpected content") }
        }
        await assertRejected {
            _ = try await repository.liveFeed(audience: .everyone, query: LiveFeedQuery(activityType: .wannas), before: nil, limit: 20) { _ in XCTFail("Unexpected content") }
        }
    }

    func testLegacyFeedRequestsFailWithoutContentCallback() async throws {
        let repository = try XCTUnwrap(LiveManualPaginationUITestRepository.make(arguments: arguments, authenticatedUserID: "user_joe"))
        await assertRejected { _ = try await repository.followedFeed(before: nil, limit: 20) }
        await assertRejected {
            _ = try await repository.followedFeed(before: nil, limit: 20) { _ in XCTFail("Unexpected content") }
        }
        await assertRejected {
            _ = try await repository.activityFeed(audience: .everyone, before: nil, limit: 20) { _ in XCTFail("Unexpected content") }
        }
    }

    private func assertRejected(_ operation: @MainActor () async throws -> Void) async {
        do { try await operation(); XCTFail("Unexpected request was accepted") }
        catch LiveManualPaginationUITestRepository.FixtureError.unexpectedRequest {}
        catch { XCTFail("Unexpected error type") }
    }
}
#endif
