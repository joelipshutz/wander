import SwiftUI
import ClerkKit

@main
struct AstirClipApp: App {
    @StateObject private var store: ClipStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ClipDemo.enabled {
            _store = StateObject(wrappedValue: ClipDemo.store())
            return
        }
        #endif
        let configuration = WanderBackendConfiguration.current()
        let auth = ClerkAuthService(configuration: configuration, configureClerk: { key in
            // Apple transfers this Clip's Keychain to its corresponding full
            // app. Use the parent's existing service name without changing the
            // full app's Keychain configuration or exporting tokens to a group.
            Clerk.configure(publishableKey: key, options: .init(telemetryEnabled: false,
                keychainConfig: .init(service: "com.grayline.wander"))).publishableKey
        })
        _store = StateObject(wrappedValue: ClipStore(auth: auth,
            service: ClipService(configuration: configuration, auth: auth), analytics: .live()))
    }

    var body: some Scene {
        WindowGroup {
            ClipView(store: store)
                .task { await store.observeSessionChanges() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.refreshOnForeground() }
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { store.open(url) }
                }
                .onOpenURL { store.open($0) }
                .task {
                    #if DEBUG
                    if ClipDemo.enabled, store.route == nil { store.open(ClipDemo.url); return }
                    if let value = ProcessInfo.processInfo.environment["_XCAppClipURL"], let url = URL(string: value), store.route == nil {
                        store.open(url)
                    }
                    #endif
                }
        }
    }
}
