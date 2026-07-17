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
}

@MainActor
final class SocialPlaceImportMetadataTests: XCTestCase {
    func testInstagramMetaParserPreservesApostrophesAndReversedAttributeOrder() throws {
        let html = """
        <html><head>
        <meta content="Ryan's lunch at @mendocinofarms &amp; a great patio" property="og:description">
        <meta property="og:title" content="Ryan on Instagram">
        <meta content="https://example.com/cover.jpg" property="og:image">
        </head></html>
        """

        let metadata = try XCTUnwrap(PublicSocialHTMLMetadataParser.metadata(from: html))

        XCTAssertEqual(metadata.caption, "Ryan's lunch at @mendocinofarms & a great patio")
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
          "thumbnail_url": "https://example.com/tiktok-cover.jpg"
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
        XCTAssertEqual(metadata?.thumbnailURL, URL(string: "https://example.com/tiktok-cover.jpg"))
        XCTAssertEqual(client.requests.first?.url?.host, "www.tiktok.com")
        XCTAssertEqual(client.requests.first?.url?.path, "/oembed")
    }

    func testInstagramProviderReadsCaptionAndCoverFromPublicPageMetadata() async throws {
        let html = """
        <meta property="og:title" content="LA Food Guide on Instagram">
        <meta property="og:description" content="Dinner at Mendocino Farms restaurant">
        <meta property="og:image" content="https://example.com/instagram-cover.jpg">
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
        XCTAssertEqual(metadata?.thumbnailURL, URL(string: "https://example.com/instagram-cover.jpg"))
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

    init(text: String? = nil) {
        self.text = text
    }

    func recognizedText(at url: URL) async -> String? {
        text
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
