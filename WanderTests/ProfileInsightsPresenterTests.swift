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
        XCTAssertEqual(insights.countrySummaries.map(\.title), ["United States"])
        XCTAssertEqual(insights.countrySummaries.map(\.count), [2])
        XCTAssertEqual(
            insights.placeSummaries.first { $0.id == WanderPlaceCategory.coffeeTeaSweets }?.placeIDs,
            ["coffee"]
        )
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
        XCTAssertEqual(insights.monthPlaceIDs[day], ["coffee"])
        XCTAssertEqual(insights.monthVisitCounts.count, 2)
    }

    func testCountryCanonicalizerDeduplicatesCodesAndNames() {
        XCTAssertEqual(CountryCanonicalizer.canonicalName("US"), "United States")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("U.S."), "United States")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("USA"), "United States")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("united states"), "United States")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("UK"), "United Kingdom")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("GBR"), "United Kingdom")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("ARE"), "United Arab Emirates")
        XCTAssertEqual(CountryCanonicalizer.canonicalName("Canada"), "Canada")
    }

    func testCityInsightsDeduplicateCapitalizationVariants() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let month = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 1)))
        let visitDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 8)))
        let places = [
            LocalPlace(
                localID: "marina-lower-connector",
                canonicalName: "Marina Cafe",
                category: WanderPlaceCategory.coffeeTeaSweets,
                locality: "Marina del Rey",
                country: "US",
                latitude: 33.98,
                longitude: -118.45
            ),
            LocalPlace(
                localID: "marina-title-connector",
                canonicalName: "Marina Park",
                category: WanderPlaceCategory.thingsToDo,
                locality: "Marina Del Rey",
                country: "United States",
                latitude: 33.97,
                longitude: -118.44
            )
        ]
        let userPlaces = places.map { place in
            LocalUserPlace(
                localID: "up-\(place.localID)",
                userID: "owner",
                placeID: place.id,
                status: .been,
                visibility: .followers,
                sourceType: "manual"
            )
        }
        let visits = userPlaces.enumerated().map { index, userPlace in
            LocalPlaceVisit(
                localID: "visit-\(index)",
                userPlaceID: userPlace.id,
                visitedAt: visitDate
            )
        }

        let insights = ProfileInsightsPresenter.present(
            ownerID: "owner",
            userPlaces: userPlaces,
            visits: visits,
            places: places,
            month: month,
            calendar: calendar
        )

        XCTAssertEqual(insights.monthCityCount, 1)
        XCTAssertEqual(insights.mapCityCount, 1)
        XCTAssertEqual(insights.citySummaries.count, 1)
        XCTAssertEqual(insights.citySummaries.first?.title, "Marina del Rey")
        XCTAssertEqual(insights.citySummaries.first?.count, 2)
        XCTAssertEqual(
            insights.citySummaries.first?.placeIDs,
            ["marina-lower-connector", "marina-title-connector"]
        )
    }

    func testTimezoneBoundaryUsesInjectedCalendar() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let place = LocalPlace(
            localID: "place",
            canonicalName: "Late Dinner",
            category: WanderPlaceCategory.restaurantsFood,
            locality: "Los Angeles",
            country: "US",
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

    func testCacheReusesLastPresentationForIdenticalRelevantSnapshot() {
        let fixture = makeFixture()
        let cache = ProfileInsightsCache()

        let first = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        let second = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(second, first)
        XCTAssertEqual(cache.computationCount, 1)
    }

    func testCacheIgnoresModelFieldsThatCannotChangeInsights() {
        let fixture = makeFixture()
        let cache = ProfileInsightsCache()

        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        fixture.userPlaces[0].note = "Unrelated note change"
        fixture.visits[0].note = "Unrelated visit note change"
        fixture.places[0].address = "Unrelated address change"
        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(cache.computationCount, 1)
    }

    func testCacheInvalidatesForOwnerMonthAndCalendarChanges() {
        let fixture = makeFixture()
        let cache = ProfileInsightsCache()
        let nextMonth = fixture.calendar.date(byAdding: .month, value: 1, to: fixture.month)!
        var alternateCalendar = fixture.calendar
        alternateCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        _ = cache.present(
            ownerID: "another-owner",
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        _ = cache.present(
            ownerID: "another-owner",
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: nextMonth,
            calendar: fixture.calendar
        )
        _ = cache.present(
            ownerID: "another-owner",
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: nextMonth,
            calendar: alternateCalendar
        )

        XCTAssertEqual(cache.computationCount, 4)
    }

    func testCacheInvalidatesForEveryRelevantUserPlaceField() {
        assertCacheInvalidates("user place local ID") {
            $0.userPlaces[0].localID += "-changed"
        }
        assertCacheInvalidates("user place server ID") {
            $0.userPlaces[0].serverID = "server-user-place"
        }
        assertCacheInvalidates("user place owner") {
            $0.userPlaces[0].userID = "another-owner"
        }
        assertCacheInvalidates("user place place ID") {
            $0.userPlaces[0].placeID = "another-place"
        }
        assertCacheInvalidates("user place status") {
            $0.userPlaces[0].statusRaw = PlaceStatus.wannaGo.rawValue
        }
        assertCacheInvalidates("user place category override") {
            $0.userPlaces[0].categoryOverride = WanderPlaceCategory.thingsToDo
        }
        assertCacheInvalidates("user place deletion") {
            $0.userPlaces[0].deletedAt = Date(timeIntervalSince1970: 1)
        }
    }

    func testCacheInvalidatesForEveryRelevantVisitField() {
        assertCacheInvalidates("visit local ID") {
            $0.visits[0].localID += "-changed"
        }
        assertCacheInvalidates("visit server ID") {
            $0.visits[0].serverID = "server-visit"
        }
        assertCacheInvalidates("visit user place ID") {
            $0.visits[0].userPlaceID = "another-user-place"
        }
        assertCacheInvalidates("visit date") {
            $0.visits[0].visitedAt = $0.visits[0].visitedAt.addingTimeInterval(3_600)
        }
        assertCacheInvalidates("visit deletion") {
            $0.visits[0].deletedAt = Date(timeIntervalSince1970: 1)
        }
    }

    func testCacheInvalidatesForEveryRelevantPlaceField() {
        assertCacheInvalidates("place local ID") {
            $0.places[0].localID += "-changed"
        }
        assertCacheInvalidates("place server ID") {
            $0.places[0].serverID = "server-place"
        }
        assertCacheInvalidates("place name") {
            $0.places[0].canonicalName += " Changed"
        }
        assertCacheInvalidates("place category") {
            $0.places[0].primaryCategory = WanderPlaceCategory.thingsToDo
        }
        assertCacheInvalidates("place locality") {
            $0.places[0].locality = "Pasadena"
        }
        assertCacheInvalidates("place country") {
            $0.places[0].country = "Canada"
        }
        assertCacheInvalidates("place latitude") {
            $0.places[0].latitude += 0.01
        }
        assertCacheInvalidates("place longitude") {
            $0.places[0].longitude += 0.01
        }
    }

    private func assertCacheInvalidates(
        _ name: String,
        mutation: (Fixture) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let fixture = makeFixture()
        let cache = ProfileInsightsCache()

        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        mutation(fixture)
        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        _ = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(cache.computationCount, 2, name, file: file, line: line)
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
            country: "US",
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
