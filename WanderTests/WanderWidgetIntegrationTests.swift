import XCTest
@testable import Wander

final class WanderWidgetIntegrationTests: XCTestCase {
    func testLaunchRequestsAreOneShotAndNormalizeSearchQueries() {
        let resetID = UUID()
        let addID = UUID()
        let searchID = UUID()
        let profileCalendarID = UUID()
        let profileCalendarTargetDate = Date(timeIntervalSince1970: 1_725_916_800)

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
        XCTAssertNotEqual(
            WanderProfileCalendarLaunchRequest().id,
            WanderProfileCalendarLaunchRequest().id
        )
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
        let root = try source("Wander/App/WanderRootView.swift")
        let add = try source("Wander/Features/Add/AddScreen.swift")
        let map = try source("Wander/Features/Map/MapScreen.swift")
        let profileScreen = try source("Wander/Features/Profile/ProfileScreen.swift")
        let profileHome = try source("Wander/Features/Profile/ProfileOwnerHome.swift")

        XCTAssertTrue(root.contains("WanderDeepLinkRoute.parse(url)"))
        XCTAssertTrue(root.contains("WanderAddLaunchRequest(destination: .hereNow)"))
        XCTAssertTrue(root.contains("WanderMapSearchLaunchRequest(query: query)"))
        XCTAssertTrue(root.contains("selectedTab = .profile"))
        XCTAssertTrue(root.contains("WanderProfileCalendarLaunchRequest(targetDate: .now)"))
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
        XCTAssertTrue(map.contains("isMapSearchFocused = true"))
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

    func testProjectEmbedsOneWidgetExtensionWithSharedAppGroup() throws {
        let project = try source("project.yml")
        let generatedProject = try source("Wander.xcodeproj/project.pbxproj")
        let appEntitlements = try propertyList("Wander/Resources/Wander.entitlements")
        let widgetEntitlements = try propertyList("WanderWidgets/WanderWidgets.entitlements")
        let widgetInfo = try propertyList("WanderWidgets/Info.plist")

        XCTAssertTrue(project.contains("WanderWidgets:"))
        XCTAssertTrue(project.contains("type: app-extension"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER: com.grayline.wander.widgets"))
        XCTAssertTrue(project.contains("APPLICATION_EXTENSION_API_ONLY: YES"))
        XCTAssertTrue(project.contains("SKIP_INSTALL: YES"))
        XCTAssertTrue(project.contains("embed: true"))
        XCTAssertTrue(project.contains("link: false"))

        XCTAssertTrue(generatedProject.contains("WanderWidgets.appex"))
        XCTAssertTrue(generatedProject.contains("Embed Foundation Extensions"))
        XCTAssertTrue(generatedProject.contains("PRODUCT_BUNDLE_IDENTIFIER = com.grayline.wander.widgets;"))

        let appGroups = try XCTUnwrap(appEntitlements["com.apple.security.application-groups"] as? [String])
        let widgetGroups = try XCTUnwrap(widgetEntitlements["com.apple.security.application-groups"] as? [String])
        XCTAssertEqual(appGroups, [WanderWidgetConstants.appGroupIdentifier])
        XCTAssertEqual(widgetGroups, [WanderWidgetConstants.appGroupIdentifier])

        let extensionDictionary = try XCTUnwrap(widgetInfo["NSExtension"] as? [String: Any])
        XCTAssertEqual(
            extensionDictionary["NSExtensionPointIdentifier"] as? String,
            "com.apple.widgetkit-extension"
        )
        XCTAssertNil(extensionDictionary["NSExtensionPrincipalClass"])
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
        XCTAssertFalse(widgetSource.contains("TextField("))
        XCTAssertTrue(widgetSource.contains(".widgetURL("))
        XCTAssertTrue(widgetSource.contains("containerBackground(for: .widget)"))
        XCTAssertTrue(widgetSource.contains("if model.needsRefresh"))
        XCTAssertFalse(widgetSource.contains("?? snapshot.currentMonth"))
        XCTAssertTrue(widgetSource.contains("WanderCalendarTimelineSchedule.make("))
        XCTAssertTrue(widgetSource.contains("See your been activity for the current month."))
        XCTAssertFalse(widgetSource.contains("model.wannaCount"))
        XCTAssertFalse(widgetSource.contains("Wanna:"))
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

    func testAppAndExtensionShareOneBuildNumberSource() throws {
        let project = try source("project.yml")
        let declarations = project.components(separatedBy: "CURRENT_PROJECT_VERSION:").count - 1

        XCTAssertEqual(declarations, 1)
        XCTAssertTrue(project.contains("CURRENT_PROJECT_VERSION: \"98\""))
        XCTAssertEqual(
            project.components(separatedBy: "CFBundleVersion: $(CURRENT_PROJECT_VERSION)").count - 1,
            2
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
