import SwiftUI
import UIKit

enum WanderDeepLinkPresentationSurface: Hashable, Sendable {
    case add
    case authGate
    case nativeAuth
    case initialPresentation
    case profileSettings
    case sharedProfile
}

struct WanderDeepLinkPresentationToken: Hashable, Sendable {
    let surface: WanderDeepLinkPresentationSurface
    let generation: UUID

    init(
        surface: WanderDeepLinkPresentationSurface,
        generation: UUID = UUID()
    ) {
        self.surface = surface
        self.generation = generation
    }
}

private struct SharedPlaceImportDrainNotice: Identifiable {
    let id = UUID()
    let report: SharedPlaceImportDrainReport

    var title: String {
        if report.importedOrDuplicateBatchCount > 0,
           report.failedEnvelopeCount + report.quarantinedEnvelopeCount + report.expiredEnvelopeCount > 0 {
            return "Some shared places were captured"
        }
        if report.importedOrDuplicateBatchCount > 0 {
            return "Shared places captured"
        }
        return "Shared import needs attention"
    }

    var message: String {
        var parts: [String] = []
        if report.importedBatchCount > 0 {
            parts.append(
                "\(report.importedBatchCount) import\(report.importedBatchCount == 1 ? " is" : "s are") ready to review."
            )
        }
        if report.duplicateBatchCount > 0 {
            parts.append(
                "\(report.duplicateBatchCount) import\(report.duplicateBatchCount == 1 ? " was" : "s were") already captured."
            )
        }
        let unavailableCount = report.failedEnvelopeCount
            + report.quarantinedEnvelopeCount
            + report.expiredEnvelopeCount
        if unavailableCount > 0 {
            parts.append(
                "\(unavailableCount) shared item\(unavailableCount == 1 ? "" : "s") could not be recovered. Share \(unavailableCount == 1 ? "it" : "them") again."
            )
        }
        return parts.joined(separator: " ")
    }

    var canReview: Bool {
        report.importedOrDuplicateBatchCount > 0
    }
}

private struct SharedPlaceImportAlertModifier: ViewModifier {
    @Binding var notice: SharedPlaceImportDrainNotice?
    let onReview: () -> Void

    func body(content: Content) -> some View {
        content.alert(item: $notice) { notice in
            if notice.canReview {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Review"), action: onReview),
                    secondaryButton: .cancel(Text("Later"))
                )
            }
            return Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct WanderDeepLinkHandoffCoordinator {
    private struct PendingHandoff {
        let requestID: UUID
        let route: WanderDeepLinkRoute
        var awaitingDismissals: Set<WanderDeepLinkPresentationToken>
    }

    private var pendingHandoff: PendingHandoff?

    var pendingRequestID: UUID? {
        pendingHandoff?.requestID
    }

    var awaitingDismissals: Set<WanderDeepLinkPresentationToken> {
        pendingHandoff?.awaitingDismissals ?? []
    }

    mutating func begin(
        requestID: UUID,
        route: WanderDeepLinkRoute,
        awaitingDismissals: Set<WanderDeepLinkPresentationToken>
    ) {
        let inheritedDismissals = pendingHandoff?.awaitingDismissals ?? []
        pendingHandoff = PendingHandoff(
            requestID: requestID,
            route: route,
            awaitingDismissals: inheritedDismissals.union(awaitingDismissals)
        )
    }

    mutating func addDismissalBlocker(_ token: WanderDeepLinkPresentationToken) {
        guard var handoff = pendingHandoff else { return }

        handoff.awaitingDismissals.insert(token)
        pendingHandoff = handoff
    }

    mutating func acknowledgeDismissal(
        _ token: WanderDeepLinkPresentationToken
    ) -> WanderDeepLinkRoute? {
        guard var handoff = pendingHandoff,
              handoff.awaitingDismissals.remove(token) != nil
        else {
            return nil
        }

        let requestID = handoff.requestID
        pendingHandoff = handoff
        return takeReadyRoute(requestID: requestID)
    }

    mutating func takeReadyRoute(requestID: UUID) -> WanderDeepLinkRoute? {
        guard let handoff = pendingHandoff,
              handoff.requestID == requestID,
              handoff.awaitingDismissals.isEmpty
        else {
            return nil
        }

        pendingHandoff = nil
        return handoff.route
    }

    mutating func cancel() {
        pendingHandoff = nil
    }
}

struct WanderDeepLinkPresentationRegistry {
    private(set) var presentedTokens: Set<WanderDeepLinkPresentationToken> = []
    private var presentedTokenOrder:
        [WanderDeepLinkPresentationSurface: [WanderDeepLinkPresentationToken]] = [:]
    private var dismissingTokenOrder:
        [WanderDeepLinkPresentationSurface: [WanderDeepLinkPresentationToken]] = [:]

    var tokensAwaitingDismissal: Set<WanderDeepLinkPresentationToken> {
        let dismissingTokens = dismissingTokenOrder.values.flatMap { $0 }
        return presentedTokens.union(dismissingTokens)
    }

    @discardableResult
    mutating func presentationDidAppear(
        _ token: WanderDeepLinkPresentationToken
    ) -> Bool {
        guard presentedTokens.insert(token).inserted else { return false }

        presentedTokenOrder[token.surface, default: []].append(token)
        return true
    }

    @discardableResult
    mutating func presentationWillDisappear(
        _ token: WanderDeepLinkPresentationToken
    ) -> Bool {
        guard presentedTokens.remove(token) != nil else { return false }

        removePresentedTokenFromOrder(token)
        dismissingTokenOrder[token.surface, default: []].append(token)
        return true
    }

    mutating func sheetDidDismiss(
        surface: WanderDeepLinkPresentationSurface
    ) -> WanderDeepLinkPresentationToken? {
        if let token = Self.popFirstToken(
            for: surface,
            from: &dismissingTokenOrder
        ) {
            return token
        }

        // SwiftUI can call a sheet's onDismiss before the presented content's
        // onDisappear. Fall back to the oldest still-presented generation so
        // either callback order acknowledges the same physical sheet.
        guard let token = Self.popFirstToken(
            for: surface,
            from: &presentedTokenOrder
        ) else {
            return nil
        }
        presentedTokens.remove(token)
        return token
    }

    @discardableResult
    mutating func presentationDidDismissImmediately(
        _ token: WanderDeepLinkPresentationToken
    ) -> Bool {
        guard presentedTokens.remove(token) != nil else { return false }

        removePresentedTokenFromOrder(token)
        return true
    }

    mutating func removeAll() {
        presentedTokens.removeAll()
        presentedTokenOrder.removeAll()
        dismissingTokenOrder.removeAll()
    }

    private mutating func removePresentedTokenFromOrder(
        _ token: WanderDeepLinkPresentationToken
    ) {
        guard var tokens = presentedTokenOrder[token.surface] else { return }

        tokens.removeAll { $0 == token }
        presentedTokenOrder[token.surface] = tokens.isEmpty ? nil : tokens
    }

    private static func popFirstToken(
        for surface: WanderDeepLinkPresentationSurface,
        from tokenOrder: inout [
            WanderDeepLinkPresentationSurface: [WanderDeepLinkPresentationToken]
        ]
    ) -> WanderDeepLinkPresentationToken? {
        guard var tokens = tokenOrder[surface], !tokens.isEmpty else {
            return nil
        }

        let token = tokens.removeFirst()
        tokenOrder[surface] = tokens.isEmpty ? nil : tokens
        return token
    }
}

struct WanderRootPresentationLifecycle<Content: View>: View {
    let surface: WanderDeepLinkPresentationSurface
    let onPresent: (WanderDeepLinkPresentationToken) -> Void
    let onDismiss: (WanderDeepLinkPresentationToken) -> Void
    @ViewBuilder let content: () -> Content

    @State private var presentedToken: WanderDeepLinkPresentationToken?

    var body: some View {
        content()
            .onAppear(perform: presentationDidAppear)
            .onDisappear(perform: presentationDidDisappear)
    }

    private func presentationDidAppear() {
        guard presentedToken == nil else { return }

        let token = WanderDeepLinkPresentationToken(surface: surface)
        presentedToken = token
        onPresent(token)
    }

    private func presentationDidDisappear() {
        guard let token = presentedToken else { return }

        presentedToken = nil
        onDismiss(token)
    }
}

@MainActor
struct WanderRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var selectedTab: WanderTab
    @State private var addTabResetToken = UUID()
    @State private var isPresentingAdd = false
    @State private var addSheetDetent: PresentationDetent
    @State private var addLaunchRequest: WanderAddLaunchRequest?
    @State private var mapSearchLaunchRequest: WanderMapSearchLaunchRequest?
    @State private var profileCalendarLaunchRequest: WanderProfileCalendarLaunchRequest?
    @State private var presentationResetRequest: WanderPresentationResetRequest?
    @State private var deepLinkHandoffTask: Task<Void, Never>?
    @State private var deepLinkHandoff = WanderDeepLinkHandoffCoordinator()
    @State private var deepLinkPresentations = WanderDeepLinkPresentationRegistry()
    @State private var handledDeepLinkLaunchRequestID: UUID?
    @State private var initialPresentation: WanderInitialPresentation?
    @State private var sharedProfile: SharedProfileRoute?
    @State private var signedInMaintenanceTask: Task<Void, Never>?
    @State private var signedInMaintenanceRunID: UUID?
    @State private var signedInMaintenanceUserID: String?
    @State private var widgetCalendarIdentityUserID: String?
    @State private var widgetCalendarHydratedUserID: String?
    @State private var widgetCalendarLastHydratedAt: Date?
    @State private var nearbyWidgetRefreshTask: Task<Void, Never>?
    @State private var sharedVisitBannerInvitation: SharedVisitInvitation?
    @State private var sharedVisitBannerTracker = SharedVisitBannerTracker()
    @State private var sharedVisitBannerTask: Task<Void, Never>?
    @State private var visitInvitationInboxRequestID: UUID?
    @State private var presentedSaveStreakCelebration: SaveStreakCelebration?
    @State private var saveStreakCelebrationTask: Task<Void, Never>?
    @State private var sharedPlaceImportNotice: SharedPlaceImportDrainNotice?
    @State private var importAutoSaveTask: Task<Void, Never>?
    @State private var automaticImportOwnerUserID: String?
    @State private var queuedAutomaticImportBatchIDs: Set<String> = []
    @State private var completedAutomaticImportBatchIDs: Set<String> = []
    @State private var restoredPlaceSaveDraftOwnerID: String?
    @State private var pendingCommittedWalkthroughDraft: PlaceSaveDraft?
    @State private var interruptedSaveRecoveryMessage: String?
    @State private var walkthroughLaunchConfiguredUserIDs: Set<String> = []
    @State private var retiredWalkthroughUserIDs: Set<String> = []
    @State private var walkthroughFeatureFlagRefreshTask: Task<Void, Never>?
    @State private var nativeTabItemControlsFrame: CGRect?
    @State private var placeProfileFloatingActionVariant = PlaceProfileFloatingActionVariant.productionDefault
    @StateObject private var store: WanderStore
    @StateObject private var importStore: PlaceImportStore
    @StateObject private var placeSaveDraftStore: PlaceSaveDraftStore
    @StateObject private var walkthroughs: FirstVisitWalkthroughCoordinator
    @StateObject private var activityNavigation = ActivityNavigationCoordinator()
    @StateObject private var controlNavigationCenter = WanderControlNavigationCenter.shared
    private let fixtureMode: WanderFixtureMode
    private let isSessionValidated: Bool
    private let deepLinkLaunchRequest: WanderDeepLinkLaunchRequest?
    private let onDeepLinkLaunchRequestHandled: (UUID) -> Void
    private let analytics: AnalyticsClient
    private let walkthroughDebugPreferences: FirstVisitWalkthroughDebugPreferences
    private let walkthroughDebugPreferenceSnapshot: FirstVisitWalkthroughDebugPreferenceSnapshot
    private let firstVisitWalkthroughEligibilityContext: FirstVisitWalkthroughEligibilityContext
    private let onFirstVisitWalkthroughCompleted: (String) -> Void

    init(
        initialTab: WanderTab? = nil,
        initialPresentation: WanderInitialPresentation? = nil,
        initialSharedProfileRoute: SharedProfileRoute? = nil,
        initialSession: AuthSession? = nil,
        isSessionValidated: Bool = true,
        isFirstVisitWalkthroughEligible: Bool = false,
        onFirstVisitWalkthroughCompleted: @escaping (String) -> Void = { _ in },
        deepLinkLaunchRequest: WanderDeepLinkLaunchRequest? = nil,
        onDeepLinkLaunchRequestHandled: @escaping (UUID) -> Void = { _ in },
        analytics: AnalyticsClient = NoopAnalyticsClient(),
        parser: any LLMFilterParser = DeterministicFilterParser(),
        socialImportUnderstandingRepository: (any SocialImportUnderstandingRepository)? = nil
    ) {
        let fixtureMode = Self.resolvedFixtureMode()
        let launchArguments = ProcessInfo.processInfo.arguments
        self.fixtureMode = fixtureMode
        self.isSessionValidated = isSessionValidated
        self.deepLinkLaunchRequest = deepLinkLaunchRequest
        self.onDeepLinkLaunchRequestHandled = onDeepLinkLaunchRequestHandled
        self.analytics = analytics
        let walkthroughDebugPreferences = FirstVisitWalkthroughDebugPreferences()
        self.walkthroughDebugPreferences = walkthroughDebugPreferences
        self.walkthroughDebugPreferenceSnapshot = walkthroughDebugPreferences.launchSnapshot()
        let firstVisitWalkthroughEligibilityContext = FirstVisitWalkthroughEligibilityContext(
            sourceUserID: initialSession?.userID,
            isEligible: isFirstVisitWalkthroughEligible
        )
        self.firstVisitWalkthroughEligibilityContext = firstVisitWalkthroughEligibilityContext
        self.onFirstVisitWalkthroughCompleted = onFirstVisitWalkthroughCompleted
        let requestedTab = initialTab ?? Self.resolvedInitialTab()
        _selectedTab = State(initialValue: requestedTab == .add ? .map : requestedTab)
        _isPresentingAdd = State(initialValue: Self.resolvedInitialAddPresentation())
        _initialPresentation = State(initialValue: initialPresentation ?? Self.resolvedInitialPresentation())
        _sharedProfile = State(initialValue: initialSharedProfileRoute ?? Self.resolvedInitialSharedProfile())
        _placeProfileFloatingActionVariant = State(
            initialValue: PlaceProfileFloatingActionVariant.resolved(from: launchArguments)
        )
        let persistence: WanderStorePersistence? = fixtureMode == .empty ? .live : nil
        let store = Self.makeStore(
            fixtureMode: fixtureMode,
            parser: parser,
            analytics: analytics,
            persistence: persistence,
            initialSession: initialSession
        )
        if Self.resolvedInitialDarkMap(from: launchArguments) {
            store.isDarkMapEnabled = true
        }
        _store = StateObject(wrappedValue: store)
        let importStore = PlaceImportStore(
            resolver: DevicePlaceImportResolver(
                socialUnderstandingRepository: socialImportUnderstandingRepository
            )
        )
        _importStore = StateObject(wrappedValue: importStore)
        _placeSaveDraftStore = StateObject(
            wrappedValue: PlaceSaveDraftStore(
                persistence: fixtureMode == .empty ? .live : .ephemeral
            )
        )
        _walkthroughs = StateObject(
            wrappedValue: FirstVisitWalkthroughCoordinator(
                isEnabled: FirstVisitWalkthroughFeatureFlag.isEnabled(
                    isEligible: firstVisitWalkthroughEligibilityContext.applies(
                        to: initialSession?.userID
                    ),
                    isUsingLiveData: fixtureMode == .empty,
                    launchArguments: launchArguments,
                    resolvedValue: nil
                ),
                onCompleted: { completedUserID in
                    walkthroughDebugPreferences.clearReplayRequest(for: completedUserID)
                    onFirstVisitWalkthroughCompleted(completedUserID)
                }
            )
        )
        _addSheetDetent = State(
            initialValue: launchArguments.contains("-WanderOpenImportHub")
                ? .large
                : AddSheetLayout.restingDetent(
                    hasPendingImports: importStore.summary.hasPendingImports
                )
        )
    }

    var body: some View {
        stateObservedRoot
            .environment(
                \.placeProfileFloatingActionVariant,
                placeProfileFloatingActionVariant
            )
    }

    private var mapAppearanceColorScheme: ColorScheme {
        selectedTab == .map && store.isDarkMapEnabled && !isPresentingAdd
            ? .dark
            : .light
    }

    private var tabRoot: some View {
        TabView(selection: tabSelection) {
            MapScreen(
                defaultSource: store.defaultMapFilter,
                isMapTabActive: selectedTab == .map,
                isAddPresented: isPresentingAdd,
                presentationResetRequest: presentationResetRequest,
                searchLaunchRequest: mapSearchLaunchRequest,
                onSearchLaunchRequestHandled: consumeMapSearchLaunchRequest,
                onAdd: presentAddSheet
            )
                .tabItem { tabItemLabel(for: .map) }
                .tag(WanderTab.map)

            FeedScreen(onAdd: presentAddSheet)
                .tabItem { tabItemLabel(for: .discover) }
                .tag(WanderTab.discover)

            ListsScreen()
                .tabItem { tabItemLabel(for: .lists) }
                .tag(WanderTab.lists)

            ProfileScreen(
                visitInvitationInboxRequestID: $visitInvitationInboxRequestID,
                presentationResetRequest: presentationResetRequest,
                calendarLaunchRequest: profileCalendarLaunchRequest,
                onCalendarLaunchRequestHandled: consumeProfileCalendarLaunchRequest,
                onSettingsPresentation: handleDeepLinkPresentation,
                onSettingsWillDismiss: handleDeepLinkPresentationWillDismiss,
                onSettingsDidDismiss: {
                    handleDeepLinkPresentationDismissal(of: .profileSettings)
                }
            ) {
                selectedTab = .discover
            }
                .tabItem { tabItemLabel(for: .profile) }
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
        .toolbarColorScheme(mapAppearanceColorScheme, for: .tabBar)
        .background {
            if walkthroughs.currentStep?.target == .mapTabs {
                WanderNativeTabFrameReader(
                    tabs: WanderTab.primaryTabs,
                    onItemControlsFrameChange: { frame in
                        guard nativeTabItemControlsFrame != frame else { return }
                        nativeTabItemControlsFrame = frame
                    }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .environmentObject(store)
        .environmentObject(placeSaveDraftStore)
        .environmentObject(walkthroughs)
        .environmentObject(activityNavigation)
        .task(id: selectedTab) {
            // Let the native tab selection render before analytics work begins
            // on the main actor.
            await Task.yield()
            guard !Task.isCancelled else { return }
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.appSurfaceViewed,
                    properties: ["surface": selectedTab.rawValue]
                )
            )
            if selectedTab == .profile {
                analytics.track(
                    .engagement(
                        need: .status,
                        action: .ownProfileViewed,
                        surface: "profile"
                    )
                )
            }
        }
        .onChange(of: activityNavigation.commentsRoute?.id) { _, requestID in
            if requestID != nil {
                selectedTab = .discover
            }
        }
        .firstVisitWalkthroughOverlay(
            walkthroughs,
            surface: walkthroughSurface(for: selectedTab),
            externalTargetFrames: nativeTabItemControlsFrame.map { [.mapTabs: $0] } ?? [:]
        )
        .walkthroughLaunchLessonOverlay(
            walkthroughs,
            onOpenImport: presentWalkthroughImportHub
        )
        .overlay {
            GeometryReader { proxy in
                if let invitation = sharedVisitBannerInvitation {
                    SharedVisitNotificationBanner(invitation: invitation) {
                        openSharedVisitFromBanner(invitation)
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.top, proxy.safeAreaInsets.top + WanderTheme.spacing2)
                    .transition(
                        accessibilityReduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .zIndex(10)
                }
            }
        }
        .overlay {
            if let celebration = presentedSaveStreakCelebration {
                Group {
                    switch celebration.kind {
                    case .dailyTakeover:
                        SaveStreakCelebrationView(celebration: celebration) {
                            dismissSaveStreakCelebration(celebration)
                        }
                    case .sameDayConfetti:
                        SaveStreakConfettiPopView()
                    }
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
    }

    private func tabItemLabel(for tab: WanderTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }

    private var presentedRoot: some View {
        tabRoot
        .walkthroughPresenterScrim(
            isPresented: isPresentingAdd && shouldDimBehindAddWalkthrough
        )
        .sheet(isPresented: $isPresentingAdd, onDismiss: handleAddSheetDismissal) {
            WanderRootPresentationLifecycle(
                surface: .add,
                onPresent: handleDeepLinkPresentation,
                onDismiss: handleDeepLinkPresentationWillDismiss
            ) {
                AddScreen(
                    importStore: importStore,
                    placeSaveDraftStore: placeSaveDraftStore,
                    resetToken: addTabResetToken,
                    selectedDetent: $addSheetDetent,
                    launchRequest: addLaunchRequest,
                    onLaunchRequestHandled: consumeAddLaunchRequest,
                    walkthroughParkSuggestion: resolveFirstVisitParkSuggestion
                ) {
                    isPresentingAdd = false
                }
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .environmentObject(walkthroughs)
                    .interactiveDismissDisabled(
                        walkthroughs.activeSurface == .add
                            || walkthroughs.activeSurface == .saveFlow
                    )
            }
        }
        .sheet(
            item: $auth.activeGate,
            onDismiss: {
                handleDeepLinkPresentationDismissal(of: .authGate)
            }
        ) { request in
            WanderRootPresentationLifecycle(
                surface: .authGate,
                onPresent: handleDeepLinkPresentation,
                onDismiss: handleDeepLinkPresentationWillDismiss
            ) {
                AuthGateSheet(request: request)
                    .environmentObject(auth)
                    .presentationDetents([.medium])
                    .presentationBackground(WanderTheme.canvasWarm.color)
            }
        }
        .sheet(
            item: $initialPresentation,
            onDismiss: {
                handleDeepLinkPresentationDismissal(of: .initialPresentation)
            }
        ) { presentation in
            WanderRootPresentationLifecycle(
                surface: .initialPresentation,
                onPresent: handleDeepLinkPresentation,
                onDismiss: handleDeepLinkPresentationWillDismiss
            ) {
                switch presentation {
                case .settings:
                    NavigationStack {
                        SettingsScreen()
                    }
                        .environmentObject(store)
                        .environmentObject(auth)
                        .environmentObject(backend)
                        .environmentObject(pushNotifications)
                }
            }
        }
        .fullScreenCover(item: $sharedProfile) { route in
            WanderRootPresentationLifecycle(
                surface: .sharedProfile,
                onPresent: handleDeepLinkPresentation,
                onDismiss: handleDeepLinkPresentationDismissalImmediately
            ) {
                ProfileDetailView(profileID: route.profileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
        }
    }

    private var shouldDimBehindAddWalkthrough: Bool {
        walkthroughs.activeSurface == .add
            || walkthroughs.activeSurface == .saveFlow
            || walkthroughs.requestedSurface == .map
    }

    private var lifecycleRoot: some View {
        presentedRoot
        .task(id: featureFlagLoadUserID) {
            guard let userID = featureFlagLoadUserID else {
                // Foreground validation deliberately preserves the last signed-in
                // session. Keep that user's resolved flags stable while Clerk
                // revalidates so walkthrough UI cannot disappear and reappear.
                if auth.state.session == nil {
                    backend.clearFeatureFlags()
                    placeProfileFloatingActionVariant = .productionDefault
                    configureWalkthroughsForCurrentUser()
                }
                return
            }

            // A different account must fail closed while its own override loads;
            // the tagged resolution prevents the previous account from leaking.
            placeProfileFloatingActionVariant = resolvedPlaceProfileFloatingActionVariant(
                for: userID
            )
            configureWalkthroughsForCurrentUser()
            await backend.refreshFeatureFlags(for: userID)
            guard !Task.isCancelled, featureFlagLoadUserID == userID else { return }
            placeProfileFloatingActionVariant = resolvedPlaceProfileFloatingActionVariant(
                for: userID
            )
            configureWalkthroughsForCurrentUser()
        }
        .task(id: isSessionValidated) {
            guard isSessionValidated else {
                cancelSignedInMaintenance()
                return
            }
            if let userID = auth.state.session?.userID {
                importStore.bind(to: userID)
            }
            restorePlaceSaveDraftIfNeeded()
            seedSharedVisitBannerTracker()
            queueSaveStreakCelebration(store.saveStreakCelebration)
            drainSharedPlaceImports()
            importStore.resumePendingImports()
            resumeAutomaticPlaceImports()
            reconcilePlaceImports()
            publishWidgetSnapshot()
            refreshNearbyWidgetSnapshot()
            await pushNotifications.refreshAuthorizationStatus()
            guard !Task.isCancelled, isSessionValidated else { return }
            applyAuthStateIfNeeded(auth.state)
            await refreshWannaGoReminders(for: auth.state)
            guard !Task.isCancelled, isSessionValidated else { return }
            drainPendingNotificationResponses()
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didRegisterForRemoteNotifications)) { notification in
            guard isSessionValidated,
                  let deviceToken = notification.userInfo?[WanderAppDelegate.deviceTokenKey] as? Data
            else { return }
            Task {
                await pushNotifications.handleRegisteredDeviceToken(deviceToken, backend: backend, authState: auth.state)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didFailToRegisterForRemoteNotifications)) { notification in
            guard let error = notification.userInfo?[WanderAppDelegate.errorKey] as? Error else { return }
            pushNotifications.handleRegistrationFailure(error)
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveNotificationResponse)) { notification in
            #if DEBUG
            WanderDebugLog.remote.debug("root received notification response session_validated=\(isSessionValidated, privacy: .public)")
            #endif
            let fallbackUserInfo = notification.userInfo?[WanderAppDelegate.userInfoKey]
                as? [AnyHashable: Any]
            drainPendingNotificationResponses(fallbackUserInfo: fallbackUserInfo)
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveRemoteNotification)) { _ in
            guard isSessionValidated else { return }
            scheduleSignedInMaintenance(for: auth.state)
        }
    }

    private var authObservedRoot: some View {
        lifecycleRoot
        .onChange(of: pushNotifications.navigationRequest) { _, request in
            #if DEBUG
            WanderDebugLog.remote.debug("root observed notification navigation request destination=\(String(describing: request?.destination), privacy: .public) session_validated=\(isSessionValidated, privacy: .public)")
            #endif
            guard isSessionValidated, let request else { return }
            routeNotification(request)
        }
        .onChange(of: auth.state) { previousState, state in
            let nextUserID = state.session?.userID
            if previousState.session?.userID != nextUserID {
                walkthroughFeatureFlagRefreshTask?.cancel()
                walkthroughFeatureFlagRefreshTask = nil
                placeProfileFloatingActionVariant = .productionDefault
            }
            if let automaticImportOwnerUserID,
               automaticImportOwnerUserID != nextUserID {
                cancelAutomaticPlaceImports(clearVerificationQueue: true)
            }
            if let userID = state.session?.userID {
                importStore.bind(to: userID)
            }
            if !state.isSignedIn {
                cancelAutomaticPlaceImports(clearVerificationQueue: true)
                placeSaveDraftStore.clear()
                restoredPlaceSaveDraftOwnerID = nil
            }
            applyAuthStateIfNeeded(state)
            if isSessionValidated {
                configureWalkthroughsForCurrentUser()
            }
            if state.isSignedIn {
                drainSharedPlaceImports()
            }
            publishWidgetSnapshot()
            Task {
                await refreshWannaGoReminders(for: state)
            }
        }
    }

    private var storeObservedRoot: some View {
        authObservedRoot
        .onChange(of: store.wannaGoReminderItems) { _, items in
            guard isSessionValidated else { return }
            Task {
                await pushNotifications.reconcileWannaGoReminders(items)
            }
        }
        .onChange(of: store.sharedVisitInvitations) { _, invitations in
            guard isSessionValidated else { return }
            presentSharedVisitBannerIfNeeded(from: invitations)
        }
        .onChange(of: store.saveStreakCelebration) { _, celebration in
            guard isSessionValidated else { return }
            queueSaveStreakCelebration(celebration)
            if let celebration {
                pushNotifications.recordSaveCompletedAfterReminderOpen(
                    userID: store.currentUser.id,
                    status: celebration.status,
                    streakCount: celebration.streakCount,
                    savedAt: celebration.saveDate
                )
            }
            Task {
                await pushNotifications.reconcileSaveStreakReminder(
                    store.saveStreakSummary,
                    cancelledBySaveStatus: celebration?.status
                )
            }
        }
        .onChange(of: store.presentationRevision) { _, _ in
            guard isSessionValidated else { return }
            reconcilePlaceImports()
            publishWidgetSnapshot()
        }
        .onChange(of: store.currentUserCalendarHydrationRevision) { _, revision in
            handleCurrentUserCalendarHydration(revision: revision)
        }
        .onChange(of: store.isRefreshingCurrentUserCalendarData) {
            handleCalendarRefreshStateChange($0, $1)
        }
    }

    private var stateObservedRoot: some View {
        storeObservedRoot
        .onChange(of: importStore.items) { _, _ in
            guard isSessionValidated else { return }
            reconcilePlaceImports()
        }
        .onChange(of: store.isSaveFlowPresented) { _, isPresented in
            if isPresented {
                saveStreakCelebrationTask?.cancel()
            } else {
                queueSaveStreakCelebration(store.saveStreakCelebration)
            }
        }
        .onChange(of: deepLinkLaunchRequest, initial: true) { _, request in
            handleDeepLinkLaunchRequestIfReady(request)
        }
        .onChange(
            of: controlNavigationCenter.pendingRequest,
            initial: true
        ) { _, request in
            handleControlNavigationRequestIfReady(request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                placeSaveDraftStore.flush()
                walkthroughs.recordSuspension()
            }
            guard phase == .active, isSessionValidated else { return }
            switch walkthroughs.restoreJourneyIfNeeded() {
            case .resumed(let surface):
                if completeCommittedWalkthroughDraftIfNeeded() {
                    routeWalkthrough(to: walkthroughs.requestedSurface ?? .map)
                } else {
                    routeWalkthrough(to: surface)
                }
            case .expired:
                retireWalkthroughPresentationAndDraft(
                    for: store.currentUser.id,
                    forceRootCleanup: true
                )
            case .none:
                break
            }
            refreshWalkthroughFeatureFlagsAfterForeground()
            drainPendingNotificationResponses()
            drainSharedPlaceImports()
            resumeAutomaticPlaceImports()
            presentPendingImportVerificationIfPossible()
            scheduleSignedInMaintenance(for: auth.state)
            publishWidgetSnapshot()
            refreshNearbyWidgetSnapshot()
            Task {
                await refreshWannaGoReminders(for: auth.state)
            }
        }
        .modifier(
            SharedPlaceImportAlertModifier(
                notice: $sharedPlaceImportNotice,
                onReview: presentSharedPlaceImportReviewFromNotice
            )
        )
        .alert(
            "Saved to your map",
            isPresented: Binding(
                get: { interruptedSaveRecoveryMessage != nil },
                set: { if !$0 { interruptedSaveRecoveryMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                interruptedSaveRecoveryMessage = nil
                pendingCommittedWalkthroughDraft = nil
                placeSaveDraftStore.clear()
            }
        } message: {
            Text(interruptedSaveRecoveryMessage ?? "")
        }
        .onChange(of: isSessionValidated, initial: true) { _, isValidated in
            if isValidated {
                configureWalkthroughsForCurrentUser()
                drainPendingNotificationResponses()
                handleControlNavigationRequestIfReady(
                    controlNavigationCenter.pendingRequest
                )
            } else {
                cancelSignedInMaintenance()
            }
        }
        .onChange(of: firstVisitWalkthroughEligibilityContext) { _, _ in
            guard isSessionValidated else { return }
            configureWalkthroughsForCurrentUser()
        }
        .onChange(of: walkthroughs.isPresentingDeviceFeaturesLesson) { _, isPresented in
            if !isPresented, !walkthroughs.hasActivePrimaryJourney {
                walkthroughs.activate(walkthroughSurface(for: selectedTab))
            }
        }
        .onChange(of: walkthroughs.requestedSurface) { _, surface in
            guard let surface else { return }
            routeWalkthrough(to: surface)
        }
        .onDisappear(perform: handleRootDisappear)
    }

    private var tabSelection: Binding<WanderTab> {
        Binding {
            selectedTab
        } set: { newTab in
            if newTab == .add {
                presentAddSheet()
            } else {
                walkthroughs.perform(.mapTabs)
                // Preserve the system Liquid Glass bar while committing the
                // destination content without its long selection transition.
                withTransaction(Transaction(animation: nil)) {
                    selectedTab = newTab
                }
                presentLaunchLessonIfAppropriate()
                walkthroughs.activate(walkthroughSurface(for: newTab))
            }
        }
    }

    private func presentAddSheet() {
        if walkthroughs.currentStep?.target == .mapAddAgain {
            walkthroughs.perform(.mapAddAgain)
        } else {
            walkthroughs.perform(.mapAdd)
        }
        walkthroughs.transition(to: .add)
        placeSaveDraftStore.clear()
        store.saveFlowDidPresent(.addSheet)
        addTabResetToken = UUID()
        addLaunchRequest = nil
        addSheetDetent = addSheetRestingDetent
        isPresentingAdd = true
        analytics.track(
            AnalyticsEvent(
                name: WanderAnalyticsEvents.appSurfaceViewed,
                properties: ["surface": "add"]
            )
        )
    }

    @MainActor
    private func resolveFirstVisitParkSuggestion() async -> PlaceCandidate? {
        // Demo fixtures have no trustworthy device location. Return the
        // deterministic fallback immediately instead of waiting on a simulator
        // that may be authorized but have no live location fix.
        guard fixtureMode == .empty else {
            return FirstVisitParkSuggestionPolicy.hotchkissPark
        }

        let context = try? await CoreFirstVisitParkLocationContextProvider()
            .alreadyAuthorizedLocationContext()
        guard let context,
              FirstVisitParkSuggestionPolicy.shouldRequestNearbySuggestion(
                  postalCode: context.postalCode
              )
        else {
            return FirstVisitParkSuggestionPolicy.hotchkissPark
        }

        do {
            return try await MapKitPlaceResolver().suggestion(near: context)
        } catch {
            guard !Task.isCancelled else { return nil }
            return FirstVisitParkSuggestionPolicy.hotchkissPark
        }
    }

    private func restorePlaceSaveDraftIfNeeded() {
        let ownerUserID = store.currentUser.id
        guard restoredPlaceSaveDraftOwnerID != ownerUserID else { return }
        restoredPlaceSaveDraftOwnerID = ownerUserID

        guard case .restored(let draft) = placeSaveDraftStore.restore(
            ownerUserID: ownerUserID
        ) else { return }

        let checkpoint = FirstVisitWalkthroughStore().checkpoint(for: ownerUserID)
        if PlaceSaveDraftWalkthroughRecoveryPolicy.shouldDiscard(
            draft,
            lastWalkthroughActivityAt: checkpoint?.updatedAt,
            now: .now,
            resumeWindow: FirstVisitWalkthroughStore.resumeWindow
        ) {
            placeSaveDraftStore.clear()
            return
        }

        let currentSave = MapPlaceSaveContext.currentUserSave(
            matching: draft.candidate,
            in: store.currentUserVisiblePlaces
        )
        let latestVisit = currentSave.flatMap {
            store.visits(for: $0.userPlace.id).first
        }
        let evidence = currentSave.map {
            PlaceSaveDraftCommitEvidence(
                userPlaceLocalID: $0.userPlace.localID,
                userPlaceUpdatedAt: $0.userPlace.localUpdatedAt,
                status: $0.userPlace.status,
                latestVisitLocalID: latestVisit?.localID,
                latestVisitCreatedAt: latestVisit?.createdAt
            )
        }

        switch PlaceSaveDraftRecoveryPolicy.outcome(for: draft, evidence: evidence) {
        case .committed:
            pendingCommittedWalkthroughDraft = draft
            if completeCommittedWalkthroughDraftIfNeeded() {
                routeWalkthrough(to: walkthroughs.requestedSurface ?? .map)
            } else {
                interruptedSaveRecoveryMessage = draft.form.selectedStatus == .been
                    ? "Your check-in finished while rec.me was in the background."
                    : "This place was added to Wanna while rec.me was in the background."
            }
        case .retry:
            placeSaveDraftStore.prepareRetry(
                message: "Save was interrupted before rec.me could confirm it. Review your details and try again."
            )
            presentRestoredAddSheet()
        case .editing:
            presentRestoredAddSheet()
        }
    }

    @discardableResult
    private func retireWalkthroughPresentationAndDraft(
        for ownerUserID: String,
        forceRootCleanup: Bool
    ) -> Bool {
        let persistedDraft: PlaceSaveDraft?
        if let draft = placeSaveDraftStore.draft, draft.ownerUserID == ownerUserID {
            persistedDraft = draft
        } else if case .restored(let draft) = placeSaveDraftStore.restore(
            ownerUserID: ownerUserID
        ) {
            persistedDraft = draft
        } else {
            persistedDraft = nil
        }

        let didDiscardWalkthroughDraft = persistedDraft?.walkthroughContentVersion != nil
        if didDiscardWalkthroughDraft {
            placeSaveDraftStore.clear()
            restoredPlaceSaveDraftOwnerID = ownerUserID
        }

        guard forceRootCleanup || didDiscardWalkthroughDraft else { return false }
        pendingCommittedWalkthroughDraft = nil
        interruptedSaveRecoveryMessage = nil
        presentationResetRequest = WanderPresentationResetRequest()
        resetRootPresentationsForDeepLink()
        selectedTab = .map
        return true
    }

    @discardableResult
    private func completeCommittedWalkthroughDraftIfNeeded() -> Bool {
        guard let draft = pendingCommittedWalkthroughDraft,
              draft.ownerUserID == store.currentUser.id,
              walkthroughs.activeSurface == .saveFlow,
              walkthroughs.currentStep?.target == .saveSubmit,
              let currentSave = MapPlaceSaveContext.currentUserSave(
                  matching: draft.candidate,
                  in: store.currentUserVisiblePlaces
              )
        else { return false }

        let form = draft.form
        let snapshot = FirstVisitTutorialMemorySnapshot(
            candidate: draft.candidate,
            status: form.selectedStatus,
            date: form.selectedStatus == .been
                ? form.visitedAt
                : (form.plannedDate ?? draft.updatedAt),
            ratingScore: form.selectedStatus == .been ? form.selectedRatingScore : nil,
            note: form.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "A peaceful neighborhood park with room to slow down and breathe."
                : form.note,
            tag: form.unifiedTags.sorted().first ?? "good walk"
        )
        walkthroughs.recordTutorialCandidate(draft.candidate)
        walkthroughs.recordTutorialSelectedStatus(form.selectedStatus)
        walkthroughs.recordTutorialMemorySnapshot(snapshot)
        walkthroughs.recordTutorialSave(userPlaceID: currentSave.userPlace.id)
        walkthroughs.perform(.saveSubmit)
        // The next NUX checkpoint is now durable. Only now is it safe to drop
        // the committed form that bridges a process kill during submission.
        placeSaveDraftStore.clear()
        pendingCommittedWalkthroughDraft = nil
        interruptedSaveRecoveryMessage = nil
        return true
    }

    private func presentRestoredAddSheet() {
        store.saveFlowDidPresent(.addSheet)
        addLaunchRequest = nil
        addSheetDetent = .large
        isPresentingAdd = true
    }

    private var addSheetRestingDetent: PresentationDetent {
        AddSheetLayout.restingDetent(
            hasPendingImports: importStore.summary.hasPendingImports
        )
    }

    private func consumeAddLaunchRequest(_ id: UUID) {
        guard addLaunchRequest?.id == id else { return }
        addLaunchRequest = nil
    }

    private func consumeMapSearchLaunchRequest(_ id: UUID) {
        guard mapSearchLaunchRequest?.id == id else { return }
        mapSearchLaunchRequest = nil
    }

    private func consumeProfileCalendarLaunchRequest(_ id: UUID) {
        guard profileCalendarLaunchRequest?.id == id else { return }
        profileCalendarLaunchRequest = nil
    }

    private func reconcilePlaceImports() {
        importStore.reconcileDuplicates(
            with: store.currentUserVisiblePlaces.map { visiblePlace in
                PlaceImportExistingPlace(
                    userPlaceID: visiblePlace.userPlace.id,
                    name: visiblePlace.place.canonicalName,
                    latitude: visiblePlace.place.latitude,
                    longitude: visiblePlace.place.longitude,
                    sourceProvider: visiblePlace.place.sourceProvider,
                    sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID
                )
            }
        )
    }

    private func drainSharedPlaceImports() {
        guard SharedPlaceImportDrainPolicy.canDrain(
            isSessionValidated: isSessionValidated,
            isSignedIn: auth.isSignedIn
        ) else { return }
        guard let inbox = try? SharedPlaceImportInbox.live() else { return }
        let report = SharedPlaceImportInboxDrainer.drain(
            inbox: inbox,
            into: importStore
        )
        guard report.hasUserVisibleResult else { return }
        reconcilePlaceImports()
        if !report.batchIDs.isEmpty {
            let automaticIDs = report.batchIDs.filter { batchID in
                importStore.batches.first(where: { $0.id == batchID })?.shouldSaveAutomatically == true
            }
            let reviewBeforeSaveIDs = report.batchIDs.filter { !automaticIDs.contains($0) }
            enqueueAutomaticPlaceImports(batchIDs: automaticIDs)
            if !reviewBeforeSaveIDs.isEmpty {
                presentSharedPlaceImportReview(batchIDs: reviewBeforeSaveIDs)
            }
        } else {
            sharedPlaceImportNotice = SharedPlaceImportDrainNotice(report: report)
        }
    }

    private func presentSharedPlaceImportReviewFromNotice() {
        guard let notice = sharedPlaceImportNotice else { return }
        presentSharedPlaceImportReview(batchIDs: notice.report.batchIDs)
    }

    private func presentSharedPlaceImportReview(batchIDs: [String]) {
        guard !batchIDs.isEmpty else { return }
        completedAutomaticImportBatchIDs.subtract(batchIDs)
        addTabResetToken = UUID()
        addSheetDetent = .large
        addLaunchRequest = WanderAddLaunchRequest(destination: .importReview(batchIDs: batchIDs))
        isPresentingAdd = true
    }

    private func resumeAutomaticPlaceImports() {
        importStore.resumePendingImports()
        completedAutomaticImportBatchIDs.formUnion(
            PlaceImportAutoSavePolicy.pendingVerificationBatchIDs(
                in: importStore.batches
            )
        )
        enqueueAutomaticPlaceImports(
            batchIDs: importStore.batches
                .filter(\.shouldSaveAutomatically)
                .map(\.id)
        )
        presentPendingImportVerificationIfPossible()
    }

    private func enqueueAutomaticPlaceImports(batchIDs: [String]) {
        guard !batchIDs.isEmpty,
              let expectedUserID = auth.state.session?.userID,
              store.currentUser.id == expectedUserID
        else { return }
        queuedAutomaticImportBatchIDs.formUnion(batchIDs)
        guard importAutoSaveTask == nil else { return }
        automaticImportOwnerUserID = expectedUserID
        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "rec.me place import",
            expirationHandler: {
                Task { @MainActor in
                    guard automaticImportOwnerUserID == expectedUserID else { return }
                    importStore.pauseProcessing(
                        batchIDs: importStore.batches
                            .filter(\.shouldSaveAutomatically)
                            .map(\.id)
                    )
                    importAutoSaveTask?.cancel()
                }
            }
        )

        importAutoSaveTask = Task { @MainActor in
            defer {
                if backgroundTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTaskID)
                }
                if automaticImportOwnerUserID == expectedUserID {
                    importAutoSaveTask = nil
                    automaticImportOwnerUserID = nil
                }
            }
            while !Task.isCancelled, !queuedAutomaticImportBatchIDs.isEmpty {
                guard auth.state.session?.userID == expectedUserID,
                      store.currentUser.id == expectedUserID
                else { return }
                let nextBatchIDs = queuedAutomaticImportBatchIDs.sorted()
                queuedAutomaticImportBatchIDs.subtract(nextBatchIDs)
                let result = await PlaceImportAutoSaveCoordinator.process(
                    batchIDs: nextBatchIDs,
                    importStore: importStore,
                    store: store,
                    expectedUserID: expectedUserID,
                    isAuthorized: {
                        auth.state.session?.userID == expectedUserID
                    }
                )
                guard !Task.isCancelled,
                      auth.state.session?.userID == expectedUserID,
                      store.currentUser.id == expectedUserID
                else { return }
                if result.hasResult {
                    completedAutomaticImportBatchIDs.formUnion(result.batchIDs)
                    if scenePhase == .active {
                        presentPendingImportVerificationIfPossible()
                    } else {
                        await pushNotifications.notifyImportFinished(
                            batchIDs: result.batchIDs,
                            savedCount: result.savedCount,
                            needsReviewCount: result.needsReviewCount,
                            sourceRetryCount: result.sourceRetryCount
                        )
                    }
                }
            }
        }
    }

    private func cancelAutomaticPlaceImports(clearVerificationQueue: Bool) {
        importAutoSaveTask?.cancel()
        importAutoSaveTask = nil
        automaticImportOwnerUserID = nil
        queuedAutomaticImportBatchIDs.removeAll()
        if clearVerificationQueue {
            completedAutomaticImportBatchIDs.removeAll()
        }
    }

    private func presentPendingImportVerificationIfPossible() {
        guard scenePhase == .active,
              !isPresentingAdd,
              !store.isSaveFlowPresented,
              !completedAutomaticImportBatchIDs.isEmpty
        else { return }
        presentSharedPlaceImportReview(
            batchIDs: completedAutomaticImportBatchIDs.sorted()
        )
    }

    private func publishWidgetSnapshot(allowFreshnessAdvance: Bool = false) {
        guard isSessionValidated || fixtureMode != .empty else { return }
        guard !store.isRefreshingCurrentUserCalendarData else { return }

        if fixtureMode == .empty, auth.isSignedIn {
            let hasLocalCalendarData = store.userPlaces.contains {
                $0.userID == store.currentUser.id && $0.deletedAt == nil
            }
            guard widgetCalendarHydratedUserID == store.currentUser.id
                    || hasLocalCalendarData
            else {
                return
            }
        }
        WanderWidgetSnapshotPublisher.publish(
            store: store,
            isAvailable: auth.isSignedIn || fixtureMode != .empty,
            allowFreshnessAdvance: allowFreshnessAdvance || fixtureMode != .empty
        )
    }

    private func refreshNearbyWidgetSnapshot() {
        nearbyWidgetRefreshTask?.cancel()
        nearbyWidgetRefreshTask = Task { @MainActor in
            await WanderNearbyWidgetSnapshotPublisher.refreshIfConfigured()
        }
    }

    private func handleCurrentUserCalendarHydration(revision: UInt64) {
        guard revision > 0,
              case .signedIn(let session) = auth.state,
              session.userID == store.currentUser.id,
              store.currentUserCalendarProjection.isAuthoritative
        else { return }

        widgetCalendarHydratedUserID = session.userID
        widgetCalendarLastHydratedAt = .now
        publishWidgetSnapshot(allowFreshnessAdvance: true)
        Task {
            await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary)
        }
    }

    static func calendarRefreshDidFinish(
        wasRefreshing: Bool,
        isRefreshing: Bool
    ) -> Bool {
        wasRefreshing && !isRefreshing
    }

    private func handleCalendarRefreshStateChange(
        _ wasRefreshing: Bool,
        _ isRefreshing: Bool
    ) {
        guard Self.calendarRefreshDidFinish(
            wasRefreshing: wasRefreshing,
            isRefreshing: isRefreshing
        ) else {
            return
        }
        publishWidgetSnapshot()
    }

    private func handleRootDisappear() {
        cancelSignedInMaintenance()
        walkthroughFeatureFlagRefreshTask?.cancel()
        walkthroughFeatureFlagRefreshTask = nil
        nearbyWidgetRefreshTask?.cancel()
        nearbyWidgetRefreshTask = nil
        deepLinkHandoffTask?.cancel()
        deepLinkHandoff.cancel()
        deepLinkPresentations.removeAll()
        sharedVisitBannerTask?.cancel()
        saveStreakCelebrationTask?.cancel()

        guard !auth.state.isSignedIn, fixtureMode == .empty else { return }
        placeSaveDraftStore.clear()
        WanderWidgetSnapshotPublisher.clear()
        store.apply(authState: auth.state)
        Task {
            await refreshWannaGoReminders(for: auth.state)
        }
    }

    private func routeNotification(_ request: NotificationNavigationRequest) {
        if case .importReview(let batchIDs) = request.destination {
            pushNotifications.consumeNavigationRequest(id: request.id)
            presentSharedPlaceImportReview(batchIDs: batchIDs)
            return
        }
        if request.destination == .quickCapture {
            pushNotifications.consumeNavigationRequest(id: request.id)
            beginDeepLinkHandoff(to: .quickCapture)
            return
        }
        if case .profile(let profileID) = request.destination {
            pushNotifications.consumeNavigationRequest(id: request.id)
            beginDeepLinkHandoff(to: .sharedProfile(profileID: profileID))
            return
        }
        if case .activityComments(let activityID) = request.destination {
            isPresentingAdd = false
            initialPresentation = nil
            selectedTab = .discover
            activityNavigation.openComments(activityID: activityID)
            pushNotifications.consumeNavigationRequest(id: request.id)
            return
        }

        isPresentingAdd = false
        initialPresentation = nil

        selectedTab = Self.notificationTab(for: request.destination)
        if request.destination == .discover {
            pushNotifications.consumeNavigationRequest(id: request.id)
        }
    }

    private func drainPendingNotificationResponses(
        fallbackUserInfo: [AnyHashable: Any]? = nil
    ) {
        guard isSessionValidated else { return }

        var handledResponse = false
        while let pendingUserInfo = WanderAppDelegate.takePendingNotificationUserInfo(
            for: store.currentUser.id
        ) {
            handledResponse = pushNotifications.handleNotificationResponse(
                userInfo: pendingUserInfo,
                userID: store.currentUser.id
            ) || handledResponse
        }

        if !handledResponse, let fallbackUserInfo {
            handledResponse = pushNotifications.handleNotificationResponse(
                userInfo: fallbackUserInfo,
                userID: store.currentUser.id
            )
        }

        if handledResponse {
            scheduleSignedInMaintenance(for: auth.state)
        }
    }

    static func notificationTab(for destination: NotificationDestination) -> WanderTab {
        switch destination {
        case .quickCapture: .map
        case .profile: .profile
        case .people, .drafts: .profile
        case .importReview: .map
        case .list, .listInvite: .lists
        case .place, .sharedVisit: .map
        case .activityComments: .discover
        case .discover: .discover
        }
    }

    static let sharedVisitBannerDestinationTab: WanderTab = .profile

    static func sharedProfileRoute(for url: URL) -> SharedProfileRoute? {
        guard case .sharedProfile(let profileID) = WanderDeepLinkRoute.parse(url) else { return nil }
        return SharedProfileRoute(profileID: profileID)
    }

    private func handleDeepLinkLaunchRequestIfReady(
        _ request: WanderDeepLinkLaunchRequest?
    ) {
        guard isSessionValidated,
              let request,
              handledDeepLinkLaunchRequestID != request.id
        else {
            return
        }

        handledDeepLinkLaunchRequestID = request.id
        beginDeepLinkHandoff(to: request.route)
        onDeepLinkLaunchRequestHandled(request.id)
    }

    private func handleControlNavigationRequestIfReady(
        _ request: WanderControlNavigationRequest?
    ) {
        guard isSessionValidated, let request else { return }

        beginDeepLinkHandoff(to: request.route)
        controlNavigationCenter.consume(request.id)
    }

    private func beginDeepLinkHandoff(to route: WanderDeepLinkRoute) {
        deepLinkHandoffTask?.cancel()

        let resetRequest = WanderPresentationResetRequest()
        deepLinkHandoff.begin(
            requestID: resetRequest.id,
            route: route,
            awaitingDismissals: deepLinkPresentationTokensAwaitingDismissal()
        )
        #if DEBUG
        WanderDebugLog.remote.debug("deep link handoff began route=\(String(describing: route), privacy: .public) awaiting=\(deepLinkHandoff.awaitingDismissals.count, privacy: .public)")
        #endif
        presentationResetRequest = resetRequest
        resetRootPresentationsForDeepLink()

        guard deepLinkHandoff.awaitingDismissals.isEmpty else {
            deepLinkHandoffTask = nil
            return
        }

        deepLinkHandoffTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled,
                  presentationResetRequest?.id == resetRequest.id
            else { return }

            activateReadyDeepLink(requestID: resetRequest.id)
        }
    }

    private func handleDeepLinkPresentation(
        _ token: WanderDeepLinkPresentationToken
    ) {
        guard deepLinkPresentations.presentationDidAppear(token) else {
            return
        }

        // A presentation can finish appearing after a handoff has started.
        // Its physical generation must still block that pending route.
        deepLinkHandoff.addDismissalBlocker(token)
    }

    private func handleDeepLinkPresentationWillDismiss(
        _ token: WanderDeepLinkPresentationToken
    ) {
        _ = deepLinkPresentations.presentationWillDisappear(token)
    }

    private func handleAddSheetDismissal() {
        placeSaveDraftStore.clear()
        handleDeepLinkPresentationDismissal(of: .add)
        Task { @MainActor in
            await Task.yield()
            presentPendingImportVerificationIfPossible()
        }
        if walkthroughs.requestedSurface == .map {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(260))
                walkthroughs.consumeRequestedSurface(.map)
                walkthroughs.activate(.map)
                presentLaunchLessonIfAppropriate()
            }
        } else {
            walkthroughs.activate(walkthroughSurface(for: selectedTab))
            presentLaunchLessonIfAppropriate()
        }
    }

    private func configureWalkthroughsForCurrentUser() {
        let launchArguments = ProcessInfo.processInfo.arguments
        let userID = auth.state.session?.userID ?? store.currentUser.id
        // Bind persisted progress to the authenticated account before reading,
        // retiring, or restoring any journey state. Disabled/established users
        // still need their own stale checkpoints cleared, never the previous
        // account's or the coordinator's placeholder account.
        walkthroughs.setUserID(userID)
        let hasLocalReplayRequest = walkthroughDebugPreferenceSnapshot.isReplayRequested(
            for: userID
        )
        let hasLaunchDeviceNUXOverride = backend.deviceFeatureFlagOverride(
            .firstVisitNUX,
            for: userID
        ) != nil
        let isDebugSettingsEntitled = DebugSettingsAccessPolicy.isEntitled(
            serverFlag: backend.remoteFeatureFlag(.debugSettings, for: userID)?.isEnabled
        ) || hasLocalReplayRequest || hasLaunchDeviceNUXOverride
        let isFeatureFlagResolutionPending = backend.featureFlagResolution
            .isPending(for: userID)
        let debugNUXOverride = isDebugSettingsEntitled
            ? backend.deviceFeatureFlagOverride(.firstVisitNUX, for: userID)?.booleanValue
            : nil
        let debugReplay = FirstVisitWalkthroughDebugReplayPolicy.resolve(
            hasLocalReplayRequest: hasLocalReplayRequest,
            isDebugSettingsEntitled: isDebugSettingsEntitled,
            isFeatureFlagResolutionPending: isFeatureFlagResolutionPending
        )
        let resolvedFlag = backend.resolvedFeatureFlag(.firstVisitNUX, for: userID)
        let shouldRetireEligibility =
            FirstVisitWalkthroughEligibilityPolicy.shouldRequestPersistedEligibilityRetirement(
                isUsingLiveData: fixtureMode == .empty,
                resolvedAccountOverride: resolvedFlag?.explicitAccountOverride
            )
        let enrollmentBelongsToCurrentUser =
            firstVisitWalkthroughEligibilityContext.applies(to: userID)
        if firstVisitWalkthroughEligibilityContext.shouldRetire(
            for: userID,
            whenRetirementIsRequested: shouldRetireEligibility
        ),
           retiredWalkthroughUserIDs.insert(userID).inserted {
            onFirstVisitWalkthroughCompleted(userID)
        }
        let effectiveEligibility = enrollmentBelongsToCurrentUser
            && !retiredWalkthroughUserIDs.contains(userID)
        walkthroughs.setEligibilityResolutionPending(
            FirstVisitWalkthroughEligibilityPolicy.isAwaitingFeatureFlagResolution(
                isEnrolled: effectiveEligibility,
                isUsingLiveData: fixtureMode == .empty,
                resolutionIsPending: isFeatureFlagResolutionPending
            )
            || debugReplay.isAwaitingEntitlementResolution
        )
        let isEnabled = FirstVisitWalkthroughFeatureFlag.isEnabled(
            isEligible: effectiveEligibility,
            isUsingLiveData: fixtureMode == .empty,
            launchArguments: launchArguments,
            resolvedValue: resolvedFlag?.isEnabled,
            entitledDebugOverride: debugNUXOverride,
            isEntitledDebugReplayRequested: debugReplay.isEntitledReplayRequested,
            isExplicitlyDisabledForAccount: resolvedFlag?.explicitAccountOverride == false
        )
        let hadActiveWalkthroughPresentation = walkthroughs.hasActivePresentation
        walkthroughs.setEnabled(isEnabled)

        guard isEnabled else {
            let hasDebugLaunchDisable = FirstVisitWalkthroughFeatureFlag
                .allowsLaunchArgumentOverride
                && launchArguments.contains("-WanderDisableWalkthroughs")
            let hasDebugLaunchEnable = FirstVisitWalkthroughFeatureFlag
                .allowsLaunchArgumentOverride
                && launchArguments.contains("-WanderEnableWalkthroughs")
            let isExplicitlyDisabled = hasDebugLaunchDisable
                || (isDebugSettingsEntitled && debugNUXOverride == false)
                || resolvedFlag?.explicitAccountOverride == false
            if FirstVisitWalkthroughEligibilityPolicy.shouldRetireLocalJourney(
                isEnrolled: effectiveEligibility,
                isExplicitReplayEnabled: hasDebugLaunchEnable
                    || debugReplay.shouldPreserveLocalJourney,
                isExplicitlyDisabled: isExplicitlyDisabled
            ) {
                walkthroughs.retireJourneyForDisabledExperience()
                retireWalkthroughPresentationAndDraft(
                    for: userID,
                    forceRootCleanup: hadActiveWalkthroughPresentation
                )
            }
            return
        }

        let forcedWalkthroughTarget: WalkthroughTargetID? = {
            guard let flagIndex = launchArguments.firstIndex(of: "-WanderWalkthroughTarget") else {
                return nil
            }
            let valueIndex = launchArguments.index(after: flagIndex)
            guard launchArguments.indices.contains(valueIndex) else { return nil }
            return WalkthroughTargetID(rawValue: launchArguments[valueIndex])
        }()
        let shouldApplyLaunchConfiguration = !walkthroughLaunchConfiguredUserIDs.contains(userID)
        if shouldApplyLaunchConfiguration {
            walkthroughLaunchConfiguredUserIDs.insert(userID)
            if walkthroughDebugPreferenceSnapshot.shouldStartReplay(for: userID) {
                walkthroughs.resetCurrentUser()
                walkthroughDebugPreferences.markReplayStarted(for: userID)
            } else if let forcedWalkthroughTarget {
                walkthroughs.prepareDebugReplay(at: forcedWalkthroughTarget)
            } else if launchArguments.contains("-WanderResetWalkthroughs") {
                walkthroughs.resetCurrentUser()
            }
        }
        walkthroughs.registerLaunch(
            forceImportLesson: launchArguments.contains("-WanderShowImportWalkthrough"),
            forceDeviceFeaturesLesson: launchArguments.contains(
                "-WanderShowDeviceFeaturesWalkthrough"
            )
        )
        if let forcedWalkthroughTarget {
            // A forced replay can be configured before a sheet's target anchors
            // exist. The authenticated-account refresh arrives once that sheet
            // is mounted; re-publish the same step without resetting any of the
            // clean replay state. Once the tester advances, the target no
            // longer matches and later refreshes cannot rewind the journey.
            if !shouldApplyLaunchConfiguration,
               walkthroughs.currentStep?.target == forcedWalkthroughTarget {
                walkthroughs.forceActivate(forcedWalkthroughTarget)
            }
            if shouldApplyLaunchConfiguration,
               let forcedSurface = walkthroughs.activeSurface {
                routeWalkthrough(to: forcedSurface)
            }
            return
        }

        switch walkthroughs.restoreJourneyIfNeeded() {
        case .resumed(let surface):
            if completeCommittedWalkthroughDraftIfNeeded() {
                routeWalkthrough(to: walkthroughs.requestedSurface ?? .map)
            } else {
                routeWalkthrough(to: surface)
            }
            return
        case .expired:
            retireWalkthroughPresentationAndDraft(
                for: userID,
                forceRootCleanup: true
            )
            return
        case .none:
            break
        }

        if !walkthroughs.hasCompletedPrimaryJourney {
            selectedTab = .map
            isPresentingAdd = false
            walkthroughs.activate(.map)
            return
        }

        presentLaunchLessonIfAppropriate()
        if !walkthroughs.isPresentingLaunchLesson {
            walkthroughs.activate(walkthroughSurface(for: selectedTab))
        }
    }

    private func refreshWalkthroughFeatureFlagsAfterForeground() {
        walkthroughFeatureFlagRefreshTask?.cancel()
        guard let userID = featureFlagLoadUserID else { return }

        walkthroughFeatureFlagRefreshTask = Task { @MainActor in
            await backend.refreshFeatureFlags(for: userID)
            guard !Task.isCancelled, featureFlagLoadUserID == userID else { return }
            placeProfileFloatingActionVariant = resolvedPlaceProfileFloatingActionVariant(
                for: userID
            )
            configureWalkthroughsForCurrentUser()
            walkthroughFeatureFlagRefreshTask = nil
        }
    }

    private func presentLaunchLessonIfAppropriate() {
        guard !isPresentingAdd, initialPresentation == nil, sharedProfile == nil else { return }
        walkthroughs.presentLaunchLessonIfEligible()
    }

    private func presentWalkthroughImportHub() {
        store.saveFlowDidPresent(.addSheet)
        addTabResetToken = UUID()
        addLaunchRequest = WanderAddLaunchRequest(destination: .importHub)
        addSheetDetent = addSheetRestingDetent
        isPresentingAdd = true
    }

    private func routeWalkthrough(to surface: WalkthroughSurface) {
        if surface == .add,
           placeSaveDraftStore.draft?.walkthroughContentVersion != nil {
            // A process can be killed after the NUX form is durable but before
            // its Add -> Save checkpoint update. Prefer the recoverable form
            // over the older Add checkpoint and reopen the exact save sheet.
            walkthroughs.transition(to: .saveFlow)
            routeWalkthrough(to: .saveFlow)
            return
        }

        let waitsForAddDismissal = isPresentingAdd && surface == .map
        switch surface {
        case .map, .sendoff:
            selectedTab = .map
            if !waitsForAddDismissal {
                isPresentingAdd = false
            }
        case .feed:
            selectedTab = .discover
            isPresentingAdd = false
        case .lists:
            selectedTab = .lists
            isPresentingAdd = false
        case .profile:
            selectedTab = .profile
            isPresentingAdd = false
        case .placeDetail:
            selectedTab = .map
            isPresentingAdd = false
        case .add:
            selectedTab = .map
            addSheetDetent = addSheetRestingDetent
            if !isPresentingAdd {
                store.saveFlowDidPresent(.addSheet)
                addTabResetToken = UUID()
                addLaunchRequest = nil
                isPresentingAdd = true
            }
        case .saveFlow:
            selectedTab = .map
            if !isPresentingAdd {
                store.saveFlowDidPresent(.addSheet)
                addTabResetToken = UUID()
                addLaunchRequest = nil
                addSheetDetent = .large
                isPresentingAdd = true
            }
        case .feedSearch:
            selectedTab = .discover
            isPresentingAdd = false
        case .listDetail, .listEditor:
            break
        }

        guard !waitsForAddDismissal else { return }

        Task { @MainActor in
            if isPresentingAdd {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .milliseconds(220))
            }
            walkthroughs.consumeRequestedSurface(surface)
            walkthroughs.activate(surface)
        }
    }

    private func walkthroughSurface(for tab: WanderTab) -> WalkthroughSurface {
        switch tab {
        case .map, .add:
            if walkthroughs.activeSurface == .sendoff
                || walkthroughs.requestedSurface == .sendoff {
                .sendoff
            } else {
                .map
            }
        case .discover:
            .feed
        case .lists:
            .lists
        case .profile:
            .profile
        }
    }

    private var featureFlagLoadUserID: String? {
        guard isSessionValidated,
              fixtureMode == .empty,
              !(FirstVisitWalkthroughFeatureFlag.allowsLaunchArgumentOverride
                && ProcessInfo.processInfo.arguments.contains("-WanderEnableWalkthroughs"))
        else { return nil }
        return auth.state.session?.userID
    }

    private func resolvedPlaceProfileFloatingActionVariant(
        for userID: String
    ) -> PlaceProfileFloatingActionVariant {
        #if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains(PlaceProfileFloatingActionVariant.selectionLaunchArgument) {
            return PlaceProfileFloatingActionVariant.resolved(from: launchArguments)
        }
        #endif

        let value = backend.integerFeatureFlag(.placeProfileActionVariant, for: userID)
            ?? PlaceProfileFloatingActionVariant.productionDefault.rawValue
        return PlaceProfileFloatingActionVariant(rawValue: value) ?? .productionDefault
    }

    private func handleDeepLinkPresentationDismissal(
        of surface: WanderDeepLinkPresentationSurface
    ) {
        guard let token = deepLinkPresentations.sheetDidDismiss(
            surface: surface
        ) else { return }
        completeDeepLinkPresentationDismissal(token)
    }

    private func handleDeepLinkPresentationDismissalImmediately(
        _ token: WanderDeepLinkPresentationToken
    ) {
        guard deepLinkPresentations.presentationDidDismissImmediately(token) else {
            return
        }

        completeDeepLinkPresentationDismissal(token)
    }

    private func completeDeepLinkPresentationDismissal(
        _ token: WanderDeepLinkPresentationToken
    ) {
        if Self.shouldResetAddFlowAfterDismissal(
            token,
            remainingPresentedTokens: deepLinkPresentationTokensAwaitingDismissal(),
            isPresentingAdd: isPresentingAdd
        ) {
            store.saveFlowDidDismiss(.addSheet)
            addTabResetToken = UUID()
            addLaunchRequest = nil
            addSheetDetent = addSheetRestingDetent
        }

        guard let route = deepLinkHandoff.acknowledgeDismissal(token) else {
            return
        }

        deepLinkHandoffTask?.cancel()
        deepLinkHandoffTask = nil
        activateDeepLink(route)
    }

    private func deepLinkPresentationTokensAwaitingDismissal()
        -> Set<WanderDeepLinkPresentationToken>
    {
        deepLinkPresentations.tokensAwaitingDismissal
    }

    static func shouldResetAddFlowAfterDismissal(
        _ token: WanderDeepLinkPresentationToken,
        remainingPresentedTokens: Set<WanderDeepLinkPresentationToken>,
        isPresentingAdd: Bool
    ) -> Bool {
        token.surface == .add
            && !isPresentingAdd
            && !remainingPresentedTokens.contains(where: { $0.surface == .add })
    }

    private func activateReadyDeepLink(requestID: UUID) {
        guard presentationResetRequest?.id == requestID,
              let route = deepLinkHandoff.takeReadyRoute(requestID: requestID)
        else {
            return
        }

        deepLinkHandoffTask = nil
        activateDeepLink(route)
    }

    private func resetRootPresentationsForDeepLink() {
        addLaunchRequest = nil
        mapSearchLaunchRequest = nil
        profileCalendarLaunchRequest = nil
        visitInvitationInboxRequestID = nil
        addTabResetToken = UUID()
        addSheetDetent = addSheetRestingDetent
        isPresentingAdd = false
        initialPresentation = nil
        sharedProfile = nil
        auth.activeGate = nil
        auth.isPresentingNativeAuth = false
    }

    private func activateDeepLink(_ route: WanderDeepLinkRoute) {
        switch route {
        case .quickCapture:
            selectedTab = .map
            store.saveFlowDidPresent(.addSheet)
            addTabResetToken = UUID()
            addLaunchRequest = WanderAddLaunchRequest(destination: .hereNow)
            addSheetDetent = .large
            isPresentingAdd = true
        case .addSearch(let query):
            selectedTab = .map
            store.saveFlowDidPresent(.addSheet)
            addTabResetToken = UUID()
            addLaunchRequest = WanderAddLaunchRequest(destination: .search(query: query))
            addSheetDetent = .large
            isPresentingAdd = true
        case .map:
            selectedTab = .map
        case .nearbyPlace(let candidateID):
            let snapshot = WanderNearbyWidgetSnapshotStore().load()
            let candidate = snapshot.flatMap {
                $0.isUsable(at: .now)
                    ? $0.place(id: candidateID)?.placeCandidate
                    : nil
            }
            selectedTab = .map
            store.saveFlowDidPresent(.addSheet)
            addTabResetToken = UUID()
            addLaunchRequest = WanderAddLaunchRequest(
                destination: candidate.map(
                    WanderAddLaunchRequest.Destination.nearbyPlace
                ) ?? .hereNow
            )
            addSheetDetent = .large
            isPresentingAdd = true
        case .quickSearch(let query):
            selectedTab = .map
            mapSearchLaunchRequest = WanderMapSearchLaunchRequest(query: query)
        case .profileCalendar:
            selectedTab = .profile
            profileCalendarLaunchRequest = WanderProfileCalendarLaunchRequest(
                targetDate: .now,
                destination: .calendar
            )
        case .profileCalendarDate(let calendarDate):
            guard let targetDate = calendarDate.date() else { return }
            selectedTab = .profile
            profileCalendarLaunchRequest = WanderProfileCalendarLaunchRequest(
                targetDate: targetDate,
                destination: .day
            )
        case .sharedProfile(let profileID):
            sharedProfile = SharedProfileRoute(profileID: profileID)
        case .sharedPlace(let placeID):
            selectedTab = .map
            pushNotifications.route(to: .place(id: placeID))
        case .sharedActivity(let activityID):
            selectedTab = .discover
            activityNavigation.openComments(activityID: activityID)
        case .sharedList(let listID):
            selectedTab = .lists
            pushNotifications.route(to: .list(id: listID))
        case .listInvite(let token):
            selectedTab = .lists
            pushNotifications.route(to: .listInvite(token: token))
        }
    }

    private func applyAuthStateIfNeeded(_ state: AuthState) {
        guard fixtureMode == .empty else {
            #if DEBUG
            WanderDebugLog.sync.debug("auth apply skipped fixture_mode=\(String(describing: fixtureMode), privacy: .public)")
            #endif
            return
        }

        switch state {
        case .signedIn(let session), .offline(let session, _):
            if widgetCalendarIdentityUserID != session.userID {
                WanderWidgetSnapshotPublisher.clear()
                widgetCalendarIdentityUserID = session.userID
                widgetCalendarHydratedUserID = nil
                widgetCalendarLastHydratedAt = nil
            }
        case .signedOut, .unavailable:
            WanderWidgetSnapshotPublisher.clear()
            widgetCalendarIdentityUserID = nil
            widgetCalendarHydratedUserID = nil
            widgetCalendarLastHydratedAt = nil
        case .loading:
            break
        }

        store.apply(authState: state)
        resetSharedVisitBannerTracking()

        if case .signedIn(let session) = state {
            if let maintenanceUserID = signedInMaintenanceUserID,
               maintenanceUserID != session.userID {
                cancelSignedInMaintenance()
            }
            scheduleSignedInMaintenance(for: state)
        } else {
            cancelSignedInMaintenance()
            #if DEBUG
            WanderDebugLog.sync.debug("auth state applied without backfill state=\(state.debugSummary, privacy: .public)")
            #endif
        }
    }

    private func seedSharedVisitBannerTracker() {
        sharedVisitBannerTracker.seed(
            invitationKeys: store.sharedVisitInvitations.map(SharedVisitBannerTracker.key)
        )
    }

    private func resetSharedVisitBannerTracking() {
        sharedVisitBannerTask?.cancel()
        sharedVisitBannerTask = nil
        sharedVisitBannerInvitation = nil
        seedSharedVisitBannerTracker()
    }

    private func presentSharedVisitBannerIfNeeded(from invitations: [SharedVisitInvitation]) {
        let keys = invitations.map(SharedVisitBannerTracker.key)
        guard let nextKey = sharedVisitBannerTracker.nextUnseenKey(in: keys),
              let invitation = invitations.first(where: { SharedVisitBannerTracker.key(for: $0) == nextKey })
        else { return }

        sharedVisitBannerTask?.cancel()
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.22)) {
            sharedVisitBannerInvitation = invitation
        }

        sharedVisitBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled,
                  sharedVisitBannerInvitation.map(SharedVisitBannerTracker.key) == nextKey
            else { return }
            dismissSharedVisitBanner()
        }
    }

    private func openSharedVisitFromBanner(_ invitation: SharedVisitInvitation) {
        dismissSharedVisitBanner()
        selectedTab = Self.sharedVisitBannerDestinationTab
        visitInvitationInboxRequestID = UUID()
    }

    private func dismissSharedVisitBanner() {
        sharedVisitBannerTask?.cancel()
        sharedVisitBannerTask = nil
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) {
            sharedVisitBannerInvitation = nil
        }
    }

    private func queueSaveStreakCelebration(_ celebration: SaveStreakCelebration?) {
        saveStreakCelebrationTask?.cancel()

        guard let celebration else {
            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
                presentedSaveStreakCelebration = nil
            }
            return
        }

        if SaveStreakPresentationPolicy.isExpired(celebration) {
            dismissSaveStreakCelebration(celebration)
            return
        }

        guard SaveStreakPresentationPolicy.canPresent(
            celebration: celebration,
            isSaveFlowPresented: store.isSaveFlowPresented
        ) else {
            return
        }

        saveStreakCelebrationTask = Task { @MainActor in
            do {
                try await Task.sleep(for: SaveStreakPresentationPolicy.postSaveSheetDelay)
            } catch {
                return
            }

            guard !Task.isCancelled,
                  store.saveStreakCelebration?.id == celebration.id
            else {
                return
            }

            if SaveStreakPresentationPolicy.isExpired(celebration) {
                dismissSaveStreakCelebration(celebration)
                return
            }

            guard !store.isSaveFlowPresented else { return }

            withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.18)) {
                presentedSaveStreakCelebration = celebration
            }

            guard let autoDismissDelay = SaveStreakPresentationPolicy.autoDismissDelay(
                for: celebration.kind
            ) else {
                return
            }

            do {
                try await Task.sleep(for: autoDismissDelay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            dismissSaveStreakCelebration(celebration)
        }
    }

    private func dismissSaveStreakCelebration(_ celebration: SaveStreakCelebration) {
        saveStreakCelebrationTask?.cancel()
        saveStreakCelebrationTask = nil
        withAnimation(accessibilityReduceMotion ? nil : .easeOut(duration: 0.16)) {
            presentedSaveStreakCelebration = nil
        }
        store.dismissSaveStreakCelebration(id: celebration.id)
    }

    private func scheduleSignedInMaintenance(for state: AuthState) {
        guard isSessionValidated,
              fixtureMode == .empty,
              case .signedIn(let session) = state,
              signedInMaintenanceTask == nil
        else { return }

        let runID = UUID()
        signedInMaintenanceRunID = runID
        signedInMaintenanceUserID = session.userID
        signedInMaintenanceTask = Task { @MainActor in
            let maintenanceSignpostID = WanderDebugLog.beginPerformanceInterval(
                "Signed-In Maintenance"
            )
            defer {
                WanderDebugLog.endPerformanceInterval(
                    "Signed-In Maintenance",
                    id: maintenanceSignpostID
                )
            }
            #if DEBUG
            if case .signedIn(let session) = state {
                WanderDebugLog.sync.debug("signed-in maintenance started user=\(WanderDebugLog.shortID(session.userID), privacy: .public) remote=\(backend.canUseRemoteData, privacy: .public)")
            }
            #endif
            if backend.notificationRepository != nil,
               let preferences = try? await backend.notificationPreferences() {
                guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                    finishSignedInMaintenance(runID: runID)
                    return
                }
                pushNotifications.applyNotificationPreferences(preferences)
            }
            await pushNotifications.refreshRemoteRegistrationIfNeeded(
                backend: backend,
                authState: state
            )
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let uploadedPhotoCount = await store.retryPendingVisitPhotoUploads(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let sentInviteCount = await store.retryPendingSharedVisitInvites(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let didHydrateCurrentProfile = await store.refreshRemoteCurrentProfile(backend: backend)
            guard didHydrateCurrentProfile,
                  shouldContinueSignedInMaintenance(runID: runID, state: state)
            else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let calendarRefreshDue = widgetCalendarHydratedUserID != session.userID
                || widgetCalendarLastHydratedAt.map {
                    Date.now.timeIntervalSince($0) >= Self.widgetCalendarRefreshInterval
                } ?? true
            if calendarRefreshDue {
                _ = await store.refreshRemoteCurrentUserCalendarData(
                    backend: backend
                )
                guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                    finishSignedInMaintenance(runID: runID)
                    return
                }
            }
            let syncedListCount = await store.syncPendingPlaceLists(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            await store.refreshRemotePlaceLists(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            await store.refreshSharedVisitInbox(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let enrichedPlaceCount = await store.refreshOwnPlaceProviderCategories(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let enrichmentSyncCount = enrichedPlaceCount > 0
                ? await store.syncUnsyncedOwnPlaces(backend: backend)
                : 0
            await refreshWannaGoReminders(for: state)
            #if DEBUG
            WanderDebugLog.sync.debug("signed-in maintenance finished synced_count=\(syncedCount, privacy: .public) list_synced_count=\(syncedListCount, privacy: .public) photo_count=\(uploadedPhotoCount, privacy: .public) invite_count=\(sentInviteCount, privacy: .public) enriched_place_count=\(enrichedPlaceCount, privacy: .public) enrichment_sync_count=\(enrichmentSyncCount, privacy: .public)")
            #endif
            finishSignedInMaintenance(runID: runID)
        }
    }

    private func shouldContinueSignedInMaintenance(runID: UUID, state: AuthState) -> Bool {
        isSessionValidated
            && !Task.isCancelled
            && signedInMaintenanceRunID == runID
            && auth.state == state
    }

    private func cancelSignedInMaintenance() {
        signedInMaintenanceRunID = nil
        signedInMaintenanceUserID = nil
        signedInMaintenanceTask?.cancel()
        signedInMaintenanceTask = nil
    }

    private func finishSignedInMaintenance(runID: UUID) {
        guard signedInMaintenanceRunID == runID else { return }
        signedInMaintenanceRunID = nil
        signedInMaintenanceUserID = nil
        signedInMaintenanceTask = nil
    }

    private static let widgetCalendarRefreshInterval: TimeInterval = 15 * 60

    private func refreshWannaGoReminders(for state: AuthState) async {
        guard case .signedIn = state else {
            pushNotifications.applyNotificationPreferences(.allDisabled)
            await pushNotifications.cancelAllWannaGoReminders()
            await pushNotifications.cancelAllSaveStreakReminders()
            return
        }
        guard isSessionValidated || fixtureMode != .empty else { return }

        if backend.notificationRepository != nil,
           let preferences = try? await backend.notificationPreferences() {
            guard auth.state == state, !Task.isCancelled else { return }
            pushNotifications.applyNotificationPreferences(preferences)
        }
        pushNotifications.configureSaveStreakReminders(for: store.currentUser.id)
        guard auth.state == state, !Task.isCancelled else { return }
        await store.refreshRemoteWannaGoPlans(backend: backend)
        guard auth.state == state, !Task.isCancelled else { return }
        await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems)
        guard auth.state == state, !Task.isCancelled else { return }
        await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary)
    }

    static func resolvedInitialTab(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderTab {
        guard let flagIndex = arguments.firstIndex(of: "-WanderInitialTab") else {
            return .map
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .map
        }

        let tab = WanderTab(rawValue: arguments[valueIndex]) ?? .map
        return tab == .add ? .map : tab
    }

    static func resolvedInitialPresentation(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderInitialPresentation? {
        arguments.contains("-WanderOpenSettings") ? .settings : nil
    }

    static func resolvedInitialDarkMap(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-WanderDarkMap")
    }

    static func resolvedInitialAddPresentation(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains("-WanderOpenAdd")
    }

    static func resolvedInitialSharedProfile(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SharedProfileRoute? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderOpenProfile") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let profileID = arguments[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return profileID.isEmpty ? nil : SharedProfileRoute(profileID: profileID)
    }

    static func resolvedFixtureMode(
        from arguments: [String] = ProcessInfo.processInfo.arguments,
        usesSimulatorTestSession: Bool? = nil
    ) -> WanderFixtureMode {
        #if DEBUG
        if arguments.contains("-WanderUseStorefrontFixtures") {
            return .storefront
        }
        #endif
        if arguments.contains("-WanderUsePerformanceFixtures") {
            return .performance
        }
        let restoresSimulatorTestSession = usesSimulatorTestSession
            ?? SimulatorTestSessionPolicy.isActive(arguments: arguments)
        if arguments.contains("-WanderUseDemoFixtures") || restoresSimulatorTestSession {
            return .demo
        }
        return .empty
    }

    static func resolvedFixtures(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtures {
        let fixtures = resolvedFixtures(mode: resolvedFixtureMode(from: arguments))
        #if DEBUG
        if arguments.contains("-WanderREC386PhotoFixture") {
            return rec386PhotoVisibilityFixtures(from: fixtures)
        }
        #endif
        return fixtures
    }

    static func resolvedFixtures(mode: WanderFixtureMode) -> WanderFixtures {
        switch mode {
        case .empty:
            WanderFixtures.empty()
        case .demo:
            WanderFixtures.seed()
        case .storefront:
            WanderFixtures.storefront()
        case .performance:
            WanderFixtures.performanceScale()
        }
    }

    #if DEBUG
    private static func rec386PhotoVisibilityFixtures(
        from source: WanderFixtures
    ) -> WanderFixtures {
        var fixtures = source
        guard let place = fixtures.places.first(where: { $0.localID == "local_place_bar_nido" }),
              let joePlace = fixtures.userPlaces.first(where: { $0.localID == "local_up_joe_bar_nido" }),
              let ryanPlace = fixtures.userPlaces.first(where: { $0.localID == "local_up_ryan_bar_nido" }),
              let image = UIImage(named: "PlaceCarouselPhotos"),
              let imageData = image.pngData(),
              let photoUUID = UUID(uuidString: "55000000-0000-0000-0000-000000000386"),
              let localAssetRef = VisitPhotoLocalFileStore.save(
                data: imageData,
                id: photoUUID,
                contentType: "image/png"
              )
        else { return fixtures }

        let previousPlaceIDs = Set([place.id, place.localID, place.serverID].compactMap { $0 })
        place.serverID = "50000000-0000-0000-0000-000000000386"
        place.canonicalName = "Dudley Market QA"
        for userPlace in fixtures.userPlaces where previousPlaceIDs.contains(userPlace.placeID) {
            userPlace.placeID = place.id
        }

        let joeVisit = LocalPlaceVisit(
            localID: "local_visit_rec386_disposable",
            serverID: "54000000-0000-0000-0000-000000000387",
            userPlaceID: joePlace.id,
            visitedAt: Date(timeIntervalSince1970: 1_777_682_100),
            note: "QA disposable check-in — delete me",
            ratingScore: 4,
            tags: ["disposable QA"],
            syncState: .pendingCreate
        )
        let ryanVisit = LocalPlaceVisit(
            localID: "local_visit_rec386_ryan",
            serverID: "54000000-0000-0000-0000-000000000386",
            userPlaceID: ryanPlace.id,
            visitedAt: Date(timeIntervalSince1970: 1_777_678_500),
            note: "QA proof: Ryan's uploaded check-in photo",
            ratingScore: 5,
            tags: ["photo proof"],
            syncState: .synced,
            serverUpdatedAt: Date(timeIntervalSince1970: 1_777_678_500)
        )
        let ryanPhoto = LocalVisitPhoto(
            localID: "local_photo_rec386_ryan",
            serverID: photoUUID.uuidString.lowercased(),
            visitID: ryanVisit.id,
            storageBucket: "visit-photos",
            storagePath: "user_ryan/54000000-0000-0000-0000-000000000386/photo.png",
            localAssetRef: localAssetRef,
            contentType: "image/png",
            byteSize: imageData.count,
            width: Int(image.size.width),
            height: Int(image.size.height),
            capturedAt: ryanVisit.visitedAt,
            uploadState: .uploaded,
            syncState: .synced,
            serverUpdatedAt: ryanVisit.serverUpdatedAt
        )
        fixtures.placeVisits.append(contentsOf: [joeVisit, ryanVisit])
        fixtures.visitPhotos.append(ryanPhoto)
        return fixtures
    }
    #endif

    private static func makeStore(
        fixtureMode: WanderFixtureMode,
        parser: any LLMFilterParser,
        analytics: AnalyticsClient,
        persistence: WanderStorePersistence?,
        initialSession: AuthSession?
    ) -> WanderStore {
        let fixturesStartedAt = CFAbsoluteTimeGetCurrent()
        let fixtures = resolvedFixtures(from: ProcessInfo.processInfo.arguments)
        let fixturesFinishedAt = CFAbsoluteTimeGetCurrent()
        #if DEBUG
        let placeResolver: any PlaceCandidateResolving = fixtureMode == .storefront
            ? StorefrontPlaceResolver()
            : MapKitPlaceResolver()
        #else
        let placeResolver: any PlaceCandidateResolving = MapKitPlaceResolver()
        #endif
        let store = WanderStore(
            fixtures: fixtures,
            placeResolver: placeResolver,
            parser: parser,
            analytics: analytics,
            persistence: persistence
        )
        if fixtureMode == .empty, let initialSession {
            store.apply(authState: .signedIn(initialSession))
        }
        let storeFinishedAt = CFAbsoluteTimeGetCurrent()
        WanderDebugLog.performance.notice(
            "root initialization fixture_mode=\(String(describing: fixtureMode), privacy: .public) fixture_ms=\((fixturesFinishedAt - fixturesStartedAt) * 1_000, privacy: .public) store_ms=\((storeFinishedAt - fixturesFinishedAt) * 1_000, privacy: .public)"
        )
        return store
    }
}

private final class WanderTabFrameAnchorView: UIView {
    var onGeometryChange: ((WanderTabFrameAnchorView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onGeometryChange?(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onGeometryChange?(self)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onGeometryChange?(self)
    }
}

enum WanderTabBarWalkthroughTargetGeometry {
    static func targetFrame(
        controlFrames: [CGRect],
        visibleBounds: CGRect
    ) -> CGRect? {
        let visibleControlFrames = controlFrames.filter {
            !$0.isNull && !$0.isInfinite && !$0.isEmpty
        }
        guard let first = visibleControlFrames.first else { return nil }

        let union = visibleControlFrames.dropFirst().reduce(first) { $0.union($1) }
        let visibleUnion = union.intersection(visibleBounds)
        guard !visibleUnion.isNull, !visibleUnion.isInfinite, !visibleUnion.isEmpty else {
            return nil
        }
        return visibleUnion
    }
}

private struct WanderNativeTabFrameReader: UIViewRepresentable {
    let tabs: [WanderTab]
    let onItemControlsFrameChange: (CGRect?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(observer: self)
    }

    func makeUIView(context: Context) -> WanderTabFrameAnchorView {
        let view = WanderTabFrameAnchorView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.onGeometryChange = { [weak coordinator = context.coordinator] anchorView in
            coordinator?.attachIfNeeded(to: anchorView)
        }
        return view
    }

    func updateUIView(_ uiView: WanderTabFrameAnchorView, context: Context) {
        context.coordinator.update(observer: self, anchorView: uiView)
    }

    static func dismantleUIView(
        _ uiView: WanderTabFrameAnchorView,
        coordinator: Coordinator
    ) {
        uiView.onGeometryChange = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private var observer: WanderNativeTabFrameReader
        private var lastPublishedItemControlsFrame: CGRect?
        private var attachmentRetryTask: Task<Void, Never>?
        private var attachmentRetryCount = 0

        init(observer: WanderNativeTabFrameReader) {
            self.observer = observer
        }

        func update(observer: WanderNativeTabFrameReader, anchorView: WanderTabFrameAnchorView) {
            self.observer = observer
            attachIfNeeded(to: anchorView)
        }

        func attachIfNeeded(to anchorView: WanderTabFrameAnchorView) {
            guard let window = anchorView.window,
                  let tabBar = Self.findTabBar(in: window),
                  tabBar.items?.count == observer.tabs.count,
                  let itemControls = Self.itemControls(
                    in: tabBar,
                    tabs: observer.tabs
                  )
            else {
                publishItemControlsFrame(nil)
                scheduleAttachmentRetry(for: anchorView)
                return
            }

            attachmentRetryTask?.cancel()
            attachmentRetryTask = nil
            attachmentRetryCount = 0

            let convertedFrames = itemControls.map {
                window.convert($0.bounds, from: $0)
            }
            let targetFrame = WanderTabBarWalkthroughTargetGeometry.targetFrame(
                controlFrames: convertedFrames,
                visibleBounds: window.bounds
            )
            publishItemControlsFrame(targetFrame)
        }

        func detach() {
            attachmentRetryTask?.cancel()
            attachmentRetryTask = nil
            attachmentRetryCount = 0
            publishItemControlsFrame(nil)
        }

        private func scheduleAttachmentRetry(for anchorView: WanderTabFrameAnchorView) {
            guard attachmentRetryTask == nil, attachmentRetryCount < 20 else { return }
            attachmentRetryCount += 1
            attachmentRetryTask = Task { @MainActor [weak self, weak anchorView] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self, let anchorView else { return }
                self.attachmentRetryTask = nil
                self.attachIfNeeded(to: anchorView)
            }
        }

        private func publishItemControlsFrame(_ frame: CGRect?) {
            guard frame != lastPublishedItemControlsFrame else { return }
            lastPublishedItemControlsFrame = frame
            let onChange = observer.onItemControlsFrameChange
            DispatchQueue.main.async {
                onChange(frame)
            }
        }

        private static func itemControls(
            in tabBar: UITabBar,
            tabs: [WanderTab]
        ) -> [UIControl]? {
            let visibleControls = descendantControls(in: tabBar)
                .filter { !$0.isHidden && $0.alpha > 0 && $0.isUserInteractionEnabled }
            let labeledControls = tabs.compactMap { tab in
                visibleControls.first { control in
                    control.accessibilityLabel?.caseInsensitiveCompare(tab.title) == .orderedSame
                }
            }
            let tabBarButtons = visibleControls.filter {
                String(describing: type(of: $0)).contains("UITabBarButton")
            }
            var controls: [UIControl]
            if Set(labeledControls.map(ObjectIdentifier.init)).count == tabs.count {
                controls = labeledControls
            } else if tabBarButtons.count == tabs.count {
                controls = tabBarButtons.sorted { $0.frame.minX < $1.frame.minX }
            } else {
                return nil
            }
            if tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft {
                controls.reverse()
            }
            return controls
        }

        private static func descendantControls(in root: UIView) -> [UIControl] {
            root.subviews.flatMap { subview in
                let control = (subview as? UIControl).map { [$0] } ?? []
                return control + descendantControls(in: subview)
            }
        }

        private static func findTabBar(in root: UIView) -> UITabBar? {
            if let tabBar = root as? UITabBar, !tabBar.isHidden, tabBar.alpha > 0 {
                return tabBar
            }

            for subview in root.subviews {
                if let tabBar = findTabBar(in: subview) {
                    return tabBar
                }
            }

            return nil
        }
    }
}

enum WanderFixtureMode: Equatable {
    case empty
    case demo
    case storefront
    case performance
}

enum WanderInitialPresentation: String, Identifiable {
    case settings

    var id: String { rawValue }
}

struct SharedProfileRoute: Equatable, Identifiable {
    let profileID: String
    var id: String { profileID }
}

enum WanderTab: String, CaseIterable, Hashable {
    case map
    case discover
    case add
    case lists
    case profile

    static let primaryTabs: [WanderTab] = [.map, .discover, .lists, .profile]

    var title: String {
        switch self {
        case .map: "Map"
        case .discover: "Feed"
        case .add: "Add"
        case .lists: "Lists"
        case .profile: "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .map: "map"
        case .discover: "newspaper"
        case .add: "plus"
        case .lists: "bookmark.square"
        case .profile: "person.crop.circle"
        }
    }

}
