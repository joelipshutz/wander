import XCTest
@testable import Wander

@MainActor
final class MapPlaceWannaRemovalDependencyTests: XCTestCase {
    func testDuplicateParentsWaitForCapturedReplacementAcrossRestartAndOwnershipChanges() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let first = try wanna("first", store: store)
        let duplicate = try wanna("duplicate", store: store)
        duplicate.place.canonicalName = first.place.canonicalName
        duplicate.place.latitude = first.place.latitude
        duplicate.place.longitude = first.place.longitude
        let item = PlaceSheetPlace(visiblePlace: first).saveCandidate
        XCTAssertEqual(LivePlaceSaveContinuation.matchingOwnPlaces(candidate: item, store: store).count, 2)
        let submitted = submission(first, store: store).capturingPriorWannas(in: store)
        XCTAssertEqual(submitted.priorWannaRemovalTargets?.count, 2)
        let saved = await persistAddPlaceSaveSubmission(submitted, store: store, backend: nil)
        XCTAssertNotNil(saved)
        let replacement = try XCTUnwrap(store.visits(for: first.userPlace.id).first)
        let targets = store.placeWannaSaves.filter { $0.replacementVisitID == replacement.localID }
        XCTAssertEqual(targets.count, 2)
        store.flushPersistence()

        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let visit = try XCTUnwrap(restored.placeVisits.first { $0.localID == replacement.localID })
        let source = try XCTUnwrap(restored.userPlaces.first { $0.localID == first.userPlace.localID })
        for parent in restored.userPlaces where [first.userPlace.localID, duplicate.userPlace.localID].contains(parent.localID) {
            parent.serverID = UUID().uuidString.lowercased()
        }
        let repository = WannaRemovalTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        visit.syncStateRaw = SyncState.failed.rawValue
        _ = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        visit.syncStateRaw = SyncState.synced.rawValue
        visit.deletedAt = .now
        _ = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        visit.deletedAt = nil
        let owner = source.userID
        source.userID = "another-account"
        _ = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        source.userID = owner
        let count = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(Set(repository.deletedIDs), Set(targets.map(\.id)))
    }

    func testNeverUploadedDuplicateRemovalCompletesLocallyAfterReplacementSyncAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let source = try wanna("source-local-duplicate", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let duplicate = try wanna("never-uploaded-duplicate", store: store)
        duplicate.place.canonicalName = source.place.canonicalName
        let duplicateRepeatID = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(PlaceSheetPlace(visiblePlace: duplicate).saveCandidate,
            operationID: duplicateRepeatID, visibility: .selfOnly, note: "Prior local repeat",
            plannedDate: nil, attributes: [], backend: nil)
        let submitted = submission(source, store: store).capturingPriorWannas(in: store)
        XCTAssertEqual(submitted.priorWannaRemovalTargets?.count, 3)
        let saved = await persistAddPlaceSaveSubmission(submitted, store: store, backend: nil)
        XCTAssertNotNil(saved)
        let replacement = try XCTUnwrap(store.visits(for: source.userPlace.id).first)
        XCTAssertNil(duplicate.userPlace.serverID)
        XCTAssertEqual(duplicate.userPlace.syncState, .tombstoned)
        XCTAssertNotNil(duplicate.userPlace.deletedAt)
        store.flushPersistence()

        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let tombstoneID = try XCTUnwrap(restored.placeWannaSaves.first {
            $0.userPlaceID == duplicate.userPlace.localID && $0.deletedAt != nil
        }?.id)
        let localTombstones = restored.placeWannaSaves.filter {
            $0.userPlaceID == duplicate.userPlace.localID && $0.deletedAt != nil
        }
        XCTAssertEqual(localTombstones.count, 2)
        XCTAssertTrue(localTombstones.allSatisfy { $0.parentWasNeverUploaded == true })
        XCTAssertTrue(localTombstones.contains { $0.id == duplicateRepeatID })
        let repository = WannaRemovalTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        _ = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertFalse(restored.placeWannaSaves.first { $0.id == tombstoneID }?.isSynced == true)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
        let visit = try XCTUnwrap(restored.placeVisits.first { $0.localID == replacement.localID })
        visit.syncStateRaw = SyncState.synced.rawValue
        let completed = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(completed, 3)
        XCTAssertTrue(restored.placeWannaSaves.filter { $0.userPlaceID == duplicate.userPlace.localID }.allSatisfy(\.isSynced))
        XCTAssertFalse(repository.deletedIDs.contains(tombstoneID), "A never-uploaded duplicate needs no remote deletion")
        XCTAssertEqual(repository.deletedIDs.count, 1)
        XCTAssertNil(restored.userPlaces.first { $0.localID == duplicate.userPlace.localID }?.serverID)

        let futureID = UUID().uuidString.lowercased()
        _ = await restored.saveNewWanna(PlaceSheetPlace(visiblePlace: source).saveCandidate,
            operationID: futureID, visibility: .selfOnly, note: "Future Wanna", plannedDate: nil,
            attributes: [], backend: backend)
        _ = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertNotNil(restored.placeWannaSaves.first { $0.id == futureID && $0.deletedAt == nil })
        XCTAssertFalse(repository.deletedIDs.contains(futureID))
    }

    func testInFlightParentCreateCannotAcknowledgeWannaRemovalLocally() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("replacement-source", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let replacement = try XCTUnwrap(store.createVisit(userPlaceID: source.userPlace.id,
            note: "Replacement", visibility: .selfOnly))
        replacement.syncStateRaw = SyncState.synced.rawValue
        let repository = WannaRemovalTestRepository()
        repository.suspendsSave = true
        let backend = WanderBackend(userPlaceRepository: repository)
        let candidate = PlaceCandidate(id: "in-flight-duplicate", name: "In-flight Duplicate", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "manual", sourceProviderPlaceID: "in-flight-duplicate", confidence: 1)
        let pendingSave = Task { await store.saveCandidate(candidate, status: .wannaGo, visibility: .selfOnly,
            note: "Original", sourceType: .manual, backend: backend) }
        await repository.waitUntilSaveStarts()
        let duplicate = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.place.sourceProviderPlaceID == candidate.id })
        XCTAssertEqual(duplicate.userPlace.syncState, .pendingUpdate)
        // A newer local edit must not erase the in-flight request evidence.
        duplicate.userPlace.syncStateRaw = SyncState.pendingCreate.rawValue
        XCTAssertTrue(store.removeImportedWanna(userPlaceID: duplicate.userPlace.id, wannaID: nil,
            isOriginal: true, replacementVisitID: replacement.localID))
        let tombstone = try XCTUnwrap(store.placeWannaSaves.first { $0.userPlaceID == duplicate.userPlace.id && $0.deletedAt != nil })
        XCTAssertFalse(tombstone.parentWasNeverUploaded == true)
        _ = await store.syncPendingWannaSaves(backend: backend)
        XCTAssertFalse(store.placeWannaSaves.first { $0.id == tombstone.id }?.isSynced == true)
        XCTAssertTrue(repository.deletedIDs.isEmpty)

        let remoteID = UUID().uuidString.lowercased()
        repository.finishSave(.success(SaveResult(userPlaceID: remoteID, syncState: .synced)))
        _ = await pendingSave.value
        _ = await store.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(repository.deletedIDs, [tombstone.id])
    }

    func testUncertainParentCreateDoesNotBecomeLocalOnlyAfterRemoval() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("uncertain-source", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let replacement = try XCTUnwrap(store.createVisit(userPlaceID: source.userPlace.id,
            note: "Replacement", visibility: .selfOnly))
        replacement.syncStateRaw = SyncState.synced.rawValue
        let duplicate = try wanna("uncertain-duplicate", store: store)
        duplicate.userPlace.syncStateRaw = SyncState.failed.rawValue
        duplicate.userPlace.lastSyncError = "The create response was lost"
        XCTAssertTrue(store.removeImportedWanna(userPlaceID: duplicate.userPlace.id, wannaID: nil,
            isOriginal: true, replacementVisitID: replacement.localID))
        let tombstone = try XCTUnwrap(store.placeWannaSaves.first { $0.userPlaceID == duplicate.userPlace.id && $0.deletedAt != nil })
        let repository = WannaRemovalTestRepository()
        _ = await store.syncPendingWannaSaves(backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertFalse(tombstone.parentWasNeverUploaded == true)
        XCTAssertFalse(store.placeWannaSaves.first { $0.id == tombstone.id }?.isSynced == true)
        XCTAssertTrue(repository.deletedIDs.isEmpty)
    }

    func testAuthoritativePreparationCapturesUnloadedRemoteRepeatsAndDuplicateParent() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("history-source", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let remotePlace = LocalPlace(localID: "remote-duplicate-place", serverID: UUID().uuidString.lowercased(),
            canonicalName: source.place.canonicalName, category: "coffee", latitude: 34, longitude: -118,
            sourceProvider: "manual", sourceProviderPlaceID: "remote-duplicate-provider")
        let remoteParent = LocalUserPlace(localID: "remote-duplicate-parent", serverID: UUID().uuidString.lowercased(),
            userID: store.currentUser.id, placeID: remotePlace.id, status: .wannaGo, visibility: .selfOnly,
            sourceType: "manual", syncState: .synced)
        let remoteAnswer = PlaceAttributeDraft(questionKey: "personal_labels", valueType: "multi_choice", valueJSON: "[\"Saved answer\"]")
        let duplicate = VisiblePlace(id: remoteParent.id, place: remotePlace, userPlace: remoteParent, owner: store.currentUser,
            attributes: [LocalPlaceAttribute(localID: "remote-wanna-answer", userPlaceID: remoteParent.id,
                questionKey: remoteAnswer.questionKey, valueType: remoteAnswer.valueType, valueJSON: remoteAnswer.valueJSON)])
        let repository = WannaRemovalTestRepository()
        repository.parents = [source, duplicate]
        let remoteIDs = [UUID().uuidString.lowercased(), UUID().uuidString.lowercased()]
        repository.rows = zip(remoteIDs, [source.userPlace.id, remoteParent.id]).map { id, parentID in
            PlaceWannaSave(id: id, ownerID: store.currentUser.id, userPlaceID: parentID,
                occurredAt: .now, note: "Remote prior Wanna", visibility: .selfOnly,
                attributeAnswersJSON: "[]", isSynced: true)
        }
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.userPlace.id == remoteParent.id })
        XCTAssertFalse(store.placeWannaSaves.contains { remoteIDs.contains($0.id) })
        let prepared = try await submission(source, store: store).preparingPriorWannaRemoval(
            in: store, backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertTrue(Set(prepared.priorWannaRemovalTargets?.compactMap(\.wannaID) ?? []).isSuperset(of: remoteIDs))
        XCTAssertTrue(prepared.priorWannaRemovalTargets?.contains { $0.userPlaceID == remoteParent.id } == true)
        let stagedOriginal = try XCTUnwrap(store.wannaSaves(for: remoteParent).first { $0.isHistoricalOriginal == true })
        XCTAssertEqual(VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: stagedOriginal.attributeAnswersJSON), [remoteAnswer],
            "A successful preflight must preserve Wanna answers even if the check-in never saves")
        let futureID = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(PlaceSheetPlace(visiblePlace: source).saveCandidate,
            operationID: futureID, visibility: .selfOnly, note: "After preparation", plannedDate: nil,
            attributes: [], backend: nil)
        let saved = await persistAddPlaceSaveSubmission(prepared, store: store, backend: nil)
        XCTAssertNotNil(saved)
        XCTAssertTrue(remoteIDs.allSatisfy { id in store.placeWannaSaves.contains { $0.id == id && $0.deletedAt != nil } })
        XCTAssertTrue(store.placeWannaSaves.contains { $0.id == futureID && $0.deletedAt == nil })
    }

    func testAuthoritativeOriginalSurvivesStaleSyncedLocalBeenProjection() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("stale-original", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let originalDate = source.userPlace.savedAt
        let priorVisit = try XCTUnwrap(store.createVisit(userPlaceID: source.userPlace.id,
            note: "Keep this visit", visibility: .selfOnly))
        priorVisit.syncStateRaw = SyncState.synced.rawValue
        source.userPlace.historicalWantedAt = nil
        source.userPlace.historicalWantNote = nil
        source.userPlace.syncStateRaw = SyncState.synced.rawValue
        let remoteParent = LocalUserPlace(localID: "remote-stale-original", serverID: source.userPlace.serverID,
            userID: store.currentUser.id, placeID: source.place.id, status: .been, visibility: .selfOnly,
            sourceType: "manual", historicalWantNote: "Authoritative original", historicalWantedAt: originalDate,
            syncState: .synced)
        let repository = WannaRemovalTestRepository()
        repository.parents = [VisiblePlace(id: remoteParent.id, place: source.place,
            userPlace: remoteParent, owner: store.currentUser)]
        let backend = WanderBackend(userPlaceRepository: repository)
        XCTAssertTrue(store.wannaSaves(for: source.userPlace).isEmpty)
        let prepared = try await submission(source, store: store).preparingPriorWannaRemoval(in: store, backend: backend)
        let target = try XCTUnwrap(prepared.priorWannaRemovalTargets?.first)
        XCTAssertEqual(prepared.priorWannaRemovalTargets?.count, 1)
        XCTAssertTrue(target.isOriginal)
        XCTAssertEqual(target.occurredAt, originalDate)
        let originalID = try XCTUnwrap(target.wannaID)
        XCTAssertEqual(store.placeWannaSaves.first { $0.id == originalID }?.note, "Authoritative original")
        XCTAssertNil(source.userPlace.historicalWantedAt, "Refreshing history must not overwrite local parent fields")
        try await store.refreshOwnWannaRemovalHistory(candidate: prepared.candidate, backend: backend)
        XCTAssertEqual(store.wannaSaves(for: source.userPlace).first?.id, originalID,
            "A repeated read must retain the captured original identity")
        let saved = await persistAddPlaceSaveSubmission(prepared, store: store, backend: nil)
        XCTAssertNotNil(saved)
        XCTAssertNil(saved?.localDetailsWarning)
        XCTAssertNotNil(store.placeWannaSaves.first { $0.id == originalID }?.deletedAt)
        XCTAssertTrue(store.visits(for: source.userPlace.id).contains { $0.id == priorVisit.id })
    }

    func testAuthoritativeOriginalPreservesPendingRevisedAndDeletedLocalAliases() async throws {
        for disposition in ["pending", "revised", "deleted"] {
            let seed = WanderStore(fixtures: .seed())
            let seededSource = try wanna("protected-original-\(disposition)", store: seed)
            seededSource.userPlace.serverID = UUID().uuidString.lowercased()
            let originalDate = seededSource.userPlace.savedAt
            seededSource.userPlace.historicalWantNote = "Local parent details"
            let originalID = UUID().uuidString.lowercased()
            let original = PlaceWannaSave(id: originalID, ownerID: seed.currentUser.id,
                userPlaceID: seededSource.userPlace.localID, occurredAt: originalDate, note: "Local original",
                visibility: .selfOnly, attributeAnswersJSON: "[]", isSynced: disposition != "pending",
                isHistoricalOriginal: true, deletedAt: disposition == "deleted" ? .now : nil)
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WanderStoreSnapshot(store: seed))) as? [String: Any])
            json["placeWannaSaves"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([original]))
            let snapshot = try JSONDecoder().decode(WanderStoreSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
            let store = WanderStore(fixtures: .seed(), persistence: WanderStorePersistence(load: { snapshot }, save: { _ in }))
            let source = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.localID == seededSource.userPlace.localID })
            let remoteParent = LocalUserPlace(localID: "remote-protected-original", serverID: source.userPlace.serverID,
                userID: store.currentUser.id, placeID: source.place.id, status: .been, visibility: .selfOnly,
                sourceType: "manual", historicalWantNote: "Stale remote original", historicalWantedAt: originalDate,
                syncState: .synced)
            let repository = WannaRemovalTestRepository()
            repository.parents = [VisiblePlace(id: remoteParent.id, place: source.place,
                userPlace: remoteParent, owner: store.currentUser)]
            if disposition == "revised" {
                repository.onHistoryRead = {
                    XCTAssertNotNil(store.updateWanna(original, visibility: .selfOnly,
                        note: "Revised during read", plannedDate: nil, attributes: []))
                }
            }
            let prepared = try await submission(source, store: store).preparingPriorWannaRemoval(
                in: store, backend: WanderBackend(userPlaceRepository: repository))
            let originals = store.placeWannaSaves.filter { $0.isHistoricalOriginal == true }
            XCTAssertEqual(originals.count, 1, disposition)
            XCTAssertEqual(originals.first?.id, originalID, disposition)
            XCTAssertEqual(originals.first?.userPlaceID, source.userPlace.localID, disposition)
            XCTAssertEqual(originals.first?.note, disposition == "revised" ? "Revised during read" : "Local original", disposition)
            XCTAssertEqual(source.userPlace.historicalWantNote, "Local parent details", disposition)
            XCTAssertEqual(prepared.priorWannaRemovalTargets?.count, disposition == "deleted" ? 0 : 1, disposition)
        }
    }

    func testAuthoritativeHistoryFailurePreventsCheckInAndRemoval() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("history-failure", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let repository = WannaRemovalTestRepository()
        repository.parents = [source]
        repository.failsHistory = true
        let backend = WanderBackend(userPlaceRepository: repository)
        let visitIDs = store.placeVisits.map(\.id)
        let wannaIDs = store.placeWannaSaves.map(\.id)
        let saved = await persistAddPlaceSaveSubmission(submission(source, store: store), store: store, backend: backend)
        XCTAssertNil(saved)
        XCTAssertEqual(store.placeVisits.map(\.id), visitIDs)
        XCTAssertEqual(store.placeWannaSaves.map(\.id), wannaIDs)
        XCTAssertNil(source.userPlace.deletedAt)
        XCTAssertEqual(source.userPlace.status, .wannaGo)
        XCTAssertTrue(MapPlaceWannaHistoryError.unavailable.localizedDescription.contains("Turn Off Remove From Wanna"))
    }

    func testHistoryPreparationRejectsSameAccountReloginAndStalePreparedMarker() async throws {
        let store = WanderStore(fixtures: .seed())
        let session = AuthSession(userID: store.currentUser.id, displayName: store.currentUser.displayName, handle: store.currentUser.handle)
        let source = try wanna("history-account", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let repository = WannaRemovalTestRepository()
        repository.parents = [source]
        let backend = WanderBackend(userPlaceRepository: repository)
        let prepared = try await submission(source, store: store).preparingPriorWannaRemoval(in: store, backend: backend)
        let previousGeneration = store.wannaRemovalAccountGeneration
        store.apply(authState: .signedOut)
        store.apply(authState: .signedIn(session))
        XCTAssertNotEqual(store.wannaRemovalAccountGeneration, previousGeneration)
        repository.failsHistory = true
        do {
            _ = try await prepared.preparingPriorWannaRemoval(in: store, backend: backend)
            XCTFail("A prior login's prepared marker must not bypass authoritative reads")
        } catch {}
        repository.failsHistory = false
        repository.onHistoryRead = {
            store.apply(authState: .signedOut)
            store.apply(authState: .signedIn(session))
        }
        let visitIDs = store.placeVisits.map(\.id)
        let saved = await persistAddPlaceSaveSubmission(submission(source, store: store), store: store, backend: backend)
        XCTAssertNil(saved)
        XCTAssertEqual(store.placeVisits.map(\.id), visitIDs)
        XCTAssertFalse(store.placeWannaSaves.contains { $0.deletedAt != nil })
    }

    func testPotentiallyCappedWannaHistoryFailsClosed() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try wanna("history-cap", store: store)
        source.userPlace.serverID = UUID().uuidString.lowercased()
        let repository = WannaRemovalTestRepository()
        repository.parents = [source]
        repository.rows = (0..<1_000).map { _ in
            PlaceWannaSave(id: UUID().uuidString.lowercased(), ownerID: store.currentUser.id,
                userPlaceID: source.userPlace.id, occurredAt: .now, visibility: .selfOnly,
                attributeAnswersJSON: "[]", isSynced: true)
        }
        let saved = await persistAddPlaceSaveSubmission(submission(source, store: store), store: store,
            backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertNil(saved)
        XCTAssertTrue(store.visits(for: source.userPlace.id).isEmpty)
        XCTAssertFalse(store.placeWannaSaves.contains { $0.userPlaceID == source.userPlace.id })
    }

    func testRemoteRemovalFailureIsVisibleDurableAndRejectsStaleOriginal() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let first = try wanna("pending", store: store)
        first.userPlace.serverID = UUID().uuidString.lowercased()
        let submitted = submission(first, store: store).capturingPriorWannas(in: store)
        let visit = try XCTUnwrap(createExplicitVisitIfNeeded(for: submitted, store: store))
        visit.syncStateRaw = SyncState.synced.rawValue
        let repository = WannaRemovalTestRepository()
        repository.shouldFail = true
        let backend = WanderBackend(userPlaceRepository: repository)
        let completed = await completeSourceWannaRemovalAfterCheckIn(
            SaveResult(userPlaceID: first.userPlace.id, syncState: .synced), visit: visit,
            submission: submitted, store: store, backend: backend)
        XCTAssertTrue(completed.localDetailsWarning?.contains("Pending") == true)
        store.flushPersistence()
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let tombstone = try XCTUnwrap(restored.placeWannaSaves.first { $0.replacementVisitID == visit.localID })
        XCTAssertNotNil(tombstone.deletedAt)
        XCTAssertFalse(tombstone.isSynced)
        repository.rows = [PlaceWannaSave(id: UUID().uuidString.lowercased(), ownerID: tombstone.ownerID,
            userPlaceID: first.userPlace.id, occurredAt: tombstone.occurredAt,
            visibility: .selfOnly, attributeAnswersJSON: "[]", isSynced: true, isHistoricalOriginal: true)]
        await restored.refreshWannaSaves(userPlaceIDs: [first.userPlace.id], backend: backend)
        XCTAssertFalse(restored.placeWannaSaves.contains { $0.isHistoricalOriginal == true && $0.deletedAt == nil })
        repository.shouldFail = false
        let delivered = await restored.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(delivered, 1)
        XCTAssertEqual(repository.deletedIDs, [tombstone.id])
    }

    func testPartialRemoteRemovalReportsPendingAndRetriesOnlyUnfinishedTargets() async throws {
        let store = WanderStore(fixtures: .seed())
        let first = try wanna("partial", store: store)
        first.userPlace.serverID = UUID().uuidString.lowercased()
        let repository = WannaRemovalTestRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let repeatID = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(PlaceSheetPlace(visiblePlace: first).saveCandidate,
            operationID: repeatID, visibility: .selfOnly, note: "Prior repeat", plannedDate: nil,
            attributes: [], backend: backend)
        let submitted = submission(first, store: store).capturingPriorWannas(in: store)
        XCTAssertEqual(submitted.priorWannaRemovalTargets?.count, 2)
        let visit = try XCTUnwrap(createExplicitVisitIfNeeded(for: submitted, store: store))
        visit.syncStateRaw = SyncState.synced.rawValue
        repository.failedIDs = [repeatID]
        let result = await completeSourceWannaRemovalAfterCheckIn(
            SaveResult(userPlaceID: first.userPlace.id, syncState: .synced), visit: visit,
            submission: submitted, store: store, backend: backend)
        XCTAssertTrue(result.localDetailsWarning?.contains("Pending") == true)
        XCTAssertEqual(repository.deletedIDs.count, 1)
        XCTAssertNotEqual(repository.deletedIDs.first, repeatID)
        repository.failedIDs = []
        let completed = await store.syncPendingWannaSaves(backend: backend)
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(repository.deletedIDs.count, 2)
        XCTAssertEqual(repository.deletedIDs.last, repeatID)
    }

    func testDeletedReplacementCannotRemovePriorWanna() async throws {
        let store = WanderStore(fixtures: .seed())
        let first = try wanna("deleted", store: store)
        let submitted = submission(first, store: store).capturingPriorWannas(in: store)
        let visit = try XCTUnwrap(createExplicitVisitIfNeeded(for: submitted, store: store))
        visit.deletedAt = .now
        let completed = await completeSourceWannaRemovalAfterCheckIn(
            SaveResult(userPlaceID: first.userPlace.id, syncState: .pendingCreate), visit: visit,
            submission: submitted, store: store, backend: nil)
        XCTAssertNotNil(completed.localDetailsWarning)
        XCTAssertFalse(store.placeWannaSaves.contains { $0.deletedAt != nil })
    }

    func testOlderWannaPayloadDecodesWithoutReplacementDependency() throws {
        let wanna = PlaceWannaSave(id: "old", ownerID: "owner", userPlaceID: "place",
            occurredAt: .now, visibility: .selfOnly, attributeAnswersJSON: "[]")
        let encoded = try JSONEncoder().encode(wanna)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["replacementVisitID"])
        XCTAssertNil(object["parentWasNeverUploaded"])
        let decoded = try JSONDecoder().decode(PlaceWannaSave.self, from: encoded)
        XCTAssertNil(decoded.replacementVisitID)
        XCTAssertNil(decoded.parentWasNeverUploaded)
    }

    private func wanna(_ id: String, store: WanderStore) throws -> VisiblePlace {
        let item = PlaceCandidate(id: id, name: "Wanna \(id)", category: "coffee",
            latitude: 34, longitude: -118, sourceProvider: "manual", sourceProviderPlaceID: id, confidence: 1)
        let saved = store.saveCandidate(item, status: .wannaGo, visibility: .selfOnly,
            note: "Keep until check-in", sourceType: .manual)
        return try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
    }

    private func submission(_ place: VisiblePlace, store: WanderStore) -> MapPlaceSaveSubmission {
        let context = MapPlaceSaveContext.addFromExistingWanna(place,
            attributes: store.attributes(for: place.userPlace.id), latestVisit: nil).preselectingStatus(.been)
        return MapPlaceSaveSubmission(context: context, candidate: context.candidate,
            status: .been, visibility: .selfOnly, ratingScore: 4, note: "Replacement check-in",
            attributes: [], photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id, removesSourceWannaAfterCheckIn: true)
    }
}

@MainActor
private final class WannaRemovalTestRepository: UserPlaceRepository, WannaSaveRepository {
    var shouldFail = false
    var deletedIDs: [String] = []
    var failedIDs = Set<String>()
    var rows: [PlaceWannaSave] = []
    var parents: [VisiblePlace] = []
    var failsHistory = false
    var onHistoryRead: (() -> Void)?
    var suspendsSave = false
    private var suspendedSave: CheckedContinuation<SaveResult, any Error>?
    private var saveStarted: CheckedContinuation<Void, Never>?
    func waitUntilSaveStarts() async {
        if suspendedSave != nil { return }
        await withCheckedContinuation { saveStarted = $0 }
    }
    func finishSave(_ result: Result<SaveResult, any Error>) {
        suspendedSave?.resume(with: result)
        suspendedSave = nil
    }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { parents }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        guard suspendsSave else { throw WanderRemoteError.invalidResponse("Unexpected parent write") }
        return try await withCheckedThrowingContinuation { continuation in
            suspendedSave = continuation
            saveStarted?.resume()
            saveStarted = nil
        }
    }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws { XCTFail("Wanna removal must not use broad place deletion") }
    func saveWanna(_ wanna: PlaceWannaSave) async throws {}
    func updateWanna(_ wanna: PlaceWannaSave) async throws -> PlaceWannaSave { wanna }
    func deleteWanna(_ wanna: PlaceWannaSave) async throws {
        if shouldFail || failedIDs.contains(wanna.id) { throw WanderRemoteError.invalidResponse("Simulated deletion failure") }
        deletedIDs.append(wanna.id)
    }
    func wannaSaves(userPlaceIDs: [String]) async throws -> [PlaceWannaSave] {
        if failsHistory { throw URLError(.notConnectedToInternet) }
        onHistoryRead?()
        return rows.filter { userPlaceIDs.contains($0.userPlaceID) }
    }
}
