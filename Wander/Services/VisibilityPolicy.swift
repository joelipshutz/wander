import Foundation

struct VisibilityPolicy {
    /// Client defense in depth; SQL remains authoritative. A place summary,
    /// list membership, or accepted invitation is not a source-activity grant.
    ///
    /// identity/deletion -> block -> owner -> exclusions -> account -> audience
    func canSeeActivity(_ context: ActivityAccessContext) -> Bool {
        guard let viewerID = context.viewerID,
              !viewerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !context.ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !context.isDeleted,
              !context.isBlocked
        else { return false }

        if viewerID == context.ownerID { return true }
        guard !context.isAccountExcluded, !context.isActivityExcluded else { return false }
        guard !context.isPrivateAccount || context.followAccess.hasAcceptedFollow else { return false }

        switch context.audience {
        case .account:
            return true
        case .followers:
            return context.followAccess.hasAcceptedFollow
        case .mutuals:
            return context.followAccess == .mutual
        case .selfOnly:
            return false
        }
    }

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
        // This entry point preserves v1 semantics. New activity projections
        // must call canSeeActivity with their complete account/exclusion facts.
        canSeeActivity(ActivityAccessContext(
            viewerID: viewerID,
            ownerID: ownerID,
            audience: ActivityAudience(preserving: visibility),
            isPrivateAccount: false,
            followAccess: ActivityFollowAccess(acceptedRelationship: relationship),
            isAccountExcluded: false,
            isActivityExcluded: false,
            isBlocked: isBlocked,
            isDeleted: false
        ))
    }
}
