import SwiftUI

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
            return "Some shared places were added"
        }
        if report.importedOrDuplicateBatchCount > 0 {
            return "Shared places added"
        }
        return "Shared import needs attention"
    }

    var message: String {
        var parts: [String] = []
        if report.importedBatchCount > 0 {
            parts.append(
                "\(report.importedBatchCount) import\(report.importedBatchCount == 1 ? "" : "s") added to your inbox."
            )
        }
        if report.duplicateBatchCount > 0 {
            parts.append(
                "\(report.duplicateBatchCount) import\(report.duplicateBatchCount == 1 ? " was" : "s were") already in your inbox."
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
    @State private var restoredPlaceSaveDraftOwnerID: String?
    @State private var interruptedSaveRecoveryMessage: String?
    @StateObject private var store: WanderStore
    @StateObject private var importStore: PlaceImportStore
    @StateObject private var placeSaveDraftStore: PlaceSaveDraftStore
    @StateObject private var controlNavigationCenter = WanderControlNavigationCenter.shared
    private let fixtureMode: WanderFixtureMode
    private let isSessionValidated: Bool
    private let deepLinkLaunchRequest: WanderDeepLinkLaunchRequest?
    private let onDeepLinkLaunchRequestHandled: (UUID) -> Void
    private let analytics: AnalyticsClient

    init(
        initialTab: WanderTab? = nil,
        initialPresentation: WanderInitialPresentation? = nil,
        initialSharedProfileRoute: SharedProfileRoute? = nil,
        initialSession: AuthSession? = nil,
        isSessionValidated: Bool = true,
        deepLinkLaunchRequest: WanderDeepLinkLaunchRequest? = nil,
        onDeepLinkLaunchRequestHandled: @escaping (UUID) -> Void = { _ in },
        analytics: AnalyticsClient = NoopAnalyticsClient(),
        parser: any LLMFilterParser = DeterministicFilterParser()
    ) {
        let fixtureMode = Self.resolvedFixtureMode()
        self.fixtureMode = fixtureMode
        self.isSessionValidated = isSessionValidated
        self.deepLinkLaunchRequest = deepLinkLaunchRequest
        self.onDeepLinkLaunchRequestHandled = onDeepLinkLaunchRequestHandled
        self.analytics = analytics
        let requestedTab = initialTab ?? Self.resolvedInitialTab()
        _selectedTab = State(initialValue: requestedTab == .add ? .map : requestedTab)
        _isPresentingAdd = State(initialValue: Self.resolvedInitialAddPresentation())
        _initialPresentation = State(initialValue: initialPresentation ?? Self.resolvedInitialPresentation())
        _sharedProfile = State(initialValue: initialSharedProfileRoute ?? Self.resolvedInitialSharedProfile())
        let persistence: WanderStorePersistence? = fixtureMode == .empty ? .live : nil
        _store = StateObject(
            wrappedValue: Self.makeStore(
                fixtureMode: fixtureMode,
                parser: parser,
                analytics: analytics,
                persistence: persistence,
                initialSession: initialSession
            )
        )
        let importStore = PlaceImportStore()
        _importStore = StateObject(wrappedValue: importStore)
        _placeSaveDraftStore = StateObject(wrappedValue: PlaceSaveDraftStore())
        _addSheetDetent = State(
            initialValue: AddSheetLayout.restingDetent(
                hasPendingImports: importStore.summary.hasPendingImports
            )
        )
    }

    var body: some View {
        stateObservedRoot
    }

    private var tabRoot: some View {
        TabView(selection: tabSelection) {
            MapScreen(
                presentationResetRequest: presentationResetRequest,
                searchLaunchRequest: mapSearchLaunchRequest,
                onSearchLaunchRequestHandled: consumeMapSearchLaunchRequest,
                onAdd: presentAddSheet
            )
                .tabItem { Label(WanderTab.map.title, systemImage: WanderTab.map.systemImage) }
                .tag(WanderTab.map)

            FeedScreen(onAdd: presentAddSheet)
                .tabItem { Label(WanderTab.discover.title, systemImage: WanderTab.discover.systemImage) }
                .tag(WanderTab.discover)

            ListsScreen()
                .tabItem { Label(WanderTab.lists.title, systemImage: WanderTab.lists.systemImage) }
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
                .tabItem { Label(WanderTab.profile.title, systemImage: WanderTab.profile.systemImage) }
                .tag(WanderTab.profile)
        }
        .tint(WanderTheme.terracotta.color)
        .preferredColorScheme(.light)
        .environmentObject(store)
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

    private var presentedRoot: some View {
        tabRoot
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
                    onLaunchRequestHandled: consumeAddLaunchRequest
                ) {
                    isPresentingAdd = false
                }
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
                    .presentationDetents(
                        AddSheetLayout.detents(
                        hasPendingImports: importStore.summary.hasPendingImports
                        ),
                        selection: $addSheetDetent
                    )
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
                    .presentationBackground(WanderTheme.surfaceBone.color)
                    .presentationContentInteraction(.resizes)
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
                    SettingsScreen()
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

    private var lifecycleRoot: some View {
        presentedRoot
        .task(id: isSessionValidated) {
            guard isSessionValidated else {
                cancelSignedInMaintenance()
                return
            }
            restorePlaceSaveDraftIfNeeded()
            seedSharedVisitBannerTracker()
            queueSaveStreakCelebration(store.saveStreakCelebration)
            drainSharedPlaceImports()
            importStore.resumePendingImports()
            reconcilePlaceImports()
            publishWidgetSnapshot()
            refreshNearbyWidgetSnapshot()
            await pushNotifications.refreshAuthorizationStatus()
            guard !Task.isCancelled, isSessionValidated else { return }
            applyAuthStateIfNeeded(auth.state)
            await refreshWannaGoReminders(for: auth.state)
            guard !Task.isCancelled, isSessionValidated else { return }
            while let pendingUserInfo = WanderAppDelegate.takePendingNotificationUserInfo(
                for: store.currentUser.id
            ) {
                pushNotifications.handleNotificationResponse(userInfo: pendingUserInfo)
            }
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
            guard isSessionValidated,
                  let userInfo = WanderAppDelegate.takePendingNotificationUserInfo(
                      for: store.currentUser.id
                  )
                ?? notification.userInfo?[WanderAppDelegate.userInfoKey] as? [AnyHashable: Any]
            else { return }
            pushNotifications.handleNotificationResponse(userInfo: userInfo)
            scheduleSignedInMaintenance(for: auth.state)
        }
        .onReceive(NotificationCenter.default.publisher(for: WanderAppDelegate.didReceiveRemoteNotification)) { _ in
            guard isSessionValidated else { return }
            scheduleSignedInMaintenance(for: auth.state)
        }
    }

    private var authObservedRoot: some View {
        lifecycleRoot
        .onChange(of: pushNotifications.navigationRequest) { _, request in
            guard isSessionValidated, let request else { return }
            routeNotification(request)
        }
        .onChange(of: auth.state) { _, state in
            if !state.isSignedIn {
                placeSaveDraftStore.clear()
                restoredPlaceSaveDraftOwnerID = nil
            }
            applyAuthStateIfNeeded(state)
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
            Task {
                await pushNotifications.reconcileSaveStreakReminder(store.saveStreakSummary)
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
        .onChange(of: importStore.summary.hasPendingImports) { _, _ in
            guard addSheetDetent != .large else { return }
            addSheetDetent = addSheetRestingDetent
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
            }
            guard phase == .active, isSessionValidated else { return }
            drainSharedPlaceImports()
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
                onReview: presentSharedPlaceImportReview
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
            }
        } message: {
            Text(interruptedSaveRecoveryMessage ?? "")
        }
        .onChange(of: isSessionValidated, initial: true) { _, isValidated in
            if isValidated {
                handleControlNavigationRequestIfReady(
                    controlNavigationCenter.pendingRequest
                )
            } else {
                cancelSignedInMaintenance()
            }
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
                selectedTab = newTab
            }
        }
    }

    private func presentAddSheet() {
        placeSaveDraftStore.clear()
        store.saveFlowDidPresent(.addSheet)
        addTabResetToken = UUID()
        addLaunchRequest = nil
        addSheetDetent = addSheetRestingDetent
        isPresentingAdd = true
    }

    private func restorePlaceSaveDraftIfNeeded() {
        let ownerUserID = store.currentUser.id
        guard restoredPlaceSaveDraftOwnerID != ownerUserID else { return }
        restoredPlaceSaveDraftOwnerID = ownerUserID

        guard case .restored(let draft) = placeSaveDraftStore.restore(
            ownerUserID: ownerUserID
        ) else { return }

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
            placeSaveDraftStore.clear()
            interruptedSaveRecoveryMessage = draft.form.selectedStatus == .been
                ? "Your check-in finished while rec.me was in the background."
                : "This place was added to Wanna while rec.me was in the background."
        case .retry:
            placeSaveDraftStore.prepareRetry(
                message: "Save was interrupted before rec.me could confirm it. Review your details and try again."
            )
            presentRestoredAddSheet()
        case .editing:
            presentRestoredAddSheet()
        }
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
        guard let inbox = try? SharedPlaceImportInbox.live() else { return }
        let report = SharedPlaceImportInboxDrainer.drain(
            inbox: inbox,
            into: importStore
        )
        guard report.hasUserVisibleResult else { return }
        reconcilePlaceImports()
        sharedPlaceImportNotice = SharedPlaceImportDrainNotice(report: report)
    }

    private func presentSharedPlaceImportReview() {
        addTabResetToken = UUID()
        addSheetDetent = .large
        addLaunchRequest = WanderAddLaunchRequest(destination: .importInbox)
        isPresentingAdd = true
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
        if request.destination == .quickCapture {
            analytics.track(
                AnalyticsEvent(
                    name: WanderAnalyticsEvents.saveStreakReminderOpened,
                    properties: [:]
                )
            )
            pushNotifications.consumeNavigationRequest(id: request.id)
            beginDeepLinkHandoff(to: .quickCapture)
            return
        }

        isPresentingAdd = false
        initialPresentation = nil

        selectedTab = Self.notificationTab(for: request.destination)
        if request.destination == .discover {
            pushNotifications.consumeNavigationRequest(id: request.id)
        }
    }

    static func notificationTab(for destination: NotificationDestination) -> WanderTab {
        switch destination {
        case .quickCapture: .map
        case .people, .drafts: .profile
        case .list, .listInvite: .lists
        case .place, .sharedVisit: .map
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
            let didHydrateCurrentProfile = await store.refreshRemoteCurrentProfile(backend: backend)
            guard didHydrateCurrentProfile,
                  shouldContinueSignedInMaintenance(runID: runID, state: state)
            else {
                finishSignedInMaintenance(runID: runID)
                return
            }
            let syncedCount = await store.syncUnsyncedOwnPlaces(backend: backend)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
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
            await pushNotifications.registerStoredDeviceTokenIfPossible(backend: backend, authState: state)
            guard shouldContinueSignedInMaintenance(runID: runID, state: state) else {
                finishSignedInMaintenance(runID: runID)
                return
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

    static func resolvedFixtureMode(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtureMode {
        if arguments.contains("-WanderUsePerformanceFixtures") {
            return .performance
        }
        return arguments.contains("-WanderUseDemoFixtures") ? .demo : .empty
    }

    static func resolvedFixtures(from arguments: [String] = ProcessInfo.processInfo.arguments) -> WanderFixtures {
        resolvedFixtures(mode: resolvedFixtureMode(from: arguments))
    }

    static func resolvedFixtures(mode: WanderFixtureMode) -> WanderFixtures {
        switch mode {
        case .empty:
            WanderFixtures.empty()
        case .demo:
            WanderFixtures.seed()
        case .performance:
            WanderFixtures.performanceScale()
        }
    }

    private static func makeStore(
        fixtureMode: WanderFixtureMode,
        parser: any LLMFilterParser,
        analytics: AnalyticsClient,
        persistence: WanderStorePersistence?,
        initialSession: AuthSession?
    ) -> WanderStore {
        let fixturesStartedAt = CFAbsoluteTimeGetCurrent()
        let fixtures = resolvedFixtures(mode: fixtureMode)
        let fixturesFinishedAt = CFAbsoluteTimeGetCurrent()
        let store = WanderStore(
            fixtures: fixtures,
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

enum WanderFixtureMode: Equatable {
    case empty
    case demo
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
