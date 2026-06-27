import SwiftUI

@MainActor
struct WanderRootView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedTab: WanderTab
    @State private var addTabResetToken = UUID()
    @State private var isPresentingAdd = false
    @State private var initialPresentation: WanderInitialPresentation?
    @StateObject private var store: WanderStore
    private let fixtureMode: WanderFixtureMode

    init(
        initialTab: WanderTab? = nil,
        initialPresentation: WanderInitialPresentation? = nil,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        let fixtureMode = Self.resolvedFixtureMode()
        self.fixtureMode = fixtureMode
        _selectedTab = State(initialValue: initialTab ?? Self.resolvedInitialTab())
        _initialPresentation = State(initialValue: initialPresentation ?? Self.resolvedInitialPresentation())
        let persistence: WanderStorePersistence? = fixtureMode == .empty ? .live : nil
        _store = StateObject(
            wrappedValue: WanderStore(
                fixtures: Self.resolvedFixtures(mode: fixtureMode),
                analytics: analytics,
                persistence: persistence
            )
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                MapScreen()
                    .tabItem { Label(WanderTab.map.title, systemImage: WanderTab.map.systemImage) }
                    .tag(WanderTab.map)

                DiscoverScreen()
                    .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                    .tag(WanderTab.discover)

                ListsScreen()
                    .tabItem { Label(WanderTab.lists.title, systemImage: WanderTab.lists.systemImage) }
                    .tag(WanderTab.lists)

                ProfileScreen()
                    .tabItem { Label(WanderTab.profile.title, systemImage: WanderTab.profile.systemImage) }
                    .tag(WanderTab.profile)
            }

            Button {
                addTabResetToken = UUID()
                isPresentingAdd = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .black))
                    .frame(width: 58, height: 58)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
                    .shadow(color: WanderTheme.terracotta.color.opacity(0.20), radius: 14, x: 0, y: 7)
                    .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 7, x: 0, y: 3)
                    .overlay(Circle().stroke(WanderTheme.surfaceBone.color, lineWidth: 4))
            }
            .accessibilityLabel("Add a place")
            .padding(.bottom, WanderTheme.spacing3)
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
    case discover
    case lists
    case profile

    var title: String {
        switch self {
        case .map: "Map"
        case .discover: "Discover"
        case .lists: "Lists"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .discover: "sparkle.magnifyingglass"
        case .lists: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }
}
