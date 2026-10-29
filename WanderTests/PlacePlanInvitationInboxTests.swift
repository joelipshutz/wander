import XCTest
@testable import Wander

@MainActor final class PlacePlanInvitationInboxTests: XCTestCase {
    func testNotificationErrorTracksBackgroundFailureAndRecoveryWithPopulatedPlans() async {
        let plans = PlacePlanInvitationInbox()
        let follows = FollowNotificationInbox()
        let planRepository = PlanInboxTestRepository()
        let followRepository = NotificationRefreshFollowRepository()
        func message(for userID: String = "recipient") -> String? {
            NotificationInboxRefreshStatus.errorMessage(
                userID: userID, plans: plans, follows: follows, checkInFailureUserID: nil
            )
        }
        await plans.refresh(userID: "recipient", repository: planRepository)
        await follows.refresh(userID: "recipient", repository: followRepository)
        let initialPlans = plans.invitations
        let initialFollows = follows.notifications
        XCTAssertNil(message())

        // A host refresh can fail while the screen's other sections stay populated.
        followRepository.shouldFail = true
        await follows.refresh(userID: "recipient", repository: followRepository)
        XCTAssertEqual(plans.invitations, initialPlans)
        XCTAssertEqual(message(), "Couldn’t refresh follower notifications")
        XCTAssertNil(message(for: "other-account"))

        // Recovery need not change the original rows or trigger a screen refresh.
        followRepository.shouldFail = false
        await follows.refresh(userID: "recipient", repository: followRepository)
        XCTAssertEqual(plans.invitations, initialPlans)
        XCTAssertEqual(follows.notifications, initialFollows)
        XCTAssertNil(message())
        XCTAssertEqual(NotificationInboxRefreshStatus.errorMessage(
            userID: "recipient", plans: plans, follows: follows, checkInFailureUserID: "recipient"
        ), "Couldn’t refresh check-in invitations")
    }

    func testOverlappingFollowRefreshDiscardsEarlierFailure() async {
        let follows = FollowNotificationInbox()
        let repository = NotificationRefreshFollowRepository()
        repository.suspend = true
        let earlier = Task { await follows.refresh(userID: "recipient", repository: repository) }
        for _ in 0..<1000 where repository.pending == nil { await Task.yield() }
        XCTAssertNotNil(repository.pending)
        repository.suspend = false
        await follows.refresh(userID: "recipient", repository: repository)
        repository.pending?.resume(throwing: URLError(.notConnectedToInternet))
        await earlier.value
        XCTAssertEqual(follows.notifications, [repository.row])
        XCTAssertFalse(follows.failed)
        XCTAssertFalse(follows.isLoading)
    }

    func testCancelledRetriesPreserveLastCompletedFailures() async {
        let plans = PlacePlanInvitationInbox()
        let follows = FollowNotificationInbox()
        await plans.refresh(userID: "recipient", repository: nil)
        await follows.refresh(userID: "recipient", repository: nil)
        let planRepository = PlanInboxTestRepository()
        let followRepository = NotificationRefreshFollowRepository()
        planRepository.suspend = true
        followRepository.suspend = true
        let planRetry = Task { await plans.refresh(userID: "recipient", repository: planRepository) }
        let followRetry = Task { await follows.refresh(userID: "recipient", repository: followRepository) }
        for _ in 0..<1000 where planRepository.pending == nil || followRepository.pending == nil { await Task.yield() }
        XCTAssertNotNil(planRepository.pending)
        XCTAssertNotNil(followRepository.pending)
        XCTAssertTrue(plans.failed)
        XCTAssertTrue(follows.failed)
        planRetry.cancel()
        followRetry.cancel()
        planRepository.pending?.resume(returning: [planRepository.row])
        followRepository.pending?.resume(returning: [followRepository.row])
        await planRetry.value
        await followRetry.value
        XCTAssertTrue(plans.failed)
        XCTAssertTrue(follows.failed)
        XCTAssertFalse(plans.isLoading)
        XCTAssertFalse(follows.isLoading)
    }

    func testAlreadyCancelledRefreshCannotResetActiveAccount() async {
        let plans = PlacePlanInvitationInbox()
        let follows = FollowNotificationInbox()
        plans.reset(for: "current")
        follows.reset(for: "current")
        let cancelled = Task {
            await plans.refresh(userID: "previous", repository: nil)
            await follows.refresh(userID: "previous", repository: nil)
        }
        cancelled.cancel()
        await cancelled.value
        XCTAssertEqual(plans.userID, "current")
        XCTAssertEqual(follows.userID, "current")
        XCTAssertFalse(plans.failed)
        XCTAssertFalse(follows.failed)
    }

    func testReadInvitationsRemainReopenableAndAnalyticsExcludeTheirContents() async {
        let repository = PlanInboxTestRepository()
        let inbox = PlacePlanInvitationInbox()
        let analytics = PlanInboxAnalytics()
        await inbox.refresh(userID: "recipient", repository: repository)
        XCTAssertEqual(inbox.unreadCount(for: "recipient"), 1)
        XCTAssertEqual(inbox.unreadCount(for: "stranger"), 0)
        let id = repository.row.id
        inbox.markOpened(id: id, userID: "stranger", analytics: analytics)
        XCTAssertTrue(analytics.events.isEmpty)
        inbox.markOpened(id: id, userID: "recipient", analytics: analytics)
        let firstRead = inbox.invitations.first?.readAt
        inbox.markOpened(id: id, userID: "recipient", analytics: analytics)
        XCTAssertEqual(inbox.invitations.count, 1)
        XCTAssertEqual(inbox.invitations.first?.readAt, firstRead)
        XCTAssertEqual(inbox.unreadCount(for: "recipient"), 0)
        XCTAssertEqual(analytics.events.count, 2)
        XCTAssertEqual(analytics.events.first, AnalyticsEvent(name: "notification_opened", properties: [
            "notification_type": "place_plan_invitation", "delivery_channel": "in_app", "route": "place_plan"
        ]))
    }

    func testFailedRefreshClearsUnverifiedAccessAndCanRecover() async {
        let repository = PlanInboxTestRepository()
        let inbox = PlacePlanInvitationInbox()
        await inbox.refresh(userID: "recipient", repository: repository)
        repository.shouldFail = true
        await inbox.refresh(userID: "recipient", repository: repository)
        XCTAssertTrue(inbox.failed)
        XCTAssertTrue(inbox.invitations.isEmpty)
        XCTAssertFalse(inbox.isLoading)
        repository.shouldFail = false
        await inbox.refresh(userID: "recipient", repository: repository)
        XCTAssertFalse(inbox.failed)
        XCTAssertEqual(inbox.invitations.count, 1)
    }

    func testAccountSwitchDiscardsLateResultsEvenAfterSwitchingBack() async {
        let repository = PlanInboxTestRepository()
        let inbox = PlacePlanInvitationInbox()
        repository.suspend = true
        let request = Task { await inbox.refresh(userID: "first", repository: repository) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        XCTAssertNotNil(repository.pending)
        inbox.reset(for: "second")
        inbox.reset(for: "first")
        repository.pending?.resume(returning: [repository.row])
        await request.value
        XCTAssertTrue(inbox.invitations.isEmpty)
        XCTAssertFalse(inbox.isLoading)
    }

    func testLateRefreshCannotMakeAnOpenedInvitationUnreadAgain() async {
        let repository = PlanInboxTestRepository()
        let inbox = PlacePlanInvitationInbox()
        await inbox.refresh(userID: "recipient", repository: repository)
        repository.suspend = true
        let request = Task { await inbox.refresh(userID: "recipient", repository: repository) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        XCTAssertNotNil(repository.pending)
        inbox.markOpened(id: repository.row.id, userID: "recipient", analytics: NoopAnalyticsClient())
        repository.pending?.resume(returning: [repository.row])
        await request.value
        XCTAssertEqual(inbox.unreadCount(for: "recipient"), 0)
        inbox.reset(for: nil)
        XCTAssertTrue(inbox.invitations.isEmpty)
    }

    func testCancelledRefreshStopsLoadingWithoutPublishingResults() async {
        let repository = PlanInboxTestRepository()
        let inbox = PlacePlanInvitationInbox()
        repository.suspend = true
        let request = Task { await inbox.refresh(userID: "recipient", repository: repository) }
        for _ in 0..<100 where repository.pending == nil { await Task.yield() }
        XCTAssertNotNil(repository.pending)
        request.cancel()
        repository.pending?.resume(returning: [repository.row])
        await request.value
        XCTAssertTrue(inbox.invitations.isEmpty)
        XCTAssertFalse(inbox.isLoading)
        XCTAssertFalse(inbox.failed)
    }
}

@MainActor private final class NotificationRefreshFollowRepository: FollowNotificationRepository {
    let row = FollowNotification(id: UUID(), actorID: "actor", displayName: "Actor", handle: "actor",
                                 avatarURL: nil, createdAt: .now, isMutual: false)
    var shouldFail = false
    var suspend = false
    var pending: CheckedContinuation<[FollowNotification], Error>?

    func receivedFollows() async throws -> [FollowNotification] {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return [row]
    }
}

@MainActor private final class PlanInboxTestRepository: PlacePlanInvitationRepository {
    let row = ReceivedPlacePlanInvitation(id: UUID(), invitation: PlacePlanInvitation(
        payload: PlacePlanInvitationPayload(title: "Private title", placeName: "Private place", location: "Private location",
            senderName: "Private sender", senderAvatarURL: nil, message: "Private message", connection: "Both Wanna Go",
            dateLabel: "Private date", imagePath: "private/path"), artworkURL: URL(string: "https://example.invalid/preview.png")!),
        createdAt: .now, readAt: nil)
    var shouldFail = false
    var suspend = false
    var pending: CheckedContinuation<[ReceivedPlacePlanInvitation], Error>?
    func receivedInvitations() async throws -> [ReceivedPlacePlanInvitation] {
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return [row]
    }
    func receivedInvitation(id: UUID) async throws -> PlacePlanInvitation? { id == row.id ? row.invitation : nil }
    func invitation(token: String) async throws -> PlacePlanInvitation? { nil }
    func create(draft: CommonGroundInvitationDraft, previewPNG: Data) async throws -> WanderShareContent {
        throw WanderRemoteError.notImplemented("test")
    }
}

private final class PlanInboxAnalytics: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
