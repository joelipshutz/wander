import Foundation

/// Version-two audiences are separate from PlaceVisibility: the legacy
/// "followers" value must never acquire public-account semantics on decode.
enum ActivityAudience: String, Codable, CaseIterable, Sendable {
    case account
    case followers
    case mutuals
    case selfOnly = "self"

    init(preserving visibility: PlaceVisibility) {
        switch visibility {
        case .followers: self = .followers
        case .mutuals: self = .mutuals
        case .selfOnly: self = .selfOnly
        }
    }
}

/// Requesting, including an optimistic request, never authorizes content.
/// Ownership is established by matching authenticated IDs, not a graph label.
enum ActivityFollowAccess: String, Codable, CaseIterable, Sendable {
    case none
    case requested
    case following
    case mutual

    init(acceptedRelationship: ViewerRelationship) {
        switch acceptedRelationship {
        case .follower: self = .following
        case .mutual: self = .mutual
        case .owner, .nonFollower: self = .none
        }
    }

    var hasAcceptedFollow: Bool {
        self == .following || self == .mutual
    }
}

/// Complete access facts for one source activity and one authenticated viewer.
/// All facts must be supplied by an authorized projection. Missing/unknown
/// fields must fail decoding rather than defaulting to public or unexcluded.
/// Do not persist or transmit an owner's exclusion list to other viewers.
struct ActivityAccessContext: Equatable, Sendable {
    let viewerID: String?
    let ownerID: String
    let audience: ActivityAudience
    let isPrivateAccount: Bool
    let followAccess: ActivityFollowAccess
    let isAccountExcluded: Bool
    let isActivityExcluded: Bool
    let isBlocked: Bool
    let isDeleted: Bool
}
