import Foundation
import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var showsSettings = false
    @State private var listMode: GraphListMode?
    @State private var savedListMode: SavedPlacesListMode?
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
            .navigationDestination(item: $savedListMode) { mode in
                SavedPlacesListScreen(mode: mode)
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
            Button {
                savedListMode = .been
            } label: {
                StatTile(
                    value: "\(store.stats.been)",
                    label: "BEEN",
                    color: WanderTheme.stateSuccess.color,
                    fill: WanderTheme.categorySage.color.opacity(0.22)
                )
            }
            .buttonStyle(ProfileStatButtonStyle())
            .accessibilityLabel("Open been places")

            Button {
                savedListMode = .wanna
            } label: {
                StatTile(value: "\(store.stats.wanna)", label: "WANNA", color: WanderTheme.stateWarning.color, fill: WanderTheme.sunTint.color)
            }
            .buttonStyle(ProfileStatButtonStyle())
            .accessibilityLabel("Open wanna places")
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

private enum SavedPlacesListMode: String, Identifiable {
    case been
    case wanna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: "Been"
        case .wanna: "Wanna"
        }
    }

    var status: PlaceStatus {
        switch self {
        case .been: .been
        case .wanna: .wannaGo
        }
    }
}

private struct SavedPlacesListScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let mode: SavedPlacesListMode
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var selectedMetadataTag: String?
    @State private var isTagFilterExpanded = false
    @State private var tagFilterQuery = ""
    @State private var selectedPlace: VisiblePlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?

    private var places: [VisiblePlace] {
        store.currentUserVisiblePlaces
            .filter { $0.userPlace.status == mode.status }
            .filter(matchesSelectedCategory)
            .filter(matchesSelectedMetadataTag)
            .filter(matchesQuery)
            .sorted { lhs, rhs in
                lhs.place.canonicalName.localizedCaseInsensitiveCompare(rhs.place.canonicalName) == .orderedAscending
            }
    }

    private var allModePlaces: [VisiblePlace] {
        store.currentUserVisiblePlaces.filter { $0.userPlace.status == mode.status }
    }

    private var categories: [String] {
        Array(Set(allModePlaces.map(\.place.category))).sorted()
    }

    private var metadataTags: [String] {
        ProfileMetadataTagParser.uniqueTags(allModePlaces.flatMap(metadataTags(for:)))
    }

    private var filteredMetadataTags: [String] {
        let normalized = tagFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return metadataTags }
        return metadataTags.filter { $0.lowercased().contains(normalized) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                searchField
                filterSection(title: "type", values: categories, selectedValue: $selectedCategory)
                tagFilterDropdown

                if places.isEmpty {
                    SmallEmptyRow(title: "No matching places", subtitle: "try clearing search or filters")
                } else {
                    ForEach(places) { visiblePlace in
                        Button {
                            selectedPlace = visiblePlace
                        } label: {
                            ProfilePlaceRow(visiblePlace: visiblePlace)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows saved place details")
                    }
                }
            }
            .padding(WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .fullScreenCover(item: $selectedPlace) { selectedPlace in
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: selectedPlace),
                saves: saveSummaries(for: selectedPlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: .edit,
                onBack: {
                    self.selectedPlace = nil
                },
                onAction: {
                    beginEditSelectedPlace(selectedPlace)
                }
            )
        }
        .sheet(item: $placeSaveFlow) { context in
            MapPlaceSaveFlowSheet(context: context) { submission in
                await saveProfileFlowSubmission(submission)
            }
        }
        .wanderScreen()
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("search \(mode.title.lowercased())", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }

    private func filterSection(
        title: String,
        values: [String],
        selectedValue: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    Button {
                        selectedValue.wrappedValue = nil
                    } label: {
                        WanderChip(title: "all", isSelected: selectedValue.wrappedValue == nil)
                    }
                    .buttonStyle(.plain)

                    ForEach(values, id: \.self) { value in
                        Button {
                            selectedValue.wrappedValue = selectedValue.wrappedValue == value ? nil : value
                        } label: {
                            WanderChip(title: value, isSelected: selectedValue.wrappedValue == value)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var tagFilterDropdown: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("tags")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    isTagFilterExpanded.toggle()
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Text(selectedMetadataTag ?? "all tags")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(selectedMetadataTag == nil ? WanderTheme.textMuted.color : WanderTheme.textInk.color)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .rotationEffect(.degrees(isTagFilterExpanded ? 180 : 0))
                }
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tag filter")

            if isTagFilterExpanded {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(WanderTheme.textMuted.color)
                        TextField("search tags", text: $tagFilterQuery)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 40)
                    .background(WanderTheme.surfaceSand.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

                    ScrollView {
                        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                            tagOption(title: "all tags", value: nil)

                            if filteredMetadataTags.isEmpty {
                                Text(metadataTags.isEmpty ? "no tags saved yet" : "no matching tags")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                    .padding(.horizontal, WanderTheme.spacing2)
                            } else {
                                ForEach(filteredMetadataTags, id: \.self) { tag in
                                    tagOption(title: tag, value: tag)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                .padding(WanderTheme.spacing2)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func tagOption(title: String, value: String?) -> some View {
        Button {
            selectedMetadataTag = value
            tagFilterQuery = ""
            withAnimation(.easeOut(duration: 0.16)) {
                isTagFilterExpanded = false
            }
        } label: {
            HStack(spacing: WanderTheme.spacing2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Spacer()
                if selectedMetadataTag == value {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.stateSuccess.color)
                }
            }
            .frame(minHeight: 40)
            .padding(.horizontal, WanderTheme.spacing2)
            .background(selectedMetadataTag == value ? WanderTheme.categorySage.color.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSmall))
        }
        .buttonStyle(.plain)
    }

    private func matchesSelectedCategory(_ visiblePlace: VisiblePlace) -> Bool {
        guard let selectedCategory else { return true }
        return visiblePlace.place.category == selectedCategory
    }

    private func matchesSelectedMetadataTag(_ visiblePlace: VisiblePlace) -> Bool {
        guard let selectedMetadataTag else { return true }
        return metadataTags(for: visiblePlace).contains { $0.caseInsensitiveCompare(selectedMetadataTag) == .orderedSame }
    }

    private func matchesQuery(_ visiblePlace: VisiblePlace) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }

        let searchable = [
            visiblePlace.place.canonicalName,
            visiblePlace.place.category,
            visiblePlace.place.locality,
            visiblePlace.userPlace.note,
            visiblePlace.userPlace.ratingSignal,
            visiblePlace.recommendedScore.map(PlaceRating.averageDisplay)
        ].compactMap { $0?.lowercased() }
        return searchable.contains { $0.contains(normalized) }
            || metadataTags(for: visiblePlace).contains { $0.lowercased().contains(normalized) }
    }

    private func metadataTags(for visiblePlace: VisiblePlace) -> [String] {
        store.attributes(for: visiblePlace.userPlace.id)
            .flatMap { ProfileMetadataTagParser.tags(from: $0.valueJSON) }
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        let summaries = store.visiblePlaces()
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard !seen.contains(visiblePlace.userPlace.id) else { return false }
                seen.insert(visiblePlace.userPlace.id)
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
            }

        return summaries.sorted { lhs, rhs in
            if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
            if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
            if lhs.visiblePlace.id == selectedPlace.id { return true }
            if rhs.visiblePlace.id == selectedPlace.id { return false }
            return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(rhs.visiblePlace.owner.displayName) == .orderedAscending
        }
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
        }
    }

    private func beginEditSelectedPlace(_ visiblePlace: VisiblePlace) {
        let context = MapPlaceSaveContext.editVisiblePlace(
            visiblePlace,
            attributes: store.attributes(for: visiblePlace.userPlace.id)
        )
        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            placeSaveFlow = context
        }
    }

    @MainActor
    private func saveProfileFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        switch submission.context.mode {
        case .add(let sourceType):
            let result = await store.saveCandidate(
                submission.context.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: sourceType,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        case .edit(let visiblePlace):
            let result = await store.saveCandidate(
                submission.context.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: AddSourceType(rawValue: visiblePlace.userPlace.sourceType) ?? .manual,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        }
    }
}

enum ProfileMetadataTagParser {
    static func tags(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return [] }

        if let string = value as? String {
            return uniqueTags([string])
        }
        if let strings = value as? [String] {
            return uniqueTags(strings)
        }
        return []
    }

    static func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(trimmed)
        }

        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                Text(value)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(color)

                Spacer(minLength: WanderTheme.spacing2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .black))
                    .frame(width: 28, height: 28)
                    .background(WanderTheme.surfaceRaised.color.opacity(0.85))
                    .foregroundStyle(color)
                    .clipShape(Circle())
            }

            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(color.opacity(0.28), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct ProfileStatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
            if let recommendedScore = visiblePlace.recommendedScore,
               visiblePlace.recommendedCount > 0 {
                RecommendedScorePill(score: recommendedScore)
            }
            PlaceVisibilityIconPill(visibility: visiblePlace.userPlace.visibility, size: 30)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var icon: String {
        WanderPlaceCategory.symbolName(for: visiblePlace.place.category)
    }

    private var subtitle: String {
        let locality = visiblePlace.place.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality, !locality.isEmpty else {
            return visiblePlace.userPlace.status.displayTitle
        }
        return "\(locality) · \(visiblePlace.userPlace.status.displayTitle)"
    }
}

private struct RecommendedScorePill: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .black))
            Text(PlaceRating.averageDisplay(score))
                .font(.system(size: 12, weight: .black))
        }
        .foregroundStyle(WanderTheme.terracotta.color)
        .padding(.horizontal, WanderTheme.spacing2)
        .frame(height: 30)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        .accessibilityLabel("Recommended score \(PlaceRating.averageDisplay(score)) out of 5")
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
