import XCTest

@MainActor
final class YourMapPrototypeUITests: XCTestCase {
    func testGeographyExpandsAndCollapsesInPlaceWithoutUnknowns() {
        let app = launchGeography()
        let toggle = app.buttons["yourMap.prototype.geography.expand"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let cityRows = geographyRows(in: app, kind: "city")
        let countryRows = geographyRows(in: app, kind: "country")
        XCTAssertEqual(cityRows.count, 5)
        XCTAssertEqual(countryRows.count, 5)
        XCTAssertEqual(toggle.value as? String, "Collapsed")
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.cityRow.Unknown city"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.countryRow.Unknown country"].exists)
        let card = app.otherElements["yourMap.prototype.citiesCountries"]
        let month = app.otherElements["yourMap.prototype.monthHeatMap"]
        let collapsedHeight = card.frame.height
        let collapsedGap = month.frame.minY - card.frame.maxY
        capture("REC-417 geography collapsed")

        toggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["yourMap.prototype.cityRow.Amsterdam"].waitForExistence(timeout: 3))
        XCTAssertEqual(cityRows.count, 10)
        XCTAssertEqual(countryRows.count, 10)
        XCTAssertEqual(toggle.value as? String, "Expanded")
        XCTAssertGreaterThan(card.frame.height, collapsedHeight + 100)
        XCTAssertEqual(month.frame.minY - card.frame.maxY, collapsedGap, accuracy: 2)
        XCTAssertFalse(app.descendants(matching: .any)["yourMap.prototype.cityRow.Berlin"].exists)
        capture("REC-417 geography expanded")

        if !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        let collapsed = NSPredicate(format: "value == %@", "Collapsed")
        expectation(for: collapsed, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(cityRows.count, 5)
        XCTAssertEqual(countryRows.count, 5)
        XCTAssertEqual(card.frame.height, collapsedHeight, accuracy: 2)
        XCTAssertEqual(month.frame.minY - card.frame.maxY, collapsedGap, accuracy: 2)
        capture("REC-417 geography collapsed again")
    }

    func testGeographyOnlyUnknownLocationsShowsEmptyColumnsWithoutToggle() {
        let app = launchGeography(page: "patternsGeographyEmpty")
        XCTAssertTrue(app.staticTexts["No cities yet"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No countries yet"].exists)
        XCTAssertFalse(app.buttons["yourMap.prototype.geography.expand"].exists)
        XCTAssertEqual(geographyRows(in: app, kind: "city").count, 0)
        XCTAssertEqual(geographyRows(in: app, kind: "country").count, 0)
    }

    private func launchGeography(page: String = "patternsGeography") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderProfileRedesignMockup", page]
        app.launch()
        return app
    }

    private func geographyRows(in app: XCUIApplication, kind: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.\(kind)Row.")
        )
    }

    func testPinSelectionAndSavedLensDeletion() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab", "profile",
        ]
        app.launch()

        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()

        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let pin = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin.")
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 6))
        pin.tap()

        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 6))
        capture("REC-338 selected personal map pin")

        app.buttons["yourMap.prototype.filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        app.buttons["This year"].tap()
        app.buttons["yourMap.prototype.saveLens"].tap()

        let savedLens = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
        ).firstMatch
        XCTAssertTrue(savedLens.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(savedLens.frame.width, app.frame.width * 0.9)

        savedLens.swipeLeft()
        XCTAssertLessThan(savedLens.frame.maxX, app.frame.maxX - 40)
        let deleteButton = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.deleteLens.")
        ).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3))
        XCTAssertTrue(deleteButton.isHittable)
        capture("REC-338 saved lens delete reveal")

        deleteButton.tap()
        XCTAssertTrue(app.staticTexts["No saved lenses yet"].waitForExistence(timeout: 2))
        XCTAssertEqual(
            app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.savedLens.")
            ).count,
            0
        )
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
