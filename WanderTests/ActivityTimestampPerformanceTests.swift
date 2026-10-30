import Foundation
import XCTest
@testable import Wander

/// Calls only the pre-existing API so this exact workload runs on baseline too.
final class ActivityTimestampPerformanceTests: XCTestCase {
    func testPerformanceOlderFeedAndPinTimestamps() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.locale = Locale(identifier: "en_US")
        let now = Date(timeIntervalSince1970: 1_735_691_400)
        let dates = (0..<600).map { now.addingTimeInterval(-Double(8 + $0) * 86_400) }
        let expected = dates.map { FeedPresentation.timestampText(for: $0, relativeTo: now, calendar: calendar) }
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            var values: [String] = []
            values.reserveCapacity(1_200)
            for date in dates {
                // Cards expose a visible timestamp and its accessibility label.
                values.append(FeedPresentation.timestampText(for: date, relativeTo: now, calendar: calendar))
                values.append(FeedPresentation.timestampText(for: date, relativeTo: now, calendar: calendar))
            }
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(values, expected.flatMap { [$0, $0] })
        }
        let attachment = XCTAttachment(string: "REC675 older_activity_timestamps events=600 reads=1200 samples_ms=\(samples) median_ms=\(samples.sorted()[2])")
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
