import XCTest
@testable import Wander

final class DiscoverParserTests: XCTestCase {
    func testLatestActivitySortsNewestFirstWithStableTieBreak() {
        let old = visiblePlace(id: "up_old", savedAt: date("2026-07-10T12:00:00Z"))
        let tieB = visiblePlace(id: "up_b", savedAt: date("2026-07-12T12:00:00Z"))
        let newest = visiblePlace(id: "up_new", savedAt: date("2026-07-13T12:00:00Z"))
        let tieA = visiblePlace(id: "up_a", savedAt: date("2026-07-12T12:00:00Z"))

        let result = DiscoverLatestActivityPresentation.places(
            from: [old, tieB, newest, tieA],
            limit: 3
        )

        XCTAssertEqual(result.map(\.id), ["up_new", "up_a", "up_b"])
    }

    func testLatestActivityDemotesImplausibleFutureDates() {
        let now = date("2026-07-13T12:00:00Z")
        let future = visiblePlace(id: "up_future", savedAt: date("2026-07-14T12:00:00Z"))
        let current = visiblePlace(id: "up_current", savedAt: date("2026-07-13T11:00:00Z"))
        let old = visiblePlace(id: "up_old", savedAt: date("2026-07-10T12:00:00Z"))

        let result = DiscoverLatestActivityPresentation.places(
            from: [future, old, current],
            relativeTo: now
        )

        XCTAssertEqual(result.map(\.id), ["up_current", "up_old", "up_future"])
    }

    func testLatestActivityFormatsSavedTimeWithoutSyntheticNowCopy() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date("2026-07-12T12:00:00Z")

        XCTAssertEqual(timestamp("2026-07-12T11:59:30Z", now: now, calendar: calendar), "just now")
        XCTAssertEqual(timestamp("2026-07-12T11:58:00Z", now: now, calendar: calendar), "2m ago")
        XCTAssertEqual(timestamp("2026-07-12T10:00:00Z", now: now, calendar: calendar), "2h ago")
        XCTAssertEqual(timestamp("2026-07-09T12:00:00Z", now: now, calendar: calendar), "3d ago")
        XCTAssertEqual(timestamp("2026-01-02T12:00:00Z", now: now, calendar: calendar), "Jan 2")
        XCTAssertEqual(timestamp("2025-12-31T12:00:00Z", now: now, calendar: calendar), "Dec 31, 2025")
        XCTAssertEqual(timestamp("2026-07-12T12:02:00Z", now: now, calendar: calendar), "just now")
        XCTAssertEqual(timestamp("2026-07-13T12:00:00Z", now: now, calendar: calendar), "Jul 13")
    }

    func testDeterministicParserMapsQueryToAllowedFiltersOnly() async throws {
        let parser = DeterministicFilterParser()
        let schema = DiscoverFilterSchema(
            allowedCategories: [WanderPlaceCategory.restaurantsFood, WanderPlaceCategory.outdoorsNature],
            allowedStatuses: [.been, .wannaGo],
            allowedRelationships: [.follower, .mutual]
        )

        let filters = try await parser.parse(query: "been hikes in LA from friends", schema: schema)

        XCTAssertEqual(filters.categories, [WanderPlaceCategory.outdoorsNature])
        XCTAssertEqual(filters.statuses, [.been])
        XCTAssertEqual(filters.relationship, .mutual)
        XCTAssertEqual(filters.area, "LA")
    }

    func testDeterministicParserMapsPossessiveNaturalLanguageSearch() async throws {
        let parser = DeterministicFilterParser()
        let schema = DiscoverFilterSchema(
            allowedCategories: [WanderPlaceCategory.coffeeTeaSweets, WanderPlaceCategory.outdoorsNature],
            allowedStatuses: [.been, .wannaGo],
            allowedRelationships: [.owner, .follower, .mutual],
            allowedTags: ["quiet", "wifi"]
        )

        let filters = try await parser.parse(query: "Joe's favorite coffee spots in LA", schema: schema)

        XCTAssertEqual(filters.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(filters.statuses, [.been])
        XCTAssertEqual(filters.ownerQuery, "joe")
        XCTAssertEqual(filters.area, "LA")
        XCTAssertEqual(filters.schemaVersion, 2)
        XCTAssertEqual(filters.opinion, .favorite)
        XCTAssertEqual(filters.sort, .ownerRatingDescending)
        XCTAssertEqual(filters.chips.map(\.title), ["Coffee, Tea, & Sweets", "check-in", "LA", "joe", "favorites"])
    }

    func testDeterministicParserFlagsUnsupportedConceptsInsteadOfPretendingToApplyThem() async throws {
        let filters = try await DeterministicFilterParser().parse(
            query: "cheap coffee open now near me",
            schema: DiscoverFilterSchema()
        )

        XCTAssertEqual(filters.resolvedUnsupportedConcepts, [.nearMe, .openNow, .price])
    }

    func testUnsupportedConceptAloneIsNotAResultProducingFacet() async throws {
        let filters = try await DeterministicFilterParser().parse(
            query: "open now near me",
            schema: DiscoverFilterSchema()
        )

        XCTAssertFalse(filters.hasRecognizedFacet)
        XCTAssertEqual(filters.resolvedUnsupportedConcepts, [.nearMe, .openNow])
    }

    func testFavoriteSynonymsShareTheSameBeenOnlyInvariant() {
        for synonym in ["favorite", "best", "loved", "highly rated"] {
            let normalized = DiscoverSemanticNormalizer.normalized(
                DiscoverFilters(
                    query: "Ryan's \(synonym) coffee spots",
                    categories: [WanderPlaceCategory.coffeeTeaSweets],
                    statuses: [.wannaGo]
                ),
                query: "Ryan's \(synonym) coffee spots"
            )

            XCTAssertEqual(normalized.opinion, .favorite, synonym)
            XCTAssertEqual(normalized.statuses, [.been], synonym)
            XCTAssertEqual(normalized.sort, .ownerRatingDescending, synonym)
        }
    }

    func testExplicitWantAndBeenPhrasesCannotRetainTheOppositeStatus() {
        let want = DiscoverSemanticNormalizer.normalized(
            DiscoverFilters(query: "coffee I want to try", statuses: [.been]),
            query: "coffee I want to try"
        )
        let been = DiscoverSemanticNormalizer.normalized(
            DiscoverFilters(query: "coffee I visited", statuses: [.wannaGo]),
            query: "coffee I visited"
        )

        XCTAssertEqual(want.statuses, [.wannaGo])
        XCTAssertEqual(been.statuses, [.been])
    }

    func testRelationshipPhrasesRepairModelOmissions() {
        let friends = DiscoverSemanticNormalizer.normalized(
            DiscoverFilters(query: "friends' sunset hikes"),
            query: "friends' sunset hikes"
        )
        let following = DiscoverSemanticNormalizer.normalized(
            DiscoverFilters(query: "coffee from people I follow"),
            query: "coffee from people I follow"
        )

        XCTAssertEqual(friends.relationship, .mutual)
        XCTAssertEqual(following.relationship, .follower)
    }

    func testApostrophelessFavoritePossessiveResolvesOwner() async throws {
        let filters = try await DeterministicFilterParser().parse(
            query: "Ryans favorite coffee spots",
            schema: DiscoverFilterSchema()
        )

        XCTAssertEqual(filters.ownerQuery, "ryan")
        XCTAssertEqual(filters.opinion, .favorite)
        XCTAssertEqual(filters.statuses, [.been])
    }

    func testSchemaV2ClientDecodesPreviousEdgeResponse() throws {
        let data = Data(
            #"""
            {
              "query":"coffee",
              "categories":["coffee_tea_sweets"],
              "area":null,
              "statuses":["been"],
              "relationship":null,
              "ownerQuery":null,
              "tags":[]
            }
            """#.utf8
        )

        let filters = try JSONDecoder().decode(DiscoverFilters.self, from: data)

        XCTAssertNil(filters.schemaVersion)
        XCTAssertNil(filters.opinion)
        XCTAssertNil(filters.sort)
        XCTAssertTrue(filters.resolvedUnsupportedConcepts.isEmpty)
    }

    private func visiblePlace(id: String, savedAt: Date) -> VisiblePlace {
        let owner = LocalProfile(
            localID: "local_maya",
            serverID: "user_maya",
            handle: "maya",
            displayName: "Maya",
            syncState: .synced
        )
        let place = LocalPlace(
            localID: "local_\(id)",
            serverID: "place_\(id)",
            canonicalName: id,
            category: "coffee",
            latitude: 34,
            longitude: -118,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_\(id)",
            serverID: id,
            userID: owner.id,
            placeID: place.id,
            status: .been,
            visibility: .followers,
            savedAt: savedAt,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(id: id, place: place, userPlace: userPlace, owner: owner)
    }

    private func timestamp(_ value: String, now: Date, calendar: Calendar) -> String {
        DiscoverLatestActivityPresentation.timestampText(
            for: date(value),
            relativeTo: now,
            calendar: calendar
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
