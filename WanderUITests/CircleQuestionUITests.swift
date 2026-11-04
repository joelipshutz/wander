import XCTest

@MainActor final class CircleQuestionUITests: XCTestCase {
    func testLivePlusOpensRealQuestionComposer() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
                               "-WanderUnifiedLiveUITest", "-WanderCircleQuestionLocalTest", "-WanderInitialTab", "discover"]
        app.launch()
        dismissStartupNotificationPromptIfNeeded(in: app)
        capture(app, "live-map")
        let add = app.buttons["Add a place"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20)); add.tap()
        let question = app.buttons["circleQuestion.create"]
        XCTAssertTrue(question.waitForExistence(timeout: 8)); capture(app, "live-plus"); question.tap()
        XCTAssertTrue(app.staticTexts["Ask your circle."].waitForExistence(timeout: 8))
        capture(app, "composer-entry")
        XCTAssertFalse(app.staticTexts["Astir Circle Question"].exists)
    }

    func testMultiPlaceBasketSurvivesNextAndBack() {
        let app = review("recommend")
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "circleQuestion.place."))
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 10))
        rows.element(boundBy: 0).tap(); rows.element(boundBy: 1).tap()
        let next = app.buttons["Next · 2 selected"]
        XCTAssertTrue(next.exists); capture(app, "multi-selected"); next.tap()
        XCTAssertTrue(app.staticTexts["A little local\nknowledge."].waitForExistence(timeout: 5))
        capture(app, "local-knowledge")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Remove ")).count, 2)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
    }

    func testEntireListCanBeSelectedThenEdited() {
        let app = review("recommend")
        app.segmentedControls.buttons["Lists"].tap()
        let list = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Choose all or a few")).firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5)); list.tap()
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Select all ")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "circleQuestion.place.")).firstMatch
        XCTAssertTrue(row.exists); row.tap()
        capture(app, "lists-selected")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Next · ")).firstMatch.exists)
    }

    func testSelectedPlacesArePostedBackToQuestion() {
        let app = review("question")
        let recommend = app.buttons["Recommend places"]
        XCTAssertTrue(recommend.waitForExistence(timeout: 10)); recommend.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "circleQuestion.place."))
        XCTAssertTrue(rows.element(boundBy: 0).waitForExistence(timeout: 5))
        rows.element(boundBy: 0).tap(); rows.element(boundBy: 1).tap()
        app.buttons["Next · 2 selected"].tap()
        let send = app.buttons["Send 2 recommendations"]
        if !send.isHittable { app.swipeUp() }
        XCTAssertTrue(send.isHittable); send.tap()
        XCTAssertTrue(app.staticTexts["Good places, passed on."].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Recommend places"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2 places recommended"].exists)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testFeedDoesNotShowPinDurationOrExpiredCopy() {
        let app = review("expired")
        XCTAssertTrue(app.staticTexts["Your circle"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "expired")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "days on")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Wanna"].exists)
    }

    @discardableResult private func review(_ scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderCircleQuestionReview", "-CircleQuestionScene", scene,
                               "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs"]
        app.launch(); return app
    }
}
