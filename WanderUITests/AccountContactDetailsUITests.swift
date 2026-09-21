import XCTest

@MainActor final class AccountContactDetailsUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestStep", "location", "-WanderAccountContactDetailsUITest"]
        app.launch()
        XCTAssertTrue(app.buttons["accountContactDetails.metro"].waitForExistence(timeout: 10))
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Los Angeles"), object: app.buttons["accountContactDetails.metro"])
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 5), .completed)
        return app
    }

    func testPrefilledMetroAndUSCountryThenContinueToContacts() {
        let app = launch()
        XCTAssertTrue(app.buttons["accountContactDetails.metro"].label.contains("Los Angeles"))
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+1"))
        let phone = app.textFields["accountContactDetails.phone"]
        phone.tap()
        phone.typeText("2025550123")
        app.buttons["Done"].tap()
        app.buttons["accountContactDetails.continue"].tap()
        XCTAssertTrue(app.staticTexts["Connect with your people"].waitForExistence(timeout: 5))
    }

    func testInvalidPhoneCannotAdvanceAndCountryPickerIsEditable() {
        let app = launch()
        let phone = app.textFields["accountContactDetails.phone"]
        phone.tap()
        phone.typeText("202555012")
        XCTAssertTrue(app.staticTexts["accountContactDetails.phoneError"].exists)
        XCTAssertFalse(app.buttons["accountContactDetails.continue"].isEnabled)
        app.buttons["Done"].tap()
        app.buttons["accountContactDetails.country"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("United Kingdom")
        app.buttons["accountContactDetails.option.GB"].tap()
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+44"))
    }

    func testMetroOptionsUseMajorAreasAndCanBeChanged() {
        let app = launch()
        app.buttons["accountContactDetails.metro"].tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("Orange County")
        app.buttons["accountContactDetails.option.orange-county"].tap()
        XCTAssertTrue(app.buttons["accountContactDetails.metro"].label.contains("Orange County"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "City and phone form"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOptionalSkipPreservesNextOnboardingStep() {
        let app = launch()
        app.buttons["accountContactDetails.skip"].tap()
        XCTAssertTrue(app.staticTexts["Connect with your people"].waitForExistence(timeout: 5))
    }
}
