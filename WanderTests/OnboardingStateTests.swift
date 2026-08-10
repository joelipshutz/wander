import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testCarouselAutoAdvanceIntervalIsSevenSeconds() {
        XCTAssertEqual(OnboardingCarouselTiming.defaultAutoAdvanceSeconds, 7)
    }

    func testCompletionStoreIsIsolatedPerUserAndPersistsProgress() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingCompletionStore(defaults: defaults)

        store.setNextStep(.friends, for: "user_a")
        store.markComplete(for: "user_a", needsServerCompletion: true)

        XCTAssertEqual(
            store.state(for: "user_a"),
            OnboardingLocalState(nextStep: .friends, isComplete: true, needsServerCompletion: true)
        )
        XCTAssertEqual(store.state(for: "user_b"), .fresh)

        store.clear(for: "user_a")

        XCTAssertEqual(store.state(for: "user_a"), .fresh)
    }

    func testServerCompletionRoutesStraightToMainApp() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let profile = LocalProfile(
            localID: "profile",
            serverID: "user",
            handle: "maya",
            displayName: "Maya",
            onboardingCompletedAt: Date()
        )

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: .fresh, remoteProfile: profile),
            .ready(session: session)
        )
    }

    func testIncompleteProfileResumesSavedOptionalStep() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let local = OnboardingLocalState(nextStep: .contacts, isComplete: false, needsServerCompletion: false)

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(session: session, localState: local, remoteProfile: nil),
            .onboarding(session: session, step: .contacts)
        )
    }

    func testInteractiveWalkthroughRootOnlyFollowsCompletedAccountOnboarding() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(
                session: session,
                localState: .fresh,
                remoteProfile: nil
            ),
            .onboarding(session: session, step: .identity)
        )

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(
                session: session,
                localState: OnboardingLocalState(
                    nextStep: .notifications,
                    isComplete: true,
                    needsServerCompletion: false
                ),
                remoteProfile: nil
            ),
            .ready(session: session)
        )
    }

    func testCompletedUserRoutesToCachedMapWhenSessionValidationIsOffline() {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let local = OnboardingLocalState(
            nextStep: .notifications,
            isComplete: true,
            needsServerCompletion: false
        )

        XCTAssertEqual(
            AppEntryStateResolver.offlineState(
                session: session,
                localState: local,
                message: "Saved map available offline"
            ),
            .ready(session: session)
        )
    }

    func testIncompleteUserKeepsOfflineRecoveryInsteadOfBypassingOnboarding() {
        let session = AuthSession(userID: "user", displayName: nil, handle: nil)

        XCTAssertEqual(
            AppEntryStateResolver.offlineState(
                session: session,
                localState: .fresh,
                message: "Saved map available offline"
            ),
            .recoverableFailure(
                session: session,
                message: "Saved map available offline",
                canContinueOffline: false
            )
        )
    }

    func testOptionalStepOrderIsStableForPhaseBReuse() {
        XCTAssertEqual(OnboardingStep.identity.next, .location)
        XCTAssertEqual(OnboardingStep.location.next, .contacts)
        XCTAssertEqual(OnboardingStep.contacts.next, .friends)
        XCTAssertEqual(OnboardingStep.friends.next, .notifications)
        XCTAssertNil(OnboardingStep.notifications.next)
    }

    func testForegroundSessionRefreshKeepsReadyRootMounted() async throws {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let provider = SuspendedRefreshAuthProvider(state: .signedIn(session))
        let auth = AuthSessionStore(provider: provider)
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        completionStore.markComplete(for: session.userID, needsServerCompletion: false)
        let coordinator = AppEntryCoordinator(
            auth: auth,
            backend: WanderBackend(),
            completionStore: completionStore
        )

        await coordinator.start()
        XCTAssertEqual(coordinator.state, .ready(session: session))

        auth.beginSessionValidation()
        provider.shouldSuspendRefresh = true
        let refreshTask = Task {
            await coordinator.start(preservingReadyState: true)
        }
        for _ in 0..<100 where !provider.isRefreshSuspended {
            await Task.yield()
        }

        XCTAssertTrue(provider.isRefreshSuspended)
        XCTAssertEqual(
            coordinator.state,
            .ready(session: session),
            "Foreground validation must not replace WanderRootView with the launch screen."
        )

        provider.resumeRefresh()
        await refreshTask.value
        XCTAssertEqual(coordinator.state, .ready(session: session))
    }

    func testLocationPermissionPolicySkipsAlreadyAuthorizedUsers() {
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .authorizedWhenInUse),
            .skip
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .authorizedAlways),
            .skip
        )
    }

    func testLocationPermissionPolicyKeepsDeniedAndRestrictedActionsUseful() {
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .notDetermined),
            .request
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .denied),
            .openSettings
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.primaryTitle(for: .denied),
            "Open Settings"
        )
        XCTAssertEqual(
            OnboardingLocationPermissionPolicy.action(for: .restricted),
            .continueWithoutAccess
        )
    }

    func testApprovedLocationValueCopyIsStable() {
        XCTAssertEqual(OnboardingLocationContent.eyebrow, "AROUND YOU")
        XCTAssertEqual(OnboardingLocationContent.title, "Find the good stuff nearby")
        XCTAssertEqual(
            OnboardingLocationContent.privacyMessage,
            "Your location is never shown to friends."
        )
        XCTAssertEqual(OnboardingLocationContent.selectedPlaceName, "Circuit Coffee")
    }

    func testLocationPreviewUsesNativeMapPinsAndSelectedPlaceCard() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/Onboarding/OnboardingLocationMapPreview.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Map(position: $position"))
        XCTAssertTrue(source.contains("OnboardingLocationMapPin(pin: pin)"))
        XCTAssertTrue(source.contains("OnboardingLocationSelectedPlaceCard()"))
        XCTAssertTrue(source.contains("isSelected: true"))
    }
}

@MainActor
private final class SuspendedRefreshAuthProvider: AuthSessionProviding {
    private(set) var state: AuthState
    var shouldSuspendRefresh = false
    private(set) var isRefreshSuspended = false
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private let changes: AsyncStream<AuthState>

    init(state: AuthState) {
        self.state = state
        changes = AsyncStream { _ in }
    }

    var canPresentNativeAuth: Bool { false }

    func sessionChanges() -> AsyncStream<AuthState> { changes }

    func refreshSession() async {
        guard shouldSuspendRefresh else { return }
        isRefreshSuspended = true
        await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
        isRefreshSuspended = false
    }

    func resumeRefresh() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }

    func signOut() async throws {
        state = .signedOut
    }

    func deleteAccount() async throws {
        state = .signedOut
    }

    func supabaseAccessToken() async throws -> String {
        throw AuthSessionError.tokenUnavailable
    }
}
