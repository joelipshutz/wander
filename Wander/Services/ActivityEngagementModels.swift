import Combine
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

    func removingComment() -> ActivityEngagementSummary {
        ActivityEngagementSummary(
            activityID: activityID,
            likeCount: likeCount,
            commentCount: commentCount - 1,
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
    let ticketKind: FeedTicketKind
    let occurredAt: Date
    let note: String?
    let media: [ActivityEngagementMedia]

    init(
        activityID: String,
        actor: ProfileShell,
        placeName: String,
        placeServerID: String?,
        placeDetail: String,
        status: PlaceStatus,
        occurredAt: Date,
        note: String? = nil,
        media: [ActivityEngagementMedia] = []
    ) {
        self.init(
            activityID: activityID,
            actor: actor,
            placeName: placeName,
            placeServerID: placeServerID,
            placeDetail: placeDetail,
            ticketKind: status == .been ? .checkIn : .wanna,
            occurredAt: occurredAt,
            note: note,
            media: media
        )
    }

    init(
        activityID: String,
        actor: ProfileShell,
        placeName: String,
        placeServerID: String?,
        placeDetail: String,
        ticketKind: FeedTicketKind,
        occurredAt: Date,
        note: String? = nil,
        media: [ActivityEngagementMedia] = []
    ) {
        self.activityID = activityID
        self.actor = actor
        self.placeName = placeName
        self.placeServerID = placeServerID
        self.placeDetail = placeDetail
        self.ticketKind = ticketKind
        self.occurredAt = occurredAt
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmedNote?.isEmpty == false ? trimmedNote : nil
        self.media = media
    }

    var id: String { activityID }

    var actionTitle: String {
        switch ticketKind {
        case .checkIn: "checked in at"
        case .wanna: "added to Wanna"
        case .list: "saved to"
        case .saved: "saved"
        }
    }

    var shareMessage: String {
        switch ticketKind {
        case .checkIn:
            "See \(actor.displayName)'s check-in at \(placeName) on rec.me"
        case .wanna:
            "See \(actor.displayName)'s Wanna pick \(placeName) on rec.me"
        case .list:
            "See \(actor.displayName)'s list activity for \(placeName) on rec.me"
        case .saved:
            "See \(actor.displayName)'s save for \(placeName) on rec.me"
        }
    }
}

struct ActivityEngagementMedia: Identifiable, Equatable {
    let id: String
    let urlString: String?
    let localAssetRef: String?
    let accessibilityLabel: String

    init(
        id: String,
        urlString: String? = nil,
        localAssetRef: String? = nil,
        accessibilityLabel: String
    ) {
        self.id = id
        self.urlString = urlString
        self.localAssetRef = localAssetRef
        self.accessibilityLabel = accessibilityLabel
    }
}

struct ActivityCommentsRoute: Identifiable {
    let id: UUID
    let activityID: String
    var context: ActivityEngagementContext?
    var visiblePlace: VisiblePlace?

    init(
        id: UUID = UUID(),
        activityID: String,
        context: ActivityEngagementContext? = nil,
        visiblePlace: VisiblePlace? = nil
    ) {
        self.id = id
        self.activityID = activityID
        self.context = context
        self.visiblePlace = visiblePlace
    }
}

@MainActor
final class ActivityNavigationCoordinator: ObservableObject {
    @Published private(set) var commentsRoute: ActivityCommentsRoute?

    func openComments(
        context: ActivityEngagementContext,
        visiblePlace: VisiblePlace?
    ) {
        commentsRoute = ActivityCommentsRoute(
            activityID: context.activityID,
            context: context,
            visiblePlace: visiblePlace
        )
    }

    func openComments(activityID: String) {
        commentsRoute = ActivityCommentsRoute(activityID: activityID)
    }

    func resolve(
        requestID: UUID,
        context: ActivityEngagementContext,
        visiblePlace: VisiblePlace?
    ) {
        guard var route = commentsRoute, route.id == requestID else { return }
        route.context = context
        route.visiblePlace = visiblePlace
        commentsRoute = route
    }

    func dismiss(requestID: UUID) {
        guard commentsRoute?.id == requestID else { return }
        commentsRoute = nil
    }
}
