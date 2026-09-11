import XCTest

@MainActor
final class ProfileAlignmentUITests: XCTestCase {
    func testMemberProfileStaysWithinScreenWhileScrolling() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderOpenProfile", "user_maya"
        ]
        app.launch()
        let back = app.buttons["Back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        let activity = app.otherElements["profile.walkthrough.activitySection"]
        XCTAssertTrue(activity.waitForExistence(timeout: 5))
        let screen = app.frame
        assertFits(activity, in: screen)
        let initialFrame = activity.frame
        capture("Profile initial alignment")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.65))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.40)))
        assertFits(activity, in: screen)
        XCTAssertEqual(activity.frame.minX, initialFrame.minX, accuracy: 1)
        XCTAssertLessThan(activity.frame.minY, initialFrame.minY, "Vertical scrolling must still work")
        capture("Profile after diagonal scroll")
        app.swipeDown()
        assertFits(activity, in: screen)
        XCTAssertEqual(activity.frame.minX, initialFrame.minX, accuracy: 1)
        capture("Profile after reverse scroll")
    }

    private func assertFits(_ element: XCUIElement, in screen: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, screen.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxX, screen.maxX, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
