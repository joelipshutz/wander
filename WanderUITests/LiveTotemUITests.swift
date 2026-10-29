import XCTest

/// Real app/MapKit interaction captures with fictional, memory-only content.
@MainActor
final class LiveTotemUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testTotemStatesFiltersAndPlaceNavigation() {
        let app = launch()
        capturePinStates(app)

        app.buttons["Filters"].tap()
        wait(app.buttons["live.filter.people"])
        app.buttons["live.filter.people"].tap()
        wait(app.buttons["live.filter.option.People.Only Friends"])
        capture("11-colored-people-options")
        app.buttons["live.filter.option.People.Only Friends"].tap()
        XCTAssertTrue(app.buttons["live.filter.option.People.Only Friends"].waitForNonExistence(timeout: 5))
        app.buttons["live.filter.scope"].tap()
        wait(app.buttons["live.filter.option.Scope.Featured"])
        capture("12-green-scope-option")
        app.buttons["live.filter.option.Scope.Featured"].tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        wait(app.buttons["live.pin.totem_noodles"])
        assertUniquePins(app)
        capture("12a-only-friends-map")
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Only Me"].tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        wait(app.buttons["live.pin.totem_coffee"])
        capture("12b-only-me-map")
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Everyone"].tap()
        app.buttons["live.filter.activity"].tap()
        let listsOption = visibleButton("Lists", in: app)
        capture("13-lists-activity-option")
        listsOption.tap()
        app.buttons["live.applyFilters"].tap()
        wait(app.buttons["live.pin.totem_list"])
        collapseDrawer(app)
        assertUniquePins(app)
        XCTAssertFalse(app.buttons["live.pin.totem_featured"].exists)
        capture("14-lists-filter-map")
        settle(app.buttons["live.pin.totem_list"])
        app.buttons["live.pin.totem_list"].tap()
        wait(app.buttons["live.placePreview.close"])
        capture("15-list-addition-preview")
        app.buttons["live.placePreview.close"].tap()

        app.buttons["Filters"].tap()
        app.buttons["live.filter.activity"].tap()
        visibleButton("All", in: app).tap()
        app.buttons["live.filter.time"].tap()
        visibleButton("Past 24 hours", in: app).tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        let coffee = app.buttons["live.pin.totem_coffee"]
        wait(coffee)
        settle(coffee)
        XCTAssertTrue(coffee.label.contains("On a list"))
        coffee.tap()
        wait(app.buttons["live.placePreview.close"])
        capture("16-old-membership-recent-filter")
        app.buttons["live.placePreview.open"].tap()
        wait(app.buttons["place-profile.back"])
        capture("17-place-profile-navigation")
        app.buttons["place-profile.back"].tap()
        wait(app.buttons["live.draw"])
        assertUniquePins(app)
        capture("18-live-return")

        app.buttons["Filters"].tap()
        app.buttons["live.filter.time"].tap()
        visibleButton("All time", in: app).tap()
        app.buttons["live.applyFilters"].tap()
        collapseDrawer(app)
        let featured = app.buttons["live.pin.totem_featured"]
        wait(featured)
        settle(featured)
        XCTAssertTrue(featured.label.contains("Featured"))
        featured.tap()
        wait(app.buttons["live.placePreview.add"])
        app.buttons["live.placePreview.add"].tap()
        wait(app.buttons["save.submit"])
        app.scrollViews["save.editorScroll"].buttons["Wanna go"].tap()
        capture("19-save-featured-as-wanna")
        app.buttons["save.submit"].tap()
        XCTAssertTrue(app.buttons["save.submit"].waitForNonExistence(timeout: 15))
        let celebration = app.buttons["Got it"]
        if celebration.waitForExistence(timeout: 3) {
            wait(celebration)
            celebration.tap()
            XCTAssertTrue(celebration.waitForNonExistence(timeout: 5))
        }
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            featured.exists && featured.label.contains("You, Wanna") && !featured.label.contains("Featured")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 15), .completed)
        wait(featured)
        settle(featured)
        assertUniquePins(app)
        capture("20-featured-becomes-wanna")
    }

    /// Focused native mockup pass for pin-only geometry refinements.
    func testRefinedTotemPinMockups() {
        capturePinStates(launch())
    }

    func testMixedSocialRailAndDenseBadgeMockups() {
        let app = launch()
        collapseDrawer(app)
        let featured = app.buttons["live.pin.totem_featured"]
        wait(featured)
        settle(featured)
        assertUniquePins(app)
        capture("21-dense-dots-without-badges")
        let mixed = app.buttons["live.pin.totem_mixed"]
        wait(mixed)
        settle(mixed)
        mixed.tap()
        wait(app.buttons["live.placePreview.close"])
        settle(mixed)
        capture("22-social-been-three-wanna-dots")
        assertUniquePins(app)
    }

    private func capturePinStates(_ app: XCUIApplication) {
        capture("01-live-with-feed")
        collapseDrawer(app)
        wait(app.buttons["live.pin.totem_featured"])
        settle(app.buttons["live.pin.totem_featured"])
        capture("02-all-states-map")
        assertUniquePins(app)

        for (id, name) in [("coffee", "03-you-been-persistent-list"),
                           ("tacos", "04-you-wanna-list"),
                           ("bar", "05-social-been"),
                           ("noodles", "06-social-wanna"),
                           ("mixed", "07-mixed-one-place"),
                           ("list", "08-list-only"),
                           ("featured_list", "09-list-over-featured"),
                           ("featured", "10-featured-only")] {
            let pin = app.buttons["live.pin.totem_\(id)"]
            wait(pin)
            settle(pin)
            pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            wait(app.buttons["live.placePreview.close"])
            capture(name)
            app.buttons["live.placePreview.close"].tap()
            XCTAssertTrue(app.buttons["live.placePreview.close"].waitForNonExistence(timeout: 5))
            collapseDrawer(app)
            assertUniquePins(app)
        }
    }

    func testWarmReturnsKeepSelectedPinAndFeedPosition() {
        let app = launch()
        collapseDrawer(app)
        let pin = app.buttons["live.pin.totem_coffee"]
        wait(pin); settle(pin)
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        wait(app.buttons["live.placePreview.close"])
        capture("rec667-before-five-second-return")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(app.buttons["live.placePreview.close"].exists, "A warm return must preserve the selected pin")
        capture("rec667-after-five-second-return")
        app.buttons["live.placePreview.close"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.15)))
        let scroll = app.scrollViews["feed.places.scroll"]
        wait(scroll)
        scroll.swipeUp()
        let cards = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'feed.activity.' AND identifier ENDSWITH '.postcard'"))
        for seconds in [30.0, 120.0] {
            let anchor = cards.allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(anchor, "Expected a visible Feed card before backgrounding")
            guard let anchor else { return }
            let identifier = anchor.identifier, before = anchor.frame.minY
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: seconds)
            app.activate()
            let restored = app.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(restored.exists, "Warm return must retain the reader's card")
            XCTAssertEqual(restored.frame.minY, before, accuracy: 8, "Warm refresh must preserve Feed position")
            capture("rec667-after-\(Int(seconds))-second-return")
        }
    }

    func testColdLaunchRestoresFilterAndDrawerBookmark() {
        let app = launch(restoration: true)
        app.buttons["Filters"].tap()
        app.buttons["live.filter.people"].tap()
        app.buttons["live.filter.option.People.Only Friends"].tap()
        app.buttons["live.applyFilters"].tap()
        let handle = app.descendants(matching: .any)["live.drawerHandle"].firstMatch
        wait(handle)
        handle.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.15)))
        let savedLabel = handle.label
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()
        wait(app.buttons["live.draw"], timeout: 30)
        XCTAssertEqual(app.descendants(matching: .any)["live.drawerHandle"].firstMatch.label, savedLabel)
        app.buttons["Filters"].tap()
        wait(app.buttons["live.filter.people"])
        XCTAssertTrue(app.buttons["live.filter.people"].label.contains("Only Friends"))
        capture("rec667-cold-restored-filters")
    }

    private func launch(restoration: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderAuthenticatedUITest", "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs", "-WanderUnifiedLiveUITest",
            "-WanderLiveTotemUITest", "-WanderInitialTab", "discover",
            "-astir.live.viewedPins.user_joe", "",
            "-recme.productUpsell.notification_app_open.user_joe.impressionCount.v1", "3",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        if restoration { app.launchArguments.append("-WanderLiveRestorationUITest") }
        app.launch()
        wait(app.buttons["live.draw"], timeout: 30)
        if app.buttons["live.introduction.notNow"].exists {
            app.buttons["live.introduction.notNow"].tap()
        }
        return app
    }

    private func wait(_ element: XCUIElement, timeout: TimeInterval = 10) {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists { capture("diagnostic-missing-element") }
        XCTAssertTrue(exists)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.isHittable }, object: nil)
        let result = XCTWaiter.wait(for: [ready], timeout: timeout)
        if result != .completed { capture("diagnostic-unhittable-element") }
        XCTAssertEqual(result, .completed)
    }

    private func collapseDrawer(_ app: XCUIApplication) {
        let handle = app.descendants(matching: .any).matching(identifier: "live.drawerHandle").firstMatch
        guard handle.exists, !handle.label.contains(", collapsed") else { return }
        wait(handle)
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            handle.exists && handle.label.contains(", collapsed")
        }, object: nil)
        let result = XCTWaiter.wait(for: [collapsed], timeout: 10)
        if result != .completed { capture("diagnostic-drawer-drag") }
        XCTAssertEqual(result, .completed)
    }

    private func visibleButton(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title))
        func visibleMatches() -> [XCUIElement] {
            matches.allElementsBoundByIndex.filter { element in
                // A native menu also exposes a noninteractive accessibility
                // container. On compact iOS it has no activation point.
                guard [.button, .staticText, .menuItem].contains(element.elementType),
                      !element.frame.isEmpty, app.frame.intersects(element.frame) else { return false }
                return element.isHittable
            }
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !visibleMatches().isEmpty
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        return visibleMatches().first ?? matches.firstMatch
    }

    /// MapKit restores the camera after a card closes. Hittability can become
    /// true while an annotation is still moving, so wait for stable geometry.
    private func settle(_ element: XCUIElement) {
        var previous = CGRect.null
        var changedAt = Date.now
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, element.isHittable else { return false }
            let frame = element.frame
            if frame != previous { previous = frame; changedAt = .now; return false }
            return Date.now.timeIntervalSince(changedAt) >= 0.8
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 10), .completed)
    }

    private func assertUniquePins(_ app: XCUIApplication) {
        let pins = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "live.pin."))
            .allElementsBoundByIndex
        let identifiers = pins.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
        XCTAssertLessThanOrEqual(identifiers.filter { $0.contains("totem_mixed") }.count, 1)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "REC-657-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
