import MapKit
import XCTest
@testable import Wander

final class WanderPlaceCategoryTests: XCTestCase {
    func testMapKitParksStayParks() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .park), WanderPlaceCategory.outdoorsNature)
        XCTAssertEqual(WanderPlaceCategory.primary(for: .nationalPark), WanderPlaceCategory.outdoorsNature)
    }

    func testCategorySymbolsIncludePark() {
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "park"), "tree.fill")
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "hike"), "tree.fill")
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
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "spiritual"), "building.columns.fill")
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
                let editable: Bool
            }

            let categories: [Category]
        }

        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let taxonomyURL = repoRoot.appendingPathComponent("shared/place-taxonomy.json")
        let data = try Data(contentsOf: taxonomyURL)
        let shared = try JSONDecoder().decode(SharedTaxonomy.self, from: data)

        XCTAssertEqual(WanderPlaceCategory.allowedCategories, shared.categories.map(\.id))
        XCTAssertEqual(WanderPlaceCategory.editableCategories, shared.categories.filter(\.editable).map(\.id))
        XCTAssertEqual(WanderPlaceCategory.editableCategories.count, 14)
        XCTAssertFalse(WanderPlaceCategory.editableCategories.contains(WanderPlaceCategory.fallbackPlace))
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
