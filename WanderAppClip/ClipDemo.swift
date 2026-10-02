#if DEBUG
import Foundation

/// Debug-only synthetic fixtures. This is not evidence of live auth or a
/// sent Messages card. No production writes or credentials are used.
@MainActor
enum ClipDemo {
    static let id = "00000000-0000-0000-0000-000000000408"
    static let place = ClipPlace(id: id, title: "Ocean Park Coffee", address: "Santa Monica, California",
        latitude: 34.003, longitude: -118.484)!
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-AstirClipDemo") }
    static var url: URL {
        let path = ProcessInfo.processInfo.arguments.contains("-AstirClipDemoInvite")
            ? "invites/" + String(repeating: "a", count: 48) : "places/" + id
        return URL(string: "https://astirmovement.com/" + path)!
    }
    static func store() -> ClipStore { ClipStore(auth: DemoAuth(), service: DemoService()) }

    private final class DemoAuth: AuthSessionProviding {
        var state: AuthState = .signedOut
        var canPresentNativeAuth: Bool { true }
        func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
        func refreshSession() async {}
        func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeSocialAuthResult {
            state = .signedIn(AuthSession(userID: "clip_demo", displayName: "Demo Person", handle: "demo_person"))
            return NativeSocialAuthResult(outcome: .completed)
        }
        func signOut() async throws { state = .signedOut }
        func supabaseAccessToken() async throws -> String { throw AuthSessionError.notConfigured }
    }
    private final class DemoService: ClipServing {
        var hasProfile = false
        func preview(_ route: AppClipRoute, authenticated: Bool) async throws -> ClipPreview {
            ClipPreview(title: route.kind == .invite || route.kind == .list ? "Weekend favorites" : place.title,
                subtitle: "Demo · Synthetic shared \(route.kind.rawValue)", imageURL: nil,
                places: route.kind == .invite ? [] : [place])
        }
        func profile() async throws -> ClipProfile? {
            hasProfile ? ClipProfile(id: "clip_demo", displayName: "Demo Person", handle: "demo_person", isPrivate: false, onboardedAt: nil) : nil
        }
        func updateProfile(name: String, handle: String) async throws -> ClipProfile {
            hasProfile = true
            return ClipProfile(id: "clip_demo", displayName: name, handle: handle, isPrivate: false, onboardedAt: nil)
        }
        func save(_ place: ClipPlace) async throws -> Bool { true }
        func join(_ route: AppClipRoute) async throws -> String { id }
    }
}
#endif
