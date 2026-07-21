import CoreLocation
import Foundation
import XCTest
@testable import Wander

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

@MainActor
final class PlaceImportStoreTests: XCTestCase {
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
                    "fremont lake": [placeImportCandidate(name: "Fremont Lake")]
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
                    candidate: placeImportCandidate(name: "Fremont Lake")
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

    func testManualSearchPreservesOneWeakMapKitCandidateForReview() async throws {
        let snapshot = try manualSearchFixtureSnapshot()
        let weakCandidate = placeImportCandidate(name: "Farson Ice Cream")
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
        let exactCandidate = placeImportCandidate(name: "Farson Mercantile")
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
            candidate: placeImportCandidate(name: "Fremont Lake")
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
            (name.lowercased(), [placeImportCandidate(name: name)])
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
        return try decoder.decode(PlaceImportSnapshot.self, from: Data(contentsOf: url))
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
}

@MainActor
final class SocialPlaceImportMetadataTests: XCTestCase {
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
            (name.lowercased(), [placeImportCandidate(name: name)])
        })
        let resolver = DevicePlaceImportResolver(
            placeResolver: RoutingDevicePlaceResolver(routes: routes),
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

    func testCandidateMatcherTreatsRestaurantSuffixAsTheSamePlaceName() {
        let candidate = placeImportCandidate(name: "Mendocino Farms")

        let match = PlaceImportCandidateMatcher.match(
            [candidate],
            nameHint: "Mendocino Farms Restaurant",
            areaHint: "Los Angeles"
        )

        XCTAssertEqual(match.selectedCandidateID, candidate.id)
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

    init(snapshot: PlaceImportSnapshot = PlaceImportSnapshot()) {
        self.snapshot = snapshot
    }

    func load() throws -> PlaceImportSnapshot {
        snapshot
    }

    func save(_ snapshot: PlaceImportSnapshot) throws {
        self.snapshot = snapshot
    }
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
    private(set) var lastSeed: PlaceImportSeed?
    private(set) var lastSource: PlaceImportSource?

    init(resolution: PlaceImportResolution) {
        self.resolution = resolution
    }

    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        lastSeed = seed
        lastSource = source
        return resolution
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
private final class SuspendedPlaceImportResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await Task.sleep(for: .seconds(60))
        return .needsHelp("Unexpected completion")
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

    init(routes: [String: [PlaceCandidate]]) {
        self.routes = routes
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        routes[input.name.lowercased()] ?? []
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

private func placeImportCandidate(
    name: String,
    address: String? = nil,
    latitude: Double = 34.0522,
    longitude: Double = -118.2437
) -> PlaceCandidate {
    PlaceCandidate(
        id: "candidate-\(name)-\(latitude)-\(longitude)",
        name: name,
        category: "restaurant",
        address: address,
        locality: "Los Angeles",
        region: "CA",
        country: "United States",
        latitude: latitude,
        longitude: longitude,
        sourceProvider: "mapkit",
        sourceProviderPlaceID: "provider-\(name)",
        confidence: 0.9
    )
}
