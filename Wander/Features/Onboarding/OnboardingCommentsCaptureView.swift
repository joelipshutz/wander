#if DEBUG
import SwiftUI
import UIKit

/// Public-safe fixture rendered through the production comments screen.
/// Used only to capture the bundled onboarding artwork; never fetches user data.
/// Capture on iPhone 16 Plus / iOS 26.5 in light appearance with
/// -WanderAuthenticatedUITest -WanderOnboardingCommentsCapture and
/// WANDER_COMMENTS_CAPTURE_RECT=44,240,342,320. The PNG is written to Documents.
/// Recheck the viewport if the production comments layout changes.
struct OnboardingCommentsCaptureView: View {
    @StateObject private var store = WanderStore(fixtures: .storefront())
    @StateObject private var auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedOut))
    @StateObject private var backend = WanderBackend(activityEngagementRepository: OnboardingCommentsRepository())
    @StateObject private var navigation = ActivityNavigationCoordinator()
    @State private var ready = false

    var body: some View {
        NavigationStack {
            if ready {
                ActivityCommentsScreen(
                    context: OnboardingCommentsRepository.context,
                    visiblePlace: nil,
                    openProfile: { _ in }, openPlace: { _ in }, openList: { _ in }
                )
                .navigationTitle("comments")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .frame(width: 342)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
        .environmentObject(store)
        .environmentObject(auth)
        .environmentObject(backend)
        .environmentObject(navigation)
        .environment(\.activityPostcardVisualStyle, .astir)
        .astirAdaptiveBrandMode()
        .task {
            _ = await store.refreshActivityComments(
                activityID: OnboardingCommentsRepository.activityID, backend: backend
            )
            ready = true
            try? await Task.sleep(for: .seconds(3))
            captureArtworkIfRequested()
        }
    }

    /// Capture the native hierarchy directly, with a tight viewport around the
    /// recommendation and replies. No generated or reconstructed UI imagery.
    @MainActor
    private func captureArtworkIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["WANDER_COMMENTS_CAPTURE_RECT"],
              let window = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first
        else { return }
        let values = raw.split(separator: ",").compactMap { Double($0) }
        guard values.count == 4 else { return }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let destination = URL.documentsDirectory.appending(path: "onboarding-comments.png")
        try? image.pngData()?.write(to: destination)
    }
}

@MainActor
private final class OnboardingCommentsRepository: ActivityEngagementRepository {
    static let activityID = "00000000-0000-0000-0000-000000000447"
    static func person(_ name: String) -> ProfileShell {
        ProfileShell(id: "onboarding-\(name)", handle: name.lowercased(), displayName: name,
                     avatarURL: nil, bio: nil, relationship: .mutual)
    }
    static var context: ActivityEngagementContext {
        ActivityEngagementContext(
            activityID: activityID, actor: person("Mina"), placeName: "Marigold Table",
            placeServerID: nil, placeDetail: "Santa Monica · Restaurant", status: .been,
            occurredAt: Date().addingTimeInterval(-7200),
            note: "The patio at golden hour. Get the focaccia!", rating: 5
        )
    }
    func comments(activityID: String, before: String?, limit: Int) async throws -> ActivityCommentsPage {
        ActivityCommentsPage(comments: [
            ActivityComment(id: "demo-1", activityID: activityID, author: Self.person("Theo"),
                            body: "This looks so good. Saving it for Friday!", createdAt: Date().addingTimeInterval(-3600)),
            ActivityComment(id: "demo-2", activityID: activityID, author: Self.person("Mina"),
                            body: "You’ll love it. Let’s go together!", createdAt: Date().addingTimeInterval(-1800))
        ], nextCursor: nil, engagement: ActivityEngagementSummary(activityID: activityID, likeCount: 8, commentCount: 2, viewerHasLiked: true))
    }
    func summaries(activityIDs: [String]) async throws -> [ActivityEngagementSummary] { [] }
    func placeActivitySummaries(userPlaceIDs: [String]) async throws -> [PlaceActivityEngagementMatch] { [] }
    func setLike(activityID: String, isLiked: Bool) async throws -> ActivityEngagementSummary {
        throw WanderRemoteError.notImplemented("capture fixture")
    }
    func addComment(activityID: String, body: String) async throws -> ActivityCommentPostResult {
        throw WanderRemoteError.notImplemented("capture fixture")
    }
    func deleteComment(commentID: String) async throws -> ActivityEngagementSummary {
        throw WanderRemoteError.notImplemented("capture fixture")
    }
}
#endif
