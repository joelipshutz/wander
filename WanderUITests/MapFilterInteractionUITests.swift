import XCTest

@MainActor
final class MapFilterInteractionUITests: XCTestCase {
    func testPerformanceFixtureCoversMapKitDuringInitialAccountLoading() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapInitialLoadingDelayMilliseconds",
            "30000"
        ]
        app.launch()

        let loading = app.descendants(matching: .any)
            .matching(identifier: "map.initialLoading")
            .firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        XCTAssertEqual(loading.label, "Loading your map…")
        XCTAssertFalse(app.maps.firstMatch.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-381 graceful large-account Map loading"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPerformanceFixtureRevealsUsableMapAfterInitialLoading() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapInitialLoadingDelayMilliseconds",
            "1000"
        ]
        app.launch()

        let loading = app.descendants(matching: .any)
            .matching(identifier: "map.initialLoading")
            .firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 5))

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 3))
        XCTAssertTrue(map.isHittable)
        XCTAssertTrue(app.buttons["map.filter.friends"].waitForExistence(timeout: 3))
    }

    func testPerformanceFixtureRevealsMapBeforeStalledInitialRefreshFinishes() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapInitialLoadingDelayMilliseconds",
            "12000",
            "-WanderMapInitialLoadingRefreshStallMilliseconds",
            "30000"
        ]
        app.launch()

        let loading = app.descendants(matching: .any)
            .matching(identifier: "map.initialLoading")
            .firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 3))
        XCTAssertTrue(loading.waitForNonExistence(timeout: 15))

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 3))
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "hittable == true"),
                        object: map
                    )
                ],
                timeout: 3
            ),
            .completed
        )
        XCTAssertTrue(app.buttons["map.filter.friends"].waitForExistence(timeout: 3))
    }

    func testPerformanceFixtureKeepsWarmSourceSwitchesResponsive() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs"
        ]
        app.launch()

        var dismissedSystemBanner = false
        addUIInterruptionMonitor(withDescription: "Dismiss notification banners") { element in
            guard element.identifier == "NotificationShortLookView" else { return false }
            dismissedSystemBanner = true
            element.swipeUp()
            return true
        }

        let sourceIDs = [
            "map.filter.friends",
            "map.filter.you",
            "map.filter.featured",
            "map.filter.friends"
        ]
        for sourceID in sourceIDs {
            XCTAssertTrue(app.buttons[sourceID].waitForExistence(timeout: 12))
        }

        let startedAt = Date()
        for sourceID in sourceIDs {
            let source = app.buttons[sourceID]
            source.tap()
            XCTAssertTrue(
                source.isSelected,
                "Dense-account source switch did not select \(sourceID)."
            )
        }

        if !dismissedSystemBanner {
            XCTAssertLessThan(
                Date().timeIntervalSince(startedAt),
                8,
                "Four warm dense-account source switches should not block the UI."
            )
        }
    }

    func testPerformanceFixtureMeasuresPlaceSelectionAndTapAwayDismissalHitches() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapPerformanceInteractionControls"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["map.filter.friends"].waitForExistence(timeout: 12))

        let card = app.buttons["map.selectedPlaceCard"]
        let activePin = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "map.pin.active.saved.")
        ).firstMatch
        let selectFirstPin = app.buttons["map.performanceSelectFirstPin"]
        let nearby = app.buttons["map.nearby"]
        XCTAssertTrue(selectFirstPin.waitForExistence(timeout: 3))
        XCTAssertTrue(selectFirstPin.isHittable)
        XCTAssertTrue(nearby.waitForExistence(timeout: 3))

        var didMeasureInteraction = false
        if #available(iOS 19.0, *) {
            // XCTest discards the first performance-block invocation. Keep it
            // as a no-op so the measured pass starts with no selected place.
            var invocationCount = 0
            let options = XCTMeasureOptions()
            options.iterationCount = 1
            options.invocationOptions = [.manuallyStart, .manuallyStop]

            measure(metrics: [XCTHitchMetric(application: app)], options: options) {
                invocationCount += 1
                startMeasuring()
                defer { stopMeasuring() }
                guard invocationCount > 1 else { return }

                selectFirstPin.tap()
                XCTAssertTrue(card.waitForExistence(timeout: 3))
                XCTAssertTrue(activePin.waitForExistence(timeout: 2))

                // Exercise the same physical empty-map tap users use to close
                // the card. The fixed point is empty in this deterministic fixture.
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.46)).tap()
                XCTAssertEqual(
                    XCTWaiter.wait(
                        for: [
                            XCTNSPredicateExpectation(
                                predicate: NSPredicate(format: "exists == false"),
                                object: card
                            )
                        ],
                        timeout: 3
                    ),
                    .completed
                )
                XCTAssertTrue(activePin.waitForNonExistence(timeout: 1))
                XCTAssertEqual(
                    XCTWaiter.wait(
                        for: [
                            XCTNSPredicateExpectation(
                                predicate: NSPredicate(format: "hittable == true"),
                                object: nearby
                            )
                        ],
                        timeout: 2
                    ),
                    .completed
                )
                didMeasureInteraction = true
            }
        } else {
            selectFirstPin.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 3))
            map.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.46)).tap()
            XCTAssertTrue(card.waitForNonExistence(timeout: 3))
            didMeasureInteraction = true
        }

        XCTAssertTrue(didMeasureInteraction)
        XCTAssertFalse(card.exists)
        XCTAssertTrue(nearby.isHittable)
    }

    func testPerformanceFixtureMeasuresSelectedPinPanCPUAndAnnotationWork() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapPerformanceProbe",
            "-WanderMapPerformanceSelectedPin"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 3))

        let dragStart = map.coordinate(
            withNormalizedOffset: CGVector(dx: 0.72, dy: 0.42)
        )
        let dragEnd = map.coordinate(
            withNormalizedOffset: CGVector(dx: 0.28, dy: 0.56)
        )
        let probe = app.descendants(matching: .any)["map.performanceProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))
        let populatedProbe = NSPredicate(format: "value CONTAINS %@", "camera=")
        var didMeasurePan = false
        var invocationCount = 0
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(application: app)],
            options: options
        ) {
            invocationCount += 1
            startMeasuring()
            defer { stopMeasuring() }
            guard invocationCount > 1 else { return }

            dragStart.press(
                forDuration: 0.08,
                thenDragTo: dragEnd,
                withVelocity: .fast,
                thenHoldForDuration: 0.08
            )
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(predicate: populatedProbe, object: probe)
                    ],
                    timeout: 3
                ),
                .completed
            )
            didMeasurePan = true
        }
        XCTAssertTrue(didMeasurePan)

        let snapshot = String(describing: probe.value)
        print("REC404_MAP_PERFORMANCE_PROBE \(snapshot)")
        add(XCTAttachment(string: snapshot))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-404 dense map after selected-pin pan"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUsePerformanceFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends",
            "-WanderMapPerformanceProbe",
            "-WanderMapPerformanceCameraControls",
            "-WanderMapPerformanceSelectedPin"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["map.selectedPlaceCard"].waitForExistence(timeout: 3))

        let probe = app.descendants(matching: .any)["map.performanceProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 3))

        func metric(_ name: String, in snapshot: String) -> Int? {
            snapshot
                .split(separator: ";")
                .first { $0.hasPrefix("\(name)=") }
                .flatMap { Int($0.dropFirst(name.count + 1)) }
        }

        func perform(_ label: String, button: XCUIElement) {
            let previousValue = probe.value as? String ?? ""
            XCTAssertTrue(button.isHittable)
            button.tap()
            let populatedProbe = NSPredicate(
                format: "value != %@ AND value CONTAINS %@",
                previousValue,
                "camera="
            )
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: populatedProbe, object: probe)],
                    timeout: 3
                ),
                .completed
            )
            let snapshot = probe.value as? String ?? ""
            print("REC404_MAP_INDIVIDUAL_PIN_TRACE \(label) \(snapshot)")
            XCTAssertLessThanOrEqual(
                metric("nativeA11yVisits", in: snapshot) ?? .max,
                200,
                "Accessibility maintenance must stay bounded to the viewport-buffered set"
            )
            XCTAssertLessThanOrEqual(
                metric("nativeSyncVisits", in: snapshot) ?? .max,
                200,
                "The 780-place fixture must stay viewport-buffered inside MapKit"
            )
            XCTAssertLessThan(
                metric("maxFrameGapMs", in: snapshot) ?? .max,
                100,
                "Dense-map camera animation must not freeze for a visible fraction of a second"
            )
        }

        let zoomOut = app.buttons["map.performanceZoomOut"]
        let zoomIn = app.buttons["map.performanceZoomIn"]
        XCTAssertTrue(zoomOut.waitForExistence(timeout: 3))
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 3))

        perform("zoom-out-1", button: zoomOut)
        perform("zoom-out-2", button: zoomOut)
        perform("zoom-in", button: zoomIn)
    }

    func testSingleScreenTapOnMapPinSelectsThatPlace() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderUseStorefrontFixtures"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["map.filter.featured"].waitForExistence(timeout: 8))

        let pin = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Canyon Lookout Trail,")
        ).firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 8))
        let pinCenter = CGPoint(x: pin.frame.midX, y: pin.frame.midY)
        XCTAssertTrue(map.frame.contains(pinCenter))

        // Tap the Map at the rendered pin's screen coordinate. Calling
        // pin.tap() would invoke its accessibility action and would not prove
        // that a normal touch reaches the passive map tap observer.
        map.coordinate(
            withNormalizedOffset: CGVector(
                dx: (pinCenter.x - map.frame.minX) / map.frame.width,
                dy: (pinCenter.y - map.frame.minY) / map.frame.height
            )
        ).tap()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(
            card.label.contains("Canyon Lookout Trail"),
            "A single physical map tap should select Canyon Lookout Trail; card was \(card.label)"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "map.pin.active.saved.")
            ).firstMatch.waitForExistence(timeout: 3)
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-360 single-tap selection and frontmost active pin"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testVisiblePlacePinSelectsOnFirstTap() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        let pin = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Bar Nido,"))
            .firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        // Tap through the map at the rendered pin center. This exercises the
        // gesture bridge instead of dispatching the pin's accessibility action.
        let normalizedPinCenter = CGVector(
            dx: (pin.frame.midX - map.frame.minX) / map.frame.width,
            dy: (pin.frame.midY - map.frame.minY) / map.frame.height
        )
        map.coordinate(withNormalizedOffset: normalizedPinCenter).tap()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("Bar Nido"))

        card.tap()
        XCTAssertTrue(
            app.staticTexts["Ratings"].waitForExistence(timeout: 3),
            "The first collapsed-card tap should open the place profile."
        )
    }

    func testSourceFiltersFitWithoutOverlapOnSmallPhones() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let filters = [
            app.buttons["map.filter.featured"],
            app.buttons["map.filter.friends"],
            app.buttons["map.filter.you"],
            app.buttons["map.filter.more"]
        ]
        let appFrame = app.windows.firstMatch.frame

        for filter in filters {
            XCTAssertTrue(filter.waitForExistence(timeout: 5))
            XCTAssertTrue(filter.isHittable)
            XCTAssertGreaterThanOrEqual(filter.frame.minX, appFrame.minX)
            XCTAssertLessThanOrEqual(filter.frame.maxX, appFrame.maxX)
            XCTAssertGreaterThanOrEqual(filter.frame.height, 44)
        }

        for (leading, trailing) in zip(filters, filters.dropFirst()) {
            XCTAssertLessThanOrEqual(leading.frame.maxX, trailing.frame.minX)
        }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-278 Option B small-phone filter geometry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSelectedTicketClearsSearchDockWithoutRedundantResultMessage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapPlace", "Woodcat Coffee"
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        let message = app.staticTexts["map.searchMessage"]
        let search = app.textFields["map.searchField"]
        let addButton = app.buttons["map.headerAdd"]
        let nearby = app.buttons["map.nearby"]

        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(card.label.contains("Woodcat Coffee"))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        XCTAssertFalse(message.exists)
        XCTAssertLessThanOrEqual(card.frame.maxY, search.frame.minY)
        XCTAssertGreaterThanOrEqual(addButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(addButton.frame.height, 44)
        XCTAssertTrue(addButton.isHittable)
        XCTAssertFalse(nearby.isHittable)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-293 selected card with Nearby hidden"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLongPressShowsDroppedPinAsAStandardPlaceCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.68))
            .press(forDuration: 0.7)

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-289 dropped pin standard place card"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if card.label.contains("Dropped pin") {
            XCTAssertFalse(app.staticTexts["map.searchMessage"].exists)
            let coordinates = app.staticTexts["map.droppedPinCoordinates"]
            XCTAssertTrue(coordinates.waitForExistence(timeout: 2))
            coordinates.press(forDuration: 1)
            XCTAssertTrue(app.buttons["Copy coordinates"].waitForExistence(timeout: 2))
        }
    }

    func testNearbyPermissionEducationAppearsBeforeTheSystemPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let nearby = app.buttons["map.nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 5))
        guard nearby.value as? String == "Location permission needed" else {
            throw XCTSkip("Simulator already has location permission")
        }

        nearby.tap()
        XCTAssertTrue(
            app.buttons["map.locationEducation.allow"].waitForExistence(timeout: 2)
        )
        XCTAssertEqual(app.buttons["map.locationEducation.allow"].label, "Continue")
        XCTAssertFalse(app.buttons["map.locationEducation.cancel"].exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-396 actual Map location permission"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchMoreFilters(source: String = "friends", resetSeconds: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderMapCaptureMode", source,
            "-WanderMapMoreFiltersOpen"
        ]
        if let resetSeconds {
            app.launchArguments += ["-WanderMapMoreFiltersAwayResetSeconds", resetSeconds]
        }
        app.launch()
        return app
    }

    func testPeopleSelectionFromFeaturedSwitchesToFriends() {
        assertPeopleSelectionSwitchesToFriends(from: "featured")
    }

    func testPeopleSelectionFromYouSwitchesToFriends() {
        assertPeopleSelectionSwitchesToFriends(from: "you")
    }

    func testPeopleSelectionFromFriendsKeepsFriends() {
        assertPeopleSelectionSwitchesToFriends(from: "friends")
    }

    private func assertPeopleSelectionSwitchesToFriends(from source: String) {
        let app = launchMoreFilters(source: source)
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let allPeople = app.buttons["map.more.people.all"]
        for _ in 0..<5 where !allPeople.isHittable {
            panel.swipeUp()
        }
        XCTAssertTrue(allPeople.isHittable)
        allPeople.tap()
        XCTAssertTrue(
            (app.buttons["map.filter.\(source)"].value as? String)?.contains("Selected") == true
        )

        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "REC-418 People available on \(source)"
        before.lifetime = .keepAlways
        add(before)

        selectDemoPerson(in: app, panel: panel)
        XCTAssertTrue(panel.exists)
        XCTAssertTrue(
            (app.buttons["map.filter.friends"].value as? String)?.contains("Selected") == true
        )
        assertOneSelectedFilter(in: app)

        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "REC-418 \(source) to Friends with person selected"
        after.lifetime = .keepAlways
        add(after)

        app.buttons["map.more.person.user_demo"].tap()
        XCTAssertTrue(
            (app.buttons["map.filter.friends"].value as? String)?.contains("Selected") == true
        )
        XCTAssertEqual(allPeople.value as? String, "Selected")
    }

    func testSourceTapDismissesAndResetsMoreFiltersInOneTap() {
        let app = launchMoreFilters()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectDemoPerson(in: app, panel: panel)

        let you = app.buttons["map.filter.you"]
        XCTAssertTrue(you.isHittable)
        you.tap()

        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue((you.value as? String)?.contains("Selected") == true)
        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("No additional filters") == true
        )
    }

    func testSearchNearbyAndBottomNavigationDismissWithoutResettingMoreFilters() {
        let app = launchMoreFilters()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        selectDemoPerson(in: app, panel: panel)

        let search = app.textFields["map.searchField"]
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        app.buttons["map.searchCancel"].tap()
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let nearby = app.buttons["Center on my location"]
        XCTAssertTrue(nearby.isHittable)
        nearby.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        let cancelLocationEducation = app.buttons["map.locationEducation.cancel"]
        if cancelLocationEducation.waitForExistence(timeout: 1) {
            cancelLocationEducation.tap()
        }
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let add = app.buttons["map.headerAdd"]
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        let closeAdd = app.buttons["Close add place"]
        XCTAssertTrue(closeAdd.waitForExistence(timeout: 3))
        closeAdd.tap()
        assertOneSelectedFilter(in: app)

        app.buttons["map.filter.more"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 2))
        let feed = app.buttons["Feed"]
        XCTAssertTrue(feed.isHittable)
        feed.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue(feed.isSelected)

        app.buttons["Map"].tap()
        assertOneSelectedFilter(in: app)
    }

    func testThreeMinutesOnAnotherTabResetsMoreFilters() {
        let app = launchMoreFilters(resetSeconds: "0.2")
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        selectDemoPerson(in: app, panel: panel)

        app.buttons["Feed"].tap()
        Thread.sleep(forTimeInterval: 0.35)
        app.buttons["Map"].tap()

        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("No additional filters") == true
        )
    }

    private func selectDemoPerson(in app: XCUIApplication, panel: XCUIElement) {
        let demo = app.buttons["map.more.person.user_demo"]
        for _ in 0..<5 where !demo.isHittable {
            panel.swipeUp()
        }
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertEqual(demo.value as? String, "Selected")
    }

    private func assertOneSelectedFilter(in app: XCUIApplication) {
        XCTAssertTrue(
            (app.buttons["map.filter.more"].value as? String)?.contains("1 selected filter") == true
        )
    }
}
