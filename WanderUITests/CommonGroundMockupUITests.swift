#if DEBUG
import XCTest

@MainActor
final class CommonGroundMockupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNarrativeRecommendationsCitySelectionAndInvitationReturn() {
        let app = launch(page: "detail")
        let openMix = app.buttons["common-ground.open-mix"]
        XCTAssertTrue(openMix.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollTo(openMix, in: app))
        openMix.tap()

        let collectionTitle = app.staticTexts["common-ground.collection-title"]
        XCTAssertTrue(collectionTitle.waitForExistence(timeout: 5))
        let count = app.staticTexts["common-ground.mix-count"]
        assertPositivePlaceCount(on: count)
        let losAngelesCount = count.label
        let cityPicker = app.buttons["common-ground.area"]
        XCTAssertTrue(cityPicker.waitForExistence(timeout: 3))
        assertLabelContains("Los Angeles", on: cityPicker)
        XCTAssertFalse(app.buttons["common-ground.occasion"].exists)
        assertLosAngelesNarratives(in: app)
        capture("rec486-flow-01-los-angeles-recommendations")

        selectCity("London", in: app)
        assertPositivePlaceCount(on: count)
        XCTAssertNotEqual(count.label, losAngelesCount)
        XCTAssertFalse(app.buttons["common-ground.invite.not-no-bar"].exists)
        XCTAssertFalse(app.buttons["common-ground.occasion"].exists)
        capture("rec486-flow-02-london-recommendations")

        selectCity("Los Angeles", in: app)
        assertLabel(losAngelesCount, on: count)
        assertLosAngelesNarratives(in: app)

        let invite = app.buttons["common-ground.invite.not-no-bar"]
        XCTAssertTrue(scrollTo(invite, in: app))
        invite.tap()
        let previewMessages = app.buttons["common-ground.invitation.messages"]
        XCTAssertTrue(previewMessages.waitForExistence(timeout: 5))
        let postcardPlace = app.staticTexts["common-ground.invitation.place"]
        let postcardReason = app.staticTexts["common-ground.invitation.reason-title"]
        XCTAssertEqual(postcardPlace.label, "Not No Bar")
        XCTAssertFalse(postcardReason.label.isEmpty)
        let expectedReason = postcardReason.label
        capture("rec486-flow-03-invitation")
        previewMessages.tap()

        assertMessagesPreview(in: app)
        let message = app.staticTexts["common-ground.messages.message"]
        assertLabelContains("Not No Bar", on: message)
        XCTAssertFalse(message.label.contains("Narwhal"), "The invitation should describe the selected place.")
        let invitationLink = app.buttons["common-ground.messages.open-invitation"]
        assertLabelContains("Not No Bar", on: invitationLink)
        assertLabelContains(expectedReason, on: invitationLink)
        capture("rec486-flow-04-local-messages-preview")

        openRecipientFromMessages(in: app)
        XCTAssertEqual(visibleText("common-ground.invitation.place", in: app).label, "Not No Bar")
        XCTAssertEqual(visibleText("common-ground.invitation.reason-title", in: app).label, expectedReason)
        XCTAssertTrue(app.buttons["Reply in Messages"].exists)
        capture("rec486-flow-05-opened-recipient")

        closeRecipientToMessages(in: app)
        assertLabelContains("Not No Bar", on: message)
        app.buttons["common-ground.messages.close"].tap()
        XCTAssertTrue(previewMessages.waitForExistence(timeout: 3))
        XCTAssertTrue(previewMessages.isHittable)
        let invitationNavigation = app.navigationBars["Your invitation"]
        XCTAssertTrue(invitationNavigation.exists)
        invitationNavigation.buttons.firstMatch.tap()

        XCTAssertTrue(collectionTitle.waitForExistence(timeout: 4))
        assertLabelContains("Los Angeles", on: cityPicker)
        assertLabel(losAngelesCount, on: count)
        XCTAssertFalse(app.buttons["common-ground.occasion"].exists)
        XCTAssertTrue(scrollTo(invite, in: app))
        capture("rec486-flow-06-returned-city-recommendations")
    }

    func testCalendarSelectionAndPersonalNoteSurviveMessagesAndRecipientRoundTrip() {
        let app = launch(page: "mix")
        XCTAssertTrue(app.staticTexts["common-ground.collection-title"].waitForExistence(timeout: 8))
        let invite = app.buttons["common-ground.invite.not-no-bar"]
        XCTAssertTrue(scrollTo(invite, in: app))
        invite.tap()

        let whenButton = app.buttons["common-ground.invitation.when"]
        XCTAssertTrue(whenButton.waitForExistence(timeout: 5))
        let whenValue = app.staticTexts["common-ground.invitation.when-value"]
        XCTAssertFalse(whenValue.exists, "An invitation from the collection starts without a proposed time.")

        let personalNote = "This looks like a good spot for our next catch-up."
        let noteField = identifiedElement("common-ground.invitation.message", in: app)
        XCTAssertTrue(scrollTo(noteField, in: app))
        noteField.tap()
        noteField.typeText(personalNote)
        XCTAssertTrue(scrollTo(whenButton, in: app))
        whenButton.tap()

        XCTAssertTrue(app.navigationBars["Pick a time"].waitForExistence(timeout: 4))
        XCTAssertTrue(identifiedElement("common-ground.invitation.date-picker", in: app).exists)
        capture("rec486-date-calendar-picker")
        let useDate = app.buttons["common-ground.invitation.use-date"]
        XCTAssertTrue(useDate.waitForExistence(timeout: 3))
        useDate.tap()

        XCTAssertTrue(whenValue.waitForExistence(timeout: 4))
        let chosenDate = whenValue.label
        XCTAssertFalse(chosenDate.isEmpty)
        assertLabelContains(chosenDate, on: whenButton)
        capture("rec486-date-01-composed-postcard")

        let previewMessages = app.buttons["common-ground.invitation.messages"]
        XCTAssertTrue(scrollTo(previewMessages, in: app))
        previewMessages.tap()
        assertMessagesPreview(in: app)
        assertLabel(personalNote, on: app.staticTexts["common-ground.messages.message"])
        let invitationLink = app.buttons["common-ground.messages.open-invitation"]
        XCTAssertEqual(invitationLink.value as? String, chosenDate)

        openRecipientFromMessages(in: app)
        XCTAssertEqual(visibleText("common-ground.invitation.place", in: app).label, "Not No Bar")
        assertLabel(chosenDate, on: visibleText("common-ground.invitation.when-value", in: app))
        assertLabel(personalNote, on: visibleText("common-ground.invitation.copy", in: app))
        capture("rec486-date-02-recipient-keeps-date-and-note")

        closeRecipientToMessages(in: app)
        XCTAssertEqual(invitationLink.value as? String, chosenDate)
        app.buttons["common-ground.messages.close"].tap()
        XCTAssertTrue(previewMessages.waitForExistence(timeout: 3))
        assertLabel(chosenDate, on: whenValue)
    }

    func testCaptureEveryNativeDesignState() {
        let pages = [
            "detail", "mix", "profile", "ownProfile", "invitation",
            "messages", "recipient", "recipientOpened", "sparse", "loading", "unavailable"
        ]

        for page in pages {
            XCTContext.runActivity(named: "Capture Common Ground: \(page)") { _ in
                let app = launch(page: page)
                assertReady(page: page, in: app)
                capture("rec486-state-\(page)")

                if page == "mix" {
                    let finalNarrative = app.staticTexts["common-ground.narrative.the-little-room"]
                    XCTAssertTrue(scrollTo(finalNarrative, in: app))
                    capture("rec486-state-mix-scrolled-evidence")
                }
                if page == "messages" {
                    app.buttons["common-ground.messages.close"].tap()
                    XCTAssertTrue(app.buttons["common-ground.profile-entry"].waitForExistence(timeout: 4))
                }
                if page == "recipient" {
                    app.buttons["Open Ryan’s invitation"].tap()
                    XCTAssertTrue(app.buttons["Reply in Messages"].waitForExistence(timeout: 4))
                    capture("rec486-state-recipient-revealed")
                }
                app.terminate()
            }
        }
    }

    private func launch(page: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderCommonGroundMockup", page
        ]
        app.launch()
        return app
    }

    private func assertReady(page: String, in app: XCUIApplication) {
        if page != "messages" {
            XCTAssertTrue(app.buttons["Design previews"].firstMatch.waitForExistence(timeout: 8))
        }
        switch page {
        case "detail":
            XCTAssertTrue(app.buttons["common-ground.open-mix"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["You & Joe"].exists)
        case "mix":
            XCTAssertTrue(app.staticTexts["common-ground.collection-title"].waitForExistence(timeout: 3))
            let count = app.staticTexts["common-ground.mix-count"]
            assertPositivePlaceCount(on: count)
            XCTAssertFalse(app.buttons["common-ground.occasion"].exists)
        case "profile":
            XCTAssertTrue(app.navigationBars["Joe’s profile"].exists)
            XCTAssertTrue(app.buttons["common-ground.profile-entry"].waitForExistence(timeout: 3))
        case "ownProfile":
            XCTAssertTrue(app.navigationBars["Your profile"].exists)
            XCTAssertTrue(app.staticTexts["Ryan"].firstMatch.exists)
            XCTAssertFalse(app.buttons["common-ground.profile-entry"].exists)
        case "invitation":
            XCTAssertTrue(app.buttons["common-ground.invitation.messages"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["common-ground.invitation.place"].exists)
        case "messages":
            assertMessagesPreview(in: app)
        case "recipient":
            XCTAssertTrue(app.buttons["Open Ryan’s invitation"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Reply in Messages"].exists)
        case "recipientOpened":
            XCTAssertTrue(app.buttons["Reply in Messages"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["common-ground.invitation.place"].exists)
        case "sparse":
            let mix = app.buttons["common-ground.open-mix"]
            XCTAssertTrue(mix.waitForExistence(timeout: 3))
            XCTAssertFalse(mix.label.isEmpty)
        case "loading":
            let loading = app.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Finding your common ground…")
            ).firstMatch
            XCTAssertTrue(loading.waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["common-ground.open-mix"].exists)
        case "unavailable":
            XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["A little out of reach"].exists)
            XCTAssertFalse(app.buttons["common-ground.open-mix"].exists)
        default:
            XCTFail("Missing readiness assertion for \(page)")
        }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    // A full-screen recipient cover preserves its presenting composer. Verify
    // the visible postcard rather than accepting either copy in the AX tree.
    private func visibleText(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.staticTexts.matching(identifier: identifier)
        let visible = matches.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(visible, "Expected visible postcard text: \(identifier)")
        return visible ?? matches.firstMatch
    }

    private func identifiedElement(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertMessagesPreview(in app: XCUIApplication) {
        XCTAssertTrue(identifiedElement("common-ground.messages.conversation", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["common-ground.messages.preview-notice"].exists)
        XCTAssertTrue(app.buttons["common-ground.messages.open-invitation"].exists)
        XCTAssertFalse(app.buttons["Send"].exists, "The local demo must not expose actual delivery.")
    }

    private func openRecipientFromMessages(in app: XCUIApplication) {
        let invitationLink = app.buttons["common-ground.messages.open-invitation"]
        XCTAssertTrue(scrollTo(invitationLink, in: app))
        invitationLink.tap()
        XCTAssertTrue(app.buttons["Reply in Messages"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Ryan’s invitation"].exists, "The Messages link should open the postcard directly.")
    }

    private func closeRecipientToMessages(in app: XCUIApplication) {
        let closeRecipient = app.buttons["common-ground.recipient.close"]
        XCTAssertTrue(closeRecipient.waitForExistence(timeout: 3))
        closeRecipient.tap()
        XCTAssertTrue(closeRecipient.waitForNonExistence(timeout: 4))
        assertMessagesPreview(in: app)
    }

    private func selectCity(_ city: String, in app: XCUIApplication) {
        let picker = app.buttons["common-ground.area"]
        for _ in 0..<8 {
            if picker.exists && picker.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(picker.isHittable, "The city picker should remain reachable.")
        picker.tap()
        XCTAssertFalse(app.buttons["Kyoto"].exists, "A city only on a Wanna list is not part of the visited-city picker.")
        let option = app.buttons[city].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        option.tap()
        assertLabelContains(city, on: picker)
    }

    private func assertLosAngelesNarratives(in app: XCUIApplication) {
        let narratives = [
            ("narwhal", "You both love Narwhal."),
            ("grove-gardens", "Grove Gardens won you both over."),
            ("not-no-bar", "You both want to try Not No Bar."),
            ("mudwater", "Joe loves Mudwater. You’re next?"),
            ("the-little-room", "You could show Joe The Little Room.")
        ]
        for (id, expectedTitle) in narratives {
            let title = app.staticTexts["common-ground.narrative.\(id)"]
            XCTAssertTrue(title.waitForExistence(timeout: 3), "Missing narrative for \(id).")
            XCTAssertEqual(title.label, expectedTitle)
        }
    }

    private func assertPositivePlaceCount(
        on element: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        let number = element.label.split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
        XCTAssertGreaterThan(number ?? 0, 0, "Expected a nonempty recommendation collection.", file: file, line: line)
    }

    private func assertLabelContains(
        _ expected: String, on element: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", expected), object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 4), .completed,
            "Expected \(element.label) to contain \(expected)", file: file, line: line
        )
    }

    private func assertLabel(
        _ expected: String, on element: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", expected), object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 4), .completed,
            "Expected \(expected), received \(element.label)", file: file, line: line
        )
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
