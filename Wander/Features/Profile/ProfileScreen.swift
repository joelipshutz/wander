import Foundation
import MapKit
import SwiftUI

struct ProfileScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @EnvironmentObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @State private var showsSettings = false
    @State private var showsProfilePhotoViewer = false
    @State private var socialGraphTab: ProfileSocialGraphTab?
    @State private var listMode: GraphListMode?
    @State private var selectedPeopleMode: GraphListMode = .following
    @State private var savedListMode: SavedPlacesListMode?
    @State private var activityListFilter: ProfileActivityFilter?
    @State private var selectedActivityItemID: String?
    @State private var placeCollectionRoute: ProfilePlaceCollectionRoute?
    @State private var showsVisitInvitations = false
    @State private var showsEditProfile = false
    @State private var selectedMonth = Date.now
    @State private var profileInsightsCache = ProfileInsightsCache()
    @State private var activeCalendarLaunchRequest: WanderProfileCalendarLaunchRequest?
    @State private var handledPresentationResetRequestID: UUID?
    @State private var settingsPresentationToken: WanderDeepLinkPresentationToken?

    @Binding private var visitInvitationInboxRequestID: UUID?
    private let presentationResetRequest: WanderPresentationResetRequest?
    private let calendarLaunchRequest: WanderProfileCalendarLaunchRequest?
    private let onCalendarLaunchRequestHandled: (UUID) -> Void
    private let onSettingsPresentation: (WanderDeepLinkPresentationToken) -> Void
    private let onSettingsWillDismiss: (WanderDeepLinkPresentationToken) -> Void
    private let onSettingsDidDismiss: () -> Void
    let onFindFriends: () -> Void

    init(
        visitInvitationInboxRequestID: Binding<UUID?> = .constant(nil),
        presentationResetRequest: WanderPresentationResetRequest? = nil,
        calendarLaunchRequest: WanderProfileCalendarLaunchRequest? = nil,
        onCalendarLaunchRequestHandled: @escaping (UUID) -> Void = { _ in },
        onSettingsPresentation: @escaping (WanderDeepLinkPresentationToken) -> Void = { _ in },
        onSettingsWillDismiss: @escaping (WanderDeepLinkPresentationToken) -> Void = { _ in },
        onSettingsDidDismiss: @escaping () -> Void = {},
        onFindFriends: @escaping () -> Void = {}
    ) {
        _visitInvitationInboxRequestID = visitInvitationInboxRequestID
        self.presentationResetRequest = presentationResetRequest
        self.calendarLaunchRequest = calendarLaunchRequest
        self.onCalendarLaunchRequestHandled = onCalendarLaunchRequestHandled
        self.onSettingsPresentation = onSettingsPresentation
        self.onSettingsWillDismiss = onSettingsWillDismiss
        self.onSettingsDidDismiss = onSettingsDidDismiss
        self.onFindFriends = onFindFriends
    }

    var body: some View {
        NavigationStack {
            ProfileOwnerHome(
                profile: store.currentUser,
                viewerProfile: store.currentUser,
                mode: .owner,
                stats: profileStats,
                saveStreak: store.saveStreakSummary,
                followerCount: store.followers(of: store.currentUser.id).count,
                followingCount: store.following(of: store.currentUser.id).count,
                sharedVisitInvitationCount: store.sharedVisitInvitations.count,
                insights: profileInsights,
                selectedMonth: $selectedMonth,
                avatarAction: presentProfilePhotoViewer,
                editAction: { showsEditProfile = true },
                settingsAction: {
                    walkthroughs.perform(.profileSettings)
                    presentSettings()
                },
                shareAction: {
                    walkthroughs.perform(.profileShare)
                },
                relationshipAction: {},
                backAction: nil,
                memberActions: nil,
                graphAction: {
                    walkthroughs.perform(.profileSocial)
                    socialGraphTab = $0
                },
                sharedVisitInvitationsAction: { showsVisitInvitations = true },
                recentActivity: profileActivityItems,
                recentActivityAction: { item in
                    walkthroughs.perform(.profileActivity)
                    selectedActivityItemID = item.id
                },
                allActivityAction: { filter in
                    walkthroughs.perform(.profileActivity)
                    activityListFilter = filter
                },
                inCommonAction: {},
                calendarDateAction: { summary in
                    placeCollectionRoute = .calendar(summary)
                },
                mapSummaryAction: { kind, item in
                    placeCollectionRoute = .mapSummary(kind: kind, item: item)
                },
                calendarScrollRequestID: activeCalendarLaunchRequest?.id,
                onCalendarScrollRequestHandled: completeCalendarLaunchRequest
            )
                .accessibilityHidden(showsSettings)
                .allowsHitTesting(!showsSettings)
                .overlay {
                    if showsSettings {
                        SettingsScreen(onDismiss: dismissSettings)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                        .environmentObject(pushNotifications)
                        .transition(.move(edge: .trailing))
                        .zIndex(1)
                        .onAppear(perform: beginSettingsPresentationLifecycle)
                    }
                }
                .toolbar(showsSettings ? .hidden : .visible, for: .tabBar)
                .sheet(item: $socialGraphTab, onDismiss: {
                    walkthroughs.activate(.profile)
                }) { tab in
                    ProfileSocialGraphScreen(
                        profileID: store.currentUser.id,
                        initialTab: tab,
                        onFindFriends: onFindFriends
                    )
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .sheet(isPresented: $showsEditProfile) {
                    ProfileEditScreen()
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .fullScreenCover(isPresented: $showsProfilePhotoViewer) {
                    ProfilePhotoFullScreenViewer(
                        avatarURL: store.currentUser.avatarURL,
                        displayName: store.currentUser.displayName
                    )
                }
                .onChange(of: showsSettings) { _, isShowing in
                    if !isShowing {
                        endSettingsPresentationLifecycle()
                        onSettingsDidDismiss()
                        walkthroughs.activate(.profile)
                    }
                }
                .navigationDestination(item: $savedListMode) { mode in
                    SavedPlacesListScreen(mode: mode, profileID: store.currentUser.id)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .navigationDestination(item: $activityListFilter) { filter in
                    ProfileActivityHistoryScreen(
                        items: profileActivityItems,
                        initialFilter: filter,
                        checkInCount: profileStats.checkIns,
                        wannaCount: profileStats.wanna,
                        itemAction: { item in
                            selectedActivityItemID = item.id
                        }
                    )
                }
                .navigationDestination(isPresented: activityPlaceDestinationBinding) {
                    selectedActivityPlaceDestination
                }
                .navigationDestination(item: $placeCollectionRoute) { route in
                    SavedPlacesListScreen(collection: route, profileID: store.currentUser.id)
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                }
                .navigationDestination(isPresented: $showsVisitInvitations) {
                    SharedVisitInvitationInboxScreen { invitation in
                        showsVisitInvitations = false
                        pushNotifications.openSharedVisit(
                            participantID: invitation.participantID,
                            generation: invitation.invitationGeneration
                        )
                    }
                    .environmentObject(store)
                    .environmentObject(backend)
                }
                .task(id: auth.isSignedIn) {
                    guard auth.isSignedIn else { return }
                    await store.refreshRemoteCurrentProfile(backend: backend)
                    await store.refreshRemoteCurrentUserProfileData(backend: backend)
                    await store.refreshSharedVisitInbox(backend: backend)
                    handleNotificationRoute(pushNotifications.navigationRequest)
                }
                .onChange(of: pushNotifications.navigationRequest) { _, request in
                    handleNotificationRoute(request)
                }
                .onAppear {
                    openRequestedVisitInvitationInbox()
                }
                .onChange(of: visitInvitationInboxRequestID) { _, _ in
                    openRequestedVisitInvitationInbox()
                }
        }
        .task(id: presentationResetRequest?.id) {
            handlePresentationResetRequest(presentationResetRequest)
        }
        .task(id: calendarLaunchRequest?.id) {
            guard let request = calendarLaunchRequest else {
                activeCalendarLaunchRequest = nil
                return
            }

            handlePresentationResetRequest(presentationResetRequest)
            resetProfilePresentations()
            selectedMonth = request.targetDate

            await Task.yield()
            guard !Task.isCancelled, calendarLaunchRequest?.id == request.id else { return }
            switch request.destination {
            case .calendar:
                activeCalendarLaunchRequest = request
            case .day:
                placeCollectionRoute = .calendar(
                    calendarDaySummary(on: request.targetDate)
                )
                onCalendarLaunchRequestHandled(request.id)
            }
        }
    }

    private func handlePresentationResetRequest(_ request: WanderPresentationResetRequest?) {
        guard let request,
              handledPresentationResetRequestID != request.id
        else { return }

        handledPresentationResetRequestID = request.id
        resetProfilePresentations()
    }

    private func resetProfilePresentations() {
        activeCalendarLaunchRequest = nil
        visitInvitationInboxRequestID = nil
        showsSettings = false
        showsProfilePhotoViewer = false
        socialGraphTab = nil
        listMode = nil
        savedListMode = nil
        activityListFilter = nil
        selectedActivityItemID = nil
        placeCollectionRoute = nil
        showsVisitInvitations = false
        showsEditProfile = false
    }

    private func presentSettings() {
        withAnimation(.easeOut(duration: 0.24)) {
            showsSettings = true
        }
    }

    private func dismissSettings() {
        withAnimation(.easeOut(duration: 0.22)) {
            showsSettings = false
        }
    }

    private func beginSettingsPresentationLifecycle() {
        guard settingsPresentationToken == nil else { return }
        let token = WanderDeepLinkPresentationToken(surface: .profileSettings)
        settingsPresentationToken = token
        onSettingsPresentation(token)
    }

    private func endSettingsPresentationLifecycle() {
        guard let token = settingsPresentationToken else { return }
        settingsPresentationToken = nil
        onSettingsWillDismiss(token)
    }

    private func completeCalendarLaunchRequest(_ id: UUID) {
        guard activeCalendarLaunchRequest?.id == id else { return }
        activeCalendarLaunchRequest = nil
        onCalendarLaunchRequestHandled(id)
    }

    private func calendarDaySummary(on date: Date) -> ProfileCalendarDaySummary {
        let projection = store.currentUserCalendarProjection
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let insights = profileInsightsCache.present(
            ownerID: store.currentUser.id,
            userPlaces: projection.userPlaces,
            visits: projection.visits,
            places: projection.places,
            month: date,
            calendar: calendar,
            dataRevision: store.presentationRevision
        )
        return insights.monthDaySummaries[day]
            ?? ProfileCalendarDaySummary.empty(on: day)
    }

    private func openRequestedVisitInvitationInbox() {
        guard visitInvitationInboxRequestID != nil else { return }
        showsVisitInvitations = true
        visitInvitationInboxRequestID = nil
    }

    private var profileInsights: ProfileInsights {
        let projection = store.currentUserCalendarProjection
        return profileInsightsCache.present(
            ownerID: store.currentUser.id,
            userPlaces: projection.userPlaces,
            visits: projection.visits,
            places: projection.places,
            month: selectedMonth,
            dataRevision: store.presentationRevision
        )
    }

    private var profileStats: ProfileStats {
        store.currentUserCalendarProjection.profileStats(
            currentUserID: store.currentUser.id,
            friends: store.friends(of: store.currentUser.id).count
        )
    }

    private var profileActivityItems: [ProfileActivityItem] {
        let projection = store.currentUserCalendarProjection
        return ProfileActivityPresenter.items(
            visiblePlaces: projection.visiblePlaces,
            visits: projection.visits,
            currentUserID: store.currentUser.id
        )
    }

    private var selectedActivityItem: ProfileActivityItem? {
        guard let selectedActivityItemID else { return nil }
        return profileActivityItems.first { $0.id == selectedActivityItemID }
    }

    private var activityPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedActivityItem != nil },
            set: { isPresented in
                if !isPresented {
                    selectedActivityItemID = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedActivityPlaceDestination: some View {
        if let item = selectedActivityItem {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: item.visiblePlace),
                saves: activitySaveSummaries(for: item.visiblePlace),
                tasteSaves: activityTasteSummaries,
                currentUserID: store.currentUser.id,
                action: .none,
                initialSection: .activity,
                onBack: {
                    selectedActivityItemID = nil
                },
                onAction: {}
            )
        }
    }

    private func activitySaveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        return store.visiblePlaces()
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard seen.insert(visiblePlace.userPlace.id).inserted else { return false }
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: store.attributes(for: visiblePlace.userPlace.id),
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
            }
            .sorted { lhs, rhs in
                if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
                if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
                return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(
                    rhs.visiblePlace.owner.displayName
                ) == .orderedAscending
            }
    }

    private var activityTasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id),
                viewerFollowsOwner: false
            )
        }
    }

    private var pageTitle: some View {
        Text("profile")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private var statsGrid: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button {
                savedListMode = .been
            } label: {
                StatTile(
                    value: "\(store.stats.checkIns)",
                    label: CheckInCopy.pluralNoun.uppercased(),
                    color: WanderTheme.stateSuccess.color,
                    fill: WanderTheme.categorySage.color.opacity(0.22)
                )
            }
            .buttonStyle(ProfileStatButtonStyle())
            .accessibilityLabel("Open checked-in places")

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
                    .id("profile.draft.\(draft.extractionJobID ?? draft.id)")
                }
            }
        }
        .id("profile.drafts")
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
        .id("profile.people")
    }

    private func handleNotificationRoute(_ request: NotificationNavigationRequest?) {
        guard let request else { return }

        switch request.destination {
        case .people(let mode):
            socialGraphTab = switch mode {
            case .following: ProfileSocialGraphTab.following
            case .followers: ProfileSocialGraphTab.followers
            case .friends: ProfileSocialGraphTab.friends
            }
        case .drafts:
            break
        default:
            return
        }

        pushNotifications.consumeNavigationRequest(id: request.id)
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

    private var hasProfilePhoto: Bool {
        guard let avatarURL = store.currentUser.avatarURL else { return false }
        return !avatarURL.isEmpty
    }

    private func presentProfilePhotoViewer() {
        guard hasProfilePhoto else { return }
        showsProfilePhotoViewer = true
    }
}

struct ProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let profileID: String
    let onBlock: (String) -> Void
    @State private var selectedMonth = Date.now
    @State private var socialGraphTab: ProfileSocialGraphTab?
    @State private var savedListMode: SavedPlacesListMode?
    @State private var activityListFilter: ProfileActivityFilter?
    @State private var selectedActivityItemID: String?
    @State private var placeCollectionRoute: ProfilePlaceCollectionRoute?
    @State private var showBlockConfirm = false
    @State private var showUnfollowConfirm = false
    @State private var reportSubject: CommunityReportSubject?
    @State private var isLoading = true
    @State private var profileInsightsCache = ProfileInsightsCache()

    init(profileID: String, onBlock: @escaping (String) -> Void = { _ in }) {
        self.profileID = profileID
        self.onBlock = onBlock
    }

    private var profile: LocalProfile? {
        store.profile(for: profileID)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                Group {
                    if let profile {
                        ProfileOwnerHome(
                            profile: profile,
                            viewerProfile: store.currentUser,
                            mode: .member(
                                relationship: store.relationship(to: profileID),
                                inCommonCount: inCommonPlaces.count
                            ),
                            stats: profileStats,
                            saveStreak: nil,
                            followerCount: store.followers(of: profileID).count,
                            followingCount: store.following(of: profileID).count,
                            sharedVisitInvitationCount: 0,
                            insights: profileInsights,
                            selectedMonth: $selectedMonth,
                            avatarAction: {},
                            editAction: {},
                            settingsAction: {},
                            shareAction: {},
                            relationshipAction: handleRelationshipAction,
                            backAction: { dismiss() },
                            memberActions: ProfileMemberActions(
                                canUnfollow: store.relationship(to: profileID) == .follower || store.relationship(to: profileID) == .mutual,
                                isMuted: store.isMuted(userID: profileID),
                                unfollowAction: { showUnfollowConfirm = true },
                                toggleMuteAction: toggleMute,
                                reportAction: presentProfileReport,
                                blockAction: { showBlockConfirm = true }
                            ),
                            graphAction: { socialGraphTab = $0 },
                            sharedVisitInvitationsAction: {},
                            recentActivity: profileActivityItems,
                            recentActivityAction: { item in
                                selectedActivityItemID = item.id
                            },
                            allActivityAction: { filter in
                                activityListFilter = filter
                            },
                            inCommonAction: { savedListMode = .inCommon },
                            calendarDateAction: { summary in
                                placeCollectionRoute = .calendar(summary)
                            },
                            mapSummaryAction: { kind, item in
                                placeCollectionRoute = .mapSummary(kind: kind, item: item)
                            },
                            calendarScrollRequestID: nil,
                            onCalendarScrollRequestHandled: { _ in }
                        )
                    } else if isLoading {
                        ProgressView("Loading profile")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .wanderScreen()
                    } else {
                        AccessChangedPanel(
                            title: "This profile isn't available",
                            subtitle: "It may have been removed, blocked, or become unavailable."
                        )
                        .padding(WanderTheme.spacing4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .wanderScreen()
                    }
                }

                if profile == nil {
                    ProfileHeaderActionButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "Back",
                        action: { dismiss() }
                    )
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.top, WanderTheme.spacing3)
                }
            }
            .navigationDestination(item: $savedListMode) { mode in
                SavedPlacesListScreen(mode: mode, profileID: profileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .navigationDestination(item: $activityListFilter) { filter in
                ProfileActivityHistoryScreen(
                    items: profileActivityItems,
                    initialFilter: filter,
                    checkInCount: profileStats.checkIns,
                    wannaCount: profileStats.wanna,
                    itemAction: { item in
                        selectedActivityItemID = item.id
                    }
                )
            }
            .navigationDestination(isPresented: activityPlaceDestinationBinding) {
                selectedActivityPlaceDestination
            }
            .navigationDestination(item: $placeCollectionRoute) { route in
                SavedPlacesListScreen(collection: route, profileID: profileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $socialGraphTab) { tab in
                ProfileSocialGraphScreen(profileID: profileID, initialTab: tab, onFindFriends: {})
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $reportSubject) { subject in
                CommunityReportSheet(subject: subject)
                    .environmentObject(backend)
            }
            .alert("Block this person?", isPresented: $showBlockConfirm) {
                Button("Block", role: .destructive) { confirmBlock() }
                Button("Cancel", role: .cancel) { showBlockConfirm = false }
            } message: {
                Text("You won't see each other's profiles, places, or search results.")
            }
            .alert(unfollowConfirmationTitle, isPresented: $showUnfollowConfirm) {
                Button("Yes, unfollow", role: .destructive) { confirmUnfollow() }
                Button("No, cancel", role: .cancel) { showUnfollowConfirm = false }
            } message: {
                Text("Their places will stop appearing in your social map.")
            }
            .task(id: profileID) {
                await refreshRemoteProfile()
                await store.refreshRemoteMutes(backend: backend)
                isLoading = false
                if profile != nil {
                    store.productAnalytics.track(
                        .engagement(
                            need: .connect,
                            action: .trustedProfileViewed,
                            surface: "profile_detail"
                        )
                    )
                }
            }
        }
    }

    private var profileVisiblePlaces: [VisiblePlace] {
        store.visiblePlaces(for: profileID)
    }

    private var inCommonPlaces: [VisiblePlace] {
        store.placesInCommon(with: profileID)
    }

    private var profileStats: ProfileStats {
        let places = VisiblePlaceGrouping.representativePlaces(
            from: profileVisiblePlaces,
            currentUserID: store.currentUser.id
        )
        let uniqueCheckedInPlaces = places.filter { $0.userPlace.status == .been }.count
        let activeIDs = Set(places.flatMap {
            [$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].compactMap { $0 }
        })
        let checkInCount = store.placeVisits.filter {
            $0.deletedAt == nil && activeIDs.contains($0.userPlaceID)
        }.count
        return ProfileStats(
            been: uniqueCheckedInPlaces,
            checkIns: max(checkInCount, uniqueCheckedInPlaces),
            wanna: places.filter { $0.userPlace.status == .wannaGo }.count,
            friends: store.friends(of: profileID).count
        )
    }

    private var profileInsights: ProfileInsights {
        profileInsightsCache.present(
            ownerID: profileID,
            userPlaces: profileVisiblePlaces.map(\.userPlace),
            visits: store.placeVisits,
            places: profileVisiblePlaces.map(\.place),
            month: selectedMonth,
            dataRevision: store.presentationRevision
        )
    }

    private var profileActivityItems: [ProfileActivityItem] {
        ProfileActivityPresenter.items(
            visiblePlaces: profileVisiblePlaces,
            visits: store.placeVisits,
            currentUserID: profileID
        )
    }

    private var selectedActivityItem: ProfileActivityItem? {
        guard let selectedActivityItemID else { return nil }
        return profileActivityItems.first { $0.id == selectedActivityItemID }
    }

    private var activityPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedActivityItem != nil },
            set: { isPresented in
                if !isPresented {
                    selectedActivityItemID = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedActivityPlaceDestination: some View {
        if let item = selectedActivityItem {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: item.visiblePlace),
                saves: activitySaveSummaries(for: item.visiblePlace),
                tasteSaves: activityTasteSummaries,
                currentUserID: store.currentUser.id,
                action: .none,
                initialSection: .activity,
                onBack: {
                    selectedActivityItemID = nil
                },
                onAction: {}
            )
        }
    }

    private func activitySaveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        return store.visiblePlaces()
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard seen.insert(visiblePlace.userPlace.id).inserted else { return false }
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: store.attributes(for: visiblePlace.userPlace.id),
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
            }
            .sorted { lhs, rhs in
                if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
                if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
                return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(
                    rhs.visiblePlace.owner.displayName
                ) == .orderedAscending
            }
    }

    private var activityTasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id),
                viewerFollowsOwner: false
            )
        }
    }

    private func handleRelationshipAction() {
        switch store.relationship(to: profileID) {
        case .nonFollower:
            auth.requireSignIn(for: .followPeople) {
                Task {
                    await store.follow(userID: profileID, source: .profile, backend: backend)
                    await refreshRemoteProfile()
                }
            }
        case .follower, .mutual:
            showUnfollowConfirm = true
        case .owner:
            break
        }
    }

    private func toggleMute() {
        auth.requireSignIn(for: .manageBlocks) {
            Task {
                if store.isMuted(userID: profileID) {
                    await store.unmute(userID: profileID, backend: backend)
                } else {
                    await store.mute(userID: profileID, backend: backend)
                }
            }
        }
    }

    private func presentProfileReport() {
        auth.requireSignIn(for: .reportContent) {
            reportSubject = CommunityReportSubject(
                kind: .profile,
                subjectID: profileID,
                reportedUserID: profileID,
                context: "Report @\(profile?.handle ?? "this person") and anything they’ve shared."
            )
        }
    }

    private func confirmBlock() {
        let shell = profile.map(store.shell(for:))
        showBlockConfirm = false
        auth.requireSignIn(for: .manageBlocks) {
            Task {
                if let shell {
                    await store.block(profile: shell, backend: backend)
                } else {
                    await store.block(userID: profileID, backend: backend)
                }
                await MainActor.run {
                    onBlock(profileID)
                    dismiss()
                }
            }
        }
    }

    private func refreshRemoteProfile() async {
        await store.refreshRemoteProfileData(profileID: profileID, backend: backend)
    }

    private var unfollowConfirmationTitle: String {
        guard let profile else { return "Are you sure you want to unfollow this person" }
        return "Are you sure you want to unfollow \(profile.displayName)"
    }

    private func confirmUnfollow() {
        showUnfollowConfirm = false
        auth.requireSignIn(for: .followPeople) {
            Task {
                await store.unfollow(userID: profileID, backend: backend)
                await refreshRemoteProfile()
            }
        }
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

private struct ProfileActivityHistoryScreen: View {
    let items: [ProfileActivityItem]
    let checkInCount: Int
    let wannaCount: Int
    let itemAction: (ProfileActivityItem) -> Void
    @State private var filter: ProfileActivityFilter

    init(
        items: [ProfileActivityItem],
        initialFilter: ProfileActivityFilter,
        checkInCount: Int,
        wannaCount: Int,
        itemAction: @escaping (ProfileActivityItem) -> Void
    ) {
        self.items = items
        self.checkInCount = checkInCount
        self.wannaCount = wannaCount
        self.itemAction = itemAction
        _filter = State(initialValue: initialFilter)
    }

    private var filteredItems: [ProfileActivityItem] {
        items.filter(filter.includes)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                ProfileActivityFilterControl(
                    selection: $filter,
                    checkInCount: checkInCount,
                    wannaCount: wannaCount
                )

                if filteredItems.isEmpty {
                    SmallEmptyRow(
                        title: emptyStateTitle,
                        subtitle: "Saved places and check-ins will appear here"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            ProfileActivityRow(item: item) {
                                itemAction(item)
                            }
                            if index < filteredItems.count - 1 {
                                Divider()
                                    .overlay(WanderTheme.borderHairline.color)
                                    .padding(.leading, 58)
                            }
                        }
                    }
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .wanderScreen()
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyStateTitle: String {
        switch filter {
        case .all: "No activity yet"
        case .checkIns: "No check-ins yet"
        case .wanna: "No Wanna activity yet"
        }
    }
}

private enum SavedPlacesListMode: String, Identifiable {
    case been
    case wanna
    case inCommon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .been: "Check-ins"
        case .wanna: "Wanna"
        case .inCommon: "In Common"
        }
    }

    var status: PlaceStatus? {
        switch self {
        case .been: .been
        case .wanna: .wannaGo
        case .inCommon: nil
        }
    }
}

enum ProfilePlaceCollectionSource: String, Hashable {
    case calendar
    case mapSummary

    var presentsInteractiveMap: Bool {
        switch self {
        case .calendar, .mapSummary:
            true
        }
    }
}

struct ProfilePlaceCollectionRoute: Identifiable, Hashable {
    let id: String
    let title: String
    let placeIDs: [String]
    let source: ProfilePlaceCollectionSource
    let calendarDay: ProfileCalendarDaySummary?

    var includesAllStatuses: Bool {
        false
    }

    static func calendar(_ summary: ProfileCalendarDaySummary, calendar: Calendar = .current) -> Self {
        let day = calendar.startOfDay(for: summary.date)
        return ProfilePlaceCollectionRoute(
            id: "calendar-\(day.timeIntervalSince1970)",
            title: summary.date.formatted(.dateTime.month(.wide).day().year()),
            placeIDs: summary.placeIDs,
            source: .calendar,
            calendarDay: summary
        )
    }

    static func mapSummary(kind: ProfileMapSummaryKind, item: ProfileSummaryItem) -> Self {
        ProfilePlaceCollectionRoute(
            id: "map-\(kind.rawValue)-\(item.id)",
            title: item.title,
            placeIDs: item.placeIDs,
            source: .mapSummary,
            calendarDay: nil
        )
    }

}

enum ProfilePlaceCollectionMatcher {
    static func matches(_ visiblePlace: VisiblePlace, acceptedPlaceIDs: Set<String>) -> Bool {
        var placeIDs = [visiblePlace.place.id, visiblePlace.place.localID]
        if let serverID = visiblePlace.place.serverID {
            placeIDs.append(serverID)
        }
        return !acceptedPlaceIDs.isDisjoint(with: placeIDs)
    }
}

struct ProfilePlaceCollectionMapItem: Identifiable {
    let id: String
    let visiblePlace: VisiblePlace
    let mapCoordinate: ListMapCoordinate
    let saveStates: [MapPinSaveState]
    let outlines: [MapPinOutline]
    let accessibilityLabel: String

    var coordinate: CLLocationCoordinate2D {
        mapCoordinate.coordinate
    }
}

struct ProfilePlaceCollectionMapPresentation {
    let items: [ProfilePlaceCollectionMapItem]
    let totalCount: Int

    var contentState: ListMapContentState {
        ListMapContentState(
            totalItemCount: totalCount,
            resolvedPlaceCount: totalCount,
            mappedPlaceCount: items.count
        )
    }

    var fittedRegion: MKCoordinateRegion? {
        MapRegionFitter.region(
            fitting: items.map(\.coordinate),
            minimumSpan: 0.012,
            paddingMultiplier: 1.65
        )
    }
}

enum ProfilePlaceCollectionMapProjection {
    static func presentation(
        for visiblePlaces: [VisiblePlace],
        currentUserID: String
    ) -> ProfilePlaceCollectionMapPresentation {
        let groups = VisiblePlaceGrouping.groups(
            from: visiblePlaces,
            currentUserID: currentUserID
        )
        let items = groups.compactMap { group -> ProfilePlaceCollectionMapItem? in
            guard let mappedPlace = group.places.first(where: isMappable) else {
                return nil
            }

            let saveStates = group.places.map { visiblePlace in
                MapPinSaveState(
                    ownership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                    status: visiblePlace.userPlace.status
                )
            }
            let outlines = MapPinOutlineBuilder.outlines(for: saveStates)
            let primary = group.primary
            let mapCoordinate = ListMapCoordinate(
                id: group.id,
                coordinate: CLLocationCoordinate2D(
                    latitude: mappedPlace.place.latitude,
                    longitude: mappedPlace.place.longitude
                )
            )

            return ProfilePlaceCollectionMapItem(
                id: group.id,
                visiblePlace: primary,
                mapCoordinate: mapCoordinate,
                saveStates: saveStates,
                outlines: outlines,
                accessibilityLabel: accessibilityLabel(for: primary, outlines: outlines)
            )
        }

        return ProfilePlaceCollectionMapPresentation(
            items: items,
            totalCount: groups.count
        )
    }

    private static func isMappable(_ visiblePlace: VisiblePlace) -> Bool {
        ListMapCoordinate(
            id: visiblePlace.id,
            coordinate: CLLocationCoordinate2D(
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude
            )
        ).isMappable
    }

    private static func accessibilityLabel(
        for visiblePlace: VisiblePlace,
        outlines: [MapPinOutline]
    ) -> String {
        let hasCurrentUser = outlines.contains { $0.ownership == .currentUser }
        let hasSocial = outlines.contains { $0.ownership == .social }
        let ownership: String
        if hasCurrentUser && hasSocial {
            ownership = "Your and social saved place"
        } else if hasCurrentUser {
            ownership = "Your saved place"
        } else {
            ownership = "Social saved place"
        }

        return "\(ownership) \(visiblePlace.effectiveCompactType), \(visiblePlace.place.canonicalName)"
    }
}

enum ProfilePlaceCollectionMapClusterer {
    private struct GridCell: Hashable {
        let column: Int
        let row: Int
    }

    private struct ClusterAccumulator {
        let anchorPoint: CGPoint
        let anchorCoordinate: ListMapCoordinate
        var memberIDs: [String]
    }

    static func clusters(
        for coordinates: [ListMapCoordinate],
        in region: MKCoordinateRegion,
        viewportSize: CGSize,
        minimumScreenDistance: CGFloat = 52
    ) -> [ListMapCluster] {
        let validCoordinates = coordinates.filter(\.isMappable)
        guard !validCoordinates.isEmpty else { return [] }

        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let latitudeSpan = max(region.span.latitudeDelta, 0.000_001)
        let longitudeSpan = max(region.span.longitudeDelta, 0.000_001)
        let resolvedDistance = max(minimumScreenDistance, 1)
        let squaredDistanceThreshold = resolvedDistance * resolvedDistance
        var clusterIndicesByCell: [GridCell: [Int]] = [:]
        var accumulators: [ClusterAccumulator] = []

        for item in validCoordinates {
            let point = CGPoint(
                x: width * (0.5 + normalizedLongitudeDelta(
                    item.longitude - region.center.longitude
                ) / longitudeSpan),
                y: height * (0.5 - (item.latitude - region.center.latitude) / latitudeSpan)
            )
            let cell = GridCell(
                column: Int(floor(point.x / resolvedDistance)),
                row: Int(floor(point.y / resolvedDistance))
            )

            var nearestCluster: (index: Int, squaredDistance: CGFloat)?
            for rowOffset in -1...1 {
                for columnOffset in -1...1 {
                    let neighbor = GridCell(
                        column: cell.column + columnOffset,
                        row: cell.row + rowOffset
                    )
                    for clusterIndex in clusterIndicesByCell[neighbor] ?? [] {
                        let anchor = accumulators[clusterIndex].anchorPoint
                        let x = point.x - anchor.x
                        let y = point.y - anchor.y
                        let squaredDistance = x * x + y * y
                        guard squaredDistance <= squaredDistanceThreshold else { continue }

                        if let currentNearest = nearestCluster {
                            if squaredDistance < currentNearest.squaredDistance
                                || (squaredDistance == currentNearest.squaredDistance
                                    && clusterIndex < currentNearest.index) {
                                nearestCluster = (clusterIndex, squaredDistance)
                            }
                        } else {
                            nearestCluster = (clusterIndex, squaredDistance)
                        }
                    }
                }
            }

            if let nearestCluster {
                accumulators[nearestCluster.index].memberIDs.append(item.id)
            } else {
                let clusterIndex = accumulators.count
                accumulators.append(
                    ClusterAccumulator(
                        anchorPoint: point,
                        anchorCoordinate: item,
                        memberIDs: [item.id]
                    )
                )
                clusterIndicesByCell[cell, default: []].append(clusterIndex)
            }
        }

        return accumulators.map { accumulator in
            return ListMapCluster(
                id: accumulator.memberIDs.sorted().joined(separator: "|"),
                memberIDs: accumulator.memberIDs,
                latitude: accumulator.anchorCoordinate.latitude,
                longitude: accumulator.anchorCoordinate.longitude
            )
        }
    }

    private static func normalizedLongitudeDelta(_ longitude: CLLocationDegrees) -> CLLocationDegrees {
        var result = longitude.truncatingRemainder(dividingBy: 360)
        if result > 180 {
            result -= 360
        } else if result < -180 {
            result += 360
        }
        return result
    }

}

enum ProfilePlaceCollectionMapCamera {
    static func region(
        fitting region: MKCoordinateRegion,
        viewportSize: CGSize
    ) -> MKCoordinateRegion {
        let width = max(viewportSize.width, 1)
        let height = max(viewportSize.height, 1)
        let viewportAspectRatio = Double(width / height)
        var latitudeDelta = max(region.span.latitudeDelta, 0.000_001)
        var longitudeDelta = max(region.span.longitudeDelta, 0.000_001)

        if longitudeDelta / latitudeDelta > viewportAspectRatio {
            latitudeDelta = max(latitudeDelta, longitudeDelta / viewportAspectRatio)
        } else {
            longitudeDelta = max(longitudeDelta, latitudeDelta * viewportAspectRatio)
        }

        latitudeDelta = min(latitudeDelta, 180)
        longitudeDelta = min(longitudeDelta, 360)
        let latitudeCenterLimit = (180 - latitudeDelta) / 2
        let latitude = min(
            max(region.center.latitude, -latitudeCenterLimit),
            latitudeCenterLimit
        )

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: latitude,
                longitude: region.center.longitude
            ),
            span: MKCoordinateSpan(
                latitudeDelta: latitudeDelta,
                longitudeDelta: longitudeDelta
            )
        )
    }
}

enum ProfilePlaceCollectionMapClusterActivation: Equatable {
    case zoom
    case open(String)
}

enum ProfilePlaceCollectionMapZoomTarget {
    private static let absoluteMinimumSpan: CLLocationDegrees = 0.0015
    private static let zoomScale: CLLocationDegrees = 0.32
    private static let paddingMultiplier: CLLocationDegrees = 1.75
    private static let expansionTolerance: CLLocationDegrees = 1.02
    private static let materialReductionRatio: CLLocationDegrees = 0.90

    static func region(
        for cluster: ListMapCluster,
        coordinatesByID: [String: ListMapCoordinate],
        visibleRegion: MKCoordinateRegion,
        viewportSize: CGSize
    ) -> MKCoordinateRegion? {
        let coordinates = cluster.memberIDs.compactMap { coordinatesByID[$0]?.coordinate }
        let minimumSpan = max(
            min(visibleRegion.span.latitudeDelta, visibleRegion.span.longitudeDelta) * zoomScale,
            absoluteMinimumSpan
        )
        guard let fittedRegion = MapRegionFitter.region(
            fitting: coordinates,
            minimumSpan: minimumSpan,
            paddingMultiplier: paddingMultiplier
        ) else {
            return nil
        }
        return ProfilePlaceCollectionMapCamera.region(
            fitting: fittedRegion,
            viewportSize: viewportSize
        )
    }

    static func makesMaterialProgress(
        from visibleRegion: MKCoordinateRegion,
        to targetRegion: MKCoordinateRegion
    ) -> Bool {
        let currentLatitude = visibleRegion.span.latitudeDelta
        let currentLongitude = visibleRegion.span.longitudeDelta
        let targetLatitude = targetRegion.span.latitudeDelta
        let targetLongitude = targetRegion.span.longitudeDelta
        guard currentLatitude.isFinite, currentLatitude > 0,
              currentLongitude.isFinite, currentLongitude > 0,
              targetLatitude.isFinite, targetLatitude > 0,
              targetLongitude.isFinite, targetLongitude > 0,
              targetLatitude <= currentLatitude * expansionTolerance,
              targetLongitude <= currentLongitude * expansionTolerance
        else {
            return false
        }

        // MapKit's Mercator projection can expand one degree span again,
        // especially at high latitudes. Requiring both spans to tighten keeps
        // a cluster from promising a zoom that renders as a no-op.
        return targetLatitude <= currentLatitude * materialReductionRatio
            && targetLongitude <= currentLongitude * materialReductionRatio
    }
}

enum ProfilePlaceCollectionMapClusterActivationResolver {
    static func activation(
        for cluster: ListMapCluster,
        coordinatesByID: [String: ListMapCoordinate],
        visibleRegion: MKCoordinateRegion,
        viewportSize: CGSize
    ) -> ProfilePlaceCollectionMapClusterActivation? {
        guard let firstID = cluster.memberIDs.first,
              let firstCoordinate = coordinatesByID[firstID] else { return nil }
        let coordinates = cluster.memberIDs.compactMap { coordinatesByID[$0] }
        let hasDistinctCoordinate = coordinates.dropFirst().contains { coordinate in
            coordinate.latitude != firstCoordinate.latitude
                || coordinate.longitude != firstCoordinate.longitude
        }
        guard hasDistinctCoordinate,
              let targetRegion = ProfilePlaceCollectionMapZoomTarget.region(
                for: cluster,
                coordinatesByID: coordinatesByID,
                visibleRegion: visibleRegion,
                viewportSize: viewportSize
              ),
              ProfilePlaceCollectionMapZoomTarget.makesMaterialProgress(
                from: visibleRegion,
                to: targetRegion
              )
        else {
            return .open(firstID)
        }
        return .zoom
    }
}

struct ProfilePlaceCollectionMapClusterAccessibility: Equatable {
    let label: String
    let hint: String

    static func presentation(
        count: Int,
        activation: ProfilePlaceCollectionMapClusterActivation?,
        destinationName: String?
    ) -> Self {
        switch activation {
        case .open:
            if let destinationName {
                return Self(
                    label: "\(destinationName), one of \(count) saved places at this location",
                    hint: "Shows \(destinationName) details. Every place remains in the list below."
                )
            }
            return Self(
                label: "\(count) saved places at this location",
                hint: "Shows one saved place. Every place remains in the list below."
            )
        case .zoom:
            return Self(
                label: "\(count) places close together",
                hint: "Zooms in"
            )
        case nil:
            return Self(
                label: "\(count) saved places",
                hint: "Every place remains in the list below."
            )
        }
    }
}

struct ProfilePlaceCollectionMapCameraLifecycle: Equatable {
    private(set) var hasAppliedOverviewRegion: Bool
    private(set) var hasAppliedViewportFit = false

    init(hasOverviewRegion: Bool) {
        hasAppliedOverviewRegion = hasOverviewRegion
    }

    mutating func reconcileOverview(isAvailable: Bool) -> Bool {
        guard isAvailable else {
            hasAppliedOverviewRegion = false
            hasAppliedViewportFit = false
            return false
        }
        guard !hasAppliedOverviewRegion else { return false }
        hasAppliedOverviewRegion = true
        hasAppliedViewportFit = false
        return true
    }

    mutating func markViewportFitApplied() {
        hasAppliedOverviewRegion = true
        hasAppliedViewportFit = true
    }
}

private struct ProfilePlaceCollectionMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let presentation: ProfilePlaceCollectionMapPresentation
    let overviewRegion: MKCoordinateRegion?
    let overviewTotalCount: Int
    let onSelect: (VisiblePlace) -> Void
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var clusters: [ListMapCluster]
    @State private var cameraLifecycle: ProfilePlaceCollectionMapCameraLifecycle

    private static let fallbackRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300)
    )

    init(
        presentation: ProfilePlaceCollectionMapPresentation,
        overviewRegion: MKCoordinateRegion?,
        overviewTotalCount: Int,
        onSelect: @escaping (VisiblePlace) -> Void
    ) {
        self.presentation = presentation
        self.overviewRegion = overviewRegion
        self.overviewTotalCount = overviewTotalCount
        self.onSelect = onSelect

        let initialRegion = overviewRegion ?? Self.fallbackRegion
        _position = State(initialValue: .region(initialRegion))
        _visibleRegion = State(initialValue: initialRegion)
        _clusters = State(initialValue: [])
        _cameraLifecycle = State(
            initialValue: ProfilePlaceCollectionMapCameraLifecycle(
                hasOverviewRegion: overviewRegion != nil
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if overviewRegion != nil {
                mapSurface
                statusBar
            } else {
                unavailablePanel
            }
        }
        .frame(maxWidth: .infinity)
        .background(WanderTheme.surfaceBone.color)
        .onChange(of: overviewRegionSignature) { _, signature in
            let shouldApplyOverview = cameraLifecycle.reconcileOverview(
                isAvailable: signature != nil
            )
            guard shouldApplyOverview, let overviewRegion else {
                if signature == nil {
                    clusters = []
                }
                return
            }
            visibleRegion = overviewRegion
            position = .region(overviewRegion)
            clusters = []
        }
    }

    private var mapSurface: some View {
        GeometryReader { proxy in
            let itemByID = Dictionary(
                uniqueKeysWithValues: presentation.items.map { ($0.id, $0) }
            )
            let coordinatesByID = Dictionary(
                uniqueKeysWithValues: presentation.items.map { ($0.id, $0.mapCoordinate) }
            )
            let currentClusters = clusters.filter { cluster in
                !cluster.memberIDs.isEmpty
                    && cluster.memberIDs.allSatisfy { itemByID[$0] != nil }
            }

            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(currentClusters) { cluster in
                    Annotation("", coordinate: cluster.coordinate) {
                        if cluster.isCluster {
                            Button {
                                activate(
                                    cluster,
                                    itemByID: itemByID,
                                    coordinatesByID: coordinatesByID,
                                    viewportSize: proxy.size
                                )
                            } label: {
                                ProfilePlaceCollectionClusterMarker(
                                    count: cluster.memberIDs.count,
                                    outlines: outlines(for: cluster, itemByID: itemByID)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(
                                clusterAccessibilityLabel(
                                    cluster,
                                    itemByID: itemByID,
                                    coordinatesByID: coordinatesByID,
                                    viewportSize: proxy.size
                                )
                            )
                            .accessibilityHint(
                                clusterAccessibilityHint(
                                    cluster,
                                    itemByID: itemByID,
                                    coordinatesByID: coordinatesByID,
                                    viewportSize: proxy.size
                                )
                            )
                        } else if let itemID = cluster.memberIDs.first,
                                  let item = itemByID[itemID] {
                            Button {
                                onSelect(item.visiblePlace)
                            } label: {
                                ProfilePlaceCollectionMapMarker(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.accessibilityLabel)
                            .accessibilityHint("Shows saved place details")
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .onAppear {
                let region = applyInitialCameraIfNeeded(viewportSize: proxy.size)
                refreshClusters(in: region, viewportSize: proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                refreshClusters(viewportSize: size)
            }
            .onChange(of: presentation.items.map(\.mapCoordinate)) { _, _ in
                refreshClusters(viewportSize: proxy.size)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                refreshClusters(in: context.region, viewportSize: proxy.size)
            }
        }
        .frame(height: mapHeight)
    }

    private var unavailablePanel: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "map")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Text(mapStatusText)
                .font(.system(size: 17, weight: .black))
                .multilineTextAlignment(.center)
            Text(unavailableSubtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: mapHeight)
        .padding(.horizontal, WanderTheme.spacing6)
        .accessibilityElement(children: .combine)
    }

    private var statusBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing2) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
            Text(mapStatusText)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
        .padding(.horizontal, WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WanderTheme.borderHairline.color)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var mapHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 240 : 280
    }

    private var overviewRegionSignature: [Double]? {
        overviewRegion.map { region in
            [
                region.center.latitude,
                region.center.longitude,
                region.span.latitudeDelta,
                region.span.longitudeDelta
            ]
        }
    }

    private var mapStatusText: String {
        switch presentation.contentState {
        case .empty:
            overviewTotalCount > 0 ? "No matching places to map" : "No places to map"
        case .unresolved(let total):
            "Locations unavailable for \(total) \(total == 1 ? "place" : "places")"
        case .partial(let mapped, let total):
            "\(mapped) mapped of \(total)"
        case .mapped(let count):
            "\(count) \(count == 1 ? "place" : "places")"
        }
    }

    private var unavailableSubtitle: String {
        if presentation.totalCount == 0, overviewTotalCount > 0 {
            return "Clear search or filters to restore map pins."
        }
        if overviewTotalCount > 0 {
            return "Every place remains available in the list below."
        }
        return "This collection does not have any places yet."
    }

    private func refreshClusters(viewportSize: CGSize) {
        refreshClusters(in: visibleRegion, viewportSize: viewportSize)
    }

    private func refreshClusters(in region: MKCoordinateRegion, viewportSize: CGSize) {
        clusters = ProfilePlaceCollectionMapClusterer.clusters(
            for: presentation.items.map(\.mapCoordinate),
            in: region,
            viewportSize: viewportSize
        )
    }

    private func applyInitialCameraIfNeeded(viewportSize: CGSize) -> MKCoordinateRegion {
        guard !cameraLifecycle.hasAppliedViewportFit, let overviewRegion else {
            return visibleRegion
        }
        let fittedRegion = ProfilePlaceCollectionMapCamera.region(
            fitting: overviewRegion,
            viewportSize: viewportSize
        )
        cameraLifecycle.markViewportFitApplied()
        visibleRegion = fittedRegion
        position = .region(fittedRegion)
        return fittedRegion
    }

    private func outlines(
        for cluster: ListMapCluster,
        itemByID: [String: ProfilePlaceCollectionMapItem]
    ) -> [MapPinOutline] {
        MapPinOutlineBuilder.outlines(
            for: cluster.memberIDs.flatMap { itemByID[$0]?.saveStates ?? [] }
        )
    }

    private func zoom(to region: MKCoordinateRegion) {
        if reduceMotion {
            position = .region(region)
        } else {
            withAnimation(.easeInOut(duration: 0.24)) {
                position = .region(region)
            }
        }
    }

    private func activate(
        _ cluster: ListMapCluster,
        itemByID: [String: ProfilePlaceCollectionMapItem],
        coordinatesByID: [String: ListMapCoordinate],
        viewportSize: CGSize
    ) {
        switch ProfilePlaceCollectionMapClusterActivationResolver.activation(
            for: cluster,
            coordinatesByID: coordinatesByID,
            visibleRegion: visibleRegion,
            viewportSize: viewportSize
        ) {
        case .zoom:
            if let targetRegion = ProfilePlaceCollectionMapZoomTarget.region(
                for: cluster,
                coordinatesByID: coordinatesByID,
                visibleRegion: visibleRegion,
                viewportSize: viewportSize
            ) {
                zoom(to: targetRegion)
            }
        case .open(let itemID):
            if let item = itemByID[itemID] {
                onSelect(item.visiblePlace)
            }
        case nil:
            break
        }
    }

    private func clusterAccessibilityLabel(
        _ cluster: ListMapCluster,
        itemByID: [String: ProfilePlaceCollectionMapItem],
        coordinatesByID: [String: ListMapCoordinate],
        viewportSize: CGSize
    ) -> String {
        clusterAccessibilityPresentation(
            for: cluster,
            itemByID: itemByID,
            coordinatesByID: coordinatesByID,
            viewportSize: viewportSize
        ).label
    }

    private func clusterAccessibilityHint(
        _ cluster: ListMapCluster,
        itemByID: [String: ProfilePlaceCollectionMapItem],
        coordinatesByID: [String: ListMapCoordinate],
        viewportSize: CGSize
    ) -> String {
        clusterAccessibilityPresentation(
            for: cluster,
            itemByID: itemByID,
            coordinatesByID: coordinatesByID,
            viewportSize: viewportSize
        ).hint
    }

    private func clusterAccessibilityPresentation(
        for cluster: ListMapCluster,
        itemByID: [String: ProfilePlaceCollectionMapItem],
        coordinatesByID: [String: ListMapCoordinate],
        viewportSize: CGSize
    ) -> ProfilePlaceCollectionMapClusterAccessibility {
        let activation = ProfilePlaceCollectionMapClusterActivationResolver.activation(
            for: cluster,
            coordinatesByID: coordinatesByID,
            visibleRegion: visibleRegion,
            viewportSize: viewportSize
        )
        let destinationName: String?
        if case .open(let itemID) = activation {
            destinationName = itemByID[itemID]?.visiblePlace.place.canonicalName
        } else {
            destinationName = nil
        }
        return ProfilePlaceCollectionMapClusterAccessibility.presentation(
            count: cluster.memberIDs.count,
            activation: activation,
            destinationName: destinationName
        )
    }
}

private struct ProfilePlaceCollectionMapMarker: View {
    let item: ProfilePlaceCollectionMapItem

    var body: some View {
        WanderCategoryEmoji(emoji: item.visiblePlace.categoryEmoji, size: 16)
            .frame(width: 38, height: 38)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(outlineLayer)
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .contentShape(Circle())
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: 6, x: 0, y: 2)
    }

    private var outlineLayer: some View {
        ForEach(Array(item.outlines.indices), id: \.self) { index in
            MapPinOutlineStroke(
                outline: item.outlines[index],
                lineWidth: item.outlines.count > 1 ? 2.5 : 3
            )
            .padding(item.outlines.count > 1 && index > 0 ? -5 : 0)
        }
    }
}

private struct ProfilePlaceCollectionClusterMarker: View {
    let count: Int
    let outlines: [MapPinOutline]

    var body: some View {
        Text("\(count)")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(WanderTheme.textInk.color)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: 38, height: 38)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(outlineLayer)
            .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            .contentShape(Circle())
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: 6, x: 0, y: 2)
    }

    private var outlineLayer: some View {
        ForEach(Array(outlines.indices), id: \.self) { index in
            MapPinOutlineStroke(
                outline: outlines[index],
                lineWidth: outlines.count > 1 ? 2.5 : 3
            )
            .padding(outlines.count > 1 && index > 0 ? -5 : 0)
        }
    }
}

private struct SavedPlacesListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let mode: SavedPlacesListMode
    let collection: ProfilePlaceCollectionRoute?
    let profileID: String
    @State private var query = ""
    @State private var selectedCategory: String?
    @State private var selectedMetadataTag: String?
    @State private var isTagFilterExpanded = false
    @State private var tagFilterQuery = ""
    @State private var selectedPlace: VisiblePlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?

    init(mode: SavedPlacesListMode, profileID: String) {
        self.mode = mode
        self.collection = nil
        self.profileID = profileID
    }

    init(collection: ProfilePlaceCollectionRoute, profileID: String) {
        self.mode = .been
        self.collection = collection
        self.profileID = profileID
    }

    private var places: [VisiblePlace] {
        modePlaces
            .filter(matchesCollection)
            .filter(matchesSelectedCategory)
            .filter(matchesSelectedMetadataTag)
            .filter(matchesQuery)
            .sorted { lhs, rhs in
                lhs.place.canonicalName.localizedCaseInsensitiveCompare(rhs.place.canonicalName) == .orderedAscending
            }
    }

    private var allModePlaces: [VisiblePlace] {
        modePlaces
            .filter(matchesCollection)
    }

    private var modePlaces: [VisiblePlace] {
        let base = mode == .inCommon
            ? store.placesInCommon(with: profileID)
            : store.visiblePlaces(for: profileID)
        if collection?.includesAllStatuses == true {
            return base
        }
        guard let status = mode.status else { return base }
        return base.filter { $0.userPlace.status == status }
    }

    private var categories: [String] {
        Array(Set(allModePlaces.map(\.effectiveCategory))).sorted()
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
        let filteredPlaces = places
        let overviewPlaces = allModePlaces
        let mapPresentation = collection?.source.presentsInteractiveMap == true
            ? ProfilePlaceCollectionMapProjection.presentation(
                for: filteredPlaces,
                currentUserID: store.currentUser.id
            )
            : nil
        let mapOverview = collection?.source.presentsInteractiveMap == true
            ? ProfilePlaceCollectionMapProjection.presentation(
                for: overviewPlaces,
                currentUserID: store.currentUser.id
            )
            : nil

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let mapPresentation, let mapOverview {
                    ProfilePlaceCollectionMap(
                        presentation: mapPresentation,
                        overviewRegion: mapOverview.fittedRegion,
                        overviewTotalCount: mapOverview.totalCount
                    ) { visiblePlace in
                        selectedPlace = visiblePlace
                    }
                }

                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    if let calendarDay = collection?.calendarDay {
                        ProfileCalendarDayDetailHeader(summary: calendarDay)
                    }
                    if collection?.calendarDay != nil {
                        calendarDayFilterControls
                    } else {
                        searchField
                        filterSection(title: "type", values: categories, selectedValue: $selectedCategory)
                        tagFilterDropdown
                    }

                    if filteredPlaces.isEmpty {
                        if collection?.calendarDay?.state == ProfileCalendarActivityState.none {
                            SmallEmptyRow(
                                title: "No activity this day",
                                subtitle: "check-ins will show up here"
                            )
                        } else if collection?.calendarDay != nil {
                            SmallEmptyRow(title: "No matching places", subtitle: "try another type or tag")
                        } else {
                            SmallEmptyRow(title: "No matching places", subtitle: "try clearing search or filters")
                        }
                    } else {
                        ForEach(filteredPlaces) { visiblePlace in
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
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if usesInlineNavigationHeader {
                inlineNavigationHeader
            }
        }
        .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
            selectedPlaceDestination
        }
        .sheet(item: $placeSaveFlow, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { context in
            MapPlaceSaveFlowSheet(context: context) { submission in
                await saveProfileFlowSubmission(submission)
            } onRemove: { context in
                await removeProfileSave(context)
            }
        }
        .wanderScreen()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(usesInlineNavigationHeader ? .hidden : .visible, for: .navigationBar)
    }

    private var navigationTitle: String {
        collection?.title ?? mode.title
    }

    private var usesInlineNavigationHeader: Bool {
        mode == .inCommon && collection == nil
    }

    private var inlineNavigationHeader: some View {
        ZStack {
            Text(navigationTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            HStack {
                ProfileBackButton(action: { dismiss() })
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: WanderTheme.tapMinimum)
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing1)
    }

    private func matchesCollection(_ visiblePlace: VisiblePlace) -> Bool {
        guard let collection else { return true }
        return ProfilePlaceCollectionMatcher.matches(
            visiblePlace,
            acceptedPlaceIDs: Set(collection.placeIDs)
        )
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: {
                selectedPlace != nil
            },
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
                action: .addVisit,
                onBack: {
                    self.selectedPlace = nil
                },
                onAction: {
                    beginAddVisitSelectedPlace(selectedPlace)
                }
            )
        }
    }

    private var calendarDayFilterControls: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            compactFilterDropdown(
                title: "type",
                systemImage: "square.grid.2x2.fill",
                allTitle: "all types",
                values: categories,
                selectedValue: $selectedCategory,
                displayTitle: { WanderPlaceCategory.broadCategory(for: $0) }
            )
            compactFilterDropdown(
                title: "tags",
                systemImage: "tag.fill",
                allTitle: "all tags",
                values: metadataTags,
                selectedValue: $selectedMetadataTag,
                displayTitle: { $0 }
            )
        }
    }

    private func compactFilterDropdown(
        title: String,
        systemImage: String,
        allTitle: String,
        values: [String],
        selectedValue: Binding<String?>,
        displayTitle: @escaping (String) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            Menu {
                Button {
                    selectedValue.wrappedValue = nil
                } label: {
                    if selectedValue.wrappedValue == nil {
                        Label(allTitle, systemImage: "checkmark")
                    } else {
                        Text(allTitle)
                    }
                }

                ForEach(values, id: \.self) { value in
                    Button {
                        selectedValue.wrappedValue = value
                    } label: {
                        if selectedValue.wrappedValue == value {
                            Label(displayTitle(value), systemImage: "checkmark")
                        } else {
                            Text(displayTitle(value))
                        }
                    }
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .black))
                    Text(selectedValue.wrappedValue.map(displayTitle) ?? allTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: WanderTheme.spacing1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(WanderTheme.textMuted.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title.capitalized) filter")
            .accessibilityValue(selectedValue.wrappedValue.map(displayTitle) ?? allTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("search \(navigationTitle.lowercased())", text: $query)
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
                            WanderChip(
                                title: title == "type" ? WanderPlaceCategory.broadCategory(for: value) : value,
                                isSelected: selectedValue.wrappedValue == value
                            )
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
        return visiblePlace.effectiveCategory == selectedCategory
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
            visiblePlace.effectiveCompactType,
            visiblePlace.effectiveCategoryDisplay.category,
            visiblePlace.effectiveCategoryDisplay.subcategory,
            visiblePlace.restaurantCuisine,
            visiblePlace.place.rawProviderType,
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
                PlaceSaveSummary(
                    visiblePlace: visiblePlace,
                    attributes: store.attributes(for: visiblePlace.userPlace.id),
                    viewerFollowsOwner: store.viewerFollows(visiblePlace.owner.id)
                )
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
            PlaceSaveSummary(
                visiblePlace: visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id),
                viewerFollowsOwner: false
            )
        }
    }

    private func beginAddVisitSelectedPlace(_ visiblePlace: VisiblePlace) {
        let context = MapPlaceSaveContext.existingCurrentUserSave(
            visiblePlace,
            attributes: store.attributes(for: visiblePlace.userPlace.id),
            latestVisit: store.visits(for: visiblePlace.userPlace.id).first
        )
        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            placeSaveFlow = context
        }
    }

    @MainActor
    private func saveProfileFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let visitBackend = auth.isSignedIn ? backend : nil
        switch submission.context.mode {
        case .sharedVisit:
            return nil
        case .add(let sourceType):
            let result = await store.saveCandidate(
                submission.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: sourceType,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        case .addVisit, .editVisit, .editWant:
            let (result, targetVisit) = await persistScopedVisitOrWantSubmission(
                submission,
                store: store,
                backend: auth.isSignedIn ? backend : nil
            )
            guard let result else { return nil }
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        }
    }

    @MainActor
    private func removeProfileSave(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            return await store.deleteVisit(visitID: visit.id, backend: auth.isSignedIn ? backend : nil)
        case .editWant(let visiblePlace):
            guard await store.removeSave(userPlaceID: visiblePlace.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil else {
                return false
            }
            selectedPlace = nil
            return true
        case .add, .addVisit, .sharedVisit:
            return false
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
    @State private var selectedProfile: GraphProfileSelection?
    @State private var pendingUnfollowProfile: LocalProfile?
    @State private var showsUnfollowConfirm = false

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
                    GraphPersonListRow(
                        profile: profile,
                        relationship: store.relationship(to: profile.id),
                        savedPlaceCount: store.visiblePlaces(for: profile.id).count,
                        onOpenProfile: {
                            selectedProfile = GraphProfileSelection(id: profile.id)
                        },
                        onFollowAction: {
                            handleFollowAction(for: profile)
                        }
                    )
                    .listRowBackground(WanderTheme.surfaceBone.color)
                }
            }
            .scrollContentBackground(.hidden)
            .wanderScreen()
            .navigationTitle(mode.rawValue.capitalized)
            .fullScreenCover(item: $selectedProfile) { selection in
                ProfileDetailView(profileID: selection.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .alert(pendingUnfollowTitle, isPresented: $showsUnfollowConfirm) {
                Button("Yes, unfollow", role: .destructive) {
                    confirmPendingUnfollow()
                }
                Button("No, cancel", role: .cancel) {
                    pendingUnfollowProfile = nil
                    showsUnfollowConfirm = false
                }
            }
            .task {
                await store.refreshRemoteSocialGraph(backend: backend)
            }
        }
    }

    private var pendingUnfollowTitle: String {
        guard let pendingUnfollowProfile else {
            return "Are you sure you want to unfollow this person"
        }
        return "Are you sure you want to unfollow \(pendingUnfollowProfile.displayName)"
    }

    private func handleFollowAction(for profile: LocalProfile) {
        auth.requireSignIn(for: .followPeople) {
            if store.relationship(to: profile.id) == .nonFollower {
                Task {
                    await store.follow(userID: profile.id, backend: backend)
                }
            } else {
                pendingUnfollowProfile = profile
                showsUnfollowConfirm = true
            }
        }
    }

    private func confirmPendingUnfollow() {
        guard let profile = pendingUnfollowProfile else { return }
        pendingUnfollowProfile = nil
        showsUnfollowConfirm = false

        auth.requireSignIn(for: .followPeople) {
            Task {
                await store.unfollow(userID: profile.id, backend: backend)
            }
        }
    }
}

private struct GraphProfileSelection: Identifiable {
    let id: String
}

private struct GraphPersonListRow: View {
    let profile: LocalProfile
    let relationship: ViewerRelationship
    let savedPlaceCount: Int
    let onOpenProfile: () -> Void
    let onFollowAction: () -> Void

    private var actionTitle: String {
        relationship == .nonFollower ? "follow" : "unfollow"
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: onOpenProfile) {
                HStack(spacing: WanderTheme.spacing3) {
                    WanderAvatar(
                        initials: profile.initials,
                        avatarURL: profile.avatarURL,
                        size: 40,
                        color: WanderTheme.pinSocial.color
                    )

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(profile.displayName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                        Text("@\(profile.handle) · \(relationship.displayTitle)")
                            .font(.system(size: 13))
                            .foregroundStyle(WanderTheme.textMuted.color)
                        Text(savedPlaceCountLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }

                    Spacer(minLength: WanderTheme.spacing2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(actionTitle, action: onFollowAction)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(actionTitle == "unfollow" ? WanderTheme.stateError.color : WanderTheme.terracotta.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 34)
                .background(
                    Capsule()
                        .fill(actionTitle == "unfollow" ? WanderTheme.surfaceRaised.color : WanderTheme.terracottaTint.color)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            actionTitle == "unfollow" ? WanderTheme.borderHairline.color : WanderTheme.terracotta.color.opacity(0.35),
                            lineWidth: 1
                        )
                )
        }
    }

    private var savedPlaceCountLabel: String {
        switch savedPlaceCount {
        case 0:
            return "no saved places yet"
        case 1:
            return "1 saved place"
        default:
            return "\(savedPlaceCount) saved places"
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
                WanderAvatar(
                    initials: profile.initials,
                    avatarURL: profile.avatarURL,
                    size: 40,
                    color: WanderTheme.pinSocial.color
                )

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
            WanderCategoryEmoji(emoji: visiblePlace.categoryEmoji, size: 17)
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

    private var subtitle: String {
        let locality = visiblePlace.place.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let locality, !locality.isEmpty else {
            return visiblePlace.userPlace.status.displayTitle
        }
        return "\(locality) · \(visiblePlace.userPlace.status.displayTitle)"
    }
}

private struct ProfileCalendarDayDetailHeader: View {
    let summary: ProfileCalendarDaySummary

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            metric(value: summary.visitCount, singular: CheckInCopy.noun, plural: CheckInCopy.pluralNoun, color: WanderTheme.terracotta.color)
            Divider()
                .overlay(WanderTheme.borderHairline.color)
            metric(value: summary.placeIDs.count, singular: "place", plural: "places", color: WanderTheme.textInk.color)
        }
        .frame(maxWidth: .infinity)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(WanderTheme.borderHairline.color))
        .accessibilityElement(children: .combine)
    }

    private func metric(
        value: Int,
        singular: String,
        plural: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(color)
            Text(value == 1 ? singular : plural)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
