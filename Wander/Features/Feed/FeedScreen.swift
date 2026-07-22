import SwiftUI

struct FeedScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var isShowingSearch = false
    @State private var selectedProfile: FeedProfileRoute?
    @State private var selectedPlace: VisiblePlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?
    @State private var savedMessage: String?
    @State private var followingProfileIDs = Set<String>()
    @State private var selectedSurface: FeedSurface = .places

    private let tickerSuggestions = [
        "Joe's favorite coffee shops in LA",
        "Maya's date night spots",
        "quiet work cafes with wifi",
        "friends' sunset hikes"
    ]

    private var page: FollowedFeedPage? { store.followedFeedPage }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FeedSurfaceTabs(selectedSurface: $selectedSurface)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing2)

                switch selectedSurface {
                case .places:
                    placesSurface
                case .people:
                    FeedPeopleSurface(openProfile: openProfile)
                }
            }
            .wanderScreen()
            .task(id: auth.isSignedIn) {
                await refresh()
            }
            .fullScreenCover(isPresented: $isShowingSearch) {
                DiscoverScreen()
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .fullScreenCover(item: $selectedProfile) { route in
                ProfileDetailView(profileID: route.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
                selectedPlaceDestination
            }
            .sheet(item: $placeSaveFlow) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveFeedFlowSubmission(submission)
                } onRemove: { _ in
                    false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert("Saved to your map", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("OK", role: .cancel) { savedMessage = nil }
            } message: {
                Text(savedMessage ?? "")
            }
        }
    }

    private var placesSurface: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                FeedSearchLauncher(placeholders: tickerSuggestions) {
                    isShowingSearch = true
                }

                content
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.feedLoadState == .loading, page == nil {
            FeedLoadingState()
        } else if let page, !page.activity.isEmpty {
            if !page.featuredPlaces.isEmpty {
                FeedSectionHeading(title: "Featured for you")
                FeedFeaturedRail(
                    places: page.featuredPlaces,
                    openProfile: openProfile,
                    save: saveFeaturedPlace
                )
            }

            FeedSectionHeading(title: "Your feed", detail: freshnessDetail)
            FeedActivityList(
                activity: page.activity,
                openProfile: openProfile,
                openPlace: openPlace,
                save: save,
                openList: openList
            )

            if store.feedLoadState == .stale {
                FeedRetryRow(
                    title: "Updated earlier",
                    subtitle: "We’ll keep this cached Feed until it reconnects.",
                    actionTitle: "Retry",
                    retry: refresh
                )
            }
        } else if store.feedLoadState == .failed || store.feedLoadState == .stale {
            FeedRefreshRecoveryState(retry: refresh)
        } else {
            FeedSectionHeading(title: "Your feed")
            FeedEmptyState(
                recommendations: peopleRecommendations,
                followingProfileIDs: followingProfileIDs,
                openSearch: { isShowingSearch = true },
                openProfile: openProfile,
                follow: follow
            )

        }
    }

    private var freshnessDetail: String? {
        guard store.feedLoadState == .stale else { return nil }
        return "Updated earlier"
    }

    private var peopleRecommendations: [DiscoverPeopleRecommendation] {
        guard case .loaded(let recommendations) = store.discoverPeopleRecommendationsState else {
            return []
        }
        return Array(recommendations.prefix(3))
    }

    private func refresh() async {
        _ = await store.refreshFollowedFeed(backend: auth.isSignedIn ? backend : nil)
        guard store.followedFeedPage?.activity.isEmpty != false else { return }
        await store.refreshDiscoverPeopleRecommendations(backend: auth.isSignedIn ? backend : nil)
    }

    private func openProfile(_ profile: ProfileShell) {
        selectedProfile = FeedProfileRoute(id: profile.id)
    }

    private func openPlace(_ visiblePlace: VisiblePlace) {
        selectedPlace = visiblePlace
    }

    private func openList(_ list: LocalPlaceList) {
        pushNotifications.route(to: .list(id: list.id))
    }

    private func saveFeaturedPlace(_ featured: FeedFeaturedPlace) {
        beginSave(visiblePlace: featured.visiblePlace)
    }

    private func save(_ activity: FeedActivity) {
        guard let place = activity.place else { return }
        beginSave(visiblePlace: place)
    }

    private func beginSave(visiblePlace: VisiblePlace) {
        auth.requireSignIn(for: .socialSave) {
            presentPlaceSaveFlow(MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.effectiveDefaultVisibility,
                attributes: attributes(for: visiblePlace)
            ))
        }
    }

    private func beginPlaceProfileAction(_ visiblePlace: VisiblePlace) {
        guard let currentUserSave = currentUserSave(matching: visiblePlace) else {
            beginSave(visiblePlace: visiblePlace)
            return
        }

        presentPlaceSaveFlow(MapPlaceSaveContext.addVisitVisiblePlace(
            currentUserSave,
            attributes: store.attributes(for: currentUserSave.userPlace.id),
            latestVisit: store.visits(for: currentUserSave.userPlace.id).first
        ))
    }

    private func presentPlaceSaveFlow(_ context: MapPlaceSaveContext) {
        guard selectedPlace != nil else {
            placeSaveFlow = context
            return
        }

        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            placeSaveFlow = context
        }
    }

    @MainActor
    private func saveFeedFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let visitBackend = auth.isSignedIn ? backend : nil
        switch submission.context.mode {
        case .add(let sourceType):
            guard sourceType != .socialSave || auth.isSignedIn else {
                placeSaveFlow = nil
                auth.presentGate(for: .socialSave)
                return nil
            }

            guard let result = await persistNewPlaceSaveSubmission(
                submission,
                store: store,
                backend: visitBackend
            ) else { return nil }

            await refresh()
            savedMessage = result.syncState == .synced
                ? "Saved."
                : "Saved locally. We'll retry sync."
            return result

        case .addVisit, .editVisit, .editWant:
            let (result, targetVisit) = await persistScopedVisitOrWantSubmission(
                submission,
                store: store,
                backend: visitBackend
            )
            guard let result else { return nil }

            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            await refresh()
            savedMessage = result.syncState == .synced
                ? "Visit saved."
                : "Saved locally. We'll retry sync."
            return result

        case .sharedVisit:
            return nil
        }
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedPlace != nil },
            set: { isPresented in
                if !isPresented {
                    selectedPlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceDestination: some View {
        if let selectedPlace {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: selectedPlace),
                saves: saveSummaries(for: selectedPlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: PlaceSheetAction.topLevelAction(currentUserSave: currentUserSave(matching: selectedPlace)),
                onBack: {
                    self.selectedPlace = nil
                },
                onAction: {
                    beginPlaceProfileAction(selectedPlace)
                }
            )
        }
    }

    private func attributes(for visiblePlace: VisiblePlace) -> [LocalPlaceAttribute] {
        let storeAttributes = store.attributes(for: visiblePlace.userPlace.id)
        return storeAttributes.isEmpty ? visiblePlace.attributes : storeAttributes
    }

    private func currentUserSave(matching visiblePlace: VisiblePlace) -> VisiblePlace? {
        store.currentUserVisiblePlaces.first { currentUserPlace in
            VisiblePlaceGrouping.matches(currentUserPlace, visiblePlace)
        }
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        let feedPlaces = (page?.activity.compactMap(\.place) ?? [])
            + (page?.featuredPlaces.map(\.visiblePlace) ?? [])

        return (store.visiblePlaces() + feedPlaces)
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard !seen.contains(visiblePlace.userPlace.id) else { return false }
                seen.insert(visiblePlace.userPlace.id)
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(visiblePlace: visiblePlace, attributes: attributes(for: visiblePlace))
            }
            .sorted { lhs, rhs in
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

    private func follow(_ recommendation: DiscoverPeopleRecommendation) {
        guard !followingProfileIDs.contains(recommendation.profile.id) else { return }
        auth.requireSignIn(for: .followPeople) {
            Task { @MainActor in
                followingProfileIDs.insert(recommendation.profile.id)
                _ = await store.follow(
                    userID: recommendation.profile.id,
                    source: .profile,
                    backend: auth.isSignedIn ? backend : nil
                )
                followingProfileIDs.remove(recommendation.profile.id)
                await refresh()
            }
        }
    }
}

private enum FeedSurface: String, CaseIterable, Identifiable {
    case places
    case people

    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: "Places"
        case .people: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .places: "mappin.and.ellipse"
        case .people: "person.2"
        }
    }
}

private struct FeedSurfaceTabs: View {
    @Binding var selectedSurface: FeedSurface

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FeedSurface.allCases) { surface in
                Button {
                    selectedSurface = surface
                } label: {
                    VStack(spacing: WanderTheme.spacing1) {
                        HStack(spacing: WanderTheme.spacing2) {
                            Image(systemName: surface.systemImage)
                                .font(.system(size: 15, weight: .black))
                            Text(surface.title)
                                .font(.system(size: 16, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(
                            selectedSurface == surface
                                ? WanderTheme.textInk.color
                                : WanderTheme.textMuted.color
                        )
                        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)

                        Rectangle()
                            .fill(selectedSurface == surface ? WanderTheme.textInk.color : .clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedSurface == surface ? .isSelected : [])
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
                .zIndex(-1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feed section")
    }
}

private struct FeedPeopleSurface: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let openProfile: (ProfileShell) -> Void

    @State private var memberQuery = ""
    @State private var memberResults: [ProfileShell] = []
    @State private var followInFlightProfileIDs: Set<String> = []
    @State private var followFailedProfileIDs: Set<String> = []
    @FocusState private var searchFieldFocused: Bool

    private var isMemberSearchActive: Bool {
        !memberQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followingProfiles: [ProfileShell] {
        store.following(of: store.currentUser.id)
            .map(store.shell(for:))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                FeedPeopleSearchField(text: $memberQuery)
                    .focused($searchFieldFocused)

                if isMemberSearchActive {
                    memberSearchResultsSection
                } else {
                    FeedPeopleValueNote()
                    peopleRecommendationsSection
                    peopleSection
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await refreshRecommendations()
        }
        .task(id: auth.isSignedIn) {
            await refreshRecommendations()
        }
        .task(id: memberQuery) {
            await refreshMembers(query: memberQuery, debounce: true)
        }
    }

    @ViewBuilder
    private var peopleRecommendationsSection: some View {
        switch store.discoverPeopleRecommendationsState {
        case .idle where !auth.isSignedIn:
            FeedPeopleActionPanel(
                icon: "person.crop.circle.badge.plus",
                title: "Find people you trust",
                message: "Sign in to see people worth following.",
                actionTitle: "Sign in"
            ) {
                auth.presentGate(for: .followPeople)
            }
        case .idle, .loading:
            FeedPeopleLoadingPanel(label: "Finding people")
        case .failed:
            FeedPeopleActionPanel(
                icon: "arrow.clockwise",
                title: "Suggestions couldn't load",
                message: "Search still works, or try these suggestions again.",
                actionTitle: "Try again"
            ) {
                Task { await refreshRecommendations(force: true) }
            }
        case .loaded(let recommendations) where recommendations.isEmpty:
            FeedPeopleEmptyPanel(
                title: "No suggestions yet",
                message: "Search a name or @handle above."
            )
        case .loaded(let recommendations):
            PeopleRecommendationShelf(
                recommendations: recommendations,
                isFollowing: { store.hasAcknowledgedFollow(to: $0) },
                isFollowInFlight: { followInFlightProfileIDs.contains($0) },
                didFollowFail: { followFailedProfileIDs.contains($0) },
                open: { openProfile($0.profile) },
                follow: followRecommendation
            )
        }
    }

    private var memberSearchResultsSection: some View {
        let profiles = memberResults.map(latestProfileShell)
        let recommendationCounts = store.visiblePlaceCountsByOwnerID()
        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            FeedSectionHeading(title: "People results")

            if profiles.isEmpty {
                FeedPeopleEmptyPanel(
                    title: "No people found",
                    message: "Try a handle or full first name."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: WanderTheme.spacing3) {
                        ForEach(profiles) { profile in
                            FeedMemberResultTile(
                                profile: profile,
                                recCount: recommendationCounts[profile.id, default: 0]
                            ) {
                                openProfile(profile)
                            }
                        }
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
            }
        }
    }

    private var peopleSection: some View {
        let recommendationCounts = store.visiblePlaceCountsByOwnerID()
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                FeedSectionHeading(title: "People")
                Spacer()
                Text("\(followingProfiles.count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if followingProfiles.isEmpty {
                FeedPeopleEmptyPanel(
                    title: "No one followed yet",
                    message: "Follow someone above or search by name."
                )
            } else {
                ForEach(followingProfiles) { profile in
                    FeedFollowedPersonRow(
                        profile: profile,
                        recCount: recommendationCounts[profile.id, default: 0]
                    ) {
                        openProfile(profile)
                    }
                }
            }
        }
    }

    private func refreshRecommendations(force: Bool = false) async {
        guard auth.isSignedIn else { return }
        await store.refreshDiscoverPeopleRecommendations(backend: backend, force: force)
    }

    private func refreshMembers(query: String, debounce: Bool) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            memberResults = []
            return
        }

        if debounce {
            do {
                try await Task.sleep(for: .milliseconds(225))
            } catch {
                return
            }
        }

        let results = await store.discoverMembers(query: query, backend: backend)
        guard !Task.isCancelled, query == memberQuery else { return }
        memberResults = results
    }

    private func followRecommendation(_ recommendation: DiscoverPeopleRecommendation) {
        auth.requireSignIn(for: .followPeople) {
            let profileID = recommendation.profile.id
            guard !followInFlightProfileIDs.contains(profileID) else { return }
            followInFlightProfileIDs.insert(profileID)
            followFailedProfileIDs.remove(profileID)

            Task { @MainActor in
                let succeeded = await store.follow(
                    userID: profileID,
                    source: .profile,
                    backend: backend
                )
                followInFlightProfileIDs.remove(profileID)
                if succeeded {
                    followFailedProfileIDs.remove(profileID)
                } else {
                    followFailedProfileIDs.insert(profileID)
                }
            }
        }
    }

    private func latestProfileShell(for profile: ProfileShell) -> ProfileShell {
        guard let localProfile = store.profiles.first(where: { $0.id == profile.id }) else {
            return profile
        }
        return store.shell(for: localProfile)
    }
}

private struct FeedPeopleSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            TextField("Search name or @handle", text: $text)
                .font(.system(size: 15, weight: .bold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(WanderTheme.textInk.color)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .accessibilityLabel("Clear people search")
            }
        }
        .padding(.leading, WanderTheme.spacing3)
        .padding(.trailing, text.isEmpty ? WanderTheme.spacing3 : WanderTheme.spacing1)
        .frame(minHeight: WanderTheme.tapMinimum)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
        .accessibilityLabel("Search people")
    }
}

private struct FeedPeopleValueNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 24, height: 24)

            Text("Follow people whose taste you trust. Shared places can appear in your Feed and on your map.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.skyTint.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private struct FeedPeopleLoadingPanel: View {
    let label: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .accessibilityElement(children: .combine)
    }
}

private struct FeedPeopleEmptyPanel: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 16, weight: .black))
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedPeopleActionPanel: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 44, height: 44)
                .background(WanderTheme.skyTint.color)
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedMemberResultTile: View {
    let profile: ProfileShell
    let recCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: String(profile.displayName.prefix(1)),
                    avatarURL: profile.avatarURL,
                    size: 46,
                    color: WanderTheme.pinSocial.color
                )
                Text(profile.displayName)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Text("@\(profile.handle)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                Spacer()
                Text("\(recCount) rec matches")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .frame(width: 154, height: 142, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct FeedFollowedPersonRow: View {
    let profile: ProfileShell
    let recCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: String(profile.displayName.prefix(1)),
                    avatarURL: profile.avatarURL,
                    size: 42,
                    color: WanderTheme.pinSocial.color
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(profile.displayName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(profile.handle)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Text("\(recCount) recs")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textFaint.color)
            }
            .padding(.vertical, WanderTheme.spacing2)
            .frame(minHeight: WanderTheme.tapMinimum)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(profile.displayName)'s profile")
    }
}

private struct FeedProfileRoute: Identifiable {
    let id: String
}

private struct FeedSearchLauncher: View {
    let placeholders: [String]
    let action: () -> Void
    @State private var placeholderIndex = 0

    private var placeholder: String {
        guard !placeholders.isEmpty else { return "Search places and people" }
        return placeholders[placeholderIndex % placeholders.count]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)

                Text(placeholder)
                    .id(placeholder)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textFaint.color)
                    .lineLimit(1)
                    .transition(.push(from: .bottom).combined(with: .opacity))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 44)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            .overlay {
                RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search places and people")
        .task {
            guard placeholders.count > 1 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.24)) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                }
            }
        }
    }
}

private struct FeedSectionHeading: View {
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(WanderTheme.textInk.color)

            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }
}

private struct FeedFeaturedRail: View {
    let places: [FeedFeaturedPlace]
    let openProfile: (ProfileShell) -> Void
    let save: (FeedFeaturedPlace) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ForEach(places) { featured in
                    FeedFeaturedCard(featured: featured, openProfile: openProfile, save: save)
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel("Featured places from people you follow")
    }
}

private struct FeedFeaturedCard: View {
    let featured: FeedFeaturedPlace
    let openProfile: (ProfileShell) -> Void
    let save: (FeedFeaturedPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .top) {
                FeedPlaceArtwork(place: featured.visiblePlace, height: 92)
                Spacer(minLength: 0)
            }

            Text(featured.visiblePlace.place.canonicalName)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(2)

            Text(placeDetail(for: featured.visiblePlace))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)

            Button {
                openProfile(ProfileShell(
                    id: featured.visiblePlace.owner.id,
                    handle: featured.visiblePlace.owner.handle,
                    displayName: featured.visiblePlace.owner.displayName,
                    avatarURL: featured.visiblePlace.owner.avatarURL,
                    bio: featured.visiblePlace.owner.bio,
                    relationship: .follower
                ))
            } label: {
                Label(featured.reason, systemImage: "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.skyTint.color)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                save(featured)
            } label: {
                Label("Save", systemImage: "plus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save \(featured.visiblePlace.place.canonicalName) to my map")
        }
        .padding(WanderTheme.spacing3)
        .frame(
            width: FeedFeaturedLayout.cardWidth,
            height: FeedFeaturedLayout.cardHeight,
            alignment: .topLeading
        )
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedActivityList: View {
    let activity: [FeedActivity]
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let save: (FeedActivity) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(activity.enumerated()), id: \.element.id) { index, event in
                FeedActivityModule(
                    activity: event,
                    openProfile: openProfile,
                    openPlace: openPlace,
                    save: save,
                    openList: openList
                )

                if index < activity.count - 1 {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                        .padding(.horizontal, -WanderTheme.spacing4)
                }
            }
        }
    }
}

private enum FeedFeaturedLayout {
    static let cardWidth: CGFloat = 184
    static let cardHeight: CGFloat = 252
}

private enum FeedActivityLayout {
    static let photoWidth: CGFloat = 88
    static let photoHeight: CGFloat = 56
}

private struct FeedActivityModule: View {
    let activity: FeedActivity
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let save: (FeedActivity) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                Button {
                    openProfile(activity.actor)
                } label: {
                    WanderAvatar(
                        initials: initials(for: activity.actor.displayName),
                        avatarURL: activity.actor.avatarURL,
                        size: 48,
                        color: WanderTheme.skyTint.color
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(activity.actor.displayName)'s profile")

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    activityTitle

                    HStack(spacing: WanderTheme.spacing1) {
                        Image(systemName: activity.list == nil ? "fork.knife" : "list.bullet")
                        Text(metadata)
                            .lineLimit(1)
                        Text("·")
                            .accessibilityHidden(true)
                        Text(FeedPresentation.timestampText(for: activity.occurredAt))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer(minLength: WanderTheme.spacing1)

                if let rating = activity.rating {
                    Text(PlaceRating.averageDisplay(rating))
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .frame(minHeight: 32)
                        .overlay {
                            Capsule().stroke(WanderTheme.terracotta.color.opacity(0.45), lineWidth: 1)
                        }
                        .accessibilityLabel("Rating \(PlaceRating.averageDisplay(rating))")
                }
            }

            if let note = activity.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                Text(note)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .padding(.leading, 60)
            }

            if !activity.media.isEmpty {
                FeedMediaRail(media: activity.media)
                    .padding(.leading, 60)
            }

            HStack {
                Spacer(minLength: 0)
                actionButton
            }
            .padding(.top, WanderTheme.spacing1)
        }
        .padding(WanderTheme.spacing3)
    }

    private var activityTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: WanderTheme.spacing1) {
                Button {
                    openProfile(activity.actor)
                } label: {
                    Text(activity.actor.displayName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(activity.actor.displayName)'s profile")

                Text(activityVerb)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
            }

            if let place = activity.place {
                Button {
                    openPlace(place)
                } label: {
                    Text(place.place.canonicalName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(place.place.canonicalName)")
            } else if let list = activity.list {
                Button {
                    openList(list)
                } label: {
                    Text(list.name)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View list \(list.name)")
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let list = activity.list, !activity.kind.isPlaceActivity || activity.kind == .listItemAdded {
            Button {
                openList(list)
            } label: {
                Label("View list", systemImage: "list.bullet")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View list \(list.name)")
        } else if activity.place != nil {
            Button {
                save(activity)
            } label: {
                Label("Save to my map", systemImage: "plus")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 38)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save to my map")
        }
    }

    private var activityVerb: String {
        switch activity.kind {
        case .placeSaved:
            "saved"
        case .placeBeen:
            "checked in at"
        case .placeWannaGo:
            "added to Want to go"
        case .listCreated:
            "created"
        case .listItemAdded:
            "added"
        }
    }

    private var metadata: String {
        if let place = activity.place {
            return placeDetail(for: place)
        }
        if let list = activity.list {
            let count = list.cachedItemCount ?? 0
            return count == 1 ? "1 place" : "\(count) places"
        }
        return "From someone you follow"
    }
}

private struct FeedMediaRail: View {
    let media: [FeedMediaPreview]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(media) { preview in
                    Group {
                        if let url = preview.urlString.flatMap(URL.init(string:)) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                FeedMediaPlaceholder()
                            }
                        } else {
                            FeedMediaPlaceholder()
                        }
                    }
                    .frame(
                        width: FeedActivityLayout.photoWidth,
                        height: FeedActivityLayout.photoHeight
                    )
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                    .accessibilityLabel(preview.accessibilityLabel)
                }
            }
        }
    }
}

private struct FeedMediaPlaceholder: View {
    var body: some View {
        LinearGradient(
            colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(WanderTheme.textOnAction.color.opacity(0.82))
        }
    }
}

private struct FeedPlaceArtwork: View {
    let place: VisiblePlace
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WanderTheme.sunTint.color, WanderTheme.skyTint.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: categorySymbol(for: place.effectiveCategory))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
}

private struct FeedLoadingState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            FeedSectionHeading(title: "Featured for you")
            HStack(spacing: WanderTheme.spacing3) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: 184, height: 218)
                }
            }
            FeedSectionHeading(title: "Your feed")
            VStack(spacing: WanderTheme.spacing3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(height: 142)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading Feed")
    }
}

/// Keeps a cold-load failure visually in the Feed instead of showing the
/// follow-people empty state. The placeholders deliberately do not invent
/// social activity that the app failed to retrieve.
private struct FeedRefreshRecoveryState: View {
    let retry: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            FeedSectionHeading(title: "Featured for you")
            FeedRecoveryFeaturedRail()

            FeedSectionHeading(title: "Your feed", detail: "Unavailable")
            FeedRecoveryActivityList()

            FeedRetryRow(
                title: "Couldn’t load Feed",
                subtitle: "Try again to reload updates from people you follow.",
                actionTitle: "Retry",
                retry: retry
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feed couldn't load. Retry to reload updates.")
    }
}

private struct FeedRecoveryFeaturedRail: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing3) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(height: 92)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(width: 116, height: 14)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(width: 82, height: 11)
                        RoundedRectangle(cornerRadius: 18)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(height: 38)
                    }
                    .padding(WanderTheme.spacing3)
                    .frame(width: 184, alignment: .leading)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                }
            }
            .padding(.horizontal, 1)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct FeedRecoveryActivityList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                    Circle()
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(width: index == 0 ? 188 : 156, height: 15)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(width: 124, height: 11)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(WanderTheme.surfaceSand.color)
                            .frame(width: index == 2 ? 168 : 210, height: 13)
                    }

                    Spacer(minLength: WanderTheme.spacing1)

                    Capsule()
                        .fill(WanderTheme.surfaceSand.color)
                        .frame(width: 38, height: 32)
                }
                .padding(WanderTheme.spacing3)

                if index < 2 {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

private struct FeedEmptyState: View {
    let recommendations: [DiscoverPeopleRecommendation]
    let followingProfileIDs: Set<String>
    let openSearch: () -> Void
    let openProfile: (ProfileShell) -> Void
    let follow: (DiscoverPeopleRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("Your Feed fills up from people you follow.")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Find people whose place memory you’d actually use, then come back here to catch up.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if recommendations.isEmpty {
                Button("Find people", action: openSearch)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .frame(minHeight: 44)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .background(WanderTheme.terracotta.color)
                    .clipShape(Capsule())
                    .accessibilityLabel("Find people to follow")
            } else {
                ForEach(recommendations) { recommendation in
                    HStack(spacing: WanderTheme.spacing3) {
                        Button {
                            openProfile(recommendation.profile)
                        } label: {
                            WanderAvatar(
                                initials: initials(for: recommendation.profile.displayName),
                                avatarURL: recommendation.profile.avatarURL,
                                size: 44,
                                color: WanderTheme.skyTint.color
                            )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.profile.displayName)
                                .font(.system(size: 15, weight: .black))
                            Text(recommendation.reason.displayText(for: recommendation.profile))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Button {
                            follow(recommendation)
                        } label: {
                            if followingProfileIDs.contains(recommendation.profile.id) {
                                ProgressView()
                                    .tint(WanderTheme.terracotta.color)
                                    .frame(width: 44, height: 44)
                            } else {
                                Text("Follow")
                                    .font(.system(size: 13, weight: .black))
                                    .foregroundStyle(WanderTheme.terracotta.color)
                                    .frame(minHeight: 44)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(followingProfileIDs.contains(recommendation.profile.id))
                    }
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct FeedRetryRow: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .black))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            Spacer(minLength: 0)

            Button(actionTitle) {
                Task { await retry() }
            }
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(minHeight: 44)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }
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

private func placeDetail(for place: VisiblePlace) -> String {
    [
        place.effectiveCategoryDisplay.compactTitle,
        place.place.locality,
        place.place.region
    ]
    .compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    .joined(separator: " · ")
}

private func categorySymbol(for category: String) -> String {
    switch WanderPlaceCategory.normalizedPrimaryCategory(category) {
    case WanderPlaceCategory.coffeeTeaSweets:
        "cup.and.saucer.fill"
    case WanderPlaceCategory.restaurantsFood:
        "fork.knife"
    case WanderPlaceCategory.outdoorsNature:
        "mountain.2.fill"
    case WanderPlaceCategory.barsNightlife:
        "wineglass.fill"
    default:
        "mappin.and.ellipse"
    }
}
