import XCTest

extension XCTestCase {
    /// The first-visit reminder covers the app's controls. Complete its real
    /// interaction before testing unrelated tabs; do not disable production UX.
    @MainActor
    func dismissStartupNotificationPromptIfNeeded(in app: XCUIApplication) {
        let primary = app.buttons["productUpsell.primary"]
        guard primary.waitForExistence(timeout: 8) else { return }
        XCTAssertTrue(app.staticTexts["Keep up with your people"].exists)
        if primary.label == "Open Settings" {
            app.buttons["productUpsell.secondary"].tap()
        } else {
            XCTAssertEqual(primary.label, "Continue")
            primary.tap()
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let deny = springboard.alerts.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")
            ).firstMatch
            if deny.waitForExistence(timeout: 5) { deny.tap() }
        }
        XCTAssertTrue(primary.waitForNonExistence(timeout: 10))
    }
}
