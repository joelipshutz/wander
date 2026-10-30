import Combine
import XCTest
@testable import Wander

@MainActor
final class SharedVisitDiscussionTests: XCTestCase {
    func testUnusedPostcardInvalidationDoesNotPublishEmptyState() {
        let model = SharedVisitDiscussionModel()
        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }

        for _ in 0..<200 { model.invalidate() }

        XCTAssertEqual(publications, 0)
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.failed)
        XCTAssertTrue(model.pendingCommentIDs.isEmpty)
    }

    func testInvalidationClearsLoadedAndFailedStateThenStopsPublishing() async {
        let repository = fake(["a"])
        repository.pages["a:nil"] = page("a", ids: ["comment"], cursor: "older")
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository,
                         includeComments: true, isCurrent: { true })
        XCTAssertNotNil(model.collection)
        XCTAssertFalse(model.comments.isEmpty)
        XCTAssertTrue(model.hasMore)

        var publications = 0
        let observation = model.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        model.invalidate()
        XCTAssertEqual(publications, 2, "Only the populated collection and comments need publication")
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertFalse(model.hasMore)
        model.invalidate()
        XCTAssertEqual(publications, 2)

        repository.failingID = "a"
        await model.load(activityID: "a", groupID: "g", repository: repository,
                         includeComments: true, isCurrent: { true })
        XCTAssertTrue(model.failed)
        publications = 0
        model.invalidate()
        XCTAssertEqual(publications, 1)
        XCTAssertFalse(model.failed)
        model.invalidate()
        XCTAssertEqual(publications, 1)
    }

    func testRepeatedEmptyInvalidationRejectsLateResponseAndPreservesReplacementLoad() async throws {
        let originalRepository = fake(["a"])
        originalRepository.suspendsSharedVisitRequest = true
        let replacementRepository = fake(["b"])
        replacementRepository.suspendsSharedVisitRequest = true
        let model = SharedVisitDiscussionModel()
        let originalTask = Task { @MainActor in
            await model.load(activityID: "a", groupID: "g", repository: originalRepository,
                             includeComments: false, isCurrent: { true })
        }
        defer {
            originalTask.cancel()
            let gate = originalRepository.sharedVisitGate
            originalRepository.sharedVisitGate = nil
            gate?.resume()
        }
        for _ in 0..<100 where originalRepository.sharedVisitGate == nil { await Task.yield() }
        let original = try XCTUnwrap(originalRepository.sharedVisitGate)
        model.invalidate()
        model.invalidate() // No public state changes; the old generation must remain invalid.

        let replacementTask = Task { @MainActor in
            await model.load(activityID: "b", groupID: "g", repository: replacementRepository,
                             includeComments: false, isCurrent: { true })
        }
        defer {
            replacementTask.cancel()
            let gate = replacementRepository.sharedVisitGate
            replacementRepository.sharedVisitGate = nil
            gate?.resume()
        }
        for _ in 0..<100 where replacementRepository.sharedVisitGate == nil { await Task.yield() }
        let replacement = try XCTUnwrap(replacementRepository.sharedVisitGate)
        originalRepository.sharedVisitGate = nil
        original.resume()
        await originalTask.value
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.isLoading, "Old completion must not clear the replacement's loading state")
        XCTAssertFalse(model.failed)

        replacementRepository.sharedVisitGate = nil
        replacement.resume()
        await replacementTask.value
        XCTAssertEqual(model.collection?.commentActivityID, "b")
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.failed)
    }

    func testCollectionRejectsDuplicateOriginalsWrongKindAndMissingTarget() {
        let a = post("a"), b = post("b", kind: .placeWannaGo)
        XCTAssertNil(SharedVisitPostCollection(groupID: "g", commentActivityID: "a", posts: [a, a]))
        XCTAssertNil(SharedVisitPostCollection(groupID: "g", commentActivityID: "a", posts: [a, b]))
        XCTAssertNil(SharedVisitPostCollection(groupID: "g", commentActivityID: "missing", posts: [a]))
        XCTAssertNil(SharedVisitPostCollection(groupID: "g", commentActivityID: "0", posts: (0...20).map { post("\($0)") }))
    }

    func testCommentsLoadAcrossOriginalsDeduplicateAndKeepSeparateCursors() async throws {
        let repository = fake(["a", "b"])
        repository.pages["a:nil"] = page("a", ids: ["a2"], cursor: "older-a")
        repository.pages["b:nil"] = page("b", ids: ["b2"], cursor: "older-b")
        repository.pages["a:older-a"] = page("a", ids: ["a1", "a2"])
        repository.pages["b:older-b"] = page("b", ids: ["b1", "b2"])
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "b", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        XCTAssertEqual(model.collection?.commentActivityID, "a")
        XCTAssertEqual(model.cursors, ["a": "older-a", "b": "older-b"])
        await model.loadMore(repository: repository, isCurrent: { true })
        XCTAssertEqual(Set(model.comments.map(\.id)), ["a1", "a2", "b1", "b2"])
        XCTAssertFalse(model.hasMore)
    }

    func testCounterpartOutsideLoadedPageIsSupplementalNotAnotherFeedEvent() async {
        let repository = fake(["source", "accepted"])
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "source", groupID: "g", repository: repository, includeComments: false, isCurrent: { true })
        XCTAssertEqual(model.collection?.posts.map(\.id), ["source", "accepted"])
        XCTAssertTrue(repository.requests.isEmpty)
    }

    func testCommentRequestsHaveFourRequestCeiling() async {
        let repository = fake((0..<12).map(String.init))
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "0", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        XCTAssertEqual(repository.requests.count, 12)
        XCTAssertLessThanOrEqual(repository.maximumActive, 4)
        XCTAssertGreaterThan(repository.maximumActive, 1)
    }

    func testOneMemberFailureClearsPartialHeaderAndAllComments() async {
        let repository = fake(["a", "b"])
        repository.failingID = "b"
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        XCTAssertTrue(model.failed)
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testAccountChangeDuringCommentsDropsPublishedHeaderAndResponse() async {
        let repository = fake(["a"])
        var current = true
        repository.onCommentRequest = { current = false }
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { current })
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testMembershipRevocationBeforeNextPageClearsTranscript() async {
        let repository = fake(["a", "b"])
        repository.pages["a:nil"] = page("a", ids: ["one"], cursor: "older")
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        repository.collection = SharedVisitPostCollection(groupID: "g", commentActivityID: "a", posts: [post("a")])
        await model.loadMore(repository: repository, isCurrent: { true })
        XCTAssertTrue(model.failed)
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testRepeatedCursorFailsClosedInsteadOfInfinitePaging() async {
        let repository = fake(["a"])
        repository.pages["a:nil"] = page("a", ids: ["one"], cursor: "older")
        repository.pages["a:older"] = page("a", ids: ["two"], cursor: "older")
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        await model.loadMore(repository: repository, isCurrent: { true })
        XCTAssertTrue(model.failed)
        XCTAssertFalse(model.hasMore)
    }

    func testWrongOriginalCommentCannotEnterGroup() async {
        let repository = fake(["a"])
        repository.pages["a:nil"] = page("unauthorized", ids: ["wrong"])
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        XCTAssertNil(model.collection)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testLikeAndDeleteUseOriginalCommentIdentity() async throws {
        let repository = fake(["a", "b"])
        repository.pages["b:nil"] = page("b", ids: ["from-b"])
        let model = SharedVisitDiscussionModel()
        await model.load(activityID: "a", groupID: "g", repository: repository, includeComments: true, isCurrent: { true })
        let comment = try XCTUnwrap(model.comments.first)
        let liked = await model.update(comment, deleting: false, repository: repository, isCurrent: { true })
        XCTAssertTrue(liked)
        XCTAssertEqual(repository.lastMutation, "from-b")
        XCTAssertTrue(model.comments.first?.viewerHasLiked == true)
        let deleted = await model.update(comment, deleting: true, repository: repository, isCurrent: { true })
        XCTAssertTrue(deleted)
        XCTAssertTrue(model.comments.isEmpty)
    }

    func testLocalDenialsHideAuthorsButUnknownAuthorizedProfilesRemainVisible() {
        XCTAssertTrue(SharedVisitLocalVisibility.permitsAuthor(authorID: "unknown", viewerID: "viewer",
            blocked: false, muted: false, privateProfile: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsAuthor(authorID: "blocked", viewerID: "viewer",
            blocked: true, muted: false, privateProfile: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsAuthor(authorID: "muted", viewerID: "viewer",
            blocked: false, muted: true, privateProfile: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsAuthor(authorID: "private", viewerID: "viewer",
            blocked: false, muted: false, privateProfile: true))
        XCTAssertTrue(SharedVisitLocalVisibility.permitsAuthor(authorID: "viewer", viewerID: "viewer",
            blocked: false, muted: false, privateProfile: true))
    }

    func testLocalCommentFilterRequiresVisibleOriginalAndUnblockedUnmutedAuthor() {
        let comment = page("a", ids: ["comment"]).comments[0]
        XCTAssertTrue(SharedVisitLocalVisibility.permitsComment(comment, visibleActivityIDs: ["a"], blocked: false, muted: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsComment(comment, visibleActivityIDs: ["b"], blocked: false, muted: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsComment(comment, visibleActivityIDs: ["a"], blocked: true, muted: false))
        XCTAssertFalse(SharedVisitLocalVisibility.permitsComment(comment, visibleActivityIDs: ["a"], blocked: false, muted: true))
    }

    func testCommentWriteAcknowledgmentCannotRepopulateAnotherAccount() async {
        await checkCommentAccountFence(succeeds: true)
    }

    func testCommentWriteFailureCannotRestoreOldAccountSummary() async {
        await checkCommentAccountFence(succeeds: false)
    }

    private func checkCommentAccountFence(succeeds: Bool) async {
        let store = WanderStore(fixtures: .empty())
        let originalID = UUID().uuidString.lowercased()
        let repository = fake([originalID])
        let author = ProfileShell(id: store.currentUser.id, handle: "synthetic", displayName: "Synthetic",
            avatarURL: nil, bio: nil, relationship: .mutual)
        let task = Task { @MainActor in
            await store.addActivityComment(activityID: originalID, body: "Synthetic draft",
                backend: WanderBackend(activityEngagementRepository: repository))
        }
        for _ in 0..<100 where repository.postContinuation == nil { await Task.yield() }
        guard let continuation = repository.postContinuation else { XCTFail("Write did not start"); task.cancel(); return }
        store.apply(authState: .signedOut)
        store.apply(authState: .signedIn(AuthSession(userID: "new_account", displayName: "New", handle: "new")))
        repository.postContinuation = nil
        if succeeds {
            continuation.resume(returning: .init(comment: .init(id: "synthetic-comment", activityID: originalID,
                author: author, body: "Synthetic draft", createdAt: .now),
                engagement: ActivityEngagementSummary.empty(activityID: originalID).addingComment()))
        } else { continuation.resume(throwing: URLError(.notConnectedToInternet)) }
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertTrue(store.activityComments(for: originalID).isEmpty)
        XCTAssertEqual(store.activityEngagement(for: originalID).commentCount, 0)
        XCTAssertNil(store.activityEngagementError(for: originalID))
    }

    private func fake(_ ids: [String]) -> SharedVisitRepositoryFake {
        SharedVisitRepositoryFake(collection: SharedVisitPostCollection(groupID: "g", commentActivityID: ids[0], posts: ids.map { post($0) })!)
    }
    private func post(_ id: String, kind: FeedActivityKind = .placeBeen) -> FeedActivity {
        FeedActivity(id: id, kind: kind, actor: author, occurredAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
    private var author: ProfileShell { .init(id: "synthetic", handle: "synthetic", displayName: "Synthetic", avatarURL: nil, bio: nil, relationship: .mutual) }
    private func page(_ original: String, ids: [String], cursor: String? = nil) -> ActivityCommentsPage {
        .init(comments: ids.map { .init(id: $0, activityID: original, author: author, body: "Synthetic comment", createdAt: .distantPast) },
              nextCursor: cursor, engagement: .empty(activityID: original))
    }
}

@MainActor private final class SharedVisitRepositoryFake: ActivityEngagementRepository {
    var collection: SharedVisitPostCollection?
    var pages: [String: ActivityCommentsPage] = [:]
    var requests: [String] = []
    var failingID: String?
    var active = 0
    var maximumActive = 0
    var lastMutation: String?
    var onCommentRequest: (() -> Void)?
    var postContinuation: CheckedContinuation<ActivityCommentPostResult, Error>?
    var suspendsSharedVisitRequest = false
    var sharedVisitGate: CheckedContinuation<Void, Never>?
    init(collection: SharedVisitPostCollection) { self.collection = collection }
    func sharedVisitPosts(activityID: String) async throws -> SharedVisitPostCollection? {
        if suspendsSharedVisitRequest {
            // The gate sends no actor-owned model values across a continuation.
            // Read the collection here after resuming on the repository's actor.
            await withCheckedContinuation { sharedVisitGate = $0 }
            try Task.checkCancellation()
        }
        return collection
    }
    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        requests.append(activityID)
        onCommentRequest?()
        await Task.yield()
        if failingID == activityID { throw URLError(.notConnectedToInternet) }
        return pages["\(activityID):\(before ?? "nil")"] ?? .init(comments: [], nextCursor: nil, engagement: .empty(activityID: activityID))
    }
    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] { [] }
    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] { [] }
    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary { .empty(activityID: activityID) }
    func setCommentLike(commentID: String, isLiked: Bool) async throws -> ActivityCommentLikeSummary {
        lastMutation = commentID
        let comment = pages.values.flatMap(\.comments).first { $0.id == commentID }!
        return .init(commentID: commentID, activityID: comment.activityID, likeCount: 1, viewerHasLiked: isLiked)
    }
    func deleteComment(commentID: String) async throws -> ActivityEngagementSummary {
        lastMutation = commentID
        return .empty(activityID: pages.values.flatMap(\.comments).first { $0.id == commentID }!.activityID)
    }
    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        try await withCheckedThrowingContinuation { postContinuation = $0 }
    }
}
