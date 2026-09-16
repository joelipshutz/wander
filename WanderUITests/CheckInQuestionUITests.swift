import XCTest
import UIKit

@MainActor
final class CheckInQuestionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshCheckInStartsBlankAndTappingSelectedAnswerClearsIt() {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)

        let options = catalogAnswerButtons(in: app)
        reveal(options.firstMatch, in: app)
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(options.count, 0)
        XCTAssertTrue(options.allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        let first = options.firstMatch
        reveal(first, in: app)
        first.tap()
        XCTAssertTrue(first.isSelected)
        first.tap()
        XCTAssertFalse(first.isSelected)
        capture("REC-485 blank optional questions and clearable answer")
    }

    func testWannaKeepsIntroductionNoteAndHidesCheckInQuestions() {
        let app = launchPlace()
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 10))
        wanna.tap()

        XCTAssertTrue(app.textFields["save.note"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["What made you save this?"].exists)
        XCTAssertFalse(app.buttons["save.questions.customize"].exists)
        XCTAssertEqual(catalogAnswerButtons(in: app).count, 0)
        capture("REC-485 Wanna introduction note")
    }

    func testCustomizeReordersRemovesAddsAndPersistsWhenReopened() throws {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        openCustomize(in: app)
        let initialIDs = recurringIDs(in: app)
        XCTAssertEqual(initialIDs.count, 3)
        let firstID = try XCTUnwrap(initialIDs.first)
        let lastID = try XCTUnwrap(initialIDs.last)
        let firstCell = recurringCell(firstID, in: app)
        let lastCell = recurringCell(lastID, in: app)
        XCTAssertTrue(firstCell.exists)
        XCTAssertTrue(lastCell.exists)

        // Drag the native reorder handle, then verify the rendered order.
        lastCell.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: firstCell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        XCTAssertLessThan(recurringElement(lastID, in: app).frame.minY, recurringElement(firstID, in: app).frame.minY)

        // The native edit control shares its row's accessibility identifier;
        // target the leading minus, not the row's privacy-navigation button.
        recurringCell(lastID, in: app).coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let confirmDelete = app.buttons["Delete"].firstMatch
        if confirmDelete.waitForExistence(timeout: 2) { confirmDelete.tap() }
        XCTAssertTrue(app.buttons["save.questions.done"].exists)
        XCTAssertTrue(recurringElement(lastID, in: app).waitForNonExistence(timeout: 3))
        XCTAssertEqual(recurringIDs(in: app).count, 2)

        let addCatalog = app.buttons["save.questions.addCatalog"]
        reveal(addCatalog, in: app)
        XCTAssertTrue(addCatalog.isEnabled, "Adding a question stays available while native reorder controls are shown.")
        addCatalog.tap()
        let catalogStealth = app.descendants(matching: .any)["save.questions.catalogStealth"].firstMatch
        XCTAssertTrue(catalogStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(catalogStealth.value as? String, "Off")
        capture("REC-485 question library Stealth control")
        catalogStealth.tap()
        let stealthEnabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "On"), object: catalogStealth)
        XCTAssertEqual(XCTWaiter.wait(for: [stealthEnabled], timeout: 3), .completed, catalogStealth.debugDescription)
        XCTAssertEqual(catalogStealth.value as? String, "On")
        let search = app.textFields["save.questions.catalogSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("outlet\n")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(recurringElement("place_detail_outlets", in: app).value as? String, "Stealth")

        let createCustom = app.buttons["save.questions.createCustom"]
        reveal(createCustom, in: app)
        XCTAssertTrue(createCustom.isEnabled, "Creating a question stays available while native reorder controls are shown.")
        createCustom.tap()
        let customStealth = app.descendants(matching: .any)["save.questions.customStealth"].firstMatch
        XCTAssertTrue(customStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(customStealth.value as? String, "On")
        reveal(customStealth, in: app)
        customStealth.tap()
        XCTAssertEqual(customStealth.value as? String, "Off")
        let prompt = app.descendants(matching: .any)["save.questions.customPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        reveal(prompt, in: app, upwards: false)
        prompt.tap()
        prompt.typeText("Lots of plants indoors?")
        app.buttons["save.questions.customAdd"].tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 3))
        let customID = try XCTUnwrap(recurringIDs(in: app).first { $0.hasPrefix("custom_question_") })
        XCTAssertEqual(recurringElement(customID, in: app).value as? String, "Check-in audience")
        let expectedIDs = recurringIDs(in: app)
        capture("REC-485 customized recurring questions")
        app.buttons["save.questions.done"].tap()

        let customYes = app.buttons["save.question.\(customID).Yes"]
        reveal(customYes, in: app)
        XCTAssertTrue(customYes.isHittable)
        XCTAssertFalse(customYes.isSelected)
        customYes.tap()
        XCTAssertTrue(customYes.isSelected)
        customYes.tap()
        XCTAssertFalse(customYes.isSelected)

        openCustomize(in: app)
        XCTAssertEqual(recurringIDs(in: app), expectedIDs)
        recurringElement(customID, in: app).tap()
        let selectedStealth = app.descendants(matching: .any)["save.questions.selectedStealth"].firstMatch
        XCTAssertTrue(selectedStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(selectedStealth.value as? String, "Off")
        selectedStealth.tap()
        XCTAssertEqual(selectedStealth.value as? String, "On")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertEqual(recurringElement(customID, in: app).value as? String, "Stealth")
        app.buttons["save.questions.done"].tap()
        restoreSuggestions(in: app)
    }

    func testChangingSubtypeChangesPromptsWithoutInventingAnswers() throws {
        let app = launchPlace()
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        // Pick a Hike detail that is not also one of Beach's defaults.
        let first = app.buttons["save.question.place_detail_incline.Mostly level"]
        reveal(first, in: app)
        let previousID = first.identifier
        first.tap()

        let subtype = app.buttons["save.placeType.subcategory"]
        reveal(subtype, in: app)
        XCTAssertTrue(subtype.isHittable)
        subtype.tap()
        let search = app.textFields["Search types"]
        let pickerOpened = search.waitForExistence(timeout: 3)
        if !pickerOpened { capture("REC-485 subtype picker did not open") }
        XCTAssertTrue(pickerOpened)
        search.tap()
        search.typeText("Beach\n")
        let beach = app.buttons.matching(NSPredicate(format: "label == %@", "Beach")).firstMatch
        XCTAssertTrue(beach.waitForExistence(timeout: 3))
        beach.tap()
        let pickerDone = app.buttons["save.placeType.done"]
        pickerDone.tap()
        XCTAssertTrue(pickerDone.waitForNonExistence(timeout: 3))

        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app)
        XCTAssertTrue(customize.label.contains("Beach"), customize.label)
        restoreSuggestions(in: app)
        XCTAssertTrue(catalogAnswerButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        let alsoNoted = app.descendants(matching: .any)["save.questions.alsoNoted"].firstMatch
        reveal(alsoNoted, in: app)
        XCTAssertTrue(alsoNoted.exists)
        alsoNoted.tap()
        let previousAnswer = app.buttons[previousID]
        reveal(previousAnswer, in: app)
        XCTAssertTrue(previousAnswer.isSelected, "Changing type must keep an earlier answer reviewable in Also noted.")
        previousAnswer.tap()
        XCTAssertTrue(previousAnswer.waitForNonExistence(timeout: 3), "Clearing a nonpreferred answer removes it from Also noted.")
        capture("REC-485 subtype change keeps earlier answers reviewable")
    }

    func testAccessibilityTextKeepsAnswerControlsReadableAndTappable() throws {
        let app = launchPlace(accessibilityText: true)
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        let options = catalogAnswerButtons(in: app)
        let first = options.firstMatch
        reveal(first, in: app)
        XCTAssertTrue(first.isHittable)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertGreaterThanOrEqual(first.frame.width, 44)
        XCTAssertGreaterThanOrEqual(first.frame.minX, 0)
        XCTAssertLessThanOrEqual(first.frame.maxX, app.frame.width)
        first.tap()
        XCTAssertTrue(first.isSelected)
        capture("REC-485 accessibility text editor")
        first.tap()
        openCustomize(in: app)
        capture("REC-485 accessibility text customization")
        let questionID = try XCTUnwrap(recurringIDs(in: app).first)
        recurringElement(questionID, in: app).tap()
        let stealth = app.descendants(matching: .any)["save.questions.selectedStealth"].firstMatch
        XCTAssertTrue(stealth.waitForExistence(timeout: 3))
        reveal(stealth, in: app)
        XCTAssertGreaterThanOrEqual(stealth.frame.height, 44)
        let initialStealth = stealth.value as? String
        stealth.tap()
        XCTAssertNotEqual(stealth.value as? String, initialStealth)
        capture("REC-485 accessibility text Stealth toggle")
        stealth.tap()
        XCTAssertEqual(stealth.value as? String, initialStealth)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["save.questions.done"].tap()
    }

    func testRestaurantFoodTypeChangesQuestionsWithoutADuplicateTypePicker() {
        let app = launchPlace(placeName: "Larchmont Noodles")
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        XCTAssertFalse(app.buttons["save.placeType.subcategory"].exists)

        let foodType = app.buttons["save.placeType.cuisine"]
        reveal(foodType, in: app)
        XCTAssertTrue(foodType.isHittable)
        foodType.tap()
        let foodTypeSearch = app.textFields["Search food types"]
        let pickerOpened = foodTypeSearch.waitForExistence(timeout: 3)
        if !pickerOpened { capture("REC-485 food type picker did not open") }
        XCTAssertTrue(pickerOpened)
        XCTAssertFalse(app.textFields["Search types"].exists)
        foodTypeSearch.tap()
        foodTypeSearch.typeText("Thai\n")
        let thai = app.buttons.matching(NSPredicate(format: "label == %@", "Thai")).firstMatch
        reveal(thai, in: app)
        XCTAssertTrue(thai.isHittable)
        thai.tap()
        let selectedThai = app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", "Thai", "Selected")).firstMatch
        XCTAssertTrue(selectedThai.waitForExistence(timeout: 3))
        let pickerDone = app.buttons["save.placeType.done"]
        pickerDone.tap()
        XCTAssertTrue(pickerDone.waitForNonExistence(timeout: 3))

        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app)
        XCTAssertTrue(customize.label.contains("Thai"), customize.label)
        restoreSuggestions(in: app)
        for id in ["place_detail_dog_access", "place_detail_spice", "place_detail_vegetarian"] {
            XCTAssertTrue(app.descendants(matching: .any)["save.question.row.\(id)"].firstMatch.exists)
        }
        XCTAssertTrue(catalogAnswerButtons(in: app).allElementsBoundByIndex.allSatisfy { !$0.isSelected })
        XCTAssertFalse(app.buttons["save.placeType.subcategory"].exists)
        capture("REC-485 restaurant food type drives useful questions")
    }

    func testSettingsManagesQuestionsWithoutOpeningAPlace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderOpenSettings"
        ]
        app.launch()
        let entry = app.descendants(matching: .any)["settings.checkInQuestions"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        reveal(entry, in: app)
        entry.tap()
        let search = app.textFields["questions.settings.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("Volleyball court\n")
        let scope = app.buttons["questions.settings.scope.wellness_fitness:volleyball court"]
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        reveal(scope, in: app)
        XCTAssertTrue(scope.isHittable)
        scope.tap()
        let openedEditor = app.buttons["save.questions.done"].waitForExistence(timeout: 8)
        if !openedEditor { capture("REC-485 Settings subtype presentation failure") }
        XCTAssertTrue(openedEditor, "Question rows: \(recurringIDs(in: app).count); add control: \(app.buttons["save.questions.addCatalog"].exists)")
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()

        let add = app.buttons["save.questions.addCatalog"]
        reveal(add, in: app, upwards: false)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["save.questions.catalogStealth"].firstMatch.waitForExistence(timeout: 3))
        let questionSearch = app.textFields["save.questions.catalogSearch"]
        questionSearch.tap()
        questionSearch.typeText("outlet\n")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        app.buttons["save.questions.done"].tap()
        XCTAssertTrue(scope.waitForExistence(timeout: 3))
        scope.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        capture("REC-485 Settings question management")
        reveal(restore, in: app)
        restore.tap()
        app.buttons["save.questions.done"].tap()
    }

    private func launchPlace(placeName: String = "Griffith Observatory Trail", accessibilityText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseDemoFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderMapPlace", placeName,
            "-WanderMapSheetExpanded", "-WanderPlaceProfileSaveTrayV1"
        ]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraLarge.rawValue]
        }
        app.launch()
        return app
    }

    private func openCheckIn(in app: XCUIApplication) {
        let action = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        action.tap()
        XCTAssertTrue(app.scrollViews["save.editorScroll"].waitForExistence(timeout: 10))
    }

    private func openCustomize(in app: XCUIApplication) {
        let customize = app.buttons["save.questions.customize"]
        reveal(customize, in: app)
        XCTAssertTrue(customize.isHittable)
        customize.tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 4))
    }

    private func restoreSuggestions(in app: XCUIApplication) {
        openCustomize(in: app)
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()
        let done = app.buttons["save.questions.done"]
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["save.editorScroll"].waitForExistence(timeout: 5))
        capture("REC-485 composer after restoring questions")
    }

    private func catalogAnswerButtons(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "save.question.place_detail_"))
    }

    private func recurringIDs(in app: XCUIApplication) -> [String] {
        let prefix = "save.questions.recurring."
        var seen = Set<String>()
        return app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByAccessibilityElement.sorted { $0.frame.minY < $1.frame.minY }
            .compactMap { element in
                let id = String(element.identifier.dropFirst(prefix.count))
                return seen.insert(id).inserted ? id : nil
            }
    }

    private func recurringElement(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["save.questions.recurring.\(id)"].firstMatch
    }

    private func recurringCell(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.cells.containing(.any, identifier: "save.questions.recurring.\(id)").firstMatch
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upwards: Bool = true) {
        for _ in 0..<16 {
            let exists = element.exists
            let frame = exists ? element.frame : .zero
            let id = exists ? element.identifier : ""
            let composerTarget = id == "save.questions.customize" || id == "save.questions.alsoNoted"
                || id.hasPrefix("save.question.") || id.hasPrefix("save.placeType.")
            let editor = app.scrollViews["save.editorScroll"]
            let composerVisible = editor.isHittable && !app.buttons["save.questions.done"].exists
            let usesEditor = (composerTarget || !exists) && composerVisible
            let surface = usesEditor ? editor : app
            var viewport = surface.frame.intersection(app.frame)
            if usesEditor {
                // A partly exposed control can be hittable while its center is
                // behind the fixed save action. Scroll within the visible body.
                let submit = app.buttons["save.submit"]
                if submit.exists {
                    viewport.size.height = max(0, min(viewport.maxY, submit.frame.minY) - viewport.minY)
                }
                viewport = viewport.insetBy(dx: 12, dy: 12)
            }
            if element.isHittable && (!usesEditor || viewport.contains(CGPoint(x: frame.midX, y: frame.midY))) {
                return
            }
            let scrollUp = frame.isEmpty ? upwards : frame.midY >= viewport.midY
            if usesEditor && viewport.height > 80 {
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let lower = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.78))
                let upper = origin.withOffset(CGVector(dx: viewport.midX, dy: viewport.minY + viewport.height * 0.22))
                (scrollUp ? lower : upper).press(
                    forDuration: 0.05,
                    thenDragTo: scrollUp ? upper : lower,
                    withVelocity: .slow,
                    thenHoldForDuration: 0.2
                )
            } else if scrollUp {
                surface.swipeUp(velocity: .slow)
            } else {
                surface.swipeDown(velocity: .slow)
            }
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
