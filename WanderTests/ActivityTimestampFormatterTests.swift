import Foundation
import XCTest
@testable import Wander

final class ActivityTimestampFormatterTests: XCTestCase {
    func testOldDatesMatchFreshFormatterAcrossCalendarsLocalesTimeZonesAndYearBoundaries() {
        for sample in samples() {
            XCTAssertEqual(FeedPresentation.timestampText(for: sample.date, relativeTo: sample.now,
                calendar: sample.calendar), sample.expected)
        }
    }

    func testFreshNowStillChangesRelativeAndYearFormatting() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = Date(timeIntervalSince1970: 1_734_739_200) // December 21, 2024.
        let sixDays = date.addingTimeInterval(6 * 86_400)
        XCTAssertEqual(FeedPresentation.timestampText(for: date, relativeTo: sixDays, calendar: calendar), "6d ago")
        let sevenDays = date.addingTimeInterval(7 * 86_400)
        XCTAssertEqual(FeedPresentation.timestampText(for: date, relativeTo: sevenDays, calendar: calendar),
            fresh(date, now: sevenDays, calendar: calendar))
        let nextYear = Date(timeIntervalSince1970: 1_735_689_600)
        XCTAssertEqual(FeedPresentation.timestampText(for: date, relativeTo: nextYear, calendar: calendar),
            fresh(date, now: nextYear, calendar: calendar))
        XCTAssertNotEqual(FeedPresentation.timestampText(for: date, relativeTo: sevenDays, calendar: calendar),
            FeedPresentation.timestampText(for: date, relativeTo: nextYear, calendar: calendar))
        XCTAssertEqual(FeedPresentation.timestampText(for: nextYear, relativeTo: nextYear, calendar: calendar), "Just now")
    }

    func testConcurrentTimestampReadsNeverMixFormatterConfigurations() {
        let samples = samples()
        let mismatches = TimestampMismatchCount()
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            let sample = samples[index % samples.count]
            let actual = FeedPresentation.timestampText(for: sample.date, relativeTo: sample.now,
                calendar: sample.calendar)
            if actual != sample.expected { mismatches.record() }
        }
        XCTAssertEqual(mismatches.value, 0)
    }

    func testCacheRemainsBoundedAcrossChangingConfigurationsAndRetainsNoDateResults() {
        let cache = ActivityDateFormatterCache(capacity: 3)
        for sample in samples() {
            let format = sample.calendar.isDate(sample.date, equalTo: sample.now, toGranularity: .year)
                ? "MMM d" : "MMM d, yyyy"
            XCTAssertEqual(cache.string(from: sample.date, calendar: sample.calendar, format: format), sample.expected)
            XCTAssertLessThanOrEqual(cache.cachedFormatterCount, 3)
        }
        let calendar = Calendar(identifier: .gregorian)
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(40 * 86_400)
        XCTAssertNotEqual(cache.string(from: first, calendar: calendar, format: "MMM d"),
            cache.string(from: second, calendar: calendar, format: "MMM d"))
    }

    private func samples() -> [TimestampSample] {
        let now = Date(timeIntervalSince1970: 1_735_691_400) // Jan 1 UTC; still Dec 31 in Los Angeles.
        let dates = [-12.0, -370.0, 12.0].map { now.addingTimeInterval($0 * 86_400) }
        var result: [TimestampSample] = []
        for identifier in [Calendar.Identifier.gregorian, .buddhist, .japanese, .hebrew, .islamicCivil] {
            for zone in ["UTC", "America/Los_Angeles", "Asia/Tokyo"] {
                for locale in ["en_US", "fr_FR", "ar_EG", "tr_TR"] {
                    var calendar = Calendar(identifier: identifier)
                    calendar.timeZone = TimeZone(identifier: zone)!
                    calendar.locale = Locale(identifier: locale)
                    calendar.firstWeekday = 2
                    calendar.minimumDaysInFirstWeek = 4
                    for date in dates {
                        result.append(TimestampSample(date: date, now: now, calendar: calendar,
                            expected: fresh(date, now: now, calendar: calendar)))
                    }
                }
            }
        }
        for calendar in [Calendar.current, .autoupdatingCurrent] {
            for date in dates {
                result.append(TimestampSample(date: date, now: now, calendar: calendar,
                    expected: fresh(date, now: now, calendar: calendar)))
            }
        }
        return result
    }

    private func fresh(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }
}

private struct TimestampSample: Sendable {
    let date: Date
    let now: Date
    let calendar: Calendar
    let expected: String
}

private final class TimestampMismatchCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}
