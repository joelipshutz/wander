import XCTest
@testable import Wander

final class MapCategoryFilterTests: XCTestCase {
    private let food = WanderPlaceCategory.restaurantsFood
    private let coffee = WanderPlaceCategory.coffeeTeaSweets
    private let outdoors = WanderPlaceCategory.outdoorsNature

    func testSelectingChildrenClearsOnlyTheirParentAndAllowsMultipleChoices() {
        var selection = MapMoreFilterSelection(categories: [outdoors])
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Mexican", in: food)

        XCTAssertEqual(selection.categories, [outdoors])
        XCTAssertTrue(selection.isCategoryOptionSelected("Italian", in: food))
        XCTAssertTrue(selection.isCategoryOptionSelected("Mexican", in: food))
        XCTAssertEqual(selection.activeOptionCount, 3)
        XCTAssertEqual(selection.activeSectionCount, 1)
        XCTAssertTrue(selection.matchesCategory(food, subcategory: nil, cuisine: "Italian"))
        XCTAssertTrue(selection.matchesCategory(food, subcategory: nil, cuisine: "Mexican"))
        XCTAssertFalse(selection.matchesCategory(food, subcategory: nil, cuisine: "French"))
        XCTAssertFalse(selection.matchesCategory(food, subcategory: nil, cuisine: nil))
        XCTAssertTrue(selection.matchesCategory(outdoors, subcategory: "Park", cuisine: nil))
    }

    func testSelectingParentSelectsAllItsChildren() {
        var selection = MapMoreFilterSelection()
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Mexican", in: food)
        selection.toggleCategoryOption("Park", in: outdoors)
        selection.toggleCategory(food)

        XCTAssertEqual(selection.categories, [food])
        XCTAssertNil(selection.categoryOptions[food])
        XCTAssertTrue(selection.isCategoryOptionSelected("Italian", in: food))
        XCTAssertTrue(selection.isCategoryOptionSelected("French", in: food))
        XCTAssertTrue(selection.isCategoryOptionSelected("Park", in: outdoors))
        XCTAssertTrue(selection.matchesCategory(food, subcategory: nil, cuisine: "French"))
        selection.toggleCategory(food)
        XCTAssertFalse(selection.matchesCategory(food, subcategory: nil, cuisine: "Italian"))
    }

    func testEveryParentSupportsAllExceptOneAndReselectingAll() throws {
        for category in WanderPlaceCategory.editableCategories {
            let choices = MapMoreFilterPolicy.options(for: category)
            let first = try XCTUnwrap(choices.first, category)
            var selection = MapMoreFilterSelection()
            selection.toggleCategory(category)
            XCTAssertTrue(choices.allSatisfy { selection.isCategoryOptionSelected($0, in: category) })
            selection.toggleCategoryOption(first, in: category)
            XCTAssertFalse(selection.categories.contains(category))
            XCTAssertFalse(selection.isCategoryOptionSelected(first, in: category))
            XCTAssertTrue(choices.dropFirst().allSatisfy { selection.isCategoryOptionSelected($0, in: category) })
            XCTAssertEqual(selection.categoryOptions[category],
                MapMoreFilterPolicy.normalizedOptions(for: category).subtracting([WanderPlaceCategory.normalizedCategoryText(first)]))
            selection.toggleCategoryOption(first, in: category)
            XCTAssertTrue(selection.categories.contains(category))
            XCTAssertNil(selection.categoryOptions[category])
            selection.toggleCategory(category)
            XCTAssertFalse(selection.hasCategorySelection)
            XCTAssertTrue(choices.allSatisfy { !selection.isCategoryOptionSelected($0, in: category) })
            for choice in choices { selection.toggleCategoryOption(choice, in: category) }
            XCTAssertTrue(selection.categories.contains(category))
        }
    }

    func testDeselectingLastChildRestoresAllOnlyWhenNoOtherCategoryIsSelected() {
        var selection = MapMoreFilterSelection()
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption(" ITALIAN ", in: food)
        XCTAssertFalse(selection.hasCategorySelection)
        XCTAssertEqual(selection.activeOptionCount, 0)
        XCTAssertTrue(selection.matchesCategory(coffee, subcategory: nil, cuisine: nil))

        selection.toggleCategory(outdoors)
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Italian", in: food)
        XCTAssertTrue(selection.hasCategorySelection)
        XCTAssertFalse(selection.matchesCategory(food, subcategory: nil, cuisine: "Italian"))
    }

    func testChildMatchingUsesCuisineForFoodAndScopedSubcategoryForOtherCategories() {
        var selection = MapMoreFilterSelection()
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Park", in: outdoors)
        XCTAssertTrue(selection.matchesCategory(outdoors, subcategory: "PARK", cuisine: nil))
        XCTAssertFalse(selection.matchesCategory(coffee, subcategory: "Park", cuisine: nil))
        XCTAssertFalse(selection.matchesCategory(food, subcategory: "Italian", cuisine: "French"))
        XCTAssertFalse(selection.matchesCategory(outdoors, subcategory: nil, cuisine: "Park"))
    }

    func testChildrenCombineWithPeopleAndStatusAndAllCategoriesClearsOnlyCategories() {
        var selection = MapMoreFilterSelection(people: ["friend"], status: .wanna)
        selection.toggleCategoryOption("Italian", in: food)
        XCTAssertEqual(selection.activeSectionCount, 3)
        XCTAssertEqual(selection.activeOptionCount, 3)
        XCTAssertTrue(MapFilterSelection.matches(
            status: .wannaGo, category: food, cuisine: "Italian", ownerID: "friend", selection: selection
        ))
        XCTAssertFalse(MapFilterSelection.matches(
            status: .been, category: food, cuisine: "Italian", ownerID: "friend", selection: selection
        ))
        XCTAssertFalse(MapFilterSelection.matches(
            status: .wannaGo, category: food, cuisine: "Italian", ownerID: "other", selection: selection
        ))

        selection.selectAllCategories()
        XCTAssertTrue(selection.categoryOptions.isEmpty)
        XCTAssertEqual(selection.people, ["friend"])
        XCTAssertEqual(selection.status, .wanna)
        XCTAssertEqual(selection.activeOptionCount, 2)
    }

    func testSourceSwitchAndResetClearChildSelections() {
        var state = MapFilterState(source: .you)
        state.more.toggleCategoryOption("Italian", in: food)
        state.selectSource(.friends)
        XCTAssertEqual(state.more, MapMoreFilterSelection())
        state.more.toggleCategoryOption("Park", in: outdoors)
        state.reset(to: .you)
        XCTAssertEqual(state.more, MapMoreFilterSelection())
    }

    func testEveryCategoryHasUniqueCanonicalChildrenAndFoodOnlyShowsCuisines() {
        for category in WanderPlaceCategory.editableCategories {
            let options = MapMoreFilterPolicy.options(for: category)
            XCTAssertFalse(options.isEmpty, category)
            XCTAssertEqual(Set(options).count, options.count, category)
        }
        XCTAssertEqual(Set(MapMoreFilterPolicy.options(for: food)), Set(WanderPlaceCategory.restaurantCuisineOptions))
        XCTAssertFalse(MapMoreFilterPolicy.options(for: food).contains("Restaurant"))
    }

    func testExternalCandidatesRespectSpecificCuisineAndSubcategorySelections() {
        var selection = MapMoreFilterSelection()
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Park", in: outdoors)
        let italian = candidate(category: food, subcategory: "Italian", rawType: "italian restaurant")
        let mexican = candidate(category: food, subcategory: "Mexican", rawType: "mexican restaurant")
        let park = candidate(category: outdoors, subcategory: "Park")
        let beach = candidate(category: outdoors, subcategory: "Beach")
        XCTAssertTrue(MapSearchExternalCandidatePolicy.allows(italian, refinements: selection))
        XCTAssertFalse(MapSearchExternalCandidatePolicy.allows(mexican, refinements: selection))
        XCTAssertTrue(MapSearchExternalCandidatePolicy.allows(park, refinements: selection))
        XCTAssertFalse(MapSearchExternalCandidatePolicy.allows(beach, refinements: selection))
        selection.people = ["friend"]
        XCTAssertFalse(MapSearchExternalCandidatePolicy.allows(italian, refinements: selection))
    }

    func testVisiblePlacesUseViewerTaxonomyAndFoodType() {
        let italian = visiblePlace(id: "italian", category: food, subcategory: "Restaurant", cuisine: "Italian")
        let mexican = visiblePlace(id: "mexican", category: food, subcategory: "Restaurant", cuisine: "Mexican")
        let park = visiblePlace(id: "park", category: outdoors, subcategory: "Park")
        let beach = visiblePlace(id: "beach", category: outdoors, subcategory: "Beach")
        let places = [italian, mexican, park, beach]
        var selection = MapMoreFilterSelection()
        selection.toggleCategoryOption("Italian", in: food)
        selection.toggleCategoryOption("Park", in: outdoors)
        XCTAssertEqual(MapFilterSelection.applying(selection, to: places).map(\.id), ["italian", "park"])
        XCTAssertEqual(MapSearchCorpusPolicy.savedPlaces(
            from: places, refinements: selection
        ).map(\.id), ["italian", "park"])

        selection.toggleCategoryOption("Mexican", in: food)
        XCTAssertEqual(MapFilterSelection.ownPlaces(
            from: places, currentUserID: "viewer", refinements: selection
        ).map(\.id), ["italian", "mexican", "park"])
        XCTAssertEqual(MapFilterSelection.friendsPlaces(
            from: places, currentUserID: "someone", followedOwnerIDs: ["viewer"], refinements: selection
        ).map(\.id), ["italian", "mexican", "park"])
    }

    private func candidate(category: String, subcategory: String, rawType: String? = nil) -> PlaceCandidate {
        PlaceCandidate(
            id: subcategory, name: "Test place", category: category, primaryCategory: category,
            subcategory: subcategory, categorySource: PlaceCategorySource.user.rawValue,
            rawProviderType: rawType, latitude: 34, longitude: -118, confidence: 1
        )
    }

    private func visiblePlace(id: String, category: String, subcategory: String, cuisine: String? = nil) -> VisiblePlace {
        let owner = LocalProfile(localID: "viewer", handle: "viewer", displayName: "Viewer")
        let place = LocalPlace(localID: id, canonicalName: "Test place", category: coffee, latitude: 34, longitude: -118)
        let save = LocalUserPlace(
            localID: id, userID: owner.id, placeID: place.id, status: .been, visibility: .selfOnly,
            viewerPrimaryCategory: category, viewerSubcategory: subcategory, viewerFoodType: cuisine, sourceType: "test"
        )
        return VisiblePlace(id: id, place: place, userPlace: save, owner: owner)
    }
}
