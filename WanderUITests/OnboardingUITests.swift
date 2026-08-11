import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testSecondLaunchImportLessonOpensImportFromPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderShowImportWalkthrough"
        ]
        app.launch()

        let lesson = app.descendants(matching: .any)["walkthrough.importLesson"]
        let openImport = app.buttons["Open import form"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(openImport.isHittable)
        XCTAssertTrue(app.buttons["Import help"].exists)

        let promptScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        promptScreenshot.name = "REC-236 second-launch Import From prompt"
        promptScreenshot.lifetime = .keepAlways
        add(promptScreenshot)

        openImport.tap()

        XCTAssertTrue(app.textViews["import.input"].waitForExistence(timeout: 4))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 second-launch Import From destination"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFirstMapCoachMarkPointsToAddButtonWithoutOversizedCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        let addButton = app.buttons["map.headerAdd"]
        let coachMark = app.descendants(matching: .any)["walkthrough.map.mapAdd"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertTrue(coachMark.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(coachMark.frame.width, 326)
        XCTAssertLessThan(coachMark.frame.height, 190)
        XCTAssertGreaterThanOrEqual(coachMark.frame.minX, 0)
        XCTAssertLessThanOrEqual(coachMark.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(coachMark.frame.minY, 0)
        XCTAssertLessThanOrEqual(coachMark.frame.maxY, app.frame.maxY)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 compact connected add coach mark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBottomTabCoachMarkCaretStaysConnectedToHighlightedTabs() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderWalkthroughTarget",
            "mapTabs"
        ]
        app.launch()

        let coachMark = app.descendants(matching: .any)["walkthrough.map.mapTabs"]
        XCTAssertTrue(coachMark.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Next"].isHittable)
        XCTAssertLessThan(coachMark.frame.maxY, app.buttons["Map"].frame.minY)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 connected bottom-tab coach mark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAddImportShortcutShowsPassiveHighlight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderOpenAdd",
            "-WanderWalkthroughTarget",
            "addImport"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addImport"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Next"].isHittable)

        let importScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        importScreenshot.name = "REC-236 passive Import From highlight"
        importScreenshot.lifetime = .keepAlways
        add(importScreenshot)

        app.buttons["Next"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAdd"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(app.buttons["Close add place"].exists)
    }

    func testMultiplePlaceResultsRemainSelectableInsideTheSpotlight() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderOpenAdd",
            "-WanderShowWalkthroughCandidateResults",
            "-WanderWalkthroughTarget",
            "addPlace"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addPlace"]
                .waitForExistence(timeout: 5)
        )
        let firstResult = app.buttons["add.candidate.walkthrough-maru"]
        let secondResult = app.buttons["add.candidate.walkthrough-dayglow"]
        XCTAssertTrue(firstResult.waitForExistence(timeout: 3))
        XCTAssertTrue(secondResult.waitForExistence(timeout: 3))
        XCTAssertTrue(firstResult.isHittable)
        XCTAssertTrue(secondResult.isHittable)

        secondResult.tap()
        XCTAssertEqual(secondResult.value as? String, "selected")
        XCTAssertEqual(firstResult.value as? String, "not selected")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 selectable multiple place results"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Save"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Dayglow Coffee"].exists)
    }

    func testMapFilterAndSearchExplanationsUseNextWithFullScrim() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderWalkthroughTarget",
            "mapFilters"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapFilters"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapSearch"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["Next"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 full scrim around Map search"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFeedActivityExplanationUsesNext() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderWalkthroughTarget",
            "feedActivity"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedActivity"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.buttons["Next"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 Feed activity passive coach mark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFeedPeopleSearchAndInviteExplanationsUseNext() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderFeedSurface",
            "people",
            "-WanderWalkthroughTarget",
            "feedPeopleSearch"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedPeopleSearch"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["Find my people"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 Feed contacts passive coach mark"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testListCreationExplanationsUseNext() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "lists",
            "-WanderListsScenario",
            "create",
            "-WanderWalkthroughTarget",
            "listEditorTitle"
        ]
        app.launch()

        for target in ["listEditorTitle", "listEditorPrivacy", "listEditorCollaborators"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.listEditor.\(target)"]
                    .waitForExistence(timeout: 6)
            )
            XCTAssertTrue(app.buttons["Next"].isHittable)

            if target == "listEditorCollaborators" {
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "REC-236 List creation passive coach mark"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }

            app.buttons["Next"].tap()
        }

        XCTAssertTrue(app.buttons["lists.headerAdd"].waitForExistence(timeout: 6))
    }

    func testProfileExplanationsUseNext() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "profile",
            "-WanderWalkthroughTarget",
            "profileSettings"
        ]
        app.launch()

        for target in ["profileSettings", "profileSocial", "profileActivity", "profileShare"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.profile.\(target)"]
                    .waitForExistence(timeout: 6)
            )
            XCTAssertTrue(app.buttons["Next"].isHittable)

            if target == "profileActivity" {
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "REC-236 Profile history passive coach mark"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }

            app.buttons["Next"].tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.buttons["Start exploring"].isHittable)
        XCTAssertTrue(app.buttons["Map"].isSelected)

        let sendoffScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        sendoffScreenshot.name = "REC-236 final Map sendoff"
        sendoffScreenshot.lifetime = .keepAlways
        add(sendoffScreenshot)

        app.buttons["Start exploring"].tap()
        XCTAssertFalse(app.buttons["Start exploring"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["map.headerAdd"].exists)
    }

    func testFirstAddActionGuidesThroughSaveBeforeReturningToMap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        let addButton = app.buttons["map.headerAdd"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addSearch"]
                .waitForExistence(timeout: 5)
        )
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Maru Coffee\n")

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addPlace"]
                .waitForExistence(timeout: 6)
        )
        app.buttons["Save"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 5)
        )
        let checkInChoice = app.buttons["check in"]
        let wannaGoChoice = app.buttons["wanna go"]
        XCTAssertEqual(checkInChoice.value as? String, "not selected")
        XCTAssertEqual(wannaGoChoice.value as? String, "not selected")
        XCTAssertFalse(app.buttons["continue to details"].exists)

        let statusScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        statusScreenshot.name = "REC-236 neutral Check In or Wanna Go choice"
        statusScreenshot.lifetime = .keepAlways
        add(statusScreenshot)

        checkInChoice.tap()
        XCTAssertEqual(checkInChoice.value as? String, "selected")
        XCTAssertTrue(app.buttons["continue to details"].waitForExistence(timeout: 3))
        app.buttons["continue to details"].tap()

        for target in [
            "saveDate",
            "saveDetails",
            "saveRating",
            "saveFriends",
            "savePhotos"
        ] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.saveFlow.\(target)"]
                    .waitForExistence(timeout: 5),
                "Expected walkthrough step \(target)"
            )
            XCTAssertTrue(app.buttons["Next"].isHittable)

            if target == "saveRating" {
                let rating = app.otherElements["place-rating-slider"]
                XCTAssertTrue(rating.waitForExistence(timeout: 3))
                let originalValue = rating.value as? String
                rating.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.58)).press(
                    forDuration: 0.1,
                    thenDragTo: rating.coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.58))
                )
                XCTAssertNotEqual(rating.value as? String, originalValue)

                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "REC-236 editable save flow rating step"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }

            app.buttons["Next"].tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveMoreOptions"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["Show more options"].tap()

        for target in ["saveNote", "saveQuestions", "saveTags", "savePrivacy"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.saveFlow.\(target)"]
                    .waitForExistence(timeout: 5),
                "Expected walkthrough step \(target)"
            )
            XCTAssertTrue(app.buttons["Next"].isHittable)

            if target == "saveTags" {
                let suggestions = app.buttons.matching(identifier: "save.tags.suggestion")
                let suggestionLabels = suggestions.allElementsBoundByIndex.map(\.label)
                XCTAssertGreaterThan(suggestionLabels.count, 1)
                let tagPicker = app.descendants(matching: .any)["save.tags.picker"]
                XCTAssertTrue(tagPicker.waitForExistence(timeout: 2))

                for label in suggestionLabels {
                    let suggestion = app.buttons[label]
                    XCTAssertTrue(suggestion.waitForExistence(timeout: 2))
                    var scrollAttempts = 0
                    while !suggestion.isHittable, scrollAttempts < 4 {
                        tagPicker.swipeUp()
                        scrollAttempts += 1
                    }
                    XCTAssertTrue(suggestion.isHittable)
                    suggestion.tap()
                }
                XCTAssertEqual(suggestions.count, 0)
                XCTAssertEqual(
                    app.buttons.matching(identifier: "save.tags.selected").count,
                    suggestionLabels.count
                )
                XCTAssertTrue(app.buttons["Next"].isHittable)

                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "REC-236 all tags selected without blocking save"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }

            app.buttons["Next"].tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveSubmit"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Check in"].waitForExistence(timeout: 3))
        app.buttons["Check in"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAddAgain"]
                .waitForExistence(timeout: 6)
        )
    }

    func testLongAddResultsCanScrollFarEnoughToRevealTheWholeCoachCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["map.headerAdd"].waitForExistence(timeout: 5))
        app.buttons["map.headerAdd"].tap()
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Starbucks\n")

        let coach = app.descendants(matching: .any)["walkthrough.add.addPlace"]
        XCTAssertTrue(coach.waitForExistence(timeout: 6))
        let save = app.buttons["Save"]
        var attempts = 0
        while !save.isHittable, attempts < 10 {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(save.isHittable)

        app.swipeUp()
        app.swipeUp()
        XCTAssertLessThanOrEqual(coach.frame.maxY, app.frame.maxY - 8)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-257 long result coach fully scrollable"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWannaGoCanCompleteTheWalkthroughSaveFlow() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAdd"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["map.headerAdd"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addSearch"]
                .waitForExistence(timeout: 5)
        )
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Maru Coffee\n")

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addPlace"]
                .waitForExistence(timeout: 6)
        )
        app.buttons["Save"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 5)
        )
        let checkInChoice = app.buttons["check in"]
        let wannaGoChoice = app.buttons["wanna go"]
        XCTAssertEqual(checkInChoice.value as? String, "not selected")
        XCTAssertEqual(wannaGoChoice.value as? String, "not selected")
        XCTAssertFalse(app.buttons["continue to details"].exists)
        wannaGoChoice.tap()
        XCTAssertEqual(wannaGoChoice.value as? String, "selected")

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveContinue"]
                .waitForExistence(timeout: 3)
        )
        app.buttons["continue to details"].tap()

        for target in ["saveDate", "saveDetails"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.saveFlow.\(target)"]
                    .waitForExistence(timeout: 5)
            )
            app.buttons["Next"].tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveMoreOptions"]
                .waitForExistence(timeout: 5)
        )
        app.buttons["Show more options"].tap()

        for target in ["saveNote", "saveQuestions", "saveTags", "savePrivacy"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.saveFlow.\(target)"]
                    .waitForExistence(timeout: 5)
            )
            app.buttons["Next"].tap()
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveSubmit"]
                .waitForExistence(timeout: 5)
        )
        let saveButton = app.buttons["Add to Wanna"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertTrue(saveButton.isHittable)
        saveButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAddAgain"]
                .waitForExistence(timeout: 6)
        )
    }

    func testListMapWalkthroughHighlightsTheFocusedPlaceCardThenReturnsToActions() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "lists",
            "-WanderListsScenario",
            "detail",
            "-WanderWalkthroughTarget",
            "listMap"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.listDetail.listMap"]
                .waitForExistence(timeout: 5)
        )
        let viewMapButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "View map for")
        ).firstMatch
        XCTAssertTrue(viewMapButton.waitForExistence(timeout: 3))
        viewMapButton.tap()

        let placeCoach = app.descendants(matching: .any)["walkthrough.listDetail.listMapPlace"]
        XCTAssertTrue(placeCoach.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Next"].isHittable)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Circuit Coffee")).firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 list map focused place-card lesson"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Next"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.listDetail.listActions"]
                .waitForExistence(timeout: 6)
        )
    }

    func testPlaceMemoryUsesRealisticSeedWhenTutorialSaveIsUnavailable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderWalkthroughTarget",
            "mapMemory"
        ]
        app.launch()

        let memoryCoach = app.descendants(matching: .any)["walkthrough.map.mapMemory"]
        XCTAssertTrue(memoryCoach.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Open place"].isHittable)
        XCTAssertLessThan(memoryCoach.frame.maxY, app.buttons["Map"].frame.minY)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 seeded place memory fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["Open place"].tap()
        for target in ["placeRatings", "placeActions", "placeHistory"] {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.placeDetail.\(target)"]
                    .waitForExistence(timeout: 6),
                "Expected place detail walkthrough step \(target)"
            )
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "REC-257 place detail \(target)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let buttonTitle = target == "placeHistory" ? "Keep going" : "Next"
            XCTAssertTrue(app.buttons[buttonTitle].isHittable)
            app.buttons[buttonTitle].tap()
        }
    }

    func testThirdLaunchDeviceLessonIncludesExtensionsGuide() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderShowDeviceFeaturesWalkthrough"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.extensionsGuide"]
                .exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.complete"]
                .exists
        )
        XCTAssertTrue(app.staticTexts["Share into rec.me"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 third-launch device extensions lesson"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPrimaryTabTapNavigatesToFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let mapTab = app.buttons["Map"]
        let feedTab = app.buttons["Feed"]
        XCTAssertTrue(mapTab.waitForExistence(timeout: 4))
        XCTAssertTrue(feedTab.waitForExistence(timeout: 2))
        XCTAssertTrue(mapTab.isSelected)

        // Navigation is a touch-up contract. Immediate touch-down icon feedback
        // is covered deterministically by NavigationContractTests.
        feedTab.tap()

        XCTAssertTrue(feedTab.isSelected)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 4))
    }

    func testFocusedMapSearchStaysWithinTheUsableViewport() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapSearchQuery",
            "coffee"
        ]
        app.launch()

        let searchField = app.textFields["map.searchField"]
        let cancelButton = app.buttons["map.searchCancel"]
        let typeaheadPanel = app.otherElements["map.typeaheadPanel"]
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        XCTAssertTrue(typeaheadPanel.waitForExistence(timeout: 4))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }

        XCTAssertGreaterThan(searchField.frame.minY, 44)
        XCTAssertGreaterThanOrEqual(typeaheadPanel.frame.minY, searchField.frame.maxY)
        XCTAssertLessThan(typeaheadPanel.frame.maxY, keyboard.frame.minY)
        XCTAssertFalse(app.buttons["map.headerAdd"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-191 focused Map search post-fix"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testRatingSliderRespondsThroughoutContinuousDrag() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace",
            "Woodcat Coffee",
            "-WanderMapSheetExpanded"
        ]
        app.launch()

        let checkInAgain = app.buttons["Check in again"].firstMatch
        XCTAssertTrue(checkInAgain.waitForExistence(timeout: 3))
        checkInAgain.tap()

        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3))

        for _ in 0..<3 where !slider.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(slider.isHittable)

        let startingValue = slider.value as? String
        let lowCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)
        )
        let highCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)
        )

        lowCoordinate.press(forDuration: 0.05, thenDragTo: highCoordinate)

        let highValue = slider.value as? String
        XCTAssertNotEqual(highValue, startingValue)
        XCTAssertTrue(highValue?.contains("4.5 out of 5") == true)

        highCoordinate.press(forDuration: 0.05, thenDragTo: lowCoordinate)

        let lowValue = slider.value as? String
        XCTAssertNotEqual(lowValue, highValue)
        XCTAssertTrue(lowValue?.contains("1.5 out of 5") == true)
    }

    func testFeedSearchUsesDedicatedStateAndBackReturnsToFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 4))
        launcher.tap()

        let searchField = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        let backButton = app.buttons["discover.searchBack"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        XCTAssertEqual(backButton.label, "Back to Feed")
        XCTAssertFalse(app.staticTexts["Discover"].exists)
        XCTAssertTrue(app.staticTexts["Try a search"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 2))
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let focusedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        focusedScreenshot.name = "Feed search focused"
        focusedScreenshot.lifetime = .keepAlways
        add(focusedScreenshot)

        searchField.tap()
        searchField.typeText("coffee")
        XCTAssertEqual(searchField.value as? String, "coffee")
        searchField.typeText("\n")
        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 4))

        app.swipeUp()
        XCTAssertTrue(backButton.exists)
        XCTAssertTrue(backButton.isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        let resultsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultsScreenshot.name = "Feed search results with pinned toolbar"
        resultsScreenshot.lifetime = .keepAlways
        add(resultsScreenshot)

        let clearButton = app.buttons["Clear search"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2))
        clearButton.tap()
        XCTAssertTrue(app.staticTexts["Try a search"].exists)
        XCTAssertTrue(backButton.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Feed dedicated search state"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        backButton.tap()
        XCTAssertTrue(launcher.waitForExistence(timeout: 3))
    }

    func testLoggedOutCarouselAutoAdvancesAndKeepsActionsVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderOnboardingUITestSignedOut"]
        app.launchEnvironment["WANDER_ONBOARDING_AUTO_ADVANCE_SECONDS"] = "2"
        app.launchEnvironment["WANDER_ONBOARDING_FORCE_AUTO_ADVANCE"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.getStarted"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["onboarding.logIn"].exists)
        let carouselPage = app.descendants(matching: .any)["onboarding.carouselPage"]
        XCTAssertTrue(carouselPage.waitForExistence(timeout: 2))
        let startingPage = carouselPage.value as? String ?? ""
        XCTAssertTrue(["1", "2", "3"].contains(startingPage))
        expectation(
            for: NSPredicate(format: "value != %@", startingPage),
            evaluatedWith: carouselPage
        )
        waitForExpectations(timeout: 3)
        XCTAssertTrue(app.buttons["onboarding.getStarted"].isHittable)
    }
}
