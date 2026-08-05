import XCTest
@testable import Wander

@MainActor
final class TrustedPlaceSearchTests: XCTestCase {
    func testQueryNormalizesPunctuationPossessivesStopWordsAndAliases() {
        let query = TrustedPlaceSearchQuery("Please show me Ryan’s cafés, with Wi-Fi!")

        XCTAssertEqual(query.normalizedPhrase, "please show me ryan coffee with wi fi")
        XCTAssertEqual(query.scoringTokens, ["ryan", "coffee", "wi", "fi"])
        XCTAssertEqual(query.requiredTokens, ["ryan", "coffee", "wi", "fi"])
    }

    func testRequiredTokensCanMatchAcrossFieldsOnTheSameMemory() {
        let matching = makeVisiblePlace(
            id: "matching",
            name: "Blue Bottle",
            ownerName: "Ryan",
            ownerHandle: "ryan",
            category: "Coffee shop",
            locality: "Pasadena",
            note: "Quiet patio"
        )
        let wrongOwner = makeVisiblePlace(
            id: "wrong-owner",
            name: "Blue Bottle",
            ownerName: "Maya",
            ownerHandle: "maya",
            category: "Coffee shop",
            locality: "Pasadena",
            note: "Quiet patio"
        )

        let matches = TrustedPlaceSearch.matches(
            query: "Ryan coffee Pasadena quiet",
            in: [wrongOwner, matching]
        )

        XCTAssertEqual(matches.map(\.place.id), ["matching"])
        XCTAssertEqual(Set(matches[0].evidence.map(\.field)), [.owner, .category, .area, .note])
    }

    func testCafeAliasMatchesCoffeeCategory() {
        let place = makeVisiblePlace(id: "coffee", name: "Circuit", category: "Coffee shop")

        XCTAssertEqual(
            TrustedPlaceSearch.matches(query: "cafes", in: [place]).map(\.place.id),
            ["coffee"]
        )
    }

    func testEveryRequiredTokenMustMatch() {
        let place = makeVisiblePlace(id: "coffee", name: "Circuit", category: "Coffee shop")

        XCTAssertTrue(
            TrustedPlaceSearch.matches(query: "coffee pasadena", in: [place]).isEmpty
        )
    }

    func testNameEvidenceRanksAheadOfNoteEvidence() {
        let oldDate = Date(timeIntervalSince1970: 100)
        let newDate = Date(timeIntervalSince1970: 200)
        let nameMatch = makeVisiblePlace(
            id: "name-match",
            name: "Circuit Coffee",
            category: "Restaurant",
            savedAt: oldDate
        )
        let noteMatch = makeVisiblePlace(
            id: "note-match",
            name: "Dinner",
            category: "Restaurant",
            note: "Try Circuit Coffee next door",
            savedAt: newDate
        )

        let matches = TrustedPlaceSearch.matches(query: "Circuit Coffee", in: [noteMatch, nameMatch])

        XCTAssertEqual(matches.map(\.place.id), ["name-match", "note-match"])
        XCTAssertGreaterThan(matches[0].score, matches[1].score)
    }

    func testMalformedAttributeJSONIsIgnored() {
        let place = makeVisiblePlace(
            id: "malformed",
            name: "Circuit",
            attributes: [("personal_labels", "not-json")]
        )

        XCTAssertTrue(TrustedPlaceSearch.matches(query: "not json", in: [place]).isEmpty)
    }

    func testStableTieBreakUsesSavedDateThenID() {
        let newest = makeVisiblePlace(
            id: "newest",
            name: "Coffee One",
            savedAt: Date(timeIntervalSince1970: 300)
        )
        let alpha = makeVisiblePlace(
            id: "alpha",
            name: "Coffee Two",
            savedAt: Date(timeIntervalSince1970: 200)
        )
        let beta = makeVisiblePlace(
            id: "beta",
            name: "Coffee Two",
            savedAt: Date(timeIntervalSince1970: 200)
        )

        let matches = TrustedPlaceSearch.matches(query: "coffee", in: [beta, alpha, newest])

        XCTAssertEqual(matches.map(\.place.id), ["newest", "alpha", "beta"])
    }

    func testPlannerConsumesLongestOverlappingLiteralPhrase() {
        let query = TrustedPlaceSearchQuery(
            "date night coffee",
            consumedPhrases: ["date", "date night"]
        )

        XCTAssertEqual(query.consumedTokens, ["date", "night"])
        XCTAssertEqual(query.requiredTokens, ["coffee"])
    }

    func testPlannerConsumesPossessiveOwnerAndStructuredAliases() {
        let filters = DiscoverFilters(
            query: "Ryan's highly rated cafes",
            categories: [WanderPlaceCategory.coffeeTeaSweets],
            statuses: [.been],
            ownerQuery: "ryan",
            opinion: .favorite,
            sort: .ownerRatingDescending
        )

        let query = TrustedPlaceSearchQuery(
            filters.query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )

        XCTAssertTrue(query.requiredTokens.isEmpty)
        XCTAssertEqual(Set(query.consumedTokens), ["ryan", "highly", "rated", "coffee"])
        XCTAssertTrue(query.allowsConsumedOnlyMatches)
    }

    func testInferredFacetWithoutLiteralSpanConsumesNothing() {
        let filters = DiscoverFilters(query: "great coffee", tags: ["cozy"])
        let query = TrustedPlaceSearchQuery(
            filters.query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )

        XCTAssertEqual(query.requiredTokens, ["great", "coffee"])
        XCTAssertTrue(query.consumedTokens.isEmpty)
    }

    func testConsumedOnlyQueryKeepsHardFilteredCandidates() {
        let place = makeVisiblePlace(id: "filtered", name: "Circuit", category: "Coffee shop")
        let query = TrustedPlaceSearchQuery("favorite coffee", consumedPhrases: ["favorite", "coffee"])

        XCTAssertEqual(
            TrustedPlaceSearch.matches(query: query, in: [place]).map(\.place.id),
            ["filtered"]
        )
    }

    func testCachedDocumentRefreshesWhenSearchableMemoryChanges() {
        let place = makeVisiblePlace(id: "cache-refresh", name: "Circuit", note: "Sunny patio")

        XCTAssertEqual(TrustedPlaceSearch.matches(query: "sunny", in: [place]).count, 1)

        place.userPlace.note = "Quiet booths"
        place.userPlace.updatedAt = place.userPlace.updatedAt.addingTimeInterval(1)

        XCTAssertTrue(TrustedPlaceSearch.matches(query: "sunny", in: [place]).isEmpty)
        XCTAssertEqual(TrustedPlaceSearch.matches(query: "quiet", in: [place]).count, 1)
    }

    func testSearchOneThousandMemoriesP95UnderFiftyMilliseconds() {
        let places = (0..<1_000).map { index in
            makeVisiblePlace(
                id: "performance-\(index)",
                name: "Place \(index)",
                ownerName: "Ryan \(index)",
                ownerHandle: "ryan\(index)",
                category: "Coffee shop",
                locality: "Pasadena",
                note: "Quiet patio number \(index)",
                attributes: [("personal_labels", #"["work"]"#)]
            )
        }
        let query = TrustedPlaceSearchQuery("Ryan coffee Pasadena quiet")
        let clock = ContinuousClock()

        for _ in 0..<5 {
            XCTAssertEqual(TrustedPlaceSearch.matches(query: query, in: places).count, 1_000)
        }

        var samples: [Double] = []
        for _ in 0..<30 {
            let start = clock.now
            let matches = TrustedPlaceSearch.matches(query: query, in: places)
            let duration = start.duration(to: clock.now)
            XCTAssertEqual(matches.count, 1_000)
            samples.append(Self.milliseconds(duration))
        }

        samples.sort()
        let p95Index = min(samples.count - 1, Int((Double(samples.count) * 0.95).rounded(.up)) - 1)
        let p95 = samples[p95Index]
        XCTAssertLessThan(
            p95,
            50,
            "host=\(ProcessInfo.processInfo.hostName) p95_ms=\(p95) samples_ms=\(samples)"
        )
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return (Double(components.seconds) * 1_000)
            + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }

    private func makeVisiblePlace(
        id: String,
        name: String,
        ownerName: String = "Maya",
        ownerHandle: String = "maya",
        category: String = "Coffee shop",
        locality: String? = nil,
        note: String? = nil,
        savedAt: Date = Date(timeIntervalSince1970: 100),
        attributes: [(key: String, json: String)] = []
    ) -> VisiblePlace {
        let owner = LocalProfile(
            localID: "owner-\(id)",
            handle: ownerHandle,
            displayName: ownerName
        )
        let place = LocalPlace(
            localID: "place-\(id)",
            canonicalName: name,
            category: category,
            address: locality.map { "1 Main Street, \($0)" },
            locality: locality,
            region: "California",
            country: "United States",
            latitude: 34,
            longitude: -118
        )
        let userPlace = LocalUserPlace(
            localID: id,
            userID: owner.id,
            placeID: place.id,
            status: .been,
            visibility: .followers,
            note: note,
            savedAt: savedAt,
            sourceType: "manual"
        )
        let localAttributes = attributes.enumerated().map { index, attribute in
            LocalPlaceAttribute(
                localID: "attribute-\(id)-\(index)",
                userPlaceID: userPlace.id,
                questionKey: attribute.key,
                valueType: "multi_select",
                valueJSON: attribute.json
            )
        }
        return VisiblePlace(
            id: id,
            place: place,
            userPlace: userPlace,
            owner: owner,
            attributes: localAttributes
        )
    }
}
