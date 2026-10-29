import XCTest
@testable import Wander

final class AppCopyTests: XCTestCase {
    func testCapitalizesOnlyTheInitialOfAStandaloneLabel() {
        XCTAssertEqual(AppCopy.capitalizingInitial("check-in at a place on your map"), "Check-in at a place on your map")
        XCTAssertEqual(AppCopy.capitalizingInitial("déjà vu"), "Déjà vu")
        XCTAssertEqual(AppCopy.capitalizingInitial("de\u{301}ja\u{300} vu"), "De\u{301}ja\u{300} vu")
        XCTAssertEqual(AppCopy.capitalizingInitial("“more places”"), "“More places”")
    }

    func testPreservesContractionsAcronymsBrandsAndNumericPhrases() {
        XCTAssertEqual(AppCopy.capitalizingInitial("don't change someone's Wi-Fi or BBQ on iPhone"),
                       "Don't change someone's Wi-Fi or BBQ on iPhone")
        XCTAssertEqual(AppCopy.capitalizingInitial("iPhone settings"), "iPhone settings")
        XCTAssertEqual(AppCopy.capitalizingInitial("2 km away · 5 min ago"), "2 km away · 5 min ago")
        XCTAssertEqual(AppCopy.capitalizingInitial(""), "")
    }

    func testQuestionDisplayDoesNotRewritePersistedAnswersOrSearchTerms() throws {
        let question = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_dietary_options"))
        XCTAssertTrue(question.acceptedOptions.contains("Gluten free"))
        XCTAssertEqual(AppCopy.capitalizingInitial("Gluten free"), "Gluten free")
        XCTAssertEqual(question.searchTerms(for: "Gluten free"), ["gluten free options"])
    }

    func testCategoryDisplayPreservesStorageAndCustomNames() {
        let assignment = PlaceCategoryAssignment(primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
                                                 subcategory: "Coffee shop", source: "user")
        XCTAssertEqual(assignment.subcategory, "Coffee shop")
        XCTAssertEqual(WanderPlaceCategory.display(for: assignment).subcategory, "Coffee shop")
        XCTAssertEqual(WanderPlaceCategory.displayLabel("CrossFit gym"), "CrossFit gym")
        XCTAssertEqual(WanderPlaceCategory.displayLabel("my special corner"), "my special corner")
    }
}
