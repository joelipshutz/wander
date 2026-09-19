import MapKit
import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class ForegroundPerformanceTests: XCTestCase {

    func testImportDuplicateIndexNormalizesEachInputOnceAndPreservesInputOrder() {
        var normalizations = 0
        let places = (0..<1_500).map { index in
            PlaceImportExistingPlace(userPlaceID: "save-\(index)", name: "Place \(index)",
                                     latitude: nil, longitude: nil, sourceProvider: "fixture", sourceProviderPlaceID: "id-\(index)")
        }
        let index = PlaceImportExistingPlaceIndex(places: places) { name in
            normalizations += 1
            return name.lowercased()
        }
        for offset in 0..<100 {
            let candidate = PlaceCandidate(id: "candidate-\(offset)", name: "Place \(offset)", category: "coffee",
                                           latitude: nil, longitude: nil,
                                           sourceProvider: "fixture", sourceProviderPlaceID: "id-1499", confidence: 1)
            XCTAssertEqual(index.firstMatch(for: candidate)?.userPlaceID, "save-\(offset)")
        }
        XCTAssertEqual(normalizations, 1_600, "Do not normalize the same places for each imported candidate")
    }

    func testImportDuplicateIndexKeepsCoordinatesProviderAndDiacriticMatching() {
        let places = [
            PlaceImportExistingPlace(userPlaceID: "far", name: "Café!", latitude: 40, longitude: 1, sourceProvider: nil, sourceProviderPlaceID: nil),
            PlaceImportExistingPlace(userPlaceID: "near", name: "CAFE", latitude: 34, longitude: -118, sourceProvider: "mapkit", sourceProviderPlaceID: "same"),
            PlaceImportExistingPlace(userPlaceID: "no-coordinate", name: "Cafe", latitude: nil, longitude: nil, sourceProvider: nil, sourceProviderPlaceID: nil)
        ]
        let index = PlaceImportExistingPlaceIndex(places: places)
        func candidate(_ name: String, _ provider: String = "mapkit", _ providerID: String? = nil) -> PlaceCandidate {
            PlaceCandidate(id: "candidate", name: name, category: "coffee", latitude: 34.0001, longitude: -118,
                           sourceProvider: provider, sourceProviderPlaceID: providerID, confidence: 1)
        }
        XCTAssertEqual(index.firstMatch(for: candidate("café"))?.userPlaceID, "near")
        XCTAssertEqual(index.firstMatch(for: candidate("renamed", "mapkit", "same"))?.userPlaceID, "near")
        XCTAssertNil(index.firstMatch(for: candidate("renamed", "google", "same")))
        XCTAssertEqual(PlaceImportExistingPlaceIndex(places: [places[0], places[2]]).firstMatch(for: candidate("cafe"))?.userPlaceID, "no-coordinate")
    }

    func testGroupingBuildsKeysOncePerDistinctPlaceInstance() {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let visible = store.visiblePlaces()
        let input = visible + visible
        var builds = 0
        let groups = VisiblePlaceGrouping.groups(from: input, currentUserID: store.currentUser.id) {
            builds += 1
        }
        XCTAssertFalse(input.isEmpty)
        XCTAssertEqual(builds, Set(input.map { ObjectIdentifier($0.place) }).count)
        XCTAssertEqual(groups.flatMap(\.places).count, input.count)
        for group in groups {
            XCTAssertEqual(group.key, VisiblePlaceGrouping.key(for: group.primary))
            for place in group.places {
                XCTAssertTrue(group.aliases.contains(VisiblePlaceGrouping.key(for: place)))
            }
        }
    }

    func testGroupingKeyReuseDoesNotOutliveMutablePlaceInputs() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let visible = try XCTUnwrap(store.visiblePlaces().first)
        let before = VisiblePlaceGrouping.groups(from: [visible], currentUserID: store.currentUser.id)
        visible.place.canonicalName = "Renamed grouping fixture"
        let after = VisiblePlaceGrouping.groups(from: [visible], currentUserID: store.currentUser.id)
        XCTAssertNotEqual(before.first?.key, after.first?.key)
        XCTAssertEqual(after.first?.key, VisiblePlaceGrouping.key(for: visible))
    }

    func testSuggestionEligibilityReusesReadsAndRefreshesAfterListEdits() async throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_laptop" })
        let batch = store.listSuggestions(for: list, limit: 5)
        let added = try XCTUnwrap(batch.first)
        XCTAssertGreaterThan(batch.count, 1)
        let initialBuilds = store.listSuggestionCandidateBuildCount
        for _ in 0..<30 {
            XCTAssertEqual(store.availableListSuggestions(batch, for: list).map(\.id), batch.map(\.id))
        }
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds)

        let result = await store.addVisiblePlace(added.visiblePlace, to: list, backend: nil)
        XCTAssertEqual(result.outcome, .added)
        let afterEdit = store.listSuggestionCandidateBuildCount
        for _ in 0..<10 {
            XCTAssertEqual(
                store.availableListSuggestions(batch, for: list).map(\.id),
                batch.dropFirst().map(\.id)
            )
        }
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, afterEdit + 1)

        XCTAssertTrue(store.removePlace(placeID: added.visiblePlace.place.id, from: list))
        let afterRemoval = store.listSuggestionCandidateBuildCount
        for _ in 0..<10 {
            XCTAssertFalse(store.availableListSuggestions(batch, for: list).contains { $0.id == added.id })
        }
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, afterRemoval + 1)
        XCTAssertTrue(store.availableListSuggestions([], for: list).isEmpty)
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, afterRemoval + 1)
    }

    func testSuggestionEligibilityRefreshesAfterBlockAndAccountChange() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let list = try XCTUnwrap(store.createPlaceList(name: "Eligibility fixture", description: "", visibility: .followers))
        let batch = store.visiblePlaces().map { ListPlaceSuggestion(visiblePlace: $0, reason: "Fixture", score: 1) }
        let initial = store.availableListSuggestions(batch, for: list)
        let friend = try XCTUnwrap(initial.first { $0.visiblePlace.owner.id != store.currentUser.id })
        let initialBuilds = store.listSuggestionCandidateBuildCount
        store.block(userID: friend.visiblePlace.owner.id)
        let afterBlock = store.availableListSuggestions(batch, for: list)
        XCTAssertFalse(afterBlock.contains { $0.visiblePlace.owner.id == friend.visiblePlace.owner.id })
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + 1)
        XCTAssertEqual(store.availableListSuggestions(batch, for: list).map(\.id), afterBlock.map(\.id))
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + 1)

        store.apply(authState: .signedIn(AuthSession(userID: "eligibility_new_account", displayName: "Fixture", handle: "fixture")))
        let newAccount = store.availableListSuggestions(batch, for: list)
        let authorized = Set(store.visiblePlaces().map(\.id))
        XCTAssertTrue(newAccount.allSatisfy { authorized.contains($0.id) })
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + 2)
    }

    func testSuggestionEligibilityCacheIsBoundedAcrossLists() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let lists = try (0..<5).map { index in
            try XCTUnwrap(store.createPlaceList(name: "Eligibility \(index)", description: "", visibility: .followers))
        }
        let batch = store.visiblePlaces().map { ListPlaceSuggestion(visiblePlace: $0, reason: "Fixture", score: 1) }
        XCTAssertFalse(batch.isEmpty)
        let initialBuilds = store.listSuggestionCandidateBuildCount
        for list in lists { _ = store.availableListSuggestions(batch, for: list) }
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + lists.count)
        for list in lists.suffix(4) { _ = store.availableListSuggestions(batch, for: list) }
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + lists.count)
        _ = store.availableListSuggestions(batch, for: lists[0])
        XCTAssertEqual(store.listSuggestionCandidateBuildCount, initialBuilds + lists.count + 1)
    }

    func testProfileMapReusesPreparationButRefreshesClockAndSavedPlaces() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let cache = ProfilePresentationCache()
        let firstTime = Date(timeIntervalSince1970: 1_787_623_200)
        var builds = 0
        func read(now: Date) -> YourMapPrototypeDataset {
            cache.mapDataset(store: store, profileID: store.currentUser.id, now: now) {
                builds += 1
                let projection = store.currentUserCalendarProjection
                return .make(ownerID: store.currentUser.id, userPlaces: projection.userPlaces,
                             visits: projection.visits, places: projection.places,
                             visiblePlaces: projection.visiblePlaces)
            }
        }
        let initial = read(now: firstTime)
        XCTAssertFalse(initial.places.isEmpty)
        for index in 1...20 {
            let time = firstTime.addingTimeInterval(Double(index) * 86_400)
            let next = read(now: time)
            XCTAssertEqual(next.now, time, "A warm dataset must not freeze date-relative map lenses")
            XCTAssertEqual(next.places.map(\.id), initial.places.map(\.id))
        }
        XCTAssertEqual(builds, 1)
        let ownPlace = try XCTUnwrap(store.currentUserCalendarProjection.visiblePlaces.first)
        XCTAssertNotNil(store.removeSave(userPlaceID: ownPlace.userPlace.id))
        let refreshed = read(now: firstTime)
        let projection = store.currentUserCalendarProjection
        let expected = YourMapPrototypeDataset.make(
            ownerID: store.currentUser.id, userPlaces: projection.userPlaces,
            visits: projection.visits, places: projection.places, visiblePlaces: projection.visiblePlaces
        )
        XCTAssertEqual(refreshed.places.map(\.id), expected.places.map(\.id))
        XCTAssertEqual(Set(refreshed.visiblePlaceByPlaceID.keys), Set(expected.visiblePlaceByPlaceID.keys))
        XCTAssertEqual(builds, 2)
    }

    func testProfileCachesSeparateStoreInstancesAndProfileIdentities() throws {
        let first = WanderStore(fixtures: WanderFixtures.seed())
        let second = WanderStore(fixtures: WanderFixtures.seed())
        XCTAssertEqual(first.presentationRevision, second.presentationRevision)
        let cache = ProfilePresentationCache()
        let firstPresentation = cache.present(store: first, profileID: first.currentUser.id)
        let secondPresentation = cache.present(store: second, profileID: second.currentUser.id)
        let firstPlace = try XCTUnwrap(firstPresentation.visiblePlaces.first?.place)
        let secondPlace = try XCTUnwrap(secondPresentation.visiblePlaces.first?.place)
        XCTAssertFalse(firstPlace === secondPlace, "A replacement store must not retain previous account model instances")
        var builds = 0
        func read(store: WanderStore, profileID: String) {
            _ = cache.mapDataset(store: store, profileID: profileID) {
                builds += 1
                let presentation = cache.present(store: store, profileID: profileID)
                return .make(ownerID: profileID, userPlaces: presentation.visiblePlaces.map(\.userPlace),
                             visits: presentation.visits, places: presentation.visiblePlaces.map(\.place),
                             visiblePlaces: presentation.visiblePlaces)
            }
        }
        read(store: first, profileID: first.currentUser.id)
        read(store: first, profileID: first.currentUser.id)
        XCTAssertEqual(builds, 1)
        read(store: second, profileID: second.currentUser.id)
        XCTAssertEqual(builds, 2)
        let friend = try XCTUnwrap(second.visiblePlaces().first { $0.owner.id != second.currentUser.id })
        read(store: second, profileID: friend.owner.id)
        read(store: second, profileID: friend.owner.id)
        XCTAssertEqual(builds, 3)
        second.block(userID: friend.owner.id)
        read(store: second, profileID: friend.owner.id)
        XCTAssertTrue(cache.present(store: second, profileID: friend.owner.id).visiblePlaces.isEmpty)
        XCTAssertEqual(builds, 4)
    }

    func testRootDescriptionsDoNotRestoreStoresBeforeSwiftUIMountsThem() {
        let probe = RootStoreProbe()
        let descriptions = (0..<100).map { index in
            WanderRootView(
                isSessionValidated: index.isMultiple(of: 2),
                storeFactory: probe.makeStore,
                importStoreFactory: probe.makeImportStore
            )
        }
        withExtendedLifetime(descriptions) {
            XCTAssertEqual(probe.storeLoads, 0)
            XCTAssertEqual(probe.importLoads, 0)
        }
    }

    func testMountedRootKeepsStoresAcrossParentUpdatesAndRecreatesForNewIdentity() async throws {
        let probe = RootStoreProbe()
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider())
        let backend = WanderBackend()
        let push = PushNotificationManager()
        let upsells = ProductUpsellCoordinator()
        let calendar = CalendarReservationManager()
        func root(account: String, dark: Bool) -> some View {
            WanderRootView(
                initialTab: .lists,
                isSessionValidated: false,
                storeFactory: probe.makeStore,
                importStoreFactory: probe.makeImportStore
            )
            .id(account)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(push)
            .environmentObject(upsells)
            .environmentObject(calendar)
        }
        let host = UIHostingController(rootView: root(account: "first", dark: false))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        await Task.yield()
        XCTAssertEqual(probe.storeLoads, 1)
        XCTAssertEqual(probe.importLoads, 1)
        let originalStore = try XCTUnwrap(probe.lastStore)
        originalStore.isDarkMapEnabled = true

        for index in 0..<8 {
            host.rootView = root(account: "first", dark: index.isMultiple(of: 2))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await Task.yield()
        }
        XCTAssertEqual(probe.storeLoads, 1, "Parent redraws must not reload the saved snapshot")
        XCTAssertEqual(probe.importLoads, 1, "Parent redraws must not reload import history")
        XCTAssertTrue(probe.lastStore === originalStore)
        XCTAssertTrue(originalStore.isDarkMapEnabled)

        host.rootView = root(account: "second", dark: false)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        await Task.yield()
        XCTAssertEqual(probe.storeLoads, 2)
        XCTAssertEqual(probe.importLoads, 2)
        XCTAssertFalse(probe.lastStore === originalStore)
    }

    func testRetainedMapProjectionReusesStableSelectionAndInvalidatesOnRevisionAndAccount() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let active = try XCTUnwrap(store.visiblePlaces().first)
        let cache = MapRenderProjectionCache<
            MapRetainedProjectionKey<MapSearchAuthorizationContext>, MapRetainedProjection
        >(capacity: 1)
        var authorizationReads = 0
        var authorized = store.visiblePlaces()
        func read(revision: UInt64, account: String) -> MapRetainedProjection {
            let key = MapRetainedProjectionKey(
                base: MapSearchAuthorizationContext(storeRevision: revision, currentUserID: account),
                activePlace: active, retainedGroup: nil, submittedGroups: []
            )
            return cache.value(for: key) {
                authorizationReads += 1
                return MapRetainedProjection(
                    places: [], groups: [], activePlace: active, retainedGroup: nil,
                    submittedGroups: [], authorizedPlaces: authorized,
                    authorizedGroups: VisiblePlaceGrouping.groups(from: authorized, currentUserID: account),
                    currentUserID: account
                )
            }
        }
        for _ in 0..<100 {
            XCTAssertTrue(read(revision: 0, account: store.currentUser.id).places.contains {
                $0.userPlace.id == active.userPlace.id
            })
        }
        XCTAssertEqual(authorizationReads, 1)

        // A delete or visibility revocation advances the store revision.
        authorized = []
        XCTAssertTrue(read(revision: 1, account: store.currentUser.id).places.isEmpty)
        XCTAssertEqual(authorizationReads, 2)
        XCTAssertTrue(read(revision: 1, account: "different-account").groups.isEmpty)
        XCTAssertEqual(authorizationReads, 3)
    }

    func testRetainedSelectionKeyDistinguishesRouteGroupMembershipAndSubmittedResults() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let groups = store.visiblePlaceGroups()
        let first = try XCTUnwrap(groups.first { $0.places.count > 1 })
        let partial = VisiblePlaceGroup(
            key: first.key, aliases: first.aliases,
            places: [first.primary], currentUserID: store.currentUser.id
        )
        func key(_ active: VisiblePlace?, _ retained: VisiblePlaceGroup?, _ submitted: [VisiblePlaceGroup])
            -> MapRetainedProjectionKey<String> {
            MapRetainedProjectionKey(base: "stable-map", activePlace: active,
                                     retainedGroup: retained, submittedGroups: submitted)
        }
        XCTAssertNotEqual(key(nil, nil, []), key(first.primary, nil, []))
        XCTAssertNotEqual(key(first.primary, nil, []), key(first.primary, first, []))
        XCTAssertNotEqual(key(first.primary, first, []), key(first.primary, partial, []))
        XCTAssertNotEqual(key(nil, nil, [first]), key(nil, nil, [partial]))
    }

    func testRetainedProjectionUsesStoreGroupingOnlyWhenMissingRoutedGroup() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let authorized = store.visiblePlaces()
        let group = try XCTUnwrap(store.visiblePlaceGroups().first)
        var groupingReads = 0
        func groups() -> [VisiblePlaceGroup] {
            groupingReads += 1
            return store.visiblePlaceGroups()
        }
        func project(_ active: VisiblePlace?, _ retained: VisiblePlaceGroup?) -> MapRetainedProjection {
            MapRetainedProjection(
                places: [], groups: [], activePlace: active, retainedGroup: retained,
                submittedGroups: [], authorizedPlaces: authorized,
                authorizedGroups: groups(), currentUserID: store.currentUser.id
            )
        }
        XCTAssertTrue(project(nil, nil).places.isEmpty)
        XCTAssertEqual(groupingReads, 0)
        XCTAssertFalse(project(group.primary, group).groups.isEmpty)
        XCTAssertEqual(groupingReads, 0)
        XCTAssertFalse(project(group.primary, nil).groups.isEmpty)
        XCTAssertEqual(groupingReads, 1)
        XCTAssertEqual(store.visiblePlaceGroupBuildCount, 1)
    }

    func testSubmittedProjectionCannotRestoreRevokedMembersOfRetainedGroup() throws {
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let group = try XCTUnwrap(store.visiblePlaceGroups().first { $0.places.count > 1 })
        let authorized = [group.primary]
        let result = MapRetainedProjection(
            places: [], groups: [], activePlace: group.primary, retainedGroup: group,
            submittedGroups: [group], authorizedPlaces: authorized,
            authorizedGroups: [], currentUserID: store.currentUser.id
        )
        XCTAssertEqual(result.places.map(\.userPlace.id), authorized.map(\.userPlace.id))
        XCTAssertEqual(result.groups.flatMap(\.places).map(\.userPlace.id), authorized.map(\.userPlace.id))
    }

    func testRetainedProjectionRefreshesFeaturedAuthorizationUnderUnchangedMapFilter() throws {
        let store = WanderStore(fixtures: .seed())
        let social = try XCTUnwrap(store.visiblePlaces().first)
        let owner = LocalProfile(
            localID: FeaturedCommunityPlaceSignal.ownerID, handle: "community", displayName: "Community"
        )
        let save = LocalUserPlace(
            localID: "featured-aggregate", userID: owner.id, placeID: social.place.id,
            status: .been, visibility: .followers, sourceType: "featured"
        )
        let aggregate = VisiblePlace(
            id: save.id, place: social.place, userPlace: save, owner: owner, communitySaveCount: 1
        )
        let cache = MapRenderProjectionCache<MapRetainedProjectionKey<String>, MapRetainedProjection>(capacity: 1)
        func read(revision: UInt64, featured: [VisiblePlace], account: String) -> MapRetainedProjection {
            let key = MapRetainedProjectionKey(
                base: "unchanged-friends-filter", authorizationRevision: revision,
                activePlace: aggregate, retainedGroup: nil, submittedGroups: []
            )
            return cache.value(for: key) {
                let authorized = MapActivePinRetention.authorizationCorpus(
                    socialPlaces: [social], featuredPlaces: featured,
                    featuredAccountID: account, currentUserID: store.currentUser.id
                )
                return MapRetainedProjection(
                    places: [], groups: [], activePlace: aggregate, retainedGroup: nil,
                    submittedGroups: [], authorizedPlaces: authorized,
                    // A social-only index cannot represent the complete group.
                    authorizedGroups: nil, currentUserID: store.currentUser.id
                )
            }
        }

        let initial = read(revision: 0, featured: [aggregate], account: store.currentUser.id)
        XCTAssertEqual(Set(initial.places.map(\.userPlace.id)), [social.userPlace.id, save.id])
        XCTAssertEqual(Set(initial.groups.flatMap(\.places).map(\.userPlace.id)), [social.userPlace.id, save.id])
        _ = read(revision: 0, featured: [aggregate], account: store.currentUser.id)
        XCTAssertEqual(cache.buildCount, 1)

        XCTAssertTrue(read(revision: 1, featured: [], account: store.currentUser.id).places.isEmpty)
        XCTAssertEqual(cache.buildCount, 2)
        XCTAssertTrue(read(revision: 2, featured: [aggregate], account: "previous-account").groups.isEmpty)
        XCTAssertEqual(cache.buildCount, 3)
    }

    func testIndexedSubcategoriesMatchOriginalOrderedCatalogScan() {
        for entry in WanderPlaceCategory.taxonomy {
            let inputs = entry.subcategories + entry.aliases + [entry.id, entry.group, "Café & thé", "東京", ""]
            for input in inputs {
                for value in [input, "  " + input.uppercased() + "\n"] {
                    let expected: String?
                    if let provider = WanderPlaceCategory.providerCategoryAssignment(for: value),
                       provider.primaryCategory == entry.id {
                        expected = provider.subcategory
                    } else if let normalized = WanderPlaceCategory.normalizedSubcategory(value) {
                        let key = WanderPlaceCategory.normalizedCategoryText(normalized)
                        expected = entry.subcategories.first {
                            WanderPlaceCategory.normalizedCategoryText($0) == key
                        } ?? normalized
                    } else {
                        expected = nil
                    }
                    XCTAssertEqual(
                        WanderPlaceCategory.canonicalSubcategory(value, primaryCategory: entry.id),
                        expected, "\(entry.id): \(value)"
                    )
                }
            }
        }
    }

    func testPerformanceStableRetainedProjectionWith1500Saves() throws {
        let owner = WanderFixtures.empty().currentUser
        let places = (0..<1_500).map { index in
            let place = LocalPlace(
                localID: "place-\(index)", canonicalName: "Fixture \(index)", category: "park",
                address: "\(index) Example Street", latitude: 34 + Double(index) * 0.001,
                longitude: -118, sourceProviderPlaceID: "fixture-\(index)"
            )
            let save = LocalUserPlace(
                localID: "save-\(index)", userID: owner.id, placeID: place.id,
                status: .been, visibility: .selfOnly, sourceType: "manual"
            )
            return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
        }
        let active = try XCTUnwrap(places.last)
        let groups = VisiblePlaceGrouping.groups(from: places, currentUserID: owner.id)
        let iterations = 20
        let previousStart = ProcessInfo.processInfo.systemUptime
        var previousCount = 0
        for _ in 0..<iterations {
            previousCount += try XCTUnwrap(MapActivePinRetention.authorizedGroup(
                nil, requiring: active, within: places, currentUserID: owner.id
            )).places.count
        }
        let previousMS = (ProcessInfo.processInfo.systemUptime - previousStart) * 1_000
        let cache = MapRenderProjectionCache<MapRetainedProjectionKey<String>, MapRetainedProjection>(capacity: 1)
        let currentStart = ProcessInfo.processInfo.systemUptime
        var currentCount = 0
        for _ in 0..<iterations {
            let key = MapRetainedProjectionKey(
                base: "unchanged-authorization-and-map", activePlace: active,
                retainedGroup: nil, submittedGroups: []
            )
            currentCount += cache.value(for: key) {
                MapRetainedProjection(
                    places: [], groups: [], activePlace: active, retainedGroup: nil,
                    submittedGroups: [], authorizedPlaces: places, authorizedGroups: groups,
                    currentUserID: owner.id
                )
            }.places.count
        }
        let currentMS = (ProcessInfo.processInfo.systemUptime - currentStart) * 1_000
        XCTAssertEqual(currentCount, previousCount)
        XCTAssertEqual(cache.buildCount, 1)
        let attachment = XCTAttachment(string:
            "REC484 retained_projection saves=1500 reads=\(iterations) previous_ms=\(previousMS) current_ms=\(currentMS)"
        )
        attachment.lifetime = .keepAlways
        add(attachment)
        // Timings are evidence, not hardware-dependent assertions.
    }
}

@MainActor
private final class RootStoreProbe {
    var storeLoads = 0
    var importLoads = 0
    var lastStore: WanderStore?

    func makeStore() -> WanderStore {
        let store = WanderStore(
            fixtures: WanderFixtures.empty(),
            persistence: WanderStorePersistence(load: { self.storeLoads += 1; return nil }, save: { _ in })
        )
        lastStore = store
        return store
    }

    func makeImportStore() -> PlaceImportStore {
        importLoads += 1
        return PlaceImportStore(persistence: EphemeralPlaceImportPersistence())
    }
}
