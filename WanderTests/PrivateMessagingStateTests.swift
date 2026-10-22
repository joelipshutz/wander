import XCTest
@testable import Wander

@MainActor
final class PrivateMessagingStateTests: XCTestCase {
    #if DEBUG && targetEnvironment(simulator)
    func testSharedDemoSessionKeepsReplyInInboxAndDropsItAcrossAccountSwitch() async throws {
        let session = LivePrivateMessageSession()
        session.configure(userID: "viewer", authenticatedUITest: true, enabled: true, participants: [])
        let replyRepository = try XCTUnwrap(session.repository)
        let context = PrivateMessageContext(kind: .activity, id: UUID().uuidString)
        let thread = try await replyRepository.startReply(recipientID: "friend", context: context)
        _ = try await replyRepository.send(conversationID: thread.id, body: "Review reply", clientID: UUID(), context: context)
        session.configure(userID: "viewer", authenticatedUITest: true, enabled: true, participants: [])
        let inboxRepository = try XCTUnwrap(session.repository)
        let page = try await inboxRepository.inbox(before: nil, limit: 20)
        XCTAssertEqual(page.items.first { $0.id == thread.id }?.lastMessagePreview, "Review reply")
        session.configure(userID: "other", authenticatedUITest: true, enabled: true, participants: [])
        let other = try XCTUnwrap(session.repository)
        let otherPage = try await other.inbox(before: nil, limit: 20)
        XCTAssertFalse(otherPage.items.contains { $0.id == thread.id })
        session.configure(userID: "viewer", authenticatedUITest: false, enabled: true, participants: [])
        XCTAssertNil(session.repository)
        session.configure(userID: "viewer", authenticatedUITest: true, enabled: false, participants: [])
        XCTAssertNil(session.repository)
    }
    #endif

    func testDraftPolicyMatchesServerScalarLimitAndRejectsEmptyOrNul() {
        XCTAssertEqual(PrivateMessageDraftPolicy.maximumCharacters, SupabasePrivateMessageRepository.maximumBodyLength)
        XCTAssertNil(PrivateMessageDraftPolicy.prepared(" \n\t"))
        XCTAssertNil(PrivateMessageDraftPolicy.prepared("hello\0there"))
        XCTAssertEqual(PrivateMessageDraftPolicy.prepared("  hello \n"), "hello")
        XCTAssertNotNil(PrivateMessageDraftPolicy.prepared(String(repeating: "a", count: 2_000)))
        XCTAssertNil(PrivateMessageDraftPolicy.prepared(String(repeating: "a", count: 2_001)))
        // One user-perceived character can contain multiple Unicode scalars.
        XCTAssertNil(PrivateMessageDraftPolicy.prepared(String(repeating: "e\u{301}", count: 1_001)))
    }

    func testInboxFailureClearsUnverifiedRowsAndRecoveryRestoresThem() async {
        let state = PrivateMessageInboxState()
        let repository = MessagingStateRepository()
        await state.refresh(userID: "viewer", repository: repository)
        XCTAssertEqual(state.conversations, [repository.summary])
        repository.failInbox = true
        await state.refresh(userID: "viewer", repository: repository)
        XCTAssertTrue(state.failed)
        XCTAssertTrue(state.conversations.isEmpty)
        repository.failInbox = false
        await state.refresh(userID: "viewer", repository: repository)
        XCTAssertFalse(state.failed)
        XCTAssertEqual(state.conversations.count, 1)
    }

    func testInboxAccountRoundTripDiscardsLateResult() async {
        let state = PrivateMessageInboxState()
        let repository = MessagingStateRepository()
        repository.suspendInbox = true
        let loading = Task { await state.refresh(userID: "viewer", repository: repository) }
        await waitUntil { repository.inboxContinuation != nil }
        state.reset(for: "other"); state.reset(for: "viewer")
        repository.inboxContinuation?.resume(returning: .init(items: [repository.summary], nextCursor: nil))
        await loading.value
        XCTAssertTrue(state.conversations.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    func testReplyResolutionDoesNotSendAndExplicitSendWaitsForAcknowledgement() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let target = PrivateMessageThreadTarget.reply(recipientID: "friend", context: repository.context)
        await state.load(userID: "viewer", target: target, repository: repository)
        XCTAssertEqual(repository.startedRecipients, ["friend"])
        XCTAssertTrue(repository.sends.isEmpty)
        XCTAssertEqual(state.replyContext, repository.context)
        XCTAssertFalse(state.canSend)
        state.draft = "A private reply"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        XCTAssertEqual(state.pending?.status, .sending)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertFalse(state.canSend)
        let request = repository.sends[0]
        repository.sendContinuation?.resume(returning: repository.message(for: request))
        await sending.value
        XCTAssertEqual(state.messages.map(\.body), ["A private reply"])
        XCTAssertNil(state.pending)
        XCTAssertNil(state.replyContext)
        XCTAssertEqual(request.context, repository.context)
    }

    func testAmbiguousFailureKeepsOriginalBodyAndClientIDAcrossRetry() async {
        let (state, repository) = await readyThread()
        state.draft = "Retry this exact reply"
        repository.sendError = URLError(.timedOut)
        await state.send(repository: repository)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(repository.sends.count, 1)
        repository.sendError = nil
        await state.retryPending(repository: repository)
        XCTAssertEqual(repository.sends.count, 2)
        XCTAssertEqual(repository.sends[0].clientID, repository.sends[1].clientID)
        XCTAssertEqual(repository.sends[0].body, repository.sends[1].body)
        XCTAssertEqual(state.messages.count, 1)
        XCTAssertNil(state.pending)
    }

    func testRefreshReconcilesServerCommittedReplyWithoutSendingAgain() async {
        let (state, repository) = await readyThread()
        state.draft = "Saved before the connection dropped"
        repository.sendError = URLError(.networkConnectionLost)
        await state.send(repository: repository)
        repository.history = [repository.message(for: repository.sends[0])]
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.messages.count, 1)
        XCTAssertEqual(repository.sends.count, 1)
    }

    func testConcurrentTapDoesNotCreateSecondSend() async {
        let (state, repository) = await readyThread()
        state.draft = "Send once"
        repository.suspendSend = true
        let first = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        await state.send(repository: repository)
        XCTAssertEqual(repository.sends.count, 1)
        repository.sendContinuation?.resume(returning: repository.message(for: repository.sends[0]))
        await first.value
        XCTAssertEqual(state.messages.count, 1)
    }

    func testAccountSwitchDiscardsSendAcknowledgementAndPrivateDraft() async {
        let (state, repository) = await readyThread()
        state.draft = "Belongs to the first account"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        state.reset(userID: "other", target: .conversation(repository.summary.id))
        state.reset(userID: "viewer", target: .conversation(repository.summary.id))
        repository.sendContinuation?.resume(returning: repository.message(for: repository.sends[0]))
        await sending.value
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.draft.isEmpty)
        XCTAssertNil(state.pending)
        XCTAssertNil(state.conversation)
    }

    func testMismatchedAcknowledgementNeverBecomesSent() async {
        let (state, repository) = await readyThread()
        repository.acknowledgementSender = "someone-else"
        state.draft = "A reply"
        await state.send(repository: repository)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
    }

    func testUnavailableSendClearsPreviouslyVisibleHistoryAndKeepsUnconfirmedAttempt() async {
        let (state, repository) = await readyThread()
        repository.sendError = PrivateMessageError.unavailable
        state.draft = "A reply"
        await state.send(repository: repository)
        XCTAssertNil(state.conversation)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(state.failed)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
        XCTAssertFalse(state.canSend)
    }

    func testHistoryIsChronologicalAndPagingDeduplicates() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let older = repository.message(body: "older", date: .init(timeIntervalSince1970: 100))
        let newer = repository.message(body: "newer", date: .init(timeIntervalSince1970: 200))
        repository.history = [newer, older]
        repository.historyCursor = .init(timestamp: "1970-01-01T00:01:40.000001Z", id: older.id)
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        XCTAssertEqual(state.messages.map(\.body), ["older", "newer"])
        repository.earlier = [older]
        await state.loadEarlier(repository: repository)
        XCTAssertEqual(state.messages.map(\.body), ["older", "newer"])
        XCTAssertEqual(repository.requestedMessageCursors.last!, repository.historyCursor)
    }

    func testReadMarkerRequiresVisibleKnownMessageAndDoesNotRepeat() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let message = repository.message(body: "hello", date: .now)
        repository.history = [message]
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        XCTAssertTrue(repository.readMarkers.isEmpty)
        await state.markVisibleRead(through: UUID(), repository: repository)
        XCTAssertTrue(repository.readMarkers.isEmpty)
        await state.markVisibleRead(through: message.id, repository: repository)
        await state.markVisibleRead(through: message.id, repository: repository)
        XCTAssertEqual(repository.readMarkers, [message.id])
    }

    func testAlreadyCancelledLoadCannotChangeCurrentAccount() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        state.reset(userID: "current", target: .conversation(repository.summary.id))
        let loading = Task { await state.load(userID: "previous", target: .conversation(repository.summary.id), repository: repository) }
        loading.cancel()
        await loading.value
        XCTAssertEqual(state.userID, "current")
        XCTAssertFalse(state.failed)
    }

    func testReadDenialHidesComposerAndFencesOutstandingSendAcknowledgement() async {
        let analytics = MessagingRecordingAnalytics()
        let state = PrivateMessageThreadState(analytics: analytics)
        let repository = MessagingStateRepository()
        let message = repository.message(body: "Previously authorized", date: .now)
        repository.history = [message]
        await state.load(userID: "viewer", target: .reply(recipientID: "friend", context: repository.context), repository: repository)
        state.draft = "An in-flight reply"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        let clientID = state.pending?.id
        state.draft = "An unsent draft"
        repository.readError = PrivateMessageError.unavailable
        await state.markVisibleRead(through: message.id, repository: repository)
        XCTAssertNil(state.conversation)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.draft, "An unsent draft")
        XCTAssertNil(state.replyContext)
        XCTAssertTrue(state.failed)
        XCTAssertFalse(state.canSend)
        XCTAssertEqual(state.pending?.id, clientID)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
        repository.sendContinuation?.resume(returning: repository.message(for: repository.sends[0]))
        await sending.value
        XCTAssertNil(state.conversation)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertTrue(analytics.events.isEmpty)
    }

    func testReadDenialFromBeforeNewerRefreshCannotClearVerifiedHistory() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let oldMessage = repository.message(body: "Older authorized result", date: .now)
        let newMessage = repository.message(body: "New authorized result", date: .now)
        repository.history = [oldMessage]
        let target = PrivateMessageThreadTarget.conversation(repository.summary.id)
        await state.load(userID: "viewer", target: target, repository: repository)
        repository.suspendRead = true
        let marking = Task { await state.markVisibleRead(through: oldMessage.id, repository: repository) }
        await waitUntil { repository.readContinuation != nil }
        repository.history = [newMessage]
        await state.load(userID: "viewer", target: target, repository: repository)
        state.draft = "New draft"
        repository.readContinuation?.resume(throwing: PrivateMessageError.unavailable)
        await marking.value
        XCTAssertEqual(state.messages, [newMessage])
        XCTAssertNotNil(state.conversation)
        XCTAssertFalse(state.failed)
        XCTAssertEqual(state.draft, "New draft")
        XCTAssertTrue(state.canSend)
    }

    func testUnavailableReadRetainsAuthoredDraftForAuthorizedRecovery() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let message = repository.message(body: "Authorized", date: .now)
        repository.history = [message]
        let target = PrivateMessageThreadTarget.reply(recipientID: "friend", context: repository.context)
        await state.load(userID: "viewer", target: target, repository: repository)
        state.draft = "Keep this unsent draft"
        // The production repository uses the same privacy-preserving error
        // for denied access and transport failures; neither discards authorship.
        repository.readError = PrivateMessageError.unavailable
        await state.markVisibleRead(through: message.id, repository: repository)
        XCTAssertNil(state.conversation)
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertFalse(state.canSend)
        XCTAssertEqual(state.draft, "Keep this unsent draft")
        XCTAssertNil(state.replyContext)
        repository.readError = nil
        await state.load(userID: "viewer", target: target, repository: repository)
        XCTAssertEqual(state.messages, [message])
        XCTAssertFalse(state.failed)
        XCTAssertEqual(state.draft, "Keep this unsent draft")
        XCTAssertTrue(state.canSend)
        XCTAssertEqual(state.replyContext, repository.context)
        await state.send(repository: repository)
        XCTAssertEqual(repository.sends.last?.context, repository.context)
        XCTAssertNil(state.replyContext)
    }

    func testCompletedContextualReplyDoesNotRegainContextAfterAccessRecovery() async {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        let target = PrivateMessageThreadTarget.reply(recipientID: "friend", context: repository.context)
        await state.load(userID: "viewer", target: target, repository: repository)
        state.draft = "First contextual reply"
        await state.send(repository: repository)
        let sent = repository.message(for: repository.sends[0])
        repository.history = [sent]
        state.draft = "Follow-on message"
        repository.readError = PrivateMessageError.unavailable
        await state.markVisibleRead(through: sent.id, repository: repository)
        XCTAssertEqual(state.draft, "Follow-on message")
        repository.readError = nil
        await state.load(userID: "viewer", target: target, repository: repository)
        XCTAssertNil(state.replyContext)
        await state.send(repository: repository)
        XCTAssertNil(repository.sends.last?.context)
    }

    func testSendAcknowledgementDuringRefreshCannotRestoreExcludedContext() async {
        let analytics = MessagingRecordingAnalytics()
        let state = PrivateMessageThreadState(analytics: analytics)
        let repository = MessagingStateRepository()
        let target = PrivateMessageThreadTarget.reply(recipientID: "friend", context: repository.context)
        await state.load(userID: "viewer", target: target, repository: repository)
        state.draft = "Reply about a subsequently revoked context"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        let sent = repository.message(for: repository.sends[0])
        repository.suspendHistory = true
        let refreshing = Task { await state.load(userID: "viewer", target: target, repository: repository) }
        await waitUntil { repository.historyContinuation != nil }
        repository.sendContinuation?.resume(returning: sent)
        await sending.value
        XCTAssertTrue(state.messages.isEmpty)
        repository.historyContinuation?.resume(returning: .init(items: [], nextCursor: nil))
        await refreshing.value
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.pending?.id, sent.clientID)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
        XCTAssertTrue(analytics.events.isEmpty)

        // A later authorized history response can reconcile the same attempt;
        // no second send or different client ID is necessary.
        repository.suspendHistory = false
        repository.history = [sent]
        await state.load(userID: "viewer", target: target, repository: repository)
        XCTAssertEqual(state.messages, [sent])
        XCTAssertNil(state.pending)
        XCTAssertEqual(repository.sends.count, 1)
        XCTAssertEqual(analytics.events.count, 2)
    }

    func testLateSendAcknowledgementCannotRestoreRowExcludedByCompletedRefresh() async {
        let (state, repository) = await readyThread()
        state.draft = "Reply with revoked context"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        let sent = repository.message(for: repository.sends[0])
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        repository.sendContinuation?.resume(returning: sent)
        await sending.value
        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.pending?.id, sent.clientID)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
    }

    func testStaleSendDenialDoesNotClearNewerVerifiedHistory() async {
        let (state, repository) = await readyThread()
        state.draft = "Pending reply"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        let authorized = repository.message(body: "Fresh authorized history", date: .now)
        repository.history = [authorized]
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        repository.sendContinuation?.resume(throwing: PrivateMessageError.unavailable)
        await sending.value
        XCTAssertEqual(state.messages, [authorized])
        XCTAssertFalse(state.failed)
        XCTAssertNotNil(state.conversation)
        XCTAssertEqual(state.pending?.status, .unconfirmed)
    }

    func testSendAnalyticsRequireAcknowledgementAndContainOnlyCoarseProperties() async {
        let analytics = MessagingRecordingAnalytics()
        let state = PrivateMessageThreadState(analytics: analytics, analyticsSurface: .live)
        let repository = MessagingStateRepository()
        await state.load(userID: "viewer", target: .reply(recipientID: "friend", context: repository.context), repository: repository)
        XCTAssertTrue(analytics.events.isEmpty)
        state.draft = "Never export this private text"
        repository.suspendSend = true
        let sending = Task { await state.send(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        XCTAssertTrue(analytics.events.isEmpty)
        repository.sendContinuation?.resume(returning: repository.message(for: repository.sends[0]))
        await sending.value
        XCTAssertEqual(analytics.events, [
            AnalyticsEvent(name: "private_message_sent", properties: ["surface": "live", "has_context": "true"]),
            AnalyticsEvent(name: "engagement_action_performed", properties: ["need": "connect", "action": "private_message_sent", "surface": "live", "has_context": "true"])
        ])
        await state.retryPending(repository: repository)
        XCTAssertEqual(analytics.events.count, 2)
    }

    func testRetryAndRefreshEmitConfirmedSendOnlyOnce() async {
        let analytics = MessagingRecordingAnalytics()
        let state = PrivateMessageThreadState(analytics: analytics, analyticsSurface: .messages)
        let repository = MessagingStateRepository()
        let target = PrivateMessageThreadTarget.conversation(repository.summary.id)
        await state.load(userID: "viewer", target: target, repository: repository)
        state.draft = "A private reply"
        repository.sendError = URLError(.timedOut)
        await state.send(repository: repository)
        XCTAssertTrue(analytics.events.isEmpty)
        repository.history = [repository.message(for: repository.sends[0])]
        await state.load(userID: "viewer", target: target, repository: repository)
        await state.load(userID: "viewer", target: target, repository: repository)
        await state.retryPending(repository: repository)
        XCTAssertEqual(analytics.events.count, 2)
        XCTAssertEqual(analytics.events.first?.properties, ["surface": "messages", "has_context": "false"])
        XCTAssertEqual(repository.sends.count, 1)
    }

    func testRejectedAndStaleAccountAcknowledgementsEmitNoAnalytics() async {
        let analytics = MessagingRecordingAnalytics()
        let state = PrivateMessageThreadState(analytics: analytics)
        let repository = MessagingStateRepository()
        let target = PrivateMessageThreadTarget.conversation(repository.summary.id)
        await state.load(userID: "viewer", target: target, repository: repository)
        repository.acknowledgementSender = "another-account"
        state.draft = "Private"
        await state.send(repository: repository)
        XCTAssertTrue(analytics.events.isEmpty)
        repository.acknowledgementSender = "viewer"; repository.suspendSend = true
        let retry = Task { await state.retryPending(repository: repository) }
        await waitUntil { repository.sendContinuation != nil }
        state.reset(userID: "other", target: target)
        repository.sendContinuation?.resume(returning: repository.message(for: repository.sends.last!))
        await retry.value
        XCTAssertTrue(analytics.events.isEmpty)
    }

    #if DEBUG && targetEnvironment(simulator)
    func testSimulationPreservesTheSelectedParticipantIdentity() async throws {
        let ryan = PrivateMessageParticipant(id: "user_ryan", displayName: "Ryan", handle: "ryan", avatarURL: nil)
        let maya = PrivateMessageParticipant(id: "user_maya", displayName: "Maya", handle: "maya", avatarURL: nil)
        let repository = try XCTUnwrap(PrivateMessageUITestFixtures.make(
            userID: "user_joe", authenticatedUITest: true, unifiedLiveEnabled: true, participants: [ryan, maya]))
        let context = PrivateMessageContext(kind: .activity, id: UUID().uuidString, title: "Larchmont Noodles")
        let first = try await repository.startReply(recipientID: ryan.id, context: context)
        let other = try await repository.startReply(recipientID: maya.id, context: context)
        let reopened = try await repository.startReply(recipientID: ryan.id, context: context)
        XCTAssertEqual(first.participant, ryan)
        XCTAssertEqual(other.participant, maya)
        XCTAssertNotEqual(first.id, other.id)
        XCTAssertEqual(reopened.id, first.id)
        XCTAssertEqual(reopened.participant, ryan)
    }

    func testSimulationRequiresBothExplicitGatesAndRetainsIdempotency() async throws {
        XCTAssertNil(PrivateMessageUITestFixtures.make(userID: "viewer", authenticatedUITest: false, unifiedLiveEnabled: true))
        XCTAssertNil(PrivateMessageUITestFixtures.make(userID: "viewer", authenticatedUITest: true, unifiedLiveEnabled: false))
        let repository = try XCTUnwrap(PrivateMessageUITestFixtures.make(userID: "viewer", authenticatedUITest: true, unifiedLiveEnabled: true))
        XCTAssertTrue((repository as? any PrivateMessageSimulationIdentifying)?.isSimulation == true)
        let page = try await repository.inbox(before: nil, limit: 40)
        let summary = try XCTUnwrap(page.items.first)
        let clientID = UUID()
        let first = try await repository.send(conversationID: summary.id, body: "Simulated reply", clientID: clientID, context: nil)
        let retry = try await repository.send(conversationID: summary.id, body: "Simulated reply", clientID: clientID, context: nil)
        XCTAssertEqual(first, retry)
        let history = try await repository.messages(conversationID: summary.id, before: nil, limit: 50)
        XCTAssertEqual(history.items.filter { $0.clientID == clientID }.count, 1)
    }
    #endif

    private func readyThread() async -> (PrivateMessageThreadState, MessagingStateRepository) {
        let state = PrivateMessageThreadState()
        let repository = MessagingStateRepository()
        await state.load(userID: "viewer", target: .conversation(repository.summary.id), repository: repository)
        return (state, repository)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "The controlled repository operation did not start")
    }
}

private final class MessagingRecordingAnalytics: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}

@MainActor
private final class MessagingStateRepository: PrivateMessageRepository {
    struct SendRequest {
        let conversationID: UUID
        let body: String
        let clientID: UUID
        let context: PrivateMessageContext?
    }
    let summary = PrivateConversationSummary(
        id: UUID(uuidString: "63600000-0000-0000-0000-000000000001")!,
        participant: .init(id: "friend", displayName: "Sample Friend", handle: "sample", avatarURL: nil),
        updatedAt: .init(timeIntervalSince1970: 1_000), unreadCount: 0,
        lastMessageAt: nil, lastMessagePreview: nil)
    let context = PrivateMessageContext(kind: .activity, id: "63600000-0000-0000-0000-000000000002", title: "Sample place")
    var failInbox = false
    var suspendInbox = false
    var suspendSend = false
    var suspendHistory = false
    var suspendRead = false
    var sendError: (any Error)?
    var readError: (any Error)?
    var acknowledgementSender = "viewer"
    var history: [PrivateMessage] = []
    var earlier: [PrivateMessage] = []
    var historyCursor: PrivateMessageCursor?
    var requestedMessageCursors: [PrivateMessageCursor?] = []
    var sends: [SendRequest] = []
    var startedRecipients: [String] = []
    var readMarkers: [UUID] = []
    var inboxContinuation: CheckedContinuation<PrivateConversationPage, any Error>?
    var sendContinuation: CheckedContinuation<PrivateMessage, any Error>?
    var historyContinuation: CheckedContinuation<PrivateMessagePage, any Error>?
    var readContinuation: CheckedContinuation<Void, any Error>?

    func inbox(before: PrivateConversationCursor?, limit: Int) async throws -> PrivateConversationPage {
        if failInbox { throw PrivateMessageError.unavailable }
        if suspendInbox { return try await withCheckedThrowingContinuation { inboxContinuation = $0 } }
        return .init(items: [summary], nextCursor: nil)
    }
    func conversation(id: UUID) async throws -> PrivateConversationSummary { summary }
    func startReply(recipientID: String, context: PrivateMessageContext) async throws -> PrivateConversationSummary {
        startedRecipients.append(recipientID); return summary
    }
    func messages(conversationID: UUID, before: PrivateMessageCursor?, limit: Int) async throws -> PrivateMessagePage {
        requestedMessageCursors.append(before)
        if suspendHistory { return try await withCheckedThrowingContinuation { historyContinuation = $0 } }
        return .init(items: before == nil ? history : earlier, nextCursor: before == nil ? historyCursor : nil)
    }
    func send(conversationID: UUID, body: String, clientID: UUID, context: PrivateMessageContext?) async throws -> PrivateMessage {
        let request = SendRequest(conversationID: conversationID, body: body, clientID: clientID, context: context)
        sends.append(request)
        if let sendError { throw sendError }
        if suspendSend { return try await withCheckedThrowingContinuation { sendContinuation = $0 } }
        return message(for: request)
    }
    func markRead(conversationID: UUID, throughMessageID: UUID) async throws {
        readMarkers.append(throughMessageID)
        if let readError { throw readError }
        if suspendRead { try await withCheckedThrowingContinuation { readContinuation = $0 } }
    }
    func message(for request: SendRequest) -> PrivateMessage {
        .init(id: request.clientID, conversationID: request.conversationID, senderID: acknowledgementSender,
              clientID: request.clientID, body: request.body, sentAt: .init(timeIntervalSince1970: 1_000),
              context: request.context, recipientReadAt: nil)
    }
    func message(body: String, date: Date) -> PrivateMessage {
        .init(id: UUID(), conversationID: summary.id, senderID: "friend", clientID: UUID(), body: body,
              sentAt: date, context: nil, recipientReadAt: nil)
    }
}
