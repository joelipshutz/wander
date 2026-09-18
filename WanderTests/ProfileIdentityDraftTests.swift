import XCTest
@testable import Wander

final class ProfileIdentityDraftTests: XCTestCase {
    func testAppleOnboardingUsesChosenUsernameWhenNameIsMissing() {
        let draft = ProfileIdentityDraft(displayName: "  ", handle: " @ALEX_Visits ", usesAppleSignIn: true)
        XCTAssertEqual(draft.normalizedDisplayName, "alex_visits")
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(
            ProfileIdentityDraft(displayName: "", handle: "not valid", usesAppleSignIn: true).validationError,
            .invalidHandle
        )
    }

    func testAppleOnboardingPreservesProvidedName() {
        let draft = ProfileIdentityDraft(displayName: " Maya Chen ", handle: "maya", usesAppleSignIn: true)
        XCTAssertEqual(draft.normalizedDisplayName, "Maya Chen")
        XCTAssertTrue(draft.isValid)
    }

    func testNormalizesIdentityLikeTheServer() {
        let draft = ProfileIdentityDraft(displayName: "  Maya Chen  ", handle: "  @MAYA_Visits@  ")

        XCTAssertEqual(draft.normalizedDisplayName, "Maya Chen")
        XCTAssertEqual(draft.normalizedHandle, "maya_visits")
        XCTAssertTrue(draft.isValid)
    }

    func testRejectsMissingNameAndInvalidHandle() {
        XCTAssertEqual(
            ProfileIdentityDraft(displayName: "  ", handle: "good_handle").validationError,
            .displayNameRequired
        )
        XCTAssertEqual(
            ProfileIdentityDraft(displayName: "Maya", handle: "not valid").validationError,
            .invalidHandle
        )
    }

    func testMapsTakenHandleWithoutDiscardingFieldSpecificMeaning() {
        let mapped = ProfileIdentitySubmissionError.map(
            WanderRemoteError.invalidResponse("RPC failed: handle_taken (23505)")
        )

        XCTAssertEqual(mapped, .handleTaken)
    }

    func testOnboardingDoesNotCheckPrefilledHandleBeforeUserEdits() {
        XCTAssertFalse(
            OnboardingHandleAvailabilityPolicy.shouldCheck(
                normalizedHandle: "maya",
                originalNormalizedHandle: "maya",
                hasUserEdited: false,
                validationError: nil
            )
        )
    }

    func testOnboardingDoesNotRecheckUsersOriginalHandle() {
        XCTAssertFalse(
            OnboardingHandleAvailabilityPolicy.shouldCheck(
                normalizedHandle: "maya",
                originalNormalizedHandle: "maya",
                hasUserEdited: true,
                validationError: nil
            )
        )
    }

    func testOnboardingChecksAValidEditedHandle() {
        XCTAssertTrue(
            OnboardingHandleAvailabilityPolicy.shouldCheck(
                normalizedHandle: "maya_eats",
                originalNormalizedHandle: "maya",
                hasUserEdited: true,
                validationError: nil
            )
        )
        XCTAssertFalse(
            OnboardingHandleAvailabilityPolicy.shouldCheck(
                normalizedHandle: "not valid",
                originalNormalizedHandle: "maya",
                hasUserEdited: true,
                validationError: .invalidHandle
            )
        )
    }
}
