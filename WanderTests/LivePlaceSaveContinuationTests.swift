import XCTest
@testable import Wander

@MainActor
final class LivePlaceSaveContinuationTests: XCTestCase {
    func testNativeProviderAliasFindsAndEditsExistingMiyaMiyaWanna() async throws {
        let store = WanderStore(fixtures: .seed())
        let savedCandidate = candidate(id: "old-mapkit-id", name: "Miya Miya Shawarma", address: "10 Test Street")
        let result = store.saveCandidate(savedCandidate, status: .wannaGo, visibility: .selfOnly,
            note: "Existing Wanna", sourceType: .manual)
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })
        let native = candidate(id: "new-mapkit-id", name: "Miya Miya Shawarma", address: "10 Test St", latitude: 34.00002)
        XCTAssertFalse(VisiblePlaceGrouping.matches(own, candidate: native))
        let context = LivePlaceSaveContinuation.context(candidate: native, store: store)
        guard case .editWant(let selected) = context.mode else { return XCTFail("Native + must edit the existing Wanna") }
        XCTAssertEqual(selected.userPlace.id, own.userPlace.id)
        XCTAssertEqual(context.initialNote, "Existing Wanna")
        XCTAssertTrue(context.requiresStatusConfirmation)
        let beforeIDs = store.currentUserVisiblePlaces.map(\.id)
        let submission = MapPlaceSaveSubmission(context: context, candidate: context.candidate,
            status: .wannaGo, visibility: .selfOnly, ratingScore: nil, note: "Edited Wanna",
            attributes: [], photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id)
        let saved = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
        XCTAssertNotNil(saved)
        XCTAssertEqual(store.currentUserVisiblePlaces.map(\.id), beforeIDs)
        XCTAssertEqual(own.userPlace.note, "Edited Wanna")
        XCTAssertTrue(store.wannaSaves(for: own.userPlace).isEmpty, "Editing the original must not append a repeat Wanna")
    }

    func testNativeAliasDoesNotCollapseNearbySameBrandWithDifferentStreetNumbers() {
        let store = WanderStore(fixtures: .seed())
        let saved = candidate(id: "branch-a", name: "Same Brand", address: "10 Test Street")
        let result = store.saveCandidate(saved, status: .wannaGo, visibility: .selfOnly, note: nil, sourceType: .manual)
        let other = candidate(id: "branch-b", name: "Same Brand", address: "12 Test Street", latitude: 34.00002)
        XCTAssertFalse(LivePlaceSaveContinuation.matchingOwnPlaces(candidate: other, store: store)
            .contains { $0.userPlace.id == result.userPlaceID })
    }

    func testVisitedPlaceHistoricalWannaRemainsEditableWithoutChangingVisits() async throws {
        let store = WanderStore(fixtures: .seed())
        let item = candidate(id: "history", name: "History Cafe")
        let result = store.saveCandidate(item, status: .wannaGo, visibility: .selfOnly,
            note: "Original Wanna", sourceType: .manual)
        let visit = try XCTUnwrap(store.createVisit(userPlaceID: result.userPlaceID,
            note: "Keep check-in", visibility: .selfOnly))
        let context = LivePlaceSaveContinuation.context(candidate: item, store: store)
        XCTAssertEqual(context.initialStatus, .wannaGo)
        XCTAssertEqual(context.initialNote, "Original Wanna")
        XCTAssertTrue(context.allowsWannaGoSelection)
        XCTAssertTrue(context.editedWanna?.isHistoricalOriginal == true)
        let submission = MapPlaceSaveSubmission(context: context, candidate: context.candidate,
            status: .wannaGo, visibility: .selfOnly, ratingScore: nil, note: "Edited original",
            attributes: [], photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id)
        let saved = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
        XCTAssertNotNil(saved)
        XCTAssertEqual(store.visits(for: result.userPlaceID).map(\.id), [visit.id])
        XCTAssertEqual(visit.note, "Keep check-in")
        let parent = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace)
        XCTAssertEqual(parent.status, .been)
        XCTAssertEqual(store.wannaSaves(for: parent).map(\.note), ["Edited original"])
    }

    func testBeenWithoutWannaOffersFreshWannaAndKeepsOriginalVisit() async throws {
        let store = WanderStore(fixtures: .seed())
        let item = candidate(id: "visited-no-wanna", name: "Visited Cafe")
        let saved = store.saveCandidate(item, status: .been, visibility: .selfOnly,
            note: "Original check-in", sourceType: .manual, ratingScore: 4)
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        let visitsBefore = store.visits(for: own.userPlace.id).map { ($0.id, $0.note) }
        let source = LivePlaceSaveContinuation.context(candidate: item, store: store)
        XCTAssertEqual(source.initialStatus, .been)
        XCTAssertTrue(source.requiresStatusConfirmation)
        XCTAssertTrue(source.preselectsInitialStatus)
        XCTAssertTrue(source.startsOnDetails)
        XCTAssertTrue(source.allowsWannaGoSelection)
        guard case .addVisit = source.preselectingStatus(.been).mode else {
            return XCTFail("Default check-in must create another visit")
        }
        let wanna = source.preselectingStatus(.wannaGo)
        guard case .add = wanna.mode else { return XCTFail("Wanna must create a new memory") }
        XCTAssertEqual(wanna.initialStatus, .wannaGo)
        XCTAssertEqual(wanna.initialNote, "")
        XCTAssertNil(wanna.initialRatingScore)
        XCTAssertNil(wanna.initialPlannedDate)
        XCTAssertTrue(wanna.initialAnswers.isEmpty)
        XCTAssertTrue(wanna.initialPhotoAttachments.isEmpty)
        XCTAssertNil(wanna.editedVisit)
        XCTAssertNil(wanna.editedWanna)
        XCTAssertNil(wanna.wannaRemovalTarget)
        let submission = MapPlaceSaveSubmission(context: wanna, candidate: wanna.candidate,
            status: .wannaGo, visibility: .selfOnly, ratingScore: nil, note: "Future Wanna",
            attributes: [], photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id)
        let result = await persistAddPlaceSaveSubmission(submission, store: store, backend: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(own.userPlace.status, .been)
        XCTAssertEqual(store.visits(for: own.userPlace.id).map(\.id), visitsBefore.map { $0.0 })
        XCTAssertEqual(store.visits(for: own.userPlace.id).map(\.note), visitsBefore.map { $0.1 })
        XCTAssertEqual(store.wannaSaves(for: own.userPlace).map(\.note), ["Future Wanna"])
        let ordinary = MapPlaceSaveContext.existingCurrentUserSave(own,
            attributes: store.attributes(for: own.userPlace.id), latestVisit: store.visits(for: own.userPlace.id).first)
        XCTAssertFalse(ordinary.allowsWannaGoSelection, "Ordinary history continuation is unchanged")
    }

    func testRemovingAllWannasDoesNotDisableNextLiveWanna() async throws {
        let store = WanderStore(fixtures: .seed())
        let item = candidate(id: "removed-wanna", name: "Return Cafe")
        let saved = store.saveCandidate(item, status: .wannaGo, visibility: .selfOnly,
            note: "Old Wanna", sourceType: .manual)
        let source = LivePlaceSaveContinuation.context(candidate: item, store: store)
        let visitContext = source.preselectingStatus(.been)
        var submission = MapPlaceSaveSubmission(context: visitContext, candidate: visitContext.candidate,
            status: .been, visibility: .selfOnly, ratingScore: nil, note: "New visit",
            attributes: [], photoAttachments: [], inviteeUserIDs: [], reconcilesSharedVisitInvitees: false,
            ownerUserID: store.currentUser.id)
        submission.removesSourceWannaAfterCheckIn = true
        let result = await persistAddPlaceSaveSubmission(submission.capturingPriorWannas(in: store), store: store, backend: nil)
        XCTAssertNotNil(result)
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        XCTAssertTrue(store.wannaSaves(for: own.userPlace).isEmpty)
        XCTAssertNil(LivePlaceSaveContinuation.originalWannaDate(for: own, store: store))
        let reopened = LivePlaceSaveContinuation.context(candidate: item, store: store)
        XCTAssertEqual(reopened.initialStatus, .been)
        XCTAssertTrue(reopened.allowsWannaGoSelection)
        XCTAssertNil(reopened.wannaRemovalTarget)
        guard case .add = reopened.preselectingStatus(.wannaGo).mode else {
            return XCTFail("After removing prior Wannas, Live + must still permit a fresh Wanna")
        }
    }

    func testMergedPinIdentityEditsOwnTransitiveWannaWithoutCreatingAnotherParent() throws {
        let store = WanderStore(fixtures: .seed())
        let saved = store.saveCandidate(candidate(id: "historic-native", name: "Original name", address: "45 Former Road"),
            status: .wannaGo, visibility: .selfOnly, note: "Existing plan", sourceType: .manual)
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        let current = LocalPlace(localID: "99000000-0000-4000-8000-000000000011", canonicalName: "Current name",
            category: "restaurant", address: "10 Current Street", latitude: 34, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: "native-current")
        let bridge = LocalPlace(localID: "99000000-0000-4000-8000-000000000012", canonicalName: "Intermediate name",
            category: "restaurant", latitude: 34, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: current.id)
        own.place.sourceProviderPlaceID = bridge.id
        let identity = LivePlaceIdentity(places: [current, bridge, own.place])
        let selected = PlaceCandidate(id: current.id, name: current.canonicalName, category: "restaurant",
            address: current.address, latitude: 34, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: "native-current", confidence: 1)
        XCTAssertFalse(VisiblePlaceGrouping.matches(own, candidate: selected, allowingProviderIdentityFallback: true))
        XCTAssertEqual(LivePlaceSaveContinuation.matchingOwnPlaces(candidate: selected, identity: identity, store: store)
            .map(\.id), [own.id])
        let before = store.currentUserVisiblePlaces.map(\.id)
        let context = LivePlaceSaveContinuation.context(candidate: selected, identity: identity, store: store)
        guard case .editWant(let existing) = context.mode else { return XCTFail("The merged pin must edit its existing own Wanna") }
        XCTAssertEqual(existing.userPlace.id, own.userPlace.id)
        XCTAssertEqual(context.initialNote, "Existing plan")
        XCTAssertEqual(store.currentUserVisiblePlaces.map(\.id), before)
        own.userPlace.deletedAt = .now
        XCTAssertTrue(LivePlaceSaveContinuation.matchingOwnPlaces(candidate: selected, identity: identity, store: store).isEmpty,
            "A retained pin identity must not revive a deleted own save.")
    }

    func testExplicitPinIdentityCannotFallBackToCaseInsensitiveProviderMatch() throws {
        let store = WanderStore(fixtures: .seed())
        let saved = store.saveCandidate(candidate(id: "PlaceTokenA", name: "Old cafe", address: "20 Other Street"),
            status: .wannaGo, visibility: .selfOnly, note: "Existing plan", sourceType: .manual)
        let own = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID })
        own.place.sourceProvider = "mapkit"
        own.place.sourceProviderPlaceID = "PlaceTokenA"
        let different = LocalPlace(localID: "separate-venue", canonicalName: "Another cafe",
            category: "restaurant", address: "10 Different Street", latitude: 35, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: "placetokena")
        let selected = PlaceCandidate(id: different.id, name: different.canonicalName, category: "restaurant",
            address: different.address, latitude: 35, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: "placetokena", confidence: 1)
        XCTAssertTrue(LivePlaceSaveContinuation.matchingOwnPlaces(candidate: selected,
            identity: LivePlaceIdentity(places: [different]), store: store).isEmpty,
            "An explicit pin identity must not borrow another venue's existing Wanna.")
    }

    private func candidate(id: String, name: String, address: String? = nil, latitude: Double = 34) -> PlaceCandidate {
        PlaceCandidate(id: id, name: name, category: "restaurant", address: address,
            locality: "Test City", region: "CA", country: "US", latitude: latitude, longitude: -118,
            sourceProvider: "mapkit", sourceProviderPlaceID: id, confidence: 1)
    }
}
