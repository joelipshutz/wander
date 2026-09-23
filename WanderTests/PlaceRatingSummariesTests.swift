import XCTest
@testable import Wander

final class PlaceRatingSummariesTests: XCTestCase {
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
