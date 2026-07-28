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
}
