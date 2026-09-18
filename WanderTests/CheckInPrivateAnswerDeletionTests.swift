import XCTest
@testable import Wander

@MainActor
final class CheckInPrivateAnswerDeletionTests: XCTestCase {
    func testDeletingOneVisitRemovesOnlyItsPrivateAnswers() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let (store, userPlace, first) = try savedVisit()
        let second = try XCTUnwrap(store.createVisit(
            userPlaceID: userPlace.id, visitedAt: .now, note: nil, ratingScore: nil
        ))
        let question = try createQuestion(in: preferences, owner: store.currentUser.id)
        for visit in [first, second] {
            try preferences.savePrivateAnswers([question.id: "yes"], ownerUserID: store.currentUser.id,
                userPlaceID: userPlace.localID, visitID: visit.serverID ?? visit.localID)
        }

        let deleted = await store.deleteVisit(visitID: first.id, backend: nil, privateQuestionPreferences: preferences)

        XCTAssertTrue(deleted)
        XCTAssertTrue(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: userPlace.localID, visitID: first.serverID ?? first.localID).isEmpty)
        XCTAssertEqual(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: userPlace.localID, visitID: second.serverID ?? second.localID), [question.id: "yes"])
        XCTAssertEqual(store.visits(for: userPlace.id).map(\.id), [second.id])
        XCTAssertEqual(preferences.allCustomQuestions(ownerUserID: store.currentUser.id), [question])
    }

    func testDeletingSaveRemovesAllItsVisitAliasesAndPreservesOtherData() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let (store, userPlace, visit) = try savedVisit()
        let question = try createQuestion(in: preferences, owner: store.currentUser.id)
        let otherOwnerQuestion = try createQuestion(in: preferences, owner: "other-owner")
        let stableVisitID = visit.serverID ?? visit.localID
        // An earlier local parent ID was never presented after restoration.
        // Whole-save deletion must still find this record through its visit UUID.
        try preferences.savePrivateAnswers([question.id: "yes"], ownerUserID: store.currentUser.id,
            userPlaceID: "earlier-parent-local-id", visitID: stableVisitID)
        try preferences.savePrivateAnswers([question.id: "no"], ownerUserID: store.currentUser.id,
            userPlaceID: "unrelated-parent", visitID: "unrelated-visit")
        try preferences.savePrivateAnswers([otherOwnerQuestion.id: "yes"], ownerUserID: "other-owner",
            userPlaceID: userPlace.localID, visitID: stableVisitID)

        XCTAssertNotNil(store.removeSave(userPlaceID: userPlace.id, privateQuestionPreferences: preferences))

        XCTAssertTrue(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: "earlier-parent-local-id", visitID: stableVisitID).isEmpty)
        XCTAssertEqual(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: "unrelated-parent", visitID: "unrelated-visit"), [question.id: "no"])
        XCTAssertEqual(try preferences.loadPrivateAnswers(ownerUserID: "other-owner",
            userPlaceID: userPlace.localID, visitID: stableVisitID), [otherOwnerQuestion.id: "yes"])
        XCTAssertEqual(preferences.allCustomQuestions(ownerUserID: store.currentUser.id), [question])
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.userPlace.id == userPlace.id })
    }

    func testUnreadablePrivateStorageDoesNotClaimSuccessfulDeletion() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let (store, userPlace, visit) = try savedVisit()
        _ = try createQuestion(in: preferences, owner: store.currentUser.id)
        let key = try XCTUnwrap(defaults.persistentDomain(forName: suite)?.keys.first)
        let corrupted = Data("invalid".utf8)
        defaults.set(corrupted, forKey: key)

        XCTAssertFalse(store.deleteVisit(visitID: visit.id, privateQuestionPreferences: preferences))
        XCTAssertNil(store.removeSave(userPlaceID: userPlace.id, privateQuestionPreferences: preferences))
        XCTAssertNil(visit.deletedAt)
        XCTAssertNil(userPlace.deletedAt)
        XCTAssertNotNil(store.lastRemoteError)
        XCTAssertEqual(defaults.data(forKey: key), corrupted)
    }

    func testLegacyVisitServerIdentityPromotionKeepsPrivateAnswersAndDeletionWorking() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let (store, userPlace, visit) = try savedVisit()
        visit.serverID = nil
        let question = try createQuestion(in: preferences, owner: store.currentUser.id)
        try preferences.savePrivateAnswers([question.id: "yes"], ownerUserID: store.currentUser.id,
            userPlaceID: userPlace.localID, visitID: visit.localID)
        let serverID = UUID().uuidString

        XCTAssertNil(store.migratePrivateQuestionAnswers(for: visit, to: serverID, preferences: preferences))
        visit.serverID = serverID
        XCTAssertEqual(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: userPlace.localID, visitID: serverID), [question.id: "yes"])
        XCTAssertTrue(store.deleteVisit(visitID: serverID, privateQuestionPreferences: preferences))
        XCTAssertTrue(try preferences.loadPrivateAnswers(ownerUserID: store.currentUser.id,
            userPlaceID: userPlace.localID, visitID: serverID).isEmpty)
    }

    private func savedVisit() throws -> (WanderStore, LocalUserPlace, LocalPlaceVisit) {
        let store = WanderStore(fixtures: .empty())
        store.apply(authState: .signedIn(AuthSession(userID: UUID().uuidString, displayName: "Test", handle: "test")))
        let result = store.saveCandidate(
            PlaceCandidate(id: "private-answer-deletion", name: "Test Cafe", category: "coffee",
                latitude: 34, longitude: -118, confidence: 1),
            status: .been, visibility: .selfOnly, note: nil, sourceType: .manual
        )
        let userPlace = try XCTUnwrap(store.userPlaces.first { $0.id == result.userPlaceID })
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        return (store, userPlace, visit)
    }

    private func createQuestion(in preferences: CheckInQuestionPreferenceStore, owner: String) throws -> CheckInCustomQuestion {
        var configuration = CheckInQuestionConfiguration(orderedQuestionIDs: [])
        let question = try configuration.addCustomQuestion(prompt: "Plants?")
        try preferences.saveConfiguration(configuration, ownerUserID: owner, subtypeKey: "cafe")
        return question
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "CheckInPrivateAnswerDeletionTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }
}
