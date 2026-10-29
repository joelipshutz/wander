import XCTest
import UIKit
@testable import Wander

@MainActor
final class MapPlaceListPickerTests: XCTestCase {
    func testWannaSelectionsDoNotAddMembershipBeforeSaveAndRetriesDoNotCreateWannas() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let candidate = candidate(id: "wanna-lists", name: "Wanna Cafe")
        let list = try XCTUnwrap(store.createPlaceList(name: "Try soon", description: "", visibility: .followers))
        var selection = MapPlaceListPickerSelection(existingListIDs: [])
        selection.togglePending(listID: list.id)
        XCTAssertTrue(store.placeListItems.isEmpty, "Selection alone must never add the place.")
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty)

        let save = await store.saveNewWanna(candidate, visibility: .selfOnly, note: "For later",
            plannedDate: nil, attributes: [], backend: nil)
        XCTAssertTrue(store.placeListItems.isEmpty)
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first?.userPlace)
        let wannaIDs = store.wannaSaves(for: place).map(\.id)
        analytics.events.removeAll()
        for _ in 0..<2 {
            _ = await store.addSavedPlaceToLists(userPlaceID: save.userPlaceID,
                listIDs: selection.pendingListIDs, ownerUserID: store.currentUser.id,
                backend: nil, analyticsSurface: "wanna")
        }
        XCTAssertEqual(store.placeListItems.count, 1)
        XCTAssertEqual(store.wannaSaves(for: place).map(\.id), wannaIDs)
        XCTAssertEqual(place.visibility, .selfOnly)
        let events = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.properties, ["surface": "wanna", "list_role": "owner", "companion_save": "existing_wanna"])
    }

    func testRepeatedWannasAndCheckInsKeepOnePlacePerListAndPickerDetectsMembership() async throws {
        let store = makeStore()
        let candidate = candidate(id: "repeat-place", name: "Repeat Cafe")
        let list = try XCTUnwrap(store.createPlaceList(name: "Favorites", description: "", visibility: .followers))
        for status in [PlaceStatus.wannaGo, .wannaGo, .been, .wannaGo, .been] {
            let save: SaveResult
            if status == .wannaGo {
                save = await store.saveNewWanna(candidate, visibility: .selfOnly, note: "Again",
                    plannedDate: nil, attributes: [], backend: nil)
            } else if let existing = store.currentUserVisiblePlaces.first {
                let visit = try XCTUnwrap(store.createVisit(userPlaceID: existing.userPlace.id,
                    note: "Another visit", visibility: .selfOnly))
                save = SaveResult(userPlaceID: visit.userPlaceID, syncState: visit.syncState)
            } else {
                XCTFail("The first Wanna should create the owned place")
                return
            }
            _ = await store.addSavedPlaceToLists(userPlaceID: save.userPlaceID,
                listIDs: [list.id], ownerUserID: store.currentUser.id, backend: nil,
                analyticsSurface: status == .been ? "check_in" : "wanna")
            XCTAssertEqual(store.placeListItems.count, 1)
            XCTAssertTrue(MapPlaceListTarget.candidate(candidate).isAlreadyInList(list, store: store))
            var picker = MapPlaceListPickerSelection(existingListIDs: [list.id])
            picker.togglePending(listID: list.id)
            XCTAssertTrue(picker.pendingListIDs.isEmpty)
        }
    }

    func testCheckInListsPreserveVisitAndAudienceAcrossOfflineRetries() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let candidate = candidate(id: "check-in", name: "Check-in Cafe")
        let save = store.saveCandidate(candidate, status: .been, visibility: .selfOnly,
                                       note: "My private memory", sourceType: .manual)
        let visitIDs = store.visits(for: save.userPlaceID).map(\.id)
        let lists = try ["Weekend", "Coffee"].map {
            try XCTUnwrap(store.createPlaceList(name: $0, description: "", visibility: .followers))
        }
        analytics.events.removeAll()
        for _ in 0..<2 {
            let result = await store.addSavedPlaceToLists(userPlaceID: save.userPlaceID,
                listIDs: Set(lists.map(\.id)), ownerUserID: store.currentUser.id, backend: nil)
            XCTAssertEqual(result.pendingCount, 2)
            XCTAssertEqual(result.syncedCount, 0)
            XCTAssertTrue(result.needsAttention)
        }
        XCTAssertEqual(store.visits(for: save.userPlaceID).map(\.id), visitIDs)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
        XCTAssertEqual(store.currentUserVisiblePlaces.first?.userPlace.visibility, .selfOnly)
        XCTAssertEqual(store.currentUserVisiblePlaces.first?.userPlace.note, "My private memory")
        XCTAssertEqual(store.placeListItems.count, 2)
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.ownerUserPlaceID == save.userPlaceID })
        XCTAssertEqual(store.placeLists.map(\.ownerUserID), lists.map(\.ownerUserID))
        XCTAssertEqual(store.placeLists.map(\.visibility), lists.map(\.visibility))
        let additions = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        XCTAssertEqual(additions.count, 2)
        XCTAssertTrue(additions.allSatisfy { $0.properties == ["surface": "check_in", "list_role": "owner", "companion_save": "none"] })
        XCTAssertEqual(analytics.events.filter { $0.name == WanderAnalyticsEvents.engagementActionPerformed }.count, 2)
        XCTAssertFalse(analytics.events.contains { $0.name == WanderAnalyticsEvents.checkInCreated })
    }

    func testCheckInListsKeepPermittedAdditionsWhenAnotherListIsUnavailable() async throws {
        let store = makeStore()
        let save = store.saveCandidate(candidate(id: "partial", name: "Cafe"), status: .been,
            visibility: .followers, note: nil, sourceType: .manual)
        let list = try XCTUnwrap(store.createPlaceList(name: "Weekend", description: "", visibility: .stealth))
        let result = await store.addSavedPlaceToLists(userPlaceID: save.userPlaceID,
            listIDs: [list.id, "unavailable"], ownerUserID: store.currentUser.id, backend: nil)
        XCTAssertEqual(result.pendingCount, 1)
        XCTAssertEqual(result.unavailableCount, 1)
        XCTAssertEqual(store.placeListItems.count, 1)
        XCTAssertEqual(store.visits(for: save.userPlaceID).count, 1)
    }

    func testCheckInListsRejectChangedAccountAndNeverCreateAMissingSave() async {
        let store = makeStore()
        let save = store.saveCandidate(candidate(id: "account", name: "Cafe"), status: .been,
            visibility: .followers, note: nil, sourceType: .manual)
        let list = store.createPlaceList(name: "Weekend", description: "", visibility: .followers)!
        let stale = await store.addSavedPlaceToLists(userPlaceID: save.userPlaceID,
            listIDs: [list.id], ownerUserID: "another-account", backend: nil)
        let missing = await store.addSavedPlaceToLists(userPlaceID: "missing-save",
            listIDs: [list.id], ownerUserID: store.currentUser.id, backend: nil)
        XCTAssertEqual(stale.unavailableCount, 1)
        XCTAssertEqual(missing.unavailableCount, 1)
        XCTAssertTrue(store.placeListItems.isEmpty)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
    }

    func testCheckInListRetryDeliversOnlyFailedMembershipWithoutAnotherVisit() async throws {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore()
        let repository = CheckInListTestRepository()
        repository.failingListIDs = [lists[1].id]
        let backend = WanderBackend(placeListRepository: repository)
        let visitIDs = store.visits(for: userPlaceID).map(\.id)
        let first = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: Set(lists.map(\.id)), ownerUserID: store.currentUser.id, backend: backend)
        XCTAssertEqual(first.syncedCount, 1)
        XCTAssertEqual(first.failedCount, 1)
        XCTAssertEqual(store.placeListItems.count, 2)

        repository.failingListIDs = []
        let retry = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: Set(lists.flatMap { [$0.localID, $0.id] }), ownerUserID: store.currentUser.id, backend: backend)
        XCTAssertEqual(retry.syncedCount, 2)
        XCTAssertFalse(retry.needsAttention)
        XCTAssertEqual(repository.itemRequests.filter { $0.listID == lists[0].id }.count, 1)
        XCTAssertEqual(repository.itemRequests.filter { $0.listID == lists[1].id }.count, 2)
        XCTAssertEqual(store.placeListItems.count, 2)
        XCTAssertEqual(store.visits(for: userPlaceID).map(\.id), visitIDs)
        XCTAssertEqual(store.currentUserVisiblePlaces.first?.userPlace.visibility, .selfOnly)
    }

    func testCheckInListOutboxRetriesCollaboratorMembershipWithoutEditingTheirList() async throws {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore(collaboration: true)
        let selected = lists[0]
        let queued = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: [selected.id], ownerUserID: store.currentUser.id, backend: nil)
        XCTAssertEqual(queued.pendingCount, 1)
        let repository = CheckInListTestRepository()
        _ = await store.syncPendingPlaceLists(backend: WanderBackend(placeListRepository: repository))
        XCTAssertEqual(store.placeListItems.first?.syncState, .synced)
        XCTAssertEqual(repository.itemRequests.map(\.listID), [selected.id])
        XCTAssertEqual(repository.upsertCount, 0)
        XCTAssertEqual(repository.collaboratorUpdateCount, 0)
        XCTAssertEqual(store.placeLists.first?.ownerUserID, selected.ownerUserID)
    }

    func testCheckInListOutboxRetriesFailedItemsAfterListMetadataSyncs() async {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore()
        let repository = CheckInListTestRepository()
        repository.failingListIDs = [lists[0].id]
        let backend = WanderBackend(placeListRepository: repository)
        _ = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: [lists[0].id], ownerUserID: store.currentUser.id, backend: backend)
        _ = await store.syncPendingPlaceLists(backend: backend)
        XCTAssertEqual(store.placeListItems.first?.syncState, .failed)
        repository.failingListIDs = []
        _ = await store.syncPendingPlaceLists(backend: backend)
        XCTAssertEqual(store.placeListItems.first?.syncState, .synced)
        XCTAssertEqual(store.placeListItems.count, 1)
    }

    func testCheckInListsDoNotRestoreADeletedList() async throws {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore()
        XCTAssertTrue(store.deletePlaceList(id: lists[0].id))
        let repository = CheckInListTestRepository()
        let result = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: [lists[0].id], ownerUserID: store.currentUser.id,
            backend: WanderBackend(placeListRepository: repository))
        XCTAssertEqual(result.unavailableCount, 1)
        XCTAssertTrue(store.placeListItems.isEmpty)
        XCTAssertTrue(repository.itemRequests.isEmpty)
    }

    func testCheckInListsRecheckCollaboratorPermissionAtSubmission() async {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore(collaboration: false)
        let repository = CheckInListTestRepository()
        let result = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: [lists[0].id], ownerUserID: store.currentUser.id,
            backend: WanderBackend(placeListRepository: repository))
        XCTAssertEqual(result.unavailableCount, 1)
        XCTAssertTrue(store.placeListItems.isEmpty)
        XCTAssertTrue(repository.itemRequests.isEmpty)
    }

    func testCheckInListSyncDoesNotApplyAResponseAfterAccountSwitch() async {
        let (store, lists, userPlaceID) = makeRemoteCheckInListStore()
        let originalOwnerID = store.currentUser.id
        let repository = CheckInListTestRepository()
        repository.onAdd = {
            store.apply(authState: .signedIn(AuthSession(userID: "new-owner", displayName: "New", handle: "new")))
        }
        _ = await store.addSavedPlaceToLists(userPlaceID: userPlaceID,
            listIDs: Set(lists.map(\.id)), ownerUserID: store.currentUser.id,
            backend: WanderBackend(placeListRepository: repository))
        XCTAssertEqual(store.currentUser.id, "new-owner")
        XCTAssertEqual(repository.itemRequests.count, 1)
        // Offline records remain owned by their original account. A stale
        // response must neither mark them synced nor assign them to the new one.
        XCTAssertEqual(store.placeListItems.count, 2)
        XCTAssertTrue(store.placeListItems.allSatisfy {
            $0.addedByUserID == originalOwnerID && $0.serverID == nil && $0.syncState == .pendingCreate
        })
    }

    private func makeRemoteCheckInListStore(collaboration: Bool? = nil) -> (WanderStore, [LocalPlaceList], String) {
        let owner = LocalProfile(localID: "local-owner", serverID: "user_live", handle: "tester", displayName: "Tester")
        let place = LocalPlace(localID: "local-place", serverID: "33333333-3333-4333-8333-333333333333",
            canonicalName: "Fixture Cafe", category: "coffee", latitude: 34, longitude: -118, syncState: .synced)
        let save = LocalUserPlace(localID: "local-save", serverID: "44444444-4444-4444-8444-444444444444",
            userID: owner.id, placeID: place.id, status: .been, visibility: .selfOnly, sourceType: "manual", syncState: .synced)
        let lists = ["11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222"].enumerated().map { index, id in
            LocalPlaceList(localID: "local-list-\(index)", serverID: id, ownerUserID: collaboration == nil ? owner.id : "list-owner",
                name: "List \(index)", description: "", syncState: .synced)
        }
        let memberships = collaboration == true ? lists.map {
            LocalPlaceListMember(localID: "member-\($0.localID)", listID: $0.id, userID: owner.id, role: .collaborator)
        } : []
        let store = WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [owner],
            places: [place], userPlaces: [save], placeAttributes: [], follows: [], blocks: [],
            placeLists: lists, placeListMembers: memberships, placeListItems: [], contactProvider: FakeContactProvider(seededMatches: [])))
        _ = store.createVisit(userPlaceID: save.id, visitedAt: .now, note: nil, ratingScore: 8,
                              attributes: [], visibility: .selfOnly)
        return (store, lists, save.id)
    }

    func testImportListMembershipPreservesBothSaveStatuses() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let list = try XCTUnwrap(store.createPlaceList(name: "Import picks", description: "", visibility: .followers))
        for status in [PlaceStatus.wannaGo, .been] {
            let candidate = candidate(id: "import-\(status.rawValue)", name: "Import \(status.rawValue)")
            let save = store.saveImportedCandidate(candidate, status: status, visibility: .selfOnly, note: nil, sourceType: .manual)
            let result = await MapPlaceListTarget.candidate(candidate).add(to: list, store: store, backend: nil, analyticsSurface: "import")
            XCTAssertEqual(result.outcome, .added)
            XCTAssertTrue(store.hasCandidate(candidate, in: list))
            XCTAssertEqual(store.existingImportSave(matching: candidate)?.status, status)
            XCTAssertEqual(store.existingImportSave(matching: candidate)?.userPlaceID, save.userPlaceID)
        }
        let events = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.properties["surface"] == "import" })
        XCTAssertTrue(events.allSatisfy { Set($0.properties.keys).isSubset(of: ["surface", "list_role", "companion_save"]) })
    }

    func testSelectionStagesNewMembershipWithoutChangingExistingMembership() {
        var selection = MapPlaceListPickerSelection(existingListIDs: ["already-there"])

        selection.togglePending(listID: "already-there")
        XCTAssertEqual(selection.existingListIDs, ["already-there"])
        XCTAssertTrue(selection.pendingListIDs.isEmpty)

        selection.togglePending(listID: "weekend")
        XCTAssertEqual(selection.pendingListIDs, ["weekend"])

        selection.togglePending(listID: "weekend")
        XCTAssertTrue(selection.pendingListIDs.isEmpty)
    }

    func testRefreshingExistingMembershipPreservesOnlyStillPendingSelections() {
        var selection = MapPlaceListPickerSelection(existingListIDs: ["already-there"])
        selection.togglePending(listID: "weekend")
        selection.togglePending(listID: "newly-added")

        selection.replaceExistingListIDs(["already-there", "newly-added"])

        XCTAssertEqual(selection.existingListIDs, ["already-there", "newly-added"])
        XCTAssertEqual(selection.pendingListIDs, ["weekend"])
    }

    func testCancelledSelectionDoesNotCreateSaveOrListMembership() throws {
        let store = makeStore()
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Weekend",
                description: "",
                visibility: .followers
            )
        )
        let candidate = candidate(id: "cancelled", name: "Cancel Cafe")
        var selection = MapPlaceListPickerSelection(existingListIDs: [])

        selection.togglePending(listID: list.id)

        XCTAssertEqual(selection.pendingListIDs, [list.id])
        XCTAssertFalse(store.hasCandidate(candidate, in: list))
        XCTAssertTrue(store.currentUserVisiblePlaces.isEmpty)
    }

    func testUnsavedMapCandidateAddsToListAndCreatesOneWanna() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Try next",
                description: "",
                visibility: .followers
            )
        )
        analytics.events.removeAll()
        let candidate = candidate(id: "unsaved", name: "New Corner Cafe")

        let result = await MapPlaceListTarget.candidate(candidate).add(
            to: list,
            store: store,
            backend: nil
        )

        XCTAssertEqual(result.outcome, .added)
        guard case .createdWanna(let userPlaceID) = result.companionSave else {
            return XCTFail("Expected a new Wanna companion save")
        }
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
        XCTAssertEqual(store.currentUserVisiblePlaces.first?.userPlace.id, userPlaceID)
        XCTAssertEqual(store.currentUserVisiblePlaces.first?.userPlace.status, .wannaGo)
        XCTAssertTrue(store.hasCandidate(candidate, in: list))

        let rawEvent = try XCTUnwrap(
            analytics.events.first { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        )
        XCTAssertEqual(rawEvent.properties["surface"], "map")
        XCTAssertEqual(rawEvent.properties["list_role"], "owner")
        XCTAssertEqual(rawEvent.properties["companion_save"], "created_wanna")

        let engagement = try XCTUnwrap(
            analytics.events.first {
                $0.name == WanderAnalyticsEvents.engagementActionPerformed
                    && $0.properties["action"] == AnalyticsEngagementAction.listPlaceAdded.rawValue
            }
        )
        XCTAssertEqual(engagement.properties["need"], AnalyticsHumanNeed.expression.rawValue)
        XCTAssertEqual(engagement.properties["action"], AnalyticsEngagementAction.listPlaceAdded.rawValue)
        XCTAssertEqual(engagement.properties["surface"], "map")
    }

    func testSavedMapCandidateDoesNotCreateAnotherSave() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Favorites",
                description: "",
                visibility: .followers
            )
        )
        let candidate = candidate(id: "visited", name: "Visited Corner Cafe")
        let existing = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let result = await store.addCandidate(
            candidate,
            to: list,
            backend: nil,
            analyticsSurface: "map"
        )

        XCTAssertEqual(result.outcome, .added)
        XCTAssertEqual(result.companionSave, .none)
        XCTAssertEqual(store.currentUserVisiblePlaces.map(\.userPlace.id), [existing.userPlaceID])
    }

    func testDiscoverPickerAddsVisiblePlaceToMultipleListsWithDiscoverAttribution() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let candidate = candidate(id: "discover-result", name: "Discover Cafe")
        _ = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "Private note",
            sourceType: .manual
        )
        let visiblePlace = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let target = MapPlaceListTarget.visiblePlace(visiblePlace)
        let lists = try ["Weekend", "Coffee"].map { name in
            try XCTUnwrap(store.createPlaceList(name: name, description: "", visibility: .followers))
        }
        analytics.events.removeAll()

        for list in lists {
            let result = await target.add(
                to: list,
                store: store,
                backend: nil,
                analyticsSurface: "discover"
            )
            XCTAssertEqual(result.outcome, .added)
            XCTAssertEqual(result.companionSave, .none)
            XCTAssertTrue(target.isAlreadyInList(list, store: store))
        }
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)

        let rawEvents = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        XCTAssertEqual(rawEvents.count, 2)
        for event in rawEvents {
            XCTAssertEqual(event.properties, [
                "surface": "discover",
                "list_role": "owner",
                "companion_save": "none",
            ])
        }
        let engagementEvents = analytics.events.filter {
            $0.name == WanderAnalyticsEvents.engagementActionPerformed
                && $0.properties["action"] == AnalyticsEngagementAction.listPlaceAdded.rawValue
        }
        XCTAssertEqual(engagementEvents.count, 2)
        XCTAssertTrue(engagementEvents.allSatisfy { $0.properties["surface"] == "discover" })
    }

    func testExistingMapListMembershipIsIdempotent() async throws {
        let analytics = MapListRecordingAnalyticsClient()
        let store = makeStore(analytics: analytics)
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Coffee",
                description: "",
                visibility: .followers
            )
        )
        analytics.events.removeAll()
        let candidate = candidate(id: "repeat", name: "Repeat Cafe")

        let first = await store.addCandidate(
            candidate,
            to: list,
            backend: nil,
            analyticsSurface: "map"
        )
        let second = await store.addCandidate(
            candidate,
            to: list,
            backend: nil,
            analyticsSurface: "map"
        )

        XCTAssertEqual(first.outcome, .added)
        XCTAssertEqual(second.outcome, .alreadyInList)
        XCTAssertEqual(store.visiblePlaces(in: list).count, 1)
        XCTAssertEqual(
            analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }.count,
            1
        )
    }

    func testNewListCountUsesItsAddedPlaceEvenWhenCachedSummaryIsStale() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "New Test",
                description: "",
                visibility: .followers
            )
        )

        let result = await store.addCandidate(
            candidate(id: "new-list-place", name: "First Stop"),
            to: list,
            backend: nil,
            analyticsSurface: "map"
        )

        let refreshed = try XCTUnwrap(store.visiblePlaceLists.first { $0.id == list.id })
        XCTAssertEqual(result.outcome, .added)
        XCTAssertEqual(refreshed.cachedItemCount, 1)
        XCTAssertEqual(store.visiblePlaces(in: refreshed).count, 1)
        XCTAssertEqual(
            PlaceListDisplayCount.resolve(cachedCount: 0, visibleCount: 1),
            1
        )
    }

    func testPickerSummaryPrefersCreatedWannaAcrossMultipleLists() {
        let result = MapPlaceListPickerResult.summarize([
            ListPlaceAddResult(
                outcome: .added,
                companionSave: .existingWanna(userPlaceID: "existing")
            ),
            ListPlaceAddResult(
                outcome: .added,
                companionSave: .createdWanna(userPlaceID: "created")
            )
        ])

        XCTAssertEqual(result.addedCount, 2)
        XCTAssertEqual(result.companionSave, .createdWanna(userPlaceID: "created"))
        XCTAssertEqual(result.message, "Added to 2 lists and Wanna Go.")
    }

    func testListActionsUsePlainBulletsDistinctFromWanna() {
        XCTAssertEqual(PlaceListSymbol.systemImage, "list.bullet")
        XCTAssertNotEqual(PlaceListSymbol.systemImage, "bookmark.fill")
        XCTAssertNotNil(UIImage(systemName: PlaceListSymbol.systemImage))
    }

    func testPaperTabImageFitsNativeIconSlotAndAcceptsSelectionTint() {
        let image = PlaceListSymbol.paperTabImage
        XCTAssertEqual(image.size, CGSize(width: 22, height: 25))
        XCTAssertEqual(image.renderingMode, .alwaysTemplate)
        XCTAssertNotNil(image.cgImage)
    }

    func testSelectedPaperTabKeepsSignalInBothAppearances() throws {
        for isDark in [false, true] {
            let selected = PlaceListSymbol.paperTabImage(isSelected: true, isDark: isDark)
            let unselected = PlaceListSymbol.paperTabImage(isSelected: false, isDark: isDark)
            XCTAssertEqual(selected.size, CGSize(width: 22, height: 25))
            XCTAssertEqual(unselected.size, selected.size)
            XCTAssertEqual(selected.renderingMode, .alwaysOriginal)
            XCTAssertEqual(unselected.renderingMode, .alwaysTemplate)
            XCTAssertEqual(try paperFillRGBA(selected), [240, 90, 60, 255])
            XCTAssertEqual(try paperFillRGBA(unselected, tintColor: .white), [255, 255, 255, 255])
            XCTAssertEqual(try paperFillRGBA(unselected, tintColor: .black), [0, 0, 0, 255])
            XCTAssertTrue(selected === PlaceListSymbol.paperTabImage(isSelected: true, isDark: isDark))
        }
    }

    private func paperFillRGBA(_ image: UIImage, tintColor: UIColor = .white) throws -> [UInt8] {
        // Sample UIKit's displayed pixels: cgImage contains the untinted template mask.
        let imageView = UIImageView(image: image)
        imageView.tintColor = tintColor
        imageView.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            imageView.layer.render(in: context.cgContext)
        }
        let source = try XCTUnwrap(rendered.cgImage)
        // A center pixel between rows measures opaque sheet fill without edge antialiasing.
        let crop = try XCTUnwrap(source.cropping(to: CGRect(
            x: 10 * rendered.scale, y: 9 * rendered.scale, width: 1, height: 1
        )))
        var rgba = [UInt8](repeating: 0, count: 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return rgba
    }

    private func makeStore(
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) -> WanderStore {
        let store = WanderStore(fixtures: .empty(), analytics: analytics)
        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Ryan",
                    handle: "ryan"
                )
            )
        )
        return store
    }

    private func candidate(id: String, name: String) -> PlaceCandidate {
        PlaceCandidate(
            id: id,
            name: name,
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.96
        )
    }
}

private final class MapListRecordingAnalyticsClient: AnalyticsClient {
    var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}

@MainActor
private final class CheckInListTestRepository: PlaceListRepository {
    var failingListIDs: Set<String> = []
    var itemRequests: [PlaceListItemDraft] = []
    var onAdd: (() -> Void)?
    var upsertCount = 0
    var collaboratorUpdateCount = 0

    func visibleLists() async throws -> [RemotePlaceListSummary] { [] }
    func detail(listID: String) async throws -> RemotePlaceListDetail? { nil }
    func upsert(_ draft: PlaceListUpsertDraft) async throws -> String {
        upsertCount += 1
        return draft.id ?? UUID().uuidString
    }
    func delete(listID: String) async throws {}
    func setCollaborators(listID: String, userIDs: [String]) async throws { collaboratorUpdateCount += 1 }
    func removeItem(listID: String, itemID: String) async throws {}
    func addItem(_ draft: PlaceListItemDraft) async throws -> String {
        itemRequests.append(draft)
        onAdd?()
        if failingListIDs.contains(draft.listID) { throw URLError(.notConnectedToInternet) }
        return UUID().uuidString
    }
}
