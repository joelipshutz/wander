import SwiftUI

enum ProfileSocialGraphTab: String, CaseIterable, Identifiable {
    case followers
    case following
    case friends

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var emptyTitle: String {
        switch self {
        case .followers: "No followers yet"
        case .following: "You are not following anyone yet"
        case .friends: "No friends yet"
        }
    }

    var emptyMessage: String {
        switch self {
        case .followers: "Members who follow you will appear here."
        case .following: "Find people you trust and follow their maps."
        case .friends: "Friends appear when you follow each other."
        }
    }
}

struct ProfileSocialGraphScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.astirBrandMode) private var brandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend

    @State private var selectedTab: ProfileSocialGraphTab
    @State private var query = ""
    @State private var selectedProfileID: ProfileGraphProfileID?
    @State private var pendingUnfollow: LocalProfile?
    @State private var isRefreshing = false
    let profileID: String
    let onFindFriends: () -> Void

    init(profileID: String, initialTab: ProfileSocialGraphTab, onFindFriends: @escaping () -> Void) {
        self.profileID = profileID
        _selectedTab = State(initialValue: initialTab)
        self.onFindFriends = onFindFriends
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    AstirEditorialSegmentedSwitch(
                        options: ProfileSocialGraphTab.allCases.map {
                            WanderSegmentOption(id: $0.rawValue, title: $0.title)
                        },
                        selection: Binding(
                            get: { selectedTab.rawValue },
                            set: { selectedTab = ProfileSocialGraphTab(rawValue: $0) ?? .followers }
                        )
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Connections")

                    ProfileGraphSearchField(query: $query)

                    if isOwnerGraph {
                        Button {
                            dismiss()
                            onFindFriends()
                        } label: {
                            HStack(spacing: WanderTheme.spacing3) {
                                Image(systemName: "person.badge.plus")
                                    .font(.system(size: 17, weight: .black))
                                    .frame(width: 36, height: 36)
                                    .background(brandMode.accentWash)
                                    .foregroundStyle(brandMode.accent)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Find friends")
                                        .font(AstirTypography.cardTitle)
                                    Text("Search rec.me members")
                                        .font(AstirTypography.caption)
                                        .foregroundStyle(brandMode.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(brandMode.secondaryText)
                            }
                            .padding(.horizontal, WanderTheme.spacing3)
                            .frame(minHeight: 62)
                            .background(brandMode.raisedBackground)
                            .foregroundStyle(brandMode.primaryText)
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                    .stroke(brandMode.border)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if isRefreshing && profiles.isEmpty {
                        ProgressView("Loading connections")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if profiles.isEmpty {
                        ProfileGraphEmptyState(tab: selectedTab)
                    } else {
                        LazyVStack(spacing: WanderTheme.spacing2) {
                            ForEach(profiles) { profile in
                                ProfileGraphRow(
                                    profile: profile,
                                    relationship: store.relationship(to: profile.id),
                                    action: { handleFollowAction(profile) },
                                    select: { selectedProfileID = ProfileGraphProfileID(id: profile.id) }
                                )
                            }
                        }
                    }

                    if let error = store.lastRemoteError, !error.isEmpty {
                        Button("Could not refresh. Try again") {
                            Task { await refresh() }
                        }
                        .font(AstirTypography.control)
                        .foregroundStyle(WanderTheme.stateError.color)
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .astirScreen()
            .navigationTitle(isOwnerGraph ? "friends" : "connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                        .font(AstirTypography.control)
                        .foregroundStyle(brandMode.accent)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
            .fullScreenCover(item: $selectedProfileID) { selection in
                ProfileDetailView(profileID: selection.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .alert("Unfollow \(pendingUnfollow?.displayName ?? "this member")?", isPresented: Binding(
                get: { pendingUnfollow != nil },
                set: { if !$0 { pendingUnfollow = nil } }
            )) {
                Button("Unfollow", role: .destructive) {
                    guard let profile = pendingUnfollow else { return }
                    pendingUnfollow = nil
                    Task { await store.unfollow(userID: profile.id, backend: backend) }
                }
                Button("Cancel", role: .cancel) { pendingUnfollow = nil }
            } message: {
                Text("Their places will stop appearing in your social map.")
            }
        }
    }

    private var profiles: [LocalProfile] {
        let base: [LocalProfile]
        switch selectedTab {
        case .followers: base = store.followers(of: profileID)
        case .following: base = store.following(of: profileID)
        case .friends: base = store.friends(of: profileID)
        }

        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return base }
        return base.filter {
            $0.displayName.lowercased().contains(normalized)
                || $0.handle.lowercased().contains(normalized.replacingOccurrences(of: "@", with: ""))
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await store.refreshRemoteSocialGraph(userID: profileID, backend: backend)
        isRefreshing = false
    }

    private var isOwnerGraph: Bool {
        profileID == store.currentUser.id
    }

    private func handleFollowAction(_ profile: LocalProfile) {
        auth.requireSignIn(for: .followPeople) {
            switch store.relationship(to: profile.id) {
            case .follower, .mutual:
                pendingUnfollow = profile
            case .nonFollower:
                Task { await store.follow(userID: profile.id, source: .profile, backend: backend) }
            case .owner:
                break
            }
        }
    }
}

private struct ProfileGraphProfileID: Identifiable {
    let id: String
}

private struct ProfileGraphSearchField: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var query: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(brandMode.secondaryText)
            TextField("Search people", text: $query)
                .font(AstirTypography.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 48)
        .foregroundStyle(brandMode.primaryText)
        .background(brandMode.recessedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                .stroke(brandMode.border)
        )
    }
}

private struct ProfileGraphRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let profile: LocalProfile
    let relationship: ViewerRelationship
    let action: () -> Void
    let select: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: select) {
                HStack(spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: profile.initials,
                        avatarURL: profile.avatarURL,
                        size: 46,
                        color: WanderTheme.avatarRyan.color
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.displayName)
                            .font(AstirTypography.cardTitle)
                            .foregroundStyle(brandMode.primaryText)
                        Text("@\(profile.handle)  •  \(relationshipLabel)")
                            .font(AstirTypography.caption)
                            .foregroundStyle(brandMode.secondaryText)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: WanderTheme.spacing2)

            if relationship != .owner {
                Button(actionTitle, action: action)
                    .font(AstirTypography.label)
                    .foregroundStyle(relationship == .nonFollower ? brandMode.accentForeground : brandMode.primaryText)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .background(relationship == .nonFollower ? brandMode.accent : brandMode.recessedBackground)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                            .stroke(relationship == .nonFollower ? brandMode.accent : brandMode.border)
                    )
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 66)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                .stroke(brandMode.border)
        )
    }

    private var relationshipLabel: String {
        switch relationship {
        case .owner: "You"
        case .mutual: "Friend"
        case .follower: "Following"
        case .nonFollower: "Follows you"
        }
    }

    private var actionTitle: String {
        relationship == .nonFollower ? "Follow" : "Following"
    }
}

private struct ProfileGraphEmptyState: View {
    @Environment(\.astirBrandMode) private var brandMode
    let tab: ProfileSocialGraphTab

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(brandMode.accent)
                .frame(width: 62, height: 62)
                .background(brandMode.accentWash)
                .clipShape(Circle())
            Text(tab.emptyTitle)
                .font(AstirTypography.sectionTitle)
            Text(tab.emptyMessage)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .padding(WanderTheme.spacing4)
    }
}
