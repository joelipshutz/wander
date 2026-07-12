import SwiftUI

@MainActor
struct WanderRootView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var selectedTab: WanderTab
    @State private var addTabResetToken = UUID()
    @State private var isPresentingAdd = false
    @State private var initialPresentation: WanderInitialPresentation?
    @StateObject private var store: WanderStore
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
        _initialPresentation = State(initialValue: initialPresentation ?? Self.resolvedInitialPresentation())
        let persistence: WanderStorePersistence? = fixtureMode == .empty ? .live : nil
        _store = StateObject(
            wrappedValue: WanderStore(
                fixtures: Self.resolvedFixtures(mode: fixtureMode),
                parser: parser,
                analytics: analytics,
                persistence: persistence
            )
        )
    }

    var body: some View {
        TabView(selection: tabSelection) {
            MapScreen()
                .tabItem { Label(WanderTab.map.title, systemImage: WanderTab.map.systemImage) }
                .tag(WanderTab.map)

            DiscoverScreen()
                .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                .tag(WanderTab.discover)

            Color.clear
                .tabItem { Label(WanderTab.add.title, systemImage: WanderTab.add.systemImage) }
                .tag(WanderTab.add)

            ListsScreen()
                .tabItem { Label(WanderTab.lists.title, systemImage: WanderTab.lists.systemImage) }
                .tag(WanderTab.lists)

            ProfileScreen()
                .tabItem { Label(WanderTab.profile.title, systemImage: WanderTab.profile.systemImage) }
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
        .environmentObject(store)
        .sheet(isPresented: $isPresentingAdd, onDismiss: {
            addTabResetToken = UUID()
        }) {
            AddScreen(resetToken: addTabResetToken)
                .environmentObject(store)
                .environmentObject(auth)
                .environmentObject(backend)
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
        .task {
            await pushNotifications.refreshAuthorizationStatus()
            await auth.refreshSession()
            applyAuthStateIfNeeded(auth.state)
            if let pendingUserInfo = WanderAppDelegate.takePendingNotificationUserInfo() {
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
    }

    private var tabSelection: Binding<WanderTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == .add {
                addTabResetToken = UUID()
                isPresentingAdd = true
            } else {
                selectedTab = newTab
            }
        }
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
        case .place: .map
        case .discover: .discover
        }
    }

    private func applyAuthStateIfNeeded(_ state: AuthState) {
        guard fixtureMode == .empty else {
            #if DEBUG
            WanderDebugLog.sync.debug("auth apply skipped fixture_mode=\(String(describing: fixtureMode), privacy: .public)")
            #endif
            return
        }
        store.apply(authState: state)

        if state.isSignedIn {
            Task {
                #if DEBUG
                if case .signedIn(let session) = state {
                    WanderDebugLog.sync.debug("signed-in backfill trigger user=\(WanderDebugLog.shortID(session.userID), privacy: .public) remote=\(backend.canUseRemoteData, privacy: .public)")
                } else {
                    WanderDebugLog.sync.debug("signed-in backfill trigger remote=\(backend.canUseRemoteData, privacy: .public)")
                }
                #endif
                await store.refreshRemoteCurrentProfile(backend: backend)
                let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
                await pushNotifications.registerStoredDeviceTokenIfPossible(backend: backend, authState: state)
                let syncedListCount = await store.syncPendingPlaceLists(backend: backend)
                await store.refreshRemotePlaceLists(backend: backend)
                #if DEBUG
                WanderDebugLog.sync.debug("signed-in backfill finished synced_count=\(syncedCount, privacy: .public) list_synced_count=\(syncedListCount, privacy: .public)")
                #endif
            }
        } else {
            #if DEBUG
            WanderDebugLog.sync.debug("auth state applied without backfill state=\(state.debugSummary, privacy: .public)")
            #endif
        }
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

    static func resolvedFixtureMode(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtureMode {
        arguments.contains("-WanderUseDemoFixtures") ? .demo : .empty
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
        }
    }
}

enum WanderFixtureMode: Equatable {
    case empty
    case demo
}

enum WanderInitialPresentation: String, Identifiable {
    case settings

    var id: String { rawValue }
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
        case .discover: "Discover"
        case .add: "Add"
        case .lists: "Lists"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .discover: "sparkle.magnifyingglass"
        case .add: "plus"
        case .lists: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }
}
