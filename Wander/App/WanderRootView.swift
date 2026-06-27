import SwiftUI

@MainActor
struct WanderRootView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedTab: WanderTab
    @State private var addTabResetToken = UUID()
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
        _selectedTab = State(initialValue: initialTab ?? Self.resolvedInitialTab())
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
        TabView(selection: $selectedTab) {
            MapScreen()
                .tabItem { Label(WanderTab.map.title, systemImage: WanderTab.map.systemImage) }
                .tag(WanderTab.map)

            AddScreen(resetToken: addTabResetToken)
                .tabItem { Label(WanderTab.add.title, systemImage: WanderTab.add.systemImage) }
                .tag(WanderTab.add)

            DiscoverScreen()
                .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                .tag(WanderTab.discover)

            ProfileScreen()
                .tabItem { Label(WanderTab.profile.title, systemImage: WanderTab.profile.systemImage) }
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
        .environmentObject(store)
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
            }
        }
        .task {
            await auth.refreshSession()
            applyAuthStateIfNeeded(auth.state)
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
        .onChange(of: selectedTab) { oldValue, newValue in
            if oldValue == .add, newValue != .add {
                addTabResetToken = UUID()
            }
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
                let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
                #if DEBUG
                WanderDebugLog.sync.debug("signed-in backfill finished synced_count=\(syncedCount, privacy: .public)")
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

        return WanderTab(rawValue: arguments[valueIndex]) ?? .map
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
    case add
    case discover
    case profile

    var title: String {
        switch self {
        case .map: "Map"
        case .add: "Add"
        case .discover: "Discover"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .add: "plus.circle.fill"
        case .discover: "sparkle.magnifyingglass"
        case .profile: "person.crop.circle"
        }
    }
}
