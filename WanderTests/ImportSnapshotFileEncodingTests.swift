import Foundation
import XCTest
@testable import Wander

final class ImportSnapshotFileEncodingTests: XCTestCase {
    func testCheckpointGroupingPolicyChangesOnlyAfterSuccessfulPreparedCommit() throws {
        let encoding = PlaceImportSnapshotFileEncoding(maximumCachedItems: 2)
        var snapshot = fixture()
        let oversized = try encoding.prepare(snapshot)
        XCTAssertFalse(encoding.prefersGroupedProcessingCheckpoints)
        encoding.didPersist(oversized)
        XCTAssertTrue(encoding.prefersGroupedProcessingCheckpoints)
        snapshot.items.removeLast()
        let smaller = try encoding.prepare(snapshot)
        XCTAssertTrue(encoding.prefersGroupedProcessingCheckpoints)
        encoding.didPersist(smaller)
        XCTAssertFalse(encoding.prefersGroupedProcessingCheckpoints)
    }

    func testPerformanceColdAndUnchangedSnapshotEncoding() throws {
        let base = fixture()
        let snapshot = PlaceImportSnapshot(ownerUserID: base.ownerUserID, batches: base.batches,
            items: (0..<1_500).map { base.items[$0 % base.items.count] })
        let encoding = PlaceImportSnapshotFileEncoding()
        let coldStart = ProcessInfo.processInfo.systemUptime
        let cold = try encoding.prepare(snapshot)
        let coldMS = (ProcessInfo.processInfo.systemUptime - coldStart) * 1_000
        XCTAssertEqual(cold.encodedItemCount, 1_500)
        encoding.didPersist(cold)
        var warmMS: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            let warm = try encoding.prepare(snapshot)
            warmMS.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(warm.encodedItemCount, 0)
            XCTAssertEqual(warm.reusedItemCount, 1_500)
            XCTAssertEqual(warm.data, cold.data)
            encoding.didPersist(warm)
        }
        try assertSchemaParity(cold.data, snapshot)
        let attachment = XCTAttachment(string: "REC675 import_encoding_cache rows=1500 cold_ms=\(coldMS) warm_ms=\(warmMS) warm_median_ms=\(warmMS.sorted()[2]) bytes=\(cold.data.count)")
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFullSchemaMatchesOrdinaryEncoderAndMetadataAlwaysRefreshes() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        let first = try encoding.prepare(snapshot)
        try assertSchemaParity(first.data, snapshot)
        XCTAssertEqual(first.encodedItemCount, 3)
        encoding.didPersist(first)

        snapshot.batches[0].sourceName = "Changed list"
        snapshot.batches[0].sourceListName = nil
        snapshot.batches[0].sourcePostTitle = "Changed title"
        snapshot.batches[0].sourceAuthorName = nil
        snapshot.batches[0].state = .complete
        snapshot.batches[0].totalCount = 9
        snapshot.batches[0].processedCount = 9
        snapshot.batches[0].destinationListID = "new-list"
        snapshot.batches[0].automaticSaveRequested = false
        snapshot.batches[0].automaticSaveCompletedAt = date(40)
        snapshot.batches[0].requestedStatusRaw = PlaceStatus.wannaGo.rawValue
        snapshot.batches[0].requestedRatingScore = nil
        snapshot.batches[0].reviewOpenedAt = date(41)
        snapshot.batches[0].completionNotifiedAt = date(42)
        snapshot.batches[0].updatedAt = date(43)
        snapshot.batches[0].receipt?.presentedAt = date(44)
        let next = try encoding.prepare(snapshot)
        XCTAssertEqual(next.encodedItemCount, 0)
        XCTAssertEqual(next.reusedItemCount, 3)
        try assertSchemaParity(next.data, snapshot)
    }

    func testChangedRowsReencodeAllNestedValues() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        encoding.didPersist(try encoding.prepare(snapshot))
        snapshot.items[1].kind = nil
        snapshot.items[1].seed = PlaceImportSeed(id: "new-seed", rawText: "New \\\" text\n雪",
            nameHint: nil, areaHint: nil, sourceURLString: nil, sourceLine: 55,
            latitude: -12.5, longitude: 52.2, sourceProvider: "other", sourceProviderPlaceID: "other-id",
            socialCaptionHint: "Changed caption", sourceThumbnailURLString: "https://fixture.invalid/new",
            socialUnderstandingRequestID: "new-request")
        snapshot.items[1].state = .saved
        snapshot.items[1].candidates[0].address = "Changed address"
        snapshot.items[1].candidates[0].areaComponents = ["Changed area"]
        snapshot.items[1].selectedCandidateID = nil
        snapshot.items[1].selectedCandidateIDsRaw = []
        snapshot.items[1].helpMessage = nil
        snapshot.items[1].savedUserPlaceID = "new-save"
        snapshot.items[1].duplicateUserPlaceID = nil
        snapshot.items[1].resolverVersion = 99
        snapshot.items[1].pendingManualSearch = false
        snapshot.items[1].stagedStatusRaw = PlaceStatus.wannaGo.rawValue
        snapshot.items[1].stagedNote = "Changed note"
        snapshot.items[1].stagedRatingScore = nil
        snapshot.items[1].stagedVisitedAt = date(99)
        snapshot.items[1].isIncludedInImport = true
        snapshot.items[1].updatedAt = date(100)
        let changed = try encoding.prepare(snapshot)
        XCTAssertEqual(changed.encodedItemCount, 1)
        XCTAssertEqual(changed.reusedItemCount, 2)
        try assertSchemaParity(changed.data, snapshot)
    }

    func testDuplicateIDsReorderRemovalAndInsertionPreserveEveryRow() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        snapshot.items[1] = snapshot.items[0]
        snapshot.items[1].stagedNote = "Same ID, different value"
        encoding.didPersist(try encoding.prepare(snapshot))
        snapshot.items.swapAt(0, 1)
        let reordered = try encoding.prepare(snapshot)
        XCTAssertEqual(reordered.encodedItemCount, 2)
        try assertSchemaParity(reordered.data, snapshot)
        encoding.didPersist(reordered)
        snapshot.items.remove(at: 1)
        let removed = try encoding.prepare(snapshot)
        try assertSchemaParity(removed.data, snapshot)
        encoding.didPersist(removed)
        XCTAssertEqual(encoding.cachedItemCount, 2)
        snapshot.items.insert(snapshot.items[0], at: 1)
        snapshot.items.append(snapshot.items[0])
        try assertSchemaParity(encoding.prepare(snapshot).data, snapshot)
    }

    func testCanonicallyEquivalentTextAndSignedZeroStillReencodeExactValues() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        snapshot.items[0].stagedNote = "Caf\u{00E9}"
        snapshot.items[0].stagedRatingScore = 0.0
        snapshot.items[0].candidates[0].address = "Caf\u{00E9}"
        encoding.didPersist(try encoding.prepare(snapshot))
        let previous = snapshot.items[0]
        snapshot.items[0].stagedNote = "Cafe\u{0301}"
        snapshot.items[0].stagedRatingScore = -0.0
        snapshot.items[0].candidates[0].address = "Cafe\u{0301}"
        XCTAssertEqual(previous, snapshot.items[0], "Value equality alone must not authorize encoding reuse")
        let changed = try encoding.prepare(snapshot)
        XCTAssertEqual(changed.encodedItemCount, 1)
        try assertSchemaParity(changed.data, snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(PlaceImportSnapshot.self, from: changed.data)
        XCTAssertEqual(Array(restored.items[0].stagedNote!.utf8), Array(snapshot.items[0].stagedNote!.utf8))
        XCTAssertEqual(Array(restored.items[0].candidates[0].address!.utf8), Array(snapshot.items[0].candidates[0].address!.utf8))
        XCTAssertEqual(restored.items[0].stagedRatingScore?.bitPattern, (-0.0 as Double).bitPattern)
    }

    func testOwnerVersionAndEmptySnapshotsDropPreviousCache() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        encoding.didPersist(try encoding.prepare(snapshot))
        snapshot.ownerUserID = "other-owner"
        let otherOwner = try encoding.prepare(snapshot)
        XCTAssertEqual(otherOwner.encodedItemCount, 3)
        XCTAssertEqual(encoding.cachedItemCount, 0)
        try assertSchemaParity(otherOwner.data, snapshot)
        encoding.didPersist(otherOwner)
        let otherVersion = PlaceImportSnapshot(version: 999, ownerUserID: snapshot.ownerUserID,
            batches: snapshot.batches, items: snapshot.items)
        let versionChange = try encoding.prepare(otherVersion)
        XCTAssertEqual(versionChange.encodedItemCount, 3)
        try assertSchemaParity(versionChange.data, otherVersion)
        encoding.didPersist(versionChange)
        let empty = PlaceImportSnapshot()
        let cleared = try encoding.prepare(empty)
        try assertSchemaParity(cleared.data, empty)
        encoding.didPersist(cleared)
        XCTAssertEqual(encoding.cachedItemCount, 0)
        XCTAssertEqual(encoding.cachedByteCount, 0)
    }

    func testCacheLimitsBypassRetentionWithoutTruncatingSnapshot() throws {
        let snapshot = fixture()
        for encoding in [PlaceImportSnapshotFileEncoding(maximumCachedItems: 2),
                         PlaceImportSnapshotFileEncoding(maximumCachedBytes: 1)] {
            let first = try encoding.prepare(snapshot)
            try assertSchemaParity(first.data, snapshot)
            encoding.didPersist(first)
            XCTAssertEqual(encoding.cachedItemCount, 0)
            XCTAssertEqual(encoding.cachedByteCount, 0)
            let second = try encoding.prepare(snapshot)
            XCTAssertEqual(second.encodedItemCount, 3)
            XCTAssertEqual(second.reusedItemCount, 0)
            try assertSchemaParity(second.data, snapshot)
        }
    }

    func testPreparedRowsBecomeReusableOnlyAfterSuccessfulWriteCommit() throws {
        let encoding = PlaceImportSnapshotFileEncoding()
        var snapshot = fixture()
        let uncommitted = try encoding.prepare(snapshot)
        XCTAssertEqual(encoding.cachedItemCount, 0)
        XCTAssertEqual(try encoding.prepare(snapshot).encodedItemCount, 3)
        encoding.didPersist(uncommitted)
        snapshot.items[0].stagedNote = "Unwritten change"
        XCTAssertEqual(try encoding.prepare(snapshot).encodedItemCount, 1)
        XCTAssertEqual(try encoding.prepare(snapshot).encodedItemCount, 1)
        encoding.didPersist(try encoding.prepare(snapshot))
        XCTAssertEqual(try encoding.prepare(snapshot).encodedItemCount, 0)
    }

    func testFileWriteFailureKeepsPreviousDocumentAndRetryWritesNewValues() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec675-file-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.json")
        let writer = FailingImportSnapshotWriter()
        let persistence = FilePlaceImportPersistence(fileURL: url, writeData: writer.write)
        var snapshot = fixture()
        try persistence.save(snapshot)
        let original = try Data(contentsOf: url)
        snapshot.ownerUserID = "new-owner"
        snapshot.items[0].stagedNote = "Changed after account handoff"
        writer.failNextWrite = true
        XCTAssertThrowsError(try persistence.save(snapshot))
        XCTAssertEqual(try Data(contentsOf: url), original)
        try persistence.save(snapshot)
        try assertSchemaParity(Data(contentsOf: url), snapshot)
        XCTAssertEqual(try FilePlaceImportPersistence(fileURL: url).load().ownerUserID, "new-owner")
    }

    func testFailedThresholdCrossingKeepsDurableFileAndPolicyUntilRetryThenShrink() throws {
        for threshold in ["rows", "item_bytes", "metadata_bytes"] {
            try autoreleasepool {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("rec675-threshold-retry-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                let url = directory.appendingPathComponent("snapshot.json")
                let writer = FailingImportSnapshotWriter()
                let persistence = FilePlaceImportPersistence(fileURL: url, writeData: writer.write)
                let originalSnapshot = fixture()
                try persistence.save(originalSnapshot)
                let originalData = try Data(contentsOf: url)
                XCTAssertFalse(persistence.prefersGroupedProcessingCheckpoints)

                var oversized = originalSnapshot
                switch threshold {
                case "rows":
                    oversized.items = (0..<4_097).map { originalSnapshot.items[$0 % originalSnapshot.items.count] }
                case "item_bytes":
                    oversized.items[0].stagedNote = String(repeating: "x", count: 8 * 1_024 * 1_024 + 1)
                default:
                    oversized.batches[0].sourcePostTitle = String(repeating: "x", count: 8 * 1_024 * 1_024 + 1)
                }

                writer.failNextWrite = true
                XCTAssertThrowsError(try persistence.save(oversized), threshold)
                XCTAssertTrue(try Data(contentsOf: url) == originalData, "A failed \(threshold) write must retain the complete old document")
                XCTAssertFalse(persistence.prefersGroupedProcessingCheckpoints,
                    "A prepared-but-unwritten \(threshold) snapshot must not change scheduler policy")
                XCTAssertEqual(try persistence.load().items.count, originalSnapshot.items.count)

                try persistence.save(oversized)
                XCTAssertTrue(persistence.prefersGroupedProcessingCheckpoints, threshold)
                try assertSchemaParity(Data(contentsOf: url), oversized)
                XCTAssertEqual(try persistence.load().items.count, oversized.items.count)

                try persistence.save(originalSnapshot)
                XCTAssertFalse(persistence.prefersGroupedProcessingCheckpoints, threshold)
                XCTAssertTrue(try Data(contentsOf: url) == originalData,
                    "A successful shrink must restore the complete original snapshot and rolling checkpoint policy")
            }
        }
    }

    func testEncodingFailureDoesNotReplaceDurableFileAndValidRetrySucceeds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec675-encoding-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("snapshot.json")
        let persistence = FilePlaceImportPersistence(fileURL: url)
        var snapshot = fixture()
        try persistence.save(snapshot)
        let original = try Data(contentsOf: url)
        snapshot.items[1].stagedRatingScore = .nan
        XCTAssertThrowsError(try persistence.save(snapshot))
        XCTAssertEqual(try Data(contentsOf: url), original)
        snapshot.items[1].stagedRatingScore = 3.75
        try persistence.save(snapshot)
        try assertSchemaParity(Data(contentsOf: url), snapshot)
    }

    private func assertSchemaParity(_ data: Data, _ snapshot: PlaceImportSnapshot,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let reference = try encoder.encode(snapshot)
        let actualObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let referenceObject = try XCTUnwrap(JSONSerialization.jsonObject(with: reference) as? NSDictionary)
        XCTAssertEqual(actualObject, referenceObject, file: file, line: line)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(PlaceImportSnapshot.self, from: data),
            try decoder.decode(PlaceImportSnapshot.self, from: reference), file: file, line: line)
    }

    private func date(_ offset: Double = 0) -> Date { Date(timeIntervalSince1970: 1_735_689_600 + offset) }

    private func fixture() -> PlaceImportSnapshot {
        let candidate = PlaceCandidate(id: "candidate", name: "Café \"雪\"", category: "park",
            primaryCategory: "outdoor", subcategory: "garden", categorySource: "provider",
            categoryConfidence: 0.9, rawProviderType: "park", address: "10 Fixture St",
            locality: "Fixture city", region: "CA", country: "US", areaComponents: ["District"],
            latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: "provider-id",
            distanceMeters: 12, websiteURLString: "https://fixture.invalid/path", phoneNumber: "+10000000000",
            timeZoneIdentifier: "America/Los_Angeles", actionLinksJSON: "{\"test\":true}", confidence: 1)
        let seed = PlaceImportSeed(id: "seed", rawText: "Quoted \" text\n雪", nameHint: "Fixture",
            areaHint: "Region", sourceURLString: "https://fixture.invalid/source", sourceLine: 1,
            latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: "source-id",
            socialCaptionHint: "Caption", sourceThumbnailURLString: "https://fixture.invalid/image",
            socialUnderstandingRequestID: "request-id")
        let items = (0..<3).map { index in
            PlaceImportItem(id: "item-\(index)", batchID: "batch", source: .instagram, kind: .sourceRetry,
                seed: seed, state: .failed, candidates: [candidate], selectedCandidateID: candidate.id,
                selectedCandidateIDs: [candidate.id], helpMessage: "Help", savedUserPlaceID: "save",
                duplicateUserPlaceID: "duplicate", resolverVersion: 11, pendingManualSearch: true,
                stagedStatus: .been, stagedNote: "Note \(index)", stagedRatingScore: 4.5,
                stagedVisitedAt: date(3), isIncludedInImport: false, createdAt: date(), updatedAt: date(4))
        }
        let entry = PlaceImportReceiptEntry(id: "entry", itemID: "item-0", displayName: "Fixture",
            displayArea: "Area", status: .been, outcome: .added, userPlaceID: "save",
            savedSelection: PlaceImportSavedSelection(status: .been, visitID: "visit", wannaID: "wanna",
                wannaIsOriginal: true, listIDs: ["list-one", "list-two"], candidateID: candidate.id),
            unfinishedRemoval: PlaceImportSavedSelectionRemoval(itemID: "item-0", status: .been,
                visitID: "visit", wannaID: "wanna", wannaIsOriginal: true, listIDs: ["list-two"]))
        let receipt = PlaceImportReceipt(id: "receipt", batchID: "batch", sourceName: "Source",
            createdAt: date(5), entries: [entry], destinationListID: "list-one", sourceRetryCount: 2,
            presentedAt: date(6))
        var batch = PlaceImportBatch(id: "batch", source: .instagram, sourceName: "Source",
            sourceListName: "List", captureDeliveryID: "delivery", createdAt: date(), updatedAt: date(7),
            state: .ready, totalCount: 3, processedCount: 3, destinationListID: "list-one", receipt: receipt,
            automaticSaveRequested: true, automaticSaveCompletedAt: date(8), requestedStatus: .been,
            requestedRatingScore: 4.5, reviewOpenedAt: date(9))
        batch.sourcePostTitle = "Post title"
        batch.sourceAuthorName = "Author"
        batch.completionNotifiedAt = date(10)
        return PlaceImportSnapshot(ownerUserID: "owner", batches: [batch], items: items)
    }
}

private final class FailingImportSnapshotWriter {
    enum Failure: Error { case requested }
    var failNextWrite = false
    func write(_ data: Data, to url: URL) throws {
        if failNextWrite {
            failNextWrite = false
            throw Failure.requested
        }
        try data.write(to: url, options: .atomic)
    }
}
