#if DEBUG
import SwiftUI
import UIKit

/// Runs the production postcard and photo viewer with app-bundled images only.
/// Each launch starts from an isolated fixture session with no remote services.
struct ActivityPostcardReviewRoot: View {
    @StateObject private var store = WanderStore(fixtures: WanderFixtures.seed())
    @StateObject private var auth = AuthSessionStore(
        provider: PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe"))
        ),
        analytics: NoopAnalyticsClient()
    )
    @StateObject private var backend = WanderBackend()
    @StateObject private var activityNavigation = ActivityNavigationCoordinator()
    @StateObject private var productUpsells = ProductUpsellCoordinator(analytics: NoopAnalyticsClient())
    @State private var selectedDestination: Destination?
    private let context: ActivityEngagementContext

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let hasLongTitle = arguments.contains("-WanderFeedPhotoStackLongTitle")
        context = ActivityEngagementContext(
            activityID: "fixture-feed-photo-stack",
            actor: ProfileShell(
                id: "user_ryan", handle: "ryan", displayName: "Ryan Lieblein",
                avatarURL: nil, bio: nil, relationship: .follower
            ),
            placeName: hasLongTitle ? "Blue Ribbon Sushi Palisades Village" : "Bacio di Latte",
            placeServerID: nil,
            placeDetail: hasLongTitle ? "Sushi · Pacific Palisades · CA" : "Ice cream · Santa Monica · CA",
            ticketKind: .checkIn,
            occurredAt: .now,
            note: "A favorite place worth returning to. Bring a friend and take your time.",
            rating: hasLongTitle ? 4 : 5,
            media: arguments.contains("-WanderFeedPhotoStackNoPhotos") ? [] : ActivityPostcardPhotoUITestFixtures.photos()
        )
    }

    @ViewBuilder var body: some View {
        #if targetEnvironment(simulator)
        if ActivityPostcardPhotoUITestFixtures.isSharedReviewEnabled(arguments: ProcessInfo.processInfo.arguments) {
            SharedVisitReviewRoot()
        } else { ordinaryBody }
        #else
        ordinaryBody
        #endif
    }

    private var ordinaryBody: some View {
        NavigationStack {
            ScrollView {
                ActivityPostcardView(
                    context: context,
                    visiblePlace: nil,
                    metadataIcon: "fork.knife",
                    secondaryMetadataTitle: nil,
                    secondaryMetadataAction: nil,
                    secondaryMetadataAccessibilityLabel: nil,
                    artworkAction: { selectedDestination = .place },
                    artworkAccessibilityLabel: "Open \(context.placeName)",
                    destinationAction: { selectedDestination = .place },
                    destinationAccessibilityLabel: "Open \(context.placeName)",
                    openProfile: { selectedDestination = .profile },
                    actorAccessibilityIdentifier: "feed.photo-stack.actor",
                    destinationAccessibilityIdentifier: "feed.photo-stack.place",
                    postcardAccessibilityIdentifier: "feed.photo-stack.postcard"
                )
                .padding(WanderTheme.spacing4)
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .astirScreen()
            .sheet(item: $selectedDestination) { destination in
                NavigationStack {
                    Text(destination == .profile ? "Ryan Lieblein’s profile" : context.placeName)
                        .font(AstirTypography.sectionTitle)
                        .accessibilityIdentifier("feed.photo-stack.\(destination.rawValue).opened")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .astirScreen()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { selectedDestination = nil }
                                    .accessibilityIdentifier("feed.photo-stack.destination.done")
                            }
                        }
                }
            }
        }
        .environmentObject(store)
        .environmentObject(auth)
        .environmentObject(backend)
        .environmentObject(activityNavigation)
        .environmentObject(productUpsells)
        .environment(\.activityPostcardVisualStyle, .astir)
        .astirAdaptiveBrandMode()
    }

    private enum Destination: String, Identifiable {
        case profile, place
        var id: String { rawValue }
    }

}

/// Shared app-bundled photos for isolated native postcard reviews only.
enum ActivityPostcardPhotoUITestFixtures {
    private struct FixturePhoto: Sendable {
        let id: String
        let localAssetRef: String
        let accessibilityLabel: String

        var media: ActivityEngagementMedia {
            ActivityEngagementMedia(id: id, localAssetRef: localAssetRef,
                isPendingLocalCapture: true, accessibilityLabel: accessibilityLabel)
        }
    }

    // The lazy cache holds Sendable descriptors, not UIKit images. Normal app
    // launches never initialize it; all image bytes stay in the app sandbox.
    private static let preparedPhotos = preparePhotos()

    static func photos() -> [ActivityEngagementMedia] { preparedPhotos.map(\.media) }

    static func isLiveEnabled(arguments: [String]) -> Bool {
        #if targetEnvironment(simulator)
        let required: Set<String> = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderLiveFeedPhotosUITest"]
        let excluded: Set<String> = ["-WanderUseLiveAuth", "-WanderForceSignedOut", "-WanderAuthUITest",
            "-WanderOnboardingUITestSignedOut", "-WanderFeedPhotoStackUITest",
            "-WanderUseStorefrontFixtures", "-WanderUsePerformanceFixtures", "-WanderUseEphemeralEmptyFixtures"]
        let supplied = Set(arguments)
        return required.isSubset(of: supplied) && excluded.isDisjoint(with: supplied)
        #else
        return false
        #endif
    }

    static func liveFeedMedia(arguments: [String] = ProcessInfo.processInfo.arguments) -> [FeedMediaPreview] {
        guard isLiveEnabled(arguments: arguments) else { return [] }
        return photos().map { FeedMediaPreview(id: $0.id, accessibilityLabel: $0.accessibilityLabel) }
    }

    static func livePhoto(matching preview: FeedMediaPreview,
                          arguments: [String] = ProcessInfo.processInfo.arguments) -> ActivityEngagementMedia? {
        guard (isLiveEnabled(arguments: arguments) || isSharedReviewEnabled(arguments: arguments)), preview.urlString == nil,
              preview.storageBucket == nil, preview.storagePath == nil else { return nil }
        return photos().first { $0.id == preview.id && $0.accessibilityLabel == preview.accessibilityLabel }
    }

    static func isSharedReviewEnabled(arguments: [String]) -> Bool {
        #if targetEnvironment(simulator)
        let args = Set(arguments)
        return args.contains("-WanderFeedPhotoStackUITest") && args.contains("-WanderSharedVisitReview")
            && !args.contains("-WanderUseLiveAuth") && !args.contains("-WanderForceSignedOut")
        #else
        return false
        #endif
    }

    private static func preparePhotos() -> [FixturePhoto] {
        guard let source = UIImage(named: "PlaceCarouselPhotos")?.cgImage else { return [] }
        let width = source.width / 2
        let height = source.height / 2
        return (0..<3).compactMap { index in
            let rect = CGRect(x: (index % 2) * width, y: (index / 2) * height, width: width, height: height)
            guard let crop = source.cropping(to: rect),
                  let data = UIImage(cgImage: crop).jpegData(compressionQuality: 0.85),
                  let id = UUID(uuidString: "64000000-0000-0000-0000-00000000064\(index + 1)"),
                  let localAssetRef = VisitPhotoLocalFileStore.save(data: data, id: id, contentType: "image/jpeg")
            else { return nil }
            return FixturePhoto(
                id: id.uuidString.lowercased(), localAssetRef: localAssetRef,
                accessibilityLabel: "Sample check-in photo \(index + 1)"
            )
        }
    }
}
#endif
