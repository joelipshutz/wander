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
        // Actual native short flicks: left edge, count, and right edge are all
        // part of the same full-width drag target. No tap/adjustable shortcuts.
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
    }

    private func headerCoordinate(_ handle: XCUIElement, app: XCUIApplication, x: CGFloat) -> XCUICoordinate {
        // AX may expose only the centered label's frame; test the real drawer
        // edges using the app width at the header's vertical center.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: app.frame.width * x, dy: handle.frame.midY - app.frame.minY))
    }

    private func assertDetent(_ state: String, handle: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        let expected = "Activity drawer, \(state)"
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: handle)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: 3), .completed,
                       "Gesture must settle promptly in its intended direction: \(expected)", file: file, line: line)
    }
}
