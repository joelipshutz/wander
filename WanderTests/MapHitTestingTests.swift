import CoreGraphics
import MapKit
import XCTest
@testable import Wander

final class MapHitTestingTests: XCTestCase {
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
}

final class MapCoordinateCandidateTests: XCTestCase {
    @MainActor
    func testCoordinateCandidateUsesDroppedPinWithFallbackCategory() {
        let coordinate = CLLocationCoordinate2D(latitude: 34.083238, longitude: -118.361472)

        let candidate = MapScreen.coordinateCandidate(at: coordinate)

        XCTAssertEqual(candidate.id, "coordinate_3408324_-11836147")
        XCTAssertEqual(candidate.name, "Dropped pin")
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
}

final class MapFilterSelectionTests: XCTestCase {
    func testSourcePillsUseFeaturedAndFriendsContract() {
        XCTAssertEqual(MapSource.allCases, [.featured, .friends])
        XCTAssertEqual(MapSource.featured.title, "Featured")
        XCTAssertEqual(MapSource.friends.title, "Friends")
        XCTAssertEqual(MapSource.featured.systemImage, "sparkles")
        XCTAssertEqual(MapSource.friends.systemImage, "person.2.fill")
        XCTAssertEqual(
            MapSource.featured.subtitle,
            "Featured shows you recommendations based on your taste"
        )
        XCTAssertEqual(
            MapSource.friends.subtitle,
            "All places from everyone you follow"
        )
    }

    func testPinEntranceStaysInsideTheShortMotionBudget() {
        XCTAssertEqual(MapPinEntranceStyle.duration, 0.40, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(MapPinEntranceStyle.hiddenScale, 0.70)
        XCTAssertLessThan(MapPinEntranceStyle.hiddenScale, 0.80)
        XCTAssertGreaterThan(MapPinEntranceStyle.hiddenVerticalOffset, 0)
        XCTAssertEqual(MapPinEntranceStyle.springBounce, 0.60, accuracy: 0.001)
        XCTAssertLessThan(MapPinEntranceStyle.fadeOutDuration, MapPinEntranceStyle.springDuration)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: -1), 0, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 1), 0.015, accuracy: 0.001)
        XCTAssertEqual(MapPinEntranceStyle.staggerDelay(for: 100), 0.06, accuracy: 0.001)
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
        XCTAssertTrue(map.contains("visibleTransitionGroupKeys?.contains(group.key)"))
        XCTAssertTrue(map.contains("MapPinEntranceModifier("))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenScale"))
        XCTAssertTrue(map.contains("MapPinEntranceStyle.hiddenVerticalOffset"))
        XCTAssertTrue(map.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        XCTAssertFalse(map.contains("incomingGroups + departingGroups"))
        XCTAssertTrue(theme.contains("if #available(iOS 26.0, *) {"))
        XCTAssertFalse(theme.contains("isElevated"))
    }

    func testMapSearchCapsuleStaysFlatWhileFilterPillsKeepLiquidGlass() throws {
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
        XCTAssertTrue(searchSurfaceSource.contains(".background(.ultraThinMaterial, in: Capsule())"))
        XCTAssertFalse(searchSurfaceSource.contains(".glassEffect("))
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

        XCTAssertEqual(Set(visible.map(\.id)), Set([ownCheckIn.id, followedWanna.id]))
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

    func testAllClearsOnlyItsOwnSectionAndSourceSwitchPreservesMore() {
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

        state.source = .friends
        XCTAssertEqual(state.source, .friends)
        XCTAssertEqual(state.more.people, Set(["user_ben"]))
        XCTAssertEqual(state.more.status, .checkIns)
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
    func testPeopleOptionsPutYouFirstThenEveryFollowedProfileAlphabetically() {
        let joe = profile(id: "user_joe", displayName: "Joe")
        let juana = profile(id: "user_juana", displayName: "Juana")
        let ben = profile(id: "user_ben", displayName: "Ben")

        let options = MapSocialOwnerSelection.options(
            currentUser: joe,
            following: [juana, joe, ben, ben]
        )

        XCTAssertEqual(options.map(\.id), [joe.id, ben.id, juana.id])
        XCTAssertEqual(options.map(\.displayName), ["You", "Ben", "Juana"])
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

    func testDirectionAVisualMetricsKeepThreePointConcentricRingsAndSelectionHalo() {
        XCTAssertEqual(MapPinVisualMetrics.discDiameter, 38)
        XCTAssertEqual(MapPinVisualMetrics.outlineWidth, 3)
        XCTAssertEqual(MapPinVisualMetrics.secondaryOutlinePadding, -6)
        XCTAssertEqual(MapPinVisualMetrics.selectionHaloPadding, -10)
        XCTAssertEqual(MapPinVisualMetrics.wannaDashPattern, [1.5, 3.5])
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
