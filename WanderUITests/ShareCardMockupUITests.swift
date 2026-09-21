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
            XCTAssertTrue(app.descendants(matching: .any)["share-mock.headline"].waitForExistence(timeout: 10))
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
        let title = app.descendants(matching: .any)["share-mock.headline"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Discover Ryan’s world. View")
        for _ in 0..<4 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        capture("profile-accessibility")
        app.buttons["Toggle preview appearance"].tap()
        XCTAssertTrue(title.exists)
        app.terminate()
    }


    func testWannaDateReplacesRadarAndKeepsLetsGo() {
        let app = launch("wanna")
        let card = app.descendants(matching: .any)["share-mock.headline"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("On Ryan’s radar"))
        XCTAssertTrue(card.label.contains("Let’s Go"))
        let dateToggle = app.switches["share-mock.dated"]
        // SwiftUI exposes the whole labeled row as the switch. Target its
        // trailing control rather than the inert center of that row.
        dateToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let dated = NSPredicate(format: "label CONTAINS %@ AND NOT (label CONTAINS %@)", "2026", "radar")
        expectation(for: dated, evaluatedWith: card)
        waitForExpectations(timeout: 4)
        XCTAssertFalse(card.label.contains("radar"))
        XCTAssertTrue(card.label.contains("2026"))
        XCTAssertTrue(card.label.contains("Let’s Go"))
        capture("wanna-dated")
        app.terminate()
    }

    func testProductionShareSheetUsesAllFormatsAndKeepsCanonicalLink() {
        let app = launch("wanna", additional: ["-ShareCardDated"])
        app.buttons["share-mock.try"].tap()
        let formats = app.segmentedControls["share.format"]
        XCTAssertTrue(formats.waitForExistence(timeout: 10))
        for format in ["Link", "Story", "Post"] {
            let segment = formats.buttons[format]
            segment.tap()
            expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: segment)
            waitForExpectations(timeout: 4)
            XCTAssertTrue(app.descendants(matching: .any)["share.card"].exists)
            capture("production-sheet-\(format)")
        }
        app.terminate()
    }

    func testExternalPlaceCopyLinkDoesNotRequireCardPublication() {
        let app = launch("place", additional: ["-ShareCardExternalPlace"])
        app.buttons["share-mock.try"].tap()
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        copy.tap()
        XCTAssertTrue(app.staticTexts["link copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("external-place-copied")
        app.terminate()
    }

    func testExternalPlaceCanOpenNativeDestinationsFromEveryFormat() {
        let app = launch("place", additional: ["-ShareCardExternalPlace"])
        app.buttons["share-mock.try"].tap()
        let formats = app.segmentedControls["share.format"]
        XCTAssertTrue(formats.waitForExistence(timeout: 10))
        let copy = app.buttons["Copy Link"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        for (format, destination) in [("Link", "Messages"), ("Story", "Instagram Story"), ("Post", "Open more sharing options")] {
            formats.buttons[format].tap()
            app.buttons[destination].tap()
            // Messages and Instagram are unavailable on the simulator, so both
            // use the same native fallback as More. Never send to a recipient.
            let activityList = app.otherElements["ActivityListView"]
            XCTAssertTrue(activityList.waitForExistence(timeout: 10))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            capture("external-place-\(format)-destination")
            app.buttons["Close"].tap()
            XCTAssertTrue(formats.waitForExistence(timeout: 5))
        }
        app.terminate()
    }

    func testPublicationFailureShowsConnectionRecoveryAndRetrySucceeds() {
        let app = launch("place", additional: ["-ShareCardPublicationFailure"])
        app.buttons["share-mock.try"].tap()
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        copy.tap()
        let alert = app.alerts["Couldn't create the share link"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Check your internet connection, then try sharing again."].exists)
        capture("publication-connection-error")
        alert.buttons["OK"].tap()
        copy.tap()
        XCTAssertTrue(app.staticTexts["link copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("publication-retry-succeeded")
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
