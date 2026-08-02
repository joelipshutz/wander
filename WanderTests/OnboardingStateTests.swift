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

    func testForegroundSessionRefreshPreservesReadyRootForSameAccount() async throws {
        let suiteName = "OnboardingStateTests.refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let provider = PreviewAuthSessionProvider(state: .signedIn(session), token: "token")
        let auth = AuthSessionStore(provider: provider)
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
        await coordinator.refreshSessionPreservingReadyState()

        XCTAssertEqual(coordinator.state, .ready(session: session))
        XCTAssertTrue(auth.isSessionValidated)
    }
}
