import Foundation

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
                title: "Sign In To Sync This Place",
                message: "It Stays On This Phone Either Way. Sign In When You Want It Backed Up And Shared By Your Visibility Setting.",
                primaryAction: "Sign In",
                secondaryAction: "Keep It Here"
            )
        case .socialSave:
            AuthGateCopy(
                title: "Sign In To Save From People",
                message: "Social Saves Need An Account So \(AppBrand.displayName) Knows Whose Map Gets The Copy.",
                primaryAction: "Sign In",
                secondaryAction: "Keep Browsing"
            )
        case .socialActivity:
            AuthGateCopy(
                title: "Sign In To Join The Conversation",
                message: "Likes And Comments Need An Account So People Know They Came From You.",
                primaryAction: "Sign In",
                secondaryAction: "Keep Browsing"
            )
        case .followPeople:
            AuthGateCopy(
                title: "Sign In To Follow People",
                message: "Follows Shape Your Social Map And Need An Account.",
                primaryAction: "Sign In",
                secondaryAction: "Not Now"
            )
        case .manageBlocks:
            AuthGateCopy(
                title: "Sign In To Manage Blocks",
                message: "Blocks Apply Across Search, Profiles, And Maps, So They Need An Account.",
                primaryAction: "Sign In",
                secondaryAction: "Cancel"
            )
        case .reportContent:
            AuthGateCopy(
                title: "Sign In To Send A Report",
                message: "Reports Need An Account So Our Safety Team Can Investigate Abuse And Prevent Duplicate Reports.",
                primaryAction: "Sign In",
                secondaryAction: "Cancel"
            )
        case .manageNotifications:
            AuthGateCopy(
                title: "Sign In For Notifications",
                message: "Notification Settings Follow Your Account And Device.",
                primaryAction: "Sign In",
                secondaryAction: "Cancel"
            )
        case .syncPending:
            AuthGateCopy(
                title: "Sign In To Sync Pending Items",
                message: "Your Local Saves Are Safe Here. Sign In To Back Them Up When You're Ready.",
                primaryAction: "Sign In",
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

@MainActor
final class AuthSessionStore: ObservableObject, AuthSessionProviding {
    private struct InFlightSessionRefresh {
        let id: UUID
        let startingUserID: String?
        let task: Task<Void, Never>
    }

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
    private let analytics: AnalyticsClient
    private var sessionObservationTask: Task<Void, Never>?
    private var inFlightSessionRefresh: InFlightSessionRefresh?
    private var refreshGeneration = 0
    private var terminalAuthMutationID: UUID?
    private var isNativeAuthAttemptActive = false

    private var isTerminalAuthMutationInProgress: Bool {
        terminalAuthMutationID != nil
    }

    init(
        provider: AuthSessionProviding,
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.provider = provider
        self.analytics = analytics
        self.state = provider.state
        sessionObservationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            for await _ in provider.sessionChanges() {
                guard !Task.isCancelled else { return }
                // Clerk can publish a transient client snapshot while its
                // authoritative refresh is still in flight. Ignore those
                // notifications until the refresh reconciles `provider.state`.
                // Outside a refresh, treat stream values as notifications and
                // read current provider state so a buffered stale payload cannot
                // overwrite a newer authoritative result.
                guard let self else { return }
                // Interactive auth is synchronized explicitly only after its
                // provider has validated the exact completed session. This
                // must precede in-flight handling so a foreground refresh
                // cannot publish an unrelated account mid-attempt.
                guard !self.isNativeAuthAttemptActive else { continue }
                if let inFlight = self.inFlightSessionRefresh {
                    let observedState = provider.state
                    if let startingUserID = inFlight.startingUserID,
                       case .signedIn(let observedSession) = observedState,
                       observedSession.userID != startingUserID {
                        // A different authenticated account is not a transient
                        // snapshot of the refresh we started. Invalidate that
                        // work, expose the switch without validating it, then
                        // run one authoritative refresh for the new account.
                        self.refreshGeneration &+= 1
                        inFlight.task.cancel()
                        self.inFlightSessionRefresh = nil
                        self.synchronizeState(observedState, validatesSession: false)
                        _ = self.startSessionRefreshIfNeeded()
                    }
                    continue
                }
                guard !self.isTerminalAuthMutationInProgress else { continue }
                let observedState = provider.state
                let validatedUserID = self.isSessionValidated
                    ? self.state.session?.userID
                    : nil
                self.synchronizeState(
                    observedState,
                    validatesSession: validatedUserID != nil
                        && observedState.session?.userID == validatedUserID
                )
            }
        }
    }

    deinit {
        sessionObservationTask?.cancel()
        inFlightSessionRefresh?.task.cancel()
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
        guard var refresh = startSessionRefreshIfNeeded() else { return }
        while true {
            await refresh.task.value
            guard !Task.isCancelled else { return }
            guard let replacement = inFlightSessionRefresh,
                  replacement.id != refresh.id
            else { return }
            // An observed account switch can invalidate the task this caller
            // originally joined. Follow the replacement single-flight refresh
            // so launch/admission waiters cannot return with the new account
            // still unvalidated.
            refresh = replacement
        }
    }

    @discardableResult
    private func startSessionRefreshIfNeeded() -> InFlightSessionRefresh? {
        guard !isTerminalAuthMutationInProgress,
              !isNativeAuthAttemptActive
        else { return nil }
        if let inFlightSessionRefresh {
            return inFlightSessionRefresh
        }

        beginSessionValidation()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let refreshID = UUID()
        let startingUserID = state.session?.userID
        let provider = self.provider
        #if DEBUG
        let startingStateSummary = state.debugSummary
        #endif
        let task = Task { @MainActor [weak self] in
            #if DEBUG
            WanderDebugLog.remote.debug("auth store refresh start current_state=\(startingStateSummary, privacy: .public)")
            #endif
            await provider.refreshSession()
            guard !Task.isCancelled,
                  let self,
                  generation == self.refreshGeneration,
                  !self.isTerminalAuthMutationInProgress,
                  !self.isNativeAuthAttemptActive,
                  self.inFlightSessionRefresh?.id == refreshID
            else { return }
            // Remove the slot before publishing the authoritative state. There
            // is no actor suspension between these operations, so a buffered
            // observation can only run afterward and will read provider.state.
            self.inFlightSessionRefresh = nil
            self.synchronizeState(provider.state)
            #if DEBUG
            WanderDebugLog.remote.debug("auth store refresh finished new_state=\(self.state.debugSummary, privacy: .public)")
            #endif
        }
        let inFlight = InFlightSessionRefresh(
            id: refreshID,
            startingUserID: startingUserID,
            task: task
        )
        inFlightSessionRefresh = inFlight
        return inFlight
    }

    /// Joins the foreground validation already in flight, or starts the same
    /// single-flight refresh when an authenticated action wins the scheduling
    /// race. No token is exposed until the expected account is validated.
    func ensureSessionValidated(for expectedUserID: String) async throws {
        if inFlightSessionRefresh != nil {
            await refreshSession()
            try Task.checkCancellation()
        }
        guard !isTerminalAuthMutationInProgress else {
            throw AuthSessionError.notSignedIn
        }
        if isSessionValidated,
           case .signedIn(let session) = state,
           session.userID == expectedUserID {
            return
        }
        guard state.session?.userID == expectedUserID else {
            throw AuthSessionError.notSignedIn
        }

        await refreshSession()
        try Task.checkCancellation()
        guard !isTerminalAuthMutationInProgress,
              isSessionValidated,
              case .signedIn(let session) = state,
              session.userID == expectedUserID
        else {
            throw AuthSessionError.notSignedIn
        }
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
            beginNativeAuthAttempt()
            isPresentingNativeAuth = true
        } else {
            nativeAuthDidDismiss()
            state = .unavailable("Clerk Is Not Configured For This Build.")
        }
    }

    func nativeAuthDidDismiss() {
        isNativeAuthAttemptActive = false
        isPresentingNativeAuth = false
        resetNativeAuthForm()
    }

    @discardableResult
    func authenticate(with socialProvider: NativeSocialAuthProvider) async -> NativeAuthOutcome? {
        let authMode = activeNativeAuthMode
        guard provider.canPresentNativeAuth else {
            recordNativeSocialAuthResult(
                provider: socialProvider,
                mode: authMode,
                result: "failed",
                sessionAdoption: nil,
                failureCategory: "not_configured"
            )
            nativeAuthError = "Sign In Is Not Available In This Build."
            return nil
        }

        nativeAuthError = nil
        beginNativeAuthAttempt()
        activeSocialAuthProvider = socialProvider
        defer { activeSocialAuthProvider = nil }

        do {
            let result = try await provider.authenticate(
                with: socialProvider,
                mode: authMode
            )
            let outcome = result.outcome
            if outcome == .completed {
                synchronizeState(provider.state)
                guard state.isSignedIn else {
                    recordNativeSocialAuthResult(
                        provider: socialProvider,
                        mode: authMode,
                        result: "failed",
                        sessionAdoption: result.sessionAdoption,
                        failureCategory: "store_session_missing"
                    )
                    nativeAuthError = "\(socialProvider.displayName) Sign-In Didn’t Finish. Try Again Or Use Another Method."
                    return nil
                }
            } else {
                nativeAuthError = incompleteSocialAuthMessage(
                    provider: socialProvider,
                    outcome: outcome
                )
            }
            recordNativeSocialAuthResult(
                provider: socialProvider,
                mode: authMode,
                result: Self.analyticsResult(for: outcome),
                sessionAdoption: result.sessionAdoption,
                failureCategory: nil
            )
            return outcome
        } catch AuthSessionError.cancelled, is CancellationError {
            recordNativeSocialAuthResult(
                provider: socialProvider,
                mode: authMode,
                result: "cancelled",
                sessionAdoption: nil,
                failureCategory: nil
            )
            return nil
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "social sign-in failed provider=\(socialProvider.rawValue, privacy: .public) error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            recordNativeSocialAuthResult(
                provider: socialProvider,
                mode: authMode,
                result: "failed",
                sessionAdoption: nil,
                failureCategory: Self.analyticsFailureCategory(for: error)
            )
            nativeAuthError = "\(socialProvider.displayName) Sign-In Didn’t Finish. Try Again Or Use Another Method."
            return nil
        }
    }

    func sendEmailCode(to rawEmailAddress: String) async -> Bool {
        guard provider.canPresentNativeAuth else {
            nativeAuthError = "Email Sign-In Is Not Available In This Build."
            return false
        }

        let emailAddress = rawEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmailAddress(emailAddress) else {
            nativeAuthError = "Enter A Valid Email Address."
            return false
        }

        nativeAuthError = nil
        beginNativeAuthAttempt()
        isSendingEmailCode = true
        defer { isSendingEmailCode = false }

        do {
            try await provider.sendEmailCode(to: emailAddress, mode: activeNativeAuthMode)
            emailVerificationAddress = emailAddress
            return true
        } catch AuthSessionError.accountNotFound {
            nativeAuthError = "We Couldn’t Find An Account For That Email. Try Apple Or Google, Or Create An Account."
        } catch AuthSessionError.emailAlreadyInUse {
            nativeAuthError = "That Email Already Has An Account. Go Back And Log In Instead."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "email code send failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            nativeAuthError = "We Couldn’t Send A Code. Check The Email And Try Again."
        }
        return false
    }

    @discardableResult
    func verifyEmailCode(_ rawCode: String) async -> NativeAuthOutcome? {
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else {
            nativeAuthError = "Enter The Code From Your Email."
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
                    nativeAuthError = "Email Sign-In Didn’t Finish. Try Again."
                    return nil
                }
            } else {
                nativeAuthError = "This Account Needs Another Verification Step. Try Apple Or Google, Or Contact Support."
            }
            return outcome
        } catch AuthSessionError.invalidVerificationCode {
            nativeAuthError = "That Code Isn’t Right. Check The Email And Try Again."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error(
                "email code verification failed error=\(WanderDebugLog.errorSummary(error), privacy: .public)"
            )
            #endif
            nativeAuthError = "We Couldn’t Verify That Code. Try Again."
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
            nativeAuthError = "Password Sign-In Is Not Available In This Build."
            return nil
        }

        let emailAddress = rawEmailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeEmailAddress(emailAddress) else {
            nativeAuthError = "Enter A Valid Email Address."
            return nil
        }
        guard !rawPassword.isEmpty else {
            nativeAuthError = "Enter Your Password."
            return nil
        }

        nativeAuthError = nil
        beginNativeAuthAttempt()
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
                    nativeAuthError = "Password Sign-In Didn’t Finish. Try Again Or Use Another Method."
                    return nil
                }
            } else {
                nativeAuthError = "This Account Needs Another Verification Step. Use Email Or Another Sign-In Method."
            }
            return outcome
        } catch AuthSessionError.invalidCredentials, AuthSessionError.accountNotFound {
            nativeAuthError = "Email Or Password Didn’t Match."
        } catch {
            #if DEBUG
            WanderDebugLog.remote.error("password sign-in failed")
            #endif
            nativeAuthError = "Password Sign-In Didn’t Finish. Check Your Connection And Try Again."
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
        guard let mutationID = beginTerminalAuthMutation() else {
            throw AuthSessionError.sessionUnavailable
        }
        nativeAuthDidDismiss()
        isSigningOut = true
        signOutError = nil
        defer {
            isSigningOut = false
            finishTerminalAuthMutation(mutationID)
        }

        do {
            try await provider.signOut()
            synchronizeStateFromProvider()
        } catch {
            await provider.refreshSession()
            synchronizeStateFromProvider()
            signOutError = "Could Not Sign Out. Try Again."
            throw error
        }
    }

    func deleteAccount() async throws {
        guard let mutationID = beginTerminalAuthMutation() else {
            throw AuthSessionError.sessionUnavailable
        }
        defer { finishTerminalAuthMutation(mutationID) }
        nativeAuthDidDismiss()
        do {
            try await provider.deleteAccount()
            await provider.refreshSession()
            synchronizeStateFromProvider()
        } catch {
            await provider.refreshSession()
            synchronizeStateFromProvider()
            throw error
        }
    }

    private func synchronizeStateFromProvider() {
        synchronizeState(provider.state)
    }

    private func beginTerminalAuthMutation() -> UUID? {
        guard terminalAuthMutationID == nil else { return nil }
        let mutationID = UUID()
        terminalAuthMutationID = mutationID
        refreshGeneration &+= 1
        inFlightSessionRefresh?.task.cancel()
        inFlightSessionRefresh = nil
        beginSessionValidation()
        return mutationID
    }

    private func beginNativeAuthAttempt() {
        guard !isNativeAuthAttemptActive else { return }
        isNativeAuthAttemptActive = true
        refreshGeneration &+= 1
        inFlightSessionRefresh?.task.cancel()
        inFlightSessionRefresh = nil
        beginSessionValidation()
    }

    private func finishTerminalAuthMutation(_ mutationID: UUID) {
        guard terminalAuthMutationID == mutationID else { return }
        terminalAuthMutationID = nil
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
            return "We Couldn’t Match That \(provider.displayName) Login To An Existing Account. Sign In With The Method You Originally Used. Your Saved Places And People Are Still There."
        case .requiresAdditionalVerification:
            return "This \(provider.displayName) Account Needs Another Verification Step. Try Email Or Your Other Sign-In Method."
        }
    }

    private func recordNativeSocialAuthResult(
        provider: NativeSocialAuthProvider,
        mode: NativeAuthMode,
        result: String,
        sessionAdoption: NativeAuthSessionAdoption?,
        failureCategory: String?
    ) {
        var properties = [
            "provider": provider.rawValue,
            "mode": Self.analyticsMode(for: mode),
            "result": result,
            "session_adoption": sessionAdoption?.rawValue ?? "none"
        ]
        if let failureCategory {
            properties["failure_category"] = failureCategory
        }
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.nativeSocialAuthResult,
                properties: properties
            )
        )
    }

    private static func analyticsMode(for mode: NativeAuthMode) -> String {
        switch mode {
        case .signInOrUp: "sign_in_or_up"
        case .signIn: "sign_in"
        case .signUp: "sign_up"
        }
    }

    private static func analyticsResult(for outcome: NativeAuthOutcome) -> String {
        switch outcome {
        case .completed: "completed"
        case .requiresExistingAccountVerification: "requires_existing_account_verification"
        case .requiresAdditionalVerification: "requires_additional_verification"
        }
    }

    private static func analyticsFailureCategory(for error: Error) -> String {
        guard let authError = error as? AuthSessionError else {
            return "provider_error"
        }
        return switch authError {
        case .notSignedIn: "not_signed_in"
        case .notConfigured: "not_configured"
        case .tokenUnavailable: "token_unavailable"
        case .cancelled: "cancelled"
        case .sessionUnavailable: "session_unavailable"
        case .accountNotFound: "account_not_found"
        case .emailAlreadyInUse: "email_already_in_use"
        case .invalidVerificationCode: "invalid_verification_code"
        case .emailVerificationUnavailable: "email_verification_unavailable"
        case .invalidCredentials: "invalid_credentials"
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

    private func synchronizeState(
        _ state: AuthState,
        validatesSession: Bool = true
    ) {
        self.state = state
        if case .signedIn = state {
            isSessionValidated = validatesSession
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
    private let nativeAuthSessionAdoption: NativeAuthSessionAdoption?
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
    private(set) var sessionChangesRequestCount = 0

    init(
        state: AuthState = .signedOut,
        canPresentNativeAuth: Bool = false,
        token: String? = nil,
        signOutError: Error? = nil,
        nativeAuthOutcome: NativeAuthOutcome = .completed,
        nativeAuthSession: AuthSession? = nil,
        nativeAuthFailure: Error? = nil,
        nativeAuthSessionAdoption: NativeAuthSessionAdoption? = nil,
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
        self.nativeAuthSessionAdoption = nativeAuthSessionAdoption
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

    func sessionChanges() -> AsyncStream<AuthState> {
        sessionChangesRequestCount += 1
        return sessionChangeStream
    }

    func refreshSession() async {}

    func authenticate(
        with provider: NativeSocialAuthProvider,
        mode: NativeAuthMode
    ) async throws -> NativeSocialAuthResult {
        requestedSocialAuth.append(.init(provider: provider, mode: mode))
        if let nativeAuthFailure {
            throw nativeAuthFailure
        }
        if nativeAuthOutcome == .completed, let nativeAuthSession {
            state = .signedIn(nativeAuthSession)
            sessionChangeContinuation.yield(state)
        }
        return NativeSocialAuthResult(
            outcome: nativeAuthOutcome,
            sessionAdoption: nativeAuthSessionAdoption
        )
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
