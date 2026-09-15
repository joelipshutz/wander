import XCTest
@testable import Wander

final class PlaceSaveAttributePolicyTests: XCTestCase {
    func testEditingPreservesUnknownTypedPayloadAndPersonalLabelIdentity() {
        let unknown = PlaceAttributeDraft(questionKey: "future_detail", valueType: "text", valueJSON: "{\"nested\":[1,true]}")
        let labels = PlaceAttributeDraft(questionKey: "personal_labels", valueType: "personal_label", stringValues: ["Favorite", "Remove me"])
        let tags = PlaceAttributeDraft(questionKey: "park_tags", valueType: "multi_tag", stringValues: ["Sunset"])
        let result = PlaceSaveAttributePolicy.attributes(
            original: [unknown, labels, tags], answers: [:], tags: ["Favorite", "Sunset", "Ryan's pick"],
            tagKey: "coffee_tags", status: .been
        )
        XCTAssertEqual(result.first, unknown)
        XCTAssertEqual(result.first { $0.questionKey == "personal_labels" }?.valueType, "personal_label")
        XCTAssertEqual(result.first { $0.questionKey == "personal_labels" }?.valueJSON, "[\"Favorite\"]")
        XCTAssertEqual(result.first { $0.questionKey == "park_tags" }, tags)
        XCTAssertEqual(result.first { $0.questionKey == "coffee_tags" }?.valueJSON, "[\"Ryan's pick\"]")
    }

    func testAddingTagsPreservesAnUnrecognizedOlderTagPayload() {
        let original = PlaceAttributeDraft(questionKey: "park_tags", valueType: "text", valueJSON: "{\"future\":true}")
        let result = PlaceSaveAttributePolicy.attributes(
            original: [original], answers: [:], tags: ["Sunset"], tagKey: "park_tags", status: .been
        )
        XCTAssertEqual(result.first, original)
        XCTAssertEqual(result.last?.questionKey, "place_memory_tags")
        XCTAssertEqual(result.last?.valueJSON, "[\"Sunset\"]")
    }

    func testUnknownFutureQuestionSurvivesWithoutLosingItsTypeOrPayload() {
        let unknown = PlaceAttributeDraft(questionKey: "place_detail_future", valueType: "boolean", valueJSON: "false")
        XCTAssertEqual(PlaceSaveAttributePolicy.attributes(
            original: [unknown], answers: [:], tags: [], tagKey: "park_tags", status: .been
        ), [unknown])
    }

    func testExplicitClearRemovesAnAnswerWhileAnUntouchedAnswerIsRetained() throws {
        let question = try XCTUnwrap(PlaceCheckInQuestionCatalog.allQuestions.first)
        let answer = try XCTUnwrap(question.options.first)
        let original = PlaceAttributeDraft(questionKey: question.id, valueType: "single_choice", stringValue: answer)
        XCTAssertEqual(PlaceSaveAttributePolicy.attributes(
            original: [original], answers: [question.id: [answer]], tags: [], tagKey: "park_tags", status: .been
        ), [original])
        XCTAssertTrue(PlaceSaveAttributePolicy.attributes(
            original: [original], answers: [question.id: []], tags: [], tagKey: "park_tags", status: .been
        ).isEmpty)
    }

    func testWannaCannotPublishNewFirsthandAnswers() throws {
        let question = try XCTUnwrap(PlaceCheckInQuestionCatalog.allQuestions.first)
        let answer = try XCTUnwrap(question.options.first)
        XCTAssertTrue(PlaceSaveAttributePolicy.attributes(
            original: [], answers: [question.id: [answer]], tags: [], tagKey: "park_tags", status: .wannaGo
        ).isEmpty)
    }

    func testHiddenAndCustomQuestionAnswersNeverBecomeSharedAttributes() {
        XCTAssertTrue(PlaceSaveAttributePolicy.attributes(
            original: [], answers: ["custom_question_123": ["yes"]], tags: [], tagKey: "park_tags", status: .been
        ).isEmpty)
    }
}
