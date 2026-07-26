import MapKit
import XCTest
@testable import Wander

final class ProfileInsightsPresenterTests: XCTestCase {
    func testInsightsKeepMapAndCalendarBeenOnly() throws {
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
        XCTAssertEqual(insights.mapPlaceCount, 2)
        XCTAssertEqual(insights.mapCityCount, 2)
        XCTAssertEqual(insights.mapPoints.map(\.name), ["Bar Nido", "Woodcat Coffee"])
        XCTAssertEqual(insights.placeSummaries.map(\.title), ["Coffee, Tea, & Sweets", "Restaurants & Food"])
        XCTAssertEqual(insights.countrySummaries.map(\.title), ["United States"])
        XCTAssertEqual(insights.countrySummaries.map(\.count), [2])
        XCTAssertEqual(
            insights.placeSummaries.first { $0.id == WanderPlaceCategory.coffeeTeaSweets }?.placeIDs,
            ["coffee"]
        )
        let coffeeSummary = try XCTUnwrap(
            insights.placeSummaries.first { $0.id == WanderPlaceCategory.coffeeTeaSweets }
        )
        XCTAssertEqual(insights.mapPoints(matching: coffeeSummary).map(\.name), ["Woodcat Coffee"])
        XCTAssertFalse(insights.mapPoints.contains { $0.name == "Wanna Noodles" })
        XCTAssertEqual(insights.monthVisitCount, 3)
        XCTAssertEqual(insights.monthWannaCount, 0)

        let day19 = try XCTUnwrap(
            fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 19))
        )
        let daySummary = try XCTUnwrap(insights.monthDaySummaries[day19])
        XCTAssertEqual(daySummary.state, .visit)
        XCTAssertEqual(daySummary.visitCount, 1)
        XCTAssertEqual(daySummary.wannaCount, 0)
        XCTAssertEqual(daySummary.visitPlaceIDs, ["dinner"])
        XCTAssertTrue(daySummary.wannaPlaceIDs.isEmpty)
        XCTAssertEqual(daySummary.placeIDs, ["dinner"])
    }

    func testMapTotalsIncludeResolvedBeenPlacesAndCitiesWithoutMappableCoordinates() {
        let fixture = makeFixture()
        fixture.places[0].latitude = 0
        fixture.places[0].longitude = 0

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(insights.mapPlaceCount, 2)
        XCTAssertEqual(insights.mapCityCount, 2)
        XCTAssertEqual(insights.citySummaries.map(\.title).sorted(), ["Los Angeles", "New York"])
        XCTAssertEqual(insights.mapPoints.map(\.name), ["Bar Nido"])
    }

    func testCalendarDaySummariesCountRepeatedOwnerVisitsAndExcludeWanna() throws {
        let fixture = makeFixture()
        let day = try XCTUnwrap(fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let laterThatDay = try XCTUnwrap(
            fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 21))
        )
        fixture.visits[2].visitedAt = laterThatDay
        fixture.visits[3].visitedAt = laterThatDay
        fixture.visits[4].visitedAt = laterThatDay

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(insights.monthVisitCounts[day], 3)
        XCTAssertEqual(insights.monthPlaceIDs[day], ["coffee", "dinner"])
        XCTAssertEqual(insights.monthVisitCounts.count, 1)
        XCTAssertEqual(insights.monthWannaCount, 0)
        XCTAssertTrue(insights.monthWannaCounts.isEmpty)
    }

    func testCalendarActivityStateAndPlacesIgnoreWannaInputs() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProfileCalendarDaySummary.empty(on: date).state, .none)
        XCTAssertEqual(
            ProfileCalendarDaySummary(
                date: date,
                visitCount: 1,
                wannaCount: 0,
                visitPlaceIDs: ["visit"],
                wannaPlaceIDs: []
            ).state,
            .visit
        )
        let wannaOnly = ProfileCalendarDaySummary(
            date: date,
            visitCount: 0,
            wannaCount: 1,
            visitPlaceIDs: [],
            wannaPlaceIDs: ["wanna"]
        )
        XCTAssertEqual(wannaOnly.state, .none)
        XCTAssertTrue(wannaOnly.placeIDs.isEmpty)

        let mixed = ProfileCalendarDaySummary(
            date: date,
            visitCount: 2,
            wannaCount: 3,
            visitPlaceIDs: ["shared", "visit"],
            wannaPlaceIDs: ["wanna", "shared"]
        )
        XCTAssertEqual(mixed.state, .visit)
        XCTAssertEqual(mixed.placeIDs, ["shared", "visit"])
    }

    func testCalendarExcludesHistoricalWannaAndKeepsVisitDay() throws {
        let fixture = makeFixture()
        let wantedDay = try XCTUnwrap(
            fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 4, hour: 9))
        )
        let visitedDay = try XCTUnwrap(
            fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 22, hour: 19))
        )
        let converted = fixture.userPlaces[0]
        converted.historicalWantedAt = wantedDay
        fixture.visits[0].visitedAt = visitedDay
        fixture.visits[1].deletedAt = visitedDay

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )
        let wantedDate = fixture.calendar.startOfDay(for: wantedDay)
        let visitedDate = fixture.calendar.startOfDay(for: visitedDay)

        XCTAssertNil(insights.monthDaySummaries[wantedDate])
        XCTAssertEqual(insights.monthDaySummaries[visitedDate]?.state, .visit)
        XCTAssertEqual(insights.monthDaySummaries[visitedDate]?.visitPlaceIDs, ["coffee"])
    }

    func testCalendarExcludesAllWannaSaves() throws {
        let fixture = makeFixture()
        let day = try XCTUnwrap(
            fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 25, hour: 10))
        )
        let otherWanna = LocalUserPlace(
            localID: "other-wanna",
            userID: "other",
            placeID: fixture.places[0].id,
            status: .wannaGo,
            visibility: .followers,
            savedAt: day,
            sourceType: "manual"
        )
        let deletedWanna = LocalUserPlace(
            localID: "deleted-wanna",
            userID: fixture.ownerID,
            placeID: fixture.places[1].id,
            status: .wannaGo,
            visibility: .followers,
            savedAt: day,
            sourceType: "manual",
            deletedAt: day
        )

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces + [otherWanna, deletedWanna],
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertNil(insights.monthDaySummaries[fixture.calendar.startOfDay(for: day)])
        XCTAssertEqual(insights.monthWannaCount, 0)
        XCTAssertTrue(insights.monthWannaCounts.isEmpty)
    }

    func testCalendarDateBadgesCanonicalizePlaceAliasesAndRetainMissingPlaceReferences() throws {
        let fixture = makeFixture()
        let day = try XCTUnwrap(fixture.calendar.date(from: DateComponents(year: 2026, month: 6, day: 8)))
        let canonicalPlace = LocalPlace(
            localID: "local-place",
            serverID: "server-place",
            canonicalName: "Canonical Place",
            category: WanderPlaceCategory.restaurantsFood,
            latitude: 34,
            longitude: -118
        )
        let localAlias = LocalUserPlace(
            localID: "local-alias-save",
            userID: fixture.ownerID,
            placeID: canonicalPlace.localID,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let serverAlias = LocalUserPlace(
            localID: "server-alias-save",
            userID: fixture.ownerID,
            placeID: canonicalPlace.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let missingPlace = LocalUserPlace(
            localID: "missing-place-save",
            userID: fixture.ownerID,
            placeID: "missing-place",
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let visits = [
            LocalPlaceVisit(localID: "local-alias-visit", userPlaceID: localAlias.id, visitedAt: day),
            LocalPlaceVisit(localID: "server-alias-visit", userPlaceID: serverAlias.id, visitedAt: day),
            LocalPlaceVisit(localID: "missing-place-visit", userPlaceID: missingPlace.id, visitedAt: day)
        ]

        let insights = ProfileInsightsPresenter.present(
            ownerID: fixture.ownerID,
            userPlaces: [localAlias, serverAlias, missingPlace],
            visits: visits,
            places: [canonicalPlace],
            month: fixture.month,
            calendar: fixture.calendar
        )

        XCTAssertEqual(insights.monthVisitCounts[day], 3)
        XCTAssertEqual(insights.monthPlaceIDs[day], ["missing-place", "server-place"])
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

    func testWannaTimezoneBoundaryDoesNotCreateCalendarActivity() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let place = LocalPlace(
            localID: "place",
            canonicalName: "Late Save",
            category: WanderPlaceCategory.restaurantsFood,
            locality: "Los Angeles",
            country: "US",
            latitude: 34,
            longitude: -118
        )
        let savedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T06:30:00Z"))
        let userPlace = LocalUserPlace(
            localID: "up",
            userID: "owner",
            placeID: place.id,
            status: .wannaGo,
            visibility: .followers,
            savedAt: savedAt,
            sourceType: "manual"
        )
        let june = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let insights = ProfileInsightsPresenter.present(
            ownerID: "owner",
            userPlaces: [userPlace],
            visits: [],
            places: [place],
            month: june,
            calendar: losAngeles
        )
        let june30 = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 6, day: 30)))

        XCTAssertTrue(insights.monthWannaCounts.isEmpty)
        XCTAssertNil(insights.monthDaySummaries[june30])
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

    func testCacheUsesExplicitStoreRevisionWithoutRescanningModelFields() {
        let fixture = makeFixture()
        let cache = ProfileInsightsCache()

        let first = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar,
            dataRevision: 41
        )
        let changedPlaceID = fixture.places[0].id
        fixture.places[0].canonicalName = "Changed behind the same revision"
        let sameRevision = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar,
            dataRevision: 41
        )
        let nextRevision = cache.present(
            ownerID: fixture.ownerID,
            userPlaces: fixture.userPlaces,
            visits: fixture.visits,
            places: fixture.places,
            month: fixture.month,
            calendar: fixture.calendar,
            dataRevision: 42
        )

        XCTAssertEqual(sameRevision, first)
        XCTAssertEqual(cache.computationCount, 2)
        XCTAssertNotEqual(
            nextRevision.mapPoints.first(where: { $0.id == changedPlaceID })?.name,
            first.mapPoints.first(where: { $0.id == changedPlaceID })?.name
        )
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
        assertCacheInvalidates("user place saved date") {
            $0.userPlaces[0].savedAt = $0.userPlaces[0].savedAt.addingTimeInterval(3_600)
        }
        assertCacheInvalidates("user place historical wanted date") {
            $0.userPlaces[0].historicalWantedAt = Date(timeIntervalSince1970: 1)
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
            savedAt: day19,
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

final class ProfilePlaceCollectionMapTests: XCTestCase {
    func testMapSummaryAndCalendarRoutesOptIntoInteractiveMap() {
        let summary = ProfileSummaryItem(
            id: "united-states",
            title: "United States",
            count: 2,
            total: 2,
            placeIDs: ["coffee", "dinner"]
        )
        let calendarSummary = ProfileCalendarDaySummary(
            date: Date(timeIntervalSince1970: 0),
            visitCount: 2,
            wannaCount: 1,
            visitPlaceIDs: ["coffee", "shared"],
            wannaPlaceIDs: ["dinner", "shared"]
        )

        let mapRoute = ProfilePlaceCollectionRoute.mapSummary(kind: .countries, item: summary)
        let calendarRoute = ProfilePlaceCollectionRoute.calendar(calendarSummary)

        XCTAssertEqual(mapRoute.source, .mapSummary)
        XCTAssertTrue(mapRoute.source.presentsInteractiveMap)
        XCTAssertFalse(mapRoute.includesAllStatuses)
        XCTAssertEqual(calendarRoute.source, .calendar)
        XCTAssertTrue(calendarRoute.source.presentsInteractiveMap)
        XCTAssertFalse(calendarRoute.includesAllStatuses)
        XCTAssertEqual(calendarRoute.placeIDs, ["coffee", "shared"])
        XCTAssertEqual(calendarRoute.calendarDay, calendarSummary)
    }

    func testCollectionMatcherAcceptsCanonicalLocalAndServerPlaceIDs() {
        let owner = profile(id: "owner")
        let visiblePlace = visiblePlace(
            owner: owner,
            userPlaceID: "saved-place",
            placeLocalID: "local-place",
            placeServerID: "server-place",
            name: "Woodcat Coffee",
            latitude: 34.06,
            longitude: -118.24,
            status: .been
        )

        XCTAssertTrue(
            ProfilePlaceCollectionMatcher.matches(
                visiblePlace,
                acceptedPlaceIDs: [visiblePlace.place.id]
            )
        )
        XCTAssertTrue(
            ProfilePlaceCollectionMatcher.matches(
                visiblePlace,
                acceptedPlaceIDs: ["local-place"]
            )
        )
        XCTAssertTrue(
            ProfilePlaceCollectionMatcher.matches(
                visiblePlace,
                acceptedPlaceIDs: ["server-place"]
            )
        )
        XCTAssertFalse(
            ProfilePlaceCollectionMatcher.matches(
                visiblePlace,
                acceptedPlaceIDs: ["another-place"]
            )
        )
    }

    func testProjectionGroupsDuplicateSavesAndKeepsInvalidPlaceInTotalCount() throws {
        let currentUser = profile(id: "current")
        let friend = profile(id: "friend")
        let currentSave = visiblePlace(
            owner: currentUser,
            userPlaceID: "current-save",
            placeLocalID: "current-mutsu",
            placeServerID: "server-current-mutsu",
            name: "Mutsu",
            address: "123 Main Street",
            latitude: 34.05,
            longitude: -118.25,
            status: .been
        )
        let socialSave = visiblePlace(
            owner: friend,
            userPlaceID: "friend-save",
            placeLocalID: "friend-mutsu",
            placeServerID: "server-friend-mutsu",
            name: "Mutsu",
            address: "123 Main Street",
            latitude: 34.0502,
            longitude: -118.2502,
            status: .wannaGo
        )
        let invalidSave = visiblePlace(
            owner: currentUser,
            userPlaceID: "invalid-save",
            placeLocalID: "invalid-place",
            placeServerID: nil,
            name: "Missing Pin",
            latitude: 0,
            longitude: 0,
            status: .been
        )

        let presentation = ProfilePlaceCollectionMapProjection.presentation(
            for: [socialSave, invalidSave, currentSave],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(presentation.totalCount, 2)
        XCTAssertEqual(presentation.items.count, 1)
        XCTAssertEqual(presentation.contentState, .partial(mapped: 1, total: 2))

        let item = try XCTUnwrap(presentation.items.first)
        XCTAssertEqual(item.visiblePlace.id, currentSave.id)
        XCTAssertEqual(item.outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(item.outlines.map(\.status), [.been, .wannaGo])
        XCTAssertTrue(item.accessibilityLabel.contains("Your and social saved place"))
        XCTAssertTrue(item.accessibilityLabel.contains("Mutsu"))
        XCTAssertNotNil(presentation.fittedRegion)
    }

    func testProjectionTreatsNearZeroAndInvalidCoordinatesAsUnmapped() {
        let owner = profile(id: "owner")
        let nearZero = visiblePlace(
            owner: owner,
            userPlaceID: "near-zero-save",
            placeLocalID: "near-zero-place",
            placeServerID: nil,
            name: "Near Zero",
            latitude: 0.000_000_1,
            longitude: -0.000_000_1,
            status: .been
        )
        let invalid = visiblePlace(
            owner: owner,
            userPlaceID: "invalid-save",
            placeLocalID: "invalid-place",
            placeServerID: nil,
            name: "Invalid",
            latitude: 91,
            longitude: 181,
            status: .been
        )

        let presentation = ProfilePlaceCollectionMapProjection.presentation(
            for: [nearZero, invalid],
            currentUserID: owner.id
        )

        XCTAssertEqual(presentation.totalCount, 2)
        XCTAssertTrue(presentation.items.isEmpty)
        XCTAssertEqual(presentation.contentState, .unresolved(total: 2))
        XCTAssertNil(presentation.fittedRegion)
    }

    func testNineHundredAnnotationClusteringStaysWithinDebugBudget() throws {
        let coordinates = (0..<900).map { index in
            let row = index / 30
            let column = index % 30
            return ListMapCoordinate(
                id: "place-\(index)",
                coordinate: CLLocationCoordinate2D(
                    latitude: 25 + Double(row) * 0.7,
                    longitude: -124 + Double(column) * 2
                )
            )
        }
        let region = try XCTUnwrap(
            MapRegionFitter.region(
                fitting: coordinates.map(\.coordinate),
                minimumSpan: 0.012,
                paddingMultiplier: 1.65
            )
        )

        let start = CFAbsoluteTimeGetCurrent()
        let clusters = ProfilePlaceCollectionMapClusterer.clusters(
            for: coordinates,
            in: region,
            viewportSize: CGSize(width: 390, height: 280)
        )
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(clusters.flatMap(\.memberIDs).count, 900)
        XCTAssertEqual(Set(clusters.flatMap(\.memberIDs)).count, 900)
        XCTAssertGreaterThan(clusters.count, 1)
        XCTAssertLessThan(clusters.map(\.memberIDs.count).max() ?? 900, 900)

        let memberCoordinates = Dictionary(uniqueKeysWithValues: coordinates.map { ($0.id, $0.coordinate) })
        let largestCluster = try XCTUnwrap(clusters.max { $0.memberIDs.count < $1.memberIDs.count })
        let zoomRegion = try XCTUnwrap(
            MapRegionFitter.region(
                fitting: largestCluster.memberIDs.compactMap { memberCoordinates[$0] },
                minimumSpan: 0.0015,
                paddingMultiplier: 1.75
            )
        )
        XCTAssertLessThan(zoomRegion.span.latitudeDelta, region.span.latitudeDelta)
        XCTAssertLessThan(zoomRegion.span.longitudeDelta, region.span.longitudeDelta)
        XCTAssertLessThan(
            elapsed,
            0.25,
            "Clustering 900 annotations took \(elapsed)s; REC-111 caches this work but camera-end updates must stay responsive"
        )
    }

    func testClusteringCrossesGridBoundariesWithoutJoiningTransitiveChains() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 10, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 100, longitudeDelta: 100)
        )
        let viewport = CGSize(width: 100, height: 100)
        let boundaryCoordinates = [
            ListMapCoordinate(
                id: "left",
                coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 1)
            ),
            ListMapCoordinate(
                id: "right",
                coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 3)
            )
        ]

        let boundaryClusters = ProfilePlaceCollectionMapClusterer.clusters(
            for: boundaryCoordinates,
            in: region,
            viewportSize: viewport
        )

        XCTAssertEqual(boundaryClusters.count, 1)
        XCTAssertEqual(boundaryClusters[0].memberIDs, ["left", "right"])

        let chainCoordinates = [
            ListMapCoordinate(
                id: "a",
                coordinate: CLLocationCoordinate2D(latitude: 10, longitude: -40)
            ),
            ListMapCoordinate(
                id: "b",
                coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10)
            ),
            ListMapCoordinate(
                id: "c",
                coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 60)
            )
        ]

        let chainClusters = ProfilePlaceCollectionMapClusterer.clusters(
            for: chainCoordinates,
            in: region,
            viewportSize: viewport
        )

        XCTAssertEqual(chainClusters.map(\.memberIDs), [["a", "b"], ["c"]])
        XCTAssertEqual(chainClusters.map(\.longitude), [-40, 60])
    }

    func testCameraFitAccountsForWideMapViewport() {
        let baseRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 38, longitude: -150),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 300)
        )

        let fittedRegion = ProfilePlaceCollectionMapCamera.region(
            fitting: baseRegion,
            viewportSize: CGSize(width: 390, height: 280)
        )

        XCTAssertEqual(fittedRegion.span.latitudeDelta, 180, accuracy: 0.000_001)
        XCTAssertEqual(fittedRegion.span.longitudeDelta, 300, accuracy: 0.000_001)
        XCTAssertEqual(fittedRegion.center.latitude, 0, accuracy: 0.000_001)
    }

    func testClusterActivationZoomsDistinctCoordinatesAndOpensUnseparablePlaces() {
        let distinctCluster = ListMapCluster(
            id: "a|b",
            memberIDs: ["a", "b"],
            latitude: 34,
            longitude: -118
        )
        let distinctCoordinates = [
            "a": ListMapCoordinate(
                id: "a",
                coordinate: CLLocationCoordinate2D(latitude: 34, longitude: -118)
            ),
            "b": ListMapCoordinate(
                id: "b",
                coordinate: CLLocationCoordinate2D(latitude: 37, longitude: -122)
            )
        ]
        XCTAssertEqual(
            ProfilePlaceCollectionMapClusterActivationResolver.activation(
                for: distinctCluster,
                coordinatesByID: distinctCoordinates,
                visibleRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 35.5, longitude: -120),
                    span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
                ),
                viewportSize: CGSize(width: 390, height: 280)
            ),
            .zoom
        )

        let coincidentCoordinates = [
            "a": ListMapCoordinate(
                id: "a",
                coordinate: CLLocationCoordinate2D(latitude: 34, longitude: -118)
            ),
            "b": ListMapCoordinate(
                id: "b",
                coordinate: CLLocationCoordinate2D(latitude: 34, longitude: -118)
            )
        ]
        XCTAssertEqual(
            ProfilePlaceCollectionMapClusterActivationResolver.activation(
                for: distinctCluster,
                coordinatesByID: coincidentCoordinates,
                visibleRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
                    span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
                ),
                viewportSize: CGSize(width: 390, height: 280)
            ),
            .open("a")
        )

        let nearCoincidentCoordinates = [
            "a": ListMapCoordinate(
                id: "a",
                coordinate: CLLocationCoordinate2D(latitude: 34, longitude: -118)
            ),
            "b": ListMapCoordinate(
                id: "b",
                coordinate: CLLocationCoordinate2D(latitude: 34.000_01, longitude: -118.000_01)
            )
        ]
        XCTAssertEqual(
            ProfilePlaceCollectionMapClusterActivationResolver.activation(
                for: distinctCluster,
                coordinatesByID: nearCoincidentCoordinates,
                visibleRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
                    span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0021)
                ),
                viewportSize: CGSize(width: 390, height: 280)
            ),
            .open("a")
        )

        let highLatitudeCoordinates = [
            "a": ListMapCoordinate(
                id: "a",
                coordinate: CLLocationCoordinate2D(latitude: 60, longitude: 10)
            ),
            "b": ListMapCoordinate(
                id: "b",
                coordinate: CLLocationCoordinate2D(latitude: 60.000_01, longitude: 10.000_01)
            )
        ]
        XCTAssertEqual(
            ProfilePlaceCollectionMapClusterActivationResolver.activation(
                for: distinctCluster,
                coordinatesByID: highLatitudeCoordinates,
                visibleRegion: MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 60, longitude: 10),
                    span: MKCoordinateSpan(latitudeDelta: 0.0015, longitudeDelta: 0.0042)
                ),
                viewportSize: CGSize(width: 390, height: 280)
            ),
            .open("a")
        )
    }

    func testUnseparableClusterAccessibilityNamesTheOpenedPlace() {
        let accessibility = ProfilePlaceCollectionMapClusterAccessibility.presentation(
            count: 3,
            activation: .open("a"),
            destinationName: "Mutsu"
        )

        XCTAssertEqual(accessibility.label, "Mutsu, one of 3 saved places at this location")
        XCTAssertEqual(
            accessibility.hint,
            "Shows Mutsu details. Every place remains in the list below."
        )
    }

    func testCameraLifecycleReappliesOverviewAfterAvailabilityCycle() {
        var lifecycle = ProfilePlaceCollectionMapCameraLifecycle(hasOverviewRegion: true)

        XCTAssertFalse(lifecycle.reconcileOverview(isAvailable: true))
        XCTAssertFalse(lifecycle.hasAppliedViewportFit)
        lifecycle.markViewportFitApplied()
        XCTAssertTrue(lifecycle.hasAppliedViewportFit)

        XCTAssertFalse(lifecycle.reconcileOverview(isAvailable: false))
        XCTAssertFalse(lifecycle.hasAppliedOverviewRegion)
        XCTAssertFalse(lifecycle.hasAppliedViewportFit)

        XCTAssertTrue(lifecycle.reconcileOverview(isAvailable: true))
        XCTAssertTrue(lifecycle.hasAppliedOverviewRegion)
        XCTAssertFalse(lifecycle.hasAppliedViewportFit)

        XCTAssertFalse(lifecycle.reconcileOverview(isAvailable: false))
        lifecycle.markViewportFitApplied()
        XCTAssertFalse(lifecycle.reconcileOverview(isAvailable: true))
        XCTAssertTrue(lifecycle.hasAppliedOverviewRegion)
        XCTAssertTrue(lifecycle.hasAppliedViewportFit)
    }

    private func profile(id: String) -> LocalProfile {
        LocalProfile(
            localID: "local-\(id)",
            serverID: id,
            handle: id,
            displayName: id.capitalized,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        userPlaceID: String,
        placeLocalID: String,
        placeServerID: String?,
        name: String,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        status: PlaceStatus
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: placeLocalID,
            serverID: placeServerID,
            canonicalName: name,
            category: WanderPlaceCategory.restaurantsFood,
            address: address,
            locality: "Los Angeles",
            country: "United States",
            latitude: latitude,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: placeServerID ?? placeLocalID,
            syncState: placeServerID == nil ? .localOnly : .synced
        )
        let userPlace = LocalUserPlace(
            localID: userPlaceID,
            serverID: "server-\(userPlaceID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner
        )
    }
}
