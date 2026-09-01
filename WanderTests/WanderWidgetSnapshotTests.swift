import Foundation
import XCTest
@testable import Wander

final class WanderWidgetDeepLinkTests: XCTestCase {
    func testWidgetConstantsMatchRegisteredContracts() {
        XCTAssertEqual(WanderWidgetConstants.appGroupIdentifier, "group.com.grayline.wander.shared")
        XCTAssertEqual(WanderWidgetConstants.calendarSnapshotFilename, "activity-calendar-snapshot.json")
        XCTAssertEqual(WanderWidgetConstants.nearbySnapshotFilename, "nearby-place-snapshot.json")
        XCTAssertEqual(
            WanderWidgetConstants.nearbyRefreshStateFilename,
            "nearby-place-refresh-state.json"
        )
        XCTAssertEqual(WanderWidgetConstants.quickCaptureKind, "QuickCaptureWidget")
        XCTAssertEqual(WanderWidgetConstants.quickSearchKind, "QuickSearchWidget")
        XCTAssertEqual(WanderWidgetConstants.activityCalendarKind, "ActivityCalendarWidget")
        XCTAssertEqual(WanderWidgetConstants.nearbyPlacesKind, "NearbyPlacesWidget")
        XCTAssertEqual(WanderWidgetConstants.quickCaptureURL.absoluteString, "recme://add/here-now")
        XCTAssertEqual(WanderWidgetConstants.mapURL.absoluteString, "recme://map")
        XCTAssertEqual(WanderWidgetConstants.quickSearchURL.absoluteString, "recme://map/search")
        XCTAssertEqual(WanderWidgetConstants.profileCalendarURL.absoluteString, "recme://profile/calendar")
    }

    func testFixedWidgetRoutesBuildExactURLsAndRoundTrip() throws {
        let expectations: [(WanderDeepLinkRoute, String)] = [
            (.quickCapture, "recme://add/here-now"),
            (.map, "recme://map"),
            (.quickSearch(query: nil), "recme://map/search"),
            (.profileCalendar, "recme://profile/calendar")
        ]

        for (route, expectedURL) in expectations {
            let url = try XCTUnwrap(route.url)
            XCTAssertEqual(url.absoluteString, expectedURL)
            XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        }
    }

    func testCalendarDateRouteBuildsExactURLAndRoundTrips() throws {
        let date = try XCTUnwrap(WanderCalendarDate(year: 2026, month: 7, day: 25))
        let route = WanderDeepLinkRoute.profileCalendarDate(date)
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(url.absoluteString, "recme://profile/calendar/2026-07-25")
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let resolved = try XCTUnwrap(date.date(timeZone: calendar.timeZone))
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: resolved),
            DateComponents(year: 2026, month: 7, day: 25)
        )
    }

    func testCalendarReservationRouteBuildsExactURLAndRoundTrips() throws {
        let reservationID = "90000000-0000-0000-0000-000000000001"
        let route = WanderDeepLinkRoute.calendarReservation(reservationID: reservationID)
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(
            url.absoluteString,
            "recme://add/reservations/90000000-0000-0000-0000-000000000001"
        )
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        XCTAssertNil(
            WanderDeepLinkRoute.parse(
                try XCTUnwrap(URL(string: "recme://add/reservations/not-a-uuid"))
            )
        )
    }

    func testCalendarDateRejectsMalformedAndImpossibleValues() throws {
        XCTAssertNil(WanderCalendarDate(urlValue: "2026-7-25"))
        XCTAssertNil(WanderCalendarDate(urlValue: "2026-07-25-extra"))
        XCTAssertNil(WanderCalendarDate(urlValue: "2026-02-29"))
        XCTAssertNil(WanderCalendarDate(year: 2026, month: 13, day: 1))
        XCTAssertNotNil(WanderCalendarDate(urlValue: "2028-02-29"))

        for rawURL in [
            "recme://profile/calendar/2026-7-25",
            "recme://profile/calendar/2026-02-29",
            "recme://profile/calendar/2026-07-25?source=widget",
            "recme://profile/calendar/2026-07-25/extra"
        ] {
            XCTAssertNil(
                WanderDeepLinkRoute.parse(try XCTUnwrap(URL(string: rawURL))),
                "Unexpectedly accepted \(rawURL)"
            )
        }
    }

    func testNearbyFreshnessFormatsWholeMinutesWithoutSeconds() {
        let generatedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(
            WanderNearbyWidgetFreshness(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(59)
            ).minuteAgeLabel,
            "updated <1 min ago"
        )
        XCTAssertEqual(
            WanderNearbyWidgetFreshness(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(60)
            ).minuteAgeLabel,
            "updated 1 min ago"
        )
        XCTAssertEqual(
            WanderNearbyWidgetFreshness(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(179)
            ).minuteAgeLabel,
            "updated 2 mins ago"
        )
    }

    func testQuickSearchTrimsAndPercentEncodesUnicodeQuery() throws {
        let route = WanderDeepLinkRoute.quickSearch(query: " \n Best Café & 東京 \t")
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(
            url.absoluteString,
            "recme://map/search?q=Best%20Caf%C3%A9%20%26%20%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(
            WanderDeepLinkRoute.parse(url),
            .quickSearch(query: "Best Café & 東京")
        )
    }

    func testAddSearchRequiresAQueryAndRoundTripsForImportEditing() throws {
        let route = WanderDeepLinkRoute.addSearch(query: "  Bavel Los Angeles  ")
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(url.absoluteString, "recme://add/search?q=Bavel%20Los%20Angeles")
        XCTAssertEqual(
            WanderDeepLinkRoute.parse(url),
            .addSearch(query: "Bavel Los Angeles")
        )
        XCTAssertNil(WanderDeepLinkRoute.addSearch(query: " \n ").url)
        XCTAssertNil(
            WanderDeepLinkRoute.parse(
                try XCTUnwrap(URL(string: "recme://add/search"))
            )
        )
    }

    func testNearbyPlaceEncodesOneOpaquePathSegmentAndRoundTripsUnicode() throws {
        let route = WanderDeepLinkRoute.nearbyPlace(candidateID: "mapkit/Ggiata 東京")
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(
            url.absoluteString,
            "recme://add/nearby/mapkit%2FGgiata%20%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        XCTAssertNil(WanderDeepLinkRoute.nearbyPlace(candidateID: " \n ").url)
    }

    func testQuickSearchOmitsBlankQueryAndParserNormalizesBlankQuery() throws {
        XCTAssertEqual(
            try XCTUnwrap(WanderDeepLinkRoute.quickSearch(query: " \n\t ").url),
            WanderWidgetConstants.quickSearchURL
        )
        XCTAssertEqual(
            WanderDeepLinkRoute.parse(
                try XCTUnwrap(URL(string: "recme://map/search?q=%20%0A%09"))
            ),
            .quickSearch(query: nil)
        )
    }

    func testSharedProfileEncodesOneOpaquePathSegmentAndRoundTripsUnicode() throws {
        let route = WanderDeepLinkRoute.sharedProfile(profileID: "user/東京")
        let url = try XCTUnwrap(route.url)

        XCTAssertEqual(
            url.absoluteString,
            "https://getrec.me/profiles/user%2F%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        XCTAssertNil(WanderDeepLinkRoute.sharedProfile(profileID: " \n ").url)
    }

    func testSharedEntityUniversalLinksRoundTripEveryPublicRoute() throws {
        let routes: [(WanderDeepLinkRoute, String)] = [
            (
                .sharedProfile(profileID: "user_joe"),
                "https://getrec.me/profiles/user_joe"
            ),
            (
                .sharedPlace(placeID: "40000000-0000-0000-0000-000000000001"),
                "https://getrec.me/places/40000000-0000-0000-0000-000000000001"
            ),
            (
                .sharedActivity(activityID: "42000000-0000-0000-0000-000000000001"),
                "https://getrec.me/activities/42000000-0000-0000-0000-000000000001"
            ),
            (
                .sharedList(listID: "44000000-0000-0000-0000-000000000001"),
                "https://getrec.me/lists/44000000-0000-0000-0000-000000000001"
            ),
            (
                .listInvite(token: String(repeating: "ab", count: 24)),
                "https://getrec.me/invites/\(String(repeating: "ab", count: 24))"
            )
        ]

        for (route, expectedURL) in routes {
            let url = try XCTUnwrap(route.url)
            XCTAssertEqual(url.absoluteString, expectedURL)
            XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        }
    }

    func testParserRejectsLookalikesExtraComponentsAndAmbiguousQueries() throws {
        let rejected = [
            "https://add/here-now",
            "recme://add",
            "recme://add/here-now/extra",
            "recme://add/here-now?q=cafe",
            "recme://add/nearby",
            "recme://add/nearby/%20%0A",
            "recme://add/nearby/place/extra",
            "recme://add/nearby/place?q=coffee",
            "recme://map?q=coffee",
            "recme://map/search/extra",
            "recme://map/search?query=cafe",
            "recme://map/search?q=one&q=two",
            "recme://map/search?",
            "recme://map:8080/search",
            "recme://profile/calendar#today",
            "recme://profile/calendar/2026-07-25#today",
            "recme://profiles",
            "recme://profiles/%20%0A",
            "recme://profiles/user/extra",
            "http://getrec.me/profiles/user",
            "https://www.getrec.me/profiles/user",
            "https://getrec.me/profiles/user/extra",
            "https://getrec.me/profiles/user?q=private",
            "https://getrec.me/places/not-a-uuid",
            "https://getrec.me/activities/not-a-uuid",
            "https://getrec.me/lists/not-a-uuid",
            "https://getrec.me/invites/too-short"
        ]

        for rawURL in rejected {
            XCTAssertNil(
                WanderDeepLinkRoute.parse(try XCTUnwrap(URL(string: rawURL))),
                "Unexpectedly accepted \(rawURL)"
            )
        }
    }

    func testParserTreatsSchemeAndHostAsCaseInsensitiveButPathsAsExact() throws {
        XCTAssertEqual(
            WanderDeepLinkRoute.parse(try XCTUnwrap(URL(string: "RECME://ADD/here-now"))),
            .quickCapture
        )
        XCTAssertNil(
            WanderDeepLinkRoute.parse(try XCTUnwrap(URL(string: "recme://add/HERE-NOW")))
        )
    }
}

final class WanderNearbyWidgetSnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var snapshotFileURL: URL!
    private var refreshStateFileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-nearby-widget-tests-\(UUID().uuidString)", isDirectory: true)
        snapshotFileURL = temporaryDirectory
            .appendingPathComponent(WanderWidgetConstants.nearbySnapshotFilename, isDirectory: false)
        refreshStateFileURL = temporaryDirectory
            .appendingPathComponent(
                WanderWidgetConstants.nearbyRefreshStateFilename,
                isDirectory: false
            )
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        snapshotFileURL = nil
        refreshStateFileURL = nil
    }

    func testRefreshStateRoundTripsAndExpires() throws {
        let store = WanderNearbyWidgetRefreshStateStore(fileURL: refreshStateFileURL)
        let startedAt = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(store.state(at: startedAt), .idle)
        let requestID = try store.begin(at: startedAt)
        XCTAssertEqual(
            store.state(at: startedAt.addingTimeInterval(10)),
            .refreshing(startedAt: startedAt)
        )
        XCTAssertEqual(
            store.state(
                at: startedAt.addingTimeInterval(
                    WanderNearbyWidgetRefreshStateStore.maximumRefreshDuration + 1
                )
            ),
            .idle
        )

        let completedAt = Date(timeIntervalSince1970: 2_000)
        XCTAssertFalse(
            try store.complete(
                requestID: UUID(),
                at: completedAt,
                availability: .ready
            )
        )
        XCTAssertTrue(
            try store.complete(
                requestID: requestID,
                at: completedAt,
                availability: .ready
            )
        )
        XCTAssertEqual(
            store.state(at: completedAt.addingTimeInterval(10)),
            .completed(at: completedAt, availability: .ready)
        )
        XCTAssertEqual(
            store.state(
                at: completedAt.addingTimeInterval(
                    WanderNearbyWidgetRefreshStateStore.completedStateLifetime + 1
                )
            ),
            .idle
        )
    }

    func testSnapshotLimitsVisiblePlacesAndRetainsRecentRoutes() throws {
        let places = try (0..<7).map { try makePlace($0) }
        let snapshot = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            places: places
        )

        XCTAssertEqual(snapshot.places.count, 5)
        XCTAssertEqual(snapshot.places.map(\.id), ["place-0", "place-1", "place-2", "place-3", "place-4"])
        XCTAssertEqual(snapshot.recentPlaces.count, 5)

        let nextPlaces = try (7..<12).map { try makePlace($0) }
        let merged = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 2_000),
            places: nextPlaces
        ).mergingRouteHistory(from: snapshot)

        XCTAssertEqual(merged.places.map(\.id), ["place-7", "place-8", "place-9", "place-10", "place-11"])
        XCTAssertEqual(merged.recentPlaces.count, 10)
        XCTAssertEqual(merged.place(id: "place-0"), places[0])
        XCTAssertEqual(merged.place(id: "place-11"), nextPlaces[4])
    }

    func testStoreRoundTripsAndPreservesRoutesAcrossRefreshes() throws {
        let store = WanderNearbyWidgetSnapshotStore(fileURL: snapshotFileURL)
        let first = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            places: [try makePlace(0)]
        )
        let second = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 2_000),
            places: [try makePlace(1)]
        )

        XCTAssertTrue(try store.save(first))
        XCTAssertTrue(try store.save(second))

        let loaded = try XCTUnwrap(store.load(now: second.generatedAt))
        XCTAssertEqual(loaded.places, second.places)
        XCTAssertEqual(loaded.place(id: "place-0"), first.places[0])
        XCTAssertEqual(loaded.place(id: "place-1"), second.places[0])

        let third = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 3_000),
            places: [try makePlace(2)]
        )
        XCTAssertTrue(try store.save(third))
        let latest = try XCTUnwrap(store.load(now: third.generatedAt))
        XCTAssertNil(latest.place(id: "place-0"))
        XCTAssertEqual(latest.place(id: "place-1"), second.places[0])
        XCTAssertEqual(latest.place(id: "place-2"), third.places[0])
    }

    func testStoreSkipsEquivalentFreshnessWriteInsideFiveMinutes() throws {
        let store = WanderNearbyWidgetSnapshotStore(fileURL: snapshotFileURL)
        let place = try makePlace(0)

        XCTAssertTrue(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: Date(timeIntervalSince1970: 1_000),
                    places: [place]
                )
            )
        )
        XCTAssertFalse(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: Date(timeIntervalSince1970: 1_299),
                    places: [place]
                )
            )
        )
        XCTAssertTrue(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: Date(timeIntervalSince1970: 1_300),
                    places: [place]
                )
            )
        )
    }

    func testStoreCanForceFreshnessAdvanceForInteractiveRefresh() throws {
        let store = WanderNearbyWidgetSnapshotStore(fileURL: snapshotFileURL)
        let place = try makePlace(0)
        let firstGeneratedAt = Date(timeIntervalSince1970: 1_000)
        let refreshedAt = Date(timeIntervalSince1970: 1_001)

        XCTAssertTrue(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: firstGeneratedAt,
                    places: [place]
                )
            )
        )
        XCTAssertTrue(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: refreshedAt,
                    places: [place]
                ),
                forceFreshnessAdvance: true
            )
        )
        XCTAssertEqual(store.load(now: refreshedAt)?.generatedAt, refreshedAt)
        XCTAssertTrue(try store.clear())
        XCTAssertNil(store.load())
        XCTAssertFalse(try store.clear())
    }

    func testStoreRejectsOlderResultsFromConcurrentRefreshes() throws {
        let store = WanderNearbyWidgetSnapshotStore(fileURL: snapshotFileURL)
        let newer = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 2_000),
            places: [try makePlace(1)]
        )
        let older = WanderNearbyWidgetSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            places: [try makePlace(0)]
        )

        XCTAssertTrue(try store.save(newer))
        XCTAssertFalse(
            try store.save(older, forceFreshnessAdvance: true)
        )
        XCTAssertEqual(store.load(now: newer.generatedAt)?.generatedAt, newer.generatedAt)
        XCTAssertEqual(store.load(now: newer.generatedAt)?.places, newer.places)
    }

    func testStoreRemovesSnapshotsAfterUsableLifetime() throws {
        let store = WanderNearbyWidgetSnapshotStore(fileURL: snapshotFileURL)
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(
            try store.save(
                WanderNearbyWidgetSnapshot(
                    generatedAt: generatedAt,
                    places: [try makePlace(0)]
                )
            )
        )

        XCTAssertNil(
            store.load(
                now: generatedAt.addingTimeInterval(
                    WanderNearbyWidgetFreshness.usableLifetime + 1
                )
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFileURL.path))
    }

    func testFreshnessHidesExactDistanceAfterThirtyMinutesAndExpiresAfterOneDay() throws {
        let generatedAt = Date(timeIntervalSince1970: 10_000)
        let place = try makePlace(0, distanceMeters: 10.7)
        let snapshot = WanderNearbyWidgetSnapshot(
            generatedAt: generatedAt,
            places: [place]
        )

        XCTAssertEqual(
            place.distanceLabel(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(30 * 60)
            ),
            "35 ft away"
        )
        XCTAssertEqual(
            place.distanceLabel(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(30 * 60 + 1)
            ),
            "near you"
        )
        XCTAssertTrue(
            WanderNearbyWidgetFreshness(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(24 * 60 * 60)
            ).isUsable
        )
        XCTAssertFalse(
            WanderNearbyWidgetFreshness(
                generatedAt: generatedAt,
                now: generatedAt.addingTimeInterval(24 * 60 * 60 + 1)
            ).isUsable
        )
        XCTAssertTrue(snapshot.isUsable(at: generatedAt.addingTimeInterval(24 * 60 * 60)))
        XCTAssertFalse(
            snapshot.isUsable(at: generatedAt.addingTimeInterval(24 * 60 * 60 + 1))
        )
    }

    func testDistanceFormatterUsesReadableFeetAndMiles() {
        XCTAssertEqual(WanderNearbyWidgetDistanceFormatter.string(meters: 10.7), "35 ft")
        XCTAssertEqual(WanderNearbyWidgetDistanceFormatter.string(meters: 152.4), "500 ft")
        XCTAssertEqual(WanderNearbyWidgetDistanceFormatter.string(meters: 804.672), "0.5 mi")
        XCTAssertEqual(WanderNearbyWidgetDistanceFormatter.string(meters: 16_093.44), "10 mi")
        XCTAssertNil(WanderNearbyWidgetDistanceFormatter.string(meters: -Double.infinity))
        XCTAssertNil(WanderNearbyWidgetDistanceFormatter.string(meters: -1))
    }

    func testSnapshotConversionPreservesRichVisitPlaceMetadata() throws {
        let snapshot = try XCTUnwrap(WanderNearbyPlaceSnapshot(
            id: "mapkit_ggiata_3408000_-11826000",
            name: "Ggiata Delicatessen",
            category: "restaurants_food",
            categoryLabel: "Restaurant",
            categoryEmoji: "🥪",
            rawProviderType: "MKPOICategoryRestaurant",
            address: "5009 Melrose Avenue",
            locality: "Los Angeles",
            region: "CA",
            country: "US",
            latitude: 34.083,
            longitude: -118.312,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit_ggiata_3408000_-11826000",
            distanceMeters: 10.7,
            websiteURLString: "https://example.com/ggiata",
            phoneNumber: "+1-323-555-0100",
            timeZoneIdentifier: "America/Los_Angeles",
            confidence: 0.92
        ))
        let restored = snapshot.placeCandidate

        XCTAssertEqual(restored.id, snapshot.id)
        XCTAssertEqual(restored.name, snapshot.name)
        XCTAssertEqual(restored.primaryCategory, snapshot.category)
        XCTAssertEqual(restored.rawProviderType, snapshot.rawProviderType?.lowercased())
        XCTAssertEqual(restored.address, snapshot.address)
        XCTAssertEqual(restored.locality, snapshot.locality)
        XCTAssertEqual(restored.region, snapshot.region)
        XCTAssertEqual(restored.country, snapshot.country)
        XCTAssertEqual(restored.latitude, snapshot.latitude)
        XCTAssertEqual(restored.longitude, snapshot.longitude)
        XCTAssertEqual(restored.sourceProviderPlaceID, snapshot.sourceProviderPlaceID)
        XCTAssertEqual(restored.distanceMeters, snapshot.distanceMeters)
        XCTAssertEqual(restored.websiteURLString, snapshot.websiteURLString)
        XCTAssertEqual(restored.phoneNumber, snapshot.phoneNumber)
        XCTAssertEqual(restored.timeZoneIdentifier, snapshot.timeZoneIdentifier)
    }

    private func makePlace(
        _ index: Int,
        distanceMeters: Double? = nil
    ) throws -> WanderNearbyPlaceSnapshot {
        try XCTUnwrap(
            WanderNearbyPlaceSnapshot(
                id: "place-\(index)",
                name: index == 0 ? "Ggiata" : "Place \(index)",
                category: "restaurant",
                categoryLabel: "Restaurant",
                categoryEmoji: "🍝",
                rawProviderType: "MKPOICategoryRestaurant",
                address: "\(index) Sunset Boulevard",
                locality: "Los Angeles",
                region: "CA",
                country: "US",
                latitude: 34.0 + Double(index) / 1_000,
                longitude: -118.0 - Double(index) / 1_000,
                sourceProviderPlaceID: "place-\(index)",
                distanceMeters: distanceMeters ?? Double(index + 1) * 25,
                confidence: 0.9
            )
        )
    }
}

final class WanderCalendarWidgetSnapshotTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var snapshotFileURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-widget-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        snapshotFileURL = temporaryDirectory
            .appendingPathComponent(WanderWidgetConstants.calendarSnapshotFilename, isDirectory: false)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        snapshotFileURL = nil
    }

    func testActivityStateCoversNoneBeenWannaAndBoth() {
        XCTAssertEqual(WanderWidgetActivityState(beenCount: 0, wannaCount: 0), .none)
        XCTAssertEqual(WanderWidgetActivityState(beenCount: 2, wannaCount: 0), .been)
        XCTAssertEqual(WanderWidgetActivityState(beenCount: 0, wannaCount: 3), .wanna)
        XCTAssertEqual(WanderWidgetActivityState(beenCount: 2, wannaCount: 3), .both)
    }

    func testMonthCompactsActivityAndProvidesLookupAndGridPadding() throws {
        let month = WanderCalendarMonthSnapshot(
            year: 2026,
            month: 7,
            title: "July 2026",
            leadingBlankCount: 3,
            dayCount: 31,
            days: [
                WanderCalendarDaySnapshot(dayNumber: 8, beenCount: 1, wannaCount: 0),
                WanderCalendarDaySnapshot(dayNumber: 2, beenCount: 0, wannaCount: 1),
                WanderCalendarDaySnapshot(dayNumber: 8, beenCount: 2, wannaCount: 4),
                WanderCalendarDaySnapshot(dayNumber: 3, beenCount: 0, wannaCount: 0)
            ]
        )

        XCTAssertEqual(month.days.map(\.dayNumber), [2, 8])
        XCTAssertEqual(month.beenCount, 3)
        XCTAssertEqual(month.wannaCount, 5)
        XCTAssertEqual(try XCTUnwrap(month.day(2)).state, .wanna)
        XCTAssertEqual(try XCTUnwrap(month.day(8)).state, .both)
        XCTAssertEqual(try XCTUnwrap(month.day(8)).beenCount, 3)
        XCTAssertEqual(try XCTUnwrap(month.day(8)).wannaCount, 4)
        XCTAssertNil(month.day(7))
        XCTAssertEqual(month.trailingBlankCount, 1)
        XCTAssertEqual(month.gridCellCount, 35)
    }

    func testSnapshotCodableRoundTripAndMonthLookup() throws {
        let snapshot = makeSnapshot()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(WanderCalendarWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.month(year: 2026, month: 6), decoded.previousMonth)
        XCTAssertEqual(decoded.month(year: 2026, month: 7), decoded.currentMonth)
        XCTAssertEqual(decoded.month(year: 2026, month: 8), decoded.nextMonth)
        XCTAssertNil(decoded.month(year: 2027, month: 7))
    }

    func testMonthContainingUsesGregorianDatesAndExpiresBeyondBufferedMonths() throws {
        let snapshot = makeSnapshot()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let currentMonthDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))
        )
        let beyondNextMonth = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))
        )

        XCTAssertEqual(snapshot.month(containing: currentMonthDate), snapshot.currentMonth)
        XCTAssertNil(snapshot.month(containing: beyondNextMonth))
    }

    func testWidgetCalendarStaysGregorianWithANonGregorianReferenceCalendar() throws {
        var hebrewCalendar = Calendar(identifier: .hebrew)
        hebrewCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        hebrewCalendar.firstWeekday = 2

        let calendar = WanderWidgetCalendar.gregorian(
            reference: hebrewCalendar,
            locale: Locale(identifier: "he_IL")
        )
        var dateCalendar = Calendar(identifier: .gregorian)
        dateCalendar.timeZone = hebrewCalendar.timeZone
        let date = try XCTUnwrap(
            dateCalendar.date(
                from: DateComponents(year: 2026, month: 8, day: 15)
            )
        )
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.firstWeekday, 2)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 15)
    }

    func testWeekdaySymbolsRotateForMondayFirstCalendars() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2

        XCTAssertEqual(
            WanderWidgetCalendar.rotatedWeekdaySymbols(calendar: calendar),
            ["M", "T", "W", "T", "F", "S", "S"]
        )
    }

    func testSnapshotCompatibilityRequiresCurrentTimeZoneAndFirstWeekday() throws {
        let snapshot = makeSnapshot()
        var matchingCalendar = Calendar(identifier: .gregorian)
        matchingCalendar.locale = Locale(identifier: "en_US")
        matchingCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        matchingCalendar.firstWeekday = 1

        XCTAssertTrue(snapshot.isCompatible(with: matchingCalendar))

        var travelledCalendar = matchingCalendar
        travelledCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        XCTAssertFalse(snapshot.isCompatible(with: travelledCalendar))

        var mondayFirstCalendar = matchingCalendar
        mondayFirstCalendar.firstWeekday = 2
        XCTAssertFalse(snapshot.isCompatible(with: mondayFirstCalendar))
    }

    func testTimelineCarriesDailyEntriesAcrossCoveredMonthBoundary() throws {
        let snapshot = makeSnapshot()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: snapshot.timeZoneIdentifier))
        let now = try XCTUnwrap(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 31, hour: 18)
            )
        )

        let schedule = WanderCalendarTimelineSchedule.make(
            startingAt: now,
            snapshot: snapshot
        )
        let components = schedule.entryDates.map {
            calendar.dateComponents([.year, .month, .day, .hour], from: $0)
        }

        XCTAssertEqual(schedule.entryDates.first, now)
        XCTAssertTrue(
            components.contains {
                $0.year == 2026 && $0.month == 8 && $0.day == 1 && $0.hour == 0
            }
        )
        XCTAssertTrue(
            components.contains {
                $0.year == 2026 && $0.month == 9 && $0.day == 1 && $0.hour == 0
            }
        )
        XCTAssertGreaterThan(schedule.reloadAfter, try XCTUnwrap(schedule.entryDates.last))
    }

    func testTimelineIgnoresSnapshotCoverageWhenCalendarContextChanged() throws {
        let snapshot = makeSnapshot()
        var currentCalendar = Calendar(identifier: .gregorian)
        currentCalendar.locale = Locale(identifier: "en_US")
        currentCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Auckland"))
        currentCalendar.firstWeekday = 2
        let now = try XCTUnwrap(
            currentCalendar.date(
                from: DateComponents(year: 2026, month: 7, day: 31, hour: 18)
            )
        )

        let schedule = WanderCalendarTimelineSchedule.make(
            startingAt: now,
            snapshot: snapshot,
            minimumDaysAhead: 2,
            referenceCalendar: currentCalendar
        )
        let finalComponents = currentCalendar.dateComponents(
            [.year, .month, .day],
            from: try XCTUnwrap(schedule.entryDates.last)
        )

        XCTAssertEqual(finalComponents.year, 2026)
        XCTAssertEqual(finalComponents.month, 8)
        XCTAssertEqual(finalComponents.day, 2)
    }

    func testStoredJSONContainsOnlyCalendarMetadataAndAggregateCounts() throws {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)
        XCTAssertTrue(try store.save(makeSnapshot()))

        let json = try XCTUnwrap(
            String(data: Data(contentsOf: snapshotFileURL), encoding: .utf8)
        ).lowercased()
        XCTAssertTrue(json.contains("\"beencount\""))
        XCTAssertTrue(json.contains("\"wannacount\""))
        XCTAssertFalse(json.contains("\"place"))
        XCTAssertFalse(json.contains("\"latitude\""))
        XCTAssertFalse(json.contains("\"longitude\""))
        XCTAssertFalse(json.contains("\"coordinate"))
        XCTAssertFalse(json.contains("\"note"))
        XCTAssertFalse(json.contains("\"auth"))
        XCTAssertFalse(json.contains("\"user"))
    }

    func testStoredSnapshotIsExcludedFromBackupAfterAtomicSave() throws {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)

        XCTAssertTrue(try store.save(makeSnapshot()))
        XCTAssertEqual(
            try snapshotFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup,
            true
        )

        let changed = makeSnapshot(
            currentDays: [
                WanderCalendarDaySnapshot(dayNumber: 24, beenCount: 1, wannaCount: 1)
            ]
        )
        XCTAssertTrue(try store.save(changed))
        XCTAssertEqual(
            try snapshotFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
                .isExcludedFromBackup,
            true
        )
    }

    func testStoreReturnsNilForMissingCorruptUnsupportedAndInconsistentData() throws {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)
        XCTAssertNil(store.load())

        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: snapshotFileURL)
        XCTAssertNil(store.load())

        XCTAssertTrue(try store.save(makeSnapshot()))
        var json = try XCTUnwrap(
            String(data: Data(contentsOf: snapshotFileURL), encoding: .utf8)
        )
        json = json.replacingOccurrences(
            of: "\"schemaVersion\":1",
            with: "\"schemaVersion\":99"
        )
        try Data(json.utf8).write(to: snapshotFileURL, options: .atomic)
        XCTAssertNil(store.load())
        XCTAssertTrue(try store.remove())
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFileURL.path))

        XCTAssertTrue(try store.save(makeSnapshot()))
        json = try XCTUnwrap(
            String(data: Data(contentsOf: snapshotFileURL), encoding: .utf8)
        )
        json = json.replacingOccurrences(
            of: "\"state\":\"both\"",
            with: "\"state\":\"none\""
        )
        try Data(json.utf8).write(to: snapshotFileURL, options: .atomic)
        XCTAssertNil(store.load())
    }

    func testStoreSkipsGeneratedAtOnlyChangesButWritesSemanticChanges() throws {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)
        let first = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 1_721_779_200))
        let laterGeneration = makeSnapshot(generatedAt: Date(timeIntervalSince1970: 1_721_779_260))

        XCTAssertTrue(try store.save(first))
        let firstData = try Data(contentsOf: snapshotFileURL)
        XCTAssertFalse(try store.save(laterGeneration))
        XCTAssertEqual(try Data(contentsOf: snapshotFileURL), firstData)
        XCTAssertEqual(store.load()?.generatedAt, first.generatedAt)

        let refreshedGeneration = makeSnapshot(
            generatedAt: first.generatedAt.addingTimeInterval(
                WanderCalendarWidgetSnapshotStore.freshnessWriteInterval + 1
            )
        )
        XCTAssertFalse(
            try store.save(
                refreshedGeneration,
                allowFreshnessAdvance: false
            )
        )
        XCTAssertEqual(store.load()?.generatedAt, first.generatedAt)

        XCTAssertTrue(try store.save(refreshedGeneration))
        XCTAssertEqual(store.load()?.generatedAt, refreshedGeneration.generatedAt)

        let changed = makeSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_721_779_320),
            currentDays: [
                WanderCalendarDaySnapshot(dayNumber: 8, beenCount: 4, wannaCount: 2)
            ]
        )
        XCTAssertTrue(try store.save(changed))
        XCTAssertNotEqual(try Data(contentsOf: snapshotFileURL), firstData)
        XCTAssertEqual(store.load()?.currentMonth.day(8)?.beenCount, 4)
        XCTAssertEqual(store.load()?.generatedAt, changed.generatedAt)
    }

    func testStoreRejectsUnsupportedSchemaOnSave() {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)
        let unsupported = makeSnapshot(schemaVersion: 99)

        XCTAssertThrowsError(try store.save(unsupported)) { error in
            XCTAssertEqual(
                error as? WanderCalendarWidgetSnapshotStoreError,
                .unsupportedSchema(99)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFileURL.path))
    }

    func testStoreRemovesStaleSnapshotAndMissingRemovalIsIdempotent() throws {
        let store = WanderCalendarWidgetSnapshotStore(fileURL: snapshotFileURL)
        XCTAssertTrue(try store.save(makeSnapshot()))
        XCTAssertNotNil(store.load())

        XCTAssertTrue(try store.remove())
        XCTAssertNil(store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotFileURL.path))
        XCTAssertFalse(try store.remove())
    }

    private func makeSnapshot(
        schemaVersion: Int = WanderCalendarWidgetSnapshot.currentSchemaVersion,
        generatedAt: Date = Date(timeIntervalSince1970: 1_721_779_200),
        currentDays: [WanderCalendarDaySnapshot] = [
            WanderCalendarDaySnapshot(dayNumber: 2, beenCount: 1, wannaCount: 0),
            WanderCalendarDaySnapshot(dayNumber: 8, beenCount: 2, wannaCount: 1)
        ]
    ) -> WanderCalendarWidgetSnapshot {
        WanderCalendarWidgetSnapshot(
            schemaVersion: schemaVersion,
            generatedAt: generatedAt,
            timeZoneIdentifier: "America/Los_Angeles",
            firstWeekday: 1,
            weekdaySymbols: ["S", "M", "T", "W", "T", "F", "S"],
            previousMonth: WanderCalendarMonthSnapshot(
                year: 2026,
                month: 6,
                title: "June 2026",
                leadingBlankCount: 1,
                dayCount: 30,
                days: [
                    WanderCalendarDaySnapshot(dayNumber: 19, beenCount: 0, wannaCount: 1)
                ]
            ),
            currentMonth: WanderCalendarMonthSnapshot(
                year: 2026,
                month: 7,
                title: "July 2026",
                leadingBlankCount: 3,
                dayCount: 31,
                days: currentDays
            ),
            nextMonth: WanderCalendarMonthSnapshot(
                year: 2026,
                month: 8,
                title: "August 2026",
                leadingBlankCount: 6,
                dayCount: 31,
                days: []
            )
        )
    }
}
