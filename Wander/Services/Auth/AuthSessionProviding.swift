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

struct AuthSession: Codable, Equatable, Identifiable {
    let userID: String
    let displayName: String?
    let handle: String?
    let email: String?
    let phoneNumber: String?

    var id: String { userID }

    init(
        userID: String,
        displayName: String?,
        handle: String?,
        email: String? = nil,
        phoneNumber: String? = nil
    ) {
        self.userID = userID
        self.displayName = displayName
        self.handle = handle
        self.email = email
        self.phoneNumber = phoneNumber
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
                        handle: session.handle
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

enum AuthGateIntent: String, Equatable, Identifiable {
    case syncPlace
    case socialSave
    case socialActivity
    case followPeople
    case manageBlocks
    case reportContent
    case manageNotifications
    case syncPending

    var id: String { rawValue }

    var copy: AuthGateCopy {
        switch self {
        case .syncPlace:
            AuthGateCopy(
                title: "Sign in to sync this place",
                message: "It stays on this phone either way. Sign in when you want it backed up and shared by your visibility setting.",
                primaryAction: "Sign in",
                secondaryAction: "Keep it here"
            )
        case .socialSave:
            AuthGateCopy(
                title: "Sign in to save from people",
                message: "Social saves need an account so \(AppBrand.displayName) knows whose map gets the copy.",
                primaryAction: "Sign in",
                secondaryAction: "Keep browsing"
            )
        case .socialActivity:
            AuthGateCopy(
                title: "Sign in to join the conversation",
                message: "Likes and comments need an account so people know they came from you.",
                primaryAction: "Sign in",
                secondaryAction: "Keep browsing"
            )
        case .followPeople:
            AuthGateCopy(
                title: "Sign in to follow people",
                message: "Follows shape your social map and need an account.",
                primaryAction: "Sign in",
                secondaryAction: "Not now"
            )
        case .manageBlocks:
            AuthGateCopy(
                title: "Sign in to manage blocks",
                message: "Blocks apply across search, profiles, and maps, so they need an account.",
                primaryAction: "Sign in",
                secondaryAction: "Cancel"
            )
        case .reportContent:
            AuthGateCopy(
                title: "Sign in to send a report",
                message: "Reports need an account so our safety team can investigate abuse and prevent duplicate reports.",
                primaryAction: "Sign in",
                secondaryAction: "Cancel"
            )
        case .manageNotifications:
            AuthGateCopy(
                title: "Sign in for notifications",
                message: "Notification settings follow your account and device.",
                primaryAction: "Sign in",
                secondaryAction: "Cancel"
            )
        case .syncPending:
            AuthGateCopy(
                title: "Sign in to sync pending items",
                message: "Your local saves are safe here. Sign in to back them up when you're ready.",
                primaryAction: "Sign in",
                secondaryAction: "Later"
            )
        }
    }
}

struct AuthGateRequest: Equatable, Identifiable {
    let intent: AuthGateIntent
    let createdAt: Date

    var id: String { "\(intent.rawValue)-\(createdAt.timeIntervalSince1970)" }
    var copy: AuthGateCopy { intent.copy }
}

enum AuthSessionError: Error, Equatable {
    case notSignedIn
    case notConfigured
    case tokenUnavailable
    case cancelled
    case appleSessionUnavailable
}

enum NativeAuthMode: String, Equatable {
    case signInOrUp
    case signIn
    case signUp
}

enum NativeAppleAuthOutcome: Equatable {
    case completed
    case requiresClerkContinuation
}

@MainActor
protocol AuthSessionProviding: AnyObject {
    var state: AuthState { get }
    var canPresentNativeAuth: Bool { get }
    func sessionChanges() -> AsyncStream<AuthState>
    func refreshSession() async
    func signInWithApple(mode: NativeAuthMode) async throws -> NativeAppleAuthOutcome
    func signOut() async throws
    func deleteAccount() async throws
    func supabaseAccessToken() async throws -> String
    func refreshSupabaseAccessToken() async throws -> String
}

extension AuthSessionProviding {
    func signInWithApple(mode: NativeAuthMode) async throws -> NativeAppleAuthOutcome {
        throw AuthSessionError.notConfigured
    }

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

@MainActor
final class AuthSessionStore: ObservableObject, AuthSessionProviding {
    @Published private(set) var state: AuthState
    @Published var activeGate: AuthGateRequest?
    @Published var isPresentingNativeAuth = false
    @Published private(set) var activeNativeAuthMode: NativeAuthMode = .signInOrUp
    @Published private(set) var isSigningInWithApple = false
    @Published private(set) var appleSignInError: String?
    @Published private(set) var isSigningOut = false
    @Published private(set) var signOutError: String?
    @Published private(set) var isSessionValidated = false

    private let provider: AuthSessionProviding
    private var sessionObservationTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var isNativeAuthAttemptActive = false

    init(provider: AuthSessionProviding) {
        self.provider = provider
        self.state = provider.state
        sessionObservationTask = Task { @MainActor [weak self] in
            for await state in provider.sessionChanges() {
                guard !Task.isCancelled else { return }
                self?.refreshGeneration &+= 1
                self?.synchronizeState(state)
            }
        }
    }

    deinit {
        sessionObservationTask?.cancel()
    }

    var isSignedIn: Bool {
        state.isSignedIn
    }

    var canPresentNativeAuth: Bool {
        provider.canPresentNativeAuth
    }

    func sessionChanges() -> AsyncStream<AuthState> {
        provider.sessionChanges()
    }

    func beginSessionValidation() {
        isSessionValidated = false
    }

    func refreshSession() async {
        beginSessionValidation()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        #if DEBUG
        WanderDebugLog.remote.debug("auth store refresh start current_state=\(self.state.debugSummary, privacy: .public)")
        #endif
        await provider.refreshSession()
        guard !Task.isCancelled, generation == refreshGeneration else { return }
        synchronizeState(provider.state)
        #if DEBUG
        WanderDebugLog.remote.debug("auth store refresh finished new_state=\(self.state.debugSummary, privacy: .public)")
        #endif
    }

    func requireSignIn(for intent: AuthGateIntent, action: () -> Void) {
        if isSignedIn {
            action()
        } else {
            presentGate(for: intent)
        }
    }

    func presentGate(for intent: AuthGateIntent) {
        activeGate = AuthGateRequest(intent: intent, createdAt: .now)
    }

    func dismissGate() {
        activeGate = nil
    }

    func beginSignIn(mode: NativeAuthMode = .signInOrUp) {
        activeGate = nil
        appleSignInError = nil
        if provider.canPresentNativeAuth {
            activeNativeAuthMode = mode
            isNativeAuthAttemptActive = true
            isPresentingNativeAuth = true
        } else {
            nativeAuthDidDismiss()
            state = .unavailable("Clerk is not configured for this build.")
        }
    }

    func nativeAuthDidDismiss() {
        isNativeAuthAttemptActive = false
        isPresentingNativeAuth = false
        isSigningInWithApple = false
        appleSignInError = nil
    }

    @discardableResult
    func signInWithApple() async -> NativeAppleAuthOutcome? {
        guard provider.canPresentNativeAuth else {
            appleSignInError = "Apple sign-in is not available in this build."
            return nil
        }

        appleSignInError = nil
        isNativeAuthAttemptActive = true
        isSigningInWithApple = true
        defer { isSigningInWithApple = false }

        do {
            let outcome = try await provider.signInWithApple(mode: activeNativeAuthMode)
            if outcome == .completed {
                synchronizeState(provider.state)
                guard state.isSignedIn else {
                    appleSignInError = "Apple sign-in didn’t finish. Try again or use another method."
                    return nil
                }
            }
            return outcome
        } catch AuthSessionError.cancelled, is CancellationError {
            return nil
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "apple sign-in failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            appleSignInError = "Apple sign-in didn’t finish. Try again or use another method."
            return nil
        }
    }

    func supabaseAccessToken() async throws -> String {
        #if DEBUG
        WanderDebugLog.remote.debug("auth store supabase token requested state=\(self.state.debugSummary, privacy: .public)")
        #endif
        guard isSessionValidated else { throw AuthSessionError.notSignedIn }
        do {
            let token = try await provider.supabaseAccessToken()
            #if DEBUG
            WanderDebugLog.remote.debug("auth store supabase token succeeded")
            #endif
            return token
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("auth store supabase token failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func refreshSupabaseAccessToken() async throws -> String {
        #if DEBUG
        WanderDebugLog.remote.debug("auth store forced supabase token refresh requested state=\(self.state.debugSummary, privacy: .public)")
        #endif
        guard isSessionValidated else { throw AuthSessionError.notSignedIn }
        do {
            let token = try await provider.refreshSupabaseAccessToken()
            #if DEBUG
            WanderDebugLog.remote.debug("auth store forced supabase token refresh succeeded")
            #endif
            return token
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("auth store forced supabase token refresh failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            throw error
        }
    }

    func signOut() async throws {
        beginSessionValidation()
        nativeAuthDidDismiss()
        isSigningOut = true
        signOutError = nil
        defer { isSigningOut = false }

        do {
            try await provider.signOut()
            synchronizeStateFromProvider()
        } catch {
            await provider.refreshSession()
            synchronizeStateFromProvider()
            signOutError = "Could not sign out. Try again."
            throw error
        }
    }

    func deleteAccount() async throws {
        beginSessionValidation()
        nativeAuthDidDismiss()
        try await provider.deleteAccount()
        await provider.refreshSession()
        synchronizeStateFromProvider()
    }

    private func synchronizeStateFromProvider() {
        synchronizeState(provider.state)
    }

    private func synchronizeState(_ state: AuthState) {
        self.state = state
        if case .signedIn = state {
            isSessionValidated = true
        } else {
            isSessionValidated = false
        }
        switch state {
        case .signedIn:
            nativeAuthDidDismiss()
        case .offline, .unavailable:
            activeGate = nil
            nativeAuthDidDismiss()
        case .loading, .signedOut:
            activeGate = nil
            if !isNativeAuthAttemptActive {
                isPresentingNativeAuth = false
            }
        }
    }
}

@MainActor
final class PreviewAuthSessionProvider: AuthSessionProviding {
    private(set) var state: AuthState
    let canPresentNativeAuth: Bool
    private let token: String?
    private let signOutError: Error?
    private let appleSignInOutcome: NativeAppleAuthOutcome
    private let appleSignInSession: AuthSession?
    private let appleSignInFailure: Error?
    private let sessionChangeStream: AsyncStream<AuthState>
    private let sessionChangeContinuation: AsyncStream<AuthState>.Continuation
    private(set) var requestedAppleAuthModes: [NativeAuthMode] = []

    init(
        state: AuthState = .signedOut,
        canPresentNativeAuth: Bool = false,
        token: String? = nil,
        signOutError: Error? = nil,
        appleSignInOutcome: NativeAppleAuthOutcome = .completed,
        appleSignInSession: AuthSession? = nil,
        appleSignInFailure: Error? = nil
    ) {
        let (stream, continuation) = AsyncStream<AuthState>.makeStream()
        self.state = state
        self.canPresentNativeAuth = canPresentNativeAuth
        self.token = token
        self.signOutError = signOutError
        self.appleSignInOutcome = appleSignInOutcome
        self.appleSignInSession = appleSignInSession
        self.appleSignInFailure = appleSignInFailure
        self.sessionChangeStream = stream
        self.sessionChangeContinuation = continuation
    }

    func setState(_ state: AuthState) {
        self.state = state
        sessionChangeContinuation.yield(state)
    }

    func setStateSilently(_ state: AuthState) {
        self.state = state
    }

    func sessionChanges() -> AsyncStream<AuthState> { sessionChangeStream }

    func refreshSession() async {}

    func signInWithApple(mode: NativeAuthMode) async throws -> NativeAppleAuthOutcome {
        requestedAppleAuthModes.append(mode)
        if let appleSignInFailure {
            throw appleSignInFailure
        }
        if appleSignInOutcome == .completed, let appleSignInSession {
            state = .signedIn(appleSignInSession)
            sessionChangeContinuation.yield(state)
        }
        return appleSignInOutcome
    }

    func signOut() async throws {
        if let signOutError {
            throw signOutError
        }
        state = .signedOut
    }

    func supabaseAccessToken() async throws -> String {
        guard state.isSignedIn else { throw AuthSessionError.notSignedIn }
        guard let token else { throw AuthSessionError.tokenUnavailable }
        return token
    }
}
