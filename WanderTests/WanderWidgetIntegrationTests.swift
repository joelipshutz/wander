import XCTest
@testable import Wander

final class WanderWidgetIntegrationTests: XCTestCase {
    func testLaunchRequestsAreOneShotAndNormalizeSearchQueries() {
        let deepLinkID = UUID()
        let resetID = UUID()
        let addID = UUID()
        let searchID = UUID()
        let profileCalendarID = UUID()
        let profileCalendarTargetDate = Date(timeIntervalSince1970: 1_725_916_800)
        let nearbyCandidate = PlaceCandidate(
            id: "mapkit_ggiata",
            name: "Ggiata",
            category: "restaurants_food",
            latitude: 34.08,
            longitude: -118.26,
            sourceProviderPlaceID: "mapkit_ggiata",
            distanceMeters: 10.7,
            confidence: 0.9
        )

        XCTAssertEqual(
            WanderDeepLinkLaunchRequest(
                id: deepLinkID,
                route: .quickCapture
            ),
            WanderDeepLinkLaunchRequest(
                id: deepLinkID,
                route: .quickCapture
            )
        )
        XCTAssertNotEqual(
            WanderDeepLinkLaunchRequest(route: .quickCapture).id,
            WanderDeepLinkLaunchRequest(route: .quickCapture).id
        )
        XCTAssertEqual(
            WanderPresentationResetRequest(id: resetID),
            WanderPresentationResetRequest(id: resetID)
        )
        XCTAssertNotEqual(
            WanderPresentationResetRequest().id,
            WanderPresentationResetRequest().id
        )
        XCTAssertEqual(
            WanderAddLaunchRequest(id: addID, destination: .hereNow),
            WanderAddLaunchRequest(id: addID, destination: .hereNow)
        )
        XCTAssertEqual(
            WanderAddLaunchRequest(
                id: addID,
                destination: .nearbyPlace(nearbyCandidate)
            ),
            WanderAddLaunchRequest(
                id: addID,
                destination: .nearbyPlace(nearbyCandidate)
            )
        )
        XCTAssertEqual(WanderMapSearchLaunchRequest(id: searchID, query: "  Bar Nido  ").query, "Bar Nido")
        XCTAssertNil(WanderMapSearchLaunchRequest(id: searchID, query: " \n ").query)
        XCTAssertNotEqual(
            WanderMapSearchLaunchRequest(query: "Bar Nido").id,
            WanderMapSearchLaunchRequest(query: "Bar Nido").id
        )
        XCTAssertEqual(
            WanderProfileCalendarLaunchRequest(
                id: profileCalendarID,
                targetDate: profileCalendarTargetDate
            ),
            WanderProfileCalendarLaunchRequest(
                id: profileCalendarID,
                targetDate: profileCalendarTargetDate
            )
        )
        XCTAssertEqual(
            WanderProfileCalendarLaunchRequest(
                id: profileCalendarID,
                targetDate: profileCalendarTargetDate
            ).targetDate,
            profileCalendarTargetDate
        )
        XCTAssertEqual(
            WanderProfileCalendarLaunchRequest(
                id: profileCalendarID,
                targetDate: profileCalendarTargetDate
            ).destination,
            .calendar
        )
        XCTAssertEqual(
            WanderProfileCalendarLaunchRequest(
                id: profileCalendarID,
                targetDate: profileCalendarTargetDate,
                destination: .day
            ).destination,
            .day
        )
        XCTAssertNotEqual(
            WanderProfileCalendarLaunchRequest().id,
            WanderProfileCalendarLaunchRequest().id
        )
    }

    func testColdStartDeepLinkInboxKeepsQuickCaptureUntilSessionValidation() throws {
        var inbox = WanderDeepLinkInbox()

        inbox.receive(WanderWidgetConstants.quickCaptureURL)

        XCTAssertNil(inbox.request(ifSessionValidated: false))
        let request = try XCTUnwrap(
            inbox.request(ifSessionValidated: true)
        )
        XCTAssertEqual(request.route, .quickCapture)

        inbox.consume(UUID())
        XCTAssertEqual(inbox.pendingRequest, request)

        inbox.consume(request.id)
        XCTAssertNil(inbox.pendingRequest)
    }

    func testColdStartDeepLinkInboxIgnoresInvalidURLsAndLatestValidRequestWins() throws {
        var inbox = WanderDeepLinkInbox()

        inbox.receive(WanderWidgetConstants.quickCaptureURL)
        let firstRequest = try XCTUnwrap(inbox.pendingRequest)
        inbox.receive(try XCTUnwrap(URL(string: "https://example.com/not-recme")))
        XCTAssertEqual(inbox.pendingRequest, firstRequest)

        inbox.receive(WanderWidgetConstants.quickSearchURL)
        XCTAssertEqual(inbox.pendingRequest?.route, .quickSearch(query: nil))
        XCTAssertNotEqual(inbox.pendingRequest?.id, firstRequest.id)
    }

    func testDeepLinkHandoffWaitsForCurrentDismissalAndLatestRequestWins() {
        let staleRequestID = UUID()
        let latestRequestID = UUID()
        let presentedAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        var handoff = WanderDeepLinkHandoffCoordinator()

        handoff.begin(
            requestID: staleRequestID,
            route: .quickCapture,
            awaitingDismissals: [presentedAdd]
        )
        handoff.begin(
            requestID: latestRequestID,
            route: .quickSearch(query: "coffee"),
            awaitingDismissals: []
        )

        XCTAssertEqual(handoff.pendingRequestID, latestRequestID)
        XCTAssertEqual(handoff.awaitingDismissals, [presentedAdd])
        XCTAssertEqual(
            handoff.acknowledgeDismissal(presentedAdd),
            .quickSearch(query: "coffee")
        )
        XCTAssertNil(handoff.acknowledgeDismissal(presentedAdd))
    }

    func testDeepLinkHandoffKeepsActualGenerationsAcrossThreeRoutes() {
        let firstAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        let newerAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        let unmatchedAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        var handoff = WanderDeepLinkHandoffCoordinator()

        handoff.begin(
            requestID: UUID(),
            route: .quickCapture,
            awaitingDismissals: [firstAdd]
        )

        // A physically newer Add sheet can appear while the first generation
        // is still dismissing. Both generations must remain distinct blockers.
        handoff.addDismissalBlocker(newerAdd)
        handoff.begin(
            requestID: UUID(),
            route: .quickSearch(query: "coffee"),
            awaitingDismissals: [newerAdd]
        )
        let latestRequestID = UUID()
        handoff.begin(
            requestID: latestRequestID,
            route: .profileCalendar,
            awaitingDismissals: [newerAdd]
        )

        XCTAssertEqual(handoff.pendingRequestID, latestRequestID)
        XCTAssertEqual(handoff.awaitingDismissals, [firstAdd, newerAdd])

        // The old callback acknowledges only its own generation. It cannot
        // release the latest route while the newer sheet is still presented.
        XCTAssertNil(handoff.acknowledgeDismissal(firstAdd))
        XCTAssertEqual(handoff.awaitingDismissals, [newerAdd])
        XCTAssertNil(handoff.acknowledgeDismissal(firstAdd))
        XCTAssertNil(handoff.acknowledgeDismissal(unmatchedAdd))

        XCTAssertEqual(
            handoff.acknowledgeDismissal(newerAdd),
            .profileCalendar
        )
        XCTAssertNil(handoff.acknowledgeDismissal(newerAdd))
        XCTAssertNil(handoff.takeReadyRoute(requestID: latestRequestID))
    }

    @MainActor
    func testOlderAddDismissalCannotResetANewerPhysicalGeneration() {
        let olderAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        let newerAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )

        XCTAssertFalse(
            WanderRootView.shouldResetAddFlowAfterDismissal(
                olderAdd,
                remainingPresentedTokens: [newerAdd],
                isPresentingAdd: false
            )
        )
        XCTAssertFalse(
            WanderRootView.shouldResetAddFlowAfterDismissal(
                olderAdd,
                remainingPresentedTokens: [],
                isPresentingAdd: true
            )
        )
        XCTAssertTrue(
            WanderRootView.shouldResetAddFlowAfterDismissal(
                olderAdd,
                remainingPresentedTokens: [],
                isPresentingAdd: false
            )
        )
    }

    func testPresentationRegistryHandlesEitherSwiftUICallbackOrder() {
        let disappearFirst = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        let dismissFirst = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        var registry = WanderDeepLinkPresentationRegistry()

        XCTAssertTrue(registry.presentationDidAppear(disappearFirst))
        XCTAssertTrue(registry.presentationWillDisappear(disappearFirst))
        XCTAssertEqual(
            registry.sheetDidDismiss(surface: .add),
            disappearFirst
        )
        XCTAssertTrue(registry.tokensAwaitingDismissal.isEmpty)

        XCTAssertTrue(registry.presentationDidAppear(dismissFirst))
        XCTAssertEqual(
            registry.sheetDidDismiss(surface: .add),
            dismissFirst
        )
        XCTAssertFalse(registry.presentationWillDisappear(dismissFirst))
        XCTAssertTrue(registry.tokensAwaitingDismissal.isEmpty)
        XCTAssertNil(registry.sheetDidDismiss(surface: .add))
    }

    func testPresentationRegistryMapsDismissCallbackToOldestPhysicalGeneration() {
        let olderAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        let newerAdd = WanderDeepLinkPresentationToken(
            surface: .add,
            generation: UUID()
        )
        var registry = WanderDeepLinkPresentationRegistry()

        XCTAssertTrue(registry.presentationDidAppear(olderAdd))
        XCTAssertTrue(registry.presentationDidAppear(newerAdd))
        XCTAssertEqual(registry.sheetDidDismiss(surface: .add), olderAdd)
        XCTAssertEqual(registry.tokensAwaitingDismissal, [newerAdd])
        XCTAssertFalse(registry.presentationWillDisappear(olderAdd))
        XCTAssertEqual(registry.sheetDidDismiss(surface: .add), newerAdd)
        XCTAssertTrue(registry.tokensAwaitingDismissal.isEmpty)
    }

    @MainActor
    func testCalendarRefreshCompletionOnlyPublishesOnTrueToFalseEdge() {
        XCTAssertTrue(
            WanderRootView.calendarRefreshDidFinish(
                wasRefreshing: true,
                isRefreshing: false
            )
        )
        XCTAssertFalse(
            WanderRootView.calendarRefreshDidFinish(
                wasRefreshing: false,
                isRefreshing: true
            )
        )
        XCTAssertFalse(
            WanderRootView.calendarRefreshDidFinish(
                wasRefreshing: false,
                isRefreshing: false
            )
        )
        XCTAssertFalse(
            WanderRootView.calendarRefreshDidFinish(
                wasRefreshing: true,
                isRefreshing: true
            )
        )
    }

    @MainActor
    func testMapSearchCompletionGateRejectsStaleChangedAndCancelledRequests() {
        XCTAssertTrue(
            MapScreen.shouldApplyMapSearchCompletion(
                requestRevision: 4,
                currentRevision: 4,
                requestedQuery: "  Bar Nido ",
                currentQuery: "bar nido",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MapScreen.shouldApplyMapSearchCompletion(
                requestRevision: 3,
                currentRevision: 4,
                requestedQuery: "Bar Nido",
                currentQuery: "Bar Nido",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MapScreen.shouldApplyMapSearchCompletion(
                requestRevision: 4,
                currentRevision: 4,
                requestedQuery: "Old search",
                currentQuery: "Widget search",
                isCancelled: false
            )
        )
        XCTAssertFalse(
            MapScreen.shouldApplyMapSearchCompletion(
                requestRevision: 4,
                currentRevision: 4,
                requestedQuery: "Bar Nido",
                currentQuery: "Bar Nido",
                isCancelled: true
            )
        )
    }

    func testAppRoutesWidgetLaunchesIntoExistingAddAndMapFlows() throws {
        let app = try source("Wander/App/WanderApp.swift")
        let root = try source("Wander/App/WanderRootView.swift")
        let launchRequests = try source("Wander/App/WanderWidgetLaunchRequest.swift")
        let add = try source("Wander/Features/Add/AddScreen.swift")
        let map = try source("Wander/Features/Map/MapScreen.swift")
        let profileScreen = try source("Wander/Features/Profile/ProfileScreen.swift")
        let profileHome = try source("Wander/Features/Profile/ProfileOwnerHome.swift")

        XCTAssertTrue(app.contains(".onOpenURL { url in"))
        XCTAssertTrue(app.contains("deepLinkInbox.receive(url)"))
        XCTAssertTrue(app.contains("ifSessionValidated: destination == .authenticated"))
        XCTAssertTrue(app.contains("deepLinkInbox.consume(requestID)"))
        XCTAssertTrue(launchRequests.contains("WanderDeepLinkRoute.parse(url)"))
        XCTAssertTrue(launchRequests.contains("isSessionValidated ? pendingRequest : nil"))
        XCTAssertTrue(root.contains("handleDeepLinkLaunchRequestIfReady(request)"))
        XCTAssertTrue(root.contains("beginDeepLinkHandoff(to: request.route)"))
        XCTAssertFalse(root.contains(".onOpenURL"))
        XCTAssertTrue(root.contains("WanderAddLaunchRequest(destination: .hereNow)"))
        XCTAssertTrue(root.contains("case .nearbyPlace(let candidateID):"))
        XCTAssertTrue(root.contains("WanderNearbyWidgetSnapshotStore()"))
        XCTAssertTrue(root.contains("WanderAddLaunchRequest.Destination.nearbyPlace"))
        XCTAssertTrue(root.contains("WanderMapSearchLaunchRequest(query: query)"))
        XCTAssertTrue(root.contains("selectedTab = .profile"))
        XCTAssertTrue(root.contains("case .profileCalendarDate(let calendarDate):"))
        XCTAssertTrue(root.contains("destination: .calendar"))
        XCTAssertTrue(root.contains("destination: .day"))
        XCTAssertTrue(root.contains("presentationResetRequest: presentationResetRequest"))
        XCTAssertTrue(root.contains("deepLinkHandoffTask?.cancel()"))
        XCTAssertTrue(root.contains("let resetRequest = WanderPresentationResetRequest()"))
        XCTAssertTrue(root.contains("WanderDeepLinkPresentationToken"))
        XCTAssertTrue(
            root.contains(
                "@State private var presentedToken: WanderDeepLinkPresentationToken?"
            )
        )
        XCTAssertTrue(root.contains("let token = WanderDeepLinkPresentationToken(surface: surface)"))
        XCTAssertTrue(root.contains("WanderDeepLinkPresentationRegistry"))
        XCTAssertTrue(root.contains("deepLinkPresentations"))
        XCTAssertTrue(root.contains("presentationDidAppear(token)"))
        XCTAssertTrue(root.contains("presentationWillDisappear(token)"))
        XCTAssertTrue(root.contains("sheetDidDismiss("))
        XCTAssertTrue(root.contains("oldest still-presented generation"))
        XCTAssertTrue(root.contains("deepLinkHandoff.begin("))
        XCTAssertTrue(root.contains("awaitingDismissals: deepLinkPresentationTokensAwaitingDismissal()"))
        XCTAssertTrue(root.contains("inheritedDismissals.union(awaitingDismissals)"))
        XCTAssertTrue(root.contains("deepLinkHandoff.addDismissalBlocker(token)"))
        XCTAssertTrue(root.contains("resetRootPresentationsForDeepLink()"))
        XCTAssertTrue(root.contains("await Task.yield()"))
        XCTAssertFalse(root.contains("Task.sleep(for: .milliseconds(300))"))
        XCTAssertTrue(
            root.contains(
                ".sheet(isPresented: $isPresentingAdd, onDismiss: handleAddSheetDismissal)"
            )
        )
        XCTAssertTrue(root.contains(".fullScreenCover(item: $sharedProfile)"))
        XCTAssertTrue(root.contains("WanderRootPresentationLifecycle("))
        XCTAssertTrue(root.contains("onDismiss: handleDeepLinkPresentationWillDismiss"))
        XCTAssertTrue(root.contains("onDismiss: handleDeepLinkPresentationDismissalImmediately"))
        XCTAssertTrue(root.contains("presentedTokens.remove(token)"))
        XCTAssertTrue(root.contains("dismissingTokenOrder[token.surface"))
        XCTAssertTrue(root.contains("!isPresentingAdd"))
        XCTAssertTrue(root.contains("acknowledgeDismissal(token)"))
        XCTAssertTrue(root.contains("presentationResetRequest?.id == requestID"))
        XCTAssertTrue(root.contains("guard !Task.isCancelled"))
        XCTAssertTrue(root.contains("activateDeepLink(route)"))
        XCTAssertTrue(root.contains("addLaunchRequest = nil"))
        XCTAssertTrue(root.contains("mapSearchLaunchRequest = nil"))
        XCTAssertTrue(root.contains("profileCalendarLaunchRequest = nil"))
        XCTAssertTrue(root.contains("visitInvitationInboxRequestID = nil"))
        XCTAssertTrue(root.contains("isPresentingAdd = false"))
        XCTAssertTrue(root.contains("initialPresentation = nil"))
        XCTAssertTrue(root.contains("sharedProfile = nil"))
        XCTAssertTrue(root.contains("auth.activeGate = nil"))
        XCTAssertTrue(root.contains("auth.isPresentingNativeAuth = false"))
        XCTAssertLessThan(
            try XCTUnwrap(root.range(of: "resetRootPresentationsForDeepLink()")).lowerBound,
            try XCTUnwrap(root.range(of: "activateDeepLink(route)")).lowerBound
        )

        XCTAssertTrue(add.contains(".task(id: launchRequest?.id)"))
        XCTAssertTrue(add.contains("await resolveCurrentLocationCandidates()"))

        XCTAssertTrue(map.contains(".task(id: searchLaunchRequest?.id)"))
        XCTAssertTrue(map.contains("await handleMapSearchLaunchRequest(searchLaunchRequest)"))
        XCTAssertTrue(map.contains("mapSearchFocusRequestID = request.id"))
        XCTAssertTrue(map.contains(".task(id: focusRequestID)"))
        XCTAssertTrue(map.contains("scenePhase == .active"))
        XCTAssertTrue(map.contains("isFocused.wrappedValue = true"))
        XCTAssertTrue(map.contains("onFocusRequestHandled(focusRequestID)"))
        XCTAssertFalse(map.contains(".milliseconds(140)"))
        XCTAssertTrue(map.contains("requestedQuery: query"))
        XCTAssertTrue(map.contains("requestRevision: requestRevision"))
        XCTAssertTrue(map.contains("mapSearchTask?.cancel()"))
        XCTAssertTrue(map.contains("invalidateMapSearchRequest()"))
        XCTAssertTrue(map.contains("shouldApplyMapSearchCompletion("))
        XCTAssertTrue(map.contains("requestRevision == mapSearchRevision"))
        XCTAssertTrue(map.contains("isCancelled: Task.isCancelled"))
        XCTAssertTrue(
            map.contains(
                """
                guard Self.shouldApplyMapSearchCompletion(
                            requestRevision: requestRevision,
                            currentRevision: mapSearchRevision,
                            requestedQuery: requestedQuery,
                            currentQuery: mapQuery,
                            isCancelled: Task.isCancelled
                        ) else {
                            return
                        }
                        isSearchingMapKit = true
                """
            )
        )
        XCTAssertFalse(map.contains("await runMapSearch()"))
        XCTAssertTrue(map.contains(".focused(isFocused)"))
        XCTAssertTrue(map.contains("clearNativeMapFeatureSelection()"))
        XCTAssertTrue(map.contains(".task(id: presentationResetRequest?.id)"))
        XCTAssertTrue(map.contains("handledPresentationResetRequestID != request.id"))
        XCTAssertTrue(map.contains("resetMapPresentations()"))
        XCTAssertTrue(map.contains("mapSaveFlow = nil"))
        XCTAssertTrue(map.contains("isPlaceProfilePresented = false"))
        XCTAssertTrue(map.contains("selectedPlaceGroupKey = nil"))
        XCTAssertTrue(map.contains("selectedSearchCandidateID = nil"))

        XCTAssertTrue(profileScreen.contains("selectedMonth = request.targetDate"))
        XCTAssertTrue(profileScreen.contains(".task(id: presentationResetRequest?.id)"))
        XCTAssertTrue(profileScreen.contains("handledPresentationResetRequestID != request.id"))
        XCTAssertTrue(profileScreen.contains("resetProfilePresentations()"))
        XCTAssertTrue(profileScreen.contains("visitInvitationInboxRequestID = nil"))
        XCTAssertTrue(profileScreen.contains("showsSettings = false"))
        XCTAssertTrue(profileScreen.contains("showsProfilePhotoMenu = false"))
        XCTAssertTrue(profileScreen.contains("showsProfilePhotoLibrary = false"))
        XCTAssertTrue(profileScreen.contains("showsProfileCamera = false"))
        XCTAssertTrue(profileScreen.contains("selectedProfilePhotoItem = nil"))
        XCTAssertTrue(profileScreen.contains("socialGraphTab = nil"))
        XCTAssertTrue(profileScreen.contains("listMode = nil"))
        XCTAssertTrue(profileScreen.contains("savedListMode = nil"))
        XCTAssertTrue(profileScreen.contains("placeCollectionRoute = nil"))
        XCTAssertTrue(profileScreen.contains("showsVisitInvitations = false"))
        XCTAssertTrue(profileScreen.contains("showsEditProfile = false"))
        XCTAssertTrue(profileScreen.contains("activeCalendarLaunchRequest = request"))
        XCTAssertTrue(profileScreen.contains("calendarDaySummary(on: request.targetDate)"))
        XCTAssertTrue(profileScreen.contains("placeCollectionRoute = .calendar("))
        XCTAssertTrue(profileScreen.contains("store.currentUserCalendarProjection"))

        XCTAssertTrue(profileHome.contains(".id(ProfileHomeScrollAnchor.calendar)"))
        XCTAssertTrue(profileHome.contains(".scrollTargetLayout()"))
        XCTAssertTrue(profileHome.contains(".scrollPosition(id: $profileScrollPosition, anchor: .top)"))
        XCTAssertTrue(profileHome.contains(".task(id: calendarScrollRequestID)"))
        XCTAssertTrue(profileHome.contains("profileScrollPosition = ProfileHomeScrollAnchor.calendar"))
        XCTAssertTrue(profileHome.contains("profileScrollPosition == ProfileHomeScrollAnchor.calendar"))
        XCTAssertTrue(profileHome.contains("onCalendarScrollRequestHandled(calendarScrollRequestID)"))
        XCTAssertFalse(profileHome.contains("proxy.scrollTo(ProfileHomeScrollAnchor.calendar"))
        XCTAssertFalse(profileHome.contains("Task { @MainActor"))
    }

    func testProjectEmbedsSeparateLocationWidgetExtensionWithSharedAppGroup() throws {
        let project = try source("project.yml")
        let generatedProject = try source("Wander.xcodeproj/project.pbxproj")
        let appEntitlements = try propertyList("Wander/Resources/Wander.entitlements")
        let widgetEntitlements = try propertyList("WanderWidgets/WanderWidgets.entitlements")
        let nearbyWidgetEntitlements = try propertyList(
            "WanderNearbyWidgets/WanderNearbyWidgets.entitlements"
        )
        let widgetInfo = try propertyList("WanderWidgets/Info.plist")
        let nearbyWidgetInfo = try propertyList("WanderNearbyWidgets/Info.plist")

        XCTAssertTrue(project.contains("WanderWidgets:"))
        XCTAssertTrue(project.contains("type: app-extension"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.grayline.wander.widgets"))
        XCTAssertTrue(project.contains("APPLICATION_EXTENSION_API_ONLY: YES"))
        XCTAssertTrue(project.contains("SKIP_INSTALL: YES"))
        XCTAssertTrue(project.contains("embed: true"))
        XCTAssertTrue(project.contains("link: false"))
        XCTAssertTrue(project.contains("WanderNearbyWidgets:"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.grayline.wander.nearbywidgets"))
        XCTAssertTrue(project.contains("NSWidgetWantsLocation: true"))

        XCTAssertTrue(generatedProject.contains("WanderWidgets.appex"))
        XCTAssertTrue(generatedProject.contains("WanderNearbyWidgets.appex"))
        XCTAssertTrue(generatedProject.contains("Embed Foundation Extensions"))
        XCTAssertTrue(generatedProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.grayline.wander.widgets;"))
        XCTAssertTrue(
            generatedProject.contains(
                "PRODUCT_BUNDLE_IDENTIFIER = com.grayline.wander.nearbywidgets;"
            )
        )

        let appGroups = try XCTUnwrap(appEntitlements["com.apple.security.application-groups"] as? [String])
        let widgetGroups = try XCTUnwrap(widgetEntitlements["com.apple.security.application-groups"] as? [String])
        let nearbyWidgetGroups = try XCTUnwrap(
            nearbyWidgetEntitlements["com.apple.security.application-groups"] as? [String]
        )
        XCTAssertEqual(appGroups, [WanderWidgetConstants.appGroupIdentifier])
        XCTAssertEqual(widgetGroups, [WanderWidgetConstants.appGroupIdentifier])
        XCTAssertEqual(nearbyWidgetGroups, [WanderWidgetConstants.appGroupIdentifier])

        let extensionDictionary = try XCTUnwrap(widgetInfo["NSExtension"] as? [String: Any])
        XCTAssertEqual(
            extensionDictionary["NSExtensionPointIdentifier"] as? String,
            "com.apple.widgetkit-extension"
        )
        XCTAssertNil(extensionDictionary["NSExtensionPrincipalClass"])

        let nearbyExtensionDictionary = try XCTUnwrap(
            nearbyWidgetInfo["NSExtension"] as? [String: Any]
        )
        XCTAssertEqual(
            nearbyExtensionDictionary["NSExtensionPointIdentifier"] as? String,
            "com.apple.widgetkit-extension"
        )
        XCTAssertEqual(nearbyWidgetInfo["NSWidgetWantsLocation"] as? Bool, true)
        XCTAssertNil(nearbyExtensionDictionary["NSExtensionPrincipalClass"])
    }

    func testWidgetBundleContainsThreeNativeWidgetConfigurationsWithoutTextInput() throws {
        let widgetSource = try source("WanderWidgets/WanderWidgets.swift")

        XCTAssertTrue(widgetSource.contains("WanderQuickCaptureWidget()"))
        XCTAssertTrue(widgetSource.contains("WanderQuickSearchWidget()"))
        XCTAssertTrue(widgetSource.contains("WanderActivityCalendarWidget()"))
        XCTAssertTrue(widgetSource.contains(".systemSmall"))
        XCTAssertTrue(widgetSource.contains(".systemMedium"))
        XCTAssertTrue(widgetSource.contains(".systemLarge"))
        XCTAssertTrue(widgetSource.contains(".accessoryCircular"))
        XCTAssertTrue(widgetSource.contains(".accessoryRectangular"))
        XCTAssertTrue(widgetSource.contains("WanderCircularWidgetArcText("))
        XCTAssertTrue(widgetSource.contains("text: \"rec.me\""))
        XCTAssertTrue(widgetSource.contains("Image(systemName: \"plus\")"))
        XCTAssertTrue(widgetSource.contains("text: \"CHECK-IN\""))
        XCTAssertTrue(
            widgetSource.contains(
                "min(geometry.size.width, geometry.size.height) / 2 - 10"
            )
        )
        XCTAssertEqual(
            widgetSource.components(separatedBy: "radius: ringBandRadius").count - 1,
            2
        )
        XCTAssertFalse(widgetSource.contains(".padding(10)"))
        XCTAssertTrue(widgetSource.contains("case .top: -radius"))
        XCTAssertTrue(widgetSource.contains("case .bottom: radius"))
        XCTAssertTrue(widgetSource.contains("case .top: 19"))
        XCTAssertTrue(widgetSource.contains("case .bottom: -14.5"))
        XCTAssertTrue(widgetSource.contains("case .top: 11"))
        XCTAssertTrue(widgetSource.contains("case .bottom: 9.5"))
        XCTAssertTrue(
            widgetSource.contains(
                "size: placement.fontSize,\n" +
                    "                            weight: .black,\n" +
                    "                            design: .default"
            )
        )
        XCTAssertTrue(widgetSource.contains("Quick capture — Lock Screen"))
        XCTAssertFalse(widgetSource.contains("TextField("))
        XCTAssertTrue(widgetSource.contains(".widgetURL("))
        XCTAssertTrue(widgetSource.contains("Link(destination: destination)"))
        XCTAssertTrue(widgetSource.contains("WanderDeepLinkRoute.profileCalendarDate(date).url"))
        XCTAssertTrue(widgetSource.contains("containerBackground(for: .widget)"))
        XCTAssertTrue(widgetSource.contains("if model.needsRefresh"))
        XCTAssertFalse(widgetSource.contains("?? snapshot.currentMonth"))
        XCTAssertTrue(widgetSource.contains("WanderCalendarTimelineSchedule.make("))
        XCTAssertTrue(widgetSource.contains("See your been activity for the current month."))
        XCTAssertFalse(widgetSource.contains("model.wannaCount"))
        XCTAssertFalse(widgetSource.contains("Wanna:"))
    }

    func testNearbyWidgetIsLargeLocationAwareAndRoutesFiveRowsIntoRichVisit() throws {
        let widgetSource = try source("WanderNearbyWidgets/WanderNearbyWidget.swift")
        let sharedSnapshot = try source(
            "WanderWidgetShared/WanderNearbyWidgetSnapshot.swift"
        )
        let publisher = try source(
            "Wander/Widgets/WanderNearbyWidgetSnapshotPublisher.swift"
        )
        let root = try source("Wander/App/WanderRootView.swift")
        let add = try source("Wander/Features/Add/AddScreen.swift")

        XCTAssertTrue(widgetSource.contains(".supportedFamilies([.systemLarge])"))
        XCTAssertTrue(widgetSource.contains("WanderNearbyWidgetLocationProvider"))
        XCTAssertTrue(widgetSource.contains("isAuthorizedForWidgetUpdates"))
        XCTAssertTrue(widgetSource.contains("CLLocationDistance(200)"))
        XCTAssertTrue(widgetSource.contains("CLLocationDistance(400)"))
        XCTAssertTrue(widgetSource.contains("CLLocationDistance(800)"))
        XCTAssertTrue(widgetSource.contains("var reloadInterval: TimeInterval"))
        XCTAssertTrue(widgetSource.contains("case .ready, .noPlaces:"))
        XCTAssertTrue(widgetSource.contains("case .locationTemporarilyUnavailable:"))
        XCTAssertTrue(widgetSource.contains("Link(destination: destination)"))
        XCTAssertTrue(widgetSource.contains(".nearbyPlace(candidateID: place.id)"))
        XCTAssertTrue(widgetSource.contains("Text(\"Nearby spots\")"))
        XCTAssertTrue(widgetSource.contains("\"tap a place to check-in\""))
        XCTAssertTrue(widgetSource.contains("Label(\"See all\", systemImage: \"chevron.right\")"))
        XCTAssertTrue(widgetSource.contains("Image(systemName: \"plus\")"))
        XCTAssertFalse(widgetSource.contains("Image(systemName: \"arrow.up.right\")"))
        XCTAssertFalse(widgetSource.contains("style: .relative"))
        XCTAssertTrue(sharedSnapshot.contains("static let maximumVisiblePlaces = 5"))
        XCTAssertTrue(sharedSnapshot.contains("static let exactDistanceLifetime"))
        XCTAssertTrue(publisher.contains("WidgetCenter.shared.currentConfigurations()"))
        XCTAssertTrue(publisher.contains("case .unknown:"))
        XCTAssertTrue(publisher.contains("case .notConfigured:"))
        XCTAssertFalse(publisher.contains("store.currentLocationCandidates()"))
        XCTAssertTrue(publisher.contains("reloadTimelines("))
        XCTAssertTrue(publisher.contains("WanderNearbyWidgetSnapshotStore.freshnessWriteInterval"))
        XCTAssertTrue(publisher.contains("isAuthorizedForWidgetUpdates"))
        XCTAssertTrue(root.contains("refreshNearbyWidgetSnapshot()"))
        XCTAssertTrue(root.contains("case .map:"))
        XCTAssertTrue(root.contains("case .nearbyPlace(let candidateID):"))
        XCTAssertTrue(add.contains("case .nearbyPlace(let candidate):"))
        XCTAssertTrue(add.contains("MapPlaceSaveContext.addCandidate("))
    }

    @MainActor
    func testCalendarPublisherMatchesOwnerProfilePresenterAndClearsUnavailableData() throws {
        let now = Date()
        let store = WanderStore(fixtures: WanderFixtures.seed())
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wander-widget-publisher-\(UUID().uuidString).json")
        let snapshotStore = WanderCalendarWidgetSnapshotStore(fileURL: fileURL)

        WanderWidgetSnapshotPublisher.publish(
            store: store,
            isAvailable: true,
            now: now,
            snapshotStore: snapshotStore
        )

        let snapshot = try XCTUnwrap(snapshotStore.load())
        let expected = ProfileInsightsPresenter.present(
            ownerID: store.currentUser.id,
            userPlaces: store.userPlaces,
            visits: store.placeVisits,
            places: store.places,
            month: now
        )

        XCTAssertEqual(snapshot.currentMonth.beenCount, expected.monthVisitCount)
        XCTAssertEqual(expected.monthWannaCount, 0)
        XCTAssertEqual(snapshot.currentMonth.wannaCount, 0)
        for summary in expected.monthDaySummaries.values {
            let dayNumber = Calendar.current.component(.day, from: summary.date)
            let day = try XCTUnwrap(snapshot.currentMonth.day(dayNumber))
            XCTAssertEqual(day.beenCount, summary.visitCount)
            XCTAssertEqual(summary.wannaCount, 0)
            XCTAssertEqual(day.wannaCount, 0)
        }

        WanderWidgetSnapshotPublisher.publish(
            store: store,
            isAvailable: false,
            now: now,
            snapshotStore: snapshotStore
        )
        XCTAssertNil(snapshotStore.load())
    }

    func testWidgetPublishingWaitsForLiveCalendarHydrationAndClearsAnyStoredFile() throws {
        let root = try source("Wander/App/WanderRootView.swift")
        let publisher = try source("Wander/Widgets/WanderWidgetSnapshotPublisher.swift")
        let snapshot = try source("WanderWidgetShared/WanderCalendarWidgetSnapshot.swift")

        XCTAssertTrue(root.contains("widgetCalendarIdentityUserID"))
        XCTAssertTrue(root.contains("widgetCalendarHydratedUserID"))
        XCTAssertTrue(root.contains("widgetCalendarLastHydratedAt"))
        XCTAssertTrue(root.contains("calendarRefreshDue"))
        XCTAssertTrue(root.contains("refreshRemoteCurrentUserCalendarData"))
        XCTAssertTrue(root.contains(".onChange(of: store.currentUserCalendarHydrationRevision)"))
        XCTAssertTrue(root.contains("handleCurrentUserCalendarHydration(revision: revision)"))
        XCTAssertTrue(root.contains(".onChange(of: store.isRefreshingCurrentUserCalendarData)"))
        XCTAssertTrue(root.contains("calendarRefreshDidFinish("))
        XCTAssertTrue(root.contains("wasRefreshing && !isRefreshing"))
        XCTAssertTrue(root.contains("guard !store.isRefreshingCurrentUserCalendarData else { return }"))
        XCTAssertTrue(root.contains("store.currentUserCalendarProjection.isAuthoritative"))
        XCTAssertTrue(root.contains("publishWidgetSnapshot(allowFreshnessAdvance: true)"))
        XCTAssertTrue(root.contains("guard widgetCalendarHydratedUserID == store.currentUser.id"))
        XCTAssertTrue(root.contains("widgetCalendarIdentityUserID != session.userID"))
        XCTAssertGreaterThanOrEqual(
            root.components(separatedBy: "WanderWidgetSnapshotPublisher.clear()").count - 1,
            2
        )
        XCTAssertLessThan(
            try XCTUnwrap(root.range(of: "WanderWidgetSnapshotPublisher.clear()")).lowerBound,
            try XCTUnwrap(root.range(of: "store.apply(authState: state)")).lowerBound
        )
        XCTAssertTrue(publisher.contains("_ = try snapshotStore.remove()"))
        XCTAssertTrue(publisher.contains("allowFreshnessAdvance: allowFreshnessAdvance"))
        XCTAssertTrue(publisher.contains("store.currentUserCalendarProjection"))
        XCTAssertTrue(snapshot.contains(".appendingPathComponent(\"Library\", isDirectory: true)"))
        XCTAssertTrue(snapshot.contains(".appendingPathComponent(\"Caches\", isDirectory: true)"))
        XCTAssertTrue(snapshot.contains("resourceValues.isExcludedFromBackup = true"))
    }

    func testNearbyWidgetRefreshesInteractivelyAndRoutesSeeAllToHereNow() throws {
        let widget = try source("WanderNearbyWidgets/WanderNearbyWidget.swift")
        let sharedSnapshot = try source(
            "WanderWidgetShared/WanderNearbyWidgetSnapshot.swift"
        )

        XCTAssertTrue(widget.contains("Button(intent: WanderRefreshNearbyPlacesIntent())"))
        XCTAssertTrue(widget.contains("private var refreshFooter: some View"))
        XCTAssertTrue(widget.contains("unavailableState\n            }\n\n            refreshFooter"))
        XCTAssertTrue(widget.contains("TimelineView(.everyMinute)"))
        XCTAssertTrue(widget.contains("now: context.date"))
        XCTAssertTrue(widget.contains("entry.availability != .locationAuthorizationRequired"))
        XCTAssertTrue(widget.contains("try? snapshotStore.clear()"))
        XCTAssertTrue(widget.contains("\"Refreshing…\" : \"Refresh\""))
        XCTAssertTrue(widget.contains("if case .refreshing = refreshStateStore.state(at: startedAt)"))
        XCTAssertTrue(widget.contains("refreshStateStore.begin(at: startedAt)"))
        XCTAssertTrue(widget.contains("refreshStateStore.complete("))
        XCTAssertTrue(widget.contains("requestID: requestID"))
        XCTAssertTrue(widget.contains("forceFreshnessAdvance: true"))
        XCTAssertTrue(sharedSnapshot.contains("snapshot.generatedAt < existing.generatedAt"))
        XCTAssertTrue(
            widget.contains(
                "WidgetCenter.shared.reloadTimelines(ofKind: WanderWidgetConstants.nearbyPlacesKind)"
            )
        )
        XCTAssertTrue(widget.contains("Link(destination: WanderWidgetConstants.quickCaptureURL)"))
        XCTAssertTrue(widget.contains(".widgetURL(WanderWidgetConstants.quickCaptureURL)"))
        XCTAssertFalse(widget.contains("Link(destination: WanderWidgetConstants.mapURL)"))
        XCTAssertTrue(widget.contains(".contentMarginsDisabled()"))
        XCTAssertTrue(widget.contains(".padding(.horizontal, 12)"))
        XCTAssertTrue(sharedSnapshot.contains("case refreshing(startedAt: Date)"))
        XCTAssertTrue(sharedSnapshot.contains("case completed(at: Date"))
    }

    func testAppAndExtensionShareOneBuildNumberSource() throws {
        let project = try source("project.yml")
        let declarations = project.components(separatedBy: "CURRENT_PROJECT_VERSION:").count - 1

        XCTAssertEqual(declarations, 1)
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"103\""))
        XCTAssertEqual(
            project.components(separatedBy: "CFBundleVersion: $(CURRENT_PROJECT_VERSION)").count - 1,
            4
        )
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectRoot.appendingPathComponent(relativePath))
    }

    private func propertyList(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
