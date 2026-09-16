import XCTest
@testable import Wander

final class PlaceMemoryTagPresentationTests: XCTestCase {
    func testSuggestionsCollapseWhitespaceCaseAndReviewedSynonyms() {
        XCTAssertEqual(PlaceMemoryTagPresentation.suggestions([
            "  morning   routine ", "MORNING SPOT", "morning stop", "Date Night", "date shortlist", "with Dad"
        ]), ["morning routine", "Date Night", "with Dad"])
    }

    func testSimilarButDifferentPersonalLabelsAreNeverFuzzyMerged() {
        let labels = ["morning spot with Dad", "morning spot with Mom", "morning spots", "Morningstar", "date with Sam", "date with Sara"]
        XCTAssertEqual(PlaceMemoryTagPresentation.suggestions(labels), labels)
        XCTAssertEqual(PlaceMemoryTagPresentation.options(suggestions: [], selected: Set(labels)).count, labels.count)
    }

    func testGroupedSelectedOptionsRetainEveryOriginalPersistedValue() {
        let originals: Set<String> = [" Morning   Routine ", "morning spot", "MORNING ROUTINE", "with Dad"]
        let options = PlaceMemoryTagPresentation.options(suggestions: ["morning stop", "work session"], selected: originals)
        XCTAssertEqual(options.count, 3)
        XCTAssertEqual(options.first?.selectedValues, Set([" Morning   Routine ", "morning spot", "MORNING ROUTINE"]))
        XCTAssertEqual(Set(options.flatMap(\.selectedValues)), originals)
        XCTAssertEqual(options.filter(\.isSelected).count, 2)
        XCTAssertEqual(originals.count, 4, "Presentation must not rewrite the saved set.")
    }

    func testSuggestionLimitDoesNotHideSelectedLegacyAndCustomTags() {
        let suggestions = (1...20).map { "suggestion \($0)" }
        let selected = Set((1...12).map { "personal label \($0)" }).union(["outlets", "dog friendly"])
        let options = PlaceMemoryTagPresentation.options(suggestions: suggestions, selected: selected)
        XCTAssertEqual(options.filter { !$0.isSelected }.count, 8)
        XCTAssertEqual(Set(options.flatMap(\.selectedValues)), selected)
        XCTAssertEqual(options.count, 22)
    }

    func testExplicitToggleClearsOnlyTheDisplayedAliasGroup() {
        let selected: Set<String> = ["morning routine", " Morning   Spot ", "morning spot with Dad", "other label"]
        let updated = PlaceMemoryTagPresentation.toggling("morning stop", selected: selected)
        XCTAssertEqual(updated, ["morning spot with Dad", "other label"])
        XCTAssertEqual(selected.count, 4)
        XCTAssertEqual(PlaceMemoryTagPresentation.toggling("new label", selected: updated), updated.union(["new label"]))
    }

    func testSuggestionsAndSelectionGroupsAreStableAndIgnoreBlankInput() {
        XCTAssertEqual(PlaceMemoryTagPresentation.suggestions(["", "  ", "a", "b", "A"]), ["a", "b"])
        XCTAssertTrue(PlaceMemoryTagPresentation.suggestions(["a"], limit: 0).isEmpty)
        let selected: Set<String> = ["work spot", "Work session", "another label"]
        XCTAssertEqual(
            PlaceMemoryTagPresentation.options(suggestions: ["work session", "date night"], selected: selected).map(\.id),
            ["work session", "date night", "another label"]
        )
        XCTAssertEqual(PlaceMemoryTagPresentation.toggling(" \n ", selected: selected), selected)
    }
}
