import MapKit
import XCTest
@testable import Wander

final class WanderPlaceCategoryTests: XCTestCase {
    func testMapKitParksStayParks() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .park), "park")
        XCTAssertEqual(WanderPlaceCategory.primary(for: .nationalPark), "park")
    }

    func testCategorySymbolsIncludePark() {
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "park"), "tree.fill")
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "hike"), "figure.hiking")
    }

    func testDisplayTaxonomySeparatesBroadCategoryAndSubcategory() {
        let restaurant = WanderPlaceCategory.display(for: "restaurant")
        XCTAssertEqual(restaurant.category, "Food & drink")
        XCTAssertEqual(restaurant.subcategory, "Restaurant")
        XCTAssertEqual(restaurant.primaryCategory, "restaurant")
        XCTAssertEqual(restaurant.compactTitle, "Restaurant · Food & drink")

        let transit = WanderPlaceCategory.display(for: "transportation")
        XCTAssertEqual(transit.category, "Transportation & transit")
        XCTAssertEqual(transit.subcategory, "Transit stop")

        let providerRestaurant = WanderPlaceCategory.display(for: "thai restaurant")
        XCTAssertEqual(providerRestaurant.primaryCategory, "restaurant")
        XCTAssertEqual(providerRestaurant.category, "Food & drink")
        XCTAssertEqual(providerRestaurant.subcategory, "Thai restaurant")

        let providerStore = WanderPlaceCategory.display(for: "art supply store")
        XCTAssertEqual(providerStore.category, "Shopping")
        XCTAssertEqual(providerStore.subcategory, "Art supply store")
    }

    func testQuestionCategoryRoutesProviderSubcategoriesToSmartQuestions() {
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "thai restaurant"), "restaurant")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "coffee shop"), "coffee")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "waterfall"), "hike")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "4-star hotel"), "hotel")
        XCTAssertEqual(WanderPlaceCategory.questionCategory(for: "art supply store"), "shop")

        let restaurantBlocks = AddQuestionTemplates.blocks(category: "thai restaurant", status: .been)
        XCTAssertEqual(restaurantBlocks.map(\.key), ["price", "occasion", "restaurant_tags"])
        XCTAssertFalse(restaurantBlocks.contains { $0.key == PlaceMemoryAttributeKeys.personalLabels })
    }

    func testMapKitHealthAndFitnessCategories() {
        XCTAssertEqual(WanderPlaceCategory.primary(for: .hospital), "hospital")
        XCTAssertEqual(WanderPlaceCategory.primary(for: .fitnessCenter), "gym")

        if #available(iOS 18.0, *) {
            XCTAssertEqual(WanderPlaceCategory.primary(for: .animalService), "veterinarian")
            XCTAssertEqual(WanderPlaceCategory.primary(for: .hiking), "hike")
        }
    }

    func testPlaceNameOverridesTuneBroadMapKitCategories() {
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Providence St. John's Health Center"),
            "hospital"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: nil as MKPointOfInterestCategory?, name: "Green Dog Dental"),
            "veterinarian"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Iron Fitness"),
            "gym"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Plankhaus"),
            "pilates studio"
        )
        XCTAssertEqual(
            WanderPlaceCategory.primary(for: .fitnessCenter, name: "Lake Shrine"),
            "spiritual"
        )
        XCTAssertEqual(WanderPlaceCategory.symbolName(for: "spiritual"), "sparkles")
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
            "231 Santa Monica Boulevard · Santa Monica · Restaurant · Food & drink"
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
            "231 Santa Monica Boulevard · Santa Monica · Restaurant · Food & drink"
        )
    }

    func testSwiftTaxonomyMatchesSharedTaxonomyIDs() throws {
        struct SharedTaxonomy: Decodable {
            struct Category: Decodable {
                let id: String
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

        XCTAssertEqual(WanderPlaceCategory.editableCategories, shared.categories.map(\.id))
    }
}
