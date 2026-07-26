import Foundation
#if canImport(ClerkKit)
import ClerkKit
#endif

@MainActor
final class ClerkAuthService: AuthSessionProviding {
    private(set) var state: AuthState = .signedOut
    private let configuration: WanderBackendConfiguration

    #if canImport(ClerkKit)
    init(
        configuration: WanderBackendConfiguration,
        configureClerk: (String) -> String = { Clerk.configure(publishableKey: $0).publishableKey }
    ) {
        self.configuration = configuration

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
    init(configuration: WanderBackendConfiguration) {
        self.configuration = configuration

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

    func sessionChanges() -> AsyncStream<Void> {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }

        let events = Clerk.shared.auth.events
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .signInCompleted, .signUpCompleted, .signedOut, .accountDeleted, .sessionChanged:
                        continuation.yield()
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
        guard configuration.isClerkConfigured else {
            state = .unavailable("Missing Clerk publishable key.")
            #if DEBUG
            WanderDebugLog.remote.error("clerk refresh skipped reason=missing_publishable_key")
            #endif
            return
        }

        if let user = Clerk.shared.user {
            let name = [user.firstName, user.lastName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            state = .signedIn(
                AuthSession(
                    userID: user.id,
                    displayName: name.isEmpty ? user.username : name,
                    handle: user.username,
                    email: user.primaryEmailAddress?.emailAddress,
                    phoneNumber: user.primaryPhoneNumber?.phoneNumber
                )
            )
            #if DEBUG
            WanderDebugLog.remote.debug("clerk refresh signed_in user=\(WanderDebugLog.shortID(user.id), privacy: .public)")
            #endif
        } else {
            state = .signedOut
            #if DEBUG
            WanderDebugLog.remote.debug("clerk refresh signed_out")
            #endif
        }
        #else
        state = .unavailable("ClerkKit is not linked.")
        #if DEBUG
        WanderDebugLog.remote.error("clerk refresh unavailable reason=clerkkit_not_linked")
        #endif
        #endif
    }

    func signOut() async throws {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }
        try await Clerk.shared.auth.signOut()
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
        guard Clerk.shared.user != nil else {
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
}
