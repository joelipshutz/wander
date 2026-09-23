import XCTest

@MainActor final class FeedbackUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testFeedbackEntryIsHiddenWithoutExplicitEnablement() {
        let app = application()
        app.launchArguments.removeAll { $0 == "-WanderFeedbackUITest" }
        app.launch()
        XCTAssertTrue(app.buttons["Edit profile"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["profile.feedback"].exists)
        capture("Profile feedback disabled")
    }

    func testProfileFeedbackAndSubmission() {
        let app = application()
        app.launch()
        let feedback = app.buttons["profile.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 20))
        capture("Profile with feedback button")
        feedback.tap()
        XCTAssertTrue(app.staticTexts["Drop us a line"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedback.tab.voice"].isSelected)
        XCTAssertTrue(app.buttons["feedback.record"].exists)
        XCTAssertFalse(app.textViews["feedback.text"].exists)
        XCTAssertTrue(app.buttons["feedback.photos"].exists)
        XCTAssertTrue(app.buttons["feedback.photos"].isEnabled)
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
        capture("Feedback voice default")
        app.buttons["feedback.tab.text"].tap()
        let field = app.textViews["feedback.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
        XCTAssertTrue(app.buttons["feedback.photos"].exists)
        capture("Feedback text empty")
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
        app.buttons["feedback.tab.text"].tap()
        let field = app.textViews["feedback.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Please keep this note")
        app.buttons["feedback.tab.voice"].tap()
        XCTAssertTrue(app.buttons["feedback.record"].exists)
        XCTAssertTrue(app.buttons["feedback.submit"].isEnabled)
        app.buttons["feedback.tab.text"].tap()
        XCTAssertEqual(field.value as? String, "Please keep this note")
        app.buttons["Close feedback"].tap()
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(field.value as? String, "Please keep this note")
        app.buttons["Close feedback"].tap()
        app.buttons["Discard feedback"].tap()
        XCTAssertTrue(app.buttons["profile.feedback"].waitForExistence(timeout: 3))
    }

    func testVoicePlaybackAndReplacementKeepsTextDraft() {
        let app = application()
        app.launchArguments.append("-WanderFeedbackVoiceUITest")
        app.launch()
        XCTAssertTrue(app.buttons["profile.feedback"].waitForExistence(timeout: 20))
        app.buttons["profile.feedback"].tap()
        let play = app.buttons["feedback.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["feedback.submit"].isEnabled)
        capture("Feedback recorded voice")
        play.tap()
        XCTAssertEqual(play.label, "Pause voice note")
        play.tap()
        XCTAssertEqual(play.label, "Play voice note")
        app.buttons["feedback.stopPlayback"].tap()
        app.buttons["feedback.tab.text"].tap()
        let field = app.textViews["feedback.text"]
        field.tap(); field.typeText("A little context for my voice note")
        app.buttons["feedback.tab.voice"].tap()
        XCTAssertTrue(play.exists)
        let recordAgain = app.buttons["Record again"]
        if !recordAgain.isHittable { app.swipeUp() }
        recordAgain.tap()
        app.buttons["Keep recording"].tap()
        XCTAssertTrue(play.exists)
        recordAgain.tap()
        app.buttons["Replace recording"].tap()
        XCTAssertTrue(app.buttons["feedback.record"].exists)
        XCTAssertFalse(play.exists)
        app.buttons["feedback.tab.text"].tap()
        XCTAssertEqual(field.value as? String, "A little context for my voice note")
    }

    func testVoiceAndTextSurviveRepeatedBackgroundAndForeground() {
        let app = application()
        app.launchArguments.append("-WanderFeedbackVoiceUITest")
        app.launch()
        let feedback = app.buttons["profile.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 20))
        feedback.tap()
        app.buttons["feedback.tab.text"].tap()
        let field = app.textViews["feedback.text"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Keep this context when I leave the app")
        app.buttons["feedback.tab.voice"].tap()

        for cycle in 1...3 {
            let play = app.buttons["feedback.play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5))
            play.tap()
            XCTAssertEqual(play.label, "Pause voice note")
            backgroundAndReturn(app)
            let paused = NSPredicate(format: "label == %@", "Play voice note")
            expectation(for: paused, evaluatedWith: play)
            waitForExpectations(timeout: 5)
            XCTAssertFalse(app.descendants(matching: .any)["feedback.error"].exists)
            XCTAssertTrue(app.buttons["feedback.submit"].isEnabled)
            XCTAssertTrue(app.buttons["feedback.photos"].isEnabled)
            capture("Feedback return \(cycle)")
            app.buttons["feedback.tab.text"].tap()
            XCTAssertEqual(field.value as? String, "Keep this context when I leave the app")
            app.buttons["feedback.tab.voice"].tap()
        }
        app.buttons["feedback.submit"].tap()
        XCTAssertTrue(app.staticTexts["You made Astir better."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
    }

    func testEmptyVoiceFormRemainsUsableAfterBackgroundAndReopening() {
        let app = application()
        app.launch()
        let feedback = app.buttons["profile.feedback"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 20))
        for _ in 0..<3 {
            feedback.tap()
            XCTAssertTrue(app.buttons["feedback.record"].waitForExistence(timeout: 5))
            backgroundAndReturn(app)
            XCTAssertTrue(app.buttons["feedback.record"].isEnabled)
            XCTAssertTrue(app.buttons["feedback.photos"].isEnabled)
            XCTAssertFalse(app.buttons["feedback.submit"].isEnabled)
            app.buttons["Close feedback"].tap()
            XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        }
    }

    private func backgroundAndReturn(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
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
