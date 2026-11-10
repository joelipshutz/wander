import XCTest

@MainActor
final class QuickCaptureReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderQuickCaptureReview", route, "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["save.submit"].waitForExistence(timeout: 30))
        return app
    }

    func testQuickSaveAndUntouchedExpandedSaveStayUnrated() {
        for route in ["quick", "details"] {
            let app = launch(route)
            app.buttons["save.submit"].tap()
            let invitation = app.otherElements["quick-review.invitation"]
            XCTAssertTrue(invitation.waitForExistence(timeout: 10))
            XCTAssertEqual(invitation.value as? String, "unrated")
            app.terminate()
        }
    }

    func testDeliberateMidpointCountsAndRemoveRestoresUnrated() {
        let app = launch("details")
        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertEqual(slider.value as? String, "Not rated")
        // The existing track is centered beneath its header; a tap at its midpoint
        // explicitly selects 3 even though the neutral thumb starts there.
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        let remove = app.buttons["quick-review.removeRating"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        XCTAssertTrue((slider.value as? String)?.contains("3") == true)
        app.buttons["save.submit"].tap()
        let savedInvitation = app.otherElements["quick-review.invitation"]
        XCTAssertTrue(savedInvitation.waitForExistence(timeout: 10))
        XCTAssertEqual(savedInvitation.value as? String, "3.0")
        app.buttons["quick-review.addDetails"].tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 10), "Editing preserves the explicit rating")
        remove.tap()
        XCTAssertEqual(slider.value as? String, "Not rated")
        app.buttons["save.submit"].tap()
        let invitation = app.otherElements["quick-review.invitation"]
        XCTAssertTrue(invitation.waitForExistence(timeout: 10))
        XCTAssertEqual(invitation.value as? String, "unrated")
    }

    func testCompactExpandsIntoExistingEditorAndWannaHasNoRating() {
        let app = launch("quick")
        app.buttons["quick-review.expand"].tap()
        XCTAssertTrue(app.textViews["save.note"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        app.terminate()
        let wanna = launch("wanna")
        XCTAssertFalse(wanna.descendants(matching: .any)["place-rating-slider"].exists)
        wanna.buttons["quick-review.expand"].tap()
        XCTAssertTrue(wanna.buttons["save.lists"].waitForExistence(timeout: 10))
        XCTAssertFalse(wanna.descendants(matching: .any)["place-rating-slider"].exists)
    }
}
