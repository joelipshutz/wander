import XCTest

@MainActor
final class QuickCaptureReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(_ route: String, waitsForEditor: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderQuickCaptureReview", route, "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest"]
        app.launch()
        if waitsForEditor {
            XCTAssertTrue(app.buttons["save.submit"].waitForExistence(timeout: 30))
        }
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

    func testQuickDateCarriesIntoExpandedEditorWithoutDuplicateWhen() throws {
        let app = launch("quick")
        let date = app.descendants(matching: .any).matching(identifier: "quick-review.date").firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 10))
        date.tap()

        // Select yesterday through the native calendar, then expand the same draft.
        // Past dates respect the existing check-in calendar's future-date limit.
        let yesterday = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        if !Calendar.current.isDate(yesterday, equalTo: .now, toGranularity: .month) {
            app.buttons["DatePicker.PreviousMonth"].tap()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        let labels = ["d", "EEEE, MMMM d", "EEEE, MMMM d, yyyy", "MMMM d, yyyy"].map { format in
            formatter.dateFormat = format
            return formatter.string(from: yesterday)
        }
        let day = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), app.debugDescription)
        day.tap()
        app.buttons["PopoverDismissRegion"].tap()
        app.buttons["quick-review.expand"].tap()

        let expandedDate = app.buttons["save.checkInDateDisclosure"]
        XCTAssertTrue(expandedDate.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["quick-review.date"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "save.checkInDateDisclosure").count, 1)
        let expected = yesterday.formatted(date: .long, time: .omitted)
        XCTAssertTrue((expandedDate.value as? String)?.contains(expected) == true,
                      "Expanded date should preserve \(expected): \(String(describing: expandedDate.value))")
    }

    func testVisitPencilAndAddDetailsOpenTheSameUnratedVisit() {
        var expectedDate: String?
        for identifier in ["place-activity.edit.quick-review-recent", "quick-review.visitDetails.quick-review-recent"] {
            let app = launch("placeHistory", waitsForEditor: false)
            let action = app.buttons[identifier]
            XCTAssertTrue(action.waitForExistence(timeout: 30))
            action.tap()
            XCTAssertTrue(app.buttons["save.submit"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.buttons["save.submit"].label, "Update check-in")
            XCTAssertEqual(app.descendants(matching: .any)["place-rating-slider"].value as? String, "Not rated")
            let actualDate = app.buttons["save.checkInDateDisclosure"].value as? String
            XCTAssertNotNil(actualDate)
            if let expectedDate { XCTAssertEqual(actualDate, expectedDate) }
            else { expectedDate = actualDate }
            XCTAssertFalse((app.textViews["save.note"].value as? String)?.contains("A good spot for a slow morning") == true)
            app.terminate()
        }
    }
}
