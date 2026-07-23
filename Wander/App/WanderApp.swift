import SwiftUI
import SwiftData

@main
struct WanderApp: App {
    @UIApplicationDelegateAdaptor(WanderAppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    @StateObject private var entryCoordinator: AppEntryCoordinator
    @StateObject private var pushNotifications = PushNotificationManager()
    private let analytics: AnalyticsClient
    private let discoverParser: any LLMFilterParser

    init() {
        let configuration = WanderBackendConfiguration.current()
        let analyticsClient: AnalyticsClient
        if let postHog = PostHogAnalyticsClient(configuration: .current()) {
            analyticsClient = postHog
        } else {
            analyticsClient = NoopAnalyticsClient()
        }
        analytics = analyticsClient
        let authStore = AuthSessionStore(provider: ClerkAuthService(configuration: configuration))
        let backendStore = WanderBackend(configuration: configuration, authSession: authStore)
        discoverParser = Self.makeDiscoverParser(configuration: configuration, authStore: authStore)
        _auth = StateObject(wrappedValue: authStore)
        _backend = StateObject(wrappedValue: backendStore)
        _entryCoordinator = StateObject(
            wrappedValue: AppEntryCoordinator(
                auth: authStore,
                backend: backendStore,
                analytics: analyticsClient
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let streakMockupPage = SaveStreakMockupPage.resolved() {
                SaveStreakMockupRoot(page: streakMockupPage)
            } else if let futureDateMockupPage = FutureDateSaveMockupPage.resolved() {
                FutureDateSaveMockupRoot(page: futureDateMockupPage)
            } else if ProcessInfo.processInfo.arguments.contains("-WanderOnboardingUITestSignedOut") {
                LoggedOutCarouselView(analytics: NoopAnalyticsClient(), getStarted: {}, logIn: {})
            } else if ProcessInfo.processInfo.arguments.contains("-WanderMapCapture") {
                mapCaptureRoot
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
        AppEntryView(coordinator: entryCoordinator, analytics: analytics, parser: discoverParser)
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(pushNotifications)
            .modelContainer(WanderModelContainer.preview)
    }

    #if DEBUG
    private var mapCaptureRoot: some View {
        WanderRootView(analytics: NoopAnalyticsClient(), parser: DeterministicFilterParser())
            .environmentObject(auth)
            .environmentObject(backend)
            .environmentObject(pushNotifications)
            .modelContainer(WanderModelContainer.preview)
    }
    #endif

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
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    private let analytics: AnalyticsClient
    private let parser: any LLMFilterParser
    @State private var hasResolvedSession = false
    @State private var sessionRefreshGeneration = 0
    @State private var authenticatedUserID: String?

    init(analytics: AnalyticsClient, parser: any LLMFilterParser) {
        self.analytics = analytics
        self.parser = parser
    }

    var body: some View {
        let destination = Self.destination(
            for: auth.state,
            hasResolvedSession: hasResolvedSession,
            isSessionValidated: auth.isSessionValidated
        )

        ZStack {
            if case .signedIn(let session) = auth.state {
                WanderRootView(
                    initialSession: session,
                    isSessionValidated: destination == .authenticated,
                    analytics: analytics,
                    parser: parser
                )
                .id(session.userID)
                .allowsHitTesting(destination == .authenticated)
                .accessibilityHidden(destination != .authenticated)
            }

            sessionOverlay(for: destination)
        }
        .task(id: sessionRefreshGeneration) {
            await resolveSession()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            auth.beginSessionValidation()
            hasResolvedSession = false
            sessionRefreshGeneration &+= 1
        }
        .onChange(of: auth.state, initial: true) { _, state in
            let newUserID: String?
            if case .signedIn(let session) = state {
                newUserID = session.userID
            } else {
                newUserID = nil
            }
            if authenticatedUserID != newUserID {
                if authenticatedUserID != nil {
                    WanderWidgetSnapshotPublisher.clear()
                    pushNotifications.clearAuthenticatedSessionState()
                }
                authenticatedUserID = newUserID
                if let newUserID, auth.isSessionValidated {
                    WanderAppDelegate.setAuthenticatedSessionActive(userID: newUserID)
                }
            }
            guard newUserID == nil else { return }
            analytics.resetIdentity()
            WanderWidgetSnapshotPublisher.clear()
        }
        .onChange(of: destination, initial: true) { _, destination in
            switch destination {
            case .authenticated:
                if case .signedIn(let session) = auth.state {
                    WanderAppDelegate.setAuthenticatedSessionActive(userID: session.userID)
                }
            case .signIn, .unavailable:
                pushNotifications.clearAuthenticatedSessionState()
            case .loading:
                WanderAppDelegate.beginAuthenticatedSessionValidation()
            }
        }
    }

    @ViewBuilder
    private func sessionOverlay(for destination: WanderAppSessionDestination) -> some View {
        switch destination {
        case .loading:
            sessionLoadingView
        case .signIn:
            ClerkNativeAuthView(isDismissable: false)
        case .authenticated:
            EmptyView()
        case .unavailable(let message):
            authUnavailableView(message: message)
        }
    }

    private var sessionLoadingView: some View {
        VStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text("Checking your session…")
                .font(.body.weight(.semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    private func authUnavailableView(message: String) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: WanderTheme.spacing4) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .accessibilityHidden(true)
                    VStack(spacing: WanderTheme.spacing2) {
                        Text("Sign in is unavailable")
                            .font(.title2.weight(.bold))
                        Text(message)
                            .font(.body)
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .multilineTextAlignment(.center)
                    }
                    WanderPrimaryButton(title: "Try again", systemImage: "arrow.clockwise") {
                        auth.beginSessionValidation()
                        hasResolvedSession = false
                        sessionRefreshGeneration &+= 1
                    }
                }
                .padding(WanderTheme.spacing4)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
    }

    static func destination(
        for state: AuthState,
        hasResolvedSession: Bool,
        isSessionValidated: Bool = true
    ) -> WanderAppSessionDestination {
        guard hasResolvedSession else { return .loading }
        switch state {
        case .loading:
            return .loading
        case .signedOut:
            return .signIn
        case .signedIn:
            return isSessionValidated ? .authenticated : .loading
        case .unavailable(let message):
            return .unavailable(message)
        }
    }

    private func resolveSession() async {
        await auth.refreshSession()
        guard !Task.isCancelled else { return }
        hasResolvedSession = true
    }
}
