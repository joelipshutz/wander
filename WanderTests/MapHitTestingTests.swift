import CoreGraphics
import MapKit
import SwiftUI
import XCTest
@testable import Wander

final class MapHitTestingTests: XCTestCase {
    func testInitialMapLoadingPolicyPreventsFlashesAndSupportsDeterministicUITests() {
        XCTAssertEqual(
            MapInitialLoadingPolicy.minimumVisibleInterval(arguments: []),
            0.35,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MapInitialLoadingPolicy.minimumVisibleInterval(
                arguments: [
                    "Wander",
                    MapInitialLoadingPolicy.testDelayArgument,
                    "1750"
                ]
            ),
            1.75,
            accuracy: 0.001
        )
        for invalidArguments in [
            ["Wander", MapInitialLoadingPolicy.testDelayArgument],
            ["Wander", MapInitialLoadingPolicy.testDelayArgument, "invalid"],
            ["Wander", MapInitialLoadingPolicy.testDelayArgument, "nan"],
            ["Wander", MapInitialLoadingPolicy.testDelayArgument, "inf"],
            ["Wander", MapInitialLoadingPolicy.testDelayArgument, "-1"],
            ["Wander", MapInitialLoadingPolicy.testDelayArgument, "0"]
        ] {
            XCTAssertEqual(
                MapInitialLoadingPolicy.minimumVisibleInterval(arguments: invalidArguments),
                0.35,
                accuracy: 0.001
            )
        }
        XCTAssertEqual(
            MapInitialLoadingPolicy.remainingVisibleInterval(
                elapsed: 0.2,
                minimumVisibleInterval: 0.35
            ),
            0.15,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MapInitialLoadingPolicy.remainingVisibleInterval(
                elapsed: 1,
                minimumVisibleInterval: 0.35
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MapInitialLoadingPolicy.remainingVisibleInterval(
                elapsed: -1,
                minimumVisibleInterval: 0.35
            ),
            0.35,
            accuracy: 0.001
        )
        XCTAssertEqual(MapInitialLoadingPolicy.postRevealHydrationDelay, 0.25, accuracy: 0.001)
        XCTAssertEqual(
            MapInitialLoadingPolicy.refreshStallInterval(arguments: []),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MapInitialLoadingPolicy.refreshStallInterval(
                arguments: [
                    "Wander",
                    MapInitialLoadingPolicy.testRefreshStallArgument,
                    "30000"
                ]
            ),
            30,
            accuracy: 0.001
        )
    }

    func testMapChromeContentWidthPreservesInsetsAcrossPhoneSizesAndSafeAreas() {
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 430,
                safeAreaInsets: EdgeInsets()
            ),
            406
        )
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 320,
                safeAreaInsets: EdgeInsets()
            ),
            296
        )
        XCTAssertEqual(
            MapChromeLayout.contentWidth(
                containerWidth: 844,
                safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 0, trailing: 59)
            ),
            702
        )
    }

    @MainActor
    func testRenderProjectionCacheReusesStableInputsAndRebuildsAfterChange() {
        let cache = MapRenderProjectionCache<String, Int>()
        var builds = 0

        let first = cache.value(for: "stable") {
            builds += 1
            return 41
        }
        let second = cache.value(for: "stable") {
            builds += 1
            return 99
        }
        let changed = cache.value(for: "changed") {
            builds += 1
            return 42
        }
        let warmRevisit = cache.value(for: "stable") {
            builds += 1
            return 100
        }

        XCTAssertEqual(first, 41)
        XCTAssertEqual(second, 41)
        XCTAssertEqual(changed, 42)
        XCTAssertEqual(warmRevisit, 41)
        XCTAssertEqual(builds, 2)
        XCTAssertEqual(cache.buildCount, 2)
    }

    @MainActor
    func testRenderProjectionCacheKeepsEachMapSourceWarmAcrossFeaturedPans() {
        let cache = MapRenderProjectionCache<String, Int>(capacity: 2)
        var builds = 0

        func value(_ key: String, source: String) -> Int {
            cache.value(for: key, partition: source) {
                builds += 1
                return builds
            }
        }

        _ = value("featured-region-1", source: "featured")
        let friends = value("friends", source: "friends")
        let you = value("you", source: "you")
        _ = value("featured-region-2", source: "featured")
        _ = value("featured-region-3", source: "featured")

        XCTAssertEqual(value("friends", source: "friends"), friends)
        XCTAssertEqual(value("you", source: "you"), you)
        XCTAssertEqual(builds, 5)
        XCTAssertEqual(cache.buildCount, 5)
    }

    func testScreenPointWithinMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertTrue(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 146, y: 260),
                nearAny: [marker]
            )
        )
    }

    func testScreenPointOutsideMarkerRadius() {
        let marker = CGPoint(x: 120, y: 240)

        XCTAssertFalse(
            MapHitTesting.isScreenPoint(
                CGPoint(x: 190, y: 260),
                nearAny: [marker]
            )
        )
    }

    func testColocatedMarkersCyclePastTheCurrentSelection() {
        XCTAssertEqual(
            MapHitTesting.nextColocatedMarkerID(
                selectedID: "place-b",
                candidateIDs: ["place-c", "place-a", "place-b"]
            ),
            "place-c"
        )
        XCTAssertEqual(
            MapHitTesting.nextColocatedMarkerID(
                selectedID: "place-c",
                candidateIDs: ["place-c", "place-a", "place-b"]
            ),
            "place-a"
        )
        XCTAssertNil(
            MapHitTesting.nextColocatedMarkerID(
                selectedID: "place-a",
                candidateIDs: ["place-a"]
            )
        )
    }

    func testSearchRankingUsesMapCenterWhileDistanceUsesCachedViewerLocation() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        let viewerLocation = CLLocation(latitude: 40.71, longitude: -74.01)

        let rankingOrigin = MapSearchPerformancePolicy.rankingOrigin(mapRegion: region)
        let cachedDistanceOrigin = MapSearchPerformancePolicy.distanceOrigin(
            viewerLocation: viewerLocation,
            mapRegion: region
        )
        let fallbackDistanceOrigin = MapSearchPerformancePolicy.distanceOrigin(
            viewerLocation: nil,
            mapRegion: region
        )

        XCTAssertEqual(rankingOrigin.coordinate.latitude, region.center.latitude)
        XCTAssertEqual(rankingOrigin.coordinate.longitude, region.center.longitude)
        XCTAssertEqual(
            cachedDistanceOrigin.coordinate.latitude,
            viewerLocation.coordinate.latitude
        )
        XCTAssertEqual(
            cachedDistanceOrigin.coordinate.longitude,
            viewerLocation.coordinate.longitude
        )
        XCTAssertEqual(fallbackDistanceOrigin.coordinate.latitude, region.center.latitude)
        XCTAssertEqual(fallbackDistanceOrigin.coordinate.longitude, region.center.longitude)
    }

    func testMapSearchRetriesWithDistinctiveQueryWhenPrimaryResultsMissTheBusinessName() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("MapSearchQueryPolicy.fallbackQuery("))
    }

    func testMapSearchQueryPolicyUsesDistinctiveTokenAfterUnrelatedFuzzyResult() {
        XCTAssertEqual(
            MapSearchQueryPolicy.fallbackQuery(
                for: "So Sentimental",
                primaryResultNames: ["Sorento"]
            ),
            "Sentimental"
        )
        XCTAssertEqual(
            MapSearchQueryPolicy.lexicalScore(
                forName: "So Sentimental",
                query: "So Sentimental"
            ),
            1_000
        )
        XCTAssertEqual(
            MapSearchQueryPolicy.lexicalScore(
                forName: "Sorento",
                query: "So Sentimental"
            ),
            0
        )
    }

    func testMapSearchQueryPolicyKeepsStrongPrimaryAndSingleWordSearchesUnchanged() {
        XCTAssertNil(
            MapSearchQueryPolicy.fallbackQuery(
                for: "So Sentimental",
                primaryResultNames: ["So Sentimental Coffee"]
            )
        )
        XCTAssertNil(
            MapSearchQueryPolicy.fallbackQuery(
                for: "Sentimental",
                primaryResultNames: ["Sorento"]
            )
        )
    }

    func testMapSearchQueryPolicyNormalizesPunctuationAndDiacritics() {
        XCTAssertEqual(
            MapSearchQueryPolicy.lexicalScore(
                forName: "J’s Kitchen Café",
                query: "j's kitchen cafe"
            ),
            1_000
        )
    }

    func testMapSearchQueryPolicyRecoversNamedPlacesButNeverGlobalizesCategories() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
        )

        XCTAssertFalse(
            MapSearchQueryPolicy.shouldRecoverBeyondRegion(
                for: "So Sentimental",
                evidence: [
                    MapSearchQueryPolicy.ResultEvidence(
                        name: "So Sentimental",
                        distanceFromSearchCenter: 40_000,
                        pointOfInterestCategory: .cafe
                    )
                ],
                searchRegion: region
            )
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.shouldRecoverBeyondRegion(
                for: "The Salty Donut",
                evidence: [
                    MapSearchQueryPolicy.ResultEvidence(
                        name: "The Salty Donut",
                        distanceFromSearchCenter: 3_400_000,
                        pointOfInterestCategory: .cafe
                    )
                ],
                searchRegion: region
            )
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.shouldRecoverBeyondRegion(
                for: "The Grey",
                evidence: [
                    MapSearchQueryPolicy.ResultEvidence(
                        name: "The Greek Theatre",
                        distanceFromSearchCenter: 5_000,
                        pointOfInterestCategory: .theater
                    )
                ],
                searchRegion: region
            )
        )
        XCTAssertTrue(
            MapSearchQueryPolicy.shouldRecoverBeyondRegion(
                for: "Sentimental",
                evidence: [],
                searchRegion: region
            )
        )
        XCTAssertFalse(
            MapSearchQueryPolicy.shouldRecoverBeyondRegion(
                for: "coffee near me",
                evidence: [],
                searchRegion: region
            )
        )
    }

    func testMapSearchQueryPolicyClassifiesGenericCategoryPhrasesWithoutMistakingNames() {
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "coffee"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "coffee shops near me"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "nearby ramen"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "best coffee"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "quiet cafes"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "coffee in Pasadena"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "best coffee in Pasadena"), .category)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "Dayglow"), .namedPlace)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "Coffee Commissary"), .namedPlace)
        XCTAssertEqual(MapSearchQueryPolicy.intent(for: "Blue Bottle Coffee"), .namedPlace)
    }

    func testCategoryProviderRankingIsDistanceFirstWhileNamedPlacesStayLexical() {
        let nearbyCategoryScore = MapProviderSearchRankingPolicy.score(
            name: "Dayglow",
            query: "coffee",
            isPointOfInterest: true,
            distanceMeters: 800
        )
        let distantLexicalCategoryScore = MapProviderSearchRankingPolicy.score(
            name: "Coffee Commissary",
            query: "coffee",
            isPointOfInterest: true,
            distanceMeters: 30_000
        )
        XCTAssertGreaterThan(nearbyCategoryScore, distantLexicalCategoryScore)

        let exactNamedScore = MapProviderSearchRankingPolicy.score(
            name: "Coffee Commissary",
            query: "Coffee Commissary",
            isPointOfInterest: true,
            distanceMeters: 30_000
        )
        let unrelatedNearbyScore = MapProviderSearchRankingPolicy.score(
            name: "Dayglow",
            query: "Coffee Commissary",
            isPointOfInterest: true,
            distanceMeters: 800
        )
        XCTAssertGreaterThan(exactNamedScore, unrelatedNearbyScore)
    }

    func testAdaptiveSearchStartsAtViewportRadiusAndStopsAtRegionalCap() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        let viewportRadius = MapAdaptiveSearchPolicy.viewportRadius(for: region)
        let radii = MapAdaptiveSearchPolicy.radii(for: region)

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(radii.first), viewportRadius)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(radii.first),
            MapAdaptiveSearchPolicy.minimumInitialRadius
        )
        XCTAssertEqual(radii.last, MapAdaptiveSearchPolicy.regionalRadiusCap)
        XCTAssertLessThanOrEqual(radii.count, MapAdaptiveSearchPolicy.maximumPassCount)
        XCTAssertEqual(radii, radii.sorted())
    }

    func testAdaptiveSearchKeepsAnAlreadyWideViewportAsItsOnlyRequiredRadius() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
            span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
        )
        let radii = MapAdaptiveSearchPolicy.radii(for: region)

        XCTAssertEqual(radii.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(radii.first),
            MapAdaptiveSearchPolicy.viewportRadius(for: region),
            accuracy: 1
        )
    }

    func testAdaptiveSearchRejectsProviderResultsOutsideRequestedRadius() {
        let center = CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285)

        XCTAssertTrue(
            MapAdaptiveSearchPolicy.contains(
                CLLocationCoordinate2D(latitude: 34.08, longitude: -118.28),
                center: center,
                radius: 2_000
            )
        )
        XCTAssertFalse(
            MapAdaptiveSearchPolicy.contains(
                CLLocationCoordinate2D(latitude: 34.1478, longitude: -118.1445),
                center: center,
                radius: 2_000
            )
        )
    }

    func testAdaptiveSearchDeduplicatesProviderResultsAcrossRadiusPasses() {
        var deduper = MapProviderResultDeduper()

        XCTAssertEqual(
            deduper.appendUnique(["dayglow", "dayglow", "jones"]) { $0 },
            ["dayglow", "jones"]
        )
        XCTAssertEqual(
            deduper.appendUnique(["jones", "maru"]) { $0 },
            ["maru"]
        )
    }

    func testExternalMapSearchCandidatesAllowAllAndCategoryORRefinements() {
        let coffee = PlaceCandidate(
            id: "coffee",
            name: "Coffee",
            category: "Cafe",
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            latitude: 34.05,
            longitude: -118.25,
            confidence: 1
        )
        let park = PlaceCandidate(
            id: "park",
            name: "Park",
            category: "Park",
            primaryCategory: WanderPlaceCategory.outdoorsNature,
            latitude: 34.06,
            longitude: -118.26,
            confidence: 1
        )
        let shop = PlaceCandidate(
            id: "shop",
            name: "Shop",
            category: "Store",
            primaryCategory: WanderPlaceCategory.shopping,
            latitude: 34.07,
            longitude: -118.27,
            confidence: 1
        )

        let all = MapMoreFilterSelection()
        XCTAssertTrue(MapSearchExternalCandidatePolicy.allowsAnyExternalResults(refinements: all))
        XCTAssertTrue(MapSearchExternalCandidatePolicy.allows(coffee, refinements: all))

        let coffeeOrOutdoors = MapMoreFilterSelection(
            categories: [
                WanderPlaceCategory.coffeeTeaSweets,
                WanderPlaceCategory.outdoorsNature
            ]
        )
        XCTAssertTrue(
            MapSearchExternalCandidatePolicy.allows(coffee, refinements: coffeeOrOutdoors)
        )
        XCTAssertTrue(
            MapSearchExternalCandidatePolicy.allows(park, refinements: coffeeOrOutdoors)
        )
        XCTAssertFalse(
            MapSearchExternalCandidatePolicy.allows(shop, refinements: coffeeOrOutdoors)
        )
    }

    func testExternalMapSearchCandidatesAreExcludedByPeopleRefinements() {
        let candidate = PlaceCandidate(
            id: "coffee",
            name: "Coffee",
            category: "Cafe",
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            latitude: 34.05,
            longitude: -118.25,
            confidence: 1
        )
        let people = MapMoreFilterSelection(people: ["user-1"])

        XCTAssertFalse(
            MapSearchExternalCandidatePolicy.allowsAnyExternalResults(refinements: people)
        )
        XCTAssertFalse(MapSearchExternalCandidatePolicy.allows(candidate, refinements: people))
    }

    func testExternalMapSearchCandidatesAreExcludedByStatusRefinements() {
        let candidate = PlaceCandidate(
            id: "coffee",
            name: "Coffee",
            category: "Cafe",
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            latitude: 34.05,
            longitude: -118.25,
            confidence: 1
        )

        for status in [MapStatusFilter.checkIns, .wanna] {
            let refinements = MapMoreFilterSelection(status: status)
            XCTAssertFalse(
                MapSearchExternalCandidatePolicy.allowsAnyExternalResults(
                    refinements: refinements
                )
            )
            XCTAssertFalse(
                MapSearchExternalCandidatePolicy.allows(candidate, refinements: refinements)
            )
        }
    }

    func testMapSearchQueryPolicyCapsProviderDerivedCategoryFallbacksAtThree() {
        let evidence = [
            MapSearchQueryPolicy.ResultEvidence(
                name: "Birdy Grey",
                distanceFromSearchCenter: 1_000,
                pointOfInterestCategory: .store
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "Earley Grey Tearoom",
                distanceFromSearchCenter: 2_000,
                pointOfInterestCategory: .restaurant
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "Gray Fashion",
                distanceFromSearchCenter: 3_000,
                pointOfInterestCategory: .store
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "Grey Studio",
                distanceFromSearchCenter: 4_000,
                pointOfInterestCategory: .museum
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "The Gray Zebra",
                distanceFromSearchCenter: 5_000,
                pointOfInterestCategory: .restaurant
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "Violet Grey",
                distanceFromSearchCenter: 6_000,
                pointOfInterestCategory: .store
            ),
            MapSearchQueryPolicy.ResultEvidence(
                name: "Grey Matter",
                distanceFromSearchCenter: 7_000,
                pointOfInterestCategory: .museum
            )
        ]

        XCTAssertEqual(
            MapSearchQueryPolicy.preferredCategoryFallbacks(from: evidence),
            [.store, .restaurant, .museum]
        )
    }

    func testMapSearchBroaderRecoveryStaysLexicalAndPreservesCompletionBranches() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("MapSearchQueryPolicy.shouldRecoverBeyondRegion("))
        XCTAssertTrue(map.contains("region: nil"))
        XCTAssertTrue(map.contains("MapSearchQueryPolicy.preferredCategoryFallbacks("))
        XCTAssertTrue(map.contains("MapSearchCompletionCollector"))
        XCTAssertTrue(map.contains("MapSearchQueryPolicy.lexicalScore("))
    }

    func testMapSearchResultIdentityKeepsSameNamedLocationsSeparate() {
        let downtown = MapSearchResultIdentity.locationKey(
            name: "Sonoratown",
            latitude: 34.04446,
            longitude: -118.25231
        )
        let midCity = MapSearchResultIdentity.locationKey(
            name: "Sonoratown",
            latitude: 34.03792,
            longitude: -118.34510
        )

        XCTAssertNotEqual(downtown, midCity)
        XCTAssertEqual(
            downtown,
            MapSearchResultIdentity.locationKey(
                name: "Sonoratown",
                latitude: 34.04446,
                longitude: -118.25231
            )
        )
    }

    func testMapSearchTypeaheadCapturesAndValidatesRefinementsWithQueryMatchedDedupe() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let scheduleStart = try XCTUnwrap(map.range(of: "private func scheduleTypeahead(for query: String)"))
        let scheduleEnd = try XCTUnwrap(
            map.range(
                of: "private func selectTypeaheadSuggestion(",
                range: scheduleStart.upperBound..<map.endIndex
            )
        )
        let schedule = map[scheduleStart.lowerBound..<scheduleEnd.lowerBound]

        XCTAssertTrue(schedule.contains("let refinements = mapFilterState.more"))
        XCTAssertTrue(schedule.contains("authorizationContext"))
        XCTAssertTrue(schedule.contains("savedCandidates: savedCandidates"))
        XCTAssertTrue(schedule.contains("refinements: refinements"))
        XCTAssertTrue(schedule.contains("mapFilterState.more == refinements"))
        XCTAssertTrue(
            schedule.contains("!MapSearchCandidatePolicy.contains($0, in: savedCandidates)")
        )
        XCTAssertTrue(schedule.contains("MapSearchCandidatePolicy.orderedCandidates("))
        XCTAssertTrue(schedule.contains("let searchRegion = currentSearchRegion"))
        XCTAssertTrue(schedule.contains("searchRegion: searchRegion"))
        XCTAssertFalse(schedule.contains("isAlreadyInMapSearchCorpus"))
        XCTAssertFalse(schedule.contains("position ="))
        XCTAssertFalse(schedule.contains("centerSearchSelection("))
        XCTAssertFalse(schedule.contains("seenTitles"))
    }

    func testMapSearchTypeaheadEditsClearPreviewWithoutImplicitSelection() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let queryChangeStart = try XCTUnwrap(
            map.range(of: ".onChange(of: mapQuery) { _, _ in")
        )
        let queryChangeEnd = try XCTUnwrap(
            map.range(
                of: ".onChange(of: walkthroughs.currentStep?.target",
                range: queryChangeStart.upperBound..<map.endIndex
            )
        )
        let queryChange = map[queryChangeStart.lowerBound..<queryChangeEnd.lowerBound]

        XCTAssertTrue(queryChange.contains("handleMapQueryChange()"))
        XCTAssertFalse(queryChange.contains("visiblePlaceGroupKeys.first"))
        XCTAssertFalse(queryChange.contains("selectedPlaceGroupKey ="))

        let previewClearStart = try XCTUnwrap(
            map.range(of: "private func clearMapSearchPreviewForEditing()")
        )
        let previewClearEnd = try XCTUnwrap(
            map.range(
                of: "private func clearMapSearchPreview()",
                range: previewClearStart.upperBound..<map.endIndex
            )
        )
        let previewClear = map[previewClearStart.lowerBound..<previewClearEnd.lowerBound]

        XCTAssertTrue(
            previewClear.contains("invalidateDeferredMapNavigationForUserInteraction()")
        )
        XCTAssertTrue(previewClear.contains("mapSearchSelectionSession.suppressPreviewForEditing()"))
        XCTAssertTrue(previewClear.contains("didDismissInitialPlaceRoute = true"))
        XCTAssertTrue(previewClear.contains("clearMapSearchPreview()"))
        XCTAssertFalse(previewClear.contains("routedVisiblePlace = nil"))

        let commonClearStart = previewClearEnd
        let commonClearEnd = try XCTUnwrap(
            map.range(
                of: "private func clearNativeMapFeatureSelection()",
                range: commonClearStart.upperBound..<map.endIndex
            )
        )
        let commonClear = map[commonClearStart.lowerBound..<commonClearEnd.lowerBound]
        XCTAssertTrue(commonClear.contains("invalidateMapSearchRequest()"))
        XCTAssertTrue(commonClear.contains("selectedPlaceGroupKey = nil"))
        XCTAssertTrue(commonClear.contains("selectedSearchCandidateID = nil"))
        XCTAssertTrue(commonClear.contains("mapSearchCandidates = []"))
        XCTAssertTrue(commonClear.contains("submittedSavedSearchGroups = []"))
        XCTAssertTrue(commonClear.contains("resetCompactCardPresentation()"))
        XCTAssertFalse(commonClear.contains("routedVisiblePlace = nil"))

        let authorizationStart = try XCTUnwrap(
            map.range(of: "private func handleMapSearchAuthorizationChange()")
        )
        let authorizationEnd = try XCTUnwrap(
            map.range(
                of: "private func orderedVisiblePlaceGroups()",
                range: authorizationStart.upperBound..<map.endIndex
            )
        )
        let authorization = map[authorizationStart.lowerBound..<authorizationEnd.lowerBound]
        XCTAssertTrue(
            authorization.contains("mapSearchSelectionSession.isPreviewSuppressed")
        )

        let searchBarCallStart = try XCTUnwrap(map.range(of: "SearchBar("))
        let searchBarCallEnd = try XCTUnwrap(
            map.range(
                of: ".walkthroughTarget(",
                range: searchBarCallStart.upperBound..<map.endIndex
            )
        )
        let searchBarCall = map[searchBarCallStart.lowerBound..<searchBarCallEnd.lowerBound]
        XCTAssertTrue(
            searchBarCall.contains("onQueryEdited: clearMapSearchPreviewForEditing")
        )
        XCTAssertTrue(searchBarCall.contains("onClear: clearMapSelectionAndSearch"))

        let searchBar = try XCTUnwrap(
            map.components(separatedBy: "private struct SearchBar: View {").last?
                .components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier").first
        )
        XCTAssertTrue(searchBar.contains("onQueryEdited()"))
        XCTAssertTrue(searchBar.contains("draftQuery = \"\"\n                    onClear()"))
        XCTAssertTrue(searchBar.contains(".accessibilityIdentifier(\"map.searchClear\")"))
        XCTAssertTrue(searchBar.contains(".onChange(of: isFocused.wrappedValue)"))
        XCTAssertTrue(searchBar.contains("cancelPendingQueryCommitAndSyncDraft()"))
        XCTAssertTrue(searchBar.contains("queryCommitTask?.cancel()"))
        XCTAssertTrue(searchBar.contains("draftQuery = query"))

        let initialSelectionStart = try XCTUnwrap(
            map.range(of: "private func resolveInitialSelection()")
        )
        let initialSelectionEnd = try XCTUnwrap(
            map.range(
                of: "private func refreshInitialMapSources()",
                range: initialSelectionStart.upperBound..<map.endIndex
            )
        )
        let initialSelection = map[
            initialSelectionStart.lowerBound..<initialSelectionEnd.lowerBound
        ]
        XCTAssertTrue(initialSelection.contains("guard !didDismissInitialPlaceRoute"))

        let fullClearStart = try XCTUnwrap(
            map.range(of: "private func clearMapSelectionAndSearch()")
        )
        let fullClearEnd = try XCTUnwrap(
            map.range(
                of: "private func clearMapSearchPreviewForEditing()",
                range: fullClearStart.upperBound..<map.endIndex
            )
        )
        let fullClear = map[fullClearStart.lowerBound..<fullClearEnd.lowerBound]
        XCTAssertTrue(fullClear.contains("didDismissInitialPlaceRoute = true"))
    }

    func testAsyncMapRoutesCheckUserIntentAfterAwaitBeforeMutatingSelection() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let notificationStart = try XCTUnwrap(
            map.range(of: "private func openNotificationPlace(")
        )
        let notificationEnd = try XCTUnwrap(
            map.range(
                of: "private func centerMap(latitude:",
                range: notificationStart.upperBound..<map.endIndex
            )
        )
        let notificationRoute = String(
            map[notificationStart.lowerBound..<notificationEnd.lowerBound]
        )
        XCTAssertTrue(notificationRoute.contains("await store.refreshRemoteSocialSurfaces"))
        XCTAssertTrue(notificationRoute.contains("try await backend.sharedPlace"))
        XCTAssertGreaterThanOrEqual(
            notificationRoute.components(separatedBy: "canApplyDeferredMapNavigation(").count,
            4
        )

        let launchStart = try XCTUnwrap(
            map.range(of: "private func handleMapSearchLaunchRequest(")
        )
        let launchEnd = try XCTUnwrap(
            map.range(
                of: "private func runMapSearch(",
                range: launchStart.upperBound..<map.endIndex
            )
        )
        let launchRoute = map[launchStart.lowerBound..<launchEnd.lowerBound]
        XCTAssertTrue(launchRoute.contains("await centerMapOnCurrentCityIfNeeded()"))
        XCTAssertTrue(launchRoute.contains("deferredMapNavigationGate.allows("))

        let invalidationStart = try XCTUnwrap(
            map.range(of: "private func invalidateDeferredMapNavigationForUserInteraction()")
        )
        let invalidationEnd = try XCTUnwrap(
            map.range(
                of: "private func resolveSharedVisitDestinationWithRetry(",
                range: invalidationStart.upperBound..<map.endIndex
            )
        )
        let invalidation = map[invalidationStart.lowerBound..<invalidationEnd.lowerBound]
        XCTAssertTrue(invalidation.contains("deferredMapNavigationGate.invalidate()"))
        XCTAssertTrue(invalidation.contains("didResolveInitialCamera = true"))
        XCTAssertTrue(invalidation.contains("case .place, .sharedVisit:"))

        for userIntentHandler in [
            "private func clearMapSearchPreviewForEditing()",
            "private func clearSearchTextForMapInteraction()",
            "private func submitMapSearch(_ requestedQuery: String)",
            "private func cancelMapSearch()",
            "private func selectTypeaheadSuggestion(_ suggestion: MapSearchSuggestion)",
        ] {
            let handlerStart = try XCTUnwrap(map.range(of: userIntentHandler))
            let handlerPrefix = map[handlerStart.lowerBound...].prefix(500)
            XCTAssertTrue(
                handlerPrefix.contains("invalidateDeferredMapNavigationForUserInteraction()"),
                "Expected \(userIntentHandler) to supersede deferred map navigation"
            )
        }
    }

    func testMoreRefinementChangeInvalidatesClearsAndRerunsOriginalSubmittedRegion() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let changeStart = try XCTUnwrap(
            map.range(of: "private func handleMapSearchRefinementChange()")
        )
        let changeEnd = try XCTUnwrap(
            map.range(
                of: "private func orderedVisiblePlaceGroups()",
                range: changeStart.upperBound..<map.endIndex
            )
        )
        let change = map[changeStart.lowerBound..<changeEnd.lowerBound]

        let moreChangeStart = try XCTUnwrap(
            map.range(of: ".onChange(of: mapFilterState.more) { _, _ in")
        )
        let moreChangeEnd = try XCTUnwrap(
            map.range(
                of: ".onChange(of: isPlaceProfilePresented)",
                range: moreChangeStart.upperBound..<map.endIndex
            )
        )
        let moreChange = map[moreChangeStart.lowerBound..<moreChangeEnd.lowerBound]
        XCTAssertTrue(moreChange.contains("handleMapSearchRefinementChange()"))
        XCTAssertTrue(change.contains("let submittedContext = mapSearchSubmissionContext"))
        XCTAssertTrue(change.contains("invalidateMapSearchRequest()"))
        XCTAssertTrue(change.contains("typeaheadTask?.cancel()"))
        XCTAssertTrue(change.contains("typeaheadSuggestions = []"))
        XCTAssertTrue(change.contains("mapSearchCandidates = []"))
        XCTAssertTrue(change.contains("submittedSavedSearchGroups = []"))
        XCTAssertTrue(change.contains("selectedPlaceGroupKey = nil"))
        XCTAssertTrue(change.contains("selectedSearchCandidateID = nil"))
        XCTAssertTrue(change.contains("mapSearchMessage = nil"))
        XCTAssertTrue(change.contains("startSubmittedMapSearch("))
        XCTAssertTrue(change.contains("searchRegion: submittedContext.region"))
        XCTAssertFalse(change.contains("searchRegion: currentSearchRegion"))
        XCTAssertTrue(change.contains("scheduleTypeahead(for: mapQuery)"))
        XCTAssertLessThan(
            try XCTUnwrap(
                change.range(of: "let submittedContext = mapSearchSubmissionContext")
            ).lowerBound,
            try XCTUnwrap(change.range(of: "invalidateMapSearchRequest()")).lowerBound
        )
        XCTAssertLessThan(
            try XCTUnwrap(change.range(of: "mapSearchCandidates = []")).lowerBound,
            try XCTUnwrap(change.range(of: "startSubmittedMapSearch(")).lowerBound
        )

        let submissionStart = try XCTUnwrap(
            map.range(of: "private func startSubmittedMapSearch(")
        )
        let submissionEnd = try XCTUnwrap(
            map.range(
                of: "private func cancelMapSearch()",
                range: submissionStart.upperBound..<map.endIndex
            )
        )
        let submission = map[submissionStart.lowerBound..<submissionEnd.lowerBound]
        XCTAssertTrue(
            submission.contains(
                "MapSearchSubmissionContext(query: requestedQuery, region: searchRegion)"
            )
        )
    }

    @MainActor
    func testExplicitMapSearchCorpusUsesAllAuthorizedSavesAndOnlyMoreFilters() {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let authorizedPlaces = store.visiblePlaces()

        XCTAssertEqual(
            Set(
                MapSearchCorpusPolicy.savedPlaces(
                    from: authorizedPlaces,
                    refinements: MapMoreFilterSelection()
                ).map(\.userPlace.id)
            ),
            Set(authorizedPlaces.map(\.userPlace.id))
        )

        let wannaOnly = MapSearchCorpusPolicy.savedPlaces(
            from: authorizedPlaces,
            refinements: MapMoreFilterSelection(status: .wanna)
        )
        XCTAssertFalse(wannaOnly.isEmpty)
        XCTAssertTrue(wannaOnly.allSatisfy { $0.userPlace.status == .wannaGo })
    }

    func testFeaturedRefreshPolicyOnlyFetchesForFeaturedSource() {
        XCTAssertTrue(MapSearchPerformancePolicy.shouldFetchFeatured(for: .featured))
        XCTAssertFalse(MapSearchPerformancePolicy.shouldFetchFeatured(for: .friends))
        XCTAssertFalse(MapSearchPerformancePolicy.shouldFetchFeatured(for: .you))
    }

    func testDeferredMapNavigationGateRejectsCancelledOrSupersededWork() {
        var gate = MapDeferredNavigationGate()
        let capturedRevision = gate.revision

        XCTAssertTrue(gate.allows(capturedRevision, isCancelled: false))
        XCTAssertFalse(gate.allows(capturedRevision, isCancelled: true))

        gate.invalidate()

        XCTAssertFalse(gate.allows(capturedRevision, isCancelled: false))
        XCTAssertTrue(gate.allows(gate.revision, isCancelled: false))
    }

    func testCancelingMapSearchRestoresTheSelectionCapturedAtSearchEntry() {
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: "sushi-fumi")
        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: "boulevard")
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertEqual(restoredSelection, "sushi-fumi")
        XCTAssertFalse(session.isActive)
    }

    func testCancelingMapSearchRestoresAnExternalCandidatePayload() {
        let externalCandidate = PlaceCandidate(
            id: "mapkit_long_tables",
            name: "Long Tables Cafe",
            category: "coffee",
            latitude: 34.0775,
            longitude: -118.2608,
            confidence: 1
        )
        let entrySelection = MapSearchSelectionSnapshot(
            selectedPlaceGroupKey: nil,
            selectedSearchCandidateID: externalCandidate.id,
            mapSearchCandidates: [externalCandidate]
        )
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selection: entrySelection)
        session.suppressPreviewForEditing()
        let restoredSelection = session.cancel(
            currentSelection: MapSearchSelectionSnapshot(selectedPlaceGroupKey: nil)
        )

        XCTAssertEqual(restoredSelection.selectedSearchCandidateID, externalCandidate.id)
        XCTAssertEqual(restoredSelection.mapSearchCandidates, [externalCandidate])
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isPreviewSuppressed)
    }

    @MainActor
    func testCancelingMapSearchRestoresSubmittedCategoryGroups() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let submittedGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: store.visiblePlaces(),
                currentUserID: store.currentUser.id
            ).first
        )
        let entrySelection = MapSearchSelectionSnapshot(
            selectedPlaceGroupKey: submittedGroup.key,
            submittedSavedSearchGroups: [submittedGroup]
        )
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selection: entrySelection)
        session.suppressPreviewForEditing()
        let restoredSelection = session.cancel(
            currentSelection: MapSearchSelectionSnapshot(selectedPlaceGroupKey: nil)
        )

        XCTAssertEqual(restoredSelection.selectedPlaceGroupKey, submittedGroup.key)
        XCTAssertEqual(restoredSelection.submittedSavedSearchGroups.map(\.key), [submittedGroup.key])
        XCTAssertFalse(session.isActive)
        XCTAssertFalse(session.isPreviewSuppressed)
    }

    func testCancelingMapSearchKeepsSelectionEmptyWhenSearchStartedEmpty() {
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: nil)
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertNil(restoredSelection)
        XCTAssertFalse(session.isActive)
    }

    func testCancelingMapSearchKeepsEntrySelectionAfterCancelButtonBlursField() {
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: nil)
        session.focusDidChange(isFocused: false, selectedPlaceGroupKey: "boulevard")
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertNil(restoredSelection)
        XCTAssertFalse(session.isActive)
    }

    func testCancelingMapSearchKeepsEntrySelectionAfterBlurAndRefocus() {
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: nil)
        session.focusDidChange(isFocused: false, selectedPlaceGroupKey: "boulevard")
        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: "boulevard")
        let restoredSelection = session.cancel(
            currentSelectedPlaceGroupKey: "boulevard"
        )

        XCTAssertNil(restoredSelection)
        XCTAssertFalse(session.isActive)
    }

    func testCompletingMapSearchKeepsAnExplicitlySelectedResult() {
        var session = MapSearchSelectionSession()

        session.focusDidChange(isFocused: true, selectedPlaceGroupKey: "sushi-fumi")
        session.finish()
        let selectedResult = session.cancel(
            currentSelectedPlaceGroupKey: "rvr"
        )

        XCTAssertEqual(selectedResult, "rvr")
        XCTAssertFalse(session.isActive)
    }

    func testMapSearchCancelWiresRestorationBeforeDismissingFocus() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let cancelStart = try XCTUnwrap(map.range(of: "private func cancelMapSearch()"))
        let cancelEnd = try XCTUnwrap(
            map.range(
                of: "@MainActor\n    private func handlePresentationResetRequest",
                range: cancelStart.upperBound..<map.endIndex
            )
        )
        let cancellation = map[cancelStart.lowerBound..<cancelEnd.lowerBound]

        XCTAssertTrue(cancellation.contains("mapSearchSelectionSession.cancel("))
        XCTAssertFalse(cancellation.contains("suppressNextQueryAutoSelection"))
        XCTAssertTrue(
            cancellation.contains(
                "selectedPlaceGroupKey = restoredSelection.selectedPlaceGroupKey"
            )
        )
        XCTAssertTrue(
            cancellation.contains(
                "mapSearchCandidates = restoredSelection.mapSearchCandidates"
            )
        )
        XCTAssertTrue(
            cancellation.contains(
                "submittedSavedSearchGroups = restoredSelection.submittedSavedSearchGroups"
            )
        )
        XCTAssertLessThan(
            try XCTUnwrap(
                cancellation.range(
                    of: "selectedPlaceGroupKey = restoredSelection.selectedPlaceGroupKey"
                )
            ).lowerBound,
            try XCTUnwrap(cancellation.range(of: "isMapSearchFocused = false")).lowerBound
        )
    }

    func testMapSearchPipelineReusesImmediateProjectionWorkWithoutFreshLocationLookup() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("viewerLocation: mapCardViewerLocation"))
        XCTAssertFalse(map.contains("searchOriginLocation"))
        XCTAssertTrue(map.contains("private var mapSearchSavedCorpus"))
        XCTAssertTrue(map.contains("from: store.visiblePlaces()"))
        XCTAssertTrue(map.contains("refinements: mapFilterState.more"))
        XCTAssertTrue(map.contains("mapSearchAuthorizationContext == authorizationContext"))

        let searchStart = try XCTUnwrap(map.range(of: "private func runMapSearch("))
        let searchEnd = try XCTUnwrap(
            map.range(
                of: "private func beginMapSearchRequest()",
                range: searchStart.upperBound..<map.endIndex
            )
        )
        let submittedSearch = map[searchStart.lowerBound..<searchEnd.lowerBound]
        XCTAssertTrue(submittedSearch.contains("savedCandidates: [MapSearchSavedCandidate]"))
        XCTAssertFalse(submittedSearch.contains("savedCandidates.first(where:"))
        XCTAssertFalse(submittedSearch.contains("MapSearchCandidatePolicy.strength(of:"))
        XCTAssertTrue(submittedSearch.contains("MapSearchCandidatePolicy.orderedCandidates("))
        XCTAssertFalse(submittedSearch.contains("searchVisiblePlaces.isEmpty"))
        XCTAssertFalse(submittedSearch.contains("visiblePlaces.first"))
        XCTAssertFalse(submittedSearch.contains("visiblePlaces.isEmpty"))

        let mapKitLookup = try XCTUnwrap(
            submittedSearch.range(of: "let candidates = try await mapKitCandidates(")
        )
        let combinedOrdering = try XCTUnwrap(
            submittedSearch.range(of: "MapSearchCandidatePolicy.orderedCandidates(")
        )
        XCTAssertLessThan(mapKitLookup.lowerBound, combinedOrdering.lowerBound)

        let trustedMatchesStart = try XCTUnwrap(map.range(of: "private func savedMapSearchCandidates("))
        let trustedMatchesEnd = try XCTUnwrap(
            map.range(
                of: "private func beginMapSearchRequest()",
                range: trustedMatchesStart.upperBound..<map.endIndex
            )
        )
        let trustedMatches = map[trustedMatchesStart.lowerBound..<trustedMatchesEnd.lowerBound]
        XCTAssertTrue(trustedMatches.contains("TrustedPlaceSearchQuery(requestedQuery)"))
        XCTAssertTrue(trustedMatches.contains("MapSearchCandidatePolicy.savedCandidates("))
        XCTAssertTrue(trustedMatches.contains("in: mapSearchSavedCorpus"))

        let sourceStart = try XCTUnwrap(map.range(of: "private func selectMapSource("))
        let sourceEnd = try XCTUnwrap(
            map.range(of: "private func dismissMoreFilters()", range: sourceStart.upperBound..<map.endIndex)
        )
        let sourceSelection = map[sourceStart.lowerBound..<sourceEnd.lowerBound]
        XCTAssertTrue(sourceSelection.contains("handleFeaturedCameraChange(currentSearchRegion)"))
        XCTAssertTrue(sourceSelection.contains("if Self.normalized(mapQuery).isEmpty"))
    }

    func testMapSearchSubmissionUsesTheLatestVisibleDraftWithoutWaitingForDebounce() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let searchBar = try XCTUnwrap(
            map.components(separatedBy: "private struct SearchBar: View {").last?
                .components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier").first
        )
        let submission = try XCTUnwrap(
            searchBar.components(separatedBy: ".onSubmit {").last?
                .components(separatedBy: ".task(id: focusRequestID)").first
        )

        XCTAssertTrue(searchBar.contains("let onSubmit: (String) -> Void"))
        XCTAssertTrue(submission.contains("let requestedQuery = draftQuery"))
        XCTAssertTrue(submission.contains("commitDraftQuery(requestedQuery)"))
        XCTAssertTrue(submission.contains("onSubmit(requestedQuery)"))
        XCTAssertLessThan(
            try XCTUnwrap(submission.range(of: "commitDraftQuery(requestedQuery)")).lowerBound,
            try XCTUnwrap(submission.range(of: "onSubmit(requestedQuery)")).lowerBound
        )

        let submitStart = try XCTUnwrap(map.range(of: "private func submitMapSearch(_ requestedQuery: String)"))
        let submitEnd = try XCTUnwrap(
            map.range(of: "private func cancelMapSearch()", range: submitStart.upperBound..<map.endIndex)
        )
        let parentSubmission = map[submitStart.lowerBound..<submitEnd.lowerBound]
        XCTAssertTrue(parentSubmission.contains("suppressedTypeaheadQuery = Self.normalized(requestedQuery)"))
        XCTAssertTrue(parentSubmission.contains("let savedCandidates = savedMapSearchCandidates(for: requestedQuery)"))
        XCTAssertFalse(parentSubmission.contains("let requestedQuery = mapQuery"))
    }

    @MainActor
    func testProviderSuggestionResolvesPhysicalDuplicateToAuthorizedSavedGroup() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let savedPlace = try XCTUnwrap(store.visiblePlaces().first)
        let candidate = PlaceCandidate(
            id: "provider-duplicate",
            name: savedPlace.place.canonicalName,
            category: savedPlace.place.category,
            latitude: savedPlace.place.latitude,
            longitude: savedPlace.place.longitude,
            sourceProvider: savedPlace.place.sourceProvider,
            sourceProviderPlaceID: savedPlace.place.sourceProviderPlaceID,
            confidence: 1
        )

        switch MapProviderSuggestionPolicy.destination(
            for: candidate,
            in: store.visiblePlaces(),
            currentUserID: store.currentUser.id
        ) {
        case .saved(let savedGroup):
            XCTAssertTrue(savedGroup.places.contains {
                $0.userPlace.id == savedPlace.userPlace.id
            })
        case .candidate:
            XCTFail("A provider duplicate should open the authorized saved-memory group.")
        }

        switch MapProviderSuggestionPolicy.destination(
            for: candidate,
            in: [],
            currentUserID: store.currentUser.id
        ) {
        case .candidate(let selectedCandidate):
            XCTAssertEqual(selectedCandidate, candidate)
        case .saved:
            XCTFail("A provider result must not recover a save outside the authorized corpus.")
        }
    }
}

final class MapSelectionMotionTests: XCTestCase {
    func testSubmittedSearchFitsCategoriesAndCentersNamedPlaces() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let searchStart = try XCTUnwrap(map.range(of: "private func runMapSearch("))
        let searchEnd = try XCTUnwrap(
            map.range(
                of: "private func beginMapSearchRequest()",
                range: searchStart.upperBound..<map.endIndex
            )
        )
        let submittedSearch = map[searchStart.lowerBound..<searchEnd.lowerBound]
        XCTAssertTrue(submittedSearch.contains("center(on: firstSavedCandidate.place)"))
        XCTAssertTrue(submittedSearch.contains("center(on: firstCandidate)"))
        XCTAssertTrue(submittedSearch.contains("queryIntent == .namedPlace"))
        XCTAssertTrue(submittedSearch.contains("queryIntent == .category"))
        XCTAssertTrue(submittedSearch.contains("fitSubmittedSearchResults("))

        let centerStart = try XCTUnwrap(map.range(of: "private func centerSearchSelection("))
        let centerEnd = try XCTUnwrap(
            map.range(
                of: "private func handleNearbyTap()",
                range: centerStart.upperBound..<map.endIndex
            )
        )
        let searchCentering = map[centerStart.lowerBound..<centerEnd.lowerBound]
        XCTAssertTrue(searchCentering.contains("MapSelectionViewport.region("))
        XCTAssertTrue(
            searchCentering.contains("obscuredBottomHeight: selectedPlaceRecenterClearance")
        )
        XCTAssertTrue(searchCentering.contains("requestMapCamera(region)"))
    }

    func testSelectedCoordinateCentersInsideTheUnobscuredMapHeight() {
        let coordinate = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        let viewportHeight: CGFloat = 800
        let obscuredBottomHeight: CGFloat = 240

        let region = MapSelectionViewport.region(
            centeredOn: coordinate,
            preserving: span,
            viewportHeight: viewportHeight,
            obscuredBottomHeight: obscuredBottomHeight
        )

        let projectedY = viewportHeight * (
            0.5 - CGFloat(coordinate.latitude - region.center.latitude) / CGFloat(region.span.latitudeDelta)
        )
        XCTAssertEqual(projectedY, (viewportHeight - obscuredBottomHeight) / 2, accuracy: 0.001)
        XCTAssertEqual(region.span.latitudeDelta, span.latitudeDelta)
        XCTAssertEqual(region.span.longitudeDelta, span.longitudeDelta)
        XCTAssertEqual(region.center.longitude, coordinate.longitude)
    }

    func testNearbyBadgeReflectsLocationAuthorization() {
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .notDetermined))
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .denied))
        XCTAssertTrue(MapNearbyPermissionPolicy.showsAttentionBadge(for: .restricted))
        XCTAssertFalse(MapNearbyPermissionPolicy.showsAttentionBadge(for: .authorizedWhenInUse))
        XCTAssertFalse(MapNearbyPermissionPolicy.showsAttentionBadge(for: .authorizedAlways))
    }

    @MainActor
    func testSelectionMotionUsesAStagedCardAndBouncyPinContract() {
        XCTAssertEqual(MapCompactCardMotionStyle.entranceDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(MapCompactCardMotionStyle.nearbyFadeDuration, 0.16, accuracy: 0.001)
        XCTAssertEqual(MapCompactCardMotionStyle.nearbyReturnFadeDuration, 0.16, accuracy: 0.001)
        XCTAssertLessThanOrEqual(MapCompactCardMotionStyle.hiddenVerticalOffset, 220)
        XCTAssertEqual(MapPinSelectionMotionStyle.inactiveScale, 0.90, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.selectedScale, 1.45, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.duration, 0.18, accuracy: 0.001)
        XCTAssertEqual(MapPinSelectionMotionStyle.bounce, 0.32, accuracy: 0.001)
        XCTAssertEqual(MapPinFocusMotionStyle.duration, 0.22, accuracy: 0.001)
        XCTAssertEqual(MapPinFocusPolicy.minimumOpacity, 0.26, accuracy: 0.001)
    }

    func testSelectedPinFocusUsesTenPointGradientStops() {
        let firstStop = MapPinFocusPolicy.opacity(
            forNormalizedDistance: MapPinFocusPolicy.innerRadius
        )
        let secondStop = MapPinFocusPolicy.opacity(
            forNormalizedDistance: MapPinFocusPolicy.innerRadius
                + MapPinFocusPolicy.distanceStep
        )
        let thirdStop = MapPinFocusPolicy.opacity(
            forNormalizedDistance: MapPinFocusPolicy.innerRadius
                + (2 * MapPinFocusPolicy.distanceStep)
        )

        XCTAssertEqual(firstStop, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
        XCTAssertEqual(secondStop - firstStop, MapPinFocusPolicy.opacityStep, accuracy: 0.001)
        XCTAssertEqual(thirdStop - secondStop, MapPinFocusPolicy.opacityStep, accuracy: 0.001)
        XCTAssertEqual(
            MapPinFocusPolicy.opacity(forNormalizedDistance: MapPinFocusPolicy.outerRadius),
            1,
            accuracy: 0.001
        )
    }

    func testSelectedPinFocusInterpolatesSmoothlyBetweenGradientStops() {
        let selected = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)

        let collidingPinOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.999),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let midFalloffOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.98),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let distantPinOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.95),
            selectedCoordinate: selected,
            regionSpan: span
        )

        XCTAssertEqual(collidingPinOpacity, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(midFalloffOpacity, MapPinFocusPolicy.minimumOpacity)
        XCTAssertLessThan(midFalloffOpacity, 1)
        XCTAssertEqual(distantPinOpacity, 1, accuracy: 0.001)
    }

    func testSelectedPinFocusClearsWithoutASelection() {
        let opacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            selectedCoordinate: nil,
            regionSpan: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        )

        XCTAssertEqual(opacity, 1, accuracy: 0.001)
    }

    func testSelectedPinFocusMovesToTheReplacementSelection() {
        let firstSelection = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let replacementSelection = CLLocationCoordinate2D(latitude: 34, longitude: -117.95)
        let nearbyFirstPin = CLLocationCoordinate2D(latitude: 34, longitude: -117.999)
        let nearbyReplacementPin = CLLocationCoordinate2D(latitude: 34, longitude: -117.951)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)

        let firstPinBeforeReplacement = MapPinFocusPolicy.opacity(
            for: nearbyFirstPin,
            selectedCoordinate: firstSelection,
            regionSpan: span
        )
        let firstPinAfterReplacement = MapPinFocusPolicy.opacity(
            for: nearbyFirstPin,
            selectedCoordinate: replacementSelection,
            regionSpan: span
        )
        let replacementPinBeforeSelection = MapPinFocusPolicy.opacity(
            for: nearbyReplacementPin,
            selectedCoordinate: firstSelection,
            regionSpan: span
        )
        let replacementPinAfterSelection = MapPinFocusPolicy.opacity(
            for: nearbyReplacementPin,
            selectedCoordinate: replacementSelection,
            regionSpan: span
        )

        XCTAssertEqual(firstPinBeforeReplacement, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
        XCTAssertEqual(firstPinAfterReplacement, 1, accuracy: 0.001)
        XCTAssertEqual(replacementPinBeforeSelection, 1, accuracy: 0.001)
        XCTAssertEqual(replacementPinAfterSelection, MapPinFocusPolicy.minimumOpacity, accuracy: 0.001)
    }

    func testSelectedPinFocusUsesAnEllipticalVerticalFalloff() {
        let selected = CLLocationCoordinate2D(latitude: 34, longitude: -118)
        let span = MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.10)
        let horizontalOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34, longitude: -117.98),
            selectedCoordinate: selected,
            regionSpan: span
        )
        let verticalOpacity = MapPinFocusPolicy.opacity(
            for: CLLocationCoordinate2D(latitude: 34.02, longitude: -118),
            selectedCoordinate: selected,
            regionSpan: span
        )

        XCTAssertGreaterThan(verticalOpacity, horizontalOpacity)
    }

    @MainActor
    func testFirstVisitPhotoIndexReusesWarmProjection() {
        let store = WanderStore(fixtures: WanderFixtures.seed())

        _ = store.firstVisitPhotosByPlaceID()
        _ = store.firstVisitPhotosByPlaceID()
        _ = store.firstVisitPhotosByPlaceID()

        XCTAssertEqual(store.firstVisitPhotoIndexBuildCount, 1)
    }

    func testColdSurfaceWorkIsDeferredAndLazy() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let feed = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Feed/FeedScreen.swift")
        )
        let placeCard = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Map/PlaceProfileMapSurface.swift"
            )
        )

        XCTAssertTrue(feed.contains("await Task.yield()"))
        XCTAssertTrue(feed.contains("LazyHStack(alignment: .top"))
        XCTAssertTrue(placeCard.contains(".onAppear(perform: onReady)"))
        XCTAssertTrue(placeCard.contains("PlaceProfileCategoryThumb(emoji: place.categoryEmoji, size: 72)"))
        XCTAssertTrue(placeCard.contains("PlacePhotoImagePipeline.shared.image("))
        XCTAssertTrue(placeCard.contains("VisitPhotoLocalFileStore.data(from: localAssetRef)"))
        XCTAssertFalse(placeCard.contains("return await image.byPreparingForDisplay() ?? image"))
        XCTAssertTrue(placeCard.contains("withAnimation(.easeOut(duration: 0.10))"))
    }

    @MainActor
    func testActivePinRemainsInAnnotationsWhenAViewportRefreshDropsIt() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let allPlaces = store.visiblePlaces()
        let activePlace = try XCTUnwrap(allPlaces.first)
        let refreshedPlaces = allPlaces.filter { $0.id != activePlace.id }

        let retainedPlaces = MapActivePinRetention.places(
            from: refreshedPlaces,
            retaining: activePlace
        )

        XCTAssertEqual(retainedPlaces.filter { $0.id == activePlace.id }.count, 1)
        XCTAssertEqual(
            MapActivePinRetention.places(
                from: allPlaces,
                retaining: activePlace
            ).filter { $0.id == activePlace.id }.count,
            1
        )

        let retainedGroup = VisiblePlaceGrouping.matchingGroup(
            for: activePlace,
            in: retainedPlaces,
            currentUserID: store.currentUser.id
        )
        XCTAssertNotNil(retainedGroup)
    }

    @MainActor
    func testActivePinRetentionMergesOmittedCurrentUserSaveIntoMatchingGroup() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let currentUserID = store.currentUser.id
        let sharedGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: store.visiblePlaces(),
                currentUserID: currentUserID
            ).first { group in
                group.places.contains { $0.owner.id == currentUserID }
                    && group.places.contains { $0.owner.id != currentUserID }
            }
        )
        let activePlace = try XCTUnwrap(
            sharedGroup.places.first { $0.owner.id == currentUserID }
        )
        let replacementPlace = try XCTUnwrap(
            sharedGroup.places.first { $0.owner.id != currentUserID }
        )
        let refreshedGroups = VisiblePlaceGrouping.groups(
            from: [replacementPlace],
            currentUserID: currentUserID
        )

        let retainedGroups = MapActivePinRetention.groups(
            from: refreshedGroups,
            retaining: activePlace,
            currentUserID: currentUserID
        )
        let retainedGroup = try XCTUnwrap(retainedGroups.first)

        XCTAssertEqual(retainedGroups.count, 1)
        XCTAssertEqual(retainedGroup.key, refreshedGroups[0].key)
        XCTAssertEqual(retainedGroup.primary.userPlace.id, activePlace.userPlace.id)
        XCTAssertEqual(
            Set(retainedGroup.places.map(\.userPlace.id)),
            Set([activePlace.userPlace.id, replacementPlace.userPlace.id])
        )
        XCTAssertEqual(
            MapActivePinRetention.groupKey(for: activePlace, in: retainedGroups),
            retainedGroup.key
        )
    }

    @MainActor
    func testActivePinRetentionKeepsTheFullSavedSearchGroupOutsideProjection() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let currentUserID = store.currentUser.id
        let fullGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: store.visiblePlaces(),
                currentUserID: currentUserID
            ).first { $0.saveCount > 1 }
        )
        let projectedPlace = try XCTUnwrap(fullGroup.places.last)
        let projectedGroups = VisiblePlaceGrouping.groups(
            from: [projectedPlace],
            currentUserID: currentUserID
        )

        let retainedPlaces = MapActivePinRetention.places(
            from: [projectedPlace],
            retaining: fullGroup.primary,
            retainingGroup: fullGroup
        )
        let retainedGroups = MapActivePinRetention.groups(
            from: projectedGroups,
            retaining: fullGroup.primary,
            retainingGroup: fullGroup,
            currentUserID: currentUserID
        )

        XCTAssertEqual(
            Set(retainedPlaces.map(\.userPlace.id)),
            Set(fullGroup.places.map(\.userPlace.id))
        )
        XCTAssertEqual(retainedGroups.count, 1)
        XCTAssertEqual(
            Set(try XCTUnwrap(retainedGroups.first).places.map(\.userPlace.id)),
            Set(fullGroup.places.map(\.userPlace.id))
        )
    }

    @MainActor
    func testSubmittedCategorySearchRetainsEveryReturnedSavedGroupOutsideProjection() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let currentUserID = store.currentUser.id
        let submittedGroups = Array(
            VisiblePlaceGrouping.groups(
                from: store.visiblePlaces(),
                currentUserID: currentUserID
            ).prefix(3)
        )
        XCTAssertEqual(submittedGroups.count, 3)

        let projectedGroup = try XCTUnwrap(submittedGroups.first)
        let retainedPlaces = MapActivePinRetention.places(
            from: projectedGroup.places,
            retainingGroups: submittedGroups
        )
        let retainedGroups = MapActivePinRetention.groups(
            from: [projectedGroup],
            retainingGroups: submittedGroups,
            currentUserID: currentUserID
        )

        let submittedUserPlaceIDs = Set(
            submittedGroups.flatMap(\.places).map(\.userPlace.id)
        )
        XCTAssertTrue(
            Set(retainedPlaces.map(\.userPlace.id)).isSuperset(of: submittedUserPlaceIDs)
        )
        XCTAssertTrue(
            Set(retainedGroups.flatMap(\.places).map(\.userPlace.id))
                .isSuperset(of: submittedUserPlaceIDs)
        )
    }

    @MainActor
    func testActivePinRetentionDropsAGroupAfterAuthorizationIsRevoked() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let currentUserID = store.currentUser.id
        let authorizedPlaces = store.visiblePlaces()
        let retainedGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: authorizedPlaces,
                currentUserID: currentUserID
            ).first
        )
        let retainedIDs = Set(retainedGroup.places.map(\.userPlace.id))
        let afterRevocation = authorizedPlaces.filter {
            !retainedIDs.contains($0.userPlace.id)
        }

        let authorizedActive = MapActivePinRetention.authorizedPlace(
            retainedGroup.primary,
            within: afterRevocation
        )
        let authorizedGroup = MapActivePinRetention.authorizedGroup(
            retainedGroup,
            requiring: authorizedActive,
            within: afterRevocation,
            currentUserID: currentUserID
        )
        let authorizedSubmittedGroups = MapActivePinRetention.authorizedGroups(
            [retainedGroup],
            within: afterRevocation,
            currentUserID: currentUserID
        )

        XCTAssertNil(authorizedActive)
        XCTAssertNil(authorizedGroup)
        XCTAssertTrue(authorizedSubmittedGroups.isEmpty)
    }

    @MainActor
    func testSubmittedRetentionRebuildsGroupsFromCurrentAuthorizedRows() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let currentUserID = store.currentUser.id
        let authorizedPlaces = store.visiblePlaces()
        let retainedGroup = try XCTUnwrap(
            VisiblePlaceGrouping.groups(
                from: authorizedPlaces,
                currentUserID: currentUserID
            ).first { $0.saveCount > 1 }
        )
        let revokedID = try XCTUnwrap(retainedGroup.places.last?.userPlace.id)
        let afterRevocation = authorizedPlaces.filter {
            $0.userPlace.id != revokedID
        }

        let refreshedGroups = MapActivePinRetention.authorizedGroups(
            [retainedGroup],
            within: afterRevocation,
            currentUserID: currentUserID
        )
        let refreshedIDs = Set(refreshedGroups.flatMap(\.places).map(\.userPlace.id))

        XCTAssertFalse(refreshedIDs.contains(revokedID))
        XCTAssertEqual(
            refreshedIDs,
            Set(retainedGroup.places.map(\.userPlace.id)).subtracting([revokedID])
        )
    }

    func testActivePinRefreshRegressionFixtureRequiresPersistentSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-selected-pin-regional-refresh-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_refresh_result"] as? [String: Any])

        XCTAssertEqual(expected["selected_place_id"] as? String, "selected-place-b")
        XCTAssertEqual(expected["selected_pin_is_annotated"] as? Bool, true)
    }

    func testPinchZoomRegressionFixtureRequiresSelectionAndCardToRemainPresented() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-pinch-zoom-selection-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_result"] as? [String: Any])

        XCTAssertEqual(expected["selected_place_id"] as? String, "selected-place-a")
        XCTAssertEqual(expected["compact_card_phase"] as? String, "presented")
        XCTAssertEqual(expected["pinch_zoom_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["empty_map_tap_dismisses_selection"] as? Bool, true)
        XCTAssertEqual(expected["one_finger_pan_dismisses_selection"] as? Bool, true)
        XCTAssertEqual(expected["active_pin_title_clearance_points"] as? Int, 2)
    }

    func testCameraGestureClassificationKeepsEveryZoomAndDismissesOnlyAPan() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let oneFingerZoom = MKCoordinateRegion(
            center: start.center,
            span: MKCoordinateSpan(latitudeDelta: 0.075, longitudeDelta: 0.09)
        )
        let pinchZoom = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.052, longitude: -118.248),
            span: MKCoordinateSpan(latitudeDelta: 0.14, longitudeDelta: 0.168)
        )
        let panWithLongitudeSpanDrift = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.065, longitude: -118.225),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.121)
        )

        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: oneFingerZoom), .zoom)
        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: pinchZoom), .zoom)
        XCTAssertEqual(
            MapSelectionGesturePolicy.classify(from: start, to: panWithLongitudeSpanDrift),
            .pan
        )
        XCTAssertEqual(MapSelectionGesturePolicy.classify(from: start, to: start), .stationary)
        XCTAssertGreaterThan(MapSelectionGesturePolicy.tapDismissalDelayNanoseconds, 250_000_000)
        XCTAssertGreaterThanOrEqual(MapSelectionGesturePolicy.postZoomTapSuppressionDuration, 0.5)
        XCTAssertGreaterThanOrEqual(
            MapSelectionGesturePolicy.nativeFeatureTapSuppressionDuration,
            0.5
        )
        XCTAssertLessThanOrEqual(
            MapSelectionGesturePolicy.doubleTapRecognitionWindow,
            Double(MapSelectionGesturePolicy.tapDismissalDelayNanoseconds) / 1_000_000_000
        )
    }

    func testCameraRegionTrackerClassifiesAContinuousPanWithoutPublishingViewState() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let tracker = MapCameraRegionTracker(region: start)
        let samples = (1...120).map { index in
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: start.center.latitude + (Double(index) * 0.0001),
                    longitude: start.center.longitude + (Double(index) * 0.00015)
                ),
                span: start.span
            )
        }

        for sample in samples {
            tracker.recordCameraChange(sample)
        }
        let end = samples[samples.count - 1]

        XCTAssertTrue(tracker.isInteractionActive)
        XCTAssertEqual(tracker.region.center.latitude, end.center.latitude)
        XCTAssertEqual(tracker.region.center.longitude, end.center.longitude)
        XCTAssertEqual(tracker.finishCameraChange(end), .pan)
        XCTAssertFalse(tracker.isInteractionActive)
    }

    func testCameraRegionTrackerKeepsPinchZoomDistinctFromPan() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let zoomed = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.052, longitude: -118.248),
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.072)
        )
        let tracker = MapCameraRegionTracker(region: start)

        tracker.recordCameraChange(zoomed)

        XCTAssertEqual(tracker.finishCameraChange(zoomed), .zoom)
        XCTAssertFalse(tracker.isInteractionActive)
    }

    func testCameraRegionTrackerRemembersZoomAcrossRapidDirectionChanges() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let zoomed = MKCoordinateRegion(
            center: start.center,
            span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.072)
        )
        let returnedWithCenterDrift = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.06, longitude: -118.24),
            span: start.span
        )
        let tracker = MapCameraRegionTracker(region: start)

        tracker.recordCameraChange(zoomed)
        tracker.recordCameraChange(returnedWithCenterDrift)

        XCTAssertEqual(tracker.finishCameraChange(returnedWithCenterDrift), .zoom)
        XCTAssertFalse(tracker.isInteractionActive)
    }

    func testCameraRegionTrackerSynchronizesProgrammaticCameraMoves() {
        let start = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
            span: MKCoordinateSpan(latitudeDelta: 0.10, longitudeDelta: 0.12)
        )
        let destination = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.71, longitude: -74.01),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.05)
        )
        let tracker = MapCameraRegionTracker(region: start)

        tracker.synchronize(with: destination)

        XCTAssertFalse(tracker.isInteractionActive)
        XCTAssertEqual(tracker.finishCameraChange(destination), .stationary)
    }

    func testSelectionLifetimeIgnoresMapKitBindingClear() {
        XCTAssertTrue(MapSelectionLifetimePolicy.shouldDismiss(for: .emptyMapTap))
        XCTAssertTrue(MapSelectionLifetimePolicy.shouldDismiss(for: .oneFingerPan))
        XCTAssertFalse(
            MapSelectionLifetimePolicy.shouldDismiss(for: .nativeFeatureBindingCleared)
        )
    }

    func testSelectedAnnotationStaysInsideMapKitsCameraLayer() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("NativeMapView("))
        XCTAssertTrue(map.contains("private final class NativeMapAnnotation: NSObject, MKAnnotation"))
        XCTAssertTrue(map.contains("mapView.addAnnotations(addedAnnotations)"))
        XCTAssertTrue(map.contains("clusteringIdentifier = nil"))
        XCTAssertTrue(map.contains("zPriority = descriptor.isSelected ? .max : .defaultUnselected"))
        XCTAssertTrue(map.contains("displayPriority = descriptor.isSelected ? .required : .defaultHigh"))
        XCTAssertFalse(map.contains("selectedReuseIdentifier"))
        XCTAssertFalse(map.contains("NativeMapClusterAnnotationView"))
        XCTAssertFalse(map.contains("activeMapAnnotationOverlay"))
        XCTAssertFalse(map.contains(".position(point)"))
    }
    func testNativeActiveAnnotationsKeepTheOneShotReselectionBounce() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("bounceRevision: group.key == selectedPlaceGroupKey"))
        XCTAssertTrue(map.contains("bounceRevision: candidate.id == selectedSearchCandidateID"))
        XCTAssertTrue(map.contains("if descriptor.bounceRevision != bounceRevision"))
        XCTAssertTrue(map.contains("transform = CGAffineTransform(scaleX: 0.82, y: 0.82)"))
        XCTAssertTrue(map.contains("animateEntrance("))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenVerticalOffset"))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenScale"))
        XCTAssertTrue(map.contains("paragraphStyle.lineBreakMode = .byTruncatingTail"))
        XCTAssertTrue(map.contains("UIView.animate("))
        XCTAssertTrue(map.contains("self.transform = .identity"))
    }
    func testNativeAnnotationsAreDiffedReusedAndBufferedAroundTheViewport() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("private var annotationsByID: [String: NativeMapAnnotation]"))
        XCTAssertTrue(map.contains("mapView.addAnnotations(addedAnnotations)"))
        XCTAssertTrue(map.contains("mapView.removeAnnotations(staleAnnotations)"))
        XCTAssertTrue(map.contains("dequeueReusableAnnotationView("))
        XCTAssertTrue(map.contains("for reuseIdentifier in NativeMapPinAnnotationView.reuseIdentifiers"))
        XCTAssertTrue(map.contains("let descriptorsChanged = nextDescriptorSnapshot != descriptorSnapshotByID"))
        XCTAssertTrue(map.contains("private var renderedViewport: MapViewport?"))
        XCTAssertTrue(map.contains("MapAnnotationViewportPolicy.shouldRefresh("))
        XCTAssertTrue(map.contains("descriptor.isSelected"))
        XCTAssertFalse(map.contains("replacedAnnotations"))
        XCTAssertFalse(map.contains("MKClusterAnnotation"))
        XCTAssertFalse(map.contains("@State private var renderedAnnotationViewport"))
        XCTAssertFalse(map.contains("MapAnnotationDensityPolicy"))
    }
    func testEntranceIdentityStateStagesOnlyPinsNewToTheViewport() throws {
        let retained = MapPinEntranceIdentity.saved("retained")
        let entering = MapPinEntranceIdentity.saved("entering")
        var state = MapPinEntranceKeyState()

        XCTAssertNil(state.prepare(for: [retained], reduceMotion: true))
        let keysToPresent = state.prepare(
            for: [retained, entering],
            reduceMotion: false
        )

        XCTAssertTrue(state.isPresented(retained))
        XCTAssertFalse(state.isPresented(entering))
        XCTAssertEqual(keysToPresent, [retained, entering])

        state.present(try XCTUnwrap(keysToPresent))

        XCTAssertTrue(state.isPresented(retained))
        XCTAssertTrue(state.isPresented(entering))
    }

    func testEntranceIdentityStateForgetsPinsThatLeaveSoReentryBounces() {
        let pin = MapPinEntranceIdentity.saved("returning")
        var state = MapPinEntranceKeyState()

        XCTAssertNil(state.prepare(for: [pin], reduceMotion: true))
        XCTAssertNil(state.prepare(for: [], reduceMotion: false))
        XCTAssertFalse(state.isPresented(pin))

        let keysToPresent = state.prepare(for: [pin], reduceMotion: false)

        XCTAssertFalse(state.isPresented(pin))
        XCTAssertEqual(keysToPresent, [pin])
    }

    func testEntranceIdentityStateDoesNotRestartPendingBounceForEveryCameraFrame() {
        let pin = MapPinEntranceIdentity.saved("crossing-edge")
        var state = MapPinEntranceKeyState()

        XCTAssertEqual(state.prepare(for: [pin], reduceMotion: false), [pin])
        XCTAssertFalse(state.needsUpdate(for: [pin], reduceMotion: false))
        XCTAssertFalse(state.isPresented(pin))

        state.present([pin])

        XCTAssertTrue(state.isPresented(pin))
        XCTAssertFalse(state.needsUpdate(for: [pin], reduceMotion: false))
    }

    func testEntranceIdentityStateKeepsRetainedPinStagedWhenPendingViewportShrinks() {
        let retained = MapPinEntranceIdentity.saved("retained")
        let departing = MapPinEntranceIdentity.saved("departing")
        var state = MapPinEntranceKeyState()

        XCTAssertEqual(
            state.prepare(for: [retained, departing], reduceMotion: false),
            [retained, departing]
        )
        XCTAssertEqual(state.prepare(for: [retained], reduceMotion: false), [retained])
        XCTAssertFalse(state.isPresented(retained))
    }

    func testEntranceIdentityStatePresentsImmediatelyForReduceMotion() {
        let pin = MapPinEntranceIdentity.search("candidate")
        var state = MapPinEntranceKeyState()

        XCTAssertNil(state.prepare(for: [pin], reduceMotion: true))
        XCTAssertTrue(state.isPresented(pin))
    }

    func testSelectionLifetimeAndLayeringFixtureRequiresDurableTopmostSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-289-selection-lifetime-layering-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_results"] as? [String: Any])

        XCTAssertEqual(expected["one_finger_zoom_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["selection_lifetime"] as? String, "unbounded_until_explicit_dismissal")
        XCTAssertEqual(expected["native_feature_binding_clear_preserves_selection"] as? Bool, true)
        XCTAssertEqual(expected["active_pin_and_title_render_after_all_inactive_annotations"] as? Bool, true)

        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertTrue(map.contains("let isSelected = highlightsCompactSelection"))
        XCTAssertTrue(map.contains("zPriority = descriptor.isSelected ? .max : .defaultUnselected"))
        XCTAssertTrue(map.contains("displayPriority = descriptor.isSelected ? .required : .defaultHigh"))
        XCTAssertTrue(map.contains("drawTitle("))
        XCTAssertTrue(map.contains("scheduleEmptyMapTapDismissal()"))
    }
    func testMapInteractionSourceLeavesNativeGesturesUnblockedAndKeepsPanDismissal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let card = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/PlaceProfileMapSurface.swift")
        )
        let continuousHandlerStart = try XCTUnwrap(
            map.range(of: "    private func handleMapCameraChange(")
        )
        let continuousHandlerEnd = try XCTUnwrap(
            map.range(
                of: "    private func handleMapCameraInteractionEnd(",
                range: continuousHandlerStart.upperBound..<map.endIndex
            )
        )
        let continuousHandler = map[
            continuousHandlerStart.lowerBound..<continuousHandlerEnd.lowerBound
        ]

        XCTAssertTrue(map.contains("NativeMapView("))
        XCTAssertTrue(map.contains("MKMapView(frame: .zero)"))
        XCTAssertTrue(map.contains("mapView.selectableMapFeatures = [.pointsOfInterest]"))
        XCTAssertTrue(map.contains("mapView.showsUserLocation = parent.showsUserLocation"))
        XCTAssertTrue(map.contains("PassiveMapTapGestureRecognizer"))
        XCTAssertTrue(map.contains("recognizer.cancelsTouchesInView = false"))
        XCTAssertTrue(map.contains("recognizer.delaysTouchesBegan = false"))
        XCTAssertTrue(map.contains("shouldRecognizeSimultaneouslyWith otherGestureRecognizer"))
        XCTAssertTrue(map.contains("parent.onLongPress(coordinate)"))
        XCTAssertTrue(map.contains("parent.onEmptyMapTap()"))
        XCTAssertTrue(map.contains("parent.onNativeFeatureSelection(feature)"))
        XCTAssertTrue(map.contains("parent.onAnnotationTap(annotation.kind)"))
        XCTAssertTrue(map.contains("mapViewDidChangeVisibleRegion"))
        XCTAssertTrue(map.contains("regionDidChangeAnimated"))
        XCTAssertTrue(map.contains("parent.onCameraChange(mapView.region)"))
        XCTAssertTrue(map.contains("parent.onCameraInteractionEnd(mapView.region)"))
        XCTAssertTrue(map.contains("@State private var cameraRegionTracker"))
        XCTAssertTrue(map.contains("cameraRegionTracker.recordCameraChange(region)"))
        XCTAssertTrue(map.contains("cameraRegionTracker.finishCameraChange(region)"))
        XCTAssertFalse(continuousHandler.contains("Task"))
        XCTAssertFalse(continuousHandler.contains("withAnimation"))
        XCTAssertFalse(continuousHandler.contains("store."))
        XCTAssertFalse(continuousHandler.contains("registerMapZoom"))
        XCTAssertTrue(map.contains("requestCompactSelectionDismissal(trigger: .oneFingerPan)"))
        XCTAssertTrue(map.contains("MapSelectionLifetimePolicy.shouldDismiss"))
        XCTAssertTrue(map.contains("clusteringIdentifier = nil"))
        XCTAssertTrue(map.contains("mapView.convert(annotation.coordinate, toPointTo: mapView)"))
        XCTAssertTrue(map.contains("MapHitTesting.nextColocatedMarkerID"))
        XCTAssertTrue(map.contains("annotation.descriptor.isSelected"))
        XCTAssertTrue(map.contains("replaceCompactSelectionIfNeeded"))
        XCTAssertTrue(map.contains("MapActivePinRetention.places("))
        XCTAssertTrue(map.contains("retainingGroup: authorizedRoutedGroup"))
        XCTAssertTrue(map.contains("centerCompactSelection(on: candidate)"))
        XCTAssertFalse(map.contains("Dropped pin. Tap + to add it."))
        XCTAssertTrue(card.contains(".textSelection(.enabled)"))
        XCTAssertTrue(card.contains("Label(\"Copy coordinates\", systemImage: \"doc.on.doc\")"))
        XCTAssertFalse(card.contains(".transition(.move(edge: .bottom).combined(with: .opacity))"))
    }
    func testPassiveSingleTapObserverRecognizesImmediatelyWithoutBlockingMapMovement() {
        XCTAssertEqual(MapHitTesting.passiveTapAllowableMovement, 10)
    }

    func testWalkthroughUsesTheCanonicalHotchkissFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let add = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Add/AddScreen.swift")
        )

        XCTAssertTrue(
            add.contains("candidate = suggested ?? FirstVisitParkSuggestionPolicy.hotchkissPark")
        )
        XCTAssertFalse(add.contains("private static let hotchkissParkCandidate"))
    }

    func testInactiveNativeAnnotationsHideTitlesAndReuseStaticImages() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("canShowCallout = false"))
        XCTAssertTrue(map.contains("isSelected ? title : \"\""))
        XCTAssertTrue(map.contains("private static let imageCache = NSCache<NSString, UIImage>()"))
        XCTAssertTrue(map.contains("dequeueReusableAnnotationView("))
        XCTAssertTrue(map.contains("zPriority = descriptor.isSelected ? .max : .defaultUnselected"))
        XCTAssertFalse(map.contains("selectedReuseIdentifier"))
        XCTAssertFalse(map.contains("NativeMapClusterAnnotationView"))
        XCTAssertFalse(map.contains("activeMapAnnotationOverlay"))
        XCTAssertFalse(map.contains(".position(point)"))
    }
    func testNativeAnnotationPriorityMatchesOnlyTheSelectedCoordinate() {
        let selected = CLLocationCoordinate2D(latitude: 33.770_050_1, longitude: -118.193_739_5)
        let withinTolerance = CLLocationCoordinate2D(
            latitude: selected.latitude + (MapAnnotationPriorityPolicy.coordinateTolerance / 2),
            longitude: selected.longitude - (MapAnnotationPriorityPolicy.coordinateTolerance / 2)
        )
        let anotherPin = CLLocationCoordinate2D(
            latitude: selected.latitude + 0.001,
            longitude: selected.longitude
        )

        XCTAssertTrue(
            MapAnnotationPriorityPolicy.matches(
                selected,
                selectedCoordinate: selected
            )
        )
        XCTAssertTrue(
            MapAnnotationPriorityPolicy.matches(
                withinTolerance,
                selectedCoordinate: selected
            )
        )
        XCTAssertFalse(
            MapAnnotationPriorityPolicy.matches(
                anotherPin,
                selectedCoordinate: selected
            )
        )

        let localQueryRect = MapAnnotationPriorityPolicy.queryRect(centeredAt: selected)
        XCTAssertTrue(localQueryRect.contains(MKMapPoint(selected)))
        XCTAssertFalse(localQueryRect.contains(MKMapPoint(anotherPin)))
    }

    @MainActor
    func testDenseNativeAnnotationPolicyRetainsEveryGroupAndSelection() {
        let currentUser = densityProfile()
        let places = (0..<100).map { index in
            densityVisiblePlace(
                owner: currentUser,
                name: "Dense Place \(index)",
                category: "coffee",
                latitude: 34.02 + Double(index / 10) * 0.005,
                longitude: -118.30 + Double(index % 10) * 0.005,
                providerID: "mapkit_dense_\(index)",
                status: .been
            )
        }
        let groups = VisiblePlaceGrouping.groups(
            from: places,
            currentUserID: currentUser.id
        )
        let selectedKey = groups.last?.key
        let rendered = MapScreen.orderedAnnotationGroups(
            groups,
            selectedGroupKey: selectedKey
        )

        XCTAssertEqual(rendered.count, groups.count)
        XCTAssertEqual(Set(rendered.map(\.key)).count, groups.count)
        XCTAssertEqual(rendered.last?.key, selectedKey)
    }
    func testMapUsesIndividualPinsInsteadOfCondensedClusters() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("clusteringIdentifier = nil"))
        XCTAssertFalse(map.contains("NativeMapClusterAnnotationView"))
        XCTAssertFalse(map.contains("MKClusterAnnotation"))
        XCTAssertFalse(map.contains("recme.map.cluster"))
    }
    func testREC360PhysicalDeviceRegressionFixtureRequiresFrontmostSingleTapSelection() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-360-active-pin-layering-and-tap-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let expected = try XCTUnwrap(fixture["expected_results"] as? [String: Any])
        let verified = try XCTUnwrap(fixture["post_fix_verification"] as? [String: Any])

        XCTAssertEqual(
            expected["selected_pin_and_title_render_above_every_other_map_annotation"] as? Bool,
            true
        )
        XCTAssertEqual(
            expected["competing_place_names_hidden_while_custom_map_content_is_shown"] as? Bool,
            true
        )
        XCTAssertEqual(expected["custom_pin_selects_on_first_completed_tap"] as? Bool, true)
        XCTAssertEqual(expected["inactive_pin_opacity_floor"] as? Double, 0.26)
        XCTAssertEqual(verified["physical_screen_coordinate_tap_selected_place"] as? String, "Canyon Lookout Trail")
        XCTAssertEqual(verified["selected_pin_and_title_visually_frontmost"] as? Bool, true)
        XCTAssertEqual(verified["competing_custom_place_names_visible"] as? Bool, false)
    }

    func testProviderPhotoTransportReusesSessionAndProtocolCaching() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repository = try String(
            contentsOf: root.appendingPathComponent(
                "Wander/Services/Remote/SupabaseRepositories.swift"
            )
        )

        XCTAssertTrue(repository.contains("private let photoSession: URLSession"))
        XCTAssertTrue(
            repository.contains(
                "photoSession: URLSession = PlacePhotoNetworkSession.shared"
            )
        )
        XCTAssertTrue(repository.contains("request.cachePolicy = .useProtocolCachePolicy"))
        XCTAssertTrue(repository.contains("photoSession.data(for: request)"))
        XCTAssertFalse(repository.contains("request.setValue(\"no-store\""))
        XCTAssertFalse(repository.contains("defer { session.invalidateAndCancel() }"))
    }

    func testMapLocationPermissionUsesExplicitEducationBeforeTheSystemPrompt() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        XCTAssertTrue(map.contains("MapNearbyPermissionPolicy.showsAttentionBadge"))
        XCTAssertTrue(map.contains("MapLocationEducationPrompt("))
        XCTAssertTrue(map.contains("permissionAction: OnboardingLocationPermissionPolicy.action("))
        XCTAssertTrue(map.contains("map.locationEducation.allow"))
        XCTAssertTrue(map.contains("map.locationEducation.cancel"))
        XCTAssertTrue(map.contains("if permissionAction != .request"))
        XCTAssertTrue(
            map.contains("OnboardingLocationPermissionPolicy.primaryTitle(for: permissionAction)")
        )
        XCTAssertTrue(map.contains("locationPermission.requestAccess()"))
        XCTAssertTrue(map.contains("WanderAnalyticsEvents.locationPermissionResult"))
        XCTAssertTrue(map.contains("guard Self.canShowUserLocation else"))
    }

    private func densityProfile() -> LocalProfile {
        LocalProfile(
            localID: "local_user_joe",
            serverID: "user_joe",
            handle: "joe",
            displayName: "Joe",
            syncState: .synced
        )
    }

    private func densityVisiblePlace(
        owner: LocalProfile,
        name: String,
        category: String,
        latitude: Double,
        longitude: Double,
        providerID: String,
        status: PlaceStatus
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "local_place_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: category,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(providerID)",
            serverID: "up_\(providerID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner
        )
    }
}

final class MapCoordinateCandidateTests: XCTestCase {
    @MainActor
    func testCoordinateCandidateUsesDroppedPinWithFallbackCategory() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.083238, longitude: -118.361472)

        let candidate = MapScreen.coordinateCandidate(at: coordinate)

        XCTAssertEqual(candidate.id, "coordinate_3408324_-11836147")
        XCTAssertEqual(candidate.name, "Dropped Pin")
        XCTAssertEqual(candidate.address, "34.08324, -118.36147")
        XCTAssertEqual(candidate.category, WanderPlaceCategory.fallbackPlace)
        XCTAssertEqual(candidate.primaryCategory, WanderPlaceCategory.fallbackPlace)
        XCTAssertNil(candidate.subcategory)
        XCTAssertEqual(candidate.categorySource, PlaceCategorySource.unknown.rawValue)
        XCTAssertEqual(candidate.sourceProvider, "coordinate")
        XCTAssertEqual(candidate.sourceProviderPlaceID, candidate.id)
        XCTAssertEqual(candidate.latitude, coordinate.latitude)
        XCTAssertEqual(candidate.longitude, coordinate.longitude)
    }

    @MainActor
    func testCoordinateDisplayRoundsToFiveDecimals() {
        let coordinate = CLLocationCoordinate2D(latitude: 33.999994, longitude: -118.000005)

        XCTAssertEqual(MapScreen.coordinateDisplay(for: coordinate), "33.99999, -118.00001")
    }

    @MainActor
    func testCoordinateCandidateCarriesResolvedCityIntoCopyableCardMetadata() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.083238, longitude: -118.361472)
        let candidate = MapScreen.coordinateCandidate(at: coordinate, locality: "West Hollywood")
        let place = PlaceSheetPlace(candidate: candidate)

        XCTAssertEqual(candidate.locality, "West Hollywood")
        XCTAssertTrue(place.isDroppedPin)
        XCTAssertEqual(place.locality, "West Hollywood")
        XCTAssertEqual(place.droppedPinCoordinateDisplay, "34.08324, -118.36147")
    }

    func testDroppedPinNameIsScopedToTheVisibleMemoryAttributes() throws {
        let customName = PlaceAttributeDraft(
            questionKey: PlaceMemoryAttributeKeys.droppedPinName,
            valueType: "text",
            stringValue: "Sunday overlook"
        )
        let localAttribute = LocalPlaceAttribute(
            localID: "local_attr_dropped_pin_name",
            userPlaceID: "up_dropped_pin",
            questionKey: customName.questionKey,
            valueType: customName.valueType,
            valueJSON: customName.valueJSON
        )

        XCTAssertEqual(
            DroppedPinNamePolicy.displayName(
                canonicalName: "Dropped Pin",
                sourceProvider: "coordinate",
                attributes: [localAttribute]
            ),
            "Sunday overlook"
        )
        XCTAssertEqual(
            DroppedPinNamePolicy.displayName(
                canonicalName: "Canonical Cafe",
                sourceProvider: "apple_maps",
                attributes: [localAttribute]
            ),
            "Canonical Cafe"
        )
        XCTAssertEqual(DroppedPinNamePolicy.normalized("   "), nil)
    }
}

final class MapFilterSelectionTests: XCTestCase {
    func testSourcePillsUseFeaturedFriendsAndYouContract() {
        XCTAssertEqual(MapSource.allCases, [.featured, .friends, .you])
        XCTAssertEqual(MapSource.featured.title, "Featured")
        XCTAssertEqual(MapSource.friends.title, "Friends")
        XCTAssertEqual(MapSource.you.title, "You")
        XCTAssertEqual(MapSource.featured.systemImage, "sparkles")
        XCTAssertEqual(MapSource.friends.systemImage, "person.2.fill")
        XCTAssertEqual(MapSource.you.systemImage, "person.fill")
        XCTAssertEqual(
            MapSource.featured.subtitle,
            "Featured shows you recommendations based on your taste"
        )
        XCTAssertEqual(
            MapSource.friends.subtitle,
            "All places from everyone you follow"
        )
        XCTAssertEqual(
            MapSource.you.subtitle,
            "Only your check-ins and Wanna Go places"
        )
    }

    func testSourceFilterRowFitsWithoutHorizontalScrolling() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let filterRow = try XCTUnwrap(
            map.components(separatedBy: "if !isMapSearchFocused {").last?
                .components(separatedBy: "if let mapFilterEmptyMessage").first
        )

        XCTAssertFalse(filterRow.contains("ScrollView(.horizontal"))
        XCTAssertTrue(filterRow.contains(".frame(maxWidth: .infinity, alignment: .center)"))
        XCTAssertTrue(filterRow.contains(".frame(minWidth: 44, minHeight: 48)"))
    }

    func testMapControlHierarchyKeepsFiltersAboveTheMapAndSearchAboveTabs() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )

        let filters = try XCTUnwrap(map.range(of: "if !isMapSearchFocused {"))
        let mapSpace = try XCTUnwrap(
            map.range(of: "Spacer()", range: filters.upperBound..<map.endIndex)
        )
        let search = try XCTUnwrap(
            map.range(of: "SearchBar(", range: mapSpace.upperBound..<map.endIndex)
        )

        XCTAssertLessThan(filters.lowerBound, mapSpace.lowerBound)
        XCTAssertLessThan(mapSpace.lowerBound, search.lowerBound)
        XCTAssertTrue(
            map.contains(
                "mapSearchDockClearance + MapControlLayout.selectedPlaceCardSearchGap"
            )
        )
        XCTAssertTrue(map.contains("static let selectedPlaceCardSearchGap: CGFloat = 12"))
        XCTAssertTrue(map.contains("MapSearchDockHeightPreferenceKey"))
        XCTAssertTrue(map.contains("measuredMapSearchDockHeight = height"))
        XCTAssertTrue(map.contains(".overlay(alignment: .bottomTrailing)"))
        XCTAssertTrue(
            map.contains(
                "if !isPlaceProfilePresented && !isMapSearchFocused"
            )
        )
        XCTAssertTrue(
            map.contains("mapSearchDockClearance - WanderTheme.spacing2 + nearbyLift")
        )
    }

    func testMoreStatusAndCategoriesMatchTheActiveSource() {
        XCTAssertFalse(MapMoreFilterPolicy.showsStatus(for: .featured))

        XCTAssertTrue(MapMoreFilterPolicy.showsStatus(for: .friends))

        XCTAssertTrue(MapMoreFilterPolicy.showsStatus(for: .you))
        XCTAssertEqual(MapMoreFilterPolicy.collapsedCategoryCount, 6)
        XCTAssertEqual(MapMoreFilterPolicy.categories(showingAll: false).count, 6)
        XCTAssertEqual(
            MapMoreFilterPolicy.categories(showingAll: false),
            Array(WanderPlaceCategory.editableCategories.prefix(6))
        )
        XCTAssertEqual(
            MapMoreFilterPolicy.categories(showingAll: true),
            WanderPlaceCategory.editableCategories
        )
    }

    func testPinEntranceStaysInsideTheShortMotionBudget() {
        XCTAssertEqual(MapPinEntranceStyle.duration, 0.40, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.maximumAnimatedPinCount, 12)
        XCTAssertGreaterThanOrEqual(MapPinEntranceStyle.hiddenScale, 0.70)
        XCTAssertLessThan(MapPinEntranceStyle.hiddenScale, 0.80)
        XCTAssertGreaterThan(MapPinEntranceStyle.hiddenVerticalOffset, 0)
        XCTAssertEqual(MapPinEntranceStyle.springBounce, 0.60, accuracy: 0.001)
        XCTAssertLessThan(MapPinEntranceStyle.fadeOutDuration, MapPinEntranceStyle.springDuration)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: -1), 0, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 1), 0.015, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 100), 0.06, accuracy: 0.001)
        XCTAssertTrue(MapPinEntranceStyle.shouldAnimate(index: 0, totalCount: 120))
        XCTAssertTrue(MapPinEntranceStyle.shouldAnimate(index: 11, totalCount: 120))
        XCTAssertFalse(MapPinEntranceStyle.shouldAnimate(index: 12, totalCount: 120))
        XCTAssertFalse(MapPinEntranceStyle.shouldAnimate(index: -1, totalCount: 120))
    }

    func testPinEntrancePresentationTransitionsFromCapturedHiddenState() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureData = try Data(
            contentsOf: root.appendingPathComponent(
                "WanderTests/Fixtures/ios-fix/rec-303-map-pin-entrance-bounce-pre.json"
            )
        )
        let fixture = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixtureData) as? [String: Any]
        )
        let snapshot = try XCTUnwrap(fixture["snapshot"] as? [String: Bool])
        let isVisible = try XCTUnwrap(snapshot["isVisible"])
        let reduceMotion = try XCTUnwrap(snapshot["reduceMotion"])
        let initiallyVisible = try XCTUnwrap(snapshot["presentationInitiallyVisible"])
        var presentation = MapPinEntrancePresentation()

        XCTAssertEqual(presentation.isPresented, initiallyVisible)
        XCTAssertEqual(
            presentation.renderedVisibility(
                isVisible: isVisible,
                reduceMotion: reduceMotion
            ),
            initiallyVisible
        )

        presentation.setVisible(isVisible)

        XCTAssertTrue(presentation.isPresented)
        XCTAssertTrue(
            presentation.renderedVisibility(isVisible: isVisible, reduceMotion: reduceMotion)
        )

        presentation.setVisible(false)

        XCTAssertFalse(presentation.isPresented)
        XCTAssertTrue(
            presentation.renderedVisibility(isVisible: true, reduceMotion: true)
        )
    }

    func testFilterTransitionIsScopedToPinsAndKeepsLiquidGlass() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let theme = try String(
            contentsOf: root.appendingPathComponent("Wander/DesignSystem/WanderTheme.swift")
        )
        let filterChipSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSourceFilterChip: View {").last?
                .components(separatedBy: "private struct MapMoreFilterChip: View {").first
        )

        XCTAssertFalse(filterChipSource.contains(".scaleEffect("))
        XCTAssertFalse(map.contains("visibleTransitionGroupKeys"))
        XCTAssertFalse(map.contains("transitionMapPins("))
        XCTAssertTrue(map.contains("MapRenderProjectionCache<"))
        XCTAssertTrue(map.contains("private final class NativeMapPinAnnotationView"))
        XCTAssertTrue(map.contains("private var presentedAnnotationID: String?"))
        XCTAssertTrue(map.contains("let shouldAnimateEntrance = presentedAnnotationID != descriptor.id"))
        XCTAssertTrue(map.contains("animateEntrance("))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenScale"))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenVerticalOffset"))
        XCTAssertTrue(map.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(map.contains("guard !reduceMotion else"))
        XCTAssertTrue(map.contains("alpha = 0"))
        XCTAssertTrue(map.contains("withDuration: MapPinEntranceStyle.springDuration"))
        XCTAssertTrue(map.contains("attachGestureObservers(to mapView: MKMapView)"))
        XCTAssertFalse(map.contains("@State private var mapPressLocation"))
        XCTAssertFalse(map.contains("@State private var lastMapPressPoint"))
        XCTAssertFalse(map.contains("incomingGroups + departingGroups"))
        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *) {"))
        XCTAssertFalse(theme.contains("isElevated"))
    }

    func testMapSearchCapsuleUsesLiquidGlassOnIOS26WithFlatFallback() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        let searchBarSource = try XCTUnwrap(
            map.components(separatedBy: "private struct SearchBar: View {").last?
                .components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier {").first
        )
        let searchSurfaceSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSearchCapsuleSurfaceModifier: ViewModifier {").last?
                .components(separatedBy: "private struct MapSearchCancelButton: View {").first
        )
        let filterChipSource = try XCTUnwrap(
            map.components(separatedBy: "private struct MapSourceFilterChip: View {").last?
                .components(separatedBy: "private struct MapMoreFilterChip: View {").first
        )

        XCTAssertTrue(searchBarSource.contains(".mapSearchCapsuleSurface()"))
        XCTAssertFalse(searchBarSource.contains(".wanderGlassCapsule()"))
        XCTAssertTrue(searchBarSource.contains("minHeight: isFocused.wrappedValue ? 56 : 48"))
        XCTAssertTrue(searchBarSource.contains(".snappy(duration: 0.24, extraBounce: 0.08)"))
        XCTAssertTrue(searchBarSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertTrue(searchBarSource.contains("@State private var draftQuery"))
        XCTAssertTrue(searchBarSource.contains("Task.sleep(for: .milliseconds(80))"))
        XCTAssertTrue(searchSurfaceSource.contains("if #available(iOS 26.0, *)"))
        XCTAssertTrue(searchSurfaceSource.contains(".glassEffect("))
        XCTAssertTrue(searchSurfaceSource.contains(".tint(appearance.isDark ? Color.black.opacity(0.50) : nil)"))
        XCTAssertTrue(searchSurfaceSource.contains(".interactive(true)"))
        XCTAssertTrue(searchSurfaceSource.contains(".background(.ultraThinMaterial, in: Capsule())"))
        XCTAssertFalse(searchSurfaceSource.contains(".shadow("))
        XCTAssertTrue(filterChipSource.contains(".wanderGlassCapsule("))
    }

    func testFeaturedIsTheOnlyDefaultSourceAndMoreDefaultsToAll() {
        let state = MapFilterState()

        XCTAssertEqual(state.source, .featured)
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertTrue(state.more.people.isEmpty)
        XCTAssertEqual(state.more.status, .all)
        XCTAssertEqual(state.more.activeSectionCount, 0)
    }

    func testResetUsesTheConfiguredDefaultAndClearsMoreFilters() {
        var state = MapFilterState(
            source: .featured,
            more: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_ben"],
                status: .checkIns
            )
        )

        state.reset(to: .friends)

        XCTAssertEqual(state, MapFilterState(source: .friends))
    }

    func testAllInEveryMoreSectionAddsNoRefinement() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let stranger = profile(id: "user_stranger")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let followedWanna = visiblePlace(owner: ben, name: "Ben Wanna", longitude: -118.24, status: .wannaGo)
        let strangerCheckIn = visiblePlace(owner: stranger, name: "Stranger Been", longitude: -118.23, status: .been)

        let visible = MapFilterSelection.friendsPlaces(
            from: [strangerCheckIn, followedWanna, ownCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([followedWanna.id]))
    }

    func testFriendsSourceAndMoreSelectionsCombineAsIntersections() {
        let state = MapFilterState(
            source: .friends,
            more: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                people: ["user_ben", "user_juana"],
                status: .checkIns
            )
        )
        let ben = profile(id: "user_ben")
        let juana = profile(id: "user_juana")
        let benCoffee = visiblePlace(owner: ben, name: "Ben Coffee", status: .been)
        let juanaCoffee = visiblePlace(owner: juana, name: "Juana Coffee", longitude: -118.24, status: .been)
        let juanaWanna = visiblePlace(owner: juana, name: "Juana Wanna", longitude: -118.23, status: .wannaGo)

        let visible = MapFilterSelection.friendsPlaces(
            from: [juanaWanna, juanaCoffee, benCoffee],
            currentUserID: "user_joe",
            followedOwnerIDs: [ben.id, juana.id],
            refinements: state.more
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([benCoffee.id, juanaCoffee.id]))
    }

    func testSpecificMoreOptionsAreOrWithinASectionAndAndAcrossSections() {
        let selection = MapMoreFilterSelection(
            categories: [WanderPlaceCategory.coffeeTeaSweets, WanderPlaceCategory.barsNightlife],
            people: ["user_ben", "user_juana"],
            status: .wanna
        )

        XCTAssertTrue(
            MapFilterSelection.matches(
                status: .wannaGo,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_juana",
                selection: selection
            )
        )
        XCTAssertFalse(
            MapFilterSelection.matches(
                status: .been,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_juana",
                selection: selection
            )
        )
        XCTAssertFalse(
            MapFilterSelection.matches(
                status: .wannaGo,
                category: WanderPlaceCategory.coffeeTeaSweets,
                ownerID: "user_ryan",
                selection: selection
            )
        )
    }

    func testAllClearsOnlyItsOwnSectionAndSourceSwitchClearsMore() {
        var state = MapFilterState()
        state.more.toggleCategory(WanderPlaceCategory.coffeeTeaSweets)
        state.more.togglePerson("user_ben")
        state.more.status = .checkIns

        XCTAssertEqual(state.more.activeSectionCount, 3)

        state.more.selectAllCategories()
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertEqual(state.more.people, Set(["user_ben"]))
        XCTAssertEqual(state.more.status, .checkIns)
        XCTAssertEqual(state.more.activeSectionCount, 2)

        state.selectSource(.friends)
        XCTAssertEqual(state.source, .friends)
        XCTAssertTrue(state.more.categories.isEmpty)
        XCTAssertTrue(state.more.people.isEmpty)
        XCTAssertEqual(state.more.status, .all)
        XCTAssertEqual(state.more.activeSectionCount, 0)
    }

    func testYouSourceIncludesOnlyOwnCheckInsAndWannaPlaces() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let ownWanna = visiblePlace(owner: joe, name: "Joe Wanna", longitude: -118.24, status: .wannaGo)
        let friendCheckIn = visiblePlace(owner: ben, name: "Ben Been", longitude: -118.23, status: .been)

        let visible = MapFilterSelection.ownPlaces(
            from: [friendCheckIn, ownWanna, ownCheckIn],
            currentUserID: joe.id,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(visible.map(\.id)), Set([ownCheckIn.id, ownWanna.id]))
    }

    func testYouSourceCombinesCategoriesAndStatus() {
        let joe = profile(id: "user_joe")
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", status: .been)
        let ownWanna = visiblePlace(owner: joe, name: "Joe Wanna", longitude: -118.24, status: .wannaGo)

        let visible = MapFilterSelection.ownPlaces(
            from: [ownWanna, ownCheckIn],
            currentUserID: joe.id,
            refinements: MapMoreFilterSelection(
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                status: .wanna
            )
        )

        XCTAssertEqual(visible.map(\.id), [ownWanna.id])
    }

    private func profile(id: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: id,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        longitude: Double = -118.25,
        status: PlaceStatus
    ) -> VisiblePlace {
        let providerID = name.lowercased().replacingOccurrences(of: " ", with: "_")
        let place = LocalPlace(
            localID: "local_place_\(owner.id)_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: WanderPlaceCategory.coffeeTeaSweets,
            latitude: 34.05,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)",
            serverID: "up_\(owner.id)_\(providerID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }
}

final class MapFeaturedSelectionTests: XCTestCase {
    private let losAngelesRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25),
        span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
    )

    func testFeaturedIncludesCommunityCheckInsButNeverWannaOrOutsideViewport() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let stranger = profile(id: "user_stranger")
        let benCheckIn = visiblePlace(owner: ben, name: "Ben Been", status: .been)
        let benWanna = visiblePlace(owner: ben, name: "Ben Wanna", longitude: -118.24, status: .wannaGo)
        let ownCheckIn = visiblePlace(owner: joe, name: "Joe Been", longitude: -118.23, status: .been)
        let strangerCheckIn = visiblePlace(owner: stranger, name: "Stranger Been", longitude: -118.22, status: .been)
        let outsideCheckIn = visiblePlace(
            owner: ben,
            name: "Outside Been",
            latitude: 35,
            longitude: -118.21,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [benWanna, ownCheckIn, strangerCheckIn, outsideCheckIn, benCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(
            Set(featured.map(\.id)),
            Set([ownCheckIn.id, benCheckIn.id, strangerCheckIn.id])
        )
        XCTAssertTrue(
            MapFeaturedSelection.places(
                from: [benCheckIn, benWanna],
                currentUserID: joe.id,
                followedOwnerIDs: [ben.id],
                in: losAngelesRegion,
                refinements: MapMoreFilterSelection(status: .wanna)
            ).isEmpty
        )
    }

    func testFeaturedStillWorksWhenViewerFollowsNobody() {
        let joe = profile(id: "user_joe")
        let community = profile(id: "user_community")
        let ownCheckIn = visiblePlace(owner: joe, name: "Own", status: .been)
        let communityCheckIn = visiblePlace(
            owner: community,
            name: "Community",
            longitude: -118.24,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [communityCheckIn, ownCheckIn],
            currentUserID: joe.id,
            followedOwnerIDs: [],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(Set(featured.map(\.id)), Set([ownCheckIn.id, communityCheckIn.id]))
    }

    func testFeaturedPrioritizesFollowedContributorWhenEvidenceIsEqual() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let timestamp = Date(timeIntervalSince1970: 1_720_000_000)
        let followed = visiblePlace(
            owner: ben,
            name: "Followed Pick",
            providerID: "followed_pick",
            status: .been,
            ratingScore: 4,
            visitedAt: timestamp
        )
        let broaderCommunity = visiblePlace(
            owner: community,
            name: "Community Pick",
            longitude: -118.24,
            providerID: "community_pick_equal",
            status: .been,
            ratingScore: 4,
            visitedAt: timestamp
        )

        let featured = MapFeaturedSelection.places(
            from: [broaderCommunity, followed],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(),
            limit: 1
        )

        XCTAssertEqual(featured.map(\.place.canonicalName), ["Followed Pick"])
    }

    func testFeaturedCanRankHighFitCommunityPlaceAboveWeakFollowedPlace() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let tasteSave = visiblePlace(
            owner: joe,
            name: "Favorite Coffee",
            providerID: "favorite_coffee",
            category: WanderPlaceCategory.coffeeTeaSweets,
            status: .wannaGo
        )
        let weakFollowed = visiblePlace(
            owner: ben,
            name: "Weak Followed",
            longitude: -118.24,
            providerID: "weak_followed",
            category: WanderPlaceCategory.shopping,
            status: .been,
            ratingScore: 2
        )
        let highFitCommunity = visiblePlace(
            owner: community,
            name: "High Fit Community",
            longitude: -118.23,
            providerID: "high_fit_community",
            category: WanderPlaceCategory.coffeeTeaSweets,
            status: .been,
            ratingScore: 5,
            communitySaveCount: 5
        )

        let featured = MapFeaturedSelection.places(
            from: [weakFollowed, highFitCommunity],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(),
            tasteSaves: [PlaceSaveSummary(visiblePlace: tasteSave, attributes: [])],
            limit: 1
        )

        XCTAssertEqual(featured.map(\.place.canonicalName), ["High Fit Community"])
    }

    func testFeaturedPeopleRefinementNarrowsWithoutChangingSource() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let community = profile(id: "user_community")
        let followed = visiblePlace(owner: ben, name: "Ben Pick", status: .been)
        let broaderCommunity = visiblePlace(
            owner: community,
            name: "Community Pick",
            longitude: -118.24,
            status: .been
        )

        let featured = MapFeaturedSelection.places(
            from: [broaderCommunity, followed],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection(people: [ben.id])
        )

        XCTAssertEqual(featured.map(\.id), [followed.id])
    }

    func testFeaturedRanksCommunitySupportBeforeRatingAndRecency() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let juana = profile(id: "user_juana")
        let olderDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newerDate = Date(timeIntervalSince1970: 1_710_000_000)
        let communityOne = visiblePlace(
            owner: ben,
            name: "Community Pick",
            providerID: "community_pick",
            status: .been,
            ratingScore: 3,
            visitedAt: olderDate
        )
        let communityTwo = visiblePlace(
            owner: juana,
            name: "Community Pick",
            providerID: "community_pick",
            status: .been,
            ratingScore: 3,
            visitedAt: olderDate
        )
        let soloFavorite = visiblePlace(
            owner: ben,
            name: "Solo Favorite",
            longitude: -118.23,
            providerID: "solo_favorite",
            status: .been,
            ratingScore: 5,
            visitedAt: newerDate
        )

        let featured = MapFeaturedSelection.places(
            from: [soloFavorite, communityOne, communityTwo],
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id, juana.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )
        let groups = VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id)

        XCTAssertEqual(groups.map { $0.primary.place.canonicalName }, ["Community Pick", "Solo Favorite"])
        XCTAssertEqual(groups.first?.saveCount, 2)
    }

    func testFeaturedCapsDensityByPlaceGroup() {
        let joe = profile(id: "user_joe")
        let ben = profile(id: "user_ben")
        let candidates = (0..<30).map { index in
            visiblePlace(
                owner: ben,
                name: "Place \(index)",
                latitude: 34.0 + Double(index) * 0.001,
                longitude: -118.25,
                providerID: "place_\(index)",
                status: .been
            )
        }

        let featured = MapFeaturedSelection.places(
            from: candidates,
            currentUserID: joe.id,
            followedOwnerIDs: [ben.id],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )

        XCTAssertEqual(
            VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id).count,
            MapFeaturedSelection.maximumPlaceGroupCount
        )
    }

    func testFeaturedLargeCandidateRankingStaysLightweight() {
        let joe = profile(id: "user_joe")
        let community = profile(id: "user_community")
        let candidates = (0..<8_000).map { index in
            visiblePlace(
                owner: community,
                name: "Candidate \(index)",
                latitude: 34.0 + Double(index % 100) * 0.001,
                longitude: -118.25,
                providerID: "candidate_\(index)",
                category: index.isMultiple(of: 2)
                    ? WanderPlaceCategory.coffeeTeaSweets
                    : WanderPlaceCategory.restaurantsFood,
                status: .been,
                ratingScore: Double(index % 6),
                communitySaveCount: (index % 8) + 1
            )
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let featured = MapFeaturedSelection.places(
            from: candidates,
            currentUserID: joe.id,
            followedOwnerIDs: [],
            in: losAngelesRegion,
            refinements: MapMoreFilterSelection()
        )
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt

        XCTAssertEqual(
            VisiblePlaceGrouping.groups(from: featured, currentUserID: joe.id).count,
            MapFeaturedSelection.maximumPlaceGroupCount
        )
        XCTAssertLessThan(elapsed, 2, "Featured ranking should remain a local, sub-two-second pass for 8,000 candidates")
    }

    func testViewportRefreshWaitsUntilCameraLeavesPrefetchBuffer() {
        let initialRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.2)
        )
        let loadedViewport = MapViewportRefreshPolicy.prefetchedViewport(for: initialRegion)
        let insideRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.04, longitude: -117.95),
            span: initialRegion.span
        )
        let outsideRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34.08, longitude: -117.95),
            span: initialRegion.span
        )

        XCTAssertEqual(loadedViewport.minLatitude, 33.9, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.maxLatitude, 34.1, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.minLongitude, -118.2, accuracy: 0.000_001)
        XCTAssertEqual(loadedViewport.maxLongitude, -117.8, accuracy: 0.000_001)
        XCTAssertFalse(
            MapViewportRefreshPolicy.shouldRefresh(
                visibleRegion: insideRegion,
                loadedViewport: loadedViewport
            )
        )
        XCTAssertTrue(
            MapViewportRefreshPolicy.shouldRefresh(
                visibleRegion: outsideRegion,
                loadedViewport: loadedViewport
            )
        )
    }

    func testAnnotationViewportContractsAfterZoomingBackIn() {
        let zoomedOutRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 34, longitude: -118),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )
        let renderedViewport = MapViewportRefreshPolicy.prefetchedViewport(for: zoomedOutRegion)
        let zoomedInRegion = MKCoordinateRegion(
            center: zoomedOutRegion.center,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )

        XCTAssertTrue(
            MapAnnotationViewportPolicy.shouldRefresh(
                visibleRegion: zoomedInRegion,
                renderedViewport: renderedViewport
            )
        )
    }

    private func profile(id: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: id,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        latitude: Double = 34.05,
        longitude: Double = -118.25,
        providerID: String? = nil,
        category: String = WanderPlaceCategory.restaurantsFood,
        status: PlaceStatus,
        ratingScore: Double? = nil,
        visitedAt: Date? = nil,
        communitySaveCount: Int = 0
    ) -> VisiblePlace {
        let providerID = providerID ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
        let place = LocalPlace(
            localID: "local_place_\(owner.id)_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: category,
            primaryCategory: category,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)_\(status.rawValue)",
            serverID: "up_\(owner.id)_\(providerID)_\(status.rawValue)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            ratingScore: ratingScore,
            recommendedScore: ratingScore,
            recommendedCount: ratingScore == nil ? 0 : 1,
            visitedAt: visitedAt,
            savedAt: visitedAt ?? .now,
            sourceType: "test",
            syncState: .synced
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner,
            communitySaveCount: communitySaveCount
        )
    }
}

final class MapSocialOwnerSelectionTests: XCTestCase {
    func testPeopleOptionsExcludeYouAndSortEveryFollowedProfileAlphabetically() {
        let joe = profile(id: "user_joe", displayName: "Joe")
        let juana = profile(id: "user_juana", displayName: "Juana")
        let ben = profile(id: "user_ben", displayName: "Ben")

        let options = MapSocialOwnerSelection.options(
            currentUser: joe,
            following: [juana, joe, ben, ben]
        )

        XCTAssertEqual(options.map(\.id), [ben.id, juana.id])
        XCTAssertEqual(options.map(\.displayName), ["Ben", "Juana"])
    }

    private func profile(id: String, displayName: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: id,
            displayName: displayName,
            syncState: .synced
        )
    }
}

final class MapPinOutlineBuilderTests: XCTestCase {
    func testPersonalBeenSaveProducesOneSolidPersonalOutline() {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser])
        XCTAssertEqual(outlines.map(\.status), [.been])
        XCTAssertNil(outlines.first?.secondaryStatus)
        XCTAssertEqual(outlines.first?.dashPattern ?? [], [CGFloat]())
        XCTAssertEqual(outlines.first?.arcs.count, 1)
    }

    func testPersonalAndSocialSavesProduceTwoStatusAwareOutlines() {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .wannaGo),
                MapPinSaveState(ownership: .social, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.wannaGo, .been])
        XCTAssertEqual(outlines.compactMap(\.secondaryStatus), [])
        XCTAssertEqual(outlines.first?.dashPattern ?? [], MapPinVisualMetrics.wannaDashPattern)
        XCTAssertEqual(outlines.last?.dashPattern ?? [], [CGFloat]())
    }

    func testMixedSocialSavesKeepWannaVisibleAlongsideAnyNumberOfBeenSaves() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .social, status: .wannaGo),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .been)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.social])
        XCTAssertEqual(outlines.map(\.status), [.been])
        XCTAssertEqual(outlines.map(\.secondaryStatus), [.wannaGo])

        let socialOutline = try XCTUnwrap(outlines.first)
        XCTAssertEqual(socialOutline.arcs.map(\.status), [.been, .wannaGo])
        XCTAssertEqual(socialOutline.arcs.map(\.trimFrom), [0.028, 0.528])
        XCTAssertEqual(socialOutline.arcs.map(\.trimTo), [0.472, 0.972])
        XCTAssertEqual(socialOutline.arcs.map(\.rotationDegrees), [-90, -90])
        XCTAssertEqual(socialOutline.arcs[0].dashPattern, [])
        XCTAssertEqual(socialOutline.arcs[1].dashPattern, [1.5, 3.5])
    }

    func testRyanBeenJoeBeenAndMayaWannaProducePersonalRingAndSplitSocialHalo() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .been),
                MapPinSaveState(ownership: .social, status: .been),
                MapPinSaveState(ownership: .social, status: .wannaGo)
            ]
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.been, .been])
        XCTAssertNil(outlines[0].secondaryStatus)
        XCTAssertEqual(outlines[1].secondaryStatus, .wannaGo)
        XCTAssertEqual(outlines[0].arcs.count, 1)
        XCTAssertEqual(outlines[1].arcs.count, 2)
    }

    func testSingleSocialWannaRemainsOneFullDashedHalo() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .social, status: .wannaGo)
            ]
        )

        let socialOutline = try XCTUnwrap(outlines.first)
        XCTAssertNil(socialOutline.secondaryStatus)
        XCTAssertEqual(socialOutline.arcs.count, 1)
        XCTAssertEqual(socialOutline.arcs[0].status, .wannaGo)
        XCTAssertEqual(socialOutline.arcs[0].trimFrom, 0)
        XCTAssertEqual(socialOutline.arcs[0].trimTo, 1)
        XCTAssertEqual(socialOutline.arcs[0].dashPattern, MapPinVisualMetrics.wannaDashPattern)
    }

    func testMixedCurrentUserHistoryKeepsExistingBeenPrecedence() throws {
        let outlines = MapPinOutlineBuilder.outlines(
            for: [
                MapPinSaveState(ownership: .currentUser, status: .wannaGo),
                MapPinSaveState(ownership: .currentUser, status: .been)
            ]
        )

        let personalOutline = try XCTUnwrap(outlines.first)
        XCTAssertEqual(personalOutline.ownership, .currentUser)
        XCTAssertEqual(personalOutline.status, .been)
        XCTAssertNil(personalOutline.secondaryStatus)
        XCTAssertEqual(personalOutline.dashPattern, [])
    }

    @MainActor
    func testPinVisualMetricsTightenEmojiSpacingWithoutASelectionHalo() throws {
        XCTAssertEqual(MapPinVisualMetrics.discDiameter, 38)
        XCTAssertEqual(MapPinVisualMetrics.emojiDiameter, 24)
        XCTAssertEqual(MapPinVisualMetrics.outlineWidth, 3)
        XCTAssertEqual(MapPinVisualMetrics.secondaryOutlinePadding, -6)
        XCTAssertEqual(MapPinVisualMetrics.wannaDashPattern, [1.5, 3.5])
        XCTAssertEqual(MapPinVisualMetrics.activeTitleClearance, 2)
        XCTAssertGreaterThanOrEqual(
            MapPinVisualMetrics.activeTitleVerticalOffset(
                selectedScale: MapPinSelectionMotionStyle.selectedScale,
                outlineCount: 0
            ),
            (MapPinVisualMetrics.discDiameter * MapPinSelectionMotionStyle.selectedScale / 2)
                + MapPinVisualMetrics.activeTitleClearance
        )
        let noOutlineOffset = MapPinVisualMetrics.activeTitleVerticalOffset(
            selectedScale: MapPinSelectionMotionStyle.selectedScale,
            outlineCount: 0
        )
        let singleOutlineOffset = MapPinVisualMetrics.activeTitleVerticalOffset(
            selectedScale: MapPinSelectionMotionStyle.selectedScale,
            outlineCount: 1
        )
        let doubleOutlineOffset = MapPinVisualMetrics.activeTitleVerticalOffset(
            selectedScale: MapPinSelectionMotionStyle.selectedScale,
            outlineCount: 2
        )
        XCTAssertLessThan(noOutlineOffset, singleOutlineOffset)
        XCTAssertLessThan(singleOutlineOffset, doubleOutlineOffset)

        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let map = try String(
            contentsOf: root.appendingPathComponent("Wander/Features/Map/MapScreen.swift")
        )
        XCTAssertFalse(map.contains("selectionHalo"))
        XCTAssertTrue(map.contains("MapPinVisualMetrics.activeTitleVerticalOffset("))
    }

    func testAccessibilityLabelDescribesOwnershipAndEveryVisibleStatusWithoutSaveCopy() {
        let label = MapPinAccessibility.label(
            outlines: [
                MapPinOutline(ownership: .currentUser, status: .been),
                MapPinOutline(ownership: .social, status: .been, secondaryStatus: .wannaGo)
            ],
            category: "Restaurant",
            placeName: "Bar Nido"
        )

        XCTAssertEqual(
            label,
            "Bar Nido, Restaurant, you checked in, social checked in and wanna"
        )
        XCTAssertFalse(label.localizedCaseInsensitiveContains("save"))
        XCTAssertFalse(label.localizedCaseInsensitiveContains("been"))
    }
}

final class VisiblePlaceGroupingTests: XCTestCase {
    @MainActor
    func testDroppedPinPresentationDoesNotReuseSameNamedPinAtAnotherCoordinate() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let northernPin = visiblePlace(
            owner: currentUser,
            name: "Dropped pin",
            category: "other",
            address: "40.71280, -124.21400",
            latitude: 40.7128,
            longitude: -124.2140,
            sourceProvider: "coordinate",
            providerID: "coordinate_4071280_-12421400",
            status: .been
        )
        let southernCandidate = MapScreen.coordinateCandidate(
            at: CLLocationCoordinate2D(latitude: 32.7157, longitude: -117.1611)
        )

        XCTAssertNil(
            MapScreen.matchingVisiblePlace(
                for: southernCandidate,
                in: [northernPin]
            )
        )
        XCTAssertEqual(
            MapScreen.matchingVisiblePlace(
                for: MapScreen.coordinateCandidate(
                    at: CLLocationCoordinate2D(latitude: 40.7128, longitude: -124.2140)
                ),
                in: [northernPin]
            )?.id,
            northernPin.id
        )
    }

    func testOutlineCatalogCarriesRyanJoeMayaTopologyToEveryGroupedSaveID() throws {
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let joe = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let maya = profile(id: "user_maya", handle: "maya", displayName: "Maya")
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05004,
            longitude: -118.25003,
            providerID: "mapkit_mutsu_ryan",
            status: .been,
            ratingScore: 5
        )
        let joeBeen = visiblePlace(
            owner: joe,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05022,
            longitude: -118.25018,
            providerID: "mapkit_mutsu_joe",
            status: .been,
            ratingScore: 4
        )
        let mayaWanna = visiblePlace(
            owner: maya,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05037,
            longitude: -118.25031,
            providerID: "mapkit_mutsu_maya",
            status: .wannaGo
        )

        let catalog = MapPinOutlineBuilder.outlineCatalog(
            for: [joeBeen, mayaWanna, ryanBeen],
            currentUserID: ryan.id
        )
        let outlines = try XCTUnwrap(catalog[joeBeen.id])

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.been, .been])
        XCTAssertNil(outlines[0].secondaryStatus)
        XCTAssertEqual(outlines[1].secondaryStatus, .wannaGo)
        XCTAssertEqual(catalog[ryanBeen.id], outlines)
        XCTAssertEqual(catalog[mayaWanna.id], outlines)
    }

    func testGroupsSameNamedNearbyPlaceAcrossDifferentProviderIDsAndStatuses() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let myWant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.05004,
            longitude: -118.25003,
            providerID: "mapkit_mutsu_joe_version",
            status: .wannaGo,
            ratingScore: nil,
            note: "want to try this"
        )
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "MUTSU",
            category: "place",
            latitude: 34.05039,
            longitude: -118.25041,
            providerID: "mapkit_mutsu_ryan_version",
            status: .been,
            ratingScore: 5,
            note: "sit at the bar"
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [ryanBeen, myWant],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].primary.owner.id, currentUser.id)
        XCTAssertEqual(groups[0].primary.userPlace.status, .wannaGo)
        XCTAssertEqual(groups[0].places.map(\.owner.id), [currentUser.id, ryan.id])

        let outlines = MapPinOutlineBuilder.outlines(
            for: groups[0].places.map { visiblePlace in
                MapPinSaveState(
                    ownership: visiblePlace.owner.id == currentUser.id ? .currentUser : .social,
                    status: visiblePlace.userPlace.status
                )
            }
        )

        XCTAssertEqual(outlines.map(\.ownership), [.currentUser, .social])
        XCTAssertEqual(outlines.map(\.status), [.wannaGo, .been])
    }

    func testDoesNotGroupSameNamedPlacesWhenCoordinatesAreFarApart() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let firstPlace = visiblePlace(
            owner: currentUser,
            name: "Blue Bottle Coffee",
            category: "coffee",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_blue_bottle_first",
            status: .wannaGo
        )
        let secondPlace = visiblePlace(
            owner: ryan,
            name: "Blue Bottle Coffee",
            category: "coffee",
            latitude: 34.080,
            longitude: -118.290,
            providerID: "mapkit_blue_bottle_second",
            status: .been,
            ratingScore: 4
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [firstPlace, secondPlace],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.saveCount), [1, 1])
    }

    func testDoesNotGroupDifferentPlacesAtSameCoordinate() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let restaurant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_mutsu",
            status: .wannaGo
        )
        let coffee = visiblePlace(
            owner: ryan,
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_maru",
            status: .been,
            ratingScore: 5
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [restaurant, coffee],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertFalse(VisiblePlaceGrouping.matches(restaurant, coffee))
        XCTAssertEqual(groups.map(\.primary.place.canonicalName), ["Mutsu", "Maru Coffee"])
    }

    @MainActor
    func testSelectedMapAnnotationGroupMovesToTheEndWithoutRegroupingPlaces() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let places = [
            visiblePlace(
                owner: currentUser,
                name: "First Place",
                category: "coffee",
                latitude: 34.050,
                longitude: -118.250,
                providerID: "mapkit_first",
                status: .been
            ),
            visiblePlace(
                owner: currentUser,
                name: "Selected Place",
                category: "restaurant",
                latitude: 34.060,
                longitude: -118.260,
                providerID: "mapkit_selected",
                status: .been
            ),
            visiblePlace(
                owner: currentUser,
                name: "Last Place",
                category: "park",
                latitude: 34.070,
                longitude: -118.270,
                providerID: "mapkit_last",
                status: .wannaGo
            )
        ]
        let groups = VisiblePlaceGrouping.groups(from: places, currentUserID: currentUser.id)
        let selectedKey = groups[1].key

        let ordered = MapScreen.orderedAnnotationGroups(
            groups,
            selectedGroupKey: selectedKey
        )

        XCTAssertEqual(ordered.map(\.key), [groups[0].key, groups[2].key, selectedKey])
        XCTAssertEqual(Set(ordered.map(\.key)), Set(groups.map(\.key)))
    }

    func testGroupsSameNamedAddressAcrossDifferentCoordinates() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let myWant = visiblePlace(
            owner: currentUser,
            name: "Mutsu",
            category: "restaurant",
            address: "412 Sunset Blvd",
            latitude: 34.050,
            longitude: -118.250,
            providerID: "mapkit_mutsu_address_joe",
            status: .wannaGo
        )
        let ryanBeen = visiblePlace(
            owner: ryan,
            name: "Mutsu",
            category: "restaurant",
            address: "412 Sunset Blvd",
            latitude: 34.056,
            longitude: -118.257,
            providerID: "mapkit_mutsu_address_ryan",
            status: .been,
            ratingScore: 5
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [ryanBeen, myWant],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(VisiblePlaceGrouping.matches(myWant, ryanBeen))
        XCTAssertEqual(groups[0].primary.owner.id, currentUser.id)
    }

    func testGroupingNormalizationPreservesPunctuationDiacriticsAndWhitespaceSemantics() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let accented = visiblePlace(
            owner: currentUser,
            name: "Café Déjà-Vu!",
            category: "coffee",
            address: "42  Rue-de l’Été",
            latitude: 34.050,
            longitude: -118.250,
            sourceProvider: "  GOOGLE   PLACES  ",
            providerID: "  Café-ID  ",
            status: .wannaGo
        )
        let normalized = visiblePlace(
            owner: ryan,
            name: "cafe deja vu",
            category: "coffee",
            address: "42 rue de l ete",
            latitude: 34.056,
            longitude: -118.257,
            sourceProvider: "google places",
            providerID: "café-id",
            status: .been
        )

        XCTAssertTrue(VisiblePlaceGrouping.matches(accented, normalized))
        XCTAssertEqual(
            VisiblePlaceGrouping.groups(
                from: [accented, normalized],
                currentUserID: currentUser.id
            ).count,
            1
        )
    }

    func testGroupsLegacyAndCanonicalHotchkissAddressesIntoOnePin() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let legacySave = visiblePlace(
            owner: currentUser,
            name: "Hotchkiss Park",
            category: "park",
            address: "2302 4th Street",
            latitude: 34.0046,
            longitude: -118.4845,
            providerID: "hotchkiss-park-ocean-park",
            status: .been
        )
        let canonicalSave = visiblePlace(
            owner: ryan,
            name: "Hotchkiss Park",
            category: "park",
            address: "2302 4th St",
            latitude: 34.00585,
            longitude: -118.4842,
            sourceProvider: "walkthrough",
            providerID: "hotchkiss-park-santa-monica",
            status: .wannaGo
        )

        let groups = VisiblePlaceGrouping.groups(
            from: [legacySave, canonicalSave],
            currentUserID: currentUser.id
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(VisiblePlaceGrouping.matches(legacySave, canonicalSave))
        XCTAssertEqual(groups[0].saveCount, 2)
    }

    func testDoesNotGroupSameNamedPlacesAtDifferentStreetNumbers() {
        let currentUser = profile(id: "user_joe", handle: "joe", displayName: "Joe")
        let ryan = profile(id: "user_ryan", handle: "ryan", displayName: "Ryan")
        let firstPlace = visiblePlace(
            owner: currentUser,
            name: "Corner Market",
            category: "shop",
            address: "2302 4th St",
            latitude: 34.0046,
            longitude: -118.4845,
            providerID: "corner-market-first",
            status: .been
        )
        let secondPlace = visiblePlace(
            owner: ryan,
            name: "Corner Market",
            category: "shop",
            address: "2303 4th Street",
            latitude: 34.0146,
            longitude: -118.4945,
            providerID: "corner-market-second",
            status: .wannaGo
        )

        XCTAssertFalse(VisiblePlaceGrouping.matches(firstPlace, secondPlace))
        XCTAssertEqual(
            VisiblePlaceGrouping.groups(
                from: [firstPlace, secondPlace],
                currentUserID: currentUser.id
            ).count,
            2
        )
    }

    private func profile(id: String, handle: String, displayName: String) -> LocalProfile {
        LocalProfile(
            localID: "local_\(id)",
            serverID: id,
            handle: handle,
            displayName: displayName,
            syncState: .synced
        )
    }

    private func visiblePlace(
        owner: LocalProfile,
        name: String,
        category: String,
        address: String? = nil,
        latitude: Double,
        longitude: Double,
        sourceProvider: String = "mapkit",
        providerID: String,
        status: PlaceStatus,
        ratingScore: Double? = nil,
        note: String? = nil
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "local_place_\(providerID)",
            serverID: "place_\(providerID)",
            canonicalName: name,
            category: category,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: providerID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_\(owner.id)_\(providerID)",
            serverID: "up_\(owner.id)_\(providerID)",
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: .followers,
            note: note,
            ratingScore: ratingScore,
            recommendedScore: ratingScore,
            recommendedCount: ratingScore == nil ? 0 : 1,
            sourceType: "test",
            syncState: .synced
        )

        return VisiblePlace(id: userPlace.id, place: place, userPlace: userPlace, owner: owner)
    }
}
