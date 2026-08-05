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

    func testContactMatchMapsExistingAndNonUserContactsWithoutPIIAnalytics() {
        let existing = InviteContact(
            contactMatch: ContactMatch(
                id: "maya-contact",
                displayName: "Maya Chen",
                handle: "mayac",
                userID: "user-maya",
                isAlreadyFollowing: true,
                followsCurrentUser: false
            )
        )
        let nonUser = InviteContact(
            contactMatch: ContactMatch(
                id: "sam-contact",
                displayName: "Sam Rivera",
                contactDetail: "+1 (555) 010-1000",
                handle: nil,
                userID: nil,
                isAlreadyFollowing: false,
                followsCurrentUser: false
            )
        )

        XCTAssertEqual(existing.relationship, .recmeUser(handle: "mayac", userID: "user-maya"))
        XCTAssertTrue(existing.isFrequentlyContacted)
        XCTAssertEqual(nonUser.relationship, .contactOnly)
        XCTAssertEqual(nonUser.contactDetail, "+1 (555) 010-1000")
        XCTAssertTrue(nonUser.matches("555"))
    }

    func testCheckInFriendPickerPlacesContactInviteBetweenSearchAndFriends() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Wander/Features/SharedVisits/SharedVisitComponents.swift"
            )
        )

        let search = try XCTUnwrap(source.range(of: "TextField(\"Search friends\""))
        let invite = try XCTUnwrap(source.range(of: "InviteEntryPointButton(surface: .sharedVisit"))
        let friends = try XCTUnwrap(source.range(of: "Section(\"friends\")"))

        XCTAssertLessThan(search.lowerBound, invite.lowerBound)
        XCTAssertLessThan(invite.lowerBound, friends.lowerBound)
        XCTAssertTrue(source.contains("Button(\"Done\") { dismiss() }"))
        XCTAssertTrue(source.contains("ContactInviteSheet("))
        XCTAssertTrue(source.contains("contactProvider: store.contactProvider"))
        XCTAssertTrue(source.contains("senderProfileID: store.currentUser.id"))
    }

    func testFeedPeoplePlacesContactInviteDirectlyAfterSearch() throws {
        let source = try projectSource("Wander/Features/Feed/FeedScreen.swift")
        let surface = try XCTUnwrap(source.components(separatedBy: "private struct FeedPeopleSurface: View").last)
        let search = try XCTUnwrap(surface.range(of: "FeedPeopleSearchField(text: $memberQuery)"))
        let invite = try XCTUnwrap(surface.range(of: "InviteEntryPointButton(surface: .feedPeople)"))
        let results = try XCTUnwrap(surface.range(of: "if isMemberSearchActive"))

        XCTAssertLessThan(search.lowerBound, invite.lowerBound)
        XCTAssertLessThan(invite.lowerBound, results.lowerBound)
        XCTAssertTrue(surface.contains("contactProvider: store.contactProvider"))
        XCTAssertTrue(surface.contains("senderProfileID: store.currentUser.id"))
    }

    func testListCollaboratorPlacesContactInviteBetweenSearchAndFriends() throws {
        let source = try projectSource("Wander/Features/Lists/ListsScreen.swift")
        let content = try XCTUnwrap(source.components(separatedBy: "private struct FriendCollaboratorSearchContent: View").last)
        let search = try XCTUnwrap(content.range(of: "TextField(\"Search friends\""))
        let invite = try XCTUnwrap(content.range(of: "InviteEntryPointButton(surface: .listCollaborator"))
        let friends = try XCTUnwrap(content.range(of: "Text(\"friends\")"))

        XCTAssertLessThan(search.lowerBound, invite.lowerBound)
        XCTAssertLessThan(invite.lowerBound, friends.lowerBound)
        XCTAssertTrue(content.contains("contactProvider: store.contactProvider"))
        XCTAssertTrue(content.contains("senderProfileID: store.currentUser.id"))
    }

    func testProductionContactsUsePermissionAndLoadingStatesInsteadOfEmptySeed() throws {
        let fixtures = try projectSource("Wander/Services/WanderFixtures.swift")
        let sheet = try projectSource("Wander/Features/Invites/ContactInviteSheet.swift")

        XCTAssertTrue(fixtures.contains("contactProvider: SystemContactProvider()"))
        XCTAssertTrue(sheet.contains("await contactProvider.requestAccess()"))
        XCTAssertTrue(sheet.contains("await contactProvider.matches()"))
        XCTAssertTrue(sheet.contains("if isLoadingContacts"))
    }

    func testContactInviteAddUsesMessagesDeliveryAndInteractiveAlphabetScrubber() throws {
        let sheet = try projectSource("Wander/Features/Invites/ContactInviteSheet.swift")

        XCTAssertTrue(sheet.contains("MFMessageComposeViewController.canSendText()"))
        XCTAssertTrue(sheet.contains("ContactInviteMessageComposer("))
        XCTAssertTrue(sheet.contains("case .sent:"))
        XCTAssertTrue(sheet.contains("WanderShareContent.appInvite(senderProfileID:"))
        XCTAssertFalse(sheet.contains("Choose how to share"))

        XCTAssertTrue(sheet.contains("AlphabetScrubber(letters:"))
        XCTAssertTrue(sheet.contains("DragGesture(minimumDistance: 0"))
        XCTAssertTrue(sheet.contains("proxy.scrollTo(targetID"))
        XCTAssertTrue(sheet.contains("magnification(for:"))
        XCTAssertTrue(sheet.contains("UISelectionFeedbackGenerator().selectionChanged()"))
    }

    private func projectSource(_ path: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(path))
    }
}
