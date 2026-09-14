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
        let share = app.buttons["Share your invitation"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Your invitation"].exists)
        capture("rec486-flow-03-invitation")
        share.tap()

        XCTAssertTrue(app.navigationBars["Sharing preview"].waitForExistence(timeout: 4))
        let localPreviewNotice = app.staticTexts["Preview only. Nothing has been sent."]
        XCTAssertTrue(localPreviewNotice.waitForExistence(timeout: 3))
        let messages = app.buttons["Messages"].firstMatch
        XCTAssertTrue(messages.waitForExistence(timeout: 3))
        messages.tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["To Joe"].exists)
        XCTAssertTrue(app.staticTexts["Not No Bar"].firstMatch.exists)
        XCTAssertTrue(localPreviewNotice.exists)
        XCTAssertFalse(app.buttons["Send"].exists, "The local demo must not expose actual delivery.")
        capture("rec486-flow-04-local-messages-preview")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertTrue(share.isHittable)
        let invitationNavigation = app.navigationBars["Your invitation"]
        XCTAssertTrue(invitationNavigation.exists)
        invitationNavigation.buttons.firstMatch.tap()

        XCTAssertTrue(collectionTitle.waitForExistence(timeout: 4))
        assertLabelContains("Los Angeles", on: cityPicker)
        assertLabel(losAngelesCount, on: count)
        XCTAssertFalse(app.buttons["common-ground.occasion"].exists)
        XCTAssertTrue(scrollTo(invite, in: app))
        capture("rec486-flow-05-returned-city-recommendations")
    }

    func testCaptureEveryNativeDesignState() {
        let pages = [
            "detail", "mix", "profile", "ownProfile", "invitation",
            "recipient", "sparse", "loading", "unavailable"
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
                if page == "recipient" {
                    app.buttons["Open Ryan’s invitation"].tap()
                    XCTAssertTrue(app.buttons["Reply in Messages"].waitForExistence(timeout: 4))
                    capture("rec486-state-recipient-opened")
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
        XCTAssertTrue(app.buttons["Design previews"].firstMatch.waitForExistence(timeout: 8))
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
            XCTAssertTrue(app.buttons["Share your invitation"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["A little nudge from Astir."].exists)
        case "recipient":
            XCTAssertTrue(app.buttons["Open Ryan’s invitation"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["Reply in Messages"].exists)
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
