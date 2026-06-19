import XCTest
@testable import Wander

@MainActor
final class AuthSessionTests: XCTestCase {
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

        let token = try? await signedInStore.supabaseAccessToken()

        XCTAssertEqual(token, "token")
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
        XCTAssertEqual(facts.map(\.id), ["everyone", "friends", "location", "extraction", "blocks", "contacts"])
        XCTAssertEqual(Set(facts.map(\.id)).count, facts.count)

        XCTAssertTrue(facts.first { $0.id == "everyone" }?.body.contains("people who follow you") == true)
        XCTAssertTrue(facts.first { $0.id == "everyone" }?.body.contains("not a public internet feed") == true)
        XCTAssertTrue(facts.first { $0.id == "friends" }?.body.contains("follow you back") == true)
        XCTAssertTrue(facts.first { $0.id == "location" }?.body.contains("does not broadcast live location") == true)
        XCTAssertTrue(facts.first { $0.id == "extraction" }?.body.contains("never auto-save") == true)
        XCTAssertTrue(facts.first { $0.id == "blocks" }?.body.contains("hides profiles, places, search results, and map content") == true)
        XCTAssertTrue(facts.first { $0.id == "contacts" }?.body.contains("not part of this alpha") == true)
    }
}
