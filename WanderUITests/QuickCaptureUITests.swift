import XCTest

final class QuickCaptureUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testQuickSaveLeavesTheActualStoredVisitUnratedAndOffersDetails() {
        let app = launch("quick")
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        app.buttons["save.submit"].tap()
        XCTAssertTrue(app.buttons["check-in.invitation.edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["quick-capture-test.state"].label.contains("unrated:pending=true"))
        app.buttons["check-in.invitation.edit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.descendants(matching: .any)["place-rating-slider"].value as? String, "Not rated")
    }

    func testExplicitMidpointCountsButOpeningDetailsAloneDoesNotRate() {
        let app = launch("details")
        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        XCTAssertEqual(slider.value as? String, "Not rated")
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).tap()
        XCTAssertTrue(app.buttons["save.removeRating"].waitForExistence(timeout: 5))
        app.buttons["save.submit"].tap()
        let state = app.staticTexts["quick-capture-test.state"]
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        XCTAssertTrue(state.label.contains(":3.0:pending=false"), state.label)
        XCTAssertFalse(app.buttons["check-in.invitation.edit"].exists)
    }

    func testExpandedUntouchedSaveRemainsUnrated() {
        let app = launch("details")
        app.buttons["save.submit"].tap()
        XCTAssertTrue(app.buttons["check-in.invitation.edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["quick-capture-test.state"].label.contains("unrated:pending=true"))
    }

    func testWannaExpandsWithoutRatingOrCheckInDate() {
        let app = launch("wanna")
        XCTAssertFalse(app.descendants(matching: .any)["save.quickDate"].exists)
        app.buttons["save.addDetails"].tap()
        XCTAssertTrue(app.buttons["save.lists"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
    }

    func testQuickDateCarriesIntoExpandedEditorWithoutDuplicateWhen() throws {
        let app = launch("quick")
        let date = app.descendants(matching: .any).matching(identifier: "save.quickDate").firstMatch
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
        app.buttons["save.addDetails"].tap()

        let expandedDate = app.buttons["save.checkInDateDisclosure"]
        XCTAssertTrue(expandedDate.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["save.quickDate"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "save.checkInDateDisclosure").count, 1)
        let expected = yesterday.formatted(date: .long, time: .omitted)
        XCTAssertTrue((expandedDate.value as? String)?.contains(expected) == true,
                      "Expanded date should preserve \(expected): \(String(describing: expandedDate.value))")
    }

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderQuickCaptureUITest", route, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["save.submit"].waitForExistence(timeout: 20))
        return app
    }
}
