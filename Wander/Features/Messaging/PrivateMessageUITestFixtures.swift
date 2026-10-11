#if DEBUG && targetEnvironment(simulator)
import Foundation

/// The host supplies its authenticated-UI-test policy and resolved Live flag.
@MainActor
enum PrivateMessageUITestFixtures {
    static func make(userID: String, authenticatedUITest: Bool, unifiedLiveEnabled: Bool) -> (any PrivateMessageRepository)? {
        guard authenticatedUITest, unifiedLiveEnabled else { return nil }
        return PrivateMessageUITestRepository(userID: userID)
    }
}

/// Memory-only automation data. The UI explicitly labels every acknowledgement
/// as simulated. There is no network, persistence, or analytics.
@MainActor
private final class PrivateMessageUITestRepository: PrivateMessageRepository, PrivateMessageSimulationIdentifying {
    let isSimulation = true
    private let userID: String
    private var summaries: [UUID: PrivateConversationSummary] = [:]
    private var history: [UUID: [PrivateMessage]] = [:]
    private let fixtureDate = Date(timeIntervalSince1970: 1_791_590_400)

    init(userID: String) {
        self.userID = userID
        let id = UUID(uuidString: "63600000-0000-0000-0000-000000000010")!
        let participant = PrivateMessageParticipant(id: "private-message-fixture-friend", displayName: "Maya Chen", handle: "maya.demo", avatarURL: nil)
        let body = "That little patio looks lovely. Let’s save it for a sunny afternoon."
        summaries[id] = .init(id: id, participant: participant, updatedAt: fixtureDate,
                              unreadCount: 1, lastMessageAt: fixtureDate, lastMessagePreview: body)
        history[id] = [.init(id: UUID(uuidString: "63600000-0000-0000-0000-000000000011")!, conversationID: id,
                             senderID: participant.id, clientID: UUID(uuidString: "63600000-0000-0000-0000-000000000012")!,
                             body: body, sentAt: fixtureDate, context: nil, recipientReadAt: nil)]
    }

    func inbox(before: PrivateConversationCursor?, limit: Int) async throws -> PrivateConversationPage {
        .init(items: summaries.values.sorted { $0.updatedAt > $1.updatedAt }, nextCursor: nil)
    }
    func conversation(id: UUID) async throws -> PrivateConversationSummary {
        guard let summary = summaries[id] else { throw PrivateMessageError.unavailable }
        return summary
    }
    func startReply(recipientID: String, context: PrivateMessageContext) async throws -> PrivateConversationSummary {
        guard recipientID != userID else { throw PrivateMessageError.unavailable }
        if let existing = summaries.values.first(where: { $0.participant.id == recipientID }) { return existing }
        let summary = PrivateConversationSummary(id: UUID(), participant: .init(id: recipientID, displayName: "Demo friend", handle: "demo.friend", avatarURL: nil),
                                                 updatedAt: fixtureDate, unreadCount: 0, lastMessageAt: nil, lastMessagePreview: nil)
        summaries[summary.id] = summary; history[summary.id] = []
        return summary
    }
    func messages(conversationID: UUID, before: PrivateMessageCursor?, limit: Int) async throws -> PrivateMessagePage {
        guard let messages = history[conversationID] else { throw PrivateMessageError.unavailable }
        return .init(items: messages.sorted { $0.sentAt > $1.sentAt }, nextCursor: nil)
    }
    func send(conversationID: UUID, body: String, clientID: UUID, context: PrivateMessageContext?) async throws -> PrivateMessage {
        guard let summary = summaries[conversationID] else { throw PrivateMessageError.unavailable }
        guard let prepared = PrivateMessageDraftPolicy.prepared(body) else { throw PrivateMessageError.invalidBody }
        if let existing = history.values.flatMap({ $0 }).first(where: { $0.clientID == clientID && $0.senderID == userID }) {
            guard existing.body == prepared, existing.conversationID == conversationID, existing.context == context else { throw PrivateMessageError.idempotencyConflict }
            return existing
        }
        let date = fixtureDate.addingTimeInterval(Double((history[conversationID]?.count ?? 0) + 1) * 60)
        let message = PrivateMessage(id: UUID(), conversationID: conversationID, senderID: userID, clientID: clientID,
                                     body: prepared, sentAt: date, context: context, recipientReadAt: nil)
        history[conversationID, default: []].append(message)
        summaries[conversationID] = .init(id: summary.id, participant: summary.participant, updatedAt: date,
                                          unreadCount: 0, lastMessageAt: date, lastMessagePreview: prepared)
        return message
    }
    func markRead(conversationID: UUID, throughMessageID: UUID) async throws {
        guard let summary = summaries[conversationID], history[conversationID]?.contains(where: { $0.id == throughMessageID }) == true else { throw PrivateMessageError.unavailable }
        summaries[conversationID] = .init(id: summary.id, participant: summary.participant, updatedAt: summary.updatedAt,
                                          unreadCount: 0, lastMessageAt: summary.lastMessageAt, lastMessagePreview: summary.lastMessagePreview)
    }
}
#endif
