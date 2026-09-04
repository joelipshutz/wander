import Foundation
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(ClerkKit)
import ClerkKit
#endif

@MainActor
final class ClerkAuthService: AuthSessionProviding {
    private(set) var state: AuthState = .loading
    private let configuration: WanderBackendConfiguration
    private let sessionCache: AuthSessionCache
    private static let canonicalUserIDMetadataKey = "canonical_user_id"

    #if canImport(ClerkKit)
    struct ResolvedSession: Sendable {
        let clerkSessionID: String
        let authSession: AuthSession
    }

    typealias SessionResolver = @MainActor () async throws -> ResolvedSession?
    typealias SessionIDResolver = @MainActor () -> String?
    typealias SessionAdoptionSleeper = @MainActor (UInt64) async throws -> Void
    private let resolveAuthoritativeSession: SessionResolver
    private let resolveActiveSessionID: SessionIDResolver
    private let nativeAuthSessionFenceStore: NativeAuthSessionFenceStore
    private let sessionAdoptionRetryDelaysNanoseconds: [UInt64]
    private let sessionAdoptionTimeoutNanoseconds: UInt64
    private let sessionAdoptionSleeper: SessionAdoptionSleeper
    private var pendingNativeAuthSessionID: String?
    private var nativeAuthSessionFence: NativeAuthSessionFence?
    private var refreshGeneration = 0
    private enum PendingEmailVerification {
        case signIn(SignIn)
        case signUp(SignUp)
    }
    private var pendingEmailVerification: PendingEmailVerification?

    init(
        configuration: WanderBackendConfiguration,
        resolveSession: @escaping SessionResolver = ClerkAuthService.resolveCurrentSession,
        resolveSessionID: @escaping SessionIDResolver = { Clerk.shared.session?.id },
        sessionCache: AuthSessionCache = .live,
        nativeAuthSessionFenceStore: NativeAuthSessionFenceStore = .live,
        sessionAdoptionRetryDelaysNanoseconds: [UInt64] = [
            200_000_000,
            600_000_000,
            2_000_000_000
        ],
        sessionAdoptionTimeoutNanoseconds: UInt64 = 6_000_000_000,
        sessionAdoptionSleeper: @escaping SessionAdoptionSleeper = { delay in
            try await Task<Never, Never>.sleep(nanoseconds: delay)
        },
        configureClerk: (String) -> String = { Clerk.configure(publishableKey: $0).publishableKey }
    ) {
        self.configuration = configuration
        self.resolveAuthoritativeSession = resolveSession
        self.resolveActiveSessionID = resolveSessionID
        self.sessionCache = sessionCache
        self.nativeAuthSessionFenceStore = nativeAuthSessionFenceStore
        self.nativeAuthSessionFence = nativeAuthSessionFenceStore.load()
        self.sessionAdoptionRetryDelaysNanoseconds = sessionAdoptionRetryDelaysNanoseconds
        self.sessionAdoptionTimeoutNanoseconds = sessionAdoptionTimeoutNanoseconds
        self.sessionAdoptionSleeper = sessionAdoptionSleeper

        if let publishableKey = configuration.clerkPublishableKey {
            let configuredPublishableKey = configureClerk(publishableKey)
            if configuredPublishableKey.isEmpty {
                state = .unavailable("Missing Clerk publishable key.")
            }
        } else {
            state = .unavailable("Missing Clerk publishable key.")
        }
    }
    #else
    init(configuration: WanderBackendConfiguration, sessionCache: AuthSessionCache = .live) {
        self.configuration = configuration
        self.sessionCache = sessionCache

        state = .unavailable("ClerkKit is not linked.")
    }
    #endif

    var canPresentNativeAuth: Bool {
        guard configuration.isClerkConfigured else {
            return false
        }
        if case .unavailable = state {
            return false
        }
        return true
    }

    func sessionChanges() -> AsyncStream<AuthState> {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        let events = Clerk.shared.auth.events
        return AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .signInCompleted, .signUpCompleted,
                         .signInNeedsContinuation, .signUpNeedsContinuation:
                        // A completed auth response does not always include the
                        // refreshed Clerk client. The initiating auth method
                        // resolves that authoritative client before succeeding.
                        // Publishing currentClientState() here can race that
                        // refresh and incorrectly turn a valid login into a
                        // signed-out result.
                        break
                    case .signedOut, .accountDeleted:
                        guard let self else { return }
                        self.applyTerminalSignedOutState()
                        continuation.yield(.signedOut)
                    case .sessionChanged:
                        guard let self else { return }
                        let state = Self.currentClientState()
                        guard self.shouldPublishSessionChange(observedState: state) else {
                            continue
                        }
                        self.applyObservedClientState(state)
                        continuation.yield(state)
                    case .tokenRefreshed:
                        break
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
        #else
        return AsyncStream { continuation in
            continuation.finish()
        }
        #endif
    }

    func refreshSession() async {
        #if canImport(ClerkKit)
        await refreshSession(expectedSessionID: nil)
        #else
        state = .unavailable("ClerkKit is not linked.")
        #if DEBUG
        WanderDebugLog.remote.error("clerk refresh unavailable reason=clerkkit_not_linked")
        #endif
        #endif
    }

    #if canImport(ClerkKit)
    private func refreshSession(
        expectedSessionID: String?,
        deadline: UInt64? = nil
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard configuration.isClerkConfigured else {
            state = .unavailable("Missing Clerk publishable key.")
            #if DEBUG
            WanderDebugLog.remote.error("clerk refresh skipped reason=missing_publishable_key")
            #endif
            return
        }

        do {
            let resolvedSession: ResolvedSession?
            if let deadline {
                let remaining = remainingNanoseconds(until: deadline)
                guard remaining > 0 else {
                    sessionCache.save(nil)
                    state = .signedOut
                    return
                }
                resolvedSession = try await resolveAuthoritativeSession(within: remaining)
            } else {
                resolvedSession = try await resolveAuthoritativeSession()
            }
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            guard let session = resolvedSession else {
                sessionCache.save(nil)
                state = .signedOut
                #if DEBUG
                WanderDebugLog.remote.debug("clerk refresh signed_out")
                #endif
                return
            }
            let requiredSessionID: String?
            if let expectedSessionID {
                requiredSessionID = expectedSessionID
            } else if let nativeAuthSessionFence {
                guard let fencedSessionID = nativeAuthSessionFence.requiredSessionID else {
                    sessionCache.save(nil)
                    state = .signedOut
                    return
                }
                requiredSessionID = fencedSessionID
            } else {
                requiredSessionID = nil
            }
            if let requiredSessionID,
               (session.clerkSessionID != requiredSessionID
                   || resolveActiveSessionID() != requiredSessionID) {
                sessionCache.save(nil)
                state = .signedOut
                #if DEBUG
                WanderDebugLog.remote.error("clerk refresh rejected reason=session_mismatch")
                #endif
                return
            }
            if expectedSessionID != nil
                || nativeAuthSessionFence?.requiredSessionID == session.clerkSessionID {
                setNativeAuthSessionFence(nil)
            }
            sessionCache.save(session.authSession)
            state = .signedIn(session.authSession)
            #if DEBUG
            WanderDebugLog.remote.debug("clerk refresh signed_in user=\(WanderDebugLog.shortID(session.authSession.userID), privacy: .public)")
            #endif
        } catch is CancellationError {
            return
        } catch {
            guard generation == refreshGeneration else { return }
            if expectedSessionID != nil || nativeAuthSessionFence != nil {
                sessionCache.save(nil)
                state = .signedOut
                return
            }
            let message = "Could not verify your session. Your saved map is available offline."
            if let session = sessionCache.load() {
                state = .offline(session, message: message)
            } else {
                state = .unavailable("Could not verify your session. Check your connection and try again.")
            }
            #if DEBUG
            WanderDebugLog.remote.error("clerk refresh failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
        }
    }
    #endif

    func authenticate(
        with provider: NativeSocialAuthProvider,
        mode: NativeAuthMode
    ) async throws -> NativeSocialAuthResult {
        #if canImport(ClerkKit) && canImport(AuthenticationServices)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }

        setNativeAuthSessionFence(.blockUncorrelated)
        let result: TransferFlowResult
        do {
            switch (provider, mode) {
            case (.apple, .signIn):
                result = try await Clerk.shared.auth.signInWithApple(transferable: false)
            case (.apple, .signInOrUp):
                result = try await Clerk.shared.auth.signInWithApple()
            case (.apple, .signUp):
                result = try await Clerk.shared.auth.signUpWithApple()
            case (.google, .signIn):
                result = try await Clerk.shared.auth.signInWithOAuth(
                    provider: .google,
                    transferable: false
                )
            case (.google, .signInOrUp):
                result = try await Clerk.shared.auth.signInWithOAuth(provider: .google)
            case (.google, .signUp):
                result = try await Clerk.shared.auth.signUpWithOAuth(provider: .google)
            }

        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw AuthSessionError.cancelled
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw AuthSessionError.cancelled
        } catch is CancellationError {
            throw AuthSessionError.cancelled
        } catch {
            throw Self.authError(from: error)
        }

        let outcome: NativeAuthOutcome
        let completedSessionID: String?
        switch result {
        case .signIn(let signIn):
            if signIn.status == .complete {
                outcome = .completed
                completedSessionID = signIn.createdSessionId
            } else if mode == .signIn {
                outcome = .requiresExistingAccountVerification
                completedSessionID = nil
            } else {
                outcome = .requiresAdditionalVerification
                completedSessionID = nil
            }
        case .signUp(let signUp):
            if signUp.status == .complete {
                outcome = .completed
                completedSessionID = signUp.createdSessionId
            } else if mode == .signIn {
                outcome = .requiresExistingAccountVerification
                completedSessionID = nil
            } else {
                outcome = .requiresAdditionalVerification
                completedSessionID = nil
            }
        }

        guard outcome == .completed else {
            return NativeSocialAuthResult(outcome: outcome)
        }
        guard let completedSessionID else {
            throw AuthSessionError.sessionUnavailable
        }
        let adoption = try await adoptCompletedNativeAuthSession(
            expectedSessionID: completedSessionID
        )
        return NativeSocialAuthResult(
            outcome: .completed,
            sessionAdoption: adoption
        )
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    #if canImport(ClerkKit)
    /// A completed Clerk auth response can precede the active client session
    /// becoming observable. Retry only this post-completion adoption boundary,
    /// require the exact session Clerk created, and cap the entire operation;
    /// ordinary foreground refreshes remain single-shot.
    func adoptCompletedNativeAuthSession(
        expectedSessionID: String
    ) async throws -> NativeAuthSessionAdoption {
        guard pendingNativeAuthSessionID == nil else {
            throw AuthSessionError.sessionUnavailable
        }
        pendingNativeAuthSessionID = expectedSessionID
        // Keep this fence after a failed or cancelled attempt. A later generic
        // foreground refresh may accept only the session this Clerk result
        // created, never a different active account.
        setNativeAuthSessionFence(.require(expectedSessionID))
        defer { pendingNativeAuthSessionID = nil }

        let deadline = DispatchTime.now().uptimeNanoseconds
            &+ sessionAdoptionTimeoutNanoseconds
        await refreshSession(
            expectedSessionID: expectedSessionID,
            deadline: deadline
        )
        try Task.checkCancellation()
        if case .signedIn = state,
           resolveActiveSessionID() == expectedSessionID {
            return .immediate
        }

        for delay in sessionAdoptionRetryDelaysNanoseconds {
            let remainingBeforeSleep = remainingNanoseconds(until: deadline)
            guard remainingBeforeSleep > 0 else {
                throw AuthSessionError.sessionUnavailable
            }
            try await sessionAdoptionSleeper(min(delay, remainingBeforeSleep))
            try Task.checkCancellation()
            if case .signedIn = state,
               resolveActiveSessionID() == expectedSessionID {
                return .afterCompletionRetry
            }
            await refreshSession(
                expectedSessionID: expectedSessionID,
                deadline: deadline
            )
            try Task.checkCancellation()
            if case .signedIn = state,
               resolveActiveSessionID() == expectedSessionID {
                return .afterCompletionRetry
            }
        }

        throw AuthSessionError.sessionUnavailable
    }

    func shouldPublishSessionChange(observedState: AuthState) -> Bool {
        if pendingNativeAuthSessionID != nil {
            return false
        }
        if nativeAuthSessionFence != nil, observedState.isSignedIn {
            return false
        }
        if observedState.isSignedIn, !state.isSignedIn {
            // Session events are notifications, never proof sufficient to
            // elevate a signed-out client. Interactive and foreground paths
            // publish only after their authoritative refresh is validated.
            return false
        }
        return true
    }

    private func resolveAuthoritativeSession(within timeoutNanoseconds: UInt64) async throws -> ResolvedSession? {
        let (stream, continuation) = AsyncThrowingStream<TimedSessionResolution, Error>.makeStream()
        let sessionResolver = resolveAuthoritativeSession
        let resolverTask = Task { @MainActor in
            do {
                let session = try await sessionResolver()
                continuation.yield(.resolved(session))
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timeoutTask = Task {
            do {
                try await Task<Never, Never>.sleep(nanoseconds: timeoutNanoseconds)
                continuation.finish(throwing: SessionAdoptionTimeoutError())
            } catch {
                // The resolver or caller won the race.
            }
        }
        defer {
            resolverTask.cancel()
            timeoutTask.cancel()
        }

        var iterator = stream.makeAsyncIterator()
        guard let resolution = try await iterator.next() else {
            throw CancellationError()
        }
        switch resolution {
        case .resolved(let session):
            return session
        }
    }

    private func remainingNanoseconds(until deadline: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        return deadline > now ? deadline - now : 0
    }

    private func setNativeAuthSessionFence(_ fence: NativeAuthSessionFence?) {
        nativeAuthSessionFence = fence
        nativeAuthSessionFenceStore.save(fence)
    }

    private struct SessionAdoptionTimeoutError: Error {}

    private enum TimedSessionResolution: Sendable {
        case resolved(ResolvedSession?)
    }
    #endif

    func sendEmailCode(to emailAddress: String, mode: NativeAuthMode) async throws {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }

        do {
            setNativeAuthSessionFence(.blockUncorrelated)
            switch mode {
            case .signIn:
                let signIn = try await Clerk.shared.auth.signInWithEmailCode(
                    emailAddress: emailAddress
                )
                pendingEmailVerification = .signIn(signIn)
            case .signUp:
                var signUp = try await Clerk.shared.auth.signUp(
                    emailAddress: emailAddress,
                    legalAccepted: true
                )
                signUp = try await signUp.sendEmailCode()
                pendingEmailVerification = .signUp(signUp)
            case .signInOrUp:
                do {
                    let signIn = try await Clerk.shared.auth.signInWithEmailCode(
                        emailAddress: emailAddress
                    )
                    pendingEmailVerification = .signIn(signIn)
                } catch let error as ClerkAPIError where Self.accountNotFoundCodes.contains(error.code) {
                    var signUp = try await Clerk.shared.auth.signUp(
                        emailAddress: emailAddress,
                        legalAccepted: true
                    )
                    signUp = try await signUp.sendEmailCode()
                    pendingEmailVerification = .signUp(signUp)
                }
            }
        } catch {
            pendingEmailVerification = nil
            throw Self.authError(from: error)
        }
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func verifyEmailCode(_ code: String) async throws -> NativeAuthOutcome {
        #if canImport(ClerkKit)
        guard let pendingEmailVerification else {
            throw AuthSessionError.emailVerificationUnavailable
        }

        do {
            let outcome: NativeAuthOutcome
            let completedSessionID: String?
            switch pendingEmailVerification {
            case .signIn(let signIn):
                let updatedSignIn = try await signIn.verifyCode(code)
                self.pendingEmailVerification = .signIn(updatedSignIn)
                outcome = updatedSignIn.status == .complete
                    ? .completed
                    : .requiresAdditionalVerification
                completedSessionID = updatedSignIn.createdSessionId
            case .signUp(let signUp):
                let updatedSignUp = try await signUp.verifyEmailCode(code)
                self.pendingEmailVerification = .signUp(updatedSignUp)
                outcome = updatedSignUp.status == .complete
                    ? .completed
                    : .requiresAdditionalVerification
                completedSessionID = updatedSignUp.createdSessionId
            }

            guard outcome == .completed else { return outcome }
            self.pendingEmailVerification = nil
            guard let completedSessionID else {
                throw AuthSessionError.sessionUnavailable
            }
            _ = try await adoptCompletedNativeAuthSession(
                expectedSessionID: completedSessionID
            )
            return .completed
        } catch {
            throw Self.authError(from: error)
        }
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func authenticateWithPassword(
        emailAddress: String,
        password: String
    ) async throws -> NativeAuthOutcome {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }

        do {
            setNativeAuthSessionFence(.blockUncorrelated)
            let signIn = try await Clerk.shared.auth.signInWithPassword(
                identifier: emailAddress,
                password: password
            )
            guard signIn.status == .complete else {
                return .requiresAdditionalVerification
            }
            guard let completedSessionID = signIn.createdSessionId else {
                throw AuthSessionError.sessionUnavailable
            }
            _ = try await adoptCompletedNativeAuthSession(
                expectedSessionID: completedSessionID
            )
            return .completed
        } catch let error as ClerkAPIError where Self.invalidCredentialCodes.contains(error.code) {
            throw AuthSessionError.invalidCredentials
        } catch {
            throw Self.authError(from: error)
        }
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func resetPendingEmailVerification() {
        #if canImport(ClerkKit)
        pendingEmailVerification = nil
        #endif
    }

    func signOut() async throws {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }
        try await Clerk.shared.auth.signOut()
        setNativeAuthSessionFence(nil)
        sessionCache.save(nil)
        state = .signedOut
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func deleteAccount() async throws {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else { throw AuthSessionError.notConfigured }
        guard let user = Clerk.shared.user else { throw AuthSessionError.notSignedIn }
        _ = try await user.delete()
        setNativeAuthSessionFence(nil)
        sessionCache.save(nil)
        state = .signedOut
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func supabaseAccessToken() async throws -> String {
        try await fetchSupabaseAccessToken(forceRefresh: false)
    }

    /// The default Clerk token cache is ideal for ordinary requests. After a
    /// server explicitly rejects one, however, obtain a new claim set instead
    /// of replaying the cached token.
    func refreshSupabaseAccessToken() async throws -> String {
        try await fetchSupabaseAccessToken(forceRefresh: true)
    }

    private func fetchSupabaseAccessToken(forceRefresh: Bool) async throws -> String {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            #if DEBUG
            WanderDebugLog.remote.error("clerk supabase token skipped reason=missing_publishable_key")
            #endif
            throw AuthSessionError.notConfigured
        }
        guard let session = Clerk.shared.session,
              Self.isActiveSessionStatus(session.status),
              session.user != nil
        else {
            #if DEBUG
            WanderDebugLog.remote.error("clerk supabase token skipped reason=no_current_user")
            #endif
            throw AuthSessionError.notSignedIn
        }
        do {
            guard let token = try await Clerk.shared.auth.getToken(.init(skipCache: forceRefresh)) else {
                #if DEBUG
                WanderDebugLog.remote.error("clerk supabase token failed reason=nil_token")
                #endif
                throw AuthSessionError.tokenUnavailable
            }
            #if DEBUG
            WanderDebugLog.remote.debug("clerk supabase token succeeded")
            #endif
            return token
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("clerk supabase token failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)")
            #endif
            throw error
        }
        #else
        #if DEBUG
        WanderDebugLog.remote.error("clerk supabase token unavailable reason=clerkkit_not_linked")
        #endif
        throw AuthSessionError.notConfigured
        #endif
    }

    private func persistAuthoritativeState(_ state: AuthState) {
        switch state {
        case .signedIn(let session):
            sessionCache.save(session)
        case .signedOut:
            sessionCache.save(nil)
        case .loading, .offline, .unavailable:
            break
        }
    }

    #if canImport(ClerkKit)
    /// Clerk emits `sessionChanged` while `refreshClient()` is still resolving.
    /// Applying that observed state must not invalidate the refresh that caused
    /// the event; the completed refresh remains the authoritative result.
    func applyObservedClientState(_ state: AuthState) {
        persistAuthoritativeState(state)
        self.state = state
    }

    /// A terminal auth event is different from an observed client refresh: it
    /// must prevent an older in-flight refresh from restoring a removed session.
    func applyTerminalSignedOutState() {
        refreshGeneration &+= 1
        setNativeAuthSessionFence(nil)
        applyObservedClientState(.signedOut)
    }
    #endif

    #if canImport(ClerkKit)
    private static let accountNotFoundCodes: Set<String> = [
        "form_identifier_not_found",
        "invitation_account_not_exists",
    ]

    private static let emailAlreadyInUseCodes: Set<String> = [
        "form_identifier_exists",
        "form_param_value_already_exists",
    ]

    private static let invalidVerificationCodeCodes: Set<String> = [
        "form_code_incorrect",
        "verification_failed",
    ]

    private static let invalidCredentialCodes: Set<String> = [
        "form_identifier_not_found",
        "invitation_account_not_exists",
        "form_password_incorrect",
        "form_password_or_identifier_incorrect",
        "form_password_validation_failed",
        "no_password_set",
    ]

    private static func authError(from error: Error) -> Error {
        guard let clerkError = error as? ClerkAPIError else { return error }
        if accountNotFoundCodes.contains(clerkError.code) {
            return AuthSessionError.accountNotFound
        }
        if emailAlreadyInUseCodes.contains(clerkError.code) {
            return AuthSessionError.emailAlreadyInUse
        }
        if invalidVerificationCodeCodes.contains(clerkError.code) {
            return AuthSessionError.invalidVerificationCode
        }
        return error
    }

    private static func resolveCurrentSession() async throws -> ResolvedSession? {
        _ = try await Clerk.shared.refreshClient()
        guard let session = Clerk.shared.session,
              isActiveSessionStatus(session.status),
              let user = session.user
        else { return nil }
        return ResolvedSession(
            clerkSessionID: session.id,
            authSession: authSession(from: user)
        )
    }

    private static func currentClientState() -> AuthState {
        guard let session = Clerk.shared.session,
              isActiveSessionStatus(session.status),
              let user = session.user
        else { return .signedOut }
        return .signedIn(authSession(from: user))
    }

    static func isActiveSessionStatus(_ status: ClerkKit.Session.SessionStatus) -> Bool {
        status == .active
    }

    private static func authSession(from user: User) -> AuthSession {
        let name = [user.firstName, user.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return AuthSession(
            userID: resolvedUserID(
                clerkUserID: user.id,
                canonicalUserID: user.publicMetadata?[canonicalUserIDMetadataKey]?.stringValue
            ),
            displayName: name.isEmpty ? user.username : name,
            handle: user.username,
            email: user.primaryEmailAddress?.emailAddress,
            phoneNumber: user.primaryPhoneNumber?.phoneNumber
        )
    }
    #endif

    static func resolvedUserID(clerkUserID: String, canonicalUserID: String?) -> String {
        guard let canonicalUserID else { return clerkUserID }
        let trimmed = canonicalUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? clerkUserID : trimmed
    }
}
