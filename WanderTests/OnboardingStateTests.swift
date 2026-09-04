import CoreLocation
import XCTest
@testable import Wander

@MainActor
final class OnboardingStateTests: XCTestCase {
    func testAuthenticatedSimulatorFixturePersistsUntilLiveAuthIsRequested() throws {
        let suiteName = "OnboardingStateTests.simulatorSession.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander"],
                defaults: defaults,
                isSimulator: true
            )
        )
        XCTAssertTrue(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander", "-WanderAuthenticatedUITest"],
                defaults: defaults,
                isSimulator: true
            )
        )
        XCTAssertTrue(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander"],
                defaults: defaults,
                isSimulator: true
            ),
            "An icon relaunch has no custom arguments but must restore the local test session."
        )
        XCTAssertFalse(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander", "-WanderUseLiveAuth"],
                defaults: defaults,
                isSimulator: true
            )
        )
        XCTAssertFalse(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander"],
                defaults: defaults,
                isSimulator: true
            )
        )
        XCTAssertFalse(
            SimulatorTestSessionPolicy.isActive(
                arguments: ["Wander", "-WanderAuthenticatedUITest"],
                defaults: defaults,
                isSimulator: false
            ),
            "Physical devices and TestFlight must never activate a preview identity."
        )
    }

    func testSimulatorOnboardingStepRoutesThroughTheActualAppEntryFlow() async {
        XCTAssertEqual(
            SimulatorTestSessionPolicy.forcedOnboardingStep(
                arguments: [
                    "Wander",
                    "-WanderAuthenticatedUITest",
                    "-WanderOnboardingUITestStep",
                    "contacts"
                ],
                isSimulator: true
            ),
            .contacts
        )
        XCTAssertNil(
            SimulatorTestSessionPolicy.forcedOnboardingStep(
                arguments: ["Wander", "-WanderOnboardingUITestStep", "contacts"],
                isSimulator: true
            ),
            "The production onboarding route requires the explicit authenticated UI-test session."
        )
        XCTAssertNil(
            SimulatorTestSessionPolicy.forcedOnboardingStep(
                arguments: [
                    "Wander",
                    "-WanderAuthenticatedUITest",
                    "-WanderOnboardingUITestStep",
                    "contacts"
                ],
                isSimulator: false
            ),
            "Physical and App Store builds must never accept the simulator route."
        )

        let session = AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(
                provider: PreviewAuthSessionProvider(state: .signedIn(session))
            ),
            backend: WanderBackend(),
            usesLocalSimulatorTestSession: true,
            forcedLocalSimulatorOnboardingStep: .location
        )

        await coordinator.start()

        XCTAssertEqual(coordinator.state, .onboarding(session: session, step: .location))
    }

    func testLocalSimulatorSessionEntersAppWithoutHostedProfileResolution() async {
        let session = AuthSession(userID: "user_joe", displayName: "Joe", handle: "joe")
        let auth = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedIn(session)))
        let coordinator = AppEntryCoordinator(
            auth: auth,
            backend: WanderBackend(),
            usesLocalSimulatorTestSession: true
        )

        await coordinator.start()

        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
    }

    func testCarouselAutoAdvanceIntervalIsSevenSeconds() {
        XCTAssertEqual(OnboardingCarouselTiming.defaultAutoAdvanceSeconds, 7)
    }

    func testCompletionStoreIsIsolatedPerUserAndPersistsProgress() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingCompletionStore(defaults: defaults)

        store.setNextStep(.friends, for: "user_a")
        store.markComplete(
            for: "user_a",
            needsServerCompletion: true,
            firstVisitWalkthroughEligible: true
        )

        XCTAssertEqual(
            store.state(for: "user_a"),
            OnboardingLocalState(
                nextStep: .friends,
                isComplete: true,
                needsServerCompletion: true,
                isFirstVisitWalkthroughEligible: true,
                firstVisitWalkthroughEnrollmentGeneration:
                    FirstVisitWalkthroughEligibilityPolicy.currentEnrollmentGeneration
            )
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
            .ready(session: session, firstVisitWalkthroughEligible: false)
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
            .ready(session: session, firstVisitWalkthroughEligible: false)
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
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
    }

    func testNewUserCompletionEnablesFirstVisitWalkthrough() async throws {
        let session = AuthSession(userID: "new-user", displayName: "Maya", handle: "maya")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(provider: SuspendedRefreshAuthProvider(state: .signedIn(session))),
            backend: WanderBackend(profileRepository: EmptyOnboardingProfileRepository()),
            completionStore: completionStore
        )

        await coordinator.start()
        XCTAssertEqual(coordinator.state, .onboarding(session: session, step: .identity))
        coordinator.completeOnboarding(for: session, serverConfirmed: true)

        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: true)
        )
        XCTAssertTrue(completionStore.state(for: session.userID).shouldEnableFirstVisitWalkthrough)

        coordinator.completeFirstVisitWalkthrough(forUserID: session.userID)

        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
        XCTAssertFalse(completionStore.state(for: session.userID).shouldEnableFirstVisitWalkthrough)
    }

    func testStaleWalkthroughCompletionCannotRetireAnotherReadyAccount() async throws {
        let sessionA = AuthSession(userID: "user-a", displayName: "A", handle: "a")
        let sessionB = AuthSession(userID: "user-b", displayName: "B", handle: "b")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(provider: SuspendedRefreshAuthProvider(state: .signedIn(sessionA))),
            backend: WanderBackend(profileRepository: EmptyOnboardingProfileRepository()),
            completionStore: completionStore
        )

        await coordinator.start()
        coordinator.completeOnboarding(for: sessionA, serverConfirmed: true)
        completionStore.markComplete(
            for: sessionB.userID,
            needsServerCompletion: false,
            firstVisitWalkthroughEligible: true
        )

        coordinator.completeFirstVisitWalkthrough(forUserID: sessionB.userID)

        XCTAssertEqual(
            coordinator.state,
            .ready(session: sessionA, firstVisitWalkthroughEligible: true)
        )
        XCTAssertTrue(completionStore.state(for: sessionA.userID).shouldEnableFirstVisitWalkthrough)
        XCTAssertTrue(completionStore.state(for: sessionB.userID).shouldEnableFirstVisitWalkthrough)

        coordinator.completeFirstVisitWalkthrough(forUserID: sessionA.userID)

        XCTAssertFalse(completionStore.state(for: sessionA.userID).shouldEnableFirstVisitWalkthrough)
        XCTAssertTrue(completionStore.state(for: sessionB.userID).shouldEnableFirstVisitWalkthrough)
    }

    func testExistingRemoteUserWithoutLocalStateNeverEnablesFirstVisitWalkthrough() {
        let session = AuthSession(userID: "existing-user", displayName: "Joe", handle: "joe")
        let profile = LocalProfile(
            localID: "profile",
            serverID: session.userID,
            handle: "joe",
            displayName: "Joe",
            onboardingCompletedAt: Date()
        )

        XCTAssertEqual(
            AppEntryStateResolver.signedInState(
                session: session,
                localState: .fresh,
                remoteProfile: profile
            ),
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
    }

    func testLegacyCompletedLocalStateDefaultsToWalkthroughIneligible() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "legacy-user"
        let legacyJSON = """
        {"nextStep":"notifications","isComplete":true,"needsServerCompletion":false}
        """.data(using: .utf8)
        defaults.set(legacyJSON, forKey: "recme.onboarding.v1.\(userID)")

        let state = OnboardingCompletionStore(defaults: defaults).state(for: userID)

        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.shouldEnableFirstVisitWalkthrough)
    }

    func testLegacyBooleanOnlyWalkthroughEligibilityFailsClosed() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "legacy-eligible-user"
        let legacyJSON = """
        {"nextStep":"notifications","isComplete":true,"needsServerCompletion":false,"isFirstVisitWalkthroughEligible":true}
        """.data(using: .utf8)
        defaults.set(legacyJSON, forKey: "recme.onboarding.v1.\(userID)")

        let state = OnboardingCompletionStore(defaults: defaults).state(for: userID)

        XCTAssertEqual(state.isFirstVisitWalkthroughEligible, true)
        XCTAssertNil(state.firstVisitWalkthroughEnrollmentGeneration)
        XCTAssertFalse(state.shouldEnableFirstVisitWalkthrough)
    }

    func testCurrentEnrollmentGenerationIsRequiredForWalkthroughEligibility() {
        XCTAssertTrue(
            FirstVisitWalkthroughEligibilityPolicy.isEnrolled(
                isPersistedEligible: true,
                enrollmentGeneration:
                    FirstVisitWalkthroughEligibilityPolicy.currentEnrollmentGeneration
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.isEnrolled(
                isPersistedEligible: true,
                enrollmentGeneration: nil
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.isEnrolled(
                isPersistedEligible: true,
                enrollmentGeneration:
                    FirstVisitWalkthroughEligibilityPolicy.currentEnrollmentGeneration + 1
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.isEnrolled(
                isPersistedEligible: false,
                enrollmentGeneration:
                    FirstVisitWalkthroughEligibilityPolicy.currentEnrollmentGeneration
            )
        )
    }

    func testFirstVisitEligibilityContextNeverCrossesAccounts() {
        let eligibleAccount = FirstVisitWalkthroughEligibilityContext(
            sourceUserID: "user-a",
            isEligible: true
        )

        XCTAssertTrue(eligibleAccount.applies(to: "user-a"))
        XCTAssertFalse(eligibleAccount.applies(to: "user-b"))
        XCTAssertFalse(eligibleAccount.applies(to: nil))
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityContext(
                sourceUserID: "user-a",
                isEligible: false
            ).applies(to: "user-a")
        )
    }

    func testEligibilityRetirementWaitsForMatchingAccountContext() {
        let staleContext = FirstVisitWalkthroughEligibilityContext(
            sourceUserID: "user-a",
            isEligible: true
        )
        let activeContext = FirstVisitWalkthroughEligibilityContext(
            sourceUserID: "user-b",
            isEligible: true
        )

        XCTAssertFalse(
            staleContext.shouldRetire(
                for: "user-b",
                whenRetirementIsRequested: true
            ),
            "A live auth change must not consume another account's retirement attempt."
        )
        XCTAssertTrue(
            activeContext.shouldRetire(
                for: "user-b",
                whenRetirementIsRequested: true
            ),
            "Retirement must retry once AppEntry publishes the matching account context."
        )
        XCTAssertFalse(
            activeContext.shouldRetire(
                for: "user-b",
                whenRetirementIsRequested: false
            )
        )
    }

    func testStaleOnboardingCompletionCannotEnrollAnotherValidatedAccount() async throws {
        let staleSession = AuthSession(userID: "user-a", displayName: "A", handle: "a")
        let activeSession = AuthSession(userID: "user-b", displayName: "B", handle: "b")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(
                provider: SuspendedRefreshAuthProvider(state: .signedIn(activeSession))
            ),
            backend: WanderBackend(profileRepository: EmptyOnboardingProfileRepository()),
            completionStore: completionStore
        )

        await coordinator.start()
        coordinator.completeOnboarding(for: staleSession, serverConfirmed: true)

        XCTAssertEqual(
            coordinator.state,
            .onboarding(session: activeSession, step: .identity)
        )
        XCTAssertEqual(completionStore.state(for: staleSession.userID), .fresh)
        XCTAssertEqual(completionStore.state(for: activeSession.userID), .fresh)
    }

    func testStaleOnboardingCompletionCannotReenrollAnAlreadyReadyAccount() async throws {
        let session = AuthSession(userID: "established-user", displayName: "Joe", handle: "joe")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        completionStore.markComplete(
            for: session.userID,
            needsServerCompletion: false,
            firstVisitWalkthroughEligible: false
        )
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(
                provider: SuspendedRefreshAuthProvider(state: .signedIn(session))
            ),
            backend: WanderBackend(profileRepository: EmptyOnboardingProfileRepository()),
            completionStore: completionStore
        )

        await coordinator.start()
        coordinator.completeOnboarding(for: session, serverConfirmed: true)

        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
        XCTAssertFalse(completionStore.state(for: session.userID).shouldEnableFirstVisitWalkthrough)
    }

    func testOnboardingCompletionRequiresValidatedSession() async throws {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        let auth = AuthSessionStore(
            provider: SuspendedRefreshAuthProvider(state: .signedIn(session))
        )
        let coordinator = AppEntryCoordinator(
            auth: auth,
            backend: WanderBackend(profileRepository: EmptyOnboardingProfileRepository()),
            completionStore: completionStore
        )

        await coordinator.start()
        auth.beginSessionValidation()
        coordinator.completeOnboarding(for: session, serverConfirmed: true)

        XCTAssertEqual(coordinator.state, .onboarding(session: session, step: .identity))
        XCTAssertEqual(completionStore.state(for: session.userID), .fresh)
    }

    func testOnlyExplicitAccountDisableRequestsPersistedEligibilityRetirement() {
        XCTAssertTrue(
            FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement(
                isUsingLiveData: true,
                resolvedAccountOverride: false
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement(
                isUsingLiveData: true,
                resolvedAccountOverride: nil
            ),
            "An unresolved or failed flag fetch must fail closed without erasing enrollment."
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement(
                isUsingLiveData: true,
                resolvedAccountOverride: true
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement(
                isUsingLiveData: false,
                resolvedAccountOverride: false
            ),
            "Fixture and preview sessions must never mutate persisted account enrollment."
        )
    }

    func testEligibleLiveUserWaitsForFlagBeforeRenderingNUXEmptyState() {
        XCTAssertTrue(
            FirstVisitWalkthroughEligibilityPolicy.isAwaitingFeatureFlagResolution(
                isEnrolled: true,
                isUsingLiveData: true,
                resolutionIsPending: true
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.isAwaitingFeatureFlagResolution(
                isEnrolled: true,
                isUsingLiveData: true,
                resolutionIsPending: false
            )
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.isAwaitingFeatureFlagResolution(
                isEnrolled: false,
                isUsingLiveData: true,
                resolutionIsPending: true
            )
        )
    }

    func testLocalJourneyRetirementRequiresDefinitiveIneligibilityOrDisablement() {
        XCTAssertTrue(
            FirstVisitWalkthroughEligibilityPolicy.shouldRetireLocalJourney(
                isEnrolled: false,
                isExplicitReplayEnabled: false,
                isExplicitlyDisabled: false
            ),
            "Established accounts must discard stale NUX checkpoints."
        )
        XCTAssertTrue(
            FirstVisitWalkthroughEligibilityPolicy.shouldRetireLocalJourney(
                isEnrolled: true,
                isExplicitReplayEnabled: false,
                isExplicitlyDisabled: true
            ),
            "An explicit account or tester disable must retire the local journey."
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.shouldRetireLocalJourney(
                isEnrolled: true,
                isExplicitReplayEnabled: false,
                isExplicitlyDisabled: false
            ),
            "A missing or global flag value must preserve an enrolled user's 12-hour checkpoint."
        )
        XCTAssertFalse(
            FirstVisitWalkthroughEligibilityPolicy.shouldRetireLocalJourney(
                isEnrolled: false,
                isExplicitReplayEnabled: true,
                isExplicitlyDisabled: false
            ),
            "An entitled replay must remain available to an established tester."
        )
    }

    func testDebugReplaySurvivesEntitlementResolutionWithoutStartingUnauthorizedNUX() {
        let pending = FirstVisitWalkthroughDebugReplayPolicy.resolve(
            hasLocalReplayRequest: true,
            isDebugSettingsEntitled: false,
            isFeatureFlagResolutionPending: true
        )
        XCTAssertFalse(pending.isEntitledReplayRequested)
        XCTAssertTrue(pending.isAwaitingEntitlementResolution)
        XCTAssertFalse(pending.canRepairCompletedLocalJourney)
        XCTAssertTrue(
            pending.shouldPreserveLocalJourney,
            "A queued tester replay must not be erased while its server entitlement is loading."
        )

        let entitled = FirstVisitWalkthroughDebugReplayPolicy.resolve(
            hasLocalReplayRequest: true,
            isDebugSettingsEntitled: true,
            isFeatureFlagResolutionPending: false
        )
        XCTAssertTrue(entitled.isEntitledReplayRequested)
        XCTAssertTrue(entitled.shouldPreserveLocalJourney)
        XCTAssertFalse(entitled.isAwaitingEntitlementResolution)
        XCTAssertTrue(entitled.canRepairCompletedLocalJourney)
        XCTAssertFalse(
            FirstVisitWalkthroughDebugReplayPolicy.shouldRepairCompletedLocalJourney(
                entitled,
                hasCompletedPrimaryJourney: false
            ),
            "An interrupted replay must resume from its checkpoint after a cold relaunch."
        )
        XCTAssertTrue(
            FirstVisitWalkthroughDebugReplayPolicy.shouldRepairCompletedLocalJourney(
                entitled,
                hasCompletedPrimaryJourney: true
            ),
            "A replay corrupted by the old launch race must recover from its completed state."
        )

        let denied = FirstVisitWalkthroughDebugReplayPolicy.resolve(
            hasLocalReplayRequest: true,
            isDebugSettingsEntitled: false,
            isFeatureFlagResolutionPending: false
        )
        XCTAssertFalse(denied.isEntitledReplayRequested)
        XCTAssertFalse(denied.isAwaitingEntitlementResolution)
        XCTAssertFalse(denied.canRepairCompletedLocalJourney)
        XCTAssertFalse(
            denied.shouldPreserveLocalJourney,
            "A stale local request must not enable or preserve NUX for an account that is not entitled."
        )
    }

    func testWalkthroughEligibilityRetirementIsIdempotent() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingCompletionStore(defaults: defaults)
        let userID = "disabled-user"
        store.markComplete(
            for: userID,
            needsServerCompletion: false,
            firstVisitWalkthroughEligible: true
        )

        XCTAssertTrue(store.retireFirstVisitWalkthrough(for: userID))
        XCTAssertFalse(store.retireFirstVisitWalkthrough(for: userID))
        XCTAssertEqual(store.state(for: userID).isFirstVisitWalkthroughEligible, false)
        XCTAssertNil(store.state(for: userID).firstVisitWalkthroughEnrollmentGeneration)
    }

    func testExplicitDisableCanRetireLegacyBooleanOnlyEnrollment() throws {
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "legacy-disabled-user"
        let legacyJSON = """
        {"nextStep":"notifications","isComplete":true,"needsServerCompletion":false,"isFirstVisitWalkthroughEligible":true}
        """.data(using: .utf8)
        defaults.set(legacyJSON, forKey: "recme.onboarding.v1.\(userID)")
        let store = OnboardingCompletionStore(defaults: defaults)

        XCTAssertTrue(store.retireFirstVisitWalkthrough(for: userID))
        XCTAssertFalse(store.retireFirstVisitWalkthrough(for: userID))
        XCTAssertEqual(store.state(for: userID).isFirstVisitWalkthroughEligible, false)
    }

    func testWalkthroughCompletionDoesNotRepublishReadyStateWithoutPersistedEnrollment() throws {
        let session = AuthSession(userID: "already-retired-user", displayName: "Joe", handle: "joe")
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = AppEntryCoordinator(
            auth: AuthSessionStore(provider: SuspendedRefreshAuthProvider(state: .signedIn(session))),
            backend: WanderBackend(),
            completionStore: OnboardingCompletionStore(defaults: defaults)
        )

        coordinator.completeFirstVisitWalkthrough(forUserID: session.userID)

        XCTAssertEqual(coordinator.state, .launching)
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

    func testOptionalStepOrderDefersCalendarConnectionToSettings() {
        XCTAssertEqual(OnboardingStep.identity.next, .location)
        XCTAssertEqual(OnboardingStep.location.next, .contacts)
        XCTAssertEqual(OnboardingStep.contacts.next, .friends)
        XCTAssertEqual(OnboardingStep.friends.next, .notifications)
        XCTAssertNil(OnboardingStep.notifications.next)
    }

    func testLegacyCalendarStepResumesAtNotifications() throws {
        let encodedStep = try XCTUnwrap("\"calendar\"".data(using: .utf8))

        XCTAssertEqual(
            try JSONDecoder().decode(OnboardingStep.self, from: encodedStep),
            .notifications
        )
    }

    func testForegroundSessionRefreshKeepsReadyRootMounted() async throws {
        let session = AuthSession(userID: "user", displayName: "Maya", handle: "maya")
        let provider = SuspendedRefreshAuthProvider(state: .signedIn(session))
        let auth = AuthSessionStore(provider: provider)
        let suiteName = "OnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let completionStore = OnboardingCompletionStore(defaults: defaults)
        completionStore.markComplete(
            for: session.userID,
            needsServerCompletion: false,
            firstVisitWalkthroughEligible: false
        )
        let coordinator = AppEntryCoordinator(
            auth: auth,
            backend: WanderBackend(),
            completionStore: completionStore
        )

        await coordinator.start()
        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )

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
            .ready(session: session, firstVisitWalkthroughEligible: false),
            "Foreground validation must not replace WanderRootView with the launch screen."
        )

        provider.resumeRefresh()
        await refreshTask.value
        XCTAssertEqual(
            coordinator.state,
            .ready(session: session, firstVisitWalkthroughEligible: false)
        )
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
            OnboardingLocationPermissionPolicy.primaryTitle(for: .notDetermined),
            "Continue"
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

    func testNotificationPermissionPolicyRequiresOneNeutralActionBeforeTheSystemPrompt() {
        XCTAssertEqual(
            OnboardingNotificationPermissionPolicy.action(for: .notDetermined),
            .request
        )
        XCTAssertEqual(
            OnboardingNotificationPermissionPolicy.primaryTitle(for: .notDetermined),
            "Continue"
        )
        XCTAssertFalse(
            OnboardingNotificationPermissionPolicy.allowsSecondaryAction(for: .notDetermined)
        )
        XCTAssertEqual(
            OnboardingNotificationPermissionPolicy.action(for: .denied),
            .openSettings
        )
        XCTAssertEqual(
            OnboardingNotificationPermissionPolicy.primaryTitle(for: .denied),
            "Open Settings"
        )
        XCTAssertTrue(
            OnboardingNotificationPermissionPolicy.allowsSecondaryAction(for: .denied)
        )
    }

    func testNotificationUpsellPreparationSkipsUnknownOrAlreadyEnabledPreferences() {
        XCTAssertGreaterThan(
            OnboardingNotificationUpsellPreparationPolicy.maximumPreferenceWaitMilliseconds,
            OnboardingNotificationUpsellPreparationPolicy.systemPermissionFallbackDelayMilliseconds
        )
        XCTAssertEqual(
            OnboardingNotificationUpsellPreparationPolicy.resolution(
                preferences: nil,
                authorizationStatus: .authorized
            ),
            .wait
        )
        XCTAssertEqual(
            OnboardingNotificationUpsellPreparationPolicy.resolution(
                preferences: nil,
                authorizationStatus: .notDetermined
            ),
            .present
        )
        XCTAssertEqual(
            OnboardingNotificationUpsellPreparationPolicy.resolution(
                preferences: .allEnabled,
                authorizationStatus: .authorized
            ),
            .skip
        )
        XCTAssertEqual(
            OnboardingNotificationUpsellPreparationPolicy.resolution(
                preferences: .allDisabled,
                authorizationStatus: .notDetermined
            ),
            .present
        )
    }

    func testCalendarPermissionPolicyUsesNeutralRequestAndSettingsRecovery() {
        XCTAssertEqual(CalendarPermissionPolicy.action(for: .notDetermined), .request)
        XCTAssertEqual(CalendarPermissionPolicy.primaryTitle(for: .notDetermined), "continue")
        XCTAssertEqual(CalendarPermissionPolicy.action(for: .denied), .openSettings)
        XCTAssertEqual(CalendarPermissionPolicy.primaryTitle(for: .denied), "open settings")
        XCTAssertEqual(CalendarPermissionPolicy.action(for: .fullAccess), .sync)
        XCTAssertEqual(CalendarPermissionPolicy.primaryTitle(for: .fullAccess), "sync now")
    }

    func testFirstVisitParkPolicyUsesHotchkissForUnavailableAndSantaMonicaZIPs() {
        let fallback = FirstVisitParkSuggestionPolicy.hotchkissPark

        XCTAssertEqual(fallback.name, "Hotchkiss Park")
        XCTAssertEqual(fallback.address, "2302 4th St")
        XCTAssertEqual(fallback.locality, "Santa Monica")
        XCTAssertEqual(fallback.region, "CA")
        XCTAssertEqual(fallback.subcategory, "Park")
        XCTAssertFalse(FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(postalCode: nil))
        XCTAssertFalse(FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(postalCode: "90403"))
        XCTAssertFalse(FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(postalCode: "90405-1234"))
        XCTAssertFalse(FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(postalCode: "invalid"))
        XCTAssertTrue(FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(postalCode: "10001"))
    }

    func testFirstVisitParkSelectionPreservesMapKitRelevanceOrderOverProximity() {
        let results = [
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: true,
                isPark: true,
                distanceMeters: 12_000
            ),
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: true,
                isPark: true,
                distanceMeters: 500
            )
        ]

        XCTAssertEqual(
            FirstVisitParkSuggestionPolicy.firstEligibleResultIndex(in: results),
            0,
            "The more relevant MapKit result must win even when another park is closer."
        )
    }

    func testFirstVisitParkSelectionEnforcesRadiusAndEligibility() {
        let results = [
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: true,
                isPark: false,
                distanceMeters: 400
            ),
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: true,
                isPark: true,
                distanceMeters: FirstVisitParkSuggestionPolicy.searchRadiusMeters + 0.01
            ),
            FirstVisitParkSearchResult(
                hasName: false,
                hasValidCoordinate: true,
                isPark: true,
                distanceMeters: 600
            ),
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: false,
                isPark: true,
                distanceMeters: 700
            ),
            FirstVisitParkSearchResult(
                hasName: true,
                hasValidCoordinate: true,
                isPark: true,
                distanceMeters: FirstVisitParkSuggestionPolicy.searchRadiusMeters
            )
        ]

        XCTAssertEqual(
            FirstVisitParkSuggestionPolicy.firstEligibleResultIndex(in: results),
            4
        )
    }

    func testFirstVisitParkSearchPlanUsesPopularityThenOrdinaryParkFallback() {
        XCTAssertEqual(
            FirstVisitParkSuggestionPolicy.searchQueries,
            ["popular parks", "park"]
        )
    }

    func testFirstVisitParkLocationDoesNotPromptWhenAuthorizationIsUndetermined() async throws {
        let locationProvider = RecordingFirstVisitLocationProvider()
        let provider = CoreFirstVisitParkLocationContextProvider(
            locationProvider: locationProvider,
            authorizationStatus: { .notDetermined },
            postalCodeResolver: { _ in
                XCTFail("Postal code lookup must not run without existing authorization")
                return "10001"
            }
        )

        let context = try await provider.alreadyAuthorizedLocationContext()

        XCTAssertNil(context)
        XCTAssertEqual(locationProvider.requestCount, 0)
    }

    func testFirstVisitParkLocationUsesOnlyNormalizedZIPAfterAuthorization() async throws {
        let locationProvider = RecordingFirstVisitLocationProvider()
        let provider = CoreFirstVisitParkLocationContextProvider(
            locationProvider: locationProvider,
            authorizationStatus: { .authorizedWhenInUse },
            postalCodeResolver: { _ in " 10001-4567 " }
        )

        let context = try await provider.alreadyAuthorizedLocationContext()

        XCTAssertEqual(context, FirstVisitParkLocationContext(postalCode: "10001"))
        XCTAssertEqual(locationProvider.requestCount, 1)
    }

    func testFirstVisitParkLocationFallsBackWhenReverseGeocodingHasNoZIP() async throws {
        let locationProvider = RecordingFirstVisitLocationProvider()
        let provider = CoreFirstVisitParkLocationContextProvider(
            locationProvider: locationProvider,
            authorizationStatus: { .authorizedAlways },
            postalCodeResolver: { _ in nil }
        )

        let context = try await provider.alreadyAuthorizedLocationContext()

        XCTAssertNil(context)
        XCTAssertEqual(locationProvider.requestCount, 1)
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
private final class RecordingFirstVisitLocationProvider: CurrentLocationProviding {
    private(set) var requestCount = 0

    func currentLocation() async throws -> CLLocation {
        requestCount += 1
        return CLLocation(latitude: 34.00585, longitude: -118.4842)
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

@MainActor
private final class EmptyOnboardingProfileRepository: ProfileRepository {
    func currentProfile() async throws -> LocalProfile? {
        nil
    }

    func profile(id: String) async throws -> ProfileViewState {
        throw WanderRemoteError.notConfigured
    }

    func searchProfiles(handleQuery: String) async throws -> [ProfileShell] {
        []
    }
}
