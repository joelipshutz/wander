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

    func testPrototypeLaunchIsExplicit() {
        XCTAssertTrue(
            YourMapPrototypeLaunchConfiguration.shouldPresent(
                arguments: ["Wander", "-WanderShowYourMapPrototype"]
            )
        )
        XCTAssertFalse(YourMapPrototypeLaunchConfiguration.shouldPresent(arguments: ["Wander"]))
    }

    func testPrototypeModeLaunchArgumentFallsBackToMap() {
        XCTAssertEqual(
            YourMapPrototypeLaunchConfiguration.mode(
                arguments: ["Wander", "-WanderYourMapPrototypeMode", "patterns"]
            ),
            .patterns
        )
        XCTAssertEqual(
            YourMapPrototypeLaunchConfiguration.mode(
                arguments: ["Wander", "-WanderYourMapPrototypeMode", "unknown"]
            ),
            .map
        )
    }

    func testSharePreviewLaunchIsExplicit() {
        XCTAssertTrue(
            YourMapPrototypeLaunchConfiguration.shouldPresentSharePreview(
                arguments: ["Wander", "-WanderShowYourMapPrototypeSharePreview"]
            )
        )
        XCTAssertFalse(
            YourMapPrototypeLaunchConfiguration.shouldPresentSharePreview(arguments: ["Wander"])
        )
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
        XCTAssertFalse(insights.insight.isEmpty)
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

        let dataset = YourMapPrototypeDataset.make(
            ownerID: "owner",
            userPlaces: [userPlace],
            visits: [visit],
            places: [place],
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
        XCTAssertTrue(yourMapScreen.contains(".navigationTitle(mode == .map ? \"Your Map\" : \"Patterns\")"))
        XCTAssertFalse(yourMapScreen.contains("YourMapPrototypeTabBar"))
        XCTAssertFalse(yourMapScreen.contains("navigationBarBackButtonHidden"))
        XCTAssertFalse(sharedScheme.contains("-WanderShowYourMapPrototype"))
    }
}
