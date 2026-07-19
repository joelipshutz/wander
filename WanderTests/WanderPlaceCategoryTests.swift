import Foundation
import MapKit
import XCTest
@testable import Wander

private final class SnapshotWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseFirstWrite = DispatchSemaphore(value: 0)
    private var startedWriteCount = 0
    private var completedSnapshots: [WanderStoreSnapshot] = []
    private var mainThreadFlags: [Bool] = []
    private var didStartFirstWrite = false
    private var firstWriteContinuation: CheckedContinuation<Void, Never>?

    func write(_ snapshot: WanderStoreSnapshot) {
        lock.lock()
        startedWriteCount += 1
        let isFirstWrite = startedWriteCount == 1
        mainThreadFlags.append(Thread.isMainThread)
        if isFirstWrite {
            didStartFirstWrite = true
        }
        let continuation = isFirstWrite ? firstWriteContinuation : nil
        if isFirstWrite {
            firstWriteContinuation = nil
        }
        lock.unlock()

        if isFirstWrite {
            continuation?.resume()
            _ = releaseFirstWrite.wait(timeout: .now() + 5)
        }

        lock.lock()
        completedSnapshots.append(snapshot)
        lock.unlock()
    }

    func waitForFirstWrite() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStartFirstWrite {
                lock.unlock()
                continuation.resume()
            } else {
                firstWriteContinuation = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        releaseFirstWrite.signal()
    }

    var completed: [WanderStoreSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return completedSnapshots
    }

    var wroteOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return mainThreadFlags.contains(true)
    }
}

final class WanderPlaceCategoryTests: XCTestCase {
    func testMapKitParksStayParks() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .park), WanderPlaceCategory.outdoorsNature)
        XCTAssertEqual(WanderPlaceCategory.primary(for: .nationalPark), WanderPlaceCategory.outdoorsNature)
    }

    func testCategoryEmojiLookupNormalizesAliases() {
        XCTAssertEqual(WanderPlaceCategory.emoji(for: WanderPlaceCategory.outdoorsNature), "🌲")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "park"), "🌳")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "hike"), "🥾")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "thai restaurant"), "🇹🇭")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "unknown provider value"), "📍")
    }

    func testCategoryEmojiUsesSpecificSubtypeBeforeBroadCategory() {
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "hospital"), "🏥")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "fitness center"), "💪")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "nail salon"), "💅")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "hair salon"), "💇")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "bakery"), "🥐")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "coffee shop"), "☕️")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "tea house"), "🫖")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "pharmacy"), "💊")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "dentist"), "🦷")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "airport"), "✈️")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "church"), "⛪️")
    }

    func testCategoryEmojiRefinesGenericProviderTypesWithNarrowPlaceNames() {
        let genericDoctor = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.wellnessFitness,
            subcategory: "Doctor",
            source: PlaceCategorySource.provider.rawValue,
            rawProviderType: "doctor"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: genericDoctor, name: "Santa Monica Eye Care Center"),
            "👁️"
        )

        let broadWellness = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.wellnessFitness,
            source: PlaceCategorySource.provider.rawValue,
            rawProviderType: WanderPlaceCategory.wellnessFitness
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: broadWellness, name: "Providence Saint John's Hospital"),
            "🏥"
        )

        let broadCoffee = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            source: PlaceCategorySource.provider.rawValue,
            rawProviderType: WanderPlaceCategory.coffeeTeaSweets
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: broadCoffee, name: "Wild Leaven Bakery"),
            "🥐"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.wellnessFitness,
                name: "Providence Saint John's Hospital"
            ),
            "🏥"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.servicesErrands,
                name: "Gloss Nail Salon"
            ),
            "💅"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.wellnessFitness,
                subcategory: "Nail salon",
                name: "Gloss Nail Salon"
            ),
            "💅"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.wellnessFitness,
                subcategory: "Hair salon",
                name: "Proper Hair"
            ),
            "💇"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.servicesErrands,
                subcategory: "Hospital",
                name: "Providence Saint John's Hospital"
            ),
            "🏥"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(
                for: WanderPlaceCategory.coffeeTeaSweets,
                name: "Wild Leaven Bakery"
            ),
            "🥐"
        )
    }

    func testReportedVenueEmojiRegressionsUseEvidenceWithoutGuessing() {
        let westsideBarber = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.fallbackPlace,
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.86,
            rawProviderType: "mkpoicategorybeauty"
        )
        XCTAssertEqual(westsideBarber.primaryCategory, WanderPlaceCategory.servicesErrands)
        XCTAssertEqual(westsideBarber.subcategory, "Beauty service")
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: westsideBarber, name: "Westside Barber Co"),
            "💈"
        )

        let cocoBeach = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.barsNightlife,
            subcategory: "Sports bar",
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: "place"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: cocoBeach, name: "Coco Beach Bar & Grill"),
            "🍻"
        )

        let broadUgo = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.86,
            rawProviderType: "mkpoicategoryrestaurant"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: broadUgo, name: "Ugo"),
            "🍽️",
            "An opaque venue name must not fabricate a cuisine"
        )

        let enrichedUgo = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.96,
            rawProviderType: "italian_restaurant"
        )
        XCTAssertEqual(WanderPlaceCategory.emoji(for: enrichedUgo, name: "Ugo"), "🍝")

        XCTAssertEqual(
            WanderPlaceCategory.preferredProviderType(
                primaryType: "restaurant",
                types: ["food", "italian_restaurant", "point_of_interest"],
                matchingPrimaryCategory: WanderPlaceCategory.restaurantsFood
            ),
            "italian_restaurant"
        )
        XCTAssertNil(
            WanderPlaceCategory.preferredProviderType(
                primaryType: "sporting_goods_store",
                types: ["store", "point_of_interest"],
                matchingPrimaryCategory: WanderPlaceCategory.restaurantsFood
            ),
            "Provider enrichment must not cross the stored broad-category boundary"
        )
    }

    func testNonUserAssignmentsRepairStaleBroadCategoriesFromStrongerMetadata() {
        let noun = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Coffee shop",
            source: PlaceCategorySource.legacy.rawValue,
            confidence: 0.86,
            rawProviderType: "coffee"
        )
        XCTAssertEqual(noun.primaryCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(noun.subcategory, "Coffee shop")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: noun, name: "Noun"), "☕️")

        let boulevard = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Coffee shop",
            source: PlaceCategorySource.legacy.rawValue,
            confidence: 0.86,
            rawProviderType: "restaurant"
        )
        XCTAssertEqual(boulevard.primaryCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(boulevard.subcategory, "Coffee shop")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: boulevard, name: "Boulevard"), "☕️")

        let costco = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Mkpoicategoryfoodmarket",
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.86,
            rawProviderType: "mkpoicategoryfoodmarket"
        )
        XCTAssertEqual(costco.primaryCategory, WanderPlaceCategory.shopping)
        XCTAssertEqual(costco.subcategory, "Grocery store")
        XCTAssertEqual(WanderPlaceCategory.emoji(for: costco, name: "Costco Wholesale"), "🛒")

        let explicitUserChoice = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: "coffee"
        )
        XCTAssertEqual(explicitUserChoice.primaryCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(explicitUserChoice.subcategory, "Restaurant")
    }

    func testSavedCuisineOutranksProviderCuisineWithoutOverstatingJapanese() {
        let menya = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.98,
            rawProviderType: "sushi_restaurant"
        )

        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: menya, cuisine: "Japanese", name: "Menya Tigre"),
            "🇯🇵"
        )
        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: menya, cuisine: "Sushi", name: "Menya Tigre"),
            "🍣"
        )
    }

    func testGenericAdjacentFoodCategoryCanUseExactProviderPrimaryType() {
        let genericRestaurant = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.86,
            rawProviderType: "mkpoicategoryrestaurant"
        )

        XCTAssertEqual(
            WanderPlaceCategory.correctiveProviderPrimaryType("bakery", for: genericRestaurant),
            "bakery"
        )
        XCTAssertNil(
            WanderPlaceCategory.correctiveProviderPrimaryType(
                "sporting_goods_store",
                for: genericRestaurant
            )
        )
    }

    func testPersistedMapKitRawTypesRecoverCanonicalCategoriesAndSubcategories() {
        let cases: [(rawType: String, primary: String, subcategory: String, emoji: String)] = [
            ("mkpoicategorybeauty", WanderPlaceCategory.servicesErrands, "Beauty service", "🪞"),
            ("mkpoicategoryfitnesscenter", WanderPlaceCategory.wellnessFitness, "Fitness center", "💪"),
            ("mkpoicategoryfoodmarket", WanderPlaceCategory.shopping, "Grocery store", "🛒"),
            ("mkpoicategoryrestaurant", WanderPlaceCategory.restaurantsFood, "Restaurant", "🍽️"),
            ("mkpoicategorycafe", WanderPlaceCategory.coffeeTeaSweets, "Cafe", "☕️"),
            ("mkpoicategorybakery", WanderPlaceCategory.coffeeTeaSweets, "Bakery", "🥐"),
            ("mkpoicategorybrewery", WanderPlaceCategory.barsNightlife, "Brewery", "🍺"),
            ("mkpoicategorynightlife", WanderPlaceCategory.barsNightlife, "Bar", "🍸"),
            ("mkpoicategoryautomotiverepair", WanderPlaceCategory.travelTransit, "Car repair", "🔧"),
            ("mkpoicategorydistillery", WanderPlaceCategory.barsNightlife, "Distillery", "🥃"),
            ("mkpoicategorymusicvenue", WanderPlaceCategory.thingsToDo, "Concert hall", "🎵"),
            ("mkpoicategorypublictransport", WanderPlaceCategory.travelTransit, "Transit station", "🚉")
        ]

        for value in cases {
            let assignment = WanderPlaceCategory.assignment(
                forRawCategory: value.rawType,
                source: PlaceCategorySource.provider.rawValue,
                confidence: 0.86,
                rawProviderType: value.rawType
            )
            XCTAssertEqual(assignment.primaryCategory, value.primary, value.rawType)
            XCTAssertEqual(assignment.subcategory, value.subcategory, value.rawType)
            XCTAssertEqual(WanderPlaceCategory.emoji(for: assignment), value.emoji, value.rawType)
        }
    }

    func testEverySupportedMapKitProviderTypeAvoidsFallbackPlaceAndPin() {
        XCTAssertEqual(
            WanderPlaceCategory.supportedMapKitProviderTypes.count,
            73,
            "Keep this in sync with every constant in the current MKPointOfInterestCategory SDK header"
        )

        for rawType in WanderPlaceCategory.supportedMapKitProviderTypes {
            let assignment = WanderPlaceCategory.assignment(
                forRawCategory: rawType,
                source: PlaceCategorySource.provider.rawValue,
                confidence: 0.86,
                rawProviderType: rawType
            )
            XCTAssertNotEqual(assignment.primaryCategory, WanderPlaceCategory.fallbackPlace, rawType)
            XCTAssertNotNil(assignment.subcategory, rawType)
            XCTAssertNotEqual(WanderPlaceCategory.emoji(for: assignment), "📍", rawType)
        }
    }

    func testCuisineDetectionRequiresWholeTerms() {
        XCTAssertEqual(WanderPlaceCategory.cuisineGuess(forRawValue: "italian_restaurant"), "Italian")
        XCTAssertEqual(WanderPlaceCategory.cuisineGuess(forRawValue: "south american cuisine"), "South American")
        XCTAssertNil(WanderPlaceCategory.cuisineGuess(forRawValue: "Indianapolis restaurant"))
    }

    func testUserEditedSubcategoryWinsOverProviderAndNameHints() {
        let assignment = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.wellnessFitness,
            subcategory: "Gym",
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: "hospital"
        )

        XCTAssertEqual(
            WanderPlaceCategory.emoji(for: assignment, name: "Providence Hospital"),
            "💪"
        )
    }

    func testRichPlaceAdaptersPreserveSubtypeAndCuisineEmojiContext() {
        let hospital = PlaceCandidate(
            id: "hospital",
            name: "Providence Saint John's Hospital",
            category: WanderPlaceCategory.wellnessFitness,
            primaryCategory: WanderPlaceCategory.wellnessFitness,
            subcategory: "Hospital",
            categorySource: PlaceCategorySource.provider.rawValue,
            rawProviderType: "hospital",
            latitude: 34.0,
            longitude: -118.0,
            sourceProvider: "mapkit",
            confidence: 1
        )
        XCTAssertEqual(hospital.categoryEmoji, "🏥")

        let owner = LocalProfile(
            localID: "owner",
            handle: "owner",
            displayName: "Owner"
        )
        let restaurant = LocalPlace(
            localID: "restaurant",
            canonicalName: "Jitlada",
            category: WanderPlaceCategory.restaurantsFood,
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            rawProviderType: "restaurant",
            latitude: 34.0,
            longitude: -118.0
        )
        let userPlace = LocalUserPlace(
            localID: "user-place",
            userID: owner.id,
            placeID: restaurant.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let cuisine = LocalPlaceAttribute(
            localID: "cuisine",
            userPlaceID: userPlace.id,
            questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
            valueType: "single_choice",
            valueJSON: "\"Thai\""
        )
        let visiblePlace = VisiblePlace(
            id: userPlace.id,
            place: restaurant,
            userPlace: userPlace,
            owner: owner,
            attributes: [cuisine]
        )

        XCTAssertEqual(visiblePlace.restaurantCuisine, "Thai")
        XCTAssertEqual(visiblePlace.categoryEmoji, "🇹🇭")

        cuisine.valueJSON = "\"Italian\""
        XCTAssertEqual(visiblePlace.restaurantCuisine, "Italian")
        XCTAssertEqual(visiblePlace.categoryEmoji, "🍝")

        userPlace.categoryOverride = WanderPlaceCategory.wellnessFitness
        userPlace.subcategoryOverride = "Gym"
        userPlace.categoryOverrideSource = PlaceCategorySource.user.rawValue
        XCTAssertEqual(visiblePlace.effectiveCategory, WanderPlaceCategory.wellnessFitness)
        XCTAssertEqual(visiblePlace.categoryEmoji, "💪")
    }

    func testEveryRestaurantCuisineHasDishOrRegionalEmoji() {
        let assignment = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            source: PlaceCategorySource.provider.rawValue,
            rawProviderType: "restaurant"
        )

        for cuisine in WanderPlaceCategory.restaurantCuisineOptions {
            let emoji = WanderPlaceCategory.emoji(for: assignment, cuisine: cuisine)
            XCTAssertFalse(emoji.isEmpty, "\(cuisine) should resolve an emoji")
            XCTAssertNotEqual(emoji, "🍽️", "\(cuisine) should be more specific than the broad restaurant icon")
            XCTAssertNotEqual(emoji, "📍", "\(cuisine) should never fall back to a generic pin")
        }
    }

    func testEmojiResolutionHotPathStaysCheapAcrossRepeatedListRendering() {
        let owner = LocalProfile(
            localID: "perf-owner",
            handle: "perf-owner",
            displayName: "Performance Owner"
        )
        let restaurant = LocalPlace(
            localID: "perf-restaurant",
            canonicalName: "Repeated Thai Restaurant",
            category: WanderPlaceCategory.restaurantsFood,
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            rawProviderType: "restaurant",
            latitude: 34,
            longitude: -118
        )
        let userPlace = LocalUserPlace(
            localID: "perf-user-place",
            userID: owner.id,
            placeID: restaurant.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let cuisine = LocalPlaceAttribute(
            localID: "perf-cuisine",
            userPlaceID: userPlace.id,
            questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
            valueType: "single_choice",
            valueJSON: "\"Thai\""
        )
        let visiblePlace = VisiblePlace(
            id: userPlace.id,
            place: restaurant,
            userPlace: userPlace,
            owner: owner,
            attributes: [cuisine]
        )

        _ = visiblePlace.categoryEmoji

        let start = Date()
        var checksum = 0
        for _ in 0..<2_000 {
            checksum += visiblePlace.categoryEmoji.utf8.count
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertGreaterThan(checksum, 0)
        XCTAssertLessThan(
            elapsed,
            0.1,
            "Visible-place category presentation took \(elapsed)s for 2,000 redraws; rendering must reuse derived cuisine and emoji work"
        )
    }

    @MainActor
    func testPerformanceFixtureExercisesARealisticHighDataAccountWithinBudget() {
        let fixtureStart = CFAbsoluteTimeGetCurrent()
        let fixtures = WanderFixtures.performanceScale()
        let fixtureElapsed = CFAbsoluteTimeGetCurrent() - fixtureStart

        XCTAssertEqual(fixtures.profiles.count, 64)
        XCTAssertEqual(fixtures.places.count, 900)
        XCTAssertEqual(fixtures.userPlaces.count, 1_620)
        XCTAssertEqual(fixtures.placeAttributes.count, 3_240)
        XCTAssertGreaterThan(fixtures.placeVisits.count, 1_200)
        XCTAssertEqual(fixtures.placeLists.count, 72)
        XCTAssertEqual(fixtures.placeListItems.count, 2_016)

        let storeStart = CFAbsoluteTimeGetCurrent()
        let store = WanderStore(fixtures: fixtures)
        let storeElapsed = CFAbsoluteTimeGetCurrent() - storeStart

        let coldProjectionStart = CFAbsoluteTimeGetCurrent()
        let visiblePlaces = store.visiblePlaces()
        let coldProjectionElapsed = CFAbsoluteTimeGetCurrent() - coldProjectionStart
        XCTAssertGreaterThan(visiblePlaces.count, 1_400)

        let warmProjectionStart = CFAbsoluteTimeGetCurrent()
        var checksum = 0
        for _ in 0..<20 {
            checksum += store.visiblePlaces().count
            checksum += store.visiblePlaceCountsByOwnerID().count
        }
        let warmProjectionElapsed = CFAbsoluteTimeGetCurrent() - warmProjectionStart

        let visibleLists = store.visiblePlaceLists
        let listProjectionStart = CFAbsoluteTimeGetCurrent()
        let visiblePlacesByListID = store.visiblePlacesByListID(in: visibleLists)
        let listProjectionElapsed = CFAbsoluteTimeGetCurrent() - listProjectionStart
        let visibleListItemCount = visiblePlacesByListID.values.reduce(0) { $0 + $1.count }

        let warmListProjectionStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 {
            checksum += store.visiblePlacesByListID(in: visibleLists).count
        }
        let warmListProjectionElapsed = CFAbsoluteTimeGetCurrent() - warmListProjectionStart

        let insightsCache = ProfileInsightsCache()
        let insightsStart = CFAbsoluteTimeGetCurrent()
        let insights = insightsCache.present(
            ownerID: store.currentUser.id,
            userPlaces: store.userPlaces,
            visits: store.placeVisits,
            places: store.places,
            month: Date(timeIntervalSince1970: 1_735_689_600),
            dataRevision: store.presentationRevision
        )
        let insightsElapsed = CFAbsoluteTimeGetCurrent() - insightsStart
        XCTAssertGreaterThan(insights.mapPoints.count, 250)

        let warmInsightsStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<20 {
            checksum += insightsCache.present(
                ownerID: store.currentUser.id,
                userPlaces: store.userPlaces,
                visits: store.placeVisits,
                places: store.places,
                month: Date(timeIntervalSince1970: 1_735_689_600),
                dataRevision: store.presentationRevision
            ).mapPoints.count
        }
        let warmInsightsElapsed = CFAbsoluteTimeGetCurrent() - warmInsightsStart

        let snapshotStart = CFAbsoluteTimeGetCurrent()
        let snapshot = WanderStoreSnapshot(store: store)
        let snapshotElapsed = CFAbsoluteTimeGetCurrent() - snapshotStart

        XCTAssertGreaterThan(checksum, 0)
        XCTAssertGreaterThan(visibleListItemCount, 1_500)
        XCTAssertEqual(snapshot.userPlaces.count, fixtures.userPlaces.count)
        XCTAssertLessThan(fixtureElapsed, 2.5, "Performance fixture construction took \(fixtureElapsed)s")
        XCTAssertLessThan(storeElapsed, 0.5, "High-data store initialization took \(storeElapsed)s")
        XCTAssertLessThan(coldProjectionElapsed, 0.5, "Cold visible-place projection took \(coldProjectionElapsed)s")
        XCTAssertLessThan(warmProjectionElapsed, 0.1, "Warm visible-place reads took \(warmProjectionElapsed)s")
        XCTAssertLessThan(listProjectionElapsed, 0.5, "High-data list projection took \(listProjectionElapsed)s")
        XCTAssertLessThan(warmListProjectionElapsed, 0.1, "Warm high-data list reads took \(warmListProjectionElapsed)s")
        XCTAssertLessThan(insightsElapsed, 0.5, "Cold Profile insights took \(insightsElapsed)s")
        XCTAssertLessThan(warmInsightsElapsed, 0.15, "Warm Profile insight reads took \(warmInsightsElapsed)s")
        XCTAssertLessThan(snapshotElapsed, 0.5, "Main-actor snapshot creation took \(snapshotElapsed)s")
    }

    @MainActor
    func testVisiblePlaceProjectionIsReusedUntilStoreMutation() {
        let store = WanderStore(fixtures: .seed())
        let filters = PlaceFilters(ownerScopes: ["you"])

        let first = store.visiblePlaces(filters: filters)
        let initialBuildCount = store.visiblePlaceProjectionBuildCount
        let second = store.visiblePlaces(filters: filters)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(store.visiblePlaceProjectionBuildCount, initialBuildCount)

        store.defaultVisibility = .mutuals
        _ = store.visiblePlaces(filters: filters)

        XCTAssertEqual(store.visiblePlaceProjectionBuildCount, initialBuildCount + 1)
    }

    @MainActor
    func testVisiblePlaceOwnerCountsAreBuiltOnceAndReusedAcrossDiscoverRows() {
        let store = WanderStore(fixtures: .seed())

        let first = store.visiblePlaceCountsByOwnerID()
        let initialBuildCount = store.visiblePlaceOwnerCountBuildCount
        let second = store.visiblePlaceCountsByOwnerID()

        XCTAssertEqual(first, second)
        XCTAssertEqual(store.visiblePlaceOwnerCountBuildCount, initialBuildCount)
        XCTAssertEqual(first.values.reduce(0, +), store.visiblePlaces().count)

        store.defaultVisibility = .mutuals
        _ = store.visiblePlaceCountsByOwnerID()

        XCTAssertEqual(store.visiblePlaceOwnerCountBuildCount, initialBuildCount + 1)
    }

    @MainActor
    func testVisiblePlaceProjectionPreservesFirstMatchForDuplicateEffectiveIDs() {
        let firstOwner = LocalProfile(
            localID: "first-owner",
            serverID: "shared-owner",
            handle: "first",
            displayName: "First Owner"
        )
        let laterOwner = LocalProfile(
            localID: "later-owner",
            serverID: "shared-owner",
            handle: "later",
            displayName: "Later Owner"
        )
        let firstPlace = LocalPlace(
            localID: "first-place",
            serverID: "shared-place",
            canonicalName: "First Place",
            category: "coffee",
            latitude: 34,
            longitude: -118
        )
        let laterPlace = LocalPlace(
            localID: "later-place",
            serverID: "shared-place",
            canonicalName: "Later Place",
            category: "restaurant",
            latitude: 35,
            longitude: -119
        )
        let userPlace = LocalUserPlace(
            localID: "duplicate-id-user-place",
            userID: firstOwner.id,
            placeID: firstPlace.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual"
        )
        let store = WanderStore(
            fixtures: WanderFixtures(
                currentUser: firstOwner,
                profiles: [firstOwner, laterOwner],
                places: [firstPlace, laterPlace],
                userPlaces: [userPlace],
                placeAttributes: [],
                follows: [],
                blocks: [],
                placeLists: [],
                placeListMembers: [],
                placeListItems: [],
                contactProvider: FakeContactProvider(seededMatches: [])
            )
        )

        let visiblePlace = store.visiblePlaces().first

        XCTAssertTrue(visiblePlace?.place === firstPlace)
        XCTAssertTrue(visiblePlace?.owner === firstOwner)
    }

    @MainActor
    func testCoalescedPersistenceWritesOnlyLatestPendingSnapshotOffMainThread() async {
        let store = WanderStore(fixtures: .seed())
        let first = WanderStoreSnapshot(store: store)
        store.defaultVisibility = .mutuals
        let second = WanderStoreSnapshot(store: store)
        store.defaultVisibility = .selfOnly
        let latest = WanderStoreSnapshot(store: store)
        let probe = SnapshotWriteProbe()
        let persistence = WanderStorePersistence.coalescing(
            load: { nil },
            write: probe.write
        )

        persistence.save(first)
        await probe.waitForFirstWrite()
        persistence.save(second)
        persistence.save(latest)
        probe.release()
        persistence.flush()

        XCTAssertEqual(probe.completed.count, 2)
        XCTAssertEqual(probe.completed.last, latest)
        XCTAssertFalse(probe.wroteOnMainThread)
    }

    @MainActor
    func testRepeatedSignedInSessionDoesNotRebuildOrRepersistTheSameUser() {
        var snapshots: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { snapshots.append($0) }
        )
        let store = WanderStore(fixtures: .empty(), persistence: persistence)
        let session = AuthSession(
            userID: "performance-user",
            displayName: "Performance User",
            handle: "performance-user"
        )

        store.apply(authState: .signedIn(session))
        XCTAssertEqual(snapshots.count, 1)
        let signedInProfile = store.currentUser

        store.apply(authState: .signedIn(session))

        XCTAssertEqual(store.currentUser.id, session.userID)
        XCTAssertTrue(store.currentUser === signedInProfile)
        XCTAssertEqual(snapshots.count, 1)
    }

    @MainActor
    func testSignedOutSessionPersistsGuestProfileAndInvalidatesProjectionCache() {
        var snapshots: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { snapshots.append($0) }
        )
        let store = WanderStore(fixtures: .empty(), persistence: persistence)

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "performance-user",
                    displayName: "Performance User",
                    handle: "performance-user"
                )
            )
        )
        _ = store.visiblePlaces()
        let signedInProjectionBuildCount = store.visiblePlaceProjectionBuildCount

        store.apply(authState: .signedOut)
        _ = store.visiblePlaces()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertNil(snapshots.last?.currentUser.serverID)
        XCTAssertEqual(snapshots.last?.currentUser.handle, "you")
        XCTAssertEqual(store.currentUser.handle, "you")
        XCTAssertEqual(store.visiblePlaceProjectionBuildCount, signedInProjectionBuildCount + 1)
    }

    func testKnownSubcategoriesResolveAndEachBroadCategoryHasUsefulVariety() {
        let minimumDistinctEmojiCounts: [String: Int] = [
            WanderPlaceCategory.restaurantsFood: 15,
            WanderPlaceCategory.coffeeTeaSweets: 10,
            WanderPlaceCategory.barsNightlife: 10,
            WanderPlaceCategory.outdoorsNature: 15,
            WanderPlaceCategory.thingsToDo: 20,
            WanderPlaceCategory.shopping: 15,
            WanderPlaceCategory.wellnessFitness: 18,
            WanderPlaceCategory.stays: 7,
            WanderPlaceCategory.servicesErrands: 25,
            WanderPlaceCategory.travelTransit: 18,
            WanderPlaceCategory.workEducation: 9,
            WanderPlaceCategory.civicFaith: 10,
            WanderPlaceCategory.areasAddresses: 8,
            WanderPlaceCategory.facilitiesOther: 4
        ]

        for category in WanderPlaceCategory.editableCategories {
            let emojis = WanderPlaceCategory.subcategorySuggestions(for: category).map { subcategory in
                WanderPlaceCategory.emoji(
                    for: PlaceCategoryAssignment(
                        primaryCategory: category,
                        subcategory: subcategory,
                        source: PlaceCategorySource.user.rawValue,
                        confidence: 1
                    ),
                    cuisine: category == WanderPlaceCategory.restaurantsFood ? subcategory : nil
                )
            }

            XCTAssertTrue(emojis.allSatisfy { !$0.isEmpty }, "\(category) should resolve every known subcategory")
            XCTAssertGreaterThanOrEqual(
                Set(emojis).count,
                minimumDistinctEmojiCounts[category] ?? 2,
                "\(category) should not collapse its subcategories into one broad emoji"
            )
        }
    }

    func testDisplayTaxonomySeparatesBroadCategoryAndSubcategory() {
        let restaurant = WanderPlaceCategory.display(for: "restaurant")
        XCTAssertEqual(restaurant.category, "Restaurants & Food")
        XCTAssertEqual(restaurant.subcategory, "Restaurant")
        XCTAssertEqual(restaurant.primaryCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(restaurant.compactTitle, "Restaurant · Restaurants & Food")

        let transit = WanderPlaceCategory.display(for: "transportation")
        XCTAssertEqual(transit.category, "Travel & Transit")
        XCTAssertEqual(transit.subcategory, "Transit stop")

        let providerRestaurant = WanderPlaceCategory.display(for: "thai restaurant")
        XCTAssertEqual(providerRestaurant.primaryCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(providerRestaurant.category, "Restaurants & Food")
        XCTAssertEqual(providerRestaurant.subcategory, "Restaurant")
        XCTAssertEqual(WanderPlaceCategory.cuisineGuess(forRawValue: "thai restaurant"), "Thai")
        XCTAssertEqual(WanderPlaceCategory.cuisineGuess(forRawValue: "south american restaurant"), "South American")
        XCTAssertEqual(WanderPlaceCategory.cuisineGuess(forRawValue: "japanese bbq"), "Japanese BBQ")

        let providerNightlife = WanderPlaceCategory.display(for: "MKPOICategoryNightlife")
        XCTAssertEqual(providerNightlife.primaryCategory, WanderPlaceCategory.barsNightlife)
        XCTAssertEqual(providerNightlife.category, "Bars & Nightlife")
        XCTAssertEqual(providerNightlife.subcategory, "Bar")

        let providerStore = WanderPlaceCategory.display(for: "art supply store")
        XCTAssertEqual(providerStore.category, "Shopping")
        XCTAssertEqual(providerStore.subcategory, "Art supply store")
    }

    func testQuestionCategoryRoutesProviderSubcategoriesToSmartQuestions() {
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "thai restaurant"), "restaurant")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "coffee shop"), "coffee")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "waterfall"), "hike")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "4-star hotel"), WanderPlaceCategory.stays)
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "art supply store"), WanderPlaceCategory.shopping)

        let restaurantBlocks = AddQuestionTemplates.blocks(category: "thai restaurant", status: .been)
        XCTAssertEqual(restaurantBlocks.map(\.key), ["price", "occasion", "restaurant_tags"])
        XCTAssertFalse(restaurantBlocks.contains { $0.key == PlaceMemoryAttributeKeys.personalLabels })
    }

    func testMapKitHealthAndFitnessCategories() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .hospital), WanderPlaceCategory.wellnessFitness)
        XCTAssertEqual(WanderPlaceCategory.primary(for: .fitnessCenter), WanderPlaceCategory.wellnessFitness)

        if #available(iOS 18.0, *) {
            XCTAssertEqual(WanderPlaceCategory.primary(for: .animalService), WanderPlaceCategory.servicesErrands)
            XCTAssertEqual(WanderPlaceCategory.primary(for: .hiking), WanderPlaceCategory.outdoorsNature)
        }
    }

    func testPlaceNameOverridesTuneBroadMapKitCategories() {
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Providence St. John's Health Center"),
            WanderPlaceCategory.wellnessFitness
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Green Dog Dental"),
            WanderPlaceCategory.wellnessFitness
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Iron Fitness"),
            WanderPlaceCategory.wellnessFitness
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Plankhaus"),
            WanderPlaceCategory.wellnessFitness
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Lake Shrine"),
            WanderPlaceCategory.civicFaith
        )
        XCTAssertEqual(WanderPlaceCategory.emoji(for: "spiritual"), "🙏")
    }

    func testCandidatePreviewSubtitleDoesNotRepeatLocality() {
        let candidate = PlaceCandidate(
            id: "jade-rabbit",
            name: "Jade Rabbit",
            category: "restaurant",
            address: "231 Santa Monica Boulevard Santa Monica",
            locality: "Santa Monica",
            latitude: 34.0,
            longitude: -118.0,
            confidence: 0.9
        )

        XCTAssertEqual(
            candidate.previewSubtitle(includeDistance: false),
            "231 Santa Monica Boulevard · Santa Monica · Restaurant · Restaurants & Food"
        )

        let commaCandidate = PlaceCandidate(
            id: "jade-rabbit-comma",
            name: "Jade Rabbit",
            category: "restaurant",
            address: "231 Santa Monica Boulevard, Santa Monica, CA",
            locality: "Santa Monica",
            latitude: 34.0,
            longitude: -118.0,
            confidence: 0.9
        )

        XCTAssertEqual(
            commaCandidate.previewSubtitle(includeDistance: false),
            "231 Santa Monica Boulevard · Santa Monica · Restaurant · Restaurants & Food"
        )
    }

    func testSwiftTaxonomyMatchesSharedTaxonomyIDs() throws {
        struct SharedTaxonomy: Decodable {
            struct Category: Decodable {
                let id: String
                let emoji: String
                let editable: Bool
                let aliases: [String]
                let subcategories: [String]
                let defaultSubcategory: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case emoji
                    case editable
                    case aliases
                    case subcategories
                    case defaultSubcategory = "default_subcategory"
                }
            }

            let version: Int
            let categories: [Category]
        }

        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let taxonomyURL = repoRoot.appendingPathComponent("shared/place-taxonomy.json")
        let data = try Data(contentsOf: taxonomyURL)
        let shared = try JSONDecoder().decode(SharedTaxonomy.self, from: data)

        XCTAssertEqual(shared.version, 6)
        XCTAssertEqual(WanderPlaceCategory.allowedCategories, shared.categories.map(\.id))
        XCTAssertEqual(WanderPlaceCategory.editableCategories, shared.categories.filter(\.editable).map(\.id))
        XCTAssertEqual(WanderPlaceCategory.editableCategories.count, 14)
        XCTAssertFalse(WanderPlaceCategory.editableCategories.contains(WanderPlaceCategory.fallbackPlace))

        let swiftEmojiByCategory = Dictionary(
            uniqueKeysWithValues: WanderPlaceCategory.taxonomy.map { ($0.id, $0.emoji) }
        )
        let sharedEmojiByCategory = Dictionary(
            uniqueKeysWithValues: shared.categories.map { ($0.id, $0.emoji) }
        )
        XCTAssertEqual(swiftEmojiByCategory, sharedEmojiByCategory)
        XCTAssertEqual(Set(WanderPlaceCategory.editableCategories.compactMap { swiftEmojiByCategory[$0] }).count, 14)

        for swiftCategory in WanderPlaceCategory.taxonomy {
            let sharedCategory = try XCTUnwrap(shared.categories.first { $0.id == swiftCategory.id })
            XCTAssertEqual(swiftCategory.defaultSubcategory, sharedCategory.defaultSubcategory)
            XCTAssertEqual(swiftCategory.aliases, sharedCategory.aliases)
            XCTAssertEqual(swiftCategory.subcategories, sharedCategory.subcategories)
        }
    }

    func testSubcategoryGroupsAreExhaustiveForEveryEditableCategory() {
        for category in WanderPlaceCategory.editableCategories {
            let suggestions = WanderPlaceCategory.subcategorySuggestions(for: category)
            let grouped = WanderPlaceCategory.subcategoryGroups(for: category).flatMap(\.subcategories)

            XCTAssertEqual(grouped.count, suggestions.count, "\(category) should group every taxonomy subcategory")
            XCTAssertEqual(Set(grouped), Set(suggestions), "\(category) grouped subcategories must match the taxonomy")
            XCTAssertEqual(Set(grouped).count, grouped.count, "\(category) should not duplicate grouped subcategories")
        }
    }

    func testRestaurantsFoodSubcategoriesSeparateTypeAndCuisineGroups() {
        let groups = WanderPlaceCategory.subcategoryGroups(for: WanderPlaceCategory.restaurantsFood)

        XCTAssertEqual(groups.map(\.title), [
            "Restaurant type",
            "Popular cuisines",
            "Asian cuisines",
            "Middle East & Africa",
            "European cuisines",
            "Americas & Pacific"
        ])
        XCTAssertEqual(groups[0].role, .type)
        XCTAssertTrue(groups[0].subcategories.contains("Restaurant"))
        XCTAssertTrue(groups[0].subcategories.contains("Taco truck"))
        XCTAssertEqual(groups[1].role, .cuisine)
        XCTAssertTrue(groups.flatMap(\.subcategories).contains("Thai"))
        XCTAssertEqual(WanderPlaceCategory.restaurantTypeGroups().flatMap(\.subcategories).count, 47)
        XCTAssertEqual(WanderPlaceCategory.restaurantCuisineOptions.count, 85)

        let restaurantTypes = Set(WanderPlaceCategory.restaurantTypeGroups().flatMap(\.subcategories))
        let cuisines = Set(WanderPlaceCategory.restaurantCuisineOptions)
        XCTAssertTrue(restaurantTypes.contains("Food court"))
        XCTAssertTrue(restaurantTypes.contains("Breakfast"))
        XCTAssertTrue(restaurantTypes.contains("Bagel"))
        XCTAssertTrue(restaurantTypes.contains("Oyster bar"))
        XCTAssertTrue(restaurantTypes.contains("Taco truck"))
        XCTAssertFalse(restaurantTypes.contains("Thai"))
        XCTAssertFalse(cuisines.contains("Food court"))
        XCTAssertTrue(cuisines.contains("Thai"))
    }

    func testDefaultSuggestionsCoverEveryEditableTaxonomySubcategory() {
        for category in WanderPlaceCategory.editableCategories {
            for subcategory in WanderPlaceCategory.subcategorySuggestions(for: category) {
                for status in [PlaceStatus.been, .wannaGo] {
                    let suggestions = PlaceMemoryDefaultCatalog.suggestions(
                        primaryCategory: category,
                        subcategory: subcategory,
                        status: status,
                        locality: "Los Angeles"
                    )

                    XCTAssertGreaterThanOrEqual(suggestions.tagOptions.count, 5, "\(category) / \(subcategory) should have useful tag options")
                    XCTAssertFalse(suggestions.defaultTags.isEmpty, "\(category) / \(subcategory) should seed at least one default tag")
                    XCTAssertLessThanOrEqual(suggestions.defaultTags.count, 3, "\(category) / \(subcategory) should keep auto-selected tags light")
                    XCTAssertGreaterThanOrEqual(suggestions.labelOptions.count, 5, "\(category) / \(subcategory) should have useful label options")
                    XCTAssertLessThanOrEqual(suggestions.defaultLabels.count, 1, "\(category) / \(subcategory) should not over-select labels")

                    for tag in suggestions.defaultTags {
                        XCTAssertTrue(suggestions.tagOptions.contains(tag), "\(tag) should be shown as an option")
                    }
                    for label in suggestions.defaultLabels {
                        XCTAssertTrue(suggestions.labelOptions.contains(label), "\(label) should be shown as an option")
                    }
                }
            }
        }
    }

    func testDefaultSuggestionsAreSpecificToCommonCombos() {
        let thaiRestaurant = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            cuisine: "Thai",
            status: .been,
            locality: "Los Angeles"
        )
        XCTAssertTrue(thaiRestaurant.tagOptions.contains("Thai craving"))
        XCTAssertTrue(thaiRestaurant.defaultTags.contains("Thai craving"))
        XCTAssertTrue(thaiRestaurant.labelOptions.contains("craving list"))
        XCTAssertTrue(thaiRestaurant.labelOptions.contains("LA favorite"))
        XCTAssertEqual(thaiRestaurant.defaultLabels, ["craving list"])

        let tacoTruck = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Taco truck",
            cuisine: "Mexican",
            status: .been,
            locality: "Los Angeles"
        )
        XCTAssertTrue(tacoTruck.tagOptions.contains("quick bite"))
        XCTAssertTrue(tacoTruck.tagOptions.contains("Mexican craving"))
        XCTAssertTrue(tacoTruck.defaultTags.contains("good value"))
        XCTAssertTrue(tacoTruck.labelOptions.contains("lunch rotation"))

        let cocktailBar = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: WanderPlaceCategory.barsNightlife,
            subcategory: "Cocktail bar",
            status: .been
        )
        XCTAssertTrue(cocktailBar.tagOptions.contains("date drinks"))
        XCTAssertTrue(cocktailBar.labelOptions.contains("after dinner"))

        let waterfall = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: WanderPlaceCategory.outdoorsNature,
            subcategory: "Waterfall",
            status: .wannaGo
        )
        XCTAssertTrue(waterfall.defaultTags.contains("views"))
        XCTAssertTrue(waterfall.labelOptions.contains("outdoor shortlist"))

        let chocolateLounge = PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            subcategory: "Chocolate lounge",
            status: .been
        )
        XCTAssertTrue(chocolateLounge.defaultTags.contains("sweet treat"))
        XCTAssertTrue(chocolateLounge.labelOptions.contains("dessert list"))
    }

    func testCoffeeTeaSweetsIncludesLoungeSubcategories() {
        let suggestions = WanderPlaceCategory.subcategorySuggestions(for: WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(suggestions.count, 25)
        XCTAssertTrue(suggestions.contains("Coffee lounge"))
        XCTAssertTrue(suggestions.contains("Chocolate lounge"))
        XCTAssertEqual(
            WanderPlaceCategory.canonicalSubcategory("coffee lounge", primaryCategory: WanderPlaceCategory.coffeeTeaSweets),
            "Coffee lounge"
        )
        XCTAssertEqual(
            WanderPlaceCategory.canonicalSubcategory("chocolate lounge", primaryCategory: WanderPlaceCategory.coffeeTeaSweets),
            "Chocolate lounge"
        )

        let groups = WanderPlaceCategory.subcategoryGroups(for: WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertTrue(groups.first { $0.title == "Coffee & tea" }?.subcategories.contains("Coffee lounge") == true)
        XCTAssertTrue(groups.first { $0.title == "Bakeries & sweets" }?.subcategories.contains("Chocolate lounge") == true)
    }
}
