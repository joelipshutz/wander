import Foundation

/// A reference, never a copied place note or activity payload. Display text is
/// resolved by the server again on each read and disappears if access is lost.
struct PrivateMessageContext: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case activity, place }
    let kind: Kind
    let id: String
    var title: String? = nil
}

struct PrivateMessageParticipant: Decodable, Equatable, Sendable, Identifiable {
    let id: String
    let displayName: String
    let handle: String
    let avatarURL: URL?
}

struct PrivateConversationSummary: Decodable, Equatable, Sendable, Identifiable {
    let id: UUID
    let participant: PrivateMessageParticipant
    let updatedAt: Date
    let unreadCount: Int
    let lastMessageAt: Date?
    let lastMessagePreview: String?
}

/// Only a successful server response is a sent message. Pending drafts belong
/// to view state and must retain their clientID across an ambiguous retry.
struct PrivateMessage: Decodable, Equatable, Sendable, Identifiable {
    let id: UUID
    let conversationID: UUID
    let senderID: String
    let clientID: UUID
    let body: String
    let sentAt: Date
    let context: PrivateMessageContext?
    let recipientReadAt: Date?
}

/// Preserve the exact server timestamp string: Foundation Date round trips can
/// lose PostgreSQL microseconds and skip rows at a pagination boundary.
struct PrivateConversationCursor: Codable, Equatable, Sendable {
    let timestamp: String
    let id: UUID
}

struct PrivateMessageCursor: Codable, Equatable, Sendable {
    let timestamp: String
    let id: UUID
}

struct PrivateConversationPage: Decodable, Equatable, Sendable {
    let items: [PrivateConversationSummary]
    let nextCursor: PrivateConversationCursor?
}

struct PrivateMessagePage: Decodable, Equatable, Sendable {
    /// Newest first; the presentation may reverse the loaded page for a thread.
    let items: [PrivateMessage]
    let nextCursor: PrivateMessageCursor?
}

enum PrivateMessageError: Error, Equatable {
    case unavailable
    case invalidBody
    case rateLimited
    case invalidCursor
    case idempotencyConflict
}
