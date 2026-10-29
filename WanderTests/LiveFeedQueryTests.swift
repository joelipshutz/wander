import XCTest
@testable import Wander

@MainActor
final class LiveFeedQueryTests: XCTestCase {
    func testCommittedTimeAndTypesIncludeLegacyStatusWithoutConflatingLists() throws {
        let store = WanderStore(fixtures: .seed())
        let actor = store.shell(for: store.currentUser)
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.status == .been })
        let date = Date(timeIntervalSince1970: 1_000)
        let query = LiveFeedQuery(occurredAfter: date, occurredBefore: date.addingTimeInterval(10), activityType: .checkIns)
        XCTAssertTrue(query.includes(FeedActivity(id: "check", kind: .placeBeen, actor: actor, occurredAt: date)))
        XCTAssertTrue(query.includes(FeedActivity(id: "legacy", kind: .placeSaved, actor: actor, place: place, occurredAt: date)))
        XCTAssertFalse(query.includes(FeedActivity(id: "list", kind: .listItemAdded, actor: actor, place: place, occurredAt: date)))
        XCTAssertFalse(query.includes(FeedActivity(id: "wanna", kind: .placeWannaGo, actor: actor, place: place, occurredAt: date)))
        XCTAssertFalse(query.includes(FeedActivity(id: "old", kind: .placeBeen, actor: actor, occurredAt: date.addingTimeInterval(-1))))
        XCTAssertFalse(query.includes(FeedActivity(id: "future", kind: .placeBeen, actor: actor, occurredAt: date.addingTimeInterval(11))))
        XCTAssertTrue(LiveFeedQuery().includes(FeedActivity(id: "list", kind: .listCreated, actor: actor, occurredAt: date)))
    }

    func testListsMatchActionsRegardlessOfSourceStatusAndStayDistinctDuringExpansion() throws {
        let store = WanderStore(fixtures: .seed())
        let actor = store.shell(for: store.currentUser)
        let been = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.status == .been })
        let wanna = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.status == .wannaGo })
        let start = Date(timeIntervalSince1970: 1_000)
        let query = LiveFeedQuery(occurredAfter: start, occurredBefore: start.addingTimeInterval(10), activityType: .lists)
        let creation = FeedActivity(id: "creation", kind: .listCreated, actor: actor, occurredAt: start)
        let beenAddition = FeedActivity(id: "been-list", kind: .listItemAdded, actor: actor, place: been, occurredAt: start)
        let wannaAddition = FeedActivity(id: "wanna-list", kind: .listItemAdded, actor: actor, place: wanna, occurredAt: start)
        for activity in [creation, beenAddition, wannaAddition] {
            XCTAssertTrue(query.includes(activity))
            XCTAssertTrue(LiveActivityFilter.lists.includes(activity))
            XCTAssertFalse(LiveActivityFilter.wannas.includes(activity))
            XCTAssertFalse(LiveActivityFilter.checkIns.includes(activity))
        }
        for kind in [FeedActivityKind.placeBeen, .placeWannaGo, .placeSaved] {
            let activity = FeedActivity(id: kind.rawValue, kind: kind, actor: actor, place: wanna, occurredAt: start)
            XCTAssertFalse(query.includes(activity))
            XCTAssertFalse(LiveActivityFilter.lists.includes(activity))
            XCTAssertEqual(query.expansionStage(for: activity), .allActivity)
        }
        let oldAddition = FeedActivity(id: "old-list", kind: .listItemAdded, actor: actor, place: been,
                                       occurredAt: start.addingTimeInterval(-1))
        XCTAssertEqual(query.expansionStage(for: oldAddition), .older)
        XCTAssertEqual(query.expandedQuery(for: .older).activityType, .lists)
        XCTAssertEqual(query.expandedQuery(for: .allActivity).activityType, .all)
        XCTAssertFalse(LiveFeedQuery(activityType: .lists).includesFeatured(been),
                       "An anonymous check-in aggregate does not establish a list action")
    }

    func testPolygonMatchesBoundaryAndAntimeridianWithoutUnmappedRows() {
        let query = LiveFeedQuery(polygon: [
            .init(latitude: -1, longitude: 179), .init(latitude: -1, longitude: -179),
            .init(latitude: 1, longitude: -179), .init(latitude: 1, longitude: 179)
        ])
        XCTAssertTrue(query.isValid)
        XCTAssertTrue(query.contains(latitude: 0, longitude: 179.5))
        XCTAssertTrue(query.contains(latitude: 0, longitude: -179.5))
        XCTAssertTrue(query.contains(latitude: 1, longitude: 180))
        XCTAssertFalse(query.contains(latitude: 0, longitude: 0))
        XCTAssertFalse(query.contains(latitude: 2, longitude: 180))
        let store = WanderStore(fixtures: .seed())
        let activity = FeedActivity(id: "list", kind: .listCreated, actor: store.shell(for: store.currentUser), occurredAt: .now)
        XCTAssertFalse(query.includes(activity))
    }

    func testInvalidShapeAndTimeFailClosed() {
        XCTAssertFalse(LiveFeedQuery(polygon: []).isValid)
        XCTAssertFalse(LiveFeedQuery(polygon: [.init(latitude: .nan, longitude: 0), .init(latitude: 1, longitude: 1), .init(latitude: 0, longitude: 1)]).isValid)
        XCTAssertFalse(LiveFeedQuery(polygon: [.init(latitude: 0, longitude: 0), .init(latitude: 1, longitude: 1), .init(latitude: 2, longitude: 2)]).isValid)
        XCTAssertFalse(LiveFeedQuery(polygon: [.init(latitude: 0, longitude: 0), .init(latitude: 1, longitude: 1), .init(latitude: 0, longitude: 1), .init(latitude: 1, longitude: 0)]).isValid)
        XCTAssertFalse(LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 2), occurredBefore: Date(timeIntervalSince1970: 1)).isValid)
        XCTAssertFalse(LiveFeedQuery(polygon: Array(repeating: .init(latitude: 0, longitude: 0), count: 513)).isValid)
        let wide: [LiveFeedQuery.Vertex] = [.init(latitude: -10, longitude: 0), .init(latitude: -10, longitude: 120), .init(latitude: 10, longitude: -120)]
        for start in wide.indices {
            let rotated = Array(wide[start...]) + Array(wide[..<start])
            XCTAssertFalse(LiveFeedQuery(polygon: rotated).isValid, "A starting vertex must not choose which hemisphere is included")
        }
    }

    func testRepositorySendsCommittedFiltersAndOpaqueCursorToOnlyLiveRPC() async throws {
        let transport = LiveQueryTransport()
        let repository = SupabaseFeedRepository(rpc: transport)
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 1_234.12345),
                                  activityType: .wannas,
                                  polygon: [.init(latitude: 0, longitude: 0), .init(latitude: 1, longitude: 0), .init(latitude: 0, longitude: 1)],
                                  center: .init(latitude: 34.05, longitude: -118.24), radiusMeters: 5_000,
                                  categoryIDs: ["restaurants_food", "coffee_tea_sweets"], personIDs: ["person-b", "person-a"])
        var contentCalls = 0
        _ = try await repository.liveFeed(audience: .onlyFriends, query: query, before: "bound|timestamp|id", limit: 500) { _ in contentCalls += 1 }
        XCTAssertEqual(transport.names, ["live_activity_feed"])
        XCTAssertEqual(transport.parameters?["input_audience"] as? String, "only_friends")
        XCTAssertEqual(transport.parameters?["input_activity_type"] as? String, "wannas")
        XCTAssertEqual(transport.parameters?["input_after"] as? String, LiveFeedQuery.timestamp(query.occurredAfter))
        XCTAssertEqual(transport.parameters?["input_before"] as? String, "bound|timestamp|id")
        XCTAssertEqual(transport.parameters?["input_limit"] as? Int, 50)
        XCTAssertEqual((transport.parameters?["input_polygon"] as? [[String: Double]])?.count, 3)
        XCTAssertEqual(transport.parameters?["input_center_latitude"] as? Double, 34.05)
        XCTAssertEqual(transport.parameters?["input_center_longitude"] as? Double, -118.24)
        XCTAssertEqual(transport.parameters?["input_radius_meters"] as? Int, 5_000)
        XCTAssertEqual(transport.parameters?["input_category_ids"] as? [String], ["coffee_tea_sweets", "restaurants_food"])
        XCTAssertEqual(transport.parameters?["input_person_ids"] as? [String], ["person-a", "person-b"])
        XCTAssertEqual(contentCalls, 1)
    }

    func testChildFiltersReachTheServerForFeedAndMapBeforePagination() async throws {
        let transport = LiveQueryTransport()
        let repository = SupabaseFeedRepository(rpc: transport)
        let query = LiveFeedQuery(categoryIDs: [WanderPlaceCategory.coffeeTeaSweets],
            categoryOptions: [WanderPlaceCategory.restaurantsFood: ["italian", "mexican"],
                              WanderPlaceCategory.outdoorsNature: ["park"]])
        _ = try await repository.liveFeed(audience: .everyone, query: query, before: "cursor", limit: 2) { _ in }
        XCTAssertEqual(transport.names.last, "live_activity_feed_category_options")
        XCTAssertEqual(transport.parameters?["input_category_options"] as? [String: [String]],
            [WanderPlaceCategory.restaurantsFood: ["italian", "mexican"], WanderPlaceCategory.outdoorsNature: ["park"]])
        XCTAssertEqual(transport.parameters?["input_category_ids"] as? [String], [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(transport.parameters?["input_before"] as? String, "cursor")
        _ = try await repository.liveMapActivity(audience: .everyone, query: query, before: "next", limit: 2)
        XCTAssertEqual(transport.names.last, "live_activity_feed_category_options")
        XCTAssertEqual(transport.parameters?["input_before"] as? String, "next")
        XCTAssertEqual(transport.parameters?["input_category_options"] as? [String: [String]],
            query.categoryOptions.mapValues { $0.sorted() })
    }

    func testListsFeedAndMapKeepCommittedFiltersAcrossOpaqueCursorPages() async throws {
        let transport = LiveQueryTransport()
        transport.nextCursors = ["feed|timestamp|id", nil, "map|timestamp|id", nil]
        let repository = SupabaseFeedRepository(rpc: transport)
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 1_000),
            occurredBefore: Date(timeIntervalSince1970: 2_000), activityType: .lists,
            center: .init(latitude: 34.05, longitude: -118.24), radiusMeters: 10_000,
            categoryIDs: ["restaurants_food"], personIDs: ["selected-person"])
        let firstFeedPage = try await repository.liveFeed(audience: .onlyFriends, query: query,
            before: nil, limit: 2, onContent: { _ in })
        let lastFeedPage = try await repository.liveFeed(audience: .onlyFriends, query: query,
            before: firstFeedPage.nextCursor, limit: 2, onContent: { _ in })
        let firstMapPage = try await repository.liveMapActivity(audience: .onlyFriends, query: query, before: nil, limit: 2)
        let lastMapPage = try await repository.liveMapActivity(audience: .onlyFriends, query: query,
            before: firstMapPage.nextCursor, limit: 2)
        XCTAssertEqual(firstFeedPage.nextCursor, "feed|timestamp|id")
        XCTAssertEqual(firstMapPage.nextCursor, "map|timestamp|id")
        XCTAssertNil(lastFeedPage.nextCursor)
        XCTAssertNil(lastMapPage.nextCursor)
        XCTAssertEqual(transport.names, Array(repeating: "live_activity_feed", count: 4))
        XCTAssertEqual(transport.parameterHistory.map { $0["input_before"] as? String },
                       [nil, "feed|timestamp|id", nil, "map|timestamp|id"])
        for parameters in transport.parameterHistory {
            XCTAssertEqual(parameters["input_activity_type"] as? String, "lists")
            XCTAssertEqual(parameters["input_audience"] as? String, "only_friends")
            XCTAssertEqual(parameters["input_after"] as? String, LiveFeedQuery.timestamp(query.occurredAfter))
            XCTAssertEqual(parameters["input_until"] as? String, LiveFeedQuery.timestamp(query.occurredBefore))
            XCTAssertEqual(parameters["input_limit"] as? Int, 2)
            XCTAssertEqual(parameters["input_radius_meters"] as? Int, 10_000)
            XCTAssertEqual(parameters["input_person_ids"] as? [String], ["selected-person"])
            XCTAssertEqual(parameters["input_category_ids"] as? [String], ["restaurants_food"])
        }
    }

    func testRadiusRequiresCompleteFiniteBoundedCenterAndFilterArraysAreBounded() {
        let center = LiveFeedQuery.Vertex(latitude: 34, longitude: -118)
        XCTAssertFalse(LiveFeedQuery(center: center).isValid)
        XCTAssertFalse(LiveFeedQuery(radiusMeters: 5_000).isValid)
        XCTAssertFalse(LiveFeedQuery(center: .init(latitude: .nan, longitude: -118), radiusMeters: 5_000).isValid)
        XCTAssertFalse(LiveFeedQuery(center: center, radiusMeters: 99).isValid)
        XCTAssertFalse(LiveFeedQuery(center: center, radiusMeters: 25_001).isValid)
        XCTAssertTrue(LiveFeedQuery(center: center, radiusMeters: 100).isValid)
        XCTAssertTrue(LiveFeedQuery(center: center, radiusMeters: 25_000).isValid)
        XCTAssertFalse(LiveFeedQuery(personIDs: [" "]).isValid)
        XCTAssertFalse(LiveFeedQuery(personIDs: Set((0...100).map(String.init))).isValid)
    }

    func testRadiusPolygonPersonAndCanonicalViewerCategoryIntersect() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        place.userPlace.viewerPrimaryCategory = WanderPlaceCategory.coffeeTeaSweets
        place.userPlace.categoryOverride = WanderPlaceCategory.restaurantsFood
        let coordinate = LiveFeedQuery.Vertex(latitude: place.place.latitude, longitude: place.place.longitude)
        let query = LiveFeedQuery(center: coordinate, radiusMeters: 100,
            categoryIDs: [WanderPlaceCategory.coffeeTeaSweets], personIDs: [store.currentUser.id])
        let event = FeedActivity(id: "matching", kind: .placeBeen, actor: store.shell(for: store.currentUser),
                                 place: place, occurredAt: .now)
        XCTAssertTrue(query.includes(event), "Use canonical viewer taxonomy, not an actor/provider override")
        XCTAssertFalse(LiveFeedQuery(center: .init(latitude: 0, longitude: 0), radiusMeters: 100).includes(event))
        XCTAssertFalse(LiveFeedQuery(personIDs: ["another-person"]).includes(event))
        let polygon = [LiveFeedQuery.Vertex(latitude: -1, longitude: -1), .init(latitude: -1, longitude: 1),
                       .init(latitude: 1, longitude: 1), .init(latitude: 1, longitude: -1)]
        XCTAssertFalse(LiveFeedQuery(polygon: polygon, center: coordinate, radiusMeters: 100).includes(event))
        XCTAssertFalse(query.includes(FeedActivity(id: "unmapped", kind: .listCreated,
            actor: store.shell(for: store.currentUser), occurredAt: .now)))
    }

    func testOlderExpansionPreservesEveryDiscoveryFilterAndAnInclusiveWindowBoundary() {
        let query = LiveFeedQuery(occurredAfter: Date(timeIntervalSince1970: 100),
            occurredBefore: Date(timeIntervalSince1970: 200), activityType: .wannas,
            polygon: [.init(latitude: 0, longitude: 0), .init(latitude: 1, longitude: 0), .init(latitude: 0, longitude: 1)],
            center: .init(latitude: 0, longitude: 0), radiusMeters: 10_000,
            categoryIDs: ["restaurants_food"], personIDs: ["selected-person"])
        let older = query.expandedQuery(for: .older)
        XCTAssertNil(older.occurredAfter)
        XCTAssertEqual(older.occurredBefore, query.occurredAfter)
        XCTAssertEqual(older.activityType, query.activityType)
        XCTAssertEqual(older.polygon, query.polygon)
        XCTAssertEqual(older.center, query.center)
        XCTAssertEqual(older.radiusMeters, query.radiusMeters)
        XCTAssertEqual(older.categoryIDs, query.categoryIDs)
        XCTAssertEqual(older.personIDs, query.personIDs)
        let all = query.expandedQuery(for: .allActivity)
        XCTAssertEqual(all.occurredBefore, query.occurredBefore)
        XCTAssertNil(all.occurredAfter)
        XCTAssertFalse(all.hasDiscoveryFilters)
        XCTAssertEqual(query.nextExpansion(after: .selected), .older)
        XCTAssertEqual(query.nextExpansion(after: .older), .allActivity)
        XCTAssertNil(query.nextExpansion(after: .allActivity))
    }

    func testExpansionDoesNotSkipSubmillisecondActivityAtTheWindowBoundary() {
        let store = WanderStore(fixtures: .seed())
        let actor = store.shell(for: store.currentUser)
        let boundary = Date(timeIntervalSince1970: 100)
        let query = LiveFeedQuery(occurredAfter: boundary)
        let justBefore = FeedActivity(id: "fractional", kind: .placeBeen, actor: actor,
                                      occurredAt: boundary.addingTimeInterval(-0.0005))
        let exact = FeedActivity(id: "boundary", kind: .placeBeen, actor: actor, occurredAt: boundary)
        XCTAssertFalse(query.includes(justBefore))
        XCTAssertTrue(query.expandedQuery(for: .older).includes(justBefore))
        XCTAssertEqual(query.expansionStage(for: justBefore), .older)
        XCTAssertTrue(query.expandedQuery(for: .older).includes(exact))
        XCTAssertEqual(query.expansionStage(for: exact), .selected,
                       "The overlapping boundary remains in the selected section")
    }

    func testMissingLiveRPCAndLegacyRepositoryCannotFallBackToLoadedPageFiltering() async {
        let transport = LiveQueryTransport()
        transport.failure = WanderRemoteError.invalidResponse("PGRST202 live_activity_feed")
        let repository = SupabaseFeedRepository(rpc: transport)
        do {
            _ = try await repository.liveFeed(audience: .everyone, query: LiveFeedQuery(), before: nil, limit: 20, onContent: { _ in XCTFail() })
            XCTFail("Missing Live RPC must fail visibly")
        } catch { XCTAssertEqual(error as? WanderRemoteError, transport.failure) }
        XCTAssertEqual(transport.names, ["live_activity_feed"])
        let legacy = LegacyOnlyLiveQueryRepository()
        do {
            _ = try await legacy.liveFeed(audience: .everyone, query: LiveFeedQuery(), before: nil, limit: 20, onContent: { _ in XCTFail() })
            XCTFail("Legacy repository must not silently filter a loaded page")
        } catch { XCTAssertEqual(error as? WanderRemoteError, .notImplemented("Live feed query")) }
        XCTAssertEqual(legacy.callCount, 0)
    }
}

@MainActor private final class LiveQueryTransport: RemoteProcedureCalling {
    var names: [String] = []
    var parameters: [String: Any]?
    var parameterHistory: [[String: Any]] = []
    var nextCursors: [String?] = []
    var failure: WanderRemoteError?
    func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params, decoder: JSONDecoder) async throws -> Value {
        names.append(name)
        parameters = try JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any]
        if let parameters { parameterHistory.append(parameters) }
        if let failure { throw failure }
        let cursor = nextCursors.isEmpty ? nil : nextCursors.removeFirst()
        let response: [String: Any] = ["activity": [], "featured_places": [],
            "next_cursor": cursor as Any? ?? NSNull(), "fetched_at": "2026-10-10T00:00:00Z"]
        return try decoder.decode(Value.self, from: JSONSerialization.data(withJSONObject: response))
    }
}

@MainActor private final class LegacyOnlyLiveQueryRepository: FeedRepository {
    var callCount = 0
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        callCount += 1
        return FollowedFeedPage(activity: [], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
    }
}
