import XCTest
@testable import Wander
#if canImport(ClerkKit)
import ClerkKit
#endif

@MainActor
final class AuthSessionTests: XCTestCase {
    func testCanonicalProductionUserIDPreservesExistingAccountIdentity() {
        XCTAssertEqual(
            ClerkAuthService.resolvedUserID(
                clerkUserID: "user_new_production",
                canonicalUserID: " user_existing_profile "
            ),
            "user_existing_profile"
        )
    }

    func testCanonicalProductionUserIDFallsBackForNewAndLegacyAccounts() {
        XCTAssertEqual(
            ClerkAuthService.resolvedUserID(
                clerkUserID: "user_new_account",
                canonicalUserID: nil
            ),
            "user_new_account"
        )
        XCTAssertEqual(
            ClerkAuthService.resolvedUserID(
                clerkUserID: "user_legacy_account",
                canonicalUserID: "  "
            ),
            "user_legacy_account"
        )
    }

    func testRequireSignInRunsActionWhenSignedIn() {
        let provider = PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")),
            token: "token"
        )
        let store = AuthSessionStore(provider: provider)
        var actionRan = false

        store.requireSignIn(for: .followPeople) {
            actionRan = true
        }

        XCTAssertTrue(actionRan)
        XCTAssertNil(store.activeGate)
    }

    func testRequireSignInPresentsGateWhenSignedOut() {
        let store = AuthSessionStore(provider: PreviewAuthSessionProvider(state: .signedOut))
        var actionRan = false

        store.requireSignIn(for: .socialSave) {
            actionRan = true
        }

        XCTAssertFalse(actionRan)
        XCTAssertEqual(store.activeGate?.intent, .socialSave)
    }

    func testBeginSignInPresentsNativeAuthWithRuntimeFallbackConfiguration() {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let service = ClerkAuthService(
            configuration: configuration,
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { publishableKey in publishableKey }
        )
        let store = AuthSessionStore(provider: service)

        store.presentGate(for: .syncPlace)
        store.beginSignIn()

        XCTAssertNil(store.activeGate)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(store.state, .loading)
    }

    func testReleasedStoreDoesNotStartCancelledProviderObservation() async {
        let provider = PreviewAuthSessionProvider(state: .signedOut)
        var store: AuthSessionStore? = AuthSessionStore(provider: provider)
        weak var releasedStore = store

        store = nil
        XCTAssertNil(releasedStore)

        await Task.yield()

        XCTAssertEqual(provider.sessionChangesRequestCount, 0)
    }

    func testNativeAuthAttemptIgnoresProviderEventsUntilCorrelatedSuccess() async throws {
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let unrelatedSession = AuthSession(
            userID: "user_unrelated",
            displayName: "Unrelated",
            handle: "unrelated"
        )
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthSession: session,
            nativeAuthSessionAdoption: .afterCompletionRetry
        )
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        store.beginSignIn(mode: .signUp)
        XCTAssertTrue(store.isPresentingNativeAuth)

        provider.setState(.loading)
        await Task.yield()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertTrue(store.isPresentingNativeAuth)

        provider.setState(.signedIn(unrelatedSession))
        await Task.yield()
        XCTAssertEqual(store.state, .signedOut)
        XCTAssertFalse(store.isSessionValidated)
        XCTAssertTrue(store.isPresentingNativeAuth)

        let outcome = await store.authenticate(with: .apple)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertFalse(store.isPresentingNativeAuth)
        XCTAssertTrue(store.isSessionValidated)
    }

    func testNativeAuthDismissalEndsAttemptBeforeLaterProviderEvents() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true
        )
        let store = AuthSessionStore(provider: provider)

        store.beginSignIn()
        XCTAssertTrue(store.isPresentingNativeAuth)

        store.nativeAuthDidDismiss()
        XCTAssertFalse(store.isPresentingNativeAuth)

        provider.setState(.loading)
        await waitForState(.loading, in: store)
        XCTAssertFalse(store.isPresentingNativeAuth)

        provider.setState(.signedOut)
        await waitForState(.signedOut, in: store)
        XCTAssertFalse(store.isPresentingNativeAuth)
    }

    func testAppleSignUpCompletesSessionAndClosesNativeAuth() async {
        let session = AuthSession(userID: "user_apple", displayName: "Apple User", handle: nil)
        let analytics = AuthRecordingAnalyticsClient()
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthSession: session,
            nativeAuthSessionAdoption: .afterCompletionRetry
        )
        let store = AuthSessionStore(provider: provider, analytics: analytics)
        store.beginSignIn(mode: .signUp)

        let outcome = await store.authenticate(with: .apple)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(
            provider.requestedSocialAuth,
            [.init(provider: .apple, mode: .signUp)]
        )
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertTrue(store.isSessionValidated)
        XCTAssertFalse(store.isPresentingNativeAuth)
        XCTAssertNil(store.activeSocialAuthProvider)
        XCTAssertNil(store.nativeAuthError)
        XCTAssertEqual(
            analytics.events,
            [
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.nativeSocialAuthResult,
                    properties: [
                        "provider": "apple",
                        "mode": "sign_up",
                        "result": "completed",
                        "session_adoption": "after_completion_retry"
                    ]
                )
            ]
        )
    }

    func testAppleCancellationKeepsAuthOpenWithoutShowingAnError() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthFailure: AuthSessionError.cancelled
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.authenticate(with: .apple)

        XCTAssertNil(outcome)
        XCTAssertEqual(
            provider.requestedSocialAuth,
            [.init(provider: .apple, mode: .signIn)]
        )
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertNil(store.activeSocialAuthProvider)
        XCTAssertNil(store.nativeAuthError)
    }

    func testAppleFailureKeepsAuthOpenWithRecoverableCopy() async {
        let analytics = AuthRecordingAnalyticsClient()
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthFailure: AuthSessionError.tokenUnavailable
        )
        let store = AuthSessionStore(provider: provider, analytics: analytics)
        store.beginSignIn()

        let outcome = await store.authenticate(with: .apple)

        XCTAssertNil(outcome)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(
            store.nativeAuthError,
            "Apple sign-in didn’t finish. Try again or use another method."
        )
        XCTAssertEqual(
            analytics.events,
            [
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.nativeSocialAuthResult,
                    properties: [
                        "provider": "apple",
                        "mode": "sign_in_or_up",
                        "result": "failed",
                        "session_adoption": "none",
                        "failure_category": "token_unavailable"
                    ]
                )
            ]
        )
        XCTAssertEqual(
            analytics.events.map(WanderAnalyticsSchema.sanitized),
            analytics.events
        )
    }

    func testUnmatchedAppleLoginRequiresExistingAccountProofWithoutCreatingAnAccount() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthOutcome: .requiresExistingAccountVerification
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.authenticate(with: .apple)

        XCTAssertEqual(outcome, .requiresExistingAccountVerification)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertNil(store.activeSocialAuthProvider)
        XCTAssertEqual(
            store.nativeAuthError,
            "We couldn’t match that Apple login to an existing account. Sign in with the method you originally used. Your saved places and people are still there."
        )
    }

    func testGoogleLoginUsesNativeProviderPathAndCompletesSession() async {
        let session = AuthSession(userID: "user_google", displayName: "Google User", handle: nil)
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthSession: session
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.authenticate(with: .google)

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(
            provider.requestedSocialAuth,
            [.init(provider: .google, mode: .signIn)]
        )
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertFalse(store.isPresentingNativeAuth)
    }

    func testEmailLoginSendsAndVerifiesCodeWithoutEnteringSignUp() async {
        let session = AuthSession(userID: "user_email", displayName: "Email User", handle: nil)
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            emailVerificationSession: session
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let didSendCode = await store.sendEmailCode(to: " person@example.com ")

        XCTAssertTrue(didSendCode)
        XCTAssertEqual(provider.requestedEmailCodes.count, 1)
        XCTAssertEqual(provider.requestedEmailCodes.first?.emailAddress, "person@example.com")
        XCTAssertEqual(provider.requestedEmailCodes.first?.mode, .signIn)
        XCTAssertEqual(store.emailVerificationAddress, "person@example.com")

        let outcome = await store.verifyEmailCode("123456")

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(provider.verifiedEmailCodes, ["123456"])
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertFalse(store.isPresentingNativeAuth)
    }

    func testMissingEmailAccountShowsLoginRecoveryInsteadOfEmailAlreadyTakenLoop() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            emailCodeFailure: AuthSessionError.accountNotFound
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let didSendCode = await store.sendEmailCode(to: "missing@example.com")

        XCTAssertFalse(didSendCode)
        XCTAssertNil(store.emailVerificationAddress)
        XCTAssertEqual(
            store.nativeAuthError,
            "We couldn’t find an account for that email. Try Apple or Google, or create an account."
        )
    }

    func testPasswordLoginCompletesDedicatedAccountWithoutChangingEmailCodeFlow() async {
        let session = AuthSession(
            userID: "user_app_review",
            displayName: "rec.me Reviewer",
            handle: "reviewer"
        )
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            passwordAuthSession: session
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.signInWithPassword(
            emailAddress: " reviewer@example.com ",
            password: "private-review-password"
        )

        XCTAssertEqual(outcome, .completed)
        XCTAssertEqual(provider.requestedPasswordSignInEmails, ["reviewer@example.com"])
        XCTAssertTrue(provider.requestedEmailCodes.isEmpty)
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertTrue(store.isSessionValidated)
        XCTAssertFalse(store.isPresentingNativeAuth)
        XCTAssertFalse(store.isSigningInWithPassword)
        XCTAssertNil(store.nativeAuthError)
    }

    func testPasswordLoginValidatesFieldsBeforeCallingProvider() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let invalidEmailOutcome = await store.signInWithPassword(
            emailAddress: "not-an-email",
            password: "password"
        )
        XCTAssertNil(invalidEmailOutcome)
        XCTAssertEqual(store.nativeAuthError, "Enter a valid email address.")
        XCTAssertTrue(provider.requestedPasswordSignInEmails.isEmpty)

        let emptyPasswordOutcome = await store.signInWithPassword(
            emailAddress: "reviewer@example.com",
            password: ""
        )
        XCTAssertNil(emptyPasswordOutcome)
        XCTAssertEqual(store.nativeAuthError, "Enter your password.")
        XCTAssertTrue(provider.requestedPasswordSignInEmails.isEmpty)
    }

    func testPasswordLoginUsesPrivacyPreservingCredentialError() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            passwordAuthFailure: AuthSessionError.invalidCredentials
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.signInWithPassword(
            emailAddress: "missing@example.com",
            password: "incorrect"
        )

        XCTAssertNil(outcome)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(store.nativeAuthError, "Email or password didn’t match.")
        XCTAssertFalse(store.isSigningInWithPassword)
    }

    func testPasswordLoginRejectsReviewerAccountThatNeedsAnotherFactor() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            passwordAuthOutcome: .requiresAdditionalVerification
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn(mode: .signIn)

        let outcome = await store.signInWithPassword(
            emailAddress: "reviewer@example.com",
            password: "password"
        )

        XCTAssertEqual(outcome, .requiresAdditionalVerification)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(
            store.nativeAuthError,
            "This account needs another verification step. Use email or another sign-in method."
        )
    }

    func testClerkAuthServiceDoesNotPresentNativeAuthWhenSDKConfigureReturnsUnconfiguredClient() {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let service = ClerkAuthService(
            configuration: configuration,
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { _ in "" }
        )

        XCTAssertEqual(service.state, .unavailable("Missing Clerk publishable key."))
        XCTAssertFalse(service.canPresentNativeAuth)
    }

    func testClerkSessionRefreshFallsBackToLastConfirmedIdentityWhenResolutionFails() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let resolution = AuthSessionResolutionHolder(.success(resolvedSession(session)))
        let cache = AuthSessionCacheHolder()
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: { try resolution.value.get() },
            sessionCache: cache.value,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        await service.refreshSession()
        XCTAssertEqual(service.state, .signedIn(session))

        resolution.value = .failure(.tokenUnavailable)
        await service.refreshSession()

        XCTAssertEqual(
            service.state,
            .offline(
                session,
                message: "Could not verify your session. Your saved map is available offline."
            )
        )
        XCTAssertEqual(cache.session, session)
    }

    func testClerkSessionRefreshWithoutCachedIdentityStillFailsClosed() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: { throw AuthSessionError.tokenUnavailable },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        await service.refreshSession()

        XCTAssertEqual(
            service.state,
            .unavailable("Could not verify your session. Check your connection and try again.")
        )
    }

    #if canImport(ClerkKit)
    func testCompletedNativeAuthRetriesUntilAuthoritativeSessionAppears() async throws {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let session = AuthSession(
            userID: "user_apple",
            displayName: "Apple User",
            handle: "apple"
        )
        var resolutions: [ClerkAuthService.ResolvedSession?] = [
            nil,
            nil,
            resolvedSession(session, clerkSessionID: "sess_apple")
        ]
        var sleepRequests: [UInt64] = []
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: { resolutions.removeFirst() },
            resolveSessionID: { "sess_apple" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [200, 600, 2_000],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { delay in sleepRequests.append(delay) },
            configureClerk: { $0 }
        )

        let adoption = try await service.adoptCompletedNativeAuthSession(
            expectedSessionID: "sess_apple"
        )

        XCTAssertEqual(adoption, .afterCompletionRetry)
        XCTAssertEqual(sleepRequests, [200, 600])
        XCTAssertEqual(service.state, .signedIn(session))
        XCTAssertTrue(resolutions.isEmpty)
    }

    func testCompletedNativeAuthFailsAfterBoundedSessionAdoptionRetries() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        var resolutionCount = 0
        var sleepRequests: [UInt64] = []
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolutionCount += 1
                return nil
            },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [200, 600],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { delay in sleepRequests.append(delay) },
            configureClerk: { $0 }
        )

        do {
            _ = try await service.adoptCompletedNativeAuthSession(
                expectedSessionID: "sess_apple"
            )
            XCTFail("Expected session adoption to fail closed")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .sessionUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(resolutionCount, 3)
        XCTAssertEqual(sleepRequests, [200, 600])
        XCTAssertEqual(service.state, .signedOut)
    }

    func testCompletedNativeAuthFenceRejectsLaterUnrelatedRefreshUntilExpectedSessionAppears() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let session = AuthSession(
            userID: "user_existing",
            displayName: "Existing User",
            handle: "existing"
        )
        let resolvedClerkSessionID = ClerkSessionIDHolder("sess_apple")
        let activeClerkSessionID = ClerkSessionIDHolder("sess_other")
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolvedSession(session, clerkSessionID: resolvedClerkSessionID.value)
            },
            resolveSessionID: { activeClerkSessionID.value },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [200, 600],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { _ in },
            configureClerk: { $0 }
        )

        do {
            _ = try await service.adoptCompletedNativeAuthSession(
                expectedSessionID: "sess_apple"
            )
            XCTFail("Expected adoption of an unrelated active session to fail closed")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .sessionUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.state, .signedOut)

        resolvedClerkSessionID.value = "sess_other"
        await service.refreshSession()
        XCTAssertEqual(service.state, .signedOut)

        resolvedClerkSessionID.value = "sess_apple"
        activeClerkSessionID.value = "sess_apple"
        await service.refreshSession()
        XCTAssertEqual(service.state, .signedIn(session))
    }

    func testNativeAuthFenceSurvivesServiceReinstantiation() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let unrelatedSession = AuthSession(
            userID: "user_unrelated",
            displayName: "Unrelated",
            handle: "unrelated"
        )
        let fenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-auth-fence-\(UUID().uuidString).json")
        let fenceStore = NativeAuthSessionFenceStore.file(url: fenceURL)
        defer { try? FileManager.default.removeItem(at: fenceURL) }

        let firstService = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolvedSession(unrelatedSession, clerkSessionID: "sess_other")
            },
            resolveSessionID: { "sess_other" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: fenceStore,
            sessionAdoptionRetryDelaysNanoseconds: [],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { _ in },
            configureClerk: { $0 }
        )

        _ = try? await firstService.adoptCompletedNativeAuthSession(
            expectedSessionID: "sess_expected"
        )
        XCTAssertEqual(
            fenceStore.load(),
            .require("sess_expected")
        )

        let relaunchedService = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolvedSession(unrelatedSession, clerkSessionID: "sess_other")
            },
            resolveSessionID: { "sess_other" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: fenceStore,
            configureClerk: { $0 }
        )

        await relaunchedService.refreshSession()

        XCTAssertEqual(relaunchedService.state, .signedOut)
        XCTAssertEqual(
            fenceStore.load(),
            .require("sess_expected")
        )
    }

    func testUncorrelatedNativeAuthFenceRejectsSessionAfterRelaunch() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let fenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("native-auth-block-\(UUID().uuidString).json")
        let fenceStore = NativeAuthSessionFenceStore.file(url: fenceURL)
        fenceStore.save(.blockUncorrelated)
        defer { try? FileManager.default.removeItem(at: fenceURL) }
        let session = AuthSession(
            userID: "user_unrelated",
            displayName: "Unrelated",
            handle: "unrelated"
        )
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolvedSession(session, clerkSessionID: "sess_unrelated")
            },
            resolveSessionID: { "sess_unrelated" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: fenceStore,
            configureClerk: { $0 }
        )

        await service.refreshSession()

        XCTAssertEqual(service.state, .signedOut)
        XCTAssertEqual(fenceStore.load(), .blockUncorrelated)
    }

    func testCompletedNativeAuthRejectsResolvedSessionFromDifferentID() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let session = AuthSession(
            userID: "user_existing",
            displayName: "Existing User",
            handle: "existing"
        )
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                resolvedSession(session, clerkSessionID: "sess_other")
            },
            resolveSessionID: { "sess_apple" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { _ in },
            configureClerk: { $0 }
        )

        do {
            _ = try await service.adoptCompletedNativeAuthSession(
                expectedSessionID: "sess_apple"
            )
            XCTFail("Expected adoption of a mismatched resolved session to fail closed")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .sessionUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(service.state, .signedOut)
    }

    func testCompletedNativeAuthTimesOutWhenAuthoritativeRefreshStalls() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        var resolverContinuation: CheckedContinuation<ClerkAuthService.ResolvedSession?, Never>?
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                await withCheckedContinuation { continuation in
                    resolverContinuation = continuation
                }
            },
            resolveSessionID: { nil },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [],
            sessionAdoptionTimeoutNanoseconds: 100_000_000,
            sessionAdoptionSleeper: { _ in },
            configureClerk: { $0 }
        )

        let adoptionTask = Task {
            try await service.adoptCompletedNativeAuthSession(
                expectedSessionID: "sess_apple"
            )
        }
        while resolverContinuation == nil { await Task.yield() }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            _ = try await adoptionTask.value
            XCTFail("Expected stalled session adoption to time out")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .sessionUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        XCTAssertLessThan(elapsed, 500_000_000)
        XCTAssertEqual(service.state, .signedOut)

        resolverContinuation?.resume(
            returning: resolvedSession(
                AuthSession(userID: "user_late", displayName: "Late", handle: "late"),
                clerkSessionID: "sess_apple"
            )
        )
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(service.state, .signedOut)
    }

    func testSessionChangesQuarantineUnrelatedSessionDuringNativeAuthAdoption() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let adoptionStarted = expectation(description: "session adoption started")
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                adoptionStarted.fulfill()
                try await Task<Never, Never>.sleep(nanoseconds: 30_000_000_000)
                return nil
            },
            resolveSessionID: { "sess_other" },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [],
            sessionAdoptionTimeoutNanoseconds: 1_000_000_000,
            sessionAdoptionSleeper: { _ in },
            configureClerk: { $0 }
        )

        let adoptionTask = Task {
            try await service.adoptCompletedNativeAuthSession(
                expectedSessionID: "sess_apple"
            )
        }
        await fulfillment(of: [adoptionStarted], timeout: 1)

        let observedSession = AuthState.signedIn(
            AuthSession(userID: "user_other", displayName: "Other", handle: "other")
        )
        XCTAssertFalse(
            service.shouldPublishSessionChange(
                observedState: .signedOut
            )
        )
        XCTAssertFalse(
            service.shouldPublishSessionChange(
                observedState: observedSession
            )
        )

        adoptionTask.cancel()
        _ = try? await adoptionTask.value
        XCTAssertFalse(
            service.shouldPublishSessionChange(
                observedState: observedSession
            )
        )
        XCTAssertTrue(
            service.shouldPublishSessionChange(
                observedState: .signedOut
            )
        )
    }
    #endif

    func testOfflineIdentityIsSignedInLocallyButCannotIssueRemoteTokens() async {
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let provider = PreviewAuthSessionProvider(
            state: .offline(session, message: "Offline"),
            token: "must-not-be-used"
        )
        let store = AuthSessionStore(provider: provider)

        await store.refreshSession()

        XCTAssertTrue(store.isSignedIn)
        XCTAssertFalse(store.isSessionValidated)
        do {
            _ = try await store.supabaseAccessToken()
            XCTFail("Expected offline token lookup to be blocked")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAuthSessionCacheOmitsContactInformation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("last-auth-session-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AuthSessionCache.file(url: url)

        cache.save(
            AuthSession(
                userID: "user_123",
                displayName: "Joe",
                handle: "joe",
                email: "joe@example.com",
                phoneNumber: "+15555550123"
            )
        )

        XCTAssertEqual(
            cache.load(),
            AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        )
    }

    #if canImport(ClerkKit)
    func testOnlyActiveClerkSessionStatusCanAuthenticate() {
        XCTAssertTrue(ClerkAuthService.isActiveSessionStatus(.active))

        let inactiveStatuses: [ClerkKit.Session.SessionStatus] = [
            .abandoned,
            .pending,
            .ended,
            .expired,
            .removed,
            .replaced,
            .revoked,
            .unknown("future")
        ]
        for status in inactiveStatuses {
            XCTAssertFalse(ClerkAuthService.isActiveSessionStatus(status))
        }
    }
    #endif

    func testOlderSessionRefreshCannotOverwriteNewerResult() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let firstStarted = expectation(description: "first refresh started")
        let secondStarted = expectation(description: "second refresh started")
        var requestCount = 0
        var firstContinuation: CheckedContinuation<ClerkAuthService.ResolvedSession?, Never>?
        var secondContinuation: CheckedContinuation<ClerkAuthService.ResolvedSession?, Never>?
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                requestCount += 1
                let requestNumber = requestCount
                return await withCheckedContinuation { continuation in
                    if requestNumber == 1 {
                        firstContinuation = continuation
                        firstStarted.fulfill()
                    } else {
                        secondContinuation = continuation
                        secondStarted.fulfill()
                    }
                }
            },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        let firstRefresh = Task { await service.refreshSession() }
        await fulfillment(of: [firstStarted], timeout: 1)
        let secondRefresh = Task { await service.refreshSession() }
        await fulfillment(of: [secondStarted], timeout: 1)

        let newerSession = AuthSession(userID: "user_b", displayName: "B", handle: "b")
        secondContinuation?.resume(returning: resolvedSession(newerSession))
        await secondRefresh.value
        XCTAssertEqual(service.state, .signedIn(newerSession))

        firstContinuation?.resume(
            returning: resolvedSession(
                AuthSession(userID: "user_a", displayName: "A", handle: "a")
            )
        )
        await firstRefresh.value
        XCTAssertEqual(service.state, .signedIn(newerSession))
    }

    #if canImport(ClerkKit)
    func testObservedClientChangeDuringRefreshCannotDiscardAuthenticatedSession() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let refreshStarted = expectation(description: "authoritative refresh started")
        var continuation: CheckedContinuation<ClerkAuthService.ResolvedSession?, Never>?
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                await withCheckedContinuation { pendingContinuation in
                    continuation = pendingContinuation
                    refreshStarted.fulfill()
                }
            },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        let refresh = Task { await service.refreshSession() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        // Clerk's refreshClient() emits sessionChanged before its caller
        // resumes. A stale client snapshot from that event must not invalidate
        // the authoritative refresh that is still in flight.
        service.applyObservedClientState(.signedOut)

        let authenticatedSession = AuthSession(
            userID: "user_authenticated",
            displayName: "Authenticated",
            handle: "authenticated"
        )
        continuation?.resume(returning: resolvedSession(authenticatedSession))
        await refresh.value

        XCTAssertEqual(service.state, .signedIn(authenticatedSession))
    }

    func testTerminalSignOutInvalidatesInFlightAuthenticatedRefresh() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let refreshStarted = expectation(description: "authoritative refresh started")
        var continuation: CheckedContinuation<ClerkAuthService.ResolvedSession?, Never>?
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                await withCheckedContinuation { pendingContinuation in
                    continuation = pendingContinuation
                    refreshStarted.fulfill()
                }
            },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        let refresh = Task { await service.refreshSession() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        service.applyTerminalSignedOutState()
        continuation?.resume(
            returning: resolvedSession(
                AuthSession(
                    userID: "user_stale",
                    displayName: "Stale",
                    handle: "stale"
                )
            )
        )
        await refresh.value

        XCTAssertEqual(service.state, .signedOut)
    }
    #endif

    func testCancelledSessionRefreshDoesNotReplaceValidatedState() async {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let validatedSession = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let cancellationStarted = expectation(description: "cancelled refresh started")
        var requestCount = 0
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: {
                requestCount += 1
                if requestCount == 1 { return resolvedSession(validatedSession) }
                cancellationStarted.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return resolvedSession(
                    AuthSession(userID: "stale", displayName: "Stale", handle: "stale")
                )
            },
            sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled,
            configureClerk: { $0 }
        )

        await service.refreshSession()
        let cancelledRefresh = Task { await service.refreshSession() }
        await fulfillment(of: [cancellationStarted], timeout: 1)
        cancelledRefresh.cancel()
        await cancelledRefresh.value

        XCTAssertEqual(service.state, .signedIn(validatedSession))
    }

    func testSupabaseTokenRequiresSignedInSession() async {
        let signedOutProvider = PreviewAuthSessionProvider(state: .signedOut, token: "token")
        let signedOutStore = AuthSessionStore(provider: signedOutProvider)

        do {
            _ = try await signedOutStore.supabaseAccessToken()
            XCTFail("Expected signed-out token lookup to throw")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let signedInProvider = PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "user_123", displayName: nil, handle: nil)),
            token: "token"
        )
        let signedInStore = AuthSessionStore(provider: signedInProvider)

        do {
            _ = try await signedInStore.supabaseAccessToken()
            XCTFail("Expected unvalidated token lookup to throw")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await signedInStore.refreshSession()
        let token = try? await signedInStore.supabaseAccessToken()

        XCTAssertEqual(token, "token")
    }

    func testSessionValidationBlocksTokensUntilRefreshCompletes() async throws {
        let provider = PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "user_123", displayName: nil, handle: nil)),
            token: "token"
        )
        let store = AuthSessionStore(provider: provider)
        await store.refreshSession()
        let validatedToken = try await store.supabaseAccessToken()
        XCTAssertEqual(validatedToken, "token")

        store.beginSessionValidation()

        do {
            _ = try await store.supabaseAccessToken()
            XCTFail("Expected access token lookup to be blocked during validation")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        }

        do {
            _ = try await store.refreshSupabaseAccessToken()
            XCTFail("Expected forced token refresh to be blocked during validation")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        }
    }

    func testAuthoritativeRefreshWinsAfterObservedSignedOutSnapshot() async throws {
        let session = AuthSession(
            userID: "user_123",
            displayName: "Joe",
            handle: "joe"
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(session: session)
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        let refresh = Task { await store.refreshSession() }
        while !provider.isRefreshSuspended { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertFalse(store.isSessionValidated)

        provider.finishRefresh()
        await refresh.value

        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertTrue(store.isSessionValidated)
        try await store.ensureSessionValidated(for: session.userID)

        provider.yieldSnapshotWithoutChangingState(.signedOut)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertTrue(store.isSessionValidated)
    }

    func testObservedAccountSwitchInvalidatesPendingRefresh() async throws {
        let firstSession = AuthSession(
            userID: "user_a",
            displayName: "A",
            handle: "a"
        )
        let secondSession = AuthSession(
            userID: "user_b",
            displayName: "B",
            handle: "b"
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(session: firstSession)
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        let firstRefresh = Task { await store.refreshSession() }
        while !provider.isRefreshSuspended { await Task.yield() }

        provider.shouldSuspendRefresh = false
        provider.setObservedState(.signedIn(secondSession))
        await waitForState(.signedIn(secondSession), in: store)
        while !store.isSessionValidated { await Task.yield() }

        provider.finishRefresh()
        await firstRefresh.value

        XCTAssertEqual(store.state, .signedIn(secondSession))
        XCTAssertTrue(store.isSessionValidated)
        try await store.ensureSessionValidated(for: secondSession.userID)
    }

    func testNativeAuthCancelsForegroundRefreshAndBlocksUnrelatedSessionEvents() async {
        let initialSession = AuthSession(
            userID: "user_initial",
            displayName: "Initial",
            handle: "initial"
        )
        let unrelatedSession = AuthSession(
            userID: "user_unrelated",
            displayName: "Unrelated",
            handle: "unrelated"
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(
            session: initialSession,
            canPresentNativeAuth: true
        )
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        let foregroundRefresh = Task { await store.refreshSession() }
        while !provider.isRefreshSuspended { await Task.yield() }

        store.beginSignIn()
        provider.setObservedState(.signedIn(unrelatedSession))
        for _ in 0..<20 { await Task.yield() }

        let refreshCountBeforeBlockedAttempt = provider.refreshCount
        await store.refreshSession()
        XCTAssertEqual(provider.refreshCount, refreshCountBeforeBlockedAttempt)

        provider.finishRefresh()
        await foregroundRefresh.value

        XCTAssertEqual(store.state, .signedIn(initialSession))
        XCTAssertFalse(store.isSessionValidated)
        XCTAssertTrue(store.isPresentingNativeAuth)
    }

    func testOriginalRefreshWaiterFollowsAccountSwitchReplacement() async throws {
        let firstSession = AuthSession(
            userID: "user_a",
            displayName: "A",
            handle: "a"
        )
        let secondSession = AuthSession(
            userID: "user_b",
            displayName: "B",
            handle: "b"
        )
        let provider = TwoStageAccountSwitchAuthProvider(
            firstSession: firstSession,
            secondSession: secondSession
        )
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        var originalWaiterFinished = false
        let originalWaiter = Task { @MainActor in
            await store.refreshSession()
            originalWaiterFinished = true
        }
        while !provider.isFirstRefreshSuspended { await Task.yield() }

        provider.switchToSecondAccount()
        while !provider.isReplacementRefreshSuspended { await Task.yield() }
        provider.finishFirstRefresh()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertFalse(originalWaiterFinished)
        XCTAssertFalse(store.isSessionValidated)

        provider.finishReplacementRefresh()
        await originalWaiter.value

        XCTAssertTrue(originalWaiterFinished)
        XCTAssertEqual(store.state, .signedIn(secondSession))
        XCTAssertTrue(store.isSessionValidated)
    }

    func testObservedSignedInCannotBypassExplicitSessionValidation() async throws {
        let session = AuthSession(
            userID: "user_123",
            displayName: "Cached",
            handle: "joe"
        )
        let observedSession = AuthSession(
            userID: session.userID,
            displayName: "Observed",
            handle: session.handle
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(session: session)
        provider.shouldSuspendRefresh = false
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        store.beginSessionValidation()
        provider.setObservedState(.signedIn(observedSession))
        await waitForState(.signedIn(observedSession), in: store)

        XCTAssertFalse(store.isSessionValidated)
        XCTAssertEqual(provider.refreshCount, 0)

        try await store.ensureSessionValidated(for: session.userID)

        XCTAssertEqual(provider.refreshCount, 1)
        XCTAssertTrue(store.isSessionValidated)
    }

    func testSignOutInvalidatesSuspendedSharedRefresh() async throws {
        let session = AuthSession(
            userID: "user_123",
            displayName: "Joe",
            handle: "joe"
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(session: session)
        let store = AuthSessionStore(provider: provider)
        while provider.sessionChangesRequestCount == 0 { await Task.yield() }

        let refresh = Task { await store.refreshSession() }
        while !provider.isRefreshSuspended { await Task.yield() }

        try await store.signOut()
        provider.finishRefresh()
        await refresh.value

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertFalse(store.isSessionValidated)
        do {
            try await store.ensureSessionValidated(for: session.userID)
            XCTFail("Expected the signed-out account to remain invalid")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notSignedIn)
        }
    }

    func testOverlappingTerminalAuthMutationIsRejected() async throws {
        let session = AuthSession(
            userID: "user_123",
            displayName: "Joe",
            handle: "joe"
        )
        let provider = ObservedSnapshotDuringRefreshAuthProvider(session: session)
        provider.shouldSuspendSignOut = true
        let store = AuthSessionStore(provider: provider)

        let signOut = Task { try await store.signOut() }
        while !provider.isSignOutSuspended { await Task.yield() }

        do {
            try await store.deleteAccount()
            XCTFail("Expected the overlapping account deletion to be rejected")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .sessionUnavailable)
        }

        provider.finishSignOut()
        try await signOut.value
        XCTAssertEqual(store.state, .signedOut)
    }

    func testFailedDeleteAccountRevalidatesTheExistingSession() async throws {
        let session = AuthSession(
            userID: "user_123",
            displayName: "Joe",
            handle: "joe"
        )
        let provider = PreviewAuthSessionProvider(state: .signedIn(session), token: "token")
        let store = AuthSessionStore(provider: provider)
        await store.refreshSession()

        do {
            try await store.deleteAccount()
            XCTFail("Expected the preview provider to reject account deletion")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .notConfigured)
        }

        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertTrue(store.isSessionValidated)
    }

    func testSignOutClearsSession() async throws {
        let provider = PreviewAuthSessionProvider(
            state: .signedIn(AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")),
            token: "token"
        )
        let store = AuthSessionStore(provider: provider)

        try await store.signOut()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertFalse(store.isSigningOut)
        XCTAssertNil(store.signOutError)
        XCTAssertFalse(store.isPresentingNativeAuth)
        XCTAssertNil(store.activeGate)
    }

    func testFailedSignOutKeepsSessionAndSurfacesError() async {
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let provider = PreviewAuthSessionProvider(
            state: .signedIn(session),
            token: "token",
            signOutError: AuthSessionError.tokenUnavailable
        )
        let store = AuthSessionStore(provider: provider)

        do {
            try await store.signOut()
            XCTFail("Expected sign out to throw")
        } catch let error as AuthSessionError {
            XCTAssertEqual(error, .tokenUnavailable)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(store.state, .signedIn(session))
        XCTAssertFalse(store.isSigningOut)
        XCTAssertEqual(store.signOutError, "Could not sign out. Try again.")
    }

    func testStoreTracksProviderLogoutWithoutManualRefresh() async {
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let provider = PreviewAuthSessionProvider(
            state: .signedIn(session),
            canPresentNativeAuth: true,
            token: "token"
        )
        let store = AuthSessionStore(provider: provider)
        store.presentGate(for: .syncPlace)
        store.isPresentingNativeAuth = true

        let signedOut = expectation(description: "provider logout reaches auth store")
        let observation = Task { @MainActor in
            while store.state != .signedOut {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }
            signedOut.fulfill()
        }
        defer { observation.cancel() }

        provider.setState(.signedOut)
        await fulfillment(of: [signedOut], timeout: 1)

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertNil(store.activeGate)
        XCTAssertFalse(store.isPresentingNativeAuth)
    }

    func testForegroundStyleRefreshRejectsSilentProviderLogout() async {
        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        let provider = PreviewAuthSessionProvider(state: .signedIn(session), token: "token")
        let store = AuthSessionStore(provider: provider)

        provider.setStateSilently(.signedOut)
        XCTAssertEqual(store.state, .signedIn(session))

        await store.refreshSession()

        XCTAssertEqual(store.state, .signedOut)
        XCTAssertEqual(
            WanderAppEntryView.destination(for: store.state, hasResolvedSession: true),
            .signIn
        )
    }

    func testWarmStartPolicySkipsValidationInsideThirtySecondGrace() {
        var policy = AppEntryForegroundRefreshPolicy()
        policy.didEnterBackground(atUptime: 100)

        XCTAssertFalse(policy.shouldRefreshSession(atUptime: 129.999))
    }

    func testWarmStartPolicyRefreshesAtGraceBoundaryAndWithoutBackgroundTimestamp() {
        var boundaryPolicy = AppEntryForegroundRefreshPolicy()
        boundaryPolicy.didEnterBackground(atUptime: 100)

        XCTAssertTrue(boundaryPolicy.shouldRefreshSession(atUptime: 130))

        var unknownBackgroundPolicy = AppEntryForegroundRefreshPolicy()
        XCTAssertTrue(unknownBackgroundPolicy.shouldRefreshSession(atUptime: 130))
    }

    func testWarmStartPolicyConsumesBackgroundTimestampAfterActivation() {
        var policy = AppEntryForegroundRefreshPolicy()
        policy.didEnterBackground(atUptime: 100)

        XCTAssertFalse(policy.shouldRefreshSession(atUptime: 110))
        XCTAssertTrue(policy.shouldRefreshSession(atUptime: 111))
    }

    func testAppSessionDestinationNeverShowsAppWithoutSignedInSession() {
        XCTAssertEqual(
            WanderAppEntryView.destination(for: .signedOut, hasResolvedSession: true),
            .signIn
        )
        XCTAssertEqual(
            WanderAppEntryView.destination(for: .loading, hasResolvedSession: true),
            .loading
        )
        XCTAssertEqual(
            WanderAppEntryView.destination(
                for: .unavailable("No auth"),
                hasResolvedSession: true
            ),
            .unavailable("No auth")
        )
        XCTAssertEqual(
            WanderAppEntryView.destination(
                for: .signedIn(AuthSession(userID: "user_123", displayName: nil, handle: nil)),
                hasResolvedSession: true
            ),
            .authenticated
        )
        XCTAssertEqual(
            WanderAppEntryView.destination(
                for: .signedIn(AuthSession(userID: "user_123", displayName: nil, handle: nil)),
                hasResolvedSession: false,
                isSessionValidated: true
            ),
            .loading
        )
        XCTAssertEqual(
            WanderAppEntryView.destination(
                for: .signedIn(AuthSession(userID: "user_123", displayName: nil, handle: nil)),
                hasResolvedSession: true,
                isSessionValidated: false
            ),
            .loading
        )
    }

    func testAuthGateCopyKeepsTrustPromisesClear() {
        let syncCopy = AuthGateIntent.syncPlace.copy
        XCTAssertTrue(syncCopy.message.contains("this phone"))
        XCTAssertTrue(syncCopy.message.contains("visibility setting"))

        let socialCopy = AuthGateIntent.socialSave.copy
        XCTAssertTrue(socialCopy.message.contains("whose map"))

        let followCopy = AuthGateIntent.followPeople.copy
        XCTAssertTrue(followCopy.message.contains("social map"))
    }

    func testSettingsTrustSurfaceKeepsAlphaPromisesClear() {
        XCTAssertEqual(SettingsTrustSurface.rowTitle, "Privacy and trust")
        XCTAssertEqual(SettingsTrustSurface.rowAccessibilityID, "settings.privacyTrust.row")
        XCTAssertEqual(SettingsTrustSurface.sheetAccessibilityID, "settings.privacyTrust.sheet")

        let facts = SettingsTrustSurface.facts
        XCTAssertEqual(facts.map(\.id), ["everyone", "stealth", "location", "extraction", "blocks", "contacts"])
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)

        XCTAssertTrue(facts.first { $0.id == "everyone" }?.body.contains("people who follow you") == true)
        XCTAssertTrue(facts.first { $0.id == "everyone" }?.body.contains("not a public internet feed") == true)
        XCTAssertTrue(facts.first { $0.id == "stealth" }?.body.contains("you only") == true)
        XCTAssertTrue(facts.first { $0.id == "location" }?.body.contains("does not broadcast live location") == true)
        XCTAssertTrue(facts.first { $0.id == "extraction" }?.body.contains("never auto-save") == true)
        XCTAssertTrue(facts.first { $0.id == "blocks" }?.body.contains("hides profiles, places, search results, and map content") == true)
        XCTAssertTrue(facts.first { $0.id == "contacts" }?.body.contains("asks for Contacts access only") == true)
        XCTAssertTrue(facts.first { $0.id == "contacts" }?.body.contains("iOS Settings") == true)
    }

    func testSettingsAccountIdentityNeverFallsBackToInternalUserID() {
        let withoutPublicHandle = AuthSession(
            userID: "user_internal_123",
            displayName: "Joe",
            handle: nil
        )
        let withPublicHandle = AuthSession(
            userID: "user_internal_456",
            displayName: "Joe",
            handle: "joelipshutz"
        )
        let withPrefixedPublicHandle = AuthSession(
            userID: "user_internal_789",
            displayName: "Joe",
            handle: "@joelipshutz"
        )
        let withBlankHandle = AuthSession(
            userID: "user_internal_000",
            displayName: "Joe",
            handle: "   "
        )

        XCTAssertNil(SettingsAccountIdentityPresentation.publicHandle(for: withoutPublicHandle))
        XCTAssertEqual(SettingsAccountIdentityPresentation.publicHandle(for: withPublicHandle), "@joelipshutz")
        XCTAssertEqual(SettingsAccountIdentityPresentation.publicHandle(for: withPrefixedPublicHandle), "@joelipshutz")
        XCTAssertNil(SettingsAccountIdentityPresentation.publicHandle(for: withBlankHandle))
    }

    func testSettingsAccountIdentityNormalizesContactDetails() {
        let session = AuthSession(
            userID: "user_internal_123",
            displayName: "Ryan",
            handle: "ryan",
            email: "  ryan@example.com  ",
            phoneNumber: "  +1 (323) 555-0119  "
        )
        let blankContacts = AuthSession(
            userID: "user_internal_456",
            displayName: "Ryan",
            handle: "ryan",
            email: "   ",
            phoneNumber: "\n"
        )

        XCTAssertEqual(SettingsAccountIdentityPresentation.emailAddress(for: session), "ryan@example.com")
        XCTAssertEqual(SettingsAccountIdentityPresentation.phoneNumber(for: session), "+1 (323) 555-0119")
        XCTAssertNil(SettingsAccountIdentityPresentation.emailAddress(for: blankContacts))
        XCTAssertNil(SettingsAccountIdentityPresentation.phoneNumber(for: blankContacts))
    }

    func testSettingsPrivacyCopyExplainsDefaultStealthAndPrivateProfileSearch() {
        XCTAssertEqual(SettingsDefaultPlacePrivacySurface.toggleTitle, "stealth mode for new saves")

        let notPrivateCopy = SettingsDefaultPlacePrivacySurface.helperCopy(for: .followers)
        XCTAssertTrue(notPrivateCopy.contains("new places"))
        XCTAssertTrue(notPrivateCopy.contains("people who follow you"))
        XCTAssertTrue(notPrivateCopy.contains("turn stealth on"))

        let privateCopy = SettingsDefaultPlacePrivacySurface.helperCopy(for: .selfOnly)
        XCTAssertTrue(privateCopy.contains("new places start private"))
        XCTAssertTrue(privateCopy.contains("Only you can see them"))

        let lockedCopy = SettingsDefaultPlacePrivacySurface.helperCopy(for: .selfOnly, isLockedByPrivateProfile: true)
        XCTAssertTrue(lockedCopy.contains("Locked on by Private Profile"))
        XCTAssertTrue(lockedCopy.contains("while Private Profile is on"))

        XCTAssertEqual(SettingsProfilePrivacySurface.title, "Private profile")
        XCTAssertTrue(SettingsProfilePrivacySurface.body(isEnabled: true).contains("saved places are in stealth mode"))
        XCTAssertTrue(SettingsProfilePrivacySurface.body(isEnabled: true).contains("new collaborative lists are unavailable"))
        XCTAssertTrue(SettingsProfilePrivacySurface.body(isEnabled: false).contains("username can appear in search"))
        XCTAssertFalse(SettingsProfilePrivacySurface.body(isEnabled: false).contains("Stealth mode below"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("Places saved by you will switch to stealth mode"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("check-ins and Wanna Go"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("username will be hidden"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("existing collaborative lists stay unchanged"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("new collaborative lists are unavailable"))
        XCTAssertFalse(SettingsProfilePrivacySurface.warningBody(enabling: true).contains("Stealth mode will stay activated"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: false).contains("username can appear in search again"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: false).contains("existing places will stay in stealth mode"))
        XCTAssertTrue(SettingsProfilePrivacySurface.warningBody(enabling: false).contains("future saves will follow"))
    }

    private func waitForState(
        _ expectedState: AuthState,
        in store: AuthSessionStore,
        timeout: TimeInterval = 1
    ) async {
        let stateReached = expectation(description: "auth store reaches expected state")
        let observation = Task { @MainActor in
            while store.state != expectedState {
                guard !Task.isCancelled else { return }
                await Task.yield()
            }
            stateReached.fulfill()
        }
        await fulfillment(of: [stateReached], timeout: timeout)
        observation.cancel()
    }
}

@MainActor
private final class AuthSessionResolutionHolder {
    var value: Result<ClerkAuthService.ResolvedSession?, AuthSessionError>

    init(_ value: Result<ClerkAuthService.ResolvedSession?, AuthSessionError>) {
        self.value = value
    }
}

@MainActor
private final class ClerkSessionIDHolder {
    var value: String

    init(_ value: String) {
        self.value = value
    }
}

#if canImport(ClerkKit)
private func resolvedSession(
    _ authSession: AuthSession,
    clerkSessionID: String = "sess_test"
) -> ClerkAuthService.ResolvedSession {
    ClerkAuthService.ResolvedSession(
        clerkSessionID: clerkSessionID,
        authSession: authSession
    )
}
#endif

@MainActor
private final class AuthSessionCacheHolder {
    var session: AuthSession?

    var value: AuthSessionCache {
        AuthSessionCache(
            load: { [weak self] in self?.session },
            save: { [weak self] session in self?.session = session }
        )
    }
}

@MainActor
private final class ObservedSnapshotDuringRefreshAuthProvider: AuthSessionProviding {
    private(set) var state: AuthState
    private(set) var sessionChangesRequestCount = 0
    private(set) var isRefreshSuspended = false
    private(set) var refreshCount = 0
    var shouldSuspendRefresh = true
    var shouldSuspendSignOut = false
    private(set) var isSignOutSuspended = false

    private let session: AuthSession
    private let changes: AsyncStream<AuthState>
    private let changesContinuation: AsyncStream<AuthState>.Continuation
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private var signOutContinuation: CheckedContinuation<Void, Never>?
    private let nativeAuthAvailable: Bool

    init(session: AuthSession, canPresentNativeAuth: Bool = false) {
        self.session = session
        nativeAuthAvailable = canPresentNativeAuth
        state = .signedIn(session)
        (changes, changesContinuation) = AsyncStream<AuthState>.makeStream()
    }

    var canPresentNativeAuth: Bool { nativeAuthAvailable }

    func sessionChanges() -> AsyncStream<AuthState> {
        sessionChangesRequestCount += 1
        return changes
    }

    func refreshSession() async {
        refreshCount += 1
        guard shouldSuspendRefresh else { return }
        state = .signedOut
        changesContinuation.yield(.signedOut)
        isRefreshSuspended = true
        await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
        isRefreshSuspended = false
        guard !Task.isCancelled else { return }
        state = .signedIn(session)
    }

    func finishRefresh() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }

    func yieldSnapshotWithoutChangingState(_ state: AuthState) {
        changesContinuation.yield(state)
    }

    func setObservedState(_ state: AuthState) {
        self.state = state
        changesContinuation.yield(state)
    }

    func signOut() async throws {
        if shouldSuspendSignOut {
            isSignOutSuspended = true
            await withCheckedContinuation { continuation in
                signOutContinuation = continuation
            }
            isSignOutSuspended = false
        }
        state = .signedOut
        changesContinuation.yield(.signedOut)
    }

    func finishSignOut() {
        signOutContinuation?.resume()
        signOutContinuation = nil
    }

    func supabaseAccessToken() async throws -> String {
        guard case .signedIn = state else { throw AuthSessionError.notSignedIn }
        return "test-token"
    }
}

@MainActor
private final class TwoStageAccountSwitchAuthProvider: AuthSessionProviding {
    private(set) var state: AuthState
    private(set) var sessionChangesRequestCount = 0
    private(set) var isFirstRefreshSuspended = false
    private(set) var isReplacementRefreshSuspended = false

    private let firstSession: AuthSession
    private let secondSession: AuthSession
    private let changes: AsyncStream<AuthState>
    private let changesContinuation: AsyncStream<AuthState>.Continuation
    private var refreshCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private var replacementContinuation: CheckedContinuation<Void, Never>?

    init(firstSession: AuthSession, secondSession: AuthSession) {
        self.firstSession = firstSession
        self.secondSession = secondSession
        state = .signedIn(firstSession)
        (changes, changesContinuation) = AsyncStream<AuthState>.makeStream()
    }

    var canPresentNativeAuth: Bool { false }

    func sessionChanges() -> AsyncStream<AuthState> {
        sessionChangesRequestCount += 1
        return changes
    }

    func refreshSession() async {
        refreshCount += 1
        if refreshCount == 1 {
            isFirstRefreshSuspended = true
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
            isFirstRefreshSuspended = false
            guard !Task.isCancelled else { return }
            state = .signedIn(firstSession)
            return
        }
        isReplacementRefreshSuspended = true
        await withCheckedContinuation { continuation in
            replacementContinuation = continuation
        }
        isReplacementRefreshSuspended = false
        guard !Task.isCancelled else { return }
        state = .signedIn(secondSession)
    }

    func switchToSecondAccount() {
        state = .signedIn(secondSession)
        changesContinuation.yield(state)
    }

    func finishFirstRefresh() {
        firstContinuation?.resume()
        firstContinuation = nil
    }

    func finishReplacementRefresh() {
        replacementContinuation?.resume()
        replacementContinuation = nil
    }

    func signOut() async throws {
        state = .signedOut
        changesContinuation.yield(state)
    }

    func supabaseAccessToken() async throws -> String {
        guard case .signedIn = state else { throw AuthSessionError.notSignedIn }
        return "test-token"
    }
}

private final class AuthRecordingAnalyticsClient: AnalyticsClient {
    private(set) var events: [AnalyticsEvent] = []

    func track(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func identify(userID: String) {}
    func resetIdentity() {}
}
