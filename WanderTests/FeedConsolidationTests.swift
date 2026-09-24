import XCTest
@testable import Wander

@MainActor final class FeedConsolidationTests: XCTestCase {
    func testPossessivePlaceSearchResolvesFirstNameAndFullNameInBothStages() async {
        let fixtures = ownerSearchFixtures()
        let store = WanderStore(fixtures: fixtures)
        for query in ["joe's favorite coffee", "Joe’s favorite coffee", "Joes favorite coffee", "show me Joe Lipshutz's favorite coffee", "List Joe’s favorite coffee", "Tell me about Joe’s favorite coffee", "what's Joe's favorite coffee"] {
            let immediate = store.searchTrustedPlaces(query: query)
            let refined = await store.discover(query: query, includeProfiles: false)
            for results in [immediate, refined] {
                XCTAssertEqual(Set(results.places.map(\.userPlace.id)), ["up_joe_woodcat", "up_joe_circuit_coffee"], query)
                XCTAssertTrue(results.places.allSatisfy { $0.owner.id == fixtures.currentUser.id }, query)
                XCTAssertTrue(results.places.allSatisfy { $0.userPlace.status == .been && ($0.userPlace.ratingScore ?? 0) >= 4 }, query)
                XCTAssertTrue(results.evidenceByUserPlaceID.values.allSatisfy { $0.ownerID == fixtures.currentUser.id }, query)
            }
        }
    }

    func testRefinementCannotOmitOrSubstituteAnExplicitOwner() async {
        for remoteOwner in [nil, "maya"] as [String?] {
            let parser = RemoteDiscoverFilterParser(repository: OwnerSearchFilterRepository(ownerQuery: remoteOwner))
            let store = WanderStore(fixtures: ownerSearchFixtures(), parser: parser)
            let query = "Joe's favorite coffee"
            let immediate = store.searchTrustedPlaces(query: query)
            let refined = await store.discover(query: query, includeProfiles: false)
            XCTAssertEqual(refined.parseSource, .remote)
            XCTAssertEqual(refined.filters.ownerQuery, "joe")
            XCTAssertEqual(Set(refined.places.map(\.userPlace.id)), Set(immediate.places.map(\.userPlace.id)))
            XCTAssertFalse(refined.places.isEmpty)
            XCTAssertTrue(refined.places.allSatisfy { $0.owner.id == "user_joe" })
        }
    }

    func testFailedRefinementRetainsDeterministicOwnerAndFavoriteFilters() async {
        let store = WanderStore(fixtures: ownerSearchFixtures(), parser: FailingOwnerSearchParser())
        let results = await store.discover(query: "Joe's favorite coffee", includeProfiles: false)
        XCTAssertEqual(results.parseSource, .deterministicFallback)
        XCTAssertEqual(results.filters.ownerQuery, "joe")
        XCTAssertEqual(results.filters.opinion, .favorite)
        XCTAssertEqual(Set(results.places.map(\.userPlace.id)), ["up_joe_woodcat", "up_joe_circuit_coffee"])
    }

    func testOwnerFavoriteSearchCannotBorrowAnotherPersonsRatingOrWannaGoSave() async {
        let fixtures = ownerSearchFixtures()
        fixtures.userPlaces.first { $0.id == "up_joe_woodcat" }?.ratingScore = 2
        fixtures.userPlaces.first { $0.id == "up_joe_circuit_coffee" }?.statusRaw = PlaceStatus.wannaGo.rawValue
        let store = WanderStore(fixtures: fixtures)
        XCTAssertTrue(store.searchTrustedPlaces(query: "Joe's favorite coffee").places.isEmpty)
        let refined = await store.discover(query: "Joe's favorite coffee", includeProfiles: false)
        XCTAssertTrue(refined.places.isEmpty)
    }

    func testOwnerAmbiguityIncludesSelfAndUsesTheSameNameMatchingAsResults() throws {
        let fixtures = ownerSearchFixtures()
        let otherJoe = try XCTUnwrap(fixtures.profiles.first { $0.id == "user_ryan" })
        otherJoe.displayName = "Joe Ramirez"
        let store = WanderStore(fixtures: fixtures)
        let results = store.searchTrustedPlaces(query: "Joe's favorite coffee")
        let candidates = store.discoverOwnerCandidates(for: results.filters)
        XCTAssertEqual(Set(candidates.map(\.id)), ["user_joe", "user_ryan"])
        XCTAssertEqual(Set(results.places.map(\.owner.id)), Set(candidates.map(\.id)))

        let exactHandle = store.searchTrustedPlaces(query: "@ryan's favorite coffee")
        XCTAssertEqual(store.discoverOwnerCandidates(for: exactHandle.filters).map(\.id), ["user_ryan"])
        XCTAssertEqual(Set(exactHandle.places.map(\.owner.id)), ["user_ryan"])
        XCTAssertTrue(store.searchTrustedPlaces(query: "@joe favorite coffee").places.isEmpty)
        XCTAssertTrue(store.searchTrustedPlaces(query: "Joey's favorite coffee").places.isEmpty)
    }

    func testPossessiveSearchDoesNotFallThroughToUnscopedProviders() async {
        let store = WanderStore(fixtures: ownerSearchFixtures())
        let query = "Joe's favorite coffee"
        let results = store.searchTrustedPlaces(query: query)
        let communityRequest = await store.recmePlaceSearchRequest(query: query)
        XCTAssertNil(communityRequest)
        XCTAssertNil(DiscoverExternalPlaceSearchPlanner.input(query: query, filters: results.filters))
    }

    private func ownerSearchFixtures() -> WanderFixtures {
        let fixtures = WanderFixtures.seed()
        fixtures.currentUser.displayName = "Joe Lipshutz"
        fixtures.currentUser.handle = "joelipshutz"
        return fixtures
    }

    private func person(_ name: String) -> ProfileShell {
        ProfileShell(id: name.lowercased(), handle: name.lowercased(), displayName: name,
                     avatarURL: nil, bio: nil, relationship: .nonFollower)
    }

    func testPeopleSearchNormalizesNamesAndHandlesAndIncludesRemoteAccounts() async {
        let search = PeopleSearchModel()
        let dana = person("Dana")
        await search.search(query: " @DaNa ", local: { _ in [] }, remote: { query in
            XCTAssertEqual(query, "dana")
            return [dana]
        }, debounce: .zero)
        XCTAssertEqual(search.profiles, [dana])
        XCTAssertFalse(search.failed)
        XCTAssertFalse(search.isLoading)
        var called = false
        await search.search(query: "r", local: { _ in [] }, remote: { _ in called = true; return [] }, debounce: .zero)
        XCTAssertFalse(called)
        XCTAssertTrue(search.profiles.isEmpty)
    }

    func testEarlierPeopleSearchCannotOverwriteNewQueryOrClearedResults() async {
        let search = PeopleSearchModel()
        let dana = person("Dana")
        let ryan = person("Ryan")
        var pending: CheckedContinuation<[ProfileShell], Error>?
        let old = Task {
            await search.search(query: "dana", local: { _ in [dana] }, remote: { _ in
                try await withCheckedThrowingContinuation { pending = $0 }
            }, debounce: .zero)
        }
        for _ in 0..<1000 where pending == nil { await Task.yield() }
        XCTAssertNotNil(pending)
        await search.search(query: "ryan", local: { _ in [ryan] }, remote: { _ in [ryan] }, debounce: .zero)
        XCTAssertEqual(search.profiles, [ryan])
        await search.search(query: "", local: { _ in [] }, remote: { _ in XCTFail("Empty query fetched"); return [] }, debounce: .zero)
        pending?.resume(returning: [dana])
        await old.value
        XCTAssertTrue(search.profiles.isEmpty)
        XCTAssertFalse(search.isLoading)
    }

    func testPeopleSearchFailureKeepsLocalResultsAndRecovers() async {
        let search = PeopleSearchModel()
        let ryan = person("Ryan")
        await search.search(query: "ryan", local: { _ in [ryan] }, remote: { _ in
            throw URLError(.notConnectedToInternet)
        }, debounce: .zero)
        XCTAssertEqual(search.profiles, [ryan])
        XCTAssertTrue(search.failed)
        await search.search(query: "ryan", local: { _ in [] }, remote: { _ in [ryan] }, debounce: .zero)
        XCTAssertFalse(search.failed)
        XCTAssertEqual(search.profiles, [ryan])
    }

    func testFollowBadgeSharesAcknowledgementAndDistinguishesRefollows() {
        let suite = "FeedConsolidationTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let badge = NotificationBadgeStore(defaults: defaults)
        let follow = makeFollow()
        let snapshot = NotificationBadgeSnapshot(userID: "joe", plans: [], checkIns: [], follows: [follow, follow])
        XCTAssertEqual(badge.count(for: snapshot), 1)
        badge.open(snapshot)
        XCTAssertEqual(badge.count(for: snapshot), 0)
        badge.close()
        let refollow = NotificationBadgeSnapshot(userID: "joe", plans: [], checkIns: [], follows: [follow, makeFollow()])
        XCTAssertEqual(badge.count(for: refollow), 1)
        let otherUser = NotificationBadgeSnapshot(userID: "other", plans: [], checkIns: [], follows: [follow])
        XCTAssertEqual(badge.count(for: otherUser), 1)
    }

    func testFollowInboxDiscardsLateAccountResultsAndCanRetryFailure() async {
        let inbox = FollowNotificationInbox()
        let repository = FollowInboxTestRepository()
        repository.suspend = true
        let request = Task { await inbox.refresh(userID: "first", repository: repository) }
        for _ in 0..<1000 where repository.pending == nil { await Task.yield() }
        XCTAssertNotNil(repository.pending)
        inbox.reset(for: "second")
        inbox.reset(for: "first")
        repository.pending?.resume(returning: [makeFollow()])
        await request.value
        XCTAssertTrue(inbox.notifications.isEmpty)
        XCTAssertFalse(inbox.isLoading)
        await inbox.refresh(userID: "first", repository: nil)
        XCTAssertTrue(inbox.failed)
        repository.suspend = false
        await inbox.refresh(userID: "first", repository: repository)
        XCTAssertFalse(inbox.failed)
        XCTAssertEqual(inbox.notifications.count, 1)
    }
}

private struct OwnerSearchFilterRepository: DiscoverFilterParsingRepository {
    let ownerQuery: String?

    func parseFilters(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        DiscoverFilters(query: query, categories: [WanderPlaceCategory.coffeeTeaSweets], ownerQuery: ownerQuery)
    }
}

private struct FailingOwnerSearchParser: LLMFilterParser {
    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        throw URLError(.notConnectedToInternet)
    }
}

private func makeFollow() -> FollowNotification {
    FollowNotification(id: UUID(), actorID: "ryan", displayName: "Ryan", handle: "ryan",
                       avatarURL: nil, createdAt: .now, isMutual: false)
}

@MainActor private final class FollowInboxTestRepository: FollowNotificationRepository {
    var suspend = false
    var pending: CheckedContinuation<[FollowNotification], Error>?
    func receivedFollows() async throws -> [FollowNotification] {
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return [makeFollow()]
    }
}
