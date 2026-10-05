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
        let app = launch(["-WanderInitialTab", "map"])
        // This exercises the picker after explicit navigation, independent of
        // the initial tab restored by a preceding onboarding fixture.
        let feed = app.tabBars.buttons["Feed"]
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: feed)
        waitForExpectations(timeout: 25)
        feed.tap()
        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 25))
        launcher.tap()
        let field = app.textViews["discover.placesSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        focus(field, in: app)
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
        assertAtomicBackspace(field, remaining: "")
    }

    func testMapSearchPickerInsertsFullName() {
        let app = launch(["-WanderInitialTab", "map"])
        let field = app.textViews["map.searchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        focus(field, in: app)
        field.typeText("@c")
        let person = app.buttons["map.searchField.person.fixture_caitlin"]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "map.searchField")
        capture("map-search-picker")
        person.tap()
        XCTAssertEqual(field.value as? String, "@Caitlin Cortez ")
        XCTAssertFalse(person.exists)
        capture("map-search-selected")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "@Caitlin Cortez")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "")
        field.typeText("@cait123 ")
        expectation(for: NSPredicate(format: "value == %@", "@Caitlin Cortez "), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        assertAtomicBackspace(field, remaining: "")
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
            assertAtomicBackspace(field, remaining: "With @Caitlin Cortez and ")
            capture("\(mode)-note-selected")
            app.terminate()
        }
    }

    private func exercisePicker(_ app: XCUIApplication, field: XCUIElement, identifier: String, prefix: String) {
        focus(field, in: app)
        field.typeText(prefix)
        let composerBottom = identifier == "activity.comment.input" ? commentComposer(app).frame.maxY : nil
        field.typeText("@")
        let caitlin = app.buttons["\(identifier).person.fixture_caitlin"]
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(caitlin.frame.height, 44)
        assertPickerAtKeyboard(app, identifier: identifier)
        if let composerBottom { XCTAssertEqual(commentComposer(app).frame.maxY, composerBottom, accuracy: 1) }
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
        if let composerBottom { XCTAssertEqual(commentComposer(app).frame.maxY, composerBottom, accuracy: 1) }
        capture("\(identifier)-selected")
        field.typeText("and @cam")
        let camilo = app.buttons["\(identifier).person.fixture_camilo"]
        XCTAssertTrue(camilo.waitForExistence(timeout: 5))
        camilo.tap()
        XCTAssertEqual(field.value as? String, prefix + "@Caitlin Cortez and @Camilo Flores ")
        XCTAssertFalse(camilo.exists)
    }

    func testCommentComposerStaysAtKeyboardThroughMultilineMentionsAndDeletion() {
        let app = launch(["-WanderNotificationPostUITest", "-WanderInitialTab", "map"])
        let field = app.textViews["activity.comment.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        focus(field, in: app)
        field.typeText("A longer comment that wraps onto several lines while the keyboard stays open. With ")
        let prefix = field.value as! String
        let bottom = commentComposer(app).frame.maxY
        field.typeText("@c")
        let caitlin = app.buttons["activity.comment.input.person.fixture_caitlin"]
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "activity.comment.input")
        XCTAssertEqual(commentComposer(app).frame.maxY, bottom, accuracy: 1)
        capture("comment-composer-multiline-picker")
        caitlin.tap()
        assertAtomicBackspace(field, remaining: prefix)
        XCTAssertEqual(commentComposer(app).frame.maxY, bottom, accuracy: 1)
        field.typeText("@cait123 ")
        expectation(for: NSPredicate(format: "value == %@", prefix + "@Caitlin Cortez "), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        assertAtomicBackspace(field, remaining: prefix)
        field.typeText("still typing @")
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "activity.comment.input")
        capture("comment-composer-reopened")
    }

    private func assertAtomicBackspace(_ field: XCUIElement, remaining: String) {
        // The inserted trailing space is ordinary text. The next delete removes
        // the entire tagged person, including @, and keeps preceding text.
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        // UIKit can finish the native edit before its accessibility value is
        // refreshed. Observe the result without sending another delete.
        expectation(for: NSPredicate { _, _ in
            field.exists && (field.value as? String ?? "") == remaining
        }, evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(field.value as? String ?? "", remaining)
    }

    private func focus(_ field: XCUIElement, in app: XCUIApplication) {
        field.tap()
        // A cold notification route can finish presenting after its field first
        // appears. Establish keyboard focus before sending simulated keystrokes.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    }

    private func commentComposer(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["activity.comment.composer"].firstMatch
    }

    func testSpaceCompletesTypedNameAndHandleWithoutTappingAResult() {
        let app = launch(["-WanderNotificationPostUITest", "-WanderInitialTab", "map"])
        let field = app.textViews["activity.comment.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        focus(field, in: app)
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
        let bottomSurface: XCUIElement
        if identifier == "activity.comment.input" {
            let composer = commentComposer(app)
            XCTAssertTrue(composer.exists)
            // Accessibility exposes the inner scroll view, excluding the
            // suggestion panel's existing six-point vertical padding.
            XCTAssertEqual(panel.frame.maxY + 6, composer.frame.minY, accuracy: 1,
                "Comment suggestions must sit above the whole composer.")
            XCTAssertLessThanOrEqual(composer.frame.maxY, keyboard.frame.minY + 1)
            bottomSurface = composer
        } else {
            bottomSurface = panel
        }
        XCTAssertLessThanOrEqual(keyboard.frame.minY - bottomSurface.frame.maxY, 60,
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
        attachment.name = "REC-632-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
