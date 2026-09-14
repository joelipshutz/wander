#if DEBUG
@testable import Wander
import XCTest

final class CommonGroundMockDataTests: XCTestCase {
    func testLaunchRequiresExplicitOptInAndResolvesEveryPage() {
        XCTAssertNil(CommonGroundMockPage.resolved(from: ["Wander"], environment: [:]))
        XCTAssertNil(CommonGroundMockPage.resolved(
            from: ["Wander", "-WanderInCommonMockup", "overlap"], environment: [:]
        ))

        for page in CommonGroundMockPage.allCases {
            XCTAssertEqual(
                CommonGroundMockPage.resolved(
                    from: ["Wander", "-WanderCommonGroundMockup", page.rawValue], environment: [:]
                ),
                page
            )
            XCTAssertEqual(
                CommonGroundMockPage.resolved(
                    from: ["Wander"], environment: ["WANDER_COMMON_GROUND_MOCKUP": page.rawValue]
                ),
                page
            )
        }
    }

    func testExplicitInvalidOrMissingLaunchValuesFallBackToDetail() {
        XCTAssertEqual(CommonGroundMockPage.resolved(
            from: ["Wander", "-WanderCommonGroundMockup"], environment: [:]
        ), .detail)
        XCTAssertEqual(CommonGroundMockPage.resolved(
            from: ["Wander", "-WanderCommonGroundMockup", "unknown"], environment: [:]
        ), .detail)
        XCTAssertEqual(CommonGroundMockPage.resolved(
            from: ["Wander"], environment: ["WANDER_COMMON_GROUND_MOCKUP": ""]
        ), .detail)
        XCTAssertEqual(CommonGroundMockPage.resolved(
            from: ["Wander", "-WanderCommonGroundMockup", "detail"],
            environment: ["WANDER_COMMON_GROUND_MOCKUP": "recipient"]
        ), .recipient)
    }

    func testPairEvidenceKeepsSeparateVisitCountsAndDoesNotInventSharedLiking() throws {
        let narwhal = try place("narwhal")
        XCTAssertEqual(narwhal.youVisits, 18)
        XCTAssertEqual(narwhal.joeVisits, 17)
        XCTAssertEqual(narwhal.totalVisits, 35)
        XCTAssertTrue(narwhal.bothLoved)
        XCTAssertTrue(narwhal.bothRegulars)

        let garden = try place("grove-gardens")
        XCTAssertEqual(garden.youRating, 5)
        XCTAssertEqual(garden.joeRating, 4.5)
        XCTAssertTrue(garden.bothLoved)
        XCTAssertTrue(garden.bothRegulars)

        for id in ["not-no-bar", "mudwater", "lantern-kitchen", "terrace"] {
            let candidate = try place(id)
            XCTAssertFalse(candidate.bothLoved, id)
            XCTAssertFalse(candidate.bothRegulars, id)
        }
        for candidate in CommonGroundMockData.places {
            for rating in [candidate.youRating, candidate.joeRating].compactMap({ $0 }) {
                XCTAssertTrue(PlaceRating.allowedScores.contains(rating), candidate.name)
            }
        }
    }

    func testLovedAndRegularThresholdsRequireEvidenceFromBothPeople() {
        let threshold = evidencePlace(youRating: 4.5, joeRating: 4.5, youVisits: 3, joeVisits: 3)
        XCTAssertTrue(threshold.bothLoved)
        XCTAssertTrue(threshold.bothRegulars)

        let oneSided = evidencePlace(youRating: 5, joeRating: 4, youVisits: 20, joeVisits: 2)
        XCTAssertFalse(oneSided.bothLoved)
        XCTAssertFalse(oneSided.bothRegulars)

        let unrated = evidencePlace(youRating: nil, joeRating: nil, youVisits: 3, joeVisits: 3)
        XCTAssertFalse(unrated.bothLoved)
        XCTAssertTrue(unrated.bothRegulars)
    }

    func testCuratedMixExcludesHistoryAndKeepsDistinctEvidenceBasedCandidates() {
        let mix = CommonGroundMockData.mix()
        XCTAssertEqual(mix.count, 6)
        XCTAssertEqual(Set(mix.map(\.id)).count, mix.count)
        XCTAssertFalse(mix.contains { $0.kind == .history })
        XCTAssertFalse(mix.contains { ["lantern-kitchen", "terrace"].contains($0.id) })
        XCTAssertTrue(mix.contains { $0.bothLoved && $0.bothRegulars })
        XCTAssertTrue(mix.contains { $0.youWanna && $0.joeWanna })
        XCTAssertTrue(mix.contains { $0.kind == .introduce })
        XCTAssertEqual(CommonGroundMockData.places.count, 8)
    }

    func testAreaAndOccasionFiltersIntersectTheAvailablePool() {
        let coffee = CommonGroundMockData.mix(occasion: .coffeeWalk)
        let date = CommonGroundMockData.mix(occasion: .dateNight)
        XCTAssertEqual(coffee.map(\.id), ["narwhal", "mudwater", "sundial-books", "grove-gardens"])
        XCTAssertEqual(date.map(\.id), ["not-no-bar", "the-little-room"])
        XCTAssertTrue(Set(coffee.map(\.id)).isDisjoint(with: date.map(\.id)))

        for occasion in CommonGroundMockOccasion.allCases {
            XCTAssertTrue(CommonGroundMockData.mix(area: "San Francisco", occasion: occasion).isEmpty)
            XCTAssertTrue(CommonGroundMockData.mix(area: "San Francisco", occasion: occasion, sparse: true).isEmpty)
        }
        XCTAssertEqual(CommonGroundMockData.mix(area: " los angeles ").count, 6)
    }

    func testSparseModeDoesNotRefillFromUnavailableCandidatesAfterFiltering() {
        let sparse = CommonGroundMockData.mix(sparse: true)
        XCTAssertEqual(sparse.map(\.id), ["narwhal", "not-no-bar"])
        XCTAssertEqual(CommonGroundMockData.mix(occasion: .coffeeWalk, sparse: true).map(\.id), ["narwhal"])
        XCTAssertEqual(CommonGroundMockData.mix(occasion: .dateNight, sparse: true).map(\.id), ["not-no-bar"])
    }

    private func place(_ id: String) throws -> CommonGroundMockPlace {
        try XCTUnwrap(CommonGroundMockData.places.first { $0.id == id })
    }

    private func evidencePlace(
        youRating: Double?, joeRating: Double?, youVisits: Int, joeVisits: Int
    ) -> CommonGroundMockPlace {
        CommonGroundMockPlace(
            id: "evidence", name: "Evidence", category: "Coffee", area: "Los Angeles",
            systemImage: "cup.and.saucer", youRating: youRating, joeRating: joeRating,
            youVisits: youVisits, joeVisits: joeVisits, youWanna: false, joeWanna: false,
            reason: "Threshold fixture", kind: .history
        )
    }
}
#endif
