import XCTest
@testable import Wander

@MainActor
final class PlaceVisitAnswerSafetyTests: XCTestCase {
    func testUnknownServerAnswersRejectEditsBeforeAnyLocalMutation() throws {
        let (store, visit, _) = try fixture()
        visit.attributeAnswersAreComplete = false
        let originalJSON = visit.attributeAnswersJSON
        let originalNote = visit.note
        let originalDate = visit.visitedAt

        XCTAssertFalse(store.canEditVisitAnswers(visitID: visit.id))
        XCTAssertNil(store.updateVisit(
            visitID: visit.id, visitedAt: .now, note: "Should not save", attributes: [], replacesNote: true
        ))
        XCTAssertEqual(visit.attributeAnswersJSON, originalJSON)
        XCTAssertEqual(visit.note, originalNote)
        XCTAssertEqual(visit.visitedAt, originalDate)
        XCTAssertEqual(visit.attributeAnswersAreComplete, false)
    }

    func testBypassingSheetStillCannotClearUnknownServerAnswers() async throws {
        let (store, visit, visiblePlace) = try fixture()
        visit.attributeAnswersAreComplete = false
        let context = MapPlaceSaveContext.editVisit(visit, visiblePlace: visiblePlace)
        let submission = MapPlaceSaveSubmission(
            context: context, candidate: context.candidate, status: .been,
            visibility: .followers, ratingScore: nil, note: "Changed", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false
        )

        XCTAssertFalse(validatesPrivateCheckInDraft(submission, store: store))
        let (result, updated) = await persistScopedVisitOrWantSubmission(submission, store: store, backend: nil)
        XCTAssertNil(result)
        XCTAssertNil(updated)
        XCTAssertEqual(visit.note, "Original")
    }

    func testCompleteOwnerAnswersMayBeExplicitlyCleared() throws {
        let (store, visit, _) = try fixture()
        visit.attributeAnswersAreComplete = true

        XCTAssertNotNil(store.updateVisit(visitID: visit.id, attributes: []))
        XCTAssertEqual(visit.attributeAnswersJSON, "[]")
        XCTAssertEqual(visit.attributeAnswersAreComplete, true)
    }

    func testLegacyUnsentLocalDraftWithAssignedUUIDRemainsEditableOffline() throws {
        let (store, visit, _) = try fixture()
        visit.attributeAnswersAreComplete = nil
        visit.attributeAnswersJSON = "[]"
        visit.serverUpdatedAt = nil
        visit.syncStateRaw = SyncState.pendingCreate.rawValue

        XCTAssertTrue(visit.localID.hasPrefix("local_visit_"))
        XCTAssertTrue(store.canEditVisitAnswers(visitID: visit.id))
        XCTAssertNotNil(store.updateVisit(visitID: visit.id, note: "Offline edit", attributes: []))
    }

    func testLegacySyncedEmptyAnswersNeedHydration() throws {
        let (store, visit, _) = try fixture()
        visit.attributeAnswersAreComplete = nil
        visit.attributeAnswersJSON = "[]"
        visit.serverUpdatedAt = Date()
        visit.syncStateRaw = SyncState.synced.rawValue

        XCTAssertFalse(store.canEditVisitAnswers(visitID: visit.id))
        XCTAssertNil(store.updateVisit(visitID: visit.id, attributes: []))
    }

    private func fixture() throws -> (WanderStore, LocalPlaceVisit, VisiblePlace) {
        let store = WanderStore(fixtures: .empty())
        let saved = store.saveCandidate(
            PlaceCandidate(
                id: "answer-safety", name: "Answer Safety", category: WanderPlaceCategory.coffeeTeaSweets,
                latitude: 1, longitude: 1, confidence: 1
            ), status: .been, visibility: .followers, note: "Original", sourceType: .manual,
            attributes: [PlaceAttributeDraft(questionKey: "place_detail_outlets", valueType: "single_choice", stringValue: "None found")]
        )
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        visit.serverID = UUID().uuidString.lowercased()
        visit.serverUpdatedAt = Date()
        visit.syncStateRaw = SyncState.synced.rawValue
        let visiblePlace = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        return (store, visit, visiblePlace)
    }
}
