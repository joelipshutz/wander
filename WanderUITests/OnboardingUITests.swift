import XCTest

@MainActor
final class OnboardingUITests: XCTestCase {
    func testActualOnboardingPermissionScreensUseSingleNeutralAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "location"
        ]
        app.launch()

        let locationContinue = app.buttons["Continue"].firstMatch
        XCTAssertTrue(locationContinue.waitForExistence(timeout: 8))
        XCTAssertEqual(locationContinue.label, "Continue")
        XCTAssertFalse(app.buttons["Not now"].exists)

        let locationScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        locationScreenshot.name = "REC-396 actual onboarding location permission"
        locationScreenshot.lifetime = .keepAlways
        add(locationScreenshot)

        app.terminate()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderOnboardingUITestStep",
            "contacts"
        ]
        app.launch()

        let contactsContinue = app.buttons["Continue"].firstMatch
        XCTAssertTrue(contactsContinue.waitForExistence(timeout: 8))
        XCTAssertTrue(contactsContinue.isHittable)
        XCTAssertFalse(app.buttons["Not now"].exists)

        let contactsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        contactsScreenshot.name = "REC-396 actual onboarding contacts permission"
        contactsScreenshot.lifetime = .keepAlways
        add(contactsScreenshot)
    }

    func testActualFeedContactInvitePrimerUsesSingleNeutralAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseEphemeralEmptyFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderFeedSurface",
            "people"
        ]
        app.launch()

        let inviteEntry = app.buttons["invite people to rec.me"]
        XCTAssertTrue(inviteEntry.waitForExistence(timeout: 8))
        inviteEntry.tap()

        let permissionContinue = app.buttons["invite.permissionContinue"]
        XCTAssertTrue(permissionContinue.waitForExistence(timeout: 5))
        XCTAssertEqual(permissionContinue.label, "Continue")
        XCTAssertFalse(app.buttons["invite.close"].exists)
        XCTAssertFalse(app.buttons["not now"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-396 actual Feed contact invite permission"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testAuthenticatedSimulatorFixtureSurvivesArgumentFreeRelaunch() {
        let app = XCUIApplication()
        defer {
            app.terminate()
            app.launchArguments = [
                "-WanderUseLiveAuth",
                "-WanderOnboardingUITestSignedOut",
            ]
            app.launch()
            app.terminate()
        }

        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Continue offline"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Profile"].exists)
        XCTAssertFalse(app.buttons["Continue offline"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)
    }

    func testSimulatorBuildExposesDebugSettingsWithoutServerEntitlement() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
            "-WanderOpenSettings",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let continueOffline = app.buttons["Continue offline"]
        if continueOffline.waitForExistence(timeout: 8) {
            continueOffline.tap()
        }

        let nuxToggle = app.descendants(matching: .any)["settings.debug.firstVisitNUX"]
        let placeStylePicker = app.descendants(matching: .any)["settings.debug.placeActionVariant"]
        for _ in 0..<5 where !placeStylePicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(nuxToggle.waitForExistence(timeout: 8))
        XCTAssertTrue(placeStylePicker.waitForExistence(timeout: 3))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Simulator @joe Debug Settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

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
        XCTAssertFalse(app.buttons["walkthrough.dismiss.importLesson"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)

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

    func testImportLessonIsUnskippableAndKeepsItsPrimaryActionAvailable() {
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
        XCTAssertFalse(app.buttons["walkthrough.dismiss.importLesson"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
        XCTAssertTrue(openImport.isHittable)
        XCTAssertTrue(app.buttons["Import help"].isHittable)

        let promptScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        promptScreenshot.name = "REC-236 unskippable import walkthrough"
        promptScreenshot.lifetime = .keepAlways
        add(promptScreenshot)

        openImport.tap()
        XCTAssertTrue(app.textViews["import.input"].waitForExistence(timeout: 4))
    }

    func testCoachMarkIsUnskippableAndOnlyTheHighlightedAddActionAdvances() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs"
        ]
        app.launch()

        let coachMark = app.descendants(matching: .any)["walkthrough.map.mapAdd"]
        let addButton = app.buttons["map.headerAdd"]
        XCTAssertTrue(coachMark.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["walkthrough.dismiss.map.mapAdd"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
        XCTAssertTrue(addButton.isHittable)

        let promptScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        promptScreenshot.name = "REC-236 unskippable Saving a place coach mark"
        promptScreenshot.lifetime = .keepAlways
        add(promptScreenshot)

        addButton.tap()

        XCTAssertTrue(coachMark.waitForNonExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addSearch"]
                .waitForExistence(timeout: 5)
        )
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
        XCTAssertFalse(app.staticTexts["No featured check-ins here yet."].exists)

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
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(app.buttons["Close add place"].exists)
    }

    func testAddWalkthroughTypesAndSelectsTheTutorialParkAutomatically() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderOpenAdd",
            "-WanderWalkthroughTarget",
            "addSearch"
        ]
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addSearch"]
                .waitForExistence(timeout: 5)
        )
        let searchField = app.textFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertFalse(searchField.isEnabled)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertTrue(app.staticTexts["Hotchkiss Park"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.add.addPlace"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 automatically selected tutorial park"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(app.staticTexts["Hotchkiss Park"].exists)
    }

    func testMapFilterLessonsStayCompiledButCannotBeForcedIntoTheLiveNUX() {
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.map.mapFeatured"]
                .waitForExistence(timeout: 1)
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.map.mapSearch"].exists)
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 1),
            "Feed and Discover lessons must remain dormant even when an old target is forced."
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"].exists { return }

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
        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 6))

        let backButton = app.buttons["discover.searchBack"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 2))
        backButton.tap()
        XCTAssertTrue(
            app.staticTexts["Understood as"].exists,
            "The first Back action stays blocked while the results preview is playing."
        )
        XCTAssertFalse(app.buttons["Lists"].isSelected)

        let resultsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resultsScreenshot.name = "REC-236 guided Discover results stay in NUX"
        resultsScreenshot.lifetime = .keepAlways
        add(resultsScreenshot)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchResultsBack"]
                .waitForExistence(timeout: 6)
        )
        expectation(
            for: NSPredicate(format: "hittable == true"),
            evaluatedWith: backButton
        )
        waitForExpectations(timeout: 3)
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

        app.buttons["walkthrough.next.feed.feedPeopleSearch"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["walkthrough.next.feed.feedInvite"].tap()
        let inviteNext = app.buttons["invite.primaryAction"]
        XCTAssertTrue(inviteNext.waitForExistence(timeout: 4))
        inviteNext.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsOpenPlan"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["walkthrough.next.sendoff.mapSendoff"].isHittable)
    }

    func testSignedInLiveAccountCompletesFeedListsAndSendoffWalkthrough() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This diagnostic requires the signed-in physical test device.")
        #else
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderUseLiveAuth",
            "-WanderEnableWalkthroughs",
            "-WanderResetWalkthroughs",
            "-WanderInitialTab",
            "discover",
            "-WanderWalkthroughTarget",
            "feedDiscoverSearch"
        ]
        app.launch()

        let launcher = app.buttons["feed.searchLauncher"]
        XCTAssertTrue(
            launcher.waitForExistence(timeout: 20),
            "The normal app did not reach the signed-in Feed."
        )
        XCTAssertFalse(app.buttons["Continue offline"].exists)
        XCTAssertFalse(app.buttons["Get started"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 1),
            "The live signed-in app must not reactivate the dormant Feed/List NUX."
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"].exists { return }
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 8)
        )
        launcher.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchField"]
                .waitForExistence(timeout: 8)
        )
        app.buttons["walkthrough.next.feedSearch.feedSearchField"].tap()

        let suggestedSearch = app.buttons["Search coffee worth crossing town for"]
        XCTAssertTrue(suggestedSearch.waitForExistence(timeout: 8))
        suggestedSearch.tap()

        let backButton = app.buttons["discover.searchBack"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 12))
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchResultsBack"]
                .waitForExistence(timeout: 12)
        )
        expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: backButton)
        waitForExpectations(timeout: 6)
        backButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedPeopleSearch"]
                .waitForExistence(timeout: 8)
        )
        app.buttons["walkthrough.next.feed.feedPeopleSearch"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
                .waitForExistence(timeout: 8)
        )
        app.buttons["walkthrough.next.feed.feedInvite"].tap()

        let inviteAction = app.buttons["invite.primaryAction"]
        if inviteAction.waitForExistence(timeout: 6) {
            inviteAction.tap()
        } else if app.buttons["continue to contacts"].waitForExistence(timeout: 2) {
            throw XCTSkip("Contacts permission is undecided on the signed-in device.")
        }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsOpenPlan"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 14)
        )
        XCTAssertTrue(app.buttons["walkthrough.next.sendoff.mapSendoff"].isHittable)
        #endif
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"]
                .waitForExistence(timeout: 1)
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedDiscoverSearch"].exists { return }

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

        XCTAssertTrue(app.staticTexts["Understood as"].waitForExistence(timeout: 6))
        let backButton = app.buttons["discover.searchBack"]
        RunLoop.current.run(until: Date().addingTimeInterval(4.2))
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feedSearch.feedSearchResultsBack"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertEqual(backButton.label, "Back to Feed")
        XCTAssertTrue(backButton.isHittable)
        XCTAssertFalse(app.buttons["Lists"].isSelected)
        backButton.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedPeopleSearch"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.buttons["Feed"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any)["Search people"].exists)
    }

    func testMapMoreSectionsAndResetFollowTheActiveSource() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapMoreFiltersOpen"
        ]
        app.launch()

        let popover = app.scrollViews.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))

        let expectedPeople = [
            (id: "user_demo", name: "Demo"),
            (id: "user_maya", name: "Maya"),
            (id: "user_ryan", name: "Ryan")
        ]
        let demo = app.buttons["map.more.person.user_demo"]
        for _ in 0..<5 where !demo.exists {
            popover.swipeUp()
        }

        XCTAssertFalse(app.buttons["map.more.person.user_joe"].exists)
        for person in expectedPeople {
            let button = app.buttons["map.more.person.\(person.id)"]
            XCTAssertTrue(button.exists, "Expected More → People to include \(person.name)")
            XCTAssertTrue(button.label.contains(person.name))
        }

        demo.tap()
        XCTAssertEqual(demo.value as? String, "Selected")

        let done = app.buttons["Done"]
        for _ in 0..<5 where !done.isHittable {
            popover.swipeDown()
        }
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(popover.waitForNonExistence(timeout: 2))

        let more = app.buttons["map.filter.more"]
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "1 selected filter"),
            evaluatedWith: more
        )
        waitForExpectations(timeout: 2)

        let you = app.buttons["map.filter.you"]
        you.tap()
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "Selected"),
            evaluatedWith: you
        )
        expectation(
            for: NSPredicate(format: "value CONTAINS %@", "No additional filters"),
            evaluatedWith: more
        )
        waitForExpectations(timeout: 2)
        more.tap()
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Categories"].exists)
        XCTAssertFalse(app.staticTexts["People"].exists)
        XCTAssertTrue(app.staticTexts["Status"].exists)
        XCTAssertFalse(app.buttons["map.more.person.user_demo"].exists)

        app.buttons["Done"].tap()
        app.buttons["map.filter.featured"].tap()
        more.tap()
        XCTAssertTrue(popover.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Categories"].exists)
        XCTAssertFalse(app.staticTexts["People"].exists)
        XCTAssertFalse(app.staticTexts["Status"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Map More follows the active source"
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedActivity"]
                .waitForExistence(timeout: 1)
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedActivity"].exists { return }

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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedActivity"]
                .waitForExistence(timeout: 1)
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedActivity"].exists { return }

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedActivity"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertTrue(app.staticTexts["Activity"].exists)
        XCTAssertTrue(app.staticTexts["See your friend's check-ins in real time"].exists)
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

    func testWalkthroughInviteUsesAddButtonsAndKeepsNextAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderInviteMockup", "walkthroughContacts"]
        app.launch()

        let primaryAction = app.buttons["invite.primaryAction"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 5))
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let firstContact = app.buttons["invite.contactAdd.maya"]
        XCTAssertTrue(firstContact.waitForExistence(timeout: 3))
        XCTAssertEqual(firstContact.value as? String, "Not sent")
        XCTAssertEqual(firstContact.label, "Invite Maya Chen")
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 per-contact walkthrough Add actions"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testWalkthroughContactInviteIsUnskippableAndNextContinuesToLists() {
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
                .waitForExistence(timeout: 1)
        )
        if !app.descendants(matching: .any)["walkthrough.feed.feedInvite"].exists { return }

        let coachMark = app.descendants(matching: .any)["walkthrough.feed.feedInvite"]
        XCTAssertTrue(coachMark.waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Next"].isHittable)
        app.buttons["Next"].tap()

        let primaryAction = app.buttons["invite.primaryAction"]
        XCTAssertTrue(primaryAction.waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["walkthrough.dismiss.contactInvite"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
        XCTAssertEqual(primaryAction.label, "Next")
        XCTAssertTrue(primaryAction.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 unskippable contact invite walkthrough"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        primaryAction.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(coachMark.exists)
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

        XCTAssertFalse(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 1),
            "Lists lessons must remain dormant even when an old target is forced."
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.lists.listsOpenPlan"].exists)
        if !app.descendants(matching: .any)["walkthrough.lists.listsScope"].exists { return }

        let startedAt = Date()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsScope"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.lists.listsOpenPlan"]
                .waitForExistence(timeout: 7)
        )
        let mapTab = app.buttons["Map"]
        XCTAssertTrue(mapTab.exists)
        let profileTab = app.buttons["Profile"]
        XCTAssertTrue(profileTab.exists)
        XCTAssertFalse(profileTab.isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileShare"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileActivity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileCalendar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileMap"].exists)

        let selectionDeadline = Date().addingTimeInterval(8)
        while !mapTab.isSelected, Date() < selectionDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(mapTab.isSelected)
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 30)
        let finish = app.buttons["walkthrough.next.sendoff.mapSendoff"]
        XCTAssertEqual(finish.label, "Finish")
        XCTAssertTrue(finish.isHittable)
        finish.tap()
        XCTAssertFalse(finish.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["map.headerAdd"].exists)
    }

    func testProfileNeverPresentsAFirstVisitWalkthrough() {
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

        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["Profile"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileShare"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileActivity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileCalendar"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.profile.profileMap"].exists)

        RunLoop.current.run(until: Date().addingTimeInterval(5))

        XCTAssertTrue(app.buttons["Profile"].isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"].exists)
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
        XCTAssertFalse(searchField.isEnabled)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertTrue(app.staticTexts["Hotchkiss Park"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.add.addPlace"].exists)
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
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveDate"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(app.buttons["continue to details"].exists)
        XCTAssertFalse(app.buttons["walkthrough.back.saveFlow.saveDate"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveNote"]
                .waitForExistence(timeout: 10)
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveRating"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertFalse(app.buttons["Next"].exists)
        let rating = app.otherElements["place-rating-slider"]
        XCTAssertTrue(rating.waitForExistence(timeout: 3))
        XCTAssertFalse(rating.isEnabled)

        let ratingScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        ratingScreenshot.name = "REC-236 automated save-flow rating demo"
        ratingScreenshot.lifetime = .keepAlways
        add(ratingScreenshot)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveMoreOptions"]
                .waitForExistence(timeout: 20)
        )
        let moreOptionsScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        moreOptionsScreenshot.name = "REC-236 automated tag and note demo"
        moreOptionsScreenshot.lifetime = .keepAlways
        add(moreOptionsScreenshot)
        let expandedMoreOptions = app.buttons["Hide more options"]
        XCTAssertTrue(expandedMoreOptions.waitForExistence(timeout: 3))
        XCTAssertFalse(expandedMoreOptions.isEnabled)
        XCTAssertFalse(app.buttons["Next"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveQuestions"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveTags"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveSubmit"]
                .waitForExistence(timeout: 16)
        )
        XCTAssertFalse(app.buttons["Check in"].isEnabled)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAddAgain"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.saveFlow.saveReview"].exists)

        app.buttons["map.headerAdd"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.add.addImport"]
                .waitForExistence(timeout: 6)
        )
        app.buttons["walkthrough.next.add.addImport"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.sendoff.mapSendoff"]
                .waitForExistence(timeout: 6)
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.feed.feedActivity"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.lists.listsScope"].exists)
    }

    func testAddWalkthroughUsesAPartialSheetAndKeepsSeeMoreOutOfFocus() {
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
        let coach = app.descendants(matching: .any)["walkthrough.add.addSearch"]
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        let addHeader = app.staticTexts["add a place"].firstMatch
        XCTAssertTrue(addHeader.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(addHeader.frame.minY, app.frame.height * 0.2)
        XCTAssertFalse(app.buttons["See more"].exists)
        XCTAssertFalse(app.buttons["Close add place"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 partial unskippable Add walkthrough"
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
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveStatus"]
                .waitForExistence(timeout: 14)
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.add.addPlace"].exists)
        let checkInChoice = app.buttons["check in"]
        let wannaGoChoice = app.buttons["wanna go"]
        XCTAssertEqual(checkInChoice.value as? String, "not selected")
        XCTAssertEqual(wannaGoChoice.value as? String, "not selected")
        XCTAssertFalse(app.buttons["continue to details"].exists)
        wannaGoChoice.tap()
        XCTAssertFalse(app.buttons["continue to details"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveDate"]
                .waitForExistence(timeout: 4)
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveMoreOptions"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(app.buttons["Next"].exists)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveQuestions"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveTags"]
                .waitForExistence(timeout: 20)
        )

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.saveFlow.saveSubmit"]
                .waitForExistence(timeout: 16)
        )
        let saveButton = app.buttons["Add to Wanna"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled)

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.map.mapAddAgain"]
                .waitForExistence(timeout: 12)
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.saveFlow.saveReview"].exists)
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
        XCTAssertFalse(
            memoryCoach.waitForExistence(timeout: 1),
            "The place-memory chapter is dormant in the shortened NUX."
        )
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.placeDetail.placeRatings"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["walkthrough.feed.feedActivity"].exists)
        if !memoryCoach.exists { return }

        XCTAssertTrue(memoryCoach.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Open the place memory"].exists)
        let openPlace = app.buttons["map.placeMemory.open"]
        XCTAssertTrue(openPlace.isHittable)
        XCTAssertFalse(app.buttons["Previous walkthrough step"].exists)
        XCTAssertFalse(app.buttons["walkthrough.next.map.mapMemory"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)
        XCTAssertLessThan(memoryCoach.frame.maxY, app.buttons["Map"].frame.minY)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-236 seeded place memory fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        openPlace.tap()
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

        XCTAssertTrue(
            app.descendants(matching: .any)["walkthrough.feed.feedActivity"]
                .waitForExistence(timeout: 8)
        )
        XCTAssertTrue(app.buttons["Feed"].isSelected)
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

        XCTAssertFalse(app.buttons["walkthrough.dismiss.deviceFeatures"].exists)
        XCTAssertFalse(app.buttons["Dismiss walkthrough"].exists)

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

        complete.tap()
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

    func testFeedHeaderFloatsAbovePlacesAndPeopleContent() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderInitialTab",
            "discover"
        ]
        app.launch()

        let placeSearch = app.buttons["feed.searchLauncher"]
        let addButton = app.buttons["feed.headerAdd"]
        let feedSectionButtons = app.buttons.matching(
            NSPredicate(format: "label == %@", "Feed section")
        )
        let placesButton = feedSectionButtons.element(boundBy: 0)
        let peopleButton = feedSectionButtons.element(boundBy: 1)

        XCTAssertTrue(placeSearch.waitForExistence(timeout: 6))
        XCTAssertTrue(addButton.isHittable)
        XCTAssertEqual(feedSectionButtons.count, 2)
        XCTAssertTrue(placesButton.isSelected)
        XCTAssertLessThan(placeSearch.frame.maxY, placesButton.frame.minY)
        XCTAssertEqual(placesButton.frame.midY, addButton.frame.midY, accuracy: 2)

        let initialSearchY = placeSearch.frame.minY
        let initialControlsY = placesButton.frame.minY
        app.swipeUp()

        XCTAssertTrue(placeSearch.isHittable)
        XCTAssertTrue(addButton.isHittable)
        XCTAssertEqual(placeSearch.frame.minY, initialSearchY, accuracy: 2)
        XCTAssertEqual(placesButton.frame.minY, initialControlsY, accuracy: 2)

        peopleButton.tap()
        let peopleSearch = app.textFields["Search people"]
        XCTAssertTrue(peopleSearch.waitForExistence(timeout: 4))
        XCTAssertTrue(peopleButton.isSelected)
        XCTAssertLessThan(peopleSearch.frame.maxY, peopleButton.frame.minY)
        XCTAssertTrue(addButton.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-281 floating Feed header on People"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCommentsEdgeSwipeReturnsToPreviousFeedPage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
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
            "-WanderDisableWalkthroughs",
            "-WanderMapSearchQuery",
            "coffee"
        ]
        app.launch()

        let searchField = app.textFields["map.searchField"]
        let cancelButton = app.buttons["map.searchCancel"]
        let typeaheadPanel = app.otherElements["map.typeaheadPanel"]
        let keyboard = app.keyboards.firstMatch

        XCTAssertTrue(searchField.waitForExistence(timeout: 4))
        if !cancelButton.waitForExistence(timeout: 2) {
            searchField.tap()
        }
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        XCTAssertTrue(typeaheadPanel.waitForExistence(timeout: 4))
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }

        XCTAssertGreaterThan(searchField.frame.minY, 44)
        XCTAssertLessThan(typeaheadPanel.frame.maxY, searchField.frame.minY)
        XCTAssertLessThan(searchField.frame.maxY, keyboard.frame.minY)
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

    func testMapPlaceProfileBackButtonCollapsesToSelectedCompactCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace",
            "Woodcat Coffee"
        ]
        app.launch()

        let compactCard = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(compactCard.waitForExistence(timeout: 8))
        XCTAssertTrue(compactCard.label.contains("Woodcat Coffee"))
        compactCard.tap()

        let ratings = app.staticTexts["Ratings"]
        XCTAssertTrue(ratings.waitForExistence(timeout: 5))
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        let expandedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedScreenshot.name = "Place profile expanded after compact card tap"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)

        backButton.tap()
        XCTAssertTrue(ratings.waitForNonExistence(timeout: 3))
        let restoredCompactCard = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(restoredCompactCard.waitForExistence(timeout: 3))
        XCTAssertTrue(restoredCompactCard.label.contains("Woodcat Coffee"))
        XCTAssertTrue(app.buttons["map.headerAdd"].isHittable)

        let collapsedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        collapsedScreenshot.name = "Place profile collapsed after back button"
        collapsedScreenshot.lifetime = .keepAlways
        add(collapsedScreenshot)
    }

    func testSettingsUsesFullPageProfileOverlayAndInteractiveEdgeSwipe() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
            "-WanderUseDemoFixtures",
            "-WanderInitialTab",
            "profile",
        ]
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 8))
        settingsButton.tap()

        let settingsScreen = app.descendants(matching: .any)["settings.screen"]
        XCTAssertTrue(settingsScreen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Settings"].exists)
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        XCTAssertLessThan(backButton.frame.midX, app.frame.midX)
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertFalse(app.buttons["Profile"].isHittable)

        let fullPageScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fullPageScreenshot.name = "Settings full-page Profile overlay"
        fullPageScreenshot.lifetime = .keepAlways
        add(fullPageScreenshot)

        let resources = app.descendants(matching: .any)["settings.resources"]
        for _ in 0..<8 where !resources.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(resources.isHittable)

        let resourcesScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resourcesScreenshot.name = "Settings Resources unobstructed"
        resourcesScreenshot.lifetime = .keepAlways
        add(resourcesScreenshot)

        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
        leftEdge.press(
            forDuration: 0.1,
            thenDragTo: rightSide,
            withVelocity: .slow,
            thenHoldForDuration: 0.1
        )

        XCTAssertTrue(settingsScreen.waitForNonExistence(timeout: 3))
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Profile"].isHittable)
    }

    func testFloatingPlaceActionsStayVisibleAndOpenThePreselectedLegacyEditor() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Woodcat Coffee",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkInAgain = app.buttons["place-profile.floating-action.checkIn"]
        let editHistory = app.buttons["place-profile.floating-action.editHistory"]
        XCTAssertTrue(checkInAgain.waitForExistence(timeout: 5))
        XCTAssertTrue(editHistory.waitForExistence(timeout: 2))
        XCTAssertTrue(checkInAgain.isHittable)
        XCTAssertTrue(editHistory.isHittable)

        let topScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        topScreenshot.name = "Floating place actions at profile top"
        topScreenshot.lifetime = .keepAlways
        add(topScreenshot)

        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(checkInAgain.isHittable)
        XCTAssertTrue(editHistory.isHittable)

        let deepScrollScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        deepScrollScreenshot.name = "Floating place actions after deep scroll"
        deepScrollScreenshot.lifetime = .keepAlways
        add(deepScrollScreenshot)

        checkInAgain.tap()
        let slider = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
    }

    func testFirstMapCheckInUsesAttachedEditorAndRestoresItsDraft() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        checkIn.tap()

        let attachedTray = app.otherElements["place-profile.attached-check-in"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertTrue(app.buttons["save.checkInDateDisclosure"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        XCTAssertTrue(app.staticTexts["Griffith Observatory Trail"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        note.tap()
        note.typeText("Sunset draft")

        app.buttons["Close"].tap()
        XCTAssertFalse(attachedTray.waitForExistence(timeout: 2))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let restoredNote = app.textFields["save.note"]
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 3))
        let restoredNoteHeading = app.staticTexts["a note for future you"]
        XCTAssertTrue(restoredNoteHeading.isHittable)
        XCTAssertTrue(restoredNote.isHittable)
        XCTAssertEqual(
            restoredNote.value as? String,
            "Sunset draft"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "First Map check-in attached editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFirstMapWannaExpandsAttachedEditorAndRestoresItsDraft() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        wanna.tap()

        let attachedTray = app.otherElements["place-profile.attached-wanna"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Add to Wanna"].exists)
        XCTAssertTrue(app.buttons["Add a Wanna go date"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        XCTAssertTrue(app.staticTexts["Griffith Observatory Trail"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        note.tap()
        note.typeText("Wanna sunset draft")

        app.buttons["save.close"].tap()
        XCTAssertFalse(attachedTray.waitForExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
        wanna.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let restoredNote = app.textFields["save.note"]
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 3))
        let restoredNoteHeading = app.staticTexts["a note for future you"]
        XCTAssertTrue(restoredNoteHeading.isHittable)
        XCTAssertTrue(restoredNote.isHittable)
        XCTAssertEqual(
            restoredNote.value as? String,
            "Wanna sunset draft"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "First Map Wanna attached editor"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["save.close"].tap()
        XCTAssertTrue(checkIn.isHittable)
        checkIn.tap()

        let switchedTray = app.descendants(matching: .any)["place-profile.attached-check-in"]
        XCTAssertTrue(switchedTray.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        let preservedNote = app.textFields["save.note"]
        XCTAssertTrue(preservedNote.waitForExistence(timeout: 3))
        XCTAssertEqual(
            preservedNote.value as? String,
            "Wanna sunset draft"
        )
    }

    func testMapWannaAndSaveRespondToSinglePhysicalTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        XCTAssertTrue(wanna.isHittable)
        wanna.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let attachedTray = app.otherElements["place-profile.attached-wanna"].firstMatch
        XCTAssertTrue(
            attachedTray.waitForExistence(timeout: 4),
            "One physical tap should open the Wanna editor."
        )

        let save = attachedTray.buttons["Add to Wanna"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            attachedTray.waitForNonExistence(timeout: 4),
            "One physical tap should submit and dismiss the Wanna editor."
        )
        XCTAssertTrue(app.buttons["place-profile.floating-action.wanna"].isSelected)
    }

    func testMapCheckInRespondsToSinglePhysicalTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            app.otherElements["place-profile.attached-check-in"].firstMatch
                .waitForExistence(timeout: 4),
            "One physical tap should open the Check in editor."
        )
    }

    func testMapCheckInSaveWorksWithFocusedNoteAndVisibleKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraLarge"
        ]
        app.launch()

        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 5))
        XCTAssertTrue(checkIn.isHittable)
        checkIn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let attachedTray = app.otherElements["place-profile.attached-check-in"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        note.tap()
        note.typeText("Keyboard-visible check-in")

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 3))

        let keyboardTutorialContinue = app.buttons["Continue"]
        if keyboardTutorialContinue.waitForExistence(timeout: 1) {
            keyboardTutorialContinue.tap()
        }

        let save = attachedTray.buttons["Check in"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        save.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(
            keyboard.waitForNonExistence(timeout: 4),
            "The same Save tap should intentionally dismiss the keyboard."
        )
        XCTAssertTrue(
            attachedTray.waitForNonExistence(timeout: 4),
            "One physical Save tap should commit and dismiss the Check-in editor."
        )
        XCTAssertTrue(
            app.buttons["Check in again"].firstMatch.waitForExistence(timeout: 4),
            "The completed Check-in should update the place action exactly once."
        )
    }

    func testAttachedWannaSheetCanExpandCollapseAndDismissFromItsNativeGrabber() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Griffith Observatory Trail",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        wanna.tap()

        let attachedTray = app.otherElements["place-profile.attached-wanna"].firstMatch
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))

        let compactScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compactScreenshot.name = "Attached Wanna native sheet compact"
        compactScreenshot.lifetime = .keepAlways
        add(compactScreenshot)

        func grabberCoordinate(for sheet: XCUIElement) -> XCUICoordinate {
            let normalizedY = max(
                0.02,
                min(0.98, (sheet.frame.minY - 10) / app.frame.height)
            )
            return app.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: normalizedY)
            )
        }

        let compactMinY = attachedTray.frame.minY
        let expandTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14))
        grabberCoordinate(for: attachedTray)
            .press(forDuration: 0.05, thenDragTo: expandTarget)

        let expanded = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return element.frame.minY < compactMinY - 150
            },
            object: attachedTray
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 3), .completed)

        let expandedScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        expandedScreenshot.name = "Attached Wanna sheet expanded by native grabber"
        expandedScreenshot.lifetime = .keepAlways
        add(expandedScreenshot)

        let collapseTarget = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: 0.5,
                dy: min(0.88, (compactMinY + 24) / app.frame.height)
            )
        )
        grabberCoordinate(for: attachedTray)
            .press(forDuration: 0.05, thenDragTo: collapseTarget)

        let collapsed = XCTNSPredicateExpectation(
            predicate: NSPredicate { object, _ in
                guard let element = object as? XCUIElement else { return false }
                return abs(element.frame.minY - compactMinY) <= 20
            },
            object: attachedTray
        )
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 3), .completed)

        let dismissTarget = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        grabberCoordinate(for: attachedTray)
            .press(forDuration: 0.05, thenDragTo: dismissTarget)

        XCTAssertTrue(attachedTray.waitForNonExistence(timeout: 3))
        XCTAssertTrue(wanna.waitForExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
    }

    func testExistingMapWannaExpandsAttachedEditorAndRestoresItsDraft() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Elysian Picnic Steps",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        wanna.tap()

        let attachedTray = app.descendants(matching: .any)["place-profile.attached-wanna"]
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Update Wanna"].exists)
        XCTAssertTrue(app.buttons["Remove from Wanna"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)

        let note = app.textFields["save.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertTrue(note.isHittable)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        XCTAssertEqual(
            note.value as? String,
            "Saved for a low-effort sunset picnic."
        )
        note.tap()
        note.typeText(" Updated")
        let editedNote = note.value as? String
        XCTAssertTrue(editedNote?.contains("Saved for a low-effort sunset picnic.") == true)
        XCTAssertTrue(editedNote?.contains("Updated") == true)

        app.buttons["save.close"].tap()
        XCTAssertFalse(attachedTray.waitForExistence(timeout: 2))
        XCTAssertTrue(wanna.isHittable)
        wanna.tap()

        XCTAssertTrue(attachedTray.waitForExistence(timeout: 3))
        let restoredNote = app.textFields["save.note"]
        XCTAssertTrue(restoredNote.waitForExistence(timeout: 3))
        XCTAssertEqual(
            restoredNote.value as? String,
            editedNote
        )

        app.buttons["save.close"].tap()
        let checkIn = app.buttons["place-profile.floating-action.checkIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 2))
        checkIn.tap()

        let conversionTray = app.descendants(matching: .any)["place-profile.attached-check-in"]
        XCTAssertTrue(conversionTray.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Elysian Picnic Steps"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["place-rating-slider"].exists)
        XCTAssertTrue(app.buttons["save.checkInDateDisclosure"].exists)
        XCTAssertFalse(app.staticTexts["what do you want to do?"].exists)
        let conversionNote = app.textFields["save.note"]
        XCTAssertTrue(conversionNote.waitForExistence(timeout: 3))
        XCTAssertEqual(conversionNote.value as? String, editedNote)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Existing Wanna converts to attached Check in"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEditWannaDeleteActionPreservesItsConfirmationBehavior() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderResetWalkthroughs",
            "-WanderMapPlace",
            "Elysian Picnic Steps",
            "-WanderMapSheetExpanded",
            "-WanderPlaceProfileSaveTrayV1"
        ]
        app.launch()

        let wanna = app.buttons["place-profile.floating-action.wanna"]
        XCTAssertTrue(wanna.waitForExistence(timeout: 5))
        wanna.tap()

        let attachedTray = app.descendants(matching: .any)["place-profile.attached-wanna"]
        XCTAssertTrue(attachedTray.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["Update Wanna"].exists)

        let deleteButton = attachedTray.buttons["Remove from Wanna"].firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))

        let editorScrollView = attachedTray.scrollViews.firstMatch
        XCTAssertTrue(editorScrollView.exists)
        editorScrollView.swipeUp()
        if !deleteButton.isHittable {
            editorScrollView.swipeUp()
        }
        XCTAssertTrue(deleteButton.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-361 lightweight Edit Wanna delete action"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        deleteButton.tap()
        let confirmation = app.alerts["Remove from Wanna?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmation.buttons["Remove from Wanna"].exists)
        XCTAssertTrue(confirmation.buttons["Cancel"].exists)
        confirmation.buttons["Cancel"].tap()

        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 2))
        XCTAssertTrue(attachedTray.exists)
        XCTAssertTrue(app.buttons["Update Wanna"].exists)
    }

    func testFeedInlineSearchCoversEntryEmptyResultsNavigationAndBack() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
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
        XCTAssertFalse(launcher.isHittable)
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

        let firstPlaceResult = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "rec.me rating")
        ).firstMatch
        XCTAssertTrue(firstPlaceResult.waitForExistence(timeout: 4))
        XCTAssertTrue(firstPlaceResult.isHittable)
        firstPlaceResult.tap()

        let placeBackButton = app.buttons["place-profile.back"]
        XCTAssertTrue(placeBackButton.waitForExistence(timeout: 4))
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let rightSide = app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: rightSide)
        XCTAssertTrue(placeBackButton.waitForNonExistence(timeout: 3))
        XCTAssertTrue(searchField.waitForExistence(timeout: 3))
        XCTAssertEqual(searchField.value as? String, "coffee")

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
        let statusSelector = app.staticTexts["save.statusSelector"]
        XCTAssertTrue(statusSelector.exists)
        XCTAssertTrue(checkInChoice.isSelected)
        let finalCheckIn = app.buttons["Check in"]
        XCTAssertTrue(finalCheckIn.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["continue to details"].exists)
        XCTAssertFalse(app.buttons["back"].exists)
        XCTAssertTrue(app.buttons["Hide more options"].exists)

        let disclosure = app.buttons["save.checkInDateDisclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(statusSelector.exists)
        let rating = app.descendants(matching: .any)["place-rating-slider"]
        XCTAssertTrue(rating.exists)
        let note = app.textFields["save.note"]
        XCTAssertTrue(note.exists)
        XCTAssertLessThan(statusSelector.frame.minY, rating.frame.minY)
        XCTAssertLessThan(rating.frame.minY, note.frame.minY)
        XCTAssertLessThan(note.frame.minY, disclosure.frame.minY)
        XCTAssertTrue(disclosure.isHittable)

        note.tap()
        note.typeText("Discard this draft")
        app.buttons["save.close"].tap()
        XCTAssertTrue(statusSelector.waitForNonExistence(timeout: 3))
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(statusSelector.waitForExistence(timeout: 3))
        XCTAssertNotEqual(app.textFields["save.note"].value as? String, "Discard this draft")

        app.textFields["save.note"].tap()
        app.textFields["save.note"].typeText("Check-in mode draft")
        let wannaChoice = app.buttons["wanna go"]
        XCTAssertTrue(wannaChoice.waitForExistence(timeout: 2))
        XCTAssertTrue(wannaChoice.isHittable)
        wannaChoice.tap()
        XCTAssertTrue(app.buttons["Add a Wanna go date"].waitForExistence(timeout: 2))
        XCTAssertTrue(wannaChoice.isSelected)
        XCTAssertTrue(app.buttons["Hide more options"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["place-rating-slider"].exists)
        let wannaNote = app.textFields["save.note"]
        XCTAssertNotEqual(wannaNote.value as? String, "Check-in mode draft")
        wannaNote.tap()
        wannaNote.typeText("Wanna mode draft")
        XCTAssertTrue(checkInChoice.isHittable)
        checkInChoice.tap()
        XCTAssertEqual(app.textFields["save.note"].value as? String, "Check-in mode draft")
        wannaChoice.tap()
        XCTAssertEqual(app.textFields["save.note"].value as? String, "Wanna mode draft")
        checkInChoice.tap()

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

        disclosure.tap()
        XCTAssertTrue((disclosure.value as? String)?.contains("Collapsed") == true)
        finalCheckIn.tap()
        XCTAssertTrue(statusSelector.waitForNonExistence(timeout: 5))
    }


}
