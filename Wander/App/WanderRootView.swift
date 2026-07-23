import SwiftUI

@MainActor
struct WanderRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var selectedTab: WanderTab
    @State private var addTabResetToken = UUID()
    @State private var isPresentingAdd = false
    @State private var addSheetDetent: PresentationDetent
    @State private var initialPresentation: WanderInitialPresentation?
    @State private var sharedProfile: SharedProfileRoute?
    @State private var signedInMaintenanceTask: Task<Void, Never>?
    @State private var signedInMaintenanceRunID: UUID?
    @State private var signedInMaintenanceUserID: String?
    @State private var sharedVisitBannerInvitation: SharedVisitInvitation?
    @State private var sharedVisitBannerTracker = SharedVisitBannerTracker()
    @State private var sharedVisitBannerTask: Task<Void, Never>?
    @State private var visitInvitationInboxRequestID: UUID?
    @State private var presentedSaveStreakCelebration: SaveStreakCelebration?
    @State private var saveStreakCelebrationTask: Task<Void, Never>?
    @StateObject private var store: WanderStore
    @StateObject private var importStore: PlaceImportStore
    private let fixtureMode: WanderFixtureMode

    init(
        initialTab: WanderTab? = nil,
        initialPresentation: WanderInitialPresentation? = nil,
        analytics: AnalyticsClient = NoopAnalyticsClient(),
        parser: any LLMFilterParser = DeterministicFilterParser()
    ) {
        let fixtureMode = Self.resolvedFixtureMode()
        self.fixtureMode = fixtureMode
        let requestedTab = initialTab ?? Self.resolvedInitialTab()
        _selectedTab = State(initialValue: requestedTab == .add ? .map : requestedTab)
        _isPresentingAdd = State(initialValue: Self.resolvedInitialAddPresentation())
        _initialPresentation = State(initialValue: initialPresentation ?? Self.resolvedInitialPresentation())
        _sharedProfile = State(initialValue: Self.resolvedInitialSharedProfile())
        let persistence: WanderStorePersistence? = fixtureMode == .empty ? .live : nil
        _store = StateObject(
            wrappedValue: Self.makeStore(
                fixtureMode: fixtureMode,
                parser: parser,
                analytics: analytics,
                persistence: persistence
            )
        )
        let importStore = PlaceImportStore()
        _importStore = StateObject(wrappedValue: importStore)
        _addSheetDetent = State(
            initialValue: AddSheetLayout.restingDetent(
                hasPendingImports: importStore.summary.hasPendingImports
            )
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            MapScreen()
                .tabItem { Label(WanderTab.map.title, systemImage: WanderTab.map.systemImage) }
                .tag(WanderTab.map)

            FeedScreen()
                .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                .tag(WanderTab.discover)

            Color.clear
                .tabItem { Label(WanderTab.add.title, systemImage: WanderTab.add.systemImage) }
                .tag(WanderTab.add)

            ListsScreen()
                .tabItem { Label(WanderTab.lists.title, systemImage: WanderTab.lists.systemImage) }
                .tag(WanderTab.lists)

            ProfileScreen(visitInvitationInboxRequestID: $visitInvitationInboxRequestID) {
                selectedTab = .discover
            }
                .tabItem { Label(WanderTab.profile.title, systemImage: WanderTab.profile.systemImage) }
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
        .environmentObject(store)
        .overlay {
            GeometryReader { proxy in
                if let invitation = sharedVisitBannerInvitation {
                    SharedVisitNotificationBanner(invitation: invitation) {
                        openSharedVisitFromBanner(invitation)
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.top, proxy.safeAreaInsets.top + WanderTheme.spacing2)
                    .transition(
                        accessibilityReduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .zIndex(10)
                }
            }
        }
        .overlay {
            if let celebration = presentedSaveStreakCelebration {
                Group {
                    switch celebration.kind {
                    case .dailyTakeover:
                        SaveStreakCelebrationView(celebration: celebration) {
                            dismissSaveStreakCelebration(celebration)
                        }
                    case .sameDayConfetti:
                        SaveStreakConfettiPopView()
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .sheet(isPresented: $isPresentingAdd, onDismiss: {
            store.saveFlowDidDismiss(.addSheet)
            addTabResetToken = UUID()
            addSheetDetent = addSheetRestingDetent
        }) {
            AddScreen(
                importStore: importStore,
                resetToken: addTabResetToken,
                selectedDetent: $addSheetDetent
            ) {
                isPresentingAdd = false
            }
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
                .presentationDetents(
                    AddSheetLayout.detents(
                        hasPendingImports: importStore.summary.hasPendingImports
                    ),
                    selection: $addSheetDetent
                )
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
                .presentationBackground(WanderTheme.surfaceBone.color)
                .presentationContentInteraction(.resizes)
        }
        .sheet(item: $auth.activeGate) { request in
            AuthGateSheet(request: request)
                .environmentObject(auth)
                .presentationDetents([.medium])
                .presentationBackground(WanderTheme.canvasWarm.color)
        }
        .sheet(isPresented: $auth.isPresentingNativeAuth) {
            ClerkNativeAuthView()
                .environmentObject(auth)
        }
        .sheet(item: $initialPresentation) { presentation in
            switch presentation {
            case .settings:
                SettingsScreen()
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .environmentObject(pushNotifications)
            }
        }
        .fullScreenCover(item: $sharedProfile) { route in
            ProfileDetailView(profileID: route.profileID)
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
        }
        .onAppear {
            seedSharedVisitBannerTracker()
            queueSaveStreakCelebration(store.saveStreakCelebration)
            importStore.resumePendingImports()
            reconcilePlaceImports()
        }
        .task {
            await pushNotifications.refreshAuthorizationStatus()
            await auth.refreshSession()
            applyAuthStateIfNeeded(auth.state)
            while let pendingUserInfo = WanderAppDelegate.takePendingNotificationUserInfo() {
                pushNotifications.handleNotificationResponse(userInfo: pendingUserInfo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didRegisterForRemoteNotifications)) { notification in
            guard let deviceToken = notification.userInfo?[WanderAppDelegate.deviceTokenKey] as? Data else { return }
            Task {
                await pushNotifications.handleRegisteredDeviceToken(deviceToken, backend: backend, authState: auth.state)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didFailToRegisterForRemoteNotifications)) { notification in
            guard let error = notification.userInfo?[WanderAppDelegate.errorKey] as? Error else { return }
            pushNotifications.handleRegistrationFailure(error)
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveNotificationResponse)) { notification in
            guard let userInfo = WanderAppDelegate.takePendingNotificationUserInfo()
                ?? notification.userInfo?[WanderAppDelegate.userInfoKey] as? [AnyHashable: Any]
            else { return }
            pushNotifications.handleNotificationResponse(userInfo: userInfo)
            scheduleSignedInMaintenance(for: auth.state)
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveRemoteNotification)) { _ in
            scheduleSignedInMaintenance(for: auth.state)
        }
        .onChange(of: pushNotifications.navigationRequest) { _, request in
            guard let request else { return }
            routeNotification(request)
        }
        .onChange(of: auth.isPresentingNativeAuth) { _, isPresenting in
            guard !isPresenting else { return }
            Task {
                await auth.refreshSession()
                applyAuthStateIfNeeded(auth.state)
            }
        }
        .onChange(of: auth.state) { _, state in
            applyAuthStateIfNeeded(state)
        }
        .onChange(of: store.sharedVisitInvitations) { _, invitations in
            presentSharedVisitBannerIfNeeded(from: invitations)
        }
        .onChange(of: store.saveStreakCelebration) { _, celebration in
            queueSaveStreakCelebration(celebration)
        }
        .onChange(of: store.presentationRevision) { _, _ in
            reconcilePlaceImports()
        }
        .onChange(of: importStore.items) { _, _ in
            reconcilePlaceImports()
        }
        .onChange(of: importStore.summary.hasPendingImports) { _, _ in
            guard addSheetDetent != .large else { return }
            addSheetDetent = addSheetRestingDetent
        }
        .onChange(of: store.isSaveFlowPresented) { _, isPresented in
            if isPresented {
                saveStreakCelebrationTask?.cancel()
            } else {
                queueSaveStreakCelebration(store.saveStreakCelebration)
            }
        }
        .onOpenURL { url in
            if let route = Self.sharedProfileRoute(for: url) {
                sharedProfile = route
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            scheduleSignedInMaintenance(for: auth.state)
        }
        .onDisappear {
            sharedVisitBannerTask?.cancel()
            saveStreakCelebrationTask?.cancel()
        }
    }

    private var tabSelection: Binding<WanderTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == .add {
                store.saveFlowDidPresent(.addSheet)
                addTabResetToken = UUID()
                addSheetDetent = addSheetRestingDetent
                isPresentingAdd = true
            } else {
                selectedTab = newTab
            }
        }
    }

    private var addSheetRestingDetent: PresentationDetent {
        AddSheetLayout.restingDetent(
            hasPendingImports: importStore.summary.hasPendingImports
        )
    }

    private func reconcilePlaceImports() {
        importStore.reconcileDuplicates(
            with: store.currentUserVisiblePlaces.map { visiblePlace in
                PlaceImportExistingPlace(
                    userPlaceID: visiblePlace.userPlace.id,
                    name: visiblePlace.place.canonicalName,
                    latitude: visiblePlace.place.latitude,
                    longitude: visiblePlace.place.longitude,
                    sourceProvider: visiblePlace.place.sourceProvider,
                    sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID
                )
            }
        )
    }

    private func routeNotification(_ request: NotificationNavigationRequest) {
        isPresentingAdd = false
        initialPresentation = nil

        selectedTab = Self.notificationTab(for: request.destination)
        if request.destination == .discover {
            pushNotifications.consumeNavigationRequest(id: request.id)
        }
    }

    static func notificationTab(for destination: NotificationDestination) -> WanderTab {
        switch destination {
        case .people, .drafts: .profile
        case .list: .lists
        case .place, .sharedVisit: .map
        case .discover: .discover
        }
    }

    static let sharedVisitBannerDestinationTab: WanderTab = .profile

    static func sharedProfileRoute(for url: URL) -> SharedProfileRoute? {
        guard url.scheme?.lowercased() == "recme", url.host?.lowercased() == "profiles" else {
            return nil
        }
        guard let profileID = url.pathComponents.dropFirst().first?.removingPercentEncoding,
              !profileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return SharedProfileRoute(profileID: profileID)
    }

    private func applyAuthStateIfNeeded(_ state: AuthState) {
        guard fixtureMode == .empty else {
            #if DEBUG
            WanderDebugLog.sync.debug("auth apply skipped fixture_mode=\(String(describing: fixtureMode), privacy: .public)")
            #endif
            return
        }
        store.apply(authState: state)
        resetSharedVisitBannerTracking()

        if case .signedIn(let session) = state {
            if let maintenanceUserID = signedInMaintenanceUserID,
               maintenanceUserID != session.userID {
                cancelSignedInMaintenance()
            }
            scheduleSignedInMaintenance(for: state)
        } else {
            cancelSignedInMaintenance()
            #if DEBUG
            WanderDebugLog.sync.debug("auth state applied without backfill state=\(state.debugSummary, privacy: .public)")
            #endif
        }
    }

    private func seedSharedVisitBannerTracker() {
        sharedVisitBannerTracker.seed(
            invitationKeys: store.sharedVisitInvitations.map(SharedVisitBannerTracker.key)
        )
    }

    private func resetSharedVisitBannerTracking() {
        sharedVisitBannerTask?.cancel()
        sharedVisitBannerTask = nil
        sharedVisitBannerInvitation = nil
        seedSharedVisitBannerTracker()
    }

    private func presentSharedVisitBannerIfNeeded(from invitations: [SharedVisitInvitation]) {
        let keys = invitations.map(SharedVisitBannerTracker.key)
        guard let nextKey = sharedVisitBannerTracker.nextUnseenKey(in: keys),
              let invitation = invitations.first(where: { SharedVisitBannerTracker.key(for: $0) == nextKey })
        else { return }

        sharedVisitBannerTask?.cancel()
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
            sharedVisitBannerInvitation = invitation
        }

        sharedVisitBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  sharedVisitBannerInvitation.map(SharedVisitBannerTracker.key) == nextKey
            else { return }
            dismissSharedVisitBanner()
        }
    }

    private func openSharedVisitFromBanner(_ invitation: SharedVisitInvitation) {
        dismissSharedVisitBanner()
        selectedTab = Self.sharedVisitBannerDestinationTab
        visitInvitationInboxRequestID = UUID()
    }

    private func dismissSharedVisitBanner() {
        sharedVisitBannerTask?.cancel()
        sharedVisitBannerTask = nil
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) {
            sharedVisitBannerInvitation = nil
        }
    }

    private func queueSaveStreakCelebration(_ celebration: SaveStreakCelebration?) {
        saveStreakCelebrationTask?.cancel()

        guard let celebration else {
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
                presentedSaveStreakCelebration = nil
            }
            return
        }

        guard SaveStreakPresentationPolicy.canPresent(
            celebration: celebration,
            isSaveFlowPresented: store.isSaveFlowPresented
        ) else {
            return
        }

        saveStreakCelebrationTask = Task { @MainActor in
            do {
                try await Task.sleep(for: SaveStreakPresentationPolicy.postSaveSheetDelay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  !store.isSaveFlowPresented,
                  store.saveStreakCelebration?.id == celebration.id
            else {
                return
            }

            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) {
                presentedSaveStreakCelebration = celebration
            }

            guard let autoDismissDelay = SaveStreakPresentationPolicy.autoDismissDelay(
                for: celebration.kind
            ) else {
                return
            }

            do {
                try await Task.sleep(for: autoDismissDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            dismissSaveStreakCelebration(celebration)
        }
    }

    private func dismissSaveStreakCelebration(_ celebration: SaveStreakCelebration) {
        saveStreakCelebrationTask?.cancel()
        saveStreakCelebrationTask = nil
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
            presentedSaveStreakCelebration = nil
        }
        store.dismissSaveStreakCelebration(id: celebration.id)
    }

    private func scheduleSignedInMaintenance(for state: AuthState) {
        guard fixtureMode == .empty,
              case .signedIn(let session) = state,
              signedInMaintenanceTask == nil
        else { return }

        let runID = UUID()
        signedInMaintenanceRunID = runID
        signedInMaintenanceUserID = session.userID
        signedInMaintenanceTask = Task { @MainActor in
            #if DEBUG
            if case .signedIn(let session) = state {
                WanderDebugLog.sync.debug("signed-in maintenance started user=\(WanderDebugLog.shortID(session.userID), privacy: .public) remote=\(backend.canUseRemoteData, privacy: .public)")
            }
            #endif
            await store.refreshRemoteCurrentProfile(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            await pushNotifications.registerStoredDeviceTokenIfPossible(backend: backend, authState: state)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let syncedListCount = await store.syncPendingPlaceLists(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            await store.refreshRemotePlaceLists(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let uploadedPhotoCount = await store.retryPendingVisitPhotoUploads(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let sentInviteCount = await store.retryPendingSharedVisitInvites(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            await store.refreshSharedVisitInbox(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let enrichedPlaceCount = await store.refreshOwnPlaceProviderCategories(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let enrichmentSyncCount = enrichedPlaceCount > 0
                ? await store.syncUnsyncedOwnPlaces(backend: backend)
                : 0
            #if DEBUG
            WanderDebugLog.sync.debug("signed-in maintenance finished synced_count=\(syncedCount, privacy: .public) list_synced_count=\(syncedListCount, privacy: .public) photo_count=\(uploadedPhotoCount, privacy: .public) invite_count=\(sentInviteCount, privacy: .public) enriched_place_count=\(enrichedPlaceCount, privacy: .public) enrichment_sync_count=\(enrichmentSyncCount, privacy: .public)")
            #endif
            finishSignedInMaintenance(runID: runID)
        }
    }

    private func shouldContinueSignedInMaintenance(runID: UUID, state: AuthState) -> Bool {
        !Task.isCancelled
            && signedInMaintenanceRunID == runID
            && auth.state == state
    }

    private func cancelSignedInMaintenance() {
        signedInMaintenanceRunID = nil
        signedInMaintenanceUserID = nil
        signedInMaintenanceTask?.cancel()
        signedInMaintenanceTask = nil
    }

    private func finishSignedInMaintenance(runID: UUID) {
        guard signedInMaintenanceRunID == runID else { return }
        signedInMaintenanceRunID = nil
        signedInMaintenanceUserID = nil
        signedInMaintenanceTask = nil
    }

    static func resolvedInitialTab(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderTab {
        guard let flagIndex = arguments.firstIndex(of: "-WanderInitialTab") else {
            return .map
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .map
        }

        let tab = WanderTab(rawValue: arguments[valueIndex]) ?? .map
        return tab == .add ? .map : tab
    }

    static func resolvedInitialPresentation(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderInitialPresentation? {
        arguments.contains("-WanderOpenSettings") ? .settings : nil
    }

    static func resolvedInitialAddPresentation(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-WanderOpenAdd")
    }

    static func resolvedInitialSharedProfile(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SharedProfileRoute? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderOpenProfile") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let profileID = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return profileID.isEmpty ? nil : SharedProfileRoute(profileID: profileID)
    }

    static func resolvedFixtureMode(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtureMode {
        if arguments.contains("-WanderUsePerformanceFixtures") {
            return .performance
        }
        return arguments.contains("-WanderUseDemoFixtures") ? .demo : .empty
    }

    static func resolvedFixtures(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtures {
        resolvedFixtures(mode: resolvedFixtureMode(from: arguments))
    }

    static func resolvedFixtures(mode: WanderFixtureMode) -> WanderFixtures {
        switch mode {
        case .empty:
            WanderFixtures.empty()
        case .demo:
            WanderFixtures.seed()
        case .performance:
            WanderFixtures.performanceScale()
        }
    }

    private static func makeStore(
        fixtureMode: WanderFixtureMode,
        parser: any LLMFilterParser,
        analytics: AnalyticsClient,
        persistence: WanderStorePersistence?
    ) -> WanderStore {
        let fixturesStartedAt = CFAbsoluteTimeGetCurrent()
        let fixtures = resolvedFixtures(mode: fixtureMode)
        let fixturesFinishedAt = CFAbsoluteTimeGetCurrent()
        let store = WanderStore(
            fixtures: fixtures,
            parser: parser,
            analytics: analytics,
            persistence: persistence
        )
        let storeFinishedAt = CFAbsoluteTimeGetCurrent()
        WanderDebugLog.performance.notice(
            "root initialization fixture_mode=\(String(describing: fixtureMode), privacy: .public) fixture_ms=\((fixturesFinishedAt - fixturesStartedAt) * 1_000, privacy: .public) store_ms=\((storeFinishedAt - fixturesFinishedAt) * 1_000, privacy: .public)"
        )
        return store
    }
}

enum WanderFixtureMode: Equatable {
    case empty
    case demo
    case performance
}

enum WanderInitialPresentation: String, Identifiable {
    case settings

    var id: String { rawValue }
}

struct SharedProfileRoute: Equatable, Identifiable {
    let profileID: String
    var id: String { profileID }
}

enum WanderTab: String, CaseIterable, Hashable {
    case map
    case discover
    case add
    case lists
    case profile

    var title: String {
        switch self {
        case .map: "Map"
        case .discover: "Feed"
        case .add: "Add"
        case .lists: "Lists"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .discover: "newspaper"
        case .add: "plus"
        case .lists: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }
}
