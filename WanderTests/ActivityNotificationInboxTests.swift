import XCTest
@testable import Wander

@MainActor final class ActivityNotificationInboxTests: XCTestCase {
    func testRefreshSortsDeduplicatesAndDropsUnsupportedOrUnroutableEvents() async {
        let inbox = ActivityNotificationInbox()
        let recent = row(createdAt: Date(timeIntervalSince1970: 200))
        let old = row(createdAt: Date(timeIntervalSince1970: 100))
        let repository = ActivityInboxTestRepository(rows: [old, recent, recent,
            row(type: "unknown"), row(data: [:])])
        await inbox.refresh(userID: "recipient", repository: repository)
        XCTAssertEqual(inbox.notifications, [recent, old])
        XCTAssertEqual(repository.requestedUsers, ["recipient"])
        XCTAssertFalse(inbox.failed)
        XCTAssertFalse(inbox.isLoading)
    }

    func testResetAndBlockedActorNeverExposeAnotherAccountsRows() async {
        let inbox = ActivityNotificationInbox()
        let visible = row(actorID: "visible")
        await inbox.refresh(userID: "first", repository: ActivityInboxTestRepository(rows: [row(actorID: "blocked"), visible]))
        XCTAssertEqual(inbox.visibleNotifications(userID: "first", isBlocked: { $0 == "blocked" }), [visible])
        XCTAssertTrue(inbox.visibleNotifications(userID: "second", isBlocked: { _ in false }).isEmpty)
        inbox.reset(for: nil)
        XCTAssertTrue(inbox.notifications.isEmpty)
        XCTAssertNil(inbox.userID)
        XCTAssertFalse(inbox.failed)
    }

    func testFailureClearsStaleContentAndSuccessfulRetryClearsError() async {
        let inbox = ActivityNotificationInbox()
        let repository = ActivityInboxTestRepository(rows: [row()])
        await inbox.refresh(userID: "recipient", repository: repository)
        await inbox.refresh(userID: "recipient", repository: nil)
        XCTAssertTrue(inbox.notifications.isEmpty)
        XCTAssertTrue(inbox.failed)
        let plans = PlacePlanInvitationInbox()
        let follows = FollowNotificationInbox()
        XCTAssertEqual(NotificationInboxRefreshStatus.errorMessage(userID: "recipient", plans: plans, follows: follows,
            checkInFailureUserID: nil, activity: inbox), "Couldn’t refresh recent activity")
        XCTAssertNil(NotificationInboxRefreshStatus.errorMessage(userID: "other", plans: plans, follows: follows,
            checkInFailureUserID: nil, activity: inbox))
        await inbox.refresh(userID: "recipient", repository: repository)
        XCTAssertEqual(inbox.notifications, repository.rows)
        XCTAssertFalse(inbox.failed)
    }

    func testEarlierResponseCannotOverwriteLaterRefresh() async {
        let inbox = ActivityNotificationInbox()
        let slow = ActivityInboxTestRepository(rows: [row()])
        slow.suspend = true
        let first = Task { await inbox.refresh(userID: "recipient", repository: slow) }
        for _ in 0..<1000 where slow.pending == nil { await Task.yield() }
        XCTAssertNotNil(slow.pending)
        let newest = row()
        await inbox.refresh(userID: "recipient", repository: ActivityInboxTestRepository(rows: [newest]))
        slow.pending?.resume(returning: slow.rows)
        await first.value
        XCTAssertEqual(inbox.notifications, [newest])
        XCTAssertFalse(inbox.isLoading)
    }

    func testLateResultCannotRestoreSignedOutAccount() async {
        let inbox = ActivityNotificationInbox()
        let slow = ActivityInboxTestRepository(rows: [row()])
        slow.suspend = true
        let task = Task { await inbox.refresh(userID: "first", repository: slow) }
        for _ in 0..<1000 where slow.pending == nil { await Task.yield() }
        XCTAssertNotNil(slow.pending)
        inbox.reset(for: "second")
        slow.pending?.resume(returning: slow.rows)
        await task.value
        XCTAssertEqual(inbox.userID, "second")
        XCTAssertTrue(inbox.notifications.isEmpty)
        XCTAssertFalse(inbox.isLoading)
    }

    func testCancellationPreservesCompletedErrorWithoutInstallingLateRows() async {
        let inbox = ActivityNotificationInbox()
        await inbox.refresh(userID: "recipient", repository: nil)
        let slow = ActivityInboxTestRepository(rows: [row()])
        slow.suspend = true
        let task = Task { await inbox.refresh(userID: "recipient", repository: slow) }
        for _ in 0..<1000 where slow.pending == nil { await Task.yield() }
        XCTAssertNotNil(slow.pending)
        task.cancel()
        slow.pending?.resume(returning: slow.rows)
        await task.value
        XCTAssertTrue(inbox.failed)
        XCTAssertTrue(inbox.notifications.isEmpty)
        XCTAssertFalse(inbox.isLoading)
    }

    func testRoutesExactActivityAndVisitBeforePlaceFallback() {
        let placeID = UUID().uuidString
        let visitID = UUID().uuidString
        let userPlaceID = UUID().uuidString
        for type in ["activity_liked", "activity_commented", "followed_place_visit", "place_saved_from_your_map"] {
            let item = row(type: type, data: ["activity_id": .string("activity"), "place_id": .string(placeID)])
            XCTAssertEqual(item.destination, .activityComments(id: "activity"))
            XCTAssertEqual(item.analyticsRoute, "activity_comments")
        }
        XCTAssertEqual(row(type: "followed_place_visit", data: ["user_place_id": .string(userPlaceID),
            "visit_id": .string(visitID), "place_id": .string(placeID)]).destination,
            .checkInComments(userPlaceID: userPlaceID, visitID: visitID))
        XCTAssertEqual(row(type: "followed_place_visit", data: ["visit_id": .string("invalid"),
            "place_id": .string(placeID)]).destination, .place(id: placeID))
        XCTAssertEqual(row(type: "place_saved_from_your_map", data: ["place_id": .string(placeID)]).destination, .place(id: placeID))
        XCTAssertNil(row(data: ["activity_id": .number(42)]).destination)
        XCTAssertNil(row(data: ["activity_id": .string("  ")]).destination)
        for type in ["list_place_added", "list_collaborator_added"] {
            XCTAssertEqual(row(type: type, data: ["list_id": .string("list")]).destination, .list(id: "list"))
        }
        XCTAssertEqual(row(type: "followed_activity_digest", data: [:]).destination, .discover)
        XCTAssertNil(row(type: "shared_visit").destination, "Invitation actions have their own inbox source")
        XCTAssertNil(row(type: "mutual_follow").destination, "Do not duplicate follower receipts")
        XCTAssertNil(row(type: "save_streak_reminder").destination)
    }

    func testGroupedImportNeverUsesSnapshotCopyOrStaleFirstPlace() {
        let item = row(type: "followed_place_visit", data: ["sender_import_id": .string("import"),
            "place_id": .string("revoked-place"), "activity_id": .string("stale-activity")])
        XCTAssertEqual(item.destination, .discover)
        XCTAssertNotEqual(item.displayTitle, item.title)
        XCTAssertNotEqual(item.displayBody, item.body)
        XCTAssertEqual(item.analyticsRoute, "discover")
    }

    func testOpenAnalyticsContainOnlyCoarseAllowlistedProperties() {
        let event = row().openedEvent
        XCTAssertEqual(event?.name, WanderAnalyticsEvents.notificationOpened)
        XCTAssertEqual(event?.properties, ["notification_type": "activity_commented",
            "delivery_channel": "in_app", "route": "activity_comments"])
        XCTAssertNil(row(type: "unknown").openedEvent)
        XCTAssertNil(row(data: [:]).openedEvent)
    }

    func testActivityBadgeDeduplicatesPersistsAndRemainsAccountScoped() {
        let suite = "ActivityNotificationInboxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let item = row()
        let first = NotificationBadgeSnapshot(userID: "first", plans: [], checkIns: [], activity: [item, item])
        let second = NotificationBadgeSnapshot(userID: "second", plans: [], checkIns: [], activity: [item])
        let badge = NotificationBadgeStore(defaults: defaults)
        XCTAssertEqual(badge.count(for: first), 1)
        badge.open(first)
        badge.acknowledge(item.badgeID, userID: "first")
        badge.updateVisibleInbox(second)
        XCTAssertEqual(badge.count(for: second), 1)
        badge.close()
        let restored = NotificationBadgeStore(defaults: defaults)
        XCTAssertEqual(restored.count(for: first), 0)
        XCTAssertEqual(restored.count(for: second), 1)
        let next = NotificationBadgeSnapshot(userID: "first", plans: [], checkIns: [], activity: [item, row()])
        XCTAssertEqual(restored.count(for: next), 1)
    }

    func testWannaAndMapSaveOverlapOnceWhileRepeatsRemainDistinct() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first { $0.userPlace.status == .wannaGo })
        let actor = ProfileShell(id: "followed", handle: "friend", displayName: "Friend", avatarURL: nil, bio: nil, relationship: .follower)
        let occurredAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = FeedActivity(id: UUID().uuidString, kind: .placeSaved, actor: actor, place: place, occurredAt: occurredAt)
        let restored = FeedActivity(id: UUID().uuidString, kind: .placeSaved, actor: actor, place: place, occurredAt: occurredAt.addingTimeInterval(60))
        let repeated = FeedActivity(id: UUID().uuidString, kind: .placeWannaGo, actor: actor, place: place, occurredAt: .now)
        let receipt = row(type: "place_saved_from_your_map", actorID: actor.id, createdAt: occurredAt,
                          data: ["user_place_id": .string(place.userPlace.id), "place_id": .string(place.place.id)])
        let result = ActivityNotification.mergingWannas([original, repeated, repeated], with: [receipt], userID: "recipient")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, receipt.id)
        XCTAssertEqual(result[0].badgeID, receipt.badgeID)
        XCTAssertEqual(result[0].destination, .activityComments(id: original.id))
        XCTAssertEqual(result[1].destination, .activityComments(id: repeated.id))
        XCTAssertEqual(result[1].notificationType, "followed_place_wanna")
        XCTAssertEqual(result[1].symbol, "bookmark")
        XCTAssertEqual(ActivityNotification.mergingWannas([restored, original, repeated], with: [receipt], userID: "recipient").count, 3,
                       "A restored save is a separate activity even with the same parent identity")
        XCTAssertEqual(result[1].openedEvent?.properties, ["notification_type": "followed_place_wanna",
            "delivery_channel": "in_app", "route": "activity_comments"])
    }

    func testCollapsingMapSaveAndWannaPreservesSeenStateInBothDirections() {
        let suite = "WannaBadgeAliases.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let wanna = ActivityNotification(id: id, actorID: "actor", notificationType: "followed_place_wanna",
            title: "Wanna", body: "Place", createdAt: .now, data: ["activity_id": .string(id.uuidString)])
        let receipt = row(type: "place_saved_from_your_map", data: ["activity_id": .string(id.uuidString)])
        let first = NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: [], activity: [wanna])
        let collapsed = NotificationBadgeSnapshot(userID: "recipient", plans: [], checkIns: [], activity: [receipt])
        let badge = NotificationBadgeStore(defaults: defaults)
        badge.open(first)
        badge.acknowledge(wanna.badgeID, userID: "recipient")
        badge.close()
        XCTAssertEqual(badge.count(for: collapsed), 0)
        defaults.removePersistentDomain(forName: suite)
        let reverse = NotificationBadgeStore(defaults: defaults)
        reverse.open(collapsed)
        reverse.acknowledge(receipt.badgeID, userID: "recipient")
        reverse.close()
        XCTAssertEqual(reverse.count(for: first), 0)
    }

    func testOnlyExactWannaIdentityMergesWithAnExplicitMapSaveReceipt() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let actor = ProfileShell(id: "followed", handle: "friend", displayName: "Friend", avatarURL: nil, bio: nil, relationship: .follower)
        let first = FeedActivity(id: UUID().uuidString, kind: .placeWannaGo, actor: actor, place: place, occurredAt: .now)
        let next = FeedActivity(id: UUID().uuidString, kind: .placeWannaGo, actor: actor, place: place, occurredAt: .now)
        let receipt = row(type: "place_saved_from_your_map", actorID: actor.id,
                          data: ["activity_id": .string(first.id), "user_place_id": .string(place.userPlace.id)])
        let result = ActivityNotification.mergingWannas([first, next], with: [receipt], userID: "recipient")
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.destination), [.activityComments(id: first.id), .activityComments(id: next.id)])
    }

    func testWannaProjectionDropsOwnUnsupportedAndMissingSourcesAndKeepsUnfollowedMapReceipts() throws {
        let store = WanderStore(fixtures: .seed())
        let place = try XCTUnwrap(store.currentUserVisiblePlaces.first)
        let actor = store.shell(for: store.currentUser)
        let own = FeedActivity(id: UUID().uuidString, kind: .placeWannaGo, actor: actor, place: place, occurredAt: .now)
        let friend = ProfileShell(id: "friend", handle: "friend", displayName: "Friend", avatarURL: nil, bio: nil, relationship: .follower)
        let missing = FeedActivity(id: UUID().uuidString, kind: .placeWannaGo, actor: friend, occurredAt: .now)
        let been = FeedActivity(id: UUID().uuidString, kind: .placeBeen, actor: friend, place: place, occurredAt: .now)
        let invalid = FeedActivity(id: "invalid", kind: .placeWannaGo, actor: friend, place: place, occurredAt: .now)
        let receipt = row(type: "place_saved_from_your_map", actorID: "not-followed", data: ["place_id": .string(place.place.id)])
        XCTAssertEqual(ActivityNotification.mergingWannas([own, missing, been, invalid], with: [receipt], userID: actor.id), [receipt])
        XCTAssertFalse(ActivityNotification.supportedTypes.contains("followed_place_wanna"), "In-app projection is not a push query type")
    }

    private func row(type: String = "activity_commented", actorID: String = "actor", createdAt: Date = .now,
                     data: [String: JSONValue] = ["activity_id": .string("activity")]) -> ActivityNotification {
        ActivityNotification(id: UUID(), actorID: actorID, notificationType: type,
            title: "Synthetic activity", body: "Synthetic details", createdAt: createdAt, data: data)
    }
}

@MainActor private final class ActivityInboxTestRepository: ActivityNotificationRepository {
    var rows: [ActivityNotification]
    var suspend = false
    var pending: CheckedContinuation<[ActivityNotification], Error>?
    var requestedUsers: [String] = []
    init(rows: [ActivityNotification]) { self.rows = rows }
    func receivedActivity(userID: String) async throws -> [ActivityNotification] {
        requestedUsers.append(userID)
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return rows
    }
}
