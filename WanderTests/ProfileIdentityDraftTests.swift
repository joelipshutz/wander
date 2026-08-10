import XCTest
@testable import Wander

final class ProfileIdentityDraftTests: XCTestCase {
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
