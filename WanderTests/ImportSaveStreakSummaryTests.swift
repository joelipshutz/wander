import Foundation
import XCTest
@testable import Wander

@MainActor
final class ImportSaveStreakSummaryTests: XCTestCase {
    func testSameDayAppendsReuseSummaryWhileFreshDatesStillReachNormalization() throws {
        let projection = ImportSaveStreakDateProjection()
        let calendar = try calendar()
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let today = calendar.startOfDay(for: now)
        var saves = try [-4, -3, -2, -1].map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: today))
        }
        XCTAssertEqual(projection.summary(saveDates: saves, now: now, calendar: calendar),
            SaveStreakCalculator.summary(saveDates: saves, now: now, calendar: calendar))
        XCTAssertEqual(projection.summaryComputationCount, 1)

        for index in 0..<64 {
            saves.append(today.addingTimeInterval(Double(index + 1)))
            let sourceDates = saves + saves // Local rows and the durable ledger both contribute.
            XCTAssertEqual(projection.summary(saveDates: sourceDates, now: now, calendar: calendar),
                SaveStreakCalculator.summary(saveDates: sourceDates, now: now, calendar: calendar))
        }
        XCTAssertEqual(projection.summaryComputationCount, 2)
        XCTAssertEqual(projection.normalizationCount, 68)

        // Reordering, duplicate removal and time-of-day edits cannot change a
        // day-derived summary, but must continue to inspect the new dates.
        saves = Array(saves.reversed())
        saves[0] = today.addingTimeInterval(3_600)
        XCTAssertEqual(projection.summary(saveDates: saves, now: now, calendar: calendar),
            SaveStreakCalculator.summary(saveDates: saves, now: now, calendar: calendar))
        XCTAssertEqual(projection.summaryComputationCount, 2)
        XCTAssertEqual(projection.normalizationCount, 69)
    }

    func testDirectInputMutationsRecoveryAndEmptyInputsMatchFreshCalculator() throws {
        let projection = ImportSaveStreakDateProjection()
        let calendar = try calendar()
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) throws -> Date {
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
        }
        var saves = try [-4, -3, -2].map(day)
        var recoveries: [Date] = []
        func assertFresh(file: StaticString = #filePath, line: UInt = #line) -> SaveStreakSummary {
            let result = projection.summary(saveDates: saves, recoveryDates: recoveries,
                now: now, calendar: calendar)
            XCTAssertEqual(result, SaveStreakCalculator.summary(saveDates: saves,
                recoveryDates: recoveries, now: now, calendar: calendar), file: file, line: line)
            return result
        }
        XCTAssertTrue(assertFresh().isRecoveryAvailable)
        recoveries = [try day(-1)]
        XCTAssertFalse(assertFresh().hasRecoveryEntitlement)
        XCTAssertEqual(assertFresh().currentCount, 4)
        saves.append(today)
        XCTAssertEqual(assertFresh().currentCount, 5)
        recoveries.removeAll()
        XCTAssertEqual(assertFresh().currentCount, 1)
        // Editing an existing row, rather than changing the source count, must
        // invalidate the old day set and rebuild both best and current streaks.
        saves[0] = try day(-1)
        XCTAssertEqual(assertFresh().currentCount, 4)
        recoveries = [try day(-30)]
        XCTAssertTrue(assertFresh().hasRecoveryEntitlement)
        recoveries[0] = try day(-29)
        XCTAssertFalse(assertFresh().hasRecoveryEntitlement)
        saves.removeAll()
        recoveries.removeAll()
        XCTAssertEqual(assertFresh().currentCount, 0)
        XCTAssertEqual(assertFresh().bestCount, 0)
    }

    func testDayRolloverAndCalendarConfigurationMatchFreshCalculator() throws {
        let projection = ImportSaveStreakDateProjection()
        let reference = Date(timeIntervalSince1970: 1_793_520_000)
        var configurations: [Calendar] = []
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .islamicCivil] {
            for zone in ["UTC", "America/Los_Angeles", "Asia/Kathmandu"] {
                for locale in ["en_US", "th_TH"] {
                    var value = Calendar(identifier: identifier)
                    value.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
                    value.locale = Locale(identifier: locale)
                    value.firstWeekday = 1
                    value.minimumDaysInFirstWeek = 1
                    configurations.append(value)
                    value.firstWeekday = 2
                    value.minimumDaysInFirstWeek = 4
                    configurations.append(value)
                }
            }
        }
        configurations.append(.autoupdatingCurrent)
        for calendar in configurations {
            let today = calendar.startOfDay(for: reference)
            let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: today))
            let saves = try [-31, -4, -3, -2, 0, 0, 2].map { offset in
                try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: today))
                    .addingTimeInterval(600)
            }
            let recoveries = try [-30, -1].map {
                try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: today))
            }
            for now in [today.addingTimeInterval(-0.001), today, tomorrow.addingTimeInterval(-0.001), tomorrow] {
                let result = projection.summary(saveDates: saves, recoveryDates: recoveries,
                    now: now, calendar: calendar)
                XCTAssertEqual(result, SaveStreakCalculator.summary(saveDates: saves,
                    recoveryDates: recoveries, now: now, calendar: calendar))
                let count = projection.summaryComputationCount
                XCTAssertEqual(projection.summary(saveDates: saves, recoveryDates: recoveries,
                    now: now, calendar: calendar), result)
                XCTAssertEqual(projection.summaryComputationCount, count)
            }
        }
    }

    func testConfigurationChangesInvalidateEvenWhenTheSummaryHappensToBeEqual() throws {
        let projection = ImportSaveStreakDateProjection()
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        var value = try calendar()
        var configurations = [value]
        value.firstWeekday = 2
        configurations.append(value)
        value.minimumDaysInFirstWeek = 4
        configurations.append(value)
        value.locale = Locale(identifier: "th_TH")
        configurations.append(value)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        configurations.append(value)
        value = Calendar(identifier: .buddhist)
        value.timeZone = configurations.last!.timeZone
        value.locale = configurations.last!.locale
        value.firstWeekday = configurations.last!.firstWeekday
        value.minimumDaysInFirstWeek = configurations.last!.minimumDaysInFirstWeek
        configurations.append(value)

        for (index, configuration) in configurations.enumerated() {
            XCTAssertEqual(projection.summary(saveDates: [], now: now, calendar: configuration),
                SaveStreakCalculator.summary(saveDates: [], now: now, calendar: configuration))
            XCTAssertEqual(projection.summaryComputationCount, index + 1)
        }
    }

    private func calendar() throws -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }
}
