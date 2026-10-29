import XCTest
@testable import Wander

@MainActor
final class PlaceCheckInObservationProjectionTests: XCTestCase {
    func testAnswerCompletenessSurvivesSnapshotRoundTrip() throws {
        for complete in [false, true] {
            let source = visit("persisted", at: 100, answer: nil)
            source.serverID = "00000000-0000-0000-0000-000000000001"
            source.attributeAnswersAreComplete = complete
            let data = try JSONEncoder().encode(WanderStoreSnapshot.PlaceVisitRecord(source))
            let record = try JSONDecoder().decode(WanderStoreSnapshot.PlaceVisitRecord.self, from: data)
            XCTAssertEqual(record.model().attributeAnswersAreComplete, complete)
        }
    }

    func testLegacyRemoteEmptySnapshotStaysUnknownUntilHydrated() throws {
        let source = visit("persisted", at: 100, answer: nil)
        source.serverID = "00000000-0000-0000-0000-000000000001"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WanderStoreSnapshot.PlaceVisitRecord(source))) as? [String: Any])
        json.removeValue(forKey: "attributeAnswersAreComplete")
        let record = try JSONDecoder().decode(WanderStoreSnapshot.PlaceVisitRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(record.model().attributeAnswersAreComplete, false)
    }

    func testLatestExplicitNegativeReplacesPositiveRegardlessOfInputOrder() throws {
        let older = visit("older", at: 100, answer: "Plenty")
        let newer = visit("newer", at: 200, answer: "None found")

        for visits in [[older, newer], [newer, older]] {
            let answer = try XCTUnwrap(project(visits).first)
            XCTAssertEqual(value(answer), "None found")
            XCTAssertEqual(answer.createdAt, newer.visitedAt)
            XCTAssertTrue(PlaceProfileAttributePresentation.searchTerms(from: answer).isEmpty)
        }
    }

    func testLaterPositiveCanReplaceEarlierNegative() throws {
        let older = visit("older", at: 100, answer: "None found")
        let newer = visit("newer", at: 200, answer: "A few")
        let answer = try XCTUnwrap(project([older, newer]).first)

        XCTAssertEqual(value(answer), "A few")
        XCTAssertEqual(PlaceProfileAttributePresentation.displayValues(from: answer), ["Outlets: A few"])
        XCTAssertTrue(PlaceProfileAttributePresentation.searchTerms(from: answer).contains("outlets"))
    }

    func testLaterUnansweredVisitRetainsEarlierAnswerAndItsDate() throws {
        let answered = visit("answered", at: 100, answer: "Plenty")
        let unanswered = visit("unanswered", at: 200, answer: nil)
        let answer = try XCTUnwrap(project([unanswered, answered]).first)

        XCTAssertEqual(value(answer), "Plenty")
        XCTAssertEqual(answer.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(answer.updatedAt, answered.updatedAt)
    }

    func testDeletingLatestVisitRevealsPreviousAnswer() throws {
        let older = visit("older", at: 100, answer: "Plenty")
        let deleted = visit("deleted", at: 200, answer: "None found")
        deleted.deletedAt = Date(timeIntervalSince1970: 300)

        XCTAssertEqual(value(try XCTUnwrap(project([older, deleted]).first)), "Plenty")
    }

    func testClearingAnEditedAnswerDoesNotMeanNoOrResurrectParentSnapshot() throws {
        let older = visit("older", at: 100, answer: "A few")
        let edited = visit("edited", at: 200, answer: "None found")
        edited.attributeAnswersJSON = "[]"
        edited.updatedAt = Date(timeIntervalSince1970: 300)
        let base = [parentAttribute(answer: "None found")]

        XCTAssertEqual(value(try XCTUnwrap(project([older, edited], base: base).first)), "A few")
        XCTAssertTrue(project([edited], base: base).isEmpty)
    }

    func testDeletingEveryVisitRemovesEvenAStaleParentAnswer() {
        let deleted = visit("deleted", at: 200, answer: "Plenty")
        deleted.deletedAt = Date(timeIntervalSince1970: 300)

        XCTAssertTrue(project([deleted], base: [parentAttribute(answer: "Plenty")]).isEmpty)
    }

    func testEditingAnOlderVisitDoesNotMakeItTheNewestObservation() throws {
        let editedOld = visit("edited-old", at: 100, answer: "Plenty")
        editedOld.createdAt = Date(timeIntervalSince1970: 500)
        editedOld.updatedAt = Date(timeIntervalSince1970: 600)
        let recentVisit = visit("recent", at: 200, answer: "None found")

        XCTAssertEqual(value(try XCTUnwrap(project([editedOld, recentVisit]).first)), "None found")
    }

    func testProjectedAnswerRetainsVisitAndEditDatesAndSyncState() throws {
        let source = visit("source", at: 100, answer: "A few")
        source.updatedAt = Date(timeIntervalSince1970: 400)
        source.syncStateRaw = SyncState.pendingUpdate.rawValue
        let answer = try XCTUnwrap(project([source]).first)

        XCTAssertEqual(answer.createdAt, source.visitedAt)
        XCTAssertEqual(answer.updatedAt, source.updatedAt)
        XCTAssertEqual(answer.syncState, .pendingUpdate)
        XCTAssertEqual(answer.userPlaceID, "save")
        XCTAssertTrue(answer.localID.contains(source.localID))
    }

    func testWannaDoesNotExposeCheckInFactsButRetainsOrdinaryMetadata() {
        let tag = LocalPlaceAttribute(
            localID: "tag", userPlaceID: "save", questionKey: "personal_labels",
            valueType: "personal_label", valueJSON: #"["Try later"]"#
        )
        let answer = parentAttribute(answer: "Plenty")
        let observations = [visit("visit", at: 100, answer: "Plenty")]

        for visits in [observations, []] {
            let projected = PlaceCheckInObservationProjection.attributes(
                base: [answer, tag], visits: visits, userPlaceID: "save", status: .wannaGo
            )
            XCTAssertEqual(projected.map(\.questionKey), ["personal_labels"])
            XCTAssertEqual(projected.first?.valueJSON, tag.valueJSON)
        }
    }

    func testNoVisitHistoryKeepsAvailableParentSnapshotWithoutChangingItsDates() {
        let parent = parentAttribute(answer: "A few")
        parent.createdAt = Date(timeIntervalSince1970: 10)
        parent.updatedAt = Date(timeIntervalSince1970: 20)
        let result = project([], base: [parent])

        XCTAssertEqual(result.map(\.valueJSON), [parent.valueJSON])
        XCTAssertEqual(result.first?.createdAt, parent.createdAt)
        XCTAssertEqual(result.first?.updatedAt, parent.updatedAt)
    }

    func testUnhydratedSocialHistoryDoesNotPretendKnownParentDetailsWereCleared() {
        let unknown = visit("social", at: 200, answer: nil)
        unknown.attributeAnswersAreComplete = false
        let parent = parentAttribute(answer: "A few")

        for hasLoadedVisitHistory in [false, true] {
            XCTAssertEqual(
                project([unknown], base: [parent], hasLoadedVisitHistory: hasLoadedVisitHistory).map(\.valueJSON),
                [parent.valueJSON]
            )
        }
    }

    func testAuthoritativeEmptyHistoryRemovesStaleDetailsButKeepsOtherAttributes() {
        let label = LocalPlaceAttribute(
            localID: "label", userPlaceID: "save", questionKey: "personal_labels",
            valueType: "personal_label", valueJSON: #"["Weekend"]"#
        )
        let base = [parentAttribute(answer: "Plenty"), label]

        XCTAssertEqual(project([], base: base).map(\.questionKey), base.map(\.questionKey))
        let loaded = project([], base: base, hasLoadedVisitHistory: true)
        XCTAssertEqual(loaded.map(\.questionKey), ["personal_labels"])
        XCTAssertEqual(loaded.first?.valueJSON, label.valueJSON)
    }

    func testUnknownLaterVisitDoesNotReplaceAnExplicitOwnerObservation() throws {
        let known = visit("known", at: 100, answer: "None found")
        let unknown = visit("unknown", at: 200, answer: nil)
        unknown.attributeAnswersAreComplete = false

        let answer = try XCTUnwrap(project([unknown, known]).first)
        XCTAssertEqual(value(answer), "None found")
        XCTAssertEqual(answer.createdAt, known.visitedAt)
    }

    func testMixedHistoryKeepsParentAnswerMissingFromCompleteVisits() throws {
        let unknown = visit("unhydrated", at: 100, answer: nil)
        unknown.attributeAnswersAreComplete = false
        let blank = visit("new-blank", at: 200, answer: nil)
        let parent = parentAttribute(answer: "Plenty")
        parent.createdAt = Date(timeIntervalSince1970: 40)
        parent.updatedAt = Date(timeIntervalSince1970: 60)

        let retained = try XCTUnwrap(project([unknown, blank], base: [parent]).first)
        XCTAssertEqual(value(retained), "Plenty")
        XCTAssertEqual(retained.createdAt, parent.createdAt)
        XCTAssertEqual(retained.updatedAt, parent.updatedAt)
    }

    func testNewerIncompleteVisitKeepsPotentiallyNewerParentAnswerWithoutInventedDates() throws {
        let known = visit("known", at: 100, answer: "None found")
        let unknown = visit("unhydrated", at: 200, answer: nil)
        unknown.attributeAnswersAreComplete = false
        let parent = parentAttribute(answer: "A few")
        parent.createdAt = Date(timeIntervalSince1970: 90)
        parent.updatedAt = Date(timeIntervalSince1970: 250)

        for visits in [[known, unknown], [unknown, known]] {
            let retained = try XCTUnwrap(project(visits, base: [parent]).first)
            XCTAssertEqual(value(retained), "A few")
            XCTAssertEqual(retained.createdAt, parent.createdAt)
            XCTAssertEqual(retained.updatedAt, parent.updatedAt)
        }
    }

    func testKnownAnswerNewerThanAllIncompleteVisitsReplacesParent() throws {
        let unknown = visit("unhydrated", at: 100, answer: nil)
        unknown.attributeAnswersAreComplete = false
        let known = visit("known", at: 200, answer: "None found")

        let answer = try XCTUnwrap(project([known, unknown], base: [parentAttribute(answer: "Plenty")]).first)
        XCTAssertEqual(value(answer), "None found")
        XCTAssertEqual(answer.createdAt, known.visitedAt)
    }

    func testDeletedIncompleteVisitDoesNotPreventAuthoritativeClear() {
        let deleted = visit("deleted-unhydrated", at: 100, answer: nil)
        deleted.attributeAnswersAreComplete = false
        deleted.deletedAt = Date(timeIntervalSince1970: 300)
        let cleared = visit("complete-cleared", at: 200, answer: nil)

        XCTAssertTrue(project([deleted, cleared], base: [parentAttribute(answer: "Plenty")]).isEmpty)
    }

    func testCompleteEmptyOwnerHistoryAuthoritativelyClearsParentSnapshot() {
        let cleared = visit("cleared", at: 200, answer: nil)
        cleared.attributeAnswersAreComplete = true

        XCTAssertTrue(project([cleared], base: [parentAttribute(answer: "Plenty")]).isEmpty)
    }

    private func project(
        _ visits: [LocalPlaceVisit], base: [LocalPlaceAttribute] = [],
        hasLoadedVisitHistory: Bool = false
    ) -> [LocalPlaceAttribute] {
        PlaceCheckInObservationProjection.attributes(
            base: base, visits: visits, userPlaceID: "save", status: .been,
            hasLoadedVisitHistory: hasLoadedVisitHistory
        )
    }

    private func visit(_ id: String, at time: TimeInterval, answer: String?) -> LocalPlaceVisit {
        let attributes = answer.map {
            [PlaceAttributeDraft(questionKey: "place_detail_outlets", valueType: "single_choice", stringValue: $0)]
        } ?? []
        let date = Date(timeIntervalSince1970: time)
        return LocalPlaceVisit(
            localID: id,
            userPlaceID: "save",
            visitedAt: date,
            attributeAnswersJSON: VisitAttributeAnswers.encoded(from: attributes),
            createdAt: date,
            updatedAt: date
        )
    }

    private func parentAttribute(answer: String) -> LocalPlaceAttribute {
        LocalPlaceAttribute(
            localID: "parent", userPlaceID: "save", questionKey: "place_detail_outlets",
            valueType: "single_choice", valueJSON: String(decoding: try! JSONEncoder().encode(answer), as: UTF8.self)
        )
    }

    private func value(_ attribute: LocalPlaceAttribute) -> String? {
        PlaceAttributeValuePresentation.strings(from: attribute.valueJSON).first
    }
}
