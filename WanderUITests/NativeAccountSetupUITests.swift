import XCTest

/// These journeys use the real production views with the native review host's
/// local auth/profile/follow providers. They make no account or member requests.
@MainActor
final class NativeAccountSetupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testProfilePreviewRetainsIdentityAcrossBackground() {
        let app = launchReview("identity")
        let name = app.textFields["onboarding.identity.name"]
        let username = app.textFields["onboarding.identity.username"]
        XCTAssertTrue(name.waitForExistence(timeout: 12))
        name.tap()
        name.typeText("Jordan Lee")
        username.tap()
        username.typeText("jordan_review")
        XCTAssertTrue(app.staticTexts["Username available"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(name.value as? String, "Jordan Lee")
        XCTAssertEqual(username.value as? String, "jordan_review")
        dismissKeyboardIfPresent(in: app)
        XCTAssertTrue(app.staticTexts["Jordan Lee"].exists)
        XCTAssertTrue(app.buttons["onboarding.identity.continue"].isEnabled)
        keepScreenshot("N08-filled", app: app)
        app.buttons["onboarding.identity.continue"].tap()
        XCTAssertTrue(app.buttons["onboarding.location.primary"].waitForExistence(timeout: 10))
    }

    func testNativeDarkSetupCaptureInventory() {
        for (route, screen) in [("identity", "N08"), ("location", "N09"), ("contacts", "N10"), ("friends", "N11"), ("notifications", "N12"), ("friends-empty", "N33"), ("friends-failure", "N34")] {
            let app = launchReview(route, extraArguments: ["-WanderBypassProductUpsellFrequencyCap"])
            let primary = app.buttons[route == "notifications" ? "productUpsell.primary" : route == "identity" ? "onboarding.identity.continue" : route == "location" ? "onboarding.location.primary" : route == "contacts" ? "onboarding.contacts.findFriends" : "onboarding.friends.continue"]
            XCTAssertTrue(primary.waitForExistence(timeout: 15))
            XCTAssertTrue(primary.isHittable)
            XCTAssertLessThanOrEqual(primary.frame.maxY, app.frame.maxY)
            keepScreenshot(screen, app: app, settleSeconds: route == "location" ? 4.5 : 1.8)
        }
    }

    func testProfilePhotoPickerCropAndValidation() {
        let app = launchReview("identity")
        let name = app.textFields["How friends know you"]
        let username = app.textFields["your_username"]
        let continueButton = app.buttons["onboarding.identity.continue"]
        XCTAssertTrue(name.waitForExistence(timeout: 12))
        XCTAssertFalse(continueButton.isEnabled)

        name.tap()
        name.typeText("Jordan Lee")
        username.tap()
        username.typeText("jordan_review")
        XCTAssertTrue(app.staticTexts["Username available"].waitForExistence(timeout: 8))
        dismissKeyboardIfPresent(in: app)
        XCTAssertTrue(app.staticTexts["Jordan Lee"].exists)
        XCTAssertEqual(app.staticTexts["@jordan_review"].label, "@jordan_review")
        XCTAssertTrue(continueButton.isEnabled, "Photo stays optional as in current main.")
        keepScreenshot("N08-filled", app: app)

        replaceText(in: username, with: "taken")
        XCTAssertTrue(app.staticTexts["That username is taken"].waitForExistence(timeout: 8))
        dismissKeyboardIfPresent(in: app)
        XCTAssertFalse(continueButton.isEnabled)
        reveal(app.staticTexts["That username is taken"], in: app)
        keepScreenshot("N35", app: app)
        replaceText(in: username, with: "jordan_review")
        XCTAssertTrue(app.staticTexts["Username available"].waitForExistence(timeout: 8))
        dismissKeyboardIfPresent(in: app)

        let photo = app.buttons["onboarding.identity.photo"]
        reveal(photo, in: app, direction: .down)
        XCTAssertEqual(photo.label, "Add an optional profile photo")
        photo.tap()
        // The recording setup imports the app's public-safe bundled avatar
        // artwork into this simulator's Photos library. Selection and crop both
        // run through the same system picker and production crop view as users.
        XCTAssertTrue(waitFor(NSPredicate(format: "hittable == false"), on: photo, timeout: 6))
        // The iOS 26 system picker exposes photo tiles as images.
        let firstPhoto = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 8))
        keepSystemScreenshot("N08-photo-picker")
        // PhotoKit exposes the correct visible frame but no synthesized hit
        // point for this remote image tile. Tap its observed frame center.
        firstPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Crop photo"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Choose"].isEnabled)
        keepScreenshot("N67", app: app)
        app.buttons["Choose"].tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Change profile photo"), on: photo, timeout: 6))
        XCTAssertTrue(continueButton.isEnabled, "A successfully chosen crop preserves valid identity input.")
        keepScreenshot("N08-photo-chosen", app: app, settleSeconds: 1)
    }

    func testFollowingOneMemberAndSearchPreservePerRowState() {
        let app = launchReview("friends")
        let mina = app.buttons["onboarding.friends.follow.native-review-mina"]
        let theo = app.buttons["onboarding.friends.follow.native-review-theo"]
        let jules = app.buttons["onboarding.friends.follow.native-review-jules"]
        XCTAssertTrue(mina.waitForExistence(timeout: 12))
        XCTAssertEqual(mina.label, "Follow Mina Park")
        mina.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Following Mina Park"), on: mina))
        XCTAssertFalse(mina.isEnabled)
        XCTAssertTrue(theo.isEnabled, "Following one person must not select all rows.")
        XCTAssertTrue(jules.isEnabled)

        let search = app.textFields["onboarding.friends.search"]
        search.tap()
        search.typeText("the")
        XCTAssertTrue(waitFor(NSPredicate(format: "exists == false"), on: mina))
        XCTAssertTrue(theo.waitForExistence(timeout: 6))
        XCTAssertFalse(jules.exists)
        theo.tap()
        XCTAssertTrue(waitFor(NSPredicate(format: "label == %@", "Following Theo Chen"), on: theo))
        XCTAssertFalse(theo.isEnabled)

        let clearSearch = app.buttons["Clear search"]
        XCTAssertTrue(clearSearch.exists)
        clearSearch.tap()
        XCTAssertTrue(mina.waitForExistence(timeout: 6))
        XCTAssertTrue(jules.waitForExistence(timeout: 6))
        XCTAssertEqual(mina.label, "Following Mina Park")
        XCTAssertEqual(theo.label, "Following Theo Chen")
        XCTAssertFalse(mina.isEnabled)
        XCTAssertFalse(theo.isEnabled)
        XCTAssertTrue(jules.isEnabled)
        XCTAssertTrue(app.buttons["onboarding.friends.continue"].isEnabled)
        dismissKeyboardIfPresent(in: app)
        keepScreenshot("N11-following", app: app)
    }

    func testNativeLocationAndContactsDenialsPreserveRecovery() {
        // SDK-supported resets re-arm the actual system prompts; no location
        // coordinate, permission manager, or Contacts result is mocked.
        XCUIApplication().resetAuthorizationStatus(for: .location)
        let locationApp = launchReview("location")
        let locationContinue = locationApp.buttons["onboarding.location.primary"]
        XCTAssertTrue(locationContinue.waitForExistence(timeout: 12))
        XCTAssertEqual(locationContinue.label, "Continue")
        locationContinue.tap()
        let locationAlert = permissionAlert(in: locationApp)
        XCTAssertTrue(locationAlert.exists)
        keepSystemScreenshot("N30")
        denyPermission(in: locationAlert)
        XCTAssertTrue(locationAlert.waitForNonExistence(timeout: 5))

        let deniedLocationApp = launchReview("location")
        let locationSettings = deniedLocationApp.buttons["onboarding.location.primary"]
        XCTAssertTrue(locationSettings.waitForExistence(timeout: 10))
        XCTAssertEqual(locationSettings.label, "Open Settings")
        XCTAssertTrue(deniedLocationApp.buttons["Not now"].exists)
        // The shared map entrance takes 2.2 seconds; retain its settled frame.
        keepScreenshot("N31", app: deniedLocationApp, settleSeconds: 2.5)

        XCUIApplication().resetAuthorizationStatus(for: .contacts)
        let contactsApp = launchReview("contacts", extraArguments: [
            "-WanderContactDiscoveryUITest",
            "-WanderContactDiscoverySystemPermissionTest"
        ])
        let contactsContinue = contactsApp.buttons["onboarding.contacts.findFriends"]
        XCTAssertTrue(contactsContinue.waitForExistence(timeout: 10))
        contactsContinue.tap()
        let contactsAlert = permissionAlert(in: contactsApp, required: false)
        if contactsAlert.exists {
            // iOS 26's initial Contacts prompt exposes Don't Allow and Continue.
            // Capture its actual system-rendered purpose text before any choice.
            keepSystemScreenshot("N36")
            denyPermission(in: contactsAlert)
            XCTAssertTrue(contactsAlert.waitForNonExistence(timeout: 5))
        }
        let contactsError = contactsApp.staticTexts["onboarding.contacts.error"]
        XCTAssertTrue(contactsError.waitForExistence(timeout: 10))
        XCTAssertEqual(contactsError.label, "Allow Contacts access in iOS Settings to find friends. You can still search by name.")
        XCTAssertTrue(contactsApp.buttons["onboarding.contacts.skip"].exists)
    }

    func testNotificationDenialPreservesSettingsRecovery() throws {
        let app = launchReview("notifications", extraArguments: ["-WanderBypassProductUpsellFrequencyCap"])
        let primary = app.buttons["productUpsell.primary"]
        XCTAssertTrue(primary.waitForExistence(timeout: 15))
        if primary.label == "Open Settings" {
            // Notifications has no XCUIProtectedResource reset. Re-runs keep
            // testing the denied state instead of pretending another OS prompt.
            XCTAssertTrue(app.buttons["productUpsell.secondary"].exists)
            keepScreenshot("N32", app: app, settleSeconds: 1.5)
            return
        }

        XCTAssertEqual(primary.label, "Continue")
        primary.tap()
        let alert = permissionAlert(in: app, required: false)
        guard alert.exists else {
            throw XCTSkip("Notification authorization was already granted on this simulator; reset/reinstall its local review app to record the first system request. XCTest has no notification authorization reset API.")
        }
        keepSystemScreenshot("N12-system-permission")
        denyPermission(in: alert)
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))

        let deniedApp = launchReview("notifications", extraArguments: ["-WanderBypassProductUpsellFrequencyCap"])
        let openSettings = deniedApp.buttons["productUpsell.primary"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 15))
        XCTAssertEqual(openSettings.label, "Open Settings")
        XCTAssertTrue(deniedApp.buttons["productUpsell.secondary"].exists)
        keepScreenshot("N32", app: deniedApp, settleSeconds: 1.5)
    }

    private func permissionAlert(in app: XCUIApplication, required: Bool = true) -> XCUIElement {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denialAction = NSPredicate(format: "label IN %@", ["Don’t Allow", "Don't Allow"])
        // The product overlay also has an accessibility alert trait. Match a
        // real system permission action rather than the first alert-shaped view.
        let appAlert = app.alerts.containing(denialAction).firstMatch
        let systemAlert = springboard.alerts.containing(denialAction).firstMatch
        let appeared = waitFor(NSPredicate { _, _ in
            systemAlert.exists || appAlert.exists
        }, on: app, timeout: 8)
        if required { XCTAssertTrue(appeared, "The actual iOS permission prompt must be present.") }
        return systemAlert.exists ? systemAlert : appAlert
    }

    private func denyPermission(in alert: XCUIElement) {
        let deny = alert.buttons.matching(NSPredicate(
            format: "label IN %@", ["Don’t Allow", "Don't Allow"]
        )).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 4))
        deny.tap()
    }

    private func keepSystemScreenshot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.65))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchReview(_ route: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderNativeOnboardingReview", route, "-WanderUseDemoFixtures"] + extraArguments
        app.launchEnvironment["WANDER_ONBOARDING_PAUSED"] = "1"
        app.launch()
        return app
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<4 where !element.isHittable {
            if direction == .up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.isHittable)
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        let existing = field.value as? String ?? ""
        // Tapping the center places the insertion point inside short text.
        // Use the visible field's trailing edge so deletion starts at its end.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        XCTAssertEqual(field.value as? String, field.placeholderValue)
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func dismissKeyboardIfPresent(in app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let keyboard = app.keyboards.firstMatch
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            // The ScrollView AX frame can extend behind the keyboard. Begin
            // inside its unobscured content so the gesture cannot press a key.
            let startY = min(scrollView.frame.maxY, keyboard.frame.minY) - 30
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: app.frame.width * 0.1, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.95))
            start.press(forDuration: 0.05, thenDragTo: end)
        } else { app.swipeDown() }
        XCTAssertTrue(waitFor(NSPredicate { _, _ in
            !keyboard.exists || !keyboard.frame.intersects(app.frame)
        }, on: app, timeout: 4), "The keyboard must be offscreen before the next field action.")
    }

    private func waitFor(_ predicate: NSPredicate, on object: Any, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: object)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func keepScreenshot(_ name: String, app: XCUIApplication, settleSeconds: TimeInterval = 0.65) {
        // Allow the production 420ms composition transition to settle before
        // storing the native frame for the recording board.
        RunLoop.current.run(until: Date().addingTimeInterval(settleSeconds))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
