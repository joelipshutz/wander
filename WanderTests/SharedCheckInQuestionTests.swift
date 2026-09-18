import XCTest
@testable import Wander

@MainActor
final class SharedCheckInQuestionTests: XCTestCase {
    private let id = "custom_question_5ebaaf58-4c10-4faa-a021-09b357aa461d"

    func testSharedEnvelopeRetainsPromptAndAnswerThroughVisitSerialization() throws {
        let question = CheckInCustomQuestion(id: id, prompt: "  Can I\nbring a dog?  ")
        let attribute = try XCTUnwrap(SharedCheckInQuestion.encode(question: question, answer: "no"))
        XCTAssertEqual(attribute.questionKey, "place_detail_custom_5ebaaf58-4c10-4faa-a021-09b357aa461d")
        XCTAssertEqual(attribute.valueType, "text")
        XCTAssertEqual(SharedCheckInQuestion.customQuestionID(for: attribute.questionKey), id)
        let roundTrip = try XCTUnwrap(VisitAttributeAnswers.drafts(
            fromAttributeAnswersJSON: VisitAttributeAnswers.encoded(from: [attribute])
        ).first)
        let decoded = try XCTUnwrap(SharedCheckInQuestion.decode(roundTrip))
        XCTAssertEqual(decoded.question.prompt, "Can I bring a dog?")
        XCTAssertEqual(decoded.answer, "no")
        XCTAssertTrue(VisitAttributeAnswers.tags(from: [attribute]).isEmpty)
    }

    func testLegacyPrivateIDsAndMalformedOrFuturePayloadsCannotBecomeSharedAnswers() throws {
        let valid = try XCTUnwrap(SharedCheckInQuestion.encode(
            question: CheckInCustomQuestion(id: id, prompt: "Dogs allowed?"), answer: "yes"
        ))
        let invalid = [
            PlaceAttributeDraft(questionKey: id, valueType: valid.valueType, valueJSON: valid.valueJSON),
            PlaceAttributeDraft(questionKey: "place_detail_custom_invalid", valueType: valid.valueType, valueJSON: valid.valueJSON),
            PlaceAttributeDraft(questionKey: valid.questionKey, valueType: "single_choice", valueJSON: valid.valueJSON),
            PlaceAttributeDraft(questionKey: valid.questionKey, valueType: "text", valueJSON: #"{"schema_version":2,"prompt":"Dogs allowed?","answer":"yes"}"#),
            PlaceAttributeDraft(questionKey: valid.questionKey, valueType: "text", valueJSON: #"{"schema_version":1,"prompt":"Dogs allowed?","answer":"maybe"}"#),
            PlaceAttributeDraft(questionKey: valid.questionKey, valueType: "text", valueJSON: #"{"schema_version":1,"prompt":"  ","answer":"yes"}"#)
        ]
        for attribute in invalid { XCTAssertNil(SharedCheckInQuestion.decode(attribute)) }
        XCTAssertNil(SharedCheckInQuestion.encode(question: CheckInCustomQuestion(id: id, prompt: "Dogs?"), answer: "Yes"))
        XCTAssertNil(SharedCheckInQuestion.encode(question: CheckInCustomQuestion(id: id, prompt: String(repeating: "x", count: 121)), answer: "yes"))
    }

    func testSharedCustomAnswerDisplaysContextWithoutInventingSearchOrTasteMeaning() throws {
        let draft = try XCTUnwrap(SharedCheckInQuestion.encode(
            question: CheckInCustomQuestion(id: id, prompt: "Are dogs prohibited?"), answer: "no"
        ))
        let attribute = localAttribute(draft)
        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: attribute), ["Are dogs prohibited? No"])
        XCTAssertTrue(PlaceProfileAttributePresentation.searchTerms(from: attribute).isEmpty)
        XCTAssertTrue(PlaceProfileTagParser.tags(from: attribute).isEmpty)

        let owner = LocalProfile(localID: "owner", handle: "owner", displayName: "Owner")
        let place = LocalPlace(localID: "place", canonicalName: "Cafe", category: "coffee", latitude: 0, longitude: 0)
        let save = LocalUserPlace(localID: "save", userID: owner.id, placeID: place.id,
            status: .been, visibility: .followers, savedAt: .now, sourceType: "manual")
        let visible = VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner, attributes: [attribute])
        for query in ["dogs", "prohibited", "yes", "no", "schema_version"] {
            XCTAssertTrue(TrustedPlaceSearch.matches(query: query, in: [visible]).isEmpty)
        }
    }

    func testSharedCustomAnswersUseVisitPrecedenceAndClearWithoutParentResurrection() throws {
        let draft = try XCTUnwrap(SharedCheckInQuestion.encode(
            question: CheckInCustomQuestion(id: id, prompt: "Dogs allowed?"), answer: "yes"
        ))
        let visit = LocalPlaceVisit(localID: "visit", userPlaceID: "save", visitedAt: .now,
            attributeAnswersJSON: VisitAttributeAnswers.encoded(from: [draft]))
        let base = [localAttribute(draft)]
        let projected = try XCTUnwrap(PlaceCheckInObservationProjection.attributes(
            base: base, visits: [visit], userPlaceID: "save", status: .been
        ).first)
        XCTAssertEqual(
            try XCTUnwrap(SharedCheckInQuestion.decode(projected)),
            try XCTUnwrap(SharedCheckInQuestion.decode(draft)),
            "Visit projection preserves the complete envelope regardless of JSON object key order"
        )
        visit.attributeAnswersJSON = "[]"
        XCTAssertTrue(PlaceCheckInObservationProjection.attributes(
            base: base, visits: [visit], userPlaceID: "save", status: .been
        ).isEmpty)
        XCTAssertTrue(PlaceCheckInObservationProjection.attributes(
            base: base, visits: [], userPlaceID: "save", status: .wannaGo
        ).isEmpty)
    }

    func testCachedInvitationCannotPrefillSomeoneElsesQuestionAnswers() {
        let answers = [
            VisitAttributeAnswer(questionKey: "place_detail_outlets", valueType: "single_choice", value: .string("Plenty")),
            VisitAttributeAnswer(questionKey: "place_detail_custom_5ebaaf58-4c10-4faa-a021-09b357aa461d", valueType: "text", value: .object(["prompt": .string("Dogs?"), "answer": .string("yes")])),
            VisitAttributeAnswer(questionKey: id, valueType: "text", value: .string("yes")),
            VisitAttributeAnswer(questionKey: "coffee_tags", valueType: "multi_tag", value: .array([.string("Quiet")]))
        ]
        let invitation = SharedVisitInvitation(
            participantID: "participant", groupID: "group", invitationGeneration: 1,
            snapshotRevision: 1, status: .pending, invitedAt: .now, sourceVisitID: "source",
            sourceOwnerUserID: "owner", sourceOwnerHandle: "owner", sourceOwnerDisplayName: "Owner",
            sourceOwnerAvatarURL: nil, placeID: "place", placeName: "Cafe", category: "coffee",
            primaryCategory: "coffee_tea_sweets", subcategory: "Coffee shop", address: nil,
            locality: nil, region: nil, country: nil, latitude: 0, longitude: 0,
            sourceProvider: "manual", sourceProviderPlaceID: nil, visitedAt: .now,
            note: "Source note", ratingScore: nil, attributeAnswers: answers, tags: ["quiet"], photos: []
        )
        XCTAssertEqual(invitation.attributeDrafts.map(\.questionKey), ["coffee_tags"])
        XCTAssertEqual(invitation.attributeAnswers, answers, "Filtering prefill does not mutate cached history")
    }

    private func localAttribute(_ draft: PlaceAttributeDraft) -> LocalPlaceAttribute {
        LocalPlaceAttribute(localID: "answer", userPlaceID: "save", questionKey: draft.questionKey,
            valueType: draft.valueType, valueJSON: draft.valueJSON)
    }
}
