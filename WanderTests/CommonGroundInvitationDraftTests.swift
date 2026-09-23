#if DEBUG
@testable import Wander
import XCTest

final class CommonGroundInvitationDraftTests: XCTestCase {
    func testFiveContextualMessagesPreserveTheDirectionOfTheInvitation() throws {
        let expectations: [(String, String, String)] = [
            ("narwhal", "You’re both regulars at Narwhal", "We’re both regulars at Narwhal\nLet’s go together?"),
            ("grove-gardens", "You both love this place", "We both loved Grove Gardens\nRound two?"),
            ("not-no-bar", "Both Wanna Go", "We both wanna go to Not No Bar\nLet’s make a plan?"),
            ("mudwater", "Joe’s been and you wanna go", "You’ve been to Mudwater and I wanna go\nTake me next time?"),
            ("the-little-room", "You’ve been and Joe wants to go", "I’ve been to The Little Room and you wanna go\nLet’s make a plan?")
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
        XCTAssertEqual(repeats.reasonDetail, "You: 18 check-ins · Joe: 17 check-ins")
        XCTAssertEqual(repeats.reasonSymbol, "arrow.counterclockwise")
        XCTAssertNil(repeats.postcardReasonDetail)
        XCTAssertFalse(repeats.reasonDetail.contains("/5"))

        let ratings = try draft("grove-gardens")
        XCTAssertEqual(ratings.reasonDetail, "You: 5/5 · Joe: 4.5/5")
        XCTAssertEqual(ratings.reasonSymbol, "heart.fill")
        XCTAssertFalse(ratings.place.bothRegulars)

        XCTAssertEqual(try draft("not-no-bar").reasonDetail, "In both of your Wannas")
        XCTAssertNil(try draft("not-no-bar").postcardReasonDetail)
        XCTAssertEqual(
            try draft("mudwater").reasonDetail,
            "Joe: 5 check-ins · In your Wannas"
        )
        XCTAssertEqual(
            try draft("the-little-room").reasonDetail,
            "You: 7 check-ins · In Joe’s Wannas"
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
        XCTAssertEqual(invitation.message, "You’ve been to Mudwater and I wanna go\nTake me next time?")
    }

    func testDateIsOptionalAndTheExactDraftSurvivesARecipientHandoff() throws {
        var invitation = try draft("not-no-bar")
        XCTAssertNil(invitation.suggestedDate)
        XCTAssertNil(invitation.whenText)
        XCTAssertEqual(invitation.linkTitle, "Let’s go to Not No Bar together")
        XCTAssertEqual(invitation.linkSubtitle, "Date TBD")
        XCTAssertFalse(invitation.shareText.contains("When:"))

        let selectedDate = Date(timeIntervalSince1970: 1_789_837_245.25)
        invitation.suggestedDate = selectedDate
        invitation.note = "Saturday works for me. You?"
        let recipientDraft = invitation
        XCTAssertEqual(recipientDraft, invitation)
        XCTAssertEqual(recipientDraft.suggestedDate, selectedDate)
        XCTAssertEqual(recipientDraft.whenText, selectedDate.formatted(date: .abbreviated, time: .shortened))
        XCTAssertEqual(recipientDraft.linkSubtitle, recipientDraft.whenText)
        XCTAssertEqual(recipientDraft.shareText, invitation.shareText)
        XCTAssertEqual(recipientDraft.shareText, "Saturday works for me. You?\n\n\(try XCTUnwrap(recipientDraft.whenText))")

        invitation.suggestedDate = selectedDate.addingTimeInterval(3_600)
        XCTAssertNotEqual(invitation, recipientDraft)
        XCTAssertEqual(recipientDraft.suggestedDate, selectedDate)
    }

    func testShareCopyContainsOnlyTheMessageWhileTheTileOwnsPlaceDateAndContext() throws {
        let invitation = try draft("the-little-room")
        let payload = invitation.shareText
        XCTAssertEqual(invitation.linkTitle, "Let’s go to The Little Room together")
        XCTAssertEqual(invitation.linkLocation, "Atwater Village, Los Angeles")
        XCTAssertTrue(payload.contains(invitation.message))
        XCTAssertEqual(payload, invitation.message)
        XCTAssertFalse(payload.contains(invitation.reasonDetail))
        XCTAssertFalse(payload.contains("check-ins"))
        XCTAssertFalse(payload.contains("When:"))
        for unsupported in ["https://", "http://", "recme://", "Sent", "Delivered", "ASTIR picked"] {
            XCTAssertFalse(payload.contains(unsupported), unsupported)
        }
    }

    func testOneSidedLoveAndUnratedHistoryStayDistinct() throws {
        let favorite = try draft("lantern-kitchen")
        XCTAssertEqual(favorite.reasonTitle, "You love this place, show Joe")
        XCTAssertEqual(favorite.message, "I love Lantern Kitchen\nLet me show you why")
        let history = try draft("terrace")
        XCTAssertEqual(history.reasonTitle, "You’ve both been here")
        XCTAssertEqual(history.message, "We’ve both been to Terrace\nGo back together?")
        XCTAssertFalse(history.reasonDetail.contains("loved"))
    }

    func testRecipientReasonsReverseTheViewerWithoutChangingTheEvidence() throws {
        XCTAssertEqual(try draft("mudwater").recipientReasonTitle, "You’ve been and Ryan wants to go")
        XCTAssertEqual(try draft("the-little-room").recipientReasonTitle, "Ryan’s been and you wanna go")
        XCTAssertEqual(try draft("not-no-bar").recipientReasonTitle, "Both Wanna Go")
    }

    func testInvitationLinksRequireAnOpaqueTokenAndNeverBecomePlaceLinks() throws {
        let draft = try draft("not-no-bar")
        let token = String(repeating: "b7", count: 24)
        let content = try XCTUnwrap(draft.shareContent(invitationToken: token))
        XCTAssertEqual(content.item.absoluteString, "https://astirmovement.com/plans/\(token)")
        XCTAssertEqual(content.subject, draft.linkTitle)
        for invalid in ["", "place-id", String(repeating: "g", count: 48), token + "?redirect=elsewhere", "../" + token] {
            XCTAssertNil(draft.shareContent(invitationToken: invalid))
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
