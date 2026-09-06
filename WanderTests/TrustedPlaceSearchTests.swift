import MapKit
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

    func testMapSearchProviderSlotsCountOnlyStrongSavedMatches() {
        let contextualPlaces = [
            makeVisiblePlace(
                id: "contextual-note-one",
                name: "Harbor House",
                category: "Restaurant",
                note: "Coffee after the farmers market"
            ),
            makeVisiblePlace(
                id: "contextual-tag-one",
                name: "Fern Desk",
                category: "Library",
                attributes: [("personal_labels", #"["coffee"]"#)]
            ),
            makeVisiblePlace(
                id: "contextual-note-two",
                name: "Canyon Room",
                category: "Restaurant",
                note: "Good coffee nearby"
            ),
            makeVisiblePlace(
                id: "contextual-tag-two",
                name: "Sunset Steps",
                category: "Park",
                attributes: [("personal_labels", #"["coffee meetings"]"#)]
            )
        ]
        let contextualCandidates = MapSearchCandidatePolicy.savedCandidates(
            query: "coffee",
            in: contextualPlaces,
            currentUserID: "viewer"
        )

        XCTAssertEqual(contextualCandidates.count, 4)
        XCTAssertTrue(
            contextualCandidates.allSatisfy {
                MapSearchCandidatePolicy.strength(of: $0) == .contextual
            }
        )
        XCTAssertEqual(MapSearchCandidatePolicy.providerSlotCount(in: contextualCandidates), 0)

        let categoryMatch = makeVisiblePlace(
            id: "strong-category",
            name: "Dayglow",
            category: "Coffee shop"
        )
        let candidatesWithCategoryMatch = MapSearchCandidatePolicy.savedCandidates(
            query: "coffee",
            in: contextualPlaces + [categoryMatch],
            currentUserID: "viewer"
        )

        XCTAssertEqual(MapSearchCandidatePolicy.providerSlotCount(in: candidatesWithCategoryMatch), 1)
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

    func testNamedSearchRanksExactProviderBeforeSavedPrefix() throws {
        let savedPrefix = makeVisiblePlace(
            id: "saved-prefix",
            name: "Dayglow Coffee",
            category: "Restaurant"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "Dayglow",
            in: [savedPrefix],
            currentUserID: "viewer"
        )
        let exactProvider = makeCandidate("exact-provider", name: "Dayglow")

        let ordered = MapSearchCandidatePolicy.orderedCandidates(
            query: "Dayglow",
            saved: saved,
            mapKit: [exactProvider]
        )

        guard case .mapKit(let first) = try XCTUnwrap(ordered.first) else {
            return XCTFail("An exact provider match should beat a saved prefix match.")
        }
        XCTAssertEqual(first.id, exactProvider.id)
        guard case .saved(let second) = try XCTUnwrap(ordered.dropFirst().first) else {
            return XCTFail("The saved prefix match should remain directly after the exact provider.")
        }
        XCTAssertEqual(second.place.id, savedPrefix.id)
    }

    func testNamedSearchRanksExactSavedBeforeExactProvider() throws {
        let exactSavedPlace = makeVisiblePlace(
            id: "exact-saved",
            name: "Dayglow",
            category: "Restaurant"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "Dayglow",
            in: [exactSavedPlace],
            currentUserID: "viewer"
        )
        let exactProvider = makeCandidate("exact-provider", name: "Dayglow")

        let ordered = MapSearchCandidatePolicy.orderedCandidates(
            query: "Dayglow",
            saved: saved,
            mapKit: [exactProvider]
        )

        guard case .saved(let first) = try XCTUnwrap(ordered.first) else {
            return XCTFail("An exact saved match should beat an exact provider match.")
        }
        XCTAssertEqual(first.place.id, exactSavedPlace.id)
        guard case .mapKit(let second) = try XCTUnwrap(ordered.dropFirst().first) else {
            return XCTFail("The exact provider match should remain after the exact saved match.")
        }
        XCTAssertEqual(second.id, exactProvider.id)
    }

    func testNamedSearchTreatsExactNameOnAnyDuplicateSaveAsExact() throws {
        let currentUserVariant = makeVisiblePlace(
            id: "current-user-variant",
            name: "Dayglow Coffee",
            ownerName: "Joe",
            ownerHandle: "joe",
            category: "Restaurant",
            sourceProviderPlaceID: "shared-dayglow"
        )
        let friendExact = makeVisiblePlace(
            id: "friend-exact",
            name: "Dayglow",
            ownerName: "Maya",
            ownerHandle: "maya",
            category: "Restaurant",
            sourceProviderPlaceID: "shared-dayglow"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "Dayglow",
            in: [friendExact, currentUserVariant],
            currentUserID: currentUserVariant.owner.id
        )
        let savedGroup = try XCTUnwrap(saved.first)
        let exactProvider = makeCandidate("other-dayglow", name: "Dayglow")

        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(savedGroup.place.id, currentUserVariant.id)
        XCTAssertEqual(savedGroup.group.saveCount, 2)
        XCTAssertEqual(
            MapSearchCandidatePolicy.nameLexicalScore(
                of: savedGroup,
                query: "Dayglow"
            ),
            1_000
        )

        let ordered = MapSearchCandidatePolicy.orderedCandidates(
            query: "Dayglow",
            saved: saved,
            mapKit: [exactProvider]
        )
        guard case .saved(let first) = try XCTUnwrap(ordered.first) else {
            return XCTFail("An exact alias in the saved group should keep that group first.")
        }
        XCTAssertEqual(first.place.id, currentUserVariant.id)
    }

    func testMapSearchProviderDedupeOnlyUsesQueryMatchingSavedRows() {
        let staleSavedPlace = makeVisiblePlace(
            id: "stale-saved",
            name: "Dayglow",
            category: "Restaurant"
        )
        let queryMatchingSavedPlace = makeVisiblePlace(
            id: "query-matching-saved",
            name: "Dayglow",
            category: "Coffee shop"
        )
        let provider = makeCandidate("provider-dayglow", name: "Dayglow")

        XCTAssertTrue(VisiblePlaceGrouping.matches(staleSavedPlace, candidate: provider))

        let staleMatches = MapSearchCandidatePolicy.savedCandidates(
            query: "coffee",
            in: [staleSavedPlace],
            currentUserID: "viewer"
        )
        XCTAssertTrue(staleMatches.isEmpty)
        XCTAssertFalse(MapSearchCandidatePolicy.contains(provider, in: staleMatches))

        let queryMatches = MapSearchCandidatePolicy.savedCandidates(
            query: "coffee",
            in: [queryMatchingSavedPlace],
            currentUserID: "viewer"
        )
        XCTAssertEqual(queryMatches.count, 1)
        XCTAssertTrue(MapSearchCandidatePolicy.contains(provider, in: queryMatches))
    }

    func testCategorySearchTreatsProviderPOIsAsCredibleWithoutNameOverlap() {
        let contextual = makeVisiblePlace(
            id: "contextual-coffee-note",
            name: "Harbor House",
            category: "Restaurant",
            note: "Coffee after the farmers market"
        )
        let saved = MapSearchCandidatePolicy.savedCandidates(
            query: "coffee",
            in: [contextual],
            currentUserID: "viewer"
        )
        let providerCandidates = [
            makeCandidate("dayglow", name: "Dayglow"),
            makeCandidate("jones", name: "Jones Bench")
        ]

        let ordered = MapSearchCandidatePolicy.orderedCandidates(
            query: "coffee",
            saved: saved,
            mapKit: providerCandidates
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
            ["mapkit:dayglow", "mapkit:jones", "saved:contextual-coffee-note"]
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

    func testExternalPlannerUsesCategoryFallbackForConsumedOnlySearch() throws {
        let filters = DeterministicFilterParser.filters(
            query: "coffee worth crossing town for",
            schema: DiscoverFilterSchema()
        )

        let input = try XCTUnwrap(
            DiscoverExternalPlaceSearchPlanner.input(
                query: filters.query,
                filters: filters
            )
        )

        XCTAssertEqual(input.name, "coffee")
        XCTAssertEqual(input.category, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertNil(input.areaHint)
    }

    func testExternalPlannerPreservesSpecificCategoryTerm() throws {
        let filters = DeterministicFilterParser.filters(
            query: "best pastries and bakeries",
            schema: DiscoverFilterSchema()
        )

        let input = try XCTUnwrap(
            DiscoverExternalPlaceSearchPlanner.input(
                query: filters.query,
                filters: filters
            )
        )

        XCTAssertEqual(input.name, "bakery")
        XCTAssertEqual(input.category, WanderPlaceCategory.coffeeTeaSweets)
    }

    func testExternalPlannerUsesCategoryTermForSuggestedHikeSearch() throws {
        let filters = DeterministicFilterParser.filters(
            query: "easy weekend hikes",
            schema: DiscoverFilterSchema()
        )

        let input = try XCTUnwrap(
            DiscoverExternalPlaceSearchPlanner.input(
                query: filters.query,
                filters: filters
            )
        )

        XCTAssertEqual(input.name, "hike")
        XCTAssertEqual(input.category, WanderPlaceCategory.outdoorsNature)
    }

    func testExternalPlannerForwardsOutOfAreaSearch() throws {
        let filters = DiscoverFilters(
            query: "coffee in NYC",
            categories: [WanderPlaceCategory.coffeeTeaSweets],
            area: "NYC"
        )

        let input = try XCTUnwrap(
            DiscoverExternalPlaceSearchPlanner.input(
                query: filters.query,
                filters: filters
            )
        )

        XCTAssertEqual(input.name, "coffee")
        XCTAssertEqual(input.areaHint, "NYC")
        XCTAssertEqual(input.category, WanderPlaceCategory.coffeeTeaSweets)
    }

    func testExternalPlannerPreservesNamedPlaceContainingCategoryWord() throws {
        let filters = DeterministicFilterParser.filters(
            query: "Courage Bagels",
            schema: DiscoverFilterSchema()
        )

        let input = try XCTUnwrap(
            DiscoverExternalPlaceSearchPlanner.input(
                query: filters.query,
                filters: filters
            )
        )

        XCTAssertEqual(input.name, "courage bagels")
        XCTAssertNil(input.category)
    }

    func testExternalPlannerKeepsSocialOnlyConstraintsInsideRecme() {
        let ownerFilters = DiscoverFilters(
            query: "Ryan's coffee",
            ownerQuery: "ryan"
        )
        let statusFilters = DiscoverFilters(
            query: "coffee I visited",
            statuses: [.been]
        )
        let relationshipFilters = DiscoverFilters(
            query: "friends coffee",
            relationship: .mutual
        )

        XCTAssertNil(DiscoverExternalPlaceSearchPlanner.input(query: ownerFilters.query, filters: ownerFilters))
        XCTAssertNil(DiscoverExternalPlaceSearchPlanner.input(query: statusFilters.query, filters: statusFilters))
        XCTAssertNil(
            DiscoverExternalPlaceSearchPlanner.input(
                query: relationshipFilters.query,
                filters: relationshipFilters
            )
        )
    }

    func testExternalEligibilityRequiresProviderPlaceAndCategoryEvidence() {
        XCTAssertFalse(
            ExternalPlaceSearchEligibilityPolicy.allows(
                pointOfInterestCategory: nil,
                name: "123 Main Street",
                requestedCategory: WanderPlaceCategory.coffeeTeaSweets
            )
        )
        XCTAssertTrue(
            ExternalPlaceSearchEligibilityPolicy.allows(
                pointOfInterestCategory: .cafe,
                name: "Dayglow",
                requestedCategory: WanderPlaceCategory.coffeeTeaSweets
            )
        )
        XCTAssertFalse(
            ExternalPlaceSearchEligibilityPolicy.allows(
                pointOfInterestCategory: .park,
                name: "Echo Park Lake",
                requestedCategory: WanderPlaceCategory.coffeeTeaSweets
            )
        )
        XCTAssertTrue(
            ExternalPlaceSearchEligibilityPolicy.allows(
                pointOfInterestCategory: .park,
                name: "Echo Park Lake",
                requestedCategory: nil
            )
        )
    }

    func testDiscoverRankingLetsExactExternalPlaceBeatWeakTrustedMatch() throws {
        let trusted = makeVisiblePlace(
            id: "trusted-context",
            name: "Harbor House",
            note: "Dayglow was mentioned here"
        )
        let trustedGroups = VisiblePlaceGrouping.groups(
            from: [trusted],
            currentUserID: "viewer"
        )
        let exactExternal = makeCandidate("external-dayglow", name: "Dayglow")

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "Dayglow",
            filters: DiscoverFilters(query: "Dayglow"),
            trusted: trustedGroups,
            recme: [],
            external: [exactExternal]
        )

        guard case .external(let first) = try XCTUnwrap(ordered.first) else {
            return XCTFail("The exact outside place should outrank a contextual saved match.")
        }
        XCTAssertEqual(first.id, exactExternal.id)
    }

    func testDiscoverRankingKeepsEquallyRelevantTrustedPlaceFirst() throws {
        let trusted = makeVisiblePlace(id: "trusted-dayglow", name: "Dayglow")
        let trustedGroups = VisiblePlaceGrouping.groups(
            from: [trusted],
            currentUserID: "viewer"
        )
        let exactExternal = makeCandidate("external-dayglow", name: "Dayglow")

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "Dayglow",
            filters: DiscoverFilters(query: "Dayglow"),
            trusted: trustedGroups,
            recme: [],
            external: [exactExternal]
        )

        guard case .trusted(let first) = try XCTUnwrap(ordered.first) else {
            return XCTFail("Trust should break an equal-relevance tie.")
        }
        XCTAssertEqual(first.primary.id, trusted.id)
    }

    func testDiscoverCategoryRankingFillsAfterTrustedAndRecmeResults() {
        let trusted = makeVisiblePlace(
            id: "trusted-coffee",
            name: "Circuit",
            category: "Coffee shop"
        )
        let trustedGroups = VisiblePlaceGrouping.groups(
            from: [trusted],
            currentUserID: "viewer"
        )
        let recme = makeCandidate("recme-coffee", name: "Maru Coffee")
        let external = makeCandidate("external-coffee", name: "Dayglow")
        let filters = DiscoverFilters(
            query: "coffee",
            categories: [WanderPlaceCategory.coffeeTeaSweets]
        )

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: filters.query,
            filters: filters,
            trusted: trustedGroups,
            recme: [recme],
            external: [external]
        )

        XCTAssertEqual(
            ordered.map { candidate in
                switch candidate {
                case .trusted: "trusted"
                case .recme: "recme"
                case .external: "external"
                }
            },
            ["trusted", "recme", "external"]
        )
    }

    func testDiscoverRankingDeduplicatesPhysicalPlaceAcrossAllCorpora() {
        let trusted = makeVisiblePlace(
            id: "trusted-dayglow",
            name: "Dayglow",
            sourceProviderPlaceID: "shared-dayglow"
        )
        let trustedGroups = VisiblePlaceGrouping.groups(
            from: [trusted],
            currentUserID: "viewer"
        )
        let recme = makeCandidate("recme-dayglow", name: "Dayglow")
        let external = makeCandidate("external-dayglow", name: "Dayglow")
        let sharedRecme = PlaceCandidate(
            id: recme.id,
            name: recme.name,
            category: recme.category,
            latitude: recme.latitude,
            longitude: recme.longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "shared-dayglow",
            confidence: recme.confidence
        )
        let sharedExternal = PlaceCandidate(
            id: external.id,
            name: external.name,
            category: external.category,
            latitude: external.latitude,
            longitude: external.longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "shared-dayglow",
            confidence: external.confidence
        )

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "Dayglow",
            filters: DiscoverFilters(query: "Dayglow"),
            trusted: trustedGroups,
            recme: [sharedRecme],
            external: [sharedExternal]
        )

        XCTAssertEqual(ordered.count, 1)
        guard case .trusted = ordered[0] else {
            return XCTFail("The visible trusted save should own the deduplicated place.")
        }
    }

    func testDiscoverRankingDeduplicatesNearbySameNameWithoutSharedProviderID() {
        let recme = PlaceCandidate(
            id: "recme-dayglow",
            name: "Dayglow",
            category: "Coffee shop",
            latitude: 34,
            longitude: -118,
            sourceProvider: "google_places",
            sourceProviderPlaceID: "google-dayglow",
            confidence: 1
        )
        let external = PlaceCandidate(
            id: "external-dayglow",
            name: "Dayglow",
            category: "Coffee shop",
            latitude: 34.0005,
            longitude: -118.0005,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: nil,
            confidence: 1
        )

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "Dayglow",
            filters: DiscoverFilters(query: "Dayglow"),
            trusted: [],
            recme: [recme],
            external: [external]
        )

        XCTAssertEqual(ordered.count, 1)
        guard case .recme = ordered[0] else {
            return XCTFail("The rec.me row should own a nearby same-name duplicate.")
        }
    }

    func testDiscoverRankingKeepsSameNamePlacesOutsideCoordinateTolerance() {
        let recme = PlaceCandidate(
            id: "recme-dayglow",
            name: "Dayglow",
            category: "Coffee shop",
            latitude: 34,
            longitude: -118,
            sourceProvider: "google_places",
            sourceProviderPlaceID: "google-dayglow",
            confidence: 1
        )
        let external = PlaceCandidate(
            id: "external-dayglow",
            name: "Dayglow",
            category: "Coffee shop",
            latitude: 34.002,
            longitude: -118.002,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: nil,
            confidence: 1
        )

        let ordered = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "Dayglow",
            filters: DiscoverFilters(query: "Dayglow"),
            trusted: [],
            recme: [recme],
            external: [external]
        )

        XCTAssertEqual(ordered.count, 2)
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

    func testRefinedCommunityPlanCarriesCategoryAreaFavoriteAndScope() throws {
        let query = "friends favorite coffee in Pasadena"
        let initial = DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query, filters: DiscoverFilters(query: query)
        )
        let refined = try XCTUnwrap(DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query,
            filters: DiscoverFilters(
                query: query, categories: [WanderPlaceCategory.coffeeTeaSweets],
                area: "Pasadena", relationship: .mutual, opinion: .favorite
            )
        ))

        XCTAssertNotEqual(initial, refined)
        XCTAssertEqual(refined.categories, [WanderPlaceCategory.coffeeTeaSweets])
        XCTAssertEqual(refined.area, "Pasadena")
        XCTAssertEqual(refined.scope, .friends)
        XCTAssertTrue(refined.favoriteOnly)
        XCTAssertEqual(refined.semanticQuery, query)
        XCTAssertFalse(refined.query.contains("pasadena"))
    }

    func testRefinedCommunityPlanStopsWhenRemoteCannotEnforceOwnerOrRelationship() {
        let query = "coffee"
        XCTAssertNotNil(DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query, filters: DiscoverFilters(query: query)
        ))
        for filters in [
            DiscoverFilters(query: query, ownerQuery: "Ryan"),
            DiscoverFilters(query: query, relationship: .nonFollower)
        ] {
            XCTAssertNil(DiscoverRecmePlaceSearchPlanner.eligibleRequest(query: query, filters: filters))
        }
    }

    func testCommunityPlanDoesNotRestartForUnchangedRemoteConstraints() {
        let query = "quiet place to read"
        let initial = DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query, filters: DiscoverFilters(query: query)
        )
        let refined = DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query, filters: DiscoverFilters(query: query, sort: .ownerRatingDescending)
        )
        XCTAssertEqual(initial, refined)
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
            limit: 5,
            deliveryStage: .fused
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
        XCTAssertEqual(outcome.deliveryStage, .fused)
        XCTAssertEqual(RecmePlaceSearchOutcome.rankingPolicyVersion, "search_rrf_v1")
    }

    func testSemanticFailureLeavesLexicalOrderingUntouched() {
        let lexical = ["a", "b", "c"].map(makeCandidate)

        let outcome = RecmePlaceSearchFusion.outcome(
            lexical: lexical,
            semantic: [],
            semanticStatus: .failed,
            limit: 20,
            deliveryStage: .lexicalFinal
        )

        XCTAssertEqual(outcome.candidates.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(outcome.matches.map(\.providers), [[.lexical], [.lexical], [.lexical]])
        XCTAssertEqual(outcome.semanticStatus, .failed)
        XCTAssertEqual(outcome.deliveryStage, .lexicalFinal)
    }

    func testBackendPublishesLexicalResultsBeforeSlowSemanticFusion() async throws {
        let lexical = makeCandidate("lexical-first")
        let semantic = makeCandidate("semantic-later")
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .success([lexical]),
            semanticResult: .success([semantic]),
            waitsForSemanticRelease: true
        )
        let backend = WanderBackend(placeRepository: repository)
        var partialOutcomes: [RecmePlaceSearchOutcome] = []
        let lexicalPublished = expectation(description: "Lexical results publish")

        let finalTask = Task { @MainActor in
            try await backend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: "rainy coffee"),
                includesSemanticProvider: true
            ) {
                partialOutcomes.append($0)
                lexicalPublished.fulfill()
            }
        }

        await fulfillment(of: [lexicalPublished], timeout: 1)
        XCTAssertEqual(partialOutcomes.count, 1)
        XCTAssertEqual(partialOutcomes.first?.candidates.map(\.id), ["lexical-first"])
        XCTAssertEqual(partialOutcomes.first?.deliveryStage, .lexical)
        XCTAssertEqual(partialOutcomes.first?.semanticStatus, .pending)

        repository.releaseSemanticResults()
        let final = try await finalTask.value
        XCTAssertEqual(final.deliveryStage, .fused)
        XCTAssertEqual(Set(final.candidates.map(\.id)), ["lexical-first", "semantic-later"])
        XCTAssertNotNil(final.timings.lexical)
        XCTAssertNotNil(final.timings.semantic)
        XCTAssertNotNil(final.timings.fusion)
        XCTAssertNotNil(final.timings.total)
    }

    func testProgressiveRecmeResultsPreserveExternalCandidatesInCombinedRanking() async throws {
        let lexical = makeCandidate("lexical", name: "Coffee House")
        let semantic = makeCandidate("semantic", name: "Coffee Garden")
        let external = makeCandidate("external", name: "Coffee Corner")
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .success([lexical]),
            semanticResult: .success([semantic]),
            waitsForSemanticRelease: true
        )
        let backend = WanderBackend(placeRepository: repository)
        let published = expectation(description: "Partial three-corpus ranking")
        var partial: [DiscoverPlaceSearchCandidate] = []
        let task = Task { @MainActor in
            try await backend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: "coffee"),
                includesSemanticProvider: true
            ) { outcome in
                partial = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
                    query: "coffee", filters: DiscoverFilters(query: "coffee"),
                    trusted: [], recme: outcome.candidates, external: [external]
                )
                published.fulfill()
            }
        }
        await fulfillment(of: [published], timeout: 1)
        XCTAssertEqual(partial.count, 2)
        XCTAssertTrue(partial.contains { if case .external = $0 { return true }; return false })
        repository.releaseSemanticResults()
        let outcome = try await task.value
        let final = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: "coffee", filters: DiscoverFilters(query: "coffee"),
            trusted: [], recme: outcome.candidates, external: [external]
        )
        XCTAssertEqual(final.count, 3)
        XCTAssertTrue(final.contains { if case .external = $0 { return true }; return false })
    }

    func testCancelledSearchCannotReturnLateSemanticRefinement() async throws {
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .success([makeCandidate("old-lexical")]),
            semanticResult: .success([makeCandidate("old-semantic")]),
            waitsForSemanticRelease: true
        )
        let backend = WanderBackend(placeRepository: repository)
        let published = expectation(description: "Lexical published before cancellation")
        let task = Task { @MainActor in
            try await backend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: "old"), includesSemanticProvider: true
            ) { _ in published.fulfill() }
        }
        await fulfillment(of: [published], timeout: 1)
        task.cancel()
        repository.releaseSemanticResults()
        do {
            _ = try await task.value
            XCTFail("A cancelled request must not deliver a final result, even if its provider ignores cancellation.")
        } catch is CancellationError {
            // Expected: a late provider completion cannot refine a newer search.
        }
    }

    func testRefinedPlanForSameQueryCannotBeOverwrittenByCancelledCompletion() async throws {
        let query = "friends coffee"
        let oldRepository = SearchProviderPlaceRepository(
            lexicalResult: .success([makeCandidate("old-lexical")]),
            semanticResult: .success([makeCandidate("old-semantic")]),
            waitsForSemanticRelease: true
        )
        let oldBackend = WanderBackend(placeRepository: oldRepository)
        let partialPublished = expectation(description: "Initial plan published")
        var displayed: [String] = []
        let oldTask = Task { @MainActor in
            let outcome = try await oldBackend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: query), includesSemanticProvider: true
            ) { partial in
                displayed = partial.candidates.map(\.id)
                partialPublished.fulfill()
            }
            displayed = outcome.candidates.map(\.id)
        }
        await fulfillment(of: [partialPublished], timeout: 1)
        oldTask.cancel()
        displayed = []
        let refinedRequest = try XCTUnwrap(DiscoverRecmePlaceSearchPlanner.eligibleRequest(
            query: query,
            filters: DiscoverFilters(query: query, relationship: .mutual)
        ))
        let refinedBackend = WanderBackend(placeRepository: SearchProviderPlaceRepository(
            lexicalResult: .success([makeCandidate("refined-friend")]),
            semanticResult: .success([])
        ))
        let refined = try await refinedBackend.searchRecmePlaces(
            refinedRequest, includesSemanticProvider: true
        )
        displayed = refined.candidates.map(\.id)
        oldRepository.releaseSemanticResults()
        do {
            try await oldTask.value
            XCTFail("A previous plan for the same query must not publish a late completion.")
        } catch is CancellationError {
            // The superseded provider deliberately ignores cancellation until released.
        }
        XCTAssertEqual(displayed, ["refined-friend"])
    }

    func testControlledProgressiveDeliveryBenchmark() async throws {
        // Controlled provider delays isolate delivery behavior from live network variability.
        // Before REC-384, first remote delivery was at the final completion measured here.
        var firstSamples: [Double] = []
        var finalSamples: [Double] = []
        for _ in 0..<10 {
            let repository = SearchProviderPlaceRepository(
                lexicalResult: .success([makeCandidate("lexical")]),
                semanticResult: .success([makeCandidate("semantic")]),
                lexicalDelay: .milliseconds(40),
                semanticDelay: .milliseconds(400)
            )
            let backend = WanderBackend(placeRepository: repository)
            let clock = ContinuousClock()
            let start = clock.now
            var first: Double?
            let outcome = try await backend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: "quiet place to read"),
                includesSemanticProvider: true
            ) { partial in
                first = Self.milliseconds(start.duration(to: clock.now))
                XCTAssertEqual(partial.candidates.map(\.id), ["lexical"])
            }
            let final = Self.milliseconds(start.duration(to: clock.now))
            let firstValue = try XCTUnwrap(first)
            XCTAssertLessThan(firstValue, final)
            XCTAssertEqual(outcome.deliveryStage, .fused)
            firstSamples.append(firstValue)
            finalSamples.append(final)
        }
        let report: [String: Any] = [
            "kind": "controlled_provider_delays_not_live_network",
            "samples": 10, "lexical_delay_ms": 40, "semantic_delay_ms": 400,
            "first_remote_p50_ms": firstSamples.sorted()[4],
            "first_remote_p95_ms": firstSamples.sorted()[9],
            "await_both_first_remote_p50_ms": finalSamples.sorted()[4],
            "await_both_first_remote_p95_ms": finalSamples.sorted()[9]
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("[REC384DeliveryBenchmark] " + String(decoding: data, as: UTF8.self))
    }

    func testSemanticRefinementKeepsThreeCorpusOrderDeduplicationAndProvenance() async throws {
        let query = "quiet place to read"
        let trusted = makeVisiblePlace(id: "trusted", name: "Neighborhood Cafe")
        let groups = VisiblePlaceGrouping.groups(from: [trusted], currentUserID: "viewer")
        let lexical = makeCandidate("cedar", name: "Cedar")
        let shared = makeCandidate("harbor", name: "Harbor")
        let semantic = makeCandidate("rainroom", name: "Rainroom")
        let external = makeCandidate("mapkit", name: "Corner")
        let backend = WanderBackend(placeRepository: SearchProviderPlaceRepository(
            lexicalResult: .success([lexical, shared]),
            semanticResult: .success([shared, semantic])
        ))
        var partialIDs: [String] = []
        let outcome = try await backend.searchRecmePlaces(
            RecmePlaceSearchRequest(query: query), includesSemanticProvider: true
        ) { partial in
            partialIDs = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
                query: query, filters: DiscoverFilters(query: query),
                trusted: groups, recme: partial.candidates, external: [shared, external]
            ).map(\.id)
        }
        let final = DiscoverPlaceSearchRankingPolicy.orderedCandidates(
            query: query, filters: DiscoverFilters(query: query),
            trusted: groups, recme: outcome.candidates, external: [shared, external]
        )
        let trustedID = DiscoverPlaceSearchCandidate.trusted(groups[0]).id
        XCTAssertEqual(partialIDs, [trustedID, "recme|cedar", "recme|harbor", "external|mapkit"])
        XCTAssertEqual(final.map(\.id), [trustedID, "recme|harbor", "recme|cedar", "recme|rainroom", "external|mapkit"])
        XCTAssertEqual(outcome.matches.first?.providers, [.lexical, .semantic])
        XCTAssertEqual(outcome.matches.last?.providers, [.semantic])
        // None of the canonical names literally contains the query. Semantic results
        // survive final ranking, shared MapKit records collapse, and trusted ties win.
        print("[REC384QueryFixture] semantic refinement: trusted, Harbor (both), Cedar (lexical), Rainroom (semantic), Corner (MapKit); shared Harbor deduplicated")
    }

    func testBackendKeepsLexicalFinalWhenSemanticProviderReturnsNoCandidates() async throws {
        let lexical = makeCandidate("lexical-only")
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .success([lexical]),
            semanticResult: .success([])
        )
        let backend = WanderBackend(placeRepository: repository)

        let outcome = try await backend.searchRecmePlaces(
            RecmePlaceSearchRequest(query: "exact business name"),
            includesSemanticProvider: true
        )

        XCTAssertEqual(outcome.candidates.map(\.id), ["lexical-only"])
        XCTAssertEqual(outcome.semanticStatus, .succeeded)
        XCTAssertEqual(outcome.deliveryStage, .lexicalFinal)
    }

    func testLexicalFailureAndEmptySemanticResponseRemainAnHonestFailure() async throws {
        let backend = WanderBackend(placeRepository: SearchProviderPlaceRepository(
            lexicalResult: .failure(SearchProviderTestError.expected),
            semanticResult: .success([])
        ))
        do {
            _ = try await backend.searchRecmePlaces(
                RecmePlaceSearchRequest(query: "coffee"), includesSemanticProvider: true
            )
            XCTFail("An empty semantic response cannot recover a failed lexical request.")
        } catch SearchProviderTestError.expected {
            // Preserve the failed-source UI instead of claiming a successful empty search.
        }
    }

    func testBackendUsesSemanticRecoveryWhenLexicalProviderReturnsNoCandidates() async throws {
        let semantic = makeCandidate("semantic-only")
        let repository = SearchProviderPlaceRepository(
            lexicalResult: .success([]),
            semanticResult: .success([semantic])
        )
        let backend = WanderBackend(placeRepository: repository)

        let outcome = try await backend.searchRecmePlaces(
            RecmePlaceSearchRequest(query: "cozy rainy coffee"),
            includesSemanticProvider: true
        )

        XCTAssertEqual(outcome.candidates.map(\.id), ["semantic-only"])
        XCTAssertEqual(outcome.deliveryStage, .semanticRecovery)
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
        XCTAssertEqual(outcome.deliveryStage, .semanticRecovery)
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
    let waitsForSemanticRelease: Bool
    let lexicalDelay: Duration
    let semanticDelay: Duration
    private(set) var lexicalRequestCount = 0
    private(set) var semanticRequestCount = 0
    private var semanticReleaseContinuation: CheckedContinuation<Void, Never>?
    private var semanticReleaseRequested = false

    init(
        lexicalResult: Result<[PlaceCandidate], Error>,
        semanticResult: Result<[PlaceCandidate], Error>,
        waitsForSemanticRelease: Bool = false,
        lexicalDelay: Duration = .zero,
        semanticDelay: Duration = .zero
    ) {
        self.lexicalResult = lexicalResult
        self.semanticResult = semanticResult
        self.waitsForSemanticRelease = waitsForSemanticRelease
        self.lexicalDelay = lexicalDelay
        self.semanticDelay = semanticDelay
    }

    func places(in viewport: MapViewport) async throws -> [VisiblePlace] { [] }

    func searchRecmePlaces(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        lexicalRequestCount += 1
        if lexicalDelay > .zero { try await Task.sleep(for: lexicalDelay) }
        return try lexicalResult.get()
    }

    func searchRecmePlacesSemantic(_ request: RecmePlaceSearchRequest) async throws -> [PlaceCandidate] {
        semanticRequestCount += 1
        if semanticDelay > .zero { try await Task.sleep(for: semanticDelay) }
        if waitsForSemanticRelease, !semanticReleaseRequested {
            await withCheckedContinuation { continuation in
                if semanticReleaseRequested {
                    continuation.resume()
                } else {
                    semanticReleaseContinuation = continuation
                }
            }
        }
        return try semanticResult.get()
    }

    func releaseSemanticResults() {
        semanticReleaseRequested = true
        semanticReleaseContinuation?.resume()
        semanticReleaseContinuation = nil
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] { [] }
    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] { [] }
}
