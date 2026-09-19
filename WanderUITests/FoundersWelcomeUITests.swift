import XCTest

@MainActor
final class FoundersWelcomeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPlayPauseMuteBackgroundAndSkipIntoWalkthrough() {
        let app = launch()
        let play = app.buttons["onboarding.founders.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        screenshot("Founders-poster", app)
        XCTAssertTrue(app.buttons["onboarding.founders.skip"].isHittable)
        play.tap()
        let pause = app.buttons["onboarding.founders.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        XCTAssertTrue(pause.label.contains("Pause"))
        screenshot("Founders-playing", app)
        pause.tap()
        XCTAssertTrue(pause.label.contains("Resume"))
        pause.tap()
        let mute = app.buttons["onboarding.founders.mute"]
        mute.tap()
        XCTAssertTrue(mute.label.contains("Sound on"))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(pause.waitForExistence(timeout: 6))
        XCTAssertTrue(pause.label.contains("Resume"), "Returning to the app must not unexpectedly resume sound.")
        app.buttons["onboarding.founders.skip"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons["onboarding.founders.skip"].exists)
        screenshot("Founders-to-NUX", app)
    }

    func testActualMovieEndEntersWalkthrough() {
        let app = launch(position: "89")
        let play = app.buttons["onboarding.founders.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 15), "The AVPlayer end notification must release the NUX gate.")
        XCTAssertFalse(app.buttons["onboarding.founders.skip"].exists)
    }

    private func launch(position: String = "0") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderNativeOnboardingReview", "founders", "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures"]
        app.launchEnvironment["WANDER_FOUNDERS_REVIEW_POSITION"] = position
        app.launch()
        return app
    }
    private func screenshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
