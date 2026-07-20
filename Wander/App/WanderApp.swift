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
            if let profileMockupPage = ProfileRedesignMockupPage.resolved() {
                ProfileRedesignMockupRoot(page: profileMockupPage)
            } else if let activityMockupPage = PlaceActivityMockupPage.resolved() {
                PlaceActivityMockupRoot(page: activityMockupPage)
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
        WanderRootView(analytics: analytics, parser: discoverParser)
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
