import XCTest
@testable import Wander

@MainActor
final class MapPlaceWannaContinuationTests: XCTestCase {
    private let candidate = PlaceCandidate(id: "wanna-continuation", name: "Wanna Continuation Cafe", category: "coffee",
        latitude: 34.1, longitude: -118.3, sourceProvider: "manual", sourceProviderPlaceID: "wanna-continuation", confidence: 1)

    func testFullEditorStartsWithOwnWannaDetailsAndKeepsBothStatuses() throws {
        let store = WanderStore(fixtures: .seed())
        let source = try makeWanna(in: store)
        let context = MapPlaceSaveContext.addFromExistingWanna(source,
            attributes: store.attributes(for: source.userPlace.id), latestVisit: nil)
        XCTAssertTrue(context.requiresStatusConfirmation)
        XCTAssertTrue(context.preselectsInitialStatus)
        XCTAssertTrue(context.startsOnDetails)
        XCTAssertTrue(context.allowsWannaGoSelection)
        XCTAssertEqual(context.initialStatus, .wannaGo)
        XCTAssertEqual(context.initialNote, "Original Wanna note")
        XCTAssertEqual(context.initialPersonalLabels, ["My tag"])
        let wanna = context.resolvingInitialEditorContext(startsOnDetails: true, selection: .wannaGo)
        guard case .editWant = wanna.mode else { return XCTFail("Wanna must edit the existing memory") }
        let visit = context.preselectingStatus(.been)
        guard case .addVisit = visit.mode else { return XCTFail("Check-in must append a distinct visit") }
        XCTAssertEqual(visit.initialNote, "Original Wanna note")
        XCTAssertEqual(visit.initialPersonalLabels, ["My tag"])
        XCTAssertEqual(visit.wannaRemovalTarget?.ownerID, store.currentUser.id)
        XCTAssertEqual(context.preselectingStatus(.wannaGo).initialNote, "Original Wanna note")
    }

    func testDefaultCheckInKeepsOriginalWannaAndSeparateCheckInAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let source = try makeWanna(in: store)
        let submission = submission(for: source, in: store)
        XCTAssertFalse(submission.removesSourceWannaAfterCheckIn)
        let saved = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
        let result = try XCTUnwrap(saved)
        store.flushPersistence()
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let parent = try XCTUnwrap(restored.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace)
        XCTAssertEqual(parent.historicalWantNote, "Original Wanna note")
        XCTAssertEqual(restored.visits(for: parent.id).map(\.note), ["New check-in note"])
        XCTAssertFalse(restored.placeWannaSaves.contains { $0.userPlaceID == parent.id && $0.deletedAt != nil })
    }

    func testExplicitRemovalRemovesAllPriorWannasAndKeepsNewWannaVisitsAndListsAcrossRestart() async throws {
        var snapshot: WanderStoreSnapshot?
        let persistence = WanderStorePersistence(load: { snapshot }, save: { snapshot = $0 })
        let store = WanderStore(fixtures: .seed(), persistence: persistence)
        let source = try makeWanna(in: store)
        let priorID = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(candidate, operationID: priorID, visibility: .selfOnly,
            note: "Prior Wanna with a future plan", plannedDate: .now.addingTimeInterval(86_400), attributes: [], backend: nil)
        let priorVisit = try XCTUnwrap(store.createVisit(userPlaceID: source.userPlace.id,
            note: "Existing check-in", visibility: .selfOnly))
        let list = try XCTUnwrap(store.createPlaceList(name: "Keep this list", description: "", visibility: .stealth))
        _ = await store.addSavedPlaceToLists(userPlaceID: source.userPlace.id, listIDs: [list.id],
            ownerUserID: store.currentUser.id, backend: nil, analyticsSurface: "check_in")
        let listItemIDs = store.placeListItems.map(\.id)
        var submission = submission(for: source, in: store)
        submission.removesSourceWannaAfterCheckIn = true
        submission = submission.capturingPriorWannas(in: store)
        let otherID = UUID().uuidString.lowercased()
        _ = await store.saveNewWanna(candidate, operationID: otherID, visibility: .selfOnly,
            note: "New Wanna after submission", plannedDate: nil, attributes: [], backend: nil)
        let saved = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
        let result = try XCTUnwrap(saved)
        store.flushPersistence()
        let restored = WanderStore(fixtures: .seed(), persistence: persistence)
        let parent = try XCTUnwrap(restored.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace)
        XCTAssertNil(parent.deletedAt)
        XCTAssertNil(parent.historicalWantedAt)
        XCTAssertEqual(Set(restored.visits(for: parent.id).compactMap(\.note)), ["New check-in note", "Existing check-in"])
        XCTAssertTrue(restored.visits(for: parent.id).contains { $0.localID == priorVisit.localID })
        XCTAssertEqual(restored.placeListItems.map(\.id), listItemIDs)
        XCTAssertEqual(restored.wannaSaves(for: parent).map(\.id), [otherID])
        XCTAssertNotNil(restored.placeWannaSaves.first { $0.id == priorID }?.deletedAt)
        XCTAssertTrue(restored.placeWannaSaves.contains { $0.isHistoricalOriginal == true && $0.deletedAt != nil })
    }

    func testFailedCheckInAndWrongAccountCannotRemoveSourceWanna() async throws {
        let store = WanderStore(fixtures: .seed())
        let source = try makeWanna(in: store)
        var submission = submission(for: source, in: store)
        submission.removesSourceWannaAfterCheckIn = true
        submission = submission.capturingPriorWannas(in: store)
        let visit = try XCTUnwrap(createExplicitVisitIfNeeded(for: submission, store: store))
        visit.syncStateRaw = SyncState.failed.rawValue
        let failed = await completeSourceWannaRemovalAfterCheckIn(
            SaveResult(userPlaceID: source.userPlace.id, syncState: .failed), visit: visit,
            submission: submission, store: store, backend: nil)
        XCTAssertNotNil(failed.localDetailsWarning)
        XCTAssertEqual(source.userPlace.historicalWantNote, "Original Wanna note")
        visit.syncStateRaw = SyncState.pendingCreate.rawValue
        submission.ownerUserID = "different-account"
        _ = await completeSourceWannaRemovalAfterCheckIn(
            SaveResult(userPlaceID: source.userPlace.id, syncState: .pendingCreate), visit: visit,
            submission: submission, store: store, backend: nil)
        XCTAssertEqual(source.userPlace.historicalWantNote, "Original Wanna note")
        XCTAssertFalse(store.placeWannaSaves.contains { $0.deletedAt != nil })
    }

    private func makeWanna(in store: WanderStore) throws -> VisiblePlace {
        let result = store.saveCandidate(candidate, status: .wannaGo, visibility: .selfOnly,
            note: "Original Wanna note", sourceType: .manual,
            attributes: [PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels,
                valueType: "multi_tag", valueJSON: "[\"My tag\"]")])
        return try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })
    }

    private func submission(for source: VisiblePlace, in store: WanderStore) -> MapPlaceSaveSubmission {
        let context = MapPlaceSaveContext.addFromExistingWanna(source,
            attributes: store.attributes(for: source.userPlace.id), latestVisit: nil).preselectingStatus(.been)
        return MapPlaceSaveSubmission(context: context, candidate: candidate, status: .been,
            visibility: .selfOnly, ratingScore: 4, note: "New check-in note", attributes: [],
            photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id)
    }
}
