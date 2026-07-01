import XCTest
@testable import Wander

final class DiscoverParserTests: XCTestCase {
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
        XCTAssertEqual(filters.chips.map(\.title), ["Coffee, Tea, & Sweets", "been", "LA", "joe"])
    }
}
