import SwiftUI

@MainActor
final class ClipStore: ObservableObject {
    @Published private(set) var route: AppClipRoute?
    @Published private(set) var preview: ClipPreview?
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    @Published var error: String?
    @Published var success: String?
    @Published var showAuth = false
    @Published var showProfile = false
    @Published var emailSent = false
    @Published var name = ""
    @Published var handle = ""
    @Published private(set) var signedIn = false
    @Published private(set) var savedIDs: Set<String> = []
    @Published private(set) var joined = false
    private let auth: any AuthSessionProviding
    private let service: any ClipServing
    private let analytics: ClipAnalytics
    private var visibleUserID: String?
    private var pending: ClipAction?
    private var pendingUserID: String?
    private var generation = 0
    private var loadTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var confirmedUserID: String?

    init(auth: any AuthSessionProviding, service: any ClipServing,
         analytics: ClipAnalytics = .init(client: NoopAnalyticsClient())) {
        self.auth = auth; self.service = service; self.analytics = analytics
    }

    func open(_ url: URL) {
        generation += 1
        loadTask?.cancel(); actionTask?.cancel()
        pending = nil; pendingUserID = nil; showAuth = false; showProfile = false
        auth.resetPendingEmailVerification(); emailSent = false
        route = AppClipRoute(url: url); preview = nil; error = nil; success = nil
        savedIDs = []; joined = false; isWorking = false; isLoading = false
        guard let route else { error = "This link can't be opened in Astir."; return }
        analytics.opened(route.kind)
        reload()
    }

    func reload() {
        guard let route else { return }
        loadTask?.cancel()
        let expected = generation
        isLoading = true; error = nil; preview = nil
        loadTask = Task {
            await auth.refreshSession()
            guard expected == generation, !Task.isCancelled else { return }
            signedIn = auth.state.isSignedIn
            updateIdentity()
            let expectedUserID = visibleUserID
            do {
                let value = try await service.preview(route, authenticated: signedIn)
                guard expected == generation, expectedUserID == auth.state.session?.userID, !Task.isCancelled else { return }
                preview = value
            } catch {
                guard expected == generation, !Task.isCancelled else { return }
                self.error = message(error)
            }
            isLoading = false
        }
    }

    func perform(_ action: ClipAction) {
        guard route != nil, !isWorking else { return }
        if action == .join, route?.kind != .invite { return }
        if case .save(let place) = action, preview?.places.contains(where: { $0.id == place.id }) != true { return }
        pending = action; pendingUserID = auth.state.session?.userID; error = nil; success = nil
        if !signedIn { showAuth = true; return }
        resume()
    }

    /// Revoked or switched sessions must not leave the previous account's
    /// authorized list/map on screen or resume its pending write.
    func observeSessionChanges() async {
        for await state in auth.sessionChanges() {
            guard !Task.isCancelled else { return }
            if state == .loading { continue }
            if let visibleUserID, visibleUserID != state.session?.userID {
                clearAccountState()
                reload()
            }
        }
    }

    func refreshOnForeground() {
        guard !isWorking, !showAuth, !showProfile else { return }
        reload()
    }

    func signOut() {
        guard !isWorking else { return }
        clearAccountState()
        work {
            try await self.auth.signOut()
            self.signedIn = false
            self.reload()
        }
    }

    private func clearAccountState() {
        generation += 1
        loadTask?.cancel(); actionTask?.cancel()
        preview = nil; pending = nil; pendingUserID = nil; confirmedUserID = nil; visibleUserID = nil
        signedIn = false; savedIDs = []; joined = false; success = nil; error = nil
        showAuth = false; showProfile = false; isWorking = false; isLoading = false
        name = ""; handle = ""; emailSent = false
        auth.resetPendingEmailVerification()
        AppClipHandoff.clear()
        analytics.client.resetIdentity()
    }

    private func updateIdentity() {
        let userID = auth.state.session?.userID
        if visibleUserID != userID {
            savedIDs = []; joined = false; success = nil; confirmedUserID = nil
            analytics.client.resetIdentity()
            if let userID { analytics.client.identify(userID: userID) }
        }
        visibleUserID = userID
    }

    func authenticate(_ provider: NativeSocialAuthProvider, mode: NativeAuthMode) {
        work {
            let outcome = try await self.auth.authenticate(with: provider, mode: mode)
            try Task.checkCancellation()
            guard outcome.outcome == .completed else { throw ClipError.verification }
            self.authenticated()
        }
    }

    func sendEmail(_ value: String, mode: NativeAuthMode) {
        work {
            try await self.auth.sendEmailCode(to: value.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode)
            try Task.checkCancellation()
            self.emailSent = true
        }
    }

    func verifyEmail(_ code: String) {
        work {
            guard try await self.auth.verifyEmailCode(code.trimmingCharacters(in: .whitespacesAndNewlines)) == .completed else { throw ClipError.verification }
            try Task.checkCancellation()
            self.authenticated()
        }
    }

    func signIn(email: String, password: String) {
        work {
            let outcome = try await self.auth.authenticateWithPassword(
                emailAddress: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            try Task.checkCancellation()
            if outcome == .completed {
                self.authenticated()
            } else {
                try await self.auth.sendPasswordVerificationCode()
                try Task.checkCancellation()
                self.emailSent = true
            }
        }
    }

    func cancelAuth() {
        guard !isWorking else { return }
        showAuth = false; showProfile = false; pending = nil; pendingUserID = nil
        auth.resetPendingEmailVerification(); emailSent = false; error = nil
    }

    func finishProfile() {
        work {
            guard self.pendingUserID == self.auth.state.session?.userID, self.pendingUserID != nil else { throw ClipError.signIn }
            let profile = try await self.service.updateProfile(name: self.name, handle: self.handle)
            try Task.checkCancellation()
            guard profile.id == self.auth.state.session?.userID else { throw ClipError.signIn }
            self.confirmedUserID = profile.id
            self.showProfile = false
            try await self.execute(profile: profile)
        }
    }

    /// A Keychain-restored session is still validated by Clerk before any write.
    private func authenticated() {
        signedIn = auth.state.isSignedIn
        if signedIn {
            updateIdentity()
            if pendingUserID == nil { pendingUserID = auth.state.session?.userID }
            analytics.authenticated()
            showAuth = false; emailSent = false
        }
    }

    func resumeAfterAuth() {
        if signedIn, pending != nil, !isWorking { resume() }
    }

    private func resume() {
        work {
            let expectedUserID = self.auth.state.session?.userID
            await self.auth.refreshSession()
            try Task.checkCancellation()
            guard self.auth.state.isSignedIn,
                  expectedUserID == self.auth.state.session?.userID, expectedUserID == self.pendingUserID else { throw ClipError.signIn }
            if self.pending == .viewProtected {
                self.pending = nil
                self.reload()
                return
            }
            let profile = try await self.service.profile()
            try Task.checkCancellation()
            guard let profile, profile.onboardedAt != nil || self.confirmedUserID == profile.id else {
                self.name = profile?.displayName ?? self.auth.state.session?.displayName ?? ""
                self.handle = profile?.handle ?? self.auth.state.session?.handle ?? ""
                self.showProfile = true
                return
            }
            try await self.execute(profile: profile)
        }
    }

    private func execute(profile: ClipProfile) async throws {
        try Task.checkCancellation()
        guard let route, profile.id == auth.state.session?.userID, profile.id == pendingUserID, let action = pending else { throw ClipError.signIn }
        let expected = generation
        switch action {
        case .save(let place):
            let created = try await service.save(place)
            guard expected == generation, !Task.isCancelled else { return }
            savedIDs.insert(place.id)
            success = created ? "Saved to your Wanna map" : "Already on your map"
            if created { analytics.saved() }
        case .join:
            guard !profile.isPrivate else { throw ClipError.privateProfile }
            let listID = try await service.join(route)
            guard expected == generation, !Task.isCancelled else { return }
            joined = true; success = "You're on the list"
            analytics.joined()
            pending = nil
            if let url = WanderDeepLinkRoute.sharedList(listID: listID).url,
               let destination = AppClipRoute(url: url) {
                self.route = destination
                try? AppClipHandoff.save(route: destination, userID: profile.id)
                preview = nil
                do {
                    let value = try await service.preview(destination, authenticated: true)
                    guard expected == generation, !Task.isCancelled else { return }
                    preview = value
                } catch {
                    guard expected == generation, !Task.isCancelled else { return }
                    self.error = "Couldn't load the list. Try again."
                }
            }
        case .viewProtected: break
        }
        pending = nil
        // The server-confirmed action survives installation. Handoff failure
        // must not turn a committed save into an apparent failed save.
        try? AppClipHandoff.save(route: self.route ?? route, userID: profile.id)
    }

    func prepareInstall() -> Bool {
        guard let route else { return false }
        do { try AppClipHandoff.save(route: route, userID: auth.state.session?.userID); return true }
        catch { self.error = "Couldn't keep this link for the full app. Try again."; return false }
    }

    private func work(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true; error = nil
        let expected = generation
        actionTask = Task {
            do { try await operation() }
            catch {
                guard expected == generation, !Task.isCancelled else { return }
                if error as? AuthSessionError != .cancelled { self.error = message(error) }
            }
            guard expected == generation, !Task.isCancelled else { return }
            isWorking = false
            // Authentication resumes from the native sheet's onDismiss. Starting
            // profile setup here races the authentication sheet's dismissal.
        }
    }

    private func message(_ error: Error) -> String {
        if let error = error as? ClipError { return error.message }
        if let error = error as? AuthSessionError {
            switch error {
            case .accountNotFound: return "No account found. Choose Create account to get started."
            case .emailAlreadyInUse: return "That email already has an account. Choose Sign in."
            case .invalidVerificationCode: return "That code didn't work. Check it and try again."
            case .invalidCredentials: return "Check your email and password, then try again."
            default: return "Couldn't finish signing in. Try your original sign-in method."
            }
        }
        return ClipError.connection.message
    }
}
