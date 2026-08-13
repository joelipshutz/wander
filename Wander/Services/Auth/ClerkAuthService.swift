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

    #if canImport(ClerkKit)
    typealias SessionResolver = @MainActor () async throws -> AuthSession?
    private let resolveAuthoritativeSession: SessionResolver
    private var refreshGeneration = 0

    init(
        configuration: WanderBackendConfiguration,
        resolveSession: @escaping SessionResolver = ClerkAuthService.resolveCurrentSession,
        sessionCache: AuthSessionCache = .live,
        configureClerk: (String) -> String = { Clerk.configure(publishableKey: $0).publishableKey }
    ) {
        self.configuration = configuration
        self.resolveAuthoritativeSession = resolveSession
        self.sessionCache = sessionCache

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
                    case .signInCompleted, .signUpCompleted, .signedOut, .accountDeleted, .sessionChanged:
                        guard let self else { return }
                        self.refreshGeneration &+= 1
                        let state = Self.currentClientState()
                        self.persistAuthoritativeState(state)
                        self.state = state
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
            let resolvedSession = try await resolveAuthoritativeSession()
            guard !Task.isCancelled, generation == refreshGeneration else { return }
            guard let session = resolvedSession else {
                sessionCache.save(nil)
                state = .signedOut
                #if DEBUG
                WanderDebugLog.remote.debug("clerk refresh signed_out")
                #endif
                return
            }
            sessionCache.save(session)
            state = .signedIn(session)
            #if DEBUG
            WanderDebugLog.remote.debug("clerk refresh signed_in user=\(WanderDebugLog.shortID(session.userID), privacy: .public)")
            #endif
        } catch is CancellationError {
            return
        } catch {
            guard generation == refreshGeneration else { return }
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
        #else
        state = .unavailable("ClerkKit is not linked.")
        #if DEBUG
        WanderDebugLog.remote.error("clerk refresh unavailable reason=clerkkit_not_linked")
        #endif
        #endif
    }

    func signInWithApple(mode: NativeAuthMode) async throws -> NativeAppleAuthOutcome {
        #if canImport(ClerkKit) && canImport(AuthenticationServices)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }

        do {
            let result: TransferFlowResult
            switch mode {
            case .signInOrUp:
                result = try await Clerk.shared.auth.signInWithApple()
            case .signIn:
                result = try await Clerk.shared.auth.signInWithApple(transferable: false)
            case .signUp:
                result = try await Clerk.shared.auth.signUpWithApple()
            }

            let outcome: NativeAppleAuthOutcome
            switch result {
            case .signIn(let signIn):
                outcome = signIn.status == .complete ? .completed : .requiresClerkContinuation
            case .signUp(let signUp):
                outcome = signUp.status == .complete ? .completed : .requiresClerkContinuation
            }

            guard outcome == .completed else { return outcome }
            await refreshSession()
            guard case .signedIn = state else {
                throw AuthSessionError.appleSessionUnavailable
            }
            return .completed
        } catch let error as ASAuthorizationError where error.code == .canceled {
            throw AuthSessionError.cancelled
        } catch is CancellationError {
            throw AuthSessionError.cancelled
        }
        #else
        throw AuthSessionError.notConfigured
        #endif
    }

    func signOut() async throws {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }
        try await Clerk.shared.auth.signOut()
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
    private static func resolveCurrentSession() async throws -> AuthSession? {
        _ = try await Clerk.shared.refreshClient()
        guard let session = Clerk.shared.session,
              isActiveSessionStatus(session.status),
              let user = session.user
        else { return nil }
        return authSession(from: user)
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
            userID: user.id,
            displayName: name.isEmpty ? user.username : name,
            handle: user.username,
            email: user.primaryEmailAddress?.emailAddress,
            phoneNumber: user.primaryPhoneNumber?.phoneNumber
        )
    }
    #endif
}
