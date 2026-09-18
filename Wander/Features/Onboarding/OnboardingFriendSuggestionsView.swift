import SwiftUI

struct OnboardingFriendSuggestionsView: View {
    @Environment(\.astirBrandMode) private var brandMode
    let analytics: AnalyticsClient
    let continueAction: () -> Void
    @StateObject private var model: OnboardingFriendSuggestionsModel
    @FocusState private var searchFocused: Bool

    init(backend: WanderBackend, userID: String, analytics: AnalyticsClient, continueAction: @escaping () -> Void) {
        self.analytics = analytics
        self.continueAction = continueAction
        _model = StateObject(wrappedValue: OnboardingFriendSuggestionsModel(backend: backend, userID: userID))
    }

    var body: some View {
        OnboardingStepScaffold(step: .friends) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                OnboardingHeadline(
                    eyebrow: "YOUR PEOPLE",
                    title: "Connect with the people you love",
                    message: "Follow a few familiar people. See where life takes them."
                )
                .padding(.horizontal, WanderTheme.spacing4)

                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "magnifyingglass").foregroundStyle(brandMode.secondaryText)
                    TextField("Search name or username", text: $model.query)
                        .font(AstirTypography.bodySmall)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .accessibilityIdentifier("onboarding.friends.search")
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(WanderTheme.spacing3)
                .astirOutlinedSurface()
                .padding(.horizontal, WanderTheme.spacing4)

                results
            }
            .padding(.top, WanderTheme.spacing2)
        } footer: {
            WanderPrimaryButton(title: "Continue", isDisabled: model.isFollowing) {
                searchFocused = false
                analytics.track(AnalyticsEvent(
                    name: WanderAnalyticsEvents.onboardingFriendSuggestionsCompleted,
                    properties: ["selected_count": String(model.completedFollowCount), "followed_count": String(model.completedFollowCount)]
                ))
                continueAction()
            }
            .accessibilityIdentifier("onboarding.friends.continue")
        }
        .task { await model.load() }
        .task(id: model.normalizedQuery) { await model.search() }
    }

    @ViewBuilder
    private var results: some View {
        if model.loadingState == .failed {
            emptyState("Suggestions are taking a minute", message: "You can skip this and find people from Discover anytime.") {
                Task { await model.load() }
            }
        } else if model.loadingState != .loaded {
            loading("Finding people…")
        } else if model.isSearching && model.normalizedQuery.count < 2 {
            emptyState("Who are you looking for?", message: "Enter at least two letters of a name or username.")
        } else if model.isSearching && model.searchState == .loading {
            loading("Searching…")
        } else if model.isSearching && model.searchState == .failed {
            emptyState("Search couldn’t load", message: "Check your connection and try again.") {
                Task { await model.search() }
            }
        } else if model.visibleProfiles.isEmpty {
            emptyState(
                model.isSearching ? "No people found" : "Your people will show up here",
                message: model.isSearching ? "Try another name or username." : "Skip for now — we’ll keep finding trusted people as Astir grows."
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.visibleProfiles) { profile in
                        OnboardingFriendRow(
                            profile: profile,
                            isFollowing: model.isFollowed(profile),
                            isPending: model.pendingIDs.contains(profile.id),
                            error: model.followErrors[profile.id]
                        ) {
                            searchFocused = false
                            Task { await follow(profile) }
                        }
                        Divider().overlay(brandMode.border).padding(.leading, 62)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func loading(_ title: String) -> some View {
        ProgressView(title)
            .font(AstirTypography.bodySmall)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyState(_ title: String, message: String, retry: (() -> Void)? = nil) -> some View {
        VStack(spacing: WanderTheme.spacing3) {
            Text(title).font(AstirTypography.sectionTitle)
            Text(message).font(AstirTypography.bodySmall).foregroundStyle(brandMode.secondaryText)
            if let retry {
                Button("Try again", action: retry).font(AstirTypography.control)
            }
        }
        .multilineTextAlignment(.center)
        .padding(WanderTheme.spacing6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func follow(_ profile: ProfileShell) async {
        guard await model.follow(profile) else { return }
        analytics.track(AnalyticsEvent(
            name: WanderAnalyticsEvents.followCreated,
            properties: ["source": "onboarding_suggestions", "outcome": "succeeded", "followed_count": "1"]
        ))
        analytics.track(.engagement(
            need: .connect, action: .followCreated, surface: "onboarding_suggestions",
            properties: ["followed_count": "1"]
        ))
    }
}

private struct OnboardingFriendRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let profile: ProfileShell
    let isFollowing: Bool
    let isPending: Bool
    let error: String?
    let follow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: String(profile.displayName.prefix(2)).uppercased(),
                    avatarURL: profile.avatarURL, size: 50, color: WanderTheme.avatarSofia.color
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName).font(AstirTypography.cardTitle).lineLimit(1)
                    Text("@\(profile.handle)")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: WanderTheme.spacing1)
                Button(action: follow) {
                    HStack(spacing: 4) {
                        if isPending {
                            ProgressView().controlSize(.small)
                        } else if isFollowing {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                        }
                        Text(isFollowing ? "Following" : "Follow")
                            .font(AstirTypography.label)
                    }
                    .foregroundStyle(isFollowing ? brandMode.secondaryText : brandMode.accentForeground)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minWidth: 88, minHeight: WanderTheme.tapMinimum)
                    .background(isFollowing ? brandMode.border.opacity(0.3) : brandMode.accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(isFollowing || isPending)
                .accessibilityLabel(isFollowing ? "Following \(profile.displayName)" : "Follow \(profile.displayName)")
                .accessibilityIdentifier("onboarding.friends.follow.\(profile.id)")
            }
            if let error {
                Text(error).font(AstirTypography.caption).foregroundStyle(WanderTheme.stateError.color)
                    .padding(.leading, 62)
            }
        }
        .padding(.vertical, WanderTheme.spacing3)
    }
}
