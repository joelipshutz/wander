import XCTest

/// Production drawer actions exercised with local fixtures; no invitations are sent.
@MainActor
final class LiveDrawerActionsUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHeaderActionsOpenExistingDestinationsAndRestoreDrawer() {
        let app = launch()
        assertHeaderLayout(in: app)
        XCTAssertFalse(app.staticTexts["Bring The People Whose Taste You Trust."].exists)
        let handle = drawer(in: app)
        let originalValue = handle.value as? String
        let originalY = handle.frame.minY
        capture("header", in: app)

        app.buttons["live.utility.events"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        XCTAssertTrue(app.descendants(matching: .any)["events.comingSoon"].firstMatch.exists)
        done.tap()
        assertRestoredDrawer("half expanded", value: originalValue, minY: originalY, in: app)

        openAndCloseInvite(in: app)
        assertRestoredDrawer("half expanded", value: originalValue, minY: originalY, in: app)
        capture("returned", in: app)
    }

    func testCollapsedHeaderActionsRemainTappable() {
        let app = launch()
        let handle = drawer(in: app)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.90)))
        waitForDrawer("collapsed", in: app)
        assertHeaderLayout(in: app)
        let value = handle.value as? String
        let minY = handle.frame.minY
        capture("collapsed", in: app)

        app.buttons["live.utility.events"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 30))
        done.tap()
        assertRestoredDrawer("collapsed", value: value, minY: minY, in: app)
        openAndCloseInvite(in: app)
        assertRestoredDrawer("collapsed", value: value, minY: minY, in: app)
    }

    func testAccessibilityTextKeepsHeaderActionsSeparate() {
        let app = launch(largeText: true)
        assertHeaderLayout(in: app)
        let handle = drawer(in: app)
        XCTAssertTrue((handle.value as? String)?.contains("All Time") == true)
        capture("accessibility-text", in: app)
        openAndCloseInvite(in: app)
        waitForDrawer("half expanded", in: app)
        assertHeaderLayout(in: app)
    }

    func testEventsStayHiddenOutsideEligibleMetro() {
        let app = launch(extraArguments: ["-WanderHomeMetroUITest", "new-york"])
        XCTAssertFalse(app.buttons["live.utility.events"].exists)
        waitHittable(app.buttons["live.utility.invite"])
        XCTAssertEqual(app.buttons["live.utility.invite"].label, "Invite People To Astir")
        openAndCloseInvite(in: app)
        waitForDrawer("half expanded", in: app)
        XCTAssertFalse(app.buttons["live.utility.events"].exists)
    }

    func testIncomingProfileLinkDismissesInviteBeforeOpeningProfile() {
        let app = launch()
        app.buttons["live.utility.invite"].tap()
        let inviteClose = app.buttons["invite.close"]
        waitHittable(inviteClose)

        app.open(URL(string: "recme://profiles/user_maya")!)
        let open = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        XCTAssertTrue(inviteClose.waitForNonExistence(timeout: 30))
        let profileBack = app.buttons["profile.back"]
        waitHittable(profileBack)
        capture("invite-to-profile-link", in: app)

        profileBack.tap()
        XCTAssertTrue(profileBack.waitForNonExistence(timeout: 30))
        waitHittable(app.buttons["live.utility.invite"])
        XCTAssertFalse(inviteClose.exists)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
    }

    private func launch(largeText: Bool = false, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
            "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
            "-astir.live.introduction.v1.user_joe.acknowledged", "YES",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName",
            largeText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"
        ] + extraArguments
        app.launch()
        addTeardownBlock { app.terminate() }
        XCTAssertTrue(app.buttons["live.draw"].waitForExistence(timeout: 30))
        waitForDrawer("half expanded", in: app)
        waitHittable(app.buttons["live.utility.invite"])
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = self.drawer(in: app).value as? String ?? ""
            return !value.isEmpty && !value.contains("Finding activities")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 30), .completed)
        return app
    }

    private func assertHeaderLayout(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let events = app.buttons["live.utility.events"]
        let invite = app.buttons["live.utility.invite"]
        waitHittable(events)
        waitHittable(invite)
        let handle = drawer(in: app)
        XCTAssertTrue(handle.exists, file: file, line: line)
        XCTAssertEqual(events.label, "Upcoming Events", file: file, line: line)
        XCTAssertEqual(invite.label, "Invite People To Astir", file: file, line: line)
        for button in [events, invite] {
            // Allow subpixel rounding when XCTest converts frames to screen coordinates.
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.01, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.01, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.minY, handle.frame.minY - 1, file: file, line: line)
            XCTAssertLessThanOrEqual(button.frame.maxY, handle.frame.maxY + 1, file: file, line: line)
        }
        XCTAssertLessThan(events.frame.maxX, handle.frame.midX - 44, file: file, line: line)
        XCTAssertGreaterThan(invite.frame.minX, handle.frame.midX + 44, file: file, line: line)
        XCTAssertEqual(events.frame.midY, invite.frame.midY, accuracy: 1, file: file, line: line)
        XCTAssertFalse(events.frame.intersects(invite.frame), file: file, line: line)
        // Both shortcuts remain separate accessibility buttons outside the feed viewport.
        let feed = app.scrollViews["feed.places.scroll"]
        XCTAssertFalse(feed.buttons["live.utility.invite"].exists, file: file, line: line)
        XCTAssertFalse(feed.buttons["live.utility.events"].exists, file: file, line: line)
    }

    private func openAndCloseInvite(in app: XCUIApplication) {
        waitHittable(app.buttons["live.utility.invite"])
        app.buttons["live.utility.invite"].tap()
        XCTAssertTrue(app.staticTexts["Invite People"].waitForExistence(timeout: 30))
        let close = app.buttons["invite.close"]
        waitHittable(close)
        // The local FakeContactProvider is already authorized. Do not request access or select contacts.
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 30))
    }

    private func assertRestoredDrawer(_ state: String, value: String?, minY: CGFloat, in app: XCUIApplication) {
        waitForDrawer(state, in: app)
        waitHittable(app.buttons["live.utility.invite"])
        XCTAssertEqual(drawer(in: app).value as? String, value)
        XCTAssertEqual(drawer(in: app).frame.minY, minY, accuracy: 2)
        XCTAssertTrue(app.tabBars.buttons["Live"].isSelected)
    }

    private func drawer(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["live.drawerHandle"].firstMatch
    }

    private func waitForDrawer(_ state: String, in app: XCUIApplication) {
        let handle = drawer(in: app)
        XCTAssertTrue(handle.waitForExistence(timeout: 30))
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Activity drawer, \(state)"), object: handle)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
    }

    private func waitHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-654-\(Int(app.frame.width))x\(Int(app.frame.height))-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
