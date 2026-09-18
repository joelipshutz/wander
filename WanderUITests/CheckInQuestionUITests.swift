import XCTest
import UIKit

@MainActor
final class CheckInQuestionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRestoreCancellationKeepsCustomizationOpen() {
        let app = launchPlace()
        openCheckIn(in: app)
        openCustomize(in: app)
        let previous = recurringIDs(in: app)
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()
        let cancel = app.buttons["No, cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("REC-485 native restore confirmation")
        cancel.tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 5))
        XCTAssertEqual(recurringIDs(in: app), previous)
        let footer = app.staticTexts["Drag to reorder."]
        reveal(footer, in: app)
        XCTAssertTrue(footer.exists)
        XCTAssertTrue(app.staticTexts["Removing a question changes future prompts and keeps previous answers."].exists)
        XCTAssertTrue(app.staticTexts["Slashed eye. This symbol means those questions only stay with you"].exists)
        capture("REC-485 restore cancellation preserves customization")
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
        XCTAssertFalse(app.descendants(matching: .any)["save.questions.catalogStealth"].firstMatch.exists)
        capture("REC-485 question library without Stealth section")
        let search = app.textFields["save.questions.catalogSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("outlet\n")
        let outlets = app.buttons["save.questions.catalog.place_detail_outlets"]
        XCTAssertTrue(outlets.waitForExistence(timeout: 3))
        outlets.tap()
        XCTAssertTrue(recurringElement("place_detail_outlets", in: app).waitForExistence(timeout: 3))
        let outletsEye = app.buttons["save.questions.stealth.place_detail_outlets"]
        XCTAssertEqual(outletsEye.value as? String, "Off, check-in audience")
        outletsEye.tap()
        XCTAssertEqual(outletsEye.value as? String, "On, only you")

        let createCustom = app.buttons["save.questions.createCustom"]
        reveal(createCustom, in: app)
        XCTAssertTrue(createCustom.isEnabled, "Creating a question stays available while native reorder controls are shown.")
        createCustom.tap()
        XCTAssertFalse(app.descendants(matching: .any)["save.questions.customStealth"].firstMatch.exists)
        let prompt = app.descendants(matching: .any)["save.questions.customPrompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 3))
        reveal(prompt, in: app, upwards: false)
        prompt.tap()
        prompt.typeText("Lots of plants indoors?")
        app.buttons["save.questions.customAdd"].tap()
        XCTAssertTrue(app.buttons["save.questions.done"].waitForExistence(timeout: 3))
        let customID = try XCTUnwrap(recurringIDs(in: app).first { $0.hasPrefix("custom_question_") })
        let customEye = app.buttons["save.questions.stealth.\(customID)"]
        XCTAssertEqual(customEye.value as? String, "On, only you")
        customEye.tap()
        XCTAssertEqual(customEye.value as? String, "Off, check-in audience")
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
        let selectedStealth = app.buttons["save.questions.stealth.\(customID)"]
        XCTAssertTrue(selectedStealth.waitForExistence(timeout: 3))
        XCTAssertEqual(selectedStealth.value as? String, "Off, check-in audience")
        selectedStealth.tap()
        XCTAssertEqual(selectedStealth.value as? String, "On, only you")
        app.buttons["save.questions.done"].tap()
        let badge = app.descendants(matching: .any)["save.question.stealth.\(customID)"].firstMatch
        reveal(badge, in: app)
        let questionText = app.staticTexts["save.question.row.\(customID)"]
        XCTAssertTrue(badge.isHittable)
        XCTAssertGreaterThanOrEqual(badge.frame.minX, questionText.frame.maxX)
        XCTAssertLessThan(badge.frame.minY, questionText.frame.maxY, "Stealth stays beside the question.")
        capture("REC-485 inline Stealth answer badge")
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
        let stealth = app.buttons["save.questions.stealth.\(questionID)"]
        XCTAssertTrue(stealth.waitForExistence(timeout: 3))
        reveal(stealth, in: app)
        XCTAssertGreaterThanOrEqual(stealth.frame.height, 44)
        let initialStealth = stealth.value as? String
        stealth.tap()
        XCTAssertNotEqual(stealth.value as? String, initialStealth)
        capture("REC-485 accessibility text Stealth toggle")
        stealth.tap()
        XCTAssertEqual(stealth.value as? String, initialStealth)
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
        for id in ["place_detail_arrival_parking", "place_detail_outdoor_seating", "place_detail_dietary_options"] {
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
        confirmRestore(in: app)

        let add = app.buttons["save.questions.addCatalog"]
        reveal(add, in: app, upwards: false)
        XCTAssertTrue(add.isEnabled)
        add.tap()
        XCTAssertFalse(app.descendants(matching: .any)["save.questions.catalogStealth"].firstMatch.exists)
        let questionSearch = app.textFields["save.questions.catalogSearch"]
        XCTAssertTrue(questionSearch.waitForExistence(timeout: 3))
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
        confirmRestore(in: app)
        app.buttons["save.questions.done"].tap()
    }

    func testNotUsefulCanUndoAndStaysHiddenUntilReadded() {
        let app = launchPlace(placeName: "Larchmont Noodles")
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        let yes = app.buttons["save.question.place_detail_arrival_parking.Yes"]
        reveal(yes, in: app)
        yes.tap()
        let usefulness = app.buttons["save.question.useful.place_detail_arrival_parking"]
        reveal(usefulness, in: app)
        // Native sheet scaling changes screen-space frames (44 logical points
        // becomes 42.4 here). Compare with the full-height Customize control.
        XCTAssertGreaterThanOrEqual(
            usefulness.frame.height,
            app.buttons["save.questions.customize"].frame.height - 0.5
        )
        usefulness.tap()
        XCTAssertEqual(usefulness.value as? String, "Hidden from future prompts")
        XCTAssertFalse(yes.isEnabled)
        XCTAssertTrue(yes.isSelected, "Hiding must preserve an answer already entered.")
        capture("REC-485 dismissed question with Undo")
        usefulness.tap()
        XCTAssertTrue(yes.isEnabled)
        XCTAssertTrue(yes.isSelected)
        usefulness.tap()
        // Reopening customization removes the transient gray row but must not
        // resurface its existing answer under Also noted.
        openCustomize(in: app)
        XCTAssertFalse(recurringElement("place_detail_arrival_parking", in: app).exists)
        let restore = app.buttons["save.questions.restore"]
        reveal(restore, in: app)
        restore.tap()
        app.buttons["No, cancel"].tap()
        XCTAssertFalse(recurringElement("place_detail_arrival_parking", in: app).exists)
        app.buttons["save.questions.done"].tap()
        app.terminate()
        app.launch()
        openCheckIn(in: app)
        XCTAssertFalse(app.staticTexts["save.question.row.place_detail_arrival_parking"].exists)
        openCustomize(in: app)
        app.buttons["save.questions.addCatalog"].tap()
        let search = app.textFields["save.questions.catalogSearch"]
        search.tap()
        search.typeText("Easy to find parking\n")
        app.buttons["save.questions.catalog.place_detail_arrival_parking"].tap()
        XCTAssertTrue(recurringElement("place_detail_arrival_parking", in: app).exists)
        app.buttons["save.questions.done"].tap()
        reveal(yes, in: app)
        XCTAssertTrue(yes.isEnabled)
        restoreSuggestions(in: app)
    }

    func testDietaryMultiSelectionSurvivesInlineStealthToggle() {
        let app = launchPlace(placeName: "Larchmont Noodles")
        openCheckIn(in: app)
        restoreSuggestions(in: app)
        let vegan = app.buttons["save.question.place_detail_dietary_options.Vegan"]
        let glutenFree = app.buttons["save.question.place_detail_dietary_options.Gluten free"]
        reveal(vegan, in: app)
        vegan.tap()
        glutenFree.tap()
        XCTAssertTrue(vegan.isSelected)
        XCTAssertTrue(glutenFree.isSelected)
        for expected in ["On, only you", "Off, check-in audience"] {
            openCustomize(in: app)
            let eye = app.buttons["save.questions.stealth.place_detail_dietary_options"]
            reveal(eye, in: app)
            eye.tap()
            XCTAssertEqual(eye.value as? String, expected)
            XCTAssertTrue(app.buttons["save.questions.done"].exists, "No separate Stealth page")
            capture("REC-485 inline privacy eyes")
            app.buttons["save.questions.done"].tap()
            reveal(vegan, in: app)
            XCTAssertTrue(vegan.isSelected)
            XCTAssertTrue(glutenFree.isSelected)
        }
        vegan.tap()
        XCTAssertFalse(vegan.isSelected)
        XCTAssertTrue(glutenFree.isSelected)
        capture("REC-485 dietary multi-select")
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
        confirmRestore(in: app)
        let done = app.buttons["save.questions.done"]
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["save.editorScroll"].waitForExistence(timeout: 5))
        capture("REC-485 composer after restoring questions")
    }

    private func confirmRestore(in app: XCUIApplication) {
        let confirm = app.buttons["Yes, restore"]
        let presented = confirm.waitForExistence(timeout: 5)
        if !presented {
            capture("REC-485 restore confirmation missing")
            print(app.debugDescription)
        }
        XCTAssertTrue(presented, "Restore must ask before changing the question list.")
        confirm.tap()
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
            let composerVisible = editor.exists && editor.isHittable && !app.buttons["save.questions.done"].exists
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
