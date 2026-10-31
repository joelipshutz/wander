import Foundation
import XCTest
@testable import Wander

/// Isolates summary work with the same growing local-row/ledger inputs. The
/// reference retains the previous import path's date-normalization cache.
@MainActor
final class ImportSaveStreakSummaryPerformanceTests: XCTestCase {
    func testPerformanceGrowingImportStreakSummariesPreserveEveryOutput() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = Date(timeIntervalSince1970: 1_793_520_000)
        let today = calendar.startOfDay(for: now)
        let historicalDates = try (1...100).map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: -$0, to: today))
        }
        let importedDates = (0..<1_500).map { today.addingTimeInterval(Double($0 + 1)) }
        var referenceMilliseconds: [Double] = []
        var cachedMilliseconds: [Double] = []

        func run(cached: Bool) -> (values: [SaveStreakSummary], milliseconds: Double, computations: Int) {
            let projection = ImportSaveStreakDateProjection()
            var ledger = historicalDates
            var localRows = historicalDates
            var values: [SaveStreakSummary] = []
            values.reserveCapacity(importedDates.count * 2)
            let started = ProcessInfo.processInfo.systemUptime
            func read() -> SaveStreakSummary {
                let dates = ledger + localRows
                if cached {
                    return projection.summary(saveDates: dates, now: now, calendar: calendar)
                }
                return SaveStreakCalculator.summary(
                    saveDates: projection.uniqueDays(in: dates, calendar: calendar),
                    now: now, calendar: calendar)
            }
            for date in importedDates {
                values.append(read())
                ledger.append(date)
                localRows.append(date)
                values.append(read())
            }
            return (values, (ProcessInfo.processInfo.systemUptime - started) * 1_000,
                projection.summaryComputationCount)
        }

        for sample in 0..<3 {
            // Alternate order so the second path does not always get the same
            // thermal/cache advantage. Each run owns a cold scoped projection.
            let first = run(cached: sample.isMultiple(of: 2))
            let second = run(cached: !sample.isMultiple(of: 2))
            let cached = sample.isMultiple(of: 2) ? first : second
            let reference = sample.isMultiple(of: 2) ? second : first
            XCTAssertEqual(cached.values, reference.values)
            XCTAssertEqual(cached.values.count, 3_000)
            XCTAssertEqual(cached.computations, 2)
            XCTAssertEqual(cached.values.first?.currentCount, 100)
            XCTAssertEqual(cached.values.last?.currentCount, 101)
            referenceMilliseconds.append(reference.milliseconds)
            cachedMilliseconds.append(cached.milliseconds)
        }
        let attachment = XCTAttachment(string: "REC675 import_streak_summary old_days=100 new_saves=1500 reads=3000 reference_ms=\(referenceMilliseconds) cached_ms=\(cachedMilliseconds) reference_median_ms=\(referenceMilliseconds.sorted()[1]) cached_median_ms=\(cachedMilliseconds.sorted()[1])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
