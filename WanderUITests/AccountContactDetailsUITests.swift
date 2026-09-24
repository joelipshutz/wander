import XCTest

@MainActor final class AccountContactDetailsUITests: XCTestCase {
    func testNormalAppLaunchReachesLiveAuthentication() {
        let app = XCUIApplication()
        // Clear the persisted simulator fixture selection, then exercise a
        // normal cold launch with the real Clerk and backend configuration.
        app.launchArguments = ["-WanderUseLiveAuth"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.logIn"].waitForExistence(timeout: 20))
        app.terminate()
        app.launchArguments = []
        app.launch()
        let logIn = app.buttons["onboarding.logIn"]
        XCTAssertTrue(logIn.waitForExistence(timeout: 20))
        logIn.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["auth.usePassword"].exists)
        capture(app, name: "Full app — Live authentication entry")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderOnboardingUITestStep", "location", "-WanderAccountContactDetailsUITest", "-WanderHomeCitySearchFixtures"]
        app.launch()
        XCTAssertTrue(app.textFields["accountContactDetails.city"].waitForExistence(timeout: 10))
        let prefilled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", "Los Angeles"), object: app.textFields["accountContactDetails.city"])
        XCTAssertEqual(XCTWaiter.wait(for: [prefilled], timeout: 5), .completed)
        return app
    }

    func testPrefilledMetroAndUSCountryThenContinueToContacts() {
        let app = launch()
        XCTAssertTrue(app.textFields["accountContactDetails.city"].value as? String == "Los Angeles")
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+1"))
        capture(app, name: "Typeahead 01 — Prefilled city and phone")
        let phone = app.textFields["accountContactDetails.phone"]
        phone.tap()
        phone.typeText("2025550123")
        let privacyNote = app.staticTexts["Your phone number is private."]
        let phoneSectionIsVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: privacyNote)
        XCTAssertEqual(XCTWaiter.wait(for: [phoneSectionIsVisible], timeout: 5), .completed)
        capture(app, name: "02 — Phone keyboard")
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertTrue(app.buttons["accountContactDetails.continue"].isHittable)
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
        app.buttons["accountContactDetails.country"].tap()
        capture(app, name: "03 — Country code picker")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("United Kingdom")
        app.buttons["accountContactDetails.option.GB"].tap()
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+44"))
    }

    func testWorldwideInlineTypeaheadShowsClearMatchesAndSelectedCity() {
        let app = launch()
        let city = app.textFields["accountContactDetails.city"]
        app.buttons["accountContactDetails.clearCity"].tap()
        XCTAssertEqual(city.value as? String, "Search any city")
        XCTAssertFalse(app.buttons["accountContactDetails.continue"].isEnabled)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["accountContactDetails.skip"].exists)
        capture(app, name: "Typeahead 02 — Cleared city")
        city.typeText("Par")
        XCTAssertTrue(app.staticTexts["Finding cities…"].waitForExistence(timeout: 2))
        capture(app, name: "Typeahead 03 — Typing")
        let paris = app.buttons["accountContactDetails.cityResult.Paris.FR"]
        XCTAssertTrue(paris.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["accountContactDetails.cityResult.Paris.US"].exists)
        capture(app, name: "Typeahead 04 — Worldwide city matches")
        paris.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Paris"), object: city)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+33"))
        let phone = app.textFields["accountContactDetails.phone"]
        phone.tap()
        phone.typeText("01 42 68 53 00")
        XCTAssertTrue(app.buttons["accountContactDetails.continue"].isEnabled)
        capture(app, name: "Typeahead 05 — Paris selected")
    }

    func testUnlistedGlobalCityAndEmptyAndOfflineStates() {
        let app = launch()
        let city = app.textFields["accountContactDetails.city"]
        app.buttons["accountContactDetails.clearCity"].tap()
        city.typeText("Kyoto")
        let kyoto = app.buttons["accountContactDetails.cityResult.Kyoto.JP"]
        XCTAssertTrue(kyoto.waitForExistence(timeout: 5))
        kyoto.tap()
        XCTAssertTrue(app.buttons["accountContactDetails.country"].label.contains("+81"))
        capture(app, name: "Typeahead 06 — Kyoto selected")
        app.buttons["accountContactDetails.clearCity"].tap()
        city.typeText("zzzzcity")
        XCTAssertTrue(app.staticTexts["No matching cities. Try another spelling."].waitForExistence(timeout: 5))
        capture(app, name: "Typeahead 07 — No matches")
        app.buttons["accountContactDetails.clearCity"].tap()
        city.typeText("offline")
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["accountContactDetails.continue"].isEnabled)
        capture(app, name: "Typeahead 08 — Connection unavailable")
    }

    func testContinueIsTheOnlyActionAndBlankPhoneCannotAdvance() {
        let app = launch()
        XCTAssertFalse(app.buttons["accountContactDetails.skip"].exists)
        XCTAssertFalse(app.buttons["Not now"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
        let primary = app.buttons["accountContactDetails.continue"]
        XCTAssertFalse(primary.isEnabled)
        XCTAssertTrue(app.staticTexts["Enter your phone number to continue."].exists)
        XCTAssertFalse(app.staticTexts["Connect with your people"].exists)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
