import XCTest

@MainActor
final class ProfileHeaderMotionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNormalOwnerPinsIdentityAndKeepsNavigationAfterReturning() {
        let app = launch(["-WanderInitialTab", "profile"])
        dismissStartupNotificationPromptIfNeeded(in: app)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        let name = app.staticTexts["profile.header.name"].firstMatch
        let photo = app.buttons["profile.header.photo"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let toolbarY = settings.frame.midY
        let photoWidth = photo.frame.width
        XCTAssertLessThan(name.frame.midY, photo.frame.midY - 5)
        capture("Owner clear header")

        app.swipeUp()
        assertPinned(in: app)
        XCTAssertEqual(photo.frame.width, photoWidth, accuracy: 1)
        XCTAssertEqual(settings.frame.midY, toolbarY, accuracy: 1)
        XCTAssertEqual(app.buttons.matching(identifier: "Settings").count, 1)
        capture("Owner pinned header")

        // Edit belongs to the scrollable identity block, below Member since.
        let edit = app.buttons["Edit profile"]
        for _ in 0..<6 where !edit.isHittable { app.swipeDown() }
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        app.swipeUp()
        assertPinned(in: app)
        settings.tap()
        let settingsScreen = app.descendants(matching: .any)["settings.screen"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(settingsScreen.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        XCTAssertEqual(settings.frame.midY, toolbarY, accuracy: 1)

        app.buttons["Feed"].firstMatch.tap()
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        XCTAssertEqual(settings.frame.midY, toolbarY, accuracy: 1)
        for _ in 0..<6 where name.frame.midY >= photo.frame.midY - 5 { app.swipeDown() }
        XCTAssertLessThan(name.frame.midY, photo.frame.midY - 5)
        capture("Owner restored header after navigation")
    }

    func testNormalMemberKeepsMoreActionsAndBackWhilePinned() {
        let app = launch(["-WanderMapCapture", "-WanderOpenProfile", "user_maya"])
        let more = app.buttons["More profile actions"]
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        let name = app.staticTexts["profile.header.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let toolbarY = more.frame.midY
        capture("Member clear header")
        app.swipeUp()
        assertPinned(in: app)
        XCTAssertEqual(more.frame.midY, toolbarY, accuracy: 1)
        capture("Member pinned header")
        more.tap()
        XCTAssertTrue(app.buttons["Unfollow"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)).tap()
        app.buttons["Back"].firstMatch.tap()
        XCTAssertTrue(more.waitForNonExistence(timeout: 5))
    }

    func testPinnedPhotoRetainsItsTapActionAndGeometryAfterFullScreenCover() {
        let app = launch(["-ProfileHeaderMotion", "compact"])
        let photo = app.buttons["profile.header.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let settings = app.buttons["Settings"]
        let toolbarY = settings.frame.midY
        app.swipeUp()
        photo.tap()
        let close = app.buttons["Close profile photo"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(settings.isHittable)
        XCTAssertEqual(settings.frame.midY, toolbarY, accuracy: 1)
        assertPinned(in: app)
        capture("Pinned photo after full-screen return")
    }

    func testPhotoRemainsVisibleThroughPartialReverseAndResnapsAtTop() {
        let app = launch(["-ProfileHeaderMotion", "compact"])
        let photo = app.buttons["profile.header.photo"]
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        let originalFrame = photo.frame
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.40))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertEqual(photo.frame.minY, originalFrame.minY, accuracy: 2)
        capture("Photo above header after downward scroll")

        // Short, slow steps stop inside the former bio-triggered disappearance
        // interval instead of skipping directly back to the top with a fling.
        for step in 0..<5 {
            let reverseEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
            end.press(forDuration: 0.1, thenDragTo: reverseEnd, withVelocity: .slow, thenHoldForDuration: 0.5)
            XCTAssertEqual(photo.frame.width, originalFrame.width, accuracy: 1)
            XCTAssertEqual(photo.frame.minY, originalFrame.minY, accuracy: 2)
            XCTAssertTrue(photo.isHittable)
            capture("Photo returning step \(step)")
        }
        photo.tap()
        XCTAssertTrue(app.buttons["Close profile photo"].waitForExistence(timeout: 5))
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs"] + arguments
        app.launch()
        return app
    }

    private func assertPinned(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        var geometry: (name: CGRect, photo: CGRect)?
        let result = UIObservation.wait(timeout: 3) {
            guard let snapshot = try? app.snapshot() else { return false }
            let nodes = UIObservation.descendants(of: snapshot)
            guard let name = nodes.first(where: { $0.elementType == .staticText && $0.identifier == "profile.header.name" }),
                  let photo = nodes.first(where: { $0.identifier == "profile.header.photo" }) else { return false }
            geometry = (name.frame, photo.frame)
            return abs(name.frame.midY - photo.frame.midY) <= 3
        }
        XCTAssertEqual(result, .completed, file: file, line: line)
        guard let geometry else { return XCTFail("Expected both header frames in one native snapshot", file: file, line: line) }
        XCTAssertEqual(geometry.name.midY, geometry.photo.midY, accuracy: 3, file: file, line: line)
        XCTAssertGreaterThan(geometry.photo.minY, 40, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
