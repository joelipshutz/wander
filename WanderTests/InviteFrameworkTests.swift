import XCTest
@testable import Wander

final class InviteFrameworkTests: XCTestCase {
    func testSurfaceConfigurationUsesContextSpecificCopyAndSanitizedAnalytics() {
        let visit = InviteSurface.sharedVisit(placeName: "Gjelina")
        let feed = InviteSurface.feedPeople
        let list = InviteSurface.listCollaborator(listName: "LA date nights")

        XCTAssertEqual(visit.sheetSubtitle, "Who joined you at Gjelina?")
        XCTAssertEqual(feed.entryTitle, "invite people to rec.me")
        XCTAssertEqual(list.sheetSubtitle, "Invite people to help build LA date nights.")
        XCTAssertEqual(InviteIntent(surface: visit, resourceID: "visit-123").analyticsProperties, ["surface": "shared_visit"])
        XCTAssertFalse(InviteIntent(surface: visit, resourceID: "visit-123").analyticsProperties.values.contains("visit-123"))
    }

    func testContactSearchMatchesNameDetailAndHandle() {
        let contact = InviteContact(
            id: "maya",
            displayName: "Maya Chen",
            contactDetail: "+1 (555) 010-1000",
            relationship: .recmeUser(handle: "mayac", userID: "user-maya"),
            isFrequentlyContacted: true
        )

        XCTAssertTrue(contact.matches("maya"))
        XCTAssertTrue(contact.matches("555"))
        XCTAssertTrue(contact.matches("@mayac"))
        XCTAssertFalse(contact.matches("joe"))
    }

    func testSectionsKeepFrequentContactsOutOfAlphabeticalDirectory() {
        let frequent = InviteContact(id: "frequent", displayName: "Maya Chen", contactDetail: nil, relationship: .contactOnly, isFrequentlyContacted: true)
        let alphabetical = InviteContact(id: "alphabetical", displayName: "Adam Rivera", contactDetail: nil, relationship: .contactOnly, isFrequentlyContacted: false)

        let sections = InviteContactSection.sections(for: [frequent, alphabetical])

        XCTAssertEqual(sections.map(\.title), ["frequently contacted", "A"])
        XCTAssertEqual(sections.flatMap(\.contacts).map(\.id), ["frequent", "alphabetical"])
    }

    func testSearchingFlattensMatchingFrequentContactIntoAlphabeticalSection() {
        let frequent = InviteContact(id: "maya", displayName: "Maya Chen", contactDetail: nil, relationship: .contactOnly, isFrequentlyContacted: true)

        let sections = InviteContactSection.sections(for: [frequent], query: "maya")

        XCTAssertEqual(sections.map(\.title), ["M"])
        XCTAssertEqual(sections.first?.contacts, [frequent])
    }

    func testSelectionToggleIsReversibleAndDeduplicated() {
        var selection = InviteSelection()

        selection.toggle("maya")
        selection.toggle("maya")
        selection.toggle("joe")

        XCTAssertEqual(selection.count, 1)
        XCTAssertFalse(selection.contains("maya"))
        XCTAssertTrue(selection.contains("joe"))
    }
}
