import XCTest
import Combine
@testable import Wander

@MainActor
final class LiveMapPinStateLoaderTests: XCTestCase {
    private let placeID = "00000000-0000-0000-0000-000000000001"
    private let additionalPlaceID = "00000000-0000-0000-0000-000000000002"

    func testRepeatedEmptyResetsAndMissingRepositoryLoadsDoNotPublish() async {
        let loader = LiveMapPinStateLoader()
        var snapshotPublications = 0
        var revisionPublications = 0
        var objectPublications = 0
        let observations = [
            loader.$snapshot.dropFirst().sink { _ in snapshotPublications += 1 },
            loader.$revision.dropFirst().sink { _ in revisionPublications += 1 },
            loader.objectWillChange.sink { _ in objectPublications += 1 }
        ]
        defer { observations.forEach { $0.cancel() } }
        for revision in 1...30 {
            loader.reset()
            await loader.load(request: nil, repository: nil)
            await loader.load(request: request(resultRevision: UInt64(revision)), repository: nil)
        }
        XCTAssertNil(loader.snapshot)
        XCTAssertEqual(loader.revision, 0)
        XCTAssertEqual(snapshotPublications, 0)
        XCTAssertEqual(revisionPublications, 0)
        XCTAssertEqual(objectPublications, 0)
    }

    func testResolvedReceiptPublishesOneClearBeforeEmptyResetsBecomeSilent() async {
        let loader = LiveMapPinStateLoader()
        await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
        let revision = loader.revision
        var clearedSnapshots = 0
        var revisions: [UInt64] = []
        let observations = [
            loader.$snapshot.dropFirst().sink { value in
                XCTAssertNil(value)
                clearedSnapshots += 1
            },
            loader.$revision.dropFirst().sink { revisions.append($0) }
        ]
        defer { observations.forEach { $0.cancel() } }
        await loader.load(request: request(), repository: nil)
        XCTAssertNil(loader.snapshot)
        XCTAssertEqual(clearedSnapshots, 1)
        XCTAssertEqual(revisions, [revision + 1])
        loader.reset()
        await loader.load(request: nil, repository: nil)
        loader.revalidate(now: Date.now.addingTimeInterval(901))
        XCTAssertEqual(clearedSnapshots, 1)
        XCTAssertEqual(revisions, [revision + 1])
    }

    func testSilentEmptyResetStillRejectsLateSuccessAndFailure() async {
        for fails in [false, true] {
            let loader = LiveMapPinStateLoader()
            let gate = DeferredStateRepository()
            let pending = Task { await loader.load(request: request(), repository: gate) }
            await gate.waitUntilRequested()
            XCTAssertNil(loader.snapshot)
            loader.reset()
            XCTAssertEqual(loader.revision, 0)
            gate.resolve(fails ? .failure(WanderRemoteError.invalidResponse("Unavailable"))
                : .success(snapshot(hasList: true)))
            await pending.value
            XCTAssertNil(loader.snapshot, "A silent reset must still fence the uncancelled old request.")
            XCTAssertEqual(loader.revision, 0)
            let current = snapshot(saves: [ownSave])
            await loader.load(request: request(storeRevision: 2), repository: Stub { _ in current })
            XCTAssertEqual(loader.snapshot, current)
            XCTAssertEqual(loader.revision, 1)
        }
    }

    func testCompleteStateIsClearedWhenRepositoryOrAccountScopeDisappears() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot()
        await loader.load(request: request(), repository: Stub { _ in expected })
        XCTAssertEqual(loader.snapshot, expected)
        await loader.load(request: nil, repository: nil)
        XCTAssertNil(loader.snapshot)
    }

    func testPartialDuplicateAndMismatchedResponsesNeverBecomeAbsenceEvidence() async {
        let state = snapshot().states[0]
        let invalid = [LiveMapPinStateSnapshot(states: [], complete: true),
                       LiveMapPinStateSnapshot(states: [state, state], complete: true),
                       LiveMapPinStateSnapshot(states: [state], complete: false),
                       LiveMapPinStateSnapshot(states: [state], complete: true),
                       LiveMapPinStateSnapshot(states: [.init(placeID: additionalPlaceID,
                           saves: [], hasListMembership: false)], complete: true, fetchedAt: .now)]
        for result in invalid {
            let loader = LiveMapPinStateLoader()
            await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
            await loader.load(request: request(refresh: 1), repository: Stub { _ in result })
            XCTAssertNil(loader.snapshot)
        }
    }

    func testSameAccountViewportAndResultReloadKeepsReceiptUntilAtomicReplacement() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot(hasList: true, saves: [ownSave])
        await loader.load(request: request(), repository: Stub { _ in expected })
        let revision = loader.revision
        let gate = DeferredStateRepository()
        let next = request(resultRevision: 2, viewport: .init(minLatitude: 30, minLongitude: -120,
            maxLatitude: 40, maxLongitude: -110), refresh: 1)
        let replacement = Task { await loader.load(request: next, repository: gate) }
        await gate.waitUntilRequested()
        XCTAssertEqual(loader.snapshot, expected)
        XCTAssertEqual(loader.revision, revision, "Starting a same-scope read must not publish neutral state.")

        let removed = snapshot()
        gate.resolve(.success(removed))
        await replacement.value
        XCTAssertEqual(loader.snapshot, removed)
        let state = state(snapshot: loader.snapshot)
        XCTAssertTrue(state.rails.isEmpty)
        XCTAssertFalse(state.hasSavedStatus)
        XCTAssertFalse(state.hasListMembership, "A complete removal replaces the previous positive receipt.")
    }

    func testAdditionalCanonicalIDsStayUnknownWhileCoveredPinsKeepTheirReceipt() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot(saves: [ownSave])
        await loader.load(request: request(), repository: Stub { _ in expected })
        let gate = DeferredStateRepository()
        let replacement = Task {
            await loader.load(request: request(ids: [placeID, additionalPlaceID]), repository: gate)
        }
        await gate.waitUntilRequested()
        XCTAssertTrue(state(snapshot: loader.snapshot).hasSavedStatus)
        XCTAssertEqual(state(snapshot: loader.snapshot, ids: [additionalPlaceID], featured: true), .empty)
        XCTAssertEqual(state(snapshot: loader.snapshot, ids: [placeID, additionalPlaceID], featured: true), .empty,
                       "Every persisted ID of a canonical pin needs coverage before its absence is proven.")
        let complete = LiveMapPinStateSnapshot(states: expected.states + [
            .init(placeID: additionalPlaceID, saves: [], hasListMembership: false)
        ], complete: true, fetchedAt: .now)
        gate.resolve(.success(complete))
        await replacement.value
        XCTAssertTrue(state(snapshot: loader.snapshot, ids: [additionalPlaceID], featured: true).isFeatured)
    }

    func testRetainedFactsImmediatelyFollowPeopleAndActivityFilters() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot(saves: [ownSave,
            .init(ownerID: "friend", hasBeen: true, hasWanna: false, isFriend: true)])
        await loader.load(request: request(), repository: Stub { _ in expected })
        let query = LiveFeedQuery(activityType: .wannas, personIDs: ["viewer"])
        let gate = DeferredStateRepository()
        let replacement = Task { await loader.load(request: request(query: query), repository: gate) }
        await gate.waitUntilRequested()
        XCTAssertEqual(state(snapshot: loader.snapshot, query: query).rails,
                       [MapPinOutline(ownership: .currentUser, status: .wannaGo)])
        let excluded = state(snapshot: loader.snapshot,
            query: .init(activityType: .wannas, personIDs: ["friend"]), featured: true)
        XCTAssertTrue(excluded.rails.isEmpty)
        XCTAssertFalse(excluded.isFeatured, "Filtered-out saves still prevent false Featured.")
        gate.resolve(.success(expected))
        await replacement.value
    }

    func testEmptySameScopeWindowRetainsReceiptWithoutCallingRepositoryOrExtendingExpiry() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot(hasList: true)
        await loader.load(request: request(), repository: Stub { _ in expected })
        await loader.load(request: request(ids: [], resultRevision: 2), repository: Stub { _ in
            XCTFail("An empty enumeration window needs no state RPC.")
            return expected
        })
        XCTAssertEqual(loader.snapshot, expected)
        loader.revalidate(now: Date.now.addingTimeInterval(901))
        XCTAssertNil(loader.snapshot)
    }

    func testAccountAndStoreChangesClearReceiptBeforeReplacementReturns() async {
        for changed in [request(user: "other"), request(storeRevision: 2)] {
            let loader = LiveMapPinStateLoader()
            let expected = snapshot(hasList: true)
            await loader.load(request: request(), repository: Stub { _ in expected })
            let gate = DeferredStateRepository()
            let replacement = Task { await loader.load(request: changed, repository: gate) }
            await gate.waitUntilRequested()
            XCTAssertNil(loader.snapshot)
            gate.resolve(.success(snapshot()))
            await replacement.value
        }
    }

    func testRepositoryLossClearsReceiptEvenWhenRequestAndAccountRemain() async {
        let loader = LiveMapPinStateLoader()
        await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
        await loader.load(request: request(), repository: nil)
        XCTAssertNil(loader.snapshot)
    }

    func testCanceledReplacementKeepsReceiptUntilOriginalExpiry() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot(hasList: true)
        await loader.load(request: request(), repository: Stub { _ in expected })
        let gate = DeferredStateRepository()
        let replacement = Task { await loader.load(request: request(resultRevision: 2, refresh: 1), repository: gate) }
        await gate.waitUntilRequested()
        replacement.cancel()
        gate.resolve(.failure(CancellationError()))
        await replacement.value
        XCTAssertEqual(loader.snapshot, expected)
        loader.revalidate(now: Date.now.addingTimeInterval(901))
        XCTAssertNil(loader.snapshot)
    }

    func testCanceledOldResponseOrFailureCannotClearNewReceipt() async {
        for fails in [false, true] {
            let loader = LiveMapPinStateLoader()
            let gate = DeferredStateRepository()
            let first = Task { await loader.load(request: request(), repository: gate) }
            await gate.waitUntilRequested()
            first.cancel()
            let current = snapshot(hasList: true)
            await loader.load(request: request(resultRevision: 2), repository: Stub { _ in current })
            gate.resolve(fails ? .failure(CancellationError()) : .success(snapshot()))
            await first.value
            XCTAssertEqual(loader.snapshot, current)
        }
    }

    func testStoreResetRejectsLateSuccessAndFailureWithoutClearingNewReceipt() async {
        for fails in [false, true] {
            let loader = LiveMapPinStateLoader()
            let gate = DeferredStateRepository()
            let old = Task { await loader.load(request: request(), repository: gate) }
            await gate.waitUntilRequested()
            loader.reset()
            let current = snapshot(hasList: true)
            await loader.load(request: request(storeRevision: 2), repository: Stub { _ in current })
            gate.resolve(fails ? .failure(WanderRemoteError.invalidResponse("Unavailable")) : .success(snapshot()))
            await old.value
            XCTAssertEqual(loader.snapshot, current)
        }
    }

    func testOriginalTimerExpiresDuringReplacementAndFreshResponseCanStillArrive() async {
        let loader = LiveMapPinStateLoader(duration: .milliseconds(100))
        let expired = expectation(description: "Original receipt expires while replacement waits")
        let observation = loader.$snapshot.dropFirst().sink { if $0 == nil { expired.fulfill() } }
        await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
        let gate = DeferredStateRepository()
        let replacement = Task { await loader.load(request: request(resultRevision: 2, refresh: 1), repository: gate) }
        await gate.waitUntilRequested()
        let outcome = await XCTWaiter.fulfillment(of: [expired], timeout: 2)
        XCTAssertEqual(outcome, .completed)
        XCTAssertNil(loader.snapshot)
        observation.cancel()

        let fresh = snapshot(saves: [ownSave])
        gate.resolve(.success(fresh))
        await replacement.value
        XCTAssertEqual(loader.snapshot, fresh, "Expiry invalidates the old receipt, not the current request.")
    }

    func testForegroundExpiryDuringReplacementDoesNotLetOldReceiptReturn() async {
        let loader = LiveMapPinStateLoader()
        await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
        let gate = DeferredStateRepository()
        let replacement = Task { await loader.load(request: request(resultRevision: 2, refresh: 1), repository: gate) }
        await gate.waitUntilRequested()
        loader.revalidate(now: Date.now.addingTimeInterval(901))
        XCTAssertNil(loader.snapshot)
        replacement.cancel()
        gate.resolve(.success(snapshot(hasList: true)))
        await replacement.value
        XCTAssertNil(loader.snapshot)
    }

    func testLateOldAccountResponseCannotReplaceNewAccountEvidence() async {
        let loader = LiveMapPinStateLoader()
        var resume: CheckedContinuation<LiveMapPinStateSnapshot, Never>?
        let old = Stub { _ in await withCheckedContinuation { resume = $0 } }
        let first = Task { await loader.load(request: request(user: "old"), repository: old) }
        for _ in 0..<100 where resume == nil { await Task.yield() }
        XCTAssertNotNil(resume)
        let current = snapshot(hasList: true)
        await loader.load(request: request(user: "new"), repository: Stub { _ in current })
        resume?.resume(returning: snapshot())
        await first.value
        XCTAssertEqual(loader.snapshot, current)
    }

    func testFailureDiscardsPreviousCompleteState() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot()
        await loader.load(request: request(), repository: Stub { _ in expected })
        await loader.load(request: request(refresh: 1), repository: Stub { _ in
            throw WanderRemoteError.invalidResponse("Unavailable")
        })
        XCTAssertNil(loader.snapshot)
    }

    func testAuthorizationLeaseExpiresWithoutPersistingFacts() async throws {
        let loader = LiveMapPinStateLoader(duration: .milliseconds(1))
        let expected = snapshot()
        await loader.load(request: request(), repository: Stub { _ in expected })
        XCTAssertEqual(loader.snapshot, expected)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(loader.snapshot)
    }

    func testAlreadyExpiredOrImplausiblyFutureResponseCannotRefreshAuthorization() async {
        for date in [Date.now.addingTimeInterval(-901), Date.now.addingTimeInterval(31)] {
            let loader = LiveMapPinStateLoader()
            await loader.load(request: request(), repository: Stub { _ in self.snapshot(hasList: true) })
            let result = LiveMapPinStateSnapshot(states: snapshot().states, complete: true, fetchedAt: date)
            await loader.load(request: request(refresh: 1), repository: Stub { _ in result })
            XCTAssertNil(loader.snapshot)
        }
    }

    func testForegroundRevalidationExpiresEvidenceBeforeSuspendedTimerRuns() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot()
        await loader.load(request: request(), repository: Stub { _ in expected })
        loader.revalidate()
        XCTAssertEqual(loader.snapshot, expected)
        let revision = loader.revision
        loader.revalidate(now: Date.now.addingTimeInterval(901))
        XCTAssertNil(loader.snapshot)
        XCTAssertGreaterThan(loader.revision, revision)
    }

    func testEquivalentResultRevisionReusesEvidenceAndForcedRefreshKeepsItWhilePending() async {
        let loader = LiveMapPinStateLoader()
        let expected = snapshot()
        var calls = 0
        await loader.load(request: request(), repository: Stub { _ in calls += 1; return expected })
        await loader.load(request: request(resultRevision: 2), repository: Stub { _ in calls += 1; return expected })
        XCTAssertEqual(calls, 1)
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { await loader.load(request: request(refresh: 1), repository: Stub { _ in
            await withCheckedContinuation { continuation = $0 }; return expected
        }) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        XCTAssertEqual(loader.snapshot, expected)
        continuation?.resume(); await task.value
        XCTAssertEqual(loader.snapshot, expected)
    }

    func testCancelledExpandedRequestCannotClaimTheOldSnapshotCoversNewPlaces() async {
        let loader = LiveMapPinStateLoader()
        let initial = request()
        await loader.load(request: initial, repository: Stub { _ in self.snapshot() })
        let secondID = UUID().uuidString.lowercased()
        let expanded = LiveMapPinStateRequest(map: initial.map, placeIDs: initial.placeIDs + [secondID],
                                             resultRevision: 2, storeRevision: initial.storeRevision)
        let full = LiveMapPinStateSnapshot(states: snapshot().states + [.init(placeID: secondID, saves: [], hasListMembership: false)],
                                          complete: true, fetchedAt: .now)
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { await loader.load(request: expanded, repository: Stub { _ in
            await withCheckedContinuation { continuation = $0 }; return full
        }) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        task.cancel()
        var calls = 0
        await loader.load(request: expanded, repository: Stub { _ in calls += 1; return full })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(loader.snapshot, full)
        continuation?.resume(); await task.value
        XCTAssertEqual(loader.snapshot, full)
    }

    func testReusedReceiptRejectsSupersededPendingResponseWithoutRenewingExpiry() async {
        for fails in [false, true] {
            let loader = LiveMapPinStateLoader()
            let expected = snapshot(hasList: true)
            await loader.load(request: request(), repository: Stub { _ in expected })
            let gate = DeferredStateRepository()
            let pending = Task { await loader.load(request: request(refresh: 1), repository: gate) }
            await gate.waitUntilRequested()

            let revision = loader.revision
            await loader.load(request: request(resultRevision: 2), repository: Stub { _ in
                XCTFail("The original request can reuse its accepted receipt.")
                return expected
            })
            XCTAssertEqual(loader.revision, revision)
            gate.resolve(fails ? .failure(WanderRemoteError.invalidResponse("Unavailable")) : .success(snapshot()))
            await pending.value
            XCTAssertEqual(loader.snapshot, expected, "Superseded success or failure must not alter reused evidence.")
            loader.revalidate(now: Date.now.addingTimeInterval(901))
            XCTAssertNil(loader.snapshot)
        }
    }

    private var ownSave: LiveMapPinSaveState {
        .init(ownerID: "viewer", hasBeen: true, hasWanna: true, isFriend: false)
    }

    private func snapshot(hasList: Bool = false, saves: [LiveMapPinSaveState] = []) -> LiveMapPinStateSnapshot {
        .init(states: [.init(placeID: placeID, saves: saves, hasListMembership: hasList)], complete: true, fetchedAt: .now)
    }

    private func request(user: String = "viewer", ids: [String]? = nil, resultRevision: UInt64 = 1,
                         storeRevision: UInt64 = 1, query: LiveFeedQuery = .init(),
                         viewport: MapViewport? = nil, refresh: UInt64 = 0) -> LiveMapPinStateRequest {
        .init(map: .init(userID: user, audience: .everyone, query: query, featured: true,
                        viewport: viewport, refresh: refresh), placeIDs: ids ?? [placeID],
              resultRevision: resultRevision, storeRevision: storeRevision)
    }

    private func state(snapshot: LiveMapPinStateSnapshot?, ids: [String]? = nil,
                       query: LiveFeedQuery = .init(), featured: Bool = false) -> LiveTotemState {
        let identity = LivePlaceIdentity(places: (ids ?? [placeID]).map {
            LocalPlace(localID: $0, canonicalName: "Example", category: "coffee", latitude: 0, longitude: 0)
        })
        return LiveTotemContext(currentUserID: "viewer", query: query, currentSavedPlaces: [],
            currentListPlaces: [], authoritativeState: snapshot, allowsCachedAssociations: false)
            .state(for: identity, activities: [], featured: featured)
    }

    private struct Stub: LiveMapPinStateRepository {
        let body: ([String]) async throws -> LiveMapPinStateSnapshot
        func liveMapPinStates(placeIDs: [String]) async throws -> LiveMapPinStateSnapshot {
            try await body(placeIDs)
        }
    }
}

@MainActor
private final class DeferredStateRepository: LiveMapPinStateRepository {
    private let requested = XCTestExpectation(description: "Pin state request started")
    private var continuations: [CheckedContinuation<LiveMapPinStateSnapshot, Error>] = []
    private var result: Result<LiveMapPinStateSnapshot, Error>?

    func liveMapPinStates(placeIDs: [String]) async throws -> LiveMapPinStateSnapshot {
        requested.fulfill()
        return try await withCheckedThrowingContinuation { continuation in
            if let result { continuation.resume(with: result) }
            else { continuations.append(continuation) }
        }
    }

    func waitUntilRequested() async {
        let outcome = await XCTWaiter.fulfillment(of: [requested], timeout: 2)
        XCTAssertEqual(outcome, .completed)
    }

    func resolve(_ result: Result<LiveMapPinStateSnapshot, Error>) {
        self.result = result
        let pending = continuations
        continuations = []
        for continuation in pending { continuation.resume(with: result) }
    }
}
