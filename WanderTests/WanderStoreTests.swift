import CoreLocation
import XCTest
@testable import Wander

private enum TestError: Error {
    case expected
}

@MainActor
final class WanderStoreTests: XCTestCase {
    private func makeStore() -> WanderStore {
        WanderStore(fixtures: WanderFixtures.seed())
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

    func testSignedInSessionPreservesExistingLocalAvatarURL() {
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
        XCTAssertEqual(store.currentUser.avatarURL, avatarURL)
        XCTAssertEqual(store.profileState(for: "user_live")?.shell.avatarURL, avatarURL)
        XCTAssertEqual(store.currentUser.syncState, .synced)
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

        await store.refreshRemoteCurrentProfile(backend: backend)

        XCTAssertEqual(store.currentUser.id, "user_live")
        XCTAssertEqual(store.currentUser.handle, "joe")
        XCTAssertEqual(store.currentUser.avatarURL, remoteAvatarURL)
        XCTAssertEqual(store.currentUser.defaultVisibility, .mutuals)
        XCTAssertEqual(store.profileState(for: "user_live")?.shell.avatarURL, remoteAvatarURL)
        XCTAssertEqual(store.pendingSyncCount, initialPendingCount)
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

    func testSavingSamePlaceMergesIntoExistingUserPlace() {
        let store = makeStore()
        let originalCount = store.currentUserVisiblePlaces.count

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
        XCTAssertEqual(woodcat?.userPlace.status, .wannaGo)
        XCTAssertEqual(woodcat?.userPlace.visibility, .selfOnly)
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
        XCTAssertEqual(saved?.userPlace.status, .wannaGo)
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
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: nil), 3)
        XCTAssertEqual(PlaceRating.scoreForSave(status: .been, score: 0), 1)
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
        XCTAssertEqual(occasion?.kind, .multiTag)
        XCTAssertEqual(occasion?.valueType, "multi_tag")
        XCTAssertTrue((occasion?.defaultValues.count ?? 0) > 1)
        XCTAssertEqual(tags?.kind, .multiTag)
    }

    func testWannaGoQuestionTemplatesAvoidVisitedOnlyPrompts() {
        let restaurantBlocks = AddQuestionTemplates.blocks(category: "restaurant", status: .wannaGo)
        let coffeeBlocks = AddQuestionTemplates.blocks(category: "coffee", status: .wannaGo)
        let hikeBlocks = AddQuestionTemplates.blocks(category: "hike", status: .wannaGo)

        XCTAssertEqual(restaurantBlocks.map(\.key), ["interest_signal", "occasion", "restaurant_tags"])
        XCTAssertEqual(restaurantBlocks.first?.title, "how excited are you?")
        XCTAssertEqual(restaurantBlocks.first?.options, ["curious", "excited", "must go"])
        XCTAssertNil(restaurantBlocks.first { $0.key == "price" })
        XCTAssertEqual(restaurantBlocks.first { $0.key == "occasion" }?.title, "planning for?")
        XCTAssertEqual(restaurantBlocks.first { $0.key == "restaurant_tags" }?.title, "why save it?")
        XCTAssertEqual(restaurantBlocks.first { $0.key == "restaurant_tags" }?.defaultValues, [])

        XCTAssertEqual(coffeeBlocks.map(\.key), ["interest_signal", "coffee_tags"])
        XCTAssertNil(coffeeBlocks.first { $0.key == "work_setup" })
        XCTAssertEqual(coffeeBlocks.first { $0.key == "coffee_tags" }?.title, "why save it?")

        XCTAssertEqual(hikeBlocks.map(\.key), ["interest_signal", "hike_tags"])
        XCTAssertNil(hikeBlocks.first { $0.key == "strenuousness" })
        XCTAssertEqual(hikeBlocks.first { $0.key == "hike_tags" }?.options.contains("easy maybe"), true)
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
        XCTAssertEqual(analytics.events.map { $0.properties["source"] }, ["parser", "cache"])
    }

    func testDiscoverParserFailureFallsBackAndTracksFailure() async {
        let analytics = RecordingAnalyticsClient()
        let parser = FakeFilterParser(error: TestError.expected)
        let store = WanderStore(fixtures: WanderFixtures.seed(), parser: parser, analytics: analytics)

        let filters = await store.parseDiscover(query: "anything")

        XCTAssertEqual(filters, DiscoverFilters(query: "anything"))
        XCTAssertEqual(analytics.events.map(\.name), [WanderAnalyticsEvents.discoverParseFailed])
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

    func testRemoteSocialSurfacesHydrateFollowedUsersAndTheirPlaces() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let maya = ProfileShell(id: "user_maya", handle: "maya", displayName: "Maya", avatarURL: nil, bio: nil, relationship: .follower)
        let ryan = ProfileShell(id: "user_ryan", handle: "ryan", displayName: "Ryan", avatarURL: nil, bio: nil, relationship: .follower)
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
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"])).map(\.place.canonicalName), ["Speranza", "Dama"])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_maya"])).map(\.place.canonicalName), ["Speranza"])
        XCTAssertEqual(store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"], ownerIDs: ["user_ryan"])).map(\.place.canonicalName), ["Dama"])
        let discoverPlaces = await store.discover(query: "", scope: .everyone, backend: backend).places
        XCTAssertEqual(discoverPlaces.map(\.owner.id), ["user_maya", "user_ryan"])
        XCTAssertEqual(discoverPlaces.map(\.place.canonicalName), ["Speranza", "Dama"])
        XCTAssertEqual(followRepository.followingUserIDs, ["user_live"])
        XCTAssertEqual(placeRepository.viewports.count, 1)
        XCTAssertEqual(userPlaceRepository.userPlaceRequests.map(\.userID), ["user_maya", "user_ryan"])
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

    func testSocialSaveFlowContextPrefillsSourceStatusAndTags() {
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
        XCTAssertEqual(context.initialAnswers["hike_tags"], Set(["sunset", "views"]))
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
        XCTAssertEqual(analytics.resetCount, 1)
    }

    func testRemoteOwnPlaceSaveFailureTracksNonPIISyncDiagnostics() async throws {
        let analytics = RecordingAnalyticsClient()
        let store = WanderStore(fixtures: WanderFixtures.empty(), analytics: analytics)
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
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

    func testRetryFailedOwnPlaceSyncsMarksRowsSynced() async {
        let store = WanderStore(fixtures: WanderFixtures.empty())
        store.apply(authState: .signedIn(AuthSession(userID: "user_live", displayName: "Joe", handle: "joe")))
        let failingBackend = WanderBackend(
            userPlaceRepository: FakeUserPlaceRepository(error: WanderRemoteError.invalidResponse("network down"))
        )

        let failed = await store.saveCandidate(
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
            attributes: [],
            backend: failingBackend
        )
        XCTAssertEqual(failed.syncState, .failed)

        let successRepository = FakeUserPlaceRepository(
            result: SaveResult(userPlaceID: "up_remote_taco", syncState: .synced, placeID: "place_remote_taco")
        )
        let retriedCount = await store.retryFailedOwnPlaceSyncs(
            backend: WanderBackend(userPlaceRepository: successRepository)
        )

        XCTAssertEqual(retriedCount, 1)
        XCTAssertEqual(successRepository.savedDrafts.count, 1)
        XCTAssertEqual(successRepository.savedDrafts[0].note, "retry this")
        let saved = store.currentUserVisiblePlaces.first { $0.place.canonicalName == "Taco Table" }
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

        await store.follow(userID: "user_sofia", source: .username, backend: backend)

        let follow = store.follows.first { $0.followedUserID == "user_sofia" }
        XCTAssertEqual(follow?.syncStateRaw, SyncState.failed.rawValue)
        XCTAssertEqual(followRepository.followedUserIDs, ["user_sofia"])
        XCTAssertNotNil(follow?.lastSyncError)
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
        XCTAssertTrue(store.visiblePlaceLists(scope: .friends).contains { $0.id == "list_maya_sunset" })
        XCTAssertTrue(store.visiblePlaceLists(scope: .collabs).contains { $0.id == "list_launch" })
        XCTAssertFalse(store.visiblePlaceLists(scope: .collabs).contains { $0.id == "list_saturday" })
    }

    func testListSuggestionsExcludeExistingPlaces() {
        let store = makeStore()
        let list = store.placeLists.first { $0.id == "list_laptop" }!
        let existingPlaceIDs = Set(store.visiblePlaces(in: list).map(\.place.id))

        let suggestions = store.listSuggestions(for: list, limit: 6)

        XCTAssertFalse(suggestions.isEmpty)
        XCTAssertTrue(suggestions.allSatisfy { !existingPlaceIDs.contains($0.visiblePlace.place.id) })
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
    }

    func testCollaboratorCannotAddPlaceToSomeoneElsesList() async {
        let store = makeStore()
        let collabList = store.placeLists.first { $0.id == "list_launch" }!
        let place = store.visiblePlaces().first { $0.place.canonicalName == "Bar Nido" }!
        let initialCount = store.visiblePlaces(in: collabList).count

        let result = await store.addVisiblePlace(place, to: collabList, backend: nil)

        XCTAssertEqual(result.outcome, .permissionDenied)
        XCTAssertEqual(store.visiblePlaces(in: collabList).count, initialCount)
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

    func testListPersistenceRestoresListsAndAutoSaveSetting() {
        let fixture = makeTemporaryPersistence()
        let firstStore = WanderStore(fixtures: WanderFixtures.seed(), persistence: fixture.persistence)
        firstStore.autoSaveListAddsToWant = false

        let relaunchedStore = WanderStore(fixtures: WanderFixtures.empty(), persistence: fixture.persistence)

        XCTAssertEqual(relaunchedStore.placeLists.map(\.id), firstStore.placeLists.map(\.id))
        XCTAssertEqual(relaunchedStore.placeListItems.map(\.id), firstStore.placeListItems.map(\.id))
        XCTAssertFalse(relaunchedStore.autoSaveListAddsToWant)
    }
}

@MainActor
private final class FakeProfileRepository: ProfileRepository {
    private let shells: [ProfileShell]
    private let currentProfileResult: LocalProfile?
    private(set) var queries: [String] = []

    init(shells: [ProfileShell] = [], currentProfile: LocalProfile? = nil) {
        self.shells = shells
        self.currentProfileResult = currentProfile
    }

    func currentProfile() async throws -> LocalProfile? {
        currentProfileResult
    }

    func profile(id: String) async throws -> ProfileViewState {
        throw WanderRemoteError.notImplemented("fake profile")
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        queries.append(handleQuery)
        return shells
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
        return followingResult
    }

    func relationship(to userID: String) async throws -> ViewerRelationship {
        relationshipUserIDs.append(userID)
        return relationships[userID] ?? .nonFollower
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
    private let placesResult: [VisiblePlace]
    private(set) var viewports: [MapViewport] = []

    init(places: [VisiblePlace]) {
        self.placesResult = places
    }

    func places(in viewport: MapViewport) async throws -> [VisiblePlace] {
        viewports.append(viewport)
        return placesResult
    }

    func resolveCurrentLocation() async throws -> [PlaceCandidate] {
        []
    }

    func resolveManualEntry(_ input: ManualPlaceInput) async throws -> [PlaceCandidate] {
        []
    }
}

@MainActor
private final class FakeUserPlaceRepository: UserPlaceRepository {
    struct UserPlaceRequest: Equatable {
        let userID: String
        let filters: PlaceFilters
    }

    private let result: SaveResult?
    private let error: Error?
    private let userPlacesByUserID: [String: [VisiblePlace]]
    private(set) var savedDrafts: [UserPlaceDraft] = []
    private(set) var userPlaceRequests: [UserPlaceRequest] = []
    private(set) var deletedUserPlaceIDs: [String] = []

    init(result: SaveResult? = nil, error: Error? = nil, userPlacesByUserID: [String: [VisiblePlace]] = [:]) {
        self.result = result
        self.error = error
        self.userPlacesByUserID = userPlacesByUserID
    }

    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] {
        userPlaceRequests.append(UserPlaceRequest(userID: userID, filters: filters))
        return userPlacesByUserID[userID] ?? []
    }

    func save(_ draft: UserPlaceDraft) async throws -> SaveResult {
        savedDrafts.append(draft)
        if let error {
            throw error
        }
        return result ?? SaveResult(userPlaceID: "up_fake", syncState: .synced, placeID: "place_fake")
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
