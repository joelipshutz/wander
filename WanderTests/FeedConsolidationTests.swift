import XCTest
@testable import Wander

@MainActor final class FeedConsolidationTests: XCTestCase {
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
