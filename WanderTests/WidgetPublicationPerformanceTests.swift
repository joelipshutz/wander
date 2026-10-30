import Foundation
import XCTest
@testable import Wander

@MainActor
final class WidgetPublicationPerformanceTests: XCTestCase {
    /// Keep this workload identical on baseline and candidate. It measures the
    /// real publisher, including the store projection, snapshot encoding/disk
    /// write, and timeline reload request; extension rendering is not measured.
    func testPerformanceCalendarWidgetPublicationWith1500Saves() throws {
        let calendar = WanderWidgetCalendar.gregorian()
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)))
        let currentMonth = try XCTUnwrap(calendar.dateInterval(of: .month, for: now)?.start)
        let months = try [-1, 0, 1].map {
            try XCTUnwrap(calendar.date(byAdding: .month, value: $0, to: currentMonth))
        }
        var firstSamples: [Double] = []
        var repeatedSamples: [Double] = []
        for _ in 0..<3 {
            let fixture = try makeFixture(months: months, calendar: calendar)
            let store = WanderStore(fixtures: fixture)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("widget-publication-performance-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let snapshotStore = WanderCalendarWidgetSnapshotStore(
                fileURL: directory.appendingPathComponent("calendar.json")
            )

            let firstStart = ProcessInfo.processInfo.systemUptime
            WanderWidgetSnapshotPublisher.publish(store: store, isAvailable: true, now: now,
                snapshotStore: snapshotStore)
            firstSamples.append((ProcessInfo.processInfo.systemUptime - firstStart) * 1_000)
            let first = try XCTUnwrap(snapshotStore.load())

            let repeatStart = ProcessInfo.processInfo.systemUptime
            WanderWidgetSnapshotPublisher.publish(store: store, isAvailable: true,
                now: now.addingTimeInterval(60), allowFreshnessAdvance: false, snapshotStore: snapshotStore)
            repeatedSamples.append((ProcessInfo.processInfo.systemUptime - repeatStart) * 1_000)
            XCTAssertEqual(snapshotStore.load(), first, "Unchanged activity must retain its persisted freshness")

            let projection = store.currentUserCalendarProjection
            let expectedMonths = months.map { month in
                legacyMonth(ownerID: store.currentUser.id, userPlaces: projection.userPlaces,
                    visits: projection.visits, places: projection.places, month: month, calendar: calendar)
            }
            XCTAssertEqual(first, WanderCalendarWidgetSnapshot(generatedAt: now,
                timeZoneIdentifier: calendar.timeZone.identifier, firstWeekday: calendar.firstWeekday,
                weekdaySymbols: WanderWidgetCalendar.rotatedWeekdaySymbols(calendar: calendar),
                previousMonth: expectedMonths[0], currentMonth: expectedMonths[1], nextMonth: expectedMonths[2]))
            XCTAssertEqual([first.previousMonth, first.currentMonth, first.nextMonth].map(\.beenCount), [500, 500, 500])
            XCTAssertEqual([first.previousMonth, first.currentMonth, first.nextMonth].map(\.wannaCount), [0, 0, 0])
            XCTAssertEqual(store.userPlaces.count, 1_500)
            XCTAssertEqual(store.placeVisits.count, 1_500)

            WanderWidgetSnapshotPublisher.publish(store: store, isAvailable: false, now: now,
                snapshotStore: snapshotStore)
            XCTAssertNil(snapshotStore.load())
        }
        let report = "REC675 widget_publication saves=1500 first_samples_ms=\(firstSamples) first_median_ms=\(firstSamples.sorted()[1]) repeated_samples_ms=\(repeatedSamples) repeated_median_ms=\(repeatedSamples.sorted()[1])"
        let attachment = XCTAttachment(string: report)
        attachment.name = "REC675-widget-publication"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(report)
    }

    private func makeFixture(months: [Date], calendar: Calendar) throws -> WanderFixtures {
        let empty = WanderFixtures.empty()
        var places: [LocalPlace] = []
        var saves: [LocalUserPlace] = []
        var visits: [LocalPlaceVisit] = []
        for index in 0..<1_500 {
            let place = LocalPlace(localID: "widget-place-\(index)", serverID: "widget-place-server-\(index)",
                canonicalName: "Widget fixture \(index)", category: index.isMultiple(of: 2) ? "park" : "coffee",
                locality: "Fixture city \(index % 20)", country: "United States",
                latitude: 34 + Double(index / 50) * 0.01, longitude: -118 + Double(index % 50) * 0.01,
                sourceProvider: "fixture", sourceProviderPlaceID: "widget-provider-\(index)")
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: (index / 3) % 28, to: months[index % 3]))
                .addingTimeInterval(12 * 60 * 60)
            let save = LocalUserPlace(localID: "widget-save-\(index)", serverID: "widget-save-server-\(index)",
                userID: empty.currentUser.id, placeID: place.id,
                status: .been, visibility: .selfOnly, visitedAt: date, savedAt: date, sourceType: "manual")
            places.append(place)
            saves.append(save)
            visits.append(LocalPlaceVisit(localID: "widget-visit-\(index)",
                userPlaceID: save.id, visitedAt: date))
        }
        return WanderFixtures(currentUser: empty.currentUser, profiles: [empty.currentUser], places: places,
            userPlaces: saves, placeAttributes: [], placeVisits: visits, follows: [], blocks: [],
            placeLists: [], placeListMembers: [], placeListItems: [], contactProvider: empty.contactProvider)
    }

    /// The publisher's original full-presenter path, outside the measured work.
    private func legacyMonth(ownerID: String, userPlaces: [LocalUserPlace], visits: [LocalPlaceVisit],
                             places: [LocalPlace], month: Date, calendar: Calendar) -> WanderCalendarMonthSnapshot {
        let insights = ProfileInsightsPresenter.present(ownerID: ownerID, userPlaces: userPlaces,
            visits: visits, places: places, month: month, calendar: calendar)
        let start = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let components = calendar.dateComponents([.year, .month], from: start)
        return WanderCalendarMonthSnapshot(year: components.year ?? 1, month: components.month ?? 1,
            title: WanderWidgetCalendar.monthTitle(for: start, calendar: calendar),
            leadingBlankCount: (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7,
            dayCount: calendar.range(of: .day, in: .month, for: start)?.count ?? 28,
            days: insights.monthDaySummaries.values.compactMap { summary in
                guard summary.visitCount > 0 else { return nil }
                return WanderCalendarDaySnapshot(dayNumber: calendar.component(.day, from: summary.date),
                    beenCount: summary.visitCount, wannaCount: 0)
            })
    }
}
