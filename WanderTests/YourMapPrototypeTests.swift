import XCTest
@testable import Wander

final class YourMapPrototypeTests: XCTestCase {
    func testRepresentativeVolumesAreDeterministic() {
        for volume in YourMapPrototypeDataVolume.allCases {
            let first = YourMapPrototypeDataset.make(volume: volume)
            let second = YourMapPrototypeDataset.make(volume: volume)

            XCTAssertEqual(first.places.count, volume.count)
            XCTAssertEqual(first.places, second.places)
        }
    }

    func testVolumeLaunchArgumentFallsBackToMedium() {
        XCTAssertEqual(
            YourMapPrototypeDataVolume.resolved(
                from: ["Wander", "-WanderYourMapPrototypeVolume", "small"]
            ),
            .small
        )
        XCTAssertEqual(
            YourMapPrototypeDataVolume.resolved(
                from: ["Wander", "-WanderYourMapPrototypeVolume", "not-a-volume"]
            ),
            .medium
        )
        XCTAssertEqual(YourMapPrototypeDataVolume.resolved(from: ["Wander"]), .medium)
    }

    func testLensUsesOrWithinDimensionAndAndAcrossDimensions() {
        let dataset = YourMapPrototypeDataset.make(volume: .large)
        let baseLens = YourMapPrototypeLens(
            statuses: [.been],
            categories: ["Coffee", "Restaurants"],
            cities: ["Los Angeles"]
        )
        let combined = dataset.places.filter { baseLens.matches($0, now: dataset.now) }

        XCTAssertFalse(combined.isEmpty)
        XCTAssertTrue(combined.allSatisfy { $0.status == .been })
        XCTAssertTrue(combined.allSatisfy { $0.city == "Los Angeles" })
        XCTAssertTrue(combined.allSatisfy { ["Coffee", "Restaurants"].contains($0.category) })

        var coffeeLens = baseLens
        coffeeLens.categories = ["Coffee"]
        var restaurantLens = baseLens
        restaurantLens.categories = ["Restaurants"]
        let separateIDs = Set(
            dataset.places.filter { coffeeLens.matches($0, now: dataset.now) }.map(\.id)
                + dataset.places.filter { restaurantLens.matches($0, now: dataset.now) }.map(\.id)
        )

        XCTAssertEqual(Set(combined.map(\.id)), separateIDs)
    }

    func testAnySelectedTagCanMatchButOtherSectionsStillNarrow() {
        let dataset = YourMapPrototypeDataset.make(volume: .large)
        let lens = YourMapPrototypeLens(
            statuses: [.been],
            tags: ["calm", "date night"],
            minimumRating: 4
        )
        let matches = dataset.places.filter { lens.matches($0, now: dataset.now) }

        XCTAssertFalse(matches.isEmpty)
        XCTAssertTrue(matches.allSatisfy { $0.status == .been })
        XCTAssertTrue(matches.allSatisfy { $0.rating >= 4 })
        XCTAssertTrue(matches.allSatisfy { !$0.tags.isDisjoint(with: ["calm", "date night"]) })
    }

    func testZeroResultLensKeepsItsSelectionUntilReset() {
        let dataset = YourMapPrototypeDataset.make(volume: .medium)
        let lens = YourMapPrototypeLens(
            categories: ["Coffee"],
            cities: ["Paris"],
            countries: ["United States"],
            tags: ["does-not-exist"]
        )

        XCTAssertTrue(dataset.places.filter { lens.matches($0, now: dataset.now) }.isEmpty)
        XCTAssertEqual(lens.categories, ["Coffee"])
        XCTAssertEqual(lens.cities, ["Paris"])
        XCTAssertEqual(lens.countries, ["United States"])
        XCTAssertEqual(lens.tags, ["does-not-exist"])
        XCTAssertEqual(lens.activeSectionCount, 3)
    }

    func testTimeRangesNarrowTheDataset() {
        let dataset = YourMapPrototypeDataset.make(volume: .large)
        let all = dataset.places.filter {
            YourMapPrototypeLens(timeRange: .all).matches($0, now: dataset.now)
        }
        let thisYear = dataset.places.filter {
            YourMapPrototypeLens(timeRange: .thisYear).matches($0, now: dataset.now)
        }
        let thisMonth = dataset.places.filter {
            YourMapPrototypeLens(timeRange: .thisMonth).matches($0, now: dataset.now)
        }

        XCTAssertEqual(all.count, dataset.places.count)
        XCTAssertLessThan(thisYear.count, all.count)
        XCTAssertLessThanOrEqual(thisMonth.count, thisYear.count)
    }

    func testInsightsUseBeenPlacesForRepeatRateAndSortCategories() {
        let dataset = YourMapPrototypeDataset.make(volume: .medium)
        let insights = YourMapPrototypeInsights(places: dataset.places, now: dataset.now)
        let beenPlaces = dataset.places.filter { $0.status == .been }
        let repeats = beenPlaces.filter { $0.visitCount > 1 }

        XCTAssertEqual(insights.totalCount, dataset.places.count)
        XCTAssertEqual(insights.repeatCount, repeats.count)
        XCTAssertEqual(
            insights.repeatRate,
            Double(repeats.count) / Double(beenPlaces.count),
            accuracy: 0.000_001
        )
        XCTAssertEqual(insights.categoryBreakdown.map(\.count), insights.categoryBreakdown.map(\.count).sorted(by: >))
        XCTAssertEqual(insights.monthlyActivity.count, 12)
        XCTAssertEqual(insights.monthlyActivity.map(\.count).reduce(0, +), dataset.places.count)
        XCTAssertEqual(insights.cityBreakdown.map(\.count).reduce(0, +), dataset.places.count)
        XCTAssertEqual(insights.countryBreakdown.map(\.count).reduce(0, +), dataset.places.count)
        XCTAssertTrue(insights.returnMagnets.allSatisfy { $0.status == .been && $0.visitCount > 1 })
        XCTAssertEqual(insights.returnMagnets.map(\.visitCount), insights.returnMagnets.map(\.visitCount).sorted(by: >))
    }

    func testGeographyExcludesUnknownsIndependentlyAndKeepsAllPlacesDenominator() {
        let values = [
            (" Los Angeles ", "United States"),
            ("Los Angeles", "Unknown country"),
            ("Unknown city", "Canada"),
            (" \n ", "Canada"),
            ("uNkNoWn CiTy", " UNKNOWN COUNTRY "),
            ("Unknown", "Unknown region"),
            ("Paris", "France"),
            ("Paris", ""),
        ]
        let places = values.enumerated().map { index, value in
            geographyPlace(id: index, city: value.0, country: value.1)
        }
        let insights = YourMapPrototypeInsights(places: places, now: Date())

        XCTAssertEqual(insights.totalCount, 8)
        XCTAssertEqual(insights.cityBreakdown.map(\.title), ["Los Angeles", "Paris"])
        XCTAssertEqual(insights.cityBreakdown.map(\.count), [2, 2])
        XCTAssertEqual(insights.cityBreakdown.map(\.fraction), [0.25, 0.25])
        XCTAssertEqual(insights.countryBreakdown.map(\.title), ["Canada", "France", "United States"])
        XCTAssertEqual(insights.countryBreakdown.map(\.count), [2, 1, 1])
        XCTAssertEqual(insights.countryBreakdown.map(\.fraction), [0.25, 0.125, 0.125])
    }

    func testGeographyWithOnlyMissingLocationsHasNoRankings() {
        let places = [geographyPlace(id: 0, city: "Unknown city", country: "Unknown country")]
        for input in [places, []] {
            let insights = YourMapPrototypeInsights(places: input, now: Date())
            XCTAssertTrue(insights.cityBreakdown.isEmpty)
            XCTAssertTrue(insights.countryBreakdown.isEmpty)
            XCTAssertEqual(insights.totalCount, input.count)
        }
    }

    private func geographyPlace(id: Int, city: String, country: String) -> YourMapPrototypePlace {
        YourMapPrototypePlace(
            id: "geography-\(id)", name: "Fixture", latitude: 0, longitude: 0,
            status: .been, category: "Restaurants", city: city, country: country,
            tags: [], rating: 4, visitCount: 1, lastVisitedAt: Date(timeIntervalSince1970: 1_787_623_200)
        )
    }

    func testSavedLensKeepsTheExactFilterRecipeAndExplainsIt() {
        let lens = YourMapPrototypeLens(
            timeRange: .thisYear,
            statuses: [.been],
            categories: ["Coffee"],
            cities: ["Los Angeles"],
            repeatOnly: true
        )
        let saved = YourMapPrototypeSavedLens(
            lens: lens,
            ordinal: 1,
            id: UUID(uuidString: "2F41DB41-399F-4C36-8F7E-CFD87C66A57A")!
        )

        XCTAssertEqual(saved.lens, lens)
        XCTAssertEqual(saved.title, "Coffee · Los Angeles")
        XCTAssertEqual(saved.detail, "5 selected options")
    }

    func testSavedLensSwipeOnlyRevealsTheTrailingDeleteAction() {
        XCTAssertEqual(YourMapPrototypeLensSwipePolicy.clampedOffset(24), 0)
        XCTAssertEqual(YourMapPrototypeLensSwipePolicy.clampedOffset(-28), -28)
        XCTAssertEqual(
            YourMapPrototypeLensSwipePolicy.clampedOffset(-120),
            -YourMapPrototypeLensSwipePolicy.revealWidth
        )
        XCTAssertEqual(YourMapPrototypeLensSwipePolicy.settledOffset(for: -20), 0)
        XCTAssertEqual(
            YourMapPrototypeLensSwipePolicy.settledOffset(for: -60),
            -YourMapPrototypeLensSwipePolicy.revealWidth
        )
    }

    func testShareLinksAreOpaqueAndDistinguishStaticFromLive() {
        let token = UUID(uuidString: "A94D4A30-31A3-48CB-B5BB-744F8F83B013")!
        let staticLink = YourMapPrototypeShareLink.make(format: .staticSnapshot, token: token)
        let liveLink = YourMapPrototypeShareLink.make(format: .liveLens, token: token)

        XCTAssertEqual(
            staticLink.url.absoluteString,
            "https://rec.me/maps/a94d4a30-31a3-48cb-b5bb-744f8f83b013?type=static"
        )
        XCTAssertEqual(
            liveLink.url.absoluteString,
            "https://rec.me/maps/a94d4a30-31a3-48cb-b5bb-744f8f83b013?type=live"
        )
        XCTAssertFalse(staticLink.url.absoluteString.contains("Coffee"))
        XCTAssertNotEqual(staticLink.url, liveLink.url)
    }

    func testInitialCuratedLensOnlyAppliesToUsefulDataVolumes() {
        XCTAssertEqual(YourMapPrototypeDataset.make(volume: .empty).initialLens, YourMapPrototypeLens())
        XCTAssertEqual(YourMapPrototypeDataset.make(volume: .small).initialLens, YourMapPrototypeLens())

        let mediumLens = YourMapPrototypeDataset.make(volume: .medium).initialLens
        XCTAssertEqual(mediumLens.statuses, [.been])
        XCTAssertEqual(mediumLens.categories, ["Coffee"])
        XCTAssertEqual(mediumLens.cities, ["Los Angeles"])
    }

    func testProfileDatasetUsesTheOwnersRealPlacesVisitsAndTags() throws {
        let now = Date(timeIntervalSince1970: 1_787_623_200)
        let place = LocalPlace(
            localID: "place-local",
            canonicalName: "Juniper Coffee",
            category: "cafe",
            locality: "Los Angeles",
            country: "United States",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let userPlace = LocalUserPlace(
            localID: "save-local",
            userID: "owner",
            placeID: place.id,
            status: .been,
            visibility: .selfOnly,
            ratingScore: 4.5,
            visitedAt: now,
            sourceType: "manual"
        )
        let visit = LocalPlaceVisit(
            localID: "visit-local",
            userPlaceID: userPlace.id,
            visitedAt: now,
            ratingScore: 4.5,
            tags: ["calm", "morning"]
        )
        let owner = LocalProfile(
            localID: "owner",
            handle: "owner",
            displayName: "Owner"
        )
        let visiblePlace = VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner
        )

        let dataset = YourMapPrototypeDataset.make(
            ownerID: "owner",
            userPlaces: [userPlace],
            visits: [visit],
            places: [place],
            visiblePlaces: [visiblePlace],
            now: now
        )
        let result = try XCTUnwrap(dataset.places.first)

        XCTAssertEqual(dataset.volume, .small)
        XCTAssertEqual(dataset.initialLens, YourMapPrototypeLens())
        XCTAssertEqual(result.id, place.id)
        XCTAssertEqual(result.name, "Juniper Coffee")
        XCTAssertEqual(result.city, "Los Angeles")
        XCTAssertEqual(result.country, "United States")
        XCTAssertEqual(result.tags, ["calm", "morning"])
        XCTAssertEqual(result.rating, 4.5)
        XCTAssertEqual(result.visitCount, 1)
        XCTAssertEqual(dataset.visiblePlaceByPlaceID[result.id]?.userPlace.id, userPlace.id)
    }

    func testProfileDatasetScopesLiveDataToTheRequestedMember() throws {
        let now = Date(timeIntervalSince1970: 1_787_623_200)
        let memberPlace = LocalPlace(
            localID: "member-place-local",
            canonicalName: "Member Coffee",
            category: "cafe",
            locality: "Los Angeles",
            country: "United States",
            latitude: 34.0522,
            longitude: -118.2437
        )
        let viewerPlace = LocalPlace(
            localID: "viewer-place-local",
            canonicalName: "Viewer Bakery",
            category: "bakery",
            locality: "New York",
            country: "United States",
            latitude: 40.7128,
            longitude: -74.0060
        )
        let memberUserPlace = LocalUserPlace(
            localID: "member-save-local",
            userID: "member",
            placeID: memberPlace.id,
            status: .been,
            visibility: .followers,
            visitedAt: now,
            sourceType: "manual"
        )
        let viewerUserPlace = LocalUserPlace(
            localID: "viewer-save-local",
            userID: "viewer",
            placeID: viewerPlace.id,
            status: .been,
            visibility: .selfOnly,
            visitedAt: now,
            sourceType: "manual"
        )
        let memberVisiblePlace = VisiblePlace(
            id: memberUserPlace.id,
            place: memberPlace,
            userPlace: memberUserPlace,
            owner: LocalProfile(localID: "member", handle: "member", displayName: "Member")
        )
        let viewerVisiblePlace = VisiblePlace(
            id: viewerUserPlace.id,
            place: viewerPlace,
            userPlace: viewerUserPlace,
            owner: LocalProfile(localID: "viewer", handle: "viewer", displayName: "Viewer")
        )
        let dataset = YourMapPrototypeDataset.make(
            ownerID: "member",
            userPlaces: [viewerUserPlace, memberUserPlace],
            visits: [
                LocalPlaceVisit(
                    localID: "viewer-visit-local",
                    userPlaceID: viewerUserPlace.id,
                    visitedAt: now,
                    tags: ["viewer-only"]
                ),
                LocalPlaceVisit(
                    localID: "member-visit-local",
                    userPlaceID: memberUserPlace.id,
                    visitedAt: now,
                    tags: ["member-only"]
                )
            ],
            places: [viewerPlace, memberPlace],
            visiblePlaces: [viewerVisiblePlace, memberVisiblePlace],
            now: now
        )

        XCTAssertEqual(dataset.places.map(\.id), [memberPlace.id])
        XCTAssertEqual(dataset.places.first?.tags, ["member-only"])
        XCTAssertEqual(
            dataset.visiblePlaceByPlaceID[memberPlace.id]?.userPlace.id,
            memberUserPlace.id
        )
        XCTAssertNil(dataset.visiblePlaceByPlaceID[viewerPlace.id])
    }

    func testProfilePreviewPushesAFullMapWithoutReplicaBottomNavigation() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let profileHome = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let yourMapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/YourMapPrototypeScreen.swift")
        )
        let sharedScheme = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander.xcodeproj/xcshareddata/xcschemes/Wander.xcscheme")
        )

        XCTAssertTrue(profileHome.contains("ProfileYourMapPreview"))
        XCTAssertTrue(profileScreen.contains(".navigationDestination(isPresented: $showsYourMapPrototype)"))
        XCTAssertTrue(profileScreen.contains("showsSettings || showsYourMapPrototype"))
        XCTAssertTrue(profileScreen.contains(".toolbar(.hidden, for: .tabBar)"))
        XCTAssertTrue(profileScreen.contains("YourMapPrototypeScreen(dataset: yourMapPrototypeDataset)"))
        XCTAssertFalse(profileScreen.contains("handledYourMapPrototypeLaunch"))
        XCTAssertFalse(profileScreen.contains("WanderShowYourMapPrototype"))
        XCTAssertTrue(yourMapScreen.contains(".navigationTitle(mode == .map ? mapTitle : \"Patterns\")"))
        XCTAssertTrue(yourMapScreen.contains("MapPinOutlineStroke"))
        XCTAssertTrue(yourMapScreen.contains("YourMapPrototypeSelectablePin"))
        XCTAssertTrue(yourMapScreen.contains("PlaceProfileMapSurface("))
        XCTAssertTrue(yourMapScreen.contains("Text(place.name)"))
        XCTAssertTrue(yourMapScreen.contains("YourMapPrototypeSavedLensRow"))
        XCTAssertTrue(yourMapScreen.contains("trash.fill"))
        XCTAssertTrue(yourMapScreen.contains(".highPriorityGesture(swipeGesture)"))
        XCTAssertTrue(yourMapScreen.contains("yourMap.prototype.monthHeatMap"))
        XCTAssertTrue(yourMapScreen.contains("yourMap.prototype.citiesCountries"))
        XCTAssertTrue(yourMapScreen.contains("yourMap.prototype.returnMagnets"))
        XCTAssertTrue(yourMapScreen.contains("Anyone with the link"))
        XCTAssertFalse(yourMapScreen.contains("Share with"))
        XCTAssertFalse(yourMapScreen.contains("private var lensDeck"))
        XCTAssertFalse(yourMapScreen.contains("private var yearComparisonPicker"))
        XCTAssertFalse(yourMapScreen.contains("private var patternFilterRow"))
        XCTAssertFalse(yourMapScreen.contains("YourMapPrototypeTabBar"))
        XCTAssertFalse(yourMapScreen.contains("navigationBarBackButtonHidden"))
        XCTAssertFalse(sharedScheme.contains("-WanderShowYourMapPrototype"))
    }

    func testMemberProfileRoutesToTheSameScopedMap() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let profileHome = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let detailStart = try XCTUnwrap(profileScreen.range(of: "struct ProfileDetailView: View {"))
        let memberProfile = String(profileScreen[detailStart.lowerBound...])

        XCTAssertTrue(profileHome.contains("if let yourMapAction {"))
        XCTAssertFalse(profileHome.contains("if mode.isOwner, let yourMapAction"))
        XCTAssertTrue(memberProfile.contains("yourMapAction: {"))
        XCTAssertTrue(memberProfile.contains("showsYourMapPrototype = true"))
        XCTAssertTrue(memberProfile.contains(".navigationDestination(isPresented: $showsYourMapPrototype)"))
        XCTAssertTrue(memberProfile.contains("YourMapPrototypeScreen("))
        XCTAssertTrue(memberProfile.contains("ownerID: profileID"))
        XCTAssertTrue(memberProfile.contains("userPlaces: profileVisiblePlaces.map(\\.userPlace)"))
        XCTAssertTrue(memberProfile.contains("places: profileVisiblePlaces.map(\\.place)"))
        XCTAssertTrue(memberProfile.contains("visiblePlaces: profileVisiblePlaces"))
        XCTAssertTrue(memberProfile.contains("viewerID: store.currentUser.id"))
        XCTAssertTrue(memberProfile.contains("pinOwnership: .social"))
        let yourMapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/YourMapPrototypeScreen.swift")
        )
        XCTAssertTrue(yourMapScreen.contains("currentUserID: viewerID ?? selectedVisiblePlace.owner.id"))
        XCTAssertTrue(yourMapScreen.contains("pinOwnership: MapPinSaveOwnership = .currentUser"))
        XCTAssertTrue(yourMapScreen.contains("ownership: pinOwnership"))
        XCTAssertTrue(yourMapScreen.contains("YourMapPrototypeMiniMap(places: places, pinOwnership: pinOwnership)"))
    }

    func testYourMapIsCompiledIntoReleaseBuilds() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let profileHome = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileOwnerHome.swift")
        )
        let profileScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/ProfileScreen.swift")
        )
        let yourMapModels = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/YourMapPrototypeModels.swift")
        )
        let yourMapScreen = try String(
            contentsOf: projectRoot.appendingPathComponent("Wander/Features/Profile/YourMapPrototypeScreen.swift")
        )

        XCTAssertFalse(
            profileScreen.contains("#if DEBUG\n    @State private var showsYourMapPrototype"),
            "The Profile route must remain available in TestFlight Release builds."
        )
        XCTAssertFalse(
            profileHome.contains("#if DEBUG\n                if mode.isOwner, let yourMapAction"),
            "The owner Profile preview must remain available in TestFlight Release builds."
        )
        XCTAssertFalse(
            profileHome.contains("#if DEBUG\nprivate struct ProfileYourMapPreview"),
            "The owner Profile preview type must remain available in TestFlight Release builds."
        )
        XCTAssertFalse(
            yourMapModels.contains("#if DEBUG"),
            "Your Map models must compile into Release builds."
        )
        XCTAssertFalse(
            yourMapScreen.contains("#if DEBUG"),
            "Your Map UI must compile into Release builds."
        )
    }
}
