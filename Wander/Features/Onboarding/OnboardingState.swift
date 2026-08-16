import Foundation

enum OnboardingStep: String, CaseIterable, Codable, Equatable {
    case identity
    case location
    case contacts
    case friends
    case notifications

    var next: OnboardingStep? {
        guard let index = Self.allCases.firstIndex(of: self) else { return nil }
        let nextIndex = Self.allCases.index(after: index)
        return nextIndex < Self.allCases.endIndex ? Self.allCases[nextIndex] : nil
    }
}

struct OnboardingLocalState: Codable, Equatable {
    var nextStep: OnboardingStep
    var isComplete: Bool
    var needsServerCompletion: Bool
    var isFirstVisitWalkthroughEligible: Bool? = nil
    var firstVisitWalkthroughEnrollmentGeneration: Int? = nil

    static let fresh = OnboardingLocalState(
        nextStep: .identity,
        isComplete: false,
        needsServerCompletion: false,
        isFirstVisitWalkthroughEligible: nil,
        firstVisitWalkthroughEnrollmentGeneration: nil
    )

    var shouldEnableFirstVisitWalkthrough: Bool {
        FirstVisitWalkthroughEligibilityPolicy.isEnrolled(
            isPersistedEligible: isFirstVisitWalkthroughEligible,
            enrollmentGeneration: firstVisitWalkthroughEnrollmentGeneration
        )
    }
}

enum FirstVisitWalkthroughEligibilityPolicy {
    /// A generation is written only by the current account-onboarding completion
    /// path. Older boolean-only records therefore fail closed instead of
    /// re-enrolling established accounts after an app update.
    static let currentEnrollmentGeneration = 1

    static func isEnrolled(
        isPersistedEligible: Bool?,
        enrollmentGeneration: Int?
    ) -> Bool {
        isPersistedEligible == true
            && enrollmentGeneration == currentEnrollmentGeneration
    }

    static func shouldRequestPersistedEligibilityRetirement(
        isUsingLiveData: Bool,
        resolvedAccountOverride: Bool?
    ) -> Bool {
        isUsingLiveData && resolvedAccountOverride == false
    }

    static func isAwaitingFeatureFlagResolution(
        isEnrolled: Bool,
        isUsingLiveData: Bool,
        resolutionIsPending: Bool
    ) -> Bool {
        isEnrolled && isUsingLiveData && resolutionIsPending
    }
}

/// Keeps a first-visit enrollment bound to the account that produced it.
/// `WanderRootView` can remain mounted while authentication changes, so a
/// bare eligibility Boolean is not sufficient to prevent cross-account NUX.
struct FirstVisitWalkthroughEligibilityContext: Equatable {
    let sourceUserID: String?
    let isEligible: Bool

    func applies(to userID: String?) -> Bool {
        guard let sourceUserID, let userID else { return false }
        return isEligible && sourceUserID == userID
    }

    func shouldRetire(
        for userID: String?,
        whenRetirementIsRequested isRequested: Bool
    ) -> Bool {
        isRequested && applies(to: userID)
    }
}

@MainActor
final class OnboardingCompletionStore {
    private let defaults: UserDefaults
    private let keyPrefix = "recme.onboarding.v1."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(for userID: String) -> OnboardingLocalState {
        guard let data = defaults.data(forKey: key(for: userID)),
              let decoded = try? JSONDecoder().decode(OnboardingLocalState.self, from: data)
        else { return .fresh }
        return decoded
    }

    func setNextStep(_ step: OnboardingStep, for userID: String) {
        var value = state(for: userID)
        value.nextStep = step
        save(value, for: userID)
    }

    func markComplete(
        for userID: String,
        needsServerCompletion: Bool,
        firstVisitWalkthroughEligible: Bool
    ) {
        var value = state(for: userID)
        value.isComplete = true
        value.needsServerCompletion = needsServerCompletion
        value.isFirstVisitWalkthroughEligible = firstVisitWalkthroughEligible
        value.firstVisitWalkthroughEnrollmentGeneration = firstVisitWalkthroughEligible
            ? FirstVisitWalkthroughEligibilityPolicy.currentEnrollmentGeneration
            : nil
        save(value, for: userID)
    }

    func confirmServerCompletion(for userID: String) {
        var value = state(for: userID)
        value.isComplete = true
        value.needsServerCompletion = false
        save(value, for: userID)
    }

    @discardableResult
    func retireFirstVisitWalkthrough(for userID: String) -> Bool {
        var value = state(for: userID)
        guard value.isFirstVisitWalkthroughEligible == true
                || value.firstVisitWalkthroughEnrollmentGeneration != nil
        else { return false }
        value.isFirstVisitWalkthroughEligible = false
        value.firstVisitWalkthroughEnrollmentGeneration = nil
        save(value, for: userID)
        return true
    }

    func clear(for userID: String) {
        defaults.removeObject(forKey: key(for: userID))
    }

    private func key(for userID: String) -> String {
        keyPrefix + userID
    }

    private func save(_ state: OnboardingLocalState, for userID: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key(for: userID))
    }
}

enum AppEntryState: Equatable {
    case launching
    case signedOut
    case onboarding(session: AuthSession, step: OnboardingStep)
    case ready(session: AuthSession, firstVisitWalkthroughEligible: Bool)
    case recoverableFailure(session: AuthSession, message: String, canContinueOffline: Bool)
    case unavailable(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

enum AppEntryStateResolver {
    static func signedInState(
        session: AuthSession,
        localState: OnboardingLocalState,
        remoteProfile: LocalProfile?
    ) -> AppEntryState {
        if localState.isComplete || remoteProfile?.onboardingCompletedAt != nil {
            return .ready(
                session: session,
                firstVisitWalkthroughEligible: localState.shouldEnableFirstVisitWalkthrough
            )
        }
        return .onboarding(session: session, step: localState.nextStep)
    }

    static func offlineState(
        session: AuthSession,
        localState: OnboardingLocalState,
        message: String
    ) -> AppEntryState {
        if localState.isComplete {
            return .ready(
                session: session,
                firstVisitWalkthroughEligible: localState.shouldEnableFirstVisitWalkthrough
            )
        }
        return .recoverableFailure(
            session: session,
            message: message,
            canContinueOffline: canContinueOffline(session: session, localState: localState)
        )
    }

    private static func canContinueOffline(
        session: AuthSession,
        localState: OnboardingLocalState
    ) -> Bool {
        localState.nextStep != .identity
            || ProfileIdentityDraft(
                displayName: session.displayName ?? "",
                handle: session.handle ?? ""
            ).isValid
    }
}

@MainActor
final class AppEntryCoordinator: ObservableObject {
    @Published private(set) var state: AppEntryState = .launching
    @Published private(set) var pendingSharedProfileRoute: SharedProfileRoute?

    private let auth: AuthSessionStore
    private let backend: WanderBackend
    private let completionStore: OnboardingCompletionStore
    private let analytics: AnalyticsClient
    private var resolutionTask: Task<Void, Never>?
    private var resolvedUserID: String?

    init(
        auth: AuthSessionStore,
        backend: WanderBackend,
        completionStore: OnboardingCompletionStore = OnboardingCompletionStore(),
        analytics: AnalyticsClient = NoopAnalyticsClient()
    ) {
        self.auth = auth
        self.backend = backend
        self.completionStore = completionStore
        self.analytics = analytics
    }

    func start(preservingReadyState: Bool = false) async {
        if !preservingReadyState || !state.isReady {
            state = .launching
        }
        await auth.refreshSession()
        await resolve(auth.state, forceRemote: false)
    }

    func authStateChanged(_ authState: AuthState) {
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            await self?.resolve(authState, forceRemote: false)
        }
    }

    func retry() {
        switch state {
        case .recoverableFailure:
            state = .launching
            resolutionTask?.cancel()
            resolutionTask = Task { [weak self] in
                guard let self else { return }
                await self.start()
            }
        case .unavailable:
            state = .launching
            resolutionTask?.cancel()
            resolutionTask = Task { [weak self] in
                await self?.start()
            }
        default:
            return
        }
    }

    func continueOffline() {
        guard case .recoverableFailure(let session, _, true) = state else { return }
        completionStore.markComplete(
            for: session.userID,
            needsServerCompletion: true,
            firstVisitWalkthroughEligible: false
        )
        analytics.identify(userID: session.userID)
        state = .ready(session: session, firstVisitWalkthroughEligible: false)
    }

    func completeOnboarding(for session: AuthSession, serverConfirmed: Bool) {
        guard auth.isSessionValidated,
              case .signedIn(let authenticatedSession) = auth.state,
              authenticatedSession.userID == session.userID,
              case .onboarding(let onboardingSession, _) = state,
              onboardingSession.userID == session.userID
        else { return }

        completionStore.markComplete(
            for: session.userID,
            needsServerCompletion: !serverConfirmed,
            firstVisitWalkthroughEligible: true
        )
        analytics.identify(userID: session.userID)
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.onboardingCompleted,
                properties: ["server_confirmed": serverConfirmed ? "true" : "false"]
            )
        )
        state = .ready(session: session, firstVisitWalkthroughEligible: true)
    }

    func completeFirstVisitWalkthrough(forUserID userID: String) {
        guard case .ready(let readySession, _) = state,
              readySession.userID == userID
        else { return }
        let didRetire = completionStore.retireFirstVisitWalkthrough(for: userID)
        guard didRetire else { return }
        state = .ready(session: readySession, firstVisitWalkthroughEligible: false)
    }

    func saveProgress(_ step: OnboardingStep, for session: AuthSession) {
        completionStore.setNextStep(step, for: session.userID)
    }

    func capturePendingURL(_ url: URL) {
        guard let route = WanderRootView.sharedProfileRoute(for: url) else { return }
        pendingSharedProfileRoute = route
    }

    private func resolve(_ authState: AuthState, forceRemote: Bool) async {
        guard !Task.isCancelled else { return }
        switch authState {
        case .loading:
            state = .launching
        case .signedOut:
            if resolvedUserID != nil {
                analytics.resetIdentity()
            }
            resolvedUserID = nil
            state = .signedOut
        case .unavailable(let message):
            state = .unavailable(message)
        case .offline(let session, let message):
            let local = completionStore.state(for: session.userID)
            resolvedUserID = session.userID
            state = AppEntryStateResolver.offlineState(
                session: session,
                localState: local,
                message: message
            )
        case .signedIn(let session):
            guard auth.isSessionValidated else {
                state = .launching
                return
            }
            let local = completionStore.state(for: session.userID)
            if local.isComplete && !forceRemote {
                resolvedUserID = session.userID
                analytics.identify(userID: session.userID)
                state = .ready(
                    session: session,
                    firstVisitWalkthroughEligible: local.shouldEnableFirstVisitWalkthrough
                )
                if local.needsServerCompletion {
                    Task { [weak self] in await self?.retryServerCompletion(for: session) }
                }
                return
            }

            do {
                let profile = try await backend.currentProfile()
                guard !Task.isCancelled else { return }
                if profile?.onboardingCompletedAt != nil {
                    completionStore.confirmServerCompletion(for: session.userID)
                }
                resolvedUserID = session.userID
                analytics.identify(userID: session.userID)
                analytics.track(AnalyticsEvent(name: WanderAnalyticsEvents.onboardingAuthCompleted, properties: [:]))
                state = AppEntryStateResolver.signedInState(
                    session: session,
                    localState: completionStore.state(for: session.userID),
                    remoteProfile: profile
                )
            } catch {
                guard !Task.isCancelled else { return }
                let canContinue = local.nextStep != .identity || validAuthIdentity(session)
                state = .recoverableFailure(
                    session: session,
                    message: "We couldn’t check your profile. Try again, or continue if you’re offline.",
                    canContinueOffline: canContinue
                )
            }
        }
    }

    private func retryServerCompletion(for session: AuthSession) async {
        do {
            _ = try await backend.updateCurrentProfile(
                ProfileDetailsUpdate(markOnboardingComplete: true)
            )
            completionStore.confirmServerCompletion(for: session.userID)
        } catch {
            // Local positive cache keeps startup fast; a later launch retries.
        }
    }

    private func validAuthIdentity(_ session: AuthSession) -> Bool {
        ProfileIdentityDraft(
            displayName: session.displayName ?? "",
            handle: session.handle ?? ""
        ).isValid
    }
}
