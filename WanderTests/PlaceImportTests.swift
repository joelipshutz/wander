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

        XCTAssertEqual(resolution, .candidates([wrongCandidate], selectedCandidateID: nil))
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
private final class SuspendedPlaceImportResolver: PlaceImportResolving {
    func resolve(seed: PlaceImportSeed, source: PlaceImportSource) async throws -> PlaceImportResolution {
        try await Task.sleep(for: .seconds(60))
        return .needsHelp("Unexpected completion")
    }
}

@MainActor
private final class FakeDevicePlaceResolver: PlaceCandidateResolving {
    let candidates: [PlaceCandidate]

    init(candidates: [PlaceCandidate]) {
        self.candidates = candidates
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { candidates }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] { candidates }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { candidates }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { candidates }
}

@MainActor
private final class FakeSocialImportMetadataProvider: SocialImportMetadataProviding {
    func title(for url: URL, source: PlaceImportSource) async -> String? { nil }
}

private func placeImportCandidate(name: String) -> PlaceCandidate {
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
