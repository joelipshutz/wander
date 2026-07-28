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
    func testFilterPillsMirrorPinOwnershipAndStatusGrammar() {
        XCTAssertEqual(MapFilter.you.title, "You")
        XCTAssertEqual(MapFilter.social.title, "Social")
        XCTAssertEqual(MapFilter.been.title, "Check-ins")
        XCTAssertEqual(MapFilter.wanna.title, "Wanna")

        XCTAssertEqual(MapFilter.you.systemImage, "person.fill")
        XCTAssertEqual(MapFilter.social.systemImage, "person.2.fill")
        XCTAssertEqual(MapFilter.been.systemImage, "circle.fill")
        XCTAssertEqual(MapFilter.wanna.systemImage, "circle.dotted")

        XCTAssertEqual(MapFilter.you.trimStyle(isSelected: true).dash, [])
        XCTAssertEqual(MapFilter.social.trimStyle(isSelected: true).dash, [])
        XCTAssertEqual(MapFilter.been.trimStyle(isSelected: true).dash, [])
        XCTAssertEqual(
            MapFilter.wanna.trimStyle(isSelected: true).dash,
            MapPinVisualMetrics.wannaDashPattern
        )
        XCTAssertEqual(MapFilter.you.trimStyle(isSelected: true).lineWidth, 2)
        XCTAssertEqual(MapFilter.you.trimStyle(isSelected: false).lineWidth, 1.25)
    }

    func testNoOwnerFiltersSelectedProducesNoPlaceFilters() {
        XCTAssertNil(
            MapFilterSelection.placeFilters(
                selectedFilters: [.been, .wanna],
                selectedSocialOwnerID: nil
            )
        )
    }

    func testNoStatusFiltersSelectedProducesNoPlaceFilters() {
        XCTAssertNil(
            MapFilterSelection.placeFilters(
                selectedFilters: [.you, .social],
                selectedSocialOwnerID: nil
            )
        )
    }

    func testAllOwnerAndStatusFiltersSelectedKeepsUnrestrictedGroups() {
        let filters = MapFilterSelection.placeFilters(
            selectedFilters: [.you, .social, .been, .wanna],
            selectedSocialOwnerID: nil
        )

        XCTAssertEqual(filters?.ownerScopes, Set(["you", "social"]))
        XCTAssertEqual(filters?.statuses, Set<PlaceStatus>())
        XCTAssertEqual(filters?.ownerIDs, Set<String>())
    }

    func testSingleStatusAndSocialOwnerSelectionBuildsNarrowFilters() {
        let filters = MapFilterSelection.placeFilters(
            selectedFilters: [.social, .wanna],
            selectedSocialOwnerID: "user_maya"
        )

        XCTAssertEqual(filters?.ownerScopes, Set(["social"]))
        XCTAssertEqual(filters?.statuses, Set([.wannaGo]))
        XCTAssertEqual(filters?.ownerIDs, Set(["user_maya"]))
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
