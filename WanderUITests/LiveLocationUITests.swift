import CoreLocation
import XCTest

@MainActor
final class LiveLocationUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testLaunchAndForegroundShowCurrentLocationOutsideHomeCity() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 40.7128, longitude: -74.0060))
        addTeardownBlock {
            app.terminate()
            app.resetAuthorizationStatus(for: .location)
            XCUIDevice.shared.location = nil
        }
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestStep", "location"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Find Places Nearby"].waitForExistence(timeout: 15))
        app.buttons["Continue"].firstMatch.tap()
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Allow While Using App"].tap()
        app.terminate()

        // Auth fixtures supply content/home city, but omit location fixture flags:
        // the production CoreLocation path must use the simulated device fix.
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3"]
        app.launch()
        assertVisibleLocation(in: app, capture: "live-current-location-new-york")

        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(latitude: 47.6062, longitude: -122.3321))
        app.activate()
        assertVisibleLocation(in: app, capture: "live-current-location-seattle-foreground")
    }

    private func assertVisibleLocation(in app: XCUIApplication, capture name: String) {
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        let dot = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                        "current location", "my location", "your location", "user location")
        ).firstMatch
        let visible = NSPredicate { _, _ in
            guard dot.exists else { return false }
            let frame = dot.frame
            let top = app.buttons["live.draw"].frame.maxY
            let bottom = app.descendants(matching: .any)["live.drawerHandle"].firstMatch.frame.minY
            return !frame.isEmpty && frame.midX > 0 && frame.midX < app.frame.width
                && frame.midY > top && frame.midY < bottom
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 25)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "\(name)-accessibility"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed,
                       "The actual device-location dot must be inside the exposed map, not at the home city.")
    }
}
