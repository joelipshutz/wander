import Foundation

struct VisibilityPolicy {
    /// Defense in depth for server-authorized projections. The server remains
    /// authoritative for follows/list access; a cached stealth save is never
    /// displayable by anyone other than its owner, even if the graph is stale.
    func canDisplayServerAuthorizedPlace(
        viewerID: String?,
        ownerID: String,
        visibility: PlaceVisibility,
        isBlocked: Bool
    ) -> Bool {
        guard let viewerID, !isBlocked else { return false }
        return viewerID == ownerID || visibility != .selfOnly
    }

    func canSeePlace(
        viewerID: String?,
        ownerID: String,
        visibility: PlaceVisibility,
        relationship: ViewerRelationship,
        isBlocked: Bool
    ) -> Bool {
        guard !isBlocked else { return false }
        guard let viewerID else { return false }
        guard viewerID != ownerID else { return true }

        switch visibility {
        case .selfOnly:
            return false
        case .followers:
            return relationship == .follower || relationship == .mutual
        case .mutuals:
            return relationship == .mutual
        }
    }
}
