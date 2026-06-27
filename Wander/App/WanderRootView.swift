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
        TabView(selection: $selectedTab) {
            MapScreen()
                .tag(WanderTab.map)

            DiscoverScreen()
                .tag(WanderTab.discover)

            ListsScreen()
                .tag(WanderTab.lists)

            ProfileScreen()
                .tag(WanderTab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            WanderBottomTray(selectedTab: $selectedTab) {
                addTabResetToken = UUID()
                isPresentingAdd = true
            }
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.top, WanderTheme.spacing2)
            .padding(.bottom, WanderTheme.spacing2)
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

private struct WanderBottomTray: View {
    @Binding var selectedTab: WanderTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            trayButton(.map)
            trayButton(.discover)
            addButton
            trayButton(.lists)
            trayButton(.profile)
        }
        .padding(5)
        .frame(minHeight: 72)
        .background(WanderTheme.surfaceRaised.color.opacity(0.96))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(WanderTheme.borderHairline.color.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: WanderTheme.textInk.color.opacity(0.12), radius: 22, x: 0, y: 10)
    }

    private func trayButton(_ tab: WanderTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 23, weight: .black))
                Text(tab.title)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .foregroundStyle(selectedTab == tab ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
            .background(selectedTab == tab ? WanderTheme.surfaceSand.color : Color.clear)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var addButton: some View {
        Button(action: onAdd) {
            VStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 23, weight: .black))
                    .frame(width: 42, height: 42)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
                Text("Add")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a place")
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
