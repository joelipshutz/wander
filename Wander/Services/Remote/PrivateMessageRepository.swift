import Foundation

@MainActor
protocol PrivateMessageRepository {
    func inbox(before: PrivateConversationCursor?, limit: Int) async throws -> PrivateConversationPage
    func conversation(id: UUID) async throws -> PrivateConversationSummary
    func startReply(recipientID: String, context: PrivateMessageContext) async throws -> PrivateConversationSummary
    func messages(conversationID: UUID, before: PrivateMessageCursor?, limit: Int) async throws -> PrivateMessagePage
    func send(conversationID: UUID, body: String, clientID: UUID, context: PrivateMessageContext?) async throws -> PrivateMessage
    func markRead(conversationID: UUID, throughMessageID: UUID) async throws
}

/// Deliberately stateless: message bodies, previews, and drafts are not persisted
/// in SwiftData, UserDefaults, file caches, notifications, or analytics.
@MainActor
final class SupabasePrivateMessageRepository: PrivateMessageRepository {
    static let maximumBodyLength = 2_000
    static let maximumPageSize = 50
    private let rpc: any RemoteProcedureCalling

    init(rpc: any RemoteProcedureCalling) { self.rpc = rpc }

    convenience init(configuration: WanderBackendConfiguration, authSession: any AuthSessionProviding) {
        self.init(rpc: PrivateMessageRPCClient(configuration: configuration, authSession: authSession))
    }

    func inbox(before: PrivateConversationCursor?, limit: Int = 20) async throws -> PrivateConversationPage {
        try await call("private_message_inbox", params: PageParams(
            input_before_at: before?.timestamp, input_before_id: before?.id,
            input_limit: Self.pageSize(limit)))
    }

    func conversation(id: UUID) async throws -> PrivateConversationSummary {
        try await call("private_message_conversation", params: ConversationParams(input_conversation_id: id))
    }

    func startReply(recipientID: String, context: PrivateMessageContext) async throws -> PrivateConversationSummary {
        guard !recipientID.isEmpty, UUID(uuidString: context.id) != nil else { throw PrivateMessageError.unavailable }
        return try await call("private_message_start", params: StartParams(
            input_recipient_id: recipientID, input_context_kind: context.kind.rawValue,
            input_context_id: context.id))
    }

    func messages(conversationID: UUID, before: PrivateMessageCursor?, limit: Int = 30) async throws -> PrivateMessagePage {
        try await call("private_message_history", params: HistoryParams(
            input_conversation_id: conversationID, input_before_at: before?.timestamp,
            input_before_id: before?.id, input_limit: Self.pageSize(limit)))
    }

    func send(conversationID: UUID, body: String, clientID: UUID, context: PrivateMessageContext? = nil) async throws -> PrivateMessage {
        let normalized = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // PostgreSQL char_length counts Unicode scalar values, not Swift's
        // extended grapheme clusters. Match that limit before making the call.
        guard !normalized.isEmpty, normalized.unicodeScalars.count <= Self.maximumBodyLength,
              !normalized.unicodeScalars.contains(where: { $0.value == 0 }) else { throw PrivateMessageError.invalidBody }
        if let context, UUID(uuidString: context.id) == nil { throw PrivateMessageError.unavailable }
        return try await call("private_message_send", params: SendParams(
            input_conversation_id: conversationID, input_body: normalized,
            input_client_id: clientID, input_context_kind: context?.kind.rawValue,
            input_context_id: context?.id))
    }

    func markRead(conversationID: UUID, throughMessageID: UUID) async throws {
        let _: EmptyRPCResponse = try await call("private_message_mark_read", params: ReadParams(
            input_conversation_id: conversationID, input_through_message_id: throughMessageID))
    }

    private static func pageSize(_ requested: Int) -> Int { min(max(requested, 1), maximumPageSize) }

    private func call<Value: Decodable, Params: Encodable>(_ name: String, params: Params) async throws -> Value {
        do {
            return try await rpc.call(name, params: params)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let urlError = error as? URLError, urlError.code == .cancelled { throw CancellationError() }
            if let safeError = error as? PrivateMessageError { throw safeError }
            // Blocked, deleted, nonparticipant, no-longer-mutual, expired auth,
            // inaccessible source, and transport failure share a safe UI state.
            throw PrivateMessageError.unavailable
        }
    }
}

private struct PageParams: Encodable {
    let input_before_at: String?
    let input_before_id: UUID?
    let input_limit: Int
}
private struct ConversationParams: Encodable { let input_conversation_id: UUID }
private struct StartParams: Encodable {
    let input_recipient_id: String
    let input_context_kind: String
    let input_context_id: String
}
private struct HistoryParams: Encodable {
    let input_conversation_id: UUID
    let input_before_at: String?
    let input_before_id: UUID?
    let input_limit: Int
}
private struct SendParams: Encodable {
    let input_conversation_id: UUID
    let input_body: String
    let input_client_id: UUID
    let input_context_kind: String?
    let input_context_id: String?
}
private struct ReadParams: Encodable {
    let input_conversation_id: UUID
    let input_through_message_id: UUID
}
