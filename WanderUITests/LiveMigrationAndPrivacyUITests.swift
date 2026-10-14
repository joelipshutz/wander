import XCTest
import Vision

/// Integrated host coverage; all data is an explicitly authenticated Simulator
/// fixture. These captures do not establish hosted delivery or replay privacy.
@MainActor
final class LiveMigrationAndPrivacyUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testDeferredCalendarRecoverySurvivesRelaunchAndExplicitOffRollback() {
        let run = UUID().uuidString
        let app = launchMigration("calendar", run: run)
        let deferButton = migrationCardButton("Not now", in: app)
        XCTAssertTrue(deferButton.waitForExistence(timeout: 15))
        deferButton.tap()
        XCTAssertTrue(deferButton.waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        waitForTab("Live", in: app)
        XCTAssertFalse(migrationCardButton("Continue", in: app).exists)
        openReplay(in: app)
        XCTAssertTrue(app.buttons["live.migration.openRecovery"].waitForExistence(timeout: 5))
        capture("D9-deferred-calendar-retained")
        app.buttons["live.migration.openRecovery"].tap()
        let calendar = app.descendants(matching: .any)["profile.walkthrough.calendarSection"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        waitUntilHittable(calendar)
        XCTAssertTrue(app.tabBars.buttons["Profile"].isSelected)
        capture("D9-calendar-canonical-destination")

        app.terminate()
        app.launchArguments.append("-WanderLiveIntroductionUITestRollback")
        app.launch()
        waitForTab("Map", in: app)
        XCTAssertFalse(app.tabBars.buttons["Live"].exists)
        openReplay(in: app)
        XCTAssertTrue(app.buttons["live.migration.openRecovery"].waitForExistence(timeout: 5),
                      "Opening the calendar must not silently complete the archived reminder.")
        capture("D9-explicit-off-retains-recovery")
    }

    func testPartialGuideAcknowledgementsPersistAcrossRelaunchAndRollback() {
        let app = launchMigration("guide", run: UUID().uuidString)
        migrationCardButton("Continue", in: app).tap()
        let continueGuide = app.buttons["live.migration.guide"]
        XCTAssertTrue(continueGuide.waitForExistence(timeout: 5))
        continueGuide.tap()
        XCTAssertTrue(app.staticTexts["Choose your filters and area"].waitForExistence(timeout: 5))
        app.buttons["live.introduction.next"].tap()
        XCTAssertTrue(app.staticTexts["Find a place or a person"].waitForExistence(timeout: 5))
        capture("D9-partial-guide")
        app.terminate()
        app.launch()
        waitForTab("Live", in: app)
        openReplay(in: app)
        continueGuide.tap()
        XCTAssertTrue(app.staticTexts["Find a place or a person"].waitForExistence(timeout: 5),
                      "Relaunch must retain the explicit first acknowledgement.")
        app.terminate()
        app.launchArguments.append("-WanderLiveIntroductionUITestRollback")
        app.launch()
        waitForTab("Map", in: app)
        openReplay(in: app)
        continueGuide.tap()
        XCTAssertTrue(app.staticTexts["Find a place or a person"].waitForExistence(timeout: 5))
        for title in ["Find a place or a person", "Keep a place for later", "The same Feed, within reach"] {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
            app.buttons["live.introduction.next"].tap()
        }
        app.terminate()
        app.launch()
        waitForTab("Map", in: app)
        XCTAssertFalse(migrationCardButton("Continue", in: app).exists)
        XCTAssertFalse(app.tabBars.buttons["Live"].exists)
        openSettings(in: app)
        for _ in 0..<6 { app.swipeUp() }
        XCTAssertFalse(app.buttons["settings.whatsChanged"].exists,
                       "A completed archive must not expose Live replay while Live is Off.")
        // A completed archive does not keep Live's replay entry visible while
        // the feature is explicitly Off. Verify ordinary replay on a later
        // enabled launch with the same account and retained migration record.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-WanderLiveIntroductionUITestRollback" }
        app.launch()
        waitForTab("Live", in: app)
        openReplay(in: app)
        XCTAssertTrue(app.staticTexts["Your Feed has a map"].waitForExistence(timeout: 5))
        XCTAssertFalse(continueGuide.exists, "Completed mapped teaching opens ordinary read-only replay.")
        capture("D9-acknowledged-guide-after-rollback")
    }

    func testDeviceRecoveryCompletesOnlyAfterExplicitGotIt() {
        let app = launchMigration("device", run: UUID().uuidString)
        migrationCardButton("Continue", in: app).tap()
        app.buttons["live.migration.openRecovery"].tap()
        let acknowledge = app.buttons["live.migration.deviceAcknowledged"]
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["These are optional setup instructions. This guide does not request or change device permissions."].exists)
        capture("D9-device-optional-lesson")
        app.navigationBars.buttons["Not now"].tap()
        waitForTab("Live", in: app)
        openReplay(in: app)
        app.buttons["live.migration.openRecovery"].tap()
        XCTAssertTrue(acknowledge.waitForExistence(timeout: 10))
        acknowledge.tap()
        app.terminate()
        app.launchArguments.append("-WanderLiveIntroductionUITestRollback")
        app.launch()
        waitForTab("Map", in: app)
        // A complete archive is retained, but no unfinished recovery is offered.
        XCTAssertFalse(migrationCardButton("Continue", in: app).exists)
        XCTAssertFalse(app.buttons["live.migration.deviceAcknowledged"].exists)
        capture("D9-device-acknowledged-after-rollback")
    }

    func testPrivateInboxAppSwitcherSnapshotHidesParticipantAndPreview() async throws {
        let app = launchLive()
        app.buttons["Messages"].tap()
        let conversation = app.buttons["messaging.conversation.63600000-0000-0000-0000-000000000010"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        let activeText = try recognizedText(in: app.screenshot())
        XCTAssertTrue(activeText.contains("maya chen"), "OCR must read the active fictional participant before checking concealment.")
        capture("privacy-inbox-active-fixture")
        try await assertAppSwitcherCover(app, forbidden: ["maya chen", "little patio", "sunny afternoon"], name: "privacy-inbox-switcher-covered")
        app.activate()
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
    }

    func testPrivateThreadAppSwitcherSnapshotHidesDraftAndRetainsItOnReturn() async throws {
        let app = launchLive()
        app.buttons["Messages"].tap()
        let conversation = app.buttons["messaging.conversation.63600000-0000-0000-0000-000000000010"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        let composer = app.textFields["messaging.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Orchid signal private draft")
        waitForValue("Orchid signal private draft", in: composer)
        XCTAssertEqual(composer.value as? String, "Orchid signal private draft")
        XCTAssertTrue(try recognizedText(in: app.screenshot()).contains("orchid signal"))
        capture("privacy-thread-active-keyboard-fixture")
        try await assertAppSwitcherCover(app, forbidden: ["orchid", "signal", "draft", "maya chen", "little patio", "sunny afternoon"],
                                  name: "privacy-thread-switcher-covered")
        app.activate()
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertEqual(composer.value as? String, "Orchid signal private draft")
        XCTAssertFalse(app.staticTexts["Simulated"].exists, "Backgrounding must not send the draft.")
        capture("privacy-thread-draft-restored")
    }

    private func migrationCardButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        // SwiftUI propagates the card's identifier to its child actions on the
        // native host. Match both the card scope and the distinct action label.
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@",
                                         "live.migration.card", label)).firstMatch
    }

    private func launchMigration(_ scenario: String, run: String) -> XCUIApplication {
        let app = launchLive(extras: ["-WanderLiveIntroductionUITest", scenario,
                                     "-WanderLiveIntroductionUITestRun", run])
        addTeardownBlock { @MainActor in
            app.terminate()
            app.launchArguments = self.baseArguments + ["-WanderLiveIntroductionUITest", "cleanup",
                                                       "-WanderLiveIntroductionUITestRun", run]
            app.launch()
            app.terminate()
        }
        XCTAssertTrue(migrationCardButton("Continue", in: app).waitForExistence(timeout: 15))
        return app
    }

    private var baseArguments: [String] {
        ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures", "-WanderDisableWalkthroughs",
         "-WanderUnifiedLiveUITest", "-WanderNUXFeedFixture", "-WanderInitialTab", "discover",
         "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
    }

    private func launchLive(extras: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = baseArguments + extras
        app.launch()
        dismissUpsellIfPresent(in: app)
        waitForTab("Live", in: app)
        return app
    }

    private func waitForTab(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons[title]
        XCTAssertTrue(tab.waitForExistence(timeout: 25))
        waitUntilHittable(tab)
    }

    private func waitForValue(_ value: String, in element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "Typed text must settle before taking the private-draft baseline.")
    }

    private func waitUntilHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func openReplay(in app: XCUIApplication) {
        openSettings(in: app)
        let replay = app.buttons["settings.whatsChanged"]
        for _ in 0..<6 where !replay.isHittable { app.swipeUp() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
    }

    private func openSettings(in app: XCUIApplication) {
        app.tabBars.buttons["Profile"].tap()
        let settings = app.buttons["Settings"]
        for _ in 0..<6 where !settings.isHittable { app.swipeDown() }
        XCTAssertTrue(settings.isHittable)
        settings.tap()
    }

    private func dismissUpsellIfPresent(in app: XCUIApplication) {
        if app.buttons["productUpsell.secondary"].waitForExistence(timeout: 3) {
            app.buttons["productUpsell.secondary"].tap()
        } else if app.buttons["productUpsell.primary"].exists {
            app.buttons["productUpsell.primary"].tap()
            let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Don")).firstMatch
            if deny.waitForExistence(timeout: 5) { deny.tap() }
        }
    }

    private func assertAppSwitcherCover(_ app: XCUIApplication, forbidden: [String], name: String) async throws {
        // Real system gesture: pull from the home indicator and hold to reveal
        // the app-switcher card. A home-screen-only screenshot is insufficient.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 1)
        // The just-used Astir card is the rightmost card. A short drag can
        // spring back with its cover label clipped beyond the screen. Cross
        // the card's center before releasing, then verify the rendered cover.
        // Process foreground state does not identify an inactive switcher card.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // The cover can be readable in a transient animation frame while the
        // card ultimately settles offscreen. Accept only a stable, centered
        // label before deciding that no framing gesture is needed.
        var stableScreenshot = try await stableSwitcherScreenshot(timeout: 3)
        if stableScreenshot == nil {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
                .press(forDuration: 0.05,
                       thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
            stableScreenshot = try await stableSwitcherScreenshot(timeout: 8)
        }
        // Preserve the actual failed switcher frame even when this test stops
        // at the first assertion; a missing cover label alone is inconclusive.
        let screenshot = stableScreenshot ?? XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "REC-636-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNotNil(stableScreenshot, "The privacy cover must settle in the visible app-switcher card.")
        let text = try recognizedText(in: screenshot)
        XCTAssertTrue(text.contains("private messages"), "The app-switcher capture must show the actual inactive privacy cover.")
        for token in forbidden { XCTAssertFalse(text.contains(token), "Private fixture content is visible in the app-switcher snapshot: \(token)") }
    }

    private func stableSwitcherScreenshot(timeout: TimeInterval) async throws -> XCUIScreenshot? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
        while ContinuousClock.now < deadline {
            let first = XCUIScreen.main.screenshot()
            // Measure rendered stability between distinct captures, rather
            // than counting expensive Vision work inside a predicate timeout.
            try await Task.sleep(for: .milliseconds(500))
            guard ContinuousClock.now < deadline else { return nil }
            let second = XCUIScreen.main.screenshot()
            guard ContinuousClock.now < deadline else { return nil }
            let firstBounds = try await Self.switcherCoverBounds(in: first.pngRepresentation)
            let secondBounds = try await Self.switcherCoverBounds(in: second.pngRepresentation)
            if let firstBounds, let secondBounds,
               abs(firstBounds.midX - secondBounds.midX) < 0.015,
               abs(firstBounds.midY - secondBounds.midY) < 0.015,
               abs(firstBounds.width - secondBounds.width) < 0.015 {
                // The full-screen forbidden-content scan below inspects this
                // same second frame, never a different post-check screenshot.
                return second
            }
        }
        return nil
    }

    private nonisolated static func switcherCoverBounds(in data: Data) async throws -> CGRect? {
        try await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(data: data).perform([request])
            guard let line = request.results?.first(where: {
                $0.topCandidates(1).first?.string.lowercased().contains("private messages") == true
            }) else { return nil }
            let bounds = line.boundingBox
            guard (0.3...0.7).contains(bounds.midX), bounds.minX > 0.05, bounds.maxX < 0.95,
                  bounds.minY > 0.1, bounds.maxY < 0.9 else { return nil }
            return bounds
        }.value
    }

    private func recognizedText(in screenshot: XCUIScreenshot) throws -> String {
        try recognizedLines(in: screenshot).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased()
    }

    private func recognizedLines(in screenshot: XCUIScreenshot) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: screenshot.pngRepresentation).perform([request])
        return request.results ?? []
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-636-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
