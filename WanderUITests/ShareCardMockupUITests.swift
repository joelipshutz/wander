#if DEBUG
import XCTest

@MainActor
final class ShareCardMockupUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLinkGalleryAndRecipientReturn() {
        for kind in ["profile", "map", "list", "place", "checkIn", "wanna", "invitation"] {
            let app = launch(kind)
            XCTAssertTrue(app.staticTexts["share-mock.headline"].waitForExistence(timeout: 10))
            capture("link-\(kind)")
            let open = app.buttons["share-mock.open"]
            if !open.isHittable { app.swipeUp() }
            open.tap()
            XCTAssertTrue(app.navigationBars["Opened link"].waitForExistence(timeout: 4))
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["share-mock.open"].waitForExistence(timeout: 4))
            app.terminate()
        }
    }

    func testListCountsAndSocialFormats() {
        for (kind, format, count, dark) in [
            ("list", "Link", "0", false), ("list", "Link", "1", false),
            ("list", "Link", "2", false), ("invitation", "Link", "4", true),
            ("checkIn", "Story", "4", false), ("wanna", "Story", "4", false),
            ("checkIn", "Post", "4", false), ("wanna", "Post", "4", true)
        ] {
            let app = launch(kind, additional: ["-ShareCardFormat", format, "-ShareCardCount", count] + (dark ? ["-ShareCardDark"] : []))
            XCTAssertTrue(app.segmentedControls["share-mock.format"].waitForExistence(timeout: 10))
            capture("\(kind)-\(format)-\(count)-\(dark ? "dark" : "light")")
            app.terminate()
        }
    }

    func testSelectorsAndAccessibilityText() {
        let app = launch("profile", additional: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let title = app.staticTexts["share-mock.headline"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Discover Ryan’s world")
        for _ in 0..<4 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        capture("profile-accessibility")
        app.buttons["Toggle preview appearance"].tap()
        XCTAssertTrue(title.exists)
        app.terminate()
    }

    private func launch(_ kind: String, additional: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderShareCardMockup", kind] + additional
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "share-card-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
