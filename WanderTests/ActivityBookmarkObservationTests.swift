import Foundation
import Observation
import XCTest
@testable import Wander

@MainActor
final class ActivityBookmarkObservationTests: XCTestCase {
    func testColdAndWarmImportScopedReadsObserveRawOwnedStatusAliasDeletionAndOwnership() async throws {
        for warm in [false, true] {
            for mutation in 0..<4 {
                let fixture = BookmarkWatchFixture()
                let store = fixture.store
                let context = try await fixture.activateImportObservation()
                defer { context.finish() }
                if warm { XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna) }
                else { fixture.revise() }
                let changes = BookmarkWatchCounter()
                let initial = withObservationTracking {
                    store.activityBookmarkState(for: fixture.target)
                } onChange: { changes.increment() }
                XCTAssertEqual(initial, .wanna)
                let revision = store.presentationRevision
                switch mutation {
                case 0: fixture.save.statusRaw = PlaceStatus.been.rawValue
                case 1: fixture.place.sourceProviderPlaceID = "different-provider-place"
                case 2: fixture.save.deletedAt = fixture.now
                default: fixture.save.userID = fixture.other.id
                }
                XCTAssertGreaterThan(changes.value, 0, "warm=\(warm), mutation=\(mutation)")
                XCTAssertEqual(store.presentationRevision, revision,
                    "The regression must exercise raw models without an explicit store revision")
                XCTAssertEqual(store.activityBookmarkState(for: fixture.target),
                    mutation == 0 ? .checkedIn : .notSaved,
                    "The first read after the setter must see its completed value")
            }
        }
    }

    func testPreviouslyBuiltFullProjectionCannotKeepDeletedOrReassignedParentsInBookmarkIndex() async throws {
        for mutation in 0..<3 {
            let fixture = BookmarkWatchFixture()
            XCTAssertEqual(fixture.store.currentUserVisiblePlaces.count, 1)
            let context = try await fixture.activateImportObservation()
            defer { context.finish() }
            XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .wanna)
            switch mutation {
            case 0: fixture.save.deletedAt = fixture.now
            case 1: fixture.save.userID = fixture.other.id
            default: fixture.save.placeID = "missing-place"
            }
            XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .notSaved,
                "Cached full visibility is not proof of current raw membership")
        }
    }

    func testForeignContentIsExcludedButForeignToOwnedRoleChangeIsObserved() async throws {
        let fixture = BookmarkWatchFixture()
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.foreignTarget), .notSaved)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking {
            fixture.store.activityBookmarkState(for: fixture.foreignTarget)
        } onChange: { changes.increment() }

        fixture.foreignSave.note = "Unrelated content"
        fixture.foreignSave.statusRaw = PlaceStatus.wannaGo.rawValue
        fixture.foreignSave.visibilityRaw = PlaceVisibility.selfOnly.rawValue
        fixture.foreignSave.localID = "different-foreign-save"
        fixture.foreignSave.deletedAt = fixture.now
        fixture.foreignPlace.canonicalName = "Different foreign content"
        fixture.foreignPlace.latitude = 12
        fixture.foreignPlace.longitude = 13
        XCTAssertEqual(changes.value, 0)
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.foreignTarget), .notSaved)

        fixture.foreignSave.deletedAt = nil
        fixture.foreignSave.userID = fixture.owner.id
        XCTAssertGreaterThan(changes.value, 0, "Ownership is a membership input even for a previously foreign row")
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.foreignTarget), .wanna)
    }

    func testReentrantAndLaterIndependentObserverReadsCannotCachePreSetterState() async throws {
        let fixture = BookmarkWatchFixture()
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        let store = fixture.store
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)
        let reads = BookmarkWatchReads()
        _ = withObservationTracking {
            store.activityBookmarkState(for: fixture.target)
        } onChange: {
            MainActor.assumeIsolated {
                reads.fromBookmarkObserver.append(store.activityBookmarkState(for: fixture.target))
            }
        }
        // A separate observer may run before or after the bridge's willSet
        // callback. Its read is not permission to cache or rearm old values.
        _ = withObservationTracking { fixture.save.statusRaw } onChange: {
            MainActor.assumeIsolated {
                reads.fromModelObserver.append(store.activityBookmarkState(for: fixture.target))
            }
        }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(reads.fromBookmarkObserver.count, 1)
        XCTAssertEqual(reads.fromModelObserver.count, 1)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .checkedIn)
        fixture.save.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna,
            "A second completed setter in the same actor turn must remain fresh")
        fixture.save.deletedAt = fixture.now
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .notSaved)
    }

    func testRawBlockChangesAndAccountSwitchRecheckAuthorization() async throws {
        let fixture = BookmarkWatchFixture()
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .wanna)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking {
            fixture.store.activityBookmarkState(for: fixture.target)
        } onChange: { changes.increment() }
        fixture.block.blockedUserID = fixture.owner.id
        XCTAssertGreaterThan(changes.value, 0)
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .notSaved)
        fixture.block.blockedUserID = "unrelated"
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .wanna)

        fixture.store.apply(authState: .signedIn(AuthSession(userID: fixture.other.id,
            displayName: fixture.other.displayName, handle: fixture.other.handle)))
        XCTAssertFalse(fixture.store.activityBookmarkObservationIsActive)
        XCTAssertEqual(fixture.store.activityBookmarkObservationRegistrationCount, 0)
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .notSaved)
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.foreignTarget), .checkedIn)
    }

    func testRemoteFirstIDPrecedenceTombstoneAndPayloadOwnershipStayFresh() async throws {
        let fixture = BookmarkWatchFixture()
        let duplicate = fixture.remote(id: fixture.save.id, providerID: "owned-provider", status: .been)
        let remote = fixture.remote(id: "remote-save", providerID: "remote-provider", status: .been)
        let remoteTarget = fixture.target(providerID: "remote-provider")
        let repository = BookmarkWatchRepository(rows: [duplicate, remote])
        await fixture.store.refreshRemoteProfileVisiblePlaces(profileID: fixture.owner.id,
            backend: WanderBackend(userPlaceRepository: repository))
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .wanna,
            "First local visible ID wins over a remote duplicate")
        XCTAssertEqual(fixture.store.activityBookmarkState(for: remoteTarget), .checkedIn)

        fixture.save.deletedAt = fixture.now
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .checkedIn,
            "An excluded local tombstone must not suppress the authorized remote row")
        remote.userPlace.deletedAt = fixture.now
        XCTAssertEqual(fixture.store.activityBookmarkState(for: remoteTarget), .notSaved)
        remote.userPlace.deletedAt = nil
        remote.userPlace.userID = fixture.other.id
        XCTAssertEqual(fixture.store.activityBookmarkState(for: remoteTarget), .notSaved,
            "An owner shell cannot authorize a foreign private payload")
        remote.userPlace.userID = fixture.owner.id
        XCTAssertEqual(fixture.store.activityBookmarkState(for: remoteTarget), .checkedIn)
    }

    func testOrdinaryReadsDoNotRegisterAndCheckpointPrewarmRequiresPriorDemand() async throws {
        let fixture = BookmarkWatchFixture()
        let store = fixture.store
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: fixture.owner.id))
        defer { context.finish() }
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, 0,
            "Pure model imports must not build an index that no view requested")

        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0,
            "Ordinary bookmark demand must retain the existing cold-read behavior")
        fixture.revise()
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        let registrations = store.activityBookmarkObservationRegistrationCount
        let builds = store.activityBookmarkIndexBuildCount
        XCTAssertGreaterThan(registrations, 0)
        for _ in 0..<20 { XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna) }
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, registrations)
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, builds,
            "Mounted reads should consume the already-prewarmed exact projection")

        context.finish()
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
        await store.waitForActivityBookmarkObservationSettlement()
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { store.activityBookmarkState(for: fixture.target) }
            onChange: { changes.increment() }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertGreaterThan(changes.value, 0,
            "Scope exit must restore the ordinary cold raw-observation contract")
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
    }

    func testPendingStoreReadsStayUncachedUntilSettlementThenReuseOneFreshIndex() async throws {
        let fixture = BookmarkWatchFixture()
        let store = fixture.store
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        let registrations = store.activityBookmarkObservationRegistrationCount
        let reads = BookmarkWatchReads()
        _ = withObservationTracking { store.activityBookmarkState(for: fixture.target) } onChange: {
            MainActor.assumeIsolated {
                reads.fromBookmarkObserver.append(store.activityBookmarkState(for: fixture.target))
            }
        }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertTrue(store.activityBookmarkObservationHasPendingSettlement)
        let builds = store.activityBookmarkIndexBuildCount
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .checkedIn)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .checkedIn)
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, builds + 2,
            "Neither a willSet read nor a post-setter read may memoize while settlement is pending")
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, registrations)
        fixture.save.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)

        await store.waitForActivityBookmarkObservationSettlement()
        XCTAssertFalse(store.activityBookmarkObservationHasPendingSettlement)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)
        let settledBuilds = store.activityBookmarkIndexBuildCount
        let settledRegistrations = store.activityBookmarkObservationRegistrationCount
        XCTAssertGreaterThan(settledRegistrations, registrations)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)
        XCTAssertEqual(store.activityBookmarkIndexBuildCount, settledBuilds)
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, settledRegistrations)
    }

    func testOlderContextCannotDetachNewlyActivatedScope() async throws {
        let fixture = BookmarkWatchFixture()
        let store = fixture.store
        let first = try await fixture.activateImportObservation()
        defer { first.finish() }
        let second = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: fixture.owner.id))
        defer { second.finish() }
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: second)
        first.finish()
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0,
            "A concurrent context must skip optional prewarm while another owns the bridge")
        await store.waitForActivityBookmarkObservationSettlement()
        _ = store.activityBookmarkState(for: fixture.target)
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: second)
        let registrations = store.activityBookmarkObservationRegistrationCount
        XCTAssertGreaterThan(registrations, 0)
        first.finish()
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, registrations)
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .checkedIn)
        await store.waitForActivityBookmarkObservationSettlement()
    }

    func testScopeFinishDuringWillSetDoesNotCacheOldStateOrKeepModelRegistrations() async throws {
        let fixture = BookmarkWatchFixture()
        let store = fixture.store
        let context = try await fixture.activateImportObservation()
        defer { context.finish() }
        let reads = BookmarkWatchReads()
        _ = withObservationTracking { store.activityBookmarkState(for: fixture.target) } onChange: {
            MainActor.assumeIsolated {
                context.finish()
                reads.fromBookmarkObserver.append(store.activityBookmarkState(for: fixture.target))
            }
        }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(reads.fromBookmarkObserver.count, 1)
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .checkedIn)
        fixture.save.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertEqual(store.activityBookmarkState(for: fixture.target), .wanna)
        await store.waitForActivityBookmarkObservationSettlement()
        XCTAssertEqual(store.activityBookmarkObservationRegistrationCount, 0)
    }

    func testEarlierIndependentModelObserverCanFinishScopeWithoutCachingPreSetterState() async throws {
        let fixture = BookmarkWatchFixture()
        let reads = BookmarkWatchReads()
        _ = withObservationTracking { fixture.save.statusRaw } onChange: {
            MainActor.assumeIsolated {
                reads.context?.finish()
                reads.fromModelObserver.append(fixture.store.activityBookmarkState(for: fixture.target))
            }
        }
        let context = try await fixture.activateImportObservation()
        reads.context = context
        defer { context.finish() }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(reads.fromModelObserver.count, 1)
        XCTAssertFalse(fixture.store.activityBookmarkObservationIsActive)
        XCTAssertEqual(fixture.store.activityBookmarkState(for: fixture.target), .checkedIn)
        await fixture.store.waitForActivityBookmarkObservationSettlement()
        XCTAssertEqual(fixture.store.activityBookmarkObservationRegistrationCount, 0)
    }

    func testHelperNeverRearmsInsideWillSetOrBeforeExplicitSettlement() async {
        let fixture = BookmarkWatchFixture()
        let observation = ActivityBookmarkObservation()
        defer { observation.finish() }
        refresh(observation, saves: [fixture.save])
        XCTAssertEqual(observation.registrationCount, 1)
        let reads = BookmarkWatchReads()
        _ = withObservationTracking { observation.revision } onChange: {
            MainActor.assumeIsolated {
                reads.refreshAdmissions.append(observation.beginRefresh())
                observation.watch(fixture.save, role: "save") { _ = $0.statusRaw }
                observation.endRefresh()
            }
        }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(reads.refreshAdmissions, [false])
        XCTAssertTrue(observation.hasPendingSettlement)
        XCTAssertFalse(observation.beginRefresh())
        observation.watch(fixture.save, role: "save") { _ = $0.statusRaw }
        observation.endRefresh()
        XCTAssertEqual(observation.registrationCount, 1,
            "A callback or same-turn read must not register a pre-setter value")

        fixture.save.statusRaw = PlaceStatus.wannaGo.rawValue
        await observation.waitForPendingSettlement()
        XCTAssertFalse(observation.hasPendingSettlement)
        refresh(observation, saves: [fixture.save])
        XCTAssertEqual(observation.registrationCount, 2)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { observation.revision } onChange: { changes.increment() }
        fixture.save.statusRaw = PlaceStatus.been.rawValue
        XCTAssertEqual(changes.value, 1, "The settled registration must observe the next real write")
        await observation.waitForPendingSettlement()
    }

    func testNestedStructureAndResetNotificationsReachNewObserverAfterOuterCallbackReturns() async {
        for resetting in [false, true] {
            let observation = ActivityBookmarkObservation()
            defer { observation.finish() }
            let first = BookmarkWatchCounter()
            let second = BookmarkWatchCounter()
            _ = withObservationTracking { observation.revision } onChange: {
                first.increment()
                MainActor.assumeIsolated {
                    _ = withObservationTracking { observation.revision } onChange: { second.increment() }
                    if resetting { observation.reset() }
                    else { observation.invalidateStructure() }
                }
            }
            // No raw model mutation exists here to supply a settlement task.
            // The second observer precedes the nested change and must receive
            // it, without recursively invoking the still-running first one.
            observation.invalidateStructure()
            XCTAssertEqual(first.value, 1)
            XCTAssertEqual(second.value, 0)
            XCTAssertTrue(observation.hasPendingSettlement)
            await observation.waitForPendingSettlement()
            XCTAssertEqual(first.value, 1)
            XCTAssertEqual(second.value, 1)
            XCTAssertFalse(observation.hasPendingSettlement)
        }
    }

    func testHelperUnchangedReadsReorderAppendAndSameIDReplacementKeepExactLifetimes() throws {
        let observation = ActivityBookmarkObservation()
        defer { observation.finish() }
        let first = BookmarkWatchFixture.place("same-id", providerID: "first")
        var second: LocalPlace? = BookmarkWatchFixture.place("same-id", providerID: "second")
        weak var oldSecond = second
        refresh(observation, places: [first, try XCTUnwrap(second), first])
        XCTAssertEqual(observation.registrationCount, 2)
        XCTAssertEqual(observation.retainedRegistrationCount, 2)
        for _ in 0..<20 { refresh(observation, places: [try XCTUnwrap(second), first, first]) }
        XCTAssertEqual(observation.registrationCount, 2, "Order and duplicate references do not need new model observers")

        let appended = BookmarkWatchFixture.place("appended", providerID: "appended")
        refresh(observation, places: [first, try XCTUnwrap(second), appended])
        XCTAssertEqual(observation.registrationCount, 3)
        second = nil
        XCTAssertNotNil(oldSecond, "Keep the old object alive through replacement identity comparison")
        let replacement = BookmarkWatchFixture.place("same-id", providerID: "replacement")
        refresh(observation, places: [first, replacement, appended])
        XCTAssertEqual(observation.registrationCount, 4)
        XCTAssertEqual(observation.retainedRegistrationCount, 3)
        XCTAssertNil(oldSecond, "Pruning must cancel and release the replaced same-ID object")

        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { observation.revision } onChange: { changes.increment() }
        replacement.sourceProviderPlaceID = "changed-replacement"
        XCTAssertEqual(changes.value, 1)
    }

    func testHelperRoleChangePrunesOwnedFieldsButKeepsMembershipObservation() {
        let fixture = BookmarkWatchFixture()
        let observation = ActivityBookmarkObservation()
        defer { observation.finish() }
        XCTAssertTrue(observation.beginRefresh())
        observation.watch(fixture.foreignSave, role: "owned") {
            _ = $0.userID
            _ = $0.statusRaw
        }
        observation.endRefresh()
        XCTAssertTrue(observation.beginRefresh())
        observation.watch(fixture.foreignSave, role: "foreign") { _ = $0.userID }
        observation.endRefresh()
        XCTAssertEqual(observation.registrationCount, 2)
        XCTAssertEqual(observation.retainedRegistrationCount, 1)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { observation.revision } onChange: { changes.increment() }
        fixture.foreignSave.statusRaw = PlaceStatus.wannaGo.rawValue
        XCTAssertEqual(changes.value, 0, "The old owned-role registration must be cancelled")
        fixture.foreignSave.userID = fixture.owner.id
        XCTAssertEqual(changes.value, 1)
    }

    func testStructureInvalidationReusesUnchangedRegistrationsAndPruningStopsCallbacks() {
        let observation = ActivityBookmarkObservation()
        defer { observation.finish() }
        let first = BookmarkWatchFixture.place("first", providerID: "first")
        let second = BookmarkWatchFixture.place("second", providerID: "second")
        refresh(observation, places: [first, second])
        observation.invalidateStructure()
        refresh(observation, places: [first, second])
        XCTAssertEqual(observation.registrationCount, 2,
            "An unrelated store publication must not reinstall all SwiftData registrations")
        refresh(observation, places: [second])
        XCTAssertEqual(observation.retainedRegistrationCount, 1)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { observation.revision } onChange: { changes.increment() }
        first.sourceProviderPlaceID = "pruned-change"
        XCTAssertEqual(changes.value, 0)
        second.sourceProviderPlaceID = "retained-change"
        XCTAssertEqual(changes.value, 1)
    }

    func testResetAndFinishCancelObserversReleaseModelsAndDoNotResurrectDemand() async throws {
        let observation = ActivityBookmarkObservation()
        var model: LocalPlace? = BookmarkWatchFixture.place("retained", providerID: "retained")
        weak var weakModel = model
        XCTAssertFalse(observation.hasDemand)
        refresh(observation, places: [try XCTUnwrap(model)])
        XCTAssertTrue(observation.hasDemand)
        model = nil
        XCTAssertNotNil(weakModel)
        observation.reset()
        XCTAssertEqual(observation.retainedRegistrationCount, 0)
        XCTAssertNil(weakModel)
        XCTAssertFalse(observation.hasDemand)

        let final = BookmarkWatchFixture.place("final", providerID: "final")
        refresh(observation, places: [final])
        final.sourceProviderPlaceID = "pending-final"
        XCTAssertTrue(observation.hasPendingSettlement)
        observation.finish()
        XCTAssertTrue(observation.isFinished)
        XCTAssertEqual(observation.retainedRegistrationCount, 0)
        // Retirement may complete a pending post-setter notification, but
        // must never retain or rearm the retired model after that handoff.
        await observation.waitForPendingSettlement()
        XCTAssertFalse(observation.hasPendingSettlement)
        let changes = BookmarkWatchCounter()
        _ = withObservationTracking { observation.revision } onChange: { changes.increment() }
        final.sourceProviderPlaceID = "after-finish"
        await observation.waitForPendingSettlement()
        XCTAssertEqual(changes.value, 0)
        XCTAssertFalse(observation.beginRefresh())
        observation.watch(final, role: "place") { _ = $0.sourceProviderPlaceID }
        observation.endRefresh()
        XCTAssertEqual(observation.retainedRegistrationCount, 0)
    }

    private func refresh(_ observation: ActivityBookmarkObservation, places: [LocalPlace],
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(observation.beginRefresh(), file: file, line: line)
        for place in places {
            observation.watch(place, role: "place") { _ = $0.sourceProviderPlaceID }
        }
        observation.endRefresh()
    }

    private func refresh(_ observation: ActivityBookmarkObservation, saves: [LocalUserPlace],
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(observation.beginRefresh(), file: file, line: line)
        for save in saves {
            observation.watch(save, role: "save") { _ = $0.statusRaw }
        }
        observation.endRefresh()
    }
}

@MainActor
private final class BookmarkWatchFixture {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let owner: LocalProfile
    let other: LocalProfile
    let place: LocalPlace
    let foreignPlace: LocalPlace
    let save: LocalUserPlace
    let foreignSave: LocalUserPlace
    let block: LocalBlock
    let store: WanderStore
    let target: VisiblePlace
    let foreignTarget: VisiblePlace

    init() {
        let owner = LocalProfile(localID: "watch-owner", handle: "watch-owner", displayName: "Owner")
        let other = LocalProfile(localID: "watch-other", handle: "watch-other", displayName: "Other")
        self.owner = owner
        self.other = other
        let place = Self.place("owned", providerID: "owned-provider")
        let foreign = Self.place("foreign", providerID: "foreign-provider")
        self.place = place
        foreignPlace = foreign
        let save = Self.save("owned-save", place: place, owner: owner, status: .wannaGo)
        let foreignSave = Self.save("foreign-save", place: foreign, owner: other, status: .been)
        self.save = save
        self.foreignSave = foreignSave
        let block = LocalBlock(localID: "watch-block", blockerUserID: owner.id, blockedUserID: "unrelated")
        self.block = block
        store = WanderStore(fixtures: WanderFixtures(currentUser: owner, profiles: [owner, other],
            places: [place, foreign], userPlaces: [save, foreignSave], placeAttributes: [],
            follows: [], blocks: [block], placeLists: [], placeListMembers: [], placeListItems: [],
            contactProvider: FakeContactProvider(seededMatches: [])),
            persistence: WanderStorePersistence(load: { nil }, save: { _ in },
                checkpoint: { _ in }, checkpointAsync: { _ in }))
        target = Self.target(providerID: "owned-provider", owner: other)
        foreignTarget = Self.target(providerID: "foreign-provider", owner: other)
    }

    func activateImportObservation() async throws -> WanderStore.AutomaticImportProjectionContext {
        _ = store.activityBookmarkState(for: target)
        let context = try XCTUnwrap(store.makeAutomaticImportProjectionContext(ownerUserID: owner.id))
        try await store.commitAutomaticImportCheckpointDurablyAsync(using: context)
        XCTAssertGreaterThan(store.activityBookmarkObservationRegistrationCount, 0)
        return context
    }

    func revise() {
        let batch = PlaceImportBatch(id: "bookmark-watch-revision", source: .googleMaps,
            sourceName: "Fixture", totalCount: 0, automaticSaveRequested: true)
        store.recordAutomaticImportCheckpoint(PlaceImportAutoSaveCheckpoint(
            ownerUserID: store.currentUser.id, batch: batch, eligibleItemIDs: []))
    }

    func target(providerID: String) -> VisiblePlace { Self.target(providerID: providerID, owner: other) }

    func remote(id: String, providerID: String, status: PlaceStatus) -> VisiblePlace {
        let place = Self.place("remote-place-\(id)", providerID: providerID)
        return VisiblePlace(id: id, place: place,
            userPlace: Self.save(id, place: place, owner: owner, status: status), owner: owner)
    }

    static func place(_ id: String, providerID: String) -> LocalPlace {
        LocalPlace(localID: id, canonicalName: "Place \(id)", category: "park",
            latitude: 34, longitude: -118, sourceProvider: "fixture", sourceProviderPlaceID: providerID)
    }

    static func save(_ id: String, place: LocalPlace, owner: LocalProfile, status: PlaceStatus) -> LocalUserPlace {
        LocalUserPlace(localID: id, userID: owner.id, placeID: place.id, status: status,
            visibility: .selfOnly, sourceType: "manual")
    }

    private static func target(providerID: String, owner: LocalProfile) -> VisiblePlace {
        // This is deliberately a different object, ID, name and location.
        // Only the provider alias matches, so target-property observation
        // cannot conceal a missing subscription to the library models.
        let place = LocalPlace(localID: "target-\(providerID)", canonicalName: "Target \(providerID)",
            category: "park", latitude: 10, longitude: 11,
            sourceProvider: "fixture", sourceProviderPlaceID: providerID)
        let save = Self.save("target-save-\(providerID)", place: place, owner: owner, status: .been)
        return VisiblePlace(id: save.id, place: place, userPlace: save, owner: owner)
    }
}

@MainActor
private final class BookmarkWatchRepository: UserPlaceRepository {
    let rows: [VisiblePlace]
    init(rows: [VisiblePlace]) { self.rows = rows }
    func userPlaces(for userID: String, filters: PlaceFilters) async throws -> [VisiblePlace] { rows }
    func save(_ draft: UserPlaceDraft) async throws -> SaveResult { throw URLError(.unsupportedURL) }
    func updateVisibility(userPlaceID: String, visibility: PlaceVisibility) async throws {}
    func delete(userPlaceID: String) async throws {}
}

@MainActor
private final class BookmarkWatchReads {
    var fromBookmarkObserver: [ActivityBookmarkState] = []
    var fromModelObserver: [ActivityBookmarkState] = []
    var refreshAdmissions: [Bool] = []
    var context: WanderStore.AutomaticImportProjectionContext?
}

private final class BookmarkWatchCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
