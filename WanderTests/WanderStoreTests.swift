import CoreLocation
import XCTest
import UIKit
@testable import Wander

private enum TestError: Error {
    case expected
}

@MainActor
final class WanderStoreTests: XCTestCase {
    func testDarkMapDefaultsOff() {
        let store = WanderStore(fixtures: .seed())

        XCTAssertFalse(store.isDarkMapEnabled)
    }

    func testSwitchingAccountsDoesNotCarryPrivateProfileSettingsOrIdentity() {
        let first = LocalProfile(
            localID: "local_profile_current",
            serverID: "user_first",
            handle: "first",
            displayName: "First Person",
            avatarURL: "https://example.com/first.jpg",
            bio: "Private notes",
            homeArea: "Los Angeles",
            onboardingCompletedAt: Date(),
            isPrivateProfile: true,
            syncState: .synced
        )
        first.defaultVisibilityRaw = PlaceVisibility.selfOnly.rawValue
        let store = WanderStore(fixtures: WanderFixtures(
            currentUser: first,
            profiles: [first],
            places: [],
            userPlaces: [],
            placeAttributes: [],
            follows: [],
            blocks: [],
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        ))
        store.defaultMapFilter = .friends

        store.apply(authState: .signedIn(AuthSession(
            userID: "user_second",
            displayName: "Second Person",
            handle: "second"
        )))

        XCTAssertEqual(store.currentUser.serverID, "user_second")
        XCTAssertEqual(store.currentUser.displayName, "Second Person")
        XCTAssertEqual(store.currentUser.handle, "second")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.currentUser.bio)
        XCTAssertNil(store.currentUser.homeArea)
        XCTAssertNil(store.currentUser.onboardingCompletedAt)
        XCTAssertTrue(store.currentUser.isPrivateProfile)
        XCTAssertTrue(store.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .selfOnly)
        XCTAssertEqual(store.defaultMapFilter, .featured)
    }

    func testSigningOutClearsPrivateIdentityFields() {
        let store = WanderStore(fixtures: .seed())
        store.updateCurrentUserProfile(
            displayName: "Sensitive Name",
            handle: "sensitive",
            bio: "Private bio",
            homeArea: "Private city"
        )
        store.updateCurrentUserAvatarURL("https://example.com/private.jpg")
        store.currentUser.onboardingCompletedAt = Date()
        store.setPrivateProfile(true)
        store.defaultMapFilter = .friends
        store.isDarkMapEnabled = true

        store.apply(authState: .signedOut)

        XCTAssertNil(store.currentUser.serverID)
        XCTAssertEqual(store.currentUser.displayName, "You")
        XCTAssertEqual(store.currentUser.handle, "you")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.currentUser.bio)
        XCTAssertNil(store.currentUser.homeArea)
        XCTAssertNil(store.currentUser.onboardingCompletedAt)
        XCTAssertFalse(store.currentUser.isPrivateProfile)
        XCTAssertFalse(store.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .followers)
        XCTAssertEqual(store.defaultMapFilter, .featured)
        XCTAssertTrue(store.isDarkMapEnabled)
    }

    func testPermanentAccountDeletionPurgesAllLocalAccountDataAndPreferences() {
        let store = WanderStore(fixtures: .seed())
        store.defaultVisibility = .mutuals
        store.setPrivateProfile(true)
        store.defaultMapFilter = .friends
        store.isDarkMapEnabled = true

        store.resetAfterAccountDeletion()

        XCTAssertEqual(store.currentUser.handle, "you")
        XCTAssertNil(store.currentUser.serverID)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertTrue(store.userPlaces.isEmpty)
        XCTAssertTrue(store.placeVisits.isEmpty)
        XCTAssertTrue(store.follows.isEmpty)
        XCTAssertTrue(store.blocks.isEmpty)
        XCTAssertTrue(store.mutes.isEmpty)
        XCTAssertTrue(store.placeLists.isEmpty)
        XCTAssertEqual(store.defaultVisibility, .followers)
        XCTAssertFalse(store.isPrivateProfile)
        XCTAssertEqual(store.defaultMapFilter, .featured)
        XCTAssertFalse(store.isDarkMapEnabled)
    }

    func testFriendsAreMutualFollowsFromSingleStoreHelper() {
        let store = WanderStore(fixtures: .seed())
        let ownerID = store.currentUser.id
        let expected = store.following(of: ownerID)
            .filter { profile in store.followers(of: ownerID).contains { $0.id == profile.id } }
            .map(\.id)

        XCTAssertEqual(store.friends(of: ownerID).map(\.id), expected)
    }

    func testPlacesInCommonIncludesBeenAndWannaMatchesWithoutDuplicates() {
        let store = makeStore()

        let matches = store.placesInCommon(with: "user_maya")

        XCTAssertEqual(
            Set(matches.map { $0.place.canonicalName }),
            ["Circuit Coffee", "Bar Nido", "Elysian Picnic Steps"]
        )
        XCTAssertEqual(matches.filter { $0.place.canonicalName == "Elysian Picnic Steps" }.map(\.userPlace.status), [.been])
        XCTAssertEqual(matches.count, Set(matches.map { VisiblePlaceGrouping.key(for: $0) }).count)
        XCTAssertTrue(store.placesInCommon(with: store.currentUser.id).isEmpty)
    }

    func testPlacesInCommonMatchesCanonicalProviderAliasesAndExcludesUnrelatedPlaces() {
        let currentUser = LocalProfile(
            localID: "local_profile_current",
            serverID: "user_current",
            handle: "current",
            displayName: "Current",
            syncState: .synced
        )
        let friend = LocalProfile(
            localID: "local_profile_friend",
            serverID: "user_friend",
            handle: "friend",
            displayName: "Friend",
            syncState: .synced
        )
        let mine = LocalPlace(
            localID: "local_place_mine",
            serverID: "place_mine",
            canonicalName: "L.A. Cafe",
            category: "coffee",
            latitude: 34.0522,
            longitude: -118.2437,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "shared-provider-id",
            syncState: .synced
        )
        let theirAlias = LocalPlace(
            localID: "local_place_theirs",
            serverID: "place_theirs",
            canonicalName: "Los Angeles Cafe",
            category: "coffee",
            latitude: 34.0523,
            longitude: -118.2436,
            sourceProvider: "MAPKIT",
            sourceProviderPlaceID: "shared-provider-id",
            syncState: .synced
        )
        let unrelated = LocalPlace(
            localID: "local_place_unrelated",
            serverID: "place_unrelated",
            canonicalName: "Different Cafe",
            category: "coffee",
            latitude: 35,
            longitude: -119,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "different-provider-id",
            syncState: .synced
        )
        let fixture = WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser, friend],
            places: [mine, theirAlias, unrelated],
            userPlaces: [
                LocalUserPlace(
                    localID: "local_up_mine",
                    serverID: "up_mine",
                    userID: currentUser.id,
                    placeID: mine.id,
                    status: .wannaGo,
                    visibility: .followers,
                    sourceType: "manual",
                    syncState: .synced
                ),
                LocalUserPlace(
                    localID: "local_up_theirs",
                    serverID: "up_theirs",
                    userID: friend.id,
                    placeID: theirAlias.id,
                    status: .been,
                    visibility: .followers,
                    sourceType: "manual",
                    syncState: .synced
                ),
                LocalUserPlace(
                    localID: "local_up_unrelated",
                    serverID: "up_unrelated",
                    userID: friend.id,
                    placeID: unrelated.id,
                    status: .been,
                    visibility: .followers,
                    sourceType: "manual",
                    syncState: .synced
                )
            ],
            placeAttributes: [],
            follows: [
                LocalFollow(
                    localID: "local_follow_current_friend",
                    serverID: "follow_current_friend",
                    followerUserID: currentUser.id,
                    followedUserID: friend.id,
                    source: .profile,
                    syncState: .synced
                )
            ],
            blocks: [],
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        )
        let store = WanderStore(fixtures: fixture)

        let matches = store.placesInCommon(with: friend.id)

        XCTAssertEqual(matches.map { $0.place.canonicalName }, ["Los Angeles Cafe"])
        XCTAssertEqual(matches.map(\.userPlace.status), [.been])
    }

    func testMemberProfileRefreshHydratesDetailPlacesGraphAndVisitsForSelectedUser() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_current", displayName: "Current", handle: "current")))
        let joinedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2023-10-01T12:00:00Z"))
        let visitedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T19:00:00Z"))
        let shell = ProfileShell(
            id: "user_friend",
            handle: "friend",
            displayName: "Friend Name",
            avatarURL: "https://example.com/friend.jpg",
            bio: "Trusted neighborhood picks.",
            homeArea: "Santa Monica",
            isPrivateProfile: false,
            createdAt: joinedAt,
            relationship: .mutual
        )
        let owner = LocalProfile(
            localID: "remote_profile_friend",
            serverID: shell.id,
            handle: shell.handle,
            displayName: shell.displayName,
            avatarURL: shell.avatarURL,
            syncState: .synced
        )
        let place = LocalPlace(
            localID: "remote_place_friend",
            serverID: "place_friend",
            canonicalName: "Friend Cafe",
            category: "coffee",
            latitude: 34.02,
            longitude: -118.49,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "friend-cafe",
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "remote_up_friend",
            serverID: "up_friend",
            userID: shell.id,
            placeID: place.id,
            status: .been,
            visibility: .mutuals,
            visitedAt: visitedAt,
            sourceType: "manual",
            syncState: .synced
        )
        let visiblePlace = VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner
        )
        let profileRepository = FakeProfileRepository(
            profileStates: [
                shell.id: ProfileViewState(
                    shell: shell,
                    visiblePlaces: [],
                    canFollow: false,
                    canBlock: true,
                    isBlocked: false
                )
            ]
        )
        let userPlaceRepository = FakeUserPlaceRepository(userPlacesByUserID: [shell.id: [visiblePlace]])
        let followRepository = FakeFollowRepository(relationships: [shell.id: .mutual])
        let visitRepository = FakeVisitRepository(
            visitsByUserPlaceID: [
                userPlace.id: [
                    PlaceVisitResult(
                        visitID: "visit_friend",
                        userPlaceID: userPlace.id,
                        visitedAt: visitedAt,
                        note: "Dinner",
                        ratingScore: 4.5,
                        tags: ["cozy"],
                        backfilledFromUserPlace: false
                    )
                ]
            ],
            photosByVisitID: [
                "visit_friend": [
                    VisitPhotoResult(
                        photoID: "photo_friend",
                        visitID: "visit_friend",
                        storageBucket: "visit-photos",
                        storagePath: "user_friend/visit_friend/photo_friend.jpg",
                        remoteURLString: "https://example.com/signed/photo_friend.jpg",
                        contentType: "image/jpeg",
                        byteSize: 1_024,
                        width: 1_200,
                        height: 1_600,
                        capturedAt: visitedAt,
                        sortOrder: 0,
                        uploadState: .uploaded
                    )
                ]
            ]
        )
        let backend = WanderBackend(
            profileRepository: profileRepository,
            followRepository: followRepository,
            userPlaceRepository: userPlaceRepository,
            visitRepository: visitRepository
        )

        await store.refreshRemoteProfileData(profileID: shell.id, backend: backend)

        let hydrated = try XCTUnwrap(store.profile(for: shell.id))
        XCTAssertEqual(hydrated.displayName, "Friend Name")
        XCTAssertEqual(hydrated.avatarURL, "https://example.com/friend.jpg")
        XCTAssertEqual(hydrated.bio, "Trusted neighborhood picks.")
        XCTAssertEqual(hydrated.homeArea, "Santa Monica")
        XCTAssertEqual(hydrated.createdAt, joinedAt)
        XCTAssertEqual(store.visiblePlaces(for: shell.id).map { $0.place.canonicalName }, ["Friend Cafe"])
        XCTAssertEqual(profileRepository.profileIDs, [shell.id])
        XCTAssertEqual(userPlaceRepository.userPlaceRequests.map(\.userID), [shell.id])
        XCTAssertEqual(followRepository.followersUserIDs, [shell.id])
        XCTAssertEqual(followRepository.followingUserIDs, [shell.id])
        XCTAssertEqual(visitRepository.visitRequests, [userPlace.id])
        XCTAssertEqual(visitRepository.photoRequests, ["visit_friend"])
        XCTAssertEqual(store.placeVisits.first { $0.id == "visit_friend" }?.visitedAt, visitedAt)
        let hydratedPhoto = try XCTUnwrap(store.photos(for: "visit_friend").first)
        XCTAssertEqual(hydratedPhoto.id, "photo_friend")
        XCTAssertEqual(hydratedPhoto.remoteURLString, "https://example.com/signed/photo_friend.jpg")
    }

    func testCurrentUserCalendarRefreshHydratesOwnPlacesAndVisitsBeforePublishing() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_current"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userID, displayName: "Current", handle: "current")
            )
        )
        let visitedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-10T19:00:00Z")
        )
        let place = LocalPlace(
            localID: "remote_place_current",
            serverID: "place_current",
            canonicalName: "Current Cafe",
            category: "coffee",
            latitude: 34.02,
            longitude: -118.49,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "current-cafe",
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "remote_up_current",
            serverID: "up_current",
            userID: userID,
            placeID: place.id,
            status: .been,
            visibility: .followers,
            visitedAt: visitedAt,
            sourceType: "manual",
            syncState: .synced
        )
        let visiblePlace = VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: store.currentUser
        )
        let userPlaceRepository = FakeUserPlaceRepository(
            userPlacesByUserID: [userID: [visiblePlace]]
        )
        let visitRepository = FakeVisitRepository(
            visitsByUserPlaceID: [
                userPlace.id: [
                    PlaceVisitResult(
                        visitID: "visit_current",
                        userPlaceID: userPlace.id,
                        visitedAt: visitedAt,
                        note: nil,
                        ratingScore: 4,
                        tags: [],
                        backfilledFromUserPlace: false
                    )
                ]
            ]
        )

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: userPlaceRepository,
                visitRepository: visitRepository
            )
        )

        XCTAssertTrue(hydrated)
        XCTAssertEqual(userPlaceRepository.userPlaceRequests.map(\.userID), [userID])
        XCTAssertEqual(visitRepository.visitRequests, [userPlace.id])
        XCTAssertEqual(store.placeVisits.first { $0.id == "visit_current" }?.visitedAt, visitedAt)
    }

    func testBatchSurfaceSnapshotRepositoryDrivesCalendarListAndSocialRefreshes() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_current", displayName: "Current", handle: "current")
            )
        )
        let repository = FakeSurfaceSnapshotRepository()
        let backend = WanderBackend(surfaceSnapshotRepository: repository)

        let calendarHydrated = await store.refreshRemoteCurrentUserCalendarData(backend: backend)
        await store.refreshRemotePlaceLists(backend: backend)
        let socialHydrated = await store.refreshRemoteSocialSurfaces(backend: backend)

        // Empty batch snapshots must not fabricate owner activity.
        XCTAssertTrue(calendarHydrated)
        XCTAssertTrue(socialHydrated)
        XCTAssertEqual(repository.calendarRequestCount, 1)
        XCTAssertEqual(repository.listRequestCount, 1)
        XCTAssertEqual(repository.socialViewports.count, 1)
    }

    func testViewportRefreshPreservesFullyHydratedOwnerCalendarAcrossRegions() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_current"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userID, displayName: "Current", handle: "current")
            )
        )
        let activityDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-10T19:00:00Z")
        )
        let owner = store.currentUser

        let visitedPlace = LocalPlace(
            localID: "remote_place_west",
            serverID: "place_west",
            canonicalName: "Westside Cafe",
            category: "coffee",
            latitude: 34.02,
            longitude: -118.49,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "westside-cafe",
            syncState: .synced
        )
        let visitedUserPlace = LocalUserPlace(
            localID: "remote_up_west",
            serverID: "up_west",
            userID: userID,
            placeID: visitedPlace.id,
            status: .been,
            visibility: .followers,
            savedAt: activityDate,
            sourceType: "manual",
            syncState: .synced
        )
        let westside = VisiblePlace(
            id: visitedUserPlace.id,
            place: visitedPlace,
            userPlace: visitedUserPlace,
            owner: owner
        )

        let wannaPlace = LocalPlace(
            localID: "remote_place_east",
            serverID: "place_east",
            canonicalName: "Eastside Garden",
            category: "park",
            latitude: 34.04,
            longitude: -118.20,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "eastside-garden",
            syncState: .synced
        )
        let wannaUserPlace = LocalUserPlace(
            localID: "remote_up_east",
            serverID: "up_east",
            userID: userID,
            placeID: wannaPlace.id,
            status: .wannaGo,
            visibility: .followers,
            savedAt: activityDate,
            sourceType: "manual",
            syncState: .synced
        )
        let eastside = VisiblePlace(
            id: wannaUserPlace.id,
            place: wannaPlace,
            userPlace: wannaUserPlace,
            owner: owner
        )

        let calendarHydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: [westside, eastside]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [
                        visitedUserPlace.id: [
                            PlaceVisitResult(
                                visitID: "visit_west",
                                userPlaceID: visitedUserPlace.id,
                                visitedAt: activityDate,
                                note: nil,
                                ratingScore: 4,
                                tags: [],
                                backfilledFromUserPlace: false
                            )
                        ]
                    ]
                )
            )
        )
        XCTAssertTrue(calendarHydrated)

        await store.refreshRemoteVisiblePlaces(
            in: MapViewport(
                minLatitude: 33.9,
                minLongitude: -118.6,
                maxLatitude: 34.1,
                maxLongitude: -118.4
            ),
            backend: WanderBackend(
                placeRepository: FakePlaceRepository(places: [westside])
            )
        )

        XCTAssertEqual(
            Set(
                store.remoteVisiblePlaceCache
                    .filter { $0.owner.id == userID }
                    .map(\.userPlace.id)
            ),
            [visitedUserPlace.id, wannaUserPlace.id]
        )
        XCTAssertEqual(store.stats.checkIns, 1)
        XCTAssertEqual(store.stats.wanna, 1)

        XCTAssertTrue(store.deleteVisit(visitID: "visit_west"))
        XCTAssertEqual(
            Set(
                store.currentUserCalendarProjection.userPlaces.map(\.id)
            ),
            [wannaUserPlace.id]
        )
        XCTAssertEqual(store.stats.checkIns, 0)
        XCTAssertEqual(store.stats.wanna, 1)

        // A viewport request can finish after the delete RPC. Its stale,
        // partial owner row must not repopulate the canonical Profile slice.
        await store.refreshRemoteVisiblePlaces(
            in: MapViewport(
                minLatitude: 33.9,
                minLongitude: -118.6,
                maxLatitude: 34.1,
                maxLongitude: -118.4
            ),
            backend: WanderBackend(
                placeRepository: FakePlaceRepository(places: [westside])
            )
        )

        XCTAssertEqual(
            Set(
                store.currentUserCalendarProjection.userPlaces.map(\.id)
            ),
            [wannaUserPlace.id]
        )
        XCTAssertEqual(store.stats.checkIns, 0)
        XCTAssertEqual(store.stats.wanna, 1)

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-widget-regions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }
        let snapshotStore = WanderCalendarWidgetSnapshotStore(fileURL: snapshotURL)
        WanderWidgetSnapshotPublisher.publish(
            store: store,
            isAvailable: true,
            now: activityDate,
            snapshotStore: snapshotStore
        )

        let snapshot = try XCTUnwrap(snapshotStore.load())
        XCTAssertEqual(snapshot.currentMonth.beenCount, 0)
        XCTAssertEqual(snapshot.currentMonth.wannaCount, 0)
    }

    func testCurrentUserCalendarRefreshReportsRemoteFailure() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_current", displayName: "Current", handle: "current")
            )
        )

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    error: WanderRemoteError.invalidResponse("network down")
                )
            )
        )

        XCTAssertFalse(hydrated)
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testCurrentUserCalendarProjectionUsesRemoteStatusDateAndDeletionForSyncedRows() async throws {
        let store = WanderStore(fixtures: .seed())
        let remoteSavedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-21T18:30:00Z")
        )
        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_joe_woodcat",
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .wannaGo,
            savedAt: remoteSavedAt
        )
        let startingRevision = store.currentUserCalendarHydrationRevision

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                )
            )
        )

        XCTAssertTrue(hydrated)
        XCTAssertFalse(store.isRefreshingCurrentUserCalendarData)
        XCTAssertEqual(
            store.currentUserCalendarHydrationRevision,
            startingRevision + 1
        )
        let projection = store.currentUserCalendarProjection
        XCTAssertTrue(projection.isAuthoritative)
        XCTAssertEqual(projection.userPlaces.map(\.id), ["up_joe_woodcat"])
        XCTAssertEqual(projection.userPlaces.first?.status, .wannaGo)
        XCTAssertEqual(projection.userPlaces.first?.savedAt, remoteSavedAt)
        XCTAssertFalse(
            projection.userPlaces.contains { $0.id == "up_joe_circuit_coffee" }
        )
    }

    func testCurrentUserCalendarProjectionPreservesPendingLocalMutationOverRemote() async throws {
        let store = WanderStore(fixtures: .seed())
        let pendingSavedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-22T12:00:00Z")
        )
        let remoteSavedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")
        )
        let localWoodcat = try XCTUnwrap(
            store.userPlaces.first { $0.id == "up_joe_woodcat" }
        )
        localWoodcat.statusRaw = PlaceStatus.wannaGo.rawValue
        localWoodcat.savedAt = pendingSavedAt
        localWoodcat.syncStateRaw = SyncState.pendingUpdate.rawValue
        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_joe_woodcat",
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: remoteSavedAt,
            visitedAt: remoteSavedAt
        )

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                )
            )
        )

        XCTAssertTrue(hydrated)
        let projectedWoodcat = try XCTUnwrap(
            store.currentUserCalendarProjection.userPlaces.first {
                $0.id == "up_joe_woodcat"
            }
        )
        XCTAssertTrue(projectedWoodcat === localWoodcat)
        XCTAssertEqual(projectedWoodcat.status, .wannaGo)
        XCTAssertEqual(projectedWoodcat.savedAt, pendingSavedAt)
        XCTAssertEqual(projectedWoodcat.syncState, .pendingUpdate)
        XCTAssertEqual(
            store.currentUserCalendarProjection.userPlaces.filter {
                $0.id == "up_joe_woodcat"
            }.count,
            1
        )
    }

    func testCurrentUserCalendarRefreshUpdatesAndDeletesSyncedVisits() async throws {
        var fixtures = WanderFixtures.seed()
        let originalDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-06-01T10:00:00Z")
        )
        let updatedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-23T20:00:00Z")
        )
        fixtures.placeVisits = [
            LocalPlaceVisit(
                localID: "local_visit_keep",
                serverID: "visit_keep",
                userPlaceID: "up_joe_woodcat",
                visitedAt: originalDate,
                note: "old",
                ratingScore: 2,
                syncState: .synced
            ),
            LocalPlaceVisit(
                localID: "local_visit_remove",
                serverID: "visit_remove",
                userPlaceID: "up_joe_woodcat",
                visitedAt: originalDate,
                note: "deleted remotely",
                syncState: .synced
            ),
            LocalPlaceVisit(
                localID: "local_visit_pending",
                serverID: "visit_pending",
                userPlaceID: "up_joe_woodcat",
                visitedAt: updatedDate,
                note: "pending local edit",
                ratingScore: 4,
                syncState: .pendingUpdate
            )
        ]
        let store = WanderStore(fixtures: fixtures)
        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_joe_woodcat",
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: updatedDate,
            visitedAt: updatedDate
        )

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [
                        "up_joe_woodcat": [
                            PlaceVisitResult(
                                visitID: "visit_keep",
                                userPlaceID: "up_joe_woodcat",
                                visitedAt: updatedDate,
                                note: "updated remotely",
                                ratingScore: 5,
                                tags: ["great table"],
                                backfilledFromUserPlace: false
                            ),
                            PlaceVisitResult(
                                visitID: "visit_pending",
                                userPlaceID: "up_joe_woodcat",
                                visitedAt: originalDate,
                                note: "stale server value",
                                ratingScore: 1,
                                tags: [],
                                backfilledFromUserPlace: false
                            )
                        ]
                    ]
                )
            )
        )

        XCTAssertTrue(hydrated)
        let updatedVisit = try XCTUnwrap(
            store.placeVisits.first { $0.id == "visit_keep" }
        )
        XCTAssertEqual(updatedVisit.localID, "local_visit_keep")
        XCTAssertEqual(updatedVisit.visitedAt, updatedDate)
        XCTAssertEqual(updatedVisit.note, "updated remotely")
        XCTAssertEqual(updatedVisit.ratingScore, 5)
        XCTAssertEqual(updatedVisit.tags, ["great table"])
        XCTAssertNil(store.placeVisits.first { $0.id == "visit_remove" })
        let pendingVisit = try XCTUnwrap(
            store.placeVisits.first { $0.id == "visit_pending" }
        )
        XCTAssertEqual(pendingVisit.note, "pending local edit")
        XCTAssertEqual(pendingVisit.ratingScore, 4)
        XCTAssertEqual(pendingVisit.syncState, .pendingUpdate)
        XCTAssertEqual(
            Set(store.currentUserCalendarProjection.visits.map(\.id)),
            ["visit_keep", "visit_pending"]
        )
    }

    func testCurrentUserCalendarRefreshDoesNotCommitPartialVisitFailure() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_atomic"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userID, displayName: "Atomic", handle: "atomic")
            )
        )
        let originalDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-10T10:00:00Z")
        )
        let changedDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-24T10:00:00Z")
        )
        let originalA = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_atomic_a",
            placeID: "place_atomic_a",
            name: "Atomic A",
            status: .been,
            savedAt: originalDate,
            visitedAt: originalDate
        )
        let originalB = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_atomic_b",
            placeID: "place_atomic_b",
            name: "Atomic B",
            status: .wannaGo,
            savedAt: originalDate
        )
        let initialHydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: [originalA, originalB]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [
                        "up_atomic_a": [
                            PlaceVisitResult(
                                visitID: "visit_atomic_a",
                                userPlaceID: "up_atomic_a",
                                visitedAt: originalDate,
                                note: "original",
                                ratingScore: 3,
                                tags: [],
                                backfilledFromUserPlace: false
                            )
                        ],
                        "up_atomic_b": []
                    ]
                )
            )
        )
        XCTAssertTrue(initialHydrated)
        let successfulRevision = store.currentUserCalendarHydrationRevision

        let changedA = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_atomic_a",
            placeID: "place_atomic_a",
            name: "Atomic A",
            status: .wannaGo,
            savedAt: changedDate
        )
        let changedB = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_atomic_b",
            placeID: "place_atomic_b",
            name: "Atomic B",
            status: .been,
            savedAt: changedDate,
            visitedAt: changedDate
        )
        let failingVisits = FakeVisitRepository(
            visitsByUserPlaceID: [
                "up_atomic_a": [
                    PlaceVisitResult(
                        visitID: "visit_atomic_a",
                        userPlaceID: "up_atomic_a",
                        visitedAt: changedDate,
                        note: "must not commit",
                        ratingScore: 5,
                        tags: [],
                        backfilledFromUserPlace: false
                    )
                ]
            ],
            failingUserPlaceIDs: ["up_atomic_b"]
        )

        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: [changedA, changedB]]
                ),
                visitRepository: failingVisits
            )
        )

        XCTAssertFalse(hydrated)
        XCTAssertFalse(store.isRefreshingCurrentUserCalendarData)
        XCTAssertEqual(
            store.currentUserCalendarHydrationRevision,
            successfulRevision
        )
        XCTAssertEqual(
            failingVisits.visitRequests,
            ["up_atomic_a", "up_atomic_b"]
        )
        let projection = store.currentUserCalendarProjection
        XCTAssertEqual(
            projection.userPlaces.first { $0.id == "up_atomic_a" }?.status,
            .been
        )
        XCTAssertEqual(
            projection.userPlaces.first { $0.id == "up_atomic_b" }?.status,
            .wannaGo
        )
        XCTAssertEqual(
            projection.visits.first { $0.id == "visit_atomic_a" }?.note,
            "original"
        )
    }

    func testCalendarRemoteStateClearsAcrossSignOutAndNextAccount() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userA = "user_private_a"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userA, displayName: "Private A", handle: "private_a")
            )
        )
        let savedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-20T08:00:00Z")
        )
        let attribute = LocalPlaceAttribute(
            localID: "remote_attr_up_private_a_tags",
            serverID: "attr_private_a",
            userPlaceID: "up_private_a",
            questionKey: "coffee_tags",
            valueType: "multi_tag",
            valueJSON: "[\"secret\"]",
            syncState: .synced
        )
        let privatePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_private_a",
            placeID: "place_private_a",
            name: "Private Place",
            status: .been,
            visibility: .selfOnly,
            savedAt: savedAt,
            visitedAt: savedAt,
            attributes: [attribute]
        )
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userA: [privatePlace]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [
                        "up_private_a": [
                            PlaceVisitResult(
                                visitID: "visit_private_a",
                                userPlaceID: "up_private_a",
                                visitedAt: savedAt,
                                note: "private",
                                ratingScore: nil,
                                tags: ["secret"],
                                backfilledFromUserPlace: false
                            )
                        ]
                    ]
                )
            )
        )
        XCTAssertTrue(hydrated)
        XCTAssertEqual(store.remoteVisiblePlaceCache.count, 1)
        XCTAssertTrue(
            store.placeVisits.contains {
                $0.localID.hasPrefix("remote_profile_visit_")
            }
        )
        XCTAssertTrue(
            store.placeAttributes.contains {
                $0.localID.hasPrefix("remote_attr_")
            }
        )

        store.apply(authState: .signedOut)
        XCTAssertTrue(store.remoteVisiblePlaceCache.isEmpty)
        XCTAssertFalse(
            store.placeVisits.contains {
                $0.localID.hasPrefix("remote_profile_visit_")
            }
        )
        XCTAssertFalse(
            store.placeAttributes.contains {
                $0.localID.hasPrefix("remote_attr_")
            }
        )
        XCTAssertTrue(store.currentUserCalendarProjection.visiblePlaces.isEmpty)
        XCTAssertFalse(store.currentUserCalendarProjection.isAuthoritative)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "User B", handle: "user_b")
            )
        )
        XCTAssertEqual(store.currentUser.id, "user_b")
        XCTAssertTrue(store.visiblePlaces().isEmpty)
        XCTAssertFalse(
            store.remoteVisiblePlaceCache.contains {
                $0.owner.id == userA || $0.userPlace.visibility == .selfOnly
            }
        )
    }

    func testCurrentUserRemoteMapCacheSurvivesOfflineRelaunchAndClearsOnSignOut() async throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(
            userID: "user_offline_cache",
            displayName: "Offline User",
            handle: "offline_user"
        )
        let savedAt = Date(timeIntervalSince1970: 1_753_100_000)

        do {
            let store = WanderStore(
                fixtures: WanderFixtures.empty(),
                persistence: fixture.persistence
            )
            store.apply(authState: .signedIn(session))
            let cachedPlace = makeRemoteCalendarVisiblePlace(
                owner: store.currentUser,
                userPlaceID: "up_offline_cache",
                placeID: "place_offline_cache",
                name: "Cached Offline Cafe",
                status: .been,
                visibility: .selfOnly,
                savedAt: savedAt,
                visitedAt: savedAt
            )
            let hydrated = await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(
                    userPlaceRepository: FakeUserPlaceRepository(
                        userPlacesByUserID: [session.userID: [cachedPlace]]
                    )
                )
            )

            XCTAssertTrue(hydrated)
            XCTAssertEqual(store.remoteVisiblePlaceCache.map(\.place.canonicalName), ["Cached Offline Cafe"])
        }

        do {
            let relaunchedStore = WanderStore(
                fixtures: WanderFixtures.empty(),
                persistence: fixture.persistence
            )
            relaunchedStore.apply(
                authState: .offline(session, message: "Saved map available offline")
            )

            XCTAssertEqual(relaunchedStore.currentUser.id, session.userID)
            XCTAssertEqual(
                relaunchedStore.currentUserVisiblePlaces.map(\.place.canonicalName),
                ["Cached Offline Cafe"]
            )
            XCTAssertEqual(relaunchedStore.remoteVisiblePlaceCache.count, 1)

            relaunchedStore.apply(authState: .signedOut)
        }

        let signedOutRelaunch = WanderStore(
            fixtures: WanderFixtures.empty(),
            persistence: fixture.persistence
        )
        XCTAssertTrue(signedOutRelaunch.remoteVisiblePlaceCache.isEmpty)
        XCTAssertFalse(
            signedOutRelaunch.visiblePlaces().contains {
                $0.place.canonicalName == "Cached Offline Cafe"
            }
        )
    }

    func testCalendarRemoteStateClearsOnDirectAccountSwitch() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userA = "user_direct_a"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userA, displayName: "Direct A", handle: "direct_a")
            )
        )
        let privatePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_direct_a",
            placeID: "place_direct_a",
            name: "Direct Private Place",
            status: .wannaGo,
            visibility: .selfOnly,
            savedAt: Date(timeIntervalSince1970: 1_753_000_000)
        )
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userA: [privatePlace]]
                )
            )
        )
        XCTAssertTrue(hydrated)
        XCTAssertFalse(store.remoteVisiblePlaceCache.isEmpty)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_direct_b", displayName: "Direct B", handle: "direct_b")
            )
        )

        XCTAssertEqual(store.currentUser.id, "user_direct_b")
        XCTAssertTrue(store.remoteVisiblePlaceCache.isEmpty)
        XCTAssertFalse(store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertFalse(
            store.visiblePlaces().contains { $0.owner.id == userA }
        )
    }

    func testConcurrentCurrentUserCalendarRefreshesShareSingleFlight() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_single_flight"
        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: userID,
                    displayName: "Single Flight",
                    handle: "single_flight"
                )
            )
        )
        let remotePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_single_flight",
            placeID: "place_single_flight",
            name: "Single Flight Cafe",
            status: .wannaGo,
            savedAt: Date(timeIntervalSince1970: 1_753_000_000)
        )
        let repository = DeferredCalendarUserPlaceRepository(result: [remotePlace])
        let backend = WanderBackend(userPlaceRepository: repository)

        let first = Task { @MainActor in
            await store.refreshRemoteCurrentUserCalendarData(backend: backend)
        }
        for _ in 0..<20 where repository.userPlaceRequests.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(repository.userPlaceRequests, [userID])
        XCTAssertTrue(store.isRefreshingCurrentUserCalendarData)

        let second = Task { @MainActor in
            await store.refreshRemoteCurrentUserCalendarData(backend: backend)
        }
        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertEqual(repository.userPlaceRequests, [userID])

        repository.finish()
        let firstResult = await first.value
        let secondResult = await second.value

        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(repository.userPlaceRequests, [userID])
        XCTAssertFalse(store.isRefreshingCurrentUserCalendarData)
        XCTAssertEqual(store.currentUserCalendarHydrationRevision, 1)
    }

    func testCurrentUserCalendarRefreshRejectsDeferredResponseAfterPendingVisitMutation() async throws {
        let store = WanderStore(fixtures: .seed())
        let userPlace = try XCTUnwrap(
            store.userPlaces.first { $0.id == "up_joe_woodcat" }
        )
        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: userPlace.id,
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: Date(timeIntervalSince1970: 1_753_000_000),
            visitedAt: Date(timeIntervalSince1970: 1_753_000_000)
        )
        let deferredVisits = FakeVisitRepository(
            visitsByUserPlaceID: [userPlace.id: []],
            suspendedUserPlaceIDs: [userPlace.id]
        )
        let startingRevision = store.currentUserCalendarHydrationRevision
        let refresh = Task { @MainActor in
            await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(
                    userPlaceRepository: FakeUserPlaceRepository(
                        userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                    ),
                    visitRepository: deferredVisits
                )
            )
        }
        for _ in 0..<20 where deferredVisits.visitRequests.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(deferredVisits.visitRequests, [userPlace.id])

        let pendingVisit = try XCTUnwrap(
            store.createVisit(
                userPlaceID: userPlace.id,
                visitedAt: Date(timeIntervalSince1970: 1_753_086_400),
                note: "Created while calendar hydration was pending",
                ratingScore: 5
            )
        )
        deferredVisits.finishVisits(for: userPlace.id)

        let refreshResult = await refresh.value
        XCTAssertFalse(refreshResult)
        XCTAssertEqual(
            store.currentUserCalendarHydrationRevision,
            startingRevision
        )
        XCTAssertNil(store.lastRemoteError)
        XCTAssertEqual(pendingVisit.syncState, .pendingCreate)
        XCTAssertTrue(
            store.placeVisits.contains { $0.localID == pendingVisit.localID }
        )
        XCTAssertFalse(store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertTrue(
            store.currentUserCalendarProjection.visits.contains {
                $0.localID == pendingVisit.localID
            }
        )
    }

    func testDirtySyntheticCalendarVisitRejectsDeferredHydrationAndPreservesLocalEdit() async throws {
        let store = WanderStore(fixtures: .seed())
        let userPlaceID = "up_joe_woodcat"
        let visitID = "visit_synthetic_deferred_edit"
        let visitedAt = Date(timeIntervalSince1970: 1_753_000_000)
        let staleVisit = PlaceVisitResult(
            visitID: visitID,
            userPlaceID: userPlaceID,
            visitedAt: visitedAt,
            note: "Stale remote note",
            ratingScore: 3,
            tags: [],
            backfilledFromUserPlace: false
        )
        let remoteWoodcat = await hydrateSyntheticCalendarVisits(
            in: store,
            userPlaceID: userPlaceID,
            results: [staleVisit]
        )
        let syntheticVisit = try XCTUnwrap(
            store.placeVisits.first { $0.serverID == visitID }
        )
        XCTAssertTrue(syntheticVisit.localID.hasPrefix("remote_profile_visit_"))
        XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
        let acceptedRevision = store.currentUserCalendarHydrationRevision

        let deferredVisits = FakeVisitRepository(
            visitsByUserPlaceID: [userPlaceID: [staleVisit]],
            suspendedUserPlaceIDs: [userPlaceID]
        )
        let staleRefresh = Task { @MainActor in
            await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(
                    userPlaceRepository: FakeUserPlaceRepository(
                        userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                    ),
                    visitRepository: deferredVisits
                )
            )
        }
        for _ in 0..<20 where deferredVisits.visitRequests.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(deferredVisits.visitRequests, [userPlaceID])

        let editedVisit = try XCTUnwrap(
            store.updateVisit(
                visitID: visitID,
                note: "Local note written during hydration",
                replacesNote: true
            )
        )
        XCTAssertEqual(editedVisit.syncState, .pendingUpdate)
        XCTAssertFalse(store.currentUserCalendarProjection.isAuthoritative)

        deferredVisits.finishVisits(for: userPlaceID)
        let refreshResult = await staleRefresh.value

        XCTAssertFalse(refreshResult)
        XCTAssertEqual(
            store.currentUserCalendarHydrationRevision,
            acceptedRevision
        )
        let preservedVisit = try XCTUnwrap(
            store.placeVisits.first { $0.serverID == visitID }
        )
        XCTAssertEqual(preservedVisit.localID, syntheticVisit.localID)
        XCTAssertEqual(preservedVisit.note, "Local note written during hydration")
        XCTAssertEqual(preservedVisit.syncState, .pendingUpdate)
        XCTAssertTrue(
            store.currentUserCalendarProjection.visits.contains {
                $0.localID == preservedVisit.localID
            }
        )
    }

    func testAccountSwitchPreservesDirtySyntheticCalendarVisitAndClearsCleanRemoteRows() async throws {
        let store = WanderStore(fixtures: .seed())
        let userPlaceID = "up_joe_woodcat"
        let dirtyVisitID = "visit_synthetic_dirty_account_switch"
        let cleanVisitID = "visit_synthetic_clean_account_switch"
        let visitedAt = Date(timeIntervalSince1970: 1_753_000_000)
        _ = await hydrateSyntheticCalendarVisits(
            in: store,
            userPlaceID: userPlaceID,
            results: [
                PlaceVisitResult(
                    visitID: dirtyVisitID,
                    userPlaceID: userPlaceID,
                    visitedAt: visitedAt,
                    note: "Remote note to edit",
                    ratingScore: 4,
                    tags: [],
                    backfilledFromUserPlace: false
                ),
                PlaceVisitResult(
                    visitID: cleanVisitID,
                    userPlaceID: userPlaceID,
                    visitedAt: visitedAt.addingTimeInterval(-86_400),
                    note: "Clean remote note",
                    ratingScore: 3,
                    tags: [],
                    backfilledFromUserPlace: false
                )
            ]
        )
        let editedVisit = try XCTUnwrap(
            store.updateVisit(
                visitID: dirtyVisitID,
                note: "Unsynced note that must survive",
                replacesNote: true
            )
        )
        XCTAssertTrue(editedVisit.localID.hasPrefix("remote_profile_visit_"))
        XCTAssertEqual(editedVisit.syncState, .pendingUpdate)

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_after_synthetic_edit",
                    displayName: "Next User",
                    handle: "next_user"
                )
            )
        )

        let preservedVisit = try XCTUnwrap(
            store.placeVisits.first { $0.serverID == dirtyVisitID }
        )
        XCTAssertEqual(preservedVisit.note, "Unsynced note that must survive")
        XCTAssertEqual(preservedVisit.syncState, .pendingUpdate)
        XCTAssertNil(
            store.placeVisits.first { $0.serverID == cleanVisitID }
        )
        XCTAssertTrue(store.remoteVisiblePlaceCache.isEmpty)
    }

    func testCalendarVisitDedupeUsesAuthorityAwareLocalAndSyntheticPrecedence() async throws {
        var fixtures = WanderFixtures.seed()
        let visitID = "visit_calendar_dedupe_precedence"
        let visitedAt = Date(timeIntervalSince1970: 1_753_000_000)
        let syntheticVisit = LocalPlaceVisit(
            localID: "remote_profile_visit_\(visitID)",
            serverID: visitID,
            userPlaceID: "up_joe_woodcat",
            visitedAt: visitedAt,
            note: "Authoritative remote value",
            ratingScore: 2,
            syncState: .synced
        )
        let localVisit = LocalPlaceVisit(
            localID: "local_visit_calendar_dedupe_precedence",
            serverID: visitID,
            userPlaceID: "up_joe_woodcat",
            visitedAt: visitedAt.addingTimeInterval(86_400),
            note: "Newly synced local value",
            ratingScore: 5,
            syncState: .synced
        )
        fixtures.placeVisits = [syntheticVisit, localVisit]
        let store = WanderStore(fixtures: fixtures)

        let nonAuthoritativeMatches = store.currentUserCalendarProjection.visits.filter {
            $0.serverID == visitID
        }
        XCTAssertFalse(store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertEqual(nonAuthoritativeMatches.count, 1)
        XCTAssertEqual(
            nonAuthoritativeMatches.first?.localID,
            localVisit.localID
        )
        XCTAssertEqual(
            nonAuthoritativeMatches.first?.note,
            "Newly synced local value"
        )

        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_joe_woodcat",
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: visitedAt,
            visitedAt: visitedAt
        )
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                )
            )
        )

        XCTAssertTrue(hydrated)
        let authoritativeMatches = store.currentUserCalendarProjection.visits.filter {
            $0.serverID == visitID
        }
        XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertEqual(authoritativeMatches.count, 1)
        XCTAssertEqual(
            authoritativeMatches.first?.localID,
            syntheticVisit.localID
        )
        XCTAssertEqual(
            authoritativeMatches.first?.note,
            "Authoritative remote value"
        )
    }

    func testCurrentUserCalendarRefreshRejectsDeferredResponseAfterPlaceAndVisitSyncComplete() async throws {
        var fixtures = WanderFixtures.seed()
        let localUserPlace = try XCTUnwrap(
            fixtures.userPlaces.first { $0.id == "up_joe_woodcat" }
        )
        localUserPlace.syncStateRaw = SyncState.pendingUpdate.rawValue
        let localVisit = LocalPlaceVisit(
            localID: "local_visit_calendar_sync_race",
            serverID: "visit_calendar_sync_race",
            userPlaceID: localUserPlace.id,
            visitedAt: Date(timeIntervalSince1970: 1_753_000_000),
            note: "Local synced value must survive",
            ratingScore: 5,
            syncState: .pendingUpdate
        )
        fixtures.placeVisits = [localVisit]
        let store = WanderStore(fixtures: fixtures)
        let staleVisit = PlaceVisitResult(
            visitID: "visit_calendar_sync_race",
            userPlaceID: localUserPlace.id,
            visitedAt: Date(timeIntervalSince1970: 1_752_000_000),
            note: "Stale remote value",
            ratingScore: 1,
            tags: [],
            backfilledFromUserPlace: false
        )
        let remoteWoodcat = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: localUserPlace.id,
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: Date(timeIntervalSince1970: 1_752_000_000),
            visitedAt: staleVisit.visitedAt
        )

        let initialHydration = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [localUserPlace.id: [staleVisit]]
                )
            )
        )
        XCTAssertTrue(initialHydration)
        XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
        let acceptedRevision = store.currentUserCalendarHydrationRevision

        let deferredVisits = FakeVisitRepository(
            visitsByUserPlaceID: [localUserPlace.id: [staleVisit]],
            suspendedUserPlaceIDs: [localUserPlace.id]
        )
        let staleRefresh = Task { @MainActor in
            await store.refreshRemoteCurrentUserCalendarData(
                backend: WanderBackend(
                    userPlaceRepository: FakeUserPlaceRepository(
                        userPlacesByUserID: [store.currentUser.id: [remoteWoodcat]]
                    ),
                    visitRepository: deferredVisits
                )
            )
        }
        for _ in 0..<20 where deferredVisits.visitRequests.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(deferredVisits.visitRequests, [localUserPlace.id])

        let syncedCount = await store.syncUnsyncedOwnPlaces(
            backend: WanderBackend(
                placeRepository: FakePlaceRepository(places: [remoteWoodcat]),
                userPlaceRepository: FakeUserPlaceRepository(
                    result: SaveResult(
                        userPlaceID: localUserPlace.id,
                        syncState: .synced,
                        placeID: "place_woodcat"
                    )
                ),
                visitRepository: FakeVisitRepository()
            )
        )
        XCTAssertEqual(syncedCount, 1)
        deferredVisits.finishVisits(for: localUserPlace.id)

        let staleRefreshResult = await staleRefresh.value
        XCTAssertFalse(staleRefreshResult)
        XCTAssertEqual(
            store.currentUserCalendarHydrationRevision,
            acceptedRevision
        )
        XCTAssertNil(store.lastRemoteError)
        XCTAssertEqual(
            store.userPlaces.first { $0.localID == localUserPlace.localID }?.syncState,
            .synced
        )
        let preservedVisit = try XCTUnwrap(
            store.placeVisits.first { $0.localID == localVisit.localID }
        )
        XCTAssertEqual(preservedVisit.syncState, .synced)
        XCTAssertEqual(preservedVisit.note, "Local synced value must survive")
        let projection = store.currentUserCalendarProjection
        XCTAssertFalse(projection.isAuthoritative)
        XCTAssertTrue(
            projection.userPlaces.contains {
                $0.localID == localUserPlace.localID
            }
        )
        XCTAssertTrue(
            projection.visits.contains {
                $0.localID == localVisit.localID
            }
        )
    }

    private func makeRemoteCalendarVisiblePlace(
        owner: LocalProfile,
        userPlaceID: String,
        placeID: String,
        name: String,
        status: PlaceStatus,
        visibility: PlaceVisibility = .selfOnly,
        savedAt: Date,
        visitedAt: Date? = nil,
        attributes: [LocalPlaceAttribute] = []
    ) -> VisiblePlace {
        let place = LocalPlace(
            localID: "remote_\(placeID)",
            serverID: placeID,
            canonicalName: name,
            category: "coffee",
            latitude: 34.02,
            longitude: -118.49,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: placeID,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "remote_\(userPlaceID)",
            serverID: userPlaceID,
            userID: owner.id,
            placeID: place.id,
            status: status,
            visibility: visibility,
            visitedAt: visitedAt,
            savedAt: savedAt,
            sourceType: "manual",
            syncState: .synced
        )
        return VisiblePlace(
            id: userPlace.id,
            place: place,
            userPlace: userPlace,
            owner: owner,
            attributes: attributes
        )
    }

    private func hydrateSyntheticCalendarVisits(
        in store: WanderStore,
        userPlaceID: String,
        results: [PlaceVisitResult]
    ) async -> VisiblePlace {
        let savedAt = results.map(\.visitedAt).max()
            ?? Date(timeIntervalSince1970: 1_753_000_000)
        let remotePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: userPlaceID,
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            savedAt: savedAt,
            visitedAt: savedAt
        )
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [store.currentUser.id: [remotePlace]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [userPlaceID: results]
                )
            )
        )
        XCTAssertTrue(hydrated)
        return remotePlace
    }

    private func makeStore() -> WanderStore {
        WanderStore(fixtures: WanderFixtures.seed())
    }

    private func makeJadeRabbitMultipleResolutionFixture() -> WanderFixtures {
        let currentUser = LocalProfile(
            localID: "local_profile_jade_tester",
            serverID: "user_jade_tester",
            handle: "jade_tester",
            displayName: "Jade Tester",
            syncState: .synced
        )
        let firstPlaceID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let secondPlaceID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let firstUserPlaceID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        let secondUserPlaceID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let listID = "11111111-1111-4111-8111-111111111111"
        let createdAt = Date(timeIntervalSince1970: 1_775_000_000)
        let firstPlace = LocalPlace(
            localID: "local_place_jade_rabbit_first",
            serverID: firstPlaceID,
            canonicalName: "Jade Rabbit",
            category: "bar",
            address: "1518 NW 22nd Avenue",
            locality: "Portland",
            region: "OR",
            country: "US",
            latitude: 45.5332,
            longitude: -122.6964,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "jade-rabbit-resolution-a",
            syncState: .synced,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let secondPlace = LocalPlace(
            localID: "local_place_jade_rabbit_second",
            serverID: secondPlaceID,
            canonicalName: "Jade Rabbit",
            category: "cocktail bar",
            address: "1518 NW 22nd Ave.",
            locality: "Portland",
            region: "OR",
            country: "US",
            latitude: 45.5333,
            longitude: -122.6965,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "jade-rabbit-resolution-b",
            syncState: .synced,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let firstUserPlace = LocalUserPlace(
            localID: "local_user_place_jade_rabbit_first",
            serverID: firstUserPlaceID,
            userID: currentUser.id,
            placeID: firstPlaceID,
            status: .been,
            visibility: .followers,
            savedAt: createdAt,
            sourceType: AddSourceType.manual.rawValue,
            syncState: .synced,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let secondUserPlace = LocalUserPlace(
            localID: "local_user_place_jade_rabbit_second",
            serverID: secondUserPlaceID,
            userID: currentUser.id,
            placeID: secondPlaceID,
            status: .been,
            visibility: .followers,
            savedAt: createdAt,
            sourceType: AddSourceType.manual.rawValue,
            syncState: .synced,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let list = LocalPlaceList(
            localID: "remote_list_\(listID)",
            serverID: listID,
            ownerUserID: currentUser.id,
            name: "Portland drinks",
            description: "Jade Rabbit provider resolution regression",
            visibility: .followers,
            syncState: .synced,
            cachedItemCount: 2,
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let items = [
            LocalPlaceListItem(
                localID: "remote_list_item_jade_rabbit_first",
                serverID: "22222222-2222-4222-8222-222222222222",
                listID: listID,
                placeID: firstPlaceID,
                ownerUserPlaceID: firstUserPlaceID,
                sourceUserPlaceID: firstUserPlaceID,
                addedByUserID: currentUser.id,
                syncState: .synced,
                createdAt: createdAt,
                updatedAt: createdAt
            ),
            LocalPlaceListItem(
                localID: "remote_list_item_jade_rabbit_second",
                serverID: "33333333-3333-4333-8333-333333333333",
                listID: listID,
                placeID: secondPlaceID,
                ownerUserPlaceID: secondUserPlaceID,
                sourceUserPlaceID: secondUserPlaceID,
                addedByUserID: currentUser.id,
                syncState: .synced,
                createdAt: createdAt.addingTimeInterval(1),
                updatedAt: createdAt.addingTimeInterval(1)
            )
        ]

        return WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser],
            places: [firstPlace, secondPlace],
            userPlaces: [firstUserPlace, secondUserPlace],
            placeAttributes: [],
            follows: [],
            blocks: [],
            placeLists: [list],
            placeListMembers: [],
            placeListItems: items,
            contactProvider: FakeContactProvider(seededMatches: [])
        )
    }

    private func makeRemoteCollaboratorListStore() -> (WanderStore, LocalPlaceList) {
        let seed = WanderFixtures.seed()
        let listID = "11111111-1111-4111-8111-111111111111"
        let list = LocalPlaceList(
            localID: "remote_list_\(listID)",
            serverID: listID,
            ownerUserID: "user_ryan",
            name: "Shared follower list",
            description: "The former collaborator should see this through normal friend visibility.",
            visibility: .followers,
            syncState: .synced
        )
        let store = WanderStore(fixtures: WanderFixtures(
            currentUser: seed.currentUser,
            profiles: seed.profiles,
            places: [],
            userPlaces: [],
            placeAttributes: [],
            follows: seed.follows,
            blocks: [],
            placeLists: [list],
            placeListMembers: [
                LocalPlaceListMember(
                    localID: "remote_list_member_\(listID)_user_joe",
                    listID: listID,
                    userID: seed.currentUser.id,
                    role: .collaborator
                )
            ],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        ))
        return (store, store.placeLists[0])
    }

    private func makeSharedVisitInvitation(
        participantID: String = "participant-1",
        generation: Int = 1,
        attributeAnswers: [VisitAttributeAnswer] = [],
        note: String? = "Great table",
        ratingScore: Double? = 4,
        tags: [String] = ["group drinks"],
        photos: [SharedVisitPhotoSnapshot] = []
    ) -> SharedVisitInvitation {
        SharedVisitInvitation(
            participantID: participantID,
            groupID: "group-1",
            invitationGeneration: generation,
            snapshotRevision: 1,
            status: .pending,
            invitedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sourceVisitID: "source-visit-1",
            sourceOwnerUserID: "user_ryan",
            sourceOwnerHandle: "ryan",
            sourceOwnerDisplayName: "Ryan",
            sourceOwnerAvatarURL: nil,
            placeID: "place-1",
            placeName: "RVR",
            category: "restaurant",
            primaryCategory: "restaurant",
            subcategory: "Italian",
            address: "1 Main Street",
            locality: "Los Angeles",
            region: "CA",
            country: "US",
            latitude: 34.0,
            longitude: -118.0,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit-rvr",
            visitedAt: Date(timeIntervalSince1970: 1_720_000_000),
            note: note,
            ratingScore: ratingScore,
            attributeAnswers: attributeAnswers,
            tags: tags,
            photos: photos
        )
    }

    private func makeStoreWithStaleBlockedGraph() -> WanderStore {
        let joe = LocalProfile(
            localID: "local_profile_joe",
            serverID: "user_joe",
            handle: "joe",
            displayName: "Joe",
            syncState: .synced
        )
        let ryan = LocalProfile(
            localID: "local_profile_ryan",
            serverID: "user_ryan",
            handle: "ryan",
            displayName: "Ryan",
            syncState: .synced
        )

        return WanderStore(
            fixtures: WanderFixtures(
                currentUser: joe,
                profiles: [joe, ryan],
                places: [],
                userPlaces: [],
                placeAttributes: [],
                follows: [
                    LocalFollow(
                        localID: "local_follow_joe_ryan",
                        serverID: "follow_joe_ryan",
                        followerUserID: joe.id,
                        followedUserID: ryan.id,
                        source: .profile,
                        syncState: .synced
                    ),
                    LocalFollow(
                        localID: "local_follow_ryan_joe",
                        serverID: "follow_ryan_joe",
                        followerUserID: ryan.id,
                        followedUserID: joe.id,
                        source: .profile,
                        syncState: .synced
                    )
                ],
                blocks: [
                    LocalBlock(
                        localID: "local_block_joe_ryan",
                        serverID: "block_joe_ryan",
                        blockerUserID: joe.id,
                        blockedUserID: ryan.id,
                        syncState: .synced
                    )
                ],
                placeLists: [],
                placeListMembers: [],
                placeListItems: [],
                contactProvider: FakeContactProvider(seededMatches: [])
            )
        )
    }

    func testStealthSavesKeepOwnerActivityAfterRelaunchAndPrivateProfileChanges() throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = WanderStore(fixtures: .empty(), persistence: fixture.persistence)
        let cache = ProfilePresentationCache()
        store.defaultVisibility = .visibilityForStealthMode(isPrivate: true)
        let wanna = store.saveCandidate(
            PlaceCandidate(id: "stealth-wanna", name: "Private Wanna", category: "coffee", latitude: 34, longitude: -118, confidence: 1),
            status: .wannaGo, visibility: store.effectiveDefaultVisibility, note: "private", sourceType: .manual
        )
        let been = store.saveCandidate(
            PlaceCandidate(id: "stealth-been", name: "Private Check-In", category: "restaurant", latitude: 35, longitude: -119, confidence: 1),
            status: .been, visibility: store.effectiveDefaultVisibility, note: "private", sourceType: .manual
        )
        XCTAssertNotNil(store.createVisit(userPlaceID: been.userPlaceID))

        func assertHistory(_ candidateStore: WanderStore, using presentationCache: ProfilePresentationCache) {
            let presentation = presentationCache.present(store: candidateStore, profileID: candidateStore.currentUser.id)
            XCTAssertEqual(presentation.activityItems.filter { $0.kind == .wanna }.count, 1)
            XCTAssertEqual(presentation.activityItems.filter { $0.kind == .checkIn }.count, 2)
            XCTAssertEqual(Set(presentation.activityItems.map { $0.visiblePlace.userPlace.id }), [wanna.userPlaceID, been.userPlaceID])
            XCTAssertTrue(presentation.activityItems.allSatisfy { $0.visiblePlace.userPlace.visibility == .selfOnly })
        }
        assertHistory(store, using: cache)
        store.setPrivateProfile(true)
        assertHistory(store, using: cache)
        store.setPrivateProfile(false)
        assertHistory(store, using: cache)

        let relaunched = WanderStore(fixtures: .empty(), persistence: fixture.persistence)
        assertHistory(relaunched, using: ProfilePresentationCache())
    }

    func testRemoteStealthCalendarRetainsOwnerProfileActivity() async {
        let store = WanderStore(fixtures: .empty())
        store.apply(authState: .signedIn(AuthSession(userID: "stealth_owner", displayName: "Owner", handle: "owner")))
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let wanna = makeRemoteCalendarVisiblePlace(owner: store.currentUser, userPlaceID: "stealth_wanna", placeID: "wanna_place", name: "Private Wanna", status: .wannaGo, visibility: .selfOnly, savedAt: date)
        let been = makeRemoteCalendarVisiblePlace(owner: store.currentUser, userPlaceID: "stealth_been", placeID: "been_place", name: "Private Check-In", status: .been, visibility: .selfOnly, savedAt: date, visitedAt: date)
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(backend: WanderBackend(
            userPlaceRepository: FakeUserPlaceRepository(userPlacesByUserID: [store.currentUser.id: [wanna, been]]),
            visitRepository: FakeVisitRepository(visitsByUserPlaceID: [been.id: [
                PlaceVisitResult(visitID: "stealth_visit", userPlaceID: been.id, visitedAt: date, note: nil, ratingScore: nil, tags: [], backfilledFromUserPlace: false)
            ]])
        ))
        XCTAssertTrue(hydrated)
        let presentation = ProfilePresentationCache().present(store: store, profileID: store.currentUser.id)
        XCTAssertEqual(presentation.activityItems.count, 2)
        XCTAssertEqual(presentation.stats.wanna, 1)
        XCTAssertEqual(presentation.stats.checkIns, 1)
        XCTAssertEqual(presentation.activityItems.first { $0.kind == .checkIn }?.visitID, "stealth_visit")
    }

    func testRemoteStealthSaveIsExcludedFromOtherProfileAndPlaceCardInputs() async {
        let store = WanderStore(fixtures: .empty())
        let owner = LocalProfile(localID: "other_stealth_owner", handle: "other", displayName: "Other")
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let stealth = makeRemoteCalendarVisiblePlace(owner: owner, userPlaceID: "private_save", placeID: "private_place", name: "Private", status: .been, visibility: .selfOnly, savedAt: date, visitedAt: date)
        let shared = makeRemoteCalendarVisiblePlace(owner: owner, userPlaceID: "shared_save", placeID: "shared_place", name: "Shared", status: .wannaGo, visibility: .followers, savedAt: date)
        await store.refreshRemoteProfileVisiblePlaces(profileID: owner.id, backend: WanderBackend(
            userPlaceRepository: FakeUserPlaceRepository(userPlacesByUserID: [owner.id: [stealth, shared]])
        ))
        XCTAssertEqual(store.visiblePlaces().map(\.id), [shared.id])
        XCTAssertEqual(store.visiblePlaces(for: owner.id).map(\.id), [shared.id])
        XCTAssertEqual(store.visiblePlaceGroups().flatMap(\.places).map(\.id), [shared.id])
        let presentation = ProfilePresentationCache().present(store: store, profileID: owner.id)
        XCTAssertEqual(presentation.activityItems.map { $0.visiblePlace.id }, [shared.id])
        XCTAssertEqual(presentation.stats.checkIns, 0)
    }

    private func makeTemporaryPersistence() -> (persistence: WanderStorePersistence, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-store-tests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("store.json")
        return (WanderStorePersistence.file(url: url), directory)
    }

    func testEmptyFixturesStartWithoutDemoPeopleOrPlaces() {
        let store = WanderStore(fixtures: WanderFixtures.empty())

        XCTAssertEqual(store.currentUser.displayName, "You")
        XCTAssertTrue(store.visiblePlaces().isEmpty)
        XCTAssertEqual(store.following(of: store.currentUser.id), [])
        XCTAssertEqual(store.followers(of: store.currentUser.id), [])
    }

    func testSignedInSessionUpdatesCurrentProfileShell() {
        let store = WanderStore(fixtures: WanderFixtures.empty())

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: nil,
                    handle: nil,
                    email: "jolipshutz@gmail.com"
                )
            )
        )

        XCTAssertEqual(store.currentUser.id, "user_live")
        XCTAssertEqual(store.currentUser.handle, "jolipshutz")
        XCTAssertEqual(store.currentUser.displayName, "jolipshutz@gmail.com")
        XCTAssertEqual(store.profiles.map(\.id), ["user_live"])
    }

    func testCurrentUserAvatarURLUpdatesProfileShellWithoutPendingSync() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let initialPendingCount = store.pendingSyncCount
        let initialSyncState = store.currentUser.syncState
        let avatarURL = "file:///tmp/wander-avatar.jpg"

        store.updateCurrentUserAvatarURL(avatarURL)

        XCTAssertEqual(store.currentUser.avatarURL, avatarURL)
        XCTAssertEqual(store.profileState(for: store.currentUser.id)?.shell.avatarURL, avatarURL)
        XCTAssertEqual(store.profiles.first?.avatarURL, avatarURL)
        XCTAssertEqual(store.currentUser.syncState, initialSyncState)
        XCTAssertEqual(store.pendingSyncCount, initialPendingCount)

        store.updateCurrentUserAvatarURL(nil)

        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.profileState(for: store.currentUser.id)?.shell.avatarURL)
        XCTAssertEqual(store.pendingSyncCount, initialPendingCount)
    }

    func testSignedInSessionDoesNotInheritSignedOutDeviceAvatarURL() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let avatarURL = "file:///tmp/wander-avatar.jpg"
        store.updateCurrentUserAvatarURL(avatarURL)

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Joe",
                    handle: "joe",
                    email: "joe@example.com"
                )
            )
        )

        XCTAssertEqual(store.currentUser.id, "user_live")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.profileState(for: "user_live")?.shell.avatarURL)
        XCTAssertEqual(store.currentUser.syncState, .synced)
    }

    func testSignedOutAndAccountSwitchClearPersonMetadata() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Account A", handle: "account_a")
            )
        )
        store.updateCurrentUserAvatarURL("https://example.com/account-a.jpg")
        store.updateCurrentUserProfile(
            displayName: "Account A",
            handle: "account_a",
            bio: "Account A bio",
            homeArea: "Los Angeles"
        )
        store.defaultVisibility = .selfOnly
        store.setPrivateProfile(true)

        store.apply(authState: .signedOut)

        XCTAssertEqual(store.currentUser.displayName, "You")
        XCTAssertEqual(store.currentUser.handle, "you")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.currentUser.bio)
        XCTAssertNil(store.currentUser.homeArea)
        XCTAssertFalse(store.currentUser.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .followers)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "Account B", handle: "account_b")
            )
        )

        XCTAssertEqual(store.currentUser.id, "user_b")
        XCTAssertEqual(store.currentUser.displayName, "Account B")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.currentUser.bio)
        XCTAssertNil(store.currentUser.homeArea)
        XCTAssertTrue(store.currentUser.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .selfOnly)
    }

    func testPersistedAccountMetadataAndSocialGraphDoNotCrossAccounts() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Account A", handle: "account_a")
            )
        )
        firstStore.updateCurrentUserAvatarURL("https://example.com/account-a.jpg")
        firstStore.updateCurrentUserProfile(
            displayName: "Account A",
            handle: "account_a",
            bio: "Account A bio",
            homeArea: "Los Angeles"
        )
        firstStore.follow(userID: "user_maya")
        firstStore.block(userID: "user_ryan")

        let relaunchedStore = WanderStore(
            fixtures: WanderFixtures.empty(),
            persistence: fixture.persistence
        )
        relaunchedStore.apply(authState: .signedOut)
        relaunchedStore.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "Account B", handle: "account_b")
            )
        )

        XCTAssertEqual(relaunchedStore.currentUser.id, "user_b")
        XCTAssertNil(relaunchedStore.currentUser.avatarURL)
        XCTAssertNil(relaunchedStore.currentUser.bio)
        XCTAssertNil(relaunchedStore.currentUser.homeArea)
        XCTAssertTrue(relaunchedStore.following(of: "user_b").isEmpty)
        XCTAssertTrue(relaunchedStore.blockedProfiles().isEmpty)
        XCTAssertTrue(relaunchedStore.searchProfiles(handleQuery: "account_a").isEmpty)
    }

    func testLateProfileResponseCannotOverwriteNewAccount() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Account A", handle: "account_a")
            )
        )
        let repository = FakeProfileRepository(
            currentProfile: LocalProfile(
                localID: "profile_a",
                serverID: "user_a",
                handle: "account_a",
                displayName: "Account A",
                avatarURL: "https://example.com/account-a.jpg",
                bio: "Account A bio",
                homeArea: "Los Angeles",
                syncState: .synced
            ),
            suspendCurrentProfile: true
        )
        let refresh = Task { @MainActor in
            await store.refreshRemoteCurrentProfile(
                backend: WanderBackend(profileRepository: repository)
            )
        }
        while repository.currentProfileRequestCount == 0 {
            await Task.yield()
        }

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "Account B", handle: "account_b")
            )
        )
        refresh.cancel()
        repository.resumeCurrentProfile()

        let didApplyProfile = await refresh.value
        XCTAssertFalse(didApplyProfile)
        XCTAssertEqual(store.currentUser.id, "user_b")
        XCTAssertEqual(store.currentUser.displayName, "Account B")
        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.currentUser.bio)
        XCTAssertNil(store.currentUser.homeArea)
    }

    func testSignedInSessionRefreshPreservesPersistedAppOwnedIdentityForSameUser() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let clerkSession = AuthSession(
            userID: "user_live",
            displayName: "Old Clerk Name",
            handle: "old_clerk_handle",
            email: "user@example.com"
        )
        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(clerkSession))
        firstStore.updateCurrentUserProfile(displayName: "Ryan Tester", handle: "ryan_tester")

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        relaunchedStore.apply(authState: .signedIn(clerkSession))

        XCTAssertEqual(relaunchedStore.currentUser.displayName, "Ryan Tester")
        XCTAssertEqual(relaunchedStore.currentUser.handle, "ryan_tester")

        relaunchedStore.apply(
            authState: .signedIn(
                AuthSession(userID: "user_other", displayName: "Other User", handle: "other_user")
            )
        )
        XCTAssertEqual(relaunchedStore.currentUser.displayName, "Other User")
        XCTAssertEqual(relaunchedStore.currentUser.handle, "other_user")
    }

    func testRemoteCurrentProfileHydratesAvatarURLWithoutPendingSync() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Local Joe",
                    handle: "localjoe",
                    email: "joe@example.com"
                )
            )
        )
        let initialPendingCount = store.pendingSyncCount
        let remoteAvatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_live/avatar.jpg?v=remote"
        let profileRepository = FakeProfileRepository(
            currentProfile: LocalProfile(
                localID: "local_profile_current",
                serverID: "user_live",
                handle: "joe",
                displayName: "Joe",
                avatarURL: remoteAvatarURL,
                bio: "places worth returning to",
                homeArea: "Los Angeles",
                defaultVisibility: .mutuals,
                syncState: .synced
            )
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        _ = await store.refreshRemoteCurrentProfile(backend: backend)

        XCTAssertEqual(store.currentUser.id, "user_live")
        XCTAssertEqual(store.currentUser.handle, "joe")
        XCTAssertEqual(store.currentUser.avatarURL, remoteAvatarURL)
        XCTAssertEqual(store.currentUser.defaultVisibility, .mutuals)
        XCTAssertEqual(store.profileState(for: "user_live")?.shell.avatarURL, remoteAvatarURL)
        XCTAssertEqual(store.pendingSyncCount, initialPendingCount)
    }

    func testSignInDoesNotCarryGuestAvatarWhenRemoteOmitsAvatar() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let localAvatarURL = "file:///tmp/wander-avatar.jpg"
        store.updateCurrentUserAvatarURL(localAvatarURL)
        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Local Joe",
                    handle: "localjoe",
                    email: "joe@example.com"
                )
            )
        )
        let profileRepository = FakeProfileRepository(
            currentProfile: LocalProfile(
                localID: "local_profile_current",
                serverID: "user_live",
                handle: "joe",
                displayName: "Joe",
                avatarURL: nil,
                bio: "places worth returning to",
                homeArea: "Los Angeles",
                defaultVisibility: .mutuals,
                syncState: .synced
            )
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        _ = await store.refreshRemoteCurrentProfile(backend: backend)

        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.profileState(for: "user_live")?.shell.avatarURL)
        XCTAssertEqual(store.currentUser.defaultVisibility, .mutuals)
    }

    func testRemoteCurrentProfileClearsHostedAvatarWhenRemoteOmitsAvatar() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Local Joe",
                    handle: "localjoe",
                    email: "joe@example.com"
                )
            )
        )
        store.updateCurrentUserAvatarURL("https://example.supabase.co/storage/v1/object/public/profile-avatars/user_live/avatar.jpg?v=old")
        let profileRepository = FakeProfileRepository(
            currentProfile: LocalProfile(
                localID: "local_profile_current",
                serverID: "user_live",
                handle: "joe",
                displayName: "Joe",
                avatarURL: nil,
                bio: "places worth returning to",
                homeArea: "Los Angeles",
                defaultVisibility: .mutuals,
                syncState: .synced
            )
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        _ = await store.refreshRemoteCurrentProfile(backend: backend)

        XCTAssertNil(store.currentUser.avatarURL)
        XCTAssertNil(store.profileState(for: "user_live")?.shell.avatarURL)
        XCTAssertEqual(store.currentUser.defaultVisibility, .mutuals)
    }

    func testPartialProfileUpdatePreservesUnspecifiedLocalDetails() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.updateCurrentUserProfile(bio: "Keep this bio", homeArea: "Santa Monica")

        try await store.updateCurrentUserDetails(
            ProfileDetailsUpdate(defaultVisibility: .mutuals, isPrivateProfile: true),
            backend: nil
        )

        XCTAssertEqual(store.currentUser.bio, "Keep this bio")
        XCTAssertEqual(store.currentUser.homeArea, "Santa Monica")
    }

    func testProfileIdentityUpdatePersistsThroughTheProfileDetailsPath() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())

        try await store.updateCurrentUserDetails(
            ProfileDetailsUpdate(displayName: "Ryan Tester", handle: "ryan_tester"),
            backend: nil
        )

        XCTAssertEqual(store.currentUser.displayName, "Ryan Tester")
        XCTAssertEqual(store.currentUser.handle, "ryan_tester")
        XCTAssertEqual(store.profileState(for: store.currentUser.id)?.shell.displayName, "Ryan Tester")
        XCTAssertEqual(store.profileState(for: store.currentUser.id)?.shell.handle, "ryan_tester")
    }

    func testRejectedRemoteProfileIdentityDoesNotOverwriteTheLocalProfile() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let originalName = store.currentUser.displayName
        let originalHandle = store.currentUser.handle
        let backend = WanderBackend(profileRepository: FakeProfileRepository(updateError: TestError.expected))

        do {
            try await store.updateCurrentUserDetails(
                ProfileDetailsUpdate(displayName: "Duplicate Name", handle: "already_taken"),
                backend: backend
            )
            XCTFail("Expected the remote update to fail")
        } catch {
            XCTAssertEqual(store.currentUser.displayName, originalName)
            XCTAssertEqual(store.currentUser.handle, originalHandle)
        }
    }

    func testSignedInSessionClaimsGuestSavedPlaces() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_guest_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "saved before auth",
            sourceType: .manual
        )

        XCTAssertEqual(store.currentUserVisiblePlaces.map(\.userPlace.id), [result.userPlaceID])

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Joe",
                    handle: "joe",
                    email: "jolipshutz@gmail.com"
                )
            )
        )

        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Maru Coffee" }
        XCTAssertEqual(saved?.userPlace.id, result.userPlaceID)
        XCTAssertEqual(saved?.userPlace.userID, "user_live")
        XCTAssertEqual(saved?.userPlace.note, "saved before auth")
        XCTAssertEqual(saved?.userPlace.syncState, .pendingCreate)
    }

    func testSeededStoreShowsOwnAndVisibleSocialPlaces() {
        let store = makeStore()

        let names = Set(store.visiblePlaces().map { $0.place.canonicalName })

        XCTAssertTrue(names.contains("Woodcat Coffee"))
        XCTAssertTrue(names.contains("Griffith Observatory Trail"))
        XCTAssertTrue(names.contains("Larchmont Noodles"))
        XCTAssertTrue(names.contains("Fern Desk Coffee"))
        XCTAssertTrue(names.contains("Juniper Table"))
    }

    func testBlockRemovesFollowEdgesAndVisiblePlaces() {
        let store = makeStore()

        XCTAssertEqual(store.relationship(to: "user_ryan"), .mutual)
        XCTAssertTrue(store.visiblePlaces().contains { $0.owner.id == "user_ryan" })

        store.block(userID: "user_ryan")

        XCTAssertEqual(store.relationship(to: "user_ryan"), .nonFollower)
        XCTAssertFalse(store.visiblePlaces().contains { $0.owner.id == "user_ryan" })
        XCTAssertEqual(store.blockedProfiles().map(\.id), ["user_ryan"])
    }

    func testBlockFiltersStaleFollowEdgesFromBlockedUsersGraph() {
        let store = makeStoreWithStaleBlockedGraph()

        XCTAssertEqual(store.relationship(to: "user_ryan"), .nonFollower)
        XCTAssertEqual(store.blockedProfiles().map(\.id), ["user_ryan"])
        XCTAssertTrue(store.followers(of: "user_ryan").isEmpty)
        XCTAssertTrue(store.following(of: "user_ryan").isEmpty)
    }

    func testBlockingProfileShellKeepsBlockedUserRenderableForUnblock() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let sofia = ProfileShell(
            id: "user_sofia",
            handle: "sofia",
            displayName: "Sofia",
            avatarURL: "https://example.com/sofia.jpg",
            bio: "sunset walks",
            relationship: .nonFollower
        )

        await store.block(profile: sofia, backend: nil)

        let blocked = store.blockedProfiles()
        XCTAssertEqual(blocked.map(\.id), ["user_sofia"])
        XCTAssertEqual(blocked.first?.displayName, "Sofia")
        XCTAssertEqual(blocked.first?.handle, "sofia")
        XCTAssertEqual(blocked.first?.avatarURL, "https://example.com/sofia.jpg")
        XCTAssertTrue(store.searchProfiles(handleQuery: "so").isEmpty)
    }

    func testBlockingByIDStillShowsPlaceholderBlockedUserForUnblock() {
        let store = makeStore()

        store.block(userID: "user_remote_only")

        let blocked = store.blockedProfiles()
        XCTAssertTrue(blocked.contains { profile in
            profile.id == "user_remote_only"
                && profile.displayName == "Blocked user"
                && profile.handle == "user_remote_only"
        })
    }

    func testSavingWannaForExistingBeenPlaceKeepsExistingSaveUnchanged() {
        let store = makeStore()
        let originalCount = store.currentUserVisiblePlaces.count
        let original = store.currentUserVisiblePlaces.first {
            $0.place.canonicalName == "Woodcat Coffee"
        }?.userPlace

        let candidate = PlaceCandidate(
            id: "place_woodcat",
            name: "Woodcat Coffee",
            category: "coffee",
            latitude: 34.077,
            longitude: -118.260,
            confidence: 1
        )

        _ = store.saveCandidate(candidate, status: .wannaGo, visibility: .selfOnly, note: "updated", sourceType: .manual)

        XCTAssertEqual(store.currentUserVisiblePlaces.count, originalCount)
        let woodcat = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Woodcat Coffee" }
        XCTAssertEqual(woodcat?.userPlace.status, .been)
        XCTAssertEqual(woodcat?.userPlace.visibility, original?.visibility)
        XCTAssertEqual(woodcat?.userPlace.note, original?.note)
        XCTAssertEqual(woodcat?.userPlace.historicalWantNote, original?.historicalWantNote)
        XCTAssertEqual(woodcat?.userPlace.historicalWantedAt, original?.historicalWantedAt)
    }

    func testRemoveSaveDeletesOwnSavedMetadataLocally() {
        let store = makeStore()
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "manual_remove_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .mutuals,
            note: "corner table",
            sourceType: .manual,
            ratingScore: 5,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet", "wifi solid"]),
                PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels, valueType: "personal_label", stringValues: ["LA favorite"])
            ]
        )

        XCTAssertTrue(store.currentUserVisiblePlaces.contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertFalse(store.attributes(for: result.userPlaceID).isEmpty)

        let removal = store.removeSave(userPlaceID: result.userPlaceID)

        XCTAssertEqual(removal?.syncState, .tombstoned)
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertTrue(store.attributes(for: result.userPlaceID).isEmpty)

        let removed = store.userPlaces.first { $0.localID == result.userPlaceID || $0.id == result.userPlaceID }
        XCTAssertNotNil(removed?.deletedAt)
        XCTAssertNil(removed?.note)
        XCTAssertNil(removed?.ratingSignal)
        XCTAssertNil(removed?.ratingScore)
        XCTAssertNil(removed?.recommendedScore)
        XCTAssertEqual(removed?.recommendedCount, 0)
        XCTAssertEqual(removed?.syncState, .tombstoned)
    }

    func testRemoveSaveCallsRemoteDeleteForSyncedSave() async {
        let store = makeStore()
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "manual_remote_remove_maru",
                name: "Remote Remove Coffee",
                category: "coffee",
                latitude: 34.0408,
                longitude: -118.2355,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "remote save",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["outlets"])
            ]
        )
        let userPlace = store.userPlaces.first { $0.id == result.userPlaceID }
        userPlace?.serverID = "up_remote_remove_save"
        userPlace?.syncStateRaw = SyncState.synced.rawValue
        let userPlaceRepository = FakeUserPlaceRepository()

        let removal = await store.removeSave(
            userPlaceID: result.userPlaceID,
            backend: WanderBackend(userPlaceRepository: userPlaceRepository)
        )

        XCTAssertEqual(removal?.syncState, .tombstoned)
        XCTAssertEqual(userPlaceRepository.deletedUserPlaceIDs, ["up_remote_remove_save"])
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.place.canonicalName == "Remote Remove Coffee" })
        XCTAssertTrue(store.attributes(for: result.userPlaceID).isEmpty)
        XCTAssertNotNil(userPlace?.deletedAt)
        XCTAssertEqual(userPlace?.syncState, .tombstoned)
        XCTAssertNil(userPlace?.lastSyncError)
    }

    func testRemoveSavePreservesFollowingSavesForSamePlaceGroup() {
        let store = makeStore()
        guard let currentUserSave = store.currentUserVisiblePlaces.first(where: { visiblePlace in
            visiblePlace.place.canonicalName == "Circuit Coffee"
        }) else {
            return XCTFail("Expected seeded current-user save for Circuit Coffee")
        }

        XCTAssertFalse(store.attributes(for: currentUserSave.userPlace.id).isEmpty)

        let removal = store.removeSave(userPlaceID: currentUserSave.userPlace.id)

        XCTAssertEqual(removal?.syncState, .pendingDelete)
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { visiblePlace in
            visiblePlace.place.canonicalName == "Circuit Coffee"
        })
        XCTAssertTrue(store.attributes(for: currentUserSave.userPlace.id).isEmpty)

        let remainingCircuitSaves = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"]))
            .filter { $0.place.canonicalName == "Circuit Coffee" }
        XCTAssertEqual(Set(remainingCircuitSaves.map(\.owner.id)), ["user_maya", "user_ryan"])

        let allVisibleCircuitSaves = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["you", "social"]))
            .filter { $0.place.canonicalName == "Circuit Coffee" }
        XCTAssertFalse(allVisibleCircuitSaves.contains { $0.owner.id == store.currentUser.id })
        let group = remainingCircuitSaves.first.flatMap { visiblePlace in
            VisiblePlaceGrouping.matchingGroup(
                for: visiblePlace,
                in: allVisibleCircuitSaves,
                currentUserID: store.currentUser.id
            )
        }
        XCTAssertEqual(group?.saveCount, 2)
        XCTAssertEqual(group?.isSavedByCurrentUser, false)
    }

    func testRemoveSaveDeletesRemoteOnlyCurrentUserSave() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan_lieblein")))
        let remoteUserPlaceID = "8b567297-6e55-45a4-ae58-79b4288aa0a6"
        let remotePlaceID = "93722c05-6b0d-4dfe-a687-85d73f8e7aa1"
        let remotePlace = VisiblePlace(
            id: remoteUserPlaceID,
            place: LocalPlace(
                localID: remotePlaceID,
                serverID: remotePlaceID,
                canonicalName: "Blind Barber",
                category: "bar",
                latitude: 34.083,
                longitude: -118.361,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: remoteUserPlaceID,
                serverID: remoteUserPlaceID,
                userID: "user_live",
                placeID: remotePlaceID,
                status: .wannaGo,
                visibility: .followers,
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "user_live",
                serverID: "user_live",
                handle: "ryan_lieblein",
                displayName: "Ryan",
                syncState: .synced
            ),
            attributes: [
                LocalPlaceAttribute(
                    localID: "remote_attr_blind_barber_tag",
                    userPlaceID: remoteUserPlaceID,
                    questionKey: "bar_tags",
                    valueType: "multi_tag",
                    valueJSON: "[\"old\"]",
                    syncState: .synced
                )
            ]
        )
        let placeRepository = FakePlaceRepository(places: [remotePlace])
        let userPlaceRepository = FakeUserPlaceRepository()
        let backend = WanderBackend(placeRepository: placeRepository, userPlaceRepository: userPlaceRepository)

        await store.refreshRemoteVisiblePlaces(
            in: MapViewport(minLatitude: 34, minLongitude: -119, maxLatitude: 35, maxLongitude: -118),
            backend: backend
        )
        XCTAssertTrue(store.currentUserVisiblePlaces.contains { $0.userPlace.id == remoteUserPlaceID })
        XCTAssertEqual(store.attributes(for: remoteUserPlaceID).map(\.questionKey), ["bar_tags"])
        placeRepository.setPlaces([])

        let removal = await store.removeSave(userPlaceID: remoteUserPlaceID, backend: backend)

        XCTAssertEqual(removal?.syncState, .tombstoned)
        XCTAssertEqual(userPlaceRepository.deletedUserPlaceIDs, [remoteUserPlaceID])
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.userPlace.id == remoteUserPlaceID })
        XCTAssertTrue(store.attributes(for: remoteUserPlaceID).isEmpty)
    }

    func testCurrentLocationSavePreservesSourceMetadata() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "mapkit_maru_3404070_-11823540",
            name: "Maru Coffee",
            category: "coffee",
            address: "101 Arts District",
            locality: "Los Angeles",
            region: "CA",
            country: "US",
            latitude: 34.0407,
            longitude: -118.2354,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit_maru_3404070_-11823540",
            websiteURLString: "https://maru.example",
            phoneNumber: "+1 (213) 555-0100",
            timeZoneIdentifier: "America/Los_Angeles",
            confidence: 0.92
        )

        _ = store.saveCandidate(candidate, status: .been, visibility: .followers, note: nil, sourceType: .currentLocation)

        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Maru Coffee" }
        XCTAssertEqual(saved?.userPlace.sourceType, AddSourceType.currentLocation.rawValue)
        XCTAssertEqual(saved?.userPlace.nearbyConfirmed, true)
        XCTAssertEqual(saved?.place.address, "101 Arts District")
        XCTAssertEqual(saved?.place.sourceProviderPlaceID, "mapkit_maru_3404070_-11823540")
        XCTAssertEqual(saved?.place.websiteURLString, "https://maru.example")
        XCTAssertEqual(saved?.place.phoneNumber, "+1 (213) 555-0100")
        XCTAssertEqual(saved?.place.timeZoneIdentifier, "America/Los_Angeles")
    }

    func testSavingSparseCandidateDoesNotEraseExistingBusinessMetadata() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let richCandidate = PlaceCandidate(
            id: "mapkit_rich_maru",
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.0407,
            longitude: -118.2354,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit_rich_maru",
            websiteURLString: "https://maru.example",
            phoneNumber: "+1 (213) 555-0100",
            timeZoneIdentifier: "America/Los_Angeles",
            confidence: 0.92
        )

        _ = store.saveCandidate(richCandidate, status: .been, visibility: .followers, note: nil, sourceType: .currentLocation)
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_rich_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: "mapkit_rich_maru",
                confidence: 0.75
            ),
            status: .wannaGo,
            visibility: .selfOnly,
            note: "still has actions",
            sourceType: .manual
        )

        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Maru Coffee" }
        XCTAssertEqual(saved?.place.websiteURLString, "https://maru.example")
        XCTAssertEqual(saved?.place.phoneNumber, "+1 (213) 555-0100")
        XCTAssertEqual(saved?.place.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertNil(saved?.userPlace.historicalWantNote)
        XCTAssertNil(saved?.userPlace.historicalWantedAt)
    }

    func testProviderBusinessMetadataEnrichmentPersistsAndPreservesValidValues() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let candidate = PlaceCandidate(
            id: "mapkit_anajak_thai",
            name: "Anajak Thai",
            category: "restaurant",
            address: "14704 Ventura Blvd",
            locality: "Sherman Oaks",
            region: "CA",
            latitude: 34.15182,
            longitude: -118.45363,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "mapkit_anajak_thai",
            confidence: 0.92
        )
        _ = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        let placeID = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Anajak Thai" }?.place.id
        )

        XCTAssertTrue(
            store.applyProviderBusinessMetadata(
                placeID: placeID,
                metadata: PlaceBusinessMetadata(
                    websiteURLString: "https://www.anajakthai.com",
                    phoneNumber: "+1 (818) 501-4201",
                    timeZoneIdentifier: "America/Los_Angeles"
                )
            )
        )
        XCTAssertFalse(
            store.applyProviderBusinessMetadata(
                placeID: placeID,
                metadata: PlaceBusinessMetadata(
                    websiteURLString: "https://wrong.example",
                    phoneNumber: "+1 213 555 0100",
                    timeZoneIdentifier: "America/New_York"
                )
            )
        )

        let saved = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Anajak Thai" }
        )
        XCTAssertEqual(saved.place.websiteURLString, "https://www.anajakthai.com")
        XCTAssertEqual(saved.place.phoneNumber, "+1 (818) 501-4201")
        XCTAssertEqual(saved.place.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(saved.place.syncState, .pendingCreate)
    }

    func testCurrentLocationCandidatesUseInjectedResolver() async throws {
        let resolver = FakePlaceResolver(
            currentLocationCandidates: [
                PlaceCandidate(
                    id: "mapkit_here",
                    name: "Here Cafe",
                    category: "coffee",
                    latitude: 34.1,
                    longitude: -118.2,
                    sourceProviderPlaceID: "mapkit_here",
                    confidence: 0.9
                )
            ]
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)

        let candidates = try await store.currentLocationCandidates()

        XCTAssertEqual(candidates.map(\.name), ["Here Cafe"])
        XCTAssertEqual(resolver.currentLocationCallCount, 1)
    }

    func testManualCandidatesUseInjectedResolverInput() async throws {
        let resolver = FakePlaceResolver(
            manualCandidates: [
                PlaceCandidate(
                    id: "mapkit_larchmont",
                    name: "Larchmont Noodles",
                    category: "restaurant",
                    latitude: 34.073,
                    longitude: -118.323,
                    sourceProviderPlaceID: "mapkit_larchmont",
                    confidence: 0.88
                )
            ]
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)

        let candidates = try await store.manualCandidates(name: "Larchmont Noodles", areaHint: "LA", category: "restaurant")

        XCTAssertEqual(candidates.map(\.name), ["Larchmont Noodles"])
        XCTAssertEqual(resolver.manualInputs, [ManualPlaceInput(name: "Larchmont Noodles", areaHint: "LA", category: "restaurant")])
    }

    func testLinkCandidatesUseInjectedResolverInput() async throws {
        let resolver = FakePlaceResolver(
            linkCandidates: [
                PlaceCandidate(
                    id: "mapkit_link_place",
                    name: "Linked Place",
                    category: "restaurant",
                    latitude: 34.07,
                    longitude: -118.32,
                    sourceProviderPlaceID: "mapkit_link_place",
                    confidence: 0.86
                )
            ]
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), placeResolver: resolver)

        let candidates = try await store.linkCandidates("https://maps.google.com/?q=Linked+Place")

        XCTAssertEqual(candidates.map(\.name), ["Linked Place"])
        XCTAssertEqual(resolver.linkInputs, [LinkPlaceInput(rawValue: "https://maps.google.com/?q=Linked+Place")])
    }

    func testSaveCandidatePersistsQuestionAttributes() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "manual_answer_test",
            name: "Answer Test Coffee",
            category: "coffee",
            latitude: 34.0522,
            longitude: -118.2437,
            confidence: 0.8
        )

        let result = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "has answers",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "work_setup", valueType: "single_choice", stringValue: "yes"),
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid", "quiet"])
            ]
        )

        let attributes = store.attributes(for: result.userPlaceID)
        XCTAssertEqual(attributes.map(\.questionKey), ["coffee_tags", "work_setup"])
        XCTAssertEqual(attributes.first { $0.questionKey == "coffee_tags" }?.valueJSON, "[\"wifi solid\",\"quiet\"]")
        let visiblePlace = store.currentUserVisiblePlaces.first { $0.id == result.userPlaceID }
        XCTAssertEqual(visiblePlace?.userPlace.ratingScore, 4)
        XCTAssertEqual(visiblePlace?.userPlace.recommendedScore, 4)
        XCTAssertEqual(visiblePlace?.userPlace.recommendedCount, 1)
        XCTAssertNil(visiblePlace?.userPlace.ratingSignal)
    }

    func testFilePersistenceRestoresSavedPlaceAfterRelaunch() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        firstStore.setPrivateProfile(false)
        firstStore.defaultVisibility = .mutuals

        let result = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mapkit_persisted_maru",
                name: "Maru Coffee",
                category: "coffee",
                address: "101 Arts District",
                locality: "Los Angeles",
                region: "CA",
                country: "US",
                latitude: 34.0407,
                longitude: -118.2354,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: "mapkit_persisted_maru",
                websiteURLString: "https://maru.example",
                phoneNumber: "+1 (213) 555-0100",
                timeZoneIdentifier: "America/Los_Angeles",
                confidence: 0.92
            ),
            status: .been,
            visibility: .mutuals,
            note: "window table",
            sourceType: .manual,
            ratingScore: 5,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid", "quiet"])
            ]
        )

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let saved = relaunchedStore.currentUserVisiblePlaces.first { $0.place.canonicalName == "Maru Coffee" }

        XCTAssertEqual(relaunchedStore.currentUser.id, "user_live")
        XCTAssertEqual(relaunchedStore.defaultVisibility, .mutuals)
        XCTAssertEqual(saved?.place.address, "101 Arts District")
        XCTAssertEqual(saved?.place.websiteURLString, "https://maru.example")
        XCTAssertEqual(saved?.place.phoneNumber, "+1 (213) 555-0100")
        XCTAssertEqual(saved?.place.timeZoneIdentifier, "America/Los_Angeles")
        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.visibility, .mutuals)
        XCTAssertEqual(saved?.userPlace.note, "window table")
        XCTAssertEqual(saved?.userPlace.ratingScore, 5)
        XCTAssertEqual(saved?.userPlace.recommendedScore, 5)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 1)
        XCTAssertNil(saved?.userPlace.ratingSignal)
        XCTAssertEqual(relaunchedStore.attributes(for: result.userPlaceID).map(\.questionKey), ["coffee_tags"])
    }

    func testWannaPlannedDatePersistsAndBecomesAReminderItem() throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let plannedDate = try XCTUnwrap(WannaGoDate.date(fromStorageString: "2026-08-20"))

        let result = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mapkit_planned_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: plannedDate
        )

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let saved = try XCTUnwrap(
            relaunchedStore.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )
        let reminder = try XCTUnwrap(relaunchedStore.wannaGoReminderItems.first)

        XCTAssertEqual(WannaGoDate.storageString(from: try XCTUnwrap(saved.userPlace.plannedDate)), "2026-08-20")
        XCTAssertEqual(reminder.placeName, "Maru Coffee")
        XCTAssertEqual(WannaGoDate.storageString(from: reminder.plannedDate), "2026-08-20")
    }

    func testEditingClearingAndCompletingWannaReconcilesPlannedDate() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_planned_maru",
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )
        let plannedDate = try XCTUnwrap(WannaGoDate.date(fromStorageString: "2026-08-20"))

        let result = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: plannedDate
        )
        XCTAssertEqual(store.wannaGoReminderItems.count, 1)

        _ = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: nil
        )
        XCTAssertNil(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace.plannedDate)
        XCTAssertTrue(store.wannaGoReminderItems.isEmpty)

        _ = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: plannedDate
        )
        _ = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        XCTAssertNil(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace.plannedDate)
        XCTAssertTrue(store.wannaGoReminderItems.isEmpty)
    }

    func testRemoteWannaSaveDraftIncludesPlannedDate() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let repository = FakeUserPlaceRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        let plannedDate = try XCTUnwrap(WannaGoDate.date(fromStorageString: "2026-08-20"))

        _ = await store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_planned_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: plannedDate,
            backend: backend
        )

        let draft = try XCTUnwrap(repository.savedDrafts.first)
        XCTAssertEqual(WannaGoDate.storageString(from: try XCTUnwrap(draft.plannedDate)), "2026-08-20")
    }

    func testRemoteWannaPlanRefreshDiscardsCompletionFromPreviousAccount() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let accountB = AuthSession(userID: "user_b", displayName: "Bee", handle: "bee")
        store.apply(authState: .signedIn(accountB))
        let plannedDate = try XCTUnwrap(WannaGoDate.date(fromStorageString: "2026-08-20"))

        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_account_b_plan",
                name: "Account B Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            plannedDate: plannedDate
        )
        let accountBPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace
        )
        accountBPlace.serverID = "up_account_b_plan"
        accountBPlace.syncStateRaw = SyncState.synced.rawValue

        let repository = DeferredWannaGoPlanRepository()
        let backend = WanderBackend(userPlaceRepository: repository)
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Aye", handle: "aye")
            )
        )

        let refreshTask = Task {
            await store.refreshRemoteWannaGoPlans(backend: backend)
        }
        while !repository.didRequestPlans {
            await Task.yield()
        }

        store.apply(authState: .signedIn(accountB))
        repository.finish(with: [])
        _ = await refreshTask.value

        XCTAssertEqual(
            WannaGoDate.storageString(from: try XCTUnwrap(accountBPlace.plannedDate)),
            "2026-08-20"
        )
    }

    func testSavingCheckInCreatesExplicitVisitAndPersistsPhotoMetadata() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mapkit_visit_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "window table",
            sourceType: .manual,
            ratingScore: 5,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid", "quiet"])
            ]
        )

        let visit = firstStore.visits(for: result.userPlaceID).first
        XCTAssertEqual(firstStore.visits(for: result.userPlaceID).count, 1)
        XCTAssertEqual(visit?.note, "window table")
        XCTAssertEqual(visit?.ratingScore, 5)
        XCTAssertEqual(visit?.tags, ["quiet", "wifi solid"])
        XCTAssertEqual(visit?.backfilledFromUserPlace, false)

        let photo = firstStore.createVisitPhoto(
            visitID: visit?.id ?? "",
            localAssetRef: "ph://asset-1",
            remoteURLString: "https://storage.example/visit-photos/user_live/photo.jpg",
            contentType: "image/jpeg",
            byteSize: 42_000,
            width: 1200,
            height: 900
        )
        XCTAssertEqual(photo?.uploadState, .uploaded)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let restoredVisit = relaunchedStore.visits(for: result.userPlaceID).first
        let restoredPhoto = restoredVisit.flatMap { relaunchedStore.photos(for: $0.id).first }

        XCTAssertEqual(restoredVisit?.ratingScore, 5)
        XCTAssertEqual(restoredVisit?.tags, ["quiet", "wifi solid"])
        XCTAssertEqual(restoredPhoto?.localAssetRef, "ph://asset-1")
        XCTAssertEqual(restoredPhoto?.remoteURLString, "https://storage.example/visit-photos/user_live/photo.jpg")
        XCTAssertEqual(restoredPhoto?.byteSize, 42_000)
        XCTAssertEqual(restoredPhoto?.width, 1200)
        XCTAssertEqual(restoredPhoto?.height, 900)
    }

    func testAutomaticImportDoesNotCreateASecondCheckInForAnExistingBeenPlace() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "mapkit_import_idempotency",
            name: "Import Idempotency Cafe",
            category: "coffee",
            latitude: 34.12345,
            longitude: -118.54321,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "import-idempotency-cafe",
            confidence: 0.99
        )
        let first = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "original memory",
            sourceType: .manual,
            ratingScore: 5
        )
        let originalVisits = store.visits(for: first.userPlaceID)

        let imported = store.saveImportedCandidate(
            candidate,
            status: .been,
            visibility: .selfOnly,
            note: "imported memory",
            sourceType: .link,
            ratingScore: 2
        )

        XCTAssertEqual(imported.userPlaceID, first.userPlaceID)
        XCTAssertEqual(store.visits(for: first.userPlaceID), originalVisits)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first(where: {
                $0.userPlace.id == first.userPlaceID
            })?.userPlace.visibility,
            .followers
        )
    }

    func testAutomaticCheckInImportEnrichesAnExistingWannaExactlyOnce() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "mapkit_import_wanna_upgrade",
            name: "Import Upgrade Cafe",
            category: "coffee",
            latitude: 34.11111,
            longitude: -118.22222,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "import-upgrade-cafe",
            confidence: 0.99
        )
        let first = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "want to try",
            sourceType: .manual
        )

        let imported = store.saveImportedCandidate(
            candidate,
            status: .been,
            visibility: .selfOnly,
            note: "went today",
            sourceType: .link,
            ratingScore: 4
        )

        XCTAssertEqual(imported.userPlaceID, first.userPlaceID)
        XCTAssertEqual(store.visits(for: first.userPlaceID).count, 1)
        XCTAssertEqual(store.visits(for: first.userPlaceID).first?.ratingScore, 4)
        XCTAssertEqual(store.visits(for: first.userPlaceID).first?.note, "went today")
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first(where: {
                $0.userPlace.id == first.userPlaceID
            })?.userPlace.visibility,
            .followers
        )
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first(where: {
                $0.userPlace.id == first.userPlaceID
            })?.userPlace.status,
            .been
        )
    }

    func testAutomaticWannaImportNeverDowngradesAnExistingCheckIn() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "mapkit_import_been_preserved",
            name: "Been Preserved Cafe",
            category: "coffee",
            latitude: 34.22222,
            longitude: -118.33333,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: "been-preserved-cafe",
            confidence: 0.99
        )
        let first = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "original memory",
            sourceType: .manual,
            ratingScore: 5
        )
        let originalVisits = store.visits(for: first.userPlaceID)

        let imported = store.saveImportedCandidate(
            candidate,
            status: .wannaGo,
            visibility: .selfOnly,
            note: "imported",
            sourceType: .link
        )

        XCTAssertEqual(imported.userPlaceID, first.userPlaceID)
        XCTAssertEqual(store.visits(for: first.userPlaceID), originalVisits)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first(where: {
                $0.userPlace.id == first.userPlaceID
            })?.userPlace.status,
            .been
        )
    }

    func testFirstVisitPhotoForPlaceUsesEarliestUsablePhoto() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "dropped_pin_photo_default",
                name: "Dropped pin",
                category: "other",
                latitude: 34.09435,
                longitude: -118.44982,
                sourceProvider: "manual",
                confidence: 1
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        let visit = store.visits(for: result.userPlaceID).first
        let first = store.createVisitPhoto(visitID: visit?.id ?? "", localAssetRef: "first.jpg")
        let second = store.createVisitPhoto(visitID: visit?.id ?? "", localAssetRef: "second.jpg")
        let placeID = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.place.id

        XCTAssertEqual(store.firstVisitPhoto(forPlaceID: placeID ?? "")?.id, first?.id)
        XCTAssertEqual(store.firstVisitPhotosByPlaceID()[placeID ?? ""]?.id, first?.id)
        XCTAssertNotEqual(first?.id, second?.id)

        _ = store.deleteVisitPhoto(photoID: first?.id ?? "")
        XCTAssertEqual(store.firstVisitPhoto(forPlaceID: placeID ?? "")?.id, second?.id)
        XCTAssertEqual(store.firstVisitPhotosByPlaceID()[placeID ?? ""]?.id, second?.id)
    }

    func testMultipleVisitsAverageRatings() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_multi_visit",
                name: "Multiple Visit Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4
        )

        XCTAssertNotNil(store.createVisit(userPlaceID: result.userPlaceID, note: "second visit", ratingScore: 5))
        XCTAssertNotNil(store.createVisit(userPlaceID: result.userPlaceID, note: "default rating visit", ratingScore: nil))

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        XCTAssertEqual(store.visits(for: result.userPlaceID).count, 3)
        XCTAssertEqual(saved?.userPlace.ratingScore, 4)
        XCTAssertEqual(saved?.userPlace.recommendedScore, 4)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 3)
    }

    func testStoreInitializationReconcilesLocalAndServerVisitAliasesWithoutBackfill() throws {
        let currentUser = LocalProfile(
            localID: "local_profile_alias",
            serverID: "user_alias",
            handle: "alias",
            displayName: "Alias User",
            syncState: .synced
        )
        let place = LocalPlace(
            localID: "local_place_alias",
            serverID: "place_alias",
            canonicalName: "Alias Cafe",
            category: "coffee",
            latitude: 34.0,
            longitude: -118.0,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_alias",
            serverID: "up_alias",
            userID: currentUser.id,
            placeID: place.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual",
            syncState: .synced
        )
        let visits = [
            LocalPlaceVisit(
                localID: "local_visit_alias_local",
                userPlaceID: userPlace.localID,
                visitedAt: Date(timeIntervalSince1970: 100),
                ratingScore: 3,
                backfilledFromUserPlace: false,
                syncState: .synced
            ),
            LocalPlaceVisit(
                localID: "local_visit_alias_server",
                serverID: "visit_alias_server",
                userPlaceID: userPlace.id,
                visitedAt: Date(timeIntervalSince1970: 200),
                ratingScore: 5,
                backfilledFromUserPlace: false,
                syncState: .synced
            )
        ]
        let fixtures = WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser],
            places: [place],
            userPlaces: [userPlace],
            placeAttributes: [],
            placeVisits: visits,
            follows: [],
            blocks: [],
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        )

        let store = WanderStore(fixtures: fixtures)
        let saved = try XCTUnwrap(store.currentUserVisiblePlaces.first?.userPlace)

        XCTAssertEqual(store.visits(for: userPlace.id).count, 2)
        XCTAssertFalse(store.visits(for: userPlace.id).contains(where: \.backfilledFromUserPlace))
        XCTAssertEqual(saved.ratingScore, 4)
        XCTAssertEqual(saved.recommendedScore, 4)
        XCTAssertEqual(saved.recommendedCount, 2)
        XCTAssertEqual(saved.visitedAt, Date(timeIntervalSince1970: 200))
    }

    func testEarlierExplicitCheckInDoesNotMutateAfterLaterCheckInsExist() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_backfill_stable",
            name: "Backfill Stable Cafe",
            category: "coffee",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )
        let result = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 3,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"])
            ]
        )
        XCTAssertNotNil(store.createVisit(userPlaceID: result.userPlaceID, note: "second visit", ratingScore: 5))

        _ = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "latest parent note",
            sourceType: .manual,
            ratingScore: 2,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["loud"])
            ]
        )

        let visits = store.visits(for: result.userPlaceID)
        let first = visits.first { $0.note == "first visit" }
        let second = visits.first { $0.note == "second visit" }
        let latest = visits.first { $0.note == "latest parent note" }
        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }

        XCTAssertEqual(visits.count, 3)
        XCTAssertEqual(first?.backfilledFromUserPlace, false)
        XCTAssertEqual(first?.ratingScore, 3)
        XCTAssertEqual(first?.tags, ["quiet"])
        XCTAssertEqual(second?.ratingScore, 5)
        XCTAssertEqual(latest?.ratingScore, 2)
        XCTAssertEqual(latest?.tags, ["loud"])
        XCTAssertEqual(saved?.userPlace.ratingScore, 3.3)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 3)
    }

    func testSavingWantAfterBeenIsANoOp() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_status_visit",
            name: "Status Visit Cafe",
            category: "coffee",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )
        let result = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "been here",
            sourceType: .manual,
            ratingScore: 4
        )
        XCTAssertEqual(store.visits(for: result.userPlaceID).count, 1)
        let before = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace
        let originalUpdatedAt = before?.updatedAt
        let originalLocalUpdatedAt = before?.localUpdatedAt

        let updated = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "want later",
            sourceType: .manual,
            ratingScore: 5
        )

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == updated.userPlaceID }
        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.ratingScore, 4)
        XCTAssertEqual(saved?.userPlace.recommendedScore, 4)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 1)
        XCTAssertEqual(saved?.userPlace.note, "been here")
        XCTAssertEqual(saved?.userPlace.visibility, before?.visibility)
        XCTAssertNil(saved?.userPlace.historicalWantNote)
        XCTAssertNil(saved?.userPlace.historicalWantedAt)
        XCTAssertEqual(saved?.userPlace.updatedAt, originalUpdatedAt)
        XCTAssertEqual(saved?.userPlace.localUpdatedAt, originalLocalUpdatedAt)
        XCTAssertEqual(store.visits(for: updated.userPlaceID).count, 1)
    }

    func testSavingWantAfterBeenDoesNotCallRemoteRepository() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_remote_status_visit",
            name: "Remote Status Visit Cafe",
            category: "coffee",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )
        let original = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "already visited",
            sourceType: .manual,
            ratingScore: 4
        )
        let repository = FakeUserPlaceRepository()
        let backend = WanderBackend(userPlaceRepository: repository)

        let result = await store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .selfOnly,
            note: "should not save",
            sourceType: .manual,
            backend: backend
        )

        XCTAssertEqual(result.userPlaceID, original.userPlaceID)
        XCTAssertTrue(repository.savedDrafts.isEmpty)
        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == original.userPlaceID }
        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.note, "already visited")
        XCTAssertNil(saved?.userPlace.historicalWantNote)
    }

    func testSavingSameNamedPlaceAtAnotherLocationCreatesDistinctWanna() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let firstLocation = PlaceCandidate(
            id: "mapkit_chain-first",
            name: "Same Name Coffee",
            category: "coffee",
            address: "100 First Street",
            latitude: 34.0407,
            longitude: -118.2354,
            sourceProviderPlaceID: "mapkit_chain-first",
            confidence: 0.92
        )
        let secondLocation = PlaceCandidate(
            id: "mapkit_chain_first",
            name: "Same Name Coffee",
            category: "coffee",
            address: "900 Second Street",
            latitude: 35.0407,
            longitude: -117.2354,
            sourceProviderPlaceID: "mapkit_chain_first",
            confidence: 0.92
        )

        let checkedIn = store.saveCandidate(
            firstLocation,
            status: .been,
            visibility: .followers,
            note: "first branch",
            sourceType: .manual,
            ratingScore: 4
        )
        let wanna = store.saveCandidate(
            secondLocation,
            status: .wannaGo,
            visibility: .selfOnly,
            note: "second branch",
            sourceType: .manual
        )

        XCTAssertNotEqual(checkedIn.userPlaceID, wanna.userPlaceID)
        let matchingPlaces = store.currentUserVisiblePlaces.filter {
            $0.place.canonicalName == "Same Name Coffee"
        }
        XCTAssertEqual(matchingPlaces.count, 2)
        XCTAssertEqual(Set(matchingPlaces.map(\.userPlace.status)), [.been, .wannaGo])
        XCTAssertEqual(Set(matchingPlaces.compactMap(\.place.address)), ["100 First Street", "900 Second Street"])

        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Second branch",
                description: "location identity regression",
                visibility: .followers
            )
        )
        let listResult = await store.addCandidate(secondLocation, to: list, backend: nil)

        XCTAssertEqual(listResult.outcome, .added)
        XCTAssertTrue(store.hasCandidate(secondLocation, in: list))
        XCTAssertFalse(store.hasCandidate(firstLocation, in: list))
        XCTAssertEqual(store.visiblePlaces(in: list).map(\.place.address), ["900 Second Street"])
    }

    func testSavingBeenWithoutRatingUsesDefaultRating() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))

        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_unrated_visit",
                name: "Unrated Visit Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "good table",
            sourceType: .manual,
            ratingScore: nil
        )

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        let visit = store.visits(for: result.userPlaceID).first

        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.ratingScore, PlaceRating.defaultScore)
        XCTAssertEqual(saved?.userPlace.recommendedScore, PlaceRating.defaultScore)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 1)
        XCTAssertEqual(visit?.ratingScore, PlaceRating.defaultScore)
    }

    func testRepeatBeenSaveCreatesAnotherVisitAndAveragesRatings() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_repeat_been",
            name: "Brothers Cousins Tacos",
            category: "tacos",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )

        let first = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "first tacos",
            sourceType: .manual,
            ratingScore: 4
        )
        let second = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "second tacos",
            sourceType: .manual,
            ratingScore: 5
        )

        let visits = store.visits(for: first.userPlaceID)
        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == second.userPlaceID }

        XCTAssertEqual(first.userPlaceID, second.userPlaceID)
        XCTAssertEqual(visits.count, 2)
        XCTAssertEqual(visits.map(\.note), ["second tacos", "first tacos"])
        XCTAssertEqual(saved?.userPlace.ratingScore, 4.5)
        XCTAssertEqual(saved?.userPlace.recommendedScore, 4.5)
        XCTAssertEqual(saved?.userPlace.recommendedCount, 2)
    }

    func testWannaThenBeenPreservesHistoricalWantAndCreatesVisit() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_want_then_been",
            name: "Want Then Been Tacos",
            category: "tacos",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )

        let want = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "heard about the salsa",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "taco_tags", valueType: "multi_tag", stringValues: ["late night"])
            ]
        )
        let been = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "finally went",
            sourceType: .manual,
            ratingScore: 4.5,
            attributes: [
                PlaceAttributeDraft(questionKey: "taco_tags", valueType: "multi_tag", stringValues: ["counter"])
            ]
        )

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == been.userPlaceID }
        let visit = store.visits(for: been.userPlaceID).first

        XCTAssertEqual(want.userPlaceID, been.userPlaceID)
        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.historicalWantNote, "heard about the salsa")
        XCTAssertEqual(saved?.userPlace.historicalWantTags, ["late night"])
        XCTAssertNotNil(saved?.userPlace.historicalWantedAt)
        XCTAssertEqual(visit?.note, "finally went")
        XCTAssertEqual(visit?.ratingScore, 4.5)
        XCTAssertEqual(visit?.tags, ["counter"])
    }

    func testHistoricalWantSnapshotPersistsAfterRelaunch() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_historical_want_persist",
            name: "Historical Want Tacos",
            category: "tacos",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.92
        )
        _ = firstStore.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "saved for al pastor",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "taco_tags", valueType: "multi_tag", stringValues: ["street stand"])
            ]
        )
        _ = firstStore.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "finally tried it",
            sourceType: .manual,
            ratingScore: 5
        )

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let saved = relaunchedStore.currentUserVisiblePlaces.first { $0.place.canonicalName == "Historical Want Tacos" }

        XCTAssertEqual(saved?.userPlace.status, .been)
        XCTAssertEqual(saved?.userPlace.historicalWantNote, "saved for al pastor")
        XCTAssertEqual(saved?.userPlace.historicalWantTags, ["street stand"])
        XCTAssertNotNil(saved?.userPlace.historicalWantedAt)
        XCTAssertEqual(relaunchedStore.visits(for: saved?.userPlace.id ?? "").count, 1)
    }

    func testCreateVisitFromWantPromotesSaveAndKeepsDetailsVisitScoped() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_want_to_visit",
                name: "Want To Visit Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .wannaGo,
            visibility: .followers,
            note: "looks good for lunch",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["sunny"])
            ]
        )

        let visit = try XCTUnwrap(store.createVisit(
            userPlaceID: result.userPlaceID,
            note: "went with Maya",
            ratingScore: nil,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet", "wifi solid"])
            ],
            visibility: .selfOnly
        ))
        let saved = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })

        XCTAssertEqual(saved.userPlace.status, .been)
        XCTAssertEqual(saved.userPlace.visibility, .selfOnly)
        XCTAssertEqual(saved.userPlace.ratingScore, PlaceRating.defaultScore)
        XCTAssertEqual(saved.userPlace.recommendedCount, 1)
        XCTAssertEqual(saved.userPlace.historicalWantNote, "looks good for lunch")
        XCTAssertEqual(saved.userPlace.historicalWantTags, ["sunny"])
        XCTAssertEqual(visit.note, "went with Maya")
        XCTAssertEqual(visit.ratingScore, PlaceRating.defaultScore)
        XCTAssertEqual(visit.tags, ["quiet", "wifi solid"])
        XCTAssertEqual(store.visits(for: result.userPlaceID).map(\.id), [visit.id])
    }

    func testUpdateVisitCanClearNoteButKeepsRequiredRatingAndInheritedVisibility() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_edit_visit",
                name: "Edit Visit Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "first note",
            sourceType: .manual,
            ratingScore: 4
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)

        let updated = try XCTUnwrap(store.updateVisit(
            visitID: visit.id,
            note: nil,
            ratingScore: nil,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["counter"])
            ],
            visibility: .selfOnly,
            replacesNote: true,
            replacesRating: true
        ))
        let saved = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })

        XCTAssertNil(updated.note)
        XCTAssertEqual(updated.ratingScore, PlaceRating.defaultScore)
        XCTAssertEqual(updated.tags, ["counter"])
        XCTAssertEqual(saved.userPlace.visibility, .selfOnly)
        XCTAssertEqual(saved.userPlace.ratingScore, PlaceRating.defaultScore)
        XCTAssertEqual(saved.userPlace.recommendedCount, 1)
    }

    func testCurrentUserVisiblePlaceCarriesSavedCuisineAttributes() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_menya_visible_attributes",
                name: "Menya Tigre",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.98,
                rawProviderType: "sushi_restaurant",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.98
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: "Sushi"
                )
            ]
        )

        let visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(visiblePlace.restaurantCuisine, "Sushi")
        XCTAssertEqual(visiblePlace.categoryEmoji, "🍣")
    }

    func testEditingVisitCuisinePromotesClassificationToMapImmediately() throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")
        let store = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        store.apply(authState: .signedIn(session))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_menya_edit_cuisine",
                name: "Menya Tigre",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.98,
                rawProviderType: "sushi_restaurant",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.98
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: "Sushi"
                )
            ]
        )
        let savedUserPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }?.userPlace
        )
        savedUserPlace.serverID = "up_menya_edit_cuisine"
        savedUserPlace.syncStateRaw = SyncState.synced.rawValue
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)

        _ = try XCTUnwrap(
            store.updateVisit(
                visitID: visit.id,
                attributes: [
                    PlaceAttributeDraft(
                        questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                        valueType: "restaurant_cuisine",
                        stringValue: "Japanese"
                    )
                ]
            )
        )

        let visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }
        )
        let cuisineAttribute = try XCTUnwrap(
            store.attributes(for: result.userPlaceID).first {
                $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine
            }
        )

        XCTAssertEqual(cuisineAttribute.valueJSON, "\"Japanese\"")
        XCTAssertEqual(cuisineAttribute.syncState, .pendingUpdate)
        XCTAssertEqual(visiblePlace.restaurantCuisine, "Japanese")
        XCTAssertEqual(visiblePlace.categoryEmoji, "🇯🇵")
        XCTAssertEqual(visiblePlace.userPlace.syncState, .pendingUpdate)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        relaunchedStore.apply(authState: .signedIn(session))
        let restoredVisiblePlace = try XCTUnwrap(
            relaunchedStore.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }
        )

        XCTAssertEqual(restoredVisiblePlace.restaurantCuisine, "Japanese")
        XCTAssertEqual(restoredVisiblePlace.categoryEmoji, "🇯🇵")
    }

    func testEditingVisitWithoutCuisineClearsCanonicalClassification() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_clear_visit_cuisine",
                name: "Generic Restaurant",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.98,
                rawProviderType: "restaurant",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.98
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: "Sushi"
                )
            ]
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)

        _ = try XCTUnwrap(
            store.updateVisit(
                visitID: visit.id,
                attributes: [
                    PlaceAttributeDraft(
                        questionKey: "restaurant_tags",
                        valueType: "multi_tag",
                        stringValues: ["date night"]
                    )
                ]
            )
        )

        let visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }
        )

        XCTAssertNil(
            store.attributes(for: result.userPlaceID).first {
                $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine
            }
        )
        XCTAssertNil(visiblePlace.restaurantCuisine)
        XCTAssertEqual(visiblePlace.categoryEmoji, "🍽️")
    }

    func testEditVisitSubmissionPersistsCategoryAndRefreshesMapImmediately() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_edit_visit_category",
                name: "Category Edit",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.98,
                rawProviderType: "restaurant",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.98
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        let originalVisiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let context = MapPlaceSaveContext.editVisit(visit, visiblePlace: originalVisiblePlace)
        let coffeeAssignment = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            subcategory: "Coffee shop",
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: "restaurant"
        )
        let submission = MapPlaceSaveSubmission(
            context: context,
            candidate: context.candidate.recategorized(as: coffeeAssignment),
            status: .been,
            visibility: .followers,
            ratingScore: visit.ratingScore,
            note: visit.note,
            attributes: [],
            photoAttachments: [],
            inviteeUserIDs: [],
            reconcilesSharedVisitInvitees: false
        )

        let (saveResult, updatedVisit) = await persistScopedVisitOrWantSubmission(
            submission,
            store: store,
            backend: nil
        )
        let updatedVisiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }
        )

        XCTAssertEqual(saveResult?.userPlaceID, result.userPlaceID)
        XCTAssertEqual(updatedVisit?.id, visit.id)
        XCTAssertEqual(updatedVisiblePlace.effectiveCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(updatedVisiblePlace.effectiveSubcategory, "Coffee shop")
        XCTAssertEqual(updatedVisiblePlace.categoryEmoji, "☕️")
        XCTAssertEqual(updatedVisiblePlace.userPlace.categoryOverrideSource, PlaceCategorySource.user.rawValue)
        XCTAssertEqual(updatedVisiblePlace.userPlace.syncState, .pendingCreate)
    }

    func testDroppedPinLabelsStayPerMemoryAndOnlyAppearWhenThatMemoryIsVisible() throws {
        let currentUser = LocalProfile(
            localID: "local_profile_current",
            serverID: "user_current",
            handle: "current",
            displayName: "Current",
            syncState: .synced
        )
        let followedUser = LocalProfile(
            localID: "local_profile_followed",
            serverID: "user_followed",
            handle: "followed",
            displayName: "Followed",
            syncState: .synced
        )
        let privateUser = LocalProfile(
            localID: "local_profile_private",
            serverID: "user_private",
            handle: "private",
            displayName: "Private",
            syncState: .synced
        )
        let droppedPin = LocalPlace(
            localID: "local_place_shared_coordinate",
            serverID: "place_shared_coordinate",
            canonicalName: DroppedPinNamePolicy.fallbackName,
            category: WanderPlaceCategory.fallbackPlace,
            latitude: 34.02123,
            longitude: -118.48191,
            sourceProvider: "coordinate",
            syncState: .synced
        )
        let currentMemory = LocalUserPlace(
            localID: "local_up_current_pin",
            serverID: "up_current_pin",
            userID: currentUser.id,
            placeID: droppedPin.id,
            status: .wannaGo,
            visibility: .selfOnly,
            sourceType: "manual",
            syncState: .synced
        )
        let followedMemory = LocalUserPlace(
            localID: "local_up_followed_pin",
            serverID: "up_followed_pin",
            userID: followedUser.id,
            placeID: droppedPin.id,
            status: .been,
            visibility: .followers,
            sourceType: "manual",
            syncState: .synced
        )
        let privateMemory = LocalUserPlace(
            localID: "local_up_private_pin",
            serverID: "up_private_pin",
            userID: privateUser.id,
            placeID: droppedPin.id,
            status: .been,
            visibility: .selfOnly,
            sourceType: "manual",
            syncState: .synced
        )
        let attributes = [
            LocalPlaceAttribute(
                localID: "local_attr_current_pin_name",
                userPlaceID: currentMemory.id,
                questionKey: PlaceMemoryAttributeKeys.droppedPinName,
                valueType: "text",
                valueJSON: "\"My overlook\"",
                syncState: .synced
            ),
            LocalPlaceAttribute(
                localID: "local_attr_followed_pin_name",
                userPlaceID: followedMemory.id,
                questionKey: PlaceMemoryAttributeKeys.droppedPinName,
                valueType: "text",
                valueJSON: "\"Their overlook\"",
                syncState: .synced
            ),
            LocalPlaceAttribute(
                localID: "local_attr_private_pin_name",
                userPlaceID: privateMemory.id,
                questionKey: PlaceMemoryAttributeKeys.droppedPinName,
                valueType: "text",
                valueJSON: "\"Hidden overlook\"",
                syncState: .synced
            )
        ]
        let store = WanderStore(fixtures: WanderFixtures(
            currentUser: currentUser,
            profiles: [currentUser, followedUser, privateUser],
            places: [droppedPin],
            userPlaces: [currentMemory, followedMemory, privateMemory],
            placeAttributes: attributes,
            follows: [
                LocalFollow(
                    localID: "local_follow_current_followed",
                    followerUserID: currentUser.id,
                    followedUserID: followedUser.id,
                    source: .profile,
                    syncState: .synced
                )
            ],
            blocks: [],
            placeLists: [],
            placeListMembers: [],
            placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])
        ))

        let visiblePlaces = store.visiblePlaces()
        let namesByOwner = Dictionary(uniqueKeysWithValues: visiblePlaces.map {
            ($0.owner.id, PlaceSheetPlace(visiblePlace: $0).name)
        })

        XCTAssertEqual(droppedPin.canonicalName, DroppedPinNamePolicy.fallbackName)
        XCTAssertEqual(namesByOwner[currentUser.id], "My overlook")
        XCTAssertEqual(namesByOwner[followedUser.id], "Their overlook")
        XCTAssertNil(namesByOwner[privateUser.id])
        XCTAssertFalse(visiblePlaces.flatMap(\.attributes).contains { $0.valueJSON == "\"Hidden overlook\"" })
    }

    func testDroppedPinRenameUpdatesTheUserMemoryWithoutChangingCanonicalPlaceName() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let candidate = MapScreen.coordinateCandidate(
            at: CLLocationCoordinate2D(latitude: 34.02123, longitude: -118.48191)
        )
        let result = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.droppedPinName,
                    valueType: "text",
                    stringValue: "Ocean steps"
                )
            ]
        )
        var visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(visiblePlace.place.canonicalName, DroppedPinNamePolicy.fallbackName)
        XCTAssertEqual(PlaceSheetPlace(visiblePlace: visiblePlace).name, "Ocean steps")

        _ = try XCTUnwrap(
            store.createVisit(
                userPlaceID: result.userPlaceID,
                ratingScore: 4.5,
                attributes: [
                    PlaceAttributeDraft(
                        questionKey: PlaceMemoryAttributeKeys.droppedPinName,
                        valueType: "text",
                        stringValue: "Sunset stairs"
                    )
                ]
            )
        )
        visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(visiblePlace.place.canonicalName, DroppedPinNamePolicy.fallbackName)
        XCTAssertEqual(PlaceSheetPlace(visiblePlace: visiblePlace).name, "Sunset stairs")
        XCTAssertEqual(visiblePlace.userPlace.ratingScore, 4.5)
    }

    func testImportStatusChangePreservesClassificationButDoesNotCarryNotesBetweenMemories() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let originalCandidate = PlaceCandidate(
            id: "mapkit_import_optional_details",
            name: "Imported Place",
            category: WanderPlaceCategory.restaurantsFood,
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            latitude: 34.0407,
            longitude: -118.2354,
            confidence: 0.98
        )
        let result = store.saveCandidate(
            originalCandidate,
            status: .been,
            visibility: .mutuals,
            note: "stale import note",
            sourceType: .link
        )
        let originalVisit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let coffeeAssignment = PlaceCategoryAssignment(
            primaryCategory: WanderPlaceCategory.coffeeTeaSweets,
            subcategory: "Coffee shop",
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: "restaurant"
        )
        let editedAttributes = [
            PlaceAttributeDraft(
                questionKey: "coffee_tags",
                valueType: "multi_tag",
                stringValues: ["quiet", "wifi solid"]
            )
        ]
        _ = try XCTUnwrap(
            store.updateVisit(
                visitID: originalVisit.id,
                note: "edited in Optional Details",
                attributes: editedAttributes,
                categoryCandidate: originalCandidate.recategorized(as: coffeeAssignment),
                visibility: .selfOnly,
                replacesNote: true
            )
        )

        _ = try XCTUnwrap(
            store.changeImportedSaveStatus(userPlaceID: result.userPlaceID, to: .wannaGo)
        )
        var visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )
        XCTAssertEqual(visiblePlace.userPlace.status, .wannaGo)
        XCTAssertNil(visiblePlace.userPlace.note)
        XCTAssertEqual(visiblePlace.userPlace.visibility, .selfOnly)
        XCTAssertEqual(visiblePlace.effectiveCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(visiblePlace.effectiveSubcategory, "Coffee shop")
        XCTAssertEqual(
            store.attributes(for: result.userPlaceID).first { $0.questionKey == "coffee_tags" }?.valueJSON,
            "[\"quiet\",\"wifi solid\"]"
        )
        XCTAssertTrue(store.visits(for: result.userPlaceID).isEmpty)

        _ = try XCTUnwrap(
            store.changeImportedSaveStatus(
                userPlaceID: result.userPlaceID,
                to: .been,
                ratingScore: 4.5
            )
        )
        visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )
        let restoredVisit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        XCTAssertEqual(visiblePlace.userPlace.status, .been)
        XCTAssertEqual(visiblePlace.effectiveCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertNil(restoredVisit.note)
        XCTAssertEqual(restoredVisit.ratingScore, 4.5)
        XCTAssertEqual(
            VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: restoredVisit.attributeAnswersJSON),
            editedAttributes
        )
    }

    func testVisitAttributeAnswerDraftsRoundTripForDefaults() {
        let drafts = [
            PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet", "wifi solid"]),
            PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.restaurantCuisine, valueType: "single_choice", stringValue: "Thai"),
            PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels, valueType: "personal_label", stringValues: ["date night"])
        ]

        let restored = VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: VisitAttributeAnswers.encoded(from: drafts))
        let restoredByKey = Dictionary(uniqueKeysWithValues: restored.map { ($0.questionKey, $0) })

        XCTAssertEqual(restoredByKey["coffee_tags"]?.valueJSON, "[\"quiet\",\"wifi solid\"]")
        XCTAssertEqual(restoredByKey[PlaceMemoryAttributeKeys.restaurantCuisine]?.valueJSON, "\"Thai\"")
        XCTAssertEqual(restoredByKey[PlaceMemoryAttributeKeys.personalLabels]?.valueJSON, "[\"date night\"]")
    }

    func testAddVisitContextCarriesVisitDetailsWithoutPrefillingTagsOrLabels() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_add_visit_defaults",
                name: "Add Visit Defaults Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .wannaGo,
            visibility: .followers,
            note: "want because patio",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["sunny"]),
                PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels, valueType: "personal_label", stringValues: ["weekend"])
            ]
        )
        let wantPlace = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })

        let wantContext = MapPlaceSaveContext.addVisitVisiblePlace(
            wantPlace,
            attributes: store.attributes(for: result.userPlaceID),
            latestVisit: nil
        )

        XCTAssertEqual(PlaceSheetAction.topLevelAction(currentUserSave: nil), .add)
        XCTAssertEqual(PlaceSheetAction.topLevelAction(currentUserSave: wantPlace), .editWant)
        XCTAssertEqual(PlaceSheetAction.mapTopLevelAction(currentUserSave: nil), .add)
        XCTAssertEqual(PlaceSheetAction.mapTopLevelAction(currentUserSave: wantPlace), .reselectWant)
        XCTAssertEqual(PlaceSheetAction.reselectWant.systemImage, "plus")
        XCTAssertEqual(PlaceSheetAction.reselectWant.accessibilityLabel, "Check in or Wanna")
        XCTAssertEqual(wantContext.initialStatus, .been)
        XCTAssertFalse(wantContext.hasPriorCheckIn)
        XCTAssertNil(wantContext.initialRatingScore)
        XCTAssertEqual(wantContext.initialNote, "")
        XCTAssertNil(wantContext.initialAnswers["coffee_tags"])
        XCTAssertTrue(wantContext.initialPersonalLabels.isEmpty)

        let reselectedWantContext = MapPlaceSaveContext.reselectCurrentUserSave(
            wantPlace,
            defaultVisibility: .followers,
            attributes: store.attributes(for: wantPlace.userPlace.id),
            latestVisit: nil
        )
        if case .add(let sourceType) = reselectedWantContext.mode {
            XCTAssertEqual(sourceType, .manual)
        } else {
            XCTFail("Tapping the map plus should open the status chooser")
        }
        XCTAssertTrue(reselectedWantContext.requiresStatusConfirmation)
        XCTAssertTrue(reselectedWantContext.allowsWannaGoSelection)
        XCTAssertEqual(
            MapPlaceSaveContext.currentUserSave(
                matching: reselectedWantContext.candidate,
                in: [wantPlace]
            )?.userPlace.id,
            wantPlace.userPlace.id
        )
        let sameNameDifferentPlace = PlaceCandidate(
            id: "mapkit_other_add_visit_defaults_cafe",
            name: reselectedWantContext.candidate.name,
            category: reselectedWantContext.candidate.category,
            address: "999 Different Street",
            latitude: 35.001,
            longitude: -117.001,
            sourceProvider: reselectedWantContext.candidate.sourceProvider,
            sourceProviderPlaceID: "mapkit_other_add_visit_defaults_cafe",
            confidence: reselectedWantContext.candidate.confidence
        )
        XCTAssertNil(
            MapPlaceSaveContext.currentUserSave(
                matching: sameNameDifferentPlace,
                in: [wantPlace]
            ),
            "A same-named place at another location must not open this Wanna record"
        )
        if case .editWant(let editedPlace) = reselectedWantContext
            .resolvingExistingSave(selection: .wannaGo)
            .mode {
            XCTAssertEqual(editedPlace.userPlace.id, wantPlace.userPlace.id)
        } else {
            XCTFail("Selecting Wanna again should open the existing Wanna editor")
        }
        if case .addVisit(let checkedInPlace) = reselectedWantContext
            .resolvingExistingSave(selection: .been)
            .mode {
            XCTAssertEqual(checkedInPlace.userPlace.id, wantPlace.userPlace.id)
        } else {
            XCTFail("Selecting Check in should convert the existing Wanna through add-visit")
        }

        let latestVisit = try XCTUnwrap(store.createVisit(
            userPlaceID: result.userPlaceID,
            note: "actual visit",
            ratingScore: 4.5,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"]),
                PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels, valueType: "personal_label", stringValues: ["return"])
            ]
        ))
        let beenPlace = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID })

        let visitContext = MapPlaceSaveContext.addVisitVisiblePlace(
            beenPlace,
            attributes: store.attributes(for: result.userPlaceID),
            latestVisit: latestVisit
        )

        XCTAssertEqual(visitContext.initialStatus, .been)
        XCTAssertTrue(visitContext.hasPriorCheckIn)
        XCTAssertEqual(visitContext.initialRatingScore, 4.5)
        XCTAssertEqual(visitContext.initialNote, "")
        XCTAssertNil(visitContext.initialAnswers["coffee_tags"])
        XCTAssertTrue(visitContext.initialPersonalLabels.isEmpty)

        let reselectedBeenContext = MapPlaceSaveContext.addCandidate(
            visitContext.candidate,
            sourceType: .currentLocation,
            defaultVisibility: .followers,
            currentUserSave: beenPlace,
            latestVisit: latestVisit
        )
        XCTAssertFalse(reselectedBeenContext.allowsWannaGoSelection)
        XCTAssertEqual(reselectedBeenContext.initialStatus, .been)
        XCTAssertEqual(PlaceSheetAction.mapTopLevelAction(currentUserSave: beenPlace), .addVisit)
        if case .addVisit(let checkedInPlace) = reselectedBeenContext
            .resolvingExistingSave(selection: .wannaGo)
            .mode {
            XCTAssertEqual(checkedInPlace.userPlace.id, beenPlace.userPlace.id)
        } else {
            XCTFail("A checked-in place must stay on the check-in path")
        }
    }

    func testOldSnapshotWithoutVisitsBackfillsExistingBeenSaves() throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mapkit_old_snapshot",
                name: "Old Snapshot Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "legacy save",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"])
            ]
        )

        let encoder = JSONEncoder()
        let snapshotData = try encoder.encode(WanderStoreSnapshot(store: firstStore))
        var snapshotObject = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshotData) as? [String: Any])
        snapshotObject.removeValue(forKey: "placeVisits")
        snapshotObject.removeValue(forKey: "visitPhotos")
        let oldSnapshotData = try JSONSerialization.data(withJSONObject: snapshotObject, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true, attributes: nil)
        try oldSnapshotData.write(to: fixture.directory.appendingPathComponent("store.json"), options: [.atomic])

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let restoredVisit = relaunchedStore.visits(for: result.userPlaceID).first

        XCTAssertEqual(relaunchedStore.visits(for: result.userPlaceID).count, 1)
        XCTAssertEqual(restoredVisit?.backfilledFromUserPlace, true)
        XCTAssertEqual(restoredVisit?.note, "legacy save")
        XCTAssertEqual(restoredVisit?.ratingScore, 4)
        XCTAssertEqual(restoredVisit?.tags, ["quiet"])
    }

    func testDeletingOnlyVisitUnsavesPlaceWithoutWannaFallback() {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_delete_visit",
                name: "Delete Visit Cafe",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "only visit",
            sourceType: .manual,
            ratingScore: 4
        )
        let visit = store.visits(for: result.userPlaceID).first
        let photo = store.createVisitPhoto(
            visitID: visit?.id ?? "",
            localAssetRef: "saba-cafe-and-surf.jpg"
        )
        photo?.serverID = "photo_saba_cafe_and_surf"

        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace.status, .been)
        XCTAssertTrue(store.deleteVisit(visitID: visit?.id ?? ""))

        XCTAssertTrue(store.visits(for: result.userPlaceID).isEmpty)
        XCTAssertEqual(
            store.deletedVisitPhotoReferenceIDs,
            Set([photo?.localID, photo?.serverID].compactMap { $0 })
        )
        XCTAssertFalse(store.currentUserVisiblePlaces.contains { $0.userPlace.id == result.userPlaceID })
    }

    func testFailedRemoteCheckInDeletePersistsAcrossRelaunchAndRetries() async throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
        let visitID: String

        do {
            let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
            firstStore.apply(authState: .signedIn(session))
            let saveRepository = FakeUserPlaceRepository(
                result: SaveResult(
                    userPlaceID: "up_remote_retry",
                    syncState: .synced,
                    placeID: "place_remote_retry"
                )
            )
            let saved = await firstStore.saveCandidate(
                PlaceCandidate(
                    id: "mapkit_delete_retry",
                    name: "Retry Check-In Cafe",
                    category: "coffee",
                    latitude: 34.0407,
                    longitude: -118.2354,
                    confidence: 0.92
                ),
                status: .been,
                visibility: .followers,
                note: "retry this delete",
                sourceType: .manual,
                ratingScore: 4,
                backend: WanderBackend(userPlaceRepository: saveRepository)
            )
            let visit = try XCTUnwrap(firstStore.visits(for: saved.userPlaceID).first)
            visitID = try XCTUnwrap(visit.serverID)

            let failingRepository = FakeUserPlaceRepository(
                error: WanderRemoteError.invalidResponse("network down")
            )
            let deleted = await firstStore.deleteVisit(
                visitID: visit.id,
                backend: WanderBackend(userPlaceRepository: failingRepository)
            )

            XCTAssertTrue(deleted)
            XCTAssertEqual(failingRepository.deletedCheckInIDs, [visitID])
            XCTAssertEqual(
                firstStore.placeVisits.first { $0.serverID == visitID }?.syncState,
                .failed
            )
            XCTAssertNotNil(firstStore.placeVisits.first { $0.serverID == visitID }?.deletedAt)
        }

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        relaunchedStore.apply(authState: .signedIn(session))
        XCTAssertEqual(
            relaunchedStore.placeVisits.first { $0.serverID == visitID }?.syncState,
            .failed
        )
        XCTAssertNotNil(relaunchedStore.placeVisits.first { $0.serverID == visitID }?.deletedAt)

        let retryRepository = FakeUserPlaceRepository()
        let retried = await relaunchedStore.retryPendingVisitDeletes(
            backend: WanderBackend(userPlaceRepository: retryRepository)
        )

        XCTAssertEqual(retried, 1)
        XCTAssertEqual(retryRepository.deletedCheckInIDs, [visitID])
        XCTAssertEqual(
            relaunchedStore.placeVisits.first { $0.serverID == visitID }?.syncState,
            .tombstoned
        )
    }

    func testRemoteCalendarCheckInDeleteIsAcceptedAndDoesNotReappearFromCache() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_current"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userID, displayName: "Current", handle: "current")
            )
        )
        let visitedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-14T07:00:00Z")
        )
        let visiblePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_remote_delete",
            placeID: "place_remote_delete",
            name: "Little Bean Cold Brew",
            status: .been,
            savedAt: visitedAt,
            visitedAt: visitedAt
        )
        let visitRepository = FakeVisitRepository(
            visitsByUserPlaceID: [
                visiblePlace.userPlace.id: [
                    PlaceVisitResult(
                        visitID: "visit_remote_delete",
                        userPlaceID: visiblePlace.userPlace.id,
                        visitedAt: visitedAt,
                        note: nil,
                        ratingScore: 5,
                        tags: [],
                        backfilledFromUserPlace: false
                    )
                ]
            ]
        )
        let hydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: [visiblePlace]]
                ),
                visitRepository: visitRepository
            )
        )
        XCTAssertTrue(hydrated)
        XCTAssertEqual(
            ProfileActivityPresenter.items(
                visiblePlaces: store.currentUserCalendarProjection.visiblePlaces,
                visits: store.currentUserCalendarProjection.visits,
                currentUserID: userID
            ).count,
            1
        )

        let failingRepository = FakeUserPlaceRepository(
            error: WanderRemoteError.invalidResponse("network down")
        )
        let deleted = await store.deleteVisit(
            visitID: "visit_remote_delete",
            backend: WanderBackend(userPlaceRepository: failingRepository)
        )

        XCTAssertTrue(deleted)
        XCTAssertEqual(failingRepository.deletedCheckInIDs, ["visit_remote_delete"])
        XCTAssertEqual(
            store.placeVisits.first { $0.serverID == "visit_remote_delete" }?.syncState,
            .failed
        )
        XCTAssertNotNil(
            store.placeVisits.first { $0.serverID == "visit_remote_delete" }?.deletedAt
        )
        XCTAssertTrue(store.currentUserCalendarProjection.visiblePlaces.isEmpty)
        XCTAssertTrue(store.currentUserCalendarProjection.visits.isEmpty)
        XCTAssertTrue(
            ProfileActivityPresenter.items(
                visiblePlaces: store.currentUserCalendarProjection.visiblePlaces,
                visits: store.currentUserCalendarProjection.visits,
                currentUserID: userID
            ).isEmpty
        )

        let deletedParent = try XCTUnwrap(
            store.userPlaces.first { $0.serverID == visiblePlace.userPlace.serverID }
        )
        XCTAssertNotNil(deletedParent.deletedAt)
        XCTAssertEqual(deletedParent.syncState, .pendingDelete)

        let staleVisiblePlace = makeRemoteCalendarVisiblePlace(
            owner: store.currentUser,
            userPlaceID: "up_remote_delete",
            placeID: "place_remote_delete",
            name: "Little Bean Cold Brew",
            status: .been,
            savedAt: visitedAt,
            visitedAt: visitedAt
        )
        let staleHydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: [staleVisiblePlace]]
                ),
                visitRepository: FakeVisitRepository(
                    visitsByUserPlaceID: [
                        staleVisiblePlace.userPlace.id: [
                            PlaceVisitResult(
                                visitID: "visit_remote_delete",
                                userPlaceID: staleVisiblePlace.userPlace.id,
                                visitedAt: visitedAt,
                                note: nil,
                                ratingScore: 5,
                                tags: [],
                                backfilledFromUserPlace: false
                            )
                        ]
                    ]
                )
            )
        )

        XCTAssertTrue(staleHydrated)
        XCTAssertTrue(store.currentUserCalendarProjection.visiblePlaces.isEmpty)
        XCTAssertTrue(store.currentUserCalendarProjection.visits.isEmpty)
        XCTAssertTrue(
            ProfileActivityPresenter.items(
                visiblePlaces: store.currentUserCalendarProjection.visiblePlaces,
                visits: store.currentUserCalendarProjection.visits,
                currentUserID: userID
            ).isEmpty
        )
    }

    func testPendingRemoteDeletesStayShadowedWhenLocalMutationClearsAuthoritativeCalendar() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let userID = "user_current"
        store.apply(
            authState: .signedIn(
                AuthSession(userID: userID, displayName: "Current", handle: "current")
            )
        )
        let savedAt = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-02T18:00:00Z")
        )

        func serverSnapshot() -> [VisiblePlace] {
            [
                makeRemoteCalendarVisiblePlace(
                    owner: store.currentUser,
                    userPlaceID: "up_failed_been_delete",
                    placeID: "place_failed_been_delete",
                    name: "Previously Deleted Check-in",
                    status: .been,
                    savedAt: savedAt,
                    visitedAt: savedAt
                ),
                makeRemoteCalendarVisiblePlace(
                    owner: store.currentUser,
                    userPlaceID: "up_failed_wanna_delete",
                    placeID: "place_failed_wanna_delete",
                    name: "Previously Deleted Wanna",
                    status: .wannaGo,
                    savedAt: savedAt
                ),
                makeRemoteCalendarVisiblePlace(
                    owner: store.currentUser,
                    userPlaceID: "up_active_been",
                    placeID: "place_active_been",
                    name: "Active Check-in",
                    status: .been,
                    savedAt: savedAt,
                    visitedAt: savedAt
                )
            ]
        }

        let initialHydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: serverSnapshot()]
                )
            )
        )
        XCTAssertTrue(initialHydrated)

        let failingRepository = FakeUserPlaceRepository(
            error: WanderRemoteError.invalidResponse("missing delete RPC")
        )
        let failedBeenDelete = await store.removeSave(
            userPlaceID: "up_failed_been_delete",
            backend: WanderBackend(userPlaceRepository: failingRepository)
        )
        let failedWannaDelete = await store.removeSave(
            userPlaceID: "up_failed_wanna_delete",
            backend: WanderBackend(userPlaceRepository: failingRepository)
        )
        XCTAssertEqual(failedBeenDelete?.syncState, .failed)
        XCTAssertEqual(failedWannaDelete?.syncState, .failed)

        let rehydrated = await store.refreshRemoteCurrentUserCalendarData(
            backend: WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(
                    userPlacesByUserID: [userID: serverSnapshot()]
                )
            )
        )
        XCTAssertTrue(rehydrated)
        XCTAssertTrue(store.currentUserCalendarProjection.isAuthoritative)
        XCTAssertEqual(
            store.currentUserCalendarProjection.profileStats(
                currentUserID: userID,
                friends: 0
            ),
            ProfileStats(been: 1, checkIns: 1, wanna: 0, friends: 0)
        )

        _ = store.saveCandidate(
            PlaceCandidate(
                id: "unrelated_local_wanna",
                name: "Unrelated Local Wanna",
                category: "coffee",
                latitude: 49.28,
                longitude: -123.12,
                confidence: 0.95
            ),
            status: .wannaGo,
            visibility: .selfOnly,
            note: nil,
            sourceType: .manual
        )

        let projection = store.currentUserCalendarProjection
        XCTAssertFalse(projection.isAuthoritative)
        XCTAssertEqual(
            projection.profileStats(currentUserID: userID, friends: 0),
            ProfileStats(been: 1, checkIns: 1, wanna: 1, friends: 0)
        )
        XCTAssertFalse(
            projection.visiblePlaces.contains {
                $0.userPlace.id == "up_failed_been_delete"
                    || $0.userPlace.id == "up_failed_wanna_delete"
            }
        )
    }

    func testFailedRemoteWannaDeletePersistsAcrossRelaunchAndRetries() async throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")
        let remoteUserPlaceID = "8b567297-6e55-45a4-ae58-79b4288aa0a6"
        let remotePlaceID = "93722c05-6b0d-4dfe-a687-85d73f8e7aa1"

        do {
            let firstStore = WanderStore(
                fixtures: WanderFixtures.empty(),
                persistence: fixture.persistence
            )
            firstStore.apply(authState: .signedIn(session))
            let remotePlace = VisiblePlace(
                id: remoteUserPlaceID,
                place: LocalPlace(
                    localID: remotePlaceID,
                    serverID: remotePlaceID,
                    canonicalName: "Retry Wanna Cafe",
                    category: "coffee",
                    latitude: 34.0407,
                    longitude: -118.2354,
                    syncState: .synced
                ),
                userPlace: LocalUserPlace(
                    localID: remoteUserPlaceID,
                    serverID: remoteUserPlaceID,
                    userID: session.userID,
                    placeID: remotePlaceID,
                    status: .wannaGo,
                    visibility: .followers,
                    sourceType: "manual",
                    syncState: .synced
                ),
                owner: firstStore.currentUser
            )
            await firstStore.refreshRemoteVisiblePlaces(
                in: MapViewport(
                    minLatitude: 34,
                    minLongitude: -119,
                    maxLatitude: 35,
                    maxLongitude: -118
                ),
                backend: WanderBackend(
                    placeRepository: FakePlaceRepository(places: [remotePlace])
                )
            )
            XCTAssertTrue(
                firstStore.currentUserVisiblePlaces.contains {
                    $0.userPlace.id == remoteUserPlaceID
                }
            )

            let failingRepository = FakeUserPlaceRepository(
                error: WanderRemoteError.invalidResponse("network down")
            )
            let removed = await firstStore.removeSave(
                userPlaceID: remoteUserPlaceID,
                backend: WanderBackend(userPlaceRepository: failingRepository)
            )

            XCTAssertEqual(removed?.syncState, .failed)
            XCTAssertEqual(failingRepository.deletedUserPlaceIDs, [remoteUserPlaceID])
            XCTAssertEqual(
                firstStore.userPlaces.first { $0.id == remoteUserPlaceID }?.syncState,
                .failed
            )
            XCTAssertNotNil(
                firstStore.userPlaces.first { $0.id == remoteUserPlaceID }?.deletedAt
            )
            XCTAssertFalse(
                firstStore.currentUserCalendarProjection.userPlaces.contains {
                    $0.id == remoteUserPlaceID
                }
            )
        }

        let relaunchedStore = WanderStore(
            fixtures: WanderFixtures.empty(),
            persistence: fixture.persistence
        )
        relaunchedStore.apply(authState: .signedIn(session))
        XCTAssertEqual(
            relaunchedStore.userPlaces.first { $0.id == remoteUserPlaceID }?.syncState,
            .failed
        )
        XCTAssertNotNil(
            relaunchedStore.userPlaces.first { $0.id == remoteUserPlaceID }?.deletedAt
        )

        let retryRepository = FakeUserPlaceRepository()
        let retried = await relaunchedStore.retryPendingUserPlaceDeletes(
            backend: WanderBackend(userPlaceRepository: retryRepository)
        )

        XCTAssertEqual(retried, 1)
        XCTAssertEqual(retryRepository.deletedUserPlaceIDs, [remoteUserPlaceID])
        XCTAssertEqual(
            relaunchedStore.userPlaces.first { $0.id == remoteUserPlaceID }?.syncState,
            .tombstoned
        )
    }

    func testFilePersistenceRestoresPrivateProfileModeAfterRelaunch() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.defaultVisibility = .followers
        firstStore.setPrivateProfile(true)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertTrue(relaunchedStore.isPrivateProfile)
        XCTAssertTrue(relaunchedStore.currentUser.isPrivateProfile)
        XCTAssertEqual(relaunchedStore.defaultVisibility, .followers)
        XCTAssertEqual(relaunchedStore.effectiveDefaultVisibility, .selfOnly)
    }

    func testPendingSharedVisitInviteOutboxPersistsAndStaysScopedToItsOwner() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        firstStore.queueSharedVisitInvites(
            sourceVisitID: "visit-local-1",
            inviteeUserIDs: ["user_sarah", "user_sarah", "user_ryan"]
        )

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        let pending = relaunchedStore.pendingSharedVisitInvites.first

        XCTAssertEqual(relaunchedStore.pendingSharedVisitInvites.count, 1)
        XCTAssertEqual(pending?.ownerUserID, "user_joe")
        XCTAssertEqual(pending?.sourceVisitID, "visit-local-1")
        XCTAssertEqual(pending?.inviteeUserIDs, ["user_ryan", "user_sarah"])

        relaunchedStore.apply(authState: .signedIn(AuthSession(userID: "user_sarah", displayName: "Sarah", handle: "sarah")))
        XCTAssertEqual(relaunchedStore.pendingSharedVisitInvites.first?.ownerUserID, "user_joe")
    }

    func testPendingSharedVisitInviteOutboxDrainsOnceSourceVisitIsSynced() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let saved = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_shared_outbox",
                name: "Shared Outbox Cafe",
                category: "coffee_tea_sweets",
                latitude: 34.04,
                longitude: -118.24,
                confidence: 1
            ),
            status: .been,
            visibility: .mutuals,
            note: "great patio",
            sourceType: .manual,
            ratingScore: 4.5
        )
        let userPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace
        )
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        userPlace.serverID = "82000000-0000-0000-0000-000000000001"
        userPlace.syncStateRaw = SyncState.synced.rawValue
        visit.serverID = "83000000-0000-0000-0000-000000000001"
        visit.syncStateRaw = SyncState.synced.rawValue

        store.queueSharedVisitInvites(
            sourceVisitID: visit.id,
            inviteeUserIDs: ["user_sarah", "user_maya"]
        )
        let repository = FakeSharedVisitRepository()

        let sentCount = await store.retryPendingSharedVisitInvites(
            backend: WanderBackend(sharedVisitRepository: repository)
        )

        XCTAssertEqual(sentCount, 2)
        XCTAssertTrue(store.pendingSharedVisitInvites.isEmpty)
        XCTAssertEqual(
            repository.setRequests,
            [
                FakeSharedVisitRepository.InviteRequest(
                    sourceVisitID: "83000000-0000-0000-0000-000000000001",
                    inviteeUserIDs: ["user_maya", "user_sarah"]
                )
            ]
        )
    }

    func testSharedVisitInviteeReconciliationReplacesQueuedSelectionAndCanClearIt() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let saved = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_shared_edit",
                name: "Shared Edit Cafe",
                category: "coffee_tea_sweets",
                latitude: 34.04,
                longitude: -118.24,
                confidence: 1
            ),
            status: .been,
            visibility: .mutuals,
            note: nil,
            sourceType: .manual,
            ratingScore: 4
        )
        let userPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace
        )
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        userPlace.serverID = "82000000-0000-0000-0000-000000000002"
        userPlace.syncStateRaw = SyncState.synced.rawValue
        visit.serverID = "83000000-0000-0000-0000-000000000002"
        visit.syncStateRaw = SyncState.synced.rawValue

        store.queueSharedVisitInviteeReconciliation(
            sourceVisitID: visit.id,
            inviteeUserIDs: ["user_sarah", "user_maya"]
        )
        store.queueSharedVisitInviteeReconciliation(
            sourceVisitID: visit.id,
            inviteeUserIDs: []
        )

        XCTAssertEqual(store.pendingSharedVisitInvites.count, 1)
        XCTAssertEqual(store.pendingSharedVisitInvites.first?.inviteeUserIDs, [])

        let repository = FakeSharedVisitRepository()
        _ = await store.retryPendingSharedVisitInvites(
            backend: WanderBackend(sharedVisitRepository: repository)
        )

        XCTAssertTrue(store.pendingSharedVisitInvites.isEmpty)
        XCTAssertEqual(
            repository.setRequests,
            [
                FakeSharedVisitRepository.InviteRequest(
                    sourceVisitID: "83000000-0000-0000-0000-000000000002",
                    inviteeUserIDs: []
                )
            ]
        )
    }

    func testSharedVisitInviteeSelectionLoadsPendingOutboxBeforeRemoteState() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let saved = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_shared_pending_selection",
                name: "Pending Shared Cafe",
                category: "coffee_tea_sweets",
                latitude: 34.04,
                longitude: -118.24,
                confidence: 1
            ),
            status: .been,
            visibility: .mutuals,
            note: nil,
            sourceType: .manual,
            ratingScore: 4
        )
        let userPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == saved.userPlaceID }?.userPlace
        )
        let visit = try XCTUnwrap(store.visits(for: saved.userPlaceID).first)
        userPlace.serverID = "82000000-0000-0000-0000-000000000003"
        visit.serverID = "83000000-0000-0000-0000-000000000003"
        store.queueSharedVisitInviteeReconciliation(
            sourceVisitID: visit.id,
            inviteeUserIDs: ["user_sarah"]
        )
        let repository = FakeSharedVisitRepository()
        repository.activeInviteeUserIDs = ["user_maya"]

        let inviteeUserIDs = try await store.sharedVisitInviteeUserIDs(
            sourceVisitID: visit.id,
            backend: WanderBackend(sharedVisitRepository: repository)
        )

        XCTAssertEqual(inviteeUserIDs, ["user_sarah"])
        XCTAssertTrue(repository.inviteeListRequests.isEmpty)
    }

    func testSharedVisitInboxDiscardsCompletionFromPreviousAccount() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let repository = FakeSharedVisitRepository()
        repository.shouldSuspendInbox = true
        let backend = WanderBackend(sharedVisitRepository: repository)

        let refreshTask = Task { @MainActor in
            await store.refreshSharedVisitInbox(backend: backend)
        }
        while !repository.hasSuspendedInboxRequest {
            await Task.yield()
        }

        store.apply(authState: .signedIn(AuthSession(userID: "user_sarah", displayName: "Sarah", handle: "sarah")))
        repository.resumeInbox()
        _ = await refreshTask.value

        XCTAssertEqual(store.currentUser.id, "user_sarah")
        XCTAssertNil(store.sharedVisitInboxUserID)
        XCTAssertTrue(store.sharedVisitInvitations.isEmpty)
    }

    func testPrivateProfileHydrationPreservesPendingSharedVisitInbox() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let invitation = makeSharedVisitInvitation()
        let sharedVisitRepository = FakeSharedVisitRepository()
        sharedVisitRepository.inboxInvitations = [invitation]

        let loaded = await store.refreshSharedVisitInbox(
            backend: WanderBackend(sharedVisitRepository: sharedVisitRepository)
        )

        XCTAssertTrue(loaded)
        XCTAssertEqual(store.sharedVisitInvitations, [invitation])

        let profileRepository = FakeProfileRepository(
            currentProfile: LocalProfile(
                localID: "local_profile_joe",
                serverID: "user_joe",
                handle: "joe",
                displayName: "Joe",
                isPrivateProfile: true,
                defaultVisibility: .selfOnly,
                syncState: .synced
            )
        )
        _ = await store.refreshRemoteCurrentProfile(
            backend: WanderBackend(profileRepository: profileRepository)
        )

        XCTAssertTrue(store.currentUser.isPrivateProfile)
        XCTAssertEqual(store.sharedVisitInvitations, [invitation])
        XCTAssertEqual(store.sharedVisitInboxUserID, "user_joe")
    }

    func testDecliningSharedVisitRemovesTheRealInboxInvitation() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        let invitation = makeSharedVisitInvitation(participantID: "participant-decline", generation: 3)
        let repository = FakeSharedVisitRepository()
        repository.inboxInvitations = [invitation]
        let backend = WanderBackend(sharedVisitRepository: repository)
        _ = await store.refreshSharedVisitInbox(backend: backend)

        let declined = await store.declineSharedVisit(
            participantID: invitation.participantID,
            generation: invitation.invitationGeneration,
            backend: backend
        )

        XCTAssertTrue(declined)
        XCTAssertTrue(store.sharedVisitInvitations.isEmpty)
        XCTAssertEqual(
            repository.declineRequests,
            [.init(participantID: "participant-decline", generation: 3)]
        )
    }

    func testOldPersistenceSnapshotClearsSavedPlaceDataButKeepsAccountGraph() throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        firstStore.defaultVisibility = .mutuals
        firstStore.follow(userID: "user_maya", source: .profile)
        firstStore.block(userID: "user_ryan")
        _ = firstStore.createUnresolvedDraft(sourceType: .link, originalInput: "https://maps.app.goo.gl/stale")
        _ = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mapkit_stale_maru",
                name: "Stale Maru",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "old local row",
            sourceType: .manual,
            ratingScore: 4
        )

        let url = fixture.directory.appendingPathComponent("store.json")
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "savedPlaceResetVersion")
        let oldSnapshotData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try oldSnapshotData.write(to: url)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertEqual(relaunchedStore.currentUser.id, "user_live")
        XCTAssertEqual(relaunchedStore.defaultVisibility, .mutuals)
        XCTAssertEqual(relaunchedStore.relationship(to: "user_maya"), .follower)
        XCTAssertEqual(relaunchedStore.blockedProfiles().map(\.id), ["user_ryan"])
        XCTAssertTrue(relaunchedStore.visiblePlaces().isEmpty)
        XCTAssertTrue(relaunchedStore.unresolvedDrafts.isEmpty)
        XCTAssertTrue(relaunchedStore.sourceArtifacts.isEmpty)
        XCTAssertTrue(relaunchedStore.extractionJobs.isEmpty)

        let cleanedData = try Data(contentsOf: url)
        let cleanedSnapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: cleanedData) as? [String: Any])
        XCTAssertEqual(cleanedSnapshot["savedPlaceResetVersion"] as? Int, WanderStoreSnapshot.currentSavedPlaceResetVersion)
        XCTAssertEqual((cleanedSnapshot["places"] as? [Any])?.count, 0)
        XCTAssertEqual((cleanedSnapshot["userPlaces"] as? [Any])?.count, 0)
    }

    func testFilePersistenceRestoresDraftsAndSocialGraphAfterRelaunch() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.follow(userID: "user_maya", source: .contacts)
        firstStore.block(userID: "user_ryan")
        _ = firstStore.createUnresolvedDraft(sourceType: .link, originalInput: "https://maps.app.goo.gl/example")

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertEqual(relaunchedStore.relationship(to: "user_maya"), .follower)
        XCTAssertEqual(relaunchedStore.blockedProfiles().map(\.id), ["user_ryan"])
        XCTAssertEqual(relaunchedStore.unresolvedDrafts.map(\.sourceType), [.link])
        XCTAssertEqual(relaunchedStore.sourceArtifacts.map(\.type), ["url"])
        XCTAssertEqual(relaunchedStore.extractionJobs.map(\.sourceType), ["link"])
    }

    func testFilePersistenceRestoresCurrentUserAvatarURLAfterRelaunch() {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let avatarURL = "file:///tmp/wander-avatar.jpg"

        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.updateCurrentUserAvatarURL(avatarURL)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertEqual(relaunchedStore.currentUser.avatarURL, avatarURL)
        XCTAssertEqual(relaunchedStore.profileState(for: relaunchedStore.currentUser.id)?.shell.avatarURL, avatarURL)
    }

    func testUpdatingCandidateReplacesQuestionAttributesWhenProvided() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "place_woodcat",
            name: "Woodcat Coffee",
            category: "coffee",
            latitude: 34.077,
            longitude: -118.260,
            confidence: 1
        )

        let result = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "changed answers",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"])
            ]
        )

        let attributes = store.attributes(for: result.userPlaceID)
        XCTAssertEqual(attributes.map(\.questionKey), ["coffee_tags"])
        XCTAssertEqual(attributes[0].valueJSON, "[\"quiet\"]")
    }

    func testUpdatingCandidateCanPersistCategoryCorrectionAndPersonalLabels() {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "place_woodcat",
            name: "Woodcat Coffee",
            category: "coffee shop",
            latitude: 34.077,
            longitude: -118.260,
            confidence: 1
        )

        let result = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "separate labels from smart answers",
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(questionKey: "work_setup", valueType: "single_choice", stringValue: "yes"),
                PlaceAttributeDraft(questionKey: PlaceMemoryAttributeKeys.personalLabels, valueType: "personal_label", stringValues: ["work-friendly", "joe rec"])
            ]
        )

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        let attributes = store.attributes(for: result.userPlaceID)

        XCTAssertEqual(saved?.place.category, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(saved?.place.subcategory, "Coffee shop")
        XCTAssertEqual(saved?.effectiveCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(attributes.map(\.questionKey), [PlaceMemoryAttributeKeys.personalLabels, "work_setup"])
        XCTAssertEqual(attributes.first { $0.questionKey == PlaceMemoryAttributeKeys.personalLabels }?.valueJSON, "[\"work-friendly\",\"joe rec\"]")
    }

    func testProviderSubcategoryFiltersByPrimaryCategory() {
        let store = makeStore()
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "place_jitlada",
                name: "Jitlada",
                category: "thai restaurant",
                rawProviderType: "thai restaurant",
                latitude: 34.098,
                longitude: -118.306,
                confidence: 1
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        XCTAssertEqual(saved?.place.category, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(saved?.place.subcategory, "Restaurant")
        XCTAssertTrue(store.visiblePlaces(filters: PlaceFilters(categories: [WanderPlaceCategory.restaurantsFood])).contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertTrue(store.visiblePlaces(filters: PlaceFilters(categories: ["restaurant"])).contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertTrue(store.visiblePlaces(filters: PlaceFilters(categories: ["thai restaurant"])).contains { $0.userPlace.id == result.userPlaceID })
    }

    func testUserCategoryOverrideFiltersWithoutRewritingSharedPlace() {
        let store = makeStore()
        let original = PlaceCandidate(
            id: "place_bodega",
            name: "Corner Bodega",
            category: "coffee shop",
            rawProviderType: "coffee shop",
            latitude: 34.08,
            longitude: -118.28,
            confidence: 1
        )
        _ = store.saveCandidate(original, status: .wannaGo, visibility: .followers, note: nil, sourceType: .manual)

        let edited = original.recategorized(
            as: PlaceCategoryAssignment(
                primaryCategory: WanderPlaceCategory.shopping,
                subcategory: "Corner store",
                source: PlaceCategorySource.user.rawValue,
                confidence: 1,
                rawProviderType: original.rawProviderType
            )
        )
        let result = store.saveCandidate(edited, status: .been, visibility: .followers, note: nil, sourceType: .manual)
        let saved = store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }

        XCTAssertEqual(saved?.place.category, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(saved?.place.subcategory, "Coffee shop")
        XCTAssertEqual(saved?.userPlace.categoryOverride, WanderPlaceCategory.shopping)
        XCTAssertEqual(saved?.userPlace.subcategoryOverride, "Corner store")
        XCTAssertEqual(saved?.effectiveCategory, WanderPlaceCategory.shopping)
        XCTAssertTrue(store.visiblePlaces(filters: PlaceFilters(categories: [WanderPlaceCategory.shopping])).contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertTrue(store.visiblePlaces(filters: PlaceFilters(categories: ["shop"])).contains { $0.userPlace.id == result.userPlaceID })
        XCTAssertFalse(store.visiblePlaces(filters: PlaceFilters(categories: ["coffee"])).contains { $0.userPlace.id == result.userPlaceID })
    }

    func testPlaceRatingsNormalizeForBeenSavesOnly() {
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: nil), PlaceRating.defaultScore)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 0), 1)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 4.25), 4.5)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 4.74), 4.5)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 4.75), 5)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 6), 5)
        XCTAssertNil(PlaceRating.scoreForSave(status: .wannaGo, score: 5))
        XCTAssertEqual(PlaceRating.averageDisplay(4.5), "4.5")
        XCTAssertEqual(PlaceRating.averageDisplay(5), "5")
    }

    func testSaveQuestionTemplatesUseSliderRatingAndMultiBestFor() {
        let restaurantBlocks = AddQuestionTemplates.blocks(category: "restaurant", status: .been)
        let occasion = restaurantBlocks.first { $0.key == "occasion" }
        let tags = restaurantBlocks.first { $0.key == "restaurant_tags" }

        XCTAssertFalse(restaurantBlocks.contains { $0.key == "rating_signal" })
        XCTAssertEqual(restaurantBlocks.map(\.key), ["price", "occasion", "restaurant_tags"])
        XCTAssertEqual(restaurantBlocks.first { $0.key == "price" }?.defaultValues, [])
        XCTAssertEqual(occasion?.kind, .multiTag)
        XCTAssertEqual(occasion?.valueType, "multi_tag")
        XCTAssertTrue((occasion?.defaultValues.count ?? 0) > 1)
        XCTAssertEqual(tags?.kind, .multiTag)
    }

    func testWannaGoQuestionTemplatesAvoidVisitedOnlyPrompts() {
        let restaurantBlocks = AddQuestionTemplates.blocks(category: "restaurant", status: .wannaGo)
        let coffeeBlocks = AddQuestionTemplates.blocks(category: "coffee", status: .wannaGo)
        let hikeBlocks = AddQuestionTemplates.blocks(category: "hike", status: .wannaGo)
        let parkBlocks = AddQuestionTemplates.blocks(category: "park", status: .wannaGo)

        XCTAssertEqual(restaurantBlocks.map(\.key), ["interest_signal", "occasion", "restaurant_tags"])
        XCTAssertEqual(restaurantBlocks.first?.title, "how excited are you?")
        XCTAssertEqual(restaurantBlocks.first?.options, ["curious", "excited", "must go"])
        XCTAssertNil(restaurantBlocks.first { $0.key == "price" })
        XCTAssertEqual(restaurantBlocks.first { $0.key == "occasion" }?.title, "planning for?")
        XCTAssertEqual(restaurantBlocks.first { $0.key == "restaurant_tags" }?.title, "why save it?")
        XCTAssertTrue(restaurantBlocks.first { $0.key == "restaurant_tags" }?.defaultValues.contains("recommended") == true)
        XCTAssertTrue(restaurantBlocks.first { $0.key == "restaurant_tags" }?.options.contains("food shortlist") == true)

        XCTAssertEqual(coffeeBlocks.map(\.key), ["interest_signal", "coffee_tags"])
        XCTAssertNil(coffeeBlocks.first { $0.key == "work_setup" })
        XCTAssertEqual(coffeeBlocks.first { $0.key == "coffee_tags" }?.title, "why save it?")
        XCTAssertTrue(coffeeBlocks.first { $0.key == "coffee_tags" }?.defaultValues.contains("work maybe") == true)

        XCTAssertEqual(hikeBlocks.map(\.key), ["interest_signal", "hike_tags"])
        XCTAssertNil(hikeBlocks.first { $0.key == "strenuousness" })
        XCTAssertEqual(hikeBlocks.first { $0.key == "hike_tags" }?.options.contains("weekend maybe"), true)

        XCTAssertEqual(parkBlocks.map(\.key), ["interest_signal", "best_for", "park_tags"])
        XCTAssertEqual(parkBlocks.first { $0.key == "best_for" }?.title, "planning for?")
        XCTAssertEqual(parkBlocks.first { $0.key == "park_tags" }?.title, "why save it?")
        XCTAssertEqual(parkBlocks.first { $0.key == "park_tags" }?.options.contains("outdoor shortlist"), true)
    }

    func testNewSaveKeepsOptionalQuestionSelectionsUnselectedByDefault() throws {
        let candidate = PlaceCandidate(
            id: "mapkit_compact_want",
            name: "Compact Want Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let context = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )
        let preselectedImport = MapPlaceSaveContext.importCandidate(
            candidate,
            sourceType: .manual,
            status: .been,
            defaultVisibility: .followers
        )
        let wannaBlock = AddQuestionTemplates.blocks(category: "coffee", status: .wannaGo)[0]
        let beenBlocks = AddQuestionTemplates.blocks(category: "restaurant", status: .been)
        let price = try XCTUnwrap(beenBlocks.first { $0.key == "price" })
        let bestFor = try XCTUnwrap(beenBlocks.first { $0.key == "occasion" })
        let tags = try XCTUnwrap(beenBlocks.first { $0.key == "restaurant_tags" })

        XCTAssertTrue(
            MapPlaceSaveDetailsPolicy.usesCompactWannaGoLayout(
                context: context,
                status: .wannaGo
            )
        )
        XCTAssertFalse(
            MapPlaceSaveDetailsPolicy.usesCompactWannaGoLayout(
                context: context,
                status: .been
            )
        )
        XCTAssertTrue(context.requiresStatusConfirmation)
        XCTAssertTrue(context.startsOnDetails)
        XCTAssertEqual(context.initialStatus, .been)
        let newSaveDraft = try XCTUnwrap(PlaceSaveDraft.addFlow(
            ownerUserID: "user-1",
            context: context,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        XCTAssertEqual(newSaveDraft.form.step, .details)
        XCTAssertTrue(newSaveDraft.form.isShowingOptionalDetails)
        XCTAssertFalse(preselectedImport.requiresStatusConfirmation)
        XCTAssertTrue(preselectedImport.startsOnDetails)
        XCTAssertEqual(preselectedImport.initialStatus, .been)
        XCTAssertEqual(
            MapPlaceSaveDetailsPolicy.suggestedSelections(
                for: wannaBlock,
                context: context,
                status: .wannaGo
            ),
            []
        )
        XCTAssertEqual(
            MapPlaceSaveDetailsPolicy.suggestedSelections(
                for: bestFor,
                context: context,
                status: .been
            ),
            []
        )
        XCTAssertEqual(
            MapPlaceSaveDetailsPolicy.suggestedSelections(
                for: tags,
                context: context,
                status: .been
            ),
            []
        )
        XCTAssertEqual(
            MapPlaceSaveDetailsPolicy.suggestedSelections(
                for: price,
                context: context,
                status: .been
            ),
            []
        )

        let synchronized = MapPlaceSaveDetailsPolicy.synchronizedSelections(
            existing: [
                bestFor.key: [],
                tags.key: ["late-night"]
            ],
            blocks: beenBlocks,
            context: context,
            status: .been
        )
        XCTAssertEqual(synchronized[bestFor.key], [])
        XCTAssertEqual(synchronized[tags.key], ["late-night"])
        XCTAssertEqual(synchronized[price.key], [])
    }

    func testChangingTaxonomyDropsStaleSuggestedTagsButKeepsCustomTags() {
        let existing: Set<String> = ["Thai craving", "date night", "Joe's pick"]
        let synchronized = MapPlaceSaveDetailsPolicy.synchronizedUnifiedTagSelections(
            existing: existing,
            previousSuggestedOptions: ["Thai craving", "date night", "craving list"],
            nextSuggestedOptions: ["Mediterranean craving", "date night", "dinner rotation"]
        )

        XCTAssertEqual(synchronized, ["date night", "Joe's pick"])
    }

    func testLocalTagSuggestionsRequireMatchingSubcategoryAndRestaurantCuisine() {
        XCTAssertTrue(
            MapPlaceSaveDetailsPolicy.matchesTagSuggestionTaxonomy(
                sourcePrimaryCategory: WanderPlaceCategory.restaurantsFood,
                sourceSubcategory: "Restaurant",
                sourceCuisine: "Mediterranean",
                selectedPrimaryCategory: WanderPlaceCategory.restaurantsFood,
                selectedSubcategory: "Restaurant",
                selectedCuisine: "Mediterranean"
            )
        )
        XCTAssertFalse(
            MapPlaceSaveDetailsPolicy.matchesTagSuggestionTaxonomy(
                sourcePrimaryCategory: WanderPlaceCategory.restaurantsFood,
                sourceSubcategory: "Restaurant",
                sourceCuisine: "Thai",
                selectedPrimaryCategory: WanderPlaceCategory.restaurantsFood,
                selectedSubcategory: "Restaurant",
                selectedCuisine: "Mediterranean"
            )
        )
        XCTAssertFalse(
            MapPlaceSaveDetailsPolicy.matchesTagSuggestionTaxonomy(
                sourcePrimaryCategory: WanderPlaceCategory.outdoorsNature,
                sourceSubcategory: "National Park",
                sourceCuisine: nil,
                selectedPrimaryCategory: WanderPlaceCategory.outdoorsNature,
                selectedSubcategory: "Playground",
                selectedCuisine: nil
            )
        )
    }

    func testUnifiedTagOrderingCanonicalizesSuggestedCaseAndKeepsCustomTags() {
        XCTAssertEqual(
            MapPlaceSaveDetailsPolicy.orderedSelections(
                values: ["Date Night", "Joe's Pick"],
                options: ["date night", "group"]
            ),
            ["date night", "Joe's Pick"]
        )
    }

    func testChangingTaxonomyRefreshesEveryOptionalQuestionBlock() {
        let candidate = PlaceCandidate(
            id: "mapkit_reactive_questions",
            name: "Reactive Questions",
            category: "restaurant",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let context = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )
        let restaurantBlocks = AddQuestionTemplates.blocks(category: "restaurant", status: .been)
        let barBlocks = AddQuestionTemplates.blocks(category: "bar", status: .been)
        let previousOptions = Dictionary(
            uniqueKeysWithValues: restaurantBlocks.map { ($0.key, $0.options) }
        )
        let synchronized = MapPlaceSaveDetailsPolicy.synchronizedSelections(
            existing: [
                "price": ["$$$"],
                "occasion": ["rainy night", "custom anniversary"]
            ],
            blocks: barBlocks,
            context: context,
            status: .been,
            previousSuggestedOptions: previousOptions
        )

        XCTAssertNil(synchronized["price"])
        XCTAssertEqual(synchronized["occasion"], ["custom anniversary"])
        XCTAssertEqual(barBlocks.map(\.key), ["occasion", "bar_tags"])
    }

    func testNewSaveContextsClearInheritedPriceFeelWhileEditPreservesIt() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")
            )
        )
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_price_feel_defaults",
                name: "Price Feel Cafe",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.98
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: [
                PlaceAttributeDraft(
                    questionKey: "price",
                    valueType: "price_scale",
                    stringValue: "$$$"
                )
            ]
        )
        let visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )
        let attributes = store.attributes(for: result.userPlaceID)
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)

        let socialSaveContext = MapPlaceSaveContext.addVisiblePlace(
            visiblePlace,
            defaultVisibility: .followers,
            attributes: attributes
        )
        let addVisitContext = MapPlaceSaveContext.addVisitVisiblePlace(
            visiblePlace,
            attributes: attributes,
            latestVisit: visit
        )
        let editContext = MapPlaceSaveContext.editVisit(
            visit,
            visiblePlace: visiblePlace
        )

        XCTAssertNil(socialSaveContext.initialAnswers["price"])
        XCTAssertNil(addVisitContext.initialAnswers["price"])
        XCTAssertEqual(editContext.initialAnswers["price"], Set(["$$$"]))
    }

    func testSaveContextFactoriesOnlyRequireStatusForNewChoiceFlows() throws {
        let store = makeStore()
        let candidate = PlaceCandidate(
            id: "mapkit_context_matrix",
            name: "Context Matrix Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let socialPlace = try XCTUnwrap(
            store.visiblePlaces().first { $0.owner.id != store.currentUser.id }
        )
        let ownBeenPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.status == .been }
        )
        let ownVisit = try XCTUnwrap(store.visits(for: ownBeenPlace.userPlace.id).first)
        let ownWantPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.status == .wannaGo }
        )

        let sharedVisitContext = MapPlaceSaveContext.sharedVisit(
            makeSharedVisitInvitation(
                attributeAnswers: [
                    VisitAttributeAnswer(
                        questionKey: "strenuousness",
                        valueType: "single_choice",
                        value: .string("easy")
                    ),
                    VisitAttributeAnswer(
                        questionKey: "hike_tags",
                        valueType: "multi_tag",
                        value: .array([.string("views")])
                    ),
                    VisitAttributeAnswer(
                        questionKey: PlaceMemoryAttributeKeys.personalLabels,
                        valueType: "personal_label",
                        value: .array([.string("sunset list")])
                    )
                ]
            ),
            defaultVisibility: .followers
        )
        let contexts: [(
            name: String,
            context: MapPlaceSaveContext,
            requiresConfirmation: Bool,
            startsOnDetails: Bool
        )] = [
            (
                "new candidate",
                .addCandidate(candidate, sourceType: .manual, defaultVisibility: .followers),
                true,
                true
            ),
            (
                "preselected import",
                .importCandidate(
                    candidate,
                    sourceType: .manual,
                    status: .been,
                    defaultVisibility: .followers
                ),
                false,
                true
            ),
            (
                "social save",
                .addVisiblePlace(
                    socialPlace,
                    defaultVisibility: .followers,
                    attributes: store.attributes(for: socialPlace.userPlace.id)
                ),
                true,
                true
            ),
            (
                "add visit",
                .addVisitVisiblePlace(
                    ownBeenPlace,
                    attributes: store.attributes(for: ownBeenPlace.userPlace.id),
                    latestVisit: ownVisit
                ),
                false,
                true
            ),
            (
                "shared visit",
                sharedVisitContext,
                false,
                true
            ),
            (
                "edit visit",
                .editVisit(ownVisit, visiblePlace: ownBeenPlace),
                false,
                true
            ),
            (
                "edit want",
                .editWant(
                    ownWantPlace,
                    attributes: store.attributes(for: ownWantPlace.userPlace.id)
                ),
                false,
                true
            )
        ]

        for entry in contexts {
            XCTAssertEqual(
                entry.context.requiresStatusConfirmation,
                entry.requiresConfirmation,
                entry.name
            )
            XCTAssertEqual(
                entry.context.startsOnDetails,
                entry.startsOnDetails,
                entry.name
            )
        }

        XCTAssertTrue(sharedVisitContext.initialAnswers.isEmpty)
        XCTAssertTrue(sharedVisitContext.initialPersonalLabels.isEmpty)
    }

    func testSharedVisitContextStartsInviteeMetadataBlankAndPreservesPlaceClassification() {
        let invitation = makeSharedVisitInvitation(
            attributeAnswers: [
                VisitAttributeAnswer(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "single_choice",
                    value: .string("Italian")
                ),
                VisitAttributeAnswer(
                    questionKey: "noise_level",
                    valueType: "single_choice",
                    value: .string("lively")
                ),
                VisitAttributeAnswer(
                    questionKey: "restaurant_tags",
                    valueType: "multi_tag",
                    value: .array([.string("date night")])
                ),
                VisitAttributeAnswer(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    value: .array([.string("birthday shortlist")])
                )
            ],
            note: "Order the pasta",
            ratingScore: 4.5,
            tags: ["date night"],
            photos: [
                SharedVisitPhotoSnapshot(
                    photoID: "photo-1",
                    storageBucket: "visit-photos",
                    storagePath: "shared/photo-1.jpg",
                    contentType: "image/jpeg",
                    byteSize: 123,
                    width: 1200,
                    height: 900,
                    capturedAt: nil,
                    sortOrder: 0
                )
            ]
        )

        let context = MapPlaceSaveContext.sharedVisit(
            invitation,
            defaultVisibility: .mutuals
        )

        XCTAssertEqual(context.candidate.primaryCategory, invitation.candidate.primaryCategory)
        XCTAssertEqual(context.candidate.subcategory, invitation.candidate.subcategory)
        XCTAssertEqual(context.initialCuisine, "Italian")
        XCTAssertEqual(context.initialVisibility, .mutuals)
        XCTAssertNil(context.initialRatingScore)
        XCTAssertEqual(context.initialNote, "")
        XCTAssertTrue(context.initialAnswers.isEmpty)
        XCTAssertTrue(context.initialPersonalLabels.isEmpty)
        XCTAssertTrue(context.initialPhotoAttachments.isEmpty)
    }

    func testQuickAddCoordinateParserAcceptsDecimalAndCardinalCoordinates() throws {
        let decimal = try XCTUnwrap(AddScreen.coordinate(from: "34.0522, -118.2437"))
        XCTAssertEqual(decimal.latitude, 34.0522, accuracy: 0.000_001)
        XCTAssertEqual(decimal.longitude, -118.2437, accuracy: 0.000_001)

        let cardinal = try XCTUnwrap(AddScreen.coordinate(from: "34.0522 N, 118.2437 W"))
        XCTAssertEqual(cardinal.latitude, 34.0522, accuracy: 0.000_001)
        XCTAssertEqual(cardinal.longitude, -118.2437, accuracy: 0.000_001)

        XCTAssertNil(AddScreen.coordinate(from: "Los Angeles"))
        XCTAssertNil(AddScreen.coordinate(from: "123.0, -118.2"))
    }

    @MainActor
    func testCanonicalNewPlaceSubmissionPersistsTheAddTabSave() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let candidate = PlaceCandidate(
            id: "mapkit_add_tab_shared_flow",
            name: "Shared Flow Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let context = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers
        )
        let submission = MapPlaceSaveSubmission(
            context: context,
            candidate: candidate,
            status: .wannaGo,
            visibility: .followers,
            ratingScore: nil,
            note: "Ryan said the patio is great",
            attributes: [],
            photoAttachments: [],
            inviteeUserIDs: [],
            reconcilesSharedVisitInvitees: false
        )

        let persistedResult = await persistNewPlaceSaveSubmission(
            submission,
            store: store,
            backend: nil
        )
        let result = try XCTUnwrap(persistedResult)
        let visiblePlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(visiblePlace.userPlace.status, .wannaGo)
        XCTAssertEqual(visiblePlace.userPlace.note, "Ryan said the patio is great")
        XCTAssertEqual(visiblePlace.userPlace.sourceType, AddSourceType.manual.rawValue)
    }

    @MainActor
    func testCanonicalAddPlaceSubmissionDeliversSelectedSharedVisitInvitees() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_ryan", displayName: "Ryan", handle: "ryan")
            )
        )
        let candidate = PlaceCandidate(
            id: "mapkit_add_tab_shared_visit",
            name: "Shared Visit Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let submission = MapPlaceSaveSubmission(
            context: MapPlaceSaveContext.addCandidate(
                candidate,
                sourceType: .manual,
                defaultVisibility: .followers
            ),
            candidate: candidate,
            status: .been,
            visibility: .followers,
            ratingScore: 4.5,
            note: "shared from the Add tab",
            attributes: [],
            photoAttachments: [],
            inviteeUserIDs: ["user_joe"],
            reconcilesSharedVisitInvitees: false,
            visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let checkInRepository = FakeUserPlaceRepository(
            result: SaveResult(
                userPlaceID: "82000000-0000-0000-0000-000000000385",
                syncState: .synced,
                placeID: "81000000-0000-0000-0000-000000000385"
            )
        )
        let sharedVisitRepository = FakeSharedVisitRepository()

        let result = await persistAddPlaceSaveSubmission(
            submission,
            store: store,
            backend: WanderBackend(
                userPlaceRepository: checkInRepository,
                sharedVisitRepository: sharedVisitRepository
            )
        )

        let savedResult = try XCTUnwrap(result)
        let visit = try XCTUnwrap(store.visits(for: savedResult.userPlaceID).first)
        XCTAssertEqual(checkInRepository.savedCheckInDrafts.count, 1)
        XCTAssertEqual(
            sharedVisitRepository.setRequests,
            [
                FakeSharedVisitRepository.InviteRequest(
                    sourceVisitID: try XCTUnwrap(visit.serverID),
                    inviteeUserIDs: ["user_joe"]
                )
            ]
        )
        XCTAssertTrue(store.pendingSharedVisitInvites.isEmpty)
    }

    @MainActor
    func testCanonicalAddPlaceSubmissionCreatesAnotherVisitForExistingCheckIn() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let candidate = PlaceCandidate(
            id: "mapkit_add_tab_repeat_visit",
            name: "Repeat Visit Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let firstSave = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4,
            visitedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let existingPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == firstSave.userPlaceID }
        )
        let existingVisit = try XCTUnwrap(store.visits(for: firstSave.userPlaceID).first)
        let context = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers,
            currentUserSave: existingPlace,
            latestVisit: existingVisit
        ).resolvingInitialEditorContext(startsOnDetails: true, selection: .been)
        guard case .addVisit = context.mode else {
            return XCTFail("The defaulted Plus editor must normalize an existing save to add-visit")
        }
        let submission = MapPlaceSaveSubmission(
            context: context,
            candidate: candidate,
            status: .been,
            visibility: .followers,
            ratingScore: 5,
            note: "tutorial revisit",
            attributes: [],
            photoAttachments: [],
            inviteeUserIDs: [],
            reconcilesSharedVisitInvitees: false,
            visitedAt: Date(timeIntervalSince1970: 1_700_086_400)
        )
        let visitCountBeforeSave = store.visits(for: firstSave.userPlaceID).count

        let result = await persistAddPlaceSaveSubmission(
            submission,
            store: store,
            backend: nil
        )

        XCTAssertEqual(result?.userPlaceID, firstSave.userPlaceID)
        XCTAssertEqual(store.currentUserVisiblePlaces.count, 1)
        XCTAssertEqual(store.visits(for: firstSave.userPlaceID).count, visitCountBeforeSave + 1)
        XCTAssertEqual(store.visits(for: firstSave.userPlaceID).first?.note, "tutorial revisit")
        let preservedParent = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == firstSave.userPlaceID }
        )
        XCTAssertEqual(preservedParent.userPlace.note, "first visit")
    }

    @MainActor
    func testPlusRepeatCheckInDraftKeepsLatestVisitDefaults() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let candidate = PlaceCandidate(
            id: "mapkit_add_tab_repeat_visit_draft",
            name: "Repeat Visit Draft Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let firstSave = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "work_setup", valueType: "single_choice", stringValue: "yes"),
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["quiet"])
            ]
        )
        let existingPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == firstSave.userPlaceID }
        )
        let latestVisit = try XCTUnwrap(store.visits(for: firstSave.userPlaceID).first)
        let sourceContext = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers,
            currentUserSave: existingPlace,
            latestVisit: latestVisit
        )

        let draft = try XCTUnwrap(
            PlaceSaveDraft.addFlow(ownerUserID: store.currentUser.id, context: sourceContext)
        )

        XCTAssertEqual(draft.form.selectedRatingScore, 4)
        XCTAssertEqual(draft.form.selectedAnswers["work_setup"], ["yes"])
        XCTAssertTrue(draft.form.unifiedTags.isEmpty)
        XCTAssertEqual(draft.baselineUserPlaceLocalID, existingPlace.userPlace.localID)
        XCTAssertEqual(draft.baselineVisitLocalID, latestVisit.localID)
    }

    @MainActor
    func testPlusExistingWannaDraftKeepsSavedDetails() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let plannedDate = WannaGoDate.normalized(Date().addingTimeInterval(14 * 24 * 60 * 60))
        let candidate = PlaceCandidate(
            id: "mapkit_add_tab_existing_wanna_draft",
            name: "Existing Wanna Draft Cafe",
            category: "coffee",
            latitude: 34.04,
            longitude: -118.24,
            confidence: 0.95
        )
        let firstSave = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "Try the patio",
            sourceType: .manual,
            plannedDate: plannedDate,
            attributes: [
                PlaceAttributeDraft(questionKey: "work_setup", valueType: "single_choice", stringValue: "yes")
            ]
        )
        let existingPlace = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == firstSave.userPlaceID }
        )
        let sourceContext = MapPlaceSaveContext.addCandidate(
            candidate,
            sourceType: .manual,
            defaultVisibility: .followers,
            currentUserSave: existingPlace,
            latestVisit: nil
        )

        let draft = try XCTUnwrap(
            PlaceSaveDraft.addFlow(ownerUserID: store.currentUser.id, context: sourceContext)
        )

        XCTAssertEqual(draft.form.selectedStatus, .wannaGo)
        XCTAssertEqual(draft.form.note, "Try the patio")
        XCTAssertEqual(draft.form.plannedDate, plannedDate)
        XCTAssertEqual(draft.form.selectedAnswers["work_setup"], ["yes"])
        XCTAssertEqual(draft.baselineUserPlaceLocalID, existingPlace.userPlace.localID)

        guard case .add = sourceContext.mode else {
            return XCTFail("A restored Plus draft must retain its unresolved source context")
        }
        let checkInContext = sourceContext.preselectingStatus(.been)
        guard case .addVisit = checkInContext.mode else {
            return XCTFail("A restored Wanna draft must be able to switch to Check in")
        }
        let wannaContext = sourceContext.preselectingStatus(.wannaGo)
        guard case .editWant = wannaContext.mode else {
            return XCTFail("A restored Wanna draft must be able to switch back to Wanna")
        }
    }

    func testFollowersAndFollowingUseGraphEdges() {
        let store = makeStore()

        XCTAssertEqual(store.followers(of: store.currentUser.id).map(\.id), ["user_ryan"])
        XCTAssertEqual(store.following(of: store.currentUser.id).map(\.id), ["user_demo", "user_maya", "user_ryan"])

        store.block(userID: "user_ryan")

        XCTAssertTrue(store.followers(of: store.currentUser.id).isEmpty)
        XCTAssertEqual(store.following(of: store.currentUser.id).map(\.id), ["user_demo", "user_maya"])
    }

    func testLinkAndPhotoCreateUnresolvedDrafts() {
        let store = makeStore()

        let linkDraft = store.createUnresolvedDraft(sourceType: .link, originalInput: "https://example.com/place")
        let photoDraft = store.createUnresolvedDraft(
            sourceType: .photo,
            originalInput: "photo import · 42 bytes",
            localAssetRef: "photos_picker:test_asset"
        )

        XCTAssertEqual(store.unresolvedDrafts, [linkDraft, photoDraft])
        XCTAssertEqual(linkDraft.sourceType, .link)
        XCTAssertEqual(photoDraft.sourceType, .photo)
        XCTAssertEqual(store.sourceArtifacts.map(\.type), ["url", "image"])
        XCTAssertEqual(store.extractionJobs.map(\.sourceType), ["link", "photo"])
        XCTAssertEqual(photoDraft.sourceArtifactID, store.sourceArtifacts.last?.localID)
        XCTAssertEqual(photoDraft.extractionJobID, store.extractionJobs.last?.localID)
    }

    func testDraftsAreIdempotentBySourceHash() {
        let store = makeStore()

        let firstDraft = store.createUnresolvedDraft(sourceType: .link, originalInput: "https://example.com/place")
        let secondDraft = store.createUnresolvedDraft(sourceType: .link, originalInput: "https://example.com/place")

        XCTAssertEqual(firstDraft, secondDraft)
        XCTAssertEqual(store.unresolvedDrafts.count, 1)
        XCTAssertEqual(store.sourceArtifacts.count, 1)
        XCTAssertEqual(store.extractionJobs.count, 1)
    }

    func testSignedInUnresolvedDraftEnqueuesRemoteExtractionJob() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let extractionRepository = FakeExtractionRepository(
            result: ExtractionJobEnqueueResult(
                sourceArtifactID: "source_remote",
                extractionJobID: "job_remote",
                status: .pending,
                attemptCount: 0
            )
        )
        let backend = WanderBackend(extractionRepository: extractionRepository)

        let draft = await store.createUnresolvedDraft(
            sourceType: .link,
            originalInput: "https://maps.app.goo.gl/example",
            backend: backend
        )

        XCTAssertEqual(draft.sourceArtifactID, "source_remote")
        XCTAssertEqual(draft.extractionJobID, "job_remote")
        XCTAssertEqual(extractionRepository.drafts.count, 1)
        XCTAssertEqual(extractionRepository.drafts[0].sourceArtifact.type, "url")
        XCTAssertEqual(extractionRepository.drafts[0].sourceType, "link")
        XCTAssertEqual(store.sourceArtifacts.first?.serverID, "source_remote")
        XCTAssertEqual(store.sourceArtifacts.first?.syncStateRaw, SyncState.synced.rawValue)
        XCTAssertEqual(store.extractionJobs.first?.serverID, "job_remote")
        XCTAssertEqual(store.extractionJobs.first?.sourceArtifactID, "source_remote")
        XCTAssertEqual(store.extractionJobs.first?.syncStateRaw, SyncState.synced.rawValue)
        XCTAssertNil(store.lastRemoteError)
    }

    func testExtractionEnqueueFailureLeavesDraftRetryable() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let extractionRepository = FakeExtractionRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(extractionRepository: extractionRepository)

        let draft = await store.createUnresolvedDraft(
            sourceType: .photo,
            originalInput: "photo import · 42 bytes",
            localAssetRef: "photos_picker:test",
            backend: backend
        )

        XCTAssertEqual(draft.sourceArtifactID, store.sourceArtifacts.first?.localID)
        XCTAssertEqual(draft.extractionJobID, store.extractionJobs.first?.localID)
        XCTAssertEqual(extractionRepository.drafts.count, 1)
        XCTAssertEqual(store.sourceArtifacts.first?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertEqual(store.extractionJobs.first?.status, .failed)
        XCTAssertEqual(store.extractionJobs.first?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertNotNil(store.extractionJobs.first?.lastSyncError)
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testFollowedFeedRetriesOneTransientAuthReadinessFailure() async {
        let store = makeStore()
        let expectedPage = FollowedFeedPage(
            activity: [],
            featuredPlaces: [],
            nextCursor: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let repository = FakeFeedRepository(responses: [
            .failure(AuthSessionError.tokenUnavailable),
            .success(expectedPage)
        ])

        let didRefresh = await store.refreshFollowedFeed(
            backend: WanderBackend(feedRepository: repository)
        )

        XCTAssertTrue(didRefresh)
        XCTAssertEqual(repository.requestCount, 2)
        XCTAssertEqual(store.feedLoadState, .loaded)
        XCTAssertEqual(store.followedFeedPage?.fetchedAt, expectedPage.fetchedAt)
        XCTAssertNil(store.lastRemoteError)
    }

    func testFollowedFeedDoesNotRetryOrdinaryRemoteFailures() async {
        let store = makeStore()
        let repository = FakeFeedRepository(responses: [
            .failure(WanderRemoteError.invalidResponse("service unavailable"))
        ])

        let didRefresh = await store.refreshFollowedFeed(
            backend: WanderBackend(feedRepository: repository)
        )

        XCTAssertFalse(didRefresh)
        XCTAssertEqual(repository.requestCount, 1)
        XCTAssertEqual(store.feedLoadState, .failed)
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testDeferredFollowedFeedRefreshCannotLeaveLoadingStateAcrossAccountSwitch() async {
        let store = WanderStore(fixtures: .empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "feed_user_a", displayName: "Feed A", handle: "feed_a")
            )
        )
        let repository = FakeFeedRepository(
            responses: [
                .success(
                    FollowedFeedPage(
                        activity: [],
                        featuredPlaces: [],
                        nextCursor: nil,
                        fetchedAt: Date(timeIntervalSince1970: 1_753_000_000)
                    )
                )
            ],
            isSuspended: true
        )
        let refresh = Task { @MainActor in
            await store.refreshFollowedFeed(
                backend: WanderBackend(feedRepository: repository)
            )
        }
        for _ in 0..<20 where repository.requestCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(repository.requestCount, 1)
        XCTAssertEqual(store.feedLoadState, .loading)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "feed_user_b", displayName: "Feed B", handle: "feed_b")
            )
        )
        XCTAssertEqual(store.feedLoadState, .idle)
        XCTAssertNil(store.followedFeedPage)

        repository.finish()
        let refreshResult = await refresh.value
        XCTAssertFalse(refreshResult)
        XCTAssertEqual(store.feedLoadState, .idle)
        XCTAssertNil(store.followedFeedPage)
    }

    func testProcessExtractionResultUpdatesJobAndReturnsCandidates() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let extractionRepository = FakeExtractionRepository(
            result: ExtractionJobEnqueueResult(
                sourceArtifactID: "source_remote",
                extractionJobID: "job_remote",
                status: .pending,
                attemptCount: 0
            ),
            processResult: ExtractionJobResult(
                extractionJobID: "job_remote",
                status: .needsConfirmation,
                attemptCount: 1,
                providerSteps: ["worker_started", "google_maps_coordinate_candidate"],
                candidates: [
                    PlaceCandidate(
                        id: "extracted_hash",
                        name: "Maru Coffee",
                        category: "coffee",
                        latitude: 34.0836,
                        longitude: -118.3614,
                        sourceProvider: "google_maps_link",
                        sourceProviderPlaceID: "https://google.com/maps/place/Maru+Coffee",
                        confidence: 0.86
                    )
                ],
                confidence: 0.86,
                errorCode: nil,
                errorMessage: nil
            )
        )
        let backend = WanderBackend(extractionRepository: extractionRepository)

        let draft = await store.createUnresolvedDraft(
            sourceType: .link,
            originalInput: "https://maps.app.goo.gl/example",
            backend: backend
        )
        let result = await store.processExtractionJob(for: draft, backend: backend)

        XCTAssertEqual(result?.status, .needsConfirmation)
        XCTAssertEqual(result?.candidates.map(\.name), ["Maru Coffee"])
        XCTAssertEqual(extractionRepository.processedJobIDs, ["job_remote"])
        XCTAssertEqual(store.extractionJobs.first?.status, .needsConfirmation)
        XCTAssertEqual(store.extractionJobs.first?.attemptCount, 1)
        XCTAssertEqual(store.extractionJobs.first?.confidence, 0.86)
        XCTAssertEqual(store.extractionJobs.first?.syncStateRaw, SyncState.synced.rawValue)
        XCTAssertTrue(store.extractionJobs.first?.extractedCandidatesJSON.contains("Maru Coffee") == true)
    }

    func testProcessExtractionNoPlaceDoesNotCreateSavedPlace() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let extractionRepository = FakeExtractionRepository(
            result: ExtractionJobEnqueueResult(
                sourceArtifactID: "source_remote",
                extractionJobID: "job_remote",
                status: .pending,
                attemptCount: 0
            ),
            processResult: ExtractionJobResult(
                extractionJobID: "job_remote",
                status: .noPlaceFound,
                attemptCount: 1,
                providerSteps: ["worker_started", "photo_ocr_not_configured"],
                candidates: [],
                confidence: 0,
                errorCode: "photo_ocr_not_configured",
                errorMessage: "Photo OCR is not wired yet."
            )
        )
        let backend = WanderBackend(extractionRepository: extractionRepository)

        let draft = await store.createUnresolvedDraft(
            sourceType: .photo,
            originalInput: "photo import · 42 bytes",
            localAssetRef: "photos_picker:test",
            backend: backend
        )
        let result = await store.processExtractionJob(for: draft, backend: backend)

        XCTAssertEqual(result?.status, .noPlaceFound)
        XCTAssertTrue(store.userPlaces.isEmpty)
        XCTAssertTrue(store.places.isEmpty)
        XCTAssertEqual(store.extractionJobs.first?.status, .noPlaceFound)
        XCTAssertEqual(store.extractionJobs.first?.errorCode, "photo_ocr_not_configured")
    }

    func testUsernameSearchIsNearExactAndHidesBlockedUsers() {
        let store = makeStore()

        XCTAssertEqual(store.searchProfiles(handleQuery: "ry").map(\.handle), ["ryan"])

        store.block(userID: "user_ryan")

        XCTAssertTrue(store.searchProfiles(handleQuery: "ry").isEmpty)
        XCTAssertTrue(store.searchProfiles(handleQuery: "r").isEmpty)
    }

    func testUsernameSearchHidesPrivateProfiles() {
        let store = makeStore()
        let maya = store.profiles.first { $0.id == "user_maya" }!

        XCTAssertEqual(store.searchProfiles(handleQuery: "ma").map(\.handle), ["maya"])

        maya.isPrivateProfile = true

        XCTAssertTrue(store.searchProfiles(handleQuery: "ma").isEmpty)
    }

    func testPrivateProfileForcesCurrentAndFutureSavesStealthWithoutRestoringOnDisable() {
        let store = makeStore()
        store.defaultVisibility = .followers
        let originalUserPlaceIDs = store.currentUserVisiblePlaces.map(\.userPlace.id)
        let otherUserPlace = store.userPlaces.first {
            $0.userID != store.currentUser.id && $0.visibility == .followers
        }!

        store.setPrivateProfile(true)

        XCTAssertTrue(store.isPrivateProfile)
        XCTAssertTrue(store.currentUser.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .followers)
        XCTAssertEqual(store.effectiveDefaultVisibility, .selfOnly)
        XCTAssertTrue(
            store.currentUserVisiblePlaces
                .filter { originalUserPlaceIDs.contains($0.userPlace.id) }
                .allSatisfy { $0.userPlace.visibility == .selfOnly }
        )
        XCTAssertEqual(
            store.userPlaces.first { $0.id == otherUserPlace.id }?.visibility,
            .followers
        )

        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mapkit_private_profile_maru",
                name: "Private Profile Maru",
                category: "coffee",
                latitude: 34.0407,
                longitude: -118.2354,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }?.userPlace.visibility, .selfOnly)

        store.setPrivateProfile(false)

        XCTAssertFalse(store.isPrivateProfile)
        XCTAssertEqual(store.defaultVisibility, .followers)
        XCTAssertEqual(store.effectiveDefaultVisibility, .followers)
        XCTAssertTrue(
            store.currentUserVisiblePlaces
                .filter { originalUserPlaceIDs.contains($0.userPlace.id) || $0.userPlace.id == result.userPlaceID }
                .allSatisfy { $0.userPlace.visibility == .selfOnly }
        )
    }

    func testContactMatchesOnlyIncludePeopleOnWander() async {
        let store = makeStore()

        let matches = await store.contactMatches()

        XCTAssertEqual(matches.map(\.id), ["contact_maya"])
        XCTAssertTrue(matches.allSatisfy { $0.isMatchedUser })
    }

    func testDiscoverSmartQueryUsesDeterministicParser() async {
        let store = makeStore()

        let results = await store.discover(query: "hikes in LA from people")

        XCTAssertFalse(results.places.isEmpty)
        XCTAssertTrue(results.places.allSatisfy { $0.place.category == WanderPlaceCategory.outdoorsNature })
        XCTAssertEqual(store.lastDiscoverFilters.chips.map(\.title), ["Outdoors & Nature", "following", "LA"])
        XCTAssertTrue(results.profiles.isEmpty)
    }

    func testDiscoverNaturalLanguageCanFilterByOwnerQuery() async {
        let store = makeStore()

        let results = await store.discover(query: "Joe's favorite coffee spots in LA")

        XCTAssertFalse(results.places.isEmpty)
        XCTAssertTrue(results.places.allSatisfy { $0.owner.handle == "joe" })
        XCTAssertTrue(results.places.allSatisfy { $0.place.category == WanderPlaceCategory.coffeeTeaSweets })
        XCTAssertEqual(store.lastDiscoverFilters.ownerQuery, "joe")
        XCTAssertEqual(store.lastDiscoverFilters.statuses, [.been])
    }

    func testDiscoverFavoriteUsesExactOwnersAndOwnerRowEvidence() async throws {
        let store = makeStore()

        let results = await store.discover(query: "Ryan's favorite coffee spots")

        XCTAssertEqual(Set(results.places.map(\.owner.handle)), ["ryan"])
        XCTAssertFalse(results.places.isEmpty)
        XCTAssertTrue(results.places.allSatisfy { $0.userPlace.status == .been })
        XCTAssertTrue(results.places.allSatisfy { ($0.userPlace.ratingScore ?? 0) >= 4 })

        let circuit = try XCTUnwrap(results.places.first { $0.place.canonicalName == "Circuit Coffee" })
        let evidence = try XCTUnwrap(results.evidenceByUserPlaceID[circuit.userPlace.id])
        XCTAssertEqual(evidence.ownerID, "user_ryan")
        XCTAssertEqual(evidence.ownerName, "Ryan")
        XCTAssertEqual(evidence.ratingScore, 4)
        XCTAssertEqual(evidence.items.map(\.kind), [.owner, .opinion, .rating, .category])
        XCTAssertTrue(evidence.items.allSatisfy { $0.sourceOwnerID == "user_ryan" })
        XCTAssertTrue(evidence.summary.contains("Ryan's save"))
        XCTAssertTrue(evidence.summary.contains("favorite"))
        XCTAssertTrue(evidence.summary.contains("4/5"))
    }

    func testDiscoverFavoriteNeverQualifiesWannaGoSaves() async {
        let store = makeStore()

        let results = await store.discover(query: "Ryan's favorite restaurants")

        XCTAssertFalse(results.places.isEmpty)
        XCTAssertTrue(results.places.allSatisfy { $0.owner.handle == "ryan" })
        XCTAssertTrue(results.places.allSatisfy { $0.userPlace.status == .been })
        XCTAssertFalse(results.places.contains { $0.place.canonicalName == "Larchmont Noodles" })
    }

    func testDiscoverOwnerResolutionDoesNotUseSubstrings() async {
        let parser = FakeFilterParser(
            result: DiscoverFilters(
                query: "Ry coffee",
                categories: [WanderPlaceCategory.coffeeTeaSweets],
                ownerQuery: "ry"
            )
        )
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser)

        let results = await store.discover(query: "Ry coffee")

        XCTAssertTrue(results.places.isEmpty)
    }

    func testDiscoverParserCachesAndTracksAnalytics() async {
        let analytics = RecordingAnalyticsClient()
        let parser = FakeFilterParser(
            result: DiscoverFilters(
                query: "coffee work",
                categories: ["coffee"],
                tags: ["work"]
            )
        )
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser, analytics: analytics)

        _ = await store.discover(query: "coffee work")
        _ = await store.discover(query: "coffee work")

        XCTAssertEqual(parser.queries, ["coffee work"])
        XCTAssertEqual(
            analytics.events.map(\.name),
            [WanderAnalyticsEvents.discoverQueryParsed, WanderAnalyticsEvents.discoverQueryParsed]
        )
        XCTAssertEqual(analytics.events.map { $0.properties["source"] }, ["remote", "cache"])
        XCTAssertEqual(store.lastDiscoverParseSource, .cache)
    }

    func testDiscoverParserCacheEvictsLeastRecentlyUsedEntryAtFiftyQueries() async {
        let parser = FakeFilterParser()
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser)

        for index in 0..<51 {
            _ = await store.parseDiscover(query: "coffee query \(index)")
        }
        _ = await store.parseDiscover(query: "coffee query 0")

        XCTAssertEqual(parser.queries.count, 52)
        XCTAssertEqual(parser.queries.last, "coffee query 0")
    }

    func testDiscoverParserFailureFallsBackAndTracksFailure() async {
        let analytics = RecordingAnalyticsClient()
        let parser = FakeFilterParser(error: TestError.expected)
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser, analytics: analytics)

        let filters = await store.parseDiscover(query: "anything")

        XCTAssertEqual(filters, DiscoverFilters(query: "anything"))
        XCTAssertEqual(analytics.events.map(\.name), [WanderAnalyticsEvents.discoverParseFailed])
    }

    func testProductActionsEmitCanonicalHumanNeedAnalyticsWithoutContent() async throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.seed(), analytics: analytics)

        store.follow(userID: "user_analytics_probe", source: .profile)
        _ = store.createPlaceList(
            name: "Private list name",
            description: "Private list description",
            visibility: .stealth
        )
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "analytics_probe_place",
                name: "Private place name",
                category: "coffee",
                latitude: 34.05,
                longitude: -118.24,
                confidence: 0.9
            ),
            status: .wannaGo,
            visibility: .selfOnly,
            note: "Private note",
            sourceType: .manual
        )
        _ = await store.toggleActivityLike(activityID: "local-analytics-activity", backend: nil)

        let engagement = analytics.events.filter {
            $0.name == WanderAnalyticsEvents.engagementActionPerformed
        }
        let needAndAction = Set(engagement.compactMap { event -> String? in
            guard let need = event.properties["need"], let action = event.properties["action"] else {
                return nil
            }
            return "\(need):\(action)"
        })
        XCTAssertTrue(needAndAction.contains("connect:follow_created"))
        XCTAssertTrue(needAndAction.contains("connect:activity_liked"))
        XCTAssertTrue(needAndAction.contains("expression:list_created"))
        XCTAssertTrue(needAndAction.contains("expression:place_saved"))

        let serializedProperties = analytics.events.flatMap(\.properties.values).joined(separator: " ")
        XCTAssertFalse(serializedProperties.contains("Private list name"))
        XCTAssertFalse(serializedProperties.contains("Private list description"))
        XCTAssertFalse(serializedProperties.contains("Private place name"))
        XCTAssertFalse(serializedProperties.contains("Private note"))
        XCTAssertFalse(serializedProperties.contains("34.05"))
        XCTAssertFalse(serializedProperties.contains("-118.24"))
    }

    func testPlaceShareTracksCompletionAndOnlyCountsSuccessfulRecommendations() {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.seed(), analytics: analytics)

        store.trackPlaceShareCompletion(completed: false)
        store.trackPlaceShareCompletion(completed: true)

        let rawEvents = analytics.events.filter {
            $0.name == WanderAnalyticsEvents.placeShareCompleted
        }
        XCTAssertEqual(rawEvents.map { $0.properties["outcome"] }, ["cancelled", "shared"])
        XCTAssertTrue(rawEvents.allSatisfy { $0.properties["surface"] == "map_place_card" })

        let engagementEvents = analytics.events.filter {
            $0.name == WanderAnalyticsEvents.engagementActionPerformed
        }
        XCTAssertEqual(engagementEvents.count, 1)
        XCTAssertEqual(engagementEvents.first?.properties["need"], "expression")
        XCTAssertEqual(engagementEvents.first?.properties["action"], "recommendation_shared")
        XCTAssertEqual(engagementEvents.first?.properties["surface"], "map_place_card")
        XCTAssertEqual(engagementEvents.first?.properties["outcome"], "shared")
    }

    func testDiscoverFreeTextSearchMatchesTrustedPlaceMemory() async {
        let store = makeStore()

        let results = await store.discover(query: "Circuit Coffee")

        XCTAssertFalse(results.places.isEmpty)
        XCTAssertTrue(results.places.allSatisfy { $0.place.canonicalName == "Circuit Coffee" })
    }

    func testTrustedPlaceImmediateAndRefinedFreeTextUseSameOrdering() async {
        let store = makeStore()

        let immediate = store.searchTrustedPlaces(query: "Circuit Coffee")
        let refined = await store.discover(query: "Circuit Coffee")

        XCTAssertEqual(immediate.places.map(\.userPlace.id), refined.places.map(\.userPlace.id))
    }

    func testTrustedPlaceImmediateSearchAppliesOpinionPhraseBeforeRemoteRefinement() {
        let store = makeStore()

        let immediate = store.searchTrustedPlaces(query: "coffee worth crossing town for")

        XCTAssertFalse(immediate.places.isEmpty)
        XCTAssertEqual(immediate.filters.opinion, .favorite)
        XCTAssertTrue(immediate.places.allSatisfy { $0.userPlace.status == .been })
    }

    func testTrustedPlaceDefaultRankingUsesBoundedSocialAffinity() {
        let store = makeStore()

        let results = store.searchTrustedPlaces(query: "Circuit Coffee")

        XCTAssertEqual(results.places.map(\.owner.id), ["user_joe", "user_ryan", "user_maya"])
    }

    func testDiscoverGenuineFreeTextMissDoesNotSilentlyReturnEveryPlace() async {
        let store = makeStore()

        let results = await store.discover(query: "teleport me somewhere surprising")

        XCTAssertTrue(results.places.isEmpty)
        XCTAssertFalse(results.filters.hasRecognizedFacet)
    }

    func testDiscoverCanScopeBetweenMyPlacesFriendsAndEveryone() async {
        let store = makeStore()

        let mine = await store.discover(query: "", scope: .myPlaces)
        let friends = await store.discover(query: "", scope: .friendsPlaces)
        let everyone = await store.discover(query: "", scope: .everyone)

        XCTAssertFalse(mine.places.isEmpty)
        XCTAssertTrue(mine.places.allSatisfy { $0.owner.id == "user_joe" })
        XCTAssertFalse(friends.places.isEmpty)
        XCTAssertTrue(friends.places.allSatisfy { $0.owner.id == "user_ryan" })
        XCTAssertEqual(Set(everyone.places.map(\.owner.id)), ["user_demo", "user_joe", "user_maya", "user_ryan"])
    }

    func testDiscoverMergesRemoteProfileSearch() async {
        let store = makeStore()
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_sofia",
                    handle: "sofia",
                    displayName: "Sofia Rivera",
                    avatarURL: nil,
                    bio: nil,
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        let results = await store.discover(query: "@so", backend: backend)

        XCTAssertEqual(results.profiles.map(\.handle), ["sofia"])
        XCTAssertEqual(profileRepository.queries, ["so"])
        XCTAssertNotNil(store.profileState(for: "user_sofia"))
    }

    func testDiscoverPlaceModeSkipsUnusedRemoteProfileSearch() async {
        let store = makeStore()
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_sofia",
                    handle: "sofia",
                    displayName: "Sofia Rivera",
                    avatarURL: nil,
                    bio: nil,
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        let results = await store.discover(
            query: "@so",
            backend: backend,
            includeProfiles: false
        )

        XCTAssertTrue(results.profiles.isEmpty)
        XCTAssertTrue(profileRepository.queries.isEmpty)
        XCTAssertNil(store.profileState(for: "user_sofia"))
    }

    func testDiscoverMembersSearchDoesNotInvokePlaceParser() async {
        let parser = FakeFilterParser()
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser)

        let profiles = await store.discoverMembers(query: "Maya")

        XCTAssertEqual(profiles.map(\.handle), ["maya"])
        XCTAssertTrue(parser.queries.isEmpty)
    }

    func testDiscoverMembersMergesRemoteProfileSearch() async {
        let store = makeStore()
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_sofia",
                    handle: "sofia",
                    displayName: "Sofia Rivera",
                    avatarURL: nil,
                    bio: nil,
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        let profiles = await store.discoverMembers(query: "@so", backend: backend)

        XCTAssertEqual(profiles.map(\.handle), ["sofia"])
        XCTAssertEqual(profileRepository.queries, ["so"])
        XCTAssertNotNil(store.profileState(for: "user_sofia"))
    }

    func testIdenticalRemoteMemberResultsDoNotInvalidatePresentationCachesAgain() async {
        let store = makeStore()
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_sofia",
                    handle: "sofia",
                    displayName: "Sofia Rivera",
                    avatarURL: nil,
                    bio: nil,
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        _ = await store.discoverMembers(query: "@so", backend: backend)
        let revisionAfterFirstSearch = store.presentationRevision
        _ = await store.discoverMembers(query: "@so", backend: backend)

        XCTAssertEqual(store.presentationRevision, revisionAfterFirstSearch)
        XCTAssertEqual(profileRepository.queries, ["so", "so"])
    }

    func testDiscoverPeopleRecommendationsLoadsCachesAndHydratesProfiles() async {
        let store = makeStore()
        let recommendation = DiscoverPeopleRecommendation(
            profile: ProfileShell(
                id: "user_sofia",
                handle: "sofia",
                displayName: "Sofia Rivera",
                avatarURL: nil,
                bio: "Neighborhood restaurants and long walks.",
                homeArea: "Los Angeles",
                isPrivateProfile: false,
                relationship: .nonFollower
            ),
            reason: .sharedFollows(2),
            rank: 1
        )
        let profileRepository = FakeProfileRepository(recommendations: [recommendation])
        let backend = WanderBackend(profileRepository: profileRepository)

        await store.refreshDiscoverPeopleRecommendations(backend: backend, limit: 12)
        await store.refreshDiscoverPeopleRecommendations(backend: backend, limit: 8)

        XCTAssertEqual(store.discoverPeopleRecommendationsState, .loaded([recommendation]))
        XCTAssertEqual(profileRepository.recommendationLimits, [12])
        XCTAssertEqual(store.profileState(for: "user_sofia")?.shell.bio, recommendation.profile.bio)
    }

    func testDiscoverPeopleRecommendationsCanForceRefreshAfterAnEmptyResponse() async {
        let store = makeStore()
        let recommendation = DiscoverPeopleRecommendation(
            profile: ProfileShell(
                id: "user_sofia",
                handle: "sofia",
                displayName: "Sofia Rivera",
                avatarURL: nil,
                bio: nil,
                isPrivateProfile: false,
                relationship: .nonFollower
            ),
            reason: .suggested,
            rank: 1
        )
        let profileRepository = FakeProfileRepository(
            recommendationResponses: [[], [recommendation]]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        await store.refreshDiscoverPeopleRecommendations(backend: backend)
        XCTAssertEqual(store.discoverPeopleRecommendationsState, .loaded([]))

        await store.refreshDiscoverPeopleRecommendations(backend: backend, force: true)

        XCTAssertEqual(store.discoverPeopleRecommendationsState, .loaded([recommendation]))
        XCTAssertEqual(profileRepository.recommendationLimits, [20, 20])
    }

    func testDiscoverPeopleRecommendationsRejectPrivateBlockedSelfAndAcknowledgedFollows() async {
        let store = makeStore()
        store.block(userID: "user_blocked")
        let shells = [
            ProfileShell(
                id: store.currentUser.id,
                handle: store.currentUser.handle,
                displayName: store.currentUser.displayName,
                avatarURL: nil,
                bio: nil,
                isPrivateProfile: false,
                relationship: .owner
            ),
            ProfileShell(
                id: "user_private",
                handle: "private",
                displayName: "Private Person",
                avatarURL: nil,
                bio: nil,
                isPrivateProfile: true,
                relationship: .nonFollower
            ),
            ProfileShell(
                id: "user_blocked",
                handle: "blocked",
                displayName: "Blocked Person",
                avatarURL: nil,
                bio: nil,
                isPrivateProfile: false,
                relationship: .nonFollower
            ),
            ProfileShell(
                id: "user_maya",
                handle: "maya",
                displayName: "Maya",
                avatarURL: nil,
                bio: nil,
                isPrivateProfile: false,
                relationship: .follower
            )
        ]
        let recommendations = shells.enumerated().map { index, shell in
            DiscoverPeopleRecommendation(profile: shell, reason: .suggested, rank: index + 1)
        }
        let backend = WanderBackend(
            profileRepository: FakeProfileRepository(recommendations: recommendations)
        )

        await store.refreshDiscoverPeopleRecommendations(backend: backend)

        XCTAssertEqual(store.discoverPeopleRecommendationsState, .loaded([]))
    }

    func testDiscoverPeopleRecommendationsFailureAndIdentityChangeResetState() async {
        let store = makeStore()
        let backend = WanderBackend(
            profileRepository: FakeProfileRepository(recommendationError: TestError.expected)
        )

        await store.refreshDiscoverPeopleRecommendations(backend: backend)
        XCTAssertEqual(store.discoverPeopleRecommendationsState, .failed)

        store.apply(authState: .signedOut)
        XCTAssertEqual(store.discoverPeopleRecommendationsState, .idle)
    }

    func testDiscoverMembersKeepsLocalAvatarWhenRemoteSearchOmitsAvatar() async {
        let store = makeStore()
        let avatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=local"
        store.profiles.first { $0.id == "user_ryan" }?.avatarURL = avatarURL
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_ryan",
                    handle: "ryan",
                    displayName: "Ryan Updated",
                    avatarURL: nil,
                    bio: "remote profile",
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        let profiles = await store.discoverMembers(query: "ry", backend: backend)

        XCTAssertEqual(profiles.map(\.handle), ["ryan"])
        XCTAssertEqual(profiles.first?.displayName, "Ryan Updated")
        XCTAssertEqual(profiles.first?.avatarURL, avatarURL)
        XCTAssertEqual(profiles.first?.relationship, .mutual)
        XCTAssertEqual(store.profileState(for: "user_ryan")?.shell.avatarURL, avatarURL)
        XCTAssertEqual(profileRepository.queries, ["ry"])
    }

    func testDiscoverMembersKeepsRemoteAvatarWhenLocalShellIsStale() async {
        let store = makeStore()
        let avatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=remote"
        let profileRepository = FakeProfileRepository(
            shells: [
                ProfileShell(
                    id: "user_ryan",
                    handle: "ryan",
                    displayName: "Ryan Updated",
                    avatarURL: avatarURL,
                    bio: "remote profile",
                    relationship: .nonFollower
                )
            ]
        )
        let backend = WanderBackend(profileRepository: profileRepository)

        let profiles = await store.discoverMembers(query: "ry", backend: backend)

        XCTAssertEqual(profiles.map(\.handle), ["ryan"])
        XCTAssertEqual(profiles.first?.displayName, "Ryan Updated")
        XCTAssertEqual(profiles.first?.avatarURL, avatarURL)
        XCTAssertEqual(profiles.first?.relationship, .mutual)
        XCTAssertEqual(store.profileState(for: "user_ryan")?.shell.avatarURL, avatarURL)
        XCTAssertEqual(profileRepository.queries, ["ry"])
    }

    func testRemoteVisiblePlacesHydrateProfilesAndAttributesWithoutLocalFollow() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let remotePlace = VisiblePlace(
            id: "up_remote_maya_maru",
            place: LocalPlace(
                localID: "remote_place_maru",
                serverID: "place_remote_maru",
                canonicalName: "Remote Maru",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_maya_maru",
                serverID: "up_remote_maya_maru",
                userID: "user_maya",
                placeID: "place_remote_maru",
                status: .been,
                visibility: .followers,
                note: "server row",
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_maya",
                serverID: "user_maya",
                handle: "maya",
                displayName: "Maya",
                syncState: .synced
            ),
            attributes: [
                LocalPlaceAttribute(
                    localID: "remote_attr_up_remote_maya_maru_work_setup",
                    userPlaceID: "up_remote_maya_maru",
                    questionKey: "work_setup",
                    valueType: "single_choice",
                    valueJSON: "\"yes\"",
                    syncState: .synced
                )
            ]
        )
        let placeRepository = FakePlaceRepository(places: [remotePlace])
        let backend = WanderBackend(placeRepository: placeRepository)

        await store.refreshRemoteVisiblePlaces(
            in: MapViewport(minLatitude: 34, minLongitude: -119, maxLatitude: 35, maxLongitude: -118),
            backend: backend
        )

        let followingPlaces = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
        XCTAssertEqual(followingPlaces.map { $0.place.canonicalName }, ["Remote Maru"])
        XCTAssertEqual(followingPlaces.first?.userPlace.note, "server row")
        let socialPlaces = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"]))
        XCTAssertEqual(socialPlaces.map { $0.place.canonicalName }, ["Remote Maru"])
        XCTAssertEqual(socialPlaces.first?.userPlace.note, "server row")
        let mayaOnlyPlaces = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_maya"]))
        XCTAssertEqual(mayaOnlyPlaces.map { $0.place.canonicalName }, ["Remote Maru"])
        let ryanOnlyPlaces = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_ryan"]))
        XCTAssertTrue(ryanOnlyPlaces.isEmpty)
        XCTAssertEqual(placeRepository.viewports.count, 1)
        XCTAssertNotNil(store.profileState(for: "user_maya"))
        XCTAssertEqual(store.attributes(for: "up_remote_maya_maru").map(\.questionKey), ["work_setup"])
        XCTAssertEqual(store.attributes(for: "up_remote_maya_maru")[0].valueJSON, "\"yes\"")
    }

    func testRemoteViewportFetchReturnsPlacesWithoutReplacingProfileWideCache() async throws {
        let store = WanderStore(fixtures: .seed())
        let remotePlace = try XCTUnwrap(store.visiblePlaces().first)
        let placeRepository = FakePlaceRepository(places: [remotePlace])
        let backend = WanderBackend(placeRepository: placeRepository)
        let viewport = MapViewport(
            minLatitude: 33.9,
            minLongitude: -118.4,
            maxLatitude: 34.2,
            maxLongitude: -118.1
        )
        let originalCacheIDs = store.remoteVisiblePlaceCache.map(\.id)

        let places = await store.fetchRemoteViewportPlaces(in: viewport, backend: backend)

        XCTAssertEqual(places?.map(\.id), [remotePlace.id])
        XCTAssertEqual(placeRepository.viewports, [viewport])
        XCTAssertEqual(store.remoteVisiblePlaceCache.map(\.id), originalCacheIDs)
    }

    func testRemoteViewportRefreshRemovesStaleSocialPlacesInsideRefreshedBounds() async {
        let store = WanderStore(fixtures: .empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_current", displayName: "Ryan", handle: "ryan")
            )
        )
        let owner = LocalProfile(
            localID: "remote_profile_joe",
            serverID: "user_joe",
            handle: "joe",
            displayName: "Joe",
            syncState: .synced
        )
        let remotePlace = makeRemoteCalendarVisiblePlace(
            owner: owner,
            userPlaceID: "up_remote_joe_woodcat",
            placeID: "place_woodcat",
            name: "Woodcat Coffee",
            status: .been,
            visibility: .followers,
            savedAt: Date(timeIntervalSince1970: 1_753_000_000)
        )
        let placeRepository = FakePlaceRepository(places: [remotePlace])
        let backend = WanderBackend(placeRepository: placeRepository)
        let viewport = MapViewport(
            minLatitude: 33.9,
            minLongitude: -118.6,
            maxLatitude: 34.2,
            maxLongitude: -118.3
        )

        await store.refreshRemoteVisiblePlaces(in: viewport, backend: backend)
        XCTAssertTrue(store.remoteVisiblePlaceCache.contains { $0.id == remotePlace.id })

        placeRepository.setPlaces([])
        await store.refreshRemoteVisiblePlaces(in: viewport, backend: backend)

        XCTAssertFalse(store.remoteVisiblePlaceCache.contains { $0.id == remotePlace.id })
    }

    func testRemoteFeaturedViewportFetchUsesCommunityPathWithoutReplacingProfileWideCache() async throws {
        let store = WanderStore(fixtures: .seed())
        let remotePlace = try XCTUnwrap(store.visiblePlaces().first)
        let placeRepository = FakePlaceRepository(
            places: [],
            featuredPlaces: [remotePlace]
        )
        let backend = WanderBackend(placeRepository: placeRepository)
        let viewport = MapViewport(
            minLatitude: 33.9,
            minLongitude: -118.4,
            maxLatitude: 34.2,
            maxLongitude: -118.1
        )
        let originalCacheIDs = store.remoteVisiblePlaceCache.map(\.id)

        let places = await store.fetchRemoteFeaturedViewportPlaces(in: viewport, backend: backend)

        XCTAssertEqual(places?.map(\.id), [remotePlace.id])
        XCTAssertEqual(placeRepository.featuredViewports, [viewport])
        XCTAssertTrue(placeRepository.viewports.isEmpty)
        XCTAssertEqual(store.remoteVisiblePlaceCache.map(\.id), originalCacheIDs)
    }

    func testRemoteSocialGraphHydratesFollowEdgesAndRelationships() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let maya = ProfileShell(id: "user_maya", handle: "maya", displayName: "Maya", avatarURL: nil, bio: nil, relationship: .mutual)
        let ryan = ProfileShell(id: "user_ryan", handle: "ryan", displayName: "Ryan", avatarURL: nil, bio: nil, relationship: .nonFollower)
        let followRepository = FakeFollowRepository(followers: [maya], following: [maya, ryan], relationships: ["user_maya": .mutual])
        let backend = WanderBackend(followRepository: followRepository)

        await store.refreshRemoteSocialGraph(backend: backend)

        XCTAssertEqual(store.following(of: store.currentUser.id).map(\.id), ["user_maya", "user_ryan"])
        XCTAssertEqual(store.followers(of: store.currentUser.id).map(\.id), ["user_maya"])
        XCTAssertEqual(store.relationship(to: "user_maya"), .mutual)
        XCTAssertEqual(store.relationship(to: "user_ryan"), .follower)
        XCTAssertNotNil(store.profileState(for: "user_maya"))
        XCTAssertEqual(followRepository.followingUserIDs, ["user_live"])
        XCTAssertEqual(followRepository.followersUserIDs, ["user_live"])
    }

    func testRemoteSocialGraphPreservesAvatarWhenGraphOmitsAvatar() async {
        let store = makeStore()
        let avatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=known"
        store.profiles.first { $0.id == "user_ryan" }?.avatarURL = avatarURL
        let ryan = ProfileShell(
            id: "user_ryan",
            handle: "ryan",
            displayName: "Ryan Updated",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let followRepository = FakeFollowRepository(following: [ryan])
        let backend = WanderBackend(followRepository: followRepository)

        await store.refreshRemoteSocialGraph(backend: backend)

        XCTAssertEqual(store.following(of: store.currentUser.id).first { $0.id == "user_ryan" }?.displayName, "Ryan Updated")
        XCTAssertEqual(store.following(of: store.currentUser.id).first { $0.id == "user_ryan" }?.avatarURL, avatarURL)
        XCTAssertEqual(store.profileState(for: "user_ryan")?.shell.avatarURL, avatarURL)
    }

    func testRemoteSocialSurfacesHydrateFollowedUsersAndTheirPlaces() async {
        var snapshots: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { snapshots.append($0) }
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        snapshots.removeAll()
        let mayaAvatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_maya/avatar.jpg?v=2"
        let ryanAvatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=2"
        let maya = ProfileShell(id: "user_maya", handle: "maya", displayName: "Maya", avatarURL: mayaAvatarURL, bio: nil, relationship: .follower)
        let ryan = ProfileShell(id: "user_ryan", handle: "ryan", displayName: "Ryan", avatarURL: ryanAvatarURL, bio: nil, relationship: .follower)
        let mayaPlace = VisiblePlace(
            id: "up_remote_maya_speranza",
            place: LocalPlace(
                localID: "remote_place_speranza",
                serverID: "place_remote_speranza",
                canonicalName: "Speranza",
                category: "restaurant",
                latitude: 34.101,
                longitude: -118.292,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_maya_speranza",
                serverID: "up_remote_maya_speranza",
                userID: "user_maya",
                placeID: "place_remote_speranza",
                status: .been,
                visibility: .followers,
                note: "great patio",
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_maya",
                serverID: "user_maya",
                handle: "maya",
                displayName: "Maya",
                syncState: .synced
            )
        )
        let ryanPlace = VisiblePlace(
            id: "up_remote_ryan_dama",
            place: LocalPlace(
                localID: "remote_place_dama",
                serverID: "place_remote_dama",
                canonicalName: "Dama",
                category: "restaurant",
                latitude: 34.033,
                longitude: -118.229,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_ryan_dama",
                serverID: "up_remote_ryan_dama",
                userID: "user_ryan",
                placeID: "place_remote_dama",
                status: .been,
                visibility: .followers,
                note: "order the prawns",
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_ryan",
                serverID: "user_ryan",
                handle: "ryan",
                displayName: "Ryan",
                syncState: .synced
            )
        )
        let followRepository = FakeFollowRepository(
            following: [maya, ryan],
            relationships: ["user_maya": .follower, "user_ryan": .follower]
        )
        let placeRepository = FakePlaceRepository(places: [])
        let userPlaceRepository = FakeUserPlaceRepository(
            userPlacesByUserID: [
                "user_maya": [mayaPlace],
                "user_ryan": [ryanPlace]
            ]
        )
        let backend = WanderBackend(
            followRepository: followRepository,
            placeRepository: placeRepository,
            userPlaceRepository: userPlaceRepository
        )

        await store.refreshRemoteSocialSurfaces(backend: backend)

        XCTAssertEqual(store.following(of: store.currentUser.id).map(\.id), ["user_maya", "user_ryan"])
        XCTAssertEqual(store.following(of: store.currentUser.id).map(\.avatarURL), [mayaAvatarURL, ryanAvatarURL])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"])).map(\.place.canonicalName), ["Speranza", "Dama"])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"])).map(\.owner.avatarURL), [mayaAvatarURL, ryanAvatarURL])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_maya"])).map(\.place.canonicalName), ["Speranza"])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_maya"])).first?.owner.avatarURL, mayaAvatarURL)
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_ryan"])).map(\.place.canonicalName), ["Dama"])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_ryan"])).first?.owner.avatarURL, ryanAvatarURL)
        let discoverPlaces = await store.discover(query: "", scope: .everyone, backend: backend).places
        XCTAssertEqual(Set(discoverPlaces.map(\.owner.id)), Set(["user_maya", "user_ryan"]))
        XCTAssertEqual(discoverPlaces.first { $0.owner.id == "user_maya" }?.owner.avatarURL, mayaAvatarURL)
        XCTAssertEqual(discoverPlaces.first { $0.owner.id == "user_maya" }?.place.canonicalName, "Speranza")
        XCTAssertEqual(discoverPlaces.first { $0.owner.id == "user_ryan" }?.owner.avatarURL, ryanAvatarURL)
        XCTAssertEqual(discoverPlaces.first { $0.owner.id == "user_ryan" }?.place.canonicalName, "Dama")
        XCTAssertEqual(followRepository.followingUserIDs, ["user_live"])
        XCTAssertEqual(placeRepository.viewports.count, 1)
        XCTAssertEqual(userPlaceRepository.userPlaceRequests.map(\.userID), ["user_maya", "user_ryan"])
        XCTAssertEqual(snapshots.count, 1, "A logical social refresh should materialize one store snapshot")
    }

    func testRemoteSocialSurfacesDiscardCompletionFromPreviousAccount() async {
        var snapshots: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { snapshots.append($0) }
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        snapshots.removeAll()
        let maya = ProfileShell(
            id: "user_maya",
            handle: "maya",
            displayName: "Maya",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let followRepository = FakeFollowRepository(following: [maya])
        followRepository.shouldSuspendFollowing = true
        let backend = WanderBackend(followRepository: followRepository)

        let refreshTask = Task { @MainActor in
            await store.refreshRemoteSocialSurfaces(backend: backend)
        }
        while !followRepository.hasSuspendedFollowingRequest {
            await Task.yield()
        }

        store.apply(authState: .signedIn(AuthSession(userID: "user_sarah", displayName: "Sarah", handle: "sarah")))
        snapshots.removeAll()
        followRepository.resumeFollowing()
        _ = await refreshTask.value

        XCTAssertEqual(store.currentUser.id, "user_sarah")
        XCTAssertFalse(store.profiles.contains { $0.id == "user_maya" })
        XCTAssertFalse(store.follows.contains {
            $0.followerUserID == "user_sarah" && $0.followedUserID == "user_maya"
        })
        XCTAssertEqual(followRepository.followingUserIDs, ["user_joe"])
        XCTAssertTrue(followRepository.followersUserIDs.isEmpty)
        XCTAssertTrue(snapshots.isEmpty, "The stale refresh must not persist into the new account")
    }

    func testCancelledRemoteSocialSurfacesRefreshDoesNotMutateStore() async {
        var snapshots: [WanderStoreSnapshot] = []
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { snapshots.append($0) }
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")))
        snapshots.removeAll()
        let maya = ProfileShell(
            id: "user_maya",
            handle: "maya",
            displayName: "Maya",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let followRepository = FakeFollowRepository(following: [maya])
        followRepository.shouldSuspendFollowing = true
        let backend = WanderBackend(followRepository: followRepository)

        let refreshTask = Task { @MainActor in
            await store.refreshRemoteSocialSurfaces(backend: backend)
        }
        while !followRepository.hasSuspendedFollowingRequest {
            await Task.yield()
        }

        refreshTask.cancel()
        followRepository.resumeFollowing()
        _ = await refreshTask.value

        XCTAssertFalse(store.profiles.contains { $0.id == "user_maya" })
        XCTAssertFalse(store.follows.contains {
            $0.followerUserID == "user_joe" && $0.followedUserID == "user_maya"
        })
        XCTAssertTrue(followRepository.followersUserIDs.isEmpty)
        XCTAssertTrue(snapshots.isEmpty, "A cancelled refresh must not publish or persist staged results")
    }

    func testRemoteSocialSaveMarksLocalCopySynced() async {
        let store = makeStore()
        let socialSaveRepository = FakeSocialPlaceSaveRepository(result: SaveResult(userPlaceID: "up_remote_saved", syncState: .synced))
        let backend = WanderBackend(socialPlaceSaveRepository: socialSaveRepository)
        let placeID = "11111111-1111-4111-8111-111111111111"
        let sourceUserPlaceID = "22222222-2222-4222-8222-222222222222"
        let socialPlace = VisiblePlace(
            id: sourceUserPlaceID,
            place: LocalPlace(
                localID: "remote_place_griffith",
                serverID: placeID,
                canonicalName: "Remote Griffith",
                category: "hike",
                latitude: 34.119,
                longitude: -118.300,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_maya_griffith",
                serverID: sourceUserPlaceID,
                userID: "user_maya",
                placeID: placeID,
                status: .been,
                visibility: .followers,
                note: "server row",
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_maya",
                serverID: "user_maya",
                handle: "maya",
                displayName: "Maya",
                syncState: .synced
            )
        )

        let result = await store.saveVisiblePlace(socialPlace, backend: backend)

        XCTAssertEqual(result, SaveResult(userPlaceID: "up_remote_saved", syncState: .synced))
        XCTAssertEqual(socialSaveRepository.requests, [FakeSocialPlaceSaveRepository.Request(placeID: placeID, sourceUserPlaceID: sourceUserPlaceID)])
        XCTAssertTrue(store.currentUserVisiblePlaces.contains { $0.userPlace.serverID == "up_remote_saved" && $0.userPlace.syncState == .synced })
        XCTAssertNil(
            store.currentUserVisiblePlaces.first {
                $0.userPlace.serverID == "up_remote_saved"
            }?.userPlace.note,
            "A social save must not copy the source account's note"
        )
    }

    func testRepeatedSocialWannaSavePreservesTheCurrentUsersOwnNote() throws {
        let store = makeStore()
        let socialPlace = try XCTUnwrap(store.visiblePlaces().first { $0.owner.id == "user_maya" })

        let firstSave = store.saveVisiblePlace(socialPlace)
        let candidate = PlaceCandidate(
            id: socialPlace.place.id,
            name: socialPlace.place.canonicalName,
            category: socialPlace.effectiveCategory,
            latitude: socialPlace.place.latitude,
            longitude: socialPlace.place.longitude,
            sourceProvider: socialPlace.place.sourceProvider,
            sourceProviderPlaceID: socialPlace.place.sourceProviderPlaceID,
            confidence: socialPlace.place.confidence ?? 1
        )
        _ = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "My own reason for going",
            sourceType: .manual
        )

        let repeatedSave = store.saveVisiblePlace(socialPlace)

        XCTAssertEqual(repeatedSave.userPlaceID, firstSave.userPlaceID)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first {
                $0.userPlace.id == firstSave.userPlaceID
            }?.userPlace.note,
            "My own reason for going"
        )
    }

    func testSocialSaveDoesNotCopyAnotherUsersPrivateTaxonomy() throws {
        let store = makeStore()
        let place = LocalPlace(
            localID: "remote_place_private_taxonomy",
            canonicalName: "Private Taxonomy",
            category: WanderPlaceCategory.restaurantsFood,
            primaryCategory: WanderPlaceCategory.restaurantsFood,
            subcategory: "Restaurant",
            categorySource: PlaceCategorySource.provider.rawValue,
            rawProviderType: "restaurant",
            latitude: 34.1,
            longitude: -118.2,
            syncState: .synced
        )
        let sourceSave = LocalUserPlace(
            localID: "remote_up_private_taxonomy",
            userID: "user_maya",
            placeID: place.id,
            status: .been,
            visibility: .followers,
            categoryOverride: WanderPlaceCategory.barsNightlife,
            subcategoryOverride: "Wine Bar",
            categoryOverrideSource: PlaceCategorySource.user.rawValue,
            viewerPrimaryCategory: WanderPlaceCategory.restaurantsFood,
            viewerSubcategory: "Restaurant",
            viewerFoodType: "Seafood",
            sourceType: "manual",
            syncState: .synced
        )
        let socialPlace = VisiblePlace(
            id: sourceSave.id,
            place: place,
            userPlace: sourceSave,
            owner: LocalProfile(localID: "user_maya", handle: "maya", displayName: "Maya"),
            attributes: [
                LocalPlaceAttribute(
                    localID: "source_private_food_type",
                    userPlaceID: sourceSave.id,
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    valueJSON: "\"Steakhouse\""
                ),
                LocalPlaceAttribute(
                    localID: "source_shareable_tag",
                    userPlaceID: sourceSave.id,
                    questionKey: "restaurant_tags",
                    valueType: "multi_tag",
                    valueJSON: "[\"date night\"]"
                )
            ]
        )

        let result = store.saveVisiblePlace(socialPlace)
        let saved = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertNil(saved.userPlace.categoryOverride)
        XCTAssertEqual(saved.effectiveCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(saved.restaurantCuisine, "Seafood")
        XCTAssertNil(store.attributes(for: result.userPlaceID).first {
            $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine
        })
        XCTAssertNotNil(store.attributes(for: result.userPlaceID).first {
            $0.questionKey == "restaurant_tags"
        })
    }

    func testRemoteSocialWannaSaveDoesNotReplaceAnExistingCheckIn() async {
        let store = makeStore()
        let socialSaveRepository = FakeSocialPlaceSaveRepository(result: SaveResult(userPlaceID: "up_remote_saved", syncState: .synced))
        let backend = WanderBackend(socialPlaceSaveRepository: socialSaveRepository)
        let placeID = "11111111-1111-4111-8111-111111111111"
        let sourceUserPlaceID = "22222222-2222-4222-8222-222222222222"
        let socialPlace = VisiblePlace(
            id: sourceUserPlaceID,
            place: LocalPlace(
                localID: "remote_place_checked_in",
                serverID: placeID,
                canonicalName: "Already Checked In",
                category: "coffee",
                latitude: 34.119,
                longitude: -118.300,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: "already-checked-in",
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_friend_checked_in",
                serverID: sourceUserPlaceID,
                userID: "user_maya",
                placeID: placeID,
                status: .been,
                visibility: .followers,
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_maya",
                serverID: "user_maya",
                handle: "maya",
                displayName: "Maya",
                syncState: .synced
            )
        )

        let checkedIn = store.saveVisiblePlace(socialPlace, status: .been)
        let result = await store.saveVisiblePlace(socialPlace, status: .wannaGo, backend: backend)

        XCTAssertEqual(result.userPlaceID, checkedIn.userPlaceID)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.userPlace.id == checkedIn.userPlaceID }?.userPlace.status, .been)
        XCTAssertTrue(socialSaveRepository.requests.isEmpty)
    }

    func testSocialSaveDoesNotCallRemoteForFixtureIDs() async {
        let store = makeStore()
        let socialSaveRepository = FakeSocialPlaceSaveRepository(result: SaveResult(userPlaceID: "up_remote_saved", syncState: .synced))
        let backend = WanderBackend(socialPlaceSaveRepository: socialSaveRepository)
        let socialPlace = store.visiblePlaces().first { $0.owner.id == "user_maya" }!

        let result = await store.saveVisiblePlace(socialPlace, backend: backend)

        XCTAssertEqual(result.syncState, .pendingCreate)
        XCTAssertTrue(socialSaveRepository.requests.isEmpty)
    }

    func testVisiblePlaceGroupingDeduplicatesSharedSavesAndPrefersCurrentUser() {
        let store = makeStore()
        let socialPlace = store.visiblePlaces().first { $0.owner.id == "user_maya" }!

        _ = store.saveVisiblePlace(socialPlace)

        let matchingPlaces = store.visiblePlaces().filter {
            VisiblePlaceGrouping.key(for: $0) == VisiblePlaceGrouping.key(for: socialPlace)
        }
        let groups = VisiblePlaceGrouping.groups(from: matchingPlaces, currentUserID: store.currentUser.id)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].saveCount, 2)
        XCTAssertEqual(groups[0].otherSaveCount, 1)
        XCTAssertEqual(groups[0].primary.owner.id, store.currentUser.id)

        let representatives = VisiblePlaceGrouping.representativePlaces(
            from: matchingPlaces,
            currentUserID: store.currentUser.id
        )
        let matchingGroup = VisiblePlaceGrouping.matchingGroup(
            for: socialPlace,
            in: matchingPlaces,
            currentUserID: store.currentUser.id
        )

        XCTAssertEqual(representatives.map(\.owner.id), [store.currentUser.id])
        XCTAssertEqual(matchingGroup?.primary.owner.id, store.currentUser.id)
    }

    func testSocialSaveFlowContextPrefillsStatusButLeavesTagsAndLabelsUnselected() {
        let store = makeStore()
        let socialPlace = store.visiblePlaces().first { $0.owner.id == "user_maya" }!
        let attributes = store.attributes(for: socialPlace.userPlace.id)

        let context = MapPlaceSaveContext.addVisiblePlace(
            socialPlace,
            defaultVisibility: .followers,
            attributes: attributes
        )

        XCTAssertEqual(context.initialStatus, .been)
        XCTAssertEqual(context.initialVisibility, .followers)
        XCTAssertEqual(context.initialAnswers["strenuousness"], Set(["easy"]))
        XCTAssertNil(context.initialAnswers["hike_tags"])
        XCTAssertTrue(context.initialPersonalLabels.isEmpty)
    }

    func testActivityBookmarkStartsABlankViewerOwnedWannaForm() throws {
        let store = makeStore()
        let socialPlace = try XCTUnwrap(
            store.visiblePlaces().first { $0.owner.id != store.currentUser.id }
        )

        let context = MapPlaceSaveContext.addWannaVisiblePlace(
            socialPlace,
            defaultVisibility: .followers
        )

        XCTAssertEqual(context.initialStatus, .wannaGo)
        XCTAssertFalse(context.requiresStatusConfirmation)
        XCTAssertEqual(context.initialNote, "")
        XCTAssertNil(context.initialRatingScore)
        XCTAssertNil(context.initialPlannedDate)
        XCTAssertTrue(context.initialAnswers.isEmpty)
        XCTAssertTrue(context.initialPersonalLabels.isEmpty)
        XCTAssertNil(context.initialCuisine)
    }

    func testRemovingActivityWannaOnlyDeletesTheViewerOwnedRecord() async throws {
        let store = makeStore()
        let socialPlace = try XCTUnwrap(
            store.visiblePlaces().first { $0.owner.id != store.currentUser.id }
        )
        let sourceUserPlaceID = socialPlace.userPlace.id
        let sourceOwnerID = socialPlace.owner.id
        let ownSave = store.saveVisiblePlace(socialPlace, status: .wannaGo)

        XCTAssertEqual(store.activityBookmarkState(for: socialPlace), .wanna)
        _ = await store.removeActivityWanna(for: socialPlace, backend: nil)

        XCTAssertEqual(store.activityBookmarkState(for: socialPlace), .notSaved)
        XCTAssertTrue(store.visiblePlaces().contains {
            $0.userPlace.id == sourceUserPlaceID && $0.owner.id == sourceOwnerID
        })
        XCTAssertFalse(store.currentUserVisiblePlaces.contains {
            $0.userPlace.id == ownSave.userPlaceID
        })
    }

    func testRemoteOwnPlaceSaveMarksLocalRowsSynced() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(result: SaveResult(userPlaceID: "up_remote_maru", syncState: .synced, placeID: "place_remote_maru"))
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository)
        let candidate = PlaceCandidate(
            id: "mk_maru",
            name: "Maru Coffee",
            category: "coffee",
            latitude: 34.045,
            longitude: -118.235,
            confidence: 0.92
        )

        let result = await store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "window table",
            sourceType: .currentLocation,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "coffee_tags", valueType: "multi_tag", stringValues: ["wifi solid"])
            ],
            backend: backend
        )

        XCTAssertEqual(result, SaveResult(userPlaceID: "up_remote_maru", syncState: .synced, placeID: "place_remote_maru"))
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].place.canonicalName, "Maru Coffee")
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].ratingScore, 4)
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].attributes.map(\.questionKey), ["coffee_tags"])

        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Maru Coffee" }
        XCTAssertEqual(saved?.place.serverID, "place_remote_maru")
        XCTAssertEqual(saved?.userPlace.serverID, "up_remote_maru")
        XCTAssertEqual(saved?.userPlace.placeID, "place_remote_maru")
        XCTAssertEqual(saved?.userPlace.ratingScore, 4)
        XCTAssertEqual(saved?.userPlace.syncState, .synced)
        XCTAssertEqual(store.attributes(for: "up_remote_maru").map(\.questionKey), ["coffee_tags"])
    }

    func testProviderPhotoMetadataEnrichesAndResyncsAStoredRestaurantCuisine() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(
                userPlaceID: "up_remote_ugo",
                syncState: .synced,
                placeID: "place_remote_ugo"
            )
        )
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository)
        let initialResult = await store.saveCandidate(
            PlaceCandidate(
                id: "mk_ugo",
                name: "Ugo",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.86,
                rawProviderType: "mkpoicategoryrestaurant",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.86
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .currentLocation,
            backend: backend
        )
        let saved = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == initialResult.userPlaceID }
        )

        let changed = await store.applyProviderCategoryEnrichment(
            placeID: saved.place.id,
            primaryType: "restaurant",
            types: ["food", "italian_restaurant", "point_of_interest"],
            backend: backend
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(saved.place.rawProviderType, "italian_restaurant")
        XCTAssertEqual(saved.effectiveCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(saved.effectiveSubcategory, "Restaurant")
        XCTAssertNil(saved.restaurantCuisine)
        XCTAssertEqual(saved.categoryEmoji, "🍽️")
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 2)
        XCTAssertEqual(userPlaceRepository.savedDrafts.last?.place.rawProviderType, "italian_restaurant")

        let rejected = await store.applyProviderCategoryEnrichment(
            placeID: saved.place.id,
            primaryType: "gym",
            types: ["fitness_center", "sporting_goods_store"],
            backend: backend
        )
        XCTAssertFalse(rejected)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 2)
        XCTAssertEqual(saved.place.rawProviderType, "italian_restaurant")
    }

    func testSignedInProviderRefreshEnrichesGenericPlacesWithoutOpeningTheirProfiles() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(
                userPlaceID: "up_remote_ugo",
                syncState: .synced,
                placeID: "place_remote_ugo"
            )
        )
        let photoRepository = FakePlacePhotoRepository(
            photo: PlacePhoto(
                provider: "google_places",
                providerPlaceID: "google_ugo",
                providerPrimaryType: "italian_restaurant",
                providerTypes: ["restaurant", "food", "italian_restaurant"],
                photoURLString: "https://example.com/ugo.jpg",
                width: 1200,
                height: 900,
                authorName: nil,
                authorProfileURLString: nil,
                authorAvatarURLString: nil,
                sourcePhotoURLString: "https://maps.google.com/ugo",
                flagContentURLString: nil,
                storageBucket: nil,
                storagePath: nil,
                localAssetRef: nil
            )
        )
        let backend = WanderBackend(
            userPlaceRepository: userPlaceRepository,
            placePhotoRepository: photoRepository
        )
        let result = await store.saveCandidate(
            PlaceCandidate(
                id: "mk_ugo",
                name: "Ugo",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.86,
                rawProviderType: "mkpoicategoryrestaurant",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.86
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .currentLocation,
            backend: backend
        )

        let changedCount = await store.refreshOwnPlaceProviderCategories(backend: backend)
        let enriched = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(changedCount, 1)
        XCTAssertEqual(photoRepository.requests.map(\.name), ["Ugo"])
        XCTAssertEqual(photoRepository.requests.map(\.requiresPhoto), [false])
        XCTAssertEqual(enriched.place.rawProviderType, "italian_restaurant")
        XCTAssertEqual(enriched.effectiveCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(enriched.effectiveSubcategory, "Restaurant")
        XCTAssertNil(enriched.restaurantCuisine)
        XCTAssertEqual(enriched.categoryEmoji, "🍽️")
        XCTAssertEqual(enriched.userPlace.syncState, .pendingUpdate)

        let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 2)
        XCTAssertEqual(userPlaceRepository.savedDrafts.last?.place.rawProviderType, "italian_restaurant")

        let repeatedChangeCount = await store.refreshOwnPlaceProviderCategories(backend: backend)
        XCTAssertEqual(repeatedChangeCount, 0)
        XCTAssertEqual(photoRepository.requests.count, 1)
    }

    func testProviderRefreshCooldownSurvivesRelaunchAfterUnusableResponse() async throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")
        let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        firstStore.apply(authState: .signedIn(session))
        _ = firstStore.saveCandidate(
            PlaceCandidate(
                id: "mk_provider_cooldown",
                name: "Provider Cooldown",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.86,
                rawProviderType: "restaurant",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.86
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .currentLocation
        )
        let unresolvedPhoto = PlacePhoto(
            provider: "none",
            providerPlaceID: "",
            providerPrimaryType: nil,
            providerTypes: nil,
            photoURLString: "",
            width: nil,
            height: nil,
            authorName: nil,
            authorProfileURLString: nil,
            authorAvatarURLString: nil,
            sourcePhotoURLString: nil,
            flagContentURLString: nil,
            storageBucket: nil,
            storagePath: nil,
            localAssetRef: nil
        )
        let firstPhotoRepository = FakePlacePhotoRepository(photo: unresolvedPhoto)

        let firstChangeCount = await firstStore.refreshOwnPlaceProviderCategories(
            backend: WanderBackend(placePhotoRepository: firstPhotoRepository)
        )
        XCTAssertEqual(firstChangeCount, 0)
        XCTAssertEqual(firstPhotoRepository.requests.count, 1)

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        relaunchedStore.apply(authState: .signedIn(session))
        let secondPhotoRepository = FakePlacePhotoRepository(photo: unresolvedPhoto)

        let repeatedChangeCount = await relaunchedStore.refreshOwnPlaceProviderCategories(
            backend: WanderBackend(placePhotoRepository: secondPhotoRepository)
        )

        XCTAssertEqual(repeatedChangeCount, 0)
        XCTAssertTrue(secondPhotoRepository.requests.isEmpty)
    }

    func testProviderPrimaryTypeRefreshPreservesExistingSaverTaxonomySnapshot() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_ghisallo",
                name: "Ghisallo",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Restaurant",
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: 0.86,
                rawProviderType: "mkpoicategoryrestaurant",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.86
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .currentLocation
        )
        let saved = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        let changed = await store.applyProviderCategoryEnrichment(
            placeID: saved.place.id,
            primaryType: "bakery",
            types: ["bakery", "italian_restaurant", "restaurant", "food"],
            backend: nil
        )
        XCTAssertTrue(changed)
        let enriched = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )
        XCTAssertEqual(enriched.place.primaryCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(enriched.place.subcategory, "Bakery")
        XCTAssertEqual(enriched.effectiveCategory, WanderPlaceCategory.restaurantsFood)
        XCTAssertEqual(enriched.effectiveSubcategory, "Restaurant")
        XCTAssertEqual(enriched.categoryEmoji, "🍽️")
    }

    func testProviderRefreshDoesNotRewriteAlreadySpecificLegacyMetadata() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Ryan", handle: "ryan")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_noun",
                name: "Noun",
                category: WanderPlaceCategory.restaurantsFood,
                primaryCategory: WanderPlaceCategory.restaurantsFood,
                subcategory: "Coffee shop",
                categorySource: PlaceCategorySource.legacy.rawValue,
                categoryConfidence: 0.86,
                rawProviderType: "coffee",
                latitude: 34.0,
                longitude: -118.0,
                confidence: 0.86
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .currentLocation
        )
        let photoRepository = FakePlacePhotoRepository(
            photo: PlacePhoto(
                provider: "google_places",
                providerPlaceID: "unused",
                providerPrimaryType: "restaurant",
                providerTypes: ["restaurant"],
                photoURLString: "https://example.com/unused.jpg",
                width: 1200,
                height: 900,
                authorName: nil,
                authorProfileURLString: nil,
                authorAvatarURLString: nil,
                sourcePhotoURLString: nil,
                flagContentURLString: nil,
                storageBucket: nil,
                storagePath: nil,
                localAssetRef: nil
            )
        )
        let backend = WanderBackend(placePhotoRepository: photoRepository)

        let changedCount = await store.refreshOwnPlaceProviderCategories(backend: backend)
        let saved = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == result.userPlaceID }
        )

        XCTAssertEqual(changedCount, 0)
        XCTAssertTrue(photoRepository.requests.isEmpty)
        XCTAssertEqual(saved.effectiveCategory, WanderPlaceCategory.coffeeTeaSweets)
        XCTAssertEqual(saved.effectiveSubcategory, "Coffee shop")
        XCTAssertEqual(saved.categoryEmoji, "☕️")
        XCTAssertEqual(saved.place.categorySource, PlaceCategorySource.legacy.rawValue)
        XCTAssertEqual(saved.place.categoryConfidence, 0.86)
    }

    func testSyncPendingCheckInsUsesAtomicBoundaryForEachExplicitTicket() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(result: SaveResult(userPlaceID: "up_remote_maru", syncState: .synced, placeID: "place_remote_maru"))
        let visitRepository = FakeVisitRepository(
            visitsByUserPlaceID: [
                "up_remote_maru": [
                    PlaceVisitResult(
                        visitID: "visit_backfill_remote",
                        userPlaceID: "up_remote_maru",
                        visitedAt: Date(timeIntervalSince1970: 10),
                        note: "first visit",
                        ratingScore: 4,
                        tags: [],
                        backfilledFromUserPlace: true
                    )
                ]
            ]
        )
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository, visitRepository: visitRepository)
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_visit_sync",
                name: "Visit Sync Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4
        )
        let explicitVisit = store.createVisit(userPlaceID: result.userPlaceID, note: "second visit", ratingScore: 5)

        let syncedCount = await store.syncPendingVisits(backend: backend)

        XCTAssertEqual(syncedCount, 2)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 2)
        XCTAssertEqual(userPlaceRepository.savedCheckInDrafts.count, 2)
        XCTAssertEqual(userPlaceRepository.savedCheckInDrafts.map(\.visit.note), ["first visit", "second visit"])
        XCTAssertTrue(visitRepository.visitRequests.isEmpty)
        XCTAssertTrue(visitRepository.upsertedVisitDrafts.isEmpty)
        XCTAssertEqual(store.visits(for: "up_remote_maru").first { $0.id == explicitVisit?.id || $0.localID == explicitVisit?.localID }?.syncState, .synced)
    }

    func testSyncVisitStopsWhenParentPlaceSyncFails() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(
            error: WanderRemoteError.invalidResponse("network down")
        )
        let visitRepository = FakeVisitRepository()
        let backend = WanderBackend(
            userPlaceRepository: userPlaceRepository,
            visitRepository: visitRepository
        )
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_visit_parent_failure",
                name: "Parent Failure Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4
        )
        let explicitVisit = try XCTUnwrap(
            store.createVisit(userPlaceID: result.userPlaceID, note: "second visit", ratingScore: 5)
        )

        let didSync = await store.syncVisit(visitID: explicitVisit.id, backend: backend)

        XCTAssertFalse(didSync)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 1)
        XCTAssertTrue(visitRepository.visitRequests.isEmpty)
        XCTAssertTrue(visitRepository.upsertedVisitDrafts.isEmpty)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first { $0.userPlace.localID == result.userPlaceID }?.userPlace.syncState,
            .failed
        )
        XCTAssertEqual(
            store.visits(for: result.userPlaceID).first {
                $0.id == explicitVisit.id || $0.localID == explicitVisit.localID
            }?.syncState,
            .failed
        )
    }

    func testVisitPhotoUploadCreatesMetadataBeforeUploadAndMarksUploaded() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(result: SaveResult(userPlaceID: "up_remote_maru", syncState: .synced, placeID: "place_remote_maru"))
        let visitRepository = FakeVisitRepository(
            visitsByUserPlaceID: [
                "up_remote_maru": [
                    PlaceVisitResult(
                        visitID: "visit_backfill_remote",
                        userPlaceID: "up_remote_maru",
                        visitedAt: Date(timeIntervalSince1970: 10),
                        note: "first visit",
                        ratingScore: 4,
                        tags: [],
                        backfilledFromUserPlace: true
                    )
                ]
            ]
        )
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository, visitRepository: visitRepository)
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_photo_sync",
                name: "Photo Sync Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "first visit",
            sourceType: .manual,
            ratingScore: 4
        )
        let explicitVisit = store.createVisit(userPlaceID: result.userPlaceID, note: "photo visit", ratingScore: 5)
        _ = await store.syncPendingVisits(backend: backend)
        let photo = store.createVisitPhoto(
            visitID: explicitVisit?.id ?? "",
            localAssetRef: "ph://asset-1",
            contentType: "image/jpeg",
            byteSize: 10_000,
            width: 1200,
            height: 900
        )

        let uploadedPhoto = await store.uploadVisitPhoto(photoID: photo?.id ?? "", data: Data([0xFF, 0xD8, 0xFF]), backend: backend)

        XCTAssertEqual(uploadedPhoto?.uploadState, .uploaded)
        XCTAssertEqual(uploadedPhoto?.syncState, .synced)
        XCTAssertEqual(visitRepository.photoEvents, ["metadata:pending_upload", "upload", "metadata:uploaded"])
        XCTAssertEqual(visitRepository.upsertedPhotoDrafts.map(\.uploadState), [.pendingUpload, .uploaded])
        XCTAssertEqual(visitRepository.uploads.first?.bucket, "visit-photos")
        XCTAssertTrue(visitRepository.uploads.first?.path.contains("/\(uploadedPhoto?.serverID ?? "")") == true)
        XCTAssertEqual(uploadedPhoto?.remoteURLString?.hasPrefix("https://example.supabase.co/storage/v1/object/public/visit-photos/"), true)
    }

    func testVisitPhotoBatchFlushesAllLocalReferencesBeforeReturning() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("visit-photo-batch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = WanderStorePersistence.coalescingFile(
            url: directory.appendingPathComponent("store.json")
        )
        let store = WanderStore(fixtures: WanderFixtures.empty(), persistence: persistence)
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_photo_batch",
                name: "Batch Photo Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "four photos",
            sourceType: .manual,
            ratingScore: 4
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        let inputs = (1...4).map { index in
            LocalVisitPhotoInput(
                localAssetRef: "local_file:photo-\(index).jpg",
                contentType: "image/jpeg",
                byteSize: index * 1_000,
                width: 1200,
                height: 900
            )
        }

        let photos = store.createVisitPhotos(visitID: visit.id, inputs: inputs)
        store.flushPersistence()

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: persistence)
        let relaunchedVisit = try XCTUnwrap(relaunchedStore.visits(for: result.userPlaceID).first)
        XCTAssertEqual(photos.count, 4)
        XCTAssertEqual(
            relaunchedStore.photos(for: relaunchedVisit.id).compactMap(\.localAssetRef),
            inputs.compactMap(\.localAssetRef)
        )
    }

    func testVisitPhotoRetryFinalizesUploadedBytesWithoutUploadingAgain() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(
                userPlaceID: "up_remote_photo_retry",
                syncState: .synced,
                placeID: "place_remote_photo_retry"
            )
        )
        let visitRepository = FakeVisitRepository(failingPhotoMetadataCallNumbers: [2])
        let backend = WanderBackend(
            userPlaceRepository: userPlaceRepository,
            visitRepository: visitRepository
        )
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_photo_finalize_retry",
                name: "Finalize Retry Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "retry final metadata",
            sourceType: .manual,
            ratingScore: 4
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        _ = await store.syncPendingVisits(backend: backend)
        let photo = try XCTUnwrap(
            store.createVisitPhoto(
                visitID: visit.id,
                localAssetRef: "local_file:finalize-retry.jpg",
                contentType: "image/jpeg",
                byteSize: 3,
                width: 12,
                height: 9
            )
        )

        _ = await store.uploadVisitPhoto(
            photoID: photo.id,
            data: Data([0xFF, 0xD8, 0xFF]),
            backend: backend
        )

        XCTAssertEqual(photo.uploadState, .uploaded)
        XCTAssertEqual(photo.syncState, .failed)
        XCTAssertEqual(visitRepository.uploads.count, 1)

        visitRepository.clearPhotoMetadataFailures()
        let retriedCount = await store.retryPendingVisitPhotoUploads(backend: backend)

        XCTAssertEqual(retriedCount, 1)
        XCTAssertEqual(photo.uploadState, .uploaded)
        XCTAssertEqual(photo.syncState, .synced)
        XCTAssertEqual(visitRepository.uploads.count, 1, "Finalization retry must not upload the same bytes twice")
        XCTAssertEqual(
            visitRepository.photoEvents,
            ["metadata:pending_upload", "upload", "metadata:uploaded", "metadata:uploaded"]
        )
    }

    func testConcurrentVisitPhotoRetriesShareSingleFlightAndDrainNewPhotos() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(
                userPlaceID: "up_remote_photo_single_flight",
                syncState: .synced,
                placeID: "place_remote_photo_single_flight"
            )
        )
        let visitRepository = FakeVisitRepository(isPhotoMetadataSuspended: true)
        let backend = WanderBackend(
            userPlaceRepository: userPlaceRepository,
            visitRepository: visitRepository
        )
        let result = store.saveCandidate(
            PlaceCandidate(
                id: "mk_photo_single_flight",
                name: "Single Flight Photo Cafe",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "one upload task",
            sourceType: .manual,
            ratingScore: 4
        )
        let visit = try XCTUnwrap(store.visits(for: result.userPlaceID).first)
        _ = await store.syncPendingVisits(backend: backend)
        let photo = try XCTUnwrap(
            store.createVisitPhoto(
                visitID: visit.id,
                remoteURLString: "https://example.supabase.co/visit-photos/already-uploaded.jpg",
                contentType: "image/jpeg",
                byteSize: 3,
                width: 12,
                height: 9
            )
        )

        let first = Task { @MainActor in
            await store.retryPendingVisitPhotoUploads(backend: backend)
        }
        for _ in 0..<20 where visitRepository.upsertedPhotoDrafts.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(visitRepository.upsertedPhotoDrafts.count, 1)

        let secondPhoto = try XCTUnwrap(
            store.createVisitPhoto(
                visitID: visit.id,
                remoteURLString: "https://example.supabase.co/visit-photos/queued-during-upload.jpg",
                contentType: "image/jpeg",
                byteSize: 3,
                width: 12,
                height: 9
            )
        )

        let second = Task { @MainActor in
            await store.retryPendingVisitPhotoUploads(backend: backend)
        }
        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertEqual(visitRepository.upsertedPhotoDrafts.count, 1)

        visitRepository.finishPhotoMetadata()
        let firstCount = await first.value
        let secondCount = await second.value

        XCTAssertEqual(firstCount, 2)
        XCTAssertEqual(secondCount, 2)
        XCTAssertEqual(photo.syncState, .synced)
        XCTAssertEqual(secondPhoto.syncState, .synced)
        XCTAssertEqual(visitRepository.upsertedPhotoDrafts.count, 2)
        XCTAssertTrue(visitRepository.uploads.isEmpty)
    }

    func testRemoteOwnPlaceSaveRefreshesVisiblePlaceCache() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(result: SaveResult(userPlaceID: "up_remote_maru", syncState: .synced, placeID: "place_remote_maru"))
        let remotePlace = VisiblePlace(
            id: "up_remote_maru",
            place: LocalPlace(
                localID: "place_remote_maru",
                serverID: "place_remote_maru",
                canonicalName: "Maru Coffee",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "up_remote_maru",
                serverID: "up_remote_maru",
                userID: "user_live",
                placeID: "place_remote_maru",
                status: .been,
                visibility: .followers,
                note: "window table",
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "user_live",
                serverID: "user_live",
                handle: "joe",
                displayName: "Joe",
                syncState: .synced
            )
        )
        let placeRepository = FakePlaceRepository(places: [remotePlace])
        let backend = WanderBackend(placeRepository: placeRepository, userPlaceRepository: userPlaceRepository)

        _ = await store.saveCandidate(
            PlaceCandidate(
                id: "mk_maru",
                name: "Maru Coffee",
                category: "coffee",
                latitude: 34.045,
                longitude: -118.235,
                confidence: 0.92
            ),
            status: .been,
            visibility: .followers,
            note: "window table",
            sourceType: .manual,
            backend: backend
        )

        XCTAssertEqual(placeRepository.viewports.count, 1)
        XCTAssertEqual(store.visiblePlaces().map { $0.place.canonicalName }, ["Maru Coffee"])
        XCTAssertNil(store.lastRemoteError)
    }

    func testRemoteOwnPlaceSaveFailureLeavesFailedLocalRows() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository)
        let candidate = PlaceCandidate(
            id: "manual_taco",
            name: "Taco Table",
            category: "restaurant",
            latitude: 34.0522,
            longitude: -118.2437,
            confidence: 0.7
        )

        let result = await store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .mutuals,
            note: nil,
            sourceType: .manual,
            attributes: [],
            backend: backend
        )

        XCTAssertEqual(result.syncState, .failed)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 1)

        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Taco Table" }
        XCTAssertEqual(saved?.userPlace.syncState, .failed)
        XCTAssertNotNil(saved?.userPlace.lastSyncError)
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testAuthStateIdentifiesAnalyticsWithInternalUserIDOnly() {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)

        store.apply(
            authState: .signedIn(
                AuthSession(
                    userID: "user_live",
                    displayName: "Joe",
                    handle: "joe",
                    email: "joe@example.com"
                )
            )
        )
        store.apply(authState: .signedOut)

        XCTAssertEqual(analytics.identifiedUserIDs, ["user_live"])
        XCTAssertEqual(analytics.resetCount, 2)
    }

    func testDirectAccountSwitchResetsAnalyticsBeforeIdentifyingNewUser() {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)

        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_a", displayName: "Account A", handle: "account_a")
            )
        )
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_b", displayName: "Account B", handle: "account_b")
            )
        )

        XCTAssertEqual(analytics.identifiedUserIDs, ["user_a", "user_b"])
        XCTAssertEqual(analytics.resetCount, 2)
    }

    func testRemoteOwnPlaceSaveFailureTracksNonPIISyncDiagnostics() async throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        store.setPrivateProfile(false)
        store.defaultVisibility = .mutuals
        let userPlaceRepository = FakeUserPlaceRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository)

        _ = await store.saveCandidate(
            PlaceCandidate(
                id: "manual_taco",
                name: "Taco Table",
                category: "restaurant",
                latitude: 34.0522,
                longitude: -118.2437,
                confidence: 0.7
            ),
            status: .wannaGo,
            visibility: .mutuals,
            note: "private note",
            sourceType: .manual,
            attributes: [],
            backend: backend
        )

        let syncEvents = analytics.events.filter { $0.name.hasPrefix("own_place_sync_") }
        XCTAssertEqual(syncEvents.map(\.name), [
            WanderAnalyticsEvents.ownPlaceSyncAttempted,
            WanderAnalyticsEvents.ownPlaceSyncFailed
        ])

        let failed = try XCTUnwrap(syncEvents.last)
        XCTAssertEqual(failed.properties["trigger"], "direct_save")
        XCTAssertEqual(failed.properties["status"], PlaceStatus.wannaGo.rawValue)
        XCTAssertEqual(failed.properties["visibility"], PlaceVisibility.mutuals.rawValue)
        XCTAssertEqual(failed.properties["source_type"], AddSourceType.manual.rawValue)
        XCTAssertEqual(failed.properties["sync_state_before"], SyncState.pendingCreate.rawValue)
        XCTAssertEqual(failed.properties["error_kind"], "invalid_response")
        XCTAssertNil(failed.properties["error"])

        let serializedProperties = failed.properties.values.joined(separator: " ")
        XCTAssertFalse(serializedProperties.contains("Taco Table"))
        XCTAssertFalse(serializedProperties.contains("private note"))
        XCTAssertFalse(serializedProperties.contains("joe@example.com"))
        XCTAssertFalse(serializedProperties.contains("network down"))
    }

    func testSignedInBackfillRetriesPersistedFailedSemanticSaveAfterRelaunch() async {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let session = AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")

        do {
            let firstStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
            firstStore.apply(authState: .signedIn(session))
            let failingBackend = WanderBackend(
                userPlaceRepository: FakeUserPlaceRepository(error: WanderRemoteError.invalidResponse("network down"))
            )

            let failed = await firstStore.saveCandidate(
                PlaceCandidate(
                    id: "manual_taco",
                    name: "Taco Table",
                    category: "restaurant",
                    latitude: 34.0522,
                    longitude: -118.2437,
                    confidence: 0.7
                ),
                status: .wannaGo,
                visibility: .mutuals,
                note: "retry this",
                sourceType: .manual,
                attributes: [
                    PlaceAttributeDraft(
                        questionKey: PlaceMemoryAttributeKeys.personalLabels,
                        valueType: "personal_label",
                        stringValues: ["date night"]
                    ),
                    PlaceAttributeDraft(
                        questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                        valueType: "restaurant_cuisine",
                        stringValue: "Thai"
                    )
                ],
                backend: failingBackend
            )
            XCTAssertEqual(failed.syncState, .failed)
        }

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)
        relaunchedStore.apply(authState: .signedIn(session))
        let restored = relaunchedStore.currentUserVisiblePlaces.first { $0.place.canonicalName == "Taco Table" }
        XCTAssertEqual(restored?.userPlace.syncState, .failed)

        let successRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_taco", syncState: .synced, placeID: "place_remote_taco")
        )
        let retriedCount = await relaunchedStore.syncUnsyncedOwnPlaces(
            backend: WanderBackend(userPlaceRepository: successRepository)
        )

        XCTAssertEqual(retriedCount, 1)
        XCTAssertEqual(successRepository.savedDrafts.count, 1)
        XCTAssertEqual(successRepository.savedDrafts[0].note, "retry this")
        XCTAssertEqual(
            successRepository.savedDrafts[0].attributes,
            [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    stringValues: ["date night"]
                ),
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: "Thai"
                )
            ]
        )
        let saved = relaunchedStore.currentUserVisiblePlaces.first { $0.place.canonicalName == "Taco Table" }
        XCTAssertEqual(saved?.place.serverID, "place_remote_taco")
        XCTAssertEqual(saved?.userPlace.serverID, "up_remote_taco")
        XCTAssertEqual(saved?.userPlace.syncState, .synced)
        XCTAssertNil(saved?.userPlace.lastSyncError)
    }

    func testSyncUnsyncedOwnPlacesTracksZeroCandidateBackfillBatch() async throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))

        let syncedCount = await store.syncUnsyncedOwnPlaces(
            backend: WanderBackend(userPlaceRepository: FakeUserPlaceRepository())
        )

        XCTAssertEqual(syncedCount, 0)
        let syncEvents = analytics.events.filter { $0.name.hasPrefix("own_place_sync_batch_") }
        XCTAssertEqual(syncEvents.map(\.name), [
            WanderAnalyticsEvents.ownPlaceSyncBatchStarted,
            WanderAnalyticsEvents.ownPlaceSyncBatchCompleted
        ])
        XCTAssertEqual(syncEvents.first?.properties["trigger"], "signed_in_backfill")
        XCTAssertEqual(syncEvents.first?.properties["candidate_count"], "0")

        let completed = try XCTUnwrap(syncEvents.last)
        XCTAssertEqual(completed.properties["candidate_count"], "0")
        XCTAssertEqual(completed.properties["synced_count"], "0")
        XCTAssertEqual(completed.properties["failed_count"], "0")
        XCTAssertEqual(completed.properties["skipped_count"], "0")
    }

    func testSyncUnsyncedOwnPlacesBackfillsPendingLocalRowsAfterSignIn() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "manual_pijja",
                name: "Pijja Palace",
                category: "restaurant",
                latitude: 34.091,
                longitude: -118.309,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: "saved while signed out",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "restaurant_tags", valueType: "multi_tag", stringValues: ["date night"])
            ]
        )

        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_pijja", syncState: .synced, placeID: "place_remote_pijja")
        )

        let syncedCount = await store.syncUnsyncedOwnPlaces(
            backend: WanderBackend(userPlaceRepository: userPlaceRepository)
        )

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts.count, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].place.canonicalName, "Pijja Palace")
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].ratingScore, 4)
        XCTAssertEqual(userPlaceRepository.savedDrafts[0].attributes.map(\.questionKey), ["restaurant_tags"])
        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Pijja Palace" }
        XCTAssertEqual(saved?.userPlace.userID, "user_live")
        XCTAssertEqual(saved?.place.serverID, "place_remote_pijja")
        XCTAssertEqual(saved?.userPlace.serverID, "up_remote_pijja")
        XCTAssertEqual(saved?.userPlace.ratingScore, 4)
        XCTAssertEqual(saved?.userPlace.syncState, .synced)
        XCTAssertNil(saved?.userPlace.lastSyncError)
    }

    func testSyncUnsyncedOwnPlacesTracksBackfillBatchCounts() async throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "manual_pijja",
                name: "Pijja Palace",
                category: "restaurant",
                latitude: 34.091,
                longitude: -118.309,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: "saved while signed out",
            sourceType: .manual,
            ratingScore: 4,
            attributes: [
                PlaceAttributeDraft(questionKey: "restaurant_tags", valueType: "multi_tag", stringValues: ["date night"])
            ]
        )

        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_pijja", syncState: .synced, placeID: "place_remote_pijja")
        )

        let syncedCount = await store.syncUnsyncedOwnPlaces(
            backend: WanderBackend(userPlaceRepository: userPlaceRepository)
        )

        XCTAssertEqual(syncedCount, 1)
        let syncEvents = analytics.events.filter { $0.name.hasPrefix("own_place_sync_") }
        XCTAssertEqual(syncEvents.map(\.name), [
            WanderAnalyticsEvents.ownPlaceSyncBatchStarted,
            WanderAnalyticsEvents.ownPlaceSyncAttempted,
            WanderAnalyticsEvents.ownPlaceSyncSucceeded,
            WanderAnalyticsEvents.ownPlaceSyncBatchCompleted
        ])

        let attempted = try XCTUnwrap(syncEvents.first { $0.name == WanderAnalyticsEvents.ownPlaceSyncAttempted })
        XCTAssertEqual(attempted.properties["trigger"], "signed_in_backfill")
        XCTAssertEqual(attempted.properties["status"], PlaceStatus.been.rawValue)
        XCTAssertEqual(attempted.properties["visibility"], PlaceVisibility.followers.rawValue)
        XCTAssertEqual(attempted.properties["source_type"], AddSourceType.manual.rawValue)
        XCTAssertEqual(attempted.properties["sync_state_before"], SyncState.pendingCreate.rawValue)
        XCTAssertEqual(attempted.properties["attribute_count"], "1")
        XCTAssertEqual(attempted.properties["has_note"], "true")

        let completed = try XCTUnwrap(syncEvents.last)
        XCTAssertEqual(completed.properties["candidate_count"], "1")
        XCTAssertEqual(completed.properties["synced_count"], "1")
        XCTAssertEqual(completed.properties["failed_count"], "0")
        XCTAssertEqual(completed.properties["skipped_count"], "0")

        let serializedProperties = syncEvents.flatMap { $0.properties.values }.joined(separator: " ")
        XCTAssertFalse(serializedProperties.contains("Pijja Palace"))
        XCTAssertFalse(serializedProperties.contains("saved while signed out"))
    }

    func testRetryFailedOwnPlaceSyncsLeavesPendingRowsForBackfillPath() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))

        _ = store.saveCandidate(
            PlaceCandidate(
                id: "manual_pending",
                name: "Pending Bakery",
                category: "bakery",
                latitude: 34.093,
                longitude: -118.31,
                confidence: 0.8
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: []
        )
        let failed = store.saveCandidate(
            PlaceCandidate(
                id: "manual_failed",
                name: "Failed Deli",
                category: "restaurant",
                latitude: 34.094,
                longitude: -118.311,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: "retry only this",
            sourceType: .manual,
            attributes: []
        )
        store.userPlaces.first { $0.id == failed.userPlaceID }?.syncStateRaw = SyncState.failed.rawValue

        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_failed", syncState: .synced, placeID: "place_remote_failed")
        )
        let retriedCount = await store.retryFailedOwnPlaceSyncs(
            backend: WanderBackend(userPlaceRepository: userPlaceRepository)
        )

        XCTAssertEqual(retriedCount, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts.map(\.place.canonicalName), ["Failed Deli"])
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Pending Bakery" }?.userPlace.syncState, .pendingCreate)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Failed Deli" }?.userPlace.syncState, .synced)
    }

    func testSyncUnsyncedOwnPlacesSkipsSocialSavesAndTerminalRows() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))

        _ = store.saveCandidate(
            PlaceCandidate(
                id: "manual_backfill",
                name: "Backfill Cafe",
                category: "coffee",
                latitude: 34.095,
                longitude: -118.312,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: []
        )
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "manual_social",
                name: "Social Copy",
                category: "restaurant",
                latitude: 34.096,
                longitude: -118.313,
                confidence: 0.8
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .socialSave,
            attributes: []
        )
        let pendingDelete = store.saveCandidate(
            PlaceCandidate(
                id: "manual_pending_delete",
                name: "Pending Delete",
                category: "bar",
                latitude: 34.097,
                longitude: -118.314,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: []
        )
        let serverDenied = store.saveCandidate(
            PlaceCandidate(
                id: "manual_denied",
                name: "Denied Place",
                category: "shop",
                latitude: 34.098,
                longitude: -118.315,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: []
        )
        let tombstoned = store.saveCandidate(
            PlaceCandidate(
                id: "manual_tombstoned",
                name: "Tombstoned Place",
                category: "park",
                latitude: 34.099,
                longitude: -118.316,
                confidence: 0.8
            ),
            status: .been,
            visibility: .followers,
            note: nil,
            sourceType: .manual,
            attributes: []
        )
        store.userPlaces.first { $0.id == pendingDelete.userPlaceID }?.syncStateRaw = SyncState.pendingDelete.rawValue
        store.userPlaces.first { $0.id == serverDenied.userPlaceID }?.syncStateRaw = SyncState.serverDenied.rawValue
        store.userPlaces.first { $0.id == tombstoned.userPlaceID }?.syncStateRaw = SyncState.tombstoned.rawValue

        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_backfill", syncState: .synced, placeID: "place_remote_backfill")
        )
        let syncedCount = await store.syncUnsyncedOwnPlaces(
            backend: WanderBackend(userPlaceRepository: userPlaceRepository)
        )

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(userPlaceRepository.savedDrafts.map(\.place.canonicalName), ["Backfill Cafe"])
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Backfill Cafe" }?.userPlace.syncState, .synced)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Social Copy" }?.userPlace.syncState, .pendingCreate)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Pending Delete" }?.userPlace.syncState, .pendingDelete)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Denied Place" }?.userPlace.syncState, .serverDenied)
        XCTAssertEqual(store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Tombstoned Place" }?.userPlace.syncState, .tombstoned)
    }

    func testRemoteFollowFailureLeavesFailedLocalFollow() async {
        let store = makeStore()
        let followRepository = FakeFollowRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(followRepository: followRepository)

        let acknowledged = await store.follow(userID: "user_sofia", source: .username, backend: backend)

        let follow = store.follows.first { $0.followedUserID == "user_sofia" }
        XCTAssertFalse(acknowledged)
        XCTAssertFalse(store.hasAcknowledgedFollow(to: "user_sofia"))
        XCTAssertEqual(follow?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertEqual(followRepository.followedUserIDs, ["user_sofia"])
        XCTAssertNotNil(follow?.lastSyncError)
    }

    func testRemoteFollowReturnsAcknowledgedOnlyAfterBackendSuccess() async {
        let store = makeStore()
        let sofia = ProfileShell(
            id: "user_sofia",
            handle: "sofia",
            displayName: "Sofia Rivera",
            avatarURL: nil,
            bio: nil,
            relationship: .follower
        )
        let followRepository = FakeFollowRepository(
            following: [sofia],
            relationships: ["user_sofia": .follower]
        )
        let backend = WanderBackend(followRepository: followRepository)

        let acknowledged = await store.follow(userID: "user_sofia", source: .profile, backend: backend)

        XCTAssertTrue(acknowledged)
        XCTAssertTrue(store.hasAcknowledgedFollow(to: "user_sofia"))
        XCTAssertEqual(followRepository.followedUserIDs, ["user_sofia"])
    }

    func testRemoteUnfollowFailureKeepsFailedLocalFollow() async {
        let store = makeStore()
        let followRepository = FakeFollowRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(followRepository: followRepository)

        await store.unfollow(userID: "user_maya", backend: backend)

        let follow = store.follows.first { $0.followedUserID == "user_maya" }
        XCTAssertEqual(follow?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertEqual(followRepository.unfollowedUserIDs, ["user_maya"])
        XCTAssertNotNil(follow?.lastSyncError)
    }

    func testRemoteUnblockFailureKeepsFailedLocalBlock() async {
        let store = makeStore()
        store.block(userID: "user_maya")
        let blockRepository = FakeBlockRepository(error: WanderRemoteError.invalidResponse("network down"))
        let backend = WanderBackend(blockRepository: blockRepository)

        await store.unblock(userID: "user_maya", backend: backend)

        let block = store.blocks.first { $0.blockedUserID == "user_maya" }
        XCTAssertEqual(block?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertEqual(blockRepository.unblockedUserIDs, ["user_maya"])
        XCTAssertNotNil(block?.lastSyncError)
    }

    func testSeededPlaceListsRespectOwnerFriendAndCollabScopes() {
        let store = makeStore()

        XCTAssertTrue(store.visiblePlaceLists(scope: .mine).contains { $0.id == "list_laptop" })
        XCTAssertTrue(store.visiblePlaceLists(scope: .mine).contains { $0.id == "list_launch" })
        XCTAssertFalse(store.visiblePlaceLists(scope: .mine).contains { $0.id == "list_maya_sunset" })
        XCTAssertTrue(store.visiblePlaceLists(scope: .friends).contains { $0.id == "list_maya_sunset" })
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).contains { $0.id == "list_launch" })
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).contains { $0.id == "list_saturday" })
        XCTAssertFalse(store.visiblePlaceLists(scope: .collabs).contains { $0.id == "list_laptop" })
    }

    func testListSuggestionsExcludeExistingPlaces() {
        let store = makeStore()
        let list = store.placeLists.first { $0.id == "list_laptop" }!
        let existingPlaceIDs = Set(store.visiblePlaces(in: list).map(\.place.id))

        let suggestions = store.listSuggestions(for: list, limit: 6)

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { !existingPlaceIDs.contains($0.visiblePlace.place.id) })
        for (index, suggestion) in suggestions.enumerated() {
            XCTAssertFalse(suggestions.dropFirst(index + 1).contains {
                VisiblePlaceGrouping.matches(suggestion.visiblePlace, $0.visiblePlace)
            })
        }
    }

    func testListSuggestionsRequireAtLeastOneSharedPlaceAttribute() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "A mixed day",
                description: "Places worth keeping together",
                visibility: .followers
            )
        )

        func save(
            _ id: String,
            name: String,
            category: String,
            locality: String,
            ratingScore: Double? = nil,
            attributes: [PlaceAttributeDraft] = []
        ) -> SaveResult {
            store.saveCandidate(
                PlaceCandidate(
                    id: id,
                    name: name,
                    category: category,
                    locality: locality,
                    region: locality == "Los Angeles" ? "CA" : "WA",
                    country: "US",
                    latitude: 34.04,
                    longitude: -118.24,
                    confidence: 0.95
                ),
                status: ratingScore == nil ? .wannaGo : .been,
                visibility: .followers,
                note: nil,
                sourceType: .manual,
                ratingScore: ratingScore,
                attributes: attributes
            )
        }

        let anchor = save(
            "anchor_coffee",
            name: "Anchor Coffee",
            category: "coffee",
            locality: "Los Angeles",
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    stringValues: ["sunny patio"]
                )
            ]
        )
        XCTAssertEqual(store.addCurrentUserPlace(userPlaceID: anchor.userPlaceID, to: list).outcome, .added)

        _ = save(
            "category_match",
            name: "Seattle Coffee",
            category: "coffee",
            locality: "Seattle"
        )
        _ = save(
            "location_match",
            name: "LA Design Museum",
            category: "museum",
            locality: "Los Angeles"
        )
        _ = save(
            "label_match",
            name: "Portland Garden",
            category: "garden",
            locality: "Portland",
            attributes: [
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    stringValues: ["sunny patio"]
                )
            ]
        )
        _ = save(
            "unrelated_high_rating",
            name: "Seattle Ridge Trail",
            category: "trail",
            locality: "Seattle",
            ratingScore: 5
        )

        let suggestions = store.listSuggestions(for: list, limit: 10)
        let names = Set(suggestions.map { $0.visiblePlace.place.canonicalName })

        XCTAssertEqual(names, ["Seattle Coffee", "LA Design Museum", "Portland Garden"])
        XCTAssertFalse(names.contains("Seattle Ridge Trail"))
    }

    func testRemoteListSuggestionsRejectUnrelatedCandidatesAndExplainTheSharedAttribute() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "A mixed day",
                description: "Places worth keeping together",
                visibility: .followers
            )
        )

        func save(_ id: String, name: String, category: String, locality: String, ratingScore: Double? = nil) -> SaveResult {
            store.saveCandidate(
                PlaceCandidate(
                    id: id,
                    name: name,
                    category: category,
                    locality: locality,
                    region: locality == "Los Angeles" ? "CA" : "WA",
                    country: "US",
                    latitude: 34.04,
                    longitude: -118.24,
                    confidence: 0.95
                ),
                status: ratingScore == nil ? .wannaGo : .been,
                visibility: .followers,
                note: nil,
                sourceType: .manual,
                ratingScore: ratingScore
            )
        }

        let anchor = save("anchor_coffee", name: "Anchor Coffee", category: "coffee", locality: "Los Angeles")
        XCTAssertEqual(store.addCurrentUserPlace(userPlaceID: anchor.userPlaceID, to: list).outcome, .added)
        let locationMatch = save("location_match", name: "LA Design Museum", category: "museum", locality: "Los Angeles")
        let unrelated = save(
            "unrelated_high_rating",
            name: "Seattle Ridge Trail",
            category: "trail",
            locality: "Seattle",
            ratingScore: 5
        )
        let locationMatchID = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == locationMatch.userPlaceID }?.id
        )
        let unrelatedID = try XCTUnwrap(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == unrelated.userPlaceID }?.id
        )
        let repository = FakeListSuggestionRepository(
            response: ListSuggestionFunctionResponse(
                suggestions: [
                    ListSuggestionFunctionItem(
                        visiblePlaceID: unrelatedID,
                        reason: "Fits: highly rated",
                        score: 1
                    ),
                    ListSuggestionFunctionItem(
                        visiblePlaceID: locationMatchID,
                        reason: "Fits: favorite",
                        score: 0.9
                    )
                ]
            )
        )
        let backend = WanderBackend(listSuggestionRepository: repository)

        let suggestions = await store.listSuggestions(for: list, limit: 10, backend: backend)

        XCTAssertEqual(suggestions.map { $0.visiblePlace.place.canonicalName }, ["LA Design Museum"])
        XCTAssertEqual(suggestions.first?.reason, "Fits: Los Angeles")
        XCTAssertEqual(repository.payloads.first?.candidatePlaces.map(\.visiblePlaceID), [locationMatchID])
    }

    func testListSuggestionReasonsRemoveInternalMetadataLabels() throws {
        let store = makeStore()
        let visiblePlace = try XCTUnwrap(
            store.visiblePlaces().first { $0.place.locality == "Los Angeles" }
        )

        XCTAssertEqual(
            ListSuggestionReasonFormatter.displayText(
                "Fits: areas_addresses + Los Angeles",
                for: visiblePlace
            ),
            "Fits: Los Angeles"
        )
        XCTAssertEqual(
            ListSuggestionReasonFormatter.displayText(
                "Fits: place + outdoor_seating",
                for: visiblePlace
            ),
            "Fits: outdoor seating"
        )
        XCTAssertEqual(
            ListSuggestionReasonFormatter.displayText(
                "Fits: Bakery + and, coffee",
                for: visiblePlace
            ),
            "Fits: Bakery + coffee"
        )

        let fallback = ListSuggestionReasonFormatter.displayText(
            "Fits: areas_addresses + addresses, areas",
            for: visiblePlace
        )
        XCTAssertTrue(fallback.contains("Los Angeles"))
        XCTAssertTrue(fallback.contains(visiblePlace.effectiveCompactType))
        XCTAssertFalse(fallback.contains("_"))
        XCTAssertFalse(fallback.lowercased().contains("areas"))
        XCTAssertFalse(fallback.lowercased().contains("place"))
    }

    func testListSuggestionFallbackRechecksMembershipAfterRemoteRequest() async throws {
        for (returnsAddedPlace, fails) in [(false, false), (true, false), (false, true)] {
            let store = makeStore()
            let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_laptop" })
            let candidate = try XCTUnwrap(store.listSuggestions(for: list, limit: 1).first)
            let response = ListSuggestionFunctionResponse(suggestions: returnsAddedPlace ? [
                ListSuggestionFunctionItem(visiblePlaceID: candidate.id, reason: "Fits", score: 1)
            ] : [])
            let repository = FakeListSuggestionRepository(response: response)
            repository.shouldFail = fails
            repository.beforeResponse = {
                let result = await store.addVisiblePlace(candidate.visiblePlace, to: list, backend: nil)
                XCTAssertEqual(result.outcome, .added)
            }

            let suggestions = await store.listSuggestions(
                for: list, limit: 5, backend: WanderBackend(listSuggestionRepository: repository)
            )

            XCTAssertTrue(store.hasPlace(candidate.visiblePlace, in: list))
            XCTAssertFalse(suggestions.contains { VisiblePlaceGrouping.matches($0.visiblePlace, candidate.visiblePlace) })
            XCTAssertFalse(suggestions.contains { store.hasPlace($0.visiblePlace, in: list) })
        }
    }

    func testDisplayedSuggestionsExcludePlacesAddedThroughAnotherFlow() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_laptop" })
        let batch = store.listSuggestions(for: list, limit: 5)
        XCTAssertGreaterThan(batch.count, 1)
        let added = try XCTUnwrap(batch.first)
        let result = await store.addVisiblePlace(added.visiblePlace, to: list, backend: nil)
        XCTAssertEqual(result.outcome, .added)

        let displayed = store.availableListSuggestions(batch, for: list)

        XCTAssertEqual(displayed.map(\.id), batch.dropFirst().map(\.id))
        XCTAssertFalse(displayed.contains { store.hasPlace($0.visiblePlace, in: list) })
    }

    func testListSuggestionsExcludeSyncedSnapshotMembersUsingPreSyncList() async throws {
        let store = makeStore()
        let ownPlaces = store.currentUserVisiblePlaces
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
            .image { _ in }.jpegData(compressionQuality: 0.8)!
        let list = try XCTUnwrap(store.createMapSnapshotList(
            placeIDs: ownPlaces.map { $0.place.id }, coverData: data
        ))
        let batch = store.listSuggestions(for: list, limit: 20)
        _ = await store.syncPendingPlaceLists(backend: WanderBackend(placeListRepository: FakePlaceListRepository()))
        let synced = try XCTUnwrap(store.placeLists.first { $0.localID == list.localID })
        XCTAssertNotEqual(list.id, synced.id)
        XCTAssertTrue(store.placeListItems.contains { $0.listID == synced.id })

        XCTAssertTrue(ownPlaces.allSatisfy { store.hasPlace($0, in: list) })
        XCTAssertEqual(store.visiblePlaces(in: list).count, store.visiblePlaces(in: synced).count)
        for suggestions in [
            store.listSuggestions(for: list, limit: 20),
            store.availableListSuggestions(batch, for: list)
        ] {
            XCTAssertFalse(suggestions.contains { store.hasPlace($0.visiblePlace, in: synced) })
        }
    }

    func testRemoteListSuggestionReasonsUseReadableMetadata() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_laptop" })
        let candidate = try XCTUnwrap(store.listSuggestions(for: list, limit: 1).first)
        let repository = FakeListSuggestionRepository(
            response: ListSuggestionFunctionResponse(
                suggestions: [
                    ListSuggestionFunctionItem(
                        visiblePlaceID: candidate.visiblePlace.id,
                        reason: "Fits: areas_addresses + \(candidate.visiblePlace.place.locality ?? "place")",
                        score: 0.9
                    )
                ]
            )
        )
        let backend = WanderBackend(listSuggestionRepository: repository)

        let suggestions = await store.listSuggestions(for: list, limit: 1, backend: backend)
        let reason = try XCTUnwrap(suggestions.first?.reason)

        XCTAssertFalse(reason.contains("_"))
        XCTAssertFalse(reason.lowercased().contains("areas"))
        XCTAssertNotEqual(reason.lowercased(), "fits: place")
    }

    func testListSuggestionsRespectAFocusedCategoryFamily() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Coffee and bakeries",
                description: "Morning coffee and pastries",
                visibility: .followers
            )
        )

        func save(_ id: String, name: String, category: String, latitude: Double) -> SaveResult {
            store.saveCandidate(
                PlaceCandidate(
                    id: id,
                    name: name,
                    category: category,
                    locality: "Los Angeles",
                    region: "CA",
                    latitude: latitude,
                    longitude: -118.24,
                    confidence: 0.95
                ),
                status: .wannaGo,
                visibility: .followers,
                note: nil,
                sourceType: .manual
            )
        }

        let existing = [
            save("coffee_1", name: "Coffee One", category: "coffee", latitude: 34.041),
            save("coffee_2", name: "Coffee Two", category: "cafe", latitude: 34.042),
            save("coffee_3", name: "Bakery Three", category: "bakery", latitude: 34.043),
            save("coffee_4", name: "Coffee Four", category: "coffee shop", latitude: 34.044),
            save("trail_1", name: "Existing Trail", category: "trail", latitude: 34.045)
        ]
        for saveResult in existing {
            XCTAssertEqual(store.addCurrentUserPlace(userPlaceID: saveResult.userPlaceID, to: list).outcome, .added)
        }
        _ = save("coffee_candidate", name: "Coffee Candidate", category: "coffee", latitude: 34.046)
        _ = save("trail_candidate", name: "S Bay Trail", category: "trail", latitude: 34.047)

        let suggestions = store.listSuggestions(for: list, limit: 8)

        XCTAssertEqual(suggestions.map { $0.visiblePlace.place.canonicalName }, ["Coffee Candidate"])
        XCTAssertTrue(suggestions.allSatisfy {
            $0.visiblePlace.effectiveCategory == WanderPlaceCategory.coffeeTeaSweets
        })
    }

    func testListSuggestionsDeduplicateCanonicalSavesAndLabelDistinctLocations() throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Coffee",
                description: "Coffee shops",
                visibility: .followers
            )
        )

        for index in 0..<3 {
            let saved = store.saveCandidate(
                PlaceCandidate(
                    id: "anchor_\(index)",
                    name: "Anchor Coffee \(index)",
                    category: "coffee",
                    locality: "Los Angeles",
                    region: "CA",
                    latitude: 34.01 + Double(index) * 0.001,
                    longitude: -118.24,
                    confidence: 0.95
                ),
                status: .wannaGo,
                visibility: .followers,
                note: nil,
                sourceType: .manual
            )
            XCTAssertEqual(store.addCurrentUserPlace(userPlaceID: saved.userPlaceID, to: list).outcome, .added)
        }

        _ = store.saveCandidate(
            PlaceCandidate(
                id: "gnarwhal_santa_monica",
                name: "Gnarwhal Coffee Co.",
                category: "coffee",
                address: "3101 Main Street",
                locality: "Santa Monica",
                region: "CA",
                latitude: 34.001,
                longitude: -118.481,
                confidence: 0.95
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )
        _ = store.saveCandidate(
            PlaceCandidate(
                id: "gnarwhal_downtown",
                name: "Gnarwhal Coffee Co.",
                category: "coffee",
                address: "700 South Grand Avenue",
                locality: "Los Angeles",
                region: "CA",
                latitude: 34.047,
                longitude: -118.256,
                confidence: 0.95
            ),
            status: .wannaGo,
            visibility: .followers,
            note: nil,
            sourceType: .manual
        )

        let suggestions = store.listSuggestions(for: list, limit: 8)
            .filter { $0.visiblePlace.place.canonicalName == "Gnarwhal Coffee Co." }

        XCTAssertEqual(suggestions.count, 2, "Different locations should remain separate suggestions")
        XCTAssertTrue(suggestions.contains { $0.reason.contains("3101 Main Street") })
        XCTAssertTrue(suggestions.contains { $0.reason.contains("700 South Grand Avenue") })
        XCTAssertEqual(
            suggestions.count,
            Set(suggestions.map { VisiblePlaceGrouping.key(for: $0.visiblePlace) }).count
        )
    }

    func testListSuggestionBatchKeepsRemainingPlacesUntilExhausted() throws {
        let store = makeStore()
        let places = Array(store.visiblePlaces().prefix(3))
        XCTAssertEqual(places.count, 3)
        let suggestions = places.enumerated().map { index, place in
            ListPlaceSuggestion(visiblePlace: place, reason: "Suggestion \(index)", score: Double(index))
        }
        var batch = ListSuggestionBatch()
        batch.replace(with: suggestions)

        let firstID = try XCTUnwrap(suggestions.first?.id)
        XCTAssertTrue(batch.beginAdding(suggestionID: firstID))
        XCTAssertFalse(batch.beginAdding(suggestionID: firstID), "Repeated taps must not start duplicate adds")
        XCTAssertFalse(batch.finishAdding(suggestionID: firstID, outcome: .added))
        XCTAssertEqual(batch.suggestions.map(\.id), Array(suggestions.dropFirst()).map(\.id))

        let secondID = suggestions[1].id
        XCTAssertTrue(batch.beginAdding(suggestionID: secondID))
        XCTAssertFalse(batch.finishAdding(suggestionID: secondID, outcome: .alreadyInList))
        XCTAssertEqual(batch.suggestions.map(\.id), [suggestions[2].id])

        let finalID = suggestions[2].id
        XCTAssertTrue(batch.beginAdding(suggestionID: finalID))
        XCTAssertTrue(batch.finishAdding(suggestionID: finalID, outcome: .added))
        XCTAssertTrue(batch.suggestions.isEmpty)
    }

    func testListSuggestionBatchKeepsFailedAdditionAndResetsForRelaunch() throws {
        let store = makeStore()
        let visiblePlace = try XCTUnwrap(store.visiblePlaces().first)
        let suggestion = ListPlaceSuggestion(visiblePlace: visiblePlace, reason: "Fits", score: 1)
        var batch = ListSuggestionBatch()
        batch.replace(with: [suggestion])

        XCTAssertTrue(batch.beginAdding(suggestionID: suggestion.id))
        XCTAssertFalse(batch.finishAdding(suggestionID: suggestion.id, outcome: .permissionDenied))
        XCTAssertEqual(batch.suggestions.map(\.id), [suggestion.id])
        XCTAssertTrue(batch.beginAdding(suggestionID: suggestion.id), "A failed add should be retryable")

        batch.cancelPendingAdditions()
        XCTAssertFalse(batch.finishAdding(suggestionID: suggestion.id, outcome: .added))
        XCTAssertEqual(batch.suggestions.map(\.id), [suggestion.id])
        XCTAssertTrue(batch.beginAdding(suggestionID: suggestion.id), "Cancelling the flow must clear pending taps")

        var relaunchedBatch = ListSuggestionBatch()
        relaunchedBatch.replace(with: [suggestion])
        XCTAssertEqual(relaunchedBatch.suggestions.map(\.id), [suggestion.id])
        XCTAssertFalse(relaunchedBatch.isAdding(suggestionID: suggestion.id))
    }

    func testRepeatedListSuggestionAddIsIdempotent() async throws {
        let store = makeStore()
        let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_laptop" })
        let suggestion = try XCTUnwrap(store.listSuggestions(for: list, limit: 1).first)
        let initialCount = store.visiblePlaces(in: list).count

        let firstResult = await store.addVisiblePlace(suggestion.visiblePlace, to: list, backend: nil)
        let repeatedResult = await store.addVisiblePlace(suggestion.visiblePlace, to: list, backend: nil)

        XCTAssertEqual(firstResult.outcome, .added)
        XCTAssertEqual(repeatedResult.outcome, .alreadyInList)
        XCTAssertEqual(store.visiblePlaces(in: list).count, initialCount + 1)
    }

    func testOwnerCanAddNetworkPlaceAndAutoSaveItToWant() async {
        let store = makeStore()
        let list = store.placeLists.first { $0.id == "list_laptop" }!
        let socialPlace = store.visiblePlaces()
            .first { $0.place.canonicalName == "Griffith Observatory Trail" && $0.owner.id != store.currentUser.id }!

        let result = await store.addVisiblePlace(socialPlace, to: list, backend: nil)

        XCTAssertEqual(result.outcome, .added)
        XCTAssertTrue(result.createdWantSave)
        XCTAssertTrue(result.shouldExplainAutoSave)
        XCTAssertTrue(store.visiblePlaces(in: list).contains { $0.place.canonicalName == "Griffith Observatory Trail" })
        XCTAssertTrue(store.currentUserVisiblePlaces.contains {
            $0.place.canonicalName == "Griffith Observatory Trail"
                && $0.userPlace.status == .wannaGo
        })
        let projectedPlace = store.visiblePlaces(in: list).first {
            $0.place.canonicalName == "Griffith Observatory Trail"
        }
        XCTAssertEqual(projectedPlace?.owner.id, store.currentUser.id)
        XCTAssertEqual(projectedPlace?.userPlace.status, .wannaGo)
        let canonicalGroup = VisiblePlaceGrouping.matchingGroup(
            for: socialPlace,
            in: store.visiblePlaces(),
            currentUserID: store.currentUser.id
        )
        XCTAssertTrue(canonicalGroup?.places.contains { $0.owner.id == store.currentUser.id } == true)
        XCTAssertTrue(canonicalGroup?.places.contains { $0.owner.id != store.currentUser.id } == true)
        let outlines = MapPinOutlineBuilder.outlines(
            for: canonicalGroup?.places.map {
                MapPinSaveState(
                    ownership: $0.owner.id == store.currentUser.id ? .currentUser : .social,
                    status: $0.userPlace.status
                )
            } ?? []
        )
        XCTAssertEqual(outlines.count, 2)
        XCTAssertTrue(outlines.contains { $0.ownership == .currentUser })
        XCTAssertTrue(outlines.contains { $0.ownership == .social })
    }

    func testListAddPreservesOutOfViewportSocialSaveForCanonicalOutlines() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(
            authState: .signedIn(
                AuthSession(userID: "user_current", displayName: "Ryan", handle: "ryan")
            )
        )
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "NYC bakeries",
                description: "Places to try",
                visibility: .followers
            )
        )
        let placeID = "11111111-1111-4111-8111-111111111111"
        let sourceUserPlaceID = "22222222-2222-4222-8222-222222222222"
        let createdUserPlaceID = "33333333-3333-4333-8333-333333333333"
        let socialPlace = VisiblePlace(
            id: sourceUserPlaceID,
            place: LocalPlace(
                localID: "remote_place_maison_twenty_seven",
                serverID: placeID,
                canonicalName: "Maison Twenty Seven",
                category: "bakery",
                address: "27 Spring Street",
                locality: "New York",
                region: "NY",
                country: "US",
                latitude: 40.722,
                longitude: -73.995,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: "maison-twenty-seven",
                syncState: .synced
            ),
            userPlace: LocalUserPlace(
                localID: "remote_up_joe_maison_twenty_seven",
                serverID: sourceUserPlaceID,
                userID: "user_joe",
                placeID: placeID,
                status: .been,
                visibility: .followers,
                sourceType: "manual",
                syncState: .synced
            ),
            owner: LocalProfile(
                localID: "remote_profile_joe",
                serverID: "user_joe",
                handle: "joe",
                displayName: "Joe",
                syncState: .synced
            )
        )
        let placeRepository = FakePlaceRepository(places: [socialPlace])
        let socialSaveRepository = FakeSocialPlaceSaveRepository(
            result: SaveResult(userPlaceID: createdUserPlaceID, syncState: .synced)
        )
        let backend = WanderBackend(
            placeRepository: placeRepository,
            socialPlaceSaveRepository: socialSaveRepository
        )
        let newYorkViewport = MapViewport(
            minLatitude: 40.6,
            minLongitude: -74.1,
            maxLatitude: 40.9,
            maxLongitude: -73.7
        )
        await store.refreshRemoteVisiblePlaces(in: newYorkViewport, backend: backend)
        let suggestion = try XCTUnwrap(
            store.visiblePlaces().first { $0.userPlace.id == sourceUserPlaceID }
        )

        // The social save is outside the automatic post-save LA viewport.
        placeRepository.setPlaces([])
        let result = await store.addVisiblePlace(suggestion, to: list, backend: backend)

        XCTAssertEqual(result.companionSave, .createdWanna(userPlaceID: createdUserPlaceID))
        let group = try XCTUnwrap(
            VisiblePlaceGrouping.matchingGroup(
                for: suggestion,
                in: store.visiblePlaces(),
                currentUserID: store.currentUser.id
            )
        )
        XCTAssertTrue(group.places.contains { $0.owner.id == store.currentUser.id })
        XCTAssertTrue(group.places.contains { $0.owner.id == "user_joe" })

        let outlines = MapPinOutlineBuilder.outlines(
            for: group.places.map {
                MapPinSaveState(
                    ownership: $0.owner.id == store.currentUser.id ? .currentUser : .social,
                    status: $0.userPlace.status
                )
            }
        )
        XCTAssertTrue(outlines.contains {
            $0.ownership == .currentUser && $0.status == .wannaGo
        })
        XCTAssertTrue(outlines.contains {
            $0.ownership == .social && $0.status == .been
        })
    }

    func testAddingUnsavedCandidateToListReportsCreatedWannaForEditableToast() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Try next",
                description: "Places to remember",
                visibility: .followers
            )
        )
        let candidate = PlaceCandidate(
            id: "rec348_unsaved",
            name: "New Corner Cafe",
            category: "coffee",
            latitude: 34.041,
            longitude: -118.236,
            confidence: 0.94
        )

        let result = await store.addCandidate(candidate, to: list, backend: nil)

        XCTAssertEqual(result.outcome, .added)
        guard case .createdWanna(let userPlaceID) = result.companionSave else {
            return XCTFail("Expected the list add to report its newly-created Wanna save")
        }
        XCTAssertTrue(result.createdWantSave)
        XCTAssertTrue(result.shouldExplainAutoSave)
        XCTAssertEqual(
            store.currentUserVisiblePlaces.first { $0.userPlace.id == userPlaceID }?.userPlace.status,
            .wannaGo
        )
        let toast = try XCTUnwrap(ListSaveToastPresentation(companionSave: result.companionSave))
        XCTAssertEqual(toast.message, "We also saved this to your Wanna Go")
        XCTAssertEqual(toast.actionTitle, "edit")
        let context = try XCTUnwrap(listSaveFlowContext(for: result.companionSave, store: store))
        guard case .add = context.mode else {
            return XCTFail("A newly-created Wanna should reopen the Check In/Wanna landing step")
        }
        XCTAssertEqual(context.initialStatus, .wannaGo)
        XCTAssertTrue(context.requiresStatusConfirmation)
        XCTAssertTrue(context.preselectsInitialStatus)
    }

    func testAddingExistingWannaToListReportsDirectWannaEditTarget() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Try next",
                description: "Places to remember",
                visibility: .followers
            )
        )
        let candidate = PlaceCandidate(
            id: "rec348_wanna",
            name: "Saved Corner Cafe",
            category: "coffee",
            latitude: 34.042,
            longitude: -118.237,
            confidence: 0.94
        )
        let wanna = store.saveCandidate(
            candidate,
            status: .wannaGo,
            visibility: .followers,
            note: "try the patio",
            sourceType: .manual
        )

        let result = await store.addCandidate(candidate, to: list, backend: nil)

        XCTAssertEqual(result.outcome, .added)
        XCTAssertEqual(result.companionSave, .existingWanna(userPlaceID: wanna.userPlaceID))
        XCTAssertFalse(result.createdWantSave)
        XCTAssertTrue(result.shouldExplainAutoSave)
        let toast = try XCTUnwrap(ListSaveToastPresentation(companionSave: result.companionSave))
        XCTAssertEqual(toast.message, "This is already saved to your Wanna Go")
        XCTAssertEqual(toast.actionTitle, "edit")
        let context = try XCTUnwrap(listSaveFlowContext(for: result.companionSave, store: store))
        guard case .editWant(let visiblePlace) = context.mode else {
            return XCTFail("An existing Wanna should open its editor directly")
        }
        XCTAssertEqual(visiblePlace.userPlace.id, wanna.userPlaceID)
    }

    func testAddingCheckedInPlaceToListDoesNotShowCompanionSaveToast() async throws {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let list = try XCTUnwrap(
            store.createPlaceList(
                name: "Favorites",
                description: "Places worth returning to",
                visibility: .followers
            )
        )
        let candidate = PlaceCandidate(
            id: "rec348_checkin",
            name: "Visited Corner Cafe",
            category: "coffee",
            latitude: 34.043,
            longitude: -118.238,
            confidence: 0.94
        )
        let checkIn = store.saveCandidate(
            candidate,
            status: .been,
            visibility: .followers,
            note: "great morning light",
            sourceType: .manual,
            ratingScore: 4.5
        )

        let result = await store.addCandidate(candidate, to: list, backend: nil)

        XCTAssertEqual(result.outcome, .added)
        XCTAssertEqual(result.companionSave, .none)
        XCTAssertFalse(result.createdWantSave)
        XCTAssertFalse(result.shouldExplainAutoSave)
        XCTAssertEqual(store.visits(for: checkIn.userPlaceID).first?.note, "great morning light")
        XCTAssertNil(ListSaveToastPresentation(companionSave: result.companionSave))
    }

    func testNonMemberCannotAddPlaceToSomeoneElsesList() async {
        let store = makeStore()
        let friendList = store.placeLists.first { $0.id == "list_maya_sunset" }!
        let place = store.visiblePlaces().first { $0.place.canonicalName == "Bar Nido" }!
        let initialCount = store.visiblePlaces(in: friendList).count

        let result = await store.addVisiblePlace(place, to: friendList, backend: nil)

        XCTAssertEqual(result.outcome, .permissionDenied)
        XCTAssertEqual(store.visiblePlaces(in: friendList).count, initialCount)
    }

    func testOwnerRemoveListPlacePersistsLocally() {
        let store = makeStore()
        let list = store.placeLists.first { $0.id == "list_laptop" }!

        XCTAssertTrue(store.removePlace(placeID: "place_circuit_coffee", from: list))

        XCTAssertFalse(store.visiblePlaces(in: list).contains { $0.place.id == "place_circuit_coffee" })
        XCTAssertEqual(
            store.placeListItems.first { $0.serverID == "list_item_laptop_circuit" }?.syncState,
            .pendingDelete
        )
    }

    func testJadeRabbitEquivalentProviderResolutionsShareCanonicalListMembership() async throws {
        let store = WanderStore(fixtures: makeJadeRabbitMultipleResolutionFixture())
        let list = try XCTUnwrap(store.placeLists.first)

        XCTAssertTrue(VisiblePlaceGrouping.matches(store.places[0], store.places[1]))
        XCTAssertEqual(store.visiblePlaces(in: list).map(\.place.canonicalName), ["Jade Rabbit"])

        XCTAssertTrue(store.removePlace(placeID: store.places[0].id, from: list))
        XCTAssertTrue(
            store.removePlace(placeID: store.places[1].id, from: list),
            "Equivalent repeated removals should be idempotent"
        )

        XCTAssertTrue(store.visiblePlaces(in: list).isEmpty)
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.deletedAt != nil })
        XCTAssertFalse(
            store.listSuggestions(for: list, limit: 10).contains {
                $0.visiblePlace.place.canonicalName == "Jade Rabbit"
            },
            "A deleted canonical venue must not immediately return as a duplicate suggestion"
        )

        let explicitRestorePlace = try XCTUnwrap(
            store.visiblePlaces().first { $0.place.canonicalName == "Jade Rabbit" }
        )
        let restoreResult = await store.addVisiblePlace(explicitRestorePlace, to: list, backend: nil)
        XCTAssertEqual(restoreResult.outcome, .added)
        XCTAssertEqual(store.visiblePlaces(in: list).map(\.place.canonicalName), ["Jade Rabbit"])
    }

    func testJadeRabbitDeletionRemovesEveryEquivalentRemoteItemOnce() async throws {
        let store = WanderStore(fixtures: makeJadeRabbitMultipleResolutionFixture())
        let list = try XCTUnwrap(store.placeLists.first)
        let repository = FakePlaceListRepository()
        let backend = WanderBackend(placeListRepository: repository)

        let firstRemoval = await store.removePlace(placeID: store.places[0].id, from: list, backend: backend)
        let repeatedRemoval = await store.removePlace(placeID: store.places[1].id, from: list, backend: backend)

        XCTAssertTrue(firstRemoval)
        XCTAssertTrue(repeatedRemoval)

        XCTAssertEqual(
            Set(repository.removedItems.map(\.itemID)),
            Set([
                "22222222-2222-4222-8222-222222222222",
                "33333333-3333-4333-8333-333333333333"
            ])
        )
        XCTAssertEqual(repository.removedItems.count, 2)
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.syncState == .tombstoned })
    }

    func testListDeletionUsesRenderedUserPlaceIdentityWhenPlaceResolutionIsStale() async throws {
        let store = WanderStore(fixtures: makeJadeRabbitMultipleResolutionFixture())
        let list = try XCTUnwrap(store.placeLists.first)
        let renderedPlace = try XCTUnwrap(store.visiblePlaces(in: list).first)
        let repository = FakePlaceListRepository()
        let backend = WanderBackend(placeListRepository: repository)

        let removed = await store.removePlace(
            placeID: "stale-provider-place-alias",
            visiblePlaceID: renderedPlace.id,
            from: list,
            backend: backend
        )

        XCTAssertTrue(removed)
        XCTAssertTrue(store.visiblePlaces(in: list).isEmpty)
        XCTAssertEqual(
            Set(repository.removedItems.map(\.itemID)),
            Set([
                "22222222-2222-4222-8222-222222222222",
                "33333333-3333-4333-8333-333333333333"
            ])
        )
    }

    func testJadeRabbitDeletionSurvivesRelaunchAndRetriesPendingRemoteDeletes() async throws {
        let fixture = makeTemporaryPersistence()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let firstStore = WanderStore(
            fixtures: makeJadeRabbitMultipleResolutionFixture(),
            persistence: fixture.persistence
        )
        let firstList = try XCTUnwrap(firstStore.placeLists.first)

        XCTAssertTrue(firstStore.removePlace(placeID: firstStore.places[0].id, from: firstList))
        firstStore.flushPersistence()

        let relaunchedStore = WanderStore(fixtures: .empty(), persistence: fixture.persistence)
        let relaunchedList = try XCTUnwrap(relaunchedStore.placeLists.first)
        XCTAssertTrue(relaunchedStore.visiblePlaces(in: relaunchedList).isEmpty)

        let repository = FakePlaceListRepository()
        let syncedCount = await relaunchedStore.syncPendingPlaceLists(
            backend: WanderBackend(placeListRepository: repository)
        )

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(
            Set(repository.removedItems.map(\.itemID)),
            Set([
                "22222222-2222-4222-8222-222222222222",
                "33333333-3333-4333-8333-333333333333"
            ])
        )
        XCTAssertTrue(relaunchedStore.visiblePlaces(in: relaunchedList).isEmpty)
        XCTAssertTrue(relaunchedStore.placeListItems.allSatisfy { $0.syncState == .tombstoned })
    }

    func testStaleListDetailCannotReviveJadeRabbitAfterDeletionSync() async throws {
        let store = WanderStore(fixtures: makeJadeRabbitMultipleResolutionFixture())
        let list = try XCTUnwrap(store.placeLists.first)
        let staleItems = store.placeListItems
        let staleList = LocalPlaceList(
            localID: list.localID,
            serverID: list.serverID,
            ownerUserID: list.ownerUserID,
            name: list.name,
            description: list.description,
            visibility: list.visibility,
            syncState: .synced,
            cachedItemCount: 2,
            createdAt: list.createdAt,
            updatedAt: list.updatedAt
        )
        let repository = FakePlaceListRepository(
            details: [
                list.id: RemotePlaceListDetail(
                    list: staleList,
                    collaborators: [],
                    items: staleItems
                )
            ]
        )
        let backend = WanderBackend(placeListRepository: repository)

        XCTAssertTrue(store.removePlace(placeID: store.places[0].id, from: list))
        let syncedCount = await store.syncPendingPlaceLists(backend: backend)
        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(store.placeLists.first?.syncState, .synced)

        await store.refreshRemotePlaceList(list, backend: backend)

        let refreshedList = try XCTUnwrap(store.placeLists.first)
        XCTAssertTrue(store.visiblePlaces(in: refreshedList).isEmpty)
        XCTAssertEqual(refreshedList.cachedItemCount, 0)
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.deletedAt != nil })
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.syncState == .pendingDelete })
    }

    func testOwnerCanCreateUpdateAndDeletePlaceListLocally() {
        let store = makeStore()

        let created = store.createPlaceList(
            name: "  LA patios  ",
            description: "  sunny tables  ",
            visibility: .stealth,
            collaboratorUserIDs: ["user_ryan", store.currentUser.id]
        )!

        XCTAssertEqual(created.name, "LA patios")
        XCTAssertEqual(created.description, "sunny tables")
        XCTAssertEqual(created.visibility, .stealth)
        XCTAssertEqual(created.syncState, .pendingCreate)
        XCTAssertEqual(store.collaborators(for: created).map(\.id), ["user_ryan"])
        XCTAssertTrue(store.visiblePlaceLists(scope: .mine).contains { $0.id == created.id })
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).contains { $0.id == created.id })

        XCTAssertTrue(
            store.updatePlaceList(
                id: created.id,
                name: "Dinner backups",
                description: "date night and late tables",
                visibility: .followers,
                collaboratorUserIDs: ["user_maya"]
            )
        )

        let updated = store.placeLists.first { $0.id == created.id }!
        XCTAssertEqual(updated.name, "Dinner backups")
        XCTAssertEqual(updated.description, "date night and late tables")
        XCTAssertEqual(updated.visibility, .followers)
        XCTAssertEqual(updated.syncState, .pendingCreate)
        XCTAssertEqual(store.collaborators(for: updated).map(\.id), ["user_maya"])

        XCTAssertTrue(store.deletePlaceList(id: updated.id))
        XCTAssertFalse(store.visiblePlaceLists(scope: .mine).contains { $0.id == updated.id })
    }

    func testCollaboratorCannotManageAnotherUsersList() {
        let store = makeStore()
        let collabList = store.placeLists.first { $0.id == "list_launch" }!

        XCTAssertFalse(store.setPlaceListCollaborators(listID: collabList.id, collaboratorUserIDs: ["user_maya"]))
        XCTAssertEqual(store.collaborators(for: collabList).map(\.id), [store.currentUser.id])
    }

    func testOnlyCollaboratorCanLeaveSharedListLocally() async {
        let store = makeStore()
        let collaboratorList = store.placeLists.first { $0.id == "list_launch" }!
        let ownedList = store.placeLists.first { $0.id == "list_laptop" }!
        let friendList = store.placeLists.first { $0.id == "list_maya_sunset" }!

        XCTAssertTrue(store.canLeave(collaboratorList))
        XCTAssertFalse(store.canLeave(ownedList))
        XCTAssertFalse(store.canLeave(friendList))

        let didLeave = await store.leavePlaceList(collaboratorList, backend: nil)

        XCTAssertTrue(didLeave)

        XCTAssertFalse(store.visiblePlaceLists.contains { $0.id == collaboratorList.id })
        XCTAssertFalse(store.visiblePlaceLists(scope: .mine).contains { $0.id == collaboratorList.id })
        XCTAssertFalse(store.visiblePlaceLists(scope: .collabs).contains { $0.id == collaboratorList.id })
        XCTAssertNotNil(
            store.placeListMembers.first {
                $0.listID == collaboratorList.id && $0.userID == store.currentUser.id
            }?.deletedAt
        )
    }

    func testRemoteCollaboratorLeaveUsesBackendAndMovesFollowerVisibleListToFriends() async {
        let (store, collaboratorList) = makeRemoteCollaboratorListStore()
        let repository = FakePlaceListRepository()
        let backend = WanderBackend(placeListRepository: repository)

        let didLeave = await store.leavePlaceList(collaboratorList, backend: backend)

        XCTAssertTrue(didLeave)
        XCTAssertEqual(repository.leftListIDs, [collaboratorList.id])
        XCTAssertTrue(store.visiblePlaceLists.contains { $0.id == collaboratorList.id })
        XCTAssertFalse(store.visiblePlaceLists(scope: .mine).contains { $0.id == collaboratorList.id })
        XCTAssertFalse(store.visiblePlaceLists(scope: .collabs).contains { $0.id == collaboratorList.id })
        XCTAssertTrue(store.visiblePlaceLists(scope: .friends).contains { $0.id == collaboratorList.id })
        XCTAssertFalse(store.canLeave(collaboratorList))
        XCTAssertFalse(store.canAddPlaces(to: collaboratorList))
        XCTAssertNil(store.lastRemoteError)
    }

    func testFailedRemoteCollaboratorLeaveKeepsListVisible() async {
        let (store, collaboratorList) = makeRemoteCollaboratorListStore()
        let repository = FakePlaceListRepository(leaveError: TestError.expected)
        let backend = WanderBackend(placeListRepository: repository)

        let didLeave = await store.leavePlaceList(collaboratorList, backend: backend)

        XCTAssertFalse(didLeave)
        XCTAssertEqual(repository.leftListIDs, [collaboratorList.id])
        XCTAssertTrue(store.visiblePlaceLists.contains { $0.id == collaboratorList.id })
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testListPersistenceRestoresListsAndLocalPreferences() {
        let fixture = makeTemporaryPersistence()
        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.autoSaveListAddsToWant = false
        firstStore.defaultMapFilter = .friends
        firstStore.isDarkMapEnabled = true

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertEqual(relaunchedStore.placeLists.map(\.id), firstStore.placeLists.map(\.id))
        XCTAssertEqual(relaunchedStore.placeListItems.map(\.id), firstStore.placeListItems.map(\.id))
        XCTAssertFalse(relaunchedStore.autoSaveListAddsToWant)
        XCTAssertEqual(relaunchedStore.defaultMapFilter, .friends)
        XCTAssertTrue(relaunchedStore.isDarkMapEnabled)
    }

    func testBatchedListProjectionMatchesIndividualListProjection() {
        let store = makeStore()
        let lists = store.visiblePlaceLists
        let batched = store.visiblePlacesByListID(in: lists)

        for list in lists {
            XCTAssertEqual(
                batched[list.id]?.map(\.id),
                store.visiblePlaces(in: list).map(\.id),
                "Batched projection changed the visible places for \(list.id)"
            )
        }
    }

    func testListPresentationIndexesAreReusedUntilStoreMutation() throws {
        let store = makeStore()
        let lists = store.visiblePlaceLists
        let authorizationKey = store.listPhotoAuthorizationScopeKey()

        XCTAssertEqual(store.visiblePlaceListsBuildCount, 1)
        XCTAssertEqual(store.listPhotoAuthorizationScopeKeyBuildCount, 1)
        XCTAssertEqual(store.visiblePlaceLists.map(\.id), lists.map(\.id))
        XCTAssertEqual(store.listPhotoAuthorizationScopeKey(), authorizationKey)
        XCTAssertEqual(store.visiblePlaceListsBuildCount, 1)
        XCTAssertEqual(store.listPhotoAuthorizationScopeKeyBuildCount, 1)

        let mine = store.visiblePlaceLists(scope: .mine)
        XCTAssertEqual(store.visiblePlaceLists(scope: .mine).map(\.id), mine.map(\.id))
        XCTAssertEqual(store.visiblePlaceListsBuildCount, 1)

        for list in lists {
            _ = store.collaborators(for: list)
        }
        for list in lists.reversed() {
            _ = store.collaborators(for: list)
        }
        XCTAssertEqual(store.collaboratorIndexBuildCount, 1)

        _ = store.visiblePlacesByListID(in: lists)
        _ = store.visiblePlaces(in: try XCTUnwrap(lists.first))
        XCTAssertEqual(store.placeGroupingIndexBuildCount, 1)

        let expectedGroups = VisiblePlaceGrouping.groups(
            from: store.visiblePlaces(),
            currentUserID: store.currentUser.id
        )
        let cachedGroups = store.visiblePlaceGroups()
        XCTAssertEqual(cachedGroups.map(\.key), expectedGroups.map(\.key))
        XCTAssertEqual(
            cachedGroups.map { $0.places.map(\.id) },
            expectedGroups.map { $0.places.map(\.id) }
        )
        _ = store.visiblePlaceGroups()
        XCTAssertEqual(store.visiblePlaceGroupBuildCount, 1)

        store.block(userID: "user_maya")

        XCTAssertNotEqual(store.listPhotoAuthorizationScopeKey(), authorizationKey)
        XCTAssertEqual(store.listPhotoAuthorizationScopeKeyBuildCount, 2)
        _ = store.visiblePlaceLists
        XCTAssertEqual(store.visiblePlaceListsBuildCount, 2)
        _ = store.collaborators(for: try XCTUnwrap(store.placeLists.first))
        XCTAssertEqual(store.collaboratorIndexBuildCount, 2)
        _ = store.visiblePlacesByListID(in: store.visiblePlaceLists)
        XCTAssertEqual(store.placeGroupingIndexBuildCount, 2)
        _ = store.visiblePlaceGroups()
        XCTAssertEqual(store.visiblePlaceGroupBuildCount, 2)
    }

    func testRestoredLegacyListMembershipMatchesCurrentCollaborationBehavior() async throws {
        for legacy in [true, false] {
            let persistence = makeTemporaryPersistence()
            defer { try? FileManager.default.removeItem(at: persistence.directory) }
            let fixtures = makeListCompatibilityFixtures(legacy: legacy, owner: false)
            let firstStore = WanderStore(fixtures: fixtures, persistence: persistence.persistence)
            persistence.persistence.save(WanderStoreSnapshot(store: firstStore))
            firstStore.flushPersistence()
            let store = WanderStore(fixtures: .empty(), persistence: persistence.persistence)
            let list = try XCTUnwrap(store.placeLists.first)

            XCTAssertEqual(store.visiblePlaceLists(scope: .mine).map(\.id), [list.id])
            XCTAssertEqual(store.visiblePlaceLists(scope: .collabs).map(\.id), [list.id])
            XCTAssertTrue(store.visiblePlaceLists(scope: .friends).isEmpty)
            XCTAssertEqual(store.collaborators(for: list).map(\.id), [store.currentUser.id])
            XCTAssertEqual(store.collaborators(for: list).count, 1)
            XCTAssertEqual(store.collaboratorIndexBuildCount, 1)
            XCTAssertTrue(store.canAddPlaces(to: list))
            XCTAssertTrue(store.canLeave(list))
            XCTAssertFalse(store.canManage(list))
            XCTAssertFalse(store.removePlace(placeID: "place_circuit_coffee", from: list))

            let left = await store.leavePlaceList(list, backend: nil)
            XCTAssertTrue(left)
            XCTAssertFalse(store.canAddPlaces(to: list))
            XCTAssertTrue(store.collaborators(for: list).isEmpty)
            XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).isEmpty)
            XCTAssertEqual(store.visiblePlaceLists(scope: .friends).map(\.id), [list.id])
            XCTAssertEqual(store.collaboratorIndexBuildCount, 2)
        }
    }

    func testRestoredLegacyAndCurrentOwnersCanEditAndRemoveListPlaces() async throws {
        for legacy in [true, false] {
            let persistence = makeTemporaryPersistence()
            defer { try? FileManager.default.removeItem(at: persistence.directory) }
            let fixtures = makeListCompatibilityFixtures(legacy: legacy, owner: true)
            let firstStore = WanderStore(fixtures: fixtures, persistence: persistence.persistence)
            persistence.persistence.save(WanderStoreSnapshot(store: firstStore))
            firstStore.flushPersistence()
            let store = WanderStore(fixtures: .empty(), persistence: persistence.persistence)
            let list = try XCTUnwrap(store.placeLists.first)

            XCTAssertTrue(store.canManage(list))
            XCTAssertTrue(store.canAddPlaces(to: list))
            XCTAssertFalse(store.canLeave(list))
            XCTAssertEqual(store.visiblePlaceLists(scope: .collabs).map(\.id), [list.id])
            XCTAssertEqual(store.collaborators(for: list).map(\.id), ["user_ryan"])
            XCTAssertTrue(store.updatePlaceList(
                id: list.localID, name: "Updated list", description: "",
                visibility: .followers, collaboratorUserIDs: ["user_ryan"]
            ))
            XCTAssertTrue(store.removePlace(placeID: "place_circuit_coffee", from: list))
            let repository = FakePlaceListRepository(upsertResult: list.id)
            let syncedCount = await store.syncPendingPlaceLists(
                backend: WanderBackend(placeListRepository: repository)
            )
            XCTAssertEqual(syncedCount, 1)
            XCTAssertEqual(repository.collaboratorRequests.map(\.userIDs), [["user_ryan"]])
            XCTAssertEqual(repository.removedItems.map(\.itemID), ["22222222-2222-4222-8222-222222222222"])
            store.flushPersistence()

            let relaunched = WanderStore(fixtures: .empty(), persistence: persistence.persistence)
            let updatedList = try XCTUnwrap(relaunched.placeLists.first)
            XCTAssertEqual(updatedList.name, "Updated list")
            XCTAssertTrue(relaunched.visiblePlaces(in: updatedList).isEmpty)
            XCTAssertTrue(relaunched.canManage(updatedList))
        }
    }

    func testLegacyListReferenceRepairIsSelectiveAndPersistedOnlyOnce() throws {
        for legacy in [true, false] {
            let fixtures = makeListCompatibilityFixtures(legacy: legacy, owner: true, removedMember: true)
            let original = WanderStore(fixtures: fixtures)
            var snapshot = WanderStoreSnapshot(store: original)
            var writes = 0
            let persistence = WanderStorePersistence(
                load: { snapshot },
                save: { snapshot = $0; writes += 1 }
            )
            let restored = WanderStore(fixtures: .empty(), persistence: persistence)
            let list = try XCTUnwrap(restored.placeLists.first)
            var expectedMembers = original.placeListMembers
            var expectedItems = original.placeListItems
            expectedMembers[0].listID = list.id
            expectedItems[0].listID = list.id

            XCTAssertEqual(restored.placeLists, original.placeLists)
            XCTAssertEqual(restored.placeListMembers, expectedMembers)
            XCTAssertEqual(restored.placeListItems, expectedItems)
            XCTAssertEqual(writes, legacy ? 1 : 0)
            XCTAssertTrue(restored.collaborators(for: list).isEmpty)

            let relaunched = WanderStore(fixtures: .empty(), persistence: persistence)
            XCTAssertEqual(relaunched.placeListMembers, expectedMembers)
            XCTAssertEqual(relaunched.placeListItems, expectedItems)
            XCTAssertEqual(writes, legacy ? 1 : 0, "Already-current lists must not be rewritten")
        }
    }

    func testLegacyListAliasesDoNotRestoreFormerCollaboratorAccess() throws {
        let fixtures = makeListCompatibilityFixtures(legacy: true, owner: false, removedMember: true)
        let store = WanderStore(fixtures: fixtures)
        let list = try XCTUnwrap(store.placeLists.first)

        XCTAssertEqual(store.visiblePlaceLists(scope: .friends).map(\.id), [list.id])
        XCTAssertTrue(store.visiblePlaceLists(scope: .mine).isEmpty)
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).isEmpty)
        XCTAssertTrue(store.collaborators(for: list).isEmpty)
        XCTAssertFalse(store.canAddPlaces(to: list))
        XCTAssertFalse(store.canLeave(list))
        XCTAssertFalse(store.canManage(list))
        XCTAssertFalse(store.removePlace(placeID: "place_circuit_coffee", from: list))
        XCTAssertFalse(store.updatePlaceList(
            id: list.localID, name: "Unauthorized", description: "",
            visibility: .followers, collaboratorUserIDs: []
        ))
    }

    func testLegacyCollaboratorAliasesDeduplicateProfilesAndRespectBlocks() throws {
        let fixtures = makeListCompatibilityFixtures(legacy: true, owner: true, duplicateMember: true)
        let store = WanderStore(fixtures: fixtures)
        let list = try XCTUnwrap(store.placeLists.first)

        XCTAssertEqual(store.collaborators(for: list).map(\.id), ["user_ryan"])
        store.block(userID: "user_ryan")
        XCTAssertTrue(store.collaborators(for: list).isEmpty)
    }

    private func makeListCompatibilityFixtures(
        legacy: Bool,
        owner: Bool,
        removedMember: Bool = false,
        duplicateMember: Bool = false
    ) -> WanderFixtures {
        let seed = WanderFixtures.seed()
        let date = legacy ? Date(timeIntervalSince1970: 1_750_000_000) : Date.now
        let list = LocalPlaceList(
            localID: "local_compatibility_list",
            serverID: "11111111-1111-4111-8111-111111111111",
            ownerUserID: owner ? seed.currentUser.id : "user_ryan",
            name: "Compatibility list", description: "",
            syncState: .synced, createdAt: date, updatedAt: date
        )
        let member = LocalPlaceListMember(
            localID: "local_compatibility_member",
            listID: legacy ? list.localID : list.id,
            userID: owner ? "user_ryan" : seed.currentUser.id,
            role: .collaborator, createdAt: date,
            deletedAt: removedMember ? .now : nil
        )
        var members = [member]
        if duplicateMember {
            members.append(LocalPlaceListMember(
                localID: "remote_compatibility_member", listID: list.id,
                userID: member.userID, role: .collaborator, createdAt: date
            ))
        }
        return WanderFixtures(
            currentUser: seed.currentUser, profiles: seed.profiles,
            places: seed.places, userPlaces: seed.userPlaces,
            placeAttributes: seed.placeAttributes, follows: seed.follows, blocks: seed.blocks,
            placeLists: [list], placeListMembers: members,
            placeListItems: [LocalPlaceListItem(
                localID: "local_compatibility_item",
                serverID: "22222222-2222-4222-8222-222222222222",
                listID: legacy ? list.localID : list.id,
                placeID: "place_circuit_coffee", ownerUserPlaceID: "up_joe_circuit_coffee",
                addedByUserID: list.ownerUserID, syncState: .synced,
                createdAt: date, updatedAt: date
            )],
            contactProvider: seed.contactProvider
        )
    }

    func testListProjectionPrefersExactSocialSourceSaveOverEarlierCurrentUserSave() throws {
        let store = makeStore()
        let list = try XCTUnwrap(store.placeLists.first { $0.id == "list_demo_laptop" })
        let item = try XCTUnwrap(
            store.placeListItems.first { $0.id == "list_item_demo_laptop_circuit" }
        )
        let matchingCandidates = store.visiblePlaces().filter {
            $0.place.id == "place_circuit_coffee"
        }

        XCTAssertEqual(matchingCandidates.first?.userPlace.id, "up_joe_circuit_coffee")
        XCTAssertEqual(item.sourceUserPlaceID, "up_maya_circuit_coffee")

        let projectedPlace = try XCTUnwrap(
            store.visiblePlaces(in: list).first { $0.place.id == "place_circuit_coffee" }
        )

        XCTAssertEqual(projectedPlace.userPlace.id, item.sourceUserPlaceID)
        XCTAssertEqual(projectedPlace.owner.id, "user_maya")
        XCTAssertEqual(projectedPlace.userPlace.note, "Quiet enough for heads-down work.")
    }

    func testRemotePlaceListsHydrateVisibleScopesCountsAndItems() async {
        let store = makeStore()
        let listID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: LocalPlaceList(
                        localID: "remote_list_\(listID)",
                        serverID: listID,
                        ownerUserID: "user_ryan",
                        name: "Ryan remote tables",
                        description: "live list",
                        visibility: .followers,
                        syncState: .synced,
                        cachedItemCount: 1
                    ),
                    owner: ProfileShell(
                        id: "user_ryan",
                        handle: "ryan",
                        displayName: "Ryan",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [],
                    itemCount: 1
                )
            ],
            details: [
                listID: RemotePlaceListDetail(
                    list: LocalPlaceList(
                        localID: "remote_list_\(listID)",
                        serverID: listID,
                        ownerUserID: "user_ryan",
                        name: "Ryan remote tables",
                        description: "live list",
                        visibility: .followers,
                        syncState: .synced,
                        cachedItemCount: 1
                    ),
                    collaborators: [],
                    items: [
                        LocalPlaceListItem(
                            localID: "remote_list_item_1",
                            serverID: "22222222-2222-4222-8222-222222222222",
                            listID: listID,
                            placeID: "place_bar_nido",
                            sourceUserPlaceID: "up_ryan_bar_nido",
                            addedByUserID: "user_ryan",
                            syncState: .synced
                        )
                    ]
                )
            ]
        )
        let backend = WanderBackend(placeListRepository: repository)

        await store.refreshRemotePlaceLists(backend: backend)

        let remoteList = store.visiblePlaceLists(scope: .friends).first { $0.id == listID }
        XCTAssertEqual(remoteList?.cachedItemCount, 1)
        XCTAssertEqual(repository.detailListIDs, [listID])
        XCTAssertTrue(remoteList.map { store.visiblePlaces(in: $0).contains { $0.place.canonicalName == "Bar Nido" } } ?? false)
    }

    func testRemotePlaceListRefreshPersistsHydrationOnce() async {
        var saveCount = 0
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { _ in saveCount += 1 }
        )
        let store = WanderStore(fixtures: WanderFixtures.seed(), persistence: persistence)
        let listID = "11111111-1111-4111-8111-111111111111"
        let remoteList = LocalPlaceList(
            localID: "remote_list_\(listID)",
            serverID: listID,
            ownerUserID: "user_ryan",
            name: "Ryan remote tables",
            description: "live list",
            visibility: .followers,
            syncState: .synced,
            cachedItemCount: 0
        )
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: remoteList,
                    owner: ProfileShell(
                        id: "user_ryan",
                        handle: "ryan",
                        displayName: "Ryan",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [],
                    itemCount: 0
                )
            ],
            details: [
                listID: RemotePlaceListDetail(list: remoteList, collaborators: [], items: [])
            ]
        )
        let userPlaceRepository = FakeUserPlaceRepository(
            userPlacesByUserID: ["user_ryan": store.visiblePlaces(for: "user_ryan")]
        )
        let backend = WanderBackend(
            userPlaceRepository: userPlaceRepository,
            placeListRepository: repository
        )

        await store.refreshRemotePlaceLists(backend: backend)

        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(repository.visibleListRequestCount, 1)
        XCTAssertEqual(repository.detailListIDs, [listID])
        XCTAssertNil(store.lastRemoteError)
    }

    func testRemotePlaceListDetailRefreshDoesNotRequestAllListSummaries() async {
        let store = makeStore()
        let listID = "11111111-1111-4111-8111-111111111111"
        let remoteList = LocalPlaceList(
            localID: "remote_list_\(listID)",
            serverID: listID,
            ownerUserID: "user_ryan",
            name: "Ryan remote tables",
            description: "live list",
            visibility: .followers,
            syncState: .synced,
            cachedItemCount: 0
        )
        let repository = FakePlaceListRepository(
            details: [
                listID: RemotePlaceListDetail(list: remoteList, collaborators: [], items: [])
            ]
        )
        let backend = WanderBackend(
            userPlaceRepository: FakeUserPlaceRepository(),
            placeListRepository: repository
        )

        await store.refreshRemotePlaceList(remoteList, backend: backend)

        XCTAssertEqual(repository.visibleListRequestCount, 0)
        XCTAssertEqual(repository.detailListIDs, [listID])
    }

    func testRemotePlaceListRefreshKeepsSummariesWhenOneDetailFails() async {
        var saveCount = 0
        let persistence = WanderStorePersistence(
            load: { nil },
            save: { _ in saveCount += 1 }
        )
        let store = WanderStore(fixtures: WanderFixtures.seed(), persistence: persistence)
        let listID = "11111111-1111-4111-8111-111111111111"
        let remoteList = LocalPlaceList(
            localID: "remote_list_\(listID)",
            serverID: listID,
            ownerUserID: "user_ryan",
            name: "Ryan remote tables",
            description: "summary survives a detail error",
            visibility: .followers,
            syncState: .synced,
            cachedItemCount: 1
        )
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: remoteList,
                    owner: ProfileShell(
                        id: "user_ryan",
                        handle: "ryan",
                        displayName: "Ryan",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [],
                    itemCount: 1
                )
            ],
            failedDetailListIDs: [listID]
        )
        let backend = WanderBackend(placeListRepository: repository)

        await store.refreshRemotePlaceLists(backend: backend)

        XCTAssertEqual(store.visiblePlaceLists.first { $0.id == listID }?.name, remoteList.name)
        XCTAssertEqual(repository.detailListIDs, [listID])
        XCTAssertEqual(saveCount, 1)
        XCTAssertNotNil(store.lastRemoteError)
    }

    func testRemotePlaceListsPreserveKnownAvatarsWhenSummaryOmitsThem() async {
        let store = makeStore()
        let ryanAvatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_ryan/avatar.jpg?v=known"
        let mayaAvatarURL = "https://example.supabase.co/storage/v1/object/public/profile-avatars/user_maya/avatar.jpg?v=known"
        store.profiles.first { $0.id == "user_ryan" }?.avatarURL = ryanAvatarURL
        store.profiles.first { $0.id == "user_maya" }?.avatarURL = mayaAvatarURL
        let listID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: LocalPlaceList(
                        localID: "remote_list_\(listID)",
                        serverID: listID,
                        ownerUserID: "user_ryan",
                        name: "Ryan remote tables",
                        description: "live list",
                        visibility: .followers,
                        syncState: .synced,
                        cachedItemCount: 0
                    ),
                    owner: ProfileShell(
                        id: "user_ryan",
                        handle: "ryan",
                        displayName: "Ryan Updated",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [
                        PlaceListCollaboratorRecord(
                            userID: "user_maya",
                            handle: "maya",
                            displayName: "Maya Updated",
                            avatarURL: nil,
                            role: .collaborator
                        )
                    ],
                    itemCount: 0
                )
            ]
        )
        let backend = WanderBackend(placeListRepository: repository)

        await store.refreshRemotePlaceLists(backend: backend)

        XCTAssertEqual(store.profileState(for: "user_ryan")?.shell.displayName, "Ryan Updated")
        XCTAssertEqual(store.profileState(for: "user_ryan")?.shell.avatarURL, ryanAvatarURL)
        XCTAssertEqual(store.profileState(for: "user_maya")?.shell.displayName, "Maya Updated")
        XCTAssertEqual(store.profileState(for: "user_maya")?.shell.avatarURL, mayaAvatarURL)
    }

    func testRemotePlaceListRefreshRemovesListAfterCollaboratorLosesAccess() async {
        let store = makeStore()
        let listID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: LocalPlaceList(
                        localID: "remote_list_\(listID)",
                        serverID: listID,
                        ownerUserID: "user_ryan",
                        name: "Ryan remote tables",
                        description: "live list",
                        visibility: .followers,
                        syncState: .synced
                    ),
                    owner: ProfileShell(
                        id: "user_ryan",
                        handle: "ryan",
                        displayName: "Ryan",
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [
                        PlaceListCollaboratorRecord(
                            userID: store.currentUser.id,
                            handle: store.currentUser.handle,
                            displayName: store.currentUser.displayName,
                            avatarURL: nil,
                            role: .collaborator
                        )
                    ],
                    itemCount: 0
                )
            ]
        )
        let backend = WanderBackend(placeListRepository: repository)

        await store.refreshRemotePlaceLists(backend: backend)
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).contains { $0.id == listID })

        repository.setVisibleLists([])
        await store.refreshRemotePlaceLists(backend: backend)

        XCTAssertFalse(store.visiblePlaceLists.contains { $0.id == listID })
        XCTAssertFalse(store.visiblePlaceLists(scope: .mine).contains { $0.id == listID })
        XCTAssertFalse(store.visiblePlaceLists(scope: .collabs).contains { $0.id == listID })
    }

    func testRemotePlaceListRefreshPreservesFailedLocalCollaboratorRemoval() async {
        let joe = LocalProfile(localID: "local_joe", serverID: "user_joe", handle: "joe", displayName: "Joe", syncState: .synced)
        let ryan = LocalProfile(localID: "local_ryan", serverID: "user_ryan", handle: "ryan", displayName: "Ryan", syncState: .synced)
        let listID = "11111111-1111-4111-8111-111111111111"
        let list = LocalPlaceList(
            localID: "local_list_joe",
            serverID: listID,
            ownerUserID: joe.id,
            name: "Dinner",
            description: "local removal pending",
            visibility: .followers,
            syncState: .failed
        )
        let removedMembership = LocalPlaceListMember(
            localID: "local_member_ryan",
            listID: list.id,
            userID: ryan.id,
            role: .collaborator,
            deletedAt: .now
        )
        let store = WanderStore(
            fixtures: WanderFixtures(
                currentUser: joe,
                profiles: [joe, ryan],
                places: [],
                userPlaces: [],
                placeAttributes: [],
                follows: [],
                blocks: [],
                placeLists: [list],
                placeListMembers: [removedMembership],
                placeListItems: [],
                contactProvider: FakeContactProvider(seededMatches: [])
            )
        )
        let repository = FakePlaceListRepository(
            visibleLists: [
                RemotePlaceListSummary(
                    list: LocalPlaceList(
                        localID: "remote_list_\(listID)",
                        serverID: listID,
                        ownerUserID: joe.id,
                        name: "Dinner",
                        description: "old remote state",
                        visibility: .followers,
                        syncState: .synced
                    ),
                    owner: ProfileShell(
                        id: joe.id,
                        handle: joe.handle,
                        displayName: joe.displayName,
                        avatarURL: nil,
                        bio: nil,
                        relationship: .mutual
                    ),
                    collaborators: [
                        PlaceListCollaboratorRecord(
                            userID: ryan.id,
                            handle: ryan.handle,
                            displayName: ryan.displayName,
                            avatarURL: nil,
                            role: .collaborator
                        )
                    ],
                    itemCount: 0
                )
            ]
        )
        let backend = WanderBackend(placeListRepository: repository)

        await store.refreshRemotePlaceLists(backend: backend)

        XCTAssertEqual(store.placeLists.first?.syncState, .failed)
        XCTAssertTrue(store.collaborators(for: list).isEmpty)
        XCTAssertNotNil(store.placeListMembers.first?.deletedAt)
    }

    func testSnapshotListAnalyticsContainsOnlyCoarseProperties() throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: .seed(), analytics: analytics)
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.jpegData(compressionQuality: 0.8)!
        let own = store.currentUserVisiblePlaces
        let list = try XCTUnwrap(store.createMapSnapshotList(placeIDs: own.map { $0.place.id }, coverData: data))
        let created = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListCreated }
        let added = analytics.events.filter { $0.name == WanderAnalyticsEvents.placeListItemAdded }
        XCTAssertEqual(created.count, 1)
        XCTAssertEqual(added.count, store.visiblePlaces(in: list).count)
        for event in added {
            XCTAssertEqual(event.properties, ["surface": "map_snapshot", "list_role": "owner", "companion_save": "none"])
        }
        let normalized = analytics.events.filter { $0.name == "engagement_action_performed" && $0.properties["surface"] == "map_snapshot" }
        XCTAssertEqual(normalized.count, added.count)
    }

    func testSnapshotCoverFailureKeepsLocalCoverAndRetriesWithoutNewList() async throws {
        let store = makeStore()
        let data = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.jpegData(compressionQuality: 0.8)!
        let created = try XCTUnwrap(store.createMapSnapshotList(
            placeIDs: store.currentUserVisiblePlaces.map { $0.place.id }, coverData: data
        ))
        let repository = FakePlaceListRepository()
        repository.failSnapshotUpload = true
        let backend = WanderBackend(placeListRepository: repository)
        _ = await store.syncPendingPlaceLists(backend: backend)
        let failed = try XCTUnwrap(store.placeLists.first { $0.localID == created.localID })
        XCTAssertEqual(failed.syncState, .failed)
        XCTAssertEqual(failed.snapshotCoverData, data)
        XCTAssertNil(failed.snapshotCoverPath)
        repository.failSnapshotUpload = false
        _ = await store.syncPendingPlaceLists(backend: backend)
        let synced = try XCTUnwrap(store.placeLists.first { $0.localID == created.localID })
        XCTAssertEqual(synced.syncState, .synced)
        XCTAssertEqual(synced.snapshotCoverPath, "\(synced.id)/snapshot.jpg")
        XCTAssertEqual(synced.snapshotCoverData, data)
        XCTAssertEqual(repository.snapshotUploadCount, 2)
        XCTAssertEqual(repository.upsertedDrafts.last?.id, synced.serverID)
        XCTAssertEqual(store.placeLists.filter { $0.localID == created.localID }.count, 1)
    }

    func testSyncPendingPlaceListsCreatesRemoteListAndCollaborators() async {
        let store = makeStore()
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(upsertResult: remoteListID)
        let backend = WanderBackend(placeListRepository: repository)
        let created = store.createPlaceList(
            name: "LA patios",
            description: "sunny tables",
            visibility: .followers,
            collaboratorUserIDs: ["user_ryan"]
        )!

        let syncedCount = await store.syncPendingPlaceLists(backend: backend)

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["LA patios"])
        XCTAssertEqual(repository.collaboratorRequests, [FakePlaceListRepository.CollaboratorRequest(listID: remoteListID, userIDs: ["user_ryan"])])
        XCTAssertEqual(store.placeLists.first { $0.localID == created.localID }?.serverID, remoteListID)
        XCTAssertEqual(store.placeLists.first { $0.localID == created.localID }?.syncState, .synced)
    }

    func testSyncPendingPlaceListsCoalescesConcurrentCalls() async {
        let store = makeStore()
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(upsertResult: remoteListID, upsertDelayNanoseconds: 100_000_000)
        let backend = WanderBackend(placeListRepository: repository)
        _ = store.createPlaceList(name: "One remote list", description: "single flight", visibility: .followers)

        let first = Task { await store.syncPendingPlaceLists(backend: backend) }
        let second = Task { await store.syncPendingPlaceLists(backend: backend) }
        let results = await [first.value, second.value]

        XCTAssertEqual(results, [1, 1])
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["One remote list"])
    }

    func testSyncPendingPlaceListsDrainsListCreatedDuringBatch() async {
        let store = makeStore()
        let repository = FakePlaceListRepository(
            upsertResults: [
                "11111111-1111-4111-8111-111111111111",
                "22222222-2222-4222-8222-222222222222"
            ],
            upsertDelayNanoseconds: 100_000_000
        )
        let backend = WanderBackend(placeListRepository: repository)
        _ = store.createPlaceList(name: "First list", description: "starts batch", visibility: .followers)

        let batch = Task { await store.syncPendingPlaceLists(backend: backend) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        _ = store.createPlaceList(name: "Second list", description: "created mid batch", visibility: .followers)
        let syncedCount = await batch.value

        XCTAssertEqual(syncedCount, 2)
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["First list", "Second list"])
        XCTAssertTrue(
            store.placeLists
                .filter { $0.name == "First list" || $0.name == "Second list" }
                .allSatisfy { $0.syncState == .synced }
        )
    }

    func testSyncPendingPlaceListsResendsOwnerEditMadeInFlight() async {
        let store = makeStore()
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(upsertResult: remoteListID, upsertDelayNanoseconds: 100_000_000)
        let backend = WanderBackend(placeListRepository: repository)
        let list = store.createPlaceList(name: "Original name", description: "before request", visibility: .followers)!

        let sync = Task { await store.syncPendingPlaceLists(backend: backend) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(
            store.updatePlaceList(
                id: list.id,
                name: "Updated name",
                description: "changed in flight",
                visibility: .followers,
                collaboratorUserIDs: []
            )
        )
        _ = await sync.value

        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["Original name", "Updated name"])
        XCTAssertEqual(store.placeLists.first { $0.localID == list.localID }?.syncState, .synced)
    }

    func testDirectListItemAddAndBatchSyncShareOneRemoteListCreate() async {
        let store = makeStore()
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(upsertResult: remoteListID, upsertDelayNanoseconds: 100_000_000)
        let backend = WanderBackend(placeListRepository: repository)
        let list = store.createPlaceList(name: "One direct list", description: "single flight", visibility: .followers)!
        let place = store.currentUserVisiblePlaces.first!

        let add = Task { await store.addVisiblePlace(place, to: list, backend: backend) }
        let batch = Task { await store.syncPendingPlaceLists(backend: backend) }
        let addResult = await add.value
        _ = await batch.value

        XCTAssertEqual(addResult.outcome, .added)
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["One direct list"])
    }

    func testSignInClaimsGuestListAndItemBeforeBackfill() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        let guestUserID = store.currentUser.id
        let list = store.createPlaceList(name: "Guest coffee", description: "saved before sign in", visibility: .followers)!
        let candidate = PlaceCandidate(
            id: "guest_coffee",
            name: "Guest Coffee",
            category: "Coffee Shop",
            latitude: 34.05,
            longitude: -118.24,
            sourceProviderPlaceID: "guest_coffee",
            confidence: 0.9
        )
        _ = await store.addCandidate(candidate, to: list, backend: nil)
        XCTAssertTrue(store.placeListItems.contains { $0.addedByUserID == guestUserID })

        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))

        let claimedList = store.placeLists.first { $0.localID == list.localID }
        XCTAssertEqual(claimedList?.ownerUserID, "user_live")
        XCTAssertTrue(store.placeListItems.allSatisfy { $0.addedByUserID != guestUserID })
        XCTAssertTrue(store.placeListItems.contains { $0.addedByUserID == "user_live" })

        let repository = FakePlaceListRepository(upsertResult: "11111111-1111-4111-8111-111111111111")
        let backend = WanderBackend(placeListRepository: repository)
        let syncedCount = await store.syncPendingPlaceLists(backend: backend)

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["Guest coffee"])
    }

    func testSyncPendingPlaceListsBackfillsPersistentLegacyLocalList() async {
        let fixture = makeTemporaryPersistence()
        let joe = LocalProfile(localID: "local_joe", serverID: "user_joe", handle: "joe", displayName: "Joe", syncState: .synced)
        let ryan = LocalProfile(localID: "local_ryan", serverID: "user_ryan", handle: "ryan", displayName: "Ryan", syncState: .synced)
        let legacyList = LocalPlaceList(
            localID: "local_list_la_coffeee",
            ownerUserID: joe.id,
            name: "LA Coffeee",
            description: "coffee spots",
            visibility: .followers,
            syncState: .localOnly
        )
        let collaborator = LocalPlaceListMember(
            localID: "local_member_la_coffeee_ryan",
            listID: legacyList.id,
            userID: ryan.id,
            role: .collaborator
        )
        let store = WanderStore(
            fixtures: WanderFixtures(
                currentUser: joe,
                profiles: [joe, ryan],
                places: [],
                userPlaces: [],
                placeAttributes: [],
                follows: [],
                blocks: [],
                placeLists: [legacyList],
                placeListMembers: [collaborator],
                placeListItems: [],
                contactProvider: FakeContactProvider(seededMatches: [])
            ),
            persistence: fixture.persistence
        )
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let repository = FakePlaceListRepository(upsertResult: remoteListID)
        let backend = WanderBackend(placeListRepository: repository)

        let syncedCount = await store.syncPendingPlaceLists(backend: backend)

        XCTAssertEqual(syncedCount, 1)
        XCTAssertEqual(repository.upsertedDrafts.map(\.name), ["LA Coffeee"])
        XCTAssertNil(repository.upsertedDrafts.first?.id)
        XCTAssertEqual(repository.collaboratorRequests, [FakePlaceListRepository.CollaboratorRequest(listID: remoteListID, userIDs: ["user_ryan"])])
        XCTAssertEqual(store.placeLists.first { $0.localID == legacyList.localID }?.serverID, remoteListID)
        XCTAssertEqual(store.placeLists.first { $0.localID == legacyList.localID }?.syncState, .synced)
    }

    func testSyncPendingPlaceListsDoesNotBackfillNonPersistentDemoLists() async {
        let store = makeStore()
        let repository = FakePlaceListRepository()
        let backend = WanderBackend(placeListRepository: repository)

        let syncedCount = await store.syncPendingPlaceLists(backend: backend)

        XCTAssertEqual(syncedCount, 0)
        XCTAssertTrue(repository.upsertedDrafts.isEmpty)
        XCTAssertTrue(repository.collaboratorRequests.isEmpty)
    }

    func testCollaboratorCanAddPlaceToSharedList() async {
        let joe = LocalProfile(localID: "local_joe", serverID: "user_joe", handle: "joe", displayName: "Joe", syncState: .synced)
        let ryan = LocalProfile(localID: "local_ryan", serverID: "user_ryan", handle: "ryan", displayName: "Ryan", syncState: .synced)
        let placeID = "33333333-3333-4333-8333-333333333333"
        let userPlaceID = "44444444-4444-4444-8444-444444444444"
        let listID = "55555555-5555-4555-8555-555555555555"
        let place = LocalPlace(
            localID: "local_place_tsubaki",
            serverID: placeID,
            canonicalName: "Tsubaki",
            category: "restaurant",
            latitude: 34.077,
            longitude: -118.261,
            syncState: .synced
        )
        let userPlace = LocalUserPlace(
            localID: "local_up_tsubaki",
            serverID: userPlaceID,
            userID: joe.id,
            placeID: place.id,
            status: .wannaGo,
            visibility: .followers,
            sourceType: "manual",
            syncState: .synced
        )
        let sharedList = LocalPlaceList(
            localID: "local_list_ryan_dinner",
            serverID: listID,
            ownerUserID: ryan.id,
            name: "Ryan dinner",
            description: "shared ideas",
            visibility: .followers,
            syncState: .synced
        )
        let membership = LocalPlaceListMember(
            localID: "local_member_ryan_dinner_joe",
            listID: sharedList.id,
            userID: joe.id,
            role: .collaborator
        )
        let store = WanderStore(
            fixtures: WanderFixtures(
                currentUser: joe,
                profiles: [joe, ryan],
                places: [place],
                userPlaces: [userPlace],
                placeAttributes: [],
                follows: [],
                blocks: [],
                placeLists: [sharedList],
                placeListMembers: [membership],
                placeListItems: [],
                contactProvider: FakeContactProvider(seededMatches: [])
            )
        )
        let repository = FakePlaceListRepository(itemResult: "66666666-6666-4666-8666-666666666666")
        let backend = WanderBackend(placeListRepository: repository)

        let result = await store.addVisiblePlace(store.currentUserVisiblePlaces[0], to: sharedList, backend: backend)

        XCTAssertEqual(result.outcome, .added)
        XCTAssertTrue(store.canAddPlaces(to: sharedList))
        XCTAssertFalse(store.canManage(sharedList))
        XCTAssertEqual(repository.itemRequests.map(\.draft.listID), [listID])
        XCTAssertEqual(repository.itemRequests.map(\.draft.placeID), [placeID])
        XCTAssertEqual(repository.itemRequests.map(\.draft.ownerUserPlaceID), [userPlaceID])
        XCTAssertEqual(store.visiblePlaceLists(scope: .collabs).first?.cachedItemCount, 1)
    }

    func testAddingUnsavedCandidateToListCreatesWantSaveAndListItem() async {
        let store = makeStore()
        let remoteListID = "11111111-1111-4111-8111-111111111111"
        let remotePlaceID = "22222222-2222-4222-8222-222222222222"
        let remoteUserPlaceID = "33333333-3333-4333-8333-333333333333"
        let remoteItemID = "44444444-4444-4444-8444-444444444444"
        let userPlaceRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: remoteUserPlaceID, syncState: .synced, placeID: remotePlaceID)
        )
        let placeListRepository = FakePlaceListRepository(upsertResult: remoteListID, itemResult: remoteItemID)
        let backend = WanderBackend(userPlaceRepository: userPlaceRepository, placeListRepository: placeListRepository)
        let list = store.createPlaceList(name: "New coffee", description: "work blocks", visibility: .followers)!
        let candidate = PlaceCandidate(
            id: "map_blue_bottle",
            name: "Blue Bottle Coffee",
            category: "Coffee Shop",
            latitude: 34.051,
            longitude: -118.245,
            sourceProviderPlaceID: "mapkit_blue_bottle",
            confidence: 0.93
        )

        let result = await store.addCandidate(candidate, to: list, backend: backend)

        XCTAssertEqual(result.outcome, .added)
        XCTAssertTrue(result.createdWantSave)
        XCTAssertEqual(userPlaceRepository.savedDrafts.map(\.status), [.wannaGo])
        XCTAssertEqual(userPlaceRepository.savedDrafts.map(\.place.canonicalName), ["Blue Bottle Coffee"])
        XCTAssertEqual(placeListRepository.itemRequests.map(\.draft.listID), [remoteListID])
        XCTAssertEqual(placeListRepository.itemRequests.map(\.draft.placeID), [remotePlaceID])
        XCTAssertEqual(placeListRepository.itemRequests.map(\.draft.ownerUserPlaceID), [remoteUserPlaceID])
        XCTAssertEqual(placeListRepository.itemRequests.map(\.draft.sourceUserPlaceID), [remoteUserPlaceID])
        XCTAssertEqual(store.visiblePlaceLists(scope: .mine).first { $0.serverID == remoteListID }?.cachedItemCount, 1)
    }
}

@MainActor
private final class FakeFeedRepository: FeedRepository {
    private var responses: [Result<FollowedFeedPage, Error>]
    private var isSuspended: Bool
    private(set) var requestCount = 0

    init(
        responses: [Result<FollowedFeedPage, Error>],
        isSuspended: Bool = false
    ) {
        self.responses = responses
        self.isSuspended = isSuspended
    }

    func followedFeed(before: String?, limit: Int) async throws -> FollowedFeedPage {
        requestCount += 1
        while isSuspended {
            await Task.yield()
        }
        guard !responses.isEmpty else { throw TestError.expected }
        return try responses.removeFirst().get()
    }

    func finish() {
        isSuspended = false
    }
}

@MainActor
private final class FakeProfileRepository: ProfileRepository {
    private let shells: [ProfileShell]
    private let profileStates: [String: ProfileViewState]
    private let currentProfileResult: LocalProfile?
    private let updateError: Error?
    private let updatedProfileResult: LocalProfile?
    private var recommendationResponses: [[DiscoverPeopleRecommendation]]
    private let recommendationError: Error?
    private var currentProfileIsSuspended: Bool
    private(set) var queries: [String] = []
    private(set) var profileIDs: [String] = []
    private(set) var recommendationLimits: [Int] = []
    private(set) var currentProfileRequestCount = 0

    init(
        shells: [ProfileShell] = [],
        profileStates: [String: ProfileViewState] = [:],
        currentProfile: LocalProfile? = nil,
        updateError: Error? = nil,
        updatedProfile: LocalProfile? = nil,
        recommendations: [DiscoverPeopleRecommendation] = [],
        recommendationResponses: [[DiscoverPeopleRecommendation]]? = nil,
        recommendationError: Error? = nil,
        suspendCurrentProfile: Bool = false
    ) {
        self.shells = shells
        self.profileStates = profileStates
        self.currentProfileResult = currentProfile
        self.updateError = updateError
        self.updatedProfileResult = updatedProfile
        self.recommendationResponses = recommendationResponses ?? [recommendations]
        self.recommendationError = recommendationError
        self.currentProfileIsSuspended = suspendCurrentProfile
    }

    func currentProfile() async throws -> LocalProfile? {
        currentProfileRequestCount += 1
        while currentProfileIsSuspended {
            await Task.yield()
        }
        return currentProfileResult
    }

    func resumeCurrentProfile() {
        currentProfileIsSuspended = false
    }

    func updateCurrentProfile(_ update: ProfileDetailsUpdate) async throws -> LocalProfile {
        if let updateError {
            throw updateError
        }
        guard let updatedProfileResult else {
            throw WanderRemoteError.notImplemented("fake profile update")
        }
        return updatedProfileResult
    }

    func profile(id: String) async throws -> ProfileViewState {
        profileIDs.append(id)
        guard let state = profileStates[id] else {
            throw WanderRemoteError.notImplemented("fake profile")
        }
        return state
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        queries.append(handleQuery)
        return shells
    }

    func discoverProfileRecommendations(limit: Int) async throws -> [DiscoverPeopleRecommendation] {
        recommendationLimits.append(limit)
        if let recommendationError {
            throw recommendationError
        }
        guard !recommendationResponses.isEmpty else { return [] }
        if recommendationResponses.count == 1 {
            return recommendationResponses[0]
        }
        return recommendationResponses.removeFirst()
    }
}

@MainActor
private final class FakeFollowRepository: FollowRepository {
    private let error: Error?
    private let followersResult: [ProfileShell]
    private let followingResult: [ProfileShell]
    private let relationships: [String: ViewerRelationship]
    private(set) var followedUserIDs: [String] = []
    private(set) var unfollowedUserIDs: [String] = []
    private(set) var followersUserIDs: [String] = []
    private(set) var followingUserIDs: [String] = []
    private(set) var relationshipUserIDs: [String] = []
    var shouldSuspendFollowing = false
    private var followingContinuation: CheckedContinuation<[ProfileShell], Error>?

    var hasSuspendedFollowingRequest: Bool { followingContinuation != nil }

    init(
        error: Error? = nil,
        followers: [ProfileShell] = [],
        following: [ProfileShell] = [],
        relationships: [String: ViewerRelationship] = [:]
    ) {
        self.error = error
        self.followersResult = followers
        self.followingResult = following
        self.relationships = relationships
    }

    func follow(userID: String) async throws {
        followedUserIDs.append(userID)
        if let error {
            throw error
        }
    }

    func unfollow(userID: String) async throws {
        unfollowedUserIDs.append(userID)
        if let error {
            throw error
        }
    }

    func followers(userID: String) async throws -> [ProfileShell] {
        followersUserIDs.append(userID)
        return followersResult
    }

    func following(userID: String) async throws -> [ProfileShell] {
        followingUserIDs.append(userID)
        if shouldSuspendFollowing {
            return try await withCheckedThrowingContinuation { continuation in
                followingContinuation = continuation
            }
        }
        return followingResult
    }

    func relationship(to userID: String) async throws -> ViewerRelationship {
        relationshipUserIDs.append(userID)
        return relationships[userID] ?? .nonFollower
    }

    func resumeFollowing() {
        followingContinuation?.resume(returning: followingResult)
        followingContinuation = nil
    }
}

@MainActor
private final class FakeBlockRepository: BlockRepository {
    private let error: Error?
    private(set) var blockedUserIDs: [String] = []
    private(set) var unblockedUserIDs: [String] = []

    init(error: Error? = nil) {
        self.error = error
    }

    func block(userID: String) async throws {
        blockedUserIDs.append(userID)
        if let error {
            throw error
        }
    }

    func unblock(userID: String) async throws {
        unblockedUserIDs.append(userID)
        if let error {
            throw error
        }
    }

    func blockedProfiles() async throws -> [ProfileShell] {
        []
    }

    func isBlocked(userID: String) async throws -> Bool {
        false
    }
}

@MainActor
private final class FakeSocialPlaceSaveRepository: SocialPlaceSaveRepository {
    struct Request: Equatable {
        let placeID: String
        let sourceUserPlaceID: String
    }

    private let result: SaveResult
    private(set) var requests: [Request] = []

    init(result: SaveResult) {
        self.result = result
    }

    func saveVisiblePlace(placeID: String, sourceUserPlaceID: String) async throws -> SaveResult {
        requests.append(Request(placeID: placeID, sourceUserPlaceID: sourceUserPlaceID))
        return result
    }
}

@MainActor
private final class FakePlaceRepository: PlaceRepository {
    private var placesResult: [VisiblePlace]
    private var featuredPlacesResult: [VisiblePlace]
    private(set) var viewports: [MapViewport] = []
    private(set) var featuredViewports: [MapViewport] = []

    init(places: [VisiblePlace], featuredPlaces: [VisiblePlace]? = nil) {
        self.placesResult = places
        self.featuredPlacesResult = featuredPlaces ?? places
    }

    func setPlaces(_ places: [VisiblePlace]) {
        placesResult = places
    }

    func places(in viewport: MapViewport) async throws -> [VisiblePlace] {
        viewports.append(viewport)
        return placesResult
    }

    func featuredPlaces(in viewport: MapViewport) async throws -> [VisiblePlace] {
        featuredViewports.append(viewport)
        return featuredPlacesResult
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        []
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        []
    }
}

@MainActor
private final class FakePlacePhotoRepository: PlacePhotoRepository {
    let resolvedPhoto: PlacePhoto
    private(set) var requests: [PlacePhotoRequest] = []

    init(photo: PlacePhoto) {
        resolvedPhoto = photo
    }

    func photo(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        requests.append(request)
        return resolvedPhoto
    }

    func visibleUserPhoto(for request: PlacePhotoRequest) async throws -> PlacePhoto {
        throw WanderRemoteError.invalidResponse("No fallback photo")
    }

    func imageData(for photo: PlacePhoto) async throws -> Data {
        Data()
    }
}

@MainActor
private final class FakeUserPlaceRepository: UserPlaceRepository, CheckInRepository {
    struct UserPlaceRequest: Equatable {
        let userID: String
        let filters: PlaceFilters
    }

    private let result: SaveResult?
    private let error: Error?
    private let userPlacesByUserID: [String: [VisiblePlace]]
    private(set) var savedDrafts: [UserPlaceDraft] = []
    private(set) var savedCheckInDrafts: [CheckInSaveDraft] = []
    private(set) var userPlaceRequests: [UserPlaceRequest] = []
    private(set) var deletedUserPlaceIDs: [String] = []
    private(set) var deletedCheckInIDs: [String] = []

    init(result: SaveResult? = nil, error: Error? = nil, userPlacesByUserID: [String: [VisiblePlace]] = [:]) {
        self.result = result
        self.error = error
        self.userPlacesByUserID = userPlacesByUserID
    }

    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] {
        userPlaceRequests.append(UserPlaceRequest(userID: userID, filters: filters))
        if let error {
            throw error
        }
        return userPlacesByUserID[userID] ?? []
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        savedDrafts.append(draft)
        if let error {
            throw error
        }
        return result ?? SaveResult(userPlaceID: "up_fake", syncState: .synced, placeID: "place_fake")
    }

    func saveCheckIn(_ draft: CheckInSaveDraft) async throws -> CheckInSaveResult {
        savedCheckInDrafts.append(draft)
        let saveResult = try await save(draft.userPlace)
        return CheckInSaveResult(
            saveResult: saveResult,
            visitResult: PlaceVisitResult(
                visitID: draft.visit.id ?? UUID().uuidString,
                userPlaceID: saveResult.userPlaceID,
                visitedAt: draft.visit.visitedAt,
                note: draft.visit.note,
                ratingScore: draft.visit.ratingScore,
                tags: VisitAttributeAnswers.tags(
                    fromAttributeAnswersJSON: draft.visit.attributeAnswersJSON
                ),
                backfilledFromUserPlace: false
            )
        )
    }

    func deleteCheckIn(visitID: String) async throws -> CheckInDeleteResult {
        deletedCheckInIDs.append(visitID)
        if let error {
            throw error
        }
        return CheckInDeleteResult(
            visitID: visitID,
            userPlaceID: result?.userPlaceID,
            transition: .checkedIn
        )
    }

    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}

    func delete(userPlaceID: String) async throws {
        deletedUserPlaceIDs.append(userPlaceID)
        if let error {
            throw error
        }
    }
}

@MainActor
private final class DeferredWannaGoPlanRepository: UserPlaceRepository {
    private var plansContinuation: CheckedContinuation<[OwnWannaGoPlan], Error>?
    private(set) var didRequestPlans = false

    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] {
        []
    }

    func ownWannaGoPlans() async throws -> [OwnWannaGoPlan] {
        didRequestPlans = true
        return try await withCheckedThrowingContinuation { continuation in
            plansContinuation = continuation
        }
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        throw WanderRemoteError.notImplemented("deferred Wanna plan fake")
    }

    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}

    func delete(userPlaceID: String) async throws {}

    func finish(with plans: [OwnWannaGoPlan]) {
        plansContinuation?.resume(returning: plans)
        plansContinuation = nil
    }
}

@MainActor
private final class DeferredCalendarUserPlaceRepository: UserPlaceRepository {
    private let result: [VisiblePlace]
    private var isSuspended = true
    private(set) var userPlaceRequests: [String] = []

    init(result: [VisiblePlace]) {
        self.result = result
    }

    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] {
        userPlaceRequests.append(userID)
        while isSuspended {
            await Task.yield()
        }
        return result
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        throw WanderRemoteError.notImplemented("deferred calendar fake")
    }

    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}

    func delete(userPlaceID: String) async throws {}

    func finish() {
        isSuspended = false
    }
}

@MainActor
private final class FakeVisitRepository: VisitRepository {
    struct Upload: Equatable {
        let bucket: String
        let path: String
        let data: Data
        let contentType: String
    }

    private let visitsByUserPlaceID: [String: [PlaceVisitResult]]
    private let photosByVisitID: [String: [VisitPhotoResult]]
    private let error: Error?
    private let failingUserPlaceIDs: Set<String>
    private var suspendedUserPlaceIDs: Set<String>
    private var failingPhotoMetadataCallNumbers: Set<Int>
    private var isPhotoMetadataSuspended: Bool
    private(set) var visitRequests: [String] = []
    private(set) var upsertedVisitDrafts: [PlaceVisitDraft] = []
    private(set) var deletedVisitIDs: [String] = []
    private(set) var photoRequests: [String] = []
    private(set) var upsertedPhotoDrafts: [VisitPhotoDraft] = []
    private(set) var uploads: [Upload] = []
    private(set) var deletedPhotos: [(photoID: String, bucket: String, path: String)] = []
    private(set) var photoEvents: [String] = []

    init(
        visitsByUserPlaceID: [String: [PlaceVisitResult]] = [:],
        photosByVisitID: [String: [VisitPhotoResult]] = [:],
        error: Error? = nil,
        failingUserPlaceIDs: Set<String> = [],
        suspendedUserPlaceIDs: Set<String> = [],
        failingPhotoMetadataCallNumbers: Set<Int> = [],
        isPhotoMetadataSuspended: Bool = false
    ) {
        self.visitsByUserPlaceID = visitsByUserPlaceID
        self.photosByVisitID = photosByVisitID
        self.error = error
        self.failingUserPlaceIDs = failingUserPlaceIDs
        self.suspendedUserPlaceIDs = suspendedUserPlaceIDs
        self.failingPhotoMetadataCallNumbers = failingPhotoMetadataCallNumbers
        self.isPhotoMetadataSuspended = isPhotoMetadataSuspended
    }

    func visits(for userPlaceID: String) async throws -> [PlaceVisitResult] {
        visitRequests.append(userPlaceID)
        while suspendedUserPlaceIDs.contains(userPlaceID) {
            await Task.yield()
        }
        if failingUserPlaceIDs.contains(userPlaceID) {
            throw error ?? TestError.expected
        }
        if let error {
            throw error
        }
        return visitsByUserPlaceID[userPlaceID] ?? []
    }

    func finishVisits(for userPlaceID: String) {
        suspendedUserPlaceIDs.remove(userPlaceID)
    }

    func upsertVisit(_ draft: PlaceVisitDraft) async throws -> PlaceVisitResult {
        upsertedVisitDrafts.append(draft)
        if let error {
            throw error
        }
        return PlaceVisitResult(
            visitID: draft.id ?? "visit_remote_\(upsertedVisitDrafts.count)",
            userPlaceID: draft.userPlaceID,
            visitedAt: draft.visitedAt,
            note: draft.note,
            ratingScore: draft.ratingScore,
            tags: VisitAttributeAnswers.tags(fromAttributeAnswersJSON: draft.attributeAnswersJSON),
            backfilledFromUserPlace: draft.backfilledFromUserPlace
        )
    }

    func deleteVisit(visitID: String) async throws {
        deletedVisitIDs.append(visitID)
        if let error {
            throw error
        }
    }

    func photos(for visitID: String) async throws -> [VisitPhotoResult] {
        photoRequests.append(visitID)
        if let error {
            throw error
        }
        return photosByVisitID[visitID] ?? []
    }

    func upsertPhotoMetadata(_ draft: VisitPhotoDraft) async throws -> VisitPhotoResult {
        upsertedPhotoDrafts.append(draft)
        photoEvents.append("metadata:\(draft.uploadState.rawValue)")
        let callNumber = upsertedPhotoDrafts.count
        while isPhotoMetadataSuspended {
            await Task.yield()
        }
        if failingPhotoMetadataCallNumbers.contains(callNumber) {
            throw error ?? TestError.expected
        }
        if let error {
            throw error
        }
        return VisitPhotoResult(
            photoID: draft.id ?? "photo_remote_\(upsertedPhotoDrafts.count)",
            visitID: draft.visitID,
            storageBucket: draft.storageBucket,
            storagePath: draft.storagePath,
            remoteURLString: draft.remoteURLString,
            contentType: draft.contentType,
            byteSize: draft.byteSize,
            width: draft.width,
            height: draft.height,
            capturedAt: draft.capturedAt,
            sortOrder: draft.sortOrder,
            uploadState: draft.uploadState
        )
    }

    func clearPhotoMetadataFailures() {
        failingPhotoMetadataCallNumbers = []
    }

    func finishPhotoMetadata() {
        isPhotoMetadataSuspended = false
    }

    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws -> URL {
        photoEvents.append("upload")
        uploads.append(Upload(bucket: bucket, path: path, data: data, contentType: contentType))
        if let error {
            throw error
        }
        return URL(string: "https://example.supabase.co/storage/v1/object/public/\(bucket)/\(path)?v=test")!
    }

    func deletePhoto(photoID: String, bucket: String, path: String) async throws {
        deletedPhotos.append((photoID: photoID, bucket: bucket, path: path))
        if let error {
            throw error
        }
    }
}

@MainActor
private final class FakeSharedVisitRepository: SharedVisitRepository {
    struct InviteRequest: Equatable {
        let sourceVisitID: String
        let inviteeUserIDs: [String]
    }

    struct DeclineRequest: Equatable {
        let participantID: String
        let generation: Int
    }

    private(set) var inviteRequests: [InviteRequest] = []
    private(set) var inviteeListRequests: [String] = []
    private(set) var setRequests: [InviteRequest] = []
    private(set) var declineRequests: [DeclineRequest] = []
    var activeInviteeUserIDs: [String] = []
    var inboxInvitations: [SharedVisitInvitation] = []
    var shouldSuspendInbox = false
    private var inboxContinuation: CheckedContinuation<[SharedVisitInvitation], Error>?

    var hasSuspendedInboxRequest: Bool { inboxContinuation != nil }

    func createInvites(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        inviteRequests.append(InviteRequest(sourceVisitID: sourceVisitID, inviteeUserIDs: inviteeUserIDs))
        return inviteeUserIDs.map {
            SharedVisitInviteResult(
                participantID: UUID().uuidString.lowercased(),
                inviteeUserID: $0,
                status: .pending,
                invitationGeneration: 1
            )
        }
    }

    func inviteeUserIDs(sourceVisitID: String) async throws -> [String] {
        inviteeListRequests.append(sourceVisitID)
        return activeInviteeUserIDs
    }

    func setInvitees(sourceVisitID: String, inviteeUserIDs: [String]) async throws -> [SharedVisitInviteResult] {
        setRequests.append(InviteRequest(sourceVisitID: sourceVisitID, inviteeUserIDs: inviteeUserIDs))
        activeInviteeUserIDs = inviteeUserIDs
        return inviteeUserIDs.map {
            SharedVisitInviteResult(
                participantID: UUID().uuidString.lowercased(),
                inviteeUserID: $0,
                status: .pending,
                invitationGeneration: 1
            )
        }
    }

    func inbox(before: Date?, limit: Int) async throws -> [SharedVisitInvitation] {
        guard shouldSuspendInbox else { return inboxInvitations }
        return try await withCheckedThrowingContinuation { continuation in
            inboxContinuation = continuation
        }
    }

    func resumeInbox() {
        inboxContinuation?.resume(returning: [])
        inboxContinuation = nil
    }
    func context(participantID: String, generation: Int) async throws -> SharedVisitInvitation? { nil }
    func resolveDestination(participantID: String, generation: Int) async throws -> SharedVisitDestination? { nil }
    func accept(_ draft: SharedVisitAcceptanceDraft) async throws -> SharedVisitAcceptanceResult {
        throw WanderRemoteError.notImplemented("fake shared visit acceptance")
    }
    func decline(participantID: String, generation: Int) async throws {
        declineRequests.append(.init(participantID: participantID, generation: generation))
    }
    func companionContext(visitIDs: [String]) async throws -> [SharedVisitCompanion] { [] }
    func downloadPhotoData(bucket: String, path: String) async throws -> Data { Data() }
    func uploadPhotoData(bucket: String, path: String, data: Data, contentType: String) async throws {}
    func markPhotoUploaded(photoID: String) async throws {}
}

@MainActor
private final class FakeExtractionRepository: ExtractionRepository {
    private let result: ExtractionJobEnqueueResult?
    private let processResult: ExtractionJobResult?
    private let error: Error?
    private(set) var drafts: [ExtractionJobDraft] = []
    private(set) var processedJobIDs: [String] = []
    private(set) var fetchedJobIDs: [String] = []

    init(result: ExtractionJobEnqueueResult? = nil, processResult: ExtractionJobResult? = nil, error: Error? = nil) {
        self.result = result
        self.processResult = processResult
        self.error = error
    }

    func enqueue(_ draft: ExtractionJobDraft) async throws -> ExtractionJobEnqueueResult {
        drafts.append(draft)
        if let error {
            throw error
        }
        return result ?? ExtractionJobEnqueueResult(
            sourceArtifactID: "source_fake",
            extractionJobID: "job_fake",
            status: .pending,
            attemptCount: 0
        )
    }

    func process(jobID: String) async throws -> ExtractionJobResult {
        processedJobIDs.append(jobID)
        if let error {
            throw error
        }
        return processResult ?? ExtractionJobResult(
            extractionJobID: jobID,
            status: .noPlaceFound,
            attemptCount: 1,
            providerSteps: ["worker_started", "no_place_found"],
            candidates: [],
            confidence: 0,
            errorCode: "no_place_found",
            errorMessage: nil
        )
    }

    func result(jobID: String) async throws -> ExtractionJobResult {
        fetchedJobIDs.append(jobID)
        if let error {
            throw error
        }
        return processResult ?? ExtractionJobResult(
            extractionJobID: jobID,
            status: .pending,
            attemptCount: 0,
            providerSteps: ["queued_for_backend_extraction"],
            candidates: [],
            confidence: 0,
            errorCode: nil,
            errorMessage: nil
        )
    }
}

@MainActor
private final class FakeListSuggestionRepository: ListSuggestionRepository {
    private let response: ListSuggestionFunctionResponse
    private(set) var payloads: [ListSuggestionPayload] = []
    var beforeResponse: (() async -> Void)?
    var shouldFail = false

    init(response: ListSuggestionFunctionResponse) {
        self.response = response
    }

    func suggestions(payload: ListSuggestionPayload) async throws -> ListSuggestionFunctionResponse {
        payloads.append(payload)
        await beforeResponse?()
        if shouldFail { throw TestError.expected }
        return response
    }
}

@MainActor
private final class FakePlaceListRepository: PlaceListRepository {
    var failSnapshotUpload = false
    private(set) var snapshotUploadCount = 0

    func uploadSnapshotCover(listID: String, jpegData: Data) async throws -> String {
        snapshotUploadCount += 1
        if failSnapshotUpload { throw TestError.expected }
        return "\(listID)/snapshot.jpg"
    }

    struct CollaboratorRequest: Equatable {
        let listID: String
        let userIDs: [String]
    }

    struct ItemRequest: Equatable {
        let draft: PlaceListItemDraft
    }

    private var visibleListsResult: [RemotePlaceListSummary]
    private let detailsByListID: [String: RemotePlaceListDetail]
    private let failedDetailListIDs: Set<String>
    private let upsertResults: [String]
    private let itemResult: String
    private let upsertDelayNanoseconds: UInt64
    private let leaveError: Error?
    private(set) var visibleListRequestCount = 0
    private(set) var detailListIDs: [String] = []
    private(set) var upsertedDrafts: [PlaceListUpsertDraft] = []
    private(set) var deletedListIDs: [String] = []
    private(set) var leftListIDs: [String] = []
    private(set) var collaboratorRequests: [CollaboratorRequest] = []
    private(set) var itemRequests: [ItemRequest] = []
    private(set) var removedItems: [(listID: String, itemID: String)] = []

    init(
        visibleLists: [RemotePlaceListSummary] = [],
        details: [String: RemotePlaceListDetail] = [:],
        failedDetailListIDs: Set<String> = [],
        upsertResult: String = "11111111-1111-4111-8111-111111111111",
        upsertResults: [String]? = nil,
        itemResult: String = "22222222-2222-4222-8222-222222222222",
        upsertDelayNanoseconds: UInt64 = 0,
        leaveError: Error? = nil
    ) {
        self.visibleListsResult = visibleLists
        self.detailsByListID = details
        self.failedDetailListIDs = failedDetailListIDs
        self.upsertResults = upsertResults ?? [upsertResult]
        self.itemResult = itemResult
        self.upsertDelayNanoseconds = upsertDelayNanoseconds
        self.leaveError = leaveError
    }

    func setVisibleLists(_ visibleLists: [RemotePlaceListSummary]) {
        visibleListsResult = visibleLists
    }

    func visibleLists() async throws -> [RemotePlaceListSummary] {
        visibleListRequestCount += 1
        return visibleListsResult
    }

    func detail(listID: String) async throws -> RemotePlaceListDetail? {
        detailListIDs.append(listID)
        if failedDetailListIDs.contains(listID) {
            throw TestError.expected
        }
        return detailsByListID[listID]
    }

    func upsert(_ draft: PlaceListUpsertDraft) async throws -> String {
        if upsertDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: upsertDelayNanoseconds)
        }
        upsertedDrafts.append(draft)
        return upsertResults[min(upsertedDrafts.count - 1, upsertResults.count - 1)]
    }

    func delete(listID: String) async throws {
        deletedListIDs.append(listID)
    }

    func leave(listID: String) async throws {
        leftListIDs.append(listID)
        if let leaveError {
            throw leaveError
        }
    }

    func setCollaborators(listID: String, userIDs: [String]) async throws {
        collaboratorRequests.append(CollaboratorRequest(listID: listID, userIDs: userIDs))
    }

    func addItem(_ draft: PlaceListItemDraft) async throws -> String {
        itemRequests.append(ItemRequest(draft: draft))
        return itemResult
    }

    func removeItem(listID: String, itemID: String) async throws {
        removedItems.append((listID: listID, itemID: itemID))
    }
}

@MainActor
private final class FakeSurfaceSnapshotRepository: SurfaceSnapshotRepository {
    private(set) var calendarRequestCount = 0
    private(set) var listRequestCount = 0
    private(set) var socialViewports: [MapViewport] = []

    func currentUserCalendarSnapshot() async throws -> CurrentUserCalendarRemoteSnapshot {
        calendarRequestCount += 1
        return CurrentUserCalendarRemoteSnapshot(visiblePlaces: [], visits: [])
    }

    func placeListsSnapshot() async throws -> PlaceListsRemoteSnapshot {
        listRequestCount += 1
        return PlaceListsRemoteSnapshot(
            summaries: [],
            details: [],
            visiblePlacesByOwnerID: [:],
            relationshipsByOwnerID: [:]
        )
    }

    func socialSurfaceSnapshot(in viewport: MapViewport) async throws -> SocialSurfaceRemoteSnapshot {
        socialViewports.append(viewport)
        return SocialSurfaceRemoteSnapshot(
            following: [],
            followers: [],
            viewportPlaces: [],
            ownWannaGoPlans: [],
            visiblePlacesByOwnerID: [:],
            relationshipsByOwnerID: [:]
        )
    }
}

@MainActor
private final class FakePlaceResolver: PlaceCandidateResolving {
    private let currentLocationResult: Result<[PlaceCandidate], Error>
    private let nearbyResult: Result<[PlaceCandidate], Error>
    private let manualResult: Result<[PlaceCandidate], Error>
    private let linkResult: Result<[PlaceCandidate], Error>
    private(set) var currentLocationCallCount = 0
    private(set) var nearbyCoordinates: [CLLocationCoordinate2D] = []
    private(set) var manualInputs: [ManualPlaceInput] = []
    private(set) var linkInputs: [LinkPlaceInput] = []

    init(
        currentLocationCandidates: [PlaceCandidate] = [],
        nearbyCandidates: [PlaceCandidate] = [],
        manualCandidates: [PlaceCandidate] = [],
        linkCandidates: [PlaceCandidate] = [],
        currentLocationError: Error? = nil,
        nearbyError: Error? = nil,
        manualError: Error? = nil,
        linkError: Error? = nil
    ) {
        if let currentLocationError {
            self.currentLocationResult = .failure(currentLocationError)
        } else {
            self.currentLocationResult = .success(currentLocationCandidates)
        }

        if let nearbyError {
            self.nearbyResult = .failure(nearbyError)
        } else {
            self.nearbyResult = .success(nearbyCandidates)
        }

        if let manualError {
            self.manualResult = .failure(manualError)
        } else {
            self.manualResult = .success(manualCandidates)
        }

        if let linkError {
            self.linkResult = .failure(linkError)
        } else {
            self.linkResult = .success(linkCandidates)
        }
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        currentLocationCallCount += 1
        return try currentLocationResult.get()
    }

    func resolveNearbyPlaces(near coordinate: CLLocationCoordinate2D) async throws -> [PlaceCandidate] {
        nearbyCoordinates.append(coordinate)
        return try nearbyResult.get()
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        manualInputs.append(input)
        return try manualResult.get()
    }

    func resolveLink(_ input: LinkPlaceInput) async throws -> [PlaceCandidate] {
        linkInputs.append(input)
        return try linkResult.get()
    }
}

@MainActor
private final class FakeFilterParser: LLMFilterParser {
    private let result: DiscoverFilters?
    private let error: Error?
    private(set) var queries: [String] = []

    init(result: DiscoverFilters? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        queries.append(query)
        if let error {
            throw error
        }
        return result ?? DiscoverFilters(query: query)
    }
}

private final class RecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []
    private(set) var identifiedUserIDs: [String] = []
    private(set) var resetCount = 0

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {
        identifiedUserIDs.append(userID)
    }

    func resetIdentity() {
        resetCount += 1
    }
}
