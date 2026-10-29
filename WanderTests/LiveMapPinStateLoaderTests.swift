import XCTest
@testable import Wander

@MainActor
final class LiveMapPinStateLoaderTests: XCTestCase {
    private let placeID = "00000000-0000-0000-0000-000000000001"

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
                       LiveMapPinStateSnapshot(states: [state], complete: false)]
        for result in invalid {
            let loader = LiveMapPinStateLoader()
            await loader.load(request: request(), repository: Stub { _ in result })
            XCTAssertNil(loader.snapshot)
        }
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
            let result = LiveMapPinStateSnapshot(states: snapshot().states, complete: true, fetchedAt: date)
            await loader.load(request: request(), repository: Stub { _ in result })
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
        await loader.load(request: request(), repository: Stub { _ in calls += 1; return expected })
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

    private func snapshot(hasList: Bool = false) -> LiveMapPinStateSnapshot {
        .init(states: [.init(placeID: placeID, saves: [], hasListMembership: hasList)], complete: true, fetchedAt: .now)
    }

    private func request(user: String = "viewer", refresh: UInt64 = 0) -> LiveMapPinStateRequest {
        .init(map: .init(userID: user, audience: .everyone, query: .init(), featured: true,
                        viewport: nil, refresh: refresh), placeIDs: [placeID], resultRevision: 1, storeRevision: 1)
    }

    private struct Stub: LiveMapPinStateRepository {
        let body: ([String]) async throws -> LiveMapPinStateSnapshot
        func liveMapPinStates(placeIDs: [String]) async throws -> LiveMapPinStateSnapshot {
            try await body(placeIDs)
        }
    }
}
