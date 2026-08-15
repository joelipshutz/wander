import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testInstagramPostExplainsFullPhotoAccessBeforeDirectShare() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderActivityShareMockup",
            "-WanderActivityShareInstagramPostMockup",
            "-activityShare.instagramPostFullPhotoAccessAcknowledged",
            "NO",
        ]
        app.launch()

        let instagramPost = app.buttons["Instagram Post"]
        XCTAssertTrue(instagramPost.waitForExistence(timeout: 5))
        XCTAssertTrue(instagramPost.isHittable)
        instagramPost.tap()

        XCTAssertTrue(
            app.staticTexts["Instagram needs Full Photo Access"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["Settings → Apps → Instagram → Photos → Full Access"].exists
        )
        XCTAssertTrue(app.buttons["I've enabled Full Access"].isHittable)
        XCTAssertTrue(app.buttons["Use compatible sharing"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-271 Instagram Full Photo Access guidance"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        XCTAssertTrue(app.buttons["walkthrough.dismiss.importLesson"].isHittable)

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

    func testImportLessonDismissRetiresAllWalkthroughPrompts() {
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
        let dismiss = app.buttons["walkthrough.dismiss.importLesson"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)

        let promptScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        promptScreenshot.name = "REC-236 import walkthrough with dismiss"
        promptScreenshot.lifetime = .keepAlways
        add(promptScreenshot)

        dismiss.tap()

        XCTAssertTrue(lesson.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)

        let dismissedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        dismissedScreenshot.name = "REC-236 import walkthrough dismissed"
        dismissedScreenshot.lifetime = .keepAlways
        add(dismissedScreenshot)

        app.terminate()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs"
        ]
        app.launch()

        XCTAssertTrue(app.buttons["map.headerAdd"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.importLesson"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
    }

    func testCoachMarkDismissRetiresAllWalkthroughPrompts() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        let coachMark = app.descendants(matching: .any)["walkthrough.map.mapAdd"]
        let dismiss = app.buttons["walkthrough.dismiss.map.mapAdd"]
        XCTAssertTrue(coachMark.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)

        let promptScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        promptScreenshot.name = "REC-236 coach mark with dismiss"
        promptScreenshot.lifetime = .keepAlways
        add(promptScreenshot)

        dismiss.tap()

        XCTAssertTrue(coachMark.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)
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

    func testMapFilterLessonsExplainEveryFilterBeforeMapSearch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderWalkthroughTarget",
            "mapFeatured"
        ]
        app.launch()

        let filterSteps = [
            ("mapFeatured", "map.filter.featured", "REC-257 Featured filter lesson"),
            ("mapFriends", "map.filter.friends", "REC-257 Friends filter lesson"),
            ("mapMoreFilters", "map.filter.more", "REC-257 More filters lesson")
        ]

        for (target, control, screenshotName) in filterSteps {
            XCTAssertTrue(
                app.descendants(matching: .any)["walkthrough.map.\(target)"]
                    .waitForExistence(timeout: 5)
            )
            XCTAssertTrue(
                app.descendants(matching: .any)[control]
                    .waitForExistence(timeout: 2)
            )
            let nextButton = app.buttons["Next"]
            XCTAssertTrue(nextButton.isHittable)
            XCTAssertLessThanOrEqual(nextButton.frame.width, 52)

            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = screenshotName
            screenshot.lifetime = .keepAlways
            add(screenshot)

            nextButton.tap()
        }

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

    func testFeedWalkthroughOpensDiscoverAndExplainsSupportedSearches() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderWalkthroughTarget",
            "feedDiscoverSearch"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 6)
        )
        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.isHittable)
        XCTAssertFalse(app.buttons["Previous walkthrough step"].exists)
        launcher.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchField"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.textFields["discover.placesSearchField"].exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists)

        let fieldScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fieldScreenshot.name = "REC-257 Discover search field lesson"
        fieldScreenshot.lifetime = .keepAlways
        add(fieldScreenshot)

        let nextButton = app.buttons["Next"]
        XCTAssertTrue(nextButton.isHittable)
        XCTAssertLessThanOrEqual(nextButton.frame.width, 52)
        nextButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSmartSearch"]
                .waitForExistence(timeout: 4)
        )
        let suggestedSearch = app.buttons["Search coffee worth crossing town for"]
        XCTAssertTrue(suggestedSearch.isHittable)

        let examplesScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        examplesScreenshot.name = "REC-257 natural-language search examples lesson"
        examplesScreenshot.lifetime = .keepAlways
        add(examplesScreenshot)

        suggestedSearch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchResultsBack"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 6))

        let backButton = app.buttons["discover.searchBack"]
        XCTAssertTrue(backButton.isHittable)
        XCTAssertFalse(app.buttons["Lists"].isSelected)

        let resultsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultsScreenshot.name = "REC-236 guided Discover results stay in NUX"
        resultsScreenshot.lifetime = .keepAlways
        add(resultsScreenshot)

        backButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchExitBack"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Try a search"].exists)
        XCTAssertTrue(backButton.isHittable)

        backButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedPeopleSearch"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.buttons["Feed"].isSelected)
        let feedSectionButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Feed section")
        )
        XCTAssertEqual(feedSectionButtons.count, 2)
        XCTAssertFalse(feedSectionButtons.element(boundBy: 0).isSelected)
        XCTAssertTrue(feedSectionButtons.element(boundBy: 1).isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["Search people"].exists)
        XCTAssertTrue(app.buttons["Next"].isHittable)
    }

    func testTypedDiscoverQueryAlsoStaysInGuidedResults() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderWalkthroughTarget",
            "feedDiscoverSearch"
        ]
        app.launch()

        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(launcher.waitForExistence(timeout: 6))
        launcher.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchField"]
                .waitForExistence(timeout: 6)
        )
        app.buttons["Next"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSmartSearch"]
                .waitForExistence(timeout: 5)
        )
        let searchField = app.textFields["discover.placesSearchField"]
        XCTAssertTrue(searchField.isHittable)
        searchField.tap()
        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }
        searchField.typeText("quiet cafes with wifi\n")

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchResultsBack"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["discover.searchBack"].isHittable)
        XCTAssertFalse(app.buttons["Lists"].isSelected)
    }

    func testMapMorePeopleIncludesYouAndPersistsAcrossSourceSwitch() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapMoreFiltersOpen"
        ]
        app.launch()

        let popover = app.scrollViews.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))

        let expectedPeople = [
            (id: "user_joe", name: "You"),
            (id: "user_demo", name: "Demo"),
            (id: "user_maya", name: "Maya"),
            (id: "user_ryan", name: "Ryan")
        ]
        let you = app.buttons["map.more.person.user_joe"]
        for _ in 0..<5 where !you.exists {
            popover.swipeUp()
        }

        for person in expectedPeople {
            let button = app.buttons["map.more.person.\(person.id)"]
            XCTAssertTrue(button.exists, "Expected More → People to include \(person.name)")
            XCTAssertTrue(button.label.contains(person.name))
        }

        you.tap()
        XCTAssertEqual(you.value as? String, "Selected")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-261 More People includes You and follows"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let done = app.buttons["Done"]
        for _ in 0..<5 where !done.isHittable {
            popover.swipeDown()
        }
        XCTAssertTrue(done.isHittable)
        done.tap()

        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Friends map source")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "More map filters")).firstMatch.tap()
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        for _ in 0..<5 where !you.exists {
            popover.swipeUp()
        }

        XCTAssertEqual(you.value as? String, "Selected")
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

    func testFeedOverviewRoutesStraightToDiscoverSearch() {
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
        XCTAssertTrue(app.staticTexts["See your friends’ check-ins here"].exists)
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["feed.searchLauncher"].isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 condensed Feed NUX"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWalkthroughInviteIsOptionalUntilAContactIsSelected() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderInviteMockup", "walkthroughContacts"]
        app.launch()

        let primaryAction = app.buttons["invite.primaryAction"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let firstContact = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Maya")
        ).firstMatch
        XCTAssertTrue(firstContact.waitForExistence(timeout: 3))
        firstContact.tap()

        XCTAssertEqual(primaryAction.label, "Invite")
        XCTAssertTrue(primaryAction.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-257 optional walkthrough invite after one selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWalkthroughContactInviteCloseDismissesTheEntireNux() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderWalkthroughTarget",
            "feedInvite"
        ]
        app.launch()

        let coachMark = app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
        XCTAssertTrue(coachMark.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()

        let dismiss = app.buttons["walkthrough.dismiss.contactInvite"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 4))
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 contact invite walkthrough dismiss"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        dismiss.tap()

        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 3))
        XCTAssertFalse(coachMark.exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
    }

    func testListsUsesTwoClearPageAutoAdvancingLessons() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "lists",
            "-WanderWalkthroughTarget",
            "listsScope"
        ]
        app.launch()

        let startedAt = Date()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsOpenPlan"]
                .waitForExistence(timeout: 4)
        )
        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.exists)
        let selectionDeadline = Date().addingTimeInterval(12)
        while !profileTab.isSelected, Date() < selectionDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(profileTab.isSelected)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 12)
    }

    func testProfileRunsAHandsFreeDemoInUnderFifteenSeconds() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "profile",
            "-WanderWalkthroughTarget",
            "profileShare"
        ]
        app.launch()

        let startedAt = Date()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.profile.profileShare"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.profile.profileActivity"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.descendants(matching: .any)["profile.walkthrough.activitySection"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.profile.profileMap"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.descendants(matching: .any)["profile.walkthrough.mapSection"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.profile.profileCalendar"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.descendants(matching: .any)["profile.walkthrough.calendarSection"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 15)
        )
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 15)
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
            "saveFriends"
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
        let moreOptionsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        moreOptionsScreenshot.name = "REC-257 highlighted More Options disclosure"
        moreOptionsScreenshot.lifetime = .keepAlways
        add(moreOptionsScreenshot)
        let moreOptions = app.buttons["Show more options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveNotes"]
                .waitForExistence(timeout: 1)
        )

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
        let moreOptions = app.buttons["Show more options"]
        XCTAssertTrue(moreOptions.waitForExistence(timeout: 3))
        app.buttons["Next"].tap()

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveNotes"]
                .waitForExistence(timeout: 1)
        )

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

    func testListDetailWalkthroughIsSuppressedForNow() {
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.listDetail.listMap"]
                .waitForExistence(timeout: 1)
        )
        let viewMapButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "View map for")
        ).firstMatch
        XCTAssertTrue(viewMapButton.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.listDetail.listMapPlace"]
                .exists
        )
        XCTAssertFalse(app.buttons["Next"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 full Lists detail NUX suppressed"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPlaceMemoryFallsBackWhenTutorialSaveIsUnavailable() {
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
                .isHittable
        )
        let card = app.descendants(matching: .any)["walkthrough.deviceFeatures.card"]
        let complete = app.descendants(matching: .any)["walkthrough.deviceFeatures.complete"]
        XCTAssertTrue(card.exists)
        XCTAssertTrue(complete.isHittable)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.actionButton"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.widgets"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures.shareExtension"].exists
        )

        let dismiss = app.buttons["walkthrough.dismiss.deviceFeatures"]
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertGreaterThanOrEqual(dismiss.frame.width, 44)
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44)

        let windowFrame = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(card.frame.minY, windowFrame.minY)
        XCTAssertLessThanOrEqual(card.frame.maxY, windowFrame.maxY)

        let cardFrameBeforeSwipe = card.frame
        app.swipeUp()
        XCTAssertEqual(card.frame.minY, cardFrameBeforeSwipe.minY, accuracy: 1)
        XCTAssertEqual(card.frame.maxY, cardFrameBeforeSwipe.maxY, accuracy: 1)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 third-launch device extensions lesson"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        dismiss.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.deviceFeatures"]
                .waitForNonExistence(timeout: 3)
        )
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)
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

    func testCommentsEdgeSwipeReturnsToPreviousFeedPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let feedSearch = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(feedSearch.waitForExistence(timeout: 4))

        let openComments = app.buttons.matching(
            NSPredicate(format: "label == %@", "Open comments")
        ).firstMatch
        XCTAssertTrue(openComments.waitForExistence(timeout: 4))
        if !openComments.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(openComments.isHittable)
        openComments.tap()

        XCTAssertTrue(app.navigationBars["comments"].waitForExistence(timeout: 4))

        let commentsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        commentsScreenshot.name = "Comments native navigation destination"
        commentsScreenshot.lifetime = .keepAlways
        add(commentsScreenshot)

        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightSide)

        XCTAssertTrue(feedSearch.waitForExistence(timeout: 4))
        XCTAssertFalse(app.navigationBars["comments"].exists)

        let returnedFeedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        returnedFeedScreenshot.name = "Feed restored after comments back-swipe"
        returnedFeedScreenshot.lifetime = .keepAlways
        add(returnedFeedScreenshot)
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

    func testLoggedOutLoginExposesAppleGoogleEmailAndPasswordWithoutClerkSheet() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthUITest"]
        app.launch()

        let apple = app.buttons["auth.continueWithApple"]
        let google = app.buttons["auth.continueWithGoogle"]
        let email = app.textFields["auth.email"]
        let emailContinue = app.buttons["auth.continueWithEmail"]
        let usePassword = app.buttons["auth.usePassword"]
        XCTAssertTrue(apple.waitForExistence(timeout: 4))
        XCTAssertTrue(google.exists)
        XCTAssertTrue(email.exists)
        XCTAssertTrue(emailContinue.exists)
        XCTAssertTrue(usePassword.exists)
        XCTAssertTrue(apple.isHittable)
        XCTAssertTrue(google.isHittable)
        XCTAssertLessThan(apple.frame.minY, google.frame.minY)
        XCTAssertLessThan(google.frame.minY, email.frame.minY)
        XCTAssertFalse(app.buttons["auth.useOtherMethod"].exists)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let systemAlert = springboard.alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 2) {
            let deny = systemAlert.buttons["Don’t Allow"]
            if deny.exists {
                deny.tap()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            }
        }

        if !usePassword.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(usePassword.isHittable)
        usePassword.tap()

        let passwordEmail = app.textFields["auth.passwordEmail"]
        let password = app.secureTextFields["auth.password"]
        let passwordSubmit = app.buttons["auth.signInWithPassword"]
        let leavePassword = app.buttons["auth.leavePassword"]
        XCTAssertTrue(passwordEmail.waitForExistence(timeout: 2))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(passwordSubmit.exists)
        XCTAssertTrue(leavePassword.exists)
        XCTAssertTrue(passwordEmail.isHittable)
        XCTAssertTrue(password.isHittable)

        let passwordScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        passwordScreenshot.name = "REC-180 App Review password sign-in"
        passwordScreenshot.lifetime = .keepAlways
        add(passwordScreenshot)

        leavePassword.tap()
        XCTAssertTrue(apple.waitForExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-259 native Welcome back auth"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCheckInCalendarTrayPresentationLatency() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let addButton = app.buttons["map.headerAdd"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        searchField.tap()
        searchField.typeText("Maru Coffee\n")

        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 6))
        saveButton.tap()

        let checkInChoice = app.buttons["check in"]
        XCTAssertTrue(checkInChoice.waitForExistence(timeout: 3))
        checkInChoice.tap()
        app.buttons["continue to details"].tap()

        let disclosure = app.buttons["save.checkInDateDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))

        let start = ProcessInfo.processInfo.systemUptime
        disclosure.tap()
        XCTAssertTrue((disclosure.value as? String)?.contains("Expanded") == true)
        let picker = app.descendants(matching: .any)["save.checkInDatePicker"]
        XCTAssertTrue(picker.exists)
        let elapsed = ProcessInfo.processInfo.systemUptime - start

        XCTContext.runActivity(named: String(format: "Calendar tray presented in %.3f seconds", elapsed)) { _ in }
        print(String(format: "REC241_CALENDAR_TRAY_LATENCY_SECONDS=%.3f", elapsed))
        XCTAssertLessThan(elapsed, 1.0)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-241 responsive check-in calendar tray"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
