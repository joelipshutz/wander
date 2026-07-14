import XCTest
@testable import Wander

final class ProfileInsightsPresenterTests: XCTestCase {
    func testInsightsUseOwnerBeenVisitsAndExcludeWannaAndOtherUsers() throws {
        let fixture = makeFixture()
        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(insights.monthSpotCount, 2)
        XCTAssertEqual(insights.monthCategoryCount, 2)
        XCTAssertEqual(insights.monthCityCount, 2)
        XCTAssertEqual(insights.mapPoints.map(\.name), ["Bar Nido", "Woodcat Coffee"])
        XCTAssertEqual(insights.placeSummaries.map(\.title), ["Coffee, Tea, & Sweets", "Restaurants & Food"])
        XCTAssertFalse(insights.mapPoints.contains { $0.name == "Wanna Noodles" })
    }

    func testMultipleVisitsOnOneDayProduceOneDayWithCount() throws {
        let fixture = makeFixture()
        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        let day = try XCTUnwrap(fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))

        XCTAssertEqual(insights.monthVisitCounts[day], 2)
        XCTAssertEqual(insights.monthVisitCounts.count, 2)
    }

    func testTimezoneBoundaryUsesInjectedCalendar() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let place = LocalPlace(
            localID: "place",
            canonicalName: "Late Dinner",
            category: WanderPlaceCategory.restaurantsFood,
            locality: "Los Angeles",
            country: "United States",
            latitude: 34,
            longitude: -118
        )
        let userPlace = LocalUserPlace(
            localID: "up",
            userID: "owner",
            placeID: place.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let visitDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T06:30:00Z"))
        let visit = LocalPlaceVisit(localID: "visit", userPlaceID: userPlace.id, visitedAt: visitDate)
        let june = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let insights = ProfileInsightsPresenter.present(
            ownerID: "owner",
            userPlaces: [userPlace],
            visits: [visit],
            places: [place],
            month: june,
            calendar: losAngeles
        )
        let june30 = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 30)))

        XCTAssertEqual(insights.monthVisitCounts[june30], 1)
    }

    func testMissingOrInvalidPlacesAreDroppedWithoutBreakingOtherInsights() {
        let fixture = makeFixture()
        let invalid = LocalPlace(
            localID: "invalid",
            canonicalName: "Missing Pin",
            category: WanderPlaceCategory.thingsToDo,
            latitude: 0,
            longitude: 0
        )
        let invalidUserPlace = LocalUserPlace(
            localID: "up_invalid",
            userID: fixture.ownerID,
            placeID: invalid.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces + [invalidUserPlace],
            visits: fixture.visits,
            places: fixture.places + [invalid],
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(insights.mapPoints.count, 2)
        XCTAssertEqual(insights.placeSummaries.first { $0.id == WanderPlaceCategory.thingsToDo }?.count, 1)
    }

    private func makeFixture() -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let day8Morning = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 10))!
        let day8Evening = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 20))!
        let day19 = calendar.date(from: DateComponents(year: 2026, month: 6, day: 19, hour: 12))!

        let coffee = LocalPlace(
            localID: "coffee",
            canonicalName: "Woodcat Coffee",
            category: WanderPlaceCategory.coffeeTeaSweets,
            locality: "Los Angeles",
            country: "United States",
            latitude: 34.06,
            longitude: -118.24
        )
        let dinner = LocalPlace(
            localID: "dinner",
            canonicalName: "Bar Nido",
            category: WanderPlaceCategory.restaurantsFood,
            locality: "New York",
            country: "United States",
            latitude: 40.71,
            longitude: -74.0
        )
        let wanna = LocalPlace(
            localID: "wanna",
            canonicalName: "Wanna Noodles",
            category: WanderPlaceCategory.restaurantsFood,
            locality: "Tokyo",
            country: "Japan",
            latitude: 35.67,
            longitude: 139.65
        )
        let ownerCoffee = LocalUserPlace(
            localID: "up_coffee",
            userID: "owner",
            placeID: coffee.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let ownerDinner = LocalUserPlace(
            localID: "up_dinner",
            userID: "owner",
            placeID: dinner.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let ownerWanna = LocalUserPlace(
            localID: "up_wanna",
            userID: "owner",
            placeID: wanna.id,
            status: .wannaGo,
            visibility: .followers,
            sourceType: "manual"
        )
        let otherCoffee = LocalUserPlace(
            localID: "up_other",
            userID: "other",
            placeID: coffee.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let visits = [
            LocalPlaceVisit(localID: "v1", userPlaceID: ownerCoffee.id, visitedAt: day8Morning),
            LocalPlaceVisit(localID: "v2", userPlaceID: ownerCoffee.id, visitedAt: day8Evening),
            LocalPlaceVisit(localID: "v3", userPlaceID: ownerDinner.id, visitedAt: day19),
            LocalPlaceVisit(localID: "v4", userPlaceID: ownerWanna.id, visitedAt: day19),
            LocalPlaceVisit(localID: "v5", userPlaceID: otherCoffee.id, visitedAt: day19)
        ]

        return Fixture(
            ownerID: "owner",
            month: month,
            calendar: calendar,
            places: [coffee, dinner, wanna],
            userPlaces: [ownerCoffee, ownerDinner, ownerWanna, otherCoffee],
            visits: visits
        )
    }

    private struct Fixture {
        let ownerID: String
        let month: Date
        let calendar: Calendar
        let places: [LocalPlace]
        let userPlaces: [LocalUserPlace]
        let visits: [LocalPlaceVisit]
    }
}
