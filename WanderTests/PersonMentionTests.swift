import XCTest
@testable import Wander

final class PersonMentionTests: XCTestCase {
    private func person(_ id: String = "caitlin", name: String = "Caitlin Cortez", handle: String = "cait123") -> ProfileShell {
        ProfileShell(id: id, handle: handle, displayName: name, avatarURL: nil, bio: nil, relationship: .mutual)
    }

    func testEmptyAndFirstLetterQueriesUseTheCaretAndIgnoreEmail() throws {
        for text in ["@", "Hi @", "(@"] {
            XCTAssertEqual(PersonMentionDraft(text: text).query(at: NSRange(location: text.utf16.count, length: 0))?.text, "")
        }
        let text = "Hi @c and elsewhere"
        XCTAssertEqual(PersonMentionDraft(text: text).query(at: NSRange(location: 5, length: 0))?.text, "c")
        XCTAssertNil(PersonMentionDraft(text: "a@c.com").query(at: NSRange(location: 7, length: 0)))
        XCTAssertNil(PersonMentionDraft(text: "@c\nnext").query(at: NSRange(location: 7, length: 0)))
        XCTAssertNil(PersonMentionDraft(text: "@c").query(at: NSRange(location: 1, length: 1)))
    }

    func testSelectionInsertsFullNameKeepsAccountIdentityAndCollapses() throws {
        var draft = PersonMentionDraft(text: "With @c")
        let query = try XCTUnwrap(draft.query(at: NSRange(location: 7, length: 0)))
        let caret = try XCTUnwrap(draft.select(person(), for: query))
        XCTAssertEqual(draft.text, "With @Caitlin Cortez ")
        XCTAssertEqual(draft.mentions.map(\.userID), ["caitlin"])
        XCTAssertEqual(draft.searchText, "With @cait123 ")
        XCTAssertNil(draft.query(at: caret))
        draft.replace(caret, with: "and @")
        XCTAssertEqual(draft.query(at: NSRange(location: draft.text.utf16.count, length: 0))?.text, "")
    }

    func testSelectionReplacesOnlyActiveQueryNotSurroundingText() throws {
        var draft = PersonMentionDraft(text: "Meet @c tomorrow")
        let query = try XCTUnwrap(draft.query(at: NSRange(location: 7, length: 0)))
        _ = draft.select(person(), for: query)
        XCTAssertEqual(draft.text, "Meet @Caitlin Cortez tomorrow")
        XCTAssertEqual(draft.mentions.count, 1)
    }

    func testEmojiOffsetsAndEditsPreserveOnlyIntactSelectedTokens() throws {
        var draft = PersonMentionDraft(text: "🍜 @c")
        let query = try XCTUnwrap(draft.query(at: NSRange(location: draft.text.utf16.count, length: 0)))
        _ = draft.select(person(), for: query)
        XCTAssertEqual(draft.mentions.first?.location, 3)
        draft.reconcile("Great " + draft.text)
        XCTAssertEqual(draft.mentions.first?.location, 9)
        XCTAssertTrue(try XCTUnwrap(draft.mentions.first).isValid(in: draft.text))
        draft.replace(NSRange(location: 11, length: 1), with: "x")
        XCTAssertTrue(draft.mentions.isEmpty)
    }

    func testNameHandleAndSurnameMatchesAreOneResultPerID() {
        let caitlin = person()
        let camilo = person("camilo", name: "Camilo Flores", handle: "camilo")
        XCTAssertEqual(PersonMentionCandidates.matching([caitlin, caitlin, camilo], query: "c").map(\.id), ["caitlin", "camilo"])
        XCTAssertEqual(PersonMentionCandidates.matching([caitlin, camilo], query: "cort").map(\.id), ["caitlin"])
        XCTAssertEqual(PersonMentionCandidates.matching([caitlin], query: "CAIT1").map(\.id), ["caitlin"])
        XCTAssertEqual(PersonMentionCandidates.matching([person(name: "José Márquez")], query: "mar").count, 1)
        XCTAssertEqual(PersonMentionCandidates.name(for: person(name: " ")), "cait123")
        let enriched = PersonMentionCandidates.matching([person(name: ""), caitlin], query: "cortez")
        XCTAssertEqual(enriched.map(\.displayName), ["Caitlin Cortez"])
    }

    func testUnselectedTextIsNeverTurnedIntoAnAccountTag() {
        let draft = PersonMentionDraft(text: "@Caitlin Cortez")
        XCTAssertTrue(draft.mentions.isEmpty)
        XCTAssertEqual(draft.searchText, draft.text)
    }

    func testInvalidatedSelectionCannotReplaceNewlyEditedText() throws {
        var draft = PersonMentionDraft(text: "@c")
        let query = try XCTUnwrap(draft.query(at: NSRange(location: 2, length: 0)))
        draft.reconcile("@joe")
        XCTAssertNil(draft.select(person(), for: query))
        XCTAssertEqual(draft.text, "@joe")
    }

    @MainActor
    func testRecommendationFailureStillSearchesAndRetries() async {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        await model.search(query: "c", ownerID: "viewer", local: { [] },
            recommendations: { throw URLError(.notConnectedToInternet) }, remote: { _ in [caitlin] },
            eligible: { _ in true }, debounce: .zero)
        XCTAssertEqual(model.profiles.map(\.id), ["caitlin"])
        XCTAssertFalse(model.failed)
        await model.search(query: "", ownerID: "viewer", local: { [] },
            recommendations: { throw URLError(.notConnectedToInternet) }, remote: { _ in [] },
            eligible: { _ in true }, debounce: .zero)
        XCTAssertTrue(model.failed)
        await model.search(query: "", ownerID: "viewer", local: { [] },
            recommendations: { [caitlin] }, remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        XCTAssertEqual(model.profiles.map(\.id), ["caitlin"])
        XCTAssertFalse(model.failed)
    }

    @MainActor
    func testAccountChangeClearsRecommendations() async {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        await model.search(query: "", ownerID: "first", local: { [] }, recommendations: { [caitlin] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        await model.search(query: "", ownerID: "second", local: { [] }, recommendations: { [] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        XCTAssertTrue(model.profiles.isEmpty)
    }

    @MainActor
    func testAsyncResultsCannotReopenDismissedPicker() async {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        var started = false
        let delayed = Task {
            await model.search(query: "c", ownerID: "viewer", local: { [caitlin] },
                recommendations: {
                    started = true
                    try? await Task.sleep(for: .milliseconds(100))
                    return [caitlin]
                }, remote: { _ in [caitlin] }, eligible: { _ in true }, debounce: .zero)
        }
        while !started { await Task.yield() }
        await model.search(query: nil, ownerID: "viewer", local: { [] }, recommendations: { [] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        await delayed.value
        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testReopeningPickerRefreshesConsentFilteredRecommendations() async {
        let model = PersonTypeaheadModel()
        await model.search(query: "", ownerID: "viewer", local: { [] }, recommendations: { [person()] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        XCTAssertEqual(model.profiles.count, 1)
        await model.search(query: nil, ownerID: "viewer", local: { [] }, recommendations: { [] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        await model.search(query: "", ownerID: "viewer", local: { [] }, recommendations: { [] },
                           remote: { _ in [] }, eligible: { _ in true }, debounce: .zero)
        XCTAssertTrue(model.profiles.isEmpty)
    }

    @MainActor
    func testBareAtKeepsConnectionsThenSharedRecommendationOrder() async {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        let camilo = person("camilo", name: "Camilo Flores", handle: "camilo")
        await model.search(query: "", ownerID: "viewer", local: { [caitlin] },
            recommendations: { [camilo, caitlin] }, remote: { _ in [] },
            eligible: { _ in true }, debounce: .zero)
        XCTAssertEqual(model.profiles.map(\.id), ["caitlin", "camilo"])
    }

    @MainActor
    func testRankingDeduplicatesAndRechecksBlocksAfterResponse() async {
        let model = PersonTypeaheadModel()
        let caitlin = person()
        let camilo = person("camilo", name: "Camilo Flores", handle: "camilo")
        var blocked = false
        await model.search(query: "c", ownerID: "viewer", local: { [caitlin] },
            recommendations: { [camilo, caitlin] }, remote: { _ in blocked = true; return [caitlin, camilo] },
            eligible: { !blocked || $0.id != "camilo" }, debounce: .zero)
        XCTAssertEqual(model.profiles.map(\.id), ["caitlin"])
    }
}
