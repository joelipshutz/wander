import XCTest
import ClerkKit
@testable import AstirClip

@MainActor
final class ClipDeviceTrustTests: XCTestCase {
    private let account = AuthSession(userID: "fixture_user", displayName: nil, handle: nil)
    private var challenge: SignIn {
        SignIn(id: "fixture_attempt", status: .needsClientTrust,
               supportedSecondFactors: [Factor(strategy: .emailCode, emailAddressId: "fixture_email")])
    }

    private func service(_ client: ClerkAuthService.PasswordVerificationClient) -> ClerkAuthService {
        ClerkAuthService(configuration: WanderBackendConfiguration.current { "$(\($0))" },
            resolveSession: { .init(clerkSessionID: "fixture_session", authSession: self.account) },
            resolveSessionID: { "fixture_session" }, sessionCache: .disabled,
            nativeAuthSessionFenceStore: .disabled, appleSignInSessionStore: .disabled,
            sessionAdoptionRetryDelaysNanoseconds: [], passwordVerification: client,
            configureClerk: { $0 })
    }

    func testDeviceTrustContinuesSameAttemptAndAdoptsOnlyCompletedSession() async throws {
        let challenge = challenge
        var requested: [String] = []
        let auth = service(.init(signIn: { _, _ in challenge }, sendCode: { signIn, emailID in
            requested.append(signIn.id); XCTAssertEqual(emailID, "fixture_email"); return signIn
        }, verifyCode: { signIn, code in
            requested.append(signIn.id)
            guard code == "123456" else { throw AuthSessionError.invalidVerificationCode }
            return SignIn(id: signIn.id, status: .complete, createdSessionId: "fixture_session")
        }))
        let outcome = try await auth.authenticateWithPassword(emailAddress: "fixture@example.invalid", password: "synthetic")
        XCTAssertEqual(outcome, .requiresAdditionalVerification)
        XCTAssertFalse(auth.state.isSignedIn)
        try await auth.sendPasswordVerificationCode()
        do { _ = try await auth.verifyEmailCode("wrong"); XCTFail("Wrong code must fail") }
        catch { XCTAssertEqual(error as? AuthSessionError, .invalidVerificationCode) }
        XCTAssertFalse(auth.state.isSignedIn)
        let verified = try await auth.verifyEmailCode("123456")
        XCTAssertEqual(verified, .completed)
        XCTAssertEqual(auth.state.session?.userID, account.userID)
        XCTAssertEqual(requested, [challenge.id, challenge.id, challenge.id])
        do { _ = try await auth.verifyEmailCode("123456"); XCTFail("Completed challenge must be cleared") }
        catch { XCTAssertEqual(error as? AuthSessionError, .emailVerificationUnavailable) }
    }

    func testLegacySecondFactorStatusUsesAdvertisedEmailChallenge() async throws {
        var challenge = challenge; challenge.status = .needsSecondFactor
        var sent = false
        let auth = service(.init(signIn: { _, _ in challenge }, sendCode: { signIn, _ in
            sent = true; return signIn
        }, verifyCode: { signIn, _ in SignIn(id: signIn.id, status: .complete, createdSessionId: "fixture_session") }))
        _ = try await auth.authenticateWithPassword(emailAddress: "fixture@example.invalid", password: "synthetic")
        try await auth.sendPasswordVerificationCode()
        XCTAssertTrue(sent)
        let outcome = try await auth.verifyEmailCode("123456")
        XCTAssertEqual(outcome, .completed)
    }

    func testUnsupportedFactorDoesNotStartNewAuthentication() async throws {
        var challenge = challenge; challenge.supportedSecondFactors = [Factor(strategy: .totp)]
        var sends = 0
        let auth = service(.init(signIn: { _, _ in challenge }, sendCode: { signIn, _ in sends += 1; return signIn },
            verifyCode: { signIn, _ in signIn }))
        _ = try await auth.authenticateWithPassword(emailAddress: "fixture@example.invalid", password: "synthetic")
        do { try await auth.sendPasswordVerificationCode(); XCTFail("Unsupported challenge must fail closed") }
        catch { XCTAssertEqual(error as? AuthSessionError, .emailVerificationUnavailable) }
        XCTAssertEqual(sends, 0)
        XCTAssertFalse(auth.state.isSignedIn)
    }

    func testResetDuringCodePreparationDiscardsLateChallenge() async throws {
        let challenge = challenge
        var auth: ClerkAuthService!
        auth = service(.init(signIn: { _, _ in challenge }, sendCode: { signIn, _ in
            auth.resetPendingEmailVerification(); return signIn
        }, verifyCode: { signIn, _ in signIn }))
        _ = try await auth.authenticateWithPassword(emailAddress: "fixture@example.invalid", password: "synthetic")
        do { try await auth.sendPasswordVerificationCode(); XCTFail("Reset must discard late preparation") }
        catch { XCTAssertEqual(error as? AuthSessionError, .emailVerificationUnavailable) }
        do { _ = try await auth.verifyEmailCode("123456"); XCTFail("No challenge may survive reset") }
        catch { XCTAssertEqual(error as? AuthSessionError, .emailVerificationUnavailable) }
        XCTAssertFalse(auth.state.isSignedIn)
    }

    func testResetDuringVerificationCannotAdoptReturnedSession() async throws {
        let challenge = challenge
        var auth: ClerkAuthService!
        auth = service(.init(signIn: { _, _ in challenge }, sendCode: { signIn, _ in signIn },
            verifyCode: { signIn, _ in
                auth.resetPendingEmailVerification()
                return SignIn(id: signIn.id, status: .complete, createdSessionId: "fixture_session")
            }))
        _ = try await auth.authenticateWithPassword(emailAddress: "fixture@example.invalid", password: "synthetic")
        try await auth.sendPasswordVerificationCode()
        do { _ = try await auth.verifyEmailCode("123456"); XCTFail("Stale session must not be adopted") }
        catch { XCTAssertEqual(error as? AuthSessionError, .emailVerificationUnavailable) }
        XCTAssertFalse(auth.state.isSignedIn)
    }
}
