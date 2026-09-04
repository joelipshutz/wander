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

    func testSnapshotCreatesListAndOpensEditablePlaces() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderResetWalkthroughs", "-WanderInitialTab", "profile"]
        app.launch()
        let preview = app.buttons["profile.yourMap.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        // The combined preview can exist below the tab bar. Bring its actual
        // tap target into view before opening Explore on every phone size.
        for _ in 0..<5 where preview.frame.maxY > app.frame.maxY - 100 || !preview.isHittable {
            app.swipeUp()
        }
        preview.tap()
        let snapshot = app.buttons["yourMap.snapshot"]
        XCTAssertTrue(snapshot.waitForExistence(timeout: 10))
        let pin = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "yourMap.prototype.pin.")).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 10))
        capture("REC-413 Explore snapshot control")
        snapshot.tap()
        let toast = app.buttons["yourMap.viewSnapshotList"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10))
        XCTAssertEqual(toast.label, "Edit")
        XCTAssertTrue(app.staticTexts["View snapshot list"].exists)
        capture("REC-413 Snapshot saved toast")
        toast.tap()
        XCTAssertTrue(app.staticTexts["edit list"].waitForExistence(timeout: 5))
        let title = app.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        let existing = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + "Snapshot test\n")
        let cover = app.images["Saved map snapshot"]
        for _ in 0..<6 {
            if cover.exists && cover.frame.minY > 100 && cover.frame.maxY < app.frame.maxY - 180 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)).press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            )
        }
        XCTAssertTrue(cover.isHittable)
        capture("REC-413 Static snapshot cover")
        let addPlaces = app.buttons["listEditor.addPlaces"]
        for _ in 0..<3 where !addPlaces.isHittable || addPlaces.frame.maxY > app.frame.maxY - 140 {
            app.swipeUp()
        }
        XCTAssertTrue(addPlaces.isHittable)
        capture("REC-413 Snapshot list editor")
        addPlaces.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
