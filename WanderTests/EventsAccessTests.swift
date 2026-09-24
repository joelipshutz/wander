import XCTest
@testable import Wander

@MainActor final class EventsAccessTests: XCTestCase {
    func testOnlySavedLAHomeGetsEventsAndTabOrderIsStable() {
        XCTAssertEqual(EventsAccessPolicy.availableTabs(metroID: "los-angeles"), [.map,.discover,.events,.lists,.profile])
        for metro in [nil, "orange-county", "inland-empire", "new-york", "other", "invalid"] {
            XCTAssertFalse(EventsAccessPolicy.isEligible(metroID: metro))
            XCTAssertEqual(EventsAccessPolicy.availableTabs(metroID: metro), [.map,.discover,.lists,.profile])
        }
    }

    func testHiddenEventsDestinationFallsBackToFeedOnly() {
        XCTAssertEqual(EventsAccessPolicy.resolvedTab(.events, metroID: nil), .discover)
        XCTAssertEqual(EventsAccessPolicy.resolvedTab(.events, metroID: "los-angeles"), .events)
        for tab in [WanderTab.map, .discover, .lists, .profile] {
            XCTAssertEqual(EventsAccessPolicy.resolvedTab(tab, metroID: nil), tab)
        }
        XCTAssertEqual(FirstVisitWalkthroughContent.primaryJourneySurfaces, [.map, .feed])
        XCTAssertTrue(FirstVisitWalkthroughContent.stepsBySurface[.events, default: []].isEmpty)
    }

    func testSavedHomeWorksOfflineAndNeverLeaksAcrossAccounts() async {
        let cache = makeCache()
        cache.remember("los-angeles", for: "owner")
        let model = EventsAccessModel(userID: "owner", cache: cache)
        XCTAssertEqual(model.homeMetro(for: "owner"), "los-angeles")
        XCTAssertNil(model.homeMetro(for: "other"))
        let repository = AccessRepository()
        repository.fails = true
        await model.load(userID: "owner", repository: repository)
        XCTAssertEqual(model.homeMetro(for: "owner"), "los-angeles")
        await model.load(userID: nil, repository: repository)
        XCTAssertNil(model.homeMetro(for: nil))
        await model.load(userID: "other", repository: repository)
        XCTAssertNil(model.homeMetro(for: "other"))
    }

    func testRemoteOutsideHomeRemovesCachedLA() async {
        let cache = makeCache()
        cache.remember("los-angeles", for: "owner")
        let model = EventsAccessModel(userID: "owner", cache: cache)
        let repository = AccessRepository()
        repository.value = .init(metroID: "orange-county")
        await model.load(userID: "owner", repository: repository)
        XCTAssertEqual(model.homeMetro(for: "owner"), "orange-county")
        XCTAssertEqual(cache.metroID(for: "owner"), "orange-county")
        repository.value = nil
        await model.load(userID: "owner", repository: repository)
        XCTAssertNil(model.homeMetro(for: "owner"))
        XCTAssertNil(cache.metroID(for: "owner"))
    }

    func testSettingsSaveBeatsStaleRemoteRead() async {
        let cache = makeCache()
        let model = EventsAccessModel(userID: "owner", cache: cache)
        let repository = DeferredAccessRepository()
        let load = Task { await model.load(userID: "owner", repository: repository) }
        while repository.continuation == nil { await Task.yield() }
        cache.remember("new-york", for: "owner")
        model.cachedSelectionDidChange(userID: "owner")
        repository.continuation?.resume(returning: .init(metroID: "los-angeles"))
        await load.value
        XCTAssertEqual(model.homeMetro(for: "owner"), "new-york")
        XCTAssertEqual(cache.metroID(for: "owner"), "new-york")
    }

    func testAccountSwitchDiscardsLateAccessResponse() async {
        let cache = makeCache()
        let model = EventsAccessModel(userID: "owner", cache: cache)
        let repository = DeferredAccessRepository()
        let load = Task { await model.load(userID: "owner", repository: repository) }
        while repository.continuation == nil { await Task.yield() }
        await model.load(userID: "other", repository: nil)
        repository.continuation?.resume(returning: .init(metroID: "los-angeles"))
        await load.value
        XCTAssertNil(model.homeMetro(for: "other"))
        XCTAssertNil(cache.metroID(for: "owner"))
    }

    private func makeCache() -> HomeMetroSelectionStore {
        let suite = "EventsAccessTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return HomeMetroSelectionStore(defaults: defaults)
    }
}

@MainActor private final class AccessRepository: EventsAccessRepository {
    var value: EventsMarketAccess?
    var fails = false
    func currentAccess() async throws -> EventsMarketAccess? {
        if fails { throw URLError(.notConnectedToInternet) }
        return value
    }
}

@MainActor private final class DeferredAccessRepository: EventsAccessRepository {
    var continuation: CheckedContinuation<EventsMarketAccess?, Never>?
    func currentAccess() async throws -> EventsMarketAccess? {
        await withCheckedContinuation { continuation = $0 }
    }
}
