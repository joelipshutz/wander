import SwiftUI
import MapKit

/// A map and a resizable window onto the existing Feed. Profile's map is an
/// independent destination; none of its owner-history tools move here.
struct LiveScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var activityNavigation: ActivityNavigationCoordinator
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @EnvironmentObject private var planInbox: PlacePlanInvitationInbox
    @Environment(\.astirBrandMode) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera: MapCameraPosition = .region(LiveMapLaunchLocation.initialRegion())
    @State private var cameraRevision: UInt64 = 0
    @State private var launchLocation = LiveMapLaunchLocation()
    @StateObject private var locationPermission = OnboardingLocationPermissionManager()
    @StateObject private var mapResults = LiveMapResults()
    @StateObject private var pinStateLoader = LiveMapPinStateLoader()
    @State private var mapActivity: [FeedActivity] = []
    @State private var mapPins: [LivePlacePin] = []
    @State private var committedMapBoundary: LiveDrawnArea?
    @State private var committedMapViewport: MapViewport?
    @State private var mapRefresh: UInt64 = 0
    @State private var mapRefreshDeferred = false
    @State private var fullProfilePin: LivePlacePin?
    @State private var fullProfileCandidate: PlaceCandidate?
    @State private var nativeFeature: MKMapFeatureAnnotation?
    @State private var selectedCandidate: PlaceCandidate?
    @State private var nativeFeatureTask: Task<Void, Never>?
    @State private var nativeFeatureRequest = UUID()
    @State private var nativeSelectionRevision = UUID()
    @State private var nativePreviewID: String?
    @State private var viewport: MKCoordinateRegion?
    @State private var mapSize: CGSize = .zero
    @State private var drawerMapOrigin: MKCoordinateRegion?
    @State private var cardMapOrigin: MKCoordinateRegion?
    @State private var previewHeight: CGFloat = 400
    @State private var previewCameraAdjusted = false
    @State private var previewAnimationTrigger = 0
    @State private var viewedPins: [String: Date] = [:]
    @State private var feedIsScrolled = false
    @State private var feedScrollResetRequest: UUID?
    @State private var previewSaveContext: MapPlaceSaveContext?
    @State private var previewSharePlace: LivePlaceShareRoute?
    @State private var departedAt: Date?
    @State private var departedDetent = 1
    @State private var departedFeedWasScrolled = false
    @State private var nearbyLoading = false
    @StateObject private var recentListAdd = RecentPlaceListAddController()
    @State private var didFrame = false
    @State private var detent = 1
    @State private var isFeedDestinationActive = false
    @State private var selection = LiveBrowseSelection()
    @State private var area: LiveSelectedArea?
    @State private var mapSearch = LiveMapSearchState()
    @State private var mapControlsHeight: CGFloat = 0
    @State private var drawerHeaderHeight: CGFloat = 0
    @State private var drawingActionsHeight: CGFloat = 0
    @State private var drawing = false
    @State private var drawPoints: [CGPoint] = []
    @State private var drawCoordinates: [CLLocationCoordinate2D] = []
    @State private var draftArea: LiveDrawnArea?
    @State private var drawingError: String?
    @State private var filtersPresented = false
    @State private var draftSelection = LiveBrowseSelection()
    @State private var draftAudience: FeedAudience = .everyone
    @State private var draftClearsArea = false
    @State private var selectedPlaceID: String?
    @State private var focusRequest: FeedActivityFocusRequest?
    @State private var surfaceRequest: FeedSurfaceRequest?
    @State private var introductionAudience: LiveIntroductionAudience?
    @State private var introductionAcknowledged = false
    @State private var showsIntroductionGuide = false
    @State private var planSource: VisiblePlace?
    @State private var queuedPlan: CommonGroundMockPlace?
    @State private var queuedPlaceID: String?
    @State private var queuedActivityID: String?
    @State private var wantsPeopleSearch = false
    @State private var selectedPlan: CommonGroundMockPlace?
    @State private var showsEvents = false
    @State private var showsContactInvites = false
    @State private var showsUpcomingInvitations = false
    @State private var receivedPlan: ReceivedPlacePlanInvitation?
    @State private var queuedReceivedPlan: ReceivedPlacePlanInvitation?
    @State private var wantsNotificationInbox = false
    @State private var showsMessages = false
    @State private var areaNotice = false
    @Environment(\.liveMessageSession) private var demoMessageSession
    @State private var replyTarget: PrivateMessageThreadTarget?
    @State private var mapProxy = LiveNativeMapProxy()

    let isActive: Bool
    let eventsAvailable: Bool
    let homeMetroID: String?
    let introductionContext: LiveIntroductionContext
    var migrationRecord: LiveIntroductionMigrationRecord? = nil
    var onContinueMigration: () -> Void = {}
    var onDeferMigration: () -> Void = {}
    var onMigrationPresented: () -> Void = {}
    let presentationResetRequest: WanderPresentationResetRequest?
    let onPresentation: (WanderDeepLinkPresentationToken) -> Void
    let onWillDismiss: (WanderDeepLinkPresentationToken) -> Void
    let onDidDismiss: (WanderDeepLinkPresentationSurface) -> Void
    let onAdd: () -> Void

    private var authorizedActivity: [FeedActivity] { mapActivity }
    private var activity: [FeedActivity] { mapActivity }
    private var pins: [LivePlacePin] { mapPins }
    private var usesTotemReviewFixture: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if LiveTotemUITestFixtures.isEnabled { return true }
        #endif
        return false
    }
    private var pinStateRequest: LiveMapPinStateRequest? {
        guard !usesTotemReviewFixture, let request = mapRequest else { return nil }
        return LiveMapPinStateRequest(map: request,
            placeIDs: Array(Set(mapPins.flatMap { $0.identity.persistedPlaceIDs })).sorted(),
            resultRevision: mapResults.revision, storeRevision: store.presentationRevision)
    }
    private var mapRequest: LiveMapRequest? {
        guard let query = store.liveFeedQuery else { return nil }
        return LiveMapRequest(userID: store.currentUser.id, audience: store.feedAudience,
            query: query, featured: selection.scope == .featured,
            viewport: committedMapViewport, refresh: mapRefresh)
    }

    private var selectedPin: LivePlacePin? { pins.first { $0.id == selectedPlaceID } }

    private var hasPlacePreview: Bool { selectedPin != nil || selectedCandidate != nil }
    private var previewID: String? { selectedPin?.id ?? nativePreviewID }
    private var previewCoordinate: CLLocationCoordinate2D? {
        if let pin = selectedPin { return coordinate(pin.place) }
        guard let latitude = selectedCandidate?.latitude, let longitude = selectedCandidate?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var showsFeedDestination: Bool {
        isFeedDestinationActive || activityNavigation.commentsRoute != nil
    }

    var body: some View {
        liveContent.modifier(LiveContactInvitePresentation(presented: $showsContactInvites,
            onDismiss: modalDidDismiss, lifecycle: modalLifecycle))
    }

    private var livePresentedContent: some View {
        GeometryReader { geometry in
            let drawerHeight = showsFeedDestination ? geometry.size.height
                : hasPlacePreview ? 0 : height(for: detent, available: geometry.size.height)
            let hidesDrawer = (drawing || hasPlacePreview) && !showsFeedDestination
            ZStack(alignment: .bottom) {
                map(drawerHeight: drawing ? 0 : drawerHeight)
                    .allowsHitTesting(!showsFeedDestination)
                    .accessibilityHidden(showsFeedDestination)
                // Keep the Feed's identity and viewport while drawing. Recreating
                // it forgets consumed navigation requests and can reopen Search.
                drawer(height: drawerHeight)
                    .offset(y: hidesDrawer ? geometry.size.height : 0)
                    .allowsHitTesting(!hidesDrawer)
                    .accessibilityHidden(hidesDrawer)
                    .background(alignment: .bottom) {
                        // Paint only below the drawer, behind the native tab
                        // bar; preserve the map's existing attribution inset.
                        brand.background.frame(height: geometry.safeAreaInsets.bottom + 1)
                            .offset(y: geometry.safeAreaInsets.bottom)
                            .allowsHitTesting(false)
                    }
                if drawing && !showsFeedDestination {
                    drawingControls
                }
                if hasPlacePreview, !drawing, !showsFeedDestination {
                    placePreview(availableHeight: geometry.size.height)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(3)
                }
                if detent == 2, !showsFeedDestination, !hasPlacePreview, !drawing {
                    Button { changeDetent(0) } label: {
                        Label("Map", systemImage: "map.fill")
                            .font(AstirTypography.body.weight(.semibold))
                            .padding(.horizontal, 22).frame(height: 48)
                            .foregroundStyle(brand.primaryText)
                            .astirGlassSurface(cornerRadius: 24, castsShadow: true, interactive: true)
                    }.buttonStyle(.plain).padding(.bottom, 18)
                        .accessibilityIdentifier("live.showMap").zIndex(4)
                }
            }
            .onAppear { mapSize = geometry.size; frameInitialMap() }
            .onChange(of: geometry.size) { _, size in mapSize = size; frameInitialMap() }
            .overlay(alignment: .top) {
                // Shield system status text from map labels without moving the
                // Map, its camera insets, or the drawing coordinate space.
                brand.background
                    .frame(height: geometry.safeAreaInsets.top)
                    .offset(y: -geometry.safeAreaInsets.top)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(brand.background)
        .recentPlaceListAddPresentation(recentListAdd)
        // These profiles return to the selected preview. A Feed departure
        // snapshot here would outlive that preview and override the next
        // actual Feed destination's scroll position.
        .fullScreenCover(item: $fullProfilePin, onDismiss: modalDidDismiss) { pin in
            LivePlaceFullProfileScreen(place: pin.place, activities: activity, identity: pin.identity,
                onBack: { fullProfilePin = nil })
                .modifier(modalLifecycle)
        }
        .fullScreenCover(item: $fullProfileCandidate, onDismiss: modalDidDismiss) { candidate in
            LivePlaceFullProfileScreen(candidate: candidate, onBack: { fullProfileCandidate = nil })
                .modifier(modalLifecycle)
        }
        .sheet(item: $previewSaveContext, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
            modalDidDismiss()
        }) { context in
            MapPlaceSaveFlowSheet(context: context,
                onSave: { submission in
                    await persistAddPlaceSaveSubmission(submission, store: store, backend: auth.isSignedIn ? backend : nil)
                },
                onRemove: { context in
                    guard case .editWant(let own) = context.mode else { return false }
                    return await store.removeSave(userPlaceID: own.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil
                },
                onClose: { previewSaveContext = nil },
                onSaveCompleted: { _ in previewSaveContext = nil })
                .modifier(modalLifecycle)
        }
        .sheet(item: $previewSharePlace, onDismiss: modalDidDismiss) { route in
            let place = route.place
            if let url = route.shareURL {
                let content = WanderShareContent.place(item: url, name: place.name,
                    message: PlaceExternalLinks.shareSummary(placeName: place.name, locality: place.locality, status: place.status))
                ActivitySharePreviewScreen(
                    card: ShareCardContent(kind: .place, name: place.name, detail: place.compactPlaceType),
                    content: content,
                    completion: { completed in store.trackPlaceShareCompletion(completed: completed) },
                    loadImages: { ShareCardImages(photos: await ShareCardRenderer.placeImages([place.photoRequest], backend: backend)) }
                ).modifier(modalLifecycle)
            }
        }
        .sheet(isPresented: $filtersPresented, onDismiss: modalDidDismiss) { filters.modifier(modalLifecycle) }
        .sheet(isPresented: $showsIntroductionGuide, onDismiss: modalDidDismiss) {
            NavigationStack {
                LiveIntroductionGuide(orientation: introductionAudience == .firstVisit
                    ? LiveIntroductionOrientationContext(userID: store.currentUser.id) : nil)
            }.modifier(modalLifecycle)
        }
        .sheet(isPresented: $showsMessages, onDismiss: modalDidDismiss) {
            NavigationStack {
                PrivateMessageInboxScreen(userID: store.currentUser.id,
                                          repository: messageRepository,
                                          analytics: store.productAnalytics, onOpenContext: openMessageContext,
                                          onOpenProfile: openMessageProfile)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showsMessages = false } } }
            }
            .modifier(modalLifecycle)
        }
        .sheet(item: $replyTarget, onDismiss: modalDidDismiss) { target in
            NavigationStack {
                PrivateMessageThreadScreen(userID: store.currentUser.id,
                                           repository: messageRepository,
                                           target: target, analytics: store.productAnalytics, onOpenContext: openMessageContext,
                                          onOpenProfile: openMessageProfile)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { replyTarget = nil } } }
            }
            .modifier(modalLifecycle)
        }
        .sheet(item: $planSource, onDismiss: modalDidDismiss) { place in
            NavigationStack {
                LivePlanPeoplePicker(place: place, onSelect: { selection in
                    queuedPlan = selection; planSource = nil
                }, onFindPeople: {
                    wantsPeopleSearch = true; planSource = nil
                }, onOpenPlace: { destination in
                    queuedPlaceID = destination.place.id; planSource = nil
                })
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { planSource = nil } } }
            }.modifier(modalLifecycle)
        }
        .sheet(item: $selectedPlan, onDismiss: modalDidDismiss) { place in
            NavigationStack {
                CommonGroundInvitationMockup(
                    draft: CommonGroundInvitationDraft(place: place), liveSharing: true,
                    analytics: store.productAnalytics,
                    canShare: { candidate in
                        LivePlanPeoplePolicy.canShare(candidate, store: store)
                    },
                    prepareShare: { draft in
                        try await CommonGroundInvitationSharing.prepare(draft: draft, backend: backend, brand: brand)
                    }
                )
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { selectedPlan = nil } } }
            }
            .modifier(modalLifecycle)
        }
        .sheet(isPresented: $showsEvents, onDismiss: modalDidDismiss) {
            NavigationStack {
                EventsComingSoonScreen(isSelected: true, userID: auth.state.session?.userID,
                                       repository: backend.eventsInterestRepository, analytics: store.productAnalytics)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsEvents = false } } }
            }
            .modifier(modalLifecycle)
        }
        .sheet(isPresented: $showsUpcomingInvitations, onDismiss: modalDidDismiss) {
            NavigationStack {
                ScrollView {
                LiveUpcomingInvitationsView(userID: invitationUserID, onOpenInvitation: {
                    queuedReceivedPlan = $0; showsUpcomingInvitations = false
                }, onOpenInbox: {
                    wantsNotificationInbox = true; showsUpcomingInvitations = false
                })
                .padding(20)
                }
                .navigationTitle("Upcoming Invitations").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showsUpcomingInvitations = false }
                } }
            }.modifier(modalLifecycle)
        }
        .sheet(item: $receivedPlan, onDismiss: modalDidDismiss) { plan in
            let recipientID = invitationUserID
            PlacePlanInvitationScreen(invitationID: plan.id,
                repository: backend.placePlanInvitationRepository, analytics: store.productAnalytics) {
                guard let recipientID, invitationUserID == recipientID else { return }
                planInbox.markOpened(id: plan.id, userID: recipientID, analytics: store.productAnalytics)
            }.modifier(modalLifecycle)
        }
    }

    private var liveContent: some View {
        livePresentedContent
        .task(id: mapRequest) {
            guard let request = mapRequest else { return }
            let repository = auth.isSignedIn ? backend.feedRepository : nil
            await mapResults.load(request: request, repository: repository,
                fixture: repository == nil ? store.liveMapFixtureActivity() : [],
                featured: { await featuredMapPlaces(request: request) },
                permits: { event in store.currentUser.id == request.userID && store.canDisplayLiveMapActivity(event) })
        }
        .onChange(of: mapResults.revision) { _, _ in rebuildMapProjection() }
        .task(id: pinStateRequest) {
            await pinStateLoader.load(request: pinStateRequest,
                repository: auth.isSignedIn ? backend.feedRepository as? any LiveMapPinStateRepository : nil)
        }
        .onChange(of: pinStateLoader.revision) { _, _ in rebuildMapProjection() }
        .onReceive(store.$followedFeedPage) { page in refreshEnrichedMapActivity(page) }
        .onChange(of: store.presentationRevision) { _, _ in
            pinStateLoader.reset()
            mapResults.revalidate(userID: store.currentUser.id, permits: store.canDisplayLiveMapActivity)
            if isMapCovered || !isActive { mapRefreshDeferred = true }
            else { mapRefresh &+= 1 }
        }
        .onChange(of: isMapCovered) { _, covered in
            if covered && !showsIntroductionGuide { launchLocation.userDidChooseCamera() }
            if !covered { resumeDeferredMapRefresh() }
        }
        .onChange(of: store.followedFeedPage?.fetchedAt, initial: true) { _, _ in frameInitialMap() }
        .onChange(of: store.currentUser.id) { _, _ in
            pinStateLoader.reset()
            isFeedDestinationActive = false
            clearNativePlaceSelection()
            area = nil; selectedPlaceID = nil; drawing = false; didFrame = false
            fullProfilePin = nil; fullProfileCandidate = nil; committedMapBoundary = nil; committedMapViewport = nil
            mapActivity = []; mapPins = []
            launchLocation = LiveMapLaunchLocation()
            mapSearch = LiveMapSearchState(); setMapCamera(.region(launchLocation.region))
            filtersPresented = false; showsMessages = false; replyTarget = nil; selectedPlan = nil
            planSource = nil; queuedPlan = nil; queuedPlaceID = nil; queuedActivityID = nil; wantsPeopleSearch = false; showsEvents = false; showsContactInvites = false
            showsUpcomingInvitations = false; receivedPlan = nil; queuedReceivedPlan = nil; wantsNotificationInbox = false
            draftArea = nil; drawPoints = []; drawCoordinates = []
            selection = LiveBrowseSelection(); draftSelection = selection; detent = 1
            viewedPins = LiveViewedPinHistory.load(userID: store.currentUser.id)
            drawerMapOrigin = nil; cardMapOrigin = nil; departedAt = nil; feedIsScrolled = false
            previewSaveContext = nil; previewSharePlace = nil; feedScrollResetRequest = UUID()
            introductionAudience = nil; introductionAcknowledged = false; showsIntroductionGuide = false
            updateIntroduction()
            installCommittedQuery()
            frameInitialMap()
        }
        .onChange(of: presentationResetRequest?.id) { _, _ in
            clearNativePlaceSelection(); fullProfileCandidate = nil
            isFeedDestinationActive = false
            filtersPresented = false; showsMessages = false; replyTarget = nil
            selectedPlan = nil; planSource = nil; queuedPlan = nil; queuedPlaceID = nil; queuedActivityID = nil; wantsPeopleSearch = false
            showsEvents = false; showsContactInvites = false; drawing = false; showsIntroductionGuide = false
            previewSaveContext = nil; previewSharePlace = nil
            showsUpcomingInvitations = false; receivedPlan = nil; queuedReceivedPlan = nil; wantsNotificationInbox = false
        }
        .onChange(of: pins.map(\.id)) { _, ids in
            if let selectedPlaceID, !ids.contains(selectedPlaceID) { dismissPlacePreview() }
            frameInitialMap()
        }
        .alert("Zoom In To Choose An Area", isPresented: $areaNotice) {
            Button("OK", role: .cancel) {}
        } message: { Text("Choose A Region Smaller Than Half The World, Then Draw Or Use The Visible Area.") }
        .onAppear {
            locationPermission.refreshAuthorizationStatus()
            viewedPins = LiveViewedPinHistory.load(userID: store.currentUser.id)
            installCommittedQuery()
            updateIntroduction()
        }
        .onChange(of: introductionContext) { _, _ in updateIntroduction() }
        .onChange(of: isActive) { _, active in
            if active { pinStateLoader.revalidate() }
            if active { resumeDeferredMapRefresh() }
            if active { restoreFeedPresentation(); updateIntroduction() }
            else { rememberFeedPresentation(); clearNativePlaceSelection() }
        }
        .onChange(of: showsFeedDestination) { _, presented in
            if presented { rememberFeedPresentation() }
            else { restoreFeedPresentation() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { launchLocation.reset() }
            if phase == .active {
                pinStateLoader.revalidate()
                locationPermission.refreshAuthorizationStatus()
                store.refreshLiveFeedDisplayLease()
                mapResults.revalidate(userID: store.currentUser.id, permits: store.canDisplayLiveMapActivity)
                viewedPins = LiveViewedPinHistory.load(userID: store.currentUser.id)
            }
        }
    }

    private func refreshEnrichedMapActivity(_ page: FollowedFeedPage?) {
        // Merge only enriched copies of already enumerated event IDs.
        // Keep the projection typed outside the large SwiftUI result builder.
        guard let page else { return }
        let enriched: [String: FeedActivity] = Dictionary(
            page.activity.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var refreshed: [FeedActivity] = []
        for existing in mapActivity {
            let event: FeedActivity = enriched[existing.id] ?? existing
            guard let query = store.liveFeedQuery, query.includes(event) else { continue }
            guard store.canDisplayLiveMapActivity(event) else { continue }
            refreshed.append(event)
        }
        mapActivity = refreshed
        mapPins = LiveMapProjection.pins(activities: mapActivity, featured: mapResults.featuredPlaces,
            ownCheckInPlaces: ownCheckInPlaces,
            totemContext: store.liveTotemContext(query: store.liveFeedQuery ?? selection.query(),
                currentStateIsComplete: usesTotemReviewFixture, authoritativeState: pinStateLoader.snapshot,
                allowsCachedAssociations: usesTotemReviewFixture || !auth.isSignedIn),
            previousPins: previousPinIdentities)
    }

    private struct LocationActivation: Equatable {
        let isActive: Bool
        let accountID: String
        let authorizationStatus: CLAuthorizationStatus
    }

    private var locationActivation: LocationActivation {
        LocationActivation(isActive: isActive && scenePhase == .active && !isMapCovered && !hasPlacePreview && !drawing,
            accountID: store.currentUser.id, authorizationStatus: locationPermission.authorizationStatus)
    }

    private var isMapCovered: Bool {
        fullProfilePin != nil || fullProfileCandidate != nil || planSource != nil || selectedPlan != nil || filtersPresented
            || previewSaveContext != nil || previewSharePlace != nil || showsFeedDestination
            || showsMessages || replyTarget != nil || showsEvents || showsContactInvites || showsUpcomingInvitations
            || receivedPlan != nil || showsIntroductionGuide
    }
    private func resumeDeferredMapRefresh() {
        guard mapRefreshDeferred, isActive, !isMapCovered else { return }
        mapRefreshDeferred = false
        mapRefresh &+= 1
    }

    private var messageRepository: (any PrivateMessageRepository)? { demoMessageSession?.repository ?? backend.privateMessageRepository }
    private var modalLifecycle: LiveModalLifecycle {
        LiveModalLifecycle(onPresentation: onPresentation, onWillDismiss: onWillDismiss)
    }
    private func modalDidDismiss() {
        onDidDismiss(.liveModal)
        if let queuedPlan { self.queuedPlan = nil; selectedPlan = queuedPlan }
        if let queuedPlaceID {
            self.queuedPlaceID = nil; pushNotifications.route(to: .place(id: queuedPlaceID))
        }
        if let queuedActivityID {
            self.queuedActivityID = nil; activityNavigation.openComments(activityID: queuedActivityID)
        }
        if let queuedReceivedPlan { self.queuedReceivedPlan = nil; receivedPlan = queuedReceivedPlan }
        if wantsNotificationInbox {
            wantsNotificationInbox = false; changeDetent(2); surfaceRequest = .init(target: .notifications)
        }
        if wantsPeopleSearch {
            wantsPeopleSearch = false; changeDetent(2); surfaceRequest = .init(target: .search)
        }
    }

    private func map(drawerHeight: CGFloat) -> some View {
        GeometryReader { geometry in
            map(size: geometry.size, drawerHeight: drawerHeight)
        }
        .task(id: locationActivation) { await resolveLaunchLocation() }
    }

    private func resolveLaunchLocation() async {
        guard locationActivation.isActive else { return }
        launchLocation.updateAuthorization(locationPermission.authorizationStatus)
        guard let region = await launchLocation.resolve(
            hasExplicitGeographicScope: area != nil || selection.scope == .nearby
        ), !Task.isCancelled, locationActivation.isActive else { return }
        applyLaunchRegion(region)
    }

    private func map(size: CGSize, drawerHeight: CGFloat) -> some View {
        let proxy = mapProxy
        let layout = LiveMapSearchLayout(size: size,
            controlsHeight: !drawing && detent < 2 ? mapControlsHeight : 0, drawerHeight: drawerHeight)
        return LiveNativeMap(
            position: $camera, positionRevision: cameraRevision, proxy: proxy, pins: pins, selectedID: selectedPlaceID,
            viewedPins: viewedPins, brand: brand, coloredMap: store.isColoredMapEnabled,
            drawing: drawing,
            contentInsets: EdgeInsets(top: drawing ? 8 : layout.controlsHeight + 8, leading: 8,
                bottom: drawing ? drawingActionsHeight + 40
                    : hasPlacePreview ? min(previewHeight, size.height * 0.72) + 12 : drawerHeight + 12,
                trailing: 8),
            showsUserLocation: LiveMapLaunchLocation.showsUserLocation(locationPermission.authorizationStatus),
            boundary: draftArea ?? (area?.isMapViewport == false ? area?.boundary : nil),
            nearbyCenter: selection.scope == .nearby ? selection.center.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            } : nil,
            nearbyRadius: selection.scope == .nearby ? Double(selection.radius.rawValue) : nil,
            nativeSelectionRevision: nativeSelectionRevision,
            onSelectPin: selectPin,
            onNativeFeature: { feature in
                nativeFeature = feature
                selectNativePlace(feature)
            },
            onCameraEnd: { region, observedCamera, positionedByUser in
                viewport = region
                if positionedByUser { didFrame = true; launchLocation.userDidChooseCamera() }
                let needsProvenanceReset = mapSearch.observe(camera: LiveMapSearchCamera(
                    latitude: observedCamera.centerCoordinate.latitude,
                    longitude: observedCamera.centerCoordinate.longitude,
                    distance: observedCamera.distance, heading: observedCamera.heading, pitch: observedCamera.pitch),
                    layout: layout, positionedByUser: positionedByUser)
                if needsProvenanceReset { preserveMapCamera(observedCamera) }
            },
            onInteraction: {
                guard !drawing else { return }
                didFrame = true
                launchLocation.userDidChooseCamera()
                mapSearch.didInteractWithMap()
                collapseForMapInteraction()
            })
            .overlay(alignment: .top) {
                if !drawing && detent < 2 && !showsFeedDestination {
                    controls.padding(.top, 8).padding(.bottom, 8)
                        .background {
                            GeometryReader { controlsGeometry in
                                Color.clear.preference(key: LiveMapControlsHeightKey.self, value: controlsGeometry.size.height)
                            }
                        }
                }
            }
            .onPreferenceChange(LiveMapControlsHeightKey.self) { mapControlsHeight = $0; frameInitialMap() }
            .onChange(of: previewID) { _, _ in
                if hasPlacePreview { revealSelectedPin(proxy: proxy, size: size) }
            }
            .onChange(of: previewHeight) { _, _ in
                previewCameraAdjusted = false
                if hasPlacePreview { revealSelectedPin(proxy: proxy, size: size) }
            }
            .overlay(alignment: .bottom) {
                if mapSearch.shouldOfferSearch, !drawing, !showsFeedDestination, detent == 0, !hasPlacePreview,
                   !filtersPresented, layout.visibleRect != nil {
                    Button {
                        guard let viewport,
                              let boundary = LiveMapSearchGeometry.area(layout: layout,
                                  longitudeSpan: viewport.span.longitudeDelta,
                                  convert: { proxy.coordinate(for: $0) }) else {
                            areaNotice = true
                            return
                        }
                        area = .mapViewport(boundary)
                        mapSearch.didCommit()
                        focusRequest = nil
                        commitSelection(selection.searchingMapArea())
                    } label: {
                        Label("Search This Area", systemImage: "magnifyingglass")
                            .font(AstirTypography.body)
                            .foregroundStyle(brand.primaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .frame(minHeight: 44)
                            .astirGlassSurface(cornerRadius: 22, castsShadow: true, interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("live.searchArea")
                    .accessibilityHint("Updates Map Pins And Activity To The Visible Map Area. Replaces The Previous Area; Keeps Your Other Filters.")
                    .padding(.horizontal, 16)
                    .padding(.bottom, drawerHeight + 12)
                }
            }
            .overlay {
                if drawing {
                    GeometryReader { _ in
                        Color.clear.contentShape(Rectangle())
                            .overlay {
                                Path { path in
                                    guard let first = drawPoints.first else { return }
                                    path.move(to: first)
                                    path.addLines(drawPoints)
                                }.stroke(brand.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                            }
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    if draftArea != nil { draftArea = nil; drawPoints = []; drawCoordinates = [] }
                                    guard drawPoints.count < 512,
                                          drawPoints.last.map({ hypot($0.x - value.location.x, $0.y - value.location.y) >= 5 }) ?? true,
                                          let point = proxy.coordinate(for: value.location) else { return }
                                    drawPoints.append(value.location); drawCoordinates.append(point)
                                    drawingError = nil
                                }
                                .onEnded { _ in
                                    draftArea = LiveDrawnArea(coordinates: drawCoordinates)
                                    drawingError = draftArea == nil ? "Draw A Closed Area Within This Region To Continue." : nil
                                    drawPoints = []; drawCoordinates = []
                                })
                    }
                    .accessibilityLabel("Map Drawing Canvas")
                    .accessibilityHint("Draw One Area With Your Finger. You Can Also Use The Visible Map Area Below.")
                }
            }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 0) {
                            scopeControls
                            HStack(spacing: 0) {
                                appControls
                                Spacer(minLength: 0)
                                filterControl
                            }
                        }
                    } else {
                        HStack(spacing: 4) {
                            scopeControls
                            Spacer(minLength: 0)
                            appControls
                            filterControl
                        }
                    }
                }
                .padding(.horizontal, 8)
                .astirGlassSurface(cornerRadius: 26, castsShadow: true, interactive: true)
                control("Add A Place", symbol: "plus") { onAdd() }
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .astirGlassSurface(cornerRadius: 24, castsShadow: true, interactive: true, accentAction: true)
            }
            HStack(spacing: 8) {
                control(area?.drawActionTitle ?? "Draw Area", symbol: "pencil.and.outline") { startDrawing() }
                    .font(.system(size: 20, weight: .medium))
                    .astirGlassSurface(cornerRadius: 24, castsShadow: true, interactive: true)
                    .accessibilityIdentifier("live.draw")
                if area != nil {
                    Button("Clear") { area = nil; resetCommittedMapWindow(); mapSearch.didCommit(); commitSelection(selection) }
                        .font(AstirTypography.bodySmall).padding(.horizontal, 14).frame(minHeight: 44)
                        .astirGlassSurface(cornerRadius: 22, interactive: true)
                        .accessibilityIdentifier("live.clearArea")
                }
                Spacer()
                if nearbyLoading { ProgressView().padding(12).background(.regularMaterial, in: Circle()) }
            }
        }
        .foregroundStyle(brand.primaryText).padding(.horizontal, 16)
    }

    private var filterControl: some View {
        control("Filters", symbol: "slider.horizontal.3") { openFilters() }
            .accessibilityValue("\(activeFilterCount) Active Filters")
            .overlay(alignment: .topTrailing) {
                if activeFilterCount > 0 {
                    Circle().fill(brand.accent).frame(width: 7, height: 7).padding(6)
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
    }

    private var scopeControls: some View {
        HStack(spacing: 6) {
            Button("Featured") {
                var next = selection; next.scope = .featured
                if area?.isMapViewport == true { area = nil; resetCommittedMapWindow(); mapSearch.didCommit() }
                commitSelection(next)
            }
                .font(AstirTypography.bodySmall.weight(selection.scope == .featured ? .bold : .regular))
                .foregroundStyle(LiveFilterTint.featured(brand: brand))
                .frame(minHeight: 44)
                .accessibilityAddTraits(selection.scope == .featured ? .isSelected : [])
                .accessibilityIdentifier("live.scope.featured")
            Button("Nearby") { selectNearby() }
                .font(AstirTypography.bodySmall.weight(selection.scope == .nearby ? .bold : .regular))
                .foregroundStyle(selection.scope == .nearby ? brand.accentText : brand.primaryText)
                .frame(minHeight: 44).disabled(nearbyLoading)
                .accessibilityAddTraits(selection.scope == .nearby ? .isSelected : [])
                .accessibilityIdentifier("live.scope.nearby")
        }
    }

    private var appControls: some View {
        HStack(spacing: 0) {
            control("Search", symbol: "magnifyingglass") { rememberFeedPresentation(); surfaceRequest = .init(target: .search) }
            control("Notifications", symbol: "bell") { rememberFeedPresentation(); surfaceRequest = .init(target: .notifications) }
        }
    }

    private var drawerUpdateCount: some View {
        Text(LiveMapPaging.countText(activity.count, complete: mapResults.complete)).font(AstirTypography.bodySmall.weight(.semibold))
            .accessibilityLabel(LiveMapPaging.countText(activity.count, complete: mapResults.complete))
    }

    private var drawerFilterSummary: some View {
        Text(selection.time == .all ? "All Time" : "Past \(selection.time.rawValue) \(selection.time.rawValue == 1 ? "Day" : "Days")")
            .font(.caption2).foregroundStyle(brand.secondaryText)
            .accessibilityIdentifier("live.filter.summary")
    }

    private func drawer(height: CGFloat) -> some View {
        drawerContent(height: height).overlay(alignment: .top) { drawerHeaderActions }
    }

    private func drawerContent(height: CGFloat) -> some View {
        LiveFeedDrawer(height: height, minimum: max(70, drawerHeaderHeight),
                       middle: self.height(for: 1, available: mapSize.height), maximum: max(height, mapSize.height),
                       detent: detent, enabled: !showsFeedDestination, onDetent: { changeDetent($0) }) {
            if !showsFeedDestination {
                VStack(spacing: 8) {
                    Capsule().fill(brand.secondaryText.opacity(0.45)).frame(width: 36, height: 5)
                    drawerUpdateCount
                    drawerFilterSummary
                }
                .padding(.horizontal, 64)
                .padding(.top, 10).padding(.bottom, 12)
                .frame(minHeight: 64)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { headerGeometry in
                        Color.clear.preference(key: LiveDrawerHeaderHeightKey.self, value: headerGeometry.size.height)
                    }
                }
                .onPreferenceChange(LiveDrawerHeaderHeightKey.self) { height in
                    if height.isFinite, height > 0, drawerHeaderHeight != ceil(height) { drawerHeaderHeight = ceil(height) }
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Activity Drawer, \(["Collapsed", "Half Expanded", "Expanded"][detent])")
                .accessibilityValue("\(LiveMapPaging.countText(activity.count, complete: mapResults.complete)). \(filterSummary)")
                .accessibilityAdjustableAction { direction in
                    changeDetent(detent + (direction == .increment ? 1 : -1))
                }
                .accessibilityIdentifier("live.drawerHandle")
            }
        } content: {
            VStack(spacing: 0) {
                if !showsFeedDestination {
                    if mapResults.error {
                        Button("Refresh Map Results") { mapRefresh &+= 1 }
                            .font(AstirTypography.caption).foregroundStyle(brand.accentText)
                            .frame(minHeight: 44).accessibilityIdentifier("live.mapResults.retry")
                    }
                    if store.liveFeedSocialExpired {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Reconnect To Refresh Your People’s Activity").font(AstirTypography.bodySmall)
                            Button("Try Again") { commitSelection(selection) }.frame(minHeight: 44)
                                .accessibilityIdentifier("live.reconnect")
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                    }
                    if migrationRecord != nil, selectedPin == nil,
                       !introductionContext.hasPriorityPresentation, detent > 0 {
                        LiveIntroductionMigrationCard(onContinue: onContinueMigration,
                            onNotNow: onDeferMigration, onPresented: onMigrationPresented)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    } else if let introductionAudience, !introductionAcknowledged, selectedPin == nil,
                       !introductionContext.hasPriorityPresentation, detent > 0 {
                        LiveIntroductionCard(audience: introductionAudience, onShowMe: {
                            acknowledgeIntroduction(); showsIntroductionGuide = true
                        }, onNotNow: acknowledgeIntroduction, onPresented: {
                            LiveIntroductionStore().markPresented(for: store.currentUser.id)
                        })
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    if upcomingInvitationCount > 0 {
                        Button { showsUpcomingInvitations = true } label: {
                            Label("Upcoming Invitations (\(upcomingInvitationCount))", systemImage: "envelope")
                                .font(AstirTypography.bodySmall)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.padding(.horizontal, 20).accessibilityIdentifier("live.upcomingInvitations")
                    }
                }
                FeedScreen(
                    isFeedTabActive: isActive, presentationResetRequest: presentationResetRequest,
                    onPresentation: onPresentation, onWillDismiss: onWillDismiss, onDidDismiss: onDidDismiss,
                    isEmbedded: true,
                    showsInviteEntry: false,
                    isEmbeddedFeedVisible: isActive && detent > 0 && selectedPin == nil && !showsFeedDestination && !drawing,
                    filteredActivityIDs: Set(activity.map(\.id)),
                    activityFocusRequest: focusRequest, surfaceRequest: surfaceRequest,
                    onPrivateReply: openReply,
                    onEmbeddedDestinationActiveChange: { isFeedDestinationActive = $0 },
                    onRefreshRequested: {
                        selection = selection.committed(at: .now)
                        installCommittedQuery(refresh: false)
                    },
                    onEmbeddedScrollPositionChange: { feedIsScrolled = $0 },
                    embeddedScrollResetRequest: feedScrollResetRequest,
                    onAdd: onAdd
                )
            }
            .opacity(showsFeedDestination || detent > 0 ? 1 : 0)
            .allowsHitTesting(showsFeedDestination || detent > 0)
            .accessibilityHidden(!showsFeedDestination && detent == 0)
        }
        .frame(maxWidth: .infinity)
        .background(brand.background, in: UnevenRoundedRectangle(topLeadingRadius: showsFeedDestination ? 0 : 26,
            topTrailingRadius: showsFeedDestination ? 0 : 26))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: showsFeedDestination ? 0 : 26,
            topTrailingRadius: showsFeedDestination ? 0 : 26))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -3)
    }

    @ViewBuilder private var drawerHeaderActions: some View {
        if !showsFeedDestination, !hasPlacePreview, !drawing {
            LiveDrawerActions(eventsAvailable: eventsAvailable,
                onEvents: { showsEvents = true }, onInvite: { showsContactInvites = true })
                .padding(.horizontal, 16)
                .frame(height: max(64, drawerHeaderHeight))
        }
    }

    @ViewBuilder private var placePreviewContent: some View {
        if let pin = selectedPin {
            LivePlacePreviewCard(place: pin.place, activities: pin.activities, identity: pin.identity,
                onOpen: { openPlace(pin) }, onAdd: { openPlace(pin, add: true) },
                onShare: { sharePlace(pin) },
                onAddToList: { recentListAdd.add(.visiblePlace(pin.place), store: store, backend: backend, analyticsSurface: "map") },
                onClose: dismissPlacePreview)
        } else if let candidate = selectedCandidate {
            LivePlacePreviewCard(candidate: candidate,
                onOpen: { fullProfileCandidate = candidate },
                onAdd: { saveNativePlace(candidate) },
                onShare: { previewSharePlace = LivePlaceShareRoute(place: PlaceSheetPlace(candidate: candidate)) },
                onAddToList: { recentListAdd.add(.candidate(candidate), store: store, backend: backend, analyticsSurface: "map") },
                onClose: dismissPlacePreview)
        }
    }

    private func placePreview(availableHeight: CGFloat) -> some View {
        ScrollView {
            placePreviewContent
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: LivePlacePreviewHeightKey.self, value: geometry.size.height)
                    }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(availableHeight * 0.72, previewHeight))
        .onPreferenceChange(LivePlacePreviewHeightKey.self) { previewHeight = $0 }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .phaseAnimator([1.0, 1.3, 1.0], trigger: previewAnimationTrigger) { content, scale in
            content.scaleEffect(x: 1, y: reduceMotion ? 1 : scale, anchor: .bottom)
        } animation: { scale in
            reduceMotion ? nil : scale == 1.3 ? .easeOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.7)
        }
        .task(id: previewID) { previewAnimationTrigger &+= 1 }
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            if value.translation.height > 60 && abs(value.translation.height) > abs(value.translation.width) {
                dismissPlacePreview()
            }
        })
        .accessibilityIdentifier("live.placePreview")
    }

    private var drawingControls: some View {
        VStack {
            Text(draftArea == nil ? "Draw An Area" : "Use This Area?")
                .font(AstirTypography.body).padding(14).background(.regularMaterial, in: Capsule())
            Spacer()
            if let drawingError { Text(drawingError).font(.caption).padding().background(.regularMaterial, in: Capsule()) }
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) { drawingActions }.frame(maxWidth: .infinity)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { drawingActions }
                        VStack(spacing: 8) { drawingActions }
                    }
                }
            }
            .font(AstirTypography.body).padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: LiveDrawingActionsHeightKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(LiveDrawingActionsHeightKey.self) { drawingActionsHeight = $0 }
        }.padding(16).padding(.bottom, 16)
    }

    @ViewBuilder private var drawingActions: some View {
        Button { drawing = false; draftArea = nil } label: {
            Text("Cancel").fixedSize(horizontal: false, vertical: true)
        }.frame(minHeight: 44)
        Button {
            draftArea = viewport.flatMap(Self.areaForViewport)
            if draftArea == nil { areaNotice = true }
        } label: {
            Text("Use Visible Area").fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }.frame(minHeight: 44)
        Button {
            guard let draftArea else { return }
            area = .drawn(draftArea); self.draftArea = nil; drawing = false; selectedPlaceID = nil
            mapSearch.didCommit()
            commitSelection(selection)
        } label: {
            Text("Apply").fixedSize(horizontal: false, vertical: true)
        }.frame(minHeight: 44).disabled(draftArea == nil).buttonStyle(.borderedProminent)
            .accessibilityIdentifier("live.applyArea")
    }

    private var filters: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Reset Filters") { resetDraftFilters() }
                        .foregroundStyle(brand.accentText)
                        .accessibilityIdentifier("live.filter.reset")
                }
                Section {
                    LiveSemanticPicker(title: "People", selection: $draftAudience,
                        options: FeedAudience.allCases.map {
                            .init(value: $0, title: $0.title, color: LiveFilterTint.people($0, brand: brand))
                        })
                    .accessibilityIdentifier("live.filter.people")
                    .accessibilityValue(draftAudience.title)
                    Picker("Activity", selection: $draftSelection.activityType) {
                        ForEach(LiveActivityFilter.allCases) { Text(AppCopy.capitalizingWords($0.rawValue)).tag($0) }
                    }.accessibilityIdentifier("live.filter.activity")
                    Picker("When", selection: $draftSelection.time) {
                        ForEach(LiveTimeFilter.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("live.filter.time")
                }
                nearbyFilterSection
                categoryFilterSection
                personFilterSection
                Section {
                    if let area, !(draftSelection.scope == .nearby && area.isMapViewport) {
                        Toggle(area.isMapViewport ? "Keep Map Area" : "Keep Drawn Area", isOn: Binding(get: { !draftClearsArea }, set: { draftClearsArea = !$0 }))
                    }
                    Text("The Map And Recent Feed Use These Filters. Scroll Further For Older Matches, Then Clearly Labeled Activity Outside Your Filters.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Time Window Ends \(selection.committedAt.formatted(date: .abbreviated, time: .shortened)). Apply Or Refresh Updates The Window.")
                        .font(.footnote).foregroundStyle(.secondary)

                }
            }
            .accessibilityIdentifier("live.filters.form")
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { filtersPresented = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        guard draftSelection.isValid else { return }
                        store.selectFeedAudience(draftAudience)
                        if draftClearsArea { area = nil; resetCommittedMapWindow(); mapSearch.didCommit() }
                        commitSelection(draftSelection)
                        filtersPresented = false
                    }.disabled(!draftSelection.isValid).accessibilityIdentifier("live.applyFilters")
                }
            }
        }.presentationDetents([.large])
    }

    private var nearbyFilterSection: some View {
        Section("Area") {
            LiveSemanticPicker(title: "Scope", selection: $draftSelection.scope,
                options: LiveBrowseSelection.Scope.allCases.map {
                    .init(value: $0, title: $0.rawValue,
                        color: $0 == .featured ? LiveFilterTint.featured(brand: brand) : brand.primaryText)
                }).accessibilityIdentifier("live.filter.scope")
            if draftSelection.scope == .nearby {
                Picker("Area Center", selection: Binding(get: {
                    draftSelection.nearbyCenter == nil ? draftSelection.cityID : nil
                }, set: { cityID in
                    draftSelection.cityID = cityID
                    draftSelection.nearbyCenter = nil; draftSelection.nearbyCenterName = nil
                })) {
                    Text(draftSelection.nearbyCenterName ?? "Choose A City").tag(nil as String?)
                    ForEach(HomeMetro.all) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("live.filter.city")
                Picker("Radius", selection: $draftSelection.radius) {
                    ForEach(LiveBrowseSelection.Radius.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("live.filter.radius")
                Text("Nearby Uses A 10 km Radius Around Your Location When Available, Otherwise The Map Center. You Can Choose A City Or Another Radius Here. A Drawn Area Narrows It Further.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var categoryFilterSection: some View {
        Section("Categories") {
            let categories = WanderPlaceCategory.allowedCategories
            ForEach(categories, id: \.self) { category in
                Toggle(AppCopy.capitalizingWords(WanderPlaceCategory.broadCategory(for: category)),
                       isOn: Binding(get: { draftSelection.categoryIDs.contains(category) }, set: { selected in
                    if selected { draftSelection.categoryIDs.insert(category) }
                    else { draftSelection.categoryIDs.remove(category) }
                })).accessibilityIdentifier("live.filter.category.\(category)")
            }
            if !draftSelection.categoryIDs.isEmpty {
                Button("Clear Category Selection") { draftSelection.categoryIDs = [] }
            }
        }
    }

    private var personFilterSection: some View {
        Section("People") {
            let people = [store.currentUser] + store.following(of: store.currentUser.id)
            ForEach(people) { person in
                Toggle(person.displayName, isOn: Binding(get: { draftSelection.personIDs.contains(person.id) }, set: { selected in
                    if selected { draftSelection.personIDs.insert(person.id) }
                    else { draftSelection.personIDs.remove(person.id) }
                })).accessibilityIdentifier("live.filter.person.\(person.id)")
            }
            if !draftSelection.personIDs.isEmpty {
                Button("Clear Person Selection") { draftSelection.personIDs = [] }
            }
        }
    }

    private func openFilters(nearby: Bool = false) {
        draftSelection = selection
        if draftSelection.cityID == nil { draftSelection.cityID = HomeMetro.find(homeMetroID)?.id }
        if nearby {
            draftSelection.scope = .nearby
            if selection.scope != .nearby { draftSelection.radius = .tenKilometers }
        }
        draftAudience = store.feedAudience
        draftClearsArea = false
        filtersPresented = true
    }

    private func resetDraftFilters() {
        let cityID = draftSelection.cityID
        draftSelection = LiveBrowseSelection(now: selection.committedAt)
        draftSelection.cityID = cityID
        draftAudience = .everyone
        draftClearsArea = true
    }

    private func selectNearby() {
        var next = selection
        next.scope = .nearby; next.radius = .tenKilometers
        next.cityID = HomeMetro.find(homeMetroID)?.id ?? next.cityID
        // Use an already-authorized location only. Otherwise the visible map
        // center gives an immediate, deterministic 10 km scope with no sheet.
        if let center = viewport?.center {
            next.nearbyCenter = .init(latitude: center.latitude, longitude: center.longitude)
            next.nearbyCenterName = "Map Center"
        }
        if next.isValid { commitSelection(next) }
        guard CLLocationManager().authorizationStatus == .authorizedWhenInUse
                || CLLocationManager().authorizationStatus == .authorizedAlways else { return }
        nearbyLoading = true
        let accountID = store.currentUser.id
        let requestedSelection = selection
        Task { @MainActor in
            defer { nearbyLoading = false }
            guard let location = try? await CoreLocationProvider(purpose: .map).currentLocation(),
                  store.currentUser.id == accountID, selection == requestedSelection, selection.scope == .nearby else { return }
            var located = selection
            located.nearbyCenter = .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            located.nearbyCenterName = "Your Location"
            located.radius = .tenKilometers
            commitSelection(located)
        }
    }

    private func commitSelection(_ next: LiveBrowseSelection) {
        guard next.isValid else { return }
        launchLocation.userDidChooseCamera()
        let changedNearby = next.scope == .nearby && (selection.scope != .nearby
            || next.center != selection.center || next.radius != selection.radius)
        if next.scope == .nearby, area?.isMapViewport == true {
            area = nil
            mapSearch.didCommit()
        }
        if next.scope == .featured && selection.scope == .nearby { resetCommittedMapWindow() }
        selection = next.committed(at: .now)
        clearNativePlaceSelection()
        selectedPlaceID = nil
        cardMapOrigin = nil
        installCommittedQuery()
        if changedNearby, let center = selection.center {
            mapSearch.willMoveProgrammatically()
            presentMapRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: Double(selection.radius.rawValue) * 2.8,
                longitudinalMeters: Double(selection.radius.rawValue) * 2.8
            ))
            didFrame = true
        }
    }

    private var filterSummary: String {
        ([selection.summary] + (store.feedAudience == .everyone ? [] : [store.feedAudience.title])
            + (area.map { [$0.summary] } ?? [])).joined(separator: " · ")
    }

    private func installCommittedQuery(refresh: Bool = true) {
        guard selection.isValid else { return }
        let boundary = resolvedMapBoundary()
        store.selectLiveFeedQuery(selection.query(area: boundary))
        store.refreshLiveFeedDisplayLease()
        if refresh {
            let userID = store.currentUser.id, query = store.liveFeedQuery
            Task {
                guard store.currentUser.id == userID, store.liveFeedQuery == query else { return }
                await store.refreshFeedSurface(backend: auth.isSignedIn ? backend : nil, force: false)
            }
        }
    }

    private func resetCommittedMapWindow() {
        committedMapBoundary = nil
        committedMapViewport = nil
    }

    private func resolvedMapBoundary() -> LiveDrawnArea? {
        if let area {
            committedMapBoundary = area.boundary
            committedMapViewport = Self.viewport(for: area.boundary)
            return area.boundary
        }
        if selection.scope == .nearby, let center = selection.center {
            committedMapBoundary = nil
            let region = MKCoordinateRegion(center: .init(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: Double(selection.radius.rawValue) * 2.4,
                longitudinalMeters: Double(selection.radius.rawValue) * 2.4)
            committedMapViewport = MapViewportRefreshPolicy.viewport(for: region)
            return nil
        }
        if committedMapBoundary == nil {
            let region = drawerMapOrigin ?? viewport.flatMap { $0.span.longitudeDelta < 180 ? $0 : nil }
                ?? launchLocation.region
            committedMapBoundary = Self.areaForViewport(region)
            committedMapViewport = MapViewportRefreshPolicy.viewport(for: region)
        }
        committedMapViewport = committedMapBoundary.flatMap(Self.viewport)
        return committedMapBoundary
    }

    private static func viewport(for area: LiveDrawnArea) -> MapViewport? {
        guard let minLat = area.vertices.map(\.latitude).min(), let maxLat = area.vertices.map(\.latitude).max(),
              let minLng = area.vertices.map(\.longitude).min(), let maxLng = area.vertices.map(\.longitude).max(),
              maxLng - minLng < 180 else { return nil }
        return MapViewport(minLatitude: minLat, minLongitude: minLng, maxLatitude: maxLat, maxLongitude: maxLng)
    }

    private func featuredMapPlaces(request: LiveMapRequest) async -> [VisiblePlace] {
        guard request.featured, request.audience == .everyone, request.query.personIDs.isEmpty,
              request.query.activityType != .wannas, request.query.activityType != .lists,
              let viewport = request.viewport else { return [] }
        let candidates = await store.fetchRemoteFeaturedViewportPlaces(in: viewport, backend: auth.isSignedIn ? backend : nil)
            ?? (usesTotemReviewFixture || !auth.isSignedIn ? store.visiblePlaces() : [])
        guard !Task.isCancelled, request.userID == store.currentUser.id else { return [] }
        let region = MKCoordinateRegion(center: .init(latitude: (viewport.minLatitude + viewport.maxLatitude)/2,
            longitude: (viewport.minLongitude + viewport.maxLongitude)/2),
            span: .init(latitudeDelta: viewport.maxLatitude - viewport.minLatitude,
                        longitudeDelta: viewport.maxLongitude - viewport.minLongitude))
        let refined = candidates.filter { request.query.includesFeatured($0) }
        var refinements = MapMoreFilterSelection(); refinements.categories = Set(request.query.categoryIDs)
        return MapFeaturedSelection.places(from: refined, currentUserID: request.userID,
            followedOwnerIDs: Set(store.following(of: request.userID).map(\.id)),
            in: region, refinements: refinements,
            tasteSaves: store.currentUserVisiblePlaces.map { PlaceSaveSummary(visiblePlace: $0,
                attributes: store.attributes(for: $0.userPlace.id), viewerFollowsOwner: false) },
            limit: Int.max)
    }

    /// Build history evidence once per projection, never during a drag sample or
    /// by scanning every visit again for every rendered pin.
    private var ownCheckInPlaces: [VisiblePlace] {
        let visitParents = Set(store.placeVisits.filter { $0.deletedAt == nil }.map(\.userPlaceID))
        return store.currentUserVisiblePlaces.filter {
            $0.userPlace.status == .been || !visitParents.isDisjoint(with:
                Set([$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].compactMap { $0 }))
        }
    }

    private var previousPinIdentities: [LivePlacePin] {
        guard let selected = selectedPin else { return mapPins }
        return [selected] + mapPins.filter { $0.id != selected.id }
    }

    private func rebuildMapProjection() {
        mapActivity = mapResults.activities.filter {
            store.liveFeedQuery?.includes($0) == true && store.canDisplayLiveMapActivity($0)
        }
        mapPins = LiveMapProjection.pins(activities: mapActivity, featured: mapResults.featuredPlaces,
                ownCheckInPlaces: ownCheckInPlaces,
                totemContext: store.liveTotemContext(query: store.liveFeedQuery ?? selection.query(),
                    currentStateIsComplete: usesTotemReviewFixture, authoritativeState: pinStateLoader.snapshot,
                    allowsCachedAssociations: usesTotemReviewFixture || !auth.isSignedIn),
                previousPins: previousPinIdentities)
    }

    private var activeFilterCount: Int {
        selection.activeFilterCount
            + (store.feedAudience == .everyone ? 0 : 1) + (area == nil ? 0 : 1)
    }

    private var invitationUserID: String? {
        guard auth.isSignedIn, auth.state.session?.userID == store.currentUser.id else { return nil }
        return store.currentUser.id
    }
    private var upcomingInvitationCount: Int {
        LiveUpcomingInvitationsProjection(invitations: planInbox.invitations,
            inboxUserID: planInbox.userID, userID: invitationUserID, failed: planInbox.failed, now: .now).rows.count
    }

    private func control(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 44, minHeight: 44) }
            .accessibilityLabel(title)
    }

    private func updateIntroduction() {
        guard introductionAudience == nil, !introductionAcknowledged else { return }
        introductionAudience = LiveIntroductionPolicy.audience(
            for: introductionContext,
            hasPresented: LiveIntroductionStore().hasPresented(for: store.currentUser.id)
        )
    }
    private func acknowledgeIntroduction() {
        LiveIntroductionStore().acknowledge(for: store.currentUser.id)
        introductionAcknowledged = true
    }
    private func coordinate(_ place: VisiblePlace) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.place.latitude, longitude: place.place.longitude)
    }
    private func height(for detent: Int, available: CGFloat) -> CGFloat {
        // The same height sizes the drawer and Map inset. Measure the header
        // without vertical compression so compact/large-text summaries stay visible.
        let minimum = max(70, drawerHeaderHeight)
        switch detent {
        case 0: return minimum
        case 2: return max(minimum, available)
        default: return max(minimum, available * 0.48)
        }
    }
    private func changeDetent(_ value: Int, restoredOrigin: MKCoordinateRegion? = nil) {
        let next = min(2, max(0, value))
        guard next != detent else { return }
        mapSearch.rebaseForPresentationChange()
        var nextRegion: MKCoordinateRegion?
        if next == 0, let origin = drawerMapOrigin {
            nextRegion = origin
            drawerMapOrigin = nil
        } else if next == 1, detent == 0, let viewport = restoredOrigin ?? viewport {
            drawerMapOrigin = viewport
            let old = LiveMapSearchLayout(size: mapSize, controlsHeight: mapControlsHeight,
                drawerHeight: height(for: 0, available: mapSize.height))
            let new = LiveMapSearchLayout(size: mapSize, controlsHeight: mapControlsHeight,
                drawerHeight: height(for: 1, available: mapSize.height))
            if let oldRect = old.visibleRect, let newRect = new.visibleRect {
                nextRegion = LiveMapViewportPolicy.fittedRegion(viewport, size: mapSize, from: oldRect, to: newRect)
            }
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            if let nextRegion { setMapCamera(.region(nextRegion)) }
            detent = next
        }
    }

    private func rememberFeedPresentation() {
        guard departedAt == nil else { return }
        departedAt = .now
        departedDetent = detent
        departedFeedWasScrolled = feedIsScrolled
    }

    private func restoreFeedPresentation() {
        let retains = LiveReviewContinuity.keepsFeedPosition(scrolled: departedFeedWasScrolled, departedAt: departedAt)
        if !retains { feedScrollResetRequest = UUID(); feedIsScrolled = false }
        let returningFromCard = hasPlacePreview || cardMapOrigin != nil
        let restoredOrigin = returningFromCard ? (cardMapOrigin ?? drawerMapOrigin) : nil
        if returningFromCard { dismissPlacePreview() }
        // MapKit publishes its new viewport asynchronously. Fit from the restored
        // origin now, rather than the previous card-reveal camera callback.
        changeDetent(retains ? max(1, departedDetent) : 1, restoredOrigin: restoredOrigin)
        departedAt = nil; departedFeedWasScrolled = false
    }

    private func selectPin(_ pin: LivePlacePin) {
        launchLocation.userDidChooseCamera()
        clearNativePlaceSelection()
        if cardMapOrigin == nil { cardMapOrigin = drawerMapOrigin ?? viewport }
        previewCameraAdjusted = false
        for id in pin.identity.placeIDs.union([pin.id]) { viewedPins[id] = .now }
        LiveViewedPinHistory.save(viewedPins, userID: store.currentUser.id)
        mapSearch.rebaseForPresentationChange()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            selectedPlaceID = pin.id
            detent = 0
        }
    }

    private func revealSelectedPin(proxy: LiveNativeMapProxy, size: CGSize) {
        guard !previewCameraAdjusted, let coordinate = previewCoordinate,
              let point = proxy.point(for: coordinate),
              let current = mapProxy.camera ?? mapSearch.latestCamera.map({
                  MapCamera(centerCoordinate: .init(latitude: $0.latitude, longitude: $0.longitude),
                            distance: $0.distance, heading: $0.heading, pitch: $0.pitch)
              }),
              let exposed = LiveMapSearchLayout(size: size, controlsHeight: mapControlsHeight,
                                                drawerHeight: min(previewHeight, size.height * 0.72) + 12).visibleRect else { return }
        let offset = LiveMapViewportPolicy.revealOffset(pin: point, exposedRect: exposed)
        guard offset != .zero,
              let center = proxy.cameraCenter(after: offset, from: current) else { return }
        previewCameraAdjusted = true
        mapSearch.rebaseForPresentationChange()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            setMapCamera(.camera(MapCamera(centerCoordinate: center, distance: current.distance,
                                      heading: current.heading, pitch: current.pitch)))
        }
    }

    private func dismissPlacePreview() {
        let closedCoordinate = previewCoordinate
        clearNativePlaceSelection()
        mapSearch.rebaseForPresentationChange()
        let restoredOrigin = (cardMapOrigin ?? drawerMapOrigin).map { origin in
            let layout = LiveMapSearchLayout(size: mapSize, controlsHeight: mapControlsHeight,
                drawerHeight: height(for: 0, available: mapSize.height))
            guard let exposed = layout.visibleRect else { return origin }
            return LiveMapViewportPolicy.restoredRegion(origin, keeping: closedCoordinate,
                size: mapSize, exposedRect: exposed)
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            selectedPlaceID = nil; detent = 0
            if let restoredOrigin { setMapCamera(.region(restoredOrigin)) }
        }
        cardMapOrigin = nil; drawerMapOrigin = nil; previewCameraAdjusted = false
    }

    private func collapseForMapInteraction() {
        guard hasPlacePreview || nativeFeature != nil || detent != 0 else { return }
        clearNativePlaceSelection()
        // The finger now owns the camera. Never undo a pan by restoring an old pose.
        cardMapOrigin = nil; drawerMapOrigin = nil; previewCameraAdjusted = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            selectedPlaceID = nil; detent = 0
        }
    }

    private func openPlace(_ pin: LivePlacePin, add: Bool = false) {
        if add {
            previewSaveContext = LivePlaceSaveContinuation.context(
                candidate: PlaceSheetPlace(visiblePlace: pin.place).saveCandidate,
                visiblePlace: pin.place, identity: pin.identity, store: store)
            store.saveFlowDidPresent(.saveSheet)
        } else {
            fullProfilePin = pin
        }
    }

    private func sharePlace(_ pin: LivePlacePin) {
        previewSharePlace = LivePlaceShareRoute(place: PlaceSheetPlace(visiblePlace: pin.place))
    }

    private func clearNativePlaceSelection() {
        nativeFeatureTask?.cancel(); nativeFeatureTask = nil
        nativeFeatureRequest = UUID()
        nativeSelectionRevision = UUID()
        nativeFeature = nil; selectedCandidate = nil; nativePreviewID = nil
    }

    private func selectNativePlace(_ feature: MKMapFeatureAnnotation) {
        guard !drawing, let candidate = LiveMapPlaceDiscovery.candidate(from: feature) else { return }
        launchLocation.userDidChooseCamera()
        nativeFeatureTask?.cancel()
        let request = UUID(); nativeFeatureRequest = request
        let accountID = store.currentUser.id
        if cardMapOrigin == nil { cardMapOrigin = drawerMapOrigin ?? viewport }
        previewCameraAdjusted = false
        mapSearch.rebaseForPresentationChange()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
            selectedPlaceID = nil; nativePreviewID = candidate.id; selectedCandidate = candidate; detent = 0
        }
        nativeFeatureTask = Task { @MainActor in
            let resolved = await LiveMapPlaceDiscovery.resolve(feature)
            guard !Task.isCancelled, request == nativeFeatureRequest,
                  accountID == store.currentUser.id, isActive, selectedCandidate != nil else { return }
            if let resolved { selectedCandidate = resolved }
            nativeFeatureTask = nil
        }
    }

    private func saveNativePlace(_ candidate: PlaceCandidate) {
        previewSaveContext = LivePlaceSaveContinuation.context(candidate: candidate, store: store)
        store.saveFlowDidPresent(.saveSheet)
    }

    private func rebaseMapCameraForPresentationChange() {
        let currentCamera = mapProxy.camera ?? mapSearch.latestCamera.map {
            MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                      distance: $0.distance, heading: $0.heading, pitch: $0.pitch)
        }
        mapSearch.rebaseForPresentationChange()
        if let currentCamera { preserveMapCamera(currentCamera) }
    }
    /// A repeated request remains a command even after native user movement.
    private func setMapCamera(_ position: MapCameraPosition) {
        camera = position
        cameraRevision &+= 1
    }

    private func preserveMapCamera(_ currentCamera: MapCamera) {
        // Reassert the same pose, not a fitted region. This clears the historic
        // user-positioned bit while leaving the map exactly where it is.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { setMapCamera(.camera(currentCamera)) }
    }
    private func startDrawing() {
        guard let viewport, viewport.span.longitudeDelta < 180 else { areaNotice = true; return }
        launchLocation.userDidChooseCamera()
        clearNativePlaceSelection()
        drawing = true; draftArea = nil; drawPoints = []; drawCoordinates = []; drawingError = nil
    }
    private static func areaForViewport(_ region: MKCoordinateRegion) -> LiveDrawnArea? {
        guard region.span.longitudeDelta < 180 else { return nil }
        let lat = region.center.latitude, lon = region.center.longitude
        let dy = region.span.latitudeDelta / 2, dx = region.span.longitudeDelta / 2
        func point(_ y: Double, _ x: Double) -> CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: min(89.9, max(-89.9, y)), longitude: (x + 540).truncatingRemainder(dividingBy: 360) - 180)
        }
        return LiveDrawnArea(coordinates: [point(lat-dy, lon-dx), point(lat-dy, lon+dx), point(lat+dy, lon+dx), point(lat+dy, lon-dx)])
    }
    private func frameInitialMap() {
        guard mapSize.width > 0, mapControlsHeight > 0,
              !didFrame, !hasPlacePreview else { return }
        applyLaunchRegion(launchLocation.region)
    }

    private func applyLaunchRegion(_ region: MKCoordinateRegion) {
        // A foreground refresh must not separate a chosen area's camera from its query.
        guard area == nil, selection.scope != .nearby else { return }
        mapSearch.willMoveProgrammatically()
        presentMapRegion(region)
        didFrame = mapSize.width > 0 && mapControlsHeight > 0
        committedMapBoundary = Self.areaForViewport(region)
        committedMapViewport = MapViewportRefreshPolicy.viewport(for: region)
        installCommittedQuery()
    }

    private func presentMapRegion(_ region: MKCoordinateRegion) {
        let old = LiveMapSearchLayout(size: mapSize, controlsHeight: mapControlsHeight,
            drawerHeight: height(for: 0, available: mapSize.height))
        let new = LiveMapSearchLayout(size: mapSize, controlsHeight: mapControlsHeight,
            drawerHeight: height(for: 1, available: mapSize.height))
        if detent > 0, let oldRect = old.visibleRect, let newRect = new.visibleRect,
           let fitted = LiveMapViewportPolicy.fittedRegion(region, size: mapSize, from: oldRect, to: newRect) {
            drawerMapOrigin = region
            setMapCamera(.region(fitted))
        } else { drawerMapOrigin = nil; setMapCamera(.region(region)) }
    }

    private func planPlace(for event: FeedActivity) -> CommonGroundMockPlace? {
        guard let place = event.place, event.actor.id != store.currentUser.id else { return nil }
        return CommonGroundLiveData.places(store: store, profileID: event.actor.id).first {
            $0.sourcePlaceID == place.id || $0.photoReference?.placeID == place.place.id
        }
    }

    private func openReply(_ event: FeedActivity) {
        replyTarget = .reply(recipientID: event.actor.id,
                             context: PrivateMessageContext(kind: .activity, id: event.id,
                                                            title: event.place?.place.canonicalName ?? "Activity"))
    }

    private func openMessageProfile(_ profileID: String) {
        pushNotifications.route(to: .profile(id: profileID))
    }

    private func openMessageContext(_ context: PrivateMessageContext) {
        showsMessages = false; replyTarget = nil
        changeDetent(2)
        switch context.kind {
        case .activity: queuedActivityID = context.id
        case .place: pushNotifications.route(to: .place(id: context.id))
        }
    }
}

private struct LivePlacePreviewHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LiveDrawerHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LiveMapControlsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Shared copy for Live's map and selection chooser; Feed cards keep their own presentation.
enum LiveActivityPresentation {
    static func shownUpdateCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "Place Update" : "Place Updates")"
    }

    static func loadedUpdateCount(_ count: Int) -> String {
        "\(count) Loaded \(count == 1 ? "Update" : "Updates")"
    }

    static func title(for activity: FeedActivity) -> String {
        switch activity.resolvedTicketKind {
        case .wanna: "Wanna"
        case .checkIn: "Check-In"
        case .list: "List Update"
        case .saved: "Saved Place"
        }
    }
}

private struct LiveModalLifecycle: ViewModifier {
    let onPresentation: (WanderDeepLinkPresentationToken) -> Void
    let onWillDismiss: (WanderDeepLinkPresentationToken) -> Void
    func body(content: Content) -> some View {
        WanderRootPresentationLifecycle(surface: .liveModal,
                                        onPresent: onPresentation, onDismiss: onWillDismiss) { content }
    }
}

private struct LivePlaceShareRoute: Identifiable {
    let id = UUID()
    let place: PlaceSheetPlace
    var shareURL: URL? {
        if UUID(uuidString: place.id) != nil { return WanderDeepLinkRoute.sharedPlace(placeID: place.id).url }
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return PlaceExternalLinks.directionsAction(placeName: place.name, latitude: latitude, longitude: longitude)?.url
    }
}

/// Isolate the invitation presentation from Live's large view expression.
private struct LiveContactInvitePresentation: ViewModifier {
    @EnvironmentObject private var store: WanderStore
    @Binding var presented: Bool
    let onDismiss: () -> Void
    let lifecycle: LiveModalLifecycle

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presented, onDismiss: onDismiss) {
            ContactInviteSheet(surface: .feedPeople, contactProvider: store.contactProvider,
                               senderProfileID: store.currentUser.id, analytics: store.productAnalytics)
                .modifier(lifecycle)
        }
    }
}

private struct LiveDrawingActionsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
