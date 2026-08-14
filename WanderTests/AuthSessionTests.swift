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
            configureClerk: { publishableKey in publishableKey }
        )
        let store = AuthSessionStore(provider: service)

        store.presentGate(for: .syncPlace)
        store.beginSignIn()

        XCTAssertNil(store.activeGate)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(store.state, .loading)
    }

    func testNativeAuthAttemptSurvivesTransientProviderStatesAndClosesOnSuccess() async {
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true
        )
        let store = AuthSessionStore(provider: provider)

        store.beginSignIn(mode: .signUp)
        XCTAssertTrue(store.isPresentingNativeAuth)

        provider.setState(.loading)
        await waitForState(.loading, in: store)
        XCTAssertTrue(store.isPresentingNativeAuth)

        provider.setState(.signedOut)
        await waitForState(.signedOut, in: store)
        XCTAssertTrue(store.isPresentingNativeAuth)

        let session = AuthSession(userID: "user_123", displayName: "Joe", handle: "joe")
        provider.setState(.signedIn(session))
        await waitForState(.signedIn(session), in: store)

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
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthSession: session
        )
        let store = AuthSessionStore(provider: provider)
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
        let provider = PreviewAuthSessionProvider(
            state: .signedOut,
            canPresentNativeAuth: true,
            nativeAuthFailure: AuthSessionError.tokenUnavailable
        )
        let store = AuthSessionStore(provider: provider)
        store.beginSignIn()

        let outcome = await store.authenticate(with: .apple)

        XCTAssertNil(outcome)
        XCTAssertTrue(store.isPresentingNativeAuth)
        XCTAssertEqual(
            store.nativeAuthError,
            "Apple sign-in didn’t finish. Try again or use another method."
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
            "We couldn’t match that Apple login to an existing account. Sign in with your original method first, then connect Apple in Settings."
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

    func testClerkAuthServiceDoesNotPresentNativeAuthWhenSDKConfigureReturnsUnconfiguredClient() {
        let configuration = WanderBackendConfiguration.current { key in
            "$(\(key))"
        }
        let service = ClerkAuthService(
            configuration: configuration,
            sessionCache: .disabled,
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
        let resolution = AuthSessionResolutionHolder(.success(session))
        let cache = AuthSessionCacheHolder()
        let service = ClerkAuthService(
            configuration: configuration,
            resolveSession: { try resolution.value.get() },
            sessionCache: cache.value,
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
            configureClerk: { $0 }
        )

        await service.refreshSession()

        XCTAssertEqual(
            service.state,
            .unavailable("Could not verify your session. Check your connection and try again.")
        )
    }

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
        var firstContinuation: CheckedContinuation<AuthSession?, Never>?
        var secondContinuation: CheckedContinuation<AuthSession?, Never>?
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
            configureClerk: { $0 }
        )

        let firstRefresh = Task { await service.refreshSession() }
        await fulfillment(of: [firstStarted], timeout: 1)
        let secondRefresh = Task { await service.refreshSession() }
        await fulfillment(of: [secondStarted], timeout: 1)

        let newerSession = AuthSession(userID: "user_b", displayName: "B", handle: "b")
        secondContinuation?.resume(returning: newerSession)
        await secondRefresh.value
        XCTAssertEqual(service.state, .signedIn(newerSession))

        firstContinuation?.resume(
            returning: AuthSession(userID: "user_a", displayName: "A", handle: "a")
        )
        await firstRefresh.value
        XCTAssertEqual(service.state, .signedIn(newerSession))
    }

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
                if requestCount == 1 { return validatedSession }
                cancellationStarted.fulfill()
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return AuthSession(userID: "stale", displayName: "Stale", handle: "stale")
            },
            sessionCache: .disabled,
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
    var value: Result<AuthSession?, AuthSessionError>

    init(_ value: Result<AuthSession?, AuthSessionError>) {
        self.value = value
    }
}

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
