import XCTest
@testable import AstirClip

final class AppClipRouteTests: XCTestCase {
    let id = "00000000-0000-0000-0000-000000000408"

    func testSupportedRoutesPreservePublishedToken() throws {
        let token = String(repeating: "a", count: 48)
        for (path, kind) in [("profiles/user_408", AppClipRoute.Kind.profile), ("places/\(id)", .place),
                             ("lists/\(id)", .list), ("activities/\(id)", .activity), ("invites/\(token)", .invite)] {
            for host in ["astirmovement.com", "www.astirmovement.com", "getrec.me"] {
                let url = try XCTUnwrap(URL(string: "https://\(host)/cards/\(path)?card=\(token)"))
                let route = try XCTUnwrap(AppClipRoute(url: url))
                XCTAssertEqual(route.kind, kind)
                XCTAssertEqual(route.cardToken, token)
                XCTAssertEqual(route.url, url)
            }
        }
    }

    func testRejectsUntrustedAndMalformedInvocations() {
        for value in ["https://evil.test/places/\(id)", "https://astirmovement.com.evil.test/places/\(id)",
                      "https://user@astirmovement.com/places/\(id)", "http://astirmovement.com/places/\(id)",
                      "recme://places/\(id)", "https://astirmovement.com/places/not-a-uuid",
                      "https://astirmovement.com/cards/places/\(id)?card=bad",
                      "https://astirmovement.com/places/\(id)#injected", "https://astirmovement.com/plans/abc"] {
            XCTAssertNil(AppClipRoute(url: URL(string: value)!), value)
        }
    }

    func testContinuationRequiresSameAccountAndExpires() {
        let url = URL(string: "https://astirmovement.com/places/\(id)")!
        let now = Date(timeIntervalSince1970: 1000000)
        let value = AppClipContinuation(url: url, userID: "owner", createdAt: now)
        XCTAssertNotNil(value.route(for: "owner", now: now))
        XCTAssertNil(value.route(for: "stranger", now: now))
        XCTAssertNil(value.route(for: "owner", now: now.addingTimeInterval(AppClipContinuation.lifetime + 1)))
        XCTAssertNil(value.route(for: "owner", now: now.addingTimeInterval(-1)))
    }

    func testRejectsInvalidMapCoordinates() {
        XCTAssertNil(ClipPlace(id: id, title: "Place", address: nil, latitude: .nan, longitude: 0))
        XCTAssertNil(ClipPlace(id: id, title: "Place", address: nil, latitude: 91, longitude: 0))
        XCTAssertNil(ClipPlace(id: id, title: " ", address: nil, latitude: 0, longitude: 0))
    }
}

@MainActor
final class ClipStoreTests: XCTestCase {
    private let url = URL(string: "https://astirmovement.com/places/00000000-0000-0000-0000-000000000408")!

    func testSaveWaitsForAuthenticationAndResumesOnce() async {
        let auth = ClipTestAuth()
        let service = ClipTestService()
        let store = ClipStore(auth: auth, service: service)
        store.open(url)
        await settle { !store.isLoading }
        store.perform(.save(service.place))
        XCTAssertTrue(store.showAuth)
        XCTAssertEqual(service.saves, 0)
        store.authenticate(.apple, mode: .signIn)
        await settle { !store.isWorking && store.signedIn }
        XCTAssertEqual(service.saves, 0)
        store.resumeAfterAuth()
        await settle { !store.isWorking && service.saves == 1 }
        XCTAssertEqual(service.saves, 1)
        XCTAssertEqual(store.success, "Saved to your Wanna map")
    }

    func testCancelDoesNotSave() async {
        let auth = ClipTestAuth(); let service = ClipTestService()
        let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place)); store.cancelAuth()
        store.authenticate(.apple, mode: .signIn)
        await settle { !store.isWorking }
        XCTAssertEqual(service.saves, 0)
    }

    func testDifferentLinkDiscardsPendingAction() async {
        let auth = ClipTestAuth(); let service = ClipTestService()
        let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place))
        store.open(URL(string: "https://astirmovement.com/profiles/another_user")!)
        await settle { !store.isLoading }
        store.authenticate(.apple, mode: .signIn)
        await settle { !store.isWorking }
        XCTAssertEqual(service.saves, 0)
    }

    func testExistingSaveIsReportedWithoutClaimingNewWrite() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); service.created = false
        let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place))
        await settle { !store.isWorking }
        XCTAssertEqual(store.success, "Already on your map")
    }

    func testSetupAndJoinRunInsideClip() async {
        let auth = ClipTestAuth(); let service = ClipTestService(); service.hasProfile = false
        let store = ClipStore(auth: auth, service: service)
        store.open(URL(string: "https://astirmovement.com/invites/" + String(repeating: "a", count: 48))!)
        await settle { !store.isLoading }
        store.perform(.join); store.authenticate(.google, mode: .signUp)
        await settle { !store.isWorking && store.signedIn }
        store.resumeAfterAuth()
        await settle { store.showProfile && !store.isWorking }
        XCTAssertEqual(service.joins, 0)
        store.name = "Demo Person"; store.handle = "demo_person"; store.finishProfile()
        await settle { !store.isWorking }
        XCTAssertEqual(service.joins, 1)
        XCTAssertEqual(store.route?.kind, .list)
        XCTAssertEqual(store.success, "You're on the list")
    }

    func testDoubleTapDoesNotDuplicateSave() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place)); store.perform(.save(service.place))
        await settle { !store.isWorking }
        XCTAssertEqual(service.saves, 1)
    }

    func testSignOutImmediatelyClearsPrivatePreviewAndSavedState() async throws {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place)); await settle { !store.isWorking }
        XCTAssertFalse(store.savedIDs.isEmpty)
        store.signOut()
        XCTAssertNil(store.preview)
        XCTAssertTrue(store.savedIDs.isEmpty)
        await settle { !store.isWorking && !store.isLoading }
        XCTAssertFalse(store.signedIn)
    }

    func testCommittedJoinRemainsSuccessfulWhenListReadFails() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); service.failJoinedPreview = true
        let store = ClipStore(auth: auth, service: service)
        store.open(URL(string: "https://astirmovement.com/invites/" + String(repeating: "a", count: 48))!)
        await settle { !store.isLoading }
        store.perform(.join); await settle { !store.isWorking }
        XCTAssertTrue(store.joined)
        XCTAssertEqual(store.success, "You're on the list")
        XCTAssertNotNil(store.error)
        store.reload(); await settle { !store.isLoading }
        XCTAssertEqual(service.joins, 1)
    }

    func testNewLinkCancelsSuspendedProfileBeforeAnySave() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); service.delayProfile = true
        let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place))
        await settle { service.profileStarted }
        store.open(URL(string: "https://astirmovement.com/profiles/another_user")!)
        await settle { !store.isLoading }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(service.saves, 0)
    }

    func testOnlyNewSaveEmitsRawAndEngagementEvents() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); let recorder = ClipRecordingAnalytics()
        let store = ClipStore(auth: auth, service: service, analytics: .init(client: ContextualAnalyticsClient(client: recorder)))
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place)); await settle { !store.isWorking }
        service.created = false
        store.perform(.save(service.place)); await settle { !store.isWorking }
        XCTAssertEqual(recorder.events.filter { $0.name == "place_saved" }.count, 1)
        XCTAssertEqual(recorder.events.filter { $0.name == "engagement_action_performed" }.count, 1)
        XCTAssertEqual(recorder.events.first { $0.name == "core_action_performed" }?.properties["completion"], "server")
        for event in recorder.events {
            XCTAssertTrue(Set(event.properties.keys).isDisjoint(with: WanderAnalyticsSchema.forbiddenPropertyKeys))
            XCTAssertFalse(event.properties.values.contains { $0.contains("http") || $0 == service.place.title || $0 == service.place.id })
        }
    }

    func testAccountChangeDuringProfileSetupCannotEditAnotherAccount() async {
        let auth = ClipTestAuth(); auth.state = .signedIn(ClipTestAuth.account)
        let service = ClipTestService(); service.hasProfile = false
        let store = ClipStore(auth: auth, service: service)
        store.open(url); await settle { !store.isLoading }
        store.perform(.save(service.place)); await settle { !store.isWorking && store.showProfile }
        auth.state = .signedIn(AuthSession(userID: "different_account", displayName: nil, handle: nil))
        store.name = "Demo Person"; store.handle = "demo_person"; store.finishProfile()
        await settle { !store.isWorking }
        XCTAssertEqual(service.profileUpdates, 0)
        XCTAssertEqual(service.saves, 0)
        XCTAssertNotNil(store.error)
    }

    private func settle(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Operation did not reach expected state", file: file, line: line)
    }
}

@MainActor
final class ClipTestAuth: AuthSessionProviding {
    static let account = AuthSession(userID: "clip_test_user", displayName: "Demo Person", handle: "demo_person")
    var state: AuthState = .signedOut
    var canPresentNativeAuth: Bool { true }
    func sessionChanges() -> AsyncStream<AuthState> { AsyncStream { $0.finish() } }
    func refreshSession() async {}
    func authenticate(with provider: NativeSocialAuthProvider, mode: NativeAuthMode) async throws -> NativeSocialAuthResult {
        state = .signedIn(Self.account); return NativeSocialAuthResult(outcome: .completed)
    }
    func signOut() async throws { state = .signedOut }
    var onToken: (() -> Void)?
    func supabaseAccessToken() async throws -> String { onToken?(); return "synthetic-test-token" }
}

@MainActor
final class ClipTestService: ClipServing {
    let place = ClipPlace(id: "00000000-0000-0000-0000-000000000408", title: "Demo Coffee", address: nil, latitude: 0, longitude: 0)!
    var delayProfile = false; var profileStarted = false; var failJoinedPreview = false
    var profileUpdates = 0
    var saves = 0; var joins = 0; var created = true; var hasProfile = true
    func preview(_ route: AppClipRoute, authenticated: Bool) async throws -> ClipPreview {
        if route.kind == .list, failJoinedPreview { throw ClipError.connection }
        return ClipPreview(title: "Demo Coffee", subtitle: "Test preview", imageURL: nil, places: [place])
    }
    func profile() async throws -> ClipProfile? {
        profileStarted = true
        if delayProfile { try await Task.sleep(for: .milliseconds(80)) }
        return hasProfile ? ClipProfile(id: ClipTestAuth.account.userID, displayName: "Demo Person", handle: "demo_person", isPrivate: false, onboardedAt: "2026-09-22") : nil
    }
    func updateProfile(name: String, handle: String) async throws -> ClipProfile {
        profileUpdates += 1; hasProfile = true; return try await profile()!
    }
    func save(_ place: ClipPlace) async throws -> Bool { saves += 1; return created }
    func join(_ route: AppClipRoute) async throws -> String { joins += 1; return place.id }
}

final class ClipRecordingAnalytics: AnalyticsClient {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
    func identify(userID: String) {}
    func resetIdentity() {}
}
