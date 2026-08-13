import XCTest
@testable import Wander

final class CommunityModerationTests: XCTestCase {
    func testCommunityContentPolicyAllowsOrdinaryPlaceText() throws {
        XCTAssertTrue(CommunityContentPolicy.allows("Tiny room, warm service, excellent noodles."))
        XCTAssertNoThrow(
            try CommunityContentPolicy.validate(
                "Date-night shortlist",
                "Places with quiet tables and good lighting"
            )
        )
    }

    func testCommunityContentPolicyRejectsBlockedTokensPhrasesAndBasicEvasion() {
        XCTAssertFalse(CommunityContentPolicy.allows("you are a nigger"))
        XCTAssertFalse(CommunityContentPolicy.allows("n1gg3r"))
        XCTAssertFalse(CommunityContentPolicy.allows("Go kill yourself"))
        XCTAssertFalse(CommunityContentPolicy.allows("I will kill you"))
    }

    func testCommunityContentPolicyDoesNotBlockSubstringsInsideOrdinaryWords() {
        XCTAssertTrue(CommunityContentPolicy.allows("A classic illustration and assignment."))
    }

    func testCommunityContentPolicyChecksNestedAttributeJSON() {
        XCTAssertNoThrow(
            try CommunityContentPolicy.validateJSONText(
                #"[{"question_key":"personal_labels","value":["date night"]}]"#
            )
        )
        XCTAssertThrowsError(
            try CommunityContentPolicy.validateJSONText(
                #"[{"question_key":"personal_labels","value":["go kill yourself"]}]"#
            )
        ) { error in
            XCTAssertEqual(error as? CommunityContentPolicyError, .prohibitedContent)
        }
    }

    func testReportReasonsMatchTheServerAllowlist() {
        XCTAssertEqual(
            CommunityReportReason.allCases.map(\.rawValue),
            [
                "spam",
                "harassment",
                "hate_or_abuse",
                "sexual_content",
                "dangerous_content",
                "impersonation",
                "privacy",
                "other"
            ]
        )
    }

    func testEveryReportSurfaceHasStableServerSubjectName() {
        XCTAssertEqual(
            CommunityReportSubjectKind.allCases.map(\.rawValue),
            ["profile", "activity", "comment", "user_place", "visit_photo", "place_list"]
        )
    }

    func testReportAuthGateExplainsWhySignInIsRequired() {
        let copy = AuthGateIntent.reportContent.copy
        XCTAssertEqual(copy.title, "Sign in to send a report")
        XCTAssertTrue(copy.message.contains("safety team"))
    }
}
