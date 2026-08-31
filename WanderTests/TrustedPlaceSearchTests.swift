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

    func testSupportingFieldsIncludeEveryFieldThatMatchesTheQuery() throws {
        let place = makeVisiblePlace(
            id: "all-fields",
            name: "Coffee Counter",
            ownerName: "Coffee Fan",
            ownerHandle: "coffee-fan",
            category: "Coffee shop",
            locality: "Coffee District",
            note: "Coffee before work",
            attributes: [("personal_labels", #"["coffee"]"#)]
        )

        let match = try XCTUnwrap(
            TrustedPlaceSearch.matches(query: "coffee been", in: [place]).first
        )

        XCTAssertEqual(Set(match.evidence.map(\.field)), [.name, .status])
        XCTAssertEqual(
            match.supportingFields,
            [.name, .owner, .category, .area, .note, .attribute, .status]
        )
    }

    func testMapSearchSavedStrengthSeparatesPlaceIdentityFromMemoryContext() throws {
        let strong = makeVisiblePlace(
            id: "strong",
            name: "Long Tables Cafe",
            category: "Restaurant"
        )
        let contextual = makeVisiblePlace(
            id: "contextual",
            name: "Fern Desk Coffee",
            category: "Restaurant",
            note: "Long tables for group work"
        )

        let candidates = MapSearchCandidatePolicy.savedCandidates(
            query: "long tables",
            in: [contextual, strong],
            currentUserID: "viewer"
        )
        let strongCandidate = try XCTUnwrap(candidates.first { $0.place.id == strong.id })
        let contextualCandidate = try XCTUnwrap(candidates.first { $0.place.id == contextual.id })

        XCTAssertEqual(MapSearchCandidatePolicy.strength(of: strongCandidate), .strong)
        XCTAssertEqual(MapSearchCandidatePolicy.strength(of: contextualCandidate), .contextual)
        XCTAssertEqual(MapSearchCandidatePolicy.strongFields, [.name, .category, .area])
        XCTAssertEqual(
            MapSearchCandidatePolicy.contextualFields,
            [.owner, .note, .attribute, .status]
        )
    }

    func testMapSearchSavedCandidatesCollapseDuplicateSavesIntoOneGroup() throws {
        let mine = makeVisiblePlace(
            id: "mine",
            name: "Larchmont Noodles",
            ownerName: "Joe",
            ownerHandle: "joe",
            locality: "Los Angeles"
        )
        let friend = makeVisiblePlace(
            id: "friend",
            name: "Larchmont Noodles",
            ownerName: "Ryan",
            ownerHandle: "ryan",
            locality: "Los Angeles"
        )

        let candidates = MapSearchCandidatePolicy.savedCandidates(
            query: "larchmont noodles",
            in: [friend, mine],
            currentUserID: mine.owner.id
        )

        let candidate = try XCTUnwrap(candidates.first)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidate.group.saveCount, 2)
        XCTAssertEqual(candidate.place.id, mine.id)
        XCTAssertEqual(Set(candidate.group.places.map(\.id)), [mine.id, friend.id])
    }

    func testMapSearchSavedGroupIsStrongWhenAnyDuplicateHasPlaceFieldEvidence() throws {
        let contextualFirst = makeVisiblePlace(
            id: "contextual-first",
            name: "Harbor House",
            ownerName: "Pasadena",
            ownerHandle: "pasadena-fan",
            locality: "Burbank",
            sourceProviderPlaceID: "shared-harbor-house"
        )
        let strongDuplicate = makeVisiblePlace(
            id: "strong-duplicate",
            name: "Harbor House Annex",
            ownerName: "Maya",
            ownerHandle: "maya",
            locality: "Pasadena",
            sourceProviderPlaceID: "shared-harbor-house"
        )

        let candidate = try XCTUnwrap(
            MapSearchCandidatePolicy.savedCandidates(
                query: "pasadena",
                in: [contextualFirst, strongDuplicate],
                currentUserID: "viewer"
            ).first
        )

        XCTAssertEqual(candidate.group.saveCount, 2)
        XCTAssertEqual(candidate.match.place.id, contextualFirst.id)
        XCTAssertEqual(candidate.match.supportingFields, [.owner, .area])
        XCTAssertEqual(MapSearchCandidatePolicy.strength(of: candidate), .strong)
    }

    func testMapSearchCandidateOrderingIsSharedAcrossSavedAndMapKitResults() {
        let strong = makeVisiblePlace(
            id: "strong",
            name: "Long Tables Cafe",
            category: "Restaurant"
        )
        let contextual = makeVisiblePlace(
            id: "contextual",
            name: "Fern Desk Coffee",
            category: "Restaurant",
            note: "Long tables for group work"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "long tables",
            in: [contextual, strong],
            currentUserID: "viewer"
        )
        let credibleMapKit = makeCandidate("credible", name: "Long Tables Bakery")
        let unrelatedMapKit = makeCandidate("unrelated", name: "Sunset Hotel")

        let ordered = MapSearchCandidatePolicy.orderedCandidates(
            query: "long tables",
            saved: saved,
            mapKit: [unrelatedMapKit, credibleMapKit]
        )

        XCTAssertEqual(
            ordered.map { candidate in
                switch candidate {
                case .saved(let saved):
                    return "saved:\(saved.place.id)"
                case .mapKit(let mapKit):
                    return "mapkit:\(mapKit.id)"
                }
            },
            ["saved:strong", "mapkit:credible", "saved:contextual", "mapkit:unrelated"]
        )
    }

    func testMapSearchPolicyPromotesStrongSavedCandidateAboveHigherScoringContextMatch() throws {
        let contextual = makeVisiblePlace(
            id: "contextual-high-score",
            name: "Harbor House",
            ownerName: "Pasadena",
            ownerHandle: "pasadena-fan",
            locality: "Burbank"
        )
        let strong = makeVisiblePlace(
            id: "strong-lower-score",
            name: "River Room",
            ownerName: "Maya",
            ownerHandle: "maya",
            locality: "Pasadena"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "pasadena",
            in: [contextual, strong],
            currentUserID: "viewer"
        )

        XCTAssertEqual(saved.first?.place.id, contextual.id)
        let first = try XCTUnwrap(
            MapSearchCandidatePolicy.orderedCandidates(
                query: "pasadena",
                saved: saved,
                mapKit: []
            ).first
        )
        guard case .saved(let selected) = first else {
            return XCTFail("Expected a saved search candidate")
        }
        XCTAssertEqual(selected.place.id, strong.id)
        XCTAssertEqual(MapSearchCandidatePolicy.strength(of: selected), .strong)
    }

    func testActivePinRetentionUsesFullSearchGroupKeyWhenProjectionHasOnlyOneDuplicate() throws {
        let currentUserSave = makeVisiblePlace(
            id: "current-user-save",
            name: "Harbor House",
            ownerName: "Joe",
            ownerHandle: "joe",
            sourceProviderPlaceID: "shared-retention-place"
        )
        let projectedFriendSave = makeVisiblePlace(
            id: "friend-save",
            name: "Harbor House Cafe",
            ownerName: "Ryan",
            ownerHandle: "ryan",
            sourceProviderPlaceID: "shared-retention-place"
        )
        let currentUserID = currentUserSave.owner.id
        let fullGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: [projectedFriendSave, currentUserSave],
                currentUserID: currentUserID
            ).first
        )
        let projectedGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: [projectedFriendSave],
                currentUserID: currentUserID
            ).first
        )
        XCTAssertNotEqual(fullGroup.key, projectedGroup.key)

        let retainedGroup = try XCTUnwrap(
            MapActivePinRetention.groups(
                from: [projectedGroup],
                retaining: fullGroup.primary,
                retainingGroup: fullGroup,
                currentUserID: currentUserID
            ).first
        )

        XCTAssertEqual(retainedGroup.key, fullGroup.key)
        XCTAssertEqual(retainedGroup.primary.userPlace.id, currentUserSave.userPlace.id)
        XCTAssertEqual(
            MapActivePinRetention.groupKey(for: fullGroup.primary, in: [retainedGroup]),
            fullGroup.key
        )
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

    func testPlannerConsumesWorthCrossingTownForAsOneOpinionPhrase() {
        let filters = DeterministicFilterParser.filters(
            query: "coffee worth crossing town for",
            schema: DiscoverFilterSchema()
        )

        let query = TrustedPlaceSearchQuery(
            filters.query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )
        let request = DiscoverRecmePlaceSearchPlanner.request(
            query: filters.query,
            filters: filters
        )

        XCTAssertTrue(query.requiredTokens.isEmpty)
        XCTAssertEqual(request.query, "")
        XCTAssertEqual(request.semanticQuery, "coffee worth crossing town for")
        XCTAssertEqual(request.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertTrue(request.favoriteOnly)
        XCTAssertEqual(request.scope, .everyone)
    }

    func testRecmePlannerTreatsFriendsAsHardMutualScope() {
        let filters = DeterministicFilterParser.filters(
            query: "friends coffee",
            schema: DiscoverFilterSchema()
        )

        let request = DiscoverRecmePlaceSearchPlanner.request(
            query: filters.query,
            filters: filters
        )

        XCTAssertEqual(request.scope, .friends)
        XCTAssertEqual(request.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(request.query, "")
    }

    func testPlannerUsesDeterministicParserCategoryAndRelationshipAliases() {
        let filters = DiscoverFilters(
            query: "hikes in LA from people",
            categories: [WanderPlaceCategory.outdoorsNature],
            area: "LA",
            relationship: .follower
        )

        let query = TrustedPlaceSearchQuery(
            filters.query,
            consumedPhrases: DiscoverTrustedPlaceSearchPlanner.consumedPhrases(for: filters)
        )

        XCTAssertTrue(query.requiredTokens.isEmpty)
        XCTAssertEqual(Set(query.consumedTokens), ["hikes", "la", "from", "people"])
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
        print("[REC225Performance] host=\(ProcessInfo.processInfo.hostName) p95_ms=\(p95)")
        XCTAssertLessThan(
            p95,
            50,
            "host=\(ProcessInfo.processInfo.hostName) p95_ms=\(p95) samples_ms=\(samples)"
        )
    }

    func testSemanticFusionBoostsProviderOverlapAndCanRecoverAHighSemanticMiss() {
        let lexical = ["lexical-a", "lexical-b", "overlap", "lexical-d"]
            .map(makeCandidate)
        let semantic = ["semantic-only", "overlap"]
            .map(makeCandidate)

        let outcome = RecmePlaceSearchFusion.outcome(
            lexical: lexical,
            semantic: semantic,
            semanticStatus: .succeeded,
            limit: 5
        )

        XCTAssertEqual(
            outcome.candidates.map(\.id),
            ["overlap", "lexical-a", "lexical-b", "semantic-only", "lexical-d"]
        )
        XCTAssertEqual(outcome.lexicalCount, 4)
        XCTAssertEqual(outcome.semanticCount, 2)
        XCTAssertEqual(outcome.overlapCount, 1)
        XCTAssertEqual(outcome.matches.first?.providers, [.lexical, .semantic])
        XCTAssertEqual(outcome.semanticStatus, .succeeded)
        XCTAssertEqual(RecmePlaceSearchOutcome.rankingPolicyVersion, "search_rrf_v1")
    }

    func testSemanticFailureLeavesLexicalOrderingUntouched() {
        let lexical = ["a", "b", "c"].map(makeCandidate)

        let outcome = RecmePlaceSearchFusion.outcome(
            lexical: lexical,
            semantic: [],
            semanticStatus: .failed,
            limit: 20
        )

        XCTAssertEqual(outcome.candidates.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(outcome.matches.map(\.providers), [[.lexical], [.lexical], [.lexical]])
        XCTAssertEqual(outcome.semanticStatus, .failed)
    }

    func testBackendCanReturnSemanticResultsWhenLexicalProviderFails() async throws {
        let semantic = makeCandidate("semantic-only")
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .failure(SearchProviderTestError.expected),
            semanticResult: .success([semantic])
        )
        let backend = WanderBackend(placeRepository: repository)

        let outcome = try await backend.searchRecmePlaces(
            RecmePlaceSearchRequest(query: "rainy coffee"),
            includesSemanticProvider: true
        )

        XCTAssertEqual(outcome.candidates.map(\.id), ["semantic-only"])
        XCTAssertEqual(outcome.semanticStatus, .succeeded)
        XCTAssertEqual(repository.lexicalRequestCount, 1)
        XCTAssertEqual(repository.semanticRequestCount, 1)
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return (Double(components.seconds) * 1_000)
            + (Double(components.attoseconds) / 1_000_000_000_000_000)
    }

    private func makeCandidate(_ id: String) -> PlaceCandidate {
        makeCandidate(id, name: nil)
    }

    private func makeCandidate(_ id: String, name: String?) -> PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name ?? id,
            category: WanderPlaceCategory.coffeeTeaSweets,
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            subcategory: "coffee_shop",
            categorySource: PlaceCategorySource.provider.rawValue,
            categoryConfidence: 1,
            rawProviderType: "cafe",
            latitude: 34,
            longitude: -118,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: id,
            confidence: 1
        )
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
        attributes: [(key: String, json: String)] = [],
        sourceProviderPlaceID: String? = nil
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
            longitude: -118,
            sourceProviderPlaceID: sourceProviderPlaceID
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

private enum SearchProviderTestError: Error {
    case expected
}

@MainActor
private final class SearchProviderPlaceRepository: PlaceRepository {
    let lexicalResult: Result<[PlaceCandidate], Error>
    let semanticResult: Result<[PlaceCandidate], Error>
    private(set) var lexicalRequestCount = 0
    private(set) var semanticRequestCount = 0

    init(
        lexicalResult: Result<[PlaceCandidate], Error>,
        semanticResult: Result<[PlaceCandidate], Error>
    ) {
        self.lexicalResult = lexicalResult
        self.semanticResult = semanticResult
    }

    func places(in viewport: MapViewport) async throws -> [VisiblePlace] { [] }

    func searchRecmePlaces(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        lexicalRequestCount += 1
        return try lexicalResult.get()
    }

    func searchRecmePlacesSemantic(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        semanticRequestCount += 1
        return try semanticResult.get()
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { [] }
}
