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
        func tapVisibleCenter(_ button: XCUIElement) {
            // A fresh simulator can expose accessibility elements while their
            // native window still has an infinite origin and zero size. Asking
            // isHittable in that state throws before XCTest can poll again.
            let laidOut = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let frame = button.frame
                let window = app.windows.firstMatch.frame
                return frame.minX.isFinite && frame.minY.isFinite
                    && frame.width.isFinite && frame.height.isFinite
                    && !frame.isEmpty && !window.isEmpty
                    && window.minX.isFinite && window.minY.isFinite
                    && window.contains(frame)
            }, object: nil)
            guard XCTWaiter.wait(for: [laidOut], timeout: 10) == .completed else {
                XCTFail("The reminder control must finish laying out inside its native window")
                return
            }
            let visible = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"), object: button
            )
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed)
            // SwiftUI's text button can expose an unreliable default hit point.
            // Use the center of the actual visible control, as a person would.
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if primary.label == "Open Settings" {
            tapVisibleCenter(app.buttons["productUpsell.secondary"])
        } else {
            XCTAssertEqual(primary.label, "Continue")
            tapVisibleCenter(primary)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let deny = springboard.alerts.buttons.matching(
                NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")
            ).firstMatch
            if deny.waitForExistence(timeout: 5) { deny.tap() }
        }
        XCTAssertTrue(primary.waitForNonExistence(timeout: 10))
    }
}
