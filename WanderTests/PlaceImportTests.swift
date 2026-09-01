import CoreLocation
import Foundation
import XCTest
@testable import Wander

final class PlaceImportBulkStatusActionTests: XCTestCase {
    func testBulkStatusControlIsAnActionInsteadOfARowStateMirror() {
        XCTAssertNotEqual(
            PlaceImportBulkStatusAction.idleSelectionID,
            PlaceStatus.wannaGo.rawValue
        )
        XCTAssertNotEqual(
            PlaceImportBulkStatusAction.idleSelectionID,
            PlaceStatus.been.rawValue
        )
        XCTAssertNil(
            PlaceImportBulkStatusAction.status(
                for: PlaceImportBulkStatusAction.idleSelectionID
            )
        )
        XCTAssertEqual(
            PlaceImportBulkStatusAction.status(for: PlaceStatus.wannaGo.rawValue),
            .wannaGo
        )
        XCTAssertEqual(
            PlaceImportBulkStatusAction.status(for: PlaceStatus.been.rawValue),
            .been
        )
    }
}

final class PlaceImportReceiptMigrationTests: XCTestCase {
    func testGenericSocialNamedNeedsReviewPlacesSurviveReceiptDecode() throws {
        let instagramPlace = PlaceImportReceiptEntry(
            id: "instagram-retry-entry",
            itemID: "instagram-post-place",
            displayName: "Instagram Post",
            displayArea: nil,
            status: nil,
            outcome: .needsReview,
            userPlaceID: nil
        )
        let tiktokPlace = PlaceImportReceiptEntry(
            id: "tiktok-retry-entry",
            itemID: "tiktok-post-place",
            displayName: "TikTok Post",
            displayArea: nil,
            status: nil,
            outcome: .needsReview,
            userPlaceID: nil
        )
        let receipt = PlaceImportReceipt(
            id: "generic-place-receipt",
            batchID: "generic-place-batch",
            sourceName: "Social import",
            createdAt: Date(timeIntervalSince1970: 1_777_000_000),
            entries: [instagramPlace, tiktokPlace],
            destinationListID: nil
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let decoded = try decoder.decode(
            PlaceImportReceipt.self,
            from: encoder.encode(receipt)
        )

        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(decoded.entries, [instagramPlace, tiktokPlace])
        XCTAssertEqual(decoded.needsReviewCount, 2)
        XCTAssertEqual(decoded.sourceRetryCount, 0)
    }

    func testNewFormatScanStatusRoundTripsIdempotently() throws {
        let receipt = PlaceImportReceipt(
            id: "new-format-receipt",
            batchID: "new-format-batch",
            sourceName: "Instagram",
            entries: [],
            destinationListID: nil,
            sourceRetryCount: 1
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let decoded = try decoder.decode(
            PlaceImportReceipt.self,
            from: encoder.encode(receipt)
        )

        XCTAssertEqual(decoded, receipt)
        XCTAssertEqual(decoded.sourceRetryCount, 1)
        XCTAssertEqual(
            try decoder.decode(PlaceImportReceipt.self, from: encoder.encode(decoded)),
            decoded
        )
    }
}

final class PlaceImportAutoSavePolicyTests: XCTestCase {
    func testCompletedAutomaticImportRestoresUnpresentedVerificationAfterRelaunch() {
        let pendingReceipt = PlaceImportReceipt(
            batchID: "pending",
            sourceName: "Instagram",
            entries: [
                PlaceImportReceiptEntry(
                    itemID: "item",
                    displayName: "Maru Coffee",
                    displayArea: "Los Angeles",
                    status: .wannaGo,
                    outcome: .added,
                    userPlaceID: "saved-place"
                )
            ],
            destinationListID: nil
        )
        var pending = PlaceImportBatch(
            id: "pending",
            source: .instagram,
            sourceName: "Instagram",
            createdAt: Date(timeIntervalSince1970: 10),
            totalCount: 1,
            receipt: pendingReceipt,
            automaticSaveRequested: true
        )
        pending.automaticSaveCompletedAt = Date(timeIntervalSince1970: 20)

        var alreadyPresented = PlaceImportBatch(
            id: "presented",
            source: .instagram,
            sourceName: "Instagram",
            createdAt: Date(timeIntervalSince1970: 5),
            totalCount: 1,
            receipt: PlaceImportReceipt(
                batchID: "presented",
                sourceName: "Instagram",
                entries: pendingReceipt.entries,
                destinationListID: nil,
                presentedAt: Date(timeIntervalSince1970: 15)
            ),
            automaticSaveRequested: true
        )
        alreadyPresented.automaticSaveCompletedAt = Date(timeIntervalSince1970: 12)

        XCTAssertEqual(
            PlaceImportAutoSavePolicy.pendingVerificationBatchIDs(
                in: [alreadyPresented, pending]
            ),
            ["pending"]
        )
    }

    func testCompletedAutomaticImportRestoresSourceScanStatusWithoutPlaceRows() {
        var batch = PlaceImportBatch(
            id: "scan-status",
            source: .instagram,
            sourceName: "Instagram",
            totalCount: 0,
            receipt: PlaceImportReceipt(
                batchID: "scan-status",
                sourceName: "Instagram",
                entries: [],
                destinationListID: nil,
                sourceRetryCount: 1
            ),
            automaticSaveRequested: true
        )
        batch.automaticSaveCompletedAt = Date(timeIntervalSince1970: 20)

        XCTAssertEqual(
            PlaceImportAutoSavePolicy.pendingVerificationBatchIDs(in: [batch]),
            ["scan-status"]
        )
    }

    func testIncompleteSourceScanNotificationDoesNotCountStatusAsAPlace() {
        let copy = PlaceImportFinishedNotificationCopy.make(
            savedCount: 3,
            needsReviewCount: 0,
            sourceRetryCount: 1
        )

        XCTAssertEqual(copy.title, "3 places saved")
        XCTAssertTrue(copy.body.contains("retry the incomplete source scan"))
        XCTAssertFalse(copy.body.contains("review 1 more"))
    }

    func testIncompleteSourceScanNotificationPluralizesMultipleRetries() {
        let copy = PlaceImportFinishedNotificationCopy.make(
            savedCount: 0,
            needsReviewCount: 0,
            sourceRetryCount: 2
        )

        XCTAssertEqual(copy.title, "2 source scans need a retry")
        XCTAssertEqual(copy.body, "Open rec.me to retry 2 incomplete source scans.")
    }

    func testWannaAutoSavesEverySelectedConfidentMatch() {
        let first = readyItem(id: "first")
        let second = readyItem(id: "second")
        let excluded = readyItem(id: "excluded", isIncluded: false)
        let batch = automaticBatch(status: .wannaGo, count: 3)

        XCTAssertEqual(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [(batch, [first, second, excluded])]
            ),
            ["first", "second"]
        )
    }

    func testCheckInAutoSavesOnlyOneConfidentPlace() {
        let first = readyItem(id: "first")
        let second = readyItem(id: "second")

        XCTAssertEqual(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [(automaticBatch(status: .been, count: 1), [first])]
            ),
            ["first"]
        )
        XCTAssertTrue(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [(automaticBatch(status: .been, count: 2), [first, second])]
            ).isEmpty
        )
    }

    func testCheckInSafetyAppliesAcrossEveryBatchFromOneShare() {
        let firstBatch = automaticBatch(status: .been, count: 1)
        let secondBatch = PlaceImportBatch(
            id: "second-batch",
            source: .textNotes,
            sourceName: "Shared text",
            captureDeliveryID: "shared-capture:1",
            totalCount: 1,
            automaticSaveRequested: true,
            requestedStatus: .been
        )

        XCTAssertTrue(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [
                    (firstBatch, [readyItem(id: "first")]),
                    (secondBatch, [readyItem(id: "second")])
                ]
            ).isEmpty
        )
    }

    func testSeparateSinglePlaceCheckInSharesCanBothAutoSave() {
        let firstBatch = automaticBatch(status: .been, count: 1)
        let secondBatch = PlaceImportBatch(
            id: "second-batch",
            source: .instagram,
            sourceName: "Instagram",
            captureDeliveryID: "another-capture:0",
            totalCount: 1,
            automaticSaveRequested: true,
            requestedStatus: .been
        )

        XCTAssertEqual(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [
                    (firstBatch, [readyItem(id: "first")]),
                    (secondBatch, [readyItem(id: "second")])
                ]
            ),
            ["first", "second"]
        )
    }

    func testLegacyReviewFirstBatchNeverAutoSaves() {
        let batch = PlaceImportBatch(
            source: .instagram,
            sourceName: "Instagram",
            totalCount: 1
        )

        XCTAssertTrue(
            PlaceImportAutoSavePolicy.committableItemIDs(
                batchItems: [(batch, [readyItem(id: "first")])]
            ).isEmpty
        )
    }

    private func automaticBatch(status: PlaceStatus, count: Int) -> PlaceImportBatch {
        PlaceImportBatch(
            id: "first-batch",
            source: .instagram,
            sourceName: "Instagram",
            captureDeliveryID: "shared-capture:0",
            totalCount: count,
            automaticSaveRequested: true,
            requestedStatus: status
        )
    }

    private func readyItem(id: String, isIncluded: Bool = true) -> PlaceImportItem {
        let candidate = placeImportCandidate(name: id)
        return PlaceImportItem(
            id: id,
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: id,
                nameHint: id,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            isIncludedInImport: isIncluded
        )
    }
}

@MainActor
final class PlaceImportAutoSaveCoordinatorTests: XCTestCase {
    func testSourceRetryIsReceiptScanStatusInsteadOfAPlaceNeedingReview() async throws {
        let batchID = "partial-social-import"
        let candidate = placeImportCandidate(name: "Maru Coffee")
        let place = PlaceImportItem(
            id: "maru",
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: "Los Angeles",
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        let sourceRetry = PlaceImportItem(
            id: "source-retry",
            batchID: batchID,
            source: .instagram,
            kind: .sourceRetry,
            seed: PlaceImportSeed(
                rawText: "https://www.instagram.com/p/partial/",
                nameHint: nil,
                areaHint: nil,
                sourceURLString: "https://www.instagram.com/p/partial/",
                sourceLine: 1
            ),
            state: .needsHelp,
            helpMessage: "Some media in this post could not be read. Retry automatic matching to look for more places."
        )
        let importStore = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(
                    ownerUserID: "user_live",
                    batches: [
                        PlaceImportBatch(
                            id: batchID,
                            source: .instagram,
                            sourceName: "Instagram",
                            state: .ready,
                            totalCount: 1,
                            processedCount: 1,
                            automaticSaveRequested: true,
                            requestedStatus: .wannaGo
                        )
                    ],
                    items: [place, sourceRetry]
                )
            ),
            resolver: FakePlaceImportResolver()
        )
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
            )
        )

        let result = await PlaceImportAutoSaveCoordinator.process(
            batchIDs: [batchID],
            importStore: importStore,
            store: store,
            expectedUserID: "user_live",
            isAuthorized: { true }
        )
        let receipt = try XCTUnwrap(importStore.batches.first?.receipt)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertEqual(result.sourceRetryCount, 1)
        XCTAssertEqual(receipt.entries.map(\.itemID), [place.id])
        XCTAssertEqual(receipt.needsReviewCount, 0)
        XCTAssertEqual(receipt.sourceRetryCount, 1)
        XCTAssertEqual(importStore.item(id: sourceRetry.id)?.state, .needsHelp)
    }

    func testFortyFivePlaceImportPersistsEachStoreOnce() async {
        let batchID = "google-list"
        let items = (1...45).map { index in
            let candidate = PlaceCandidate(
                id: "candidate-\(index)",
                name: "Bakery \(index)",
                category: "bakery",
                latitude: 34 + Double(index) / 10_000,
                longitude: -118 - Double(index) / 10_000,
                sourceProvider: "google_maps",
                sourceProviderPlaceID: "google-place-\(index)",
                confidence: 1
            )
            return PlaceImportItem(
                id: "item-\(index)",
                batchID: batchID,
                source: .googleMaps,
                seed: PlaceImportSeed(
                    rawText: candidate.name,
                    nameHint: candidate.name,
                    areaHint: "Los Angeles",
                    sourceURLString: nil,
                    sourceLine: index,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    sourceProvider: candidate.sourceProvider,
                    sourceProviderPlaceID: candidate.sourceProviderPlaceID
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id
            )
        }
        let importPersistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                ownerUserID: "user_live",
                batches: [
                    PlaceImportBatch(
                        id: batchID,
                        source: .googleMaps,
                        sourceName: "Ryan’s Bakeries",
                        state: .ready,
                        totalCount: items.count,
                        processedCount: items.count,
                        automaticSaveRequested: true,
                        requestedStatus: .wannaGo
                    )
                ],
                items: items
            )
        )
        let importStore = PlaceImportStore(
            persistence: importPersistence,
            resolver: FakePlaceImportResolver()
        )
        var storeSaveCount = 0
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { _ in storeSaveCount += 1 }
        )
        let store = WanderStore(
            fixtures: WanderFixtures.empty(),
            persistence: persistence
        )
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
            )
        )
        storeSaveCount = 0

        let result = await PlaceImportAutoSaveCoordinator.process(
            batchIDs: [batchID],
            importStore: importStore,
            store: store,
            expectedUserID: "user_live",
            isAuthorized: { true }
        )

        XCTAssertEqual(result.addedCount, 45)
        XCTAssertEqual(result.needsReviewCount, 0)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 45)
        XCTAssertEqual(store.visiblePlaceLists.first?.cachedItemCount, 45)
        XCTAssertEqual(storeSaveCount, 1)
        XCTAssertEqual(importPersistence.saveCount, 1)
        XCTAssertNotNil(importStore.batches.first?.automaticSaveCompletedAt)
        XCTAssertEqual(importStore.batches.first?.receipt?.entries.count, 45)
    }

    func testAccountMismatchStopsBeforeAnyImportMutation() async {
        let batchID = "account-a-batch"
        let candidate = placeImportCandidate(name: "Maru")
        let item = PlaceImportItem(
            id: "maru",
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        let importPersistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                ownerUserID: "account-a",
                batches: [
                    PlaceImportBatch(
                        id: batchID,
                        source: .instagram,
                        sourceName: "Instagram",
                        state: .ready,
                        totalCount: 1,
                        processedCount: 1,
                        automaticSaveRequested: true,
                        requestedStatus: .wannaGo
                    )
                ],
                items: [item]
            )
        )
        let importStore = PlaceImportStore(
            persistence: importPersistence,
            resolver: FakePlaceImportResolver()
        )
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "account-b", displayName: "B", handle: "b")
            )
        )

        let result = await PlaceImportAutoSaveCoordinator.process(
            batchIDs: [batchID],
            importStore: importStore,
            store: store,
            expectedUserID: "account-a",
            isAuthorized: { false }
        )

        XCTAssertFalse(result.hasResult)
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty)
        XCTAssertEqual(importStore.item(id: item.id)?.state, .ready)
        XCTAssertNil(importStore.batches.first?.automaticSaveCompletedAt)
        XCTAssertEqual(importPersistence.saveCount, 0)
    }

    func testDuplicateRowsShareOneSaveAndOnlyFirstReceiptEntryIsAdded() async throws {
        let batchID = "duplicate-rows"
        let candidate = placeImportCandidate(name: "Maru")
        let items = ["first", "second"].enumerated().map { index, id in
            PlaceImportItem(
                id: id,
                batchID: batchID,
                source: .googleMaps,
                seed: PlaceImportSeed(
                    rawText: candidate.name,
                    nameHint: candidate.name,
                    areaHint: "Los Angeles",
                    sourceURLString: nil,
                    sourceLine: index
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id
            )
        }
        let importStore = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(
                    ownerUserID: "user_live",
                    batches: [
                        PlaceImportBatch(
                            id: batchID,
                            source: .googleMaps,
                            sourceName: "Saved places",
                            state: .ready,
                            totalCount: items.count,
                            processedCount: items.count,
                            automaticSaveRequested: true,
                            requestedStatus: .wannaGo
                        )
                    ],
                    items: items
                )
            ),
            resolver: FakePlaceImportResolver()
        )
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
            )
        )

        let result = await PlaceImportAutoSaveCoordinator.process(
            batchIDs: [batchID],
            importStore: importStore,
            store: store,
            expectedUserID: "user_live",
            isAuthorized: { true }
        )
        let receipt = try XCTUnwrap(importStore.batches.first?.receipt)

        XCTAssertEqual(result.addedCount, 1)
        XCTAssertEqual(result.existingCount, 1)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
        XCTAssertEqual(receipt.entries.map(\.outcome), [.added, .existing])
        XCTAssertEqual(Set(receipt.entries.compactMap(\.userPlaceID)).count, 1)
    }

    func testExactSaveMatcherProtectsPreexistingMemoryWhenReconciliationMissesRename() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
            )
        )
        let original = PlaceCandidate(
            id: "old-candidate-id",
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.0522,
            longitude: -118.2437,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "provider-123",
            confidence: 0.95
        )
        let existingResult = store.saveCandidate(
            original,
            status: .wannaGo,
            visibility: .selfOnly,
            note: "keep my note",
            sourceType: .manual
        )
        let renamedImport = PlaceCandidate(
            id: "provider-123",
            name: "Maru Arts District",
            category: "coffee",
            latitude: 34.0522,
            longitude: -118.2437,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: nil,
            confidence: 0.95
        )
        let batchID = "renamed-existing"
        let item = PlaceImportItem(
            id: "renamed-item",
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: renamedImport.name,
                nameHint: renamedImport.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [renamedImport],
            selectedCandidateID: renamedImport.id
        )
        let importStore = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(
                    ownerUserID: "user_live",
                    batches: [
                        PlaceImportBatch(
                            id: batchID,
                            source: .instagram,
                            sourceName: "Instagram",
                            state: .ready,
                            totalCount: 1,
                            processedCount: 1,
                            automaticSaveRequested: true,
                            requestedStatus: .wannaGo
                        )
                    ],
                    items: [item]
                )
            ),
            resolver: FakePlaceImportResolver()
        )

        let result = await PlaceImportAutoSaveCoordinator.process(
            batchIDs: [batchID],
            importStore: importStore,
            store: store,
            expectedUserID: "user_live",
            isAuthorized: { true }
        )
        let receiptEntry = try XCTUnwrap(importStore.batches.first?.receipt?.entries.first)
        let visiblePlace = try XCTUnwrap(store.currentUserVisiblePlaces.first)

        XCTAssertEqual(result.addedCount, 0)
        XCTAssertEqual(result.existingCount, 1)
        XCTAssertEqual(receiptEntry.outcome, .existing)
        XCTAssertEqual(receiptEntry.userPlaceID, existingResult.userPlaceID)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
        XCTAssertEqual(visiblePlace.userPlace.note, "keep my note")
    }
}

final class PlaceImportParserTests: XCTestCase {
    func testParsesAndDeduplicatesTextNotes() throws {
        let seeds = try PlaceImportParser.parse(
            source: .textNotes,
            text: """
            - Maru Coffee, Los Angeles
            maru coffee, LOS ANGELES
            1. Gjusta | Venice
            Night + Market - West Hollywood
            """
        )

        XCTAssertEqual(seeds.count, 3)
        XCTAssertEqual(seeds[0].nameHint, "Maru Coffee")
        XCTAssertEqual(seeds[0].areaHint, "Los Angeles")
        XCTAssertEqual(seeds[1].nameHint, "Gjusta")
        XCTAssertEqual(seeds[1].areaHint, "Venice")
        XCTAssertEqual(seeds[2].nameHint, "Night + Market")
        XCTAssertEqual(seeds[2].areaHint, "West Hollywood")
    }

    func testParsesThreeHundredRowQuotedTakeoutCSV() throws {
        let rows = (1...300).map { index in
            "\"Coffee Shop \(index), Roasters\",\"\(index) Main St, Los Angeles, CA\",https://maps.google.com/?cid=\(index)"
        }
        let csv = (["name,address,url"] + rows).joined(separator: "\n")

        let seeds = try PlaceImportParser.parse(
            source: .googleMaps,
            text: csv,
            fileName: "Saved Places.csv"
        )

        XCTAssertEqual(seeds.count, 300)
        XCTAssertEqual(seeds.first?.nameHint, "Coffee Shop 1, Roasters")
        XCTAssertEqual(seeds.first?.areaHint, "1 Main St, Los Angeles, CA")
        XCTAssertEqual(seeds.last?.sourceLine, 301)
    }

    func testParsesNestedTakeoutJSON() throws {
        let json = """
        {
          "features": [
            {"name": "Botanica", "address": "Silver Lake", "url": "https://maps.google.com/?cid=1"},
            {"title": "Gjusta", "city": "Venice", "google maps url": "https://maps.google.com/?cid=2"}
          ]
        }
        """

        let seeds = try PlaceImportParser.parse(
            source: .googleMaps,
            text: json,
            fileName: "Saved Places.json"
        )

        XCTAssertEqual(seeds.count, 2)
        XCTAssertEqual(Set(seeds.compactMap(\.nameHint)), ["Botanica", "Gjusta"])
    }

    func testPreservesSocialURLAndManualHint() throws {
        let seeds = try PlaceImportParser.parse(
            source: .instagram,
            text: "Gjusta | Venice https://www.instagram.com/reel/example/"
        )

        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(seeds[0].nameHint, "Gjusta")
        XCTAssertEqual(seeds[0].areaHint, "Venice")
        XCTAssertEqual(seeds[0].sourceURLString, "https://www.instagram.com/reel/example/")
    }

    func testPreservesInstagramShortcodeContainingDoubleHyphen() throws {
        let sourceURL = "https://www.instagram.com/p/Db--aE4DIh1/"

        let seeds = try PlaceImportParser.parse(source: .textNotes, text: sourceURL)

        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(seeds[0].rawText, sourceURL)
        XCTAssertEqual(seeds[0].sourceURLString, sourceURL)
        XCTAssertNil(seeds[0].nameHint)
        XCTAssertEqual(PlaceImportSourceDetector.source(for: seeds[0]), .instagram)
    }

    func testRepairsInstagramURLChangedBySmartTextInput() throws {
        let seeds = try PlaceImportParser.parse(
            source: .textNotes,
            text: "Https://www.instagram.com/p/Db\u{2014}aE4DIh1/"
        )

        XCTAssertEqual(seeds.count, 1)
        XCTAssertEqual(seeds[0].rawText, "https://www.instagram.com/p/Db--aE4DIh1/")
        XCTAssertEqual(seeds[0].sourceURLString, "https://www.instagram.com/p/Db--aE4DIh1/")
        XCTAssertNil(seeds[0].nameHint)
        XCTAssertEqual(PlaceImportSourceDetector.source(for: seeds[0]), .instagram)
    }
}

final class GoogleMapsSharedListParserTests: XCTestCase {
    func testExpandsEveryPlaceInAFortyFiveItemList() throws {
        let list = try GoogleMapsSharedListParser.parse(googleSharedListPayload(count: 45))

        XCTAssertEqual(list.name, "Ryan's Bakeries")
        XCTAssertEqual(list.seeds.count, 45)
        XCTAssertEqual(list.seeds.first?.nameHint, "Bakery 1")
        XCTAssertEqual(list.seeds.first?.areaHint, "1 Main St, Los Angeles, CA")
        XCTAssertEqual(list.seeds.first?.sourceProvider, "google_maps")
        XCTAssertEqual(list.seeds.first?.sourceProviderPlaceID, "google-place-1")
        XCTAssertEqual(list.seeds.last?.nameHint, "Bakery 45")
        XCTAssertEqual(list.seeds.last?.sourceLine, 45)
    }
}

@MainActor
final class GoogleMapsSharedListImporterTests: XCTestCase {
    func testLoadsTheBulkListEndpointInsteadOfTreatingTheLinkAsOneMapPin() async throws {
        let listURL = try XCTUnwrap(
            URL(string: "https://www.google.com/maps/@/data=!3m1!4b1!4m3!11m2!2slist_45!3e3")
        )
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data("<html></html>".utf8),
                finalURL: listURL,
                statusCode: 200,
                mimeType: "text/html"
            ),
            PlaceImportHTTPResponse(
                data: try googleSharedListPayload(count: 45),
                finalURL: URL(string: "https://www.google.com/maps/preview/entitylist/getlist")!,
                statusCode: 200,
                mimeType: "application/json"
            )
        ])
        let importer = GoogleMapsSharedListImporter(httpClient: client)

        let result = await importer.load(from: URL(string: "https://maps.app.goo.gl/bakeries")!)

        guard case .list(let list) = result else {
            return XCTFail("Expected the public shared list to expand, got \(result)")
        }
        XCTAssertEqual(list.seeds.count, 45)
        XCTAssertEqual(client.requests.count, 2)
        XCTAssertTrue(client.requests[1].url?.absoluteString.contains("4i1000") == true)
    }
}

final class PlaceImportReviewPlanTests: XCTestCase {
    func testAdaptiveRoutingUsesTotalCandidateBoundaries() {
        XCTAssertEqual(plan(ready: 1).surface, .quickAdd)
        XCTAssertEqual(plan(duplicates: 1).surface, .duplicate)
        XCTAssertEqual(plan(ready: 2).surface, .compact)
        XCTAssertEqual(plan(ready: 5).surface, .compact)
        XCTAssertEqual(plan(ready: 6).surface, .batch)
    }

    func testExceptionHeavyBatchKeepsTheDenominatorInTheAction() {
        let review = plan(ready: 1, needsHelp: 99)

        XCTAssertEqual(review.surface, .batch)
        XCTAssertEqual(review.committableCount, 1)
        XCTAssertEqual(review.primaryActionTitle, "Add 1 of 100 places")
    }

    func testProcessingItemsSuppressCommitUntilTheWholeCaptureFinishesResolving() {
        let candidate = placeImportCandidate(name: "Ready")
        let ready = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        let resolving = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "Resolving",
                nameHint: "Resolving",
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .resolving
        )

        let review = PlaceImportReviewPlan(items: [ready, resolving])

        XCTAssertEqual(review.surface, .resolving)
        XCTAssertEqual(review.committableCount, 1)
        XCTAssertNil(review.primaryActionTitle)
    }

    func testStoredReceiptIsTerminalOnlyAfterNoActiveItemsRemain() {
        XCTAssertFalse(
            PlaceImportReceiptPresentationPolicy.canUseStoredReceipt(activeItemCount: 1)
        )
        XCTAssertTrue(
            PlaceImportReceiptPresentationPolicy.canUseStoredReceipt(activeItemCount: 0)
        )
    }

    func testCommitAuthorizationStopsOnCancellationOrAccountChange() {
        XCTAssertTrue(
            PlaceImportCommitAuthorization.isValid(
                expectedUserID: "account-a",
                authUserID: "account-a",
                currentUserID: "account-a",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            PlaceImportCommitAuthorization.isValid(
                expectedUserID: "account-a",
                authUserID: "account-b",
                currentUserID: "account-b",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            PlaceImportCommitAuthorization.isValid(
                expectedUserID: "account-a",
                authUserID: "account-a",
                currentUserID: "account-a",
                isCancelled: true
            )
        )
    }

    func testZeroReadyRoutesToRecoveryWithoutAnAddZeroAction() {
        let review = plan(needsHelp: 3)

        XCTAssertEqual(review.surface, .recovery)
        XCTAssertNil(review.primaryActionTitle)
    }

    func testUnlinkedDuplicateDoesNotOfferAnActionThatCannotCommit() {
        let candidate = placeImportCandidate(name: "Unlinked")
        let item = PlaceImportItem(
            batchID: "batch",
            source: .googleMaps,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .duplicate,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )

        let review = PlaceImportReviewPlan(items: [item])

        XCTAssertEqual(review.surface, .recovery)
        XCTAssertEqual(review.committableCount, 0)
        XCTAssertNil(review.primaryActionTitle)
    }

    func testSingleNewCandidateUsesExplicitWannaAction() {
        XCTAssertEqual(plan(ready: 1).primaryActionTitle, "Add as Wanna")
    }

    func testCheckedSubsetControlsCommitCountWithoutChangingBatchSurface() {
        let firstCandidate = placeImportCandidate(name: "First")
        let secondCandidate = placeImportCandidate(name: "Second")
        let first = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: firstCandidate.name,
                nameHint: firstCandidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [firstCandidate],
            selectedCandidateID: firstCandidate.id
        )
        let second = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: secondCandidate.name,
                nameHint: secondCandidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [secondCandidate],
            selectedCandidateID: secondCandidate.id,
            isIncludedInImport: false
        )
        let recovery = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "Needs help",
                nameHint: "Needs help",
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 2
            ),
            state: .needsHelp,
            isIncludedInImport: false
        )

        let review = PlaceImportReviewPlan(items: [first, second, recovery])

        XCTAssertEqual(review.surface, .compact)
        XCTAssertEqual(review.totalCount, 3)
        XCTAssertEqual(review.selectedCount, 1)
        XCTAssertEqual(review.committableCount, 1)
        XCTAssertEqual(review.primaryActionTitle, "Add 1 place")
    }

    func testCheckedUnresolvedRowsRemainInTheSelectedDenominator() {
        let candidate = placeImportCandidate(name: "Ready")
        let ready = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        let recovery = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "Needs help",
                nameHint: "Needs help",
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .needsHelp
        )

        let review = PlaceImportReviewPlan(items: [ready, recovery])

        XCTAssertEqual(review.selectedCount, 2)
        XCTAssertEqual(review.committableCount, 1)
        XCTAssertEqual(review.primaryActionTitle, "Add 1 of 2 places")
    }

    func testSourceRetryStatusIsNotASelectedPlaceAndKeepsTheCompactSurfaceVisible() {
        let candidate = placeImportCandidate(name: "Ready")
        let ready = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        var retry = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            kind: .sourceRetry,
            seed: PlaceImportSeed(
                rawText: "https://www.instagram.com/p/partial/",
                nameHint: nil,
                areaHint: nil,
                sourceURLString: "https://www.instagram.com/p/partial/",
                sourceLine: 0
            ),
            state: .needsHelp,
            helpMessage: "Some media could not be read. Retry automatic matching."
        )

        retry.isSelectedForImport = true
        let review = PlaceImportReviewPlan(items: [ready, retry])

        XCTAssertFalse(retry.isSelectedForImport)
        XCTAssertEqual(review.surface, .compact)
        XCTAssertEqual(review.totalCount, 1)
        XCTAssertEqual(review.selectedCount, 1)
        XCTAssertEqual(review.needsHelpCount, 0)
        XCTAssertEqual(review.primaryActionTitle, "Add 1 place")
    }

    func testSingleBeenCandidateUsesExplicitBeenAction() {
        let candidate = placeImportCandidate(name: "Visited")
        let item = PlaceImportItem(
            batchID: "batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: candidate.name,
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            stagedStatus: .been
        )

        XCTAssertEqual(PlaceImportReviewPlan(items: [item]).primaryActionTitle, "Add as Been")
    }

    func testDestinationListNameNormalizesBoundsAndCollisionsWithoutSplittingGraphemes() {
        XCTAssertEqual(
            PlaceImportDestinationListName.normalized("  LA\n\t Spots  "),
            "LA Spots"
        )
        XCTAssertEqual(PlaceImportDestinationListName.normalized("\n\t"), "Google Maps Import")

        let family = "👨‍👩‍👧‍👦"
        let longName = String(repeating: family, count: 30)
        let normalized = PlaceImportDestinationListName.normalized(longName)
        XCTAssertLessThanOrEqual(normalized.unicodeScalars.count, 96)
        XCTAssertTrue(normalized.allSatisfy { String($0) == family })

        XCTAssertEqual(
            PlaceImportDestinationListName.unique(
                "LA Spots",
                existingNames: ["LA Spots", "LA Spots — Google Maps"]
            ),
            "LA Spots — Google Maps 2"
        )
    }

    private func plan(
        ready: Int = 0,
        duplicates: Int = 0,
        needsHelp: Int = 0
    ) -> PlaceImportReviewPlan {
        var items: [PlaceImportItem] = []
        for index in 0..<ready {
            let candidate = placeImportCandidate(name: "Ready \(index)")
            items.append(
                PlaceImportItem(
                    batchID: "batch",
                    source: .googleMaps,
                    seed: PlaceImportSeed(
                        rawText: candidate.name,
                        nameHint: candidate.name,
                        areaHint: nil,
                        sourceURLString: nil,
                        sourceLine: index
                    ),
                    state: .ready,
                    candidates: [candidate],
                    selectedCandidateID: candidate.id
                )
            )
        }
        for index in 0..<duplicates {
            let candidate = placeImportCandidate(name: "Existing \(index)")
            items.append(
                PlaceImportItem(
                    batchID: "batch",
                    source: .googleMaps,
                    seed: PlaceImportSeed(
                        rawText: candidate.name,
                        nameHint: candidate.name,
                        areaHint: nil,
                        sourceURLString: nil,
                        sourceLine: ready + index
                    ),
                    state: .duplicate,
                    candidates: [candidate],
                    selectedCandidateID: candidate.id,
                    duplicateUserPlaceID: "existing-\(index)"
                )
            )
        }
        for index in 0..<needsHelp {
            items.append(
                PlaceImportItem(
                    batchID: "batch",
                    source: .googleMaps,
                    seed: PlaceImportSeed(
                        rawText: "Needs help \(index)",
                        nameHint: "Needs help \(index)",
                        areaHint: nil,
                        sourceURLString: nil,
                        sourceLine: ready + duplicates + index
                    ),
                    state: .needsHelp
                )
            )
        }
        return PlaceImportReviewPlan(items: items)
    }
}

@MainActor
final class PlaceImportStoreTests: XCTestCase {
    func testExplicitSocialRetryRotatesRemoteAttemptID() async throws {
        let resolver = RecordingPlaceImportResolver(
            resolution: .needsHelp("Try the remote import again.")
        )
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )
        let batchID = try store.enqueue(
            source: .instagram,
            text: "https://www.instagram.com/reel/retry-attempt/"
        )
        await store.waitForProcessing(batchID: batchID)
        let itemID = try XCTUnwrap(store.items(for: batchID).first?.id)
        let firstSeed = try XCTUnwrap(resolver.seeds.first)

        store.retry(itemID: itemID)
        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(resolver.seeds.count, 2)
        XCTAssertEqual(firstSeed.effectiveSocialUnderstandingRequestID, firstSeed.id)
        XCTAssertNotEqual(
            resolver.seeds[1].effectiveSocialUnderstandingRequestID,
            firstSeed.effectiveSocialUnderstandingRequestID
        )
        XCTAssertEqual(
            store.item(id: itemID)?.seed.socialUnderstandingRequestID,
            resolver.seeds[1].effectiveSocialUnderstandingRequestID
        )
    }

    func testResumedSocialAttemptKeepsPersistedRemoteAttemptID() async throws {
        let requestID = "persisted-social-attempt"
        let sourceURL = "https://www.instagram.com/reel/resumed-attempt/"
        let batch = PlaceImportBatch(
            id: "resumed-social-batch",
            source: .instagram,
            sourceName: nil,
            totalCount: 1
        )
        let item = PlaceImportItem(
            id: "resumed-social-item",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                id: "stable-resumed-seed",
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1,
                socialUnderstandingRequestID: requestID
            ),
            state: .resolving
        )
        let resolver = RecordingPlaceImportResolver(
            resolution: .needsHelp("The resumed attempt finished.")
        )
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
            ),
            resolver: resolver
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertEqual(resolver.seeds.count, 1)
        XCTAssertEqual(resolver.seeds[0].effectiveSocialUnderstandingRequestID, requestID)
    }

    func testReplayRequiredPersistsFreshIDBeforeTheSecondAttempt() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .retrySocialUnderstanding(requestID: "persisted-replay-attempt"),
            .needsHelp("The replay completed without a match.")
        ])
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)
        let batchID = try store.enqueue(
            source: .instagram,
            text: "https://www.instagram.com/reel/persisted-replay/"
        )

        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(resolver.seeds.count, 2)
        XCTAssertNotEqual(
            resolver.seeds[0].effectiveSocialUnderstandingRequestID,
            resolver.seeds[1].effectiveSocialUnderstandingRequestID
        )
        XCTAssertEqual(
            resolver.seeds[1].effectiveSocialUnderstandingRequestID,
            "persisted-replay-attempt"
        )
        XCTAssertEqual(
            persistence.snapshot.items.first?.seed.socialUnderstandingRequestID,
            "persisted-replay-attempt"
        )
    }

    func testPartialSourceRetryMergesNewPlacesWithoutDuplicatingExistingRows() async throws {
        let sourceURL = "https://www.instagram.com/p/partial-source-retry/"
        let firstCandidate = placeImportCandidate(name: "First Place", address: "Los Angeles")
        let secondCandidate = placeImportCandidate(name: "Second Place", address: "Malibu")
        let retrySeed = PlaceImportSeed(
            id: "partial-source-seed",
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let unresolvedFirstEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "First Place",
                areaHint: "Los Angeles",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [],
            selectedCandidateID: nil,
            helpMessage: "Apple Maps needs your help matching it."
        )
        let resolvedFirstEntry = PlaceImportResolvedEntry(
            seed: unresolvedFirstEntry.seed,
            candidates: [firstCandidate],
            selectedCandidateID: firstCandidate.id,
            helpMessage: nil
        )
        let secondEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Second Place",
                areaHint: "Malibu",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [secondCandidate],
            selectedCandidateID: secondCandidate.id,
            helpMessage: nil
        )
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .partialExpandedResolved([
                unresolvedFirstEntry,
                PlaceImportResolvedEntry(
                    seed: retrySeed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Some media in this post could not be read."
                )
            ], sourceName: nil),
            .expandedResolved([resolvedFirstEntry, secondEntry], sourceName: nil)
        ])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)
        let originalFirstItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.displayName == "First Place" })?.id
        )
        let retryItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.seed.nameHint == nil })?.id
        )

        store.retry(itemID: retryItemID)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["First Place", "Second Place"])
        XCTAssertEqual(items.map(\.state), [.ready, .ready])
        XCTAssertEqual(items.first?.id, originalFirstItemID)
        XCTAssertEqual(resolver.seeds.count, 2)
        XCTAssertNotEqual(
            resolver.seeds[0].effectiveSocialUnderstandingRequestID,
            resolver.seeds[1].effectiveSocialUnderstandingRequestID
        )
    }

    func testResolvedSourceRetryBecomesACountableSelectedPlace() async throws {
        let sourceURL = "https://www.instagram.com/p/source-retry-resolves-one/"
        let firstCandidate = placeImportCandidate(name: "First Place", address: "Ojai")
        let secondCandidate = placeImportCandidate(name: "Second Place", address: "Ojai")
        let firstEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "First Place",
                areaHint: "Ojai",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [firstCandidate],
            selectedCandidateID: firstCandidate.id,
            helpMessage: nil
        )
        let retryEntry = PlaceImportResolvedEntry(
            kind: .sourceRetry,
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [],
            selectedCandidateID: nil,
            helpMessage: "Some media could not be read. Retry automatic matching."
        )
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .partialExpandedResolved([firstEntry, retryEntry], sourceName: nil),
            .candidates([secondCandidate], selectedCandidateID: secondCandidate.id)
        ])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )
        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let retryItem = try XCTUnwrap(store.items(for: batchID).first(where: \.isSourceRetry))
        XCTAssertFalse(retryItem.isSelectedForImport)
        XCTAssertEqual(store.batches.first?.totalCount, 1)
        XCTAssertEqual(store.summary.totalCount, 1)
        XCTAssertEqual(store.summary.sourceRetryCount, 1)

        store.retry(itemID: retryItem.id)
        await store.waitForProcessing(batchID: batchID)

        let resolved = try XCTUnwrap(store.item(id: retryItem.id))
        XCTAssertFalse(resolved.isSourceRetry)
        XCTAssertTrue(resolved.isSelectedForImport)
        XCTAssertEqual(resolved.state, .ready)
        XCTAssertEqual(store.batches.first?.totalCount, 2)
        XCTAssertEqual(store.summary.totalCount, 2)
        XCTAssertEqual(store.summary.sourceRetryCount, 0)
    }

    func testPartialSourceRetryDoesNotReintroduceAnAlreadySavedPlace() async throws {
        let sourceURL = "https://www.instagram.com/p/partial-saved-retry/"
        let candidate = placeImportCandidate(name: "Saved Place", address: "Los Angeles")
        let resolvedEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Saved Place",
                areaHint: "Los Angeles",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            helpMessage: nil
        )
        let retrySeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .partialExpandedResolved([
                resolvedEntry,
                PlaceImportResolvedEntry(
                    seed: retrySeed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Some media in this post could not be read."
                )
            ], sourceName: nil),
            .expandedResolved([resolvedEntry], sourceName: nil)
        ])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )
        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)
        let savedItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.displayName == "Saved Place" })?.id
        )
        let retryItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.seed.nameHint == nil })?.id
        )
        store.markSaved(itemID: savedItemID, userPlaceID: "saved-user-place")

        store.retry(itemID: retryItemID)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, savedItemID)
        XCTAssertEqual(items.first?.state, .saved)
        XCTAssertEqual(items.first?.savedUserPlaceID, "saved-user-place")
    }

    func testPartialSourceRetryDoesNotReintroduceADismissedPlace() async throws {
        let sourceURL = "https://www.instagram.com/p/partial-dismissed-retry/"
        let candidate = placeImportCandidate(name: "Dismissed Place", address: "Los Angeles")
        let resolvedEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Dismissed Place",
                areaHint: "Los Angeles",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            helpMessage: nil
        )
        let retrySeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .partialExpandedResolved([
                resolvedEntry,
                PlaceImportResolvedEntry(
                    seed: retrySeed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Some media in this post could not be read."
                )
            ], sourceName: nil),
            .expandedResolved([resolvedEntry], sourceName: nil)
        ])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )
        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)
        let dismissedItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.displayName == "Dismissed Place" })?.id
        )
        let retryItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.seed.nameHint == nil })?.id
        )
        store.dismiss(itemID: dismissedItemID)

        store.retry(itemID: retryItemID)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, dismissedItemID)
        XCTAssertEqual(items.first?.state, .dismissed)
    }

    func testSocialDedupKeepsSameNameSameCityBranchesWithDistinctProviderIDs() async throws {
        let sourceURL = "https://www.instagram.com/p/same-name-branches/"
        let firstCandidate = PlaceCandidate(
            id: "branch-one",
            name: "Starbucks",
            category: "cafe",
            address: "Via A 1",
            locality: "Firenze",
            region: "Toscana",
            country: "IT",
            latitude: 43.7696,
            longitude: 11.2558,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-branch-one",
            confidence: 0.9
        )
        let secondCandidate = PlaceCandidate(
            id: "branch-two",
            name: "Starbucks",
            category: "cafe",
            address: "Via B 2",
            locality: "Firenze",
            region: "Toscana",
            country: "IT",
            latitude: 43.7710,
            longitude: 11.2580,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-branch-two",
            confidence: 0.9
        )
        let entries = [firstCandidate, secondCandidate].enumerated().map { index, candidate in
            PlaceImportResolvedEntry(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: candidate.name,
                    areaHint: candidate.address,
                    sourceURLString: sourceURL,
                    sourceLine: index + 1
                ),
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                helpMessage: nil
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SequencedPlaceImportResolver(
                resolutions: [.expandedResolved(entries, sourceName: nil)]
            )
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.state), [.ready, .ready])
        XCTAssertEqual(
            items.compactMap { $0.selectedCandidate?.sourceProviderPlaceID },
            ["mapkit-branch-one", "mapkit-branch-two"]
        )
    }

    func testSocialDedupKeepsDistinctAmbiguousVenuesWithTheSameLeadingCandidate() async throws {
        let sourceURL = "https://www.instagram.com/reel/distinct-overlapping-candidates/"
        let rorysPlace = placeImportCandidate(
            name: "Rory's Place",
            address: "Ojai, CA",
            locality: "Ojai",
            latitude: 34.4480,
            longitude: -119.2429
        )
        let rorysOtherPlace = placeImportCandidate(
            name: "Rory's Other Place",
            address: "Ojai, CA",
            locality: "Ojai",
            latitude: 34.4490,
            longitude: -119.2440
        )
        let candidates = [rorysPlace, rorysOtherPlace]
        let entries = ["Rory's Place", "Rory's Other Place"].map { name in
            PlaceImportResolvedEntry(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Ojai, CA",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                candidates: candidates,
                selectedCandidateID: nil,
                helpMessage: "Choose the matching venue from this post."
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SequencedPlaceImportResolver(
                resolutions: [.expandedResolved(entries, sourceName: nil)]
            )
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Rory's Place", "Rory's Other Place"])
        XCTAssertEqual(items.map(\.state), [.ambiguous, .ambiguous])
        XCTAssertTrue(items.allSatisfy { $0.candidates.map(\.id) == candidates.map(\.id) })
    }

    func testSocialDedupCollapsesAmbiguousVenueWithGroundedAreaNameSuffix() async throws {
        let sourceURL = "https://www.instagram.com/reel/grounded-area-name-suffix/"
        let rorysPlace = placeImportCandidate(
            name: "Rory's Place",
            address: "139 E Ojai Ave, Ojai, CA",
            locality: "Ojai",
            latitude: 34.4480,
            longitude: -119.2429
        )
        let alternatives = [
            rorysPlace,
            placeImportCandidate(
                name: "Rory's Other Place",
                address: "250 E Ojai Ave, Ojai, CA",
                locality: "Ojai",
                latitude: 34.4490,
                longitude: -119.2440
            )
        ]
        let entries = ["Rory's Place", "Rory's Place Ojai"].map { name in
            PlaceImportResolvedEntry(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Ojai, CA",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                candidates: alternatives,
                selectedCandidateID: nil,
                helpMessage: "Choose the matching venue from this post."
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SequencedPlaceImportResolver(
                resolutions: [.expandedResolved(entries, sourceName: nil)]
            )
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Rory's Place"])
        XCTAssertEqual(items.map(\.state), [.ambiguous])
    }

    func testSocialDedupKeepsAmbiguousAreaSuffixWithoutGroundedAreaEvidence() async throws {
        let sourceURL = "https://www.instagram.com/reel/ungrounded-area-name-suffix/"
        let sharedCandidate = placeImportCandidate(
            name: "Rory's Place",
            address: "Ventura, CA",
            locality: "Ventura",
            latitude: 34.2805,
            longitude: -119.2945
        )
        let entries = ["Rory's Place", "Rory's Place Ojai"].map { name in
            PlaceImportResolvedEntry(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Ventura, CA",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                candidates: [sharedCandidate],
                selectedCandidateID: nil,
                helpMessage: "Choose the matching venue from this post."
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SequencedPlaceImportResolver(
                resolutions: [.expandedResolved(entries, sourceName: nil)]
            )
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Rory's Place", "Rory's Place Ojai"])
        XCTAssertEqual(items.map(\.state), [.ambiguous, .ambiguous])
    }

    func testSocialDedupKeepsRorysPlaceAndRorysOtherPlaceWhenBothResolve() async throws {
        let sourceURL = "https://www.instagram.com/reel/rorys-distinct-resolved-venues/"
        let rorysPlace = placeImportCandidate(
            name: "Rory's Place",
            address: "139 E Ojai Ave, Ojai, CA",
            locality: "Ojai",
            latitude: 34.4480,
            longitude: -119.2429
        )
        let rorysOtherPlace = placeImportCandidate(
            name: "Rory's Other Place",
            address: "250 E Ojai Ave, Ojai, CA",
            locality: "Ojai",
            latitude: 34.4490,
            longitude: -119.2440
        )
        let entries = [rorysPlace, rorysOtherPlace].enumerated().map { index, place in
            PlaceImportResolvedEntry(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: place.name,
                    areaHint: "Ojai, CA",
                    sourceURLString: sourceURL,
                    sourceLine: index + 1
                ),
                candidates: [place],
                selectedCandidateID: place.id,
                helpMessage: nil
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SequencedPlaceImportResolver(
                resolutions: [.expandedResolved(entries, sourceName: nil)]
            )
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Rory's Place", "Rory's Other Place"])
        XCTAssertEqual(items.map(\.state), [.ready, .ready])
        XCTAssertEqual(
            items.compactMap { $0.selectedCandidate?.sourceProviderPlaceID },
            [rorysPlace.sourceProviderPlaceID, rorysOtherPlace.sourceProviderPlaceID]
        )
    }

    func testCountryOnlyPartialMissDeduplicatesAfterResolvedRetry() async throws {
        let sourceURL = "https://www.instagram.com/p/italy-partial-retry/"
        let unresolvedSeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: "Ditta Artigianale",
            areaHint: "ITALY",
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let candidate = PlaceCandidate(
            id: "italy-mapkit-place",
            name: "Ditta Artigianale",
            category: "cafe",
            address: "Via dei Neri 32R",
            locality: "Firenze",
            region: "Toscana",
            country: "IT",
            latitude: 43.7697,
            longitude: 11.2556,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "italy-provider-place",
            confidence: 0.9
        )
        let ambiguousCandidate = PlaceCandidate(
            id: "italy-ambiguous-place",
            name: "Ditta Artigianale",
            category: "cafe",
            address: "Via dello Sprone 5R",
            locality: "Firenze",
            region: "Toscana",
            country: "Italy",
            latitude: 43.7680,
            longitude: 11.2480,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "different-italy-provider-place",
            confidence: 0.7
        )
        let resolvedEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Ditta Artigianale",
                areaHint: candidate.address,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            helpMessage: nil
        )
        let retrySeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let resolver = SequencedPlaceImportResolver(resolutions: [
            .partialExpandedResolved([
                PlaceImportResolvedEntry(
                    seed: unresolvedSeed,
                    candidates: [ambiguousCandidate],
                    selectedCandidateID: nil,
                    helpMessage: "Choose the matching venue from this post."
                ),
                PlaceImportResolvedEntry(
                    seed: retrySeed,
                    candidates: [],
                    selectedCandidateID: nil,
                    helpMessage: "Some media in this post could not be read."
                )
            ], sourceName: nil),
            .expandedResolved([resolvedEntry], sourceName: nil)
        ])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )
        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        await store.waitForProcessing(batchID: batchID)
        let retryItemID = try XCTUnwrap(
            store.items(for: batchID).first(where: { $0.seed.nameHint == nil })?.id
        )

        store.retry(itemID: retryItemID)
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.displayName, "Ditta Artigianale")
        XCTAssertEqual(items.first?.state, .ready)
        XCTAssertEqual(items.first?.selectedCandidateID, candidate.id)
    }

    func testBindingASecondAccountClearsTheFirstAccountsImportSnapshot() throws {
        let candidate = placeImportCandidate(name: "Private caption place")
        let firstAccountItem = PlaceImportItem(
            batchID: "account-a-batch",
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "private caption",
                nameHint: candidate.name,
                areaHint: nil,
                sourceURLString: "https://www.instagram.com/reel/example/",
                sourceLine: 0
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                ownerUserID: "account-a",
                batches: [
                    PlaceImportBatch(
                        id: "account-a-batch",
                        source: .instagram,
                        sourceName: "Instagram",
                        totalCount: 1
                    )
                ],
                items: [firstAccountItem]
            )
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )

        store.bind(to: "account-b")

        XCTAssertTrue(store.batches.isEmpty)
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(persistence.snapshot.ownerUserID, "account-b")
        XCTAssertTrue(persistence.snapshot.items.isEmpty)
    }

    func testBulkMutationsPersistTheSnapshotOncePerUserAction() throws {
        let candidate = placeImportCandidate(name: "Ready")
        let items = (0..<50).map { index in
            PlaceImportItem(
                batchID: "batch",
                source: .googleMaps,
                seed: PlaceImportSeed(
                    rawText: "Ready \(index)",
                    nameHint: "Ready \(index)",
                    areaHint: nil,
                    sourceURLString: nil,
                    sourceLine: index
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                batches: [
                    PlaceImportBatch(
                        id: "batch",
                        source: .googleMaps,
                        sourceName: "Google Maps",
                        totalCount: items.count
                    )
                ],
                items: items
            )
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let itemIDs = items.map(\.id)

        store.setIncludedInImport(false, itemIDs: itemIDs)
        XCTAssertEqual(persistence.saveCount, 1)
        XCTAssertTrue(store.items.allSatisfy { !$0.isSelectedForImport })

        store.setStagedStatus(PlaceStatus.been, itemIDs: itemIDs)
        XCTAssertEqual(persistence.saveCount, 2)
        XCTAssertTrue(store.items.allSatisfy { $0.stagedStatus == PlaceStatus.been })
    }

    func testUnifiedImportRoutesMixedSourcesWithoutSourceSelection() throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: FakePlaceImportResolver()
        )

        let batchIDs = try store.enqueueUnified(
            text: """
            https://maps.app.goo.gl/example
            https://www.tiktok.com/@recme/video/123
            https://www.instagram.com/reel/example/
            Maru Coffee, Los Angeles
            """
        )

        XCTAssertEqual(batchIDs.count, 4)
        XCTAssertEqual(store.batches.map(\.source), [.googleMaps, .tiktok, .instagram, .textNotes])
        XCTAssertEqual(store.items.map(\.source), [.googleMaps, .tiktok, .instagram, .textNotes])
    }

    func testImportReviewIsPendingOnlyWhileItemsNeedProcessingOrReview() async throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: FakePlaceImportResolver()
        )

        XCTAssertFalse(store.summary.hasPendingImports)

        let batchID = try store.enqueue(source: .textNotes, text: "Ready, Los Angeles")
        XCTAssertTrue(store.summary.hasPendingImports)

        await store.waitForProcessing(batchID: batchID)
        XCTAssertTrue(store.summary.hasPendingImports)

        let readyItem = try XCTUnwrap(store.items(for: batchID).first)
        store.markSaved(itemID: readyItem.id, userPlaceID: "saved-place")

        XCTAssertFalse(store.summary.hasPendingImports)
        XCTAssertTrue(store.summary.hasImports)
        XCTAssertEqual(store.summary.savedCount, 1)
    }

    func testReadyImportsDefaultToWannaAndStagedStatusSurvivesReload() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let batchID = try XCTUnwrap(store).enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles"
        )
        await store?.waitForProcessing(batchID: batchID)
        let itemID = try XCTUnwrap(store?.items(for: batchID).first?.id)

        XCTAssertEqual(store?.item(id: itemID)?.stagedStatus, .wannaGo)
        store?.setStagedStatus(.been, itemID: itemID)
        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        XCTAssertEqual(store?.item(id: itemID)?.stagedStatus, .been)
    }

    func testImportSelectionDefaultsOnAndSurvivesReload() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let batchID = try XCTUnwrap(store).enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles"
        )
        await store?.waitForProcessing(batchID: batchID)
        let itemID = try XCTUnwrap(store?.items(for: batchID).first?.id)

        XCTAssertEqual(store?.item(id: itemID)?.isSelectedForImport, true)
        store?.setIncludedInImport(false, itemID: itemID)
        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        XCTAssertEqual(store?.item(id: itemID)?.isSelectedForImport, false)
    }

    func testOptionalImportDetailsPersistAndWannaClearsCheckInOnlyFields() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let batchID = try XCTUnwrap(store).enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles"
        )
        await store?.waitForProcessing(batchID: batchID)
        let itemID = try XCTUnwrap(store?.items(for: batchID).first?.id)
        let visitDate = Date(timeIntervalSince1970: 1_774_000_000)

        store?.setStagedStatus(.been, itemID: itemID)
        store?.setStagedNote("  Great patio  ", itemID: itemID)
        store?.setStagedRatingScore(4, itemID: itemID)
        store?.setStagedVisitedAt(visitDate, itemID: itemID)
        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        XCTAssertEqual(store?.item(id: itemID)?.stagedNote, "Great patio")
        XCTAssertEqual(store?.item(id: itemID)?.stagedRatingScore, 4)
        XCTAssertEqual(store?.item(id: itemID)?.stagedVisitedAt, visitDate)

        store?.setStagedStatus(.wannaGo, itemID: itemID)

        XCTAssertEqual(store?.item(id: itemID)?.stagedStatus, .wannaGo)
        XCTAssertEqual(store?.item(id: itemID)?.stagedNote, "Great patio")
        XCTAssertNil(store?.item(id: itemID)?.stagedRatingScore)
        XCTAssertNil(store?.item(id: itemID)?.stagedVisitedAt)
    }

    func testReceiptPersistsUntilPresented() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let batchID = try XCTUnwrap(store).enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles"
        )
        await store?.waitForProcessing(batchID: batchID)
        let item = try XCTUnwrap(store?.items(for: batchID).first)
        let entry = PlaceImportReceiptEntry(
            itemID: item.id,
            displayName: item.displayName,
            displayArea: item.displayArea,
            status: .wannaGo,
            outcome: .added,
            userPlaceID: "user-place"
        )
        store?.recordReceipt(batchID: batchID, entries: [entry], destinationListID: "list")
        let receiptID = try XCTUnwrap(store?.latestUnpresentedReceipt?.id)

        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())
        XCTAssertEqual(store?.latestUnpresentedReceipt?.id, receiptID)
        store?.markReceiptPresented(receiptID: receiptID)

        XCTAssertNil(store?.latestUnpresentedReceipt)
    }

    func testReceiptPersistsSourceRetryAsStatusAndNeverAsAPlaceEntry() throws {
        let batchID = "partial-social-import"
        let marker = PlaceImportItem(
            id: "source-retry",
            batchID: batchID,
            source: .instagram,
            kind: .sourceRetry,
            seed: PlaceImportSeed(
                rawText: "https://www.instagram.com/p/partial/",
                nameHint: nil,
                areaHint: nil,
                sourceURLString: "https://www.instagram.com/p/partial/",
                sourceLine: 1
            ),
            state: .needsHelp,
            helpMessage: "Some media in this post could not be read. Retry automatic matching to look for more places."
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                batches: [
                    PlaceImportBatch(
                        id: batchID,
                        source: .instagram,
                        sourceName: "Instagram",
                        state: .ready,
                        totalCount: 0,
                        processedCount: 0
                    )
                ],
                items: [marker]
            )
        )
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        store?.recordReceipt(
            batchID: batchID,
            entries: [
                PlaceImportReceiptEntry(
                    itemID: marker.id,
                    displayName: "Instagram post",
                    displayArea: nil,
                    status: nil,
                    outcome: .needsReview,
                    userPlaceID: nil
                )
            ],
            destinationListID: nil
        )

        var receipt = try XCTUnwrap(store?.batches.first?.receipt)
        XCTAssertTrue(receipt.entries.isEmpty)
        XCTAssertEqual(receipt.needsReviewCount, 0)
        XCTAssertEqual(receipt.sourceRetryCount, 1)

        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())
        receipt = try XCTUnwrap(store?.batches.first?.receipt)
        XCTAssertTrue(receipt.entries.isEmpty)
        XCTAssertEqual(receipt.sourceRetryCount, 1)
    }

    func testOldSnapshotReceiptNormalizesRetryByItemIDWithoutDoubleCountingStatus() throws {
        let batchID = "old-partial-social-import"
        let legacyMarker = PlaceImportItem(
            id: "legacy-source-retry",
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "https://www.instagram.com/p/partial/",
                nameHint: nil,
                areaHint: nil,
                sourceURLString: "https://www.instagram.com/p/partial/",
                sourceLine: 1
            ),
            state: .needsHelp,
            helpMessage: "Some media in this post could not be read. Retry automatic matching to look for more places."
        )
        let realPlace = PlaceImportItem(
            id: "barts-books",
            batchID: batchID,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "Bart's Books",
                nameHint: "Bart's Books",
                areaHint: nil,
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .needsHelp,
            helpMessage: "Needs your help matching this place."
        )
        let realPlaceReceiptEntry = PlaceImportReceiptEntry(
            id: "real-entry",
            itemID: realPlace.id,
            displayName: realPlace.displayName,
            displayArea: nil,
            status: nil,
            outcome: .needsReview,
            userPlaceID: nil
        )
        let legacyMarkerReceiptEntry = PlaceImportReceiptEntry(
            id: "legacy-marker-entry",
            itemID: legacyMarker.id,
            // The text is intentionally irrelevant. Only the matching legacy
            // source-retry item identity authorizes migration.
            displayName: "Retry unread carousel media",
            displayArea: nil,
            status: nil,
            outcome: .needsReview,
            userPlaceID: nil
        )
        let batch = PlaceImportBatch(
            id: batchID,
            source: .instagram,
            sourceName: "Instagram",
            state: .ready,
            totalCount: 1,
            processedCount: 1,
            receipt: PlaceImportReceipt(
                id: "legacy-receipt",
                batchID: batchID,
                sourceName: "Instagram",
                entries: [legacyMarkerReceiptEntry, realPlaceReceiptEntry],
                destinationListID: nil,
                sourceRetryCount: 1
            )
        )
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(
                    batches: [batch],
                    items: [legacyMarker, realPlace]
                )
            ),
            resolver: FakePlaceImportResolver()
        )

        let normalizedReceipt = try XCTUnwrap(store.batches.first?.receipt)
        XCTAssertEqual(normalizedReceipt.entries, [realPlaceReceiptEntry])
        XCTAssertEqual(normalizedReceipt.needsReviewCount, 1)
        XCTAssertEqual(normalizedReceipt.sourceRetryCount, 1)
    }

    func testProcessingProducesReviewStatesAndSaveProgress() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        let store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        let batchID = try store.enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles\nAmbiguous, Santa Monica\nNeeds Help"
        )
        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(store.items(for: batchID).map(\.state), [.ready, .ambiguous, .needsHelp])
        XCTAssertEqual(store.summary.processedCount, 3)
        XCTAssertEqual(store.summary.readyCount, 1)
        XCTAssertEqual(store.summary.needsHelpCount, 2)

        let readyItem = try XCTUnwrap(store.items(for: batchID).first(where: { $0.state == .ready }))
        store.markSaved(itemID: readyItem.id, userPlaceID: "saved-1")

        XCTAssertEqual(store.item(id: readyItem.id)?.state, .saved)
        XCTAssertEqual(store.summary.savedCount, 1)
        XCTAssertEqual(store.summary.readyCount, 0)
    }

    func testCompletedResolutionSurvivesStoreReload() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let batchID = try XCTUnwrap(store).enqueue(source: .textNotes, text: "Ready, Los Angeles")
        await store?.waitForProcessing(batchID: batchID)
        XCTAssertEqual(store?.items(for: batchID).first?.state, .ready)

        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        XCTAssertEqual(store?.items(for: batchID).first?.state, .ready)
        XCTAssertEqual(store?.summary.readyCount, 1)
    }

    func testInterruptedResolutionResumesAfterRelaunch() async {
        let batch = PlaceImportBatch(id: "batch", source: .textNotes, sourceName: nil, totalCount: 1)
        let item = PlaceImportItem(
            id: "item",
            batchID: batch.id,
            source: .textNotes,
            seed: PlaceImportSeed(
                id: "seed",
                rawText: "Ready, Los Angeles",
                nameHint: "Ready",
                areaHint: "Los Angeles",
                sourceURLString: nil,
                sourceLine: 1
            ),
            state: .resolving
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
        )
        let store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())

        XCTAssertEqual(store.item(id: item.id)?.state, .queued)
        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertEqual(store.item(id: item.id)?.state, .ready)
        XCTAssertEqual(store.batches.first?.processedCount, 1)
    }

    func testPausingProcessingReturnsInflightRowsToDurableQueue() async {
        let batch = PlaceImportBatch(
            id: "background-pause",
            source: .googleMaps,
            sourceName: nil,
            totalCount: 1
        )
        let item = PlaceImportItem(
            id: "background-item",
            batchID: batch.id,
            source: .googleMaps,
            seed: PlaceImportSeed(
                rawText: "Maru",
                nameHint: "Maru",
                areaHint: "Los Angeles",
                sourceURLString: nil,
                sourceLine: 1
            )
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: CancellationThenSuccessPlaceImportResolver()
        )

        store.resumePendingImports()
        for _ in 0..<100 where store.item(id: item.id)?.state != .resolving {
            await Task.yield()
        }
        XCTAssertEqual(store.item(id: item.id)?.state, .resolving)

        store.pauseProcessing(batchIDs: [batch.id])
        await Task.yield()

        XCTAssertEqual(store.item(id: item.id)?.state, .queued)
        XCTAssertEqual(persistence.snapshot.items.first?.state, .queued)
        XCTAssertEqual(store.batches.first?.state, .processing)

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertEqual(store.item(id: item.id)?.state, .ready)
        XCTAssertEqual(persistence.snapshot.items.first?.state, .ready)
    }

    func testReconcileMarksAnAlreadySavedProviderPlaceAsDuplicate() async throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: FakePlaceImportResolver()
        )
        let batchID = try store.enqueue(source: .textNotes, text: "Ready, Los Angeles")
        await store.waitForProcessing(batchID: batchID)
        let item = try XCTUnwrap(store.items(for: batchID).first)
        let candidate = try XCTUnwrap(item.selectedCandidate)

        store.reconcileDuplicates(with: [
            PlaceImportExistingPlace(
                userPlaceID: "existing-save",
                name: candidate.name,
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                sourceProvider: candidate.sourceProvider,
                sourceProviderPlaceID: candidate.sourceProviderPlaceID
            )
        ])

        XCTAssertEqual(store.item(id: item.id)?.state, .duplicate)
        XCTAssertEqual(store.item(id: item.id)?.duplicateUserPlaceID, "existing-save")
        XCTAssertEqual(store.summary.duplicateCount, 1)
    }

    func testCancellingAnActiveResolutionKeepsTheItemDismissed() async throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: SuspendedPlaceImportResolver()
        )
        let batchID = try store.enqueue(source: .textNotes, text: "Slow Place, Los Angeles")

        for _ in 0..<100 where store.items(for: batchID).first?.state != .resolving {
            await Task.yield()
        }
        XCTAssertEqual(store.items(for: batchID).first?.state, .resolving)

        store.cancel(batchID: batchID)
        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(store.items(for: batchID).first?.state, .dismissed)
        XCTAssertEqual(store.batches.first(where: { $0.id == batchID })?.state, .cancelled)
    }

    func testClearAllRemovesEveryBatchAndPersistsTheEmptyInbox() async throws {
        let persistence = InMemoryPlaceImportPersistence()
        var store: PlaceImportStore? = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let firstBatchID = try XCTUnwrap(store).enqueue(
            source: .textNotes,
            text: "Ready, Los Angeles\nNeeds Help"
        )
        await store?.waitForProcessing(batchID: firstBatchID)
        let secondBatchID = try XCTUnwrap(store).enqueue(
            source: .instagram,
            text: "Ready, Santa Monica"
        )
        await store?.waitForProcessing(batchID: secondBatchID)

        store?.clearAll()

        XCTAssertEqual(store?.batches, [])
        XCTAssertEqual(store?.items, [])
        XCTAssertEqual(store?.summary, .empty)
        XCTAssertEqual(persistence.snapshot, PlaceImportSnapshot())

        store = PlaceImportStore(persistence: persistence, resolver: FakePlaceImportResolver())
        XCTAssertEqual(store?.batches, [])
        XCTAssertEqual(store?.items, [])
    }

    func testExpandedGoogleListReplacesOneURLWithEveryImportedPlace() async throws {
        let seeds = (1...45).map { index in
            PlaceImportSeed(
                id: "seed-\(index)",
                rawText: "Bakery \(index) | \(index) Main St",
                nameHint: "Bakery \(index)",
                areaHint: "\(index) Main St, Los Angeles, CA",
                sourceURLString: nil,
                sourceLine: index,
                latitude: 34 + Double(index) / 10_000,
                longitude: -118 - Double(index) / 10_000,
                sourceProvider: "google_maps",
                sourceProviderPlaceID: "google-place-\(index)"
            )
        }
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: ExpandingPlaceImportResolver(seeds: seeds)
        )

        let batchID = try store.enqueue(
            source: .googleMaps,
            text: "https://maps.app.goo.gl/bakeries"
        )
        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(store.items(for: batchID).count, 45)
        XCTAssertEqual(store.items(for: batchID).map(\.state), Array(repeating: .ready, count: 45))
        XCTAssertEqual(store.batches.first(where: { $0.id == batchID })?.sourceName, "Ryan's Bakeries")
        XCTAssertEqual(store.batches.first(where: { $0.id == batchID })?.totalCount, 45)
        XCTAssertEqual(store.summary.totalCount, 45)
    }

    func testLargeGoogleListResolvesWithBoundedConcurrency() async throws {
        let seeds = (1...45).map { index in
            PlaceImportSeed(
                id: "concurrent-seed-\(index)",
                rawText: "Bakery \(index)",
                nameHint: "Bakery \(index)",
                areaHint: "Los Angeles",
                sourceURLString: nil,
                sourceLine: index,
                latitude: 34 + Double(index) / 10_000,
                longitude: -118 - Double(index) / 10_000,
                sourceProvider: "google_maps",
                sourceProviderPlaceID: "concurrent-google-\(index)"
            )
        }
        let resolver = ConcurrentGoogleListPlaceImportResolver(seeds: seeds)
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )

        let batchID = try store.enqueue(
            source: .googleMaps,
            text: "https://maps.app.goo.gl/concurrent-bakeries"
        )
        await store.waitForProcessing(batchID: batchID)

        XCTAssertEqual(store.items(for: batchID).count, 45)
        XCTAssertTrue(store.items(for: batchID).allSatisfy { $0.state == .ready })
        XCTAssertGreaterThan(resolver.maximumConcurrentCount, 1)
        XCTAssertLessThanOrEqual(resolver.maximumConcurrentCount, 6)
    }

    func testOneSocialPostExpandsIntoEveryConfidentVenue() async throws {
        let maru = placeImportCandidate(name: "Maru Coffee")
        let gjusta = placeImportCandidate(name: "Gjusta Bakery")
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [
                "maru coffee": [maru],
                "gjusta bakery": [gjusta]
            ]),
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Two coffee stops",
                    caption: "Coffee at @marucoffee and pastries at @gjustabakery.",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: resolver
        )

        let batchID = try store.enqueue(
            source: .instagram,
            text: "https://www.instagram.com/reel/two-venues/"
        )
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.state), [.ready, .ready])
        XCTAssertEqual(Set(items.map(\.displayName)), ["Maru Coffee", "Gjusta Bakery"])
        XCTAssertTrue(items.allSatisfy {
            $0.seed.sourceURLString == "https://www.instagram.com/reel/two-venues/"
        })
    }

    func testFreshSocialImportKeepsResolvedPlacesWhenAnotherHintHasNoMapCandidate() async throws {
        let metadata = SocialImportMetadata(
            title: "Wyoming itinerary",
            caption: "Stop at Fremont Lake! Base camp at Half Moon Lake Lodge!",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let persistence = InMemoryPlaceImportPersistence()
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: RoutingNoCandidateThrowingDevicePlaceResolver(routes: [
                    "fremont lake": [placeImportCandidate(
                        name: "Fremont Lake",
                        locality: "Pinedale",
                        region: "WY"
                    )]
                ]),
                metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        let batchID = try store.enqueue(
            source: .instagram,
            text: "https://www.instagram.com/p/fresh-no-candidate/"
        )
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Fremont Lake", "Half Moon Lake Lodge"])
        XCTAssertEqual(items.map(\.state), [.ready, .needsHelp])
        XCTAssertFalse(items.contains { $0.displayName == "instagram.com" })
        XCTAssertEqual(persistence.snapshot.items.map(\.displayName), items.map(\.displayName))
    }

    func testFreshSocialImportKeepsPartialResultsDuringTransientMapFailure() async throws {
        let metadata = SocialImportMetadata(
            title: "Wyoming itinerary",
            caption: "Stop at Fremont Lake! Base camp at Half Moon Lake Lodge!",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let persistence = InMemoryPlaceImportPersistence()
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: PartiallyThrowingDevicePlaceResolver(
                    successfulName: "Fremont Lake",
                    candidate: placeImportCandidate(
                        name: "Fremont Lake",
                        locality: "Pinedale",
                        region: "WY"
                    )
                ),
                metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        let batchID = try store.enqueue(
            source: .instagram,
            text: "https://www.instagram.com/p/fresh-partial-map-failure/"
        )
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.map(\.displayName), ["Fremont Lake", "Half Moon Lake Lodge"])
        XCTAssertEqual(items.map(\.state), [.ready, .needsHelp])
        XCTAssertFalse(items.contains { $0.displayName == "instagram.com" })
        XCTAssertEqual(persistence.snapshot.items.map(\.displayName), items.map(\.displayName))
    }

    func testManualSearchReturnsVisibleFailureFromDeviceSnapshot() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let resolver = RecordingPlaceImportResolver(
            resolution: .needsHelp("Apple Maps search is temporarily unavailable.")
        )
        let persistence = InMemoryPlaceImportPersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)

        let outcome = await store.search(
            itemID: "rec-106-farson-manual-search",
            name: "  Farson Mercantile  ",
            area: "Farson, Wyoming"
        )

        XCTAssertEqual(outcome, .failed("Apple Maps search is temporarily unavailable."))
        XCTAssertEqual(resolver.lastSeed?.nameHint, "Farson Mercantile")
        XCTAssertEqual(resolver.lastSeed?.areaHint, "Farson, Wyoming")
        XCTAssertEqual(resolver.lastSource, .instagram)
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.state, .needsHelp)
        XCTAssertEqual(
            store.item(id: "rec-106-farson-manual-search")?.helpMessage,
            "Apple Maps search is temporarily unavailable."
        )
        XCTAssertEqual(persistence.snapshot.items.first?.helpMessage, "Apple Maps search is temporarily unavailable.")
    }

    func testManualSearchPreviewReturnsCandidatesWithoutMutatingImport() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let firstCandidate = placeImportCandidate(
            name: "Farson Mercantile",
            locality: "Farson",
            region: "WY"
        )
        let secondCandidate = placeImportCandidate(
            name: "Farson General Store",
            locality: "Farson",
            region: "WY"
        )
        let resolver = RecordingPlaceImportResolver(
            resolution: .candidates(
                [firstCandidate, secondCandidate],
                selectedCandidateID: firstCandidate.id
            )
        )
        let persistence = InMemoryPlaceImportPersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)
        let itemBeforeSearch = try XCTUnwrap(store.item(id: "rec-106-farson-manual-search"))

        let outcome = await store.previewManualSearch(
            itemID: itemBeforeSearch.id,
            name: "  Farson Mercantile  ",
            area: "  Farson, Wyoming  "
        )

        XCTAssertEqual(outcome, .results([firstCandidate, secondCandidate]))
        XCTAssertEqual(resolver.lastSeed?.nameHint, "Farson Mercantile")
        XCTAssertEqual(resolver.lastSeed?.areaHint, "Farson, Wyoming")
        XCTAssertEqual(store.item(id: itemBeforeSearch.id), itemBeforeSearch)
        XCTAssertEqual(persistence.snapshot.items.first, snapshot.items.first)
    }

    func testConfirmManualSearchPersistsOnlyTheSelectedCandidateID() throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let persistence = InMemoryPlaceImportPersistence(snapshot: snapshot)
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )
        let firstCandidate = placeImportCandidate(name: "Farson Mercantile")
        let secondCandidate = placeImportCandidate(name: "Farson General Store")

        store.confirmManualSearch(
            itemID: "rec-106-farson-manual-search",
            name: "  Farson Mercantile  ",
            area: "  Farson, Wyoming  ",
            candidates: [firstCandidate, secondCandidate],
            selectedCandidateID: secondCandidate.id
        )

        let item = try XCTUnwrap(store.item(id: "rec-106-farson-manual-search"))
        XCTAssertEqual(item.seed.nameHint, "Farson Mercantile")
        XCTAssertEqual(item.seed.areaHint, "Farson, Wyoming")
        XCTAssertEqual(item.candidates, [firstCandidate, secondCandidate])
        XCTAssertEqual(item.selectedCandidateID, secondCandidate.id)
        XCTAssertEqual(item.state, .ready)
        XCTAssertNil(item.helpMessage)
        XCTAssertEqual(persistence.snapshot.items.first, item)
    }

    func testManualSearchPreservesOneWeakMapKitCandidateForReview() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let weakCandidate = placeImportCandidate(
            name: "Farson Ice Cream",
            locality: "Farson",
            region: "WY"
        )
        let placeResolver = FakeDevicePlaceResolver(candidates: [weakCandidate])
        let persistence = InMemoryPlaceImportPersistence(snapshot: snapshot)
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: placeResolver,
                metadataProvider: FakeSocialImportMetadataProvider(),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        let outcome = await store.search(
            itemID: "rec-106-farson-manual-search",
            name: "Farson Mercantile",
            area: "Wyoming"
        )

        XCTAssertEqual(outcome, .needsReview(candidateCount: 1))
        XCTAssertEqual(placeResolver.manualInputs, [
            ManualPlaceInput(name: "Farson Mercantile", areaHint: "Wyoming", category: nil)
        ])
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.state, .ambiguous)
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.candidates, [weakCandidate])
        XCTAssertNil(store.item(id: "rec-106-farson-manual-search")?.selectedCandidateID)
        XCTAssertNil(store.item(id: "rec-106-farson-manual-search")?.helpMessage)
    }

    func testManualSearchAutoSelectsAnExactMapKitCandidate() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let exactCandidate = placeImportCandidate(
            name: "Farson Mercantile",
            locality: "Farson",
            region: "WY"
        )
        let placeResolver = FakeDevicePlaceResolver(candidates: [exactCandidate])
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(snapshot: snapshot),
            resolver: DevicePlaceImportResolver(
                placeResolver: placeResolver,
                metadataProvider: FakeSocialImportMetadataProvider(),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        let outcome = await store.search(
            itemID: "rec-106-farson-manual-search",
            name: "Farson Mercantile",
            area: "Wyoming"
        )

        XCTAssertEqual(outcome, .matched)
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.state, .ready)
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.selectedCandidateID, exactCandidate.id)
    }

    func testNewManualSearchSupersedesAnInFlightResult() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let resolver = ControllablePlaceImportResolver()
        let persistence = InMemoryPlaceImportPersistence(snapshot: snapshot)
        let store = PlaceImportStore(persistence: persistence, resolver: resolver)
        let firstCandidate = placeImportCandidate(name: "First Place")
        let secondCandidate = placeImportCandidate(name: "Second Place")

        let firstSearch = Task {
            await store.search(
                itemID: "rec-106-farson-manual-search",
                name: "First Place",
                area: "Wyoming"
            )
        }
        let receivedFirstRequest = await waitForManualRequestCount(1, resolver: resolver)
        XCTAssertTrue(receivedFirstRequest)

        let secondSearch = Task {
            await store.search(
                itemID: "rec-106-farson-manual-search",
                name: "Second Place",
                area: "Wyoming"
            )
        }
        let queuedSecondRequest = await waitForImportItem(
            id: "rec-106-farson-manual-search",
            nameHint: "Second Place",
            state: .queued,
            store: store
        )
        XCTAssertTrue(queuedSecondRequest)
        XCTAssertTrue(
            resolver.completeNext(
                .candidates([firstCandidate], selectedCandidateID: firstCandidate.id)
            )
        )
        let receivedSecondRequest = await waitForManualRequestCount(2, resolver: resolver)
        XCTAssertTrue(receivedSecondRequest)
        XCTAssertTrue(
            resolver.completeNext(
                .candidates([secondCandidate], selectedCandidateID: secondCandidate.id)
            )
        )

        let secondOutcome = await secondSearch.value
        let firstOutcome = await firstSearch.value
        XCTAssertEqual(secondOutcome, .matched)
        XCTAssertEqual(firstOutcome, .matched)
        XCTAssertEqual(resolver.manualSeeds.map(\.nameHint), ["First Place", "Second Place"])
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.seed.nameHint, "Second Place")
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.selectedCandidateID, secondCandidate.id)
        XCTAssertEqual(persistence.snapshot.items.first?.selectedCandidateID, secondCandidate.id)
    }

    func testDismissedManualSearchIgnoresItsInFlightResult() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let resolver = ControllablePlaceImportResolver()
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(snapshot: snapshot),
            resolver: resolver
        )
        let candidate = placeImportCandidate(name: "Farson Mercantile")

        let search = Task {
            await store.search(
                itemID: "rec-106-farson-manual-search",
                name: "Farson Mercantile",
                area: "Wyoming"
            )
        }
        let receivedRequest = await waitForManualRequestCount(1, resolver: resolver)
        XCTAssertTrue(receivedRequest)
        store.dismiss(itemID: "rec-106-farson-manual-search")
        XCTAssertTrue(
            resolver.completeNext(
                .candidates([candidate], selectedCandidateID: candidate.id)
            )
        )

        let outcome = await search.value
        XCTAssertEqual(
            outcome,
            .failed("This import is no longer waiting for a place match.")
        )
        XCTAssertEqual(store.item(id: "rec-106-farson-manual-search")?.state, .dismissed)
        XCTAssertNil(store.item(id: "rec-106-farson-manual-search")?.selectedCandidateID)
    }

    func testManualSearchJumpsAheadOfAutomaticGuideBacklogAndReturnsForItsItem() async throws {
        let batch = PlaceImportBatch(
            id: "manual-priority-batch",
            source: .instagram,
            sourceName: nil,
            totalCount: 3
        )
        let sourceURL = "https://www.instagram.com/p/guide/"
        let items = ["Automatic One", "Automatic Two", "Manual Target"].enumerated().map { offset, name in
            PlaceImportItem(
                id: "priority-item-\(offset)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "USA",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                )
            )
        }
        let resolver = BackloggedManualSearchResolver()
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: items)
            ),
            resolver: resolver
        )

        store.resumePendingImports()
        let receivedAutomaticRequest = await resolver.waitForAutomaticRequestCount(1)
        XCTAssertTrue(receivedAutomaticRequest)

        let search = Task {
            await store.search(
                itemID: "priority-item-2",
                name: "Manual Target",
                area: "USA"
            )
        }
        let queuedManualRequest = await waitForImportItem(
            id: "priority-item-2",
            nameHint: "Manual Target",
            state: .queued,
            store: store
        )
        XCTAssertTrue(queuedManualRequest)
        XCTAssertTrue(resolver.completeAutomatic(.needsHelp("Automatic lookup paused")))
        let receivedManualRequest = await resolver.waitForManualRequestCount(1)
        XCTAssertTrue(receivedManualRequest)
        XCTAssertEqual(resolver.manualSeeds.first?.id, items[2].seed.id)

        let candidate = placeImportCandidate(name: "Manual Target", country: "US")
        XCTAssertTrue(
            resolver.completeManual(
                .candidates([candidate], selectedCandidateID: candidate.id)
            )
        )
        let outcome = await search.value
        XCTAssertEqual(outcome, .matched)
        XCTAssertEqual(store.item(id: "priority-item-2")?.selectedCandidateID, candidate.id)
        XCTAssertTrue([.queued, .resolving].contains(store.item(id: "priority-item-1")?.state))
        store.cancel(batchID: batch.id)
        _ = resolver.completeAutomatic(.needsHelp("Cancelled"))
        await Task.yield()
    }

    func testPendingManualSearchSurvivesRelaunchAndResumesAsManual() async {
        let batch = PlaceImportBatch(
            id: "durable-manual-batch",
            source: .instagram,
            sourceName: nil,
            totalCount: 1
        )
        let item = PlaceImportItem(
            id: "durable-manual-item",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: "Farson Mercantile / USA",
                nameHint: "Farson Mercantile",
                areaHint: "USA",
                sourceURLString: "https://www.instagram.com/p/guide/",
                sourceLine: 1
            ),
            state: .needsHelp
        )
        let firstResolver = ControllablePlaceImportResolver()
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
        )
        let firstStore = PlaceImportStore(persistence: persistence, resolver: firstResolver)

        let search = Task {
            await firstStore.search(
                itemID: item.id,
                name: "Farson Mercantile",
                area: "USA"
            )
        }
        let queuedRequest = await waitForManualRequestCount(1, resolver: firstResolver)
        XCTAssertTrue(queuedRequest)
        XCTAssertEqual(persistence.snapshot.items.first?.state, .resolving)
        XCTAssertEqual(persistence.snapshot.items.first?.pendingManualSearch, true)
        let interruptedSnapshot = persistence.snapshot

        firstStore.cancel(batchID: batch.id)
        XCTAssertTrue(firstResolver.completeNext(.needsHelp("Cancelled")))
        _ = await search.value

        let resumedResolver = ControllablePlaceImportResolver()
        let resumedPersistence = InMemoryPlaceImportPersistence(snapshot: interruptedSnapshot)
        let resumedStore = PlaceImportStore(
            persistence: resumedPersistence,
            resolver: resumedResolver
        )

        XCTAssertEqual(resumedStore.item(id: item.id)?.state, .queued)
        XCTAssertEqual(resumedStore.item(id: item.id)?.pendingManualSearch, true)
        resumedStore.resumePendingImports()
        let receivedManualRequest = await waitForManualRequestCount(1, resolver: resumedResolver)
        XCTAssertTrue(receivedManualRequest)
        XCTAssertTrue(resumedResolver.completeNext(.needsHelp("No match")))
        await resumedStore.waitForProcessing(batchID: batch.id)

        XCTAssertNil(resumedStore.item(id: item.id)?.pendingManualSearch)
        XCTAssertNil(resumedPersistence.snapshot.items.first?.pendingManualSearch)
    }

    func testAutomaticLookupPacerDoesNotBurstConcurrentCallers() async throws {
        let pacer = SocialImportAutomaticLookupPacer(minimumInterval: .milliseconds(60))
        let clock = ContinuousClock()
        let starts = try await withThrowingTaskGroup(of: ContinuousClock.Instant.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    try await pacer.waitForTurn()
                    return clock.now
                }
            }
            var values: [ContinuousClock.Instant] = []
            for try await value in group {
                values.append(value)
            }
            return values.sorted()
        }

        XCTAssertEqual(starts.count, 4)
        for (earlier, later) in zip(starts, starts.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, .milliseconds(35))
        }
    }

    func testSocialResolverRejectsGenericCoffeeHintsAroundOneNamedVenue() async throws {
        let oneCedar = placeImportCandidate(name: "One Cedar")
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [
                "one cedar": [oneCedar],
                "local coffee shop": [placeImportCandidate(name: "Local Coffee + Shop")],
                "coffee": [placeImportCandidate(name: "TikTok Coffee")]
            ]),
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "This coffee shop is called One Cedar",
                    caption: "This coffee shop is called One Cedar. #localcoffeeshop #tiktokcoffee",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let seed = PlaceImportSeed(
            rawText: "https://www.tiktok.com/@creator/video/one-cedar",
            nameHint: nil,
            areaHint: nil,
            sourceURLString: "https://www.tiktok.com/@creator/video/one-cedar",
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .tiktok)

        XCTAssertEqual(resolution, .candidates([oneCedar], selectedCandidateID: oneCedar.id))
    }

    func testResolverUpgradeCollapsesExpandedSocialChildrenBackToOneSourceJob() {
        let batch = PlaceImportBatch(id: "social-batch", source: .tiktok, sourceName: nil, totalCount: 2)
        let sourceURL = "https://www.tiktok.com/@creator/video/one-cedar"
        let items = ["TikTok Coffee", "Local Coffee + Shop"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "old-\(index)",
                batchID: batch.id,
                source: .tiktok,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Los Angeles",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: PlaceImportItem.currentResolverVersion - 1
            )
        }

        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: items)
            ),
            resolver: SuspendedPlaceImportResolver()
        )

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.state, .queued)
        XCTAssertNil(store.items.first?.seed.nameHint)
        XCTAssertEqual(store.items.first?.seed.sourceURLString, sourceURL)
    }

    func testResolverUpgradeCollapsesQueuedAndResolvingSocialChildrenBackToOneSourceJob() {
        let batch = PlaceImportBatch(
            id: "social-inflight-upgrade",
            source: .instagram,
            sourceName: nil,
            totalCount: 2
        )
        let sourceURL = "https://www.instagram.com/p/inflight-upgrade/"
        let items = [
            (name: "Queued Guess", state: PlaceImportItemState.queued),
            (name: "Resolving Guess", state: PlaceImportItemState.resolving)
        ].enumerated().map { index, fixture in
            PlaceImportItem(
                id: "inflight-old-\(index)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: fixture.name,
                    areaHint: "Los Angeles",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: fixture.state,
                resolverVersion: PlaceImportItem.currentResolverVersion - 1
            )
        }

        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: items)
            ),
            resolver: SuspendedPlaceImportResolver()
        )

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.state, .queued)
        XCTAssertNil(store.items.first?.seed.nameHint)
        XCTAssertEqual(store.items.first?.seed.sourceURLString, sourceURL)
        XCTAssertEqual(store.items.first?.resolverVersion, PlaceImportItem.currentResolverVersion)
    }

    func testSocialResolverUpgradeKeepsOldRowsWhenMetadataRefreshFails() async {
        let batch = PlaceImportBatch(id: "social-fallback", source: .instagram, sourceName: nil, totalCount: 2)
        let sourceURL = "https://www.instagram.com/p/temporarily-unavailable/"
        let oldItems = ["Fremont Lake", "Pine Coffee Supply"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "fallback-old-\(index)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Wyoming",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: 4
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: oldItems)
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: RoutingDevicePlaceResolver(routes: [:]),
                metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertEqual(Set(store.items.map(\.displayName)), ["Fremont Lake", "Pine Coffee Supply"])
        XCTAssertEqual(store.items.map(\.resolverVersion), [4, 4])
        XCTAssertEqual(Set(persistence.snapshot.items.map(\.displayName)), ["Fremont Lake", "Pine Coffee Supply"])
    }

    func testSocialResolverUpgradeDropsStaleRowsWhenHostedScanReturnsOnlySourceRetry() async {
        let batch = PlaceImportBatch(
            id: "social-retry-only-upgrade",
            source: .instagram,
            sourceName: nil,
            totalCount: 2
        )
        let sourceURL = "https://www.instagram.com/p/retry-only-upgrade/"
        let oldItems = ["Unreliable Guess A", "Unreliable Guess B"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "retry-only-old-\(index)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Los Angeles",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: PlaceImportItem.currentResolverVersion - 1
            )
        }
        let retrySeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: oldItems)
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: SequencedPlaceImportResolver(resolutions: [
                .partialExpandedResolved(
                    [
                        PlaceImportResolvedEntry(
                            kind: .sourceRetry,
                            seed: retrySeed,
                            candidates: [],
                            selectedCandidateID: nil,
                            helpMessage: "Automatic matching is temporarily unavailable. Retry the source scan."
                        )
                    ],
                    sourceName: nil
                )
            ])
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        let items = store.items(for: batch.id)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isSourceRetry)
        XCTAssertEqual(items[0].resolverVersion, PlaceImportItem.currentResolverVersion)
        XCTAssertFalse(items.map(\.displayName).contains("Unreliable Guess A"))
        XCTAssertFalse(items.map(\.displayName).contains("Unreliable Guess B"))
        XCTAssertEqual(persistence.snapshot.items, items)
    }

    func testCompletingOneSocialUpgradeKeepsOtherUpgradeBackupAcrossRelaunch() async {
        let firstBatch = PlaceImportBatch(
            id: "durable-upgrade-first",
            source: .instagram,
            sourceName: nil,
            totalCount: 1
        )
        let secondBatch = PlaceImportBatch(
            id: "durable-upgrade-second",
            source: .instagram,
            sourceName: nil,
            totalCount: 2
        )
        let firstURL = "https://www.instagram.com/p/durable-first/"
        let secondURL = "https://www.instagram.com/p/durable-second/"
        let firstCandidate = placeImportCandidate(name: "Old First Place")
        let firstOldItem = PlaceImportItem(
            id: "durable-first-old",
            batchID: firstBatch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: firstURL,
                nameHint: firstCandidate.name,
                areaHint: "Wyoming",
                sourceURLString: firstURL,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [firstCandidate],
            selectedCandidateID: firstCandidate.id,
            resolverVersion: 4
        )
        let secondOldItems = ["Old Second Place", "Old Third Place"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "durable-second-old-\(index)",
                batchID: secondBatch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: secondURL,
                    nameHint: name,
                    areaHint: "Wyoming",
                    sourceURLString: secondURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: 4
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                batches: [firstBatch, secondBatch],
                items: [firstOldItem] + secondOldItems
            )
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: FakePlaceImportResolver()
        )

        // Process only the first batch. The second placeholder remains staged in memory
        // while the first success saves the whole snapshot.
        store.retry(itemID: firstOldItem.id)
        await store.waitForProcessing(batchID: firstBatch.id)

        XCTAssertEqual(
            persistence.snapshot.items.filter { $0.batchID == secondBatch.id },
            secondOldItems
        )
        XCTAssertTrue(
            persistence.snapshot.items.filter { $0.batchID == secondBatch.id }
                .allSatisfy { $0.resolverVersion == 4 }
        )

        // Simulate terminating and relaunching before the second refresh. A failed retry
        // must still restore both original rows from the durable snapshot.
        let reloaded = PlaceImportStore(
            persistence: persistence,
            resolver: NeedsHelpPlaceImportResolver()
        )
        reloaded.resumePendingImports()
        await reloaded.waitForProcessing(batchID: secondBatch.id)

        XCTAssertEqual(reloaded.items(for: secondBatch.id), secondOldItems)
        XCTAssertEqual(
            persistence.snapshot.items.filter { $0.batchID == secondBatch.id },
            secondOldItems
        )
    }

    func testCancellingSocialUpgradeRestoresOldRowsBeforePersisting() {
        let batch = PlaceImportBatch(id: "social-cancel", source: .instagram, sourceName: nil, totalCount: 2)
        let sourceURL = "https://www.instagram.com/p/cancel-upgrade/"
        let oldItems = ["Fremont Lake", "Pine Coffee Supply"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "cancel-old-\(index)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Wyoming",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: 4
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: oldItems)
        )
        let store = PlaceImportStore(persistence: persistence, resolver: SuspendedPlaceImportResolver())

        store.resumePendingImports()
        store.cancel(batchID: batch.id)

        XCTAssertEqual(store.items, oldItems)
        XCTAssertEqual(persistence.snapshot.items, oldItems)
        XCTAssertEqual(store.batches.first?.state, .cancelled)
    }

    func testSocialUpgradeKeepsOldRowsWhenEveryMapLookupThrows() async {
        let batch = PlaceImportBatch(id: "social-map-failure", source: .instagram, sourceName: nil, totalCount: 1)
        let sourceURL = "https://www.instagram.com/p/map-failure/"
        let candidate = placeImportCandidate(name: "Fremont Lake")
        let oldItem = PlaceImportItem(
            id: "map-failure-old",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Fremont Lake",
                areaHint: "Wyoming",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            resolverVersion: 4
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [oldItem])
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: ThrowingDevicePlaceResolver(),
                metadataProvider: FakeSocialImportMetadataProvider(
                    metadata: SocialImportMetadata(
                        title: "Wyoming itinerary",
                        caption: "Stop at Fremont Lake!",
                        authorName: "Creator",
                        thumbnailURL: nil
                    )
                ),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertEqual(store.items, [oldItem])
        XCTAssertEqual(persistence.snapshot.items, [oldItem])
    }

    func testSocialUpgradeKeepsOldRowsWhenMapLookupFailsAfterOneSuccess() async {
        let batch = PlaceImportBatch(
            id: "social-partial-map-failure",
            source: .instagram,
            sourceName: nil,
            totalCount: 2
        )
        let sourceURL = "https://www.instagram.com/p/partial-map-failure/"
        let oldItems = ["Fremont Lake", "Half Moon Lake Lodge"].enumerated().map { index, name in
            let candidate = placeImportCandidate(name: name)
            return PlaceImportItem(
                id: "partial-map-failure-old-\(index)",
                batchID: batch.id,
                source: .instagram,
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: name,
                    areaHint: "Wyoming",
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                state: .ready,
                candidates: [candidate],
                selectedCandidateID: candidate.id,
                resolverVersion: 4
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: oldItems)
        )
        let placeResolver = PartiallyThrowingDevicePlaceResolver(
            successfulName: "Fremont Lake",
            candidate: placeImportCandidate(
                name: "Fremont Lake",
                locality: "Pinedale",
                region: "WY"
            )
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: DevicePlaceImportResolver(
                placeResolver: placeResolver,
                metadataProvider: FakeSocialImportMetadataProvider(
                    metadata: SocialImportMetadata(
                        title: "Wyoming itinerary",
                        caption: "Stop at Fremont Lake! Base camp at Half Moon Lake Lodge!",
                        authorName: "Creator",
                        thumbnailURL: nil
                    )
                ),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
            )
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        XCTAssertTrue(placeResolver.manualInputs.contains { $0.name == "Fremont Lake" })
        XCTAssertTrue(placeResolver.manualInputs.contains { $0.name == "Half Moon Lake Lodge" })
        XCTAssertEqual(store.items, oldItems)
        XCTAssertEqual(persistence.snapshot.items, oldItems)
    }

    func testPartialSocialUpgradeMergesRecoveredPlacesAndKeepsSourceRetry() async throws {
        let sourceURL = "https://www.instagram.com/p/partial-upgrade-merge/"
        let batch = PlaceImportBatch(
            id: "partial-upgrade-merge",
            source: .instagram,
            sourceName: nil,
            totalCount: 1
        )
        let existingCandidate = placeImportCandidate(name: "Existing Place", address: "Los Angeles")
        let existingItem = PlaceImportItem(
            id: "partial-upgrade-existing",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Existing Place",
                areaHint: "Los Angeles",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            state: .ready,
            candidates: [existingCandidate],
            selectedCandidateID: existingCandidate.id,
            resolverVersion: 4
        )
        let recoveredCandidate = placeImportCandidate(name: "Recovered Place", address: "Malibu")
        let recoveredEntry = PlaceImportResolvedEntry(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: "Recovered Place",
                areaHint: "Malibu",
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            candidates: [recoveredCandidate],
            selectedCandidateID: recoveredCandidate.id,
            helpMessage: nil
        )
        let retrySeed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [existingItem])
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: SequencedPlaceImportResolver(resolutions: [
                .partialExpandedResolved([
                    recoveredEntry,
                    PlaceImportResolvedEntry(
                        seed: retrySeed,
                        candidates: [],
                        selectedCandidateID: nil,
                        helpMessage: "Some media in this post could not be read."
                    )
                ], sourceName: nil)
            ])
        )

        store.resumePendingImports()
        await store.waitForProcessing(batchID: batch.id)

        let items = store.items(for: batch.id)
        XCTAssertEqual(items.map(\.displayName), ["Existing Place", "Recovered Place", "Instagram post"])
        XCTAssertEqual(items.map(\.state), [.ready, .ready, .needsHelp])
        XCTAssertEqual(items.first?.id, existingItem.id)
        XCTAssertEqual(persistence.snapshot.items.map(\.displayName), items.map(\.displayName))
    }

    func testCurrentGoogleResolverVersionIsNotRequeuedBySocialVersionBump() {
        let batch = PlaceImportBatch(id: "google-current", source: .googleMaps, sourceName: nil, totalCount: 1)
        let candidate = placeImportCandidate(name: "Maru Coffee")
        let item = PlaceImportItem(
            id: "google-current-item",
            batchID: batch.id,
            source: .googleMaps,
            seed: PlaceImportSeed(
                rawText: "Maru Coffee",
                nameHint: "Maru Coffee",
                areaHint: "Los Angeles",
                sourceURLString: "https://maps.app.goo.gl/maru",
                sourceLine: 1
            ),
            state: .ready,
            candidates: [candidate],
            selectedCandidateID: candidate.id,
            resolverVersion: 4
        )

        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
            ),
            resolver: SuspendedPlaceImportResolver()
        )

        XCTAssertEqual(store.items, [item])
    }

    func testInstagramCarouselUpgradeProcessesEverySlideAndPersistsNineNamedPlaces() async throws {
        let destinationNames = [
            "Fremont Lake",
            "Green River Lakes",
            "Half Moon Lake Lodge",
            "White Mountain Petroglyphs",
            "Flaming Gorge",
            "Wind River Range",
            "Skyline Drive Overlook",
            "Pine Coffee Supply",
            "Farson Mercantile"
        ]
        // Captured from the live REC-106 post on July 20, 2026. These intentionally
        // include OCR mistakes, slogans, split business names, and noisy all-caps copy.
        let slideText: [String?] = [
            "an ~off the beaten path~ road trip through\nWYOMING",
            "@shoreline fishing at Fremont Lake",
            "Spaddle & hike at Green River Lakes",
            "g stay at\nHalf Moon Lake Lodge",
            "White Mountain Petroglyphs",
            "© cool off at Flaming Gorge",
            "Wind Riyer Range",
            "Skyline Drive Overlook",
            "PINE\nCOFFEE & SUPPLY\nmake sure you grab\na coffee because...\nCOFFEE",
            "you may stay up late admiring the night sky",
            nil,
            "FARSON\nMERCANTILE\nHome of the Big Cone\nGOURMET COFFEE,\nSANDWICHES & ICE CREAM\nnish\nthe adventure"
        ]
        let accessibilityText = [
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of poster, mountain and text that says 'an ~off the beaten path~ road trip through WYOMING 0 W Y M I N G 醬 ዮ は谷'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of standing, towel, raft, lake and text that says '@shoreline fishing at Fremont Lake'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of kayak, raft and text.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of campsite, fire, outdoors and text that says 'stay at Half stay+Half-MoonLakeLod Moon Lake Lodge'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of the Great Sphinx of Giza, Stone Henge and text that says 'S White Mountain WhiteMountainPetroglyphs Petroglyphs Aby'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of raft, Lake Powell and text that says '@cooloffa+FlamingGorge o! off at Flaming Gorge'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of mountain and text that says 'Wind RiverRange WindRiyerRange River Range'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of mountain and text that says 'Skyline Drive SkylineDriveOverlook Overlook'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of bolo tie, miniskirt and text that says 'PINE COFFEE COFFEE@SUPPLY 樂 SUPPLY COFFEE make makesuryougrab sure you grab acoffeebecause... a coffee because...'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of night, sky and text that says '...you may stay иp late admiring the night sky'.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of rearview mirror and text.",
            "Video by Rachel ☼ Travel | Adventure on July 09, 2026. May be an image of ice cream, signboard and text that says 'FARSON MERCANTILE Home of the Big Cone GOURMET COFFEE, SANDWICHES & ICE CREAM finish the adventure at Farson Farson_Mercantile! Mercantile! tile!'."
        ]
        let slideURLs = (1...12).compactMap {
            URL(string: "https://scontent-lax3-1.cdninstagram.com/carousel-\($0).jpg")
        }
        let mediaItems = zip(slideURLs, accessibilityText).map { url, text in
            SocialImportMediaEvidence(
                accessibilityText: text,
                imageURL: url
            )
        }
        var recognizedText: [URL: String] = [:]
        for (url, text) in zip(slideURLs, slideText) {
            if let text {
                recognizedText[url] = text
            }
        }
        let recognizer = FakeSocialThumbnailTextRecognizer(textByURL: recognizedText)
        let metadata = SocialImportMetadata(
            title: "sunnrayy on Instagram",
            caption: """
            Here's my guide to an off the beaten path trip through Wyoming! @visitWyoming
            Stop at Fremont Lake for some shoreline trout fishing!
            Rent a paddle board from @greatoutdoorsshopwy and spend the day paddling at Green River Lakes!
            Base camp at Half Moon Lake Lodge!
            Explore rustic roads on the way to see the petroglyphs at White Mountain Petroglyphs!
            Take a dip at Flaming Gorge!
            Go for a hike in @windrivercountry and afterwards, stop for dinner at @windriverbrewing!
            Enjoy the sunset at Skyline Drive Overlook!
            Grab a coffee at @PineCoffeeSupply!
            Reward yourself with a big cone at Farson Mercantile!
            """,
            authorName: "sunnrayy",
            thumbnailURL: nil,
            mediaItems: mediaItems
        )
        var routes = Dictionary(uniqueKeysWithValues: destinationNames.map { name in
            (name.lowercased(), [placeImportCandidate(
                name: name,
                locality: "Pinedale",
                region: "WY",
                latitude: 42.8,
                longitude: -109.8
            )])
        })
        routes["wind riyer range"] = routes["wind river range"]
        routes["pine coffee & supply"] = routes["pine coffee supply"]
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingNoCandidateThrowingDevicePlaceResolver(routes: routes),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: recognizer
        )
        let batchID = "wyoming-carousel"
        let sourceURL = "https://www.instagram.com/p/Dak2JCClKkF/"
        let oldItems = ["Pine Coffee Supply", "Fremont Lake", "Half Moon Lake Lodge"]
            .enumerated()
            .map { index, name in
                let candidate = placeImportCandidate(name: name)
                return PlaceImportItem(
                    id: "wyoming-old-\(index)",
                    batchID: batchID,
                    source: .instagram,
                    seed: PlaceImportSeed(
                        rawText: sourceURL,
                        nameHint: name,
                        areaHint: "Wyoming",
                        sourceURLString: sourceURL,
                        sourceLine: 1
                    ),
                    state: .ready,
                    candidates: [candidate],
                    selectedCandidateID: candidate.id,
                    resolverVersion: 4
                )
            }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(
                batches: [
                    PlaceImportBatch(
                        id: batchID,
                        source: .instagram,
                        sourceName: nil,
                        state: .ready,
                        totalCount: oldItems.count,
                        processedCount: oldItems.count
                    )
                ],
                items: oldItems
            )
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: resolver
        )

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.state, .queued)
        store.resumePendingImports()
        await store.waitForProcessing(batchID: batchID)

        let items = store.items(for: batchID)
        XCTAssertEqual(recognizer.requestedURLs.count, slideURLs.count)
        XCTAssertEqual(Set(recognizer.requestedURLs), Set(slideURLs))
        XCTAssertEqual(items.count, 9)
        XCTAssertEqual(items.map(\.displayName), destinationNames)
        XCTAssertTrue(items.allSatisfy { $0.state == .ready })
        XCTAssertEqual(store.batches.first?.totalCount, 9)
        XCTAssertEqual(store.batches.first?.processedCount, 9)
        XCTAssertEqual(store.summary.totalCount, 9)
        XCTAssertEqual(store.summary.readyCount, 9)
        XCTAssertEqual(persistence.snapshot.items.count, 9)

        let reloaded = PlaceImportStore(
            persistence: persistence,
            resolver: SuspendedPlaceImportResolver()
        )
        XCTAssertEqual(reloaded.items.count, 9)
        XCTAssertEqual(reloaded.items(for: batchID).map(\.displayName), destinationNames)
        XCTAssertEqual(reloaded.summary.readyCount, 9)
    }

    func testSummaryAggregatesUnresolvedItemsAcrossEveryImportBatch() async throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: FakePlaceImportResolver()
        )
        let readyBatchID = try store.enqueue(source: .textNotes, text: "Ready, Los Angeles")
        await store.waitForProcessing(batchID: readyBatchID)
        let helpBatchID = try store.enqueue(source: .tiktok, text: "Needs Help")
        await store.waitForProcessing(batchID: helpBatchID)

        XCTAssertEqual(store.summary.totalCount, 2)
        XCTAssertEqual(store.summary.readyCount, 1)
        XCTAssertEqual(store.summary.needsHelpCount, 1)
        XCTAssertEqual(Set(store.items.map(\.batchID)), [readyBatchID, helpBatchID])
    }

    func testSavedHistoryDoesNotInflateANewImportsProgress() async throws {
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(),
            resolver: FakePlaceImportResolver()
        )
        let oldBatchID = try store.enqueue(source: .textNotes, text: "Ready, Los Angeles")
        await store.waitForProcessing(batchID: oldBatchID)
        let oldItem = try XCTUnwrap(store.items(for: oldBatchID).first)
        store.markSaved(itemID: oldItem.id, userPlaceID: "saved-old")

        let newBatchID = try store.enqueue(source: .textNotes, text: "Ambiguous, Santa Monica")
        await store.waitForProcessing(batchID: newBatchID)

        XCTAssertEqual(store.summary.totalCount, 1)
        XCTAssertEqual(store.summary.processedCount, 1)
        XCTAssertEqual(store.summary.savedCount, 1)
        XCTAssertEqual(store.summary.needsHelpCount, 1)
    }

    func testLegacySocialAndGoogleFailuresAreRequeuedForTheNewResolver() {
        let batch = PlaceImportBatch(
            id: "legacy-batch",
            source: .googleMaps,
            sourceName: nil,
            totalCount: 1
        )
        let item = PlaceImportItem(
            id: "legacy-item",
            batchID: batch.id,
            source: .googleMaps,
            seed: PlaceImportSeed(
                id: "legacy-seed",
                rawText: "https://maps.app.goo.gl/bakeries",
                nameHint: nil,
                areaHint: nil,
                sourceURLString: "https://maps.app.goo.gl/bakeries",
                sourceLine: 1
            ),
            state: .ambiguous,
            candidates: (1...8).map { placeImportCandidate(name: "Nearby \($0)") },
            resolverVersion: nil
        )
        let store = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(
                snapshot: PlaceImportSnapshot(batches: [batch], items: [item])
            ),
            resolver: FakePlaceImportResolver()
        )

        XCTAssertEqual(store.item(id: item.id)?.state, .queued)
        XCTAssertEqual(store.item(id: item.id)?.candidates, [])
        XCTAssertEqual(store.item(id: item.id)?.resolverVersion, PlaceImportItem.currentResolverVersion)
    }

    private func manualSearchFixtureSnapshot() throws -> PlaceImportSnapshot {
        let bundle = Bundle(for: PlaceImportStoreTests.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "rec-106-manual-place-search-pre", withExtension: "json")
                ?? bundle.url(
                    forResource: "rec-106-manual-place-search-pre",
                    withExtension: "json",
                    subdirectory: "Fixtures"
                )
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshot = try decoder.decode(PlaceImportSnapshot.self, from: Data(contentsOf: url))
        snapshot.items = snapshot.items.map { item in
            var currentItem = item
            currentItem.resolverVersion = PlaceImportItem.currentResolverVersion
            return currentItem
        }
        return snapshot
    }

    private func waitForManualRequestCount(
        _ expectedCount: Int,
        resolver: ControllablePlaceImportResolver
    ) async -> Bool {
        for _ in 0..<1_000 {
            if resolver.manualSeeds.count >= expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private func waitForImportItem(
        id: String,
        nameHint: String,
        state: PlaceImportItemState,
        store: PlaceImportStore
    ) async -> Bool {
        for _ in 0..<1_000 {
            if let item = store.item(id: id),
               item.seed.nameHint == nameHint,
               item.state == state {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

@MainActor
final class DevicePlaceImportResolverTests: XCTestCase {
    func testDoesNotAutoSelectALoneCandidateWithADifferentName() async throws {
        let wrongCandidate = placeImportCandidate(name: "Blue Daisy")
        let placeResolver = FakeDevicePlaceResolver(candidates: [wrongCandidate])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider()
        )
        let seed = PlaceImportSeed(
            rawText: "Maru Coffee, Los Angeles",
            nameHint: "Maru Coffee",
            areaHint: "Los Angeles",
            sourceURLString: nil,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .textNotes)

        XCTAssertEqual(
            resolution,
            .needsHelp("The only Apple Maps result was not a confident venue match. Search for the correct place.")
        )
    }

    func testGoogleListPlaceKeepsGoogleNameAddressAndIdentityWhenMapKitReturnsAZipCode() async throws {
        let wrongCandidate = placeImportCandidate(
            name: "06700",
            address: "Cuauhtemoc, CDMX",
            latitude: 19.419,
            longitude: -99.162
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(candidates: [wrongCandidate]),
            metadataProvider: FakeSocialImportMetadataProvider()
        )
        let seed = PlaceImportSeed(
            rawText: "Palo de Rosa Cafe | Monterrey 177-Local C",
            nameHint: "Palo de Rosa Cafe",
            areaHint: "Monterrey 177-Local C, Roma Norte, CDMX",
            sourceURLString: "https://www.google.com/maps/place/?q=place_id:g/11inns9vzs",
            sourceLine: 1,
            latitude: 19.419,
            longitude: -99.162,
            sourceProvider: "google_maps",
            sourceProviderPlaceID: "g/11inns9vzs"
        )

        let resolution = try await resolver.resolve(seed: seed, source: .googleMaps)

        guard case .candidates(let candidates, let selectedCandidateID) = resolution else {
            return XCTFail("Expected one authoritative Google Maps candidate, got \(resolution)")
        }
        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(selectedCandidateID, candidate.id)
        XCTAssertEqual(candidate.name, "Palo de Rosa Cafe")
        XCTAssertEqual(candidate.address, "Monterrey 177-Local C, Roma Norte, CDMX")
        XCTAssertEqual(candidate.sourceProvider, "google_maps")
        XCTAssertEqual(candidate.sourceProviderPlaceID, "g/11inns9vzs")
        XCTAssertEqual(candidate.latitude, 19.419)
        XCTAssertEqual(candidate.longitude, -99.162)

        let item = PlaceImportItem(
            batchID: "batch",
            source: .googleMaps,
            seed: seed,
            state: .ready,
            candidates: [wrongCandidate],
            selectedCandidateID: wrongCandidate.id
        )
        XCTAssertEqual(item.displayName, "Palo de Rosa Cafe")
    }

    func testAutoSelectsAnExactNormalizedNameMatch() async throws {
        let candidate = placeImportCandidate(name: "Maru Coffee")
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(candidates: [candidate]),
            metadataProvider: FakeSocialImportMetadataProvider()
        )
        let seed = PlaceImportSeed(
            rawText: "Maru Coffee, Los Angeles",
            nameHint: "maru coffee",
            areaHint: "Los Angeles",
            sourceURLString: nil,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .textNotes)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
    }

    func testResolvesMendocinoFarmsFromASocialCaptionHandle() async throws {
        let candidate = placeImportCandidate(name: "Mendocino Farms")
        let placeResolver = FakeDevicePlaceResolver(candidates: [candidate])
        let metadata = SocialImportMetadata(
            title: "Lunch in Los Angeles",
            caption: "Lunch at @mendocinofarms restaurant in Los Angeles.",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let seed = PlaceImportSeed(
            rawText: "https://www.instagram.com/reel/example/",
            nameHint: nil,
            areaHint: nil,
            sourceURLString: "https://www.instagram.com/reel/example/",
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
        XCTAssertEqual(placeResolver.manualInputs.first?.name, "mendocino farms")
    }

    func testUsesCaptionCapturedByTheExtensionWhenInstagramMetadataIsUnavailable() async throws {
        let candidate = placeImportCandidate(name: "Mendocino Farms")
        let placeResolver = FakeDevicePlaceResolver(candidates: [candidate])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/reel/example/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1,
            socialCaptionHint: "Lunch at @mendocinofarms restaurant in Los Angeles."
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
        XCTAssertEqual(placeResolver.manualInputs.first?.name, "mendocino farms")
    }

    func testUsesCoverFrameTextWhenTheSocialCaptionHasNoPlaceName() async throws {
        let candidate = placeImportCandidate(name: "Mendocino Farms")
        let metadata = SocialImportMetadata(
            title: nil,
            caption: nil,
            authorName: nil,
            thumbnailURL: URL(string: "https://example.com/cover.jpg")
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(candidates: [candidate]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(text: "MENDOCINO FARMS\nLos Angeles, CA")
        )
        let seed = PlaceImportSeed(
            rawText: "https://www.tiktok.com/@creator/video/123",
            nameHint: nil,
            areaHint: nil,
            sourceURLString: "https://www.tiktok.com/@creator/video/123",
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .tiktok)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
    }

    func testSocialOCRCanCorrectOneCharacterWithoutEnablingFuzzyManualMatching() async throws {
        let candidate = placeImportCandidate(name: "Wind River Range")
        let imageURL = try XCTUnwrap(URL(string: "https://scontent-lax3-1.cdninstagram.com/wind-range.jpg"))
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [
                "wind riyer range": [candidate]
            ]),
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: nil,
                    caption: nil,
                    authorName: nil,
                    thumbnailURL: imageURL
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(text: "Wind Riyer Range")
        )
        let seed = PlaceImportSeed(
            rawText: "https://www.instagram.com/p/ocr-typo/",
            nameHint: nil,
            areaHint: nil,
            sourceURLString: "https://www.instagram.com/p/ocr-typo/",
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
    }

    func testSocialOCRRecoverySelectsColocatedCafeKevahDuplicatesAfterExactMiss() async throws {
        let cafeKevah = placeImportCandidate(
            name: "Cafe Kevah",
            address: "48510 Highway 1",
            locality: "Big Sur",
            latitude: 36.23295,
            longitude: -121.76612
        )
        let cafeKevahDuplicate = placeImportCandidate(
            name: "Cafe Kevah",
            address: "48510 CA-1",
            locality: "Big Sur",
            latitude: 36.23299,
            longitude: -121.76610
        )
        let nepenthe = placeImportCandidate(
            name: "Nepenthe",
            address: "48510 Highway 1",
            locality: "Big Sur",
            latitude: 36.23286,
            longitude: -121.76615
        )
        let bigSurBakery = placeImportCandidate(
            name: "Big Sur Bakery",
            address: "47540 CA-1",
            locality: "Big Sur",
            latitude: 36.23775,
            longitude: -121.76598
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "cafe nivah": [],
            "cafe": [nepenthe, cafeKevah, bigSurBakery, cafeKevahDuplicate]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Cafe Nivah",
                        area: "Big Sur",
                        evidence: .imageText
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/p/ocr-cafe-kevah/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .candidates(let candidates, let selectedCandidateID) = resolution else {
            return XCTFail("Expected recovered Cafe Kevah candidates, got \(resolution)")
        }
        XCTAssertEqual(selectedCandidateID, cafeKevah.id)
        XCTAssertEqual(candidates.first?.name, "Cafe Kevah")
        XCTAssertEqual(
            Set(candidates.map(\.id)),
            Set([cafeKevah.id, cafeKevahDuplicate.id, nepenthe.id, bigSurBakery.id])
        )
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Cafe Nivah", "Cafe"])
        XCTAssertEqual(placeResolver.manualInputs.map(\.areaHint), ["Big Sur", "Big Sur"])
    }

    func testSocialCaptionMissDoesNotUseOCRDesignatorRecovery() async throws {
        let cafeKevah = placeImportCandidate(
            name: "Cafe Kevah",
            locality: "Big Sur",
            latitude: 36.23295,
            longitude: -121.76612
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "cafe nivah": [],
            "cafe": [cafeKevah]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Cafe Nivah",
                        area: "Big Sur",
                        evidence: .itineraryPhrase
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/p/caption-cafe-nivah/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected an unresolved caption hint, got \(resolution)")
        }
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Cafe Nivah"])
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].candidates.isEmpty)
        XCTAssertNil(entries[0].selectedCandidateID)
    }

    func testSocialOCRRecoveryLeavesNonColocatedCafeKevahCandidatesUnresolved() async throws {
        let northCafeKevah = placeImportCandidate(
            name: "Cafe Kevah",
            address: "48510 Highway 1",
            locality: "Big Sur",
            latitude: 36.23295,
            longitude: -121.76612
        )
        let southCafeKevah = placeImportCandidate(
            name: "Cafe Kevah",
            address: "47225 Highway 1",
            locality: "Big Sur",
            latitude: 36.21420,
            longitude: -121.75720
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "cafe nivah": [],
            "cafe": [northCafeKevah, southCafeKevah]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Cafe Nivah",
                        area: "Big Sur",
                        evidence: .imageText
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/p/ocr-cafe-kevah-ambiguous/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected non-colocated candidates to require review, got \(resolution)")
        }
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Cafe Nivah", "Cafe"])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].candidates.map(\.id), [northCafeKevah.id, southCafeKevah.id])
        XCTAssertNil(entries[0].selectedCandidateID)
    }

    func testServerUnderstandingTurnsBlindCarouselIntoEightResolvedMapKitRows() async throws {
        let places: [(String, String)] = [
            ("Carbon Beach Club", "Malibu"),
            ("Vasquez Rocks Natural Area and Nature Center", "Agua Dulce"),
            ("Naples Canal", "Long Beach"),
            ("Cafe on 27", "Topanga"),
            ("Hotel Bel-Air", "Los Angeles"),
            ("Storrier Stearns Japanese Garden", "Pasadena"),
            ("The Stonehaus", "Westlake Village"),
            ("Sunset Ranch Hollywood", "Los Angeles")
        ]
        let routes = Dictionary(uniqueKeysWithValues: places.map { name, area in
            (name.lowercased(), [placeImportCandidate(name: name, address: area)])
        })
        let placeResolver = RoutingDevicePlaceResolver(routes: routes)
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .ok,
                hints: places.map { name, area in
                    SocialPlaceSearchHint(name: name, area: area, evidence: .imageText)
                },
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 9,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/p/DcAU9e5DYcH/"
        let seed = PlaceImportSeed(
            id: "blind-carousel-request",
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected eight resolved rows, got \(resolution)")
        }
        XCTAssertEqual(entries.map(\.seed.nameHint), places.map { Optional($0.0) })
        XCTAssertEqual(entries.count, 8)
        XCTAssertTrue(entries.allSatisfy { $0.selectedCandidateID != nil })
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), places.map { $0.0 })
        XCTAssertEqual(understanding.requests.first?.clientRequestID, "blind-carousel-request")
        XCTAssertEqual(understanding.requests.first?.source, .instagram)
    }

    func testDeclaredCountCompleteGoogleCandidateSkipsMapKitAndSourceRetry() async throws {
        let googleCandidate = PlaceCandidate(
            id: "google-places-nimmo",
            name: "Nimmo Bay Resort",
            category: "resort_hotel",
            rawProviderType: "resort_hotel",
            address: "1978 Broughton Blvd, Port McNeill, BC, Canada",
            locality: "Port McNeill",
            region: "BC",
            country: "CA",
            latitude: 50.6014,
            longitude: -126.6812,
            sourceProvider: "google_places",
            sourceProviderPlaceID: "nimmo",
            confidence: 1
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [:])
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .partial,
                hints: [
                    SocialPlaceSearchHint(
                        name: "Nimmo Bay Resort",
                        area: "British Columbia, Canada",
                        evidence: .itineraryPhrase,
                        isServerGrounded: true,
                        resolvedCandidates: [googleCandidate]
                    )
                ],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 1,
                    modelAttemptCount: 1,
                    failureCategory: "media_incomplete",
                    declaredCountComplete: true
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/p/server-google-candidate/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .candidates(let candidates, let selectedCandidateID) = resolution else {
            return XCTFail("Expected a selected Google candidate, got \(resolution)")
        }
        XCTAssertEqual(candidates, [googleCandidate])
        XCTAssertEqual(selectedCandidateID, googleCandidate.id)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testSocialMatchingSelectsUniqueGroundedLocalityDefaultAndRetainsAlternatives() async throws {
        let expected = placeImportCandidate(
            name: "Summit Archive",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let sameStateAlternative = placeImportCandidate(
            name: "Summit Archive",
            locality: "Pasadena",
            region: "CA",
            latitude: 34.1478,
            longitude: -118.1445
        )
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .ok,
                hints: [
                    SocialPlaceSearchHint(
                        name: "Summit Archive",
                        area: "Los Angeles, California",
                        evidence: .imageText
                    )
                ],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 1,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [
                "summit archive": [sameStateAlternative, expected]
            ]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/grounded-locality/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .candidates(let candidates, let selectedCandidateID) = resolution else {
            return XCTFail("Expected a selected default with alternatives, got \(resolution)")
        }
        XCTAssertEqual(selectedCandidateID, expected.id)
        XCTAssertEqual(candidates.map(\.id), [expected.id, sameStateAlternative.id])
    }

    func testPartialGeminiUnderstandingDoesNotResurrectFilteredLocalEvidence() async throws {
        let remoteCandidate = placeImportCandidate(
            name: "Fremont Lake",
            address: "Wyoming",
            locality: "Wyoming",
            region: ""
        )
        let localCandidate = placeImportCandidate(
            name: "Half Moon Lake Lodge",
            address: "Wyoming",
            locality: "Wyoming",
            region: ""
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [remoteCandidate],
            "half moon lake lodge": [localCandidate]
        ])
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .partial,
                hints: [
                    SocialPlaceSearchHint(
                        name: "Fremont Lake",
                        area: "Wyoming",
                        evidence: .imageText,
                        isServerGrounded: true
                    )
                ],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 2,
                    modelAttemptCount: 1,
                    failureCategory: "media_incomplete"
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Base camp at Half Moon Lake Lodge!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/p/partial-carousel/"
        let seed = PlaceImportSeed(
            id: "partial-carousel-request",
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected a retryable partial result, got \(resolution)")
        }
        XCTAssertEqual(entries.compactMap(\.seed.nameHint), ["Fremont Lake"])
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotNil(entries.first?.selectedCandidateID)
        XCTAssertNil(entries.last?.seed.nameHint)
        XCTAssertTrue(entries.last?.candidates.isEmpty == true)
        XCTAssertTrue(entries.last?.helpMessage?.contains("Retry automatic matching") == true)
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Fremont Lake"])
    }

    func testEmptyPartialGeminiScanCreatesOnlySourceRetryWithoutLocalGuessResurrection() async throws {
        let candidate = placeImportCandidate(name: "Fremont Lake", address: "Wyoming")
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .partial,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 3,
                    modelAttemptCount: 1,
                    failureCategory: "media_incomplete"
                )
            )
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [candidate]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Stop at Fremont Lake!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/empty-partial/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one source retry row, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sourceRetry)
        XCTAssertNil(entries[0].seed.nameHint)
        XCTAssertTrue(entries[0].candidates.isEmpty)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testServerGroundedMapKitMissesAllRemainVisibleInOrder() async throws {
        let names = ["First Grounded Place", "Second Grounded Place", "Third Grounded Place"]
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .ok,
                hints: names.map {
                    SocialPlaceSearchHint(name: $0, area: "California", evidence: .imageText)
                },
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 3,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [:]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/p/grounded-mapkit-misses/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected every grounded miss to remain reviewable, got \(resolution)")
        }
        XCTAssertEqual(entries.map(\.seed.nameHint), names.map(Optional.some))
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.allSatisfy { $0.candidates.isEmpty && $0.helpMessage != nil })
    }

    func testEveryRequiredRemoteHintKeepsOneReviewRowAcrossResolvedAmbiguousAndUnresolvedMatches() async throws {
        let bartsBooks = placeImportCandidate(
            name: "Bart's Books",
            address: "302 W Matilija St",
            locality: "Ojai",
            latitude: 34.4481,
            longitude: -119.2489
        )
        let kennethHahnMatches = [
            placeImportCandidate(
                name: "Kenneth Hahn State Recreation Area",
                address: "4100 S La Cienega Blvd",
                locality: "Los Angeles",
                latitude: 34.0064,
                longitude: -118.3658
            ),
            placeImportCandidate(
                name: "Kenneth Hahn State Recreation Area",
                address: "Bowl Loop",
                locality: "Los Angeles",
                latitude: 34.0224,
                longitude: -118.3581
            )
        ]
        let requiredHints = [
            SocialPlaceSearchHint(name: "Bart's Books", area: "Ojai", evidence: .itineraryPhrase),
            SocialPlaceSearchHint(
                name: "Kenneth Hahn State Recreation Area",
                area: "Los Angeles",
                evidence: .imageText
            ),
            SocialPlaceSearchHint(name: "Paseo del Mar Bluffs", area: "Los Angeles", evidence: .imageText)
        ]
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .ok,
                hints: requiredHints,
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 3,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [
                "bart's books": [bartsBooks],
                "kenneth hahn state recreation area": kennethHahnMatches
            ]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/required-review-rows/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one review row per required hint, got \(resolution)")
        }
        XCTAssertEqual(entries.map(\.seed.nameHint), requiredHints.map { Optional($0.name) })
        XCTAssertEqual(entries.count, requiredHints.count)
        XCTAssertNotNil(entries[0].selectedCandidateID)
        XCTAssertNil(entries[1].selectedCandidateID)
        XCTAssertEqual(entries[1].candidates.count, 2)
        XCTAssertNil(entries[2].selectedCandidateID)
        XCTAssertTrue(entries[2].candidates.isEmpty)
        XCTAssertNotNil(entries[2].helpMessage)
    }

    func testSocialLookupRetriesTransientFailuresAndThenUsesTheSuccessfulCandidate() async throws {
        let candidate = placeImportCandidate(name: "Bart's Books", locality: "Ojai")
        let placeResolver = ScriptedDevicePlaceResolver(results: [
            .failure(.timedOut),
            .failure(.networkConnectionLost),
            .candidates([candidate])
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Bart's Books",
                        area: "Ojai",
                        evidence: .itineraryPhrase
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/reel/transient-mapkit/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
        XCTAssertEqual(placeResolver.manualInputs.count, 3)
    }

    func testSocialNoCandidatesIsTerminalAndIsNotRetried() async throws {
        let placeResolver = ScriptedDevicePlaceResolver(results: [.noCandidates])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Paseo del Mar Bluffs",
                        area: "Los Angeles",
                        evidence: .imageText
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/reel/no-map-candidate/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one unresolved review row, got \(resolution)")
        }
        XCTAssertEqual(placeResolver.manualInputs.count, 1)
        XCTAssertTrue(entries[0].helpMessage?.contains("needs your help matching") == true)
        XCTAssertFalse(entries[0].helpMessage?.contains("temporarily unavailable") == true)
    }

    func testOptionalOCRRecoveryFailureDoesNotOverrideCleanPrimaryNoCandidate() async throws {
        let placeResolver = ScriptedDevicePlaceResolver(results: [
            .noCandidates,
            .failure(.timedOut),
            .failure(.timedOut),
            .failure(.timedOut)
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Cafe Nivah",
                        area: "Big Sur",
                        evidence: .imageText
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/p/ocr-recovery-outage/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected clean unresolved review row, got \(resolution)")
        }
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Cafe Nivah", "Cafe", "Cafe", "Cafe"])
        XCTAssertTrue(entries[0].helpMessage?.contains("needs your help matching") == true)
        XCTAssertFalse(entries[0].helpMessage?.contains("temporarily unavailable") == true)
    }

    func testPlausibleSoleSocialCandidateRemainsAvailableForReview() async throws {
        let candidate = placeImportCandidate(name: "Rory's Place Ojai")
        let resolver = DevicePlaceImportResolver(
            placeResolver: ScriptedDevicePlaceResolver(results: [.candidates([candidate])]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: socialUnderstandingResult(
                    hint: SocialPlaceSearchHint(
                        name: "Rory's Place",
                        area: nil,
                        evidence: .itineraryPhrase
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/reel/sole-plausible-candidate/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected sole candidate to remain reviewable, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].candidates, [candidate])
        XCTAssertNil(entries[0].selectedCandidateID)
    }

    func testServerUnderstandingUsesAttemptScopedRequestIDWhenPresent() async throws {
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .noPlaces,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 1,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/attempt-scoped/"
        let seed = PlaceImportSeed(
            id: "stable-import-seed",
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1,
            socialUnderstandingRequestID: "explicit-retry-attempt"
        )

        _ = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(understanding.requests.first?.clientRequestID, "explicit-retry-attempt")
    }

    func testFinishedAttemptRequestsOnePersistableFreshID() async throws {
        let understanding = SequencedSocialImportUnderstandingRepository(results: [
            SocialImportUnderstandingResult(
                outcome: .fallback,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_deterministic",
                    mediaCount: 0,
                    modelAttemptCount: 0,
                    failureCategory: "retry_required"
                )
            )
        ])
        let resolver = DevicePlaceImportResolver(
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/replay-finished/"
        let seed = PlaceImportSeed(
            id: "persisted-attempt-id",
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .retrySocialUnderstanding(let freshRequestID) = resolution else {
            return XCTFail("Expected a persistable replay request, got \(resolution)")
        }
        XCTAssertEqual(understanding.requests.count, 1)
        XCTAssertEqual(understanding.requests[0].clientRequestID, "persisted-attempt-id")
        XCTAssertNotEqual(freshRequestID, understanding.requests[0].clientRequestID)
        XCTAssertNotNil(UUID(uuidString: freshRequestID))
    }

    func testHostedFailuresWithoutGroundedHintsCreateOnlyASourceRetryRow() async throws {
        for failureCategory in [
            "auth_unavailable",
            "feature_flag_unavailable",
            "not_configured",
            "duplicate_request",
            "media_unavailable"
        ] {
            let candidate = placeImportCandidate(name: "Unreliable Local Guess")
            let placeResolver = FakeDevicePlaceResolver(candidates: [candidate])
            let resolver = DevicePlaceImportResolver(
                placeResolver: placeResolver,
                metadataProvider: FakeSocialImportMetadataProvider(
                    metadata: SocialImportMetadata(
                        title: "Unreliable Local Guess",
                        caption: "Visit Unreliable Local Guess",
                        authorName: nil,
                        thumbnailURL: nil
                    )
                ),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
                socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                    result: SocialImportUnderstandingResult(
                        outcome: .fallback,
                        hints: [],
                        diagnostics: SocialImportUnderstandingDiagnostics(
                            providerPath: "local_fallback",
                            mediaCount: 0,
                            modelAttemptCount: 0,
                            failureCategory: failureCategory
                        )
                    )
                )
            )
            let sourceURL = "https://www.instagram.com/reel/admission-\(failureCategory)/"

            let resolution = try await resolver.resolve(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: nil,
                    areaHint: nil,
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                source: .instagram
            )

            guard case .partialExpandedResolved(let entries, _) = resolution else {
                return XCTFail("Expected one source retry for \(failureCategory), got \(resolution)")
            }
            XCTAssertEqual(entries.count, 1, failureCategory)
            XCTAssertEqual(entries[0].kind, .sourceRetry, failureCategory)
            XCTAssertNil(entries[0].seed.nameHint, failureCategory)
            XCTAssertTrue(entries[0].candidates.isEmpty, failureCategory)
            XCTAssertTrue(placeResolver.manualInputs.isEmpty, failureCategory)
        }
    }

    func testThrownHostedFailureCreatesOnlyASourceRetryRow() async throws {
        let candidate = placeImportCandidate(name: "Unreliable Local Guess")
        let placeResolver = FakeDevicePlaceResolver(candidates: [candidate])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Unreliable Local Guess",
                    caption: "Visit Unreliable Local Guess",
                    authorName: nil,
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: ThrowingSocialImportUnderstandingRepository(
                error: URLError(.timedOut)
            )
        )
        let sourceURL = "https://www.instagram.com/reel/hosted-timeout/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one source retry row, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sourceRetry)
        XCTAssertNil(entries[0].seed.nameHint)
        XCTAssertTrue(entries[0].candidates.isEmpty)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testInFlightDuplicateDoesNotCreateLocalPlaceClaims() async throws {
        let candidate = placeImportCandidate(name: "Fremont Lake", address: "Wyoming")
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .fallback,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_deterministic",
                    mediaCount: 0,
                    modelAttemptCount: 0,
                    failureCategory: "duplicate_request"
                )
            )
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [candidate]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Stop at Fremont Lake!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/in-flight-duplicate/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one source retry row, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sourceRetry)
        XCTAssertNil(entries[0].seed.nameHint)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testServerMediaFallbackDoesNotCreateLocalPlaceClaims() async throws {
        let candidate = placeImportCandidate(name: "Fremont Lake", address: "Wyoming")
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .fallback,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_deterministic",
                    mediaCount: 1,
                    modelAttemptCount: 0,
                    failureCategory: "media_unavailable"
                )
            )
        )
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [candidate]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Stop at Fremont Lake!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/media-fallback/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one source retry row, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sourceRetry)
        XCTAssertNil(entries[0].seed.nameHint)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testHostedFallbackPreservesGroundedRemoteHintsWithoutAddingLocalGuesses() async throws {
        let remoteCandidate = placeImportCandidate(name: "Fremont Lake", address: "Wyoming")
        let localCandidate = placeImportCandidate(name: "Half Moon Lake Lodge", address: "Wyoming")
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [remoteCandidate],
            "half moon lake lodge": [localCandidate]
        ])
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .fallback,
                hints: [
                    SocialPlaceSearchHint(
                        name: "Fremont Lake",
                        area: "Wyoming",
                        evidence: .imageText,
                        isServerGrounded: true
                    )
                ],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 2,
                    modelAttemptCount: 1,
                    failureCategory: "media_unavailable"
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Base camp at Half Moon Lake Lodge!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/grounded-hosted-fallback/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected grounded partial results plus retry, got \(resolution)")
        }
        XCTAssertEqual(entries.compactMap(\.seed.nameHint), ["Fremont Lake"])
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.last?.kind, .sourceRetry)
        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["Fremont Lake"])
    }

    func testHostedFallbackRejectsUngroundedHintsWithoutAddingLocalGuesses() async throws {
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "fremont lake": [placeImportCandidate(name: "Fremont Lake", address: "Wyoming")]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Wyoming itinerary",
                    caption: "Stop at Fremont Lake!",
                    authorName: "Creator",
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                result: SocialImportUnderstandingResult(
                    outcome: .fallback,
                    hints: [
                        SocialPlaceSearchHint(
                            name: "Fremont Lake",
                            area: "Wyoming",
                            evidence: .imageText
                        )
                    ],
                    diagnostics: SocialImportUnderstandingDiagnostics(
                        providerPath: "apify_deterministic",
                        mediaCount: 1,
                        modelAttemptCount: 0,
                        failureCategory: "media_unavailable"
                    )
                )
            )
        )
        let sourceURL = "https://www.instagram.com/reel/ungrounded-hosted-fallback/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        guard case .partialExpandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one source retry row, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, .sourceRetry)
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testHostedFailureCategoryOverridesOtherwiseAuthoritativeOutcome() async throws {
        for outcome: SocialImportUnderstandingOutcome in [.ok, .noPlaces] {
            let placeResolver = FakeDevicePlaceResolver(
                candidates: [placeImportCandidate(name: "Unreliable Local Guess")]
            )
            let resolver = DevicePlaceImportResolver(
                placeResolver: placeResolver,
                metadataProvider: FakeSocialImportMetadataProvider(
                    metadata: SocialImportMetadata(
                        title: "Unreliable Local Guess",
                        caption: "Visit Unreliable Local Guess",
                        authorName: nil,
                        thumbnailURL: nil
                    )
                ),
                thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
                socialUnderstandingRepository: FakeSocialImportUnderstandingRepository(
                    result: SocialImportUnderstandingResult(
                        outcome: outcome,
                        hints: [],
                        diagnostics: SocialImportUnderstandingDiagnostics(
                            providerPath: "apify_gemini",
                            mediaCount: 1,
                            modelAttemptCount: 1,
                            failureCategory: "upstream_timeout"
                        )
                    )
                )
            )
            let sourceURL = "https://www.instagram.com/reel/failure-shaped-\(outcome.rawValue)/"

            let resolution = try await resolver.resolve(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: nil,
                    areaHint: nil,
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                source: .instagram
            )

            guard case .partialExpandedResolved(let entries, _) = resolution else {
                return XCTFail("Expected one source retry row for \(outcome), got \(resolution)")
            }
            XCTAssertEqual(entries.count, 1, outcome.rawValue)
            XCTAssertEqual(entries[0].kind, .sourceRetry, outcome.rawValue)
            XCTAssertTrue(placeResolver.manualInputs.isEmpty, outcome.rawValue)
        }
    }

    func testServerFallbackUsesExistingCaptionAndVisionPath() async throws {
        let candidate = placeImportCandidate(name: "Mendocino Farms")
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .fallback,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_deterministic",
                    mediaCount: 0,
                    modelAttemptCount: 0,
                    failureCategory: "feature_disabled"
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(candidates: [candidate]),
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: nil,
                    caption: "Lunch at @mendocinofarms restaurant in Los Angeles.",
                    authorName: nil,
                    thumbnailURL: nil
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/reel/fallback-example/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(resolution, .candidates([candidate], selectedCandidateID: candidate.id))
        XCTAssertEqual(understanding.requests.count, 1)
    }

    func testServerNoPlacesRemainsHonestWithoutRunningLocalGuessing() async throws {
        let placeResolver = FakeDevicePlaceResolver(
            candidates: [placeImportCandidate(name: "Unrelated Place")]
        )
        let understanding = FakeSocialImportUnderstandingRepository(
            result: SocialImportUnderstandingResult(
                outcome: .noPlaces,
                hints: [],
                diagnostics: SocialImportUnderstandingDiagnostics(
                    providerPath: "apify_gemini",
                    mediaCount: 1,
                    modelAttemptCount: 1,
                    failureCategory: nil
                )
            )
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "Los Angeles",
                    caption: "A nice day",
                    authorName: nil,
                    thumbnailURL: nil
                )
            ),
            socialUnderstandingRepository: understanding
        )
        let sourceURL = "https://www.instagram.com/p/no-place-example/"

        let resolution = try await resolver.resolve(
            seed: PlaceImportSeed(
                rawText: sourceURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: sourceURL,
                sourceLine: 1
            ),
            source: .instagram
        )

        XCTAssertEqual(
            resolution,
            .needsHelp("No destination was explicitly identified in this post. Add a place name and nearby city to match it.")
        )
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testCancelledServerUnderstandingDoesNotStartTheLocalNetworkFallback() async throws {
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(candidates: []),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: nil),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(),
            socialUnderstandingRepository: SelfCancellingSocialImportUnderstandingRepository()
        )
        let sourceURL = "https://www.instagram.com/reel/cancelled-example/"

        do {
            _ = try await resolver.resolve(
                seed: PlaceImportSeed(
                    rawText: sourceURL,
                    nameHint: nil,
                    areaHint: nil,
                    sourceURLString: sourceURL,
                    sourceLine: 1
                ),
                source: .instagram
            )
            XCTFail("Expected cancellation to stop before local fallback")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }
}

@MainActor
final class SocialPlaceImportMetadataTests: XCTestCase {
    func testEvidencePlannerRejectsSourceChromeAndCollapsesNestedAliases() {
        let hints = [
            SocialPlaceSearchHint(
                name: "instagram.com",
                area: nil,
                evidence: .imageText
            ),
            SocialPlaceSearchHint(
                name: "Presidio",
                area: "San Francisco",
                evidence: .explicitLocation
            ),
            SocialPlaceSearchHint(
                name: "Presidio National Park",
                area: "San Francisco",
                evidence: .imageText
            )
        ]

        let planned = SocialImportEvidencePlanner.reviewHints(hints)

        XCTAssertEqual(planned.map(\.name), ["Presidio National Park"])
    }

    func testEvidencePlannerDemotesExactGeographyUsedByDurableVenueAsArea() {
        let hints = [
            SocialPlaceSearchHint(
                name: "San Diego",
                area: "California",
                evidence: .explicitLocation
            ),
            SocialPlaceSearchHint(
                name: "Caroline's Seaside Cafe",
                area: "San Diego",
                evidence: .imageText
            )
        ]

        let planned = SocialImportEvidencePlanner.reviewHints(hints)

        XCTAssertEqual(planned.map(\.name), ["Caroline's Seaside Cafe"])
        XCTAssertEqual(planned.first?.area, "San Diego")
    }

    func testEvidencePlannerRemovesContextCityForVenueWithoutGenericDesignator() {
        let hints = [
            SocialPlaceSearchHint(
                name: "Westlake Village",
                area: "California",
                evidence: .imageText
            ),
            SocialPlaceSearchHint(
                name: "The Stonehaus",
                area: "Westlake Village",
                evidence: .imageText
            )
        ]

        let planned = SocialImportEvidencePlanner.reviewHints(hints)

        XCTAssertEqual(planned.map(\.name), ["The Stonehaus"])
        XCTAssertEqual(planned.first?.area, "Westlake Village")
    }

    func testEvidencePlannerKeepsDistinctNestedVenueNames() {
        let hints = [
            SocialPlaceSearchHint(
                name: "Gjusta",
                area: "Venice, California",
                evidence: .imageText
            ),
            SocialPlaceSearchHint(
                name: "Gjusta Goods",
                area: "Venice, California",
                evidence: .imageText
            )
        ]

        let planned = SocialImportEvidencePlanner.reviewHints(hints)

        XCTAssertEqual(planned.map(\.name), ["Gjusta", "Gjusta Goods"])
    }

    func testEvidencePlannerTrustsServerReasoningForGeographyAndNestedVenues() {
        let hints = [
            SocialPlaceSearchHint(
                name: "Westlake Village",
                area: "California",
                evidence: .itineraryPhrase,
                isServerGrounded: true
            ),
            SocialPlaceSearchHint(
                name: "The Stonehaus",
                area: "Westlake Village",
                evidence: .itineraryPhrase,
                isServerGrounded: true
            ),
            SocialPlaceSearchHint(
                name: "Acme",
                area: "Ojai",
                evidence: .imageText,
                isServerGrounded: true
            ),
            SocialPlaceSearchHint(
                name: "Acme Market",
                area: "Ojai",
                evidence: .imageText,
                isServerGrounded: true
            )
        ]

        XCTAssertEqual(
            SocialImportEvidencePlanner.reviewHints(hints).map(\.name),
            ["Westlake Village", "The Stonehaus", "Acme", "Acme Market"]
        )
    }

    func testEvidencePlannerKeepsGeographyWithoutDurableVenueContext() {
        let geography = SocialPlaceSearchHint(
            name: "San Diego",
            area: "California",
            evidence: .explicitLocation
        )
        let nonDurableVenue = SocialPlaceSearchHint(
            name: "Caroline's Seaside Cafe",
            area: "San Diego",
            evidence: .socialHandle
        )

        XCTAssertEqual(
            SocialImportEvidencePlanner.reviewHints([geography]).map(\.name),
            ["San Diego"]
        )
        XCTAssertEqual(
            SocialImportEvidencePlanner.reviewHints([geography, nonDurableVenue]).map(\.name),
            ["San Diego", "Caroline's Seaside Cafe"]
        )
    }

    func testEvidencePlannerDoesNotDemoteVenueLikeGeographicName() {
        let hints = [
            SocialPlaceSearchHint(
                name: "San Diego Zoo",
                area: "California",
                evidence: .explicitLocation
            ),
            SocialPlaceSearchHint(
                name: "Safari Kitchen",
                area: "San Diego Zoo",
                evidence: .imageText
            )
        ]

        XCTAssertEqual(
            SocialImportEvidencePlanner.reviewHints(hints).map(\.name),
            ["San Diego Zoo", "Safari Kitchen"]
        )
    }

    func testSeveralUnmatchedCaptionHintsProduceOneHonestRecoveryItem() async throws {
        let metadata = SocialImportMetadata(
            title: "Wyoming itinerary",
            caption: "Stop at Fremont Lake! Base camp at Half Moon Lake Lodge!",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [:]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/p/unmatched-itinerary/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected one recovery entry, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.seed.nameHint, "Half Moon Lake Lodge")
        XCTAssertTrue(entries.first?.candidates.isEmpty == true)
    }

    func testDenseGuideParserReconstructsWrappedNamesAndCountries() {
        let observations = [
            SocialTextObservation(
                text: "MOMOS COFFEE FLAGSHIP STORE / REPUBLIC",
                boundingBox: CGRect(x: 0.16, y: 0.80, width: 0.66, height: 0.016)
            ),
            SocialTextObservation(
                text: "OF KOREA",
                boundingBox: CGRect(x: 0.70, y: 0.794, width: 0.12, height: 0.012)
            ),
            SocialTextObservation(
                text: "DITTA ARTIGIANALE SPECIALTY",
                boundingBox: CGRect(x: 0.16, y: 0.60, width: 0.46, height: 0.015)
            ),
            SocialTextObservation(
                text: "COFFEE ROASTERS",
                boundingBox: CGRect(x: 0.16, y: 0.593, width: 0.29, height: 0.013)
            ),
            SocialTextObservation(
                text: "/ ITALY",
                boundingBox: CGRect(x: 0.63, y: 0.596, width: 0.12, height: 0.016)
            ),
            SocialTextObservation(
                text: "CASA BARISTA & CO., / DOMINICAN",
                boundingBox: CGRect(x: 0.12, y: 0.40, width: 0.46, height: 0.016)
            ),
            SocialTextObservation(
                text: "CASCO HISTORICO",
                boundingBox: CGRect(x: 0.12, y: 0.390, width: 0.27, height: 0.012)
            ),
            SocialTextObservation(
                text: "REPUBLIC",
                boundingBox: CGRect(x: 0.46, y: 0.394, width: 0.11, height: 0.009)
            ),
            SocialTextObservation(
                text: "OTTOMAN COFFEE HOUSE / UNITED KINGDOM NEW ENTRY",
                boundingBox: CGRect(x: 0.12, y: 0.20, width: 0.77, height: 0.015)
            ),
            SocialTextObservation(
                text: "THE BEST COFFEE SHOP IN EUROPE SPONSORED BY SLAYER",
                boundingBox: CGRect(x: 0.16, y: 0.788, width: 0.78, height: 0.009)
            )
        ]

        XCTAssertEqual(SocialGuideTextParser.rows(from: observations), [
            "MOMOS COFFEE FLAGSHIP STORE / REPUBLIC OF KOREA",
            "DITTA ARTIGIANALE SPECIALTY COFFEE ROASTERS / ITALY",
            "CASA BARISTA & CO., CASCO HISTORICO / DOMINICAN REPUBLIC",
            "OTTOMAN COFFEE HOUSE / UNITED KINGDOM"
        ])
    }

    func testExactHundredCoffeeGuideKeepsEveryOrderedNameAndCountry() {
        let expected = hundredCoffeeGuideRows()
        let recognizedTexts = [
            expected.prefix(50),
            expected.suffix(50)
        ].map { rows in
            rows.map { "\($0.name) / \($0.country)" }.joined(separator: "\n")
        }

        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: "The World's 100 Best Coffee Shops",
                caption: nil,
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: recognizedTexts
        )

        XCTAssertEqual(hints.count, 100)
        XCTAssertEqual(hints.map(\.name), expected.map(\.name))
        XCTAssertEqual(hints.map(\.area), expected.map { Optional($0.country) })
        XCTAssertTrue(hints.allSatisfy { $0.evidence == .imageText })
    }

    func testExactHundredCoffeeGuideReconstructsCapturedVisionGeometry() throws {
        let expected = hundredCoffeeGuideRows()
        let observationColumns = try hundredCoffeeGuideObservationColumns()
        let recognizedTexts = observationColumns.map {
            SocialGuideTextParser.rows(from: $0).joined(separator: "\n")
        }
        let parsedRows = recognizedTexts
            .flatMap { $0.split(separator: "\n").map(String.init) }
            .compactMap(SocialGuideTextParser.components(from:))

        XCTAssertEqual(parsedRows.count, 100)
        XCTAssertEqual(
            parsedRows.map { normalizedCoffeeGuideValue($0.name) },
            expected.map { normalizedCoffeeGuideValue($0.name) }
        )
        XCTAssertEqual(parsedRows.map(\.area), expected.map(\.country))

        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: "The World's 100 Best Coffee Shops",
                caption: nil,
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: recognizedTexts
        )
        XCTAssertEqual(hints.count, 100)
        XCTAssertEqual(
            hints.map { normalizedCoffeeGuideValue($0.name) },
            expected.map { normalizedCoffeeGuideValue($0.name) }
        )
        XCTAssertEqual(hints.map(\.area), expected.map { Optional($0.country) })
    }

    func testExactHundredCoffeeGuideExpandsBeforeAnyMapLookup() async throws {
        let expected = hundredCoffeeGuideRows()
        let slideURLs = [
            URL(string: "https://scontent-lax3-1.cdninstagram.com/coffee-guide-1.jpg")!,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/coffee-guide-2.jpg")!
        ]
        let recognizedTextByURL = Dictionary(uniqueKeysWithValues: zip(
            slideURLs,
            [expected.prefix(50), expected.suffix(50)].map { rows in
                rows.map { "\($0.name) / \($0.country)" }.joined(separator: "\n")
            }
        ))
        let placeResolver = RoutingDevicePlaceResolver(routes: [:])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(
                metadata: SocialImportMetadata(
                    title: "The World's 100 Best Coffee Shops",
                    caption: nil,
                    authorName: nil,
                    thumbnailURL: nil,
                    mediaItems: slideURLs.map {
                        SocialImportMediaEvidence(accessibilityText: nil, imageURL: $0)
                    }
                )
            ),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer(textByURL: recognizedTextByURL)
        )
        let sourceURL = "https://www.instagram.com/p/DU6kxigDOD-/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)
        guard case .expanded(let seeds, _) = resolution else {
            return XCTFail("Expected a durable guide expansion, got \(resolution)")
        }

        XCTAssertEqual(seeds.count, 100)
        XCTAssertEqual(seeds.map(\.nameHint), expected.map { Optional($0.name) })
        XCTAssertEqual(seeds.map(\.areaHint), expected.map { Optional($0.country) })
        XCTAssertEqual(seeds.map(\.sourceLine), Array(repeating: 1, count: 100))
        XCTAssertTrue(placeResolver.manualInputs.isEmpty)
    }

    func testHundredRowSocialExpansionPersistsBeforeFirstChildLookupAndReloadsInOrder() async throws {
        let sourceURL = "https://www.instagram.com/p/DU6kxigDOD-/"
        let seeds = hundredCoffeeGuideRows().map { row in
            PlaceImportSeed(
                rawText: sourceURL,
                nameHint: row.name,
                areaHint: row.country,
                sourceURLString: sourceURL,
                sourceLine: 1
            )
        }
        let persistence = InMemoryPlaceImportPersistence()
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: ExpandingThenSuspendingPlaceImportResolver(seeds: seeds)
        )

        let batchID = try store.enqueue(source: .instagram, text: sourceURL)
        let persistedEveryRow = await waitForPersistedItemCount(100, persistence: persistence)
        XCTAssertTrue(persistedEveryRow)

        let items = store.items(for: batchID)
        XCTAssertEqual(items.count, 100)
        XCTAssertEqual(items.map(\.displayName), seeds.compactMap(\.nameHint))
        XCTAssertEqual(items.map(\.seed.sourceLine), Array(repeating: 1, count: 100))
        XCTAssertEqual(store.summary.totalCount, 100)
        XCTAssertEqual(store.batches.first?.totalCount, 100)
        XCTAssertEqual(persistence.snapshot.items.count, 100)

        let relaunchedStore = PlaceImportStore(
            persistence: InMemoryPlaceImportPersistence(snapshot: persistence.snapshot),
            resolver: SuspendedPlaceImportResolver()
        )
        XCTAssertEqual(relaunchedStore.items(for: batchID).map(\.displayName), seeds.compactMap(\.nameHint))
        XCTAssertTrue(relaunchedStore.items(for: batchID).allSatisfy { $0.state == .queued })
        store.cancel(batchID: batchID)
    }

    func testGuideExpansionStaysAheadOfTheNextPastedSource() async {
        let batch = PlaceImportBatch(
            id: "multi-source-guide",
            source: .instagram,
            sourceName: nil,
            totalCount: 2
        )
        let firstURL = "https://www.instagram.com/p/guide/"
        let secondURL = "https://www.instagram.com/p/second/"
        let placeholder = PlaceImportItem(
            id: "guide-placeholder",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: firstURL,
                nameHint: nil,
                areaHint: nil,
                sourceURLString: firstURL,
                sourceLine: 1
            )
        )
        let secondCandidate = placeImportCandidate(name: "Second Source")
        let secondItem = PlaceImportItem(
            id: "second-source",
            batchID: batch.id,
            source: .instagram,
            seed: PlaceImportSeed(
                rawText: secondURL,
                nameHint: "Second Source",
                areaHint: "USA",
                sourceURLString: secondURL,
                sourceLine: 2
            ),
            state: .ready,
            candidates: [secondCandidate],
            selectedCandidateID: secondCandidate.id
        )
        let expandedSeeds = ["Guide One", "Guide Two", "Guide Three"].map { name in
            PlaceImportSeed(
                rawText: firstURL,
                nameHint: name,
                areaHint: "USA",
                sourceURLString: firstURL,
                sourceLine: 1
            )
        }
        let persistence = InMemoryPlaceImportPersistence(
            snapshot: PlaceImportSnapshot(batches: [batch], items: [placeholder, secondItem])
        )
        let store = PlaceImportStore(
            persistence: persistence,
            resolver: ExpandingThenSuspendingPlaceImportResolver(seeds: expandedSeeds)
        )

        store.resumePendingImports()
        let persistedExpansion = await waitForPersistedItemCount(4, persistence: persistence)
        XCTAssertTrue(persistedExpansion)
        XCTAssertEqual(
            store.items(for: batch.id).map(\.displayName),
            ["Guide One", "Guide Two", "Guide Three", "Second Source"]
        )
        store.cancel(batchID: batch.id)
    }

    func testManualSearchRejectsCandidatesFromTheWrongCountry() async throws {
        let wrongCountry = placeImportCandidate(
            name: "GOTA Coffee Experts",
            locality: "Los Angeles",
            region: "CA",
            country: "US"
        )
        let correctCountry = placeImportCandidate(
            name: "GOTA Coffee Experts",
            locality: "Vienna",
            region: "Vienna",
            country: "AT"
        )
        let unknownCountry = PlaceCandidate(
            id: "unknown-country-gota",
            name: "GOTA Coffee Experts",
            category: "cafe",
            locality: "Unknown",
            region: nil,
            country: nil,
            latitude: 0,
            longitude: 0,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "unknown-country-gota",
            confidence: 0.9
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: FakeDevicePlaceResolver(
                candidates: [wrongCountry, unknownCountry, correctCountry]
            )
        )
        let seed = PlaceImportSeed(
            rawText: "GOTA Coffee Experts / Austria",
            nameHint: "GOTA Coffee Experts",
            areaHint: "Austria",
            sourceURLString: "https://www.instagram.com/p/DU6kxigDOD-/",
            sourceLine: 1
        )

        let resolution = try await resolver.resolveManualSearch(seed: seed, source: .instagram)
        guard case .candidates(let candidates, _) = resolution else {
            return XCTFail("Expected the Austrian candidate, got \(resolution)")
        }
        XCTAssertEqual(candidates.map(\.id), [correctCountry.id])
    }

    func testEmbeddedInstagramParserPrefersLargestImageCandidate() throws {
        let post: [String: Any] = [
            "code": "DU6kxigDOD-",
            "caption": ["text": "The World's 100 Best Coffee Shops"],
            "carousel_media": [[
                "display_uri": "https://scontent-lax3-1.cdninstagram.com/display-513.jpg",
                "image_versions2": [
                    "candidates": [
                        [
                            "url": "https://scontent-lax3-1.cdninstagram.com/medium-750.jpg",
                            "width": 750,
                            "height": 935
                        ],
                        [
                            "url": "https://scontent-lax3-1.cdninstagram.com/original-1440.jpg",
                            "width": 1440,
                            "height": 1795
                        ]
                    ]
                ]
            ]]
        ]
        let json = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: post), encoding: .utf8)
        )

        let evidence = try XCTUnwrap(
            InstagramEmbeddedPostParser.evidence(
                from: "<script type='application/json'>\(json)</script>",
                expectedCode: "DU6kxigDOD-"
            )
        )

        XCTAssertEqual(
            evidence.mediaItems.first?.imageURL,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/original-1440.jpg")
        )
    }

    func testInstagramReelDoesNotTreatCreatorAttributionAsAPlace() async throws {
        let metadata = SocialImportMetadata(
            title: "Frank N Frank's on Instagram",
            caption: "@franknfranks is the latest Chinatown spot from veterans of Amboy and Howlin’s Ray’s, serving stacked sandwiches on house-made focaccia.",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let frank = placeImportCandidate(name: "Frank N Frank's")
        let incidental = placeImportCandidate(name: "Veterans of Amboy")
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "franknfranks": [frank],
            "veterans of amboy": [incidental]
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/reel/Da9EdCzBFuw/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)

        XCTAssertEqual(placeResolver.manualInputs.map(\.name), ["franknfranks"])
        XCTAssertEqual(resolution, .candidates([frank], selectedCandidateID: frank.id))
    }

    func testAcquisitionFromPhraseStillProducesAPlaceHint() {
        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: nil,
                caption: "Grab a sandwich from Maru Coffee.",
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: []
        )

        XCTAssertEqual(hints.map(\.name), ["Maru Coffee"])
    }

    func testAcquisitionFromPhraseRejectsPeopleAndCreatorAttribution() {
        let captions = [
            "Get restaurant recommendations from my friend Sara.",
            "Get this from the veterans of Amboy.",
            "Get the recipe from the team behind Maru Coffee."
        ]

        for caption in captions {
            let hints = SocialPlaceHintExtractor.hints(
                from: SocialImportMetadata(
                    title: nil,
                    caption: caption,
                    authorName: nil,
                    thumbnailURL: nil
                ),
                recognizedTexts: []
            )

            XCTAssertTrue(hints.isEmpty, "Unexpected place hint for: \(caption)")
        }
    }

    func testAcquisitionFromPhraseKeepsDistinctiveNameNonDurable() throws {
        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: nil,
                caption: "Grab lunch from Gjusta.",
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: []
        )

        let hint = try XCTUnwrap(hints.first)
        XCTAssertEqual(hint.name, "Gjusta")
        XCTAssertEqual(hint.evidence, .acquisitionPhrase)
        XCTAssertFalse(hint.evidence.shouldRemainVisibleWithoutCandidates)
    }

    func testAcquisitionFromPhraseKeepsVenueNamesBeginningWithFriend() {
        let captions = [
            "Grab pastries from Friends & Family.": "Friends & Family",
            "Get coffee from Friendship Coffee.": "Friendship Coffee"
        ]

        for (caption, expectedName) in captions {
            let hints = SocialPlaceHintExtractor.hints(
                from: SocialImportMetadata(
                    title: nil,
                    caption: caption,
                    authorName: nil,
                    thumbnailURL: nil
                ),
                recognizedTexts: []
            )

            XCTAssertEqual(hints.map(\.name), [expectedName], "Unexpected hints for: \(caption)")
        }
    }

    func testOneOCRSlideStateDoesNotConstrainTheWholeCarousel() throws {
        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: "Summer road trip guide",
                caption: nil,
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: [
                "an off the beaten path road trip through WYOMING",
                "Skyline Drive Overlook"
            ]
        )

        let skyline = try XCTUnwrap(hints.first { $0.name == "Skyline Drive Overlook" })
        XCTAssertNil(skyline.area)
    }

    func testVenueNameContainingStateDoesNotBecomePostWideArea() throws {
        for caption in [
            "Dinner at California Grill.",
            "Visit California Grill.",
            "Disney World travel guide for dinner at California Grill."
        ] {
            let hints = SocialPlaceHintExtractor.hints(
                from: SocialImportMetadata(
                    title: "Disney World travel guide",
                    caption: caption,
                    authorName: nil,
                    thumbnailURL: nil
                ),
                recognizedTexts: []
            )

            let grill = try XCTUnwrap(hints.first { $0.name == "California Grill" })
            XCTAssertNil(grill.area, "Unexpected post-wide area for: \(caption)")
        }
    }

    func testWyomingCarouselCaptionKeepsEveryNamedDestination() async throws {
        let metadata = SocialImportMetadata(
            title: "sunnrayy on Instagram",
            caption: """
            Here’s my guide to an off the beaten path trip through Wyoming!🌄🛶🗺️🌞 @visitWyoming #ThatsWY

            ‼️Remember that traveling to these beautiful places is a privilege - we must preserve and protect these areas for future generations! Leave no trace, adhere to local regulations and always leave places better than you found them! #WYresponsbily

            🎣 Stop at Fremont Lake for some shoreline trout fishing!
            🏔️ Rent a paddle board from @greatoutdoorsshopwy and spend the day paddling at Green River Lakes!
            🏕️ Base camp at Half Moon Lake Lodge!
            🗺️ Explore rustic roads on the way to see the petroglyphs at White Mountain Petroglyphs!
            💦 Take a dip at Flaming Gorge!
            🏞️ Go for a hike in @windrivercountry and afterwards, stop for dinner at @windriverbrewing!
            🌅 Enjoy the sunset at Skyline Drive Overlook!
            ☕️ Grab a coffee at @PineCoffeeSupply!
            🌌 Stargaze in Wyoming’s dark sky country!
            🗺️ Be ready to get a little dusty!
            🍦 Reward yourself for exploring the path less traveled with a big cone at Farson Mercantile!
            """,
            authorName: "sunnrayy",
            thumbnailURL: nil
        )
        let destinationNames = [
            "Fremont Lake",
            "Green River Lakes",
            "Half Moon Lake Lodge",
            "White Mountain Petroglyphs",
            "Flaming Gorge",
            "Skyline Drive Overlook",
            "Pine Coffee Supply",
            "Farson Mercantile"
        ]
        let routes = Dictionary(uniqueKeysWithValues: destinationNames.map { name in
            (name.lowercased(), [placeImportCandidate(
                name: name,
                locality: "Pinedale",
                region: "WY",
                latitude: 42.8,
                longitude: -109.8
            )])
        })
        let placeResolver = RoutingDevicePlaceResolver(routes: routes)
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/p/Dak2JCClKkF/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)
        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected every itinerary destination to expand, got \(resolution)")
        }
        XCTAssertEqual(Set(entries.compactMap(\.seed.nameHint)), Set(destinationNames))
        XCTAssertEqual(Set(placeResolver.manualInputs.compactMap(\.areaHint)), ["Wyoming"])
        XCTAssertTrue(placeResolver.manualInputs.allSatisfy { $0.areaHint == "Wyoming" })
    }

    func testSocialResolutionNormalizesMapKitAliasesAndRejectsWrongStateResults() async throws {
        let metadata = SocialImportMetadata(
            title: "Wyoming itinerary",
            caption: "Here’s my guide to a road trip through Wyoming! Stop at Farson Mercantile. Take a dip at Flaming Gorge. Enjoy the sunset at Skyline Drive Overlook!",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let farson = placeImportCandidate(
            name: "Farson Merc",
            address: "4048 U.S. Highway 191, Farson, WY",
            locality: "Farson",
            region: "WY",
            latitude: 42.109160,
            longitude: -109.448601
        )
        let flamingGorge = placeImportCandidate(
            name: "Flaming Gorge Reservoir",
            locality: "Green River",
            region: "WY",
            latitude: 41.084987,
            longitude: -109.545341
        )
        let skylineLosAngeles = (1...8).map { index in
            placeImportCandidate(
                name: "Skyline Drive Overlook",
                locality: "Los Angeles",
                region: "CA",
                latitude: 34.0 + Double(index) / 1_000,
                longitude: -118.2
            )
        }
        let placeResolver = RoutingDevicePlaceResolver(routes: [
            "farson mercantile": [farson],
            "flaming gorge": [flamingGorge],
            "skyline drive overlook": skylineLosAngeles
        ])
        let resolver = DevicePlaceImportResolver(
            placeResolver: placeResolver,
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/p/Dak2JCClKkF/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)
        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected three review entries, got \(resolution)")
        }

        XCTAssertEqual(placeResolver.manualInputs.map(\.areaHint), ["Wyoming", "Wyoming", "Wyoming"])
        XCTAssertEqual(entries.map(\.seed.nameHint), [
            "Farson Mercantile",
            "Flaming Gorge",
            "Skyline Drive Overlook"
        ])
        XCTAssertEqual(entries.map { $0.selectedCandidateID != nil }, [true, true, false])
        XCTAssertEqual(entries[0].candidates.first?.name, "Farson Mercantile")
        XCTAssertEqual(entries[0].candidates.first?.sourceProviderPlaceID, farson.sourceProviderPlaceID)
        XCTAssertEqual(entries[1].candidates.first?.name, "Flaming Gorge")
        XCTAssertTrue(entries[2].candidates.isEmpty)
        XCTAssertNotNil(entries[2].helpMessage)
    }

    func testNamedCaptionDestinationRemainsVisibleWhenMapKitReturnsNoCandidates() async throws {
        let metadata = SocialImportMetadata(
            title: "Wyoming itinerary",
            caption: "Explore the petroglyphs at White Mountain Petroglyphs!",
            authorName: "Creator",
            thumbnailURL: nil
        )
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: [:]),
            metadataProvider: FakeSocialImportMetadataProvider(metadata: metadata),
            thumbnailRecognizer: FakeSocialThumbnailTextRecognizer()
        )
        let sourceURL = "https://www.instagram.com/p/unresolved-example/"
        let seed = PlaceImportSeed(
            rawText: sourceURL,
            nameHint: nil,
            areaHint: nil,
            sourceURLString: sourceURL,
            sourceLine: 1
        )

        let resolution = try await resolver.resolve(seed: seed, source: .instagram)
        guard case .expandedResolved(let entries, _) = resolution else {
            return XCTFail("Expected an honest unresolved entry, got \(resolution)")
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.seed.nameHint, "White Mountain Petroglyphs")
        XCTAssertEqual(entries.first?.candidates, [])
        XCTAssertNotNil(entries.first?.helpMessage)
    }

    func testEmbeddedInstagramParserSelectsExpectedPostAndKeepsTwelveSlidesInOrder() throws {
        let children: [[String: Any]] = (1...12).map { index in
            var child: [String: Any] = [
                "id": "slide-\(index)",
                "accessibility_caption": "Slide \(index) text"
            ]
            if index.isMultiple(of: 2) {
                child["image_versions2"] = [
                    "candidates": [[
                        "url": "https://scontent-lax3-1.cdninstagram.com/fallback-\(index).jpg",
                        "width": 640,
                        "height": 853
                    ]]
                ]
            } else {
                child["display_uri"] = "https://scontent-lax3-1.cdninstagram.com/display-\(index).jpg"
            }
            return child
        }
        let root: [String: Any] = [
            "require": [
                ["nested": [
                    "code": "decoy-post",
                    "caption": ["text": "Wrong caption"],
                    "carousel_media": [["display_uri": "https://scontent-lax3-1.cdninstagram.com/decoy.jpg"]]
                ]],
                ["relay": ["payload": [
                    "code": "Dak2JCClKkF",
                    "caption": ["text": "Line one\nCoffee at @PineCoffeeSupply"],
                    "carousel_media": children
                ]]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: root)
        var body = try XCTUnwrap(String(data: data, encoding: .utf8))
        body = body.replacingOccurrences(of: "@PineCoffeeSupply", with: "\\u0040PineCoffeeSupply")
        let html = """
        <html><head></head><body>
        <script type='application/json' data-sjs>\(body)</script>
        </body></html>
        """

        let evidence = try XCTUnwrap(
            InstagramEmbeddedPostParser.evidence(
                from: html,
                expectedCode: "Dak2JCClKkF"
            )
        )

        XCTAssertEqual(evidence.caption, "Line one\nCoffee at @PineCoffeeSupply")
        XCTAssertEqual(evidence.mediaItems.count, 12)
        XCTAssertEqual(evidence.mediaItems.map(\.accessibilityText), (1...12).map { "Slide \($0) text" })
        XCTAssertEqual(
            evidence.mediaItems.first?.imageURL,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/display-1.jpg")
        )
        XCTAssertEqual(
            evidence.mediaItems[1].imageURL,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/fallback-2.jpg")
        )
    }

    func testEmbeddedInstagramParserFindsFullPostAfterBudgetHeavyPartialDuplicate() throws {
        let partial: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Partial duplicate"],
            "carousel_media": [],
            "unrelated_nodes": Array(repeating: 0, count: 100_100)
        ]
        let full: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Full caption"],
            "carousel_media": [
                ["display_uri": "https://scontent-lax3-1.cdninstagram.com/1.jpg"],
                ["display_uri": "https://scontent-lax3-1.cdninstagram.com/2.jpg"]
            ]
        ]
        let partialJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: partial), encoding: .utf8)
        )
        let fullJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: full), encoding: .utf8)
        )
        let html = """
        <script type="application/json">\(partialJSON)</script>
        <script type="application/json">\(fullJSON)</script>
        """

        let evidence = try XCTUnwrap(
            InstagramEmbeddedPostParser.evidence(from: html, expectedCode: "POST123")
        )

        XCTAssertEqual(evidence.caption, "Full caption")
        XCTAssertEqual(evidence.mediaItems.count, 2)
    }

    func testEmbeddedInstagramParserPrefersUsableImagesOverMoreAccessibilityOnlyRows() throws {
        let accessibilityOnly: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Accessibility-only duplicate"],
            "carousel_media": (1...12).map { index in
                ["accessibility_caption": "Slide \(index)"]
            }
        ]
        let usable: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Usable duplicate"],
            "carousel_media": (1...11).map { index in
                ["display_uri": "https://scontent-lax3-1.cdninstagram.com/usable-\(index).jpg"]
            }
        ]
        let accessibilityJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: accessibilityOnly), encoding: .utf8)
        )
        let usableJSON = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: usable), encoding: .utf8)
        )
        let html = """
        <script type="application/json">\(accessibilityJSON)</script>
        <script type="application/json">\(usableJSON)</script>
        """

        let evidence = try XCTUnwrap(
            InstagramEmbeddedPostParser.evidence(from: html, expectedCode: "POST123")
        )

        XCTAssertEqual(evidence.caption, "Usable duplicate")
        XCTAssertEqual(evidence.mediaItems.count, 11)
        XCTAssertTrue(evidence.mediaItems.allSatisfy { $0.imageURL != nil })
    }

    func testEmbeddedInstagramParserRejectsNonMetaMediaHosts() throws {
        let post: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Caption"],
            "carousel_media": [["display_uri": "https://attacker.example/image.jpg"]]
        ]
        let json = try XCTUnwrap(
            String(data: JSONSerialization.data(withJSONObject: post), encoding: .utf8)
        )

        let evidence = try XCTUnwrap(
            InstagramEmbeddedPostParser.evidence(
                from: "<script type='application/json'>\(json)</script>",
                expectedCode: "POST123"
            )
        )

        XCTAssertEqual(evidence.caption, "Caption")
        XCTAssertTrue(evidence.mediaItems.isEmpty)
    }

    func testInstagramMetaParserPreservesApostrophesAndReversedAttributeOrder() throws {
        let html = """
        <html><head>
        <meta name="twitter:title" content="Generic Instagram profile">
        <meta content="Ryan's lunch at @mendocinofarms &amp; a great patio" property="og:description">
        <meta property="og:title" content="Ryan on Instagram">
        <meta content="https://example.com/cover.jpg" property="og:image">
        </head></html>
        """

        let metadata = try XCTUnwrap(PublicSocialHTMLMetadataParser.metadata(from: html))

        XCTAssertEqual(metadata.caption, "Ryan's lunch at @mendocinofarms & a great patio")
        XCTAssertEqual(metadata.title, "Ryan on Instagram")
        XCTAssertEqual(metadata.authorName, "Ryan")
        XCTAssertEqual(metadata.thumbnailURL, URL(string: "https://example.com/cover.jpg"))
    }

    func testCaveSpringsInstagramPostExtractsEveryCreatorNamedPlace() throws {
        let html = """
        <html><head>
        <meta property="og:title" content="CAVE SPRINGS RESORT on Instagram: &quot;Castle Crags might just be Northern California&#x2019;s best-kept secret.&quot;">
        <meta property="og:description" content="1,229 likes, 36 comments - cavespringsdunsmuir on July 25, 2026: &quot;Castle Crags might just be Northern California&#x2019;s best-kept secret.

        Here&#x2019;s our favorite way to spend the day:

        Coffee at Cave Springs
        15-minute drive to Castle Crags State Park
        Hike to Castle Dome
        Head back to Cave Springs for a swim in the river, dinner, and a quiet evening under the stars.

        If you&#x2019;re planning a stay with us, make sure Castle Crags is on your itinerary.

        📍 Just 15 minutes from Cave Springs.&quot;.">
        </head></html>
        """
        let metadata = try XCTUnwrap(PublicSocialHTMLMetadataParser.metadata(from: html))

        let hints = SocialImportEvidencePlanner.reviewHints(
            SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])
        )

        XCTAssertEqual(
            Set(hints.map(\.name)),
            Set(["Cave Springs", "Castle Crags State Park", "Castle Dome"])
        )
        XCTAssertTrue(hints.allSatisfy { $0.evidence == .itineraryPhrase })
    }

    func testItineraryActionsRejectGenericDestinationsAndRelativeMapPins() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            Hike to feel better.
            Drive to the coast.
            Head to Castle Dome.
            📍 Just 15 minutes from Cave Springs.
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialImportEvidencePlanner.reviewHints(
            SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])
        )

        XCTAssertEqual(hints.map(\.name), ["Castle Dome"])
        XCTAssertEqual(hints.first?.evidence, .itineraryPhrase)
    }

    func testNumberedItineraryExtractsDestinationTailsWithoutInstructionWrappers() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            First time in Osaka? Here are the stops.
            1. Eat takoyaki (octopus balls). Osaka's soul food that can be found everywhere.
            2. Stroll down Dotonbori and gawk at the giant restaurant signboards
            3. Take a photo with the Glico man
            4. Grab a Japanese cheesecake from Rikuro
            5. Go to Teppanyaro izakaya in Namba for okonomiyaki
            6. Shop til you drop in Amerikamura
            7. Eat your way through Kuromon Market
            8. Explore Kitchen Street (Doguyasuji)
            9. Fish your own meal at Turikichi
            10. Base yourself in the heart of Osaka @Caption by Hyatt Namba to explore the city
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialImportEvidencePlanner.reviewHints(
            SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])
        )

        XCTAssertEqual(
            Set(hints.map(\.name)),
            Set([
                "Dotonbori",
                "Glico man",
                "Rikuro",
                "Teppanyaro izakaya",
                "Amerikamura",
                "Kuromon Market",
                "Kitchen Street (Doguyasuji)",
                "Turikichi",
                "Caption by Hyatt Namba"
            ])
        )
        XCTAssertEqual(
            hints.first(where: { $0.name == "Teppanyaro izakaya" })?.area,
            "Namba"
        )
        XCTAssertFalse(hints.contains { hint in
            ["the giant restaurant signboards", "Shop til you drop", "Eat your way through Kuromon Market",
             "Fish your own meal at Turikichi", "Eat takoyaki"].contains(hint.name)
        })
    }

    func testNumberedItineraryPreservesLegacyFormsConnectorsAndMultipleStops() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            1. Dinner at Gjusta
            2. Stop at Fremont Lake
            3. Visit Griffith Observatory
            4. Base camp at Half Moon Lake Lodge
            5. Visit Story and Soil Coffee
            6. Go to Atte for Coffee
            7. Breakfast at Republique, then drinks at Bar Stella
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])

        XCTAssertEqual(
            hints.map(\.name),
            [
                "Gjusta",
                "Fremont Lake",
                "Griffith Observatory",
                "Half Moon Lake Lodge",
                "Story and Soil Coffee",
                "Atte for Coffee",
                "Republique",
                "Bar Stella"
            ]
        )
    }

    func testNumberedItineraryKeepsPlainNamesAndRejectsGenericInstructionsOrMentions() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            1. Pine Coffee Supply
            2. Farson Mercantile
            3. Go get coffee
            4. Grab lunch at the hotel
            5. Shop in local markets
            6. Eat at Gjusta with @Ryan
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])

        XCTAssertEqual(hints.map(\.name), ["Pine Coffee Supply", "Farson Mercantile", "Gjusta"])
        XCTAssertFalse(hints.contains { $0.name == "Ryan" })
    }

    func testNumberedItineraryRejectsProseWhilePreservingLowercaseAndNamesContainingIn() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            1. Pack sunscreen
            2. Check the weather
            3. Dinner at gjusta
            4. Base yourself at @captionbyhyattnambaosaka
            5. Visit Alice in Wonderland Cafe
            6. Explore all of these spots
            7. Visit frank n franks
            8. Visit @carolines_seaside_cafe
            9. Visit Baked in Brooklyn
            10. Visit 麺屋 一燈
            11. Dinner at the @sunrise_bakery
            12. Visit Nobu in Malibu
            13. Go to dave and busters
            14. Walk to mama shelter
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])

        XCTAssertEqual(
            hints.map(\.name),
            [
                "gjusta",
                "captionbyhyattnambaosaka",
                "Alice in Wonderland Cafe",
                "frank n franks",
                "carolines seaside cafe",
                "Baked in Brooklyn",
                "麺屋 一燈",
                "sunrise bakery",
                "Nobu",
                "dave and busters",
                "mama shelter"
            ]
        )
        XCTAssertNil(hints.first(where: { $0.name == "Alice in Wonderland Cafe" })?.area)
        XCTAssertNil(hints.first(where: { $0.name == "Baked in Brooklyn" })?.area)
        XCTAssertEqual(hints.first(where: { $0.name == "Nobu" })?.area, "Malibu")
        XCTAssertEqual(
            hints.first(where: { $0.name == "captionbyhyattnambaosaka" })?.evidence,
            .itineraryHandle
        )
        let handleHint = try? XCTUnwrap(
            hints.first(where: { $0.name == "carolines seaside cafe" })
        )
        XCTAssertEqual(handleHint?.evidence, .itineraryHandle)
        XCTAssertEqual(handleHint?.evidence.shouldRemainVisibleWithoutCandidates, false)
        XCTAssertEqual(
            hints.first(where: { $0.name == "sunrise bakery" })?.evidence,
            .itineraryHandle
        )
    }

    func testNumberedItineraryRejectsActivityWrappersAndIncidentalStayMention() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            1. Stay at Hotel Juno with @ryan for two nights
            2. Walk to get ice cream
            3. Go to see the sunset
            4. Drive to find parking
            5. Visit Made in Italy
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])

        XCTAssertEqual(hints.map(\.name), ["Hotel Juno", "Made in Italy"])
        XCTAssertTrue(hints.allSatisfy { $0.area == nil })
    }

    func testNumberedItineraryOnRecognizedSlideUsesImageEvidence() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: nil,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialPlaceHintExtractor.hints(
            from: metadata,
            recognizedTexts: [
                """
                1. Dinner at Gjusta
                2. Visit Griffith Observatory
                """
            ]
        )

        XCTAssertEqual(hints.map(\.name), ["Gjusta", "Griffith Observatory"])
        XCTAssertTrue(hints.allSatisfy { $0.evidence == .imageText })
    }

    func testExtractorAndPlannerDemoteExplicitGeographyUsedAsVenueArea() {
        let metadata = SocialImportMetadata(
            title: nil,
            caption: """
            📍 San Diego
            Dinner at Caroline's Seaside Cafe in San Diego.
            """,
            authorName: nil,
            thumbnailURL: nil
        )

        let hints = SocialImportEvidencePlanner.reviewHints(
            SocialPlaceHintExtractor.hints(from: metadata, recognizedTexts: [])
        )

        XCTAssertEqual(hints.map(\.name), ["Caroline's Seaside Cafe"])
        XCTAssertEqual(hints.first?.area, "San Diego")
    }

    func testCandidateMatcherTreatsRestaurantSuffixAsTheSamePlaceName() {
        let candidate = placeImportCandidate(name: "Mendocino Farms")

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Mendocino Farms Restaurant",
            areaHint: "Los Angeles"
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
    }

    func testCandidateMatcherTreatsCreatorQualifiedCafeNameAsTheSameVenue() {
        let candidate = placeImportCandidate(
            name: "Caroline's Seaside Cafe",
            address: "8610 Kennel Way, La Jolla, CA"
        )

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Caroline's Seaside Cafe by Giuseppe",
            areaHint: "San Diego"
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
    }

    func testCandidateMatcherDoesNotCollapseGenericByNameWithoutVenueDesignator() {
        let candidate = placeImportCandidate(name: "Caption")

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Caption by Hyatt Namba",
            areaHint: "Osaka"
        )

        XCTAssertNil(match.selectedCandidateID)
    }

    func testCandidateMatcherDoesNotCollapseGenericCreatorQualifiedVenueNames() {
        for (candidateName, hint) in [
            ("Cafe", "Cafe by the Bay"),
            ("Hotel", "Hotel by Marriott"),
            ("Coffee Shop", "Coffee Shop by Jane"),
            ("Coffee House", "Coffee House by Jane"),
            ("Coffeehouse Cafe", "Coffeehouse Cafe by Jane"),
            ("Local Cafe", "Local Cafe by Jane"),
            ("Neighborhood Cafe", "Neighborhood Cafe by Jane"),
            ("Street Cafe", "Street Cafe by Jane")
        ] {
            let candidate = placeImportCandidate(name: candidateName)
            let match = PlaceImportCandidateMatcher.match(
                [candidate],
                nameHint: hint,
                areaHint: nil
            )
            XCTAssertNil(match.selectedCandidateID, "Unexpected generic alias: \(candidateName)")
        }
    }

    func testCandidateMatcherTreatsMercAsMercantileAcrossStateNameFormats() {
        let candidate = placeImportCandidate(
            name: "Farson Merc",
            address: "4048 U.S. Highway 191, Farson, WY",
            locality: "Farson",
            region: "WY",
            latitude: 42.109160,
            longitude: -109.448601
        )

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Farson Mercantile",
            areaHint: "Wyoming"
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
    }

    func testSocialCandidateMatcherTreatsVgnAsVeganForGroundedVenue() {
        let candidate = placeImportCandidate(
            name: "Hip Vgn",
            address: "201 N Montgomery St, Ojai, CA",
            locality: "Ojai",
            region: "CA",
            latitude: 34.4490,
            longitude: -119.2433
        )

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Hip Vegan",
            areaHint: "Ojai, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
        XCTAssertGreaterThanOrEqual(match.bestScore, 0.9)
    }

    func testExplicitStateCodeWinsOverStateNameInsideCity() {
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "Kansas City, MO"), "MO")
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "Washington, DC"), "DC")
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "Jackson, wy"), "WY")
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "Kansas City, Mo"), "MO")
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "Washington, D.C."), "DC")
        XCTAssertEqual(PlaceImportGeography.stateCode(in: "NE Portland, OR"), "OR")
    }

    func testLosAngelesShorthandDoesNotBecomeLouisianaSearchRegion() {
        let losAngeles = ManualPlaceSearchPlan(name: "Gjusta", areaHint: "LA")
        let downtown = ManualPlaceSearchPlan(name: "Gjusta", areaHint: "Downtown LA")
        let batonRouge = ManualPlaceSearchPlan(name: "Coffee Call", areaHint: "Baton Rouge, LA")

        XCTAssertEqual(losAngeles.query, "Gjusta LA")
        XCTAssertNil(losAngeles.regionHint)
        XCTAssertEqual(downtown.query, "Gjusta Downtown LA")
        XCTAssertNil(downtown.regionHint)
        XCTAssertEqual(batonRouge.query, "Coffee Call Baton Rouge")
        XCTAssertNotNil(batonRouge.regionHint)
    }

    func testGeorgiaCountryDoesNotBecomeUSStateSearchRegion() {
        let country = ManualPlaceSearchPlan(name: "Cafe Littera", areaHint: "Tbilisi, Georgia")
        let ambiguous = ManualPlaceSearchPlan(name: "The Grey", areaHint: "Georgia")
        let postalState = ManualPlaceSearchPlan(name: "The Grey", areaHint: "Savannah, GA")
        let namedState = ManualPlaceSearchPlan(name: "The Grey", areaHint: "Savannah, Georgia, USA")

        XCTAssertEqual(country.query, "Cafe Littera Tbilisi, Georgia")
        XCTAssertNil(country.regionHint)
        XCTAssertEqual(ambiguous.query, "The Grey Georgia")
        XCTAssertNil(ambiguous.regionHint)
        XCTAssertEqual(postalState.query, "The Grey Savannah")
        XCTAssertNotNil(postalState.regionHint)
        XCTAssertEqual(namedState.query, "The Grey Savannah")
        XCTAssertNotNil(namedState.regionHint)
    }

    func testGeorgiaCountryDoesNotBecomePostWideUSStateContext() throws {
        let hints = SocialPlaceHintExtractor.hints(
            from: SocialImportMetadata(
                title: nil,
                caption: "Road trip through Georgia. Dinner at Cafe Littera.",
                authorName: nil,
                thumbnailURL: nil
            ),
            recognizedTexts: []
        )

        let cafe = try XCTUnwrap(hints.first { $0.name == "Cafe Littera" })
        XCTAssertNil(cafe.area)
    }

    func testCandidateMatcherRejectsAnExactNameInAConflictingState() {
        let candidate = placeImportCandidate(
            name: "Skyline Drive Overlook",
            locality: "Los Angeles",
            region: "CA"
        )

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Skyline Drive Overlook",
            areaHint: "Wyoming"
        )

        XCTAssertTrue(match.candidates.isEmpty)
        XCTAssertNil(match.selectedCandidateID)
    }

    func testCandidateMatcherAcceptsGeographicProviderSuffixInTheRightState() {
        let candidate = placeImportCandidate(
            name: "Flaming Gorge Reservoir",
            locality: "Green River",
            region: "WY",
            latitude: 41.084987,
            longitude: -109.545341
        )

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Flaming Gorge",
            areaHint: "Wyoming"
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
    }

    func testSocialCandidateMatcherRejectsExactNameInConflictingState() {
        let texas = placeImportCandidate(
            name: "Vital Junction",
            locality: "Austin",
            region: "TX",
            latitude: 30.2672,
            longitude: -97.7431
        )

        let match = PlaceImportCandidateMatcher.match(
            [texas],
            nameHint: "Vital Junction",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertTrue(match.candidates.isEmpty)
        XCTAssertNil(match.selectedCandidateID)
    }

    func testSocialCandidateMatcherSelectsExactCanadianVenueWithProvinceAndCountryAliases() {
        let nimmoBay = placeImportCandidate(
            name: "Nimmo Bay Resort",
            address: "1978 Broughton Blvd",
            locality: "Port McNeill",
            region: "BC",
            country: "CA",
            latitude: 50.9393249,
            longitude: -126.682148
        )

        let match = PlaceImportCandidateMatcher.match(
            [nimmoBay],
            nameHint: "Nimmo Bay Resort",
            areaHint: "British Columbia, Canada",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, nimmoBay.id)
    }

    func testSocialCandidateMatcherDoesNotSelectExactCanadianVenueInWrongProvince() {
        let ontario = placeImportCandidate(
            name: "Nimmo Bay Resort",
            locality: "Toronto",
            region: "ON",
            country: "CA",
            latitude: 43.6532,
            longitude: -79.3832
        )

        let match = PlaceImportCandidateMatcher.match(
            [ontario],
            nameHint: "Nimmo Bay Resort",
            areaHint: "British Columbia, Canada",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.candidates.map(\.id), [ontario.id])
        XCTAssertNil(match.selectedCandidateID)
    }

    func testSocialCandidateMatcherSelectsUniqueExactInternationalVenueWhenAddressOmitsBroaderRegion() {
        let shintaManiWild = placeImportCandidate(
            name: "Shinta Mani Wild",
            address: "Preah Sihanouk, Cambodia",
            locality: "Preah Sihanouk",
            region: "Preah Sihanouk Province",
            country: "KH",
            latitude: 11.1935,
            longitude: 103.8364
        )

        let match = PlaceImportCandidateMatcher.match(
            [shintaManiWild],
            nameHint: "Shinta Mani Wild",
            areaHint: "Cardamom Mountains, Cambodia",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, shintaManiWild.id)
    }

    func testSocialCandidateMatcherRejectsExactInternationalVenueInWrongCountry() {
        let washington = placeImportCandidate(
            name: "Nimmo Bay Resort",
            locality: "Seattle",
            region: "WA",
            country: "US",
            latitude: 47.6062,
            longitude: -122.3321
        )

        let match = PlaceImportCandidateMatcher.match(
            [washington],
            nameHint: "Nimmo Bay Resort",
            areaHint: "British Columbia, Canada",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertTrue(match.candidates.isEmpty)
        XCTAssertNil(match.selectedCandidateID)
    }

    func testSocialCandidateMatcherMatchesCountryNameHintToISOProviderCountry() {
        let retreat = placeImportCandidate(
            name: "The Retreat at Blue Lagoon Iceland",
            locality: "Grindavik",
            region: "Southern Peninsula",
            country: "IS",
            latitude: 63.8804,
            longitude: -22.4495
        )

        let match = PlaceImportCandidateMatcher.match(
            [retreat],
            nameHint: "The Retreat at Blue Lagoon Iceland",
            areaHint: "Iceland",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, retreat.id)
    }

    func testSocialCandidateMatcherDoesNotTreatCanadianCountryCodeAsCalifornia() {
        let vancouver = placeImportCandidate(
            name: "Summit Archive",
            locality: "Vancouver",
            region: "BC",
            country: "CA",
            latitude: 49.2827,
            longitude: -123.1207
        )

        let match = PlaceImportCandidateMatcher.match(
            [vancouver],
            nameHint: "Summit Archive",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.candidates.map(\.id), [vancouver.id])
        XCTAssertNil(match.selectedCandidateID)
    }

    func testSocialCandidateMatcherDoesNotSelectExactNameWhenLocalityContextConflicts() {
        let texas = placeImportCandidate(
            name: "Vital Junction",
            locality: "Austin",
            region: "TX",
            latitude: 30.2672,
            longitude: -97.7431
        )

        for areaHint in ["Los Angeles", "LA"] {
            let match = PlaceImportCandidateMatcher.match(
                [texas],
                nameHint: "Vital Junction",
                areaHint: areaHint,
                selectionPolicy: .socialGroundedArea
            )

            XCTAssertEqual(match.candidates.map(\.id), [texas.id])
            XCTAssertNil(match.selectedCandidateID, "Unexpected selection for area hint \(areaHint)")
        }
    }

    func testSocialCandidateMatcherDoesNotTreatSameStateAsLocalityEvidence() {
        let sanDiego = placeImportCandidate(
            name: "Summit Archive",
            locality: "San Diego",
            region: "CA",
            latitude: 32.7157,
            longitude: -117.1611
        )

        let match = PlaceImportCandidateMatcher.match(
            [sanDiego],
            nameHint: "Summit Archive",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.candidates.map(\.id), [sanDiego.id])
        XCTAssertNil(match.selectedCandidateID)
    }

    func testSocialCandidateMatcherTreatsLAAliasAsLosAngelesEvidence() {
        let losAngeles = placeImportCandidate(
            name: "Summit Archive",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0522,
            longitude: -118.2437
        )

        let match = PlaceImportCandidateMatcher.match(
            [losAngeles],
            nameHint: "Summit Archive",
            areaHint: "LA",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, losAngeles.id)
    }

    func testSocialCandidateMatcherLeavesSameLocalityTieAmbiguous() {
        let first = placeImportCandidate(
            name: "Summit Archive",
            address: "100 First St",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let second = placeImportCandidate(
            name: "Summit Archive",
            address: "200 Second St",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0622,
            longitude: -118.2537
        )

        let match = PlaceImportCandidateMatcher.match(
            [first, second],
            nameHint: "Summit Archive",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertNil(match.selectedCandidateID)
        XCTAssertEqual(match.candidates.count, 2)
    }

    func testSocialCandidateMatcherSelectsGroundedLandmarkProviderLeadAndKeepsAlternatives() {
        let providerLead = placeImportCandidate(
            name: "Mount Meridian",
            region: "CA",
            latitude: 34.2244,
            longitude: -118.0575
        )
        let lowerRankedAlternative = placeImportCandidate(
            name: "Mount Meridian",
            locality: "Pasadena",
            region: "CA",
            latitude: 34.1478,
            longitude: -118.1445
        )

        let socialMatch = PlaceImportCandidateMatcher.match(
            [lowerRankedAlternative, providerLead],
            nameHint: "Mount Meridian",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )
        let manualMatch = PlaceImportCandidateMatcher.match(
            [lowerRankedAlternative, providerLead],
            nameHint: "Mount Meridian",
            areaHint: "Los Angeles, California"
        )

        XCTAssertEqual(socialMatch.selectedCandidateID, providerLead.id)
        XCTAssertEqual(
            socialMatch.candidates.map(\.id),
            [providerLead.id, lowerRankedAlternative.id]
        )
        XCTAssertNil(manualMatch.selectedCandidateID)
    }

    func testSocialCandidateMatcherSelectsUniqueSameStateLandmarkWithoutLocality() {
        let landmark = placeImportCandidate(
            name: "Vetter Mountain",
            region: "CA",
            latitude: 34.2914,
            longitude: -118.0281
        )
        let trail = placeImportCandidate(
            name: "Vetter Mountain Trail",
            locality: "Palmdale",
            region: "CA",
            latitude: 34.2901,
            longitude: -118.0302
        )

        let match = PlaceImportCandidateMatcher.match(
            [trail, landmark],
            nameHint: "Vetter Mountain",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, landmark.id)
        XCTAssertEqual(match.candidates.map(\.id), [landmark.id, trail.id])
    }

    func testSocialCandidateMatcherSelectsColocatedProviderDuplicateAndKeepsAlternatives() {
        let first = placeImportCandidate(
            name: "Griffith Observatory",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.118105,
            longitude: -118.300376
        )
        let duplicate = placeImportCandidate(
            name: "Griffith Observatory",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.118099,
            longitude: -118.300400
        )

        let match = PlaceImportCandidateMatcher.match(
            [first, duplicate],
            nameHint: "Griffith Observatory",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )

        XCTAssertEqual(match.selectedCandidateID, first.id)
        XCTAssertEqual(match.candidates.map(\.id), [first.id, duplicate.id])
    }

    func testSocialCandidateMatcherSelectsGroundedFeatureCoreAndKeepsAlternatives() {
        let losAngeles = placeImportCandidate(
            name: "Paseo del Mar",
            locality: "Los Angeles",
            region: "CA",
            latitude: 33.706426,
            longitude: -118.289488
        )
        let palosVerdes = placeImportCandidate(
            name: "Paseo del Mar",
            locality: "Palos Verdes Estates",
            region: "CA",
            latitude: 33.778918,
            longitude: -118.422794
        )
        let unrelatedStreet = placeImportCandidate(
            name: "Puerto del Mar St",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.039837,
            longitude: -118.538601
        )

        let socialMatch = PlaceImportCandidateMatcher.match(
            [palosVerdes, unrelatedStreet, losAngeles],
            nameHint: "Paseo del Mar Bluffs",
            areaHint: "Los Angeles, California",
            selectionPolicy: .socialGroundedArea
        )
        let manualMatch = PlaceImportCandidateMatcher.match(
            [palosVerdes, unrelatedStreet, losAngeles],
            nameHint: "Paseo del Mar Bluffs",
            areaHint: "Los Angeles, California"
        )

        XCTAssertEqual(socialMatch.selectedCandidateID, losAngeles.id)
        XCTAssertEqual(socialMatch.candidates.first?.id, losAngeles.id)
        XCTAssertEqual(socialMatch.candidates.count, 3)
        XCTAssertNil(manualMatch.selectedCandidateID)
    }

    func testGroundedSocialDefaultDoesNotChangeConservativeManualMatching() {
        let expected = placeImportCandidate(
            name: "Summit Archive",
            locality: "Los Angeles",
            region: "CA",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let sameStateAlternative = placeImportCandidate(
            name: "Summit Archive",
            locality: "Pasadena",
            region: "CA",
            latitude: 34.1478,
            longitude: -118.1445
        )

        let match = PlaceImportCandidateMatcher.match(
            [sameStateAlternative, expected],
            nameHint: "Summit Archive",
            areaHint: "Los Angeles, California"
        )

        XCTAssertNil(match.selectedCandidateID)
        XCTAssertEqual(match.candidates.first?.id, expected.id)
    }

    func testStateAreaHintUsesMapRegionWithoutPollutingSearchText() {
        let plan = ManualPlaceSearchPlan(
            name: "Farson Mercantile",
            areaHint: "Wyoming"
        )

        XCTAssertEqual(plan.query, "Farson Mercantile")
    }

    func testFeatureSuffixSearchAddsDistinctiveCoreFallbackWithoutBroadOneWordQuery() {
        let recoverable = ManualPlaceSearchPlan(
            name: "Paseo del Mar Bluffs",
            areaHint: "Los Angeles, California"
        )
        let tooBroad = ManualPlaceSearchPlan(
            name: "Sunset Peak",
            areaHint: "Los Angeles, California"
        )
        let prefixedLandmark = ManualPlaceSearchPlan(
            name: "Mount Wilson",
            areaHint: "Los Angeles, California"
        )
        let ordinaryBusiness = ManualPlaceSearchPlan(
            name: "Starbucks",
            areaHint: "Los Angeles, California"
        )

        XCTAssertEqual(recoverable.queries, [
            "Paseo del Mar Bluffs Los Angeles",
            "Paseo del Mar Bluffs",
            "Paseo del Mar Los Angeles",
            "Paseo del Mar"
        ])
        XCTAssertEqual(tooBroad.queries, [
            "Sunset Peak Los Angeles",
            "Sunset Peak"
        ])
        XCTAssertEqual(prefixedLandmark.queries, [
            "Mount Wilson Los Angeles",
            "Mount Wilson"
        ])
        XCTAssertEqual(ordinaryBusiness.queries, [
            "Starbucks Los Angeles"
        ])
    }

    func testStateRegionSearchKeepsCityInQuery() {
        let jackson = ManualPlaceSearchPlan(
            name: "Starbucks",
            areaHint: "Jackson, Wyoming"
        )
        let kansasCity = ManualPlaceSearchPlan(
            name: "Cafe Gratitude",
            areaHint: "Kansas City, MO"
        )
        let washington = ManualPlaceSearchPlan(
            name: "Compass Coffee",
            areaHint: "Washington, D.C."
        )
        let portland = ManualPlaceSearchPlan(
            name: "Proud Mary Coffee",
            areaHint: "NE Portland, OR"
        )

        XCTAssertEqual(jackson.query, "Starbucks Jackson")
        XCTAssertEqual(kansasCity.query, "Cafe Gratitude Kansas City")
        XCTAssertEqual(washington.query, "Compass Coffee Washington")
        XCTAssertEqual(portland.query, "Proud Mary Coffee NE Portland")
        XCTAssertNotNil(jackson.regionHint)
        XCTAssertNotNil(kansasCity.regionHint)
        XCTAssertNotNil(washington.regionHint)
        XCTAssertNotNil(portland.regionHint)
    }

    func testCandidateMatcherDoesNotApplyOneCharacterOCRCorrectionByDefault() {
        let candidate = placeImportCandidate(name: "Hotel Juno")

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Hotel June",
            areaHint: nil
        )

        XCTAssertNil(match.selectedCandidateID)
    }

    func testCandidateMatcherUsesAddressAndCoordinatesToChooseAChainBranch() {
        let expected = placeImportCandidate(
            name: "Corner Bakery Cafe",
            address: "5312 Clark Ave, Lakewood, CA",
            latitude: 33.8517,
            longitude: -118.1338
        )
        let otherBranch = placeImportCandidate(
            name: "Corner Bakery Cafe",
            address: "1000 Main St, Los Angeles, CA",
            latitude: 34.0522,
            longitude: -118.2437
        )

        let match = PlaceImportCandidateMatcher.match(
            [otherBranch, expected],
            nameHint: "Corner Bakery Cafe",
            areaHint: "5312 Clark Ave, Lakewood, CA",
            latitude: 33.8517,
            longitude: -118.1338
        )

        XCTAssertEqual(match.selectedCandidateID, expected.id)
        XCTAssertEqual(match.candidates.first?.id, expected.id)
    }

    func testCandidateMatcherLeavesSameNameBranchesAmbiguousWithoutLocationEvidence() {
        let first = placeImportCandidate(
            name: "Mendocino Farms",
            address: "Branch One",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let second = placeImportCandidate(
            name: "Mendocino Farms",
            address: "Branch Two",
            latitude: 34.02,
            longitude: -118.49
        )

        let match = PlaceImportCandidateMatcher.match(
            [first, second],
            nameHint: "Mendocino Farms Restaurant",
            areaHint: nil
        )

        XCTAssertNil(match.selectedCandidateID)
    }

    func testTikTokProviderReadsCaptionAndCoverFromPublicOEmbed() async throws {
        let response = """
        {
          "title": "Lunch at @mendocinofarms in Los Angeles",
          "author_name": "LA Food Guide",
          "thumbnail_url": "https://p16-sign.tiktokcdn.com/tiktok-cover.jpg"
        }
        """
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data(response.utf8),
                finalURL: URL(string: "https://www.tiktok.com/oembed")!,
                statusCode: 200,
                mimeType: "application/json"
            )
        ])
        let provider = PublicSocialImportMetadataProvider(httpClient: client)

        let metadata = await provider.metadata(
            for: URL(string: "https://www.tiktok.com/@creator/video/123")!,
            source: .tiktok
        )

        XCTAssertEqual(metadata?.caption, "Lunch at @mendocinofarms in Los Angeles")
        XCTAssertEqual(metadata?.authorName, "LA Food Guide")
        XCTAssertEqual(
            metadata?.thumbnailURL,
            URL(string: "https://p16-sign.tiktokcdn.com/tiktok-cover.jpg")
        )
        XCTAssertEqual(client.requests.first?.url?.host, "www.tiktok.com")
        XCTAssertEqual(client.requests.first?.url?.path, "/oembed")
    }

    func testInstagramProviderReadsCaptionAndCoverFromPublicPageMetadata() async throws {
        let html = """
        <meta property="og:title" content="LA Food Guide on Instagram">
        <meta property="og:description" content="Dinner at Mendocino Farms restaurant">
        <meta property="og:image" content="https://scontent-lax3-1.cdninstagram.com/instagram-cover.jpg">
        """
        let reelURL = URL(string: "https://www.instagram.com/reel/example/")!
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data(html.utf8),
                finalURL: reelURL,
                statusCode: 200,
                mimeType: "text/html"
            )
        ])
        let provider = PublicSocialImportMetadataProvider(httpClient: client)

        let metadata = await provider.metadata(for: reelURL, source: .instagram)

        XCTAssertEqual(metadata?.caption, "Dinner at Mendocino Farms restaurant")
        XCTAssertEqual(metadata?.authorName, "LA Food Guide")
        XCTAssertEqual(
            metadata?.thumbnailURL,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/instagram-cover.jpg")
        )
    }

    func testInstagramProviderPrefersExactEmbeddedCarouselOverOpenGraphCaption() async throws {
        let post: [String: Any] = [
            "code": "POST123",
            "caption": ["text": "Stop at North Lake"],
            "carousel_media": [
                [
                    "accessibility_caption": "North Lake slide",
                    "display_uri": "https://scontent-lax3-1.cdninstagram.com/1.jpg"
                ],
                [
                    "accessibility_caption": "Pine Cafe slide",
                    "display_uri": "https://scontent-lax3-1.cdninstagram.com/2.jpg"
                ]
            ]
        ]
        let json = try JSONSerialization.data(withJSONObject: ["nested": post])
        let body = try XCTUnwrap(String(data: json, encoding: .utf8))
        let html = """
        <meta property="og:title" content="Creator on Instagram">
        <meta property="og:description" content="Generic fallback caption">
        <meta property="og:image" content="https://scontent-lax3-1.cdninstagram.com/fallback-cover.jpg">
        <script data-sjs type="application/json">\(body)</script>
        """
        let postURL = URL(string: "https://www.instagram.com/p/POST123/")!
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data(html.utf8),
                finalURL: postURL,
                statusCode: 200,
                mimeType: "text/html"
            )
        ])
        let provider = PublicSocialImportMetadataProvider(httpClient: client)

        let metadata = await provider.metadata(for: postURL, source: .instagram)

        XCTAssertEqual(metadata?.caption, "Stop at North Lake")
        XCTAssertEqual(metadata?.mediaItems.count, 2)
        XCTAssertEqual(
            metadata?.mediaItems.map(\.imageURL),
            [
                URL(string: "https://scontent-lax3-1.cdninstagram.com/1.jpg"),
                URL(string: "https://scontent-lax3-1.cdninstagram.com/2.jpg")
            ]
        )
        XCTAssertEqual(
            metadata?.thumbnailURL,
            URL(string: "https://scontent-lax3-1.cdninstagram.com/fallback-cover.jpg")
        )
    }

    func testInstagramProviderRejectsNonInstagramSourceBeforeFetching() async {
        let client = FakePlaceImportHTTPClient(responses: [])
        let provider = PublicSocialImportMetadataProvider(httpClient: client)

        let metadata = await provider.metadata(
            for: URL(string: "https://attacker.example/p/POST123/")!,
            source: .instagram
        )

        XCTAssertNil(metadata)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testInstagramProviderRejectsRedirectAwayFromInstagram() async {
        let sourceURL = URL(string: "https://www.instagram.com/p/POST123/")!
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data("<meta property='og:title' content='Wrong host'>".utf8),
                finalURL: URL(string: "https://attacker.example/p/POST123/")!,
                statusCode: 200,
                mimeType: "text/html"
            )
        ])
        let provider = PublicSocialImportMetadataProvider(httpClient: client)

        let metadata = await provider.metadata(for: sourceURL, source: .instagram)

        XCTAssertNil(metadata)
        XCTAssertEqual(client.requests.count, 1)
    }

    func testThumbnailRecognizerRejectsRedirectAwayFromTrustedMediaFamily() async {
        let sourceURL = URL(string: "https://scontent-lax3-1.cdninstagram.com/image.jpg")!
        let client = FakePlaceImportHTTPClient(responses: [
            PlaceImportHTTPResponse(
                data: Data([0, 1, 2]),
                finalURL: URL(string: "https://attacker.example/image.jpg")!,
                statusCode: 200,
                mimeType: "image/jpeg"
            )
        ])
        let recognizer = VisionSocialThumbnailTextRecognizer(httpClient: client)

        let text = await recognizer.recognizedText(at: sourceURL)

        XCTAssertNil(text)
        XCTAssertEqual(client.requests.count, 1)
    }
}

private final class InMemoryPlaceImportPersistence: PlaceImportPersisting {
    var snapshot: PlaceImportSnapshot
    private(set) var saveCount = 0

    init(snapshot: PlaceImportSnapshot = PlaceImportSnapshot()) {
        self.snapshot = snapshot
    }

    func load() throws -> PlaceImportSnapshot {
        snapshot
    }

    func save(_ snapshot: PlaceImportSnapshot) throws {
        self.snapshot = snapshot
        saveCount += 1
    }
}

@MainActor
private func waitForPersistedItemCount(
    _ expectedCount: Int,
    persistence: InMemoryPlaceImportPersistence
) async -> Bool {
    for _ in 0..<1_000 {
        if persistence.snapshot.items.count == expectedCount {
            return true
        }
        await Task.yield()
    }
    return false
}

@MainActor
private final class FakePlaceImportHTTPClient: PlaceImportHTTPFetching {
    private var responses: [PlaceImportHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [PlaceImportHTTPResponse]) {
        self.responses = responses
    }

    func response(for request: URLRequest) async throws -> PlaceImportHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

@MainActor
private final class FakePlaceImportResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        switch seed.nameHint {
        case "Ambiguous":
            return .candidates(
                [candidate(name: "Ambiguous One"), candidate(name: "Ambiguous Two")],
                selectedCandidateID: nil
            )
        case "Needs Help":
            return .needsHelp("Add a nearby city to match this place.")
        default:
            let result = candidate(name: seed.nameHint ?? "Resolved Place")
            return .candidates([result], selectedCandidateID: result.id)
        }
    }

    private func candidate(name: String) -> PlaceCandidate {
        PlaceCandidate(
            id: "candidate-\(name)",
            name: name,
            category: "restaurant",
            locality: "Los Angeles",
            region: "CA",
            country: "United States",
            latitude: 34.0522,
            longitude: -118.2437,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "provider-\(name)",
            confidence: 0.9
        )
    }
}

@MainActor
private final class RecordingPlaceImportResolver: PlaceImportResolving {
    let resolution: PlaceImportResolution
    private(set) var seeds: [PlaceImportSeed] = []
    private(set) var lastSeed: PlaceImportSeed?
    private(set) var lastSource: PlaceImportSource?

    init(resolution: PlaceImportResolution) {
        self.resolution = resolution
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        seeds.append(seed)
        lastSeed = seed
        lastSource = source
        return resolution
    }
}

@MainActor
private final class SequencedPlaceImportResolver: PlaceImportResolving {
    private let resolutions: [PlaceImportResolution]
    private(set) var seeds: [PlaceImportSeed] = []

    init(resolutions: [PlaceImportResolution]) {
        self.resolutions = resolutions
    }

    func resolve(seed: PlaceImportSeed, source _: PlaceImportSource) async throws -> PlaceImportResolution {
        seeds.append(seed)
        return resolutions[min(seeds.count - 1, resolutions.count - 1)]
    }
}

@MainActor
private final class ControllablePlaceImportResolver: PlaceImportResolving {
    private(set) var manualSeeds: [PlaceImportSeed] = []
    private var continuations: [CheckedContinuation<PlaceImportResolution, Never>] = []

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        .needsHelp("Automatic resolution was not expected in this test.")
    }

    func resolveManualSearch(
        seed: PlaceImportSeed,
        source _: PlaceImportSource
    ) async throws -> PlaceImportResolution {
        manualSeeds.append(seed)
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func completeNext(_ resolution: PlaceImportResolution) -> Bool {
        guard !continuations.isEmpty else { return false }
        continuations.removeFirst().resume(returning: resolution)
        return true
    }
}

@MainActor
private final class BackloggedManualSearchResolver: PlaceImportResolving {
    private(set) var automaticSeeds: [PlaceImportSeed] = []
    private(set) var manualSeeds: [PlaceImportSeed] = []
    private var automaticContinuations: [CheckedContinuation<PlaceImportResolution, Never>] = []
    private var manualContinuations: [CheckedContinuation<PlaceImportResolution, Never>] = []

    func resolve(seed: PlaceImportSeed, source _: PlaceImportSource) async throws -> PlaceImportResolution {
        automaticSeeds.append(seed)
        return await withCheckedContinuation { continuation in
            automaticContinuations.append(continuation)
        }
    }

    func resolveManualSearch(
        seed: PlaceImportSeed,
        source _: PlaceImportSource
    ) async throws -> PlaceImportResolution {
        manualSeeds.append(seed)
        return await withCheckedContinuation { continuation in
            manualContinuations.append(continuation)
        }
    }

    func completeAutomatic(_ resolution: PlaceImportResolution) -> Bool {
        guard !automaticContinuations.isEmpty else { return false }
        automaticContinuations.removeFirst().resume(returning: resolution)
        return true
    }

    func completeManual(_ resolution: PlaceImportResolution) -> Bool {
        guard !manualContinuations.isEmpty else { return false }
        manualContinuations.removeFirst().resume(returning: resolution)
        return true
    }

    func waitForAutomaticRequestCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<1_000 {
            if automaticSeeds.count >= expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }

    func waitForManualRequestCount(_ expectedCount: Int) async -> Bool {
        for _ in 0..<1_000 {
            if manualSeeds.count >= expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

@MainActor
private final class ExpandingPlaceImportResolver: PlaceImportResolving {
    private let seeds: [PlaceImportSeed]
    private var hasExpanded = false

    init(seeds: [PlaceImportSeed]) {
        self.seeds = seeds
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        if !hasExpanded {
            hasExpanded = true
            return .expanded(seeds, sourceName: "Ryan's Bakeries")
        }
        let candidate = placeImportCandidate(name: seed.nameHint ?? "Imported Place")
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }
}

@MainActor
private final class ConcurrentGoogleListPlaceImportResolver: PlaceImportResolving {
    private let seeds: [PlaceImportSeed]
    private var didExpand = false
    private var concurrentCount = 0
    private(set) var maximumConcurrentCount = 0

    init(seeds: [PlaceImportSeed]) {
        self.seeds = seeds
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        if !didExpand {
            didExpand = true
            return .expanded(seeds, sourceName: "Concurrent bakeries")
        }

        concurrentCount += 1
        maximumConcurrentCount = max(maximumConcurrentCount, concurrentCount)
        defer { concurrentCount -= 1 }
        try await Task.sleep(for: .milliseconds(20))
        let candidate = placeImportCandidate(name: seed.nameHint ?? "Imported Place")
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }
}

@MainActor
private final class ExpandingThenSuspendingPlaceImportResolver: PlaceImportResolving {
    private let seeds: [PlaceImportSeed]
    private var hasExpanded = false

    init(seeds: [PlaceImportSeed]) {
        self.seeds = seeds
    }

    func resolve(seed: PlaceImportSeed, source _: PlaceImportSource) async throws -> PlaceImportResolution {
        if !hasExpanded {
            hasExpanded = true
            return .expanded(seeds, sourceName: nil)
        }
        try await Task.sleep(for: .seconds(60))
        return .needsHelp("Unexpected completion for \(seed.nameHint ?? "guide row")")
    }
}

@MainActor
private final class SuspendedPlaceImportResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await Task.sleep(for: .seconds(60))
        return .needsHelp("Unexpected completion")
    }
}

@MainActor
private final class CancellationThenSuccessPlaceImportResolver: PlaceImportResolving {
    private var attemptCount = 0

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        attemptCount += 1
        if attemptCount == 1 {
            try await Task.sleep(for: .seconds(60))
        }
        let candidate = placeImportCandidate(name: seed.nameHint ?? "Imported Place")
        return .candidates([candidate], selectedCandidateID: candidate.id)
    }
}

@MainActor
private final class NeedsHelpPlaceImportResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        .needsHelp("Temporary refresh failure")
    }
}

@MainActor
private final class FakeDevicePlaceResolver: PlaceCandidateResolving {
    let candidates: [PlaceCandidate]
    private(set) var manualInputs: [ManualPlaceInput] = []

    init(candidates: [PlaceCandidate]) {
        self.candidates = candidates
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { candidates }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { candidates }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        return candidates
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { candidates }
}

@MainActor
private final class RoutingDevicePlaceResolver: PlaceCandidateResolving {
    let routes: [String: [PlaceCandidate]]
    private(set) var manualInputs: [ManualPlaceInput] = []

    init(routes: [String: [PlaceCandidate]]) {
        self.routes = routes
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        return routes[input.name.lowercased()] ?? []
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { [] }
}

@MainActor
private final class RoutingNoCandidateThrowingDevicePlaceResolver: PlaceCandidateResolving {
    let routes: [String: [PlaceCandidate]]

    init(routes: [String: [PlaceCandidate]]) {
        self.routes = routes
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        guard let candidates = routes[input.name.lowercased()] else {
            throw PlaceResolutionError.noCandidates
        }
        return candidates
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { [] }
}

@MainActor
private final class ThrowingDevicePlaceResolver: PlaceCandidateResolving {
    func resolveCurrentLocation() async throws -> [PlaceCandidate] { throw URLError(.timedOut) }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        throw URLError(.timedOut)
    }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        throw URLError(.timedOut)
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { throw URLError(.timedOut) }
}

@MainActor
private final class PartiallyThrowingDevicePlaceResolver: PlaceCandidateResolving {
    let successfulName: String
    let candidate: PlaceCandidate
    private(set) var manualInputs: [ManualPlaceInput] = []

    init(successfulName: String, candidate: PlaceCandidate) {
        self.successfulName = successfulName
        self.candidate = candidate
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        if input.name == successfulName {
            return [candidate]
        }
        throw URLError(.timedOut)
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { [] }
}

@MainActor
private final class ScriptedDevicePlaceResolver: PlaceCandidateResolving {
    enum ManualResult {
        case candidates([PlaceCandidate])
        case noCandidates
        case failure(URLError.Code)
    }

    private var results: [ManualResult]
    private(set) var manualInputs: [ManualPlaceInput] = []

    init(results: [ManualResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        let result = results.count == 1 ? results[0] : results.removeFirst()
        switch result {
        case .candidates(let candidates):
            return candidates
        case .noCandidates:
            throw PlaceResolutionError.noCandidates
        case .failure(let code):
            throw URLError(code)
        }
    }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { [] }
}

@MainActor
private final class FakeSocialImportUnderstandingRepository: SocialImportUnderstandingRepository {
    struct Request: Equatable {
        let url: URL
        let source: PlaceImportSource
        let clientRequestID: String
    }

    let result: SocialImportUnderstandingResult
    private(set) var requests: [Request] = []

    init(result: SocialImportUnderstandingResult) {
        self.result = result
    }

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        requests.append(
            Request(url: url, source: source, clientRequestID: clientRequestID)
        )
        return result
    }
}

@MainActor
private final class ThrowingSocialImportUnderstandingRepository: SocialImportUnderstandingRepository {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        throw error
    }
}

@MainActor
private final class SequencedSocialImportUnderstandingRepository: SocialImportUnderstandingRepository {
    typealias Request = FakeSocialImportUnderstandingRepository.Request

    private let results: [SocialImportUnderstandingResult]
    private(set) var requests: [Request] = []

    init(results: [SocialImportUnderstandingResult]) {
        precondition(!results.isEmpty)
        self.results = results
    }

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        requests.append(Request(url: url, source: source, clientRequestID: clientRequestID))
        return results[min(requests.count - 1, results.count - 1)]
    }
}

@MainActor
private final class SelfCancellingSocialImportUnderstandingRepository: SocialImportUnderstandingRepository {
    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        withUnsafeCurrentTask { task in
            task?.cancel()
        }
        throw URLError(.cancelled)
    }
}

@MainActor
private final class FakeSocialImportMetadataProvider: SocialImportMetadataProviding {
    let providedMetadata: SocialImportMetadata?

    init(metadata: SocialImportMetadata? = nil) {
        providedMetadata = metadata
    }

    func metadata(for url: URL, source: PlaceImportSource) async -> SocialImportMetadata? {
        providedMetadata
    }
}

@MainActor
private final class FakeSocialThumbnailTextRecognizer: SocialThumbnailTextRecognizing {
    let text: String?
    let textByURL: [URL: String]?
    private(set) var requestedURLs: [URL] = []

    init(text: String? = nil) {
        self.text = text
        textByURL = nil
    }

    init(textByURL: [URL: String]) {
        text = nil
        self.textByURL = textByURL
    }

    func recognizedText(at url: URL) async -> String? {
        requestedURLs.append(url)
        return textByURL?[url] ?? text
    }
}

private func hundredCoffeeGuideRows() -> [(name: String, country: String)] {
    [
        ("ONYX COFFEE LAB", "USA"),
        ("TIM WENDELBOE", "NORWAY"),
        ("ALQUIMIA COFFEE", "EL SALVADOR"),
        ("ONLY COFFEE PROJECT CROWS NEST", "AUSTRALIA"),
        ("TOBY'S ESTATE COFFEE ROASTERS", "AUSTRALIA"),
        ("APARTMENT COFFEE", "SINGAPORE"),
        ("GOTA COFFEE EXPERTS", "AUSTRIA"),
        ("STORY OF ONO", "MALAYSIA"),
        ("TROPICALIA COFFEE", "COLOMBIA"),
        ("TANAT", "FRANCE"),
        ("FANKØR", "ECUADOR"),
        ("ARCANE ESTATE COFFEE", "USA"),
        ("BETA COFFEE", "AUSTRALIA"),
        ("NOMADIC SPECIALTY COFFEE", "EGYPT"),
        ("NEMESIS COFFEE", "CANADA"),
        ("NOMAD FRUTAS SELECTAS", "SPAIN"),
        ("KAFI WASI CAFÉ TOSTADURÍA", "PERU"),
        ("BENCHMARK COFFEE", "UAE"),
        ("HOLA LAGASCA", "SPAIN"),
        ("BLENDIN COFFEE CLUB", "USA"),
        ("HOLASTE! SPECIALTY COFFEE", "CHILE"),
        ("MOMOS COFFEE FLAGSHIP STORE", "REPUBLIC OF KOREA"),
        ("MONOTONO SPECIALTY COFFEE", "PERU"),
        ("ULT COFFEE", "JAPAN"),
        ("EL INJERTO", "GUATEMALA"),
        ("THREE MONKEYS COFFEE", "PERU"),
        ("PROUD MARY COFFEE", "AUSTRALIA"),
        ("KOFFEE MAMEYA KAKERU", "JAPAN"),
        ("COFFEE ANTHOLOGY", "AUSTRALIA"),
        ("7G ROASTER", "PORTUGAL"),
        ("ESPRESSO ALCHEMY", "CHINA"),
        ("COFFEEWERK + PRESS", "IRELAND"),
        ("TYPICA CAFÉ", "BOLIVIA"),
        ("YARDSTICK", "THE PHILIPPINES"),
        ("HISTÓRICO", "MEXICO"),
        ("COFFEE SIND", "TAIWAN"),
        ("DELAFINCA SPECIALTY COFFEE", "NICARAGUA"),
        ("OTTOMAN COFFEE HOUSE", "UNITED KINGDOM"),
        ("CASA CANELA", "VENEZUELA"),
        ("ESPRESSO LAB", "SOUTH AFRICA"),
        ("SEVEN MYSTERY", "CANADA"),
        ("FARO", "ITALY"),
        ("DOMESTIQUE", "USA"),
        ("HARVEST COFFEE", "QATAR"),
        ("ORIGEN TOSTADORES DE CAFÉ", "PERU"),
        ("KEEP COFFEE ROASTERY", "TAIWAN"),
        ("MEET LAB COFFEE", "TURKEY"),
        ("MULANO COFFEE SHOP", "ECUADOR"),
        ("LA CABRA", "DENMARK"),
        ("BIRCH COFFEE", "UNITED KINGDOM"),
        ("RULI COFFEE", "REPUBLIC OF KOREA"),
        ("ATTE FOR COFFEE", "GUATEMALA"),
        ("SINGLE O", "AUSTRALIA"),
        ("RUBIA COFFEE ROASTERS", "RWANDA"),
        ("BOB COFFEE LAB", "ROMANIA"),
        ("UNFILTERED COFFEE", "IRELAND"),
        ("TOMORROW COFFEE ROASTERS", "TAIWAN"),
        ("CA PASSE CREME", "SWITZERLAND"),
        ("ECO MAPU", "CHILE"),
        ("43.12 COFFEE", "BULGARIA"),
        ("FIKA & CO. CAFE", "THAILAND"),
        ("DITTA ARTIGIANALE SPECIALTY COFFEE ROASTERS", "ITALY"),
        ("CAFÉ NATIVO", "HONDURAS"),
        ("CAFERATTO", "COLOMBIA"),
        ("KROSS COFFEE ROASTERS", "GREECE"),
        ("PREVAIL COFFEE", "USA"),
        ("MOK COFFEE", "BELGIUM"),
        ("AZURA - THE COFFEE COMPANY", "OMAN"),
        ("PUKU PUKU", "PERU"),
        ("THE GOLDEN PIG", "HONDURAS"),
        ("LITTLE VICTORIES COFFEE", "CANADA"),
        ("PUSH X PULL", "USA"),
        ("GALANI COFFEE", "ETHIOPIA"),
        ("WAKE UP", "CHILE"),
        ("BOUCHE", "BELGIUM"),
        ("CAFÉ DE REYES", "GUATEMALA"),
        ("SAVAYA COFFEE MARKET", "USA"),
        ("COFFEE STOPOVER BLACK", "TAIWAN"),
        ("FUKU", "NETHERLANDS"),
        ("THE MINERS COFFEE", "CZECH REPUBLIC"),
        ("CUPPING CAFÉ", "BRAZIL"),
        ("COFFEA GUATEMALA", "GUATEMALA"),
        ("D·ORIGEN COFFEE ROASTERS BARCELONA", "SPAIN"),
        ("COFFEE STAIN", "MALAYSIA"),
        ("THE DUDE SPECIALTY COFFEE", "NORTH MACEDONIA"),
        ("STORY AND SOIL COFFEE", "USA"),
        ("EXPLORADORES", "MEXICO"),
        ("THE FOLKS", "PORTUGAL"),
        ("CASA BARISTA & CO., CASCO HISTORICO", "DOMINICAN REPUBLIC"),
        ("CYPHER URBAN ROASTERY", "UAE"),
        ("CAFETANO", "HONDURAS"),
        ("COFFEE FIVE", "BRAZIL"),
        ("KIMA COFFEE", "SPAIN"),
        ("NEGRO", "ARGENTINA"),
        ("METRIC", "USA"),
        ("EL TERRIBLE JUAN CAFÉ", "MEXICO"),
        ("FLAT WHITE SPECIALTY COFFEE", "QATAR"),
        ("CAFEOTECA", "COSTA RICA"),
        ("SURRY HILLS PALERMO", "ARGENTINA"),
        ("VACATION COFFEE", "AUSTRALIA")
    ]
}

private func hundredCoffeeGuideObservationColumns() throws -> [[SocialTextObservation]] {
    let bundle = Bundle(for: SocialPlaceImportMetadataTests.self)
    let url = try XCTUnwrap(
        bundle.url(forResource: "rec-106-guide-observations", withExtension: "tsv")
            ?? bundle.url(
                forResource: "rec-106-guide-observations",
                withExtension: "tsv",
                subdirectory: "Fixtures"
            )
    )
    var observationsByColumn: [String: [SocialTextObservation]] = [:]
    let contents = try String(contentsOf: url, encoding: .utf8)
    for line in contents.split(separator: "\n") where !line.hasPrefix("#") {
        let fields = line.split(separator: "|", maxSplits: 6, omittingEmptySubsequences: false)
        guard fields.count == 7,
              let x = Double(fields[2]),
              let y = Double(fields[3]),
              let width = Double(fields[4]),
              let height = Double(fields[5])
        else {
            throw NSError(
                domain: "SocialPlaceImportMetadataTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid captured Vision observation: \(line)"]
            )
        }
        let key = "\(fields[0])-\(fields[1])"
        observationsByColumn[key, default: []].append(
            SocialTextObservation(
                text: String(fields[6]),
                boundingBox: CGRect(x: x, y: y, width: width, height: height)
            )
        )
    }
    return try ["1-0", "1-1", "2-0", "2-1"].map { key in
        try XCTUnwrap(observationsByColumn[key], "Missing captured Vision column \(key)")
    }
}

private func normalizedCoffeeGuideValue(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .filter { $0.isLetter || $0.isNumber }
}

private func googleSharedListPayload(count: Int) throws -> Data {
    var entries: [Any] = []
    for index in 1...count {
        var coordinates = Array<Any>(repeating: NSNull(), count: 4)
        coordinates[2] = 34.0 + Double(index) / 10_000
        coordinates[3] = -118.0 - Double(index) / 10_000

        var placeInfo = Array<Any>(repeating: NSNull(), count: 8)
        placeInfo[4] = "\(index) Main St, Los Angeles, CA"
        placeInfo[5] = coordinates
        placeInfo[7] = "google-place-\(index)"

        var entry = Array<Any>(repeating: NSNull(), count: 4)
        entry[1] = placeInfo
        entry[2] = "Bakery \(index)"
        entry[3] = "Imported bakery \(index)"
        entries.append(entry)
    }

    var root = Array<Any>(repeating: NSNull(), count: 9)
    root[4] = "Ryan's Bakeries"
    root[8] = entries
    let json = try JSONSerialization.data(withJSONObject: [root])
    var payload = Data(")]}'\n".utf8)
    payload.append(json)
    return payload
}

private func socialUnderstandingResult(
    hint: SocialPlaceSearchHint
) -> SocialImportUnderstandingResult {
    SocialImportUnderstandingResult(
        outcome: .ok,
        hints: [hint],
        diagnostics: SocialImportUnderstandingDiagnostics(
            providerPath: "apify_gemini",
            mediaCount: 1,
            modelAttemptCount: 1,
            failureCategory: nil
        )
    )
}

private func placeImportCandidate(
    name: String,
    address: String? = nil,
    locality: String = "Los Angeles",
    region: String = "CA",
    country: String = "United States",
    latitude: Double = 34.0522,
    longitude: Double = -118.2437
) -> PlaceCandidate {
    PlaceCandidate(
        id: "candidate-\(name)-\(latitude)-\(longitude)",
        name: name,
        category: "restaurant",
        address: address,
        locality: locality,
        region: region,
        country: country,
        latitude: latitude,
        longitude: longitude,
        sourceProvider: "mapkit",
        sourceProviderPlaceID: "provider-\(name)",
        confidence: 0.9
    )
}
