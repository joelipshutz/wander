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
        XCTAssertTrue(app.staticTexts["Find places nearby"].waitForExistence(timeout: 15))
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
        let deadline = ProcessInfo.processInfo.systemUptime + 25
        let visible = NSPredicate { _, _ in
            guard ProcessInfo.processInfo.systemUptime < deadline,
                  let snapshot = try? app.snapshot(),
                  ProcessInfo.processInfo.systemUptime < deadline else { return false }
            // One native read keeps the dot and exposed-map bounds simultaneous.
            return self.hasVisibleLocation(in: snapshot)
                && ProcessInfo.processInfo.systemUptime < deadline
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

    private func hasVisibleLocation(in snapshot: XCUIElementSnapshot) -> Bool {
        @MainActor
        func descendants(of node: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            node.children.flatMap { [$0] + descendants(of: $0) }
        }
        @MainActor
        func valid(_ frame: CGRect) -> Bool {
            !frame.isEmpty && !frame.isNull && !frame.isInfinite
                && [frame.minX, frame.minY, frame.maxX, frame.maxY].allSatisfy(\.isFinite)
        }
        let nodes = descendants(of: snapshot)
        let maps = nodes.filter { $0.identifier == "live.map" }
        let draws = nodes.filter { $0.elementType == .button && $0.identifier == "live.draw" }
        let drawers = nodes.filter { $0.identifier == "live.drawerHandle" }
        guard maps.count == 1, draws.count == 1, drawers.count == 1,
              valid(snapshot.frame), valid(maps[0].frame), valid(draws[0].frame), valid(drawers[0].frame)
        else { return false }
        let nativeMaps = ([maps[0]] + descendants(of: maps[0])).filter { $0.elementType == .map }
        guard nativeMaps.count == 1, valid(nativeMaps[0].frame) else { return false }
        let mapFrame = maps[0].frame.intersection(nativeMaps[0].frame).intersection(snapshot.frame)
        let top = max(mapFrame.minY, draws[0].frame.maxY)
        let bottom = min(mapFrame.maxY, drawers[0].frame.minY)
        guard valid(mapFrame), top < bottom else { return false }
        let locationLabels = ["current location", "my location", "your location", "user location"]
        let frames = descendants(of: maps[0]).filter { node in
            locationLabels.contains { node.label.localizedCaseInsensitiveContains($0) }
        }.map(\.frame)
        // MapKit may repeat the same annotation in its accessibility hierarchy.
        // Distinct candidate geometry is ambiguous and must not pass by chance.
        guard let frame = frames.first, valid(frame), frames.allSatisfy({ $0 == frame }) else { return false }
        return frame.midX > mapFrame.minX && frame.midX < mapFrame.maxX
            && frame.midY > top && frame.midY < bottom
    }
}
