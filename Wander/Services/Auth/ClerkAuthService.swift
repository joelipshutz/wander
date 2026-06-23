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

    func refreshSession() async {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            state = .unavailable("Missing Clerk publishable key.")
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
                    email: user.primaryEmailAddress?.emailAddress
                )
            )
        } else {
            state = .signedOut
        }
        #else
        state = .unavailable("ClerkKit is not linked.")
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

    func supabaseAccessToken() async throws -> String {
        #if canImport(ClerkKit)
        guard configuration.isClerkConfigured else {
            throw AuthSessionError.notConfigured
        }
        guard Clerk.shared.user != nil else {
            throw AuthSessionError.notSignedIn
        }
        guard let token = try await Clerk.shared.auth.getToken() else {
            throw AuthSessionError.tokenUnavailable
        }
        return token
        #else
        throw AuthSessionError.notConfigured
        #endif
    }
}
