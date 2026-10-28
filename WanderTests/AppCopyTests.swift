import XCTest
@testable import Wander

final class AppCopyTests: XCTestCase {
    func testCapitalizesEveryWordIncludingSmallWordsAndHyphenatedWords() {
        XCTAssertEqual(AppCopy.capitalizingWords("check-in at a place on your map"), "Check-In At A Place On Your Map")
        XCTAssertEqual(AppCopy.capitalizingWords("déjà vu\nmore places"), "Déjà Vu\nMore Places")
        XCTAssertEqual(AppCopy.capitalizingWords("de\u{301}ja\u{300} vu"), "De\u{301}ja\u{300} Vu")
    }

    func testPreservesContractionsAcronymsBrandsAndUnits() {
        XCTAssertEqual(AppCopy.capitalizingWords("don't change someone's Wi-Fi or BBQ on iPhone"),
                       "Don't Change Someone's Wi-Fi Or BBQ On iPhone")
        XCTAssertEqual(AppCopy.capitalizingWords("2 km away · 5 min ago"), "2 km Away · 5 min Ago")
        XCTAssertEqual(AppCopy.capitalizingWords(""), "")
    }

    func testQuestionDisplayDoesNotRewritePersistedAnswersOrSearchTerms() throws {
        let question = try XCTUnwrap(PlaceCheckInQuestionCatalog.question(id: "place_detail_dietary_options"))
        XCTAssertTrue(question.acceptedOptions.contains("Gluten free"))
        XCTAssertFalse(question.acceptedOptions.contains("Gluten Free"))
        XCTAssertEqual(AppCopy.capitalizingWords("Gluten free"), "Gluten Free")
        XCTAssertEqual(question.searchTerms(for: "Gluten free"), ["gluten free options"])
    }

    func testCategoryDisplayPreservesStorageAndCustomNames() {
        let assignment = PlaceCategoryAssignment(primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
                                                 subcategory: "Coffee shop", source: "user")
        XCTAssertEqual(assignment.subcategory, "Coffee shop")
        XCTAssertEqual(WanderPlaceCategory.display(for: assignment).subcategory, "Coffee Shop")
        XCTAssertEqual(WanderPlaceCategory.displayLabel("CrossFit gym"), "CrossFit Gym")
        XCTAssertEqual(WanderPlaceCategory.displayLabel("my special corner"), "my special corner")
    }
}
