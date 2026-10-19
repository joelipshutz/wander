import Combine
import Foundation

enum PrivateMessageAnalyticsSurface: String { case live, messages }

enum PrivateMessageThreadTarget: Identifiable {
    case conversation(UUID)
    case reply(recipientID: String, context: PrivateMessageContext)

    var id: String {
        switch self {
        case .conversation(let id): "conversation:\(id.uuidString)"
        case .reply(let recipientID, let context): "reply:\(recipientID):\(context.id)"
        }
    }
}

enum PrivateMessageDraftPolicy {
    static let maximumCharacters = 2_000
    static func prepared(_ body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.unicodeScalars.count <= maximumCharacters
            && !trimmed.unicodeScalars.contains(where: { $0.value == 0 }) ? trimmed : nil
    }
}

struct PrivatePendingMessage: Identifiable, Equatable {
    enum Status: Equatable { case sending, unconfirmed }
    let id: UUID
    let body: String
    let context: PrivateMessageContext?
    var status: Status
}

/// Account-scoped, memory-only state. Failed refreshes remove content whose
/// current authorization could not be verified. No backend error text escapes.
@MainActor
final class PrivateMessageInboxState: ObservableObject {
    @Published private(set) var conversations: [PrivateConversationSummary] = []
    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var nextCursor: PrivateConversationCursor?
    private var generation = UUID()

    func reset(for userID: String?) {
        guard self.userID != userID else { return }
        generation = UUID()
        self.userID = userID
        conversations = []; nextCursor = nil; isLoading = false
        isLoadingMore = false; failed = false; hasLoaded = false
    }

    func refresh(userID: String, repository: (any PrivateMessageRepository)?) async {
        guard !Task.isCancelled else { return }
        reset(for: userID)
        let request = UUID(); generation = request
        isLoading = true; isLoadingMore = false
        defer { if self.userID == userID, generation == request { isLoading = false } }
        do {
            guard let repository else { throw PrivateMessagingUnavailable() }
            let page = try await repository.inbox(before: nil, limit: 40)
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            conversations = sortedUnique(page.items)
            nextCursor = page.nextCursor; failed = false; hasLoaded = true
        } catch {
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            guard !isMessagingCancellation(error) else { return }
            conversations = []; nextCursor = nil; failed = true; hasLoaded = true
        }
    }

    func loadMore(userID: String, repository: (any PrivateMessageRepository)?) async {
        guard self.userID == userID, !isLoading, !isLoadingMore, let cursor = nextCursor, !Task.isCancelled else { return }
        let request = generation
        isLoadingMore = true
        defer { if self.userID == userID, generation == request { isLoadingMore = false } }
        do {
            guard let repository else { throw PrivateMessagingUnavailable() }
            let page = try await repository.inbox(before: cursor, limit: 40)
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            conversations = sortedUnique(conversations + page.items)
            nextCursor = page.nextCursor; failed = false
        } catch {
            guard self.userID == userID, generation == request, !Task.isCancelled else { return }
            guard !isMessagingCancellation(error) else { return }
            conversations = []; nextCursor = nil; failed = true
        }
    }

    private func sortedUnique(_ rows: [PrivateConversationSummary]) -> [PrivateConversationSummary] {
        var records: [UUID: PrivateConversationSummary] = [:]
        for row in rows {
            if let existing = records[row.id], existing.updatedAt > row.updatedAt { continue }
            records[row.id] = row
        }
        return records.values.sorted {
            $0.updatedAt == $1.updatedAt ? $0.id.uuidString < $1.id.uuidString : $0.updatedAt > $1.updatedAt
        }
    }
}

@MainActor
final class PrivateMessageThreadState: ObservableObject {
    @Published private(set) var conversation: PrivateConversationSummary?
    @Published private(set) var messages: [PrivateMessage] = []
    @Published private(set) var pending: PrivatePendingMessage?
    @Published private(set) var userID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingEarlier = false
    @Published private(set) var failed = false
    @Published private(set) var earlierFailed = false
    @Published private(set) var nextCursor: PrivateMessageCursor?
    @Published private(set) var replyContext: PrivateMessageContext?
    @Published private(set) var sendFailure: PrivateMessageError?
    @Published var draft = ""
    private var targetID: String?
    private var session = UUID()
    private var loadRequest = UUID()
    private var sendRequest = UUID()
    private var lastMarkedReadID: UUID?
    private var unverifiedReplyContext: PrivateMessageContext?
    private let analytics: any AnalyticsClient
    private let analyticsSurface: PrivateMessageAnalyticsSurface
    private var recordedSendIDs: Set<UUID> = []

    init(analytics: any AnalyticsClient = NoopAnalyticsClient(), analyticsSurface: PrivateMessageAnalyticsSurface = .messages) {
        self.analytics = analytics; self.analyticsSurface = analyticsSurface
    }

    var canSend: Bool {
        conversation != nil && !failed && !isLoading && pending == nil && PrivateMessageDraftPolicy.prepared(draft) != nil
    }
    var isSending: Bool { pending?.status == .sending }

    func reset(userID: String?, target: PrivateMessageThreadTarget?) {
        guard self.userID != userID || targetID != target?.id else { return }
        session = UUID(); loadRequest = UUID(); sendRequest = UUID()
        self.userID = userID; targetID = target?.id
        conversation = nil; messages = []; pending = nil; draft = ""
        isLoading = false; isLoadingEarlier = false; failed = false; earlierFailed = false
        nextCursor = nil; lastMarkedReadID = nil; sendFailure = nil
        unverifiedReplyContext = nil
        recordedSendIDs = []
        if let target, case .reply(_, let context) = target { replyContext = context } else { replyContext = nil }
    }

    func load(userID: String, target: PrivateMessageThreadTarget, repository: (any PrivateMessageRepository)?) async {
        guard !Task.isCancelled else { return }
        reset(userID: userID, target: target)
        let activeSession = session; let request = UUID(); loadRequest = request
        isLoading = true; isLoadingEarlier = false
        defer { if session == activeSession, loadRequest == request { isLoading = false } }
        do {
            guard let repository else { throw PrivateMessagingUnavailable() }
            let summary: PrivateConversationSummary
            switch target {
            case .conversation(let id): summary = try await repository.conversation(id: id)
            case .reply(let recipientID, let context): summary = try await repository.startReply(recipientID: recipientID, context: context)
            }
            guard session == activeSession, loadRequest == request, !Task.isCancelled else { return }
            let page = try await repository.messages(conversationID: summary.id, before: nil, limit: 50)
            guard session == activeSession, loadRequest == request, !Task.isCancelled else { return }
            // This authorized read replaces all visible history. A concurrent
            // send acknowledgement cannot restore a row this response excludes.
            conversation = summary
            messages = sortedUnique(page.items)
            nextCursor = page.nextCursor; failed = false; earlierFailed = false
            // Reattach only an unsent context which this successful startReply
            // and history read just reauthorized. Completed replies stay plain.
            if case .reply(_, let context) = target,
               let hidden = unverifiedReplyContext,
               hidden.kind == context.kind, hidden.id == context.id {
                replyContext = hidden
                unverifiedReplyContext = nil
            }
            reconcilePending()
        } catch {
            guard session == activeSession, loadRequest == request, !Task.isCancelled else { return }
            guard !isMessagingCancellation(error) else { return }
            clearUnverifiedConversation()
        }
    }

    func loadEarlier(repository: (any PrivateMessageRepository)?) async {
        guard let conversation, let cursor = nextCursor, !isLoading, !isLoadingEarlier, !Task.isCancelled else { return }
        let activeSession = session; let request = loadRequest
        isLoadingEarlier = true
        defer { if session == activeSession, loadRequest == request { isLoadingEarlier = false } }
        do {
            guard let repository else { throw PrivateMessagingUnavailable() }
            let page = try await repository.messages(conversationID: conversation.id, before: cursor, limit: 50)
            guard session == activeSession, loadRequest == request, !Task.isCancelled else { return }
            messages = sortedUnique(page.items + messages); nextCursor = page.nextCursor; earlierFailed = false
            reconcilePending()
        } catch {
            guard session == activeSession, loadRequest == request, !Task.isCancelled else { return }
            guard !isMessagingCancellation(error) else { return }
            earlierFailed = true
            clearUnverifiedConversation()
        }
    }

    func send(repository: (any PrivateMessageRepository)?) async {
        guard canSend, let body = PrivateMessageDraftPolicy.prepared(draft) else { return }
        pending = PrivatePendingMessage(id: UUID(), body: body, context: replyContext, status: .sending)
        draft = ""; sendFailure = nil
        await transmitPending(repository: repository)
    }

    func retryPending(repository: (any PrivateMessageRepository)?) async {
        guard conversation != nil, !failed, pending?.status == .unconfirmed, !isLoading else { return }
        pending?.status = .sending
        sendFailure = nil
        await transmitPending(repository: repository)
    }

    func markVisibleRead(through messageID: UUID, repository: (any PrivateMessageRepository)?) async {
        guard let conversation, !isLoading, !isLoadingEarlier, lastMarkedReadID != messageID,
              messages.contains(where: { $0.id == messageID }), !Task.isCancelled else { return }
        let activeSession = session; let verifiedRead = loadRequest
        do {
            guard let repository else { return }
            try await repository.markRead(conversationID: conversation.id, throughMessageID: messageID)
            guard session == activeSession, loadRequest == verifiedRead,
                  self.conversation?.id == conversation.id, !Task.isCancelled else { return }
            lastMarkedReadID = messageID
        } catch {
            guard session == activeSession, loadRequest == verifiedRead,
                  self.conversation?.id == conversation.id, !Task.isCancelled else { return }
            if (error as? PrivateMessageError) == .unavailable {
                invalidateConversationAccess()
            }
            // The repository also maps transport failures to unavailable, so
            // hide unverified remote content conservatively. Authored drafts
            // remain in memory; read markers never imply delivery in the UI.
        }
    }

    private func transmitPending(repository: (any PrivateMessageRepository)?) async {
        guard let pending, let conversation, let userID, !Task.isCancelled else {
            self.pending?.status = .unconfirmed; return
        }
        let activeSession = session; let verifiedRead = loadRequest
        let request = UUID(); sendRequest = request
        do {
            guard let repository else { throw PrivateMessagingUnavailable() }
            let acknowledged = try await repository.send(conversationID: conversation.id, body: pending.body, clientID: pending.id, context: pending.context)
            guard session == activeSession, sendRequest == request, self.conversation?.id == conversation.id else { return }
            guard loadRequest == verifiedRead else {
                // A newer read owns authorization, even when its result arrives
                // before this acknowledgement. Retain the original retry key;
                // only authorized history can reconcile this overlapping send.
                if self.pending?.id == pending.id { self.pending?.status = .unconfirmed }
                return
            }
            guard acknowledged.conversationID == conversation.id, acknowledged.senderID == userID,
                  acknowledged.clientID == pending.id, acknowledged.body == pending.body else {
                self.pending?.status = .unconfirmed; return
            }
            // Only the durable server acknowledgement produces a Sent bubble.
            messages = sortedUnique(messages + [acknowledged])
            recordAcknowledgedSend(clientID: pending.id, hasContext: pending.context != nil)
            self.pending = nil; replyContext = nil; unverifiedReplyContext = nil; sendFailure = nil
        } catch {
            guard session == activeSession, sendRequest == request else { return }
            // A timeout/cancellation can happen after a server commit. Keep the
            // same idempotency key and say Not confirmed, never Not sent.
            self.pending?.status = .unconfirmed
            guard loadRequest == verifiedRead else { return }
            sendFailure = error as? PrivateMessageError
            if sendFailure == .unavailable { invalidateConversationAccess() }
        }
    }

    private func reconcilePending() {
        guard let pending, let userID, let conversation,
              messages.contains(where: { $0.conversationID == conversation.id && $0.clientID == pending.id && $0.senderID == userID && $0.body == pending.body }) else { return }
        recordAcknowledgedSend(clientID: pending.id, hasContext: pending.context != nil)
        self.pending = nil; replyContext = nil; unverifiedReplyContext = nil; sendFailure = nil
    }

    private func recordAcknowledgedSend(clientID: UUID, hasContext: Bool) {
        guard recordedSendIDs.insert(clientID).inserted else { return }
        let properties = ["surface": analyticsSurface.rawValue, "has_context": hasContext ? "true" : "false"]
        analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.privateMessageSent, properties: properties))
        analytics.track(.engagement(need: .connect, action: .privateMessageSent,
                                    surface: analyticsSurface.rawValue,
                                    properties: ["has_context": hasContext ? "true" : "false"]))
    }

    private func clearUnverifiedConversation() {
        conversation = nil; messages = []; nextCursor = nil; failed = true
        if pending != nil { pending?.status = .unconfirmed }
    }

    private func invalidateConversationAccess() {
        // Fence outstanding operations before clearing the remote transcript
        // and hiding the composer. Authored drafts and retry keys stay in memory.
        loadRequest = UUID(); sendRequest = UUID(); lastMarkedReadID = nil
        isLoading = false; isLoadingEarlier = false
        unverifiedReplyContext = replyContext ?? unverifiedReplyContext
        replyContext = nil
        clearUnverifiedConversation()
    }

    private func sortedUnique(_ rows: [PrivateMessage]) -> [PrivateMessage] {
        var records: [UUID: PrivateMessage] = [:]
        for row in rows { records[row.id] = row }
        return records.values.sorted {
            $0.sentAt == $1.sentAt ? $0.id.uuidString < $1.id.uuidString : $0.sentAt < $1.sentAt
        }
    }
}

private struct PrivateMessagingUnavailable: Error { }
private func isMessagingCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}
