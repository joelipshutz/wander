import XCTest

@MainActor
final class ProfileHeaderMotionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testNormalOwnerPinsIdentityAndKeepsNavigationAfterReturning() {
        let app = launch(["-WanderInitialTab", "profile"])
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
        assertPinned(name: name, photo: photo)
        XCTAssertEqual(photo.frame.width, photoWidth, accuracy: 1)
        XCTAssertEqual(settings.frame.midY, toolbarY, accuracy: 1)
        XCTAssertEqual(app.buttons.matching(identifier: "Settings").count, 1)
        capture("Owner pinned header")

        app.buttons["Edit profile"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
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
        let photo = app.descendants(matching: .any)["profile.header.photo"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let toolbarY = more.frame.midY
        capture("Member clear header")
        app.swipeUp()
        assertPinned(name: name, photo: photo)
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
        assertPinned(name: app.staticTexts["profile.header.name"].firstMatch, photo: photo)
        capture("Pinned photo after full-screen return")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs"] + arguments
        app.launch()
        return app
    }

    private func assertPinned(name: XCUIElement, photo: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(name.frame.midY, photo.frame.midY, accuracy: 3, file: file, line: line)
        XCTAssertGreaterThan(photo.frame.minY, 40, file: file, line: line)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
