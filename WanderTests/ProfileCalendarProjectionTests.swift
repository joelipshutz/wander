import Foundation
import XCTest
@testable import Wander

@MainActor
final class ProfileCalendarProjectionTests: XCTestCase {
    func testCalendarProjectionPreservesParentAliasesAndDedupeOrder() throws {
        let calendar = try calendar(timeZone: "UTC")
        let day = try date(2026, 7, 15, calendar: calendar)
        let firstPlace = place("place-local", serverID: "place-server")
        let lastPlace = place("place-local", serverID: "place-last")
        let parents = [
            parent("a-local", serverID: "a-server", placeID: firstPlace.localID),
            parent("a-local", serverID: "b-server", placeID: lastPlace.id),
            parent("wanna-first", serverID: "duplicate-parent", status: .wannaGo),
            parent("been-second", serverID: "duplicate-parent"),
            parent("deleted-first", serverID: "restored-parent", deletedAt: day),
            parent("restored", serverID: "restored-parent", placeID: "missing-place"),
            parent("other-first", serverID: "shared-owner-id", ownerID: "other"),
            parent("own-after-other", serverID: "shared-owner-id"),
            parent("deleted-only", deletedAt: day),
            parent("other-only", ownerID: "other"),
            parent("wanna-only", status: .wannaGo)
        ]
        let visits = [
            visit("local-alias", parentID: "a-local", at: day),
            visit("server-alias", parentID: "a-server", at: day),
            visit("last-parent", parentID: "b-server", at: day),
            visit("restored", parentID: "restored-parent", at: day),
            visit("owner-filter-first", parentID: "shared-owner-id", at: day),
            visit("out-of-month-first", serverID: "duplicate-outside", parentID: "a-server", at: day.addingTimeInterval(-100 * 86_400)),
            visit("in-month-second", serverID: "duplicate-outside", parentID: "a-server", at: day),
            visit("deleted-visit", serverID: "active-visit", parentID: "a-server", at: day, deletedAt: day),
            visit("valid-after-deleted", serverID: "active-visit", parentID: "a-server", at: day),
            visit("orphan-first", serverID: "resolved-visit", parentID: "missing-parent", at: day),
            visit("valid-after-orphan", serverID: "resolved-visit", parentID: "a-server", at: day),
            visit("duplicate-first", serverID: "duplicate-visit", parentID: "a-server", at: day),
            visit("duplicate-second", serverID: "duplicate-visit", parentID: "a-local", at: day),
            visit("wanna-wins", parentID: "duplicate-parent", at: day),
            visit("deleted-parent", parentID: "deleted-only", at: day),
            visit("other-parent", parentID: "other-only", at: day),
            visit("wanna-parent", parentID: "wanna-only", at: day)
        ]
        let result = assertParity(ownerID: "owner", parents: parents, visits: visits,
            places: [firstPlace, lastPlace], months: [day], calendar: calendar)
        let summary = try XCTUnwrap(result[0][calendar.startOfDay(for: day)])
        XCTAssertEqual(summary.visitCount, 8)
        XCTAssertEqual(summary.visitPlaceIDs, ["missing-place", "place-last"])
        XCTAssertEqual(summary.wannaCount, 0)
        XCTAssertTrue(summary.wannaPlaceIDs.isEmpty)
    }

    func testCalendarProjectionPreservesMonthEndpointsDSTLeapDaysAndRequestedOrder() throws {
        let saved = parent("save")
        for zone in ["UTC", "America/Los_Angeles", "Asia/Kathmandu", "Pacific/Apia"] {
            let calendar = try calendar(timeZone: zone)
            for (year, month) in [(2024, 2), (2026, 3), (2026, 12)] {
                let middle = try date(year, month, 15, calendar: calendar)
                let start = try XCTUnwrap(calendar.dateInterval(of: .month, for: middle)?.start)
                let next = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: start))
                let previous = try XCTUnwrap(calendar.date(byAdding: .month, value: -1, to: start))
                let dates = [previous, start.addingTimeInterval(-0.001), start, middle,
                    next.addingTimeInterval(-0.001), next, next.addingTimeInterval(0.001)]
                let visits = dates.enumerated().map { visit("visit-\($0.offset)", parentID: saved.id, at: $0.element) }
                let months = [next, previous, middle, middle]
                let result = assertParity(ownerID: "owner", parents: [saved], visits: visits,
                    places: [], months: months, calendar: calendar)
                XCTAssertEqual(result[2], result[3], "Repeated requested months retain their position")
                XCTAssertEqual(result[2][calendar.startOfDay(for: next)]?.visitCount, 1,
                    "The original DateInterval.contains includes the exact next-month endpoint")
            }
        }
        XCTAssertEqual(ProfileInsightsPresenter.calendarDaySummaries(ownerID: "owner", userPlaces: [saved],
            visits: [], places: [], months: []), [])
    }

    func testCalendarProjectionReadsMutableModelsAndCurrentOwnerOnEveryCall() throws {
        let calendar = try calendar(timeZone: "America/Los_Angeles")
        let firstMonth = try date(2026, 10, 15, calendar: calendar)
        let nextMonth = try date(2026, 11, 15, calendar: calendar)
        let saved = parent("save", serverID: "server-save")
        let other = parent("other-save", ownerID: "other")
        let place = place("place-local", serverID: "place-server")
        saved.placeID = place.localID
        let ownVisit = visit("visit", parentID: saved.localID, at: firstMonth)
        let otherVisit = visit("other-visit", parentID: other.id, at: nextMonth)
        func project(_ ownerID: String = "owner") -> [[Date: ProfileCalendarDaySummary]] {
            assertParity(ownerID: ownerID, parents: [saved, other], visits: [ownVisit, otherVisit],
                places: [place], months: [firstMonth, nextMonth], calendar: calendar)
        }
        XCTAssertEqual(project()[0].values.first?.visitPlaceIDs, [place.id])
        ownVisit.visitedAt = nextMonth
        place.serverID = "remapped-place"
        XCTAssertTrue(project()[0].isEmpty)
        XCTAssertEqual(project()[1].values.first?.visitPlaceIDs, ["remapped-place"])
        ownVisit.deletedAt = nextMonth
        XCTAssertTrue(project().allSatisfy(\.isEmpty))
        ownVisit.deletedAt = nil
        saved.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertTrue(project().allSatisfy(\.isEmpty))
        saved.statusRaw = PlaceStatus.been.rawValue
        saved.deletedAt = nextMonth
        XCTAssertTrue(project().allSatisfy(\.isEmpty))
        saved.deletedAt = nil
        XCTAssertEqual(project("other")[1].values.first?.visitCount, 1)
        saved.userID = "other"
        XCTAssertTrue(project().allSatisfy(\.isEmpty))
        XCTAssertEqual(project("other")[1].values.first?.visitCount, 2)
    }

    @discardableResult
    private func assertParity(ownerID: String, parents: [LocalUserPlace], visits: [LocalPlaceVisit],
                              places: [LocalPlace], months: [Date], calendar: Calendar,
                              file: StaticString = #filePath, line: UInt = #line) -> [[Date: ProfileCalendarDaySummary]] {
        let actual = ProfileInsightsPresenter.calendarDaySummaries(ownerID: ownerID, userPlaces: parents,
            visits: visits, places: places, months: months, calendar: calendar)
        let expected = months.map {
            legacyDays(ownerID: ownerID, parents: parents, visits: visits, places: places, month: $0, calendar: calendar)
        }
        XCTAssertEqual(actual, expected, file: file, line: line)
        for (index, month) in months.enumerated() {
            XCTAssertEqual(ProfileInsightsPresenter.present(ownerID: ownerID, userPlaces: parents,
                visits: visits, places: places, month: month, calendar: calendar).monthDaySummaries,
                expected[index], file: file, line: line)
        }
        return actual
    }

    /// Independent copy of the original calendar selection, before extraction.
    private func legacyDays(ownerID: String, parents: [LocalUserPlace], visits: [LocalPlaceVisit],
                            places: [LocalPlace], month: Date, calendar: Calendar) -> [Date: ProfileCalendarDaySummary] {
        var seenParents = Set<String>()
        let activeParents = parents.filter { $0.userID == ownerID && $0.deletedAt == nil }
            .filter { seenParents.insert($0.id).inserted }.filter { $0.status == .been }
        var parentByID: [String: LocalUserPlace] = [:]
        for parent in activeParents {
            parentByID[parent.id] = parent
            parentByID[parent.localID] = parent
            if let serverID = parent.serverID { parentByID[serverID] = parent }
        }
        var placeByID: [String: LocalPlace] = [:]
        for place in places {
            placeByID[place.id] = place
            placeByID[place.localID] = place
            if let serverID = place.serverID { placeByID[serverID] = place }
        }
        var seenVisits = Set<String>()
        let activeVisits = visits.filter { $0.deletedAt == nil && parentByID[$0.userPlaceID] != nil }
            .filter { seenVisits.insert($0.id).inserted }
        let interval = calendar.dateInterval(of: .month, for: month)
        let monthVisits = activeVisits.filter { interval?.contains($0.visitedAt) == true }
        var counts: [Date: Int] = [:]
        var ids: [Date: Set<String>] = [:]
        for visit in monthVisits {
            let day = calendar.startOfDay(for: visit.visitedAt)
            counts[day, default: 0] += 1
            if let parent = parentByID[visit.userPlaceID] {
                ids[day, default: []].insert(placeByID[parent.placeID]?.id ?? parent.placeID)
            }
        }
        return Dictionary(uniqueKeysWithValues: counts.map { day, count in
            (day, ProfileCalendarDaySummary(date: day, visitCount: count, wannaCount: 0,
                visitPlaceIDs: ids[day, default: []].sorted(), wannaPlaceIDs: []))
        })
    }

    private func calendar(timeZone: String) throws -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        result.locale = Locale(identifier: "en_US_POSIX")
        result.firstWeekday = 2
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }
    private func parent(_ localID: String, serverID: String? = nil, placeID: String = "place-local",
                        ownerID: String = "owner", status: PlaceStatus = .been, deletedAt: Date? = nil) -> LocalUserPlace {
        LocalUserPlace(localID: localID, serverID: serverID, userID: ownerID, placeID: placeID,
            status: status, visibility: .selfOnly, sourceType: "manual", deletedAt: deletedAt)
    }
    private func place(_ localID: String, serverID: String? = nil) -> LocalPlace {
        LocalPlace(localID: localID, serverID: serverID, canonicalName: localID, category: "park",
            latitude: 34, longitude: -118)
    }
    private func visit(_ localID: String, serverID: String? = nil, parentID: String, at date: Date,
                       deletedAt: Date? = nil) -> LocalPlaceVisit {
        LocalPlaceVisit(localID: localID, serverID: serverID, userPlaceID: parentID,
            visitedAt: date, deletedAt: deletedAt)
    }
}
