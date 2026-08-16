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
        XCTAssertEqual(visit.entrySubtitle, "Invite them to rec.me, then connect after they join.")
        XCTAssertTrue(list.inviteMessage.contains("add you as a collaborator on LA date nights"))
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

    func testSelectionInsertTracksSentInviteOnlyOnce() {
        var selection = InviteSelection()

        XCTAssertTrue(selection.insert("maya"))
        XCTAssertFalse(selection.insert("maya"))
        XCTAssertEqual(selection.count, 1)
        XCTAssertTrue(selection.contains("maya"))
    }

    func testWalkthroughProgressReducerOnlyCountsSentAndDeduplicatesContacts() {
        let initial = InviteSelection()
        let cancelled = ContactInviteWalkthroughProgressReducer.reduce(
            state: initial,
            action: .messageComposerFinished(contactID: "maya", outcome: .cancelled)
        )
        let failed = ContactInviteWalkthroughProgressReducer.reduce(
            state: cancelled,
            action: .messageComposerFinished(contactID: "maya", outcome: .failed)
        )
        let sent = ContactInviteWalkthroughProgressReducer.reduce(
            state: failed,
            action: .messageComposerFinished(contactID: "maya", outcome: .sent)
        )
        let duplicate = ContactInviteWalkthroughProgressReducer.reduce(
            state: sent,
            action: .messageComposerFinished(contactID: "maya", outcome: .sent)
        )

        XCTAssertEqual(cancelled.count, 0)
        XCTAssertEqual(failed.count, 0)
        XCTAssertEqual(sent.count, 1)
        XCTAssertTrue(sent.contains("maya"))
        XCTAssertEqual(duplicate, sent)
    }

    func testWalkthroughProgressReducerCompletesAtFiveAndBlocksSixth() {
        var progress = InviteSelection()

        for index in 1...4 {
            progress = ContactInviteWalkthroughProgressReducer.reduce(
                state: progress,
                action: .messageComposerFinished(contactID: "contact-\(index)", outcome: .sent)
            )
        }
        XCTAssertEqual(progress.count, 4)
        XCTAssertFalse(ContactInviteWalkthroughProgressReducer.isComplete(state: progress))

        progress = ContactInviteWalkthroughProgressReducer.reduce(
            state: progress,
            action: .messageComposerFinished(contactID: "contact-5", outcome: .sent)
        )
        XCTAssertEqual(progress.count, 5)
        XCTAssertTrue(ContactInviteWalkthroughProgressReducer.isComplete(state: progress))
        XCTAssertFalse(
            ContactInviteWalkthroughProgressReducer.canInvite(
                contactID: "contact-6",
                state: progress
            )
        )

        let attemptedSixth = ContactInviteWalkthroughProgressReducer.reduce(
            state: progress,
            action: .messageComposerFinished(contactID: "contact-6", outcome: .sent)
        )
        XCTAssertEqual(attemptedSixth, progress)
        XCTAssertFalse(attemptedSixth.contains("contact-6"))
    }

    func testSelectionEnforcesTwentyPersonLimitAndStillAllowsRemoval() {
        var selection = InviteSelection()

        for index in 0..<InviteSelection.maximumCount {
            XCTAssertTrue(selection.toggle("contact-\(index)"))
        }

        XCTAssertEqual(selection.count, 20)
        XCTAssertFalse(selection.toggle("contact-over-limit"))
        XCTAssertFalse(selection.contains("contact-over-limit"))
        XCTAssertTrue(selection.toggle("contact-0"))
        XCTAssertEqual(selection.count, 19)
        XCTAssertTrue(selection.toggle("contact-over-limit"))
        XCTAssertEqual(selection.count, 20)
    }

    func testMessageDeliveryPlanPreservesProgressAcrossCancellation() throws {
        let first = inviteContact(id: "first")
        let second = inviteContact(id: "second")
        var plan = InviteMessageDeliveryPlan(contacts: [first, second])

        XCTAssertEqual(plan.currentContact, first)
        XCTAssertEqual(plan.markCurrentSent(), first)
        XCTAssertEqual(plan.sentContactIDs, ["first"])
        XCTAssertEqual(plan.sentCount, 1)
        XCTAssertEqual(plan.currentContact, second)

        plan.cancelRemaining()

        XCTAssertNil(plan.currentContact)
        XCTAssertEqual(plan.sentContactIDs, ["first"])
        XCTAssertEqual(plan.sentCount, 1)
    }

    func testAlphabetIndexMapsDragPositionToBoundedLetter() {
        XCTAssertEqual(InviteAlphabetIndex.index(yPosition: -20, height: 270, itemCount: 27), 0)
        XCTAssertEqual(InviteAlphabetIndex.index(yPosition: 135, height: 270, itemCount: 27), 13)
        XCTAssertEqual(InviteAlphabetIndex.index(yPosition: 270, height: 270, itemCount: 27), 26)
        XCTAssertNil(InviteAlphabetIndex.index(yPosition: 10, height: 0, itemCount: 27))
        XCTAssertNil(InviteAlphabetIndex.index(yPosition: 10, height: 270, itemCount: 0))
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

    func testFeedWalkthroughOpensContactsAndRewardsAFivePersonCircle() throws {
        let feed = try projectSource("Wander/Features/Feed/FeedScreen.swift")
        let sheet = try projectSource("Wander/Features/Invites/ContactInviteSheet.swift")

        XCTAssertTrue(feed.contains("walkthroughs.isRequestingContactInvite"))
        XCTAssertTrue(feed.contains("walkthroughSelectionGoal: walkthroughs.isRequestingContactInvite ? 5 : nil"))
        XCTAssertTrue(feed.contains("walkthroughs.completeContactInviteRequest()"))
        XCTAssertTrue(sheet.contains("ContactInviteWalkthroughGoalBanner("))
        XCTAssertTrue(sheet.contains("Start with five people"))
        XCTAssertTrue(sheet.contains("Fewer is fine too"))
        XCTAssertTrue(sheet.contains("finishWalkthroughAfterDeniedPermission()"))
    }

    func testWalkthroughInviteNextRemainsAvailableAndAccentsAtGoal() {
        let empty = ContactInvitePrimaryActionState.resolve(
            selectionCount: 0,
            walkthroughSelectionGoal: 5,
            defaultTitle: "Invite"
        )
        let selected = ContactInvitePrimaryActionState.resolve(
            selectionCount: 1,
            walkthroughSelectionGoal: 5,
            defaultTitle: "Invite"
        )
        let completed = ContactInvitePrimaryActionState.resolve(
            selectionCount: 5,
            walkthroughSelectionGoal: 5,
            defaultTitle: "Invite"
        )
        let ordinaryEmpty = ContactInvitePrimaryActionState.resolve(
            selectionCount: 0,
            walkthroughSelectionGoal: nil,
            defaultTitle: "Invite"
        )

        XCTAssertEqual(empty, ContactInvitePrimaryActionState(title: "Next", isEnabled: true, isSubdued: true))
        XCTAssertEqual(selected, ContactInvitePrimaryActionState(title: "Next", isEnabled: true, isSubdued: true))
        XCTAssertEqual(completed, ContactInvitePrimaryActionState(title: "Next", isEnabled: true, isSubdued: false))
        XCTAssertEqual(ordinaryEmpty, ContactInvitePrimaryActionState(title: "Invite", isEnabled: false, isSubdued: true))
    }

    func testWalkthroughInviteUsesRequestedProse() {
        XCTAssertEqual(ContactInviteWalkthroughContent.selectionGoal, 5)
        XCTAssertEqual(
            ContactInviteWalkthroughContent.inviteProse,
            "Hey sharing an invite to rec.me a social app for tracking places. This app is perfect for you and selfishly i need you on the app so i can see the places that you've been to. Excited to have you on and make sure to use my link. Heads up this invite expires in 24 hours."
        )

        let content = WanderShareContent.appInvite(
            senderProfileID: "user-sender",
            contextMessage: ContactInviteWalkthroughContent.inviteProse,
            includeInstallPrompt: false
        )
        XCTAssertEqual(content.message, ContactInviteWalkthroughContent.inviteProse)
        XCTAssertTrue(content.messageBody.hasPrefix("\(ContactInviteWalkthroughContent.inviteProse)\n\n"))
        XCTAssertTrue(content.items.contains(WanderShareContent.publicTestFlightURL))
        XCTAssertEqual(content.items.count, 2)
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
        let provider = try projectSource("Wander/Services/ContactProvider.swift")
        XCTAssertFalse(provider.contains("CNContactEmailAddressesKey"))
        XCTAssertTrue(provider.contains("guard let phoneNumber, !phoneNumber.isEmpty else { return nil }"))
    }

    func testContactInviteAddUsesMessagesDeliveryAndInteractiveAlphabetScrubber() throws {
        let sheet = try projectSource("Wander/Features/Invites/ContactInviteSheet.swift")

        XCTAssertTrue(sheet.contains("MFMessageComposeViewController.canSendText()"))
        XCTAssertTrue(sheet.contains("ContactInviteMessageComposer("))
        XCTAssertTrue(sheet.contains("case .sent:"))
        XCTAssertTrue(sheet.contains("Text(isSent ? \"Sent\" : \"Add\")"))
        XCTAssertTrue(sheet.contains("beginWalkthroughInviteDelivery(for: contact)"))
        XCTAssertTrue(sheet.contains("ContactInviteWalkthroughProgressReducer.reduce("))
        XCTAssertTrue(sheet.contains("MessageUI's `.sent` is only a successful handoff"))
        XCTAssertTrue(sheet.contains("WanderShareContent.appInvite("))
        XCTAssertTrue(sheet.contains("ContactInviteWalkthroughContent.inviteProse"))
        XCTAssertTrue(sheet.contains(".accessibilityIdentifier(\"invite.contactAdd.\\(contact.id)\")"))
        XCTAssertTrue(sheet.contains(": surface.inviteMessage"))
        XCTAssertTrue(sheet.contains("includeInstallPrompt: !isWalkthroughMode"))
        XCTAssertFalse(sheet.contains("Choose how to share"))

        XCTAssertTrue(sheet.contains("AlphabetScrubber(letters:"))
        XCTAssertTrue(sheet.contains("DragGesture(minimumDistance: 0"))
        XCTAssertTrue(sheet.contains("proxy.scrollTo(targetID"))
        XCTAssertTrue(sheet.contains("magnification(for:"))
        XCTAssertTrue(sheet.contains("UISelectionFeedbackGenerator().selectionChanged()"))
    }

    func testWalkthroughContactRowOnlyMakesAddCapsuleTappable() throws {
        let sheet = try projectSource("Wander/Features/Invites/ContactInviteSheet.swift")
        let walkthroughRow = try XCTUnwrap(
            sheet.components(separatedBy: "private func walkthroughContactRow").last?
                .components(separatedBy: "private func contactIdentity").first
        )
        let standardRow = try XCTUnwrap(
            sheet.components(separatedBy: "private func standardContactRow").last?
                .components(separatedBy: "private func walkthroughContactRow").first
        )

        XCTAssertEqual(walkthroughRow.components(separatedBy: "Button {").count - 1, 1)
        XCTAssertTrue(walkthroughRow.contains("beginWalkthroughInviteDelivery(for: contact)"))
        XCTAssertTrue(walkthroughRow.contains("Text(isSent ? \"Sent\" : \"Add\")"))
        XCTAssertTrue(standardRow.contains("Button {"))
        XCTAssertTrue(standardRow.contains("selection.toggle(contact.id)"))
    }

    private func projectSource(_ path: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: projectRoot.appendingPathComponent(path))
    }

    private func inviteContact(id: String) -> InviteContact {
        InviteContact(
            id: id,
            displayName: id.capitalized,
            contactDetail: "+1 (555) 010-1000",
            relationship: .contactOnly,
            isFrequentlyContacted: false
        )
    }
}
