#if DEBUG
@testable import Wander
import XCTest

final class CommonGroundInvitationDraftTests: XCTestCase {
    func testFiveContextualMessagesPreserveTheDirectionOfTheInvitation() throws {
        let expectations: [(String, String, String)] = [
            ("narwhal", "Shared regulars", "We’re both Narwhal people. Coffee together?"),
            ("grove-gardens", "Shared love", "We both loved Grove Gardens. Round two?"),
            ("not-no-bar", "Both wanna go", "We both wanna go to Not No Bar. Let’s make a plan?"),
            ("mudwater", "Joe’s regular spot", "You keep going back to Mudwater. Take me next time?"),
            ("the-little-room", "Ryan’s regular spot", "I keep going back to The Little Room. Let me show you why.")
        ]
        for (id, reason, message) in expectations {
            let invitation = try draft(id)
            XCTAssertEqual(invitation.reasonTitle, reason, id)
            XCTAssertEqual(invitation.message, message, id)
            XCTAssertFalse(invitation.reasonSymbol.isEmpty, id)
        }
    }

    func testEvidenceNamesPeopleAndSeparatesRepeatVisitsFromRatings() throws {
        let repeats = try draft("narwhal")
        XCTAssertEqual(repeats.reasonDetail, "Ryan: 18 check-ins · Joe: 17 check-ins")
        XCTAssertEqual(repeats.reasonSymbol, "flame.fill")
        XCTAssertFalse(repeats.reasonDetail.contains("/5"))

        let ratings = try draft("grove-gardens")
        XCTAssertEqual(ratings.reasonDetail, "Ryan: 5/5 · Joe: 4.5/5")
        XCTAssertEqual(ratings.reasonSymbol, "heart.fill")
        XCTAssertFalse(ratings.place.bothRegulars)

        XCTAssertEqual(try draft("not-no-bar").reasonDetail, "In both of your Wannas")
        XCTAssertEqual(
            try draft("mudwater").reasonDetail,
            "Joe: 5 check-ins · In Ryan’s Wannas."
        )
        XCTAssertEqual(
            try draft("the-little-room").reasonDetail,
            "Ryan: 7 check-ins · In Joe’s Wannas."
        )
    }

    func testPersonalNoteOverridesDefaultAfterTrimmingWithoutChangingEvidence() throws {
        var invitation = try draft("mudwater")
        let initialEvidence = invitation.reasonDetail
        invitation.note = "  \nTake me for coffee this weekend?\n  "
        XCTAssertEqual(invitation.message, "Take me for coffee this weekend?")
        XCTAssertEqual(invitation.reasonDetail, initialEvidence)
        XCTAssertTrue(invitation.shareText.hasPrefix(invitation.message))
        invitation.note = " \n\t "
        XCTAssertEqual(invitation.message, "You keep going back to Mudwater. Take me next time?")
    }

    func testDateIsOptionalAndTheExactDraftSurvivesARecipientHandoff() throws {
        var invitation = try draft("not-no-bar")
        XCTAssertNil(invitation.suggestedDate)
        XCTAssertNil(invitation.whenText)
        XCTAssertFalse(invitation.shareText.contains("When:"))

        let selectedDate = Date(timeIntervalSince1970: 1_789_837_245.25)
        invitation.suggestedDate = selectedDate
        invitation.note = "Saturday works for me. You?"
        let recipientDraft = invitation
        XCTAssertEqual(recipientDraft, invitation)
        XCTAssertEqual(recipientDraft.suggestedDate, selectedDate)
        XCTAssertEqual(recipientDraft.whenText, selectedDate.formatted(date: .abbreviated, time: .shortened))
        XCTAssertEqual(recipientDraft.shareText, invitation.shareText)
        XCTAssertTrue(recipientDraft.shareText.contains("When: \(try XCTUnwrap(recipientDraft.whenText))"))

        invitation.suggestedDate = selectedDate.addingTimeInterval(3_600)
        XCTAssertNotEqual(invitation, recipientDraft)
        XCTAssertEqual(recipientDraft.suggestedDate, selectedDate)
    }

    func testSharePayloadContainsThePlaceAndEvidenceWithoutInventedLinksOrDelivery() throws {
        let invitation = try draft("the-little-room")
        let payload = invitation.shareText
        XCTAssertTrue(payload.contains(invitation.message))
        XCTAssertTrue(payload.contains("The Little Room · Atwater Village, Los Angeles"))
        XCTAssertTrue(payload.contains(invitation.reasonDetail))
        for unsupported in ["https://", "http://", "recme://", "Sent", "Delivered", "Astir picked"] {
            XCTAssertFalse(payload.contains(unsupported), unsupported)
        }
    }

    func testHistoryDoesNotBecomeAFavoriteOrSharedVisitInAnInvitation() throws {
        for id in ["lantern-kitchen", "terrace"] {
            let invitation = try draft(id)
            XCTAssertEqual(invitation.reasonTitle, "Shared place")
            XCTAssertEqual(invitation.message, "Want to go to \(invitation.place.name)?")
            XCTAssertFalse(invitation.reasonDetail.contains("together"))
            XCTAssertFalse(invitation.reasonDetail.contains("loved"))
        }
    }

    func testPreviewUsesNarwhalAndADeterministicSuggestedDate() throws {
        let invitation = CommonGroundInvitationDraft.preview
        XCTAssertEqual(invitation.place.id, "narwhal")
        let date = try XCTUnwrap(invitation.suggestedDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 19)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 0)
    }

    private func draft(_ id: String) throws -> CommonGroundInvitationDraft {
        CommonGroundInvitationDraft(place: try XCTUnwrap(
            CommonGroundMockData.places.first { $0.id == id }
        ))
    }
}
#endif
