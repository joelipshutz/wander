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

    func testLegacyPrivateCustomAnswersNeverInitializeThePublicAnswerMap() throws {
        let (store, visit, visiblePlace) = try fixture()
        let key = "custom_question_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let legacy = PlaceAttributeDraft(questionKey: key, valueType: "text", stringValue: "yes")
        visit.attributeAnswersJSON = VisitAttributeAnswers.encoded(from: [legacy])
        let checkIn = MapPlaceSaveContext.editVisit(visit, visiblePlace: visiblePlace)
        let local = LocalPlaceAttribute(localID: "legacy", userPlaceID: visit.userPlaceID,
            questionKey: key, valueType: "text", valueJSON: legacy.valueJSON)
        let wanna = MapPlaceSaveContext.editWant(visiblePlace, attributes: [local])

        XCTAssertNil(checkIn.initialAnswers[key])
        XCTAssertNil(wanna.initialAnswers[key])
        XCTAssertEqual(checkIn.originalAttributes, [legacy], "Private source is retained for safe recovery")
        XCTAssertTrue(PlaceSaveAttributePolicy.attributes(
            original: [legacy], answers: checkIn.initialAnswers, tags: [], tagKey: "coffee_tags", status: .been,
            customQuestions: [CheckInCustomQuestion(id: key, prompt: "Dogs?")]
        ).isEmpty, "An existing definition must not turn legacy history into publication consent")
        let submission = MapPlaceSaveSubmission(
            context: checkIn, candidate: checkIn.candidate, status: .been,
            visibility: .followers, ratingScore: nil, note: nil, attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false
        )
        XCTAssertFalse(validatesPrivateCheckInDraft(submission, store: store),
            "A caller cannot omit the private channel while removing legacy private history")
    }

    func testFailedPrivateAnswerLoadRejectsSubmissionBeforePublicAnswerIsCleared() async throws {
        let (store, visit, visiblePlace) = try fixture()
        let original = visit.attributeAnswersJSON
        let context = MapPlaceSaveContext.editVisit(visit, visiblePlace: visiblePlace)
        var submission = MapPlaceSaveSubmission(
            context: context, candidate: context.candidate, status: .been,
            visibility: .followers, ratingScore: nil, note: "Changed", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            customQuestionAnswersLoaded: false
        )
        XCTAssertFalse(validatesPrivateCheckInDraft(submission, store: store))
        let (result, updated) = await persistScopedVisitOrWantSubmission(submission, store: store, backend: nil)
        XCTAssertNil(result)
        XCTAssertNil(updated)
        XCTAssertEqual(visit.attributeAnswersJSON, original)
        XCTAssertEqual(visit.note, "Original")

        submission.customQuestionAnswersLoaded = true
        XCTAssertTrue(validatesPrivateCheckInDraft(submission, store: store),
            "A complete non-editor submission without a private channel remains supported")
        submission.customQuestionAnswers = [:]
        submission.customQuestionOwnerID = store.currentUser.id
        XCTAssertTrue(validatesPrivateCheckInDraft(submission, store: store),
            "A loaded empty private answer set is valid for fresh or edited Check-ins")
    }

    func testLegacyPrivateRecoveryIsPersistedAndNeverOverwritesNewerPrivateAnswer() throws {
        let suite = "check-in-legacy-recovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let question = CheckInCustomQuestion(id: "custom_question_aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", prompt: "Dogs?")
        let configuration = CheckInQuestionConfiguration(
            orderedQuestionIDs: [question.id], customQuestions: [question], stealthByQuestionID: [question.id: false]
        )
        try preferences.saveConfiguration(configuration, ownerUserID: "owner", subtypeKey: "coffee")
        let original = [PlaceAttributeDraft(questionKey: question.id, valueType: "text", stringValue: "yes")]
        let recovered = try loadAndMigratePrivateCheckInAnswers(
            originalAttributes: original, ownerUserID: "owner", userPlaceID: "save", visitID: "visit", preferences: preferences
        )
        XCTAssertEqual(recovered, [question.id: "yes"])
        XCTAssertEqual(try preferences.loadPrivateAnswers(ownerUserID: "owner", userPlaceID: "save", visitID: "visit"), recovered)
        XCTAssertFalse(preferences.configuration(ownerUserID: "owner", subtypeKey: "coffee", defaultQuestionIDs: []).isStealth(questionID: question.id),
            "Recovery leaves future preferences unchanged while historical answers remain in private storage")

        try preferences.savePrivateAnswers([question.id: "no"], ownerUserID: "owner", userPlaceID: "save", visitID: "visit")
        XCTAssertEqual(try loadAndMigratePrivateCheckInAnswers(
            originalAttributes: original, ownerUserID: "owner", userPlaceID: "save", visitID: "visit", preferences: preferences
        ), [question.id: "no"])
    }

    func testUnrecoverableLegacyPrivatePayloadRejectsEditWithoutPartialMigration() throws {
        let suite = "check-in-unknown-recovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = CheckInQuestionPreferenceStore(defaults: defaults)
        let original = [PlaceAttributeDraft(questionKey: "custom_question_future", valueType: "text", valueJSON: #"{"preserved":true}"#)]
        XCTAssertThrowsError(try loadAndMigratePrivateCheckInAnswers(
            originalAttributes: original, ownerUserID: "owner", userPlaceID: "save", visitID: "visit", preferences: preferences
        ))
        XCTAssertTrue(try preferences.loadPrivateAnswers(ownerUserID: "owner", userPlaceID: "save", visitID: "visit").isEmpty)
        XCTAssertEqual(original.first?.valueJSON, #"{"preserved":true}"#)
    }

    func testModeDraftCacheNeverRestoresAnotherAccountsPublicOrPrivateAnswers() throws {
        let draft = MapPlaceSaveModeDraft<String>(
            visibility: .followers, ratingScore: 4,
            selectedAnswers: ["place_detail_outlets": ["Plenty"]], unifiedTags: ["cozy"],
            note: "Owner A memory", visitedAt: .now, plannedDate: nil,
            photoAttachments: ["owner-a-photo"], selectedInviteeUserIDs: [],
            isShowingOptionalDetails: true, didLoadSharedVisitInvitees: true,
            sharedVisitInviteesError: nil,
            customQuestionAnswers: ["place_detail_noise": "Quiet"], customQuestionAnswersLoaded: true
        )
        var cache = MapPlaceSaveModeDraftCache<MapPlaceSaveModeDraft<String>>()
        cache.store(draft, for: .been, ownerUserID: "owner-a")
        cache.store(draft, for: .wannaGo, ownerUserID: "owner-a")
        XCTAssertEqual(cache.draft(for: .been, ownerUserID: "owner-a"), draft)
        XCTAssertEqual(cache.draft(for: .wannaGo, ownerUserID: "owner-a"), draft)
        XCTAssertNil(cache.draft(for: .been, ownerUserID: "owner-b"))
        XCTAssertNil(cache.draft(for: .wannaGo, ownerUserID: "owner-b"))
        XCTAssertNil(cache.draft(for: .been), "Unscoped callers cannot retrieve an account-bound draft")

        cache.store(draft, for: .wannaGo, ownerUserID: "owner-b")
        XCTAssertNil(cache.draft(for: .been, ownerUserID: "owner-b"), "Binding a new owner clears both old modes")
        XCTAssertNil(cache.draft(for: .wannaGo, ownerUserID: "owner-a"))
    }

    func testAccountSwitchRejectsActiveNewCheckInAndWannaSubmissionsBeforeSaving() async throws {
        let (store, _, _) = try fixture(ownerUserID: "owner-a")
        let ownerID = store.currentUser.id
        XCTAssertEqual(store.currentUser.serverID, "owner-a")
        let context = MapPlaceSaveContext.importCandidate(
            PlaceCandidate(id: "new-owner-draft", name: "Owner draft", category: WanderPlaceCategory.coffeeTeaSweets,
                latitude: 2, longitude: 2, confidence: 1), sourceType: .manual,
            status: .been, defaultVisibility: .followers
        )
        let attributes = [PlaceAttributeDraft(questionKey: "place_detail_outlets", valueType: "single_choice", stringValue: "Plenty")]
        let submission = MapPlaceSaveSubmission(
            context: context, candidate: context.candidate, status: .been, visibility: .followers,
            ratingScore: 4, note: "Owner A draft", attributes: attributes, photoAttachments: [],
            inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            customQuestionAnswers: [:], customQuestionOwnerID: ownerID, ownerUserID: ownerID
        )
        XCTAssertTrue(validatesPrivateCheckInDraft(submission, store: store))

        store.apply(authState: .signedIn(AuthSession(userID: "owner-b", displayName: "Owner B", handle: "owner_b")))
        let originalCount = store.currentUserVisiblePlaces.count
        for status in [PlaceStatus.been, .wannaGo] {
            var switched = submission.replacingImportCandidate(context.candidate, sourceType: .manual, status: status)
            switched.customQuestionOwnerID = store.currentUser.id
            XCTAssertEqual(switched.ownerUserID, ownerID)
            XCTAssertFalse(validatesPrivateCheckInDraft(switched, store: store),
                "Even a mistakenly restamped private channel cannot reassign the whole draft")
            let saved = await persistNewPlaceSaveSubmission(switched, store: store, backend: nil)
            XCTAssertNil(saved)
            XCTAssertEqual(store.currentUserVisiblePlaces.count, originalCount)
        }
    }

    func testExistingSourceOwnerCannotBeBypassedByOmittingSubmissionOwner() async throws {
        let (store, _, visiblePlace) = try fixture(ownerUserID: "owner-a")
        XCTAssertEqual(store.currentUser.serverID, "owner-a")
        let context = MapPlaceSaveContext.editWant(visiblePlace, attributes: [])
        let submission = MapPlaceSaveSubmission(
            context: context, candidate: context.candidate, status: .wannaGo,
            visibility: .followers, ratingScore: nil, note: "Owner A draft", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false
        )
        XCTAssertEqual(context.saveOwnerUserID, store.currentUser.id)
        XCTAssertTrue(validatesPrivateCheckInDraft(submission, store: store), "Existing owner-scoped callers remain valid")
        store.apply(authState: .signedIn(AuthSession(userID: "owner-b", displayName: "Owner B", handle: "owner_b")))
        XCTAssertEqual(store.currentUser.id, "owner-b")
        XCTAssertEqual(context.saveOwnerUserID, "owner-a", "Authenticated saves are not guest rows eligible for adoption")
        XCTAssertFalse(validatesPrivateCheckInDraft(submission, store: store))
        let (result, visit) = await persistScopedVisitOrWantSubmission(submission, store: store, backend: nil)
        XCTAssertNil(result)
        XCTAssertNil(visit)
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty)
    }

    private func fixture(ownerUserID: String? = nil) throws -> (WanderStore, LocalPlaceVisit, VisiblePlace) {
        let store = WanderStore(fixtures: .empty())
        if let ownerUserID {
            store.apply(authState: .signedIn(AuthSession(userID: ownerUserID, displayName: "Owner A", handle: "owner_a")))
        }
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
