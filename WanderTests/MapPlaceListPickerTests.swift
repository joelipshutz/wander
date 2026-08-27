import XCTest
@testable import Wander

@MainActor
final class MapPlaceListPickerTests: XCTestCase {
    func testSelectionStagesNewMembershipWithoutChangingExistingMembership() {
        var selection = MapPlaceListPickerSelection(existingListIDs: ["already-there"])

        selection.togglePending(listID: "already-there")
        XCTAssertEqual(selection.existingListIDs, ["already-there"])
        XCTAssertTrue(selection.pendingListIDs.isEmpty)

        selection.togglePending(listID: "weekend")
        XCTAssertEqual(selection.pendingListIDs, ["weekend"])
        XCTAssertEqual(selection.selectedListIDs, ["already-there", "weekend"])

        selection.togglePending(listID: "weekend")
        XCTAssertTrue(selection.pendingListIDs.isEmpty)
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

        let result = await store.addCandidate(
            candidate,
            to: list,
            backend: nil,
            analyticsSurface: "map"
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

    func testMapListActionUsesExactBottomNavigationSymbol() {
        XCTAssertEqual(WanderTab.lists.systemImage, "bookmark.square")
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
