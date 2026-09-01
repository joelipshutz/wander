import SwiftUI

struct FeedScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.astirBrandMode) private var astirBrandMode
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    @State private var isShowingSearch = ProcessInfo.processInfo.arguments.contains("-WanderOpenDiscoverSearch")
    @State private var selectedProfile: FeedProfileRoute?
    @State private var selectedPlace: VisiblePlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?
    @State private var savedMessage: String?
    @State private var followingProfileIDs = Set<String>()
    @State private var focusedActivityID: String?
    @State private var selectedSurface: FeedSurface
    @State private var hasMountedPeopleSurface: Bool
    @State private var peopleQuery = ""
    @State private var floatingHeaderHeight = FeedFloatingHeaderMetrics.estimatedHeight
    @State private var isFloatingHeaderHidden = false
    @State private var lastFeedScrollOffset: CGFloat?
    @State private var accumulatedFeedScrollTravel: CGFloat = 0
    @FocusState private var peopleSearchFieldFocused: Bool
    @Namespace private var searchTransitionNamespace
    private let onAdd: () -> Void

    init(onAdd: @escaping () -> Void = {}) {
        self.onAdd = onAdd
        let initialSurface = FeedSurface.resolvedInitialSurface()
        _selectedSurface = State(initialValue: initialSurface)
        _hasMountedPeopleSurface = State(initialValue: initialSurface == .people)
    }

    private let tickerSuggestions = [
        "friends' favorite coffee shops",
        "date night spots from people you follow",
        "quiet work cafes with wifi",
        "friends' sunset hikes"
    ]

    private var page: FollowedFeedPage? { store.followedFeedPage }

    var body: some View {
        NavigationStack {
            ZStack {
                ZStack(alignment: .top) {
                    placesSurface
                        .opacity(selectedSurface == .places ? 1 : 0)
                        .allowsHitTesting(selectedSurface == .places)
                        .accessibilityHidden(selectedSurface != .places)
                        .zIndex(selectedSurface == .places ? 1 : 0)

                    if hasMountedPeopleSurface || selectedSurface == .people {
                        FeedPeopleSurface(
                            memberQuery: $peopleQuery,
                            contentTopInset: feedContentTopInset,
                            dismissSearchFocus: { peopleSearchFieldFocused = false },
                            onScrollOffsetChange: { offset in
                                updateFloatingHeaderVisibility(
                                    scrollOffset: offset,
                                    surface: .people
                                )
                            },
                            openProfile: openProfile
                        )
                        .opacity(selectedSurface == .people ? 1 : 0)
                        .allowsHitTesting(selectedSurface == .people)
                        .accessibilityHidden(selectedSurface != .people)
                        .zIndex(selectedSurface == .people ? 1 : 0)
                    }

                    floatingHeader
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: FeedFloatingHeaderHeightPreferenceKey.self,
                                    value: proxy.size.height
                                )
                            }
                        }
                        .offset(
                            y: isFloatingHeaderHidden
                                ? -(floatingHeaderHeight + WanderTheme.spacing4)
                                : 0
                        )
                        .opacity(isFloatingHeaderHidden ? 0 : 1)
                        .allowsHitTesting(!isFloatingHeaderHidden)
                        .animation(
                            FeedFloatingHeaderBehavior.animation(reduceMotion: reduceMotion),
                            value: isFloatingHeaderHidden
                        )
                        .zIndex(3)
                }
                .opacity(isShowingSearch ? 0 : 1)
                .allowsHitTesting(!isShowingSearch)
                .accessibilityHidden(isShowingSearch)

                if isShowingSearch {
                    DiscoverScreen(
                        startsInPlaceSearch: true,
                        embedsInHostNavigation: true,
                        searchTransitionNamespace: searchTransitionNamespace,
                        onClose: closeDiscoverSearch
                    )
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .environmentObject(walkthroughs)
                    .transition(.opacity)
                    .zIndex(2)
                }
            }
            .background(astirBrandMode.background.ignoresSafeArea())
            .foregroundStyle(astirBrandMode.primaryText)
            .onPreferenceChange(FeedFloatingHeaderHeightPreferenceKey.self) { height in
                guard height > 0 else { return }
                floatingHeaderHeight = height
            }
            .task(id: auth.isSignedIn) {
                // Commit the selected tab's first frame before starting the
                // remote refresh and its published state changes.
                await Task.yield()
                guard !Task.isCancelled else { return }
                await refresh()
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
            .navigationDestination(item: commentsRouteBinding) { route in
                ActivityCommentsRouteScreen(
                    requestID: route.id,
                    retry: resolveCommentsRouteIfNeeded,
                    openProfile: openProfile,
                    openPlace: openPlace,
                    openList: openListByID
                )
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
                .environmentObject(activityNavigation)
                .environment(\.activityPostcardVisualStyle, .astir)
            }
            .sheet(item: $placeSaveFlow, onDismiss: {
                store.saveFlowDidDismiss(.saveSheet)
            }) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveFeedFlowSubmission(submission)
                } onRemove: { _ in
                    false
                }
            }
            .alert("Map updated", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("OK", role: .cancel) { savedMessage = nil }
            } message: {
                Text(savedMessage ?? "")
            }
            .onChange(of: selectedSurface) { _, surface in
                if surface == .people {
                    hasMountedPeopleSurface = true
                }
                peopleSearchFieldFocused = false
                if surface != .people {
                    peopleQuery = ""
                }
                walkthroughs.perform(.feedSurfaceSwitch)
                resetFloatingHeaderScrollTracking(revealHeader: true)
            }
            .onChange(of: walkthroughs.currentStep?.target, initial: true) { _, target in
                if target == .feedDiscoverSearch || target == .feedActivity {
                    selectedSurface = .places
                } else if target == .feedPeopleSearch || target == .feedInvite {
                    selectedSurface = .people
                }
                if target == .feedInvite {
                    peopleSearchFieldFocused = false
                }
            }
            .onChange(of: peopleSearchFieldFocused) { _, isFocused in
                if isFocused {
                    setFloatingHeaderHidden(false)
                    walkthroughs.perform(.feedPeopleSearch)
                }
            }
            .onChange(of: walkthroughs.activeSurface, initial: true) { _, surface in
                if surface == .feedSearch {
                    setSearchPresented(true)
                }
            }
            .onChange(of: isShowingSearch) { _, isShowing in
                if !isShowing {
                    restoreFeedWalkthroughAfterDiscoverDismissal()
                }
            }
        }
        .task(id: activityNavigation.commentsRoute?.id) {
            await resolveCommentsRouteIfNeeded()
        }
    }

    private var floatingHeader: some View {
        AstirFloatingHeaderSurface {
            floatingHeaderContent
        }
    }

    private var floatingHeaderContent: some View {
        VStack(spacing: WanderTheme.spacing2) {
            HStack {
                AstirMastheadLockup()
                Spacer(minLength: WanderTheme.spacing4)
            }

            switch selectedSurface {
            case .places:
                FeedSearchLauncher(
                    placeholders: tickerSuggestions,
                    isWalkthroughTarget: walkthroughs.currentStep?.target == .feedDiscoverSearch,
                    action: openDiscoverSearch
                )
                .feedSearchMatchedGeometry(
                    in: searchTransitionNamespace,
                    isSource: !isShowingSearch
                )
                .walkthroughTarget(.feedDiscoverSearch)
            case .people:
                FeedPeopleSearchField(text: $peopleQuery)
                    .focused($peopleSearchFieldFocused)
                    .walkthroughTarget(.feedPeopleSearch)
            }

            HStack(spacing: WanderTheme.spacing2) {
                FeedSurfaceTabs(selectedSurface: $selectedSurface)
                    .walkthroughTarget(.feedSurfaceSwitch)

                AstirIconActionButton(
                    systemImage: "plus",
                    accessibilityLabel: "Add a place",
                    accessibilityIdentifier: "feed.headerAdd",
                    action: onAdd
                )
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
    }

    private var placesSurface: some View {
        ScrollViewReader { proxy in
            ScrollView {
                FeedScrollOffsetReader(
                    coordinateSpaceName: FeedScrollCoordinateSpace.places
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    content
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, feedContentTopInset)
                .padding(.bottom, WanderTheme.spacing16)
            }
            .coordinateSpace(name: FeedScrollCoordinateSpace.places)
            .feedScrollTracking(
                coordinateSpaceName: FeedScrollCoordinateSpace.places
            ) { offset in
                updateFloatingHeaderVisibility(
                    scrollOffset: offset,
                    surface: .places
                )
            }
            .accessibilityIdentifier("feed.places.scroll")
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await refresh()
            }
            .onChange(of: focusedActivityID, initial: true) { _, activityID in
                scrollToFocusedActivity(activityID, proxy: proxy)
            }
            .onChange(of: page?.activity.map(\.id), initial: true) { _, _ in
                scrollToFocusedActivity(focusedActivityID, proxy: proxy)
            }
        }
    }

    private var feedContentTopInset: CGFloat {
        floatingHeaderHeight + WanderTheme.spacing3
    }

    private func updateFloatingHeaderVisibility(
        scrollOffset: CGFloat,
        surface: FeedSurface
    ) {
        guard selectedSurface == surface, !isShowingSearch else { return }

        if scrollOffset <= FeedFloatingHeaderBehavior.topRevealOffset {
            lastFeedScrollOffset = scrollOffset
            accumulatedFeedScrollTravel = 0
            setFloatingHeaderHidden(false)
            return
        }

        guard let previousOffset = lastFeedScrollOffset else {
            lastFeedScrollOffset = scrollOffset
            return
        }

        let delta = scrollOffset - previousOffset
        lastFeedScrollOffset = scrollOffset
        guard abs(delta) >= FeedFloatingHeaderBehavior.minimumMeaningfulDelta else { return }

        if delta > 0 {
            if accumulatedFeedScrollTravel < 0 {
                accumulatedFeedScrollTravel = 0
            }
            accumulatedFeedScrollTravel += delta

            if scrollOffset >= FeedFloatingHeaderBehavior.minimumHideOffset,
               accumulatedFeedScrollTravel >= FeedFloatingHeaderBehavior.hideTravelThreshold {
                accumulatedFeedScrollTravel = 0
                setFloatingHeaderHidden(true)
            }
        } else {
            if accumulatedFeedScrollTravel > 0 {
                accumulatedFeedScrollTravel = 0
            }
            accumulatedFeedScrollTravel += delta

            if accumulatedFeedScrollTravel <= -FeedFloatingHeaderBehavior.revealTravelThreshold {
                accumulatedFeedScrollTravel = 0
                setFloatingHeaderHidden(false)
            }
        }
    }

    private func resetFloatingHeaderScrollTracking(revealHeader: Bool) {
        lastFeedScrollOffset = nil
        accumulatedFeedScrollTravel = 0
        if revealHeader {
            setFloatingHeaderHidden(false)
        }
    }

    private func setFloatingHeaderHidden(_ isHidden: Bool) {
        guard isFloatingHeaderHidden != isHidden else { return }
        if reduceMotion {
            isFloatingHeaderHidden = isHidden
        } else {
            withAnimation(FeedFloatingHeaderBehavior.animation(reduceMotion: false)) {
                isFloatingHeaderHidden = isHidden
            }
        }
    }

    private func openDiscoverSearch() {
        if walkthroughs.currentStep?.target == .feedDiscoverSearch {
            walkthroughs.perform(.feedDiscoverSearch)
            walkthroughs.consumeRequestedSurface(.feedSearch)
        }
        walkthroughs.transition(to: .feedSearch)
        setSearchPresented(true)
    }

    private func closeDiscoverSearch() {
        setSearchPresented(false)
    }

    private func setSearchPresented(_ isPresented: Bool) {
        withAnimation(FeedSearchTransitionPolicy.animation(reduceMotion: reduceMotion)) {
            isShowingSearch = isPresented
        }
    }

    /// Resolve both supported coordinator handoff states synchronously as the
    /// inline search layer fades back to the preserved Feed state.
    private func restoreFeedWalkthroughAfterDiscoverDismissal() {
        if walkthroughs.requestedSurface == .feed {
            walkthroughs.consumeRequestedSurface(.feed)
            walkthroughs.activate(.feed)
        }

        guard let destination = FeedSurface.walkthroughDestination(
            activeSurface: walkthroughs.activeSurface,
            target: walkthroughs.currentStep?.target
        ) else { return }
        selectedSurface = destination
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
                    openPlace: openPlace
                )
            }

            FeedSectionHeading(title: "Recent", detail: freshnessDetail)
            FeedActivityList(
                activity: page.activity,
                openProfile: openProfile,
                openPlace: openPlace,
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
            FeedSectionHeading(title: "Recent")
            FeedEmptyState(
                recommendations: peopleRecommendations,
                followingProfileIDs: followingProfileIDs,
                openSearch: openDiscoverSearch,
                openProfile: openProfile,
                follow: follow
            )
            .walkthroughTarget(.feedActivity)

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
        _ = await store.refreshFollowedFeed(
            backend: auth.isSignedIn ? backend : nil,
            preservingActivityID: activityNavigation.commentsRoute?.activityID ?? focusedActivityID
        )
        guard store.followedFeedPage?.activity.isEmpty != false else { return }
        await store.refreshDiscoverPeopleRecommendations(backend: auth.isSignedIn ? backend : nil)
    }

    private var commentsRouteBinding: Binding<ActivityCommentsRoute?> {
        Binding(
            get: { activityNavigation.commentsRoute },
            set: { route in
                guard route == nil,
                      let requestID = activityNavigation.commentsRoute?.id
                else { return }
                activityNavigation.dismiss(requestID: requestID)
            }
        )
    }

    @MainActor
    private func resolveCommentsRouteIfNeeded() async {
        guard let route = activityNavigation.commentsRoute else { return }
        let requestUserID = store.currentUser.id
        let allowsCachedContext = !auth.isSignedIn
            || backend.activityEngagementRepository == nil
            || UUID(uuidString: route.activityID) == nil
        focusedActivityID = route.activityID

        if !allowsCachedContext {
            activityNavigation.resolve(requestID: route.id, activity: nil)
        }

        let activity = await store.activity(
            id: route.activityID,
            backend: auth.isSignedIn ? backend : nil
        )
        guard !Task.isCancelled, store.currentUser.id == requestUserID else { return }
        activityNavigation.resolve(
            requestID: route.id,
            activity: activity,
            allowsCachedContext: allowsCachedContext
        )
    }

    private func scrollToFocusedActivity(_ activityID: String?, proxy: ScrollViewProxy) {
        guard let activityID,
              page?.activity.contains(where: { $0.id == activityID }) == true
        else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(activityID, anchor: .center)
            }
        }
    }

    private func openProfile(_ profile: ProfileShell) {
        walkthroughs.perform(.feedActivity)
        selectedProfile = FeedProfileRoute(id: profile.id)
    }

    private func openPlace(_ visiblePlace: VisiblePlace) {
        walkthroughs.perform(.feedActivity)
        selectedPlace = visiblePlace
    }

    private func openList(_ list: LocalPlaceList) {
        walkthroughs.perform(.feedActivity)
        pushNotifications.route(to: .list(id: list.id))
    }

    private func openListByID(_ listID: String) {
        walkthroughs.perform(.feedActivity)
        pushNotifications.route(to: .list(id: listID))
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

        presentPlaceSaveFlow(MapPlaceSaveContext.existingCurrentUserSave(
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
            savedMessage = confirmationMessage(for: submission.status, syncState: result.syncState)
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
            savedMessage = confirmationMessage(for: submission.status, syncState: result.syncState)
            return result

        case .sharedVisit:
            return nil
        }
    }

    private func confirmationMessage(for status: PlaceStatus, syncState: SyncState) -> String {
        if syncState == .synced {
            return status == .been ? "Check-in complete." : "Added to Wanna."
        }
        return status == .been
            ? "Check-in is on this phone. We'll retry sync."
            : "Wanna is on this phone. We'll retry sync."
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
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: attributes(for: visiblePlace),
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
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
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id),
                viewerFollowsOwner: false
            )
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

enum FeedSurface: String, CaseIterable, Identifiable {
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

    static func resolvedInitialSurface(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> FeedSurface {
        guard let flagIndex = arguments.firstIndex(of: "-WanderFeedSurface") else {
            return .places
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return .places }
        return FeedSurface(rawValue: arguments[valueIndex]) ?? .places
    }

    static func walkthroughDestination(
        activeSurface: WalkthroughSurface?,
        target: WalkthroughTargetID?
    ) -> FeedSurface? {
        guard activeSurface == .feed else { return nil }
        switch target {
        case .feedPeopleSearch, .feedInvite:
            return .people
        case .feedActivity, .feedDiscoverSearch:
            return .places
        default:
            return nil
        }
    }
}

private struct FeedSurfaceTabs: View {
    @Binding var selectedSurface: FeedSurface

    var body: some View {
        AstirEditorialSegmentedSwitch(
            options: FeedSurface.allCases.map {
                WanderSegmentOption(id: $0.rawValue, title: $0.title)
            },
            selection: Binding(
                get: { selectedSurface.rawValue },
                set: { selectedSurface = FeedSurface(rawValue: $0) ?? .places }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Feed section")
        .accessibilityIdentifier("feed.surfaceSwitch")
    }
}

private struct FeedPeopleSurface: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @Binding var memberQuery: String
    let contentTopInset: CGFloat
    let dismissSearchFocus: () -> Void
    let onScrollOffsetChange: (CGFloat) -> Void
    let openProfile: (ProfileShell) -> Void

    @State private var memberResults: [ProfileShell] = []
    @State private var followInFlightProfileIDs: Set<String> = []
    @State private var followFailedProfileIDs: Set<String> = []
    @State private var isPresentingContactInvites = false

    private var isMemberSearchActive: Bool {
        !memberQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var followingProfiles: [ProfileShell] {
        store.following(of: store.currentUser.id)
            .map(store.shell(for:))
    }

    var body: some View {
        ScrollView {
            FeedScrollOffsetReader(
                coordinateSpaceName: FeedScrollCoordinateSpace.people
            )

            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                InviteEntryPointButton(surface: .feedPeople) {
                    dismissSearchFocus()
                    walkthroughs.perform(.feedInvite)
                    isPresentingContactInvites = true
                }
                .walkthroughTarget(.feedInvite)

                if isMemberSearchActive {
                    memberSearchResultsSection
                } else {
                    peopleRecommendationsSection
                    peopleSection
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, contentTopInset)
            .padding(.bottom, WanderTheme.spacing16)
        }
        .coordinateSpace(name: FeedScrollCoordinateSpace.people)
        .feedScrollTracking(
            coordinateSpaceName: FeedScrollCoordinateSpace.people,
            onOffsetChange: onScrollOffsetChange
        )
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await refreshRecommendations()
        }
        .task(id: auth.isSignedIn) {
            await refreshRecommendations()
        }
        .task(id: memberQuery) {
            walkthroughs.recordUserActivity()
            await refreshMembers(query: memberQuery, debounce: true)
        }
        .onChange(of: walkthroughs.isRequestingContactInvite, initial: true) { _, isRequested in
            guard isRequested else { return }
            dismissSearchFocus()
            isPresentingContactInvites = true
        }
        .sheet(isPresented: $isPresentingContactInvites, onDismiss: {
            walkthroughs.completeContactInviteRequest()
        }) {
            ContactInviteSheet(
                surface: .feedPeople,
                contactProvider: store.contactProvider,
                senderProfileID: store.currentUser.id,
                canDismiss: !walkthroughs.isRequestingContactInvite,
                walkthroughSelectionGoal: walkthroughs.isRequestingContactInvite ? 5 : nil,
                onPermissionDenied: walkthroughPermissionDeniedAction,
                selectedContactIDs: walkthroughs.tutorialInvitedContactIDs,
                onWalkthroughSelectionChange: walkthroughs.recordTutorialInvitedContactIDs,
                analytics: store.productAnalytics
            )
            .interactiveDismissDisabled(walkthroughs.isRequestingContactInvite)
        }
    }

    private var walkthroughPermissionDeniedAction: (() -> Void)? {
        guard walkthroughs.isRequestingContactInvite else { return nil }
        return {
            isPresentingContactInvites = false
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
        let profiles = followingProfiles
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                FeedSectionHeading(title: "People")
                Spacer()
                Text("\(profiles.count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if profiles.isEmpty {
                FeedPeopleEmptyPanel(
                    title: "No one followed yet",
                    message: "Follow someone above or search by name."
                )
            } else {
                ForEach(profiles) { profile in
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

        let localResults = store.searchProfiles(handleQuery: query)
        guard !Task.isCancelled, query == memberQuery else { return }
        memberResults = localResults

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
    @Environment(\.astirBrandMode) private var astirBrandMode
    @Binding var text: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(astirBrandMode.secondaryText)

            TextField("Search name or @handle", text: $text)
                .font(AstirTypography.bodySmall)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(astirBrandMode.primaryText)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(astirBrandMode.secondaryText)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .accessibilityLabel("Clear people search")
            }
        }
        .padding(.leading, WanderTheme.spacing3)
        .padding(.trailing, text.isEmpty ? WanderTheme.spacing3 : WanderTheme.spacing1)
        .frame(minHeight: WanderTheme.tapMinimum)
        .contentShape(Rectangle())
        .astirOutlinedSurface(castsShadow: true)
        .accessibilityLabel("Search people")
    }
}

private struct FeedPeopleLoadingPanel: View {
    @Environment(\.astirBrandMode) private var brandMode
    let label: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(brandMode.accent)
            Text(label)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)
            Spacer()
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FeedPeopleEmptyPanel: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(AstirTypography.cardTitle)
            Text(message)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
    }
}

private struct FeedPeopleActionPanel: View {
    @Environment(\.astirBrandMode) private var brandMode
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(brandMode.accent)
                .frame(width: 44, height: 44)
                .background(brandMode.accentWash)
                .clipShape(Circle())

            Text(title)
                .font(AstirTypography.sectionTitle)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.secondaryText)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(brandMode.accent)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
    }
}

private struct FeedMemberResultTile: View {
    @Environment(\.astirBrandMode) private var brandMode
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
                    .font(AstirTypography.cardTitle)
                    .foregroundStyle(brandMode.primaryText)
                    .lineLimit(1)
                Text("@\(profile.handle)")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .lineLimit(1)
                Spacer()
                Text("\(recCount) rec matches")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.accent)
            }
            .frame(width: 154, height: 142, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(brandMode.raisedBackground)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct FeedFollowedPersonRow: View {
    @Environment(\.astirBrandMode) private var brandMode
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
                        .font(AstirTypography.cardTitle)
                        .foregroundStyle(brandMode.primaryText)
                    Text("@\(profile.handle)")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                }

                Spacer()

                Text("\(recCount) recs")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(brandMode.secondaryText)
            }
            .padding(.vertical, WanderTheme.spacing2)
            .frame(minHeight: WanderTheme.tapMinimum)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(profile.displayName)'s profile")
    }
}

private enum FeedFloatingHeaderMetrics {
    static let estimatedHeight = WanderTheme.spacing2
        + WanderTheme.tapMinimum
        + WanderTheme.spacing2
        + WanderTheme.tapMinimum
}

private enum FeedFloatingHeaderBehavior {
    static let topRevealOffset: CGFloat = 8
    static let minimumHideOffset: CGFloat = 28
    static let minimumMeaningfulDelta: CGFloat = 0.7
    static let hideTravelThreshold: CGFloat = 24
    static let revealTravelThreshold: CGFloat = 9

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.30, extraBounce: 0)
    }
}

private enum FeedScrollCoordinateSpace {
    static let places = "feed.places.scroll-space"
    static let people = "feed.people.scroll-space"
}

private struct FeedScrollOffsetReader: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FeedScrollOffsetPreferenceKey.self,
                value: max(
                    0,
                    -proxy.frame(in: .named(coordinateSpaceName)).minY
                )
            )
        }
        .frame(height: 1)
        .padding(.bottom, -1)
        .accessibilityHidden(true)
    }
}

private struct FeedScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FeedScrollTrackingModifier: ViewModifier {
    let coordinateSpaceName: String
    let onOffsetChange: (CGFloat) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                onOffsetChange(offset)
            }
        } else {
            content.onPreferenceChange(FeedScrollOffsetPreferenceKey.self) { offset in
                onOffsetChange(offset)
            }
        }
    }
}

private extension View {
    func feedScrollTracking(
        coordinateSpaceName: String,
        onOffsetChange: @escaping (CGFloat) -> Void
    ) -> some View {
        modifier(
            FeedScrollTrackingModifier(
                coordinateSpaceName: coordinateSpaceName,
                onOffsetChange: onOffsetChange
            )
        )
    }
}

enum FeedSearchTransitionPolicy {
    static let geometryID = "feed.placeSearchTransition"

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .snappy(duration: 0.28, extraBounce: 0)
    }
}

private struct FeedSearchMatchedGeometryModifier: ViewModifier {
    let namespace: Namespace.ID?
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(
                id: FeedSearchTransitionPolicy.geometryID,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource
            )
        } else {
            content
        }
    }
}

extension View {
    func feedSearchMatchedGeometry(
        in namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        modifier(
            FeedSearchMatchedGeometryModifier(
                namespace: namespace,
                isSource: isSource
            )
        )
    }
}

private struct FeedFloatingHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FeedProfileRoute: Identifiable {
    let id: String
}

private struct FeedSearchLauncher: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.astirBrandMode) private var astirBrandMode
    let placeholders: [String]
    let isWalkthroughTarget: Bool
    let action: () -> Void
    @State private var placeholderIndex = 0
    @State private var isPulsing = false

    private var placeholder: String {
        guard !placeholders.isEmpty else { return "Search trusted places" }
        return placeholders[placeholderIndex % placeholders.count]
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(astirBrandMode.secondaryText)

                Text(placeholder)
                    .id(placeholder)
                    .font(AstirTypography.control)
                    .foregroundStyle(astirBrandMode.secondaryText)
                    .lineLimit(1)
                    .transition(.push(from: .bottom).combined(with: .opacity))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .astirOutlinedSurface(castsShadow: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search trusted places")
        .accessibilityIdentifier("feed.searchLauncher")
        .overlay {
            if isWalkthroughTarget {
                Rectangle()
                    .stroke(astirBrandMode.accent, lineWidth: 2)
                    .padding(-2)
            }
        }
        .scaleEffect(
            isWalkthroughTarget && !reduceMotion && isPulsing ? 1.025 : 1
        )
        .shadow(
            color: isWalkthroughTarget
                ? astirBrandMode.accent.opacity(isPulsing ? 0.55 : 0.2)
                : .clear,
            radius: isWalkthroughTarget && isPulsing ? 12 : 3
        )
        .task(id: isWalkthroughTarget) {
            isPulsing = false
            guard isWalkthroughTarget, !reduceMotion else { return }
            await Task.yield()
            isPulsing = true
        }
        .animation(
            isWalkthroughTarget && !reduceMotion
                ? .easeInOut(duration: 1.15).repeatForever(autoreverses: true)
                : .easeOut(duration: 0.2),
            value: isPulsing
        )
        .task {
            guard placeholders.count > 1,
                  !ProcessInfo.processInfo.arguments.contains("-WanderUsePerformanceFixtures")
            else { return }
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
    @Environment(\.astirBrandMode) private var astirBrandMode
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(AstirTypography.sectionTitle)
                .foregroundStyle(astirBrandMode.primaryText)

            if let detail {
                Text(detail)
                    .font(AstirTypography.caption)
                    .foregroundStyle(astirBrandMode.secondaryText)
            }
        }
    }
}

private struct FeedFeaturedRail: View {
    let places: [FeedFeaturedPlace]
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: WanderTheme.spacing3) {
                ForEach(places) { featured in
                    FeedFeaturedCard(
                        featured: featured,
                        openProfile: openProfile,
                        openPlace: openPlace
                    )
                }
            }
            .padding(.vertical, 1)
        }
        .contentMargins(
            .horizontal,
            FeedFeaturedLayout.screenEdgeBleed,
            for: .scrollContent
        )
        .padding(.horizontal, -FeedFeaturedLayout.screenEdgeBleed)
        .accessibilityLabel("Featured places from people you follow")
    }
}

private struct FeedFeaturedCard: View {
    @Environment(\.astirBrandMode) private var astirBrandMode
    let featured: FeedFeaturedPlace
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Button {
                openPlace(featured.visiblePlace)
            } label: {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    FeedPlaceArtwork(
                        place: featured.visiblePlace,
                        height: FeedFeaturedLayout.fullBleedArtworkHeight
                    )
                    .padding(.horizontal, -FeedFeaturedLayout.cardContentInset)
                    .padding(.top, -FeedFeaturedLayout.cardContentInset)

                    Text(featured.visiblePlace.place.canonicalName)
                        .font(AstirTypography.sectionTitle)
                        .foregroundStyle(astirBrandMode.primaryText)
                        .lineLimit(2)

                    Text(placeDetail(for: featured.visiblePlace))
                        .font(AstirTypography.caption)
                        .foregroundStyle(astirBrandMode.secondaryText)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(featured.visiblePlace.place.canonicalName)")

            Button {
                openProfile(featured.actor)
            } label: {
                HStack(alignment: .top, spacing: WanderTheme.spacing1) {
                    WanderAvatar(
                        initials: initials(for: featured.actor.displayName),
                        avatarURL: featured.actor.avatarURL,
                        size: 20,
                        color: featured.actor.handle == "ryan"
                            ? WanderTheme.avatarRyan.color
                            : WanderTheme.pinSocial.color
                    )

                    Text("• \(featured.actor.displayName) • \(featuredActivity)")
                        .font(AstirTypography.caption)
                        .foregroundStyle(astirBrandMode.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(featured.actor.displayName), \(featuredActivity)")

            Spacer(minLength: 0)
        }
        .padding(FeedFeaturedLayout.cardContentInset)
        .frame(width: FeedFeaturedLayout.cardWidth, alignment: .topLeading)
        .background(astirBrandMode.raisedBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(astirBrandMode.border.opacity(0.72), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 14, y: 7)
    }

    private var featuredActivity: String {
        featured.visiblePlace.userPlace.status == .been ? "Checked in" : "Added to Wanna"
    }
}

private struct FeedActivityList: View {
    let activity: [FeedActivity]
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        LazyVStack(spacing: WanderTheme.spacing3) {
            ForEach(activity) { event in
                FeedActivityModule(
                    activity: event,
                    openProfile: openProfile,
                    openPlace: openPlace,
                    openList: openList
                )
                .id(event.id)
                .walkthroughTarget(
                    event.id == activity.first?.id ? .feedActivity : nil
                )
            }
        }
    }
}

private enum FeedFeaturedLayout {
    static let cardWidth: CGFloat = 184
    static let cardContentInset = WanderTheme.spacing3
    static let insetArtworkHeight: CGFloat = 88
    // Reclaiming the top inset while adding the same amount to the artwork
    // keeps the image's lower edge and every row below it in place.
    static let fullBleedArtworkHeight = insetArtworkHeight + cardContentInset
    static let screenEdgeBleed = WanderTheme.spacing4
}

private struct FeedActivityModule: View {
    let activity: FeedActivity
    let openProfile: (ProfileShell) -> Void
    let openPlace: (VisiblePlace) -> Void
    let openList: (LocalPlaceList) -> Void

    var body: some View {
        let engagementContext = activity.activityEngagementContext
        ActivityPostcardView(
            context: engagementContext ?? fallbackPostcardContext,
            visiblePlace: activity.place,
            metadataIcon: metadataIcon,
            secondaryMetadataTitle: secondaryMetadataTitle,
            secondaryMetadataAction: listDestinationAction,
            secondaryMetadataAccessibilityLabel: secondaryMetadataAccessibilityLabel,
            artworkAction: activityDestinationAction,
            artworkAccessibilityLabel: activityDestinationAccessibilityLabel,
            destinationAction: activityDestinationAction,
            destinationAccessibilityLabel: activityDestinationAccessibilityLabel,
            openProfile: { openProfile(activity.actor) },
            actorAccessibilityIdentifier: "feed.activity.\(activity.id).actor",
            destinationAccessibilityIdentifier: "feed.activity.\(activity.id).place",
            postcardAccessibilityIdentifier: "feed.activity.\(activity.id).postcard",
            showsEngagementActions: engagementContext != nil
        )
        .environment(\.activityPostcardVisualStyle, .astir)
    }

    private func openActivityDestination() {
        if let place = activity.place {
            openPlace(place)
        } else if let list = activity.list {
            openList(list)
        }
    }

    private func openListDestination() {
        guard let list = activity.list else { return }
        openList(list)
    }

    private var activityDestinationAction: (() -> Void)? {
        guard hasActivityDestination else { return nil }
        return openActivityDestination
    }

    private var secondaryMetadataTitle: String? {
        guard activity.place != nil else { return nil }
        return activity.list?.name
    }

    private var listDestinationAction: (() -> Void)? {
        guard secondaryMetadataTitle != nil else { return nil }
        return openListDestination
    }

    private var secondaryMetadataAccessibilityLabel: String? {
        activity.list.map { "View list \($0.name)" }
    }

    private var hasActivityDestination: Bool {
        activity.place != nil || activity.list != nil
    }

    private var activityDestinationAccessibilityLabel: String {
        if let place = activity.place {
            return "Open activity at \(place.place.canonicalName)"
        }
        if let list = activity.list {
            return "Open list \(list.name)"
        }
        return "Activity preview"
    }

    private var metadataIcon: String {
        if let place = activity.place { return categorySymbol(for: place.effectiveCategory) }
        return "list.bullet"
    }

    private var fallbackPostcardContext: ActivityEngagementContext {
        ActivityEngagementContext(
            activityID: activity.id,
            actor: activity.actor,
            placeName: "Map activity",
            placeServerID: nil,
            placeDetail: "From someone you follow",
            ticketKind: activity.resolvedTicketKind,
            occurredAt: activity.occurredAt,
            note: activity.note,
            rating: activity.rating,
            ticketEyebrow: activity.postcardTicketEyebrow,
            attributionAction: activity.postcardAttributionAction,
            listContext: activity.list?.activityEngagementListContext,
            media: activity.media.map(\.activityEngagementMedia)
        )
    }
}

extension FeedActivity {
    var activityEngagementContext: ActivityEngagementContext? {
        let subjectName: String
        let subjectServerID: String?
        let detail: String

        if let place {
            subjectName = place.place.canonicalName
            subjectServerID = place.place.serverID ?? place.place.id
            detail = placeDetail(for: place)
        } else if let list {
            subjectName = list.name
            subjectServerID = nil
            let count = list.cachedItemCount ?? 0
            detail = count == 1 ? "1 place" : "\(count) places"
        } else {
            return nil
        }

        return ActivityEngagementContext(
            activityID: id,
            actor: actor,
            placeName: subjectName,
            placeServerID: subjectServerID,
            placeDetail: detail,
            ticketKind: resolvedTicketKind,
            occurredAt: occurredAt,
            note: note,
            rating: rating,
            ticketEyebrow: postcardTicketEyebrow,
            attributionAction: postcardAttributionAction,
            listContext: list?.activityEngagementListContext,
            media: media.map(\.activityEngagementMedia)
        )
    }

    fileprivate var postcardTicketEyebrow: String {
        kind == .listCreated ? "CREATED A LIST" : resolvedTicketKind.defaultTicketEyebrow
    }

    fileprivate var postcardAttributionAction: String {
        kind == .listCreated ? "created a list" : resolvedTicketKind.defaultAttributionAction
    }
}

private extension LocalPlaceList {
    var activityEngagementListContext: ActivityEngagementListContext {
        ActivityEngagementListContext(id: id, name: name)
    }
}

private extension FeedMediaPreview {
    var activityEngagementMedia: ActivityEngagementMedia {
        ActivityEngagementMedia(
            id: id,
            urlString: urlString,
            accessibilityLabel: accessibilityLabel
        )
    }
}

private struct FeedPlaceArtwork: View {
    @Environment(\.astirBrandMode) private var astirBrandMode
    let place: VisiblePlace
    let height: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [astirBrandMode.raisedBackground, astirBrandMode.background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            AstirPlacePhotoAsset(stableKey: place.place.id)
                .accessibilityHidden(true)

            FeedResolvedPlacePhoto(place: place)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }
}

struct FeedResolvedPlacePhoto: View {
    let place: VisiblePlace
    @EnvironmentObject private var backend: WanderBackend
    @State private var photo: PlacePhoto?
    @State private var failedGooglePhotoID: String?

    private var sheetPlace: PlaceSheetPlace {
        PlaceSheetPlace(visiblePlace: place)
    }

    private var photoResolutionKey: String {
        "\(sheetPlace.photoLookupKey)|\(failedGooglePhotoID ?? "ready")"
    }

    var body: some View {
        Group {
            if let photo {
                PlaceProfilePhotoImage(
                    photo: photo,
                    canonicalPlaceKey: sheetPlace.photoRequest.canonicalPhotoCacheKey,
                    placeName: place.place.canonicalName,
                    photoRequest: sheetPlace.photoRequest,
                    variant: .feed,
                    onLoadFailure: handlePhotoLoadFailure
                )
            } else {
                Color.clear
                    .accessibilityHidden(true)
            }
        }
        .task(id: photoResolutionKey) {
            await resolvePhoto()
        }
    }

    private func resolvePhoto() async {
        let resolutionKey = photoResolutionKey
        let request = sheetPlace.photoRequest.rendering(.feed)
        if let cachedPhoto = backend.cachedPlacePhoto(for: request),
           !(cachedPhoto.isGooglePlacesPhoto
                && cachedPhoto.providerPlaceID == failedGooglePhotoID) {
            photo = cachedPhoto
            return
        }
        photo = nil

        do {
            let remotePhoto = try await backend.placePhoto(for: request)
            try Task.checkCancellation()
            let resolvedPhoto: PlacePhoto
            if remotePhoto.isGooglePlacesPhoto,
               remotePhoto.providerPlaceID == failedGooglePhotoID {
                resolvedPhoto = try await backend.visibleUserPlacePhoto(for: sheetPlace.photoRequest)
            } else {
                resolvedPhoto = remotePhoto
            }
            try Task.checkCancellation()
            guard resolutionKey == photoResolutionKey else { return }
            photo = resolvedPhoto
        } catch is CancellationError {
            return
        } catch {
            guard resolutionKey == photoResolutionKey else { return }
            photo = nil
        }
    }

    private func handlePhotoLoadFailure(_ failedPhoto: PlacePhoto) {
        guard failedPhoto.providerPlaceID == photo?.providerPlaceID else { return }
        if failedPhoto.isGooglePlacesPhoto {
            failedGooglePhotoID = failedPhoto.providerPlaceID
        } else {
            photo = nil
        }
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
            FeedSectionHeading(title: "Recent")
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

            FeedSectionHeading(title: "Recent", detail: "Unavailable")
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
    @Environment(\.astirBrandMode) private var brandMode
    let recommendations: [DiscoverPeopleRecommendation]
    let followingProfileIDs: Set<String>
    let openSearch: () -> Void
    let openProfile: (ProfileShell) -> Void
    let follow: (DiscoverPeopleRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("Your Feed fills up from people you follow.")
                    .font(AstirTypography.sectionTitle)
                    .foregroundStyle(brandMode.primaryText)
                Text("Find people whose place memory you’d actually use, then come back here to catch up.")
                    .font(AstirTypography.bodySmall)
                    .foregroundStyle(brandMode.secondaryText)
            }

            if recommendations.isEmpty {
                Button("Find people", action: openSearch)
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentForeground)
                    .frame(minHeight: 44)
                    .padding(.horizontal, WanderTheme.spacing4)
                    .background(brandMode.accent)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
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
                                color: brandMode.accent
                            )
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(recommendation.profile.displayName)
                                .font(AstirTypography.cardTitle)
                            Text(recommendation.reason.displayText(for: recommendation.profile))
                                .font(AstirTypography.caption)
                                .foregroundStyle(brandMode.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        Button {
                            follow(recommendation)
                        } label: {
                            if followingProfileIDs.contains(recommendation.profile.id) {
                                ProgressView()
                                    .tint(brandMode.accent)
                                    .frame(width: 44, height: 44)
                            } else {
                                Text("Follow")
                                    .font(AstirTypography.label)
                                    .foregroundStyle(brandMode.accent)
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
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge, style: .continuous)
                .stroke(brandMode.border, lineWidth: 1)
        }
    }
}

private struct FeedRetryRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let title: String
    let subtitle: String
    let actionTitle: String
    let retry: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(brandMode.secondaryText)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AstirTypography.label)
                Text(subtitle)
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            }

            Spacer(minLength: 0)

            Button(actionTitle) {
                Task { await retry() }
            }
            .font(AstirTypography.label)
            .foregroundStyle(brandMode.accent)
            .frame(minHeight: 44)
        }
        .padding(WanderTheme.spacing3)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous))
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
        place.effectiveCompactType,
        place.place.locality,
        place.place.region
    ]
    .compactMap { value in
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
    .joined(separator: " · ")
}

func categorySymbol(for category: String) -> String {
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
