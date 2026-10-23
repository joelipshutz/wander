#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Synthetic app-bundled screenshot fixture; no hosted content or credentials.
struct SharedVisitReviewRoot: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @StateObject private var auth = AuthSessionStore(provider: PreviewAuthSessionProvider(
        state: .signedIn(AuthSession(userID: "user_joe", displayName: "Alex", handle: "alex"))), analytics: NoopAnalyticsClient())
    @StateObject private var backend = WanderBackend(activityEngagementRepository: SharedVisitReviewRepository())
    @StateObject private var navigation = ActivityNavigationCoordinator()
    @StateObject private var upsells = ProductUpsellCoordinator(analytics: NoopAnalyticsClient())
    private var group: FeedActivityGroup { FeedPresentation.groupedActivity(SharedVisitReviewRepository.posts).first! }
    var body: some View {
        NavigationStack {
            ScrollView {
                if let context = group.primaryActivity.activityEngagementContext {
                    ActivityPostcardView(context: context, visiblePlace: group.primaryActivity.place,
                        metadataIcon: "cup.and.saucer", secondaryMetadataTitle: nil,
                        secondaryMetadataAction: nil, secondaryMetadataAccessibilityLabel: nil,
                        artworkAction: nil, artworkAccessibilityLabel: nil, destinationAction: nil,
                        destinationAccessibilityLabel: nil, openProfile: nil,
                        actorAccessibilityIdentifier: "sharedVisit.review.actor",
                        destinationAccessibilityIdentifier: "sharedVisit.review.place",
                        postcardAccessibilityIdentifier: "sharedVisit.review.postcard", activityGroup: group,
                        sharedVisitCompanions: group.primaryActivity.sharedVisit?.companions ?? [],
                        sharedVisitCurrentUserID: store.currentUser.id)
                    .padding()
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .astirScreen()
            .navigationDestination(item: Binding(get: { navigation.commentsRoute }, set: { route in
                if route == nil { navigation.reset() }
            })) { route in
                ActivityCommentsRouteScreen(requestID: route.id, retry: {}, openProfile: { _ in }, openPlace: { _ in }, openList: { _ in })
            }
        }
        .environmentObject(store).environmentObject(auth).environmentObject(backend)
        .environmentObject(navigation).environmentObject(upsells)
        .environment(\.activityPostcardVisualStyle, .astir).astirAdaptiveBrandMode()
        .task {
            await auth.refreshSession()
            guard !Task.isCancelled, auth.isSessionValidated else { return }
            store.apply(authState: auth.state)
        }
    }
}

@MainActor private final class SharedVisitReviewRepository: ActivityEngagementRepository {
    static let groupID = "96000000-0000-4000-8000-000000000001"
    static let ids = ["96000000-0000-4000-8000-000000000011", "96000000-0000-4000-8000-000000000012"]
    static var posts: [FeedActivity] {
        ["Alex", "Sam"].enumerated().map { index, name in
            let userID = index == 0 ? "user_joe" : "fixture_sam"
            let place = LocalPlace(localID: "shared-review-cafe", canonicalName: "Juniper Café", category: "coffee", latitude: 34, longitude: -118)
            let save = LocalUserPlace(localID: "shared-review-save-\(index)", userID: userID, placeID: place.id,
                status: .been, visibility: .followers, sourceType: "manual")
            let profile = ProfileShell(id: userID, handle: name.lowercased(), displayName: name,
                avatarURL: nil, bio: nil, relationship: index == 0 ? .owner : .mutual)
            return FeedActivity(id: ids[index], kind: .placeBeen, actor: profile,
                place: VisiblePlace(id: save.id, place: place, userPlace: save,
                    owner: LocalProfile(localID: userID, handle: name.lowercased(), displayName: name)),
                occurredAt: Date(timeIntervalSince1970: 1_792_627_200 + Double(index)),
                note: index == 0 ? "The shaded patio made a perfect afternoon stop." : "Loved the cardamom latte. Next time, let’s try breakfast.",
                media: ActivityPostcardPhotoUITestFixtures.photos().enumerated().filter { $0.offset % 2 == index }.map {
                    FeedMediaPreview(id: $0.element.id, accessibilityLabel: $0.element.accessibilityLabel)
                }, sharedVisit: .init(groupID: groupID, visitID: "review-visit-\(index)", companions: [
                    .init(profile: ProfileShell(id: index == 0 ? "fixture_sam" : "user_joe",
                        handle: index == 0 ? "sam" : "alex", displayName: index == 0 ? "Sam" : "Alex",
                        avatarURL: nil, bio: nil, relationship: index == 0 ? .mutual : .owner), status: .accepted)
                ]))
        }
    }
    private var posted: [ActivityComment] = []
    func sharedVisitPosts(activityID: String) async throws -> SharedVisitPostCollection? {
        guard Self.ids.contains(activityID) else { return nil }
        return .init(groupID: Self.groupID, commentActivityID: Self.ids[0], posts: Self.posts)
    }
    func activity(id: String) async throws -> FeedActivity {
        guard let post = Self.posts.first(where: { $0.id == id }) else { throw URLError(.resourceUnavailable) }
        return post
    }
    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        guard let post = Self.posts.first(where: { $0.id == activityID }) else { throw URLError(.resourceUnavailable) }
        let comment = ActivityComment(id: "review-comment-\(post.actor.id)", activityID: activityID,
            author: post.actor, body: post.actor.id == "user_joe" ? "Happy we finally made it here." : "Count me in for another visit.",
            createdAt: post.occurredAt.addingTimeInterval(60))
        return .init(comments: [comment] + posted.filter { $0.activityID == activityID }, nextCursor: nil,
            engagement: .init(activityID: activityID, commentCount: 1))
    }
    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] { activityIDs.map { .init(activityID: $0, commentCount: 1) } }
    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] { [] }
    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary { .init(activityID: activityID, likeCount: isLiked ? 1 : 0, viewerHasLiked: isLiked) }
    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        let comment = ActivityComment(id: UUID().uuidString.lowercased(), activityID: activityID,
            author: Self.posts[0].actor, body: body, createdAt: .now)
        posted.append(comment)
        return .init(comment: comment, engagement: .init(activityID: activityID, commentCount: 2))
    }
    func deleteComment(commentID: String) async throws -> ActivityEngagementSummary {
        let activityID = posted.first { $0.id == commentID }?.activityID ?? Self.ids[0]
        posted.removeAll { $0.id == commentID }
        return .empty(activityID: activityID)
    }
}
#endif
