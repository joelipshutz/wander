import XCTest
@testable import Wander

@MainActor
final class FeatureFlagTests: XCTestCase {
    func testRegistryContainsEveryHostedFlagAndTypedDefinitions() {
        XCTAssertEqual(
            FeatureFlagKey.allCases.map(\.rawValue),
            [
                "first_visit_nux",
                "debug_settings",
                "place_profile_save_tray_v1",
                "semantic_place_search_v1",
                "social_import_apify_gemini_v1",
                "place_profile_action_variant",
            ]
        )
        XCTAssertEqual(FeatureFlagKey.placeProfileSaveTrayV1.definition.valueKind, .boolean)
        XCTAssertTrue(FeatureFlagKey.placeProfileSaveTrayV1.definition.isEditableOnDevice)
        XCTAssertEqual(FeatureFlagKey.placeProfileActionVariant.definition.valueKind, .integer)
        XCTAssertEqual(FeatureFlagKey.placeProfileActionVariant.definition.integerRange, 1 ... 5)
        XCTAssertFalse(FeatureFlagKey.debugSettings.definition.isEditableOnDevice)
        XCTAssertEqual(
            FeatureFlagKey.socialImportApifyGeminiV1.definition.bundledDefault,
            .boolean(false)
        )
        XCTAssertTrue(
            FeatureFlagKey.socialImportApifyGeminiV1.definition.allowsRemoteAccountOverride
        )
        XCTAssertTrue(FeatureFlagKey.socialImportApifyGeminiV1.definition.isEditableOnDevice)
    }

    func testOverrideStorePersistsBooleanAndIntegerValuesPerAccount() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureFlagOverrideStore(defaults: defaults)

        store.setOverride(.boolean(true), for: .placeProfileSaveTrayV1, userID: "user_a")
        store.setOverride(.integer(2), for: .placeProfileActionVariant, userID: "user_a")
        store.setOverride(.integer(99), for: .placeProfileActionVariant, userID: "user_a")

        XCTAssertEqual(
            store.override(for: .placeProfileSaveTrayV1, userID: "user_a"),
            .boolean(true)
        )
        XCTAssertEqual(
            store.override(for: .placeProfileActionVariant, userID: "user_a"),
            .integer(2),
            "An invalid integer must not replace the last valid override."
        )
        XCTAssertNil(store.override(for: .placeProfileSaveTrayV1, userID: "user_b"))

        store.clearAllOverrides(for: "user_a")
        XCTAssertTrue(store.overrides(for: "user_a").isEmpty)
    }

    func testLaunchSnapshotMakesChangesApplyOnlyAfterRestartAndResetReturnsToRemote() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureFlagOverrideStore(defaults: defaults)
        let remoteValues: [FeatureFlagKey: ResolvedFeatureFlagValue] = [
            .placeProfileSaveTrayV1: ResolvedFeatureFlagValue(
                isEnabled: false,
                source: .globalDefault
            )
        ]

        let runningBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        await runningBackend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(runningBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), false)

        store.setOverride(.boolean(true), for: .placeProfileSaveTrayV1, userID: "user_a")
        XCTAssertEqual(
            runningBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"),
            false,
            "The running process must keep the launch snapshot until restart."
        )

        let restartedBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        XCTAssertEqual(restartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), true)
        XCTAssertEqual(
            restartedBackend.resolvedFeatureFlag(.placeProfileSaveTrayV1, for: "user_a")?.source,
            .deviceOverride
        )

        store.clearOverride(for: .placeProfileSaveTrayV1, userID: "user_a")
        XCTAssertEqual(restartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"), true)

        let resetAndRestartedBackend = WanderBackend(
            featureFlagRepository: FeatureFlagTestRepository(values: remoteValues),
            featureFlagDeviceOverrides: store.launchSnapshot()
        )
        await resetAndRestartedBackend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(
            resetAndRestartedBackend.featureFlag(.placeProfileSaveTrayV1, for: "user_a"),
            false
        )
        XCTAssertEqual(
            resetAndRestartedBackend.resolvedFeatureFlag(.placeProfileSaveTrayV1, for: "user_a")?.source,
            .globalDefault
        )
    }

    func testLegacyNUXAndPlaceActionOverridesAreReadAndMigrated() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "wander.debugSettings.user_a.firstVisitNUX.enabled")
        defaults.set(3, forKey: "wander.debugSettings.user_a.placeActionVariant")
        let store = FeatureFlagOverrideStore(defaults: defaults)

        XCTAssertEqual(store.override(for: .firstVisitNUX, userID: "user_a"), .boolean(true))
        XCTAssertEqual(store.override(for: .placeProfileActionVariant, userID: "user_a"), .integer(3))

        store.setOverride(.integer(4), for: .placeProfileActionVariant, userID: "user_a")
        XCTAssertNil(defaults.object(forKey: "wander.debugSettings.user_a.placeActionVariant"))
        XCTAssertEqual(store.override(for: .placeProfileActionVariant, userID: "user_a"), .integer(4))
    }

    func testSocialImportProviderWaitsForTheColdLaunchAccountFlag() async throws {
        let understanding = FeatureFlagUnderstandingRepository()
        let flags = GatedFeatureFlagTestRepository(values: [
            .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                isEnabled: true,
                source: .accountOverride
            )
        ])
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: flags
        )
        let provider = backend.socialImportUnderstandingProvider(for: "user_a")
        XCTAssertNil(backend.featureFlag(.socialImportApifyGeminiV1, for: "user_a"))

        let rootRefresh = Task { await backend.refreshFeatureFlags(for: "user_a") }
        while flags.startedRequestCount < 1 { await Task.yield() }
        let importRequest = Task {
            try await provider.understand(
                url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/cold-launch-example/")),
                source: .instagram,
                clientRequestID: "cold-launch-request"
            )
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(flags.startedRequestCount, 1)
        XCTAssertEqual(understanding.requestCount, 0)
        flags.complete()
        await rootRefresh.value
        let result = try await importRequest.value

        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(understanding.requestCount, 1)
        XCTAssertEqual(backend.featureFlag(.socialImportApifyGeminiV1, for: "user_a"), true)
    }

    func testSocialImportProviderWaitsForForegroundRetryAfterEarlierFlagFailure() async throws {
        let understanding = FeatureFlagUnderstandingRepository()
        let flags = RecoveringGatedFeatureFlagTestRepository(values: [
            .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                isEnabled: true,
                source: .accountOverride
            )
        ])
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: flags
        )
        let provider = backend.socialImportUnderstandingProvider(for: "user_a")

        await backend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(backend.featureFlagResolution, .failed(userID: "user_a"))
        XCTAssertEqual(backend.featureFlag(.socialImportApifyGeminiV1, for: "user_a"), false)

        let foregroundRefresh = Task { await backend.refreshFeatureFlags(for: "user_a") }
        while flags.startedRequestCount < 2 { await Task.yield() }
        let importRequest = Task {
            try await provider.understand(
                url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/foreground-retry/")),
                source: .instagram,
                clientRequestID: "foreground-retry-request"
            )
        }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(flags.startedRequestCount, 2)
        XCTAssertEqual(understanding.requestCount, 0)

        flags.completeRecovery()
        await foregroundRefresh.value
        let result = try await importRequest.value

        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(understanding.requestCount, 1)
        XCTAssertEqual(backend.featureFlag(.socialImportApifyGeminiV1, for: "user_a"), true)
    }

    func testSocialImportProviderRetriesFailedFlagStateBeforeUsingBundledDefault() async throws {
        let understanding = FeatureFlagUnderstandingRepository()
        let flags = FailOnceFeatureFlagTestRepository(values: [
            .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                isEnabled: true,
                source: .accountOverride
            )
        ])
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: flags
        )

        await backend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(backend.featureFlagResolution, .failed(userID: "user_a"))

        let result = try await backend.socialImportUnderstandingProvider(for: "user_a").understand(
            url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/retry-failed-flag/")),
            source: .instagram,
            clientRequestID: "retry-failed-flag-request"
        )

        XCTAssertEqual(flags.requestCount, 2)
        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(understanding.requestCount, 1)
        XCTAssertEqual(backend.featureFlag(.socialImportApifyGeminiV1, for: "user_a"), true)
    }

    func testSocialImportProviderDoesNotTreatFailedFlagRefreshAsDisabled() async throws {
        let understanding = FeatureFlagUnderstandingRepository()
        let flags = AlwaysFailingFeatureFlagTestRepository()
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: flags
        )

        await backend.refreshFeatureFlags(for: "user_a")
        XCTAssertEqual(backend.featureFlagResolution, .failed(userID: "user_a"))

        let result = try await backend.socialImportUnderstandingProvider(for: "user_a").understand(
            url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/flag-unavailable/")),
            source: .instagram,
            clientRequestID: "flag-unavailable-request"
        )

        XCTAssertEqual(flags.requestCount, 2)
        XCTAssertEqual(result.outcome, .fallback)
        XCTAssertEqual(result.diagnostics.failureCategory, "feature_flag_unavailable")
        XCTAssertEqual(understanding.requestCount, 0)
    }

    func testSocialImportProviderWaitsForForegroundSessionValidationBeforeHostedCall() async throws {
        let session = AuthSession(userID: "user_a", displayName: nil, handle: nil)
        let authProvider = GatedSocialImportAuthProvider(state: .signedIn(session))
        let auth = AuthSessionStore(provider: authProvider)
        await auth.refreshSession()
        authProvider.shouldSuspendRefresh = true
        auth.beginSessionValidation()

        let understanding = FeatureFlagUnderstandingRepository()
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: FeatureFlagTestRepository(values: [
                .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                    isEnabled: true,
                    source: .accountOverride
                )
            ])
        )
        let provider = backend.socialImportUnderstandingProvider(
            for: session.userID,
            authSession: auth
        )

        let foregroundRefresh = Task { await auth.refreshSession() }
        while !authProvider.isRefreshSuspended { await Task.yield() }
        let observedSession = AuthSession(
            userID: session.userID,
            displayName: "Observed snapshot",
            handle: session.handle
        )
        authProvider.setObservedState(.signedIn(observedSession))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(auth.state, .signedIn(session))
        XCTAssertFalse(auth.isSessionValidated)
        let importRequest = Task {
            try await provider.understand(
                url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/foreground-auth/")),
                source: .instagram,
                clientRequestID: "foreground-auth-request"
            )
        }
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(authProvider.refreshCount, 2)
        XCTAssertEqual(understanding.requestCount, 0)

        authProvider.resumeRefresh()
        await foregroundRefresh.value
        let result = try await importRequest.value

        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(authProvider.refreshCount, 2)
        XCTAssertEqual(understanding.requestCount, 1)
    }

    func testSocialImportProviderReportsAuthUnavailableWithoutCallingHostedRepository() async throws {
        let session = AuthSession(userID: "user_a", displayName: nil, handle: nil)
        let authProvider = GatedSocialImportAuthProvider(state: .offline(session, message: "Offline"))
        let auth = AuthSessionStore(provider: authProvider)
        let understanding = FeatureFlagUnderstandingRepository()
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: FeatureFlagTestRepository(values: [
                .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                    isEnabled: true,
                    source: .accountOverride
                )
            ])
        )

        let result = try await backend.socialImportUnderstandingProvider(
            for: session.userID,
            authSession: auth
        ).understand(
            url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/offline-auth/")),
            source: .instagram,
            clientRequestID: "offline-auth-request"
        )

        XCTAssertEqual(result.outcome, .fallback)
        XCTAssertEqual(result.diagnostics.failureCategory, "auth_unavailable")
        XCTAssertEqual(understanding.requestCount, 0)
    }

    func testSocialImportProviderTranslatesAuthFailureAfterAdmission() async throws {
        let session = AuthSession(userID: "user_a", displayName: nil, handle: nil)
        let authProvider = GatedSocialImportAuthProvider(state: .signedIn(session))
        let auth = AuthSessionStore(provider: authProvider)
        await auth.refreshSession()
        let understanding = InvalidatingAuthUnderstandingRepository(auth: auth)
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: FeatureFlagTestRepository(values: [
                .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                    isEnabled: true,
                    source: .accountOverride
                )
            ])
        )

        let result = try await backend.socialImportUnderstandingProvider(
            for: session.userID,
            authSession: auth
        ).understand(
            url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/auth-use-race/")),
            source: .instagram,
            clientRequestID: "auth-use-race-request"
        )

        XCTAssertEqual(understanding.requestCount, 1)
        XCTAssertEqual(result.outcome, .fallback)
        XCTAssertEqual(result.diagnostics.failureCategory, "auth_unavailable")
    }

    func testDeviceOffOverrideNeverCallsThePaidSocialImportRepository() async throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let overrideStore = FeatureFlagOverrideStore(defaults: defaults)
        overrideStore.setOverride(
            .boolean(false),
            for: .socialImportApifyGeminiV1,
            userID: "user_a"
        )
        let understanding = FeatureFlagUnderstandingRepository()
        let backend = WanderBackend(
            socialImportUnderstandingRepository: understanding,
            featureFlagRepository: FeatureFlagTestRepository(values: [
                .socialImportApifyGeminiV1: ResolvedFeatureFlagValue(
                    isEnabled: true,
                    source: .accountOverride
                )
            ]),
            featureFlagDeviceOverrides: overrideStore.launchSnapshot()
        )

        let result = try await backend.socialImportUnderstandingProvider(for: "user_a").understand(
            url: try XCTUnwrap(URL(string: "https://www.instagram.com/p/disabled-example/")),
            source: .instagram,
            clientRequestID: "disabled-request"
        )

        XCTAssertEqual(result.outcome, .fallback)
        XCTAssertEqual(result.diagnostics.failureCategory, "feature_disabled")
        XCTAssertEqual(understanding.requestCount, 0)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "FeatureFlagTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

@MainActor
private struct FeatureFlagTestRepository: FeatureFlagRepository {
    let values: [FeatureFlagKey: ResolvedFeatureFlagValue]

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        values
    }
}

@MainActor
private final class GatedFeatureFlagTestRepository: FeatureFlagRepository {
    let values: [FeatureFlagKey: ResolvedFeatureFlagValue]
    private var continuation: CheckedContinuation<[FeatureFlagKey: ResolvedFeatureFlagValue], Never>?
    private(set) var startedRequestCount = 0

    init(values: [FeatureFlagKey: ResolvedFeatureFlagValue]) {
        self.values = values
    }

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        startedRequestCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete() {
        continuation?.resume(returning: values)
        continuation = nil
    }
}

@MainActor
private final class RecoveringGatedFeatureFlagTestRepository: FeatureFlagRepository {
    private enum TestError: Error {
        case firstRequestFailed
    }

    let values: [FeatureFlagKey: ResolvedFeatureFlagValue]
    private var recoveryContinuation: CheckedContinuation<
        [FeatureFlagKey: ResolvedFeatureFlagValue],
        Never
    >?
    private(set) var startedRequestCount = 0

    init(values: [FeatureFlagKey: ResolvedFeatureFlagValue]) {
        self.values = values
    }

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        startedRequestCount += 1
        if startedRequestCount == 1 {
            throw TestError.firstRequestFailed
        }
        return await withCheckedContinuation { continuation in
            recoveryContinuation = continuation
        }
    }

    func completeRecovery() {
        recoveryContinuation?.resume(returning: values)
        recoveryContinuation = nil
    }
}

@MainActor
private final class FailOnceFeatureFlagTestRepository: FeatureFlagRepository {
    private enum TestError: Error {
        case firstRequestFailed
    }

    let values: [FeatureFlagKey: ResolvedFeatureFlagValue]
    private(set) var requestCount = 0

    init(values: [FeatureFlagKey: ResolvedFeatureFlagValue]) {
        self.values = values
    }

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        requestCount += 1
        if requestCount == 1 {
            throw TestError.firstRequestFailed
        }
        return values
    }
}

@MainActor
private final class AlwaysFailingFeatureFlagTestRepository: FeatureFlagRepository {
    private enum TestError: Error {
        case unavailable
    }

    private(set) var requestCount = 0

    func resolvedFlags(for userID: String) async throws -> [FeatureFlagKey: ResolvedFeatureFlagValue] {
        requestCount += 1
        throw TestError.unavailable
    }
}

@MainActor
private final class GatedSocialImportAuthProvider: AuthSessionProviding {
    private(set) var state: AuthState
    var shouldSuspendRefresh = false
    private(set) var isRefreshSuspended = false
    private(set) var refreshCount = 0
    private var refreshContinuation: CheckedContinuation<Void, Never>?
    private let changes: AsyncStream<AuthState>
    private let changesContinuation: AsyncStream<AuthState>.Continuation

    init(state: AuthState) {
        self.state = state
        (changes, changesContinuation) = AsyncStream<AuthState>.makeStream()
    }

    var canPresentNativeAuth: Bool { false }

    func sessionChanges() -> AsyncStream<AuthState> { changes }

    func refreshSession() async {
        refreshCount += 1
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

    func setObservedState(_ state: AuthState) {
        self.state = state
        changesContinuation.yield(state)
    }

    func signOut() async throws {
        state = .signedOut
    }

    func deleteAccount() async throws {
        state = .signedOut
    }

    func supabaseAccessToken() async throws -> String {
        guard case .signedIn = state else { throw AuthSessionError.notSignedIn }
        return "test-token"
    }
}

@MainActor
private final class FeatureFlagUnderstandingRepository: SocialImportUnderstandingRepository {
    private(set) var requestCount = 0

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        requestCount += 1
        return SocialImportUnderstandingResult(
            outcome: .ok,
            hints: [
                SocialPlaceSearchHint(
                    name: "Carbon Beach Club",
                    area: "Malibu",
                    evidence: .imageText
                )
            ],
            diagnostics: SocialImportUnderstandingDiagnostics(
                providerPath: "apify_gemini",
                mediaCount: 1,
                modelAttemptCount: 1,
                failureCategory: nil
            )
        )
    }
}

@MainActor
private final class InvalidatingAuthUnderstandingRepository: SocialImportUnderstandingRepository {
    private weak var auth: AuthSessionStore?
    private(set) var requestCount = 0

    init(auth: AuthSessionStore) {
        self.auth = auth
    }

    func understand(
        url: URL,
        source: PlaceImportSource,
        clientRequestID: String
    ) async throws -> SocialImportUnderstandingResult {
        requestCount += 1
        auth?.beginSessionValidation()
        throw AuthSessionError.notSignedIn
    }
}
