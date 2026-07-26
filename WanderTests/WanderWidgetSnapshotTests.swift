import Foundation
import XCTest
@testable import Wander

final class WanderWidgetDeepLinkTests: XCTestCase {
    func testWidgetConstantsMatchRegisteredContracts() {
        XCTAssertEqual(WanderWidgetConstants.appGroupIdentifier, "group.com.grayline.wander.shared")
        XCTAssertEqual(WanderWidgetConstants.calendarSnapshotFilename, "activity-calendar-snapshot.json")
        XCTAssertEqual(WanderWidgetConstants.quickCaptureKind, "QuickCaptureWidget")
        XCTAssertEqual(WanderWidgetConstants.quickSearchKind, "QuickSearchWidget")
        XCTAssertEqual(WanderWidgetConstants.activityCalendarKind, "ActivityCalendarWidget")
        XCTAssertEqual(WanderWidgetConstants.quickCaptureURL.absoluteString, "recme://add/here-now")
        XCTAssertEqual(WanderWidgetConstants.quickSearchURL.absoluteString, "recme://map/search")
        XCTAssertEqual(WanderWidgetConstants.profileCalendarURL.absoluteString, "recme://profile/calendar")
    }

    func testFixedWidgetRoutesBuildExactURLsAndRoundTrip() throws {
        let expectations: [(WanderDeepLinkRoute, String)] = [
            (.quickCapture, "recme://add/here-now"),
            (.quickSearch(query: nil), "recme://map/search"),
            (.profileCalendar, "recme://profile/calendar")
        ]

        for (route, expectedURL) in expectations {
            let url = try XCTUnwrap(route.url)
            XCTAssertEqual(url.absoluteString, expectedURL)
            XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        }
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
            "recme://profiles/user%2F%E6%9D%B1%E4%BA%AC"
        )
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        XCTAssertNil(WanderDeepLinkRoute.sharedProfile(profileID: " \n ").url)
    }

    func testParserRejectsLookalikesExtraComponentsAndAmbiguousQueries() throws {
        let rejected = [
            "https://add/here-now",
            "recme://add",
            "recme://add/here-now/extra",
            "recme://add/here-now?q=cafe",
            "recme://map/search/extra",
            "recme://map/search?query=cafe",
            "recme://map/search?q=one&q=two",
            "recme://map/search?",
            "recme://map:8080/search",
            "recme://profile/calendar#today",
            "recme://profiles",
            "recme://profiles/%20%0A",
            "recme://profiles/user/extra"
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
