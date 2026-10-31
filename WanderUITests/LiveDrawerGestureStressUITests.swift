import XCTest

@MainActor
final class LiveDrawerGestureStressUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testRepeatedQuickFlicksAcrossHeaderAndLongDragsKeepDirection() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture",
            "-WanderFeedPaginationUITest",
            "-WanderInitialTab", "discover",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3"]
        app.launch()
        let handle = app.staticTexts.matching(identifier: "live.drawerHandle").element
        XCTAssertTrue(handle.waitForExistence(timeout: 30))
        assertDetent("half expanded", handle: handle)
        // Actual native short flicks across the clear grabber strip at the left,
        // center and right. The action buttons below it are separate controls.
        // No tap/adjustable shortcuts replace any drawer gesture.
        for x in [0.08, 0.5, 0.92] {
            for _ in 0..<2 {
                drag(handle, app: app, x: x, dy: 56, velocity: .fast)
                assertDetent("collapsed", handle: handle)
                drag(handle, app: app, x: x, dy: -56, velocity: .fast)
                assertDetent("half expanded", handle: handle)
                drag(handle, app: app, x: x, dy: -56, velocity: .fast)
                assertDetent("expanded", handle: handle)
                drag(handle, app: app, x: x, dy: 56, velocity: .fast)
                assertDetent("half expanded", handle: handle)
            }
        }
        // Hold/drag through a full detent, then release with no momentum.
        drag(handle, app: app, x: 0.08, dy: 240, velocity: .slow, hold: 0.25)
        assertDetent("collapsed", handle: handle)
        let start = headerCoordinate(handle, app: app, x: 0.92)
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.14))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        assertDetent("expanded", handle: handle)
        XCTAssertTrue(app.buttons["live.showMap"].isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "drawer-after-26-native-gestures"
        capture.lifetime = .keepAlways
        add(capture)
        app.buttons["live.showMap"].tap()
        assertDetent("collapsed", handle: handle)
        XCTAssertTrue(app.buttons["live.draw"].isHittable)
    }

    private func drag(_ handle: XCUIElement, app: XCUIApplication, x: CGFloat, dy: CGFloat,
                      velocity: XCUIGestureVelocity, hold: TimeInterval = 0) {
        XCTAssertTrue(handle.isHittable)
        let start = headerCoordinate(handle, app: app, x: x)
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)),
                    withVelocity: velocity, thenHoldForDuration: hold)
        let events = app.staticTexts["events.comingSoon"]
        XCTAssertFalse(events.exists && events.isHittable,
                       "A drawer drag must not activate the Events destination")
    }

    private func headerCoordinate(_ handle: XCUIElement, app: XCUIApplication, x: CGFloat) -> XCUICoordinate {
        // The header's vertical center intersects the 44pt Events/Invite
        // buttons. Begin in the same full-width grabber strip used by a finger,
        // above those independent controls, and keep all three horizontal lanes.
        let frame = handle.frame
        let point = CGPoint(x: app.frame.minX + app.frame.width * x,
                            y: frame.minY + min(12, frame.height * 0.15))
        XCTAssertTrue(frame.contains(point), "The gesture must begin inside the drawer header")
        for identifier in ["live.utility.events", "live.utility.invite"] {
            let button = app.buttons[identifier]
            if button.exists {
                XCTAssertFalse(button.frame.contains(point), "The drag origin must avoid \(identifier)")
            }
        }
        return app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    private func assertDetent(_ state: String, handle: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = "Activity drawer, \(state)"
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: handle)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed,
                       "Gesture must settle promptly in its intended direction: \(expected)", file: file, line: line)
    }
}
