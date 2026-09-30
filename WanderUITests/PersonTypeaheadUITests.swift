import XCTest

@MainActor
final class PersonTypeaheadUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCommentPickerFiltersDeduplicatesSelectsAndReopens() {
        let app = launch(["-WanderNotificationPostUITest", "-WanderInitialTab", "map"])
        let field = app.textViews["activity.comment.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        exercisePicker(app, field: field, identifier: "activity.comment.input", prefix: "With ")
        field.typeText("\n")
        XCTAssertTrue(app.staticTexts["With @Caitlin Cortez and @Camilo Flores"].waitForExistence(timeout: 5))
        capture("comments-saved")
    }

    func testFeedSearchPickerInsertsFullNameAndKeepsKeyboard() {
        let app = launch(["-WanderInitialTab", "discover"])
        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 25))
        launcher.tap()
        let field = app.textViews["discover.placesSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("@c")
        let person = app.buttons["discover.placesSearchField.person.fixture_caitlin"]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "discover.placesSearchField")
        capture("feed-search-picker")
        person.tap()
        XCTAssertEqual(field.value as? String, "@Caitlin Cortez ")
        XCTAssertFalse(person.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("feed-search-selected")
    }

    func testMapSearchPickerInsertsFullName() {
        let app = launch(["-WanderInitialTab", "map"])
        let field = app.textViews["map.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("@c")
        let person = app.buttons["map.searchField.person.fixture_caitlin"]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "map.searchField")
        capture("map-search-picker")
        person.tap()
        XCTAssertEqual(field.value as? String, "@Caitlin Cortez ")
        XCTAssertFalse(person.exists)
        capture("map-search-selected")
    }

    func testCheckInAndWannaNotesUseTheSamePicker() {
        for mode in ["checkIn", "wanna"] {
            let app = launch(["-WanderMapPlace", "Griffith Observatory Trail", "-WanderMapSheetExpanded", "-WanderPlaceProfileSaveTrayV1"], demo: true)
            let action = app.buttons["place-profile.floating-action.\(mode)"]
            XCTAssertTrue(action.waitForExistence(timeout: 25))
            action.tap()
            let field = app.textViews["save.note"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            for _ in 0..<4 where !field.isHittable { app.swipeUp() }
            exercisePicker(app, field: field, identifier: "save.note", prefix: "With ")
            capture("\(mode)-note-selected")
            app.terminate()
        }
    }

    private func exercisePicker(_ app: XCUIApplication, field: XCUIElement, identifier: String, prefix: String) {
        field.tap()
        field.typeText(prefix + "@")
        let caitlin = app.buttons["\(identifier).person.fixture_caitlin"]
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(caitlin.frame.height, 44)
        assertPickerAtKeyboard(app, identifier: identifier)
        capture("\(identifier)-ranked")
        if identifier == "save.note" {
            let submit = app.buttons["save.submit"]
            XCTAssertLessThanOrEqual(field.frame.maxY, submit.frame.minY,
                "The note input must remain above the save button while suggestions are open.")
        }
        let bottom = app.buttons["\(identifier).person.fixture_long"]
        let panel = app.descendants(matching: .any)["\(identifier).suggestions"].firstMatch
        panel.swipeUp()
        XCTAssertTrue(bottom.waitForExistence(timeout: 3))
        capture("\(identifier)-scrolled")
        field.typeText("c")
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "\(identifier).person.fixture_caitlin").count, 1)
        XCTAssertFalse(app.buttons["\(identifier).person.fixture_abdou"].exists)
        capture("\(identifier)-filtered")
        caitlin.tap()
        XCTAssertEqual(field.value as? String, prefix + "@Caitlin Cortez ")
        XCTAssertFalse(caitlin.exists)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("\(identifier)-selected")
        field.typeText("and @cam")
        let camilo = app.buttons["\(identifier).person.fixture_camilo"]
        XCTAssertTrue(camilo.waitForExistence(timeout: 5))
        camilo.tap()
        XCTAssertEqual(field.value as? String, prefix + "@Caitlin Cortez and @Camilo Flores ")
        XCTAssertFalse(camilo.exists)
    }

    func testSpaceCompletesTypedNameAndHandleWithoutTappingAResult() {
        let app = launch(["-WanderNotificationPostUITest", "-WanderInitialTab", "map"])
        let field = app.textViews["activity.comment.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        field.tap()
        field.typeText("@Caitlin Cortez ")
        let caitlin = app.buttons["activity.comment.input.person.fixture_caitlin"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: caitlin)
        waitForExpectations(timeout: 5)
        field.typeText("and @camilo tomorrow")
        expectation(for: NSPredicate(format: "value == %@", "@Caitlin Cortez and @Camilo Flores tomorrow"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        capture("space-completed-names")
        field.typeText(" @")
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        field.typeText("nobody! still typing")
        expectation(for: NSPredicate(format: "value == %@", "@Caitlin Cortez and @Camilo Flores tomorrow @nobody! still typing"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
    }

    private func assertPickerAtKeyboard(_ app: XCUIApplication, identifier: String) {
        let panel = app.descendants(matching: .any)["\(identifier).suggestions"].firstMatch
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(keyboard.exists)
        XCTAssertGreaterThan(panel.frame.height, 44)
        XCTAssertLessThanOrEqual(panel.frame.maxY, keyboard.frame.minY + 1)
        XCTAssertLessThanOrEqual(keyboard.frame.minY - panel.frame.maxY, 60,
            "Suggestions must sit at the keyboard, allowing for the native predictions bar.")
    }

    private func launch(_ arguments: [String], demo: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", demo ? "-WanderUseDemoFixtures" : "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderPersonTypeaheadUITest"] + arguments
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-631-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
