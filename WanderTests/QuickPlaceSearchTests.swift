import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class QuickPlaceSearchTests: XCTestCase {
    func testTextLookupUsesQuickSearchResolverAndPreservesProviderOrder() async throws {
        let resolver = QuickSearchResolver()
        let expected = [candidate("second"), candidate("first")]
        resolver.results = expected
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)

        let results = try await store.quickSearchCandidates(for: "  Coffee in Venice\n")

        XCTAssertEqual(results, expected)
        XCTAssertEqual(resolver.manualInputs.map(\.name), ["Coffee in Venice"])
        XCTAssertNil(resolver.manualInputs.first?.areaHint)
        XCTAssertNil(resolver.manualInputs.first?.category)
        XCTAssertTrue(resolver.coordinates.isEmpty)
    }

    func testCoordinatesUseSameNearbyLookupAsQuickSearch() async throws {
        let resolver = QuickSearchResolver()
        resolver.results = [candidate("nearby")]
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)

        for query in ["34.0522, -118.2437", " 34.0522 N, 118.2437 W "] {
            let results = try await store.quickSearchCandidates(for: query)
            XCTAssertEqual(results, resolver.results)
        }

        XCTAssertTrue(resolver.manualInputs.isEmpty)
        XCTAssertEqual(resolver.coordinates.count, 2)
        for coordinate in resolver.coordinates {
            XCTAssertEqual(coordinate.latitude, 34.0522, accuracy: 0.0001)
            XCTAssertEqual(coordinate.longitude, -118.2437, accuracy: 0.0001)
        }
    }

    func testBlankQueryDoesNotCallProvider() async throws {
        let resolver = QuickSearchResolver()
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)
        let results = try await store.quickSearchCandidates(for: " \n ")
        XCTAssertTrue(results.isEmpty)
        XCTAssertTrue(resolver.manualInputs.isEmpty)
        XCTAssertTrue(resolver.coordinates.isEmpty)
    }

    func testOlderCompletionCannotReplaceNewQueryResults() async {
        let model = ListPlaceSearchModel()
        let oldStarted = expectation(description: "old request started")
        var oldResponse: CheckedContinuation<[PlaceCandidate], Never>?
        let oldTask = Task {
            await model.search("old", debounce: .zero) { _ in
                await withCheckedContinuation { continuation in
                    oldResponse = continuation
                    oldStarted.fulfill()
                }
            }
        }
        await fulfillment(of: [oldStarted], timeout: 2)
        await model.search("new", debounce: .zero) { _ in [self.candidate("new")] }
        oldResponse?.resume(returning: [candidate("old")])
        await oldTask.value

        XCTAssertEqual(model.candidates.map(\.id), ["new"])
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.errorMessage)
    }

    func testOlderFailureDoesNotEndNewQueriesLoadingState() async {
        let model = ListPlaceSearchModel()
        let oldStarted = expectation(description: "old request started")
        let newStarted = expectation(description: "new request started")
        var oldResponse: CheckedContinuation<[PlaceCandidate], Error>?
        var newResponse: CheckedContinuation<[PlaceCandidate], Never>?
        let oldTask = Task {
            await model.search("old", debounce: .zero) { _ in
                try await withCheckedThrowingContinuation { continuation in
                    oldResponse = continuation
                    oldStarted.fulfill()
                }
            }
        }
        await fulfillment(of: [oldStarted], timeout: 2)
        let newTask = Task {
            await model.search("new", debounce: .zero) { _ in
                await withCheckedContinuation { continuation in
                    newResponse = continuation
                    newStarted.fulfill()
                }
            }
        }
        await fulfillment(of: [newStarted], timeout: 2)
        oldResponse?.resume(throwing: URLError(.notConnectedToInternet))
        await oldTask.value
        XCTAssertTrue(model.isSearching)
        XCTAssertNil(model.errorMessage)
        newResponse?.resume(returning: [candidate("new")])
        await newTask.value
        XCTAssertEqual(model.candidates.map(\.id), ["new"])
    }

    func testClearingQueryDiscardsPendingResults() async {
        let model = ListPlaceSearchModel()
        let started = expectation(description: "request started")
        var response: CheckedContinuation<[PlaceCandidate], Never>?
        let task = Task {
            await model.search("coffee", debounce: .zero) { _ in
                await withCheckedContinuation { continuation in
                    response = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        await model.search(" \n ") { _ in
            XCTFail("Blank queries must not reach the resolver")
            return []
        }
        response?.resume(returning: [candidate("old")])
        await task.value
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledProviderCompletionDoesNotPublishResults() async {
        let model = ListPlaceSearchModel()
        let started = expectation(description: "request started")
        var response: CheckedContinuation<[PlaceCandidate], Never>?
        let task = Task {
            await model.search("coffee", debounce: .zero) { _ in
                await withCheckedContinuation { continuation in
                    response = continuation
                    started.fulfill()
                }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        response?.resume(returning: [candidate("cancelled")])
        await task.value
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledDebounceDoesNotCallProvider() async {
        let model = ListPlaceSearchModel()
        let task = Task {
            await model.search("co", debounce: .seconds(60)) { _ in
                XCTFail("Cancelled typing must not call the provider")
                return []
            }
        }
        task.cancel()
        await task.value
        XCTAssertFalse(model.isSearching)
        XCTAssertTrue(model.candidates.isEmpty)
    }

    func testProviderFailureIsRetryableAndNoMatchesAreNotNetworkErrors() async {
        let model = ListPlaceSearchModel()
        await model.search("coffee", debounce: .zero) { _ in
            throw URLError(.notConnectedToInternet)
        }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)

        await model.search("coffee", debounce: .zero) { _ in [self.candidate("retry")] }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.candidates.map(\.id), ["retry"])

        await model.search("missing", debounce: .zero) { _ in throw PlaceResolutionError.noCandidates }
        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
    }

    private func candidate(_ id: String) -> PlaceCandidate {
        PlaceCandidate(id: id, name: id, category: "cafe", latitude: 34, longitude: -118, confidence: 0.9)
    }
}

@MainActor
private final class QuickSearchResolver: PlaceCandidateResolving {
    var results: [PlaceCandidate] = []
    var manualInputs: [ManualPlaceInput] = []
    var coordinates: [CLLocationCoordinate2D] = []

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        return results
    }
    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        coordinates.append(coordinate)
        return results
    }
}
