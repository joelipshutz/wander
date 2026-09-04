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
