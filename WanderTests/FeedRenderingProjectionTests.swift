import XCTest
@testable import Wander

@MainActor
final class FeedRenderingProjectionTests: XCTestCase {
    func testPagingHistoryPreservesBottomCrossingResizeAndReverseScrollDecisions() {
        let history = FeedPagingHistory()
        let samples: [FeedScrollMetrics?] = [
            metrics(0), metrics(1_100), metrics(1_200), metrics(1_220), metrics(1_100),
            metrics(1_200), metrics(1_200, height: 3_000), metrics(2_200, height: 3_000),
            metrics(2_300, height: 3_000, viewport: 700), nil, metrics(2_300, height: 3_000, viewport: 700)
        ]
        var bottomCrossings: [Int] = []
        var sizeChanges: [Int] = []
        var expectedPrevious: FeedScrollMetrics?
        for (index, sample) in samples.enumerated() {
            history.receive(sample) { previous in
                XCTAssertEqual(previous, expectedPrevious)
                XCTAssertEqual(history.latest, expectedPrevious,
                    "Callbacks must see the previous sample until their decisions finish.")
                guard let sample else { return }
                if sample.contentHeight != previous?.contentHeight
                    || sample.viewportHeight != previous?.viewportHeight {
                    sizeChanges.append(index)
                }
                if sample.reachedBottom(after: previous) { bottomCrossings.append(index) }
            }
            XCTAssertEqual(history.latest, sample,
                "Visibility/load/pagination callbacks must read the exact latest sample.")
            expectedPrevious = sample
        }
        XCTAssertEqual(bottomCrossings, [2, 5, 7])
        XCTAssertEqual(sizeChanges, [0, 6, 8, 10])
    }

    func testPagingResetDoesNotCarryPriorBottomIntoNewFeedOrDiscardLatestViewport() {
        let history = FeedPagingHistory()
        history.receive(metrics(1_100)) { _ in }
        history.reset()
        XCTAssertNil(history.latest)
        history.receive(metrics(1_200)) { previous in
            XCTAssertNil(previous)
            XCTAssertFalse(self.metrics(1_200).reachedBottom(after: previous))
        }
        XCTAssertEqual(history.latest, metrics(1_200))
        history.receive(nil) { previous in XCTAssertEqual(previous, self.metrics(1_200)) }
        XCTAssertNil(history.latest)
    }

    func testRenderProjectionRetainsSectionsOrderedRowsAndCombinedFocusTargets() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let actor = store.shell(for: store.currentUser)
        let combined = FeedPresentation.groupedActivity([
            FeedActivity(id: "wanna", kind: .placeWannaGo, actor: actor, place: place,
                occurredAt: now.addingTimeInterval(-120)),
            FeedActivity(id: "check-in", kind: .placeBeen, actor: actor, place: place,
                occurredAt: now.addingTimeInterval(-60))
        ], relativeTo: now)
        XCTAssertEqual(combined.count, 1)
        let outside = FeedActivityGroup(FeedActivity(id: "outside", kind: .listCreated,
            actor: actor, occurredAt: now.addingTimeInterval(-500)))
        let sections = [
            LiveFeedActivitySection(stage: .selected, groups: []),
            LiveFeedActivitySection(stage: .older, groups: combined),
            LiveFeedActivitySection(stage: .allActivity, groups: [outside])
        ]
        let projection = FeedActivityRenderProjection(sections: sections)
        XCTAssertEqual(projection.sections.map(\.stage), [.selected, .older, .allActivity])
        XCTAssertTrue(projection.sections[0].groups.isEmpty)
        XCTAssertEqual(projection.groups.map(\.id), sections.flatMap(\.groups).map(\.id))
        XCTAssertEqual(projection.activityIDs, sections.flatMap(\.groups).flatMap(\.activities).map(\.id))
        XCTAssertEqual(projection.groupID(containing: "wanna"), combined.first?.id)
        XCTAssertEqual(projection.groupID(containing: "check-in"), combined.first?.id)
        XCTAssertEqual(projection.groupID(containing: "outside"), outside.id)
        XCTAssertNil(projection.groupID(containing: "absent"))
        XCTAssertNil(projection.groupID(containing: nil))
        let ordinary = FeedActivityRenderProjection(groups: projection.groups)
        XCTAssertTrue(ordinary.sections.isEmpty)
        XCTAssertEqual(ordinary.activityIDs, projection.activityIDs)
    }

    func testNextRenderUsesCurrentLeaseAndNeverRetainsExpiredSocialRows() async throws {
        var instant = ContinuousClock.now
        let store = WanderStore(fixtures: .seed(), liveFeedClock: { instant })
        let friend = try XCTUnwrap(store.profile(for: "user_maya"))
        let date = Date.now.addingTimeInterval(-3_600)
        let events = [
            FeedActivity(id: "own", kind: .listCreated, actor: store.shell(for: store.currentUser), occurredAt: date),
            FeedActivity(id: "social", kind: .listCreated, actor: store.shell(for: friend), occurredAt: date)
        ]
        store.selectLiveFeedQuery(LiveFeedQuery())
        let loaded = await store.refreshFollowedFeed(backend: WanderBackend(
            feedRepository: RenderProjectionFeedRepository(activity: events)))
        XCTAssertTrue(loaded)
        let initial = FeedActivityRenderProjection(sections: store.visibleLiveFeedSections)
        XCTAssertEqual(Set(initial.activityIDs), ["own", "social"])
        instant = instant.advanced(by: LiveFeedDisplayLease.duration)
        let expired = FeedActivityRenderProjection(sections: store.visibleLiveFeedSections)
        XCTAssertEqual(expired.activityIDs, ["own"])
        XCTAssertNil(expired.groupID(containing: "social"))
        XCTAssertEqual(Set(initial.activityIDs), ["own", "social"],
            "Projection values belong to one render; the next render must construct a fresh value.")
    }

    func testDirectFeedPhotoRequestMatchesFullSheetForFixtureAndMutableProviderFields() throws {
        let store = WanderStore(fixtures: .seed())
        for visible in store.visiblePlaces() {
            assertPhotoParity(visible)
        }
        let visible = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        visible.place.serverID = "renamed-photo-place"
        visible.place.canonicalName = "Changed name"
        visible.place.address = "Changed address"
        visible.place.latitude = 10.25
        visible.place.longitude = -40.75
        visible.place.sourceProvider = "google_places"
        visible.place.sourceProviderPlaceID = "changed-provider-reference"
        assertPhotoParity(visible)
    }

    func testDirectFeedPhotoRequestPreservesDroppedPinLastNameAndMalformedFallback() throws {
        let store = WanderStore(fixtures: .seed())
        let original = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        original.place.sourceProvider = "coordinate"
        original.place.canonicalName = "Canonical coordinate name"
        let first = nameAttribute("First name", id: "first", userPlaceID: original.userPlace.id)
        let last = nameAttribute("  Sunday overlook  ", id: "last", userPlaceID: original.userPlace.id)
        let visible = VisiblePlace(id: original.id, place: original.place,
            userPlace: original.userPlace, owner: original.owner, attributes: [first, last])
        assertPhotoParity(visible)
        XCTAssertEqual(FeedPlacePhotoPolicy.request(for: visible).name, "Sunday overlook")
        last.valueJSON = "invalid json"
        assertPhotoParity(visible)
        XCTAssertEqual(FeedPlacePhotoPolicy.request(for: visible).name, DroppedPinNamePolicy.fallbackName)
        visible.place.sourceProvider = "mapkit"
        assertPhotoParity(visible)
        XCTAssertEqual(FeedPlacePhotoPolicy.request(for: visible).name, "Canonical coordinate name")
    }

    private func metrics(_ offset: CGFloat, height: CGFloat = 2_000, viewport: CGFloat = 800) -> FeedScrollMetrics {
        FeedScrollMetrics(offset: offset, contentHeight: height, viewportHeight: viewport)
    }

    private func assertPhotoParity(_ visible: VisiblePlace, file: StaticString = #filePath, line: UInt = #line) {
        let expected = PlaceSheetPlace(visiblePlace: visible).photoRequest
        let actual = FeedPlacePhotoPolicy.request(for: visible)
        XCTAssertEqual(actual, expected, file: file, line: line)
        XCTAssertEqual(actual.lookupKey, expected.lookupKey, file: file, line: line)
        XCTAssertEqual(actual.canonicalPhotoCacheKey, expected.canonicalPhotoCacheKey, file: file, line: line)
        XCTAssertEqual(actual.rendering(.feed), expected.rendering(.feed), file: file, line: line)
    }

    private func nameAttribute(_ name: String, id: String, userPlaceID: String) -> LocalPlaceAttribute {
        let draft = PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.droppedPinName,
            valueType: "text", stringValue: name)
        return LocalPlaceAttribute(localID: id, userPlaceID: userPlaceID, questionKey: draft.questionKey,
            valueType: draft.valueType, valueJSON: draft.valueJSON)
    }
}

@MainActor
private final class RenderProjectionFeedRepository: FeedRepository {
    let activity: [FeedActivity]
    init(activity: [FeedActivity]) { self.activity = activity }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        FollowedFeedPage(activity: activity, featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
    }

    func liveFeed(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        try await activityFeed(audience: audience, before: before, limit: limit, onContent: onContent)
    }

    func activityFeed(audience: FeedAudience, before: String?, limit: Int,
        onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        let page = FollowedFeedPage(activity: activity, featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        onContent(page)
        return page
    }
}
