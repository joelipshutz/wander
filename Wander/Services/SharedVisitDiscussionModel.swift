import Combine
import Foundation

/// Supplemental originals are context, never additional matching Feed rows.
struct SharedVisitPostCollection {
    let groupID: String
    let commentActivityID: String
    let posts: [FeedActivity]
    let companions: [FeedSharedVisitCompanion]
    let visitIDs: [String]

    init?(groupID: String, commentActivityID: String, posts: [FeedActivity], companions: [FeedSharedVisitCompanion] = [], visitIDs: [String] = []) {
        guard !groupID.isEmpty, !posts.isEmpty, posts.count <= 20,
              Set(posts.map(\.id)).count == posts.count,
              posts.allSatisfy({ $0.kind == .placeBeen }),
              posts.contains(where: { $0.id == commentActivityID }) else { return nil }
        self.groupID = groupID
        self.commentActivityID = commentActivityID
        self.posts = posts
        self.companions = companions
        self.visitIDs = Array(Set(visitIDs + posts.compactMap { $0.sharedVisit?.visitID })).sorted()
    }

    var commentTarget: FeedActivity? { posts.first { $0.id == commentActivityID } }
}

/// Local denials take effect before a delayed server projection can reappear.
/// Unknown profiles remain governed by the authorized RPC response.
enum SharedVisitLocalVisibility {
    static func permitsAuthor(authorID: String, viewerID: String, blocked: Bool,
                              muted: Bool, privateProfile: Bool) -> Bool {
        !blocked && !muted && (authorID == viewerID || !privateProfile)
    }

    static func permitsComment(_ comment: ActivityComment, visibleActivityIDs: Set<String>,
                               blocked: Bool, muted: Bool) -> Bool {
        visibleActivityIDs.contains(comment.activityID) && !blocked && !muted
    }
}

/// Memory-only, account/foreground-fenced paging. Each original owns its cursor;
/// comments are deduplicated by immutable comment ID, not author or text.
@MainActor
final class SharedVisitDiscussionModel: ObservableObject {
    @Published private(set) var collection: SharedVisitPostCollection?
    @Published private(set) var comments: [ActivityComment] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var pendingCommentIDs: Set<String> = []
    private(set) var cursors: [String: String] = [:]
    private var generation = UUID()

    var hasMore: Bool { !cursors.isEmpty }

    func invalidate() {
        generation = UUID()
        // Ordinary postcards also own this model. Their disappearance must not
        // publish unchanged empty state, but every invalidation still fences
        // outstanding responses through the generation above.
        if collection != nil { collection = nil }
        if !comments.isEmpty { comments = [] }
        cursors = [:]
        if isLoading { isLoading = false }
        if failed { failed = false }
        if !pendingCommentIDs.isEmpty { pendingCommentIDs = [] }
    }

    func load(activityID: String, groupID: String, repository: any ActivityEngagementRepository,
              includeComments: Bool, isCurrent: @escaping @MainActor () -> Bool) async {
        invalidate()
        let request = generation
        guard isCurrent() else { return }
        isLoading = true
        do {
            guard let result = try await repository.sharedVisitPosts(activityID: activityID),
                  result.groupID == groupID else { throw SharedVisitReadError.unavailable }
            guard current(request, isCurrent) else { return }
            collection = result // The reauthorized header need not wait for discussions.
            let pages = includeComments ? try await Self.pages(
                ids: result.posts.map(\.id), cursors: [:], repository: repository) : [:]
            guard current(request, isCurrent) else { return }
            var loaded: [ActivityComment] = []
            var next: [String: String] = [:]
            for (id, page) in pages {
                guard page.comments.allSatisfy({ $0.activityID == id }) else {
                    throw SharedVisitReadError.unavailable
                }
                loaded += page.comments
                next[id] = page.nextCursor
            }
            guard current(request, isCurrent) else { return }
            collection = result
            comments = Self.uniqueComments(loaded)
            cursors = next
            isLoading = false
        } catch {
            guard current(request, isCurrent) else { return }
            invalidate()
            failed = true
        }
    }

    func loadMore(repository: any ActivityEngagementRepository,
                  isCurrent: @escaping @MainActor () -> Bool) async {
        guard !isLoading, let collection, hasMore, isCurrent() else { return }
        let request = generation
        isLoading = true
        do {
            // Membership and source visibility may change between pages. The
            // new collection must agree before any cached transcript survives.
            guard let checked = try await repository.sharedVisitPosts(activityID: collection.commentActivityID),
                  checked.groupID == collection.groupID,
                  Set(checked.posts.map(\.id)) == Set(collection.posts.map(\.id)),
                  checked.commentActivityID == collection.commentActivityID else {
                throw SharedVisitReadError.unavailable
            }
            guard current(request, isCurrent) else { return }
            var loaded = comments
            var next = cursors
            let pages = try await Self.pages(ids: cursors.keys.sorted(), cursors: cursors, repository: repository)
            guard current(request, isCurrent) else { return }
            for (id, page) in pages {
                guard page.nextCursor == nil || page.nextCursor != cursors[id],
                      page.comments.allSatisfy({ $0.activityID == id }) else {
                    throw SharedVisitReadError.unavailable
                }
                loaded += page.comments
                next[id] = page.nextCursor
            }
            guard current(request, isCurrent) else { return }
            self.collection = checked
            comments = Self.uniqueComments(loaded)
            cursors = next
            isLoading = false
        } catch {
            guard current(request, isCurrent) else { return }
            invalidate()
            failed = true
        }
    }

    /// A fixed four-request window avoids twenty serial round trips without
    /// allowing unbounded fan-out. The accumulator stays on the main actor.
    private static func pages(ids: [String], cursors: [String: String],
                              repository: any ActivityEngagementRepository) async throws -> [String: ActivityCommentsPage] {
        let accumulator = SharedVisitPageAccumulator(repository: repository)
        for start in stride(from: 0, to: ids.count, by: 4) {
            try Task.checkCancellation()
            let batch = Array(ids[start..<min(start + 4, ids.count)])
            try await withThrowingTaskGroup(of: Void.self) { tasks in
                for id in batch {
                    let cursor = cursors[id]
                    tasks.addTask {
                        try await accumulator.fetch(activityID: id, before: cursor)
                    }
                }
                try await tasks.waitForAll()
            }
        }
        return accumulator.pages
    }

    func update(_ comment: ActivityComment, deleting: Bool, repository: any ActivityEngagementRepository,
                isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        guard isCurrent(), comments.contains(where: { $0.id == comment.id }),
              pendingCommentIDs.insert(comment.id).inserted else { return false }
        let request = generation
        defer { if request == generation { pendingCommentIDs.remove(comment.id) } }
        do {
            if deleting {
                let summary = try await repository.deleteComment(commentID: comment.id)
                guard summary.activityID == comment.activityID else { throw SharedVisitReadError.unavailable }
                guard current(request, isCurrent) else { return false }
                comments.removeAll { $0.id == comment.id }
            } else {
                let summary = try await repository.setCommentLike(commentID: comment.id, isLiked: !comment.viewerHasLiked)
                guard summary.activityID == comment.activityID, summary.commentID == comment.id else {
                    throw SharedVisitReadError.unavailable
                }
                guard current(request, isCurrent) else { return false }
                comments = comments.map { $0.id == comment.id
                    ? $0.withLikes(count: summary.likeCount, isLiked: summary.viewerHasLiked) : $0 }
            }
            return true
        } catch {
            guard current(request, isCurrent) else { return false }
            invalidate()
            failed = true
            return false
        }
    }

    private func current(_ request: UUID, _ isCurrent: @MainActor () -> Bool) -> Bool {
        guard request == generation else { return false }
        guard !Task.isCancelled, isCurrent() else { invalidate(); return false }
        return true
    }

    static func uniqueComments(_ input: [ActivityComment]) -> [ActivityComment] {
        Dictionary(input.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest }).values.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id < $1.id
        }
    }
}

private enum SharedVisitReadError: Error { case unavailable }

@MainActor private final class SharedVisitPageAccumulator {
    private let repository: any ActivityEngagementRepository
    private(set) var pages: [String: ActivityCommentsPage] = [:]

    init(repository: any ActivityEngagementRepository) { self.repository = repository }

    func fetch(activityID: String, before: String?) async throws {
        try Task.checkCancellation()
        let page = try await repository.comments(activityID: activityID, before: before, limit: 50)
        try Task.checkCancellation()
        pages[activityID] = page
    }
}
