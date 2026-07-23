import XCTest

final class OnboardingUITests: XCTestCase {
    func testLoggedOutCarouselAutoAdvancesAndKeepsActionsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderOnboardingUITestSignedOut"]
        app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "0.75"
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["onboarding.logIn"].exists)
        XCTAssertTrue(app.staticTexts["Keep track of everywhere you’ve been"].exists)
        XCTAssertTrue(app.staticTexts["See the places your friends love"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["onboarding.getStarted"].isHittable)
    }
}
