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
        XCTAssertEqual(filters.chips.map(\.title), ["Coffee, Tea, & Sweets", "been", "LA", "joe"])
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
