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
        XCTAssertFalse(garden.bothRegulars)
        XCTAssertEqual(garden.totalVisits, 2)
        XCTAssertNotEqual(narwhal.narrativeTitle, garden.narrativeTitle)
        XCTAssertNotEqual(narwhal.narrativeSymbol, garden.narrativeSymbol)

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
        XCTAssertFalse(mix.contains { $0.id == "terrace" })
        XCTAssertTrue(mix.contains { $0.bothLoved && $0.bothRegulars })
        XCTAssertTrue(mix.contains { $0.bothLoved && !$0.bothRegulars })
        XCTAssertTrue(mix.contains { $0.youWanna && $0.joeWanna })
        XCTAssertTrue(mix.contains { $0.kind == .introduce })
        XCTAssertEqual(Set(mix.map(\.narrativeTitle)).count, 6)
        XCTAssertEqual(Set(mix.map(\.narrativeSymbol)).count, 5)
        XCTAssertTrue(mix.allSatisfy { $0.narrativeTitle.contains($0.name) })
        XCTAssertEqual(CommonGroundMockData.places.count, 10)
    }

    func testIntroductionNarrativesRespectWhoseFavoriteTheOtherPersonWantsToTry() throws {
        let joesFavorite = try place("mudwater")
        XCTAssertTrue(joesFavorite.youWanna)
        XCTAssertEqual(joesFavorite.youVisits, 0)
        XCTAssertGreaterThanOrEqual(joesFavorite.joeVisits, 3)
        XCTAssertEqual(joesFavorite.narrativeTitle, "Joe’s been to Mudwater\nYou wanna go")

        let yourFavorite = try place("the-little-room")
        XCTAssertTrue(yourFavorite.joeWanna)
        XCTAssertEqual(yourFavorite.joeVisits, 0)
        XCTAssertGreaterThanOrEqual(yourFavorite.youVisits, 3)
        XCTAssertEqual(yourFavorite.narrativeTitle, "You’ve been to The Little Room\nJoe wants to go")

        for candidate in [try place("narwhal"), joesFavorite, yourFavorite] {
            XCTAssertFalse(candidate.reason.contains("/5"), "Repeat evidence should describe check-ins.")
        }
    }

    func testMutualWannaStillRecommendsAPlaceWithCheckInsAndMultipleWannaEvents() throws {
        let candidate = try place("not-no-bar")
        XCTAssertEqual(candidate.youVisits, 1)
        XCTAssertEqual(candidate.youEvidence.wannaCount, 2)
        XCTAssertTrue(candidate.youWanna)
        XCTAssertTrue(candidate.joeWanna)
        XCTAssertEqual(candidate.kind, .mutualWanna)
        XCTAssertEqual(candidate.reason, "In both of your Wannas")
        XCTAssertTrue(CommonGroundMockData.mix().contains { $0.id == candidate.id })
        XCTAssertEqual(candidate.narrativeTitle, "You both want to go to Not No Bar")
        XCTAssertFalse(candidate.narrativeDetail.hasSuffix("."))
        XCTAssertFalse(CommonGroundInvitationDraft(place: candidate).message.contains("finally"))
    }

    func testWannaEventsCanCreateEitherRecommendationDirectionAfterACheckIn() {
        let joesFavorite = CommonGroundMockPlace(
            id: "repeat", name: "Repeat", category: "Coffee", area: "Silver Lake", city: "Los Angeles",
            systemImage: "cup.and.saucer", youRating: 4, joeRating: 5,
            youVisits: 1, joeVisits: 8, youWanna: false, joeWanna: false,
            youWannaEventIDs: ["wanna-1", "wanna-2"], reason: "In your Wannas"
        )
        XCTAssertEqual(joesFavorite.kind, .introduce)
        XCTAssertEqual(joesFavorite.narrativeTitle, "Joe’s been to Repeat\nYou wanna go")

        let yourFavorite = CommonGroundMockPlace(
            id: "repeat", name: "Repeat", category: "Coffee", area: "Silver Lake", city: "Los Angeles",
            systemImage: "cup.and.saucer", youRating: 5, joeRating: 4,
            youVisits: 8, joeVisits: 1, youWanna: false, joeWanna: false,
            joeWannaEventIDs: ["wanna-3"], reason: "In Joe’s Wannas"
        )
        XCTAssertEqual(yourFavorite.kind, .introduce)
        XCTAssertEqual(yourFavorite.narrativeTitle, "You’ve been to Repeat\nJoe wants to go")
        XCTAssertTrue(CommonGroundInvitationDraft(place: joesFavorite).message.contains("I wanna go"))
        XCTAssertTrue(CommonGroundInvitationDraft(place: yourFavorite).message.contains("you wanna go"))
    }

    func testAvailableCitiesUseTheUnionOfVisitsAndExcludeWannaOnlyCities() {
        XCTAssertEqual(CommonGroundMockData.availableCities, ["Los Angeles", "London"])
        let london = CommonGroundMockData.places.filter { $0.city == "London" }
        XCTAssertTrue(london.allSatisfy { $0.youVisits == 0 })
        XCTAssertTrue(london.contains { $0.joeVisits > 0 })
        XCTAssertTrue(CommonGroundMockData.availableCities.contains("London"))

        let kyoto = CommonGroundMockData.places.filter { $0.city == "Kyoto" }
        XCTAssertFalse(kyoto.isEmpty)
        XCTAssertTrue(kyoto.allSatisfy { $0.youWanna && $0.joeWanna && $0.totalVisits == 0 })
        XCTAssertFalse(CommonGroundMockData.availableCities.contains("Kyoto"))
    }

    func testMixUsesTheChosenEligibleCityAndSparseKeepsItsFirstTwoCandidates() {
        XCTAssertEqual(CommonGroundMockData.mix().map(\.id), [
            "narwhal", "grove-gardens", "not-no-bar", "mudwater", "the-little-room", "lantern-kitchen"
        ])
        XCTAssertEqual(CommonGroundMockData.mix(area: "London").map(\.id), ["canal-coffee", "sundial-books"])
        XCTAssertEqual(CommonGroundMockData.mix(area: " los angeles ").count, 6)
        XCTAssertTrue(CommonGroundMockData.mix(area: "San Francisco").isEmpty)
        XCTAssertTrue(CommonGroundMockData.mix(area: "Kyoto").isEmpty)
        XCTAssertTrue(CommonGroundMockData.mix(area: "Kyoto", sparse: true).isEmpty)
        XCTAssertEqual(CommonGroundMockData.mix(sparse: true).map(\.id), ["narwhal", "grove-gardens"])
        XCTAssertEqual(CommonGroundMockData.mix(area: "London", sparse: true).map(\.id), ["canal-coffee", "sundial-books"])
    }

    func testEveryRelationshipUsesActualVisitsAndIndependentWannaEvidence() {
        let states: [(Int, Int, Bool, Bool, Double?, Double?, CommonGroundMockPlace.Linkage)] = [
            (13, 3, false, false, 5, 5, .sharedRegulars),
            (1, 1, false, false, 5, 5, .sharedLove),
            (1, 0, false, true, nil, nil, .viewerBeenPartnerWanna),
            (0, 1, true, false, nil, nil, .partnerBeenViewerWanna),
            (1, 1, false, false, nil, 5, .partnerLoves),
            (1, 1, false, false, 5, nil, .viewerLoves),
            (0, 0, true, true, nil, nil, .mutualWanna),
            (12, 0, true, true, 5, nil, .mutualWanna),
            (0, 0, true, true, 5, 5, .mutualWanna),
            (1, 1, false, false, nil, nil, .bothBeen),
            (1, 0, false, false, nil, nil, .viewerBeen),
            (0, 1, false, false, nil, nil, .partnerBeen),
            (0, 0, true, false, nil, nil, .viewerWanna),
            (0, 0, false, true, nil, nil, .partnerWanna),
            (0, 0, false, false, 5, 5, .sharedPlace)
        ]
        for (mine, theirs, myWanna, theirWanna, myRating, theirRating, expected) in states {
            let place = CommonGroundMockPlace(
                id: "state", name: "Charleston Park", category: "Park", area: "City", city: "City",
                systemImage: "tree", youRating: myRating, joeRating: theirRating,
                youVisits: mine, joeVisits: theirs, youWanna: myWanna, joeWanna: theirWanna,
                reason: "Stale fallback must never override actual evidence"
            )
            XCTAssertEqual(place.linkage, expected)
            XCTAssertFalse(place.narrativeTitle.hasSuffix("."))
            XCTAssertFalse(place.narrativeDetail.contains("Stale fallback"))
            if mine == 0 || theirs == 0 {
                XCTAssertFalse(place.narrativeTitle.contains("both been"))
                XCTAssertFalse(CommonGroundInvitationDraft(place: place).reasonTitle.contains("both been"))
            }
            if expected == .viewerBeenPartnerWanna {
                XCTAssertEqual(place.narrativeTitle, "You’ve been to Charleston Park\nJoe wants to go")
            }
        }
    }

    private func place(_ id: String) throws -> CommonGroundMockPlace {
        try XCTUnwrap(CommonGroundMockData.places.first { $0.id == id })
    }

    private func evidencePlace(
        youRating: Double?, joeRating: Double?, youVisits: Int, joeVisits: Int
    ) -> CommonGroundMockPlace {
        CommonGroundMockPlace(
            id: "evidence", name: "Evidence", category: "Coffee", area: "Silver Lake", city: "Los Angeles",
            systemImage: "cup.and.saucer", youRating: youRating, joeRating: joeRating,
            youVisits: youVisits, joeVisits: joeVisits, youWanna: false, joeWanna: false,
            reason: "Threshold fixture"
        )
    }
}
#endif
