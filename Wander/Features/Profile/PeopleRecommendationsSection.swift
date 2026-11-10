import SwiftUI

/// Profile and Invite share the existing ranked recommendations and acknowledged follows.
/// Only transient request feedback belongs to this view; eligibility stays in the store.
struct PeopleRecommendationsSection: View {
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    var horizontalInset: CGFloat = WanderTheme.spacing4
    var seeAll: (() -> Void)? = nil
    @State private var followingProfileIDs: Set<String> = []
    @State private var failedProfileIDs: Set<String> = []
    @State private var selectedProfile: PeopleRecommendationProfileRoute?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .firstTextBaseline) {
                Text("People worth following")
                    .font(AstirTypography.sectionTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let seeAll {
                    Button("See all", action: seeAll)
                        .font(AstirTypography.label)
                        .fixedSize()
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("profile.people.seeAll")
                }
            }

            if !store.visibleDiscoverPeopleRecommendations.isEmpty {
                PeopleRecommendationShelf(
                    recommendations: store.visibleDiscoverPeopleRecommendations,
                    isFollowing: { store.hasAcknowledgedFollow(to: $0) },
                    isFollowInFlight: { followingProfileIDs.contains($0) },
                    didFollowFail: { failedProfileIDs.contains($0) },
                    open: { selectedProfile = PeopleRecommendationProfileRoute(id: $0.id) },
                    follow: follow,
                    showsTitle: false,
                    horizontalInset: horizontalInset
                )
            } else {
                switch store.discoverPeopleRecommendationsState {
                case .idle, .loading:
                    if auth.isSignedIn {
                        PeopleRecommendationLoadingShelf(showsTitle: false, horizontalInset: horizontalInset)
                    } else {
                        Button("Sign in to find people") { auth.presentGate(for: .followPeople) }
                            .font(AstirTypography.control)
                            .frame(minHeight: 44)
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        Text("Suggestions couldn’t load")
                            .font(AstirTypography.bodySmall)
                            .foregroundStyle(brandMode.secondaryText)
                        Button("Try again") {
                            Task { await store.refreshDiscoverPeopleRecommendations(backend: backend, force: true) }
                        }
                        .font(AstirTypography.control)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("people.recommendations.retry")
                    }
                case .loaded:
                    Text("You’re all caught up. More people will appear here as your circle grows.")
                        .font(AstirTypography.bodySmall)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .task(id: "\(store.currentUser.id)-\(auth.isSignedIn)") {
            await store.refreshDiscoverPeopleRecommendations(backend: auth.isSignedIn ? backend : nil)
        }
        .onChange(of: store.currentUser.id) { _, _ in
            followingProfileIDs = []
            failedProfileIDs = []
            selectedProfile = nil
        }
        .fullScreenCover(item: $selectedProfile) { route in
            ProfileDetailView(profileID: route.id)
        }
        .blocksProductUpsells(while: selectedProfile != nil)
    }

    private func follow(_ recommendation: DiscoverPeopleRecommendation) {
        let id = recommendation.id
        guard !followingProfileIDs.contains(id) else { return }
        auth.requireSignIn(for: .followPeople) {
            let userID = store.currentUser.id
            followingProfileIDs.insert(id)
            failedProfileIDs.remove(id)
            Task { @MainActor in
                await Task.yield()
                let succeeded = await store.followRecommendation(userID: id, backend: auth.isSignedIn ? backend : nil)
                guard store.currentUser.id == userID else { return }
                followingProfileIDs.remove(id)
                if !succeeded { failedProfileIDs.insert(id) }
            }
        }
    }
}

private struct PeopleRecommendationProfileRoute: Identifiable {
    let id: String
}

struct ProfilePeopleDisclosure: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { isExpanded.toggle() }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(brandMode.primaryText)
                .frame(width: 44, height: 44)
                .background(brandMode.primaryText.opacity(brandMode.prefersDarkInterface ? 0.10 : 0.055),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("People worth following")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Hide suggested people" : "Show suggested people")
        .accessibilityIdentifier("profile.people.toggle")
    }
}
