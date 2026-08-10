import Foundation

struct ActivityEngagementSummary: Equatable {
    let activityID: String
    let likeCount: Int
    let commentCount: Int
    let viewerHasLiked: Bool

    init(
        activityID: String,
        likeCount: Int = 0,
        commentCount: Int = 0,
        viewerHasLiked: Bool = false
    ) {
        self.activityID = activityID
        self.likeCount = max(0, likeCount)
        self.commentCount = max(0, commentCount)
        self.viewerHasLiked = viewerHasLiked
    }

    static func empty(activityID: String) -> ActivityEngagementSummary {
        ActivityEngagementSummary(activityID: activityID)
    }

    func settingLike(_ isLiked: Bool) -> ActivityEngagementSummary {
        guard isLiked != viewerHasLiked else { return self }
        return ActivityEngagementSummary(
            activityID: activityID,
            likeCount: likeCount + (isLiked ? 1 : -1),
            commentCount: commentCount,
            viewerHasLiked: isLiked
        )
    }

    func addingComment() -> ActivityEngagementSummary {
        ActivityEngagementSummary(
            activityID: activityID,
            likeCount: likeCount,
            commentCount: commentCount + 1,
            viewerHasLiked: viewerHasLiked
        )
    }
}

struct ActivityComment: Identifiable, Equatable {
    let id: String
    let activityID: String
    let author: ProfileShell
    let body: String
    let createdAt: Date
    let isPending: Bool

    init(
        id: String,
        activityID: String,
        author: ProfileShell,
        body: String,
        createdAt: Date,
        isPending: Bool = false
    ) {
        self.id = id
        self.activityID = activityID
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.isPending = isPending
    }
}

struct ActivityCommentsPage: Equatable {
    let comments: [ActivityComment]
    let nextCursor: String?
    let engagement: ActivityEngagementSummary
}

struct ActivityCommentPostResult: Equatable {
    let comment: ActivityComment
    let engagement: ActivityEngagementSummary
}

struct PlaceActivityEngagementMatch: Identifiable, Equatable {
    let activityID: String
    let userPlaceID: String
    let visitID: String?
    let kind: FeedActivityKind
    let occurredAt: Date
    let engagement: ActivityEngagementSummary

    var id: String { activityID }
}

enum ActivityBookmarkState: Equatable {
    case notSaved
    case wanna
    case checkedIn

    var accessibilityValue: String {
        switch self {
        case .notSaved: "Not in Wanna"
        case .wanna: "In Wanna"
        case .checkedIn: "Already checked in"
        }
    }
}

struct ActivityEngagementContext: Identifiable, Equatable {
    let activityID: String
    let actor: ProfileShell
    let placeName: String
    let placeServerID: String?
    let placeDetail: String
    let status: PlaceStatus
    let occurredAt: Date

    var id: String { activityID }

    var actionTitle: String {
        status == .been ? "checked in at" : "added to Wanna"
    }

    var shareMessage: String {
        status == .been
            ? "See \(actor.displayName)'s check-in at \(placeName) on rec.me"
            : "See \(actor.displayName)'s Wanna pick \(placeName) on rec.me"
    }
}
