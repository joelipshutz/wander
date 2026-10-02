import XCTest

extension XCTestCase {
    /// Establish the normal post-onboarding permission state before a launch
    /// fixture opens a sheet or walkthrough. A fresh system prompt interrupts
    /// scene activation and would otherwise dismiss those launch-only fixtures.
    @MainActor
    func launchAfterResolvingLocationPermission(in app: XCUIApplication) {
        let arguments = app.launchArguments
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"
        ]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if !allow.waitForExistence(timeout: 1) {
            let nearby = app.buttons["map.nearby"]
            XCTAssertTrue(nearby.waitForExistence(timeout: 10))
            nearby.tap()
            let continueButton = app.buttons["map.locationEducation.allow"]
            XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
            continueButton.tap()
        }
        XCTAssertTrue(allow.waitForExistence(timeout: 5))
        allow.tap()
        XCTAssertTrue(allow.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launchArguments = arguments
        app.launch()
    }
}
