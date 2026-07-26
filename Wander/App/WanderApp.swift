import SwiftUI
import SwiftData

@main
struct WanderApp: App {
    @UIApplicationDelegateAdaptor(WanderAppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var pushNotifications = PushNotificationManager()
    private let analytics: AnalyticsClient
    private let discoverParser: any LLMFilterParser

    init() {
        let configuration = WanderBackendConfiguration.current()
        analytics = PostHogAnalyticsClient(configuration: .current()) ?? NoopAnalyticsClient()
        let authStore = AuthSessionStore(provider: ClerkAuthService(configuration: configuration))
        discoverParser = Self.makeDiscoverParser(configuration: configuration, authStore: authStore)
        _auth = StateObject(wrappedValue: authStore)
        _backend = StateObject(wrappedValue: WanderBackend(configuration: configuration, authSession: authStore))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let streakMockupPage = SaveStreakMockupPage.resolved() {
                SaveStreakMockupRoot(page: streakMockupPage)
            } else if let futureDateMockupPage = FutureDateSaveMockupPage.resolved() {
                FutureDateSaveMockupRoot(page: futureDateMockupPage)
            } else if let profileMockupPage = ProfileRedesignMockupPage.resolved() {
                ProfileRedesignMockupRoot(page: profileMockupPage)
            } else if let carouselMockupPage = PlacePhotoCarouselMockupPage.resolved() {
                PlacePhotoCarouselMockupRoot(page: carouselMockupPage)
            } else if let activityMockupPage = PlaceActivityMockupPage.resolved() {
                PlaceActivityMockupRoot(page: activityMockupPage)
            } else if PlaceImportCandidateMockupPage.isPresented {
                PlaceImportCandidateMockupRoot()
                    .environmentObject(auth)
                    .environmentObject(backend)
            } else if let mockupPage = CategoryTaxonomyMockupPage.resolved() {
                CategoryTaxonomyMockupRoot(page: mockupPage)
            } else {
                appRoot
            }
            #else
            appRoot
            #endif
        }
    }

    private var appRoot: some View {
        WanderAppEntryView(analytics: analytics, parser: discoverParser)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(pushNotifications)
            .modelContainer(WanderModelContainer.preview)
    }

    private static func makeDiscoverParser(
        configuration: WanderBackendConfiguration,
        authStore: AuthSessionStore
    ) -> any LLMFilterParser {
        guard configuration.isSupabaseConfigured else {
            return DeterministicFilterParser()
        }

        let client = WanderSupabaseClient(configuration: configuration, authSession: authStore)
        return RemoteDiscoverFilterParser(
            repository: SupabaseDiscoverFilterRepository(functions: client)
        )
    }
}

enum WanderAppSessionDestination: Equatable {
    case loading
    case signIn
    case authenticated
    case unavailable(String)
}

@MainActor
struct WanderAppEntryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var auth: AuthSessionStore
    private let analytics: AnalyticsClient
    private let parser: any LLMFilterParser
    @State private var hasResolvedSession = false

    init(analytics: AnalyticsClient, parser: any LLMFilterParser) {
        self.analytics = analytics
        self.parser = parser
    }

    var body: some View {
        Group {
            switch Self.destination(for: auth.state, hasResolvedSession: hasResolvedSession) {
            case .loading:
                sessionLoadingView
            case .signIn:
                ClerkNativeAuthView(isDismissable: false)
            case .authenticated:
                WanderRootView(analytics: analytics, parser: parser)
            case .unavailable(let message):
                authUnavailableView(message: message)
            }
        }
        .task {
            await resolveSession()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            hasResolvedSession = false
            Task {
                await resolveSession()
            }
        }
    }

    static func destination(
        for state: AuthState,
        hasResolvedSession: Bool
    ) -> WanderAppSessionDestination {
        guard hasResolvedSession else { return .loading }
        switch state {
        case .loading:
            return .loading
        case .signedOut:
            return .signIn
        case .signedIn:
            return .authenticated
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    private var sessionLoadingView: some View {
        VStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text("Checking your session…")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private func authUnavailableView(message: String) -> some View {
        VStack(spacing: WanderTheme.spacing4) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(WanderTheme.terracotta.color)
            VStack(spacing: WanderTheme.spacing2) {
                Text("Sign in is unavailable")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
            }
            WanderPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                hasResolvedSession = false
                Task {
                    await resolveSession()
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private func resolveSession() async {
        await auth.refreshSession()
        hasResolvedSession = true
    }
}
