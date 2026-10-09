import Foundation

enum AuthState: Equatable {
    case signedOut
    case loading
    case signedIn(AuthSession)
    case offline(AuthSession, message: String)
    case unavailable(String)

    var isSignedIn: Bool {
        switch self {
        case .signedIn, .offline:
            return true
        case .signedOut, .loading, .unavailable:
            return false
        }
    }

    var session: AuthSession? {
        switch self {
        case .signedIn(let session), .offline(let session, _):
            return session
        case .signedOut, .loading, .unavailable:
            return nil
        }
    }
}

#if DEBUG
extension AuthState {
    var debugSummary: String {
        switch self {
        case .signedOut:
            return "signed_out"
        case .loading:
            return "loading"
        case .signedIn(let session):
            return "signed_in:\(WanderDebugLog.shortID(session.userID))"
        case .offline(let session, _):
            return "offline:\(WanderDebugLog.shortID(session.userID))"
        case .unavailable:
            return "unavailable"
        }
    }
}
#endif

struct AuthSession: Codable, Equatable, Identifiable, Sendable {
    let userID: String
    let displayName: String?
    let handle: String?
    let email: String?
    let phoneNumber: String?
    // Optional for compatibility with sessions cached before Apple-only onboarding.
    var isAppleSignIn: Bool?

    var id: String { userID }

    init(
        userID: String,
        displayName: String?,
        handle: String?,
        email: String? = nil,
        phoneNumber: String? = nil,
        isAppleSignIn: Bool? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.handle = handle
        self.email = email
        self.phoneNumber = phoneNumber
        self.isAppleSignIn = isAppleSignIn
    }
}

@MainActor
struct AuthSessionCache {
    let load: () -> AuthSession?
    let save: (AuthSession?) -> Void

    static let disabled = AuthSessionCache(load: { nil }, save: { _ in })

    static let live = file(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("last-auth-session-v1.json")
    )

    static func file(url: URL) -> AuthSessionCache {
        AuthSessionCache(
            load: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(AuthSession.self, from: data)
            },
            save: { session in
                guard let session else {
                    try? FileManager.default.removeItem(at: url)
                    return
                }

                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                    )
                    let cachedSession = AuthSession(
                        userID: session.userID,
                        displayName: session.displayName,
                        handle: session.handle,
                        isAppleSignIn: session.isAppleSignIn
                    )
                    let data = try JSONEncoder().encode(cachedSession)
                    try data.write(
                        to: url,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                } catch {
                    #if DEBUG
                    WanderDebugLog.remote.error(
                        "auth session cache write failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
                    )
                    #endif
                }
            }
        )
    }
}

/// UI context only: never used as proof of authentication or account ownership.
/// Match the exact Clerk session so linked Apple accounts signing in by email
/// or Google retain their normal onboarding, including after a relaunch.
@MainActor
struct AppleSignInSessionStore {
    let load: () -> String?
    let save: (String?) -> Void

    static let disabled = AppleSignInSessionStore(load: { nil }, save: { _ in })
    static let live = preferences(.standard)

    static func preferences(_ defaults: UserDefaults) -> AppleSignInSessionStore {
        let key = "astir.onboarding.appleSignInSession.v1"
        return AppleSignInSessionStore(
            load: { defaults.string(forKey: key) },
            save: { sessionID in
                if let sessionID { defaults.set(sessionID, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        )
    }
}

struct NativeAuthSessionFence: Codable, Equatable, Sendable {
    /// Nil means no session can be adopted without a new correlated auth
    /// result. A value permits only that exact Clerk session ID.
    let requiredSessionID: String?

    static let blockUncorrelated = NativeAuthSessionFence(requiredSessionID: nil)

    static func require(_ sessionID: String) -> NativeAuthSessionFence {
        NativeAuthSessionFence(requiredSessionID: sessionID)
    }
}

@MainActor
struct NativeAuthSessionFenceStore {
    enum LoadResult: Equatable {
        case missing
        case fence(NativeAuthSessionFence)
        case invalid
    }

    let load: () -> LoadResult
    let save: (NativeAuthSessionFence?) -> Bool

    static let disabled = NativeAuthSessionFenceStore(
        load: { .missing },
        save: { _ in true }
    )

    static let live = file(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wander", isDirectory: true)
            .appendingPathComponent("native-auth-session-fence-v1.json")
    )

    static func file(url: URL) -> NativeAuthSessionFenceStore {
        NativeAuthSessionFenceStore(
            load: {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    return .missing
                }
                guard let data = try? Data(contentsOf: url),
                      let fence = try? JSONDecoder().decode(NativeAuthSessionFence.self, from: data)
                else {
                    return .invalid
                }
                return .fence(fence)
            },
            save: { fence in
                guard let fence else {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        return true
                    }
                    do {
                        try FileManager.default.removeItem(at: url)
                        return true
                    } catch {
                        #if DEBUG
                        WanderDebugLog.remote.error(
                            "native auth fence removal failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
                        )
                        #endif
                        return false
                    }
                }

                do {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                    )
                    let data = try JSONEncoder().encode(fence)
                    try data.write(
                        to: url,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                    return true
                } catch {
                    #if DEBUG
                    WanderDebugLog.remote.error(
                        "native auth fence write failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
                    )
                    #endif
                    return false
                }
            }
        )
    }
}

enum AuthSessionError: Error, Equatable {
    case notSignedIn
    case notConfigured
    case tokenUnavailable
    case cancelled
    case sessionUnavailable
    case accountNotFound
    case emailAlreadyInUse
    case invalidVerificationCode
    case emailVerificationUnavailable
    case invalidCredentials
}

enum NativeAuthMode: String, Equatable {
    case signInOrUp
    case signIn
    case signUp
}

enum NativeSocialAuthProvider: String, Equatable {
    case apple
    case google

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        }
    }
}

struct NativeSocialAuthRequest: Equatable {
    let provider: NativeSocialAuthProvider
    let mode: NativeAuthMode
}

enum NativeAuthOutcome: Equatable {
    case completed
    case requiresExistingAccountVerification
    case requiresAdditionalVerification
}

enum NativeAuthSessionAdoption: String, Equatable {
    case notRequired = "not_required"
    case immediate
    case afterCompletionRetry = "after_completion_retry"
}

struct NativeSocialAuthResult: Equatable {
    let outcome: NativeAuthOutcome
    let sessionAdoption: NativeAuthSessionAdoption

    init(
        outcome: NativeAuthOutcome,
        sessionAdoption: NativeAuthSessionAdoption? = nil
    ) {
        self.outcome = outcome
        self.sessionAdoption = sessionAdoption
            ?? (outcome == .completed ? .immediate : .notRequired)
    }
}

@MainActor
protocol AuthSessionProviding: AnyObject {
    var state: AuthState { get }
    var canPresentNativeAuth: Bool { get }
    func sessionChanges() -> AsyncStream<AuthState>
    func refreshSession() async
    func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeSocialAuthResult
    func sendEmailCode(to emailAddress: String, mode: NativeAuthMode) async throws
    func verifyEmailCode(_ code: String) async throws -> NativeAuthOutcome
    func authenticateWithPassword(emailAddress: String, password: String) async throws -> NativeAuthOutcome
    func sendPasswordVerificationCode() async throws
    func resetPendingEmailVerification()
    func signOut() async throws
    func deleteAccount() async throws
    func supabaseAccessToken() async throws -> String
    func refreshSupabaseAccessToken() async throws -> String
}

extension AuthSessionProviding {
    func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeSocialAuthResult {
        throw AuthSessionError.notConfigured
    }

    func sendEmailCode(to emailAddress: String, mode: NativeAuthMode) async throws {
        throw AuthSessionError.notConfigured
    }

    func verifyEmailCode(_ code: String) async throws -> NativeAuthOutcome {
        throw AuthSessionError.notConfigured
    }

    func authenticateWithPassword(emailAddress: String, password: String) async throws -> NativeAuthOutcome {
        throw AuthSessionError.notConfigured
    }

    func sendPasswordVerificationCode() async throws {
        throw AuthSessionError.emailVerificationUnavailable
    }

    func resetPendingEmailVerification() {}

    func deleteAccount() async throws {
        throw AuthSessionError.notConfigured
    }

    /// Providers that do not maintain a server-token cache can treat a forced
    /// refresh as an ordinary token request. Clerk overrides this to bypass
    /// its short-lived in-memory cache after an authorization response.
    func refreshSupabaseAccessToken() async throws -> String {
        try await supabaseAccessToken()
    }
}
