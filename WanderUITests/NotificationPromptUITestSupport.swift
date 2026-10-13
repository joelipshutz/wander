import XCTest

extension XCTestCase {
    /// Home is asynchronous on a busy simulator. Wait for the actual lifecycle
    /// transition before requesting foreground entry or opening a deep link.
    @MainActor
    func backgroundApplication(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCUIDevice.shared.press(.home)
        let backgrounded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground || app.state == .runningBackgroundSuspended
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [backgrounded], timeout: 10), .completed, file: file, line: line)
    }

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
