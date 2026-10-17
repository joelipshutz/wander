import XCTest
@testable import Wander

@MainActor final class LiveUpcomingInvitationsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testSuggestedDateDecodesAndOlderPayloadsRemainCompatible() throws {
        var payload: [String: Any] = [
            "title": "Invitation", "place_name": "Example place", "location": "Example city",
            "sender_name": "Example person", "sender_avatar_url": NSNull(),
            "message": "Example invitation", "connection": "Shared place", "date_label": "Any time",
            "image_path": "example/preview.png"
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func decode() throws -> PlacePlanInvitationPayload {
            try decoder.decode(PlacePlanInvitationPayload.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        XCTAssertNil(try decode().suggestedAt)
        payload["suggested_at"] = NSNull()
        XCTAssertNil(try decode().suggestedAt)
        payload["suggested_at"] = "2033-05-18T03:33:20Z"
        XCTAssertEqual(try decode().suggestedAt, now)
    }

    func testUndatedAndPastInvitationsAreExcludedRegardlessOfCopyOrCreationTime() {
        let rows = [invitation(1, date: nil), invitation(2, date: now.addingTimeInterval(-1)),
                    invitation(3, date: now)]
        XCTAssertEqual(project(rows).rows.map(\.id), [rows[2].id])
        XCTAssertNil(invitation(4).invitation.payload.suggestedAt)
    }

    func testNearestDatesSortFirstWithStableIDTiesAndOnlyThreeVisible() {
        let later = invitation(1, date: now.addingTimeInterval(300))
        let first = invitation(2, date: now.addingTimeInterval(100))
        let second = invitation(3, date: now.addingTimeInterval(100))
        let third = invitation(4, date: now.addingTimeInterval(200))
        let result = project([later, second, third, first])
        XCTAssertEqual(result.rows.map(\.id), [first.id, second.id, third.id, later.id])
        XCTAssertEqual(result.visibleRows.map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(result.rows.count, 4)
    }

    func testAccountMismatchAndSignedOutStateNeverProjectCachedInvitations() {
        let rows = [invitation(1, date: now.addingTimeInterval(100))]
        for userID: String? in [nil, "", "different-account"] {
            let result = LiveUpcomingInvitationsProjection(
                invitations: rows, inboxUserID: "recipient", userID: userID, now: now
            )
            XCTAssertTrue(result.rows.isEmpty)
        }
        XCTAssertTrue(LiveUpcomingInvitationsProjection(
            invitations: rows, inboxUserID: nil, userID: "recipient", now: now
        ).rows.isEmpty)
    }

    func testClockAdvancementRemovesAnInvitationWhoseSuggestedTimePassed() {
        let row = invitation(1, date: now.addingTimeInterval(30))
        XCTAssertEqual(project([row]).rows, [row])
        XCTAssertTrue(LiveUpcomingInvitationsProjection(
            invitations: [row], inboxUserID: "recipient", userID: "recipient",
            now: now.addingTimeInterval(31)
        ).rows.isEmpty)
    }

    func testUnverifiedRefreshCannotKeepAnUpcomingPreviewVisible() {
        XCTAssertTrue(LiveUpcomingInvitationsProjection(
            invitations: [invitation(1, date: now.addingTimeInterval(100))],
            inboxUserID: "recipient", userID: "recipient", failed: true, now: now
        ).rows.isEmpty)
    }

    private func project(_ rows: [ReceivedPlacePlanInvitation]) -> LiveUpcomingInvitationsProjection {
        LiveUpcomingInvitationsProjection(invitations: rows, inboxUserID: "recipient", userID: "recipient", now: now)
    }

    private func invitation(_ index: Int, date: Date? = nil) -> ReceivedPlacePlanInvitation {
        let payload = PlacePlanInvitationPayload(
            title: "Invitation", placeName: "Example place", location: "Example city",
            senderName: "Example person", senderAvatarURL: nil, message: "Example invitation",
            connection: "Shared place", dateLabel: "Tomorrow", imagePath: "example/preview.png",
            suggestedAt: date
        )
        return ReceivedPlacePlanInvitation(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
            invitation: PlacePlanInvitation(payload: payload, artworkURL: URL(string: "https://example.invalid/preview.png")!),
            createdAt: now.addingTimeInterval(1_000), readAt: nil
        )
    }
}
