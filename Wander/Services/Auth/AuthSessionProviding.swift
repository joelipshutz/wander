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

@MainActor
protocol AuthSessionProviding: AnyObject {
    var state: AuthState { get }
    var canPresentNativeAuth: Bool { get }
    func sessionChanges() -> AsyncStream<AuthState>
    func refreshSession() async
    func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeAuthOutcome
    func sendEmailCode(to emailAddress: String, mode: NativeAuthMode) async throws
    func verifyEmailCode(_ code: String) async throws -> NativeAuthOutcome
    func authenticateWithPassword(emailAddress: String, password: String) async throws -> NativeAuthOutcome
    func resetPendingEmailVerification()
    func signOut() async throws
    func deleteAccount() async throws
    func supabaseAccessToken() async throws -> String
    func refreshSupabaseAccessToken() async throws -> String
}

extension AuthSessionProviding {
    func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeAuthOutcome {
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

@MainActor
final class AuthSessionStore: ObservableObject, AuthSessionProviding {
    @Published private(set) var state: AuthState
    @Published var activeGate: AuthGateRequest?
    @Published var isPresentingNativeAuth = false
    @Published private(set) var activeNativeAuthMode: NativeAuthMode = .signInOrUp
    @Published private(set) var activeSocialAuthProvider: NativeSocialAuthProvider?
    @Published private(set) var isSendingEmailCode = false
    @Published private(set) var isVerifyingEmailCode = false
    @Published private(set) var isSigningInWithPassword = false
    @Published private(set) var emailVerificationAddress: String?
    @Published private(set) var nativeAuthError: String?
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

    var isPerformingNativeAuth: Bool {
        activeSocialAuthProvider != nil
            || isSendingEmailCode
            || isVerifyingEmailCode
            || isSigningInWithPassword
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
        resetNativeAuthForm()
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
        resetNativeAuthForm()
    }

    @discardableResult
    func authenticate(with socialProvider: NativeSocialAuthProvider) async -> NativeAuthOutcome? {
        guard provider.canPresentNativeAuth else {
            nativeAuthError = "Sign in is not available in this build."
            return nil
        }

        nativeAuthError = nil
        isNativeAuthAttemptActive = true
        activeSocialAuthProvider = socialProvider
        defer { activeSocialAuthProvider = nil }

        do {
            let outcome = try await provider.authenticate(
                with: socialProvider,
                mode: activeNativeAuthMode
            )
            if outcome == .completed {
                synchronizeState(provider.state)
                guard state.isSignedIn else {
                    nativeAuthError = "\(socialProvider.displayName) sign-in didn’t finish. Try again or use another method."
                    return nil
                }
            } else {
                nativeAuthError = incompleteSocialAuthMessage(
                    provider: socialProvider,
                    outcome: outcome
                )
            }
            return outcome
        } catch AuthSessionError.cancelled, is CancellationError {
            return nil
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "social sign-in failed provider=\(socialProvider.rawValue, privacy: .public) error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            nativeAuthError = "\(socialProvider.displayName) sign-in didn’t finish. Try again or use another method."
            return nil
        }
    }

    func sendEmailCode(to rawEmailAddress: String) async -> Bool {
        guard provider.canPresentNativeAuth else {
            nativeAuthError = "Email sign-in is not available in this build."
            return false
        }

        let emailAddress = rawEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmailAddress(emailAddress) else {
            nativeAuthError = "Enter a valid email address."
            return false
        }

        nativeAuthError = nil
        isNativeAuthAttemptActive = true
        isSendingEmailCode = true
        defer { isSendingEmailCode = false }

        do {
            try await provider.sendEmailCode(to: emailAddress, mode: activeNativeAuthMode)
            emailVerificationAddress = emailAddress
            return true
        } catch AuthSessionError.accountNotFound {
            nativeAuthError = "We couldn’t find an account for that email. Try Apple or Google, or create an account."
        } catch AuthSessionError.emailAlreadyInUse {
            nativeAuthError = "That email already has an account. Go back and log in instead."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "email code send failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            nativeAuthError = "We couldn’t send a code. Check the email and try again."
        }
        return false
    }

    @discardableResult
    func verifyEmailCode(_ rawCode: String) async -> NativeAuthOutcome? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            nativeAuthError = "Enter the code from your email."
            return nil
        }

        nativeAuthError = nil
        isVerifyingEmailCode = true
        defer { isVerifyingEmailCode = false }

        do {
            let outcome = try await provider.verifyEmailCode(code)
            if outcome == .completed {
                synchronizeState(provider.state)
                guard state.isSignedIn else {
                    nativeAuthError = "Email sign-in didn’t finish. Try again."
                    return nil
                }
            } else {
                nativeAuthError = "This account needs another verification step. Try Apple or Google, or contact support."
            }
            return outcome
        } catch AuthSessionError.invalidVerificationCode {
            nativeAuthError = "That code isn’t right. Check the email and try again."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "email code verification failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            nativeAuthError = "We couldn’t verify that code. Try again."
        }
        return nil
    }

    func cancelEmailVerification() {
        provider.resetPendingEmailVerification()
        emailVerificationAddress = nil
        nativeAuthError = nil
    }

    @discardableResult
    func signInWithPassword(
        emailAddress rawEmailAddress: String,
        password rawPassword: String
    ) async -> NativeAuthOutcome? {
        guard provider.canPresentNativeAuth else {
            nativeAuthError = "Password sign-in is not available in this build."
            return nil
        }

        let emailAddress = rawEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmailAddress(emailAddress) else {
            nativeAuthError = "Enter a valid email address."
            return nil
        }
        guard !rawPassword.isEmpty else {
            nativeAuthError = "Enter your password."
            return nil
        }

        nativeAuthError = nil
        isNativeAuthAttemptActive = true
        isSigningInWithPassword = true
        defer { isSigningInWithPassword = false }

        do {
            let outcome = try await provider.authenticateWithPassword(
                emailAddress: emailAddress,
                password: rawPassword
            )
            if outcome == .completed {
                synchronizeState(provider.state)
                guard state.isSignedIn else {
                    nativeAuthError = "Password sign-in didn’t finish. Try again or use another method."
                    return nil
                }
            } else {
                nativeAuthError = "This account needs another verification step. Use email or another sign-in method."
            }
            return outcome
        } catch AuthSessionError.invalidCredentials, AuthSessionError.accountNotFound {
            nativeAuthError = "Email or password didn’t match."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("password sign-in failed")
            #endif
            nativeAuthError = "Password sign-in didn’t finish. Check your connection and try again."
        }
        return nil
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

    private func resetNativeAuthForm() {
        activeSocialAuthProvider = nil
        isSendingEmailCode = false
        isVerifyingEmailCode = false
        isSigningInWithPassword = false
        emailVerificationAddress = nil
        nativeAuthError = nil
        provider.resetPendingEmailVerification()
    }

    private func incompleteSocialAuthMessage(
        provider: NativeSocialAuthProvider,
        outcome: NativeAuthOutcome
    ) -> String {
        switch outcome {
        case .completed:
            return ""
        case .requiresExistingAccountVerification:
            return "We couldn’t match that \(provider.displayName) login to an existing account. Sign in with your original method first, then connect \(provider.displayName) in Settings."
        case .requiresAdditionalVerification:
            return "This \(provider.displayName) account needs another verification step. Try email or your other sign-in method."
        }
    }

    private static func looksLikeEmailAddress(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix(".")
        else {
            return false
        }
        return true
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
    private let nativeAuthOutcome: NativeAuthOutcome
    private let nativeAuthSession: AuthSession?
    private let nativeAuthFailure: Error?
    private let emailVerificationOutcome: NativeAuthOutcome
    private let emailVerificationSession: AuthSession?
    private let emailCodeFailure: Error?
    private let emailVerificationFailure: Error?
    private let passwordAuthOutcome: NativeAuthOutcome
    private let passwordAuthSession: AuthSession?
    private let passwordAuthFailure: Error?
    private let sessionChangeStream: AsyncStream<AuthState>
    private let sessionChangeContinuation: AsyncStream<AuthState>.Continuation
    private(set) var requestedSocialAuth: [NativeSocialAuthRequest] = []
    private(set) var requestedEmailCodes: [(emailAddress: String, mode: NativeAuthMode)] = []
    private(set) var verifiedEmailCodes: [String] = []
    private(set) var requestedPasswordSignInEmails: [String] = []
    private(set) var didResetPendingEmailVerification = false

    init(
        state: AuthState = .signedOut,
        canPresentNativeAuth: Bool = false,
        token: String? = nil,
        signOutError: Error? = nil,
        nativeAuthOutcome: NativeAuthOutcome = .completed,
        nativeAuthSession: AuthSession? = nil,
        nativeAuthFailure: Error? = nil,
        emailVerificationOutcome: NativeAuthOutcome = .completed,
        emailVerificationSession: AuthSession? = nil,
        emailCodeFailure: Error? = nil,
        emailVerificationFailure: Error? = nil,
        passwordAuthOutcome: NativeAuthOutcome = .completed,
        passwordAuthSession: AuthSession? = nil,
        passwordAuthFailure: Error? = nil
    ) {
        let (stream, continuation) = AsyncStream<AuthState>.makeStream()
        self.state = state
        self.canPresentNativeAuth = canPresentNativeAuth
        self.token = token
        self.signOutError = signOutError
        self.nativeAuthOutcome = nativeAuthOutcome
        self.nativeAuthSession = nativeAuthSession
        self.nativeAuthFailure = nativeAuthFailure
        self.emailVerificationOutcome = emailVerificationOutcome
        self.emailVerificationSession = emailVerificationSession
        self.emailCodeFailure = emailCodeFailure
        self.emailVerificationFailure = emailVerificationFailure
        self.passwordAuthOutcome = passwordAuthOutcome
        self.passwordAuthSession = passwordAuthSession
        self.passwordAuthFailure = passwordAuthFailure
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

    func authenticate(
        with provider: NativeSocialAuthProvider,
        mode: NativeAuthMode
    ) async throws -> NativeAuthOutcome {
        requestedSocialAuth.append(.init(provider: provider, mode: mode))
        if let nativeAuthFailure {
            throw nativeAuthFailure
        }
        if nativeAuthOutcome == .completed, let nativeAuthSession {
            state = .signedIn(nativeAuthSession)
            sessionChangeContinuation.yield(state)
        }
        return nativeAuthOutcome
    }

    func sendEmailCode(to emailAddress: String, mode: NativeAuthMode) async throws {
        requestedEmailCodes.append((emailAddress, mode))
        if let emailCodeFailure {
            throw emailCodeFailure
        }
        didResetPendingEmailVerification = false
    }

    func verifyEmailCode(_ code: String) async throws -> NativeAuthOutcome {
        verifiedEmailCodes.append(code)
        if let emailVerificationFailure {
            throw emailVerificationFailure
        }
        if emailVerificationOutcome == .completed, let emailVerificationSession {
            state = .signedIn(emailVerificationSession)
            sessionChangeContinuation.yield(state)
        }
        return emailVerificationOutcome
    }

    func authenticateWithPassword(
        emailAddress: String,
        password: String
    ) async throws -> NativeAuthOutcome {
        requestedPasswordSignInEmails.append(emailAddress)
        if let passwordAuthFailure {
            throw passwordAuthFailure
        }
        if passwordAuthOutcome == .completed, let passwordAuthSession {
            state = .signedIn(passwordAuthSession)
            sessionChangeContinuation.yield(state)
        }
        return passwordAuthOutcome
    }

    func resetPendingEmailVerification() {
        didResetPendingEmailVerification = true
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
