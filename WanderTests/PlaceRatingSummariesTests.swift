import XCTest
@testable import Wander

final class PlaceRatingSummariesTests: XCTestCase {
    @MainActor
    func testSearchRatingLookupDoesNotRequireAnyVisibleSavedActivity() {
        let candidate = PlaceCandidate(id: "provider-search-result", name: "Coffee", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "mapkit", sourceProviderPlaceID: "coffee-123", confidence: 1)
        let lookup = PlaceRatingLookup(candidate: candidate, knownPlaces: [])
        XCTAssertTrue(lookup.canQuery)
        XCTAssertNil(lookup.placeID)
        XCTAssertEqual(lookup.sourceProvider, "mapkit")
        XCTAssertEqual(lookup.sourceProviderPlaceID, "coffee-123")
    }

    @MainActor
    func testRatingsUseSyncedIdentityAndDoNotTreatLocalUUIDAsServerIdentity() {
        let localID = "11111111-1111-4111-8111-111111111111"
        let serverID = "22222222-2222-4222-8222-222222222222"
        let local = LocalPlace(localID: localID, canonicalName: "Coffee", category: "coffee", latitude: 34, longitude: -118)
        let candidate = PlaceCandidate(id: localID, name: "Coffee", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "mapkit", confidence: 1)
        XCTAssertFalse(PlaceRatingLookup(candidate: candidate, knownPlaces: [local]).canQuery)
        local.serverID = serverID
        XCTAssertEqual(PlaceRatingLookup(candidate: candidate, knownPlaces: [local]).placeID, serverID)
    }

    func testRailAlwaysKeepsYourFriendsAndAstirSlotsWithoutFitOrFakeFive() throws {
        let empty = PlaceRatingsState.loaded(.init(own: .empty, friends: .empty, astir: .empty)).metrics
        XCTAssertEqual(empty.map(\.title), ["Your rating", "Friends rating", "Astir rating"])
        XCTAssertEqual(empty.map { $0.value + $0.suffix }, ["—/5", "—/5", "—/5"])
        let hiddenOnly = PlaceRatingsState.loaded(.init(
            own: .empty, friends: .empty, astir: try PlaceRatingAggregate(score: 4.5, count: 1)
        )).metrics
        XCTAssertEqual(hiddenOnly.map(\.value), ["—", "—", "4.5"])
        XCTAssertEqual(hiddenOnly[1].subtitle, "No visible ratings yet")
        XCTAssertEqual(hiddenOnly[2].subtitle, "1 rating")
    }

    func testFailedAndLoadingRatingsAreNotPresentedAsAnEmptySuccessfulResponse() {
        XCTAssertTrue(PlaceRatingsState.loading.metrics.allSatisfy { $0.subtitle == "Loading…" })
        XCTAssertTrue(PlaceRatingsState.unavailable.metrics.allSatisfy { $0.subtitle == "Unavailable" })
    }

    func testHiddenOnlyFriendsContributionCanRemainInAstir() throws {
        let result = try decode("""
        {"own":{"score":null,"count":0},"friends":{"score":null,"count":0},"astir":{"score":4.5,"count":1}}
        """)
        XCTAssertNil(result.friends.score)
        XCTAssertEqual(result.friends.count, 0)
        XCTAssertEqual(result.astir.score, 4.5)
        XCTAssertEqual(result.astir.count, 1)
    }

    func testFriendsAndAstirKeepIndependentScoresAndDenominators() throws {
        let result = try decode("""
        {"own":{"score":3.5,"count":2},"friends":{"score":4,"count":1},"astir":{"score":2.8,"count":10}}
        """)
        XCTAssertEqual(result.own.count, 2)
        XCTAssertEqual(result.friends.score, 4)
        XCTAssertEqual(result.friends.count, 1)
        XCTAssertEqual(result.astir.score, 2.8)
        XCTAssertEqual(result.astir.count, 10)
        XCTAssertEqual(try JSONDecoder().decode(PlaceRatingSummaries.self, from: JSONEncoder().encode(result)), result)
    }

    func testEmptyRatingsDoNotInventAScore() throws {
        let empty = try PlaceRatingAggregate(score: nil, count: 0)
        XCTAssertNil(empty.score)
        XCTAssertEqual(empty.count, 0)
    }

    func testMalformedPairsAndNonFiniteScoresAreRejected() {
        for (score, count) in [(nil, 1), (nil, -1), (5.0, 0), (0.0, 1), (5.1, 1), (.infinity, 1), (.nan, 1)] as [(Double?, Int)] {
            XCTAssertThrowsError(try PlaceRatingAggregate(score: score, count: count))
        }
        for value in ["{\"score\":5,\"count\":0}", "{\"score\":null,\"count\":1}", "{\"score\":6,\"count\":1}", "{\"score\":3}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(PlaceRatingAggregate.self, from: Data(value.utf8)))
        }
    }

    func testMissingGlobalSummaryIsNotReplacedByFriends() {
        XCTAssertThrowsError(try decode("""
        {"own":{"score":null,"count":0},"friends":{"score":4,"count":1}}
        """))
    }

    private func decode(_ json: String) throws -> PlaceRatingSummaries {
        try JSONDecoder().decode(PlaceRatingSummaries.self, from: Data(json.utf8))
    }
}
