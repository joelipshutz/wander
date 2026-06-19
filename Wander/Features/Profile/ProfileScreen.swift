import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var showsSettings = false
    @State private var listMode: GraphListMode?
    @State private var selectedPeopleMode: GraphListMode = .following

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    pageTitle
                    ownerHeader
                    statsGrid
                    monthCard
                    draftsSection
                    recentSection
                    peopleSection
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .wanderScreen()
            .sheet(isPresented: $showsSettings) {
                SettingsScreen()
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $listMode) { mode in
                GraphListScreen(mode: mode)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .task(id: auth.isSignedIn) {
                guard auth.isSignedIn else { return }
                await store.refreshRemoteSocialGraph(backend: backend)
            }
        }
    }

    private var pageTitle: some View {
        Text("profile")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private var ownerHeader: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top) {
                WanderAvatar(initials: store.currentUser.initials, size: 56, color: WanderTheme.terracotta.color)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(store.currentUser.displayName)
                        .font(.system(size: 24, weight: .black))
                    Text("@\(store.currentUser.handle) · \(store.currentUser.homeArea ?? "Los Angeles")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Button {
                    showsSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var statsGrid: some View {
        HStack(spacing: WanderTheme.spacing3) {
            StatTile(value: "\(store.stats.been)", label: "BEEN", color: WanderTheme.terracotta.color, fill: WanderTheme.terracottaTint.color)
            StatTile(value: "\(store.stats.wanna)", label: "WANNA", color: WanderTheme.stateWarning.color, fill: WanderTheme.sunTint.color)
        }
    }

    private var monthCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("this month")
                    .font(.system(size: 17, weight: .black))
                Spacer()
                Text("JUN '26")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            HStack(alignment: .center, spacing: WanderTheme.spacing4) {
                Text("\(store.currentUserVisiblePlaces.count)")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                Text("saved places this month.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Spacer()
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }

    private var draftsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("drafts")
                .font(.system(size: 17, weight: .black))

            if store.unresolvedDrafts.isEmpty {
                SmallEmptyRow(title: "No unresolved drafts", subtitle: "link and photo shells land here")
            } else {
                ForEach(store.unresolvedDrafts) { draft in
                    HStack {
                        Image(systemName: draft.sourceType == .link ? "link" : "photo")
                            .foregroundStyle(WanderTheme.terracotta.color)
                        VStack(alignment: .leading) {
                            Text(draft.title)
                                .font(.system(size: 15, weight: .bold))
                            Text(draft.message)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                Text("recent")
                    .font(.system(size: 17, weight: .black))
                Spacer()
            }

            ForEach(store.currentUserVisiblePlaces) { visiblePlace in
                ProfilePlaceRow(visiblePlace: visiblePlace)
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Text("people")
                .font(.system(size: 17, weight: .black))

            WanderSegmentedSwitch(
                options: GraphListMode.allCases.map { mode in
                    WanderSegmentOption(id: mode.rawValue, title: mode.title)
                },
                selection: Binding(
                    get: { selectedPeopleMode.rawValue },
                    set: { selectedPeopleMode = GraphListMode(rawValue: $0) ?? .following }
                )
            )

            let people = people(for: selectedPeopleMode)
            if people.isEmpty {
                SmallEmptyRow(title: "No \(selectedPeopleMode.title) yet", subtitle: selectedPeopleMode.emptySubtitle)
            } else {
                ForEach(people, id: \.id) { profile in
                    ProfilePersonRow(profile: profile, relationship: store.relationship(to: profile.id)) {
                        listMode = selectedPeopleMode
                    }
                }
            }
        }
    }

    private func people(for mode: GraphListMode) -> [LocalProfile] {
        switch mode {
        case .following:
            return store.following(of: store.currentUser.id)
        case .followers:
            return store.followers(of: store.currentUser.id)
        case .friends:
            return store.following(of: store.currentUser.id).filter { store.relationship(to: $0.id) == .mutual }
        }
    }
}

struct ProfileDetailView: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let profileID: String
    @State private var showBlockConfirm = false

    private var state: ProfileViewState? {
        store.profileState(for: profileID)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let state {
                    VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                        profileHeader(state: state)

                        if state.isBlocked {
                            AccessChangedPanel(title: "This profile isn't available", subtitle: "Blocked profiles stay out of search, lists, and map results.")
                        } else if state.visiblePlaces.isEmpty && state.shell.relationship == .nonFollower {
                            AccessChangedPanel(title: "Follow to see shared places", subtitle: "You'll only see places this person shares with followers.")
                        } else {
                            ForEach(state.visiblePlaces) { visiblePlace in
                                ProfilePlaceRow(visiblePlace: visiblePlace)
                            }
                        }
                    }
                    .padding(WanderTheme.spacing3)
                }
            }
            .wanderScreen()
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Block this person?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    auth.requireSignIn(for: .manageBlocks) {
                        Task {
                            await store.block(userID: profileID, backend: backend)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You won't see each other's profiles, places, or search results.")
            }
            .task(id: profileID) {
                await refreshRemoteProfile()
            }
        }
    }

    private func profileHeader(state: ProfileViewState) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            HStack(alignment: .top) {
                WanderAvatar(initials: initials(for: state.shell.displayName), size: 56, color: WanderTheme.pinSocial.color)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(state.shell.displayName)
                        .font(.system(size: 23, weight: .black))
                        .lineLimit(1)
                    Text("@\(state.shell.handle) · \(state.shell.relationship.displayTitle)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Menu {
                    if state.shell.relationship != .owner && state.shell.relationship != .nonFollower && !state.isBlocked {
                        Button("Unfollow", role: .destructive) {
                            auth.requireSignIn(for: .followPeople) {
                                Task {
                                    await store.unfollow(userID: state.shell.id, backend: backend)
                                    await refreshRemoteProfile()
                                }
                            }
                        }
                    }
                    Button("Block", role: .destructive) {
                        showBlockConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
            }

            if let bio = state.shell.bio {
                Text(bio)
                    .font(.system(size: 14))
                    .italic()
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            HStack {
                if state.shell.relationship == .nonFollower && !state.isBlocked {
                    WanderPrimaryButton(title: "follow", systemImage: "person.badge.plus") {
                        auth.requireSignIn(for: .followPeople) {
                            Task {
                                await store.follow(userID: state.shell.id, backend: backend)
                                await refreshRemoteProfile()
                            }
                        }
                    }
                } else if state.shell.relationship != .owner && !state.isBlocked {
                    Text(state.shell.relationship == .mutual ? "friend" : "following")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private func refreshRemoteProfile() async {
        await store.refreshRemoteProfileVisiblePlaces(profileID: profileID, backend: backend)
    }

    private func initials(for name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private enum GraphListMode: String, CaseIterable, Identifiable {
    case following
    case followers
    case friends

    var id: String { rawValue }

    var title: String {
        switch self {
        case .following: "following"
        case .followers: "followers"
        case .friends: "friends"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .following: "follow someone from contacts or username search"
        case .followers: "people who follow you will show up here"
        case .friends: "mutual follows show up here"
        }
    }
}

private struct GraphListScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let mode: GraphListMode

    private var profiles: [LocalProfile] {
        switch mode {
        case .followers:
            return store.followers(of: store.currentUser.id)
        case .following:
            return store.following(of: store.currentUser.id)
        case .friends:
            return store.following(of: store.currentUser.id).filter { store.relationship(to: $0.id) == .mutual }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(profiles, id: \.id) { profile in
                    HStack {
                        WanderAvatar(initials: profile.initials, size: 40, color: WanderTheme.pinSocial.color)
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                                .font(.system(size: 15, weight: .bold))
                            Text("@\(profile.handle) · \(store.relationship(to: profile.id).displayTitle)")
                                .font(.system(size: 13))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }
                        Spacer()
                        Button(store.relationship(to: profile.id) == .nonFollower ? "follow" : "unfollow") {
                            auth.requireSignIn(for: .followPeople) {
                                Task {
                                    if store.relationship(to: profile.id) == .nonFollower {
                                        await store.follow(userID: profile.id, backend: backend)
                                    } else {
                                        await store.unfollow(userID: profile.id, backend: backend)
                                    }
                                }
                            }
                        }
                        .font(.system(size: 13, weight: .bold))
                    }
                    .listRowBackground(WanderTheme.surfaceBone.color)
                }
            }
            .scrollContentBackground(.hidden)
            .wanderScreen()
            .navigationTitle(mode.rawValue.capitalized)
            .task {
                await store.refreshRemoteSocialGraph(backend: backend)
            }
        }
    }
}

private struct ConnectionRow: View {
    let title: String
    let subtitle: String
    let count: Int
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(width: 40, height: 40)
                    .background(WanderTheme.terracottaTint.color)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .frame(minWidth: 30, alignment: .trailing)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct ProfilePersonRow: View {
    let profile: LocalProfile
    let relationship: ViewerRelationship
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(initials: profile.initials, size: 40, color: WanderTheme.pinSocial.color)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(profile.displayName)
                        .font(.system(size: 15, weight: .bold))
                    Text("@\(profile.handle) · \(relationship.displayTitle)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    let color: Color
    let fill: Color

    var body: some View {
        VStack(spacing: WanderTheme.spacing1) {
            Text(value)
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct ProfilePlaceRow: View {
    let visiblePlace: VisiblePlace

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
                .frame(width: 40, height: 40)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(visiblePlace.place.canonicalName)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text("\(visiblePlace.place.locality ?? "Los Angeles") · \(visiblePlace.userPlace.status.displayTitle)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            Text(visiblePlace.userPlace.visibility.displayTitle)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var icon: String {
        WanderPlaceCategory.symbolName(for: visiblePlace.place.category)
    }
}

private struct SmallEmptyRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct AccessChangedPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}
