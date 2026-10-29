import XCTest

@MainActor
final class MapFilterInteractionUITests: XCTestCase {
    func testInitialSplashDoesNotReturnAfterTabRoundTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-WanderMapCapture", "-WanderUsePerformanceFixtures", "-WanderAuthenticatedUITest", "-WanderDisableWalkthroughs"]
        app.launch()
        let loading = app.descendants(matching: .any).matching(identifier: "map.initialLoading").firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 3))
        app.buttons["Profile"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
        app.buttons["Map"].firstMatch.tap()
        XCTAssertFalse(loading.exists)
        XCTAssertTrue(app.maps.firstMatch.isHittable)
    }

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
        XCTAssertEqual(loading.label, "Opening Astir")
        XCTAssertFalse(app.staticTexts["Loading your map…"].exists)
        XCTAssertFalse(loading.progressIndicators.firstMatch.exists)
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        XCTAssertFalse(app.maps.firstMatch.isHittable)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.86, dy: 0.68))
            .press(forDuration: 0.7)
        XCTAssertTrue(loading.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-537 uninterrupted launch artwork while Map loads"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(loading.waitForNonExistence(timeout: 35))
        XCTAssertFalse(app.buttons["map.selectedPlaceCard"].exists)
        XCTAssertTrue(app.maps.firstMatch.isHittable)
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
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
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

        let applicationFrame = app.frame
        guard applicationFrame.minX.isFinite, applicationFrame.minY.isFinite,
              applicationFrame.width.isFinite, applicationFrame.height.isFinite,
              applicationFrame.width > 0, applicationFrame.height > 0 else {
            return XCTFail("Expected finite application geometry before timing source switches.")
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        var sourceTaps: [(id: String, source: XCUIElement, coordinate: XCUICoordinate)] = []
        for sourceID in sourceIDs {
            let source = app.buttons[sourceID]
            guard source.isHittable else {
                return XCTFail("Expected hittable source control \(sourceID) before timing.")
            }
            let frame = source.frame
            guard frame.minX.isFinite, frame.minY.isFinite,
                  frame.width.isFinite, frame.height.isFinite,
                  frame.width > 0, frame.height > 0,
                  applicationFrame.contains(frame), source.frame == frame,
                  app.frame == applicationFrame else {
                return XCTFail("Expected stable visible source geometry for \(sourceID).")
            }
            sourceTaps.append((sourceID, source, origin.withOffset(CGVector(
                dx: frame.midX - applicationFrame.minX,
                dy: frame.midY - applicationFrame.minY
            ))))
        }

        // Locate stable controls before measuring the four physical interactions.
        let startedAt = Date()
        for tap in sourceTaps {
            tap.coordinate.tap()
            XCTAssertTrue(
                tap.source.isSelected,
                "Dense-account source switch did not select \(tap.id)."
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
            // Warm up with the same complete interaction as the measured pass.
            // Every invocation restores the unselected map before returning.
            let options = XCTMeasureOptions()
            options.iterationCount = 1

            measure(metrics: [XCTHitchMetric(application: app)], options: options) {
                selectFirstPin.tap()
                XCTAssertTrue(card.waitForExistence(timeout: 3))
                XCTAssertTrue(activePin.waitForExistence(timeout: 2))

                // Exercise the same physical empty-map tap users use to close
                // the card. The fixed point is empty in this deterministic fixture.
                map.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.46)).tap()
                XCTAssertTrue(card.waitForNonExistence(timeout: 3))
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

    func testPerformanceFixtureSelectsPinAndDismissesCardOnEmptyMapTap() {
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
        let card = app.buttons["map.selectedPlaceCard"]
        let activePin = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "map.pin.active.saved.")
        ).firstMatch
        let selectFirstPin = app.buttons["map.performanceSelectFirstPin"]
        let nearby = app.buttons["map.nearby"]

        XCTAssertTrue(map.waitForExistence(timeout: 12))
        XCTAssertTrue(selectFirstPin.waitForExistence(timeout: 3))
        selectFirstPin.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(activePin.waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists, "The offscreen preloaded place page must not expose a modal alert")
        XCTAssertFalse(app.scrollViews["place-profile.scroll"].isHittable, "The preloaded page must not intercept touches before it is opened")

        map.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.46)).tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3))
        XCTAssertTrue(activePin.waitForNonExistence(timeout: 1))
        XCTAssertTrue(nearby.waitForExistence(timeout: 2))
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
        // The diagnostic view exists before MapKit finishes the initial camera.
        // Wait for that completion so a gesture cannot consume startup's result.
        let initialCamera = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "completion="), object: probe
        )
        XCTAssertEqual(XCTWaiter.wait(for: [initialCamera], timeout: 15), .completed)
        dismissStartupNotificationPromptIfNeeded(in: app)
        let previousProbe = probe.value as? String ?? ""
        let populatedProbe = NSPredicate { _, _ in
            let current = app.descendants(matching: .any)["map.performanceProbe"].firstMatch.value as? String ?? ""
            return current != previousProbe && current.contains("camera=")
        }
        let beforePanFrame = map.frame
        let beforePan = XCTAttachment(string:
            "probe=\(previousProbe)\nmapFrame=\(beforePanFrame)\n"
                + "normalizedStart=(0.72,0.42); normalizedEnd=(0.28,0.56); velocity=slow"
        )
        beforePan.name = "REC-404 selected-pin pan before probe and geometry"
        beforePan.lifetime = .keepAlways
        add(beforePan)

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
                withVelocity: .slow,
                thenHoldForDuration: 0.08
            )
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(predicate: populatedProbe, object: nil)
                    ],
                    timeout: 10
                ),
                .completed
            )
            didMeasurePan = true
        }
        XCTAssertTrue(didMeasurePan)

        let snapshot = String(describing: probe.value)
        print("REC404_MAP_PERFORMANCE_PROBE \(snapshot)")
        add(XCTAttachment(string: snapshot))

        let afterPanFrame = map.frame
        let afterPan = XCTAttachment(string: "probe=\(snapshot)\nmapFrame=\(afterPanFrame)")
        afterPan.name = "REC-404 selected-pin pan after probe and geometry"
        afterPan.lifetime = .keepAlways
        add(afterPan)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-404 dense map after selected-pin pan"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testPerformanceFixtureTracesDenseMapPanZoomWithoutCondensedPins() {
        traceDenseMapPanZoom(enforceFrameBudget: true)
    }

    func testPerformanceFixtureTracesDenseMapPanZoomAndBoundsAnnotationWork() {
        traceDenseMapPanZoom(enforceFrameBudget: false)
    }

    // Shared virtualized displays cannot establish a phone's frame cadence.
    // Both checks exercise the same cameras and annotation-work limits; the
    // original frame budget remains required on the reference simulator.
    private func traceDenseMapPanZoom(enforceFrameBudget: Bool) {
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
        // The diagnostic view exists before MapKit finishes the initial camera.
        // Wait for that completion so a gesture cannot consume startup's result.
        let initialCamera = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "completion="), object: probe
        )
        XCTAssertEqual(XCTWaiter.wait(for: [initialCamera], timeout: 15), .completed)

        func metric(_ name: String, in snapshot: String) -> Int? {
            snapshot
                .split(separator: ";")
                .first { $0.hasPrefix("\(name)=") }
                .flatMap { Int($0.dropFirst(name.count + 1)) }
        }

        func perform(_ label: String, button: XCUIElement) {
            let previousValue = app.descendants(matching: .any)["map.performanceProbe"].firstMatch.value as? String ?? ""
            XCTAssertTrue(button.isHittable)
            button.tap()
            let populatedProbe = NSPredicate { _, _ in
                let current = app.descendants(matching: .any)["map.performanceProbe"].firstMatch.value as? String ?? ""
                return current != previousValue && current.contains("camera=")
            }
            XCTAssertEqual(
                XCTWaiter.wait(
                    for: [XCTNSPredicateExpectation(predicate: populatedProbe, object: nil)],
                    timeout: 10
                ),
                .completed
            )
            let snapshot = app.descendants(matching: .any)["map.performanceProbe"].firstMatch.value as? String ?? ""
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
            if enforceFrameBudget {
                XCTAssertLessThan(
                    metric("maxFrameGapMs", in: snapshot) ?? .max,
                    100,
                    "Dense-map camera animation must not freeze for a visible fraction of a second"
                )
            }
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
            "-WanderUseStorefrontFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["map.filter.friends"].waitForExistence(timeout: 8))

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
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
            "-WanderMapCaptureMode", "friends"
        ]
        app.launch()

        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 5))

        let pin = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Griffith Observatory Trail,"))
            .firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 5))

        // Use the isolated trail marker at the initial camera. Nearby restaurant
        // markers can be collision-hidden while still exposing accessibility frames.
        let beforeTap = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        beforeTap.name = "Isolated Griffith trail pin before physical tap"
        beforeTap.lifetime = .keepAlways
        add(beforeTap)

        // Tap through the map at the rendered pin center. This exercises the
        // gesture bridge instead of dispatching the pin's accessibility action.
        let normalizedPinCenter = CGVector(
            dx: (pin.frame.midX - map.frame.minX) / map.frame.width,
            dy: (pin.frame.midY - map.frame.minY) / map.frame.height
        )
        map.coordinate(withNormalizedOffset: normalizedPinCenter).tap()

        let card = app.buttons["map.selectedPlaceCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("Griffith Observatory Trail"), "Selected card: \(card.label)")

        let unexpectedRecenterDismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: card
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [unexpectedRecenterDismissal], timeout: 1.2),
            .timedOut,
            "A programmatic pin recenter must not dismiss the selected place card."
        )
        XCTAssertTrue(card.exists)

        card.tap()
        XCTAssertTrue(
            app.staticTexts["Ratings"].waitForExistence(timeout: 3),
            "The first collapsed-card tap should open the place profile."
        )
        let unexpectedProfileDismissal = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.staticTexts["Ratings"]
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [unexpectedProfileDismissal], timeout: 1),
            .timedOut,
            "The place profile should remain presented after the recenter animation finishes."
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

    func testSelectedTicketKeepsSearchDockClearAndReachable() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderMapPlace", "Woodcat Coffee"
        ]
        app.launch()

        let card = app.buttons["map.selectedPlaceCard"]
        let message = app.staticTexts["map.searchMessage"]
        let search = app.textViews["map.searchField"]
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
        XCTAssertTrue(nearby.isHittable)
        XCTAssertGreaterThanOrEqual(nearby.frame.width, 44)
        XCTAssertGreaterThanOrEqual(nearby.frame.height, 44)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-293 selected card with reachable Nearby control"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLongPressShowsDroppedPinAsAStandardPlaceCard() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderAuthenticatedUITest",
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
        app.resetAuthorizationStatus(for: .location)
        addTeardownBlock {
            app.terminate()
            app.resetAuthorizationStatus(for: .location)
        }
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures"
        ]
        app.launch()

        let nearby = app.buttons["map.nearby"]
        XCTAssertTrue(nearby.waitForExistence(timeout: 5))
        XCTAssertEqual(nearby.value as? String, "Location permission needed")

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

        app.buttons["map.locationEducation.allow"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let permissionAlert = springboard.alerts.firstMatch
        XCTAssertTrue(permissionAlert.waitForExistence(timeout: 5))

        // Complete the native request before teardown resets authorization.
        // Terminating with an unanswered request can leave the next iteration
        // in the denied state instead of exercising the first-request primer.
        let deny = permissionAlert.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")
        ).firstMatch
        XCTAssertTrue(deny.waitForExistence(timeout: 2))
        deny.tap()
        XCTAssertTrue(permissionAlert.waitForNonExistence(timeout: 3))
    }

    func testCategoryDropdownSupportsMultipleCuisinesAndParentSelection() {
        let app = launchMoreFilters(source: "featured")
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let category = "restaurants_food"
        let parent = app.buttons["map.more.category.\(category)"]
        let expand = app.buttons["map.more.category.\(category).expand"]
        XCTAssertTrue(parent.waitForExistence(timeout: 3))
        parent.tap()
        XCTAssertTrue(parent.isSelected)
        expand.tap()
        XCTAssertTrue(parent.isSelected, "Expanding must not change selection")

        let american = app.buttons["map.more.category.\(category).option.American"]
        let mexican = app.buttons["map.more.category.\(category).option.Mexican"]
        XCTAssertTrue(american.waitForExistence(timeout: 3))
        XCTAssertTrue(american.isSelected)
        XCTAssertTrue(mexican.isSelected)
        american.tap()
        XCTAssertFalse(parent.isSelected)
        XCTAssertFalse(american.isSelected)
        XCTAssertTrue(mexican.isSelected)
        XCTAssertFalse(app.buttons["map.more.categories.all"].isSelected)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-671 all except one cuisines"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        expand.tap()
        expand.tap()
        XCTAssertFalse(american.isSelected, "Collapsing must preserve the excluded cuisine")
        XCTAssertTrue(mexican.isSelected)
        parent.tap()
        XCTAssertTrue(parent.isSelected)
        XCTAssertTrue(american.isSelected)
        XCTAssertTrue(mexican.isSelected)
        parent.tap()
        XCTAssertFalse(parent.isSelected)
        XCTAssertFalse(american.isSelected)
        XCTAssertFalse(mexican.isSelected)
        XCTAssertTrue(app.buttons["map.more.categories.all"].isSelected)
        american.tap()
        panel.buttons["Reset"].tap()
        XCTAssertTrue(app.buttons["map.more.categories.all"].isSelected)
    }

    func testCategoryDropdownSupportsMultipleSubcategories() {
        let app = launchMoreFilters()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        let category = "coffee_tea_sweets"
        let parent = app.buttons["map.more.category.\(category)"]
        XCTAssertTrue(parent.waitForExistence(timeout: 3))
        parent.tap()
        app.buttons["map.more.category.\(category).expand"].tap()
        let options = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "map.more.category.\(category).option."
        ))
        XCTAssertTrue(options.firstMatch.waitForExistence(timeout: 3))
        let first = options.element(boundBy: 0)
        let second = options.element(boundBy: 1)
        XCTAssertTrue(first.isSelected)
        XCTAssertTrue(second.isSelected)
        first.tap()
        XCTAssertFalse(parent.isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertTrue(second.isSelected)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "REC-671 all except one subcategories"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchMoreFilters(source: String = "friends", resetSeconds: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-WanderMapCapture",
            "-WanderUseDemoFixtures",
            "-WanderAuthenticatedUITest",
            "-WanderDisableWalkthroughs",
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

    func testMoreFiltersHidesMapDockAndBottomNavigationDismissesWithoutResetting() {
        let app = launchMoreFilters()
        let panel = app.scrollViews["map.moreFilters.popover"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        selectDemoPerson(in: app, panel: panel)

        let search = app.textViews["map.searchField"]
        let nearby = app.buttons["map.nearby"]
        let add = app.buttons["map.headerAdd"]
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Hidden Map dock accessibility tree"
        hierarchy.lifetime = .keepAlways
        self.add(hierarchy)
        if search.isHittable {
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "Map dock hidden while accessibility reports hittable"
            capture.lifetime = .keepAlways
            self.add(capture)
        }
        XCTAssertFalse(search.exists, "The hidden editor must leave the accessibility tree")
        XCTAssertFalse(search.isHittable)
        XCTAssertFalse(app.images["magnifyingglass"].exists, "The search icon is decorative; the native field supplies its label")
        XCTAssertFalse(nearby.isHittable)
        XCTAssertFalse(add.exists, "The hidden glass action must leave the accessibility tree")
        XCTAssertFalse(add.isHittable)

        let feed = app.buttons["Feed"]
        XCTAssertTrue(feed.isHittable)
        feed.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 2))
        XCTAssertTrue(feed.isSelected)

        app.buttons["Map"].tap()
        assertOneSelectedFilter(in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        XCTAssertTrue(search.isHittable, "Dismissing More filters must restore the retained editor")
        XCTAssertEqual(app.textViews.matching(identifier: "map.searchField").count, 1)
        XCTAssertTrue(add.waitForExistence(timeout: 2))
        XCTAssertTrue(add.isHittable)

        // Exercise real nonempty editor state too: hiding must remove the
        // clear action without removing the editor or discarding its query.
        search.tap()
        search.typeText("coffee")
        let clear = app.buttons["map.searchClear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        search.typeText("\n")
        let more = app.buttons["map.filter.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        XCTAssertTrue(search.waitForNonExistence(timeout: 3))
        XCTAssertEqual(app.textViews.matching(identifier: "map.searchField").count, 0)
        XCTAssertFalse(clear.exists)
        XCTAssertFalse(app.images["magnifyingglass"].exists)
        XCTAssertFalse(add.exists)
        XCTAssertFalse(app.buttons["map.searchCancel"].exists)
        let retainedHierarchy = XCTAttachment(string: app.debugDescription)
        retainedHierarchy.name = "Hidden Map dock with retained query accessibility tree"
        retainedHierarchy.lifetime = .keepAlways
        self.add(retainedHierarchy)
        panel.buttons["Done"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        let restoredHierarchy = XCTAttachment(string: app.debugDescription)
        restoredHierarchy.name = "Restored Map query accessibility tree"
        restoredHierarchy.lifetime = .keepAlways
        self.add(restoredHierarchy)
        XCTAssertTrue(search.isHittable)
        XCTAssertEqual(search.value as? String, "coffee")
        XCTAssertEqual(app.textViews.matching(identifier: "map.searchField").count, 1)
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertTrue(clear.isHittable)
        XCTAssertFalse(clear.frame.intersects(search.frame), "Clear must not cover the editor's accessibility frame")
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "The restored retained editor must accept a physical tap")
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
