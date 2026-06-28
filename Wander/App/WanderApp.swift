import SwiftUI
import SwiftData

@main
struct WanderApp: App {
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
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
            WanderRootView(analytics: analytics, parser: discoverParser)
                .environmentObject(auth)
                .environmentObject(backend)
                .modelContainer(WanderModelContainer.preview)
        }
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
