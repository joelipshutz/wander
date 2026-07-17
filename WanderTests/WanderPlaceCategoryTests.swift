import MapKit
import XCTest
@testable import Wander

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

        XCTAssertEqual(shared.version, 5)
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
