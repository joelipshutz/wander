import MapKit
import SwiftUI
import UIKit
import XCTest
@testable import Wander

@MainActor
final class ForegroundPerformanceTests: XCTestCase {
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
