#if DEBUG
import XCTest

@MainActor
final class CommonGroundMockupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDetailMixFilterInvitationAndReturnPreserveTheChosenOccasion() {
        let app = launch(page: "detail")
        let openMix = app.buttons["common-ground.open-mix"]
        XCTAssertTrue(openMix.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollTo(openMix, in: app))
        openMix.tap()

        let count = app.staticTexts["common-ground.mix-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "6 PLACES FOR YOU TWO")
        let occasion = app.buttons["common-ground.occasion"]
        XCTAssertTrue(occasion.waitForExistence(timeout: 3))
        occasion.tap()
        let dateNight = app.buttons["Date night"].firstMatch
        XCTAssertTrue(dateNight.waitForExistence(timeout: 3))
        dateNight.tap()
        assertLabel("2 PLACES FOR YOU TWO", on: count)
        capture("rec486-flow-01-date-night-mix")

        let invite = app.buttons["common-ground.invite.not-no-bar"]
        XCTAssertTrue(scrollTo(invite, in: app))
        invite.tap()
        let share = app.buttons["Share your invitation"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Your invitation"].exists)
        capture("rec486-flow-02-invitation")
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
        capture("rec486-flow-03-local-messages-preview")

        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Messages"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertTrue(share.isHittable)
        let invitationNavigation = app.navigationBars["Your invitation"]
        XCTAssertTrue(invitationNavigation.exists)
        invitationNavigation.buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["For you two"].waitForExistence(timeout: 4))
        assertLabel("2 PLACES FOR YOU TWO", on: count)
        XCTAssertTrue(scrollTo(invite, in: app))
        capture("rec486-flow-04-returned-filtered-mix")
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
            let count = app.staticTexts["common-ground.mix-count"]
            XCTAssertTrue(count.waitForExistence(timeout: 3))
            XCTAssertEqual(count.label, "6 PLACES FOR YOU TWO")
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
            XCTAssertEqual(mix.label, "Open your mix, 2 places for you and Joe")
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
        for _ in 0..<4 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
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
