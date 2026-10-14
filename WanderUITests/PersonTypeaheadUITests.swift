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

    func testCommentDraftAndSelectedMentionSurviveBackgroundEntry() {
        let app = launch(["-WanderNotificationPostUITest", "-WanderInitialTab", "map",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"])
        let field = app.textViews["activity.comment.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 25))
        focus(field, in: app)
        field.typeText("With @c")
        let person = app.buttons["activity.comment.input.person.fixture_caitlin"]
        XCTAssertTrue(person.waitForExistence(timeout: 5))
        person.tap()
        XCTAssertEqual(field.value as? String, "With @Caitlin Cortez ")

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The draft must preserve the comments destination")
        XCTAssertEqual(field.value as? String, "With @Caitlin Cortez ")
        focus(field, in: app)
        // A recreated UITextView starts its caret at zero, and XCUI's default
        // activation point can tap the beginning. Establish the deletion point
        // explicitly, then verify the retained mention still deletes atomically.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText("x")
        // UIKit and the accessibility snapshot can settle on different turns
        // after foregrounding. Require the exact edit before testing deletion.
        expectation(for: NSPredicate(format: "value == %@", "With @Caitlin Cortez x"), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(field.value as? String, "With @Caitlin Cortez x")
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        waitForFieldValue("With @Caitlin Cortez ", in: field)
        XCTAssertEqual(field.value as? String, "With @Caitlin Cortez ",
                       "Deleting the caret probe must preserve the selected mention and its separator")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        assertAtomicBackspace(field, removing: "@Caitlin Cortez", remaining: "With ")
    }

    func testFeedSearchPickerInsertsFullNameAndKeepsKeyboard() {
        let app = launch(["-WanderInitialTab", "discover"])
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
        assertAtomicBackspace(field, removing: "@Caitlin Cortez", remaining: "")
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
        assertAtomicBackspace(field, removing: "@Caitlin Cortez", remaining: "")
    }

    func testCheckInAndWannaNotesUseTheSamePicker() {
        for mode in ["checkIn", "wanna"] {
            let app = launch(["-WanderMapPlace", "Griffith Observatory Trail", "-WanderPlaceProfileSaveTrayV1"], demo: true)
            // This test covers picker semantics. Open the normal visible card
            // instead of depending on the separate expanded-startup fixture.
            let card = app.buttons["map.selectedPlaceCard"]
            let cardReady = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"), object: card
            )], timeout: 25) == .completed
            XCTAssertTrue(cardReady, "The selected place card must be ready for a real tap.")
            guard cardReady else { return }
            card.tap()

            let action = app.buttons["place-profile.floating-action.\(mode)"]
            let actionReady = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND hittable == true"), object: action
            )], timeout: 10) == .completed
            XCTAssertTrue(actionReady, "The expanded place action must be visible and hittable.")
            guard actionReady else { return }
            action.tap()
            let field = app.textViews["save.note"]
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            for _ in 0..<4 where !field.isHittable { app.swipeUp() }
            exercisePicker(app, field: field, identifier: "save.note", prefix: "With ")
            assertAtomicBackspace(field, removing: "@Camilo Flores", remaining: "With @Caitlin Cortez and ")
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
        assertAtomicBackspace(field, removing: "@Caitlin Cortez", remaining: prefix)
        XCTAssertEqual(commentComposer(app).frame.maxY, bottom, accuracy: 1)
        field.typeText("@cait123 ")
        expectation(for: NSPredicate(format: "value == %@", prefix + "@Caitlin Cortez "), evaluatedWith: field)
        waitForExpectations(timeout: 5)
        assertAtomicBackspace(field, removing: "@Caitlin Cortez", remaining: prefix)
        field.typeText("still typing @")
        XCTAssertTrue(caitlin.waitForExistence(timeout: 5))
        assertPickerAtKeyboard(app, identifier: "activity.comment.input")
        capture("comment-composer-reopened")
    }

    private func assertAtomicBackspace(
        _ field: XCUIElement,
        removing mention: String,
        remaining: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        waitForFieldValue(remaining + mention + " ", in: field, file: file, line: line)
        XCTAssertEqual(field.value as? String, remaining + mention + " ", file: file, line: line)
        // Observe the ordinary separator deletion separately so the atomic
        // assertion starts with the caret immediately after the tagged name.
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        waitForFieldValue(remaining + mention, in: field, file: file, line: line)
        XCTAssertEqual(field.value as? String, remaining + mention,
                       "The first backspace must remove only the trailing separator", file: file, line: line)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        waitForFieldValue(remaining, in: field, file: file, line: line)
        XCTAssertEqual(field.value as? String, remaining,
                       "One backspace must remove the entire tagged person, including @", file: file, line: line)
    }

    private func waitForFieldValue(
        _ value: String,
        in field: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // Require the exact native edit before checking atomic deletion; an
        // intermediate accessibility snapshot cannot satisfy this predicate.
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed,
                       "The exact native edit must reach accessibility.", file: file, line: line)
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
        // XCUI's Keyboard frame contains the keys, excluding Apple's native
        // prediction bar. That bar is 78 points on iOS 26.3, and can sit below
        // the display while a hardware keyboard is connected. Measure app
        // spacing from its upper edge rather than counting it as blank space.
        let assistant = app.otherElements["SystemInputAssistantView"].firstMatch
        let assistantFrame = assistant.exists ? assistant.frame : .zero
        let keyboardTop = assistant.exists && assistantFrame.height > 0
            && assistantFrame.minY <= keyboard.frame.minY
            && assistantFrame.maxY <= keyboard.frame.minY + 1
            ? assistantFrame.minY : keyboard.frame.minY
        XCTAssertLessThanOrEqual(bottomSurface.frame.maxY, keyboardTop + 1,
            "Suggestions and the composer must not overlap the native input bar.")
        XCTAssertLessThanOrEqual(keyboardTop - bottomSurface.frame.maxY, 12,
            "Only the suggestion panel's padding may separate it from the native input bar.")
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
