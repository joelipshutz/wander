#if DEBUG
import XCTest

@MainActor
final class ShareCardMockupUITests: XCTestCase {
    private struct DatedTitleObservation {
        let started: TimeInterval
        var evaluations = 0
        var readStarted: TimeInterval?
        var readFinished: TimeInterval?
        var label: String?
        var conditionMatches = false
        var accepted = false
        var outcome = "notRequested"
    }

    private var datedTitleObservation: DatedTitleObservation?

    override func tearDown() async throws {
        // XCTest may stop the body on its original failed wait. Retain only the
        // already-observed synthetic label after that verdict; make no AX read.
        if let observation = datedTitleObservation, (testRun?.failureCount ?? 0) > 0 {
            let label = observation.label.map { String(reflecting: String($0.prefix(512))) } ?? "nil"
            let text = "evaluations=\(observation.evaluations); outcome=\(observation.outcome); label=\(label); labelCharacters=\(observation.label?.count ?? 0); readStarted=\(observation.readStarted.map(String.init(describing:)) ?? "nil"); readFinished=\(observation.readFinished.map(String.init(describing:)) ?? "nil"); elapsed=\(ProcessInfo.processInfo.systemUptime - observation.started); conditionMatches=\(observation.conditionMatches); acceptedWithinDeadline=\(observation.accepted); originalTestFailureCount=\(testRun?.failureCount ?? 0)"
            let attachment = XCTAttachment(string: text)
            attachment.name = "share-card-dated-title-native-observation"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        try await super.tearDown()
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLinkGalleryAndRecipientReturn() {
        for kind in ["profile", "map", "list", "place", "checkIn", "wanna", "invitation"] {
            let app = launch(kind)
            XCTAssertTrue(app.descendants(matching: .any)["share-mock.headline"].waitForExistence(timeout: 10))
            capture("link-\(kind)")
            let open = app.buttons["share-mock.open"]
            if !open.isHittable { app.swipeUp() }
            open.tap()
            XCTAssertTrue(app.navigationBars["Opened link"].waitForExistence(timeout: 4))
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["share-mock.open"].waitForExistence(timeout: 4))
            app.terminate()
        }
    }

    func testListCountsAndSocialFormats() {
        for (kind, format, count, dark) in [
            ("list", "Link", "0", false), ("list", "Link", "1", false),
            ("list", "Link", "2", false), ("invitation", "Link", "4", true),
            ("checkIn", "Story", "4", false), ("wanna", "Story", "4", false),
            ("checkIn", "Post", "4", false), ("wanna", "Post", "4", true)
        ] {
            let app = launch(kind, additional: ["-ShareCardFormat", format, "-ShareCardCount", count] + (dark ? ["-ShareCardDark"] : []))
            XCTAssertTrue(app.segmentedControls["share-mock.format"].waitForExistence(timeout: 10))
            capture("\(kind)-\(format)-\(count)-\(dark ? "dark" : "light")")
            app.terminate()
        }
    }

    func testSelectorsAndAccessibilityText() {
        let app = launch("profile", additional: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let title = app.descendants(matching: .any)["share-mock.headline"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Discover Ryan’s world")
        for _ in 0..<4 where !title.isHittable { app.swipeUp() }
        XCTAssertTrue(title.isHittable)
        capture("profile-accessibility")
        app.buttons["Toggle preview appearance"].tap()
        XCTAssertTrue(title.exists)
        app.terminate()
    }


    func testWannaNativeTitleIncludesPlaceAndDateWithoutImageAction() {
        var app = launch("wanna")
        let card = app.descendants(matching: .any)["share-mock.headline"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(card.label.contains("On Ryan’s radar"))
        XCTAssertTrue(card.label.contains("Bar Chelou"))
        XCTAssertFalse(card.label.contains("Let’s Go"))
        // Exercise the actual dated content contract independently of the
        // design-rehearsal switch's synthesized touch coordinates.
        app.terminate()
        app = launch("wanna", additional: ["-ShareCardDated"])
        let datedCard = app.descendants(matching: .any)["share-mock.headline"]
        XCTAssertTrue(datedCard.waitForExistence(timeout: 10))
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + 4
        datedTitleObservation = DatedTitleObservation(started: started)
        let dated = NSPredicate { _, _ in
            var observation = self.datedTitleObservation!
            observation.evaluations += 1
            let requested = ProcessInfo.processInfo.systemUptime
            guard requested <= deadline else {
                observation.outcome = "deadlineBeforeRead"
                observation.accepted = false
                self.datedTitleObservation = observation
                return false
            }
            observation.readStarted = requested
            do {
                // Read this element once; both original conditions use the same
                // fresh native snapshot inside the original four-second budget.
                let snapshot = try datedCard.snapshot()
                let finished = ProcessInfo.processInfo.systemUptime
                observation.readFinished = finished
                observation.label = snapshot.label
                observation.conditionMatches = snapshot.label.contains("2026")
                    && !snapshot.label.contains("radar")
                observation.outcome = finished <= deadline ? "snapshot" : "deadlineAfterRead"
                observation.accepted = observation.conditionMatches
                    && ProcessInfo.processInfo.systemUptime <= deadline
            } catch {
                observation.readFinished = ProcessInfo.processInfo.systemUptime
                observation.label = nil
                observation.conditionMatches = false
                observation.accepted = false
                observation.outcome = "snapshotError"
            }
            self.datedTitleObservation = observation
            return observation.accepted
        }
        expectation(for: dated, evaluatedWith: datedCard)
        waitForExpectations(timeout: 4)
        XCTAssertFalse(datedCard.label.contains("radar"))
        XCTAssertTrue(datedCard.label.contains("2026"))
        XCTAssertFalse(datedCard.label.contains("Let’s Go"))
        capture("wanna-dated")
        app.terminate()
    }

    func testProductionShareSheetUsesAllFormatsAndKeepsCanonicalLink() {
        let app = launch("wanna", additional: ["-ShareCardDated"])
        app.buttons["share-mock.try"].tap()
        let formats = app.segmentedControls["share.format"]
        XCTAssertTrue(formats.waitForExistence(timeout: 10))
        for format in ["Link", "Story", "Post"] {
            let segment = formats.buttons[format]
            segment.tap()
            expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: segment)
            waitForExpectations(timeout: 4)
            XCTAssertTrue(app.descendants(matching: .any)["share.card"].exists)
            capture("production-sheet-\(format)")
        }
        app.terminate()
    }

    func testExternalPlaceCopyLinkDoesNotRequireCardPublication() {
        let app = launch("place", additional: ["-ShareCardExternalPlace"])
        app.buttons["share-mock.try"].tap()
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        copy.tap()
        XCTAssertTrue(app.staticTexts["link copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("external-place-copied")
        app.terminate()
    }

    func testExternalPlaceCanOpenNativeDestinationsFromEveryFormat() {
        let app = launch("place", additional: ["-ShareCardExternalPlace"])
        app.buttons["share-mock.try"].tap()
        let formats = app.segmentedControls["share.format"]
        XCTAssertTrue(formats.waitForExistence(timeout: 10))
        let copy = app.buttons["Copy Link"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        for (format, destination) in [("Link", "Messages"), ("Story", "Instagram Story"), ("Post", "Open more sharing options")] {
            let formatButton = formats.buttons[format]
            expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: formatButton)
            waitForExpectations(timeout: 10)
            formatButton.tap()
            app.buttons[destination].tap()
            // Messages and Instagram are unavailable on the simulator, so both
            // use the same native fallback as More. Never send to a recipient.
            let activityList = app.otherElements["ActivityListView"]
            XCTAssertTrue(activityList.waitForExistence(timeout: 10))
            XCTAssertFalse(app.alerts.firstMatch.exists)
            capture("external-place-\(format)-destination")
            // ActivityListView spans the entire display, including its dimmed
            // background. Drag the actual sheet grabber so image destinations
            // dismiss the sheet instead of scrolling its content.
            let grabber = activityList.buttons["Sheet Grabber"]
            XCTAssertTrue(grabber.waitForExistence(timeout: 5))
            grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
            XCTAssertTrue(activityList.waitForNonExistence(timeout: 5))
            XCTAssertTrue(formats.waitForExistence(timeout: 5))
            expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: formats)
            waitForExpectations(timeout: 5)
        }
        app.terminate()
    }

    func testPublicationFailureShowsConnectionRecoveryAndRetrySucceeds() {
        let app = launch("place", additional: ["-ShareCardPublicationFailure"])
        app.buttons["share-mock.try"].tap()
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        copy.tap()
        let alert = app.alerts["Couldn't create the share link"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Check your internet connection, then try sharing again."].exists)
        capture("publication-connection-error")
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        let retryReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true AND isEnabled == true"), object: copy
        )
        XCTAssertEqual(XCTWaiter.wait(for: [retryReady], timeout: 5), .completed)
        copy.tap()
        XCTAssertTrue(app.staticTexts["link copied"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("publication-retry-succeeded")
        app.terminate()
    }

    private func launch(_ kind: String, additional: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs", "-WanderShareCardMockup", kind] + additional
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "share-card-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
