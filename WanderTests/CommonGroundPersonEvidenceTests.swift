#if DEBUG
import XCTest
@testable import Wander

final class CommonGroundPersonEvidenceTests: XCTestCase {
    func testRepeatedWannasCoexistWithCheckInHistory() {
        let evidence = aggregate([
            record("visit-1", kind: .checkIn),
            record("wanna-1", kind: .wanna),
            record("wanna-2", kind: .wanna),
            record("visit-2", kind: .checkIn)
        ])

        XCTAssertTrue(evidence.hasWanna)
        XCTAssertEqual(evidence.wannaCount, 2)
        XCTAssertEqual(evidence.visitCount, 2)
        XCTAssertEqual(evidence.wannaRecordIDs, ["wanna-1", "wanna-2"])
        XCTAssertEqual(evidence.visitRecordIDs, ["visit-1", "visit-2"])
    }

    func testDuplicateEventSnapshotsDoNotInflateCounts() {
        let wanna = record("same-wanna-operation", kind: .wanna)
        let visit = record("same-visit", kind: .checkIn)
        let evidence = aggregate([wanna, visit, wanna, visit])

        XCTAssertEqual(evidence.wannaCount, 1)
        XCTAssertEqual(evidence.visitCount, 1)
    }

    func testEvidenceRequiresMatchingPersonPlaceAndVisibleLiveRecord() {
        let evidence = aggregate([
            record("other-owner", kind: .wanna, ownerID: "joe"),
            record("other-place", kind: .wanna, canonicalPlaceID: "other-cafe"),
            record("private-wanna", kind: .wanna, isVisible: false),
            record("deleted-wanna", kind: .wanna, isDeleted: true),
            record("private-visit", kind: .checkIn, isVisible: false),
            record("deleted-visit", kind: .checkIn, isDeleted: true),
            record("visible-visit", kind: .checkIn)
        ])

        XCTAssertFalse(evidence.hasWanna)
        XCTAssertEqual(evidence.wannaCount, 0)
        XCTAssertEqual(evidence.visitRecordIDs, ["visible-visit"])
    }

    func testLegacyCurrentWannaCountsButHistoricalSnapshotAloneDoesNot() {
        let history = record("fulfilled-original-wanna", kind: .historicalWanna)
        let visit = record("visit", kind: .checkIn)
        let fulfilled = aggregate([history, visit])
        XCTAssertFalse(fulfilled.hasWanna)
        XCTAssertEqual(fulfilled.visitCount, 1)

        let renewed = aggregate([history, visit, record("legacy-current-wanna", kind: .legacyWanna)])
        XCTAssertTrue(renewed.hasWanna)
        XCTAssertEqual(renewed.wannaRecordIDs, ["legacy-current-wanna"])
        XCTAssertEqual(renewed.visitCount, 1)
    }

    func testNewestDisplayRecordCannotReplaceIndependentWannaEvidence() {
        let records = [
            record("first-wanna", kind: .wanna),
            record("second-wanna", kind: .wanna),
            record("latest-check-in", kind: .checkIn)
        ]
        let forward = aggregate(records)
        let reverse = aggregate(Array(records.reversed()))

        XCTAssertEqual(forward, reverse)
        XCTAssertTrue(forward.hasWanna)
        XCTAssertEqual(forward.wannaCount, 2)
        XCTAssertEqual(forward.visitCount, 1)
    }

    private func aggregate(_ records: [CommonGroundEvidenceRecord]) -> CommonGroundPersonEvidence {
        CommonGroundPersonEvidence.aggregate(personID: "ryan", canonicalPlaceID: "cafe", records: records)
    }

    private func record(
        _ id: String,
        kind: CommonGroundEvidenceRecord.Kind,
        ownerID: String = "ryan",
        canonicalPlaceID: String = "cafe",
        isVisible: Bool = true,
        isDeleted: Bool = false
    ) -> CommonGroundEvidenceRecord {
        CommonGroundEvidenceRecord(
            id: id, ownerID: ownerID, canonicalPlaceID: canonicalPlaceID, kind: kind,
            isVisible: isVisible, isDeleted: isDeleted
        )
    }
}
#endif
