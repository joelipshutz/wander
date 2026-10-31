import Foundation
import XCTest
@testable import Wander

@MainActor
final class StoreProjectionPerformanceTests: XCTestCase {
    func testPerformanceRepeatedLiveSections() async throws {
        let store = WanderStore(fixtures: .performanceScale())
        let places = store.visiblePlaces()
        let actor = store.shell(for: store.currentUser)
        let reference = Date(timeIntervalSince1970: 1_735_689_600)
        let events = (0..<600).map { index in
            FeedActivity(id: "projection-event-\(index)", kind: .placeBeen, actor: actor,
                         place: places[index % places.count],
                         occurredAt: reference.addingTimeInterval(-Double(index) * 1_800))
        }
        let repository = ProjectionFeedRepository(page: FollowedFeedPage(
            activity: events, featuredPlaces: [], nextCursor: nil, fetchedAt: reference))
        store.selectLiveFeedQuery(LiveFeedQuery())
        let loaded = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: repository))
        XCTAssertTrue(loaded)
        let expected = store.visibleLiveFeedSections.flatMap(\.groups).map(\.id)
        XCTAssertFalse(expected.isEmpty)
        var checksum = 0
        report("live_sections_600_events_20_reads") {
            for _ in 0..<20 {
                let sections = store.visibleLiveFeedSections
                checksum += sections.reduce(0) { $0 + $1.groups.count }
            }
        }
        XCTAssertGreaterThan(checksum, 0)
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).map(\.id), expected)
    }

    func testLiveSectionCacheReusesHistoricalGroupingAndReadsMutablePlaceInputs() async throws {
        let store = WanderStore(fixtures: ownedHistoryFixture(count: 2))
        let places = store.currentUserVisiblePlaces
        let actor = store.shell(for: store.currentUser)
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        let query = LiveFeedQuery(categoryIDs: [WanderPlaceCategory.normalizedPrimaryCategory("park")])
        let page = FollowedFeedPage(activity: [
            FeedActivity(id: "wanna", kind: .placeWannaGo, actor: actor, place: places[0], occurredAt: date),
            FeedActivity(id: "visit", kind: .placeBeen, actor: actor, place: places[1], occurredAt: date.addingTimeInterval(30))
        ], featuredPlaces: [], nextCursor: nil, fetchedAt: date)
        store.selectLiveFeedQuery(query)
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: ProjectionFeedRepository(page: page)))
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).count, 2)
        let builds = store.liveFeedSectionBuildCount
        for _ in 0..<20 { XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).count, 2) }
        XCTAssertEqual(store.liveFeedSectionBuildCount, builds)

        places[1].place.serverID = places[0].place.id
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).count, 1)
        XCTAssertEqual(store.liveFeedSectionBuildCount, builds + 1)
        places[1].userPlace.viewerPrimaryCategory = "restaurant"
        XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).flatMap(\.activities).map(\.id), ["wanna"])
        XCTAssertEqual(store.liveFeedSectionBuildCount, builds + 2)
        store.selectFeedAudience(.onlyFriends)
        XCTAssertTrue(store.visibleLiveFeedSections.flatMap(\.groups).isEmpty)
        store.apply(authState: .signedIn(AuthSession(userID: "different-projection-user", displayName: "Other", handle: "other")))
        XCTAssertTrue(store.visibleLiveFeedSections.isEmpty)
    }

    func testLiveSectionCacheDoesNotFreezeFutureClockSkewBehavior() async {
        let store = WanderStore(fixtures: .seed())
        let event = FeedActivity(id: "future", kind: .listCreated, actor: store.shell(for: store.currentUser),
                                 occurredAt: Date.now.addingTimeInterval(600))
        let page = FollowedFeedPage(activity: [event], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: ProjectionFeedRepository(page: page)))
        let before = store.liveFeedSectionBuildCount
        for _ in 0..<3 { XCTAssertEqual(store.visibleLiveFeedSections.flatMap(\.groups).map(\.id), ["future"]) }
        XCTAssertEqual(store.liveFeedSectionBuildCount, before + 3)
    }

    func testLiveSectionCacheRefreshesMutableLegacyTicketKind() async throws {
        let store = WanderStore(fixtures: ownedHistoryFixture(count: 1))
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let event = FeedActivity(id: "legacy-ticket", kind: .placeSaved, actor: store.shell(for: store.currentUser),
                                 place: place, occurredAt: Date(timeIntervalSince1970: 1_735_689_600))
        let page = FollowedFeedPage(activity: [event], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: ProjectionFeedRepository(page: page)))
        XCTAssertEqual(store.visibleFeedActivityGroups.first?.primaryActivity.resolvedTicketKind, .checkIn)
        let builds = store.liveFeedSectionBuildCount
        place.userPlace.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertEqual(store.visibleFeedActivityGroups.first?.primaryActivity.resolvedTicketKind, .wanna)
        XCTAssertEqual(store.liveFeedSectionBuildCount, builds + 1)
    }

    func testLiveSectionsRejectLeaseAtExactDeadlineWithoutTimerCallback() async {
        var clock = ContinuousClock.now
        let store = WanderStore(fixtures: .seed(), liveFeedClock: { clock })
        let own = store.shell(for: store.currentUser)
        let other = ProfileShell(id: "projection-friend", handle: "projection-friend",
                                 displayName: "Friend", avatarURL: nil, bio: nil, relationship: .follower)
        let page = FollowedFeedPage(activity: [
            FeedActivity(id: "own", kind: .listCreated, actor: own, occurredAt: .now),
            FeedActivity(id: "friend", kind: .listCreated, actor: other, occurredAt: .now)
        ], featuredPlaces: [], nextCursor: nil, fetchedAt: .now)
        store.selectLiveFeedQuery(LiveFeedQuery())
        _ = await store.refreshFollowedFeed(backend: WanderBackend(feedRepository: ProjectionFeedRepository(page: page)))
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["own", "friend"])
        clock = clock.advanced(by: LiveFeedDisplayLease.duration - .nanoseconds(1))
        XCTAssertEqual(Set(store.visibleFeedActivityGroups.map(\.id)), ["own", "friend"])
        clock = clock.advanced(by: .nanoseconds(1))
        // Deliberately do not call refreshLiveFeedDisplayLease: a cache read is
        // itself responsible for observing the exact authorization deadline.
        XCTAssertEqual(store.visibleFeedActivityGroups.map(\.id), ["own"])
    }

    func testPerformanceColdRemoteProjection() async {
        let source = WanderStore(fixtures: .performanceScale())
        let remote = source.visiblePlaces()
        let store = WanderStore(fixtures: emptyContentFixture(from: source))
        let repository = ProjectionUserPlaceRepository(places: remote)
        await store.refreshRemoteProfileVisiblePlaces(profileID: store.currentUser.id,
            backend: WanderBackend(userPlaceRepository: repository))
        XCTAssertGreaterThan(store.remoteVisiblePlaceCache.count, 1_400)
        let filters = PlaceFilters(ownerScopes: ["friends", "following", "you"])
        let expected = store.visiblePlaces(filters: filters).map(\.id)
        var samples: [Double] = []
        for _ in 0..<5 {
            store.isDarkMapEnabled.toggle() // Invalidate outside the timed projection.
            let start = ProcessInfo.processInfo.systemUptime
            let result = store.visiblePlaces(filters: filters)
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertEqual(result.map(\.id), expected)
        }
        attach("remote_projection_1620_saves", samples: samples)
    }

    func testRemoteProjectionIndexMatchesOrderedOwnerAndGraphScans() async throws {
        let source = WanderStore(fixtures: .seed())
        let remote = source.visiblePlaces()
        let store = WanderStore(fixtures: emptyContentFixture(from: source))
        await store.refreshRemoteProfileVisiblePlaces(profileID: store.currentUser.id,
            backend: WanderBackend(userPlaceRepository: ProjectionUserPlaceRepository(places: remote)))
        let foreign = try XCTUnwrap(remote.first { $0.owner.id != store.currentUser.id })
        let firstProfile = try XCTUnwrap(store.profiles.first)
        // The earlier handle match must win over a later exact ID match.
        firstProfile.handle = foreign.owner.handle
        let filters = [PlaceFilters(), PlaceFilters(ownerScopes: ["you"]),
                       PlaceFilters(ownerScopes: ["friends"]), PlaceFilters(ownerScopes: ["following"]),
                       PlaceFilters(ownerScopes: ["social"]), PlaceFilters(statuses: [.been]),
                       PlaceFilters(categories: ["park", "coffee"]), PlaceFilters(ownerIDs: [foreign.owner.id])]
        func verify() {
            store.isDarkMapEnabled.toggle()
            for filter in filters {
                let expected = referenceRemoteProjection(store: store, filters: filter)
                let actual = store.visiblePlaces(filters: filter)
                XCTAssertEqual(actual.map(\.id), expected.map(\.id))
                XCTAssertEqual(actual.map { ObjectIdentifier($0.owner) }, expected.map { ObjectIdentifier($0.owner) })
            }
        }
        verify()
        XCTAssertTrue(store.visiblePlaces().first { $0.id == foreign.id }?.owner === firstProfile)
        firstProfile.handle = "changed-after-index-read"
        verify()
        store.block(userID: foreign.owner.id)
        verify()
    }

    func testPerformanceAuthoritativeCalendarOmittingSyncedHistories() async {
        var samples: [Double] = []
        for _ in 0..<5 {
            let fixtures = ownedHistoryFixture(count: 1_500)
            fixtures.placeAttributes[0].syncStateRaw = SyncState.pendingUpdate.rawValue
            let store = WanderStore(fixtures: fixtures)
            let loaded = await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(surfaceSnapshotRepository: ProjectionSurfaceRepository()))
            XCTAssertTrue(loaded)
            let start = ProcessInfo.processInfo.systemUptime
            let projection = store.currentUserCalendarProjection
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
            XCTAssertTrue(projection.isAuthoritative)
            XCTAssertEqual(projection.userPlaces.map(\.localID), ["projection-save-0"])
        }
        attach("calendar_1500_omitted_synced_histories", samples: samples)
    }

    func testPerformancePerSaveAttributeAndVisitReads() {
        let store = WanderStore(fixtures: ownedHistoryFixture(count: 1_500))
        let ids = store.userPlaces.map(\.id)
        var checksum = 0
        report("attributes_visits_1500_saves") {
            for id in ids {
                checksum += store.attributes(for: id).count
                checksum += store.visits(for: id).count
            }
        }
        XCTAssertEqual(checksum, 1_500 * 2 * 5)
    }

    func testPerformanceBulkAttributeReads() {
        let store = WanderStore(fixtures: ownedHistoryFixture(count: 1_500))
        let ids = store.userPlaces.map(\.id)
        let expected = ids.map { store.attributes(for: $0).map(\.localID) }
        var referenceCount = 0
        report("individual_attributes_1500_saves_reference") {
            for id in ids { referenceCount += store.attributes(for: id).count }
        }
        XCTAssertEqual(referenceCount, 1_500 * 5)
        var result: [String: [LocalPlaceAttribute]] = [:]
        report("bulk_attributes_1500_saves") {
            result = store.attributesByUserPlaceID(for: ids)
        }
        XCTAssertEqual(ids.map { result[$0, default: []].map(\.localID) }, expected)
    }

    func testBulkAttributesPreserveAliasesFirstMatchOrderAndMutableInputs() {
        let fixtures = ownedHistoryFixture(count: 4)
        let first = fixtures.userPlaces[0]
        let second = fixtures.userPlaces[1]
        second.serverID = first.localID
        fixtures.placeAttributes[1].userPlaceID = first.id
        fixtures.placeAttributes[2].userPlaceID = first.localID
        fixtures.placeAttributes[3].userPlaceID = "unknown-parent"
        let store = WanderStore(fixtures: fixtures)
        func verify(_ ids: [String]) {
            let result = store.attributesByUserPlaceID(for: ids)
            XCTAssertEqual(Set(result.keys), Set(ids))
            for id in ids {
                XCTAssertEqual(result[id, default: []].map(\.localID), store.attributes(for: id).map(\.localID), id)
            }
        }
        let ids = [first.id, first.localID, second.localID, "unknown-parent", "missing", first.id]
        verify(ids)
        XCTAssertEqual(store.attributesByUserPlaceID(for: [first.id])[first.id]?.map(\.localID),
                       ["projection-attribute-0", "projection-attribute-1", "projection-attribute-2"])
        XCTAssertTrue(store.attributesByUserPlaceID(for: []).isEmpty)
        first.serverID = "changed-server-alias"
        fixtures.placeAttributes[1].questionKey = "a_first"
        fixtures.placeAttributes[2].userPlaceID = first.id
        verify(ids + [first.id])
    }

    func testCalendarChildIndexPreservesDirtyAliasesAndDeletedChildIntent() async {
        let fixtures = ownedHistoryFixture(count: 6)
        fixtures.placeAttributes[0].syncStateRaw = SyncState.pendingUpdate.rawValue
        fixtures.placeVisits[1].syncStateRaw = SyncState.pendingUpdate.rawValue
        fixtures.placeAttributes[2].syncStateRaw = SyncState.pendingDelete.rawValue
        fixtures.placeVisits[3].syncStateRaw = SyncState.pendingDelete.rawValue
        fixtures.placeVisits[3].deletedAt = .now
        fixtures.userPlaces[4].deletedAt = .now
        fixtures.placeAttributes[4].syncStateRaw = SyncState.pendingUpdate.rawValue
        let store = WanderStore(fixtures: fixtures)
        let loaded = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(surfaceSnapshotRepository: ProjectionSurfaceRepository()))
        XCTAssertTrue(loaded)
        XCTAssertEqual(Set(store.currentUserCalendarProjection.userPlaces.map(\.localID)),
                       Set((0..<4).map { "projection-save-\($0)" }))
    }

    private func report(_ name: String, operation: () -> Void) {
        var samples: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            operation()
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
        attach(name, samples: samples)
    }

    private func attach(_ name: String, samples: [Double]) {
        let sorted = samples.sorted()
        let text = "REC675 \(name) median_ms=\(sorted[sorted.count / 2]) samples_ms=\(samples)"
        print(text)
        let attachment = XCTAttachment(string: text)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func emptyContentFixture(from store: WanderStore) -> WanderFixtures {
        WanderFixtures(currentUser: store.currentUser, profiles: store.profiles,
                       places: [], userPlaces: [], placeAttributes: [],
                       follows: store.follows, blocks: store.blocks, placeLists: [],
                       placeListMembers: [], placeListItems: [], contactProvider: store.contactProvider)
    }

    private func referenceRemoteProjection(store: WanderStore, filters: PlaceFilters) -> [VisiblePlace] {
        let policy = VisibilityPolicy()
        return store.remoteVisiblePlaceCache.map { visible in
            guard let owner = store.profiles.first(where: { $0.id == visible.owner.id || $0.handle == visible.owner.handle })
            else { return visible }
            return VisiblePlace(id: visible.id, place: visible.place, userPlace: visible.userPlace,
                                owner: owner, attributes: visible.attributes)
        }.filter { visible in
            guard visible.userPlace.deletedAt == nil,
                  policy.canDisplayServerAuthorizedPlace(viewerID: store.currentUser.id,
                    ownerID: visible.userPlace.userID, visibility: visible.userPlace.visibility,
                    isBlocked: store.isBlockedBetweenCurrentUser(and: visible.owner.id)) else { return false }
            guard filters.statuses.isEmpty || filters.statuses.contains(visible.userPlace.status),
                  filters.normalizedCategories.isEmpty || filters.normalizedCategories.contains(visible.effectiveCategory),
                  filters.ownerIDs.isEmpty || filters.ownerIDs.contains(visible.owner.id) else { return false }
            guard !filters.ownerScopes.isEmpty else { return true }
            let isMine = visible.owner.id == store.currentUser.id
            let isFriend = store.relationship(to: visible.owner.id) == .mutual
            return (filters.ownerScopes.contains("you") && isMine)
                || (filters.ownerScopes.contains("friends") && !isMine && (isFriend || visible.userPlace.visibility == .mutuals))
                || (filters.ownerScopes.contains("following") && !isMine)
                || (filters.ownerScopes.contains("social") && !isMine)
        }
    }

    private func ownedHistoryFixture(count: Int) -> WanderFixtures {
        let seed = WanderFixtures.empty()
        let owner = seed.currentUser
        let date = Date(timeIntervalSince1970: 1_735_689_600)
        var places: [LocalPlace] = []
        var saves: [LocalUserPlace] = []
        var attributes: [LocalPlaceAttribute] = []
        var visits: [LocalPlaceVisit] = []
        for index in 0..<count {
            let place = LocalPlace(localID: "projection-place-\(index)",
                canonicalName: "Projection Place \(index)", category: "park", latitude: 34, longitude: -118)
            let save = LocalUserPlace(localID: "projection-save-\(index)",
                serverID: "projection-save-server-\(index)", userID: owner.id, placeID: place.id,
                status: .been, visibility: .selfOnly, visitedAt: date, sourceType: "manual", syncState: .synced)
            places.append(place)
            saves.append(save)
            attributes.append(LocalPlaceAttribute(localID: "projection-attribute-\(index)",
                userPlaceID: index.isMultiple(of: 2) ? save.localID : save.id,
                questionKey: "place_tags", valueType: "multi_tag", valueJSON: "[\"quiet\"]", syncState: .synced))
            visits.append(LocalPlaceVisit(localID: "projection-visit-\(index)",
                serverID: "projection-visit-server-\(index)", userPlaceID: save.id,
                visitedAt: date, syncState: .synced))
        }
        return WanderFixtures(currentUser: owner, profiles: [owner], places: places,
            userPlaces: saves, placeAttributes: attributes, placeVisits: visits,
            follows: [], blocks: [], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: seed.contactProvider)
    }
}

@MainActor
private final class ProjectionFeedRepository: FeedRepository {
    let page: FollowedFeedPage
    init(page: FollowedFeedPage) { self.page = page }
    func liveFeed(audience: FeedAudience, query: LiveFeedQuery, before: String?, limit: Int,
                  onContent: @MainActor (FollowedFeedPage) -> Void) async throws -> FollowedFeedPage {
        onContent(page)
        return page
    }
    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage { page }
}

@MainActor
private final class ProjectionUserPlaceRepository: UserPlaceRepository {
    let places: [VisiblePlace]
    init(places: [VisiblePlace]) { self.places = places }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { places }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

@MainActor
private final class ProjectionSurfaceRepository: SurfaceSnapshotRepository {
    func currentUserCalendarSnapshot() async throws -> CurrentUserCalendarRemoteSnapshot {
        CurrentUserCalendarRemoteSnapshot(visiblePlaces: [], visits: [])
    }
    func placeListsSnapshot() async throws -> PlaceListsRemoteSnapshot {
        PlaceListsRemoteSnapshot(summaries: [], details: [], visiblePlacesByOwnerID: [:], relationshipsByOwnerID: [:])
    }
    func socialSurfaceSnapshot(in viewport: MapViewport) async throws -> SocialSurfaceRemoteSnapshot {
        SocialSurfaceRemoteSnapshot(following: [], followers: [], viewportPlaces: [], ownWannaGoPlans: [],
            visiblePlacesByOwnerID: [:], relationshipsByOwnerID: [:])
    }
}
