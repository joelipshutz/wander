import SwiftUI
import SwiftData

@main
struct WanderApp: App {
    @StateObject private var auth: AuthSessionStore
    @StateObject private var backend: WanderBackend
    private let analytics: AnalyticsClient

    init() {
        let configuration = WanderBackendConfiguration.current()
        analytics = PostHogAnalyticsClient(configuration: .current()) ?? NoopAnalyticsClient()
        let authStore = AuthSessionStore(provider: ClerkAuthService(configuration: configuration))
        _auth = StateObject(wrappedValue: authStore)
        _backend = StateObject(wrappedValue: WanderBackend(configuration: configuration, authSession: authStore))
    }

    var body: some Scene {
        WindowGroup {
            WanderRootView(analytics: analytics)
                .environmentObject(auth)
                .environmentObject(backend)
                .modelContainer(WanderModelContainer.preview)
        }
    }
}
