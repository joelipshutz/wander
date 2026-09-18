import Foundation

/// Only deliberately shared invitation content, never the source save records.
struct PlacePlanInvitationPayload: Decodable, Equatable, Sendable {
    let title: String
    let placeName: String
    let location: String
    let senderName: String
    let senderAvatarURL: URL?
    let message: String
    let connection: String
    let dateLabel: String
    let imagePath: String

    enum CodingKeys: String, CodingKey {
        case title, location, message, connection
        case placeName = "place_name"
        case senderName = "sender_name"
        case senderAvatarURL = "sender_avatar_url"
        case dateLabel = "date_label"
        case imagePath = "image_path"
    }
}

struct PlacePlanInvitation: Equatable, Sendable {
    let payload: PlacePlanInvitationPayload
    let artworkURL: URL

    static func isValidToken(_ token: String) -> Bool {
        token.range(of: "^[a-f0-9]{48}$", options: .regularExpression) != nil
    }
}

struct PlacePlanInvitationRoute: Identifiable {
    let token: String
    var id: String { token }
}

struct ReceivedPlacePlanInvitation: Identifiable, Equatable, Sendable {
    let id: UUID
    let invitation: PlacePlanInvitation
    let createdAt: Date
    var readAt: Date?

    var isUnread: Bool { readAt == nil }
}

enum PlacePlanInvitationSource: Hashable {
    case link(String)
    case notifications(UUID)
}

/// Public artwork uses a fixed layout so recipients can reuse its exact photo
/// crop while drawing accessible, resizable title/date text without the View CTA.
enum PlacePlanArtworkLayout {
    static let width: CGFloat = 390
    static let photoHeight: CGFloat = 176
}
