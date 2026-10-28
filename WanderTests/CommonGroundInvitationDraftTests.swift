#if DEBUG
@testable import Wander
import XCTest

final class CommonGroundInvitationDraftTests: XCTestCase {
    func testFiveContextualMessagesPreserveTheDirectionOfTheInvitation() throws {
        let expectations: [(String, String, String)] = [
            ("narwhal", "You’re Both Regulars At Narwhal", "We’re Both Regulars At Narwhal\nLet’s Go Together?"),
            ("grove-gardens", "You Both Love This Place", "We Both Loved Grove Gardens\nRound Two?"),
            ("not-no-bar", "Both Wanna Go", "We Both Wanna Go To Not No Bar\nLet’s Make A Plan?"),
            ("mudwater", "Joe’s Been And You Wanna Go", "You’ve Been To Mudwater And I Wanna Go\nTake Me Next Time?"),
            ("the-little-room", "You’ve Been And Joe Wants To Go", "I’ve Been To The Little Room And You Wanna Go\nLet’s Make A Plan?")
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
        XCTAssertEqual(repeats.reasonDetail, "You: 18 Check-Ins · Joe: 17 Check-Ins")
        XCTAssertEqual(repeats.reasonSymbol, "arrow.counterclockwise")
        XCTAssertNil(repeats.postcardReasonDetail)
        XCTAssertFalse(repeats.reasonDetail.contains("/5"))

        let ratings = try draft("grove-gardens")
        XCTAssertEqual(ratings.reasonDetail, "You: 5/5 · Joe: 4.5/5")
        XCTAssertEqual(ratings.reasonSymbol, "heart.fill")
        XCTAssertFalse(ratings.place.bothRegulars)

        XCTAssertEqual(try draft("not-no-bar").reasonDetail, "In Both Of Your Wannas")
        XCTAssertNil(try draft("not-no-bar").postcardReasonDetail)
        XCTAssertEqual(
            try draft("mudwater").reasonDetail,
            "Joe: 5 Check-Ins · In Your Wannas"
        )
        XCTAssertEqual(
            try draft("the-little-room").reasonDetail,
            "You: 7 Check-Ins · In Joe’s Wannas"
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
        XCTAssertEqual(invitation.message, "You’ve Been To Mudwater And I Wanna Go\nTake Me Next Time?")
    }

    func testDateIsOptionalAndTheExactDraftSurvivesARecipientHandoff() throws {
        var invitation = try draft("not-no-bar")
        XCTAssertNil(invitation.suggestedDate)
        XCTAssertNil(invitation.whenText)
        XCTAssertEqual(invitation.linkTitle, "Let’s Go To Not No Bar Together")
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
        XCTAssertEqual(invitation.linkTitle, "Let’s Go To The Little Room Together")
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
        XCTAssertEqual(favorite.reasonTitle, "You Love This Place, Show Joe")
        XCTAssertEqual(favorite.message, "I Love Lantern Kitchen\nLet Me Show You Why")
        let history = try draft("terrace")
        XCTAssertEqual(history.reasonTitle, "You’ve Both Been Here")
        XCTAssertEqual(history.message, "We’ve Both Been To Terrace\nGo Back Together?")
        XCTAssertFalse(history.reasonDetail.contains("loved"))
    }

    func testRecipientReasonsReverseTheViewerWithoutChangingTheEvidence() throws {
        XCTAssertEqual(try draft("mudwater").recipientReasonTitle, "You’ve Been And Ryan Wants To Go")
        XCTAssertEqual(try draft("the-little-room").recipientReasonTitle, "Ryan’s Been And You Wanna Go")
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
