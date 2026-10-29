import CoreLocation
import XCTest
@testable import Wander

final class PhotoPlaceTextExtractorTests: XCTestCase {
    func testPrefersPlaceLikeLineOverReceiptNoise() {
        let query = PhotoPlaceTextExtractor.searchQuery(
            from: """
            Receipt
            ORDER 1042
            Lake Shrine
            Total $12.44
            """
        )

        XCTAssertEqual(query, "Lake Shrine")
    }

    func testBuildsRankedQueriesWithNearbyAddressContext() {
        let queries = PhotoPlaceTextExtractor.searchQueries(
            from: """
            Photos
            Directions
            Heavy Handed
            2912 Main St
            Santa Monica, CA
            4.6 (321)
            Open now
            """
        )

        XCTAssertEqual(queries.first, "Heavy Handed")
        XCTAssertTrue(queries.contains("Heavy Handed 2912 Main St"))
        XCTAssertFalse(queries.contains("Directions"))
        XCTAssertFalse(queries.contains("4.6 (321)"))
    }

    func testTriesMoreThanOneLikelyPlaceLine() {
        let queries = PhotoPlaceTextExtractor.searchQueries(
            from: """
            Apple Maps
            Search
            Top result
            Botanica Restaurant
            El Matador State Beach
            Malibu, CA
            Share
            """
        )

        XCTAssertTrue(queries.contains("Botanica Restaurant"))
        XCTAssertTrue(queries.contains("El Matador State Beach"))
        XCTAssertTrue(queries.contains("El Matador State Beach Malibu, CA"))
        XCTAssertFalse(queries.contains("Search"))
        XCTAssertFalse(queries.contains("Share"))
    }

    func testRejectsPureReceiptLines() {
        let query = PhotoPlaceTextExtractor.searchQuery(
            from: """
            Receipt
            Total $12.44
            VISA 4242
            """
        )

        XCTAssertNil(query)
    }
}

@MainActor
final class PhotoPlaceImportResolverTests: XCTestCase {
    func testOCRCandidateResolutionShowsConfirmableCandidates() async {
        let heavyHanded = photoPlaceCandidate(name: "Heavy Handed")
        let searcher = FakePhotoPlaceCandidateSearcher(
            textResults: ["Heavy Handed": [heavyHanded]]
        )

        let resolution = await PhotoPlaceImportResolver.resolve(
            recognizedText: """
            Photos
            Directions
            Heavy Handed
            2912 Main St
            Santa Monica, CA
            """,
            photoCoordinate: nil,
            searcher: searcher
        )

        XCTAssertEqual(resolution.outcome, .candidates)
        XCTAssertEqual(resolution.source, .recognizedText)
        XCTAssertEqual(resolution.candidates, [heavyHanded])
        XCTAssertEqual(resolution.manualName, "Heavy Handed")
        XCTAssertEqual(searcher.textQueries.first, "Heavy Handed")
        XCTAssertTrue(searcher.nearbyCoordinates.isEmpty)
    }

    func testPhotoCoordinateResolutionShowsNearbyCandidatesWhenTextMisses() async {
        let nearbyCafe = photoPlaceCandidate(name: "Jade Rabbit", distanceMeters: 24)
        let coordinate = CLLocationCoordinate2D(latitude: 34.0159, longitude: -118.4973)
        let searcher = FakePhotoPlaceCandidateSearcher(nearbyResults: [nearbyCafe])

        let resolution = await PhotoPlaceImportResolver.resolve(
            recognizedText: nil,
            photoCoordinate: coordinate,
            searcher: searcher
        )

        XCTAssertEqual(resolution.outcome, .candidates)
        XCTAssertEqual(resolution.source, .photoLocation)
        XCTAssertEqual(resolution.candidates, [nearbyCafe])
        XCTAssertEqual(resolution.manualName, "Jade Rabbit")
        XCTAssertEqual(searcher.nearbyCoordinates.count, 1)
    }

    func testRecognizedTextWithoutCandidatesRoutesToEditableManualRescue() async {
        let searcher = FakePhotoPlaceCandidateSearcher()

        let resolution = await PhotoPlaceImportResolver.resolve(
            recognizedText: """
            Chamberlain Coffee
            1418 4th St
            Santa Monica, CA
            """,
            photoCoordinate: nil,
            searcher: searcher
        )

        XCTAssertEqual(resolution.outcome, .manualRescue)
        XCTAssertEqual(resolution.source, .recognizedText)
        XCTAssertEqual(resolution.manualName, "Chamberlain Coffee")
        XCTAssertEqual(resolution.candidates, [])
        XCTAssertEqual(
            resolution.message,
            "Read \"Chamberlain Coffee\" from the photo. Confirm or edit it, then tap find this place."
        )
    }

    func testDraftIsOnlyUsedWhenPhotoHasNoUsableSignal() async {
        let searcher = FakePhotoPlaceCandidateSearcher()

        let resolution = await PhotoPlaceImportResolver.resolve(
            recognizedText: nil,
            photoCoordinate: nil,
            searcher: searcher
        )

        XCTAssertEqual(resolution.outcome, .draft)
        XCTAssertEqual(resolution.source, .none)
        XCTAssertEqual(resolution.candidates, [])
        XCTAssertNil(resolution.manualName)
        XCTAssertEqual(
            resolution.message,
            "We could not read a place from that photo yet. Add it manually if you want it on your map now."
        )
    }
}

@MainActor
private final class FakePhotoPlaceCandidateSearcher: PhotoPlaceCandidateSearching {
    private let textResults: [String: [PlaceCandidate]]
    private let nearbyResults: [PlaceCandidate]
    private(set) var textQueries: [String] = []
    private(set) var nearbyCoordinates: [CLLocationCoordinate2D] = []

    init(
        textResults: [String: [PlaceCandidate]] = [:],
        nearbyResults: [PlaceCandidate] = []
    ) {
        self.textResults = textResults
        self.nearbyResults = nearbyResults
    }

    func photoTextCandidates(for query: String) async throws -> [PlaceCandidate] {
        textQueries.append(query)
        guard let candidates = textResults[query], !candidates.isEmpty else {
            throw PlaceResolutionError.noCandidates
        }
        return candidates
    }

    func photoLocationCandidates(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        nearbyCoordinates.append(coordinate)
        guard !nearbyResults.isEmpty else {
            throw PlaceResolutionError.noCandidates
        }
        return nearbyResults
    }
}

private func photoPlaceCandidate(
    name: String,
    category: String = "coffee",
    distanceMeters: Double? = nil
) -> PlaceCandidate {
    PlaceCandidate(
        id: "mapkit_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))",
        name: name,
        category: category,
        address: "1418 4th St",
        locality: "Santa Monica",
        region: "CA",
        country: "US",
        latitude: 34.0159,
        longitude: -118.4973,
        distanceMeters: distanceMeters,
        confidence: 0.92
    )
}
