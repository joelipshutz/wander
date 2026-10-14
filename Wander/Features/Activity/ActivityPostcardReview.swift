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
            media: arguments.contains("-WanderFeedPhotoStackNoPhotos") ? [] : Self.fixturePhotos()
        )
    }

    var body: some View {
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

    private static func fixturePhotos() -> [ActivityEngagementMedia] {
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
            return ActivityEngagementMedia(
                id: id.uuidString.lowercased(), localAssetRef: localAssetRef,
                isPendingLocalCapture: true, accessibilityLabel: "Sample check-in photo \(index + 1)"
            )
        }
    }
}
#endif
