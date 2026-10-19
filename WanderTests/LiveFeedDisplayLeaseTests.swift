import XCTest
@testable import Wander

final class LiveFeedDisplayLeaseTests: XCTestCase {
    private let now = ContinuousClock.now

    func testOtherPeopleExpireAtExactlyFifteenMinutesAndOwnActivityDoesNot() {
        var lease = LiveFeedDisplayLease()
        lease.accept(activityIDs: ["friend"], at: now, replacing: true)
        XCTAssertTrue(lease.permits(activityID: "friend", isOwn: false, at: now.advanced(by: .milliseconds(899_999))))
        XCTAssertFalse(lease.permits(activityID: "friend", isOwn: false, at: now.advanced(by: .seconds(900))))
        XCTAssertTrue(lease.permits(activityID: "own", isOwn: true, at: now.advanced(by: .seconds(90_000))))
        XCTAssertFalse(lease.permits(activityID: "unknown", isOwn: false, at: now))
        XCTAssertFalse(lease.permits(activityID: "friend", isOwn: false, at: now.advanced(by: .seconds(-1))))
    }

    func testPagingRenewsOnlyItsRowsAndFullRefreshReplacesReceipts() {
        var lease = LiveFeedDisplayLease()
        lease.accept(activityIDs: ["older"], at: now, replacing: true)
        lease.accept(activityIDs: ["next-page"], at: now.advanced(by: .seconds(800)), replacing: false)
        XCTAssertFalse(lease.permits(activityID: "older", isOwn: false, at: now.advanced(by: .seconds(900))))
        XCTAssertTrue(lease.permits(activityID: "next-page", isOwn: false, at: now.advanced(by: .seconds(900))))
        XCTAssertEqual(lease.nextExpiry(after: now.advanced(by: .seconds(900))), now.advanced(by: .seconds(1700)))
        lease.accept(activityIDs: ["refreshed"], at: now.advanced(by: .seconds(901)), replacing: true)
        XCTAssertFalse(lease.permits(activityID: "next-page", isOwn: false, at: now.advanced(by: .seconds(902))))
        XCTAssertTrue(lease.permits(activityID: "refreshed", isOwn: false, at: now.advanced(by: .seconds(902))))
    }
}
