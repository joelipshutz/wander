import XCTest
@testable import Wander

@MainActor
final class PlaceWannaSaveTests: XCTestCase {
    private var candidate: PlaceCandidate {
        PlaceCandidate(id: "repeat-wanna-cafe", name: "Repeat Wanna Cafe", category: "coffee",
                       latitude: 34.1, longitude: -118.3, sourceProvider: "manual",
                       sourceProviderPlaceID: "repeat-wanna-cafe", confidence: 1)
    }

    func testWannaCheckInAndRepeatedWannasPreserveCheckInSummaryAndCounters() async throws {
        let store = WanderStore(fixtures: .seed())
        _ = await store.saveNewWanna(candidate, visibility: .followers, note: "First Wanna",
                                     plannedDate: nil, attributes: [], backend: nil)
        let checkedIn = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                            note: "Actual visit", sourceType: .manual, ratingScore: 4)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first {
            $0.userPlace.id == checkedIn.userPlaceID
        }?.userPlace)
        let wannaCount = store.currentUserVisiblePlaces.filter { $0.userPlace.status == .wannaGo }.count
        let visitIDs = store.visits(for: parent.id).map(\.id)
        let updatedAt = parent.updatedAt
        for note in ["Go again", "One more Wanna"] {
            _ = await store.saveNewWanna(candidate, visibility: .selfOnly, note: note,
                                         plannedDate: nil, attributes: [], backend: nil)
        }
        XCTAssertEqual(parent.status, .been)
        XCTAssertEqual(parent.note, "Actual visit")
        XCTAssertEqual(parent.visibility, .followers)
        XCTAssertEqual(parent.ratingScore, 4)
        XCTAssertEqual(parent.updatedAt, updatedAt)
        XCTAssertEqual(parent.historicalWantNote, "First Wanna")
        XCTAssertEqual(store.visits(for: parent.id).map(\.id), visitIDs)
        XCTAssertEqual(store.currentUserVisiblePlaces.filter { $0.userPlace.status == .wannaGo }.count, wannaCount)
        XCTAssertEqual(Set(store.wannaSaves(for: parent).compactMap(\.note)), ["Go again", "One more Wanna"])
        let summary = PlaceSaveSummary(visiblePlace: try XCTUnwrap(store.currentUserVisiblePlaces.first {
            $0.userPlace.id == parent.id
        }), attributes: [])
        let entry = PlaceActivityEntry(summary: summary, visit: nil, kind: .historicalWant,
                                       currentUserID: store.currentUser.id, wanna: store.wannaSaves(for: parent)[0])
        XCTAssertEqual(entry.status, .wannaGo)
        XCTAssertNotEqual(entry.note, parent.note)
        XCTAssertNil(entry.ratingScore)
        XCTAssertTrue(entry.canEdit)
        XCTAssertEqual(entry.sortBucket, 0, "New Wanna events sort by their own date in ALL")
    }

    func testCompletedWannaAndCheckInFormsKeepDistinctDetailsAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let statuses: [PlaceStatus] = [.wannaGo, .wannaGo, .been, .been, .wannaGo]
        let plannedDate = WannaGoDate.normalized(Date.now.addingTimeInterval(86400 * 10))
        var operationIDs = Set<UUID>()
        var parentID: String?
        for (index, status) in statuses.enumerated() {
            let existing = MapPlaceSaveContext.currentUserSave(matching: candidate, in: store.currentUserVisiblePlaces)
            let base = MapPlaceSaveContext.addCandidate(candidate, sourceType: .manual,
                defaultVisibility: .followers, currentUserSave: existing,
                latestVisit: existing.flatMap { store.visits(for: $0.userPlace.id).first })
            let state = PlaceProfileSaveActionPolicy.state(currentUserSave: existing,
                hasSharedVisitInvitation: false, isReadOnly: false)
            let action = try XCTUnwrap(PlaceProfileSaveActionPolicy.resolve(state: state).actions.first {
                $0.destinationStatus == status
            })
            let context = PlaceProfileSaveActionPolicy.attachedSaveContext(route: .floatingActions,
                state: state, action: action, baseContext: base) ?? base.preselectingStatus(status)
            let draft = try XCTUnwrap(PlaceSaveDraft.restorableFlow(ownerUserID: store.currentUser.id, context: context))
            XCTAssertTrue(operationIDs.insert(draft.id).inserted)
            let submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: status,
                visibility: .followers, ratingScore: status == .been ? 4 : nil,
                note: "Record \(index)", attributes: [PlaceAttributeDraft(questionKey: "coffee_tags",
                    valueType: "multi_tag", valueJSON: "[\"tag-\(index)\"]")],
                photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
                visitedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86400),
                plannedDate: status == .wannaGo ? plannedDate : nil, wannaOperationID: draft.id)
            let saved = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
            let result = try XCTUnwrap(saved)
            parentID = result.userPlaceID
        }
        let data = try JSONEncoder().encode(try XCTUnwrap(snapshot))
        snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: data)
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let parent = try XCTUnwrap(restored.currentUserVisiblePlaces.first { $0.userPlace.id == parentID }?.userPlace)
        XCTAssertEqual(parent.status, .been)
        XCTAssertEqual(parent.historicalWantNote, "Record 0")
        let wannas = restored.wannaSaves(for: parent)
        XCTAssertEqual(Set(wannas.compactMap(\.note)), ["Record 1", "Record 4"])
        XCTAssertEqual(Set(wannas.map(\.id)).count, 2)
        XCTAssertTrue(wannas.allSatisfy { $0.plannedDate == plannedDate })
        XCTAssertTrue(wannas.allSatisfy { $0.attributeAnswersJSON.contains("tag-") })
        let visits = restored.visits(for: parent.id)
        XCTAssertEqual(Set(visits.compactMap(\.note)), ["Record 2", "Record 3"])
        XCTAssertEqual(Set(visits.map(\.id)).count, 2)
        XCTAssertEqual(Set(visits.map(\.visitedAt)).count, 2)
    }

    func testRepeatWannaOnlyCountsPlaceOnceAndPersistsAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        _ = await store.saveNewWanna(candidate, visibility: .followers, note: "Original",
                                     plannedDate: nil, attributes: [], backend: nil)
        let before = store.currentUserVisiblePlaces.filter { $0.userPlace.status == .wannaGo }.count
        let id = UUID().uuidString.lowercased()
        for _ in 0..<2 {
            let result = await store.saveNewWanna(candidate, operationID: id, visibility: .followers, note: "Repeat",
                                                   plannedDate: nil, attributes: [], backend: WanderBackend())
            XCTAssertEqual(result.syncState, .pendingCreate)
        }
        XCTAssertEqual(store.currentUserVisiblePlaces.filter { $0.userPlace.status == .wannaGo }.count, before)
        XCTAssertEqual(store.placeWannaSaves.count, 1, "A retry of the same form must not append twice")
        let encoded = try JSONEncoder().encode(try XCTUnwrap(snapshot))
        snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: encoded)
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        XCTAssertEqual(restored.placeWannaSaves.map(\.id), [id])
        XCTAssertFalse(try XCTUnwrap(restored.placeWannaSaves.first).isSynced)
        XCTAssertEqual(restored.currentUserVisiblePlaces.filter { $0.userPlace.status == .wannaGo }.count, before)
    }

    func testFailedSyncRetriesTheSameUUIDAndNeverWritesTheParentSummary() async throws {
        let store = WanderStore(fixtures: .seed())
        let result = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                          note: "Visit", sourceType: .manual, ratingScore: 5)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace)
        parent.serverID = "22222222-2222-4222-8222-222222222222"
        let repository = RepeatWannaTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let failed = await store.saveNewWanna(candidate, visibility: .followers, note: "Again",
                                               plannedDate: nil, attributes: [], backend: backend)
        XCTAssertEqual(failed.syncState, .failed)
        XCTAssertEqual(parent.status, .been)
        XCTAssertEqual(parent.note, "Visit")
        let id = try XCTUnwrap(store.placeWannaSaves.first?.id)
        repository.shouldFail = false
        let count = await store.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(repository.attempts, [id, id])
        XCTAssertEqual(repository.parentWriteCount, 0)
        XCTAssertTrue(try XCTUnwrap(store.placeWannaSaves.first).isSynced)
        let duplicate = await store.saveNewWanna(candidate, operationID: id, visibility: .followers,
                                                  note: "Again", plannedDate: nil, attributes: [], backend: backend)
        XCTAssertEqual(duplicate.syncState, .synced)
        XCTAssertEqual(store.placeWannaSaves.count, 1)
        XCTAssertEqual(repository.attempts.count, 2)
    }

    func testWannaSubmissionReturnsAfterLocalPersistenceWhileServerIsStillWaiting() async throws {
        var snapshot: WanderStoreSnapshot?
        var flushed = false
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 },
                                                 flush: { flushed = true })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                        note: "Visit", sourceType: .manual)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace)
        parent.serverID = "22222222-2222-4222-8222-222222222222"
        parent.syncStateRaw = SyncState.synced.rawValue
        let repository = RepeatWannaTestRepository()
        repository.shouldFail = false
        let backend = WanderBackend(userPlaceRepository: repository)
        let networkStarted = expectation(description: "Server request started")
        let formCompleted = expectation(description: "Form completed without waiting for server")
        var releaseResponse: CheckedContinuation<Void, Never>?
        repository.onSave = {
            await withCheckedContinuation { continuation in
                releaseResponse = continuation
                networkStarted.fulfill()
            }
        }
        let operationID = UUID()
        let context = MapPlaceSaveContext.addCandidate(candidate, sourceType: .manual,
                                                       defaultVisibility: .followers).freshWannaContext()
        let submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: .wannaGo,
            visibility: .followers, ratingScore: nil, note: "Queued Wanna", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            visitedAt: .now, plannedDate: nil, wannaOperationID: operationID)
        let saveTask = Task { @MainActor in
            let result = await persistNewPlaceSaveSubmission(submission, store: store, backend: backend)
            XCTAssertEqual(result?.syncState, .pendingCreate)
            formCompleted.fulfill()
        }
        await fulfillment(of: [networkStarted, formCompleted], timeout: 2)
        XCTAssertTrue(flushed, "The outbox must be flushed before closing the form")
        XCTAssertEqual(snapshot?.placeWannaSaves?.map(\.id), [operationID.uuidString.lowercased()])
        XCTAssertFalse(store.placeWannaSaves[0].isSynced)
        releaseResponse?.resume()
        await saveTask.value
        for _ in 0..<100 where !store.placeWannaSaves[0].isSynced { await Task.yield() }
        XCTAssertTrue(store.placeWannaSaves[0].isSynced)
        XCTAssertEqual(repository.attempts, [operationID.uuidString.lowercased()])
        XCTAssertEqual(repository.parentWriteCount, 0)
        XCTAssertEqual(parent.status, .been)
    }

    func testFirstWannaBackgroundDeliveryCreatesParentWithoutARepeatEvent() async throws {
        let store = WanderStore(fixtures: .seed())
        let repository = RepeatWannaTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let parentSaved = expectation(description: "First Wanna delivered")
        repository.onParentSave = { draft in
            XCTAssertEqual(draft.status, .wannaGo)
            XCTAssertEqual(draft.note, "First Wanna")
            parentSaved.fulfill()
            return SaveResult(userPlaceID: "22222222-2222-4222-8222-222222222222", syncState: .synced)
        }
        let context = MapPlaceSaveContext.addCandidate(candidate, sourceType: .manual,
                                                       defaultVisibility: .followers).freshWannaContext()
        let submission = MapPlaceSaveSubmission(context: context, candidate: candidate, status: .wannaGo,
            visibility: .followers, ratingScore: nil, note: "First Wanna", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            wannaOperationID: UUID())
        let saved = await persistNewPlaceSaveSubmission(submission, store: store, backend: backend)
        XCTAssertEqual(saved?.syncState, .pendingCreate)
        await fulfillment(of: [parentSaved], timeout: 2)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first {
            VisiblePlaceGrouping.matches($0, candidate: candidate)
        }?.userPlace)
        XCTAssertEqual(parent.syncState, .synced)
        XCTAssertEqual(parent.serverID, "22222222-2222-4222-8222-222222222222")
        XCTAssertTrue(store.placeWannaSaves.isEmpty)
        XCTAssertTrue(repository.attempts.isEmpty)
        XCTAssertEqual(repository.parentWriteCount, 1)
    }

    func testHistoryRefreshDoesNotEvictAWannaSyncedWhileTheReadWasInFlight() async throws {
        let store = WanderStore(fixtures: .seed())
        let result = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                          note: "Visit", sourceType: .manual)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace)
        parent.serverID = "22222222-2222-4222-8222-222222222222"
        let repository = RepeatWannaTestRepository()
        repository.shouldFail = false
        let backend = WanderBackend(userPlaceRepository: repository)
        repository.onRead = {
            _ = await store.saveNewWanna(self.candidate, visibility: .followers, note: "Concurrent Wanna",
                                         plannedDate: nil, attributes: [], backend: backend)
            return [] // The server read took its snapshot before the new write.
        }
        await store.refreshWannaSaves(userPlaceIDs: [parent.id], backend: backend)
        XCTAssertEqual(store.placeWannaSaves.count, 1)
        XCTAssertTrue(try XCTUnwrap(store.placeWannaSaves.first).isSynced)
        repository.onRead = nil
    }

    func testRepeatWannaAnalyticsContainOnlyCoarsePropertiesAndDoNotRepeatOnRetry() async {
        let analytics = RepeatWannaAnalyticsRecorder()
        let store = WanderStore(fixtures: .seed(), analytics: analytics)
        _ = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                  note: "Private visit", sourceType: .manual)
        analytics.events = []
        let id = UUID().uuidString.lowercased()
        for _ in 0..<2 {
            _ = await store.saveNewWanna(candidate, operationID: id, visibility: .selfOnly,
                                         note: "Private Wanna", plannedDate: nil, attributes: [], backend: nil)
        }
        let saves = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeSaved }
        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.properties, ["source_type": "manual", "status": "wanna_go", "visibility": "self"])
        XCTAssertEqual(analytics.events.filter { $0.name == "engagement_action_performed" }.count, 1)
        XCTAssertFalse(analytics.events.contains { event in
            event.properties.values.contains("Private Wanna") || event.properties.values.contains(id)
        })
    }

    func testRepeatWannaCelebratesEveryNewSubmissionButNotRetryOrEdit() async throws {
        let store = WanderStore(fixtures: .seed())
        _ = await store.saveNewWanna(candidate, visibility: .followers, note: "First", plannedDate: nil, attributes: [], backend: nil)
        if let first = store.saveStreakCelebration { store.dismissSaveStreakCelebration(id: first.id) }
        let id = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(candidate, operationID: id, visibility: .followers, note: "Repeat", plannedDate: nil, attributes: [], backend: nil)
        let celebration = try XCTUnwrap(store.saveStreakCelebration)
        XCTAssertEqual(celebration.kind, .sameDayConfetti)
        XCTAssertEqual(celebration.status, .wannaGo)
        store.dismissSaveStreakCelebration(id: celebration.id)
        _ = await store.saveNewWanna(candidate, operationID: id, visibility: .followers, note: "Repeat", plannedDate: nil, attributes: [], backend: nil)
        XCTAssertNil(store.saveStreakCelebration)
        let wanna = try XCTUnwrap(store.placeWannaSaves.first)
        _ = store.updateWanna(wanna, visibility: .followers, note: "Edited", plannedDate: nil, attributes: [])
        XCTAssertNil(store.saveStreakCelebration)
    }

    func testEditingOneWannaPreservesOthersAndCheckInAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers, note: "Visit", sourceType: .manual, ratingScore: 4)
        for note in ["First repeat", "Second repeat"] {
            _ = await store.saveNewWanna(candidate, visibility: .followers, note: note, plannedDate: nil, attributes: [], backend: nil)
        }
        let target = store.placeWannaSaves[0]
        let untouched = store.placeWannaSaves[1]
        let plannedDate = WannaGoDate.normalized(Date.now.addingTimeInterval(86400))
        XCTAssertNotNil(store.updateWanna(target, visibility: .selfOnly, note: "Edited only first",
            plannedDate: plannedDate, attributes: [PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", valueJSON: "[\"quiet\"]")]))
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let updated = try XCTUnwrap(restored.placeWannaSaves.first { $0.id == target.id })
        XCTAssertEqual(updated.note, "Edited only first")
        XCTAssertEqual(updated.visibility, .selfOnly)
        XCTAssertEqual(updated.plannedDate, plannedDate)
        XCTAssertEqual(updated.occurredAt, target.occurredAt)
        XCTAssertFalse(updated.isSynced)
        XCTAssertNotNil(updated.editedAt)
        XCTAssertEqual(restored.placeWannaSaves.first { $0.id == untouched.id }, untouched)
        let parent = try XCTUnwrap(restored.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        XCTAssertEqual(parent.userPlace.status, .been)
        XCTAssertEqual(parent.userPlace.note, "Visit")
        XCTAssertEqual(parent.userPlace.ratingScore, 4)
        let context = MapPlaceSaveContext.editWanna(updated, visiblePlace: parent)
        XCTAssertEqual(context.editedWanna?.id, target.id)
        XCTAssertEqual(context.initialNote, "Edited only first")
        XCTAssertEqual(context.initialPlannedDate, plannedDate)
        XCTAssertFalse(context.showsRemoveControl)
    }

    func testRefreshAndInFlightCreateCannotEraseNewerWannaEdit() async throws {
        let store = WanderStore(fixtures: .seed())
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers, note: "Visit", sourceType: .manual)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace)
        parent.serverID = "22222222-2222-4222-8222-222222222222"
        let repository = RepeatWannaTestRepository()
        repository.shouldFail = false
        let backend = WanderBackend(userPlaceRepository: repository)
        _ = await store.saveNewWanna(candidate, visibility: .followers, note: "Before edit", plannedDate: nil, attributes: [], backend: nil)
        let original = store.placeWannaSaves[0]
        repository.onSave = {
            repository.onSave = nil
            _ = store.updateWanna(original, visibility: .followers, note: "Edited during create", plannedDate: nil, attributes: [])
        }
        _ = await store.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(store.placeWannaSaves[0].note, "Edited during create")
        XCTAssertTrue(store.placeWannaSaves[0].isSynced)
        repository.onRead = {
            _ = store.updateWanna(store.placeWannaSaves[0], visibility: .selfOnly, note: "Pending newer edit", plannedDate: nil, attributes: [])
            var stale = original; stale.isSynced = true
            return [stale]
        }
        await store.refreshWannaSaves(userPlaceIDs: [parent.id], backend: backend)
        XCTAssertEqual(store.placeWannaSaves.count, 1)
        XCTAssertEqual(store.placeWannaSaves[0].note, "Pending newer edit")
        XCTAssertFalse(store.placeWannaSaves[0].isSynced)
    }

    func testEveryOwnedActivityKindHasEditButOtherPeoplesDoNot() throws {
        let store = WanderStore(fixtures: .seed())
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers, note: "Visit", sourceType: .manual)
        let visible = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        let summary = PlaceSaveSummary(visiblePlace: visible, attributes: [])
        for kind in [PlaceActivityEntryKind.visit, .currentWant, .historicalWant, .legacyBeenSummary] {
            let entry = PlaceActivityEntry(summary: summary, visit: nil, kind: kind, currentUserID: store.currentUser.id)
            XCTAssertTrue(entry.canEdit)
            let other = PlaceActivityEntry(summary: summary, visit: nil, kind: kind, currentUserID: "different-viewer")
            XCTAssertFalse(other.canEdit)
        }
    }

    func testEditedOriginalWannaSurvivesLastCheckInDeletionAndRemainsEditable() async throws {
        let store = WanderStore(fixtures: .seed())
        _ = await store.saveNewWanna(candidate, visibility: .followers, note: "Original",
                                     plannedDate: nil, attributes: [], backend: nil)
        let saved = store.saveCandidate(candidate, status: .been, visibility: .followers,
                                        note: "Visit", sourceType: .manual)
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace)
        let original = PlaceWannaSave(id: UUID().uuidString.lowercased(), ownerID: store.currentUser.id,
            userPlaceID: parent.id, occurredAt: try XCTUnwrap(parent.historicalWantedAt), note: "Original",
            visibility: .followers, plannedDate: nil, attributeAnswersJSON: "[]", isHistoricalOriginal: true)
        XCTAssertNotNil(store.updateWanna(original, visibility: .selfOnly, note: nil, plannedDate: nil, attributes: []))
        let visit = try XCTUnwrap(store.visits(for: parent.id).first)
        XCTAssertTrue(store.deleteVisit(visitID: visit.id))
        XCTAssertEqual(parent.status, .wannaGo)
        XCTAssertNil(parent.note, "Clearing the original note must not resurrect its old text")
        XCTAssertEqual(parent.visibility, .selfOnly)
        XCTAssertNotNil(store.updateWanna(store.placeWannaSaves[0], visibility: .selfOnly,
                                          note: "Edited after deletion", plannedDate: nil, attributes: []))
        XCTAssertEqual(parent.note, "Edited after deletion")
        XCTAssertEqual(store.placeWannaSaves.count, 1)
    }

    func testRightActionIsFreshWannaForEveryEditablePlaceState() throws {
        for state in [PlaceProfileSaveActionState.unsaved, .wanna, .checkInHistory] {
            let actions = PlaceProfileSaveActionPolicy.resolve(state: state).actions
            XCTAssertEqual(actions[0].kind, .checkIn)
            XCTAssertEqual(actions[0].title, "Check in")
            XCTAssertEqual(actions[1].kind, .wanna)
            XCTAssertEqual(actions[1].title, "Wanna")
            XCTAssertFalse(actions[1].isSelected)
            let base = MapPlaceSaveContext.addCandidate(candidate, sourceType: .manual, defaultVisibility: .followers)
            let context = try XCTUnwrap(PlaceProfileSaveActionPolicy.attachedSaveContext(
                route: .floatingActions, state: state, action: actions[1], baseContext: base))
            XCTAssertFalse(context.isEditing)
            XCTAssertEqual(context.initialStatus, .wannaGo)
            XCTAssertTrue(context.initialNote.isEmpty)
            XCTAssertTrue(context.initialAnswers.isEmpty)
            XCTAssertNil(context.initialPlannedDate)
            XCTAssertNil(context.initialRatingScore)
            XCTAssertFalse(context.showsRemoveControl)
        }
    }
}

@MainActor
private final class RepeatWannaTestRepository: UserPlaceRepository, WannaSaveRepository {
    var shouldFail = true
    var attempts: [String] = []
    var parentWriteCount = 0
    var onRead: (() async -> [PlaceWannaSave])?
    var onSave: (() async -> Void)?
    var onParentSave: ((UserPlaceDraft) async throws -> SaveResult)?
    func saveWanna(_ wanna: PlaceWannaSave) async throws {
        attempts.append(wanna.id)
        await onSave?()
        if shouldFail { throw WanderRemoteError.invalidResponse("test failure") }
    }
    func updateWanna(_ wanna: PlaceWannaSave) async throws -> PlaceWannaSave {
        if shouldFail { throw WanderRemoteError.invalidResponse("test failure") }
        return wanna
    }
    func wannaSaves(userPlaceIDs: [String]) async throws -> [PlaceWannaSave] {
        await onRead?() ?? []
    }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { [] }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        parentWriteCount += 1
        if let onParentSave { return try await onParentSave(draft) }
        throw WanderRemoteError.invalidResponse("Parent must stay unchanged")
    }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

private final class RepeatWannaAnalyticsRecorder: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
