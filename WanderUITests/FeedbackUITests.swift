import XCTest

@MainActor final class FeedbackUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testProfileFeedbackAndSubmission() {
        let app = application()
        app.launch()
        let feedback = app.buttons["profile.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 20))
        capture("Profile with feedback button")
        feedback.tap()
        let field = app.textViews["feedback.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
        capture("Feedback empty")
        field.tap()
        field.typeText("Feature request: let us add more parks. Love Astir!")
        capture("Feedback keyboard")
        XCTAssertTrue(app.buttons["feedback.submit"].isEnabled)
        app.buttons["feedback.submit"].tap()
        XCTAssertTrue(app.staticTexts["You made Astir better."].waitForExistence(timeout: 5))
        capture("Feedback success")
        app.buttons["Done"].tap()
        XCTAssertTrue(feedback.waitForExistence(timeout: 3))
    }

    func testDraftRequiresExplicitDiscard() {
        let app = application()
        app.launch()
        XCTAssertTrue(app.buttons["profile.feedback"].waitForExistence(timeout: 20))
        app.buttons["profile.feedback"].tap()
        let field = app.textViews["feedback.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Please keep this note")
        app.buttons["Close feedback"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(field.value as? String, "Please keep this note")
        app.buttons["Close feedback"].tap()
        app.buttons["Discard feedback"].tap()
        XCTAssertTrue(app.buttons["profile.feedback"].waitForExistence(timeout: 3))
    }

    private func application() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUsePerformanceFixtures",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "profile", "-WanderFeedbackUITest"]
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
