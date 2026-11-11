import XCTest
@testable import Wander

@MainActor
final class QuickCaptureTests: XCTestCase {
    private let candidate = PlaceCandidate(id: "quick-capture-fixture", name: "Fixture Cafe",
        category: "coffee", latitude: 34, longitude: -118, sourceProvider: "manual", confidence: 1)

    private func store() -> WanderStore {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "quick-owner", displayName: "Fixture", handle: "fixture")))
        return store
    }

    func testUnratedDraftSurvivesRecoveryAndExplicitMidpointRemainsRated() throws {
        let context = MapPlaceSaveContext.importCandidate(candidate, sourceType: .manual,
            status: .been, defaultVisibility: .followers)
        var draft = try XCTUnwrap(PlaceSaveDraft.addFlow(ownerUserID: "quick-owner", context: context))
        XCTAssertNil(draft.form.selectedRatingScore)
        let recovered = try JSONDecoder().decode(PlaceSaveDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertNil(recovered.form.selectedRatingScore)
        draft.form.selectedRatingScore = 3
        let rated = try JSONDecoder().decode(PlaceSaveDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(rated.form.selectedRatingScore, 3)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: rated.form.selectedRatingScore), 3)
        XCTAssertNil(PlaceRating.scoreForSave(status: .been, score: recovered.form.selectedRatingScore))
    }

    func testQuickCapturePersistsUnratedAndExactPastVisitCanBeEnriched() async throws {
        let store = store()
        let original = store.saveCandidate(candidate, status: .been, visibility: .followers,
            note: "First memory", sourceType: .manual, ratingScore: 4.5)
        let first = try XCTUnwrap(store.visits(for: original.userPlaceID).first)
        let context = MapPlaceSaveContext.importCandidate(candidate, sourceType: .manual,
            status: .been, defaultVisibility: .followers)
        var submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: .been,
            visibility: .followers, ratingScore: nil, note: nil, attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            visitedAt: .now.addingTimeInterval(-86400))
        submission.detailsPending = true
        let result = await persistNewPlaceSaveSubmission(submission, store: store, backend: nil)
        let saved = try XCTUnwrap(result)
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first { $0.id != first.id })
        let visitID = visit.id
        XCTAssertNil(visit.ratingScore)
        XCTAssertEqual(visit.detailsPending, true)
        XCTAssertEqual(store.pendingCheckInDetails?.0.id, visitID)
        XCTAssertEqual(store.visits(for: saved.userPlaceID).count, 2)
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        submission = MapPlaceSaveSubmission(context: .editVisit(visit, visiblePlace: place),
            candidate: candidate, status: .been, visibility: .followers, ratingScore: 3,
            note: "Added later", attributes: [], photoAttachments: [], inviteeUserIDs: [],
            reconcilesSharedVisitInvitees: false, visitedAt: visit.visitedAt)
        let (_, updated) = await persistScopedVisitOrWantSubmission(submission, store: store, backend: nil)
        XCTAssertEqual(updated?.id, visitID)
        XCTAssertEqual(updated?.visitedAt, visit.visitedAt)
        XCTAssertEqual(updated?.ratingScore, 3)
        XCTAssertEqual(updated?.detailsPending, false)
        XCTAssertNil(store.pendingCheckInDetails)
        XCTAssertEqual(store.visits(for: saved.userPlaceID).count, 2)
        XCTAssertEqual(first.note, "First memory")
        XCTAssertEqual(first.ratingScore, 4.5)
        XCTAssertNotNil(store.updateVisit(visitID: visitID, ratingScore: nil, replacesRating: true))
        XCTAssertNil(visit.ratingScore)
    }

    func testBackdatedDetailedSaveSyncsItsOwnVisitWhileAnotherCaptureIsPending() async throws {
        let store = store()
        let pending = store.saveCandidate(candidate, status: .been, visibility: .followers,
            note: nil, sourceType: .manual, detailsPending: true)
        let recent = try XCTUnwrap(store.placeVisits.first { $0.id == pending.visitID })
        let repository = SuspendedQuickCaptureRepository()
        repository.suspendsFirstWrite = false
        let backend = WanderBackend(userPlaceRepository: repository)
        let context = MapPlaceSaveContext.importCandidate(candidate, sourceType: .manual,
            status: .been, defaultVisibility: .followers)
        let submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: .been,
            visibility: .followers, ratingScore: 4, note: "Older detailed visit", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            visitedAt: .now.addingTimeInterval(-86400))
        let result = await persistNewPlaceSaveSubmission(submission, store: store, backend: backend)
        let saved = try XCTUnwrap(result)
        let older = try XCTUnwrap(store.placeVisits.first { $0.id == saved.visitID })
        XCTAssertNotEqual(older.id, recent.id)
        XCTAssertEqual(repository.drafts.count, 1)
        XCTAssertEqual(repository.drafts.first?.visit.id, older.serverID)
        XCTAssertEqual(repository.drafts.first?.visit.note, "Older detailed visit")
        XCTAssertEqual(older.syncState, .synced)
        XCTAssertEqual(recent.detailsPending, true)
        XCTAssertNil(recent.note)
        XCTAssertNil(recent.ratingScore)
        XCTAssertNotEqual(recent.syncState, .synced)
    }

    func testDismissalSurvivesPersistenceAndDoesNotChangeTheVisitContents() throws {
        let store = store()
        let result = store.saveCandidate(candidate, status: .been, visibility: .selfOnly,
            note: nil, sourceType: .manual, detailsPending: true)
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let date = visit.visitedAt
        XCTAssertEqual(store.pendingCheckInDetails?.0.id, visit.id)
        store.dismissCheckInDetails(visitID: visit.id)
        let record = WanderStoreSnapshot.PlaceVisitRecord(visit)
        let restored = try JSONDecoder().decode(WanderStoreSnapshot.PlaceVisitRecord.self,
            from: JSONEncoder().encode(record)).model()
        XCTAssertEqual(restored.detailsPending, false)
        XCTAssertEqual(restored.visitedAt, date)
        XCTAssertNil(restored.ratingScore)
        XCTAssertNil(restored.note)
        XCTAssertEqual(restored.id, visit.id)
        XCTAssertNil(store.pendingCheckInDetails)
    }

    func testRepeatingVisitStartsUnratedWithoutCopyingPreviousVisitAnswers() throws {
        let store = store()
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers,
            note: "Earlier", sourceType: .manual, ratingScore: 5,
            attributes: [PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"])])
        let prior = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let context = MapPlaceSaveContext.addVisitVisiblePlace(place, attributes: store.attributes(for: place.id), latestVisit: prior)
        XCTAssertNil(context.initialRatingScore)
        XCTAssertNil(context.questionAnswerSourceVisit)
        XCTAssertTrue(context.initialAnswers.isEmpty)
        XCTAssertTrue(context.initialPersonalLabels.isEmpty)
        XCTAssertEqual(MapPlaceSaveContext.editVisit(prior, visiblePlace: place).initialRatingScore, 5)
    }

    func testQuickWannaHasNoVisitOrRating() async throws {
        let store = store()
        let context = MapPlaceSaveContext.importCandidate(candidate, sourceType: .manual,
            status: .wannaGo, defaultVisibility: .followers)
        let submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: .wannaGo,
            visibility: .followers, ratingScore: nil, note: nil, attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false)
        let result = await persistNewPlaceSaveSubmission(submission, store: store, backend: nil)
        let saved = try XCTUnwrap(result)
        XCTAssertTrue(store.visits(for: saved.userPlaceID).isEmpty)
        XCTAssertNil(store.currentUserVisiblePlaces.first?.userPlace.ratingScore)
        XCTAssertNil(store.pendingCheckInDetails)
    }

    func testEditingOrDismissingDuringFirstSyncCannotBeOverwrittenByItsAcknowledgement() async throws {
        for addsDetails in [false, true] {
            let store = store()
            let result = store.saveCandidate(candidate, status: .been, visibility: .followers,
                note: nil, sourceType: .manual, detailsPending: true)
            let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
            let repository = SuspendedQuickCaptureRepository()
            let backend = WanderBackend(userPlaceRepository: repository)
            let first = Task { await store.syncVisit(visitID: visit.id, backend: backend) }
            for _ in 0..<100 where repository.drafts.isEmpty { await Task.yield() }
            XCTAssertEqual(repository.drafts.count, 1)
            if addsDetails {
                XCTAssertNotNil(store.updateVisit(visitID: visit.id, note: "Added while saving", ratingScore: 4))
            } else {
                store.dismissCheckInDetails(visitID: visit.id)
            }
            let joiners = (0..<4).map { _ in Task { await store.syncVisit(visitID: visit.id, backend: backend) } }
            await Task.yield()
            XCTAssertEqual(repository.drafts.count, 1, "Only one write per visit may be in flight")
            repository.resume()
            let firstSynced = await first.value
            XCTAssertTrue(firstSynced)
            for joiner in joiners {
                let joined = await joiner.value
                XCTAssertTrue(joined)
            }
            XCTAssertEqual(repository.drafts.count, 2)
            XCTAssertEqual(repository.drafts.first?.visit.id, repository.drafts.last?.visit.id)
            XCTAssertEqual(repository.drafts.last?.visit.detailsPending, false)
            XCTAssertEqual(visit.detailsPending, false)
            XCTAssertEqual(visit.note, addsDetails ? "Added while saving" : nil)
            XCTAssertEqual(visit.ratingScore, addsDetails ? 4 : nil)
            XCTAssertEqual(visit.syncState, .synced)
        }
    }

    func testOrdinarySyncFailureDoesNotLoopAsIfTheUserEdited() async throws {
        let store = store()
        let result = store.saveCandidate(candidate, status: .been, visibility: .followers,
            note: nil, sourceType: .manual, detailsPending: true)
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let repository = SuspendedQuickCaptureRepository()
        repository.shouldFail = true
        let synced = await store.syncVisit(visitID: visit.id, backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertFalse(synced)
        XCTAssertEqual(repository.drafts.count, 1)
        XCTAssertEqual(visit.detailsPending, true)
        XCTAssertEqual(visit.syncState, .failed)
    }

    func testSwitchingAwayAndBackInvalidatesTheOriginalAcknowledgement() async throws {
        let store = store()
        let result = store.saveCandidate(candidate, status: .been, visibility: .followers,
            note: nil, sourceType: .manual, detailsPending: true)
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let repository = SuspendedQuickCaptureRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let syncing = Task { await store.syncVisit(visitID: visit.id, backend: backend) }
        for _ in 0..<100 where repository.drafts.isEmpty { await Task.yield() }
        XCTAssertEqual(repository.drafts.count, 1)
        store.apply(authState: .signedIn(AuthSession(userID: "other-owner", displayName: "Other", handle: "other")))
        store.apply(authState: .signedIn(AuthSession(userID: "quick-owner", displayName: "Fixture", handle: "fixture")))
        repository.resume()
        let synced = await syncing.value
        XCTAssertFalse(synced)
        XCTAssertNotEqual(visit.syncState, .synced)
    }

    func testLegacyUntouchedMidpointDraftIsRecoveredAsUnrated() throws {
        let context = MapPlaceSaveContext.importCandidate(candidate, sourceType: .manual,
            status: .been, defaultVisibility: .followers, ratingScore: 3)
        let draft = try XCTUnwrap(PlaceSaveDraft.addFlow(ownerUserID: "quick-owner", context: context))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        legacy["schemaVersion"] = 1
        let recovered = try JSONDecoder().decode(PlaceSaveDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(recovered.isRestorable(for: "quick-owner", now: .now))
        XCTAssertNil(recovered.restoredRatingScore)
        XCTAssertEqual(draft.restoredRatingScore, 3, "New drafts know that 3 was explicit")
        var persisted: PlaceSaveDraft? = recovered
        let persistence = PlaceSaveDraftPersistence(load: { persisted }, save: { persisted = $0 })
        let draftStore = PlaceSaveDraftStore(persistence: persistence)
        _ = draftStore.restore(ownerUserID: "quick-owner")
        var form = try XCTUnwrap(draftStore.draft?.form)
        XCTAssertNil(form.selectedRatingScore)
        form.selectedRatingScore = 3
        draftStore.update(draftID: recovered.id, form: form, submittedAt: nil)
        let relaunched = PlaceSaveDraftStore(persistence: persistence)
        _ = relaunched.restore(ownerUserID: "quick-owner")
        XCTAssertEqual(relaunched.draft?.restoredRatingScore, 3)
        XCTAssertEqual(relaunched.draft?.schemaVersion, PlaceSaveDraft.currentSchemaVersion)
    }

    func testReminderRoutesOnlyToTheExactVisitAndRejectsMalformedIdentity() throws {
        let parent = UUID().uuidString.lowercased(), visit = UUID().uuidString.lowercased()
        let route = WanderDeepLinkRoute.checkInDetails(userPlaceID: parent, visitID: visit)
        let url = try XCTUnwrap(route.url)
        XCTAssertEqual(WanderDeepLinkRoute.parse(url), route)
        XCTAssertEqual(PushNotificationManager.destination(from: url), .checkInDetails(userPlaceID: parent, visitID: visit))
        XCTAssertEqual(WanderRootView.notificationTab(for: .checkInDetails(userPlaceID: parent, visitID: visit)), .map)
        XCTAssertNil(WanderDeepLinkRoute.parse(URL(string: "recme://check-in-details/not-a-uuid/\(visit)")!))
        XCTAssertNil(PushNotificationManager.destination(from: ["recme": ["notification_type": "check_in_reminder", "data": ["visit_id": visit]]]))
    }

    func testReminderOpenAnalyticsAreCoarseAndDeduplicated() {
        let analytics = QuickCaptureRecordingAnalytics()
        let manager = PushNotificationManager(analytics: analytics)
        let payload: [AnyHashable: Any] = ["recme": [
            "event_id": UUID().uuidString,
            "notification_type": "check_in_reminder",
            "data": ["user_place_id": UUID().uuidString, "visit_id": UUID().uuidString]
        ]]
        XCTAssertTrue(manager.handleNotificationResponse(userInfo: payload))
        XCTAssertFalse(manager.handleNotificationResponse(userInfo: payload))
        XCTAssertEqual(analytics.events.count, 1)
        XCTAssertEqual(analytics.events.first?.name, WanderAnalyticsEvents.notificationOpened)
        XCTAssertEqual(analytics.events.first?.properties, [
            "notification_type": "check_in_reminder", "delivery_channel": "remote", "route": "check_in_details"
        ])
    }

    func testReminderPreferenceCanBeDisabledWithoutChangingOtherPushTypes() {
        var preferences = NotificationPreferences.allEnabled
        preferences.checkInRemindersEnabled = false
        XCTAssertTrue(preferences.pushEnabled)
        XCTAssertTrue(preferences.sharedVisitsEnabled)
        XCTAssertFalse(preferences.checkInRemindersEnabled)
        XCTAssertFalse(NotificationPreferences.allDisabled.checkInRemindersEnabled)
    }
}

@MainActor
private final class SuspendedQuickCaptureRepository: UserPlaceRepository, CheckInRepository {
    var drafts: [CheckInSaveDraft] = []
    var shouldFail = false
    var suspendsFirstWrite = true
    private var continuation: CheckedContinuation<Void, Never>?
    func resume() { continuation?.resume(); continuation = nil }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { [] }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        SaveResult(userPlaceID: "synced-quick-parent", syncState: .synced, placeID: "synced-quick-place")
    }
    func saveCheckIn(_ draft: CheckInSaveDraft) async throws -> CheckInSaveResult {
        drafts.append(draft)
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if drafts.count == 1 && suspendsFirstWrite { await withCheckedContinuation { continuation = $0 } }
        let parent = try await save(draft.userPlace)
        return CheckInSaveResult(saveResult: parent, visitResult: PlaceVisitResult(
            visitID: draft.visit.id!, userPlaceID: parent.userPlaceID, visitedAt: draft.visit.visitedAt,
            note: draft.visit.note, ratingScore: draft.visit.ratingScore, tags: [],
            backfilledFromUserPlace: false, attributeAnswersJSON: draft.visit.attributeAnswersJSON,
            detailsPending: draft.visit.detailsPending))
    }
    func deleteCheckIn(visitID: String) async throws -> CheckInDeleteResult {
        CheckInDeleteResult(visitID: visitID, userPlaceID: nil, transition: .removed)
    }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

private final class QuickCaptureRecordingAnalytics: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
