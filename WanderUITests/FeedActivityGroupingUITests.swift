import XCTest

final class FeedActivityGroupingUITests: XCTestCase {
    @MainActor
    func testAuthenticatedRootSurvivesRepeatedColdLaunches() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderInitialTab", "discover"
        ]
        for _ in 0..<3 {
            app.launch()
            XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 20))
            let exited = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in app.state != .runningForeground },
                object: nil
            )
            exited.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [exited], timeout: 3), .completed)
            app.terminate()
        }
    }

    @MainActor
    func testCombinedActivityExpandsInOrderCollapsesAndOpensOriginalPost() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedGroupingUITest", "-WanderInitialTab", "discover"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 15))
        let disclosure = app.buttons["feed.activity.fixture-feed-group-wanna.disclosure"]
        for _ in 0..<5 where !disclosure.isHittable { app.swipeUp() }
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        capture("feed-group-collapsed")

        let wanna = app.buttons["feed.activity.fixture-feed-group-wanna.sequenceEvent"]
        let visit = app.buttons["feed.activity.fixture-feed-maya-been-bar-nido.sequenceEvent"]
        let list = app.buttons["feed.activity.fixture-feed-group-list.sequenceEvent"]
        XCTAssertFalse(wanna.exists)
        disclosure.tap()
        XCTAssertTrue(wanna.waitForExistence(timeout: 3))
        XCTAssertEqual(disclosure.value as? String, "Expanded, 3 activities")
        XCTAssertLessThan(wanna.frame.minY, visit.frame.minY)
        XCTAssertLessThan(visit.frame.minY, list.frame.minY)
        for _ in 0..<3 where !list.isHittable { app.swipeUp() }
        capture("feed-group-expanded")

        for _ in 0..<3 where !disclosure.isHittable { app.swipeDown() }
        disclosure.tap()
        // The disclosure removes these rows with an opacity transition. Wait
        // for that removal before another tap can reverse the same animation.
        XCTAssertTrue(wanna.waitForNonExistence(timeout: 3))
        XCTAssertEqual(disclosure.value as? String, "Collapsed, 3 activities")
        disclosure.tap()
        for _ in 0..<3 where !wanna.isHittable { app.swipeUp() }
        wanna.tap()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 5))
        capture("feed-group-original-post")
    }

    @MainActor
    func testNotificationOpensPostWithArrowComposerAndBackReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "map"
        ]
        app.launch()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 20))
        XCTAssertFalse(app.navigationBars["comments"].exists)
        XCTAssertFalse(app.staticTexts["Start the conversation"].exists)
        XCTAssertFalse(app.buttons["Post"].exists)
        XCTAssertFalse(send.isEnabled)
        XCTAssertGreaterThanOrEqual(send.frame.width, 44)
        XCTAssertGreaterThanOrEqual(send.frame.height, 44)
        capture("REC-543-post-empty")
        let composer = app.descendants(matching: .any)["activity.comment.input"].firstMatch
        composer.tap()
        composer.typeText("Meet you here next time!")
        XCTAssertTrue(send.isEnabled)
        capture("REC-543-post-composer")
        send.tap()
        XCTAssertTrue(app.staticTexts["Meet you here next time!"].waitForExistence(timeout: 5))
        capture("REC-543-post-comment")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(send.exists)
        capture("REC-543-back-to-feed")
    }

    @MainActor
    func testCommentHeartLikesAndUnlikesWithoutChangingActivityLike() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "map"
        ]
        app.launch()
        let send = app.buttons["activity.comment.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 20))
        let rating = app.staticTexts["comments.activity.postcard.rating.value"]
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        XCTAssertEqual(rating.label, "Rating 4 out of 5")
        XCTAssertTrue(rating.isHittable)
        XCTAssertGreaterThan(rating.frame.width, 0)
        capture("REC-564-postcard-rating")
        let composer = app.textViews["activity.comment.input"]
        let frame = composer.frame
        let tapOffset = CGVector(dx: 0.5, dy: 0.25)
        let tapPoint = CGPoint(x: frame.midX, y: frame.minY + frame.height * tapOffset.dy)
        guard composer.isHittable, !frame.isNull, !frame.isInfinite, !frame.isEmpty,
              [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
              app.frame.contains(frame), frame.contains(tapPoint) else {
            XCTFail("Expected a visible native comment text view before the single focus tap")
            return
        }
        let scrollbars = composer.descendants(matching: .other).matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Vertical scroll bar", "Horizontal scroll bar"))
            .allElementsBoundByIndex
        for scrollbar in scrollbars where scrollbar.frame.contains(tapPoint) {
            XCTFail("The single comment focus tap must avoid native scrollbar frames")
            return
        }
        let focusGeometry = XCTAttachment(string: "composerFrame=\(frame); tapPoint=\(tapPoint); scrollbarFrames=\(scrollbars.map(\.frame)); keyboardPresentBeforeTap=\(app.keyboards.firstMatch.exists)")
        focusGeometry.name = "REC-564 single native comment focus geometry"
        focusGeometry.lifetime = .keepAlways
        add(focusGeometry)
        composer.coordinate(withNormalizedOffset: tapOffset).tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("The single native comment tap must establish keyboard readiness before typing")
            return
        }
        composer.typeText("A place worth returning to.")
        send.tap()
        let heart = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.comment.like.")).firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        XCTAssertEqual(heart.label, "Like Comment")
        XCTAssertEqual(heart.value as? String, "0 likes")
        XCTAssertGreaterThanOrEqual(heart.frame.width, 44)
        XCTAssertGreaterThanOrEqual(heart.frame.height, 44)
        let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "activity.comment.actions.")).firstMatch
        XCTAssertTrue(actions.exists)
        XCTAssertLessThanOrEqual(heart.frame.maxX, actions.frame.minX + 1)
        XCTAssertEqual(heart.frame.midY, actions.frame.midY, accuracy: 1)
        XCTAssertGreaterThan(heart.frame.midX, app.frame.midX)
        let activity = app.buttons["Like Activity"].firstMatch
        let activityValue = activity.value as? String
        capture("REC-564-comment-unliked")
        heart.tap()
        XCTAssertEqual(heart.label, "Unlike Comment")
        XCTAssertEqual(heart.value as? String, "1 Like")
        XCTAssertEqual(activity.value as? String, activityValue)
        capture("REC-564-comment-liked")
        heart.tap()
        XCTAssertEqual(heart.label, "Like Comment")
        XCTAssertEqual(heart.value as? String, "0 likes")
        capture("REC-564-comment-unliked-again")
    }

    @MainActor
    func testNotificationPostEdgeSwipeReturnsFeed() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture", "-WanderUseStorefrontFixtures", "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs", "-WanderNotificationPostUITest", "-WanderInitialTab", "profile"
        ]
        app.launch()
        XCTAssertTrue(app.buttons["activity.comment.send"].waitForExistence(timeout: 20))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.buttons["feed.searchLauncher"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["activity.comment.send"].exists)
    }

    @MainActor
    func testFeedRatingsStayAtTopRightForShortAndLongPlaceNames() {
        var ratingFrames: [CGRect] = []
        for longTitle in [false, true] {
            let app = launchPhotoStackFixture(extraArguments: longTitle ? ["-WanderFeedPhotoStackLongTitle"] : [])
            let title = app.buttons["feed.photo-stack.place"]
            let rating = app.staticTexts["feed.photo-stack.postcard.rating.value"]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            XCTAssertTrue(rating.exists)
            XCTAssertEqual(rating.label, longTitle ? "Rating 4 out of 5" : "Rating 5 out of 5")
            XCTAssertGreaterThan(rating.frame.minX, title.frame.minX)
            XCTAssertGreaterThan(rating.frame.midX, app.frame.midX)
            XCTAssertGreaterThanOrEqual(rating.frame.minX, title.frame.maxX)
            XCTAssertEqual(rating.frame.minY, title.frame.minY, accuracy: 22,
                           "The rating stays beside the first title line, including when the name wraps.")
            ratingFrames.append(rating.frame)

            let actor = app.buttons["feed.photo-stack.actor"]
            XCTAssertTrue(actor.exists)
            XCTAssertEqual(actor.label, "Ryan Lieblein checked in, just now")
            XCTAssertFalse(actor.label.localizedCaseInsensitiveContains("your activity"))
            XCTAssertFalse(actor.label.localizedCaseInsensitiveContains("someone you follow"))
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "your activity", "someone you follow"
            )).firstMatch.exists)
            capture(longTitle ? "REC-641-long-title" : "REC-641-short-title")
            app.terminate()
        }
        XCTAssertEqual(ratingFrames[0].minY, ratingFrames[1].minY, accuracy: 2)
        XCTAssertEqual(ratingFrames[0].maxX, ratingFrames[1].maxX, accuracy: 2)
    }

    @MainActor
    func testFeedPhotoStackPagesAndReturnsWithoutOpeningProfileOrPlace() {
        let app = launchPhotoStackFixture(extraArguments: ["-WanderFeedPhotoStackLongTitle"])
        let photos = app.buttons["feed.photo-stack.postcard.photos"]
        XCTAssertTrue(photos.waitForExistence(timeout: 10))
        XCTAssertEqual(photos.value as? String, "3 photos")
        XCTAssertGreaterThanOrEqual(photos.frame.width, 44)
        XCTAssertGreaterThanOrEqual(photos.frame.height, 44)
        let actor = app.buttons["feed.photo-stack.actor"]
        XCTAssertGreaterThanOrEqual(photos.frame.minX, actor.frame.maxX)
        photos.tap()

        let back = app.buttons["activity.photos.back"]
        let position = app.staticTexts["activity.photos.position"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        XCTAssertEqual(position.label, "1 of 3")
        XCTAssertFalse(app.descendants(matching: .any)["activity.photos.unavailable"].exists)
        XCTAssertFalse(app.staticTexts["feed.photo-stack.profile.opened"].exists)
        XCTAssertFalse(app.staticTexts["feed.photo-stack.place.opened"].exists)
        capture("REC-641-photos-first")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        )
        let secondPhoto = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 of 3"), object: position)
        XCTAssertEqual(XCTWaiter.wait(for: [secondPhoto], timeout: 5), .completed)
        capture("REC-641-photos-second")
        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "The photo viewer must dismiss before Feed controls are used.")
        XCTAssertTrue(photos.exists)
        XCTAssertTrue(photos.isHittable)
        XCTAssertFalse(back.exists)

        actor.tap()
        XCTAssertTrue(app.staticTexts["feed.photo-stack.profile.opened"].waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
        app.buttons["feed.photo-stack.destination.done"].tap()
        let place = app.buttons["feed.photo-stack.place"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        place.tap()
        XCTAssertTrue(app.staticTexts["feed.photo-stack.place.opened"].waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
    }

    @MainActor
    func testFeedOmitsPhotoStackWhenSaveHasNoPhotos() {
        let app = launchPhotoStackFixture(extraArguments: ["-WanderFeedPhotoStackNoPhotos"])
        XCTAssertTrue(app.buttons["feed.photo-stack.actor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["feed.photo-stack.postcard.photos"].exists)
        XCTAssertTrue(app.staticTexts["feed.photo-stack.postcard.rating.value"].exists)
        capture("REC-641-no-photos")
    }

    @MainActor
    func testActivityMenuPreservesReportForNonMutualAuthor() {
        let app = launchPhotoStackFixture(extraArguments: ["-WanderActivityReportMenuUITest"])
        let actions = app.buttons["activity.65200000-0000-0000-0000-000000000001.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        for _ in 0..<5 where !actions.isHittable { app.swipeUp() }
        XCTAssertTrue(actions.isHittable)
        XCTAssertEqual(actions.frame.height, 44, accuracy: 0.001)
        actions.tap()
        let report = app.buttons["Report Activity"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reply Privately"].exists)
        capture("REC-652-nonmutual-activity-menu")
        report.tap()
        let submit = app.buttons["communityReport.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "Reporting must still require a reason before submission.")
        capture("REC-652-existing-report-sheet")
        // Do not submit a moderation report from this fixture.
    }

    @MainActor
    private func launchPhotoStackFixture(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs",
            "-WanderFeedPhotoStackUITest", "-AppleInterfaceStyle", "Dark"
        ] + extraArguments
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
