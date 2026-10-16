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
    @State private var camera: MapCameraPosition = .automatic
    @State private var viewport: MKCoordinateRegion?
    @State private var didFrame = false
    @State private var detent = 1
    @State private var selection = LiveBrowseSelection()
    @State private var area: LiveDrawnArea?
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
    @State private var showsUpcomingInvitations = false
    @State private var receivedPlan: ReceivedPlacePlanInvitation?
    @State private var queuedReceivedPlan: ReceivedPlacePlanInvitation?
    @State private var wantsNotificationInbox = false
    @State private var showsMessages = false
    @State private var areaNotice = false
    @State private var demoMessageRepository: (any PrivateMessageRepository)?
    @State private var replyTarget: PrivateMessageThreadTarget?

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

    private var authorizedActivity: [FeedActivity] {
        store.visibleFeedActivityGroups.flatMap(\.activities).filter {
            store.feedAudience.includes(actorID: $0.actor.id, currentUserID: store.currentUser.id,
                                        relationship: $0.actor.relationship)
        }
    }

    private var activity: [FeedActivity] {
        authorizedActivity.filter {
            selection.includes($0)
                && (area == nil || $0.place.map { area!.contains(coordinate($0)) } == true)
        }
    }

    private var pins: [LivePlacePin] {
        let groups = Dictionary(grouping: activity.filter { $0.place != nil }) { $0.place!.place.id }
        return groups.compactMap { id, activities in
            guard let first = activities.first, let place = first.place,
                  CLLocationCoordinate2DIsValid(coordinate(place)) else { return nil }
            return LivePlacePin(id: id, place: place, activities: FeedPresentation.newestFirst(activities))
        }.sorted { $0.id < $1.id }
    }

    private var selectedPin: LivePlacePin? { pins.first { $0.id == selectedPlaceID } }

    var body: some View {
        GeometryReader { geometry in
            let drawerHeight = drawing ? 0 : height(for: detent, available: geometry.size.height)
            ZStack(alignment: .bottom) {
                map(drawerHeight: drawerHeight)
                if !drawing {
                    drawer(height: drawerHeight)
                        .background(alignment: .bottom) {
                            // Paint only below the drawer, behind the native tab
                            // bar; preserve the map's existing attribution inset.
                            brand.background.frame(height: geometry.safeAreaInsets.bottom + 1)
                                .offset(y: geometry.safeAreaInsets.bottom)
                                .allowsHitTesting(false)
                        }
                } else {
                    drawingControls
                }
            }
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
                        CommonGroundLiveData.places(store: store, profileID: candidate.partner.id).contains(candidate)
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
                .navigationTitle("Upcoming invitations").navigationBarTitleDisplayMode(.inline)
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
        .onChange(of: store.followedFeedPage?.fetchedAt, initial: true) { _, _ in frameInitialMap() }
        .onChange(of: store.currentUser.id) { _, _ in
            area = nil; selectedPlaceID = nil; drawing = false; didFrame = false
            filtersPresented = false; showsMessages = false; replyTarget = nil; selectedPlan = nil
            planSource = nil; queuedPlan = nil; queuedPlaceID = nil; queuedActivityID = nil; wantsPeopleSearch = false; showsEvents = false
            showsUpcomingInvitations = false; receivedPlan = nil; queuedReceivedPlan = nil; wantsNotificationInbox = false
            demoMessageRepository = nil; draftArea = nil; drawPoints = []; drawCoordinates = []
            selection = LiveBrowseSelection(); draftSelection = selection; detent = 1
            introductionAudience = nil; introductionAcknowledged = false; showsIntroductionGuide = false
            updateIntroduction()
            installCommittedQuery()
            frameInitialMap()
        }
        .onChange(of: presentationResetRequest?.id) { _, _ in
            filtersPresented = false; showsMessages = false; replyTarget = nil
            selectedPlan = nil; planSource = nil; queuedPlan = nil; queuedPlaceID = nil; queuedActivityID = nil; wantsPeopleSearch = false
            showsEvents = false; drawing = false; showsIntroductionGuide = false
            showsUpcomingInvitations = false; receivedPlan = nil; queuedReceivedPlan = nil; wantsNotificationInbox = false
        }
        .onChange(of: pins.map(\.id)) { _, ids in
            if let selectedPlaceID, !ids.contains(selectedPlaceID) { self.selectedPlaceID = nil }
        }
        .onChange(of: activityNavigation.commentsRoute?.id) { _, requestID in
            if requestID != nil { changeDetent(2) }
        }
        .alert("Zoom in to choose an area", isPresented: $areaNotice) {
            Button("OK", role: .cancel) {}
        } message: { Text("Choose a region smaller than half the world, then draw or use the visible area.") }
        .onAppear {
            installCommittedQuery()
            updateIntroduction()
            #if DEBUG && targetEnvironment(simulator)
            if demoMessageRepository == nil {
                demoMessageRepository = PrivateMessageUITestFixtures.make(
                    userID: store.currentUser.id,
                    authenticatedUITest: ProcessInfo.processInfo.arguments.contains("-WanderAuthenticatedUITest"),
                    unifiedLiveEnabled: ProcessInfo.processInfo.arguments.contains("-WanderUnifiedLiveUITest"),
                    participants: store.profiles.map { profile in
                        PrivateMessageParticipant(id: profile.id, displayName: profile.displayName,
                                                  handle: profile.handle, avatarURL: profile.avatarURL.flatMap { URL(string: $0) })
                    }
                )
            }
            #endif
        }
        .onChange(of: introductionContext) { _, _ in updateIntroduction() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.refreshLiveFeedDisplayLease() }
        }
    }

    private var messageRepository: (any PrivateMessageRepository)? { demoMessageRepository ?? backend.privateMessageRepository }
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
        MapReader { proxy in
            Map(position: $camera, interactionModes: drawing ? [] : .all) {
                ForEach(pins) { pin in
                    Annotation(pin.place.place.canonicalName, coordinate: coordinate(pin.place)) {
                        Button {
                            selectedPlaceID = pin.id
                            changeDetent(1)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: pin.isWanna ? "bookmark" : "checkmark")
                                if pin.activities.count > 1 { Text("\(pin.activities.count)").font(.caption.bold()) }
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(pin.isWanna ? brand.primaryText : Color.white)
                            .padding(11)
                            .background(pin.isWanna ? brand.background : brand.accent, in: RoundedRectangle(cornerRadius: pin.isWanna ? 12 : 22))
                            .overlay(RoundedRectangle(cornerRadius: pin.isWanna ? 12 : 22)
                                .stroke(pin.id == selectedPlaceID ? brand.primaryText : brand.secondaryText.opacity(0.5), lineWidth: pin.id == selectedPlaceID ? 3 : 1.5))
                            .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(pin.accessibilityLabel)
                        .accessibilityIdentifier("live.pin.\(pin.id)")
                    }
                    .annotationTitles(.hidden)
                }
                if let drawn = draftArea ?? area {
                    MapPolygon(coordinates: drawn.vertices.map(\.coordinate))
                        .foregroundStyle(brand.accent.opacity(0.12))
                        .stroke(brand.accent, lineWidth: 3)
                }
                if selection.scope == .nearby, let center = selection.center {
                    MapCircle(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                              radius: Double(selection.radius.rawValue))
                        .foregroundStyle(brand.accent.opacity(0.05))
                        .stroke(brand.accent.opacity(0.7), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: drawerHeight) }
            .safeAreaInset(edge: .top, spacing: 0) {
                // MapKit frames content below the actual controls. At full
                // drawer height, avoid competing top/bottom viewport insets.
                if !drawing && detent < 2 {
                    controls.padding(.top, 8).padding(.bottom, 8)
                }
            }
            .onMapCameraChange(frequency: .onEnd) {
                viewport = $0.region
                if camera.positionedByUser { didFrame = true }
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
                                          let point = proxy.convert(value.location, from: .local) else { return }
                                    drawPoints.append(value.location); drawCoordinates.append(point)
                                    drawingError = nil
                                }
                                .onEnded { _ in
                                    draftArea = LiveDrawnArea(coordinates: drawCoordinates)
                                    drawingError = draftArea == nil ? "Draw a closed area within this region to continue." : nil
                                    drawPoints = []; drawCoordinates = []
                                })
                    }
                    .accessibilityLabel("Map drawing canvas")
                    .accessibilityHint("Draw one area with your finger. You can also use the visible map area below.")
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) { scopeControls; appControls }
                } else {
                    HStack(spacing: 8) { scopeControls; Spacer(minLength: 0); appControls }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            HStack {
                Button { startDrawing() } label: { Label(area == nil ? "Draw area" : "Redraw", systemImage: "pencil.and.outline").frame(minHeight: 44) }
                    .accessibilityIdentifier("live.draw")
                if area != nil {
                    Button("Clear") { area = nil; commitSelection(selection) }.frame(minHeight: 44).accessibilityIdentifier("live.clearArea")
                }
                Spacer()
                control("Filters", symbol: "slider.horizontal.3") {
                    openFilters()
                }
                .accessibilityValue("\(activeFilterCount) active filters")
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)").font(.caption2.bold()).foregroundStyle(Color.white)
                            .padding(4).background(brand.accent, in: Circle()).allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                control("Add a place", symbol: "plus") { onAdd() }
            }
            .font(AstirTypography.body).padding(.horizontal, 14).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
        }
        .foregroundStyle(brand.primaryText).padding(.horizontal, 16)
    }

    private var scopeControls: some View {
        HStack(spacing: 8) {
            Button("Following") {
                var next = selection; next.scope = .following
                commitSelection(next)
            }
                .font(AstirTypography.bodySmall.weight(selection.scope == .following ? .bold : .regular)).frame(minHeight: 44)
                .accessibilityIdentifier("live.scope.following")
            Button("Nearby") { openFilters(nearby: true) }
                .font(AstirTypography.bodySmall.weight(selection.scope == .nearby ? .bold : .regular)).frame(minHeight: 44)
                .accessibilityIdentifier("live.scope.nearby")
        }
    }

    private var appControls: some View {
        HStack(spacing: 8) {
            control("Search", symbol: "magnifyingglass") {
                // REC636-NATIVE-DIAGNOSTIC-BEGIN
                #if DEBUG && targetEnvironment(simulator)
                NativeInputRecipientDiagnostic.record(.searchActionEntered)
                #endif
                // REC636-NATIVE-DIAGNOSTIC-END
                changeDetent(2); surfaceRequest = .init(target: .search)
                // REC636-NATIVE-DIAGNOSTIC-BEGIN
                #if DEBUG && targetEnvironment(simulator)
                NativeInputRecipientDiagnostic.record(.searchSurfaceRequested)
                #endif
                // REC636-NATIVE-DIAGNOSTIC-END
            }
            control("Notifications", symbol: "bell") { changeDetent(2); surfaceRequest = .init(target: .notifications) }
            control("Messages", symbol: "bubble.left.and.bubble.right") { showsMessages = true }
        }
    }

    private func drawer(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Capsule().fill(brand.secondaryText.opacity(0.45)).frame(width: 36, height: 5)
                HStack {
                    Text(LiveActivityPresentation.shownUpdateCount(activity.count)).font(AstirTypography.sectionTitle)
                        .accessibilityLabel(LiveActivityPresentation.loadedUpdateCount(activity.count))
                    Spacer()
                    Text(filterSummary).font(.caption).foregroundStyle(brand.secondaryText)
                        .lineLimit(2).multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("live.filter.summary")
                }
            }
            .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
            .frame(minHeight: 64).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                let travel = value.predictedEndTranslation.height
                if abs(travel) > 35 { changeDetent(detent + (travel < 0 ? 1 : -1)) }
            })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Activity drawer, \(["collapsed", "half expanded", "expanded"][detent])")
            .accessibilityValue("\(LiveActivityPresentation.loadedUpdateCount(activity.count)). \(filterSummary)")
            .accessibilityAdjustableAction { direction in
                changeDetent(detent + (direction == .increment ? 1 : -1))
            }
            .accessibilityIdentifier("live.drawerHandle")

            VStack(spacing: 0) {
                if store.liveFeedSocialExpired {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Reconnect to refresh your people’s activity").font(AstirTypography.bodySmall)
                        Button("Try again") { commitSelection(selection) }.frame(minHeight: 44)
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
                if eventsAvailable {
                    Button { showsEvents = true } label: {
                        Label("Upcoming events", systemImage: "calendar").font(AstirTypography.bodySmall)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.padding(.horizontal, 20)
                }
                if upcomingInvitationCount > 0 {
                    Button { showsUpcomingInvitations = true } label: {
                        Label("Upcoming invitations (\(upcomingInvitationCount))", systemImage: "envelope")
                            .font(AstirTypography.bodySmall)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.padding(.horizontal, 20).accessibilityIdentifier("live.upcomingInvitations")
                }
                if let selectedPin {
                    ScrollView { selectedPlace(selectedPin) }
                        .frame(maxHeight: max(96, height * 0.55))
                }
                FeedScreen(
                    isFeedTabActive: isActive, presentationResetRequest: presentationResetRequest,
                    onPresentation: onPresentation, onWillDismiss: onWillDismiss, onDidDismiss: onDidDismiss,
                    isEmbedded: true, filteredActivityIDs: Set(activity.map(\.id)),
                    activityFocusRequest: focusRequest, surfaceRequest: surfaceRequest,
                    onPrivateReply: openReply,
                    onRefreshRequested: {
                        selection = selection.committed(at: .now)
                        installCommittedQuery(refresh: false)
                    },
                    onAdd: onAdd
                )
            }
            .opacity(detent > 0 ? 1 : 0)
            .allowsHitTesting(detent > 0)
            .accessibilityHidden(detent == 0)
        }
        .frame(height: height, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(brand.background, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -3)
    }

    private func selectedPlace(_ pin: LivePlacePin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(pin.place.place.canonicalName).font(AstirTypography.sectionTitle)
                Spacer()
                control("Close selected place", symbol: "xmark") { selectedPlaceID = nil }
            }
            ForEach(pin.activities) { event in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(event.actor.displayName) · \(LiveActivityPresentation.title(for: event))")
                            .font(AstirTypography.body)
                        Text(FeedPresentation.timestampText(for: event.occurredAt))
                            .font(.caption).foregroundStyle(brand.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("live.activityTime.\(event.id)")
                    }
                    Spacer()
                    Button("Open") { changeDetent(2); focusRequest = .init(activityID: event.id, target: .place) }
                }
                HStack {
                    Button("Show in Feed") { changeDetent(2); focusRequest = .init(activityID: event.id, target: .activity) }
                    if event.resolvedTicketKind == .wanna, let place = event.place {
                        Button("Make a plan") {
                            if let plan = planPlace(for: event) { selectedPlan = plan }
                            else { planSource = place }
                        }
                    }
                    if event.actor.relationship == .mutual {
                        Button("Reply privately") { openReply(event) }
                    }
                }.font(.subheadline).buttonStyle(.bordered)
            }
        }
        .padding(16).background(brand.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var drawingControls: some View {
        VStack {
            Text(draftArea == nil ? "Draw an area" : "Use this area?")
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
            Text("Use visible area").fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }.frame(minHeight: 44)
        Button {
            guard let draftArea else { return }
            area = draftArea; self.draftArea = nil; drawing = false; selectedPlaceID = nil
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
                    Picker("People", selection: $draftAudience) {
                        ForEach(FeedAudience.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("live.filter.people")
                    .accessibilityValue(draftAudience.title)
                    Picker("Activity", selection: $draftSelection.activityType) {
                        ForEach(LiveActivityFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("When", selection: $draftSelection.time) {
                        ForEach(LiveTimeFilter.allCases) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("live.filter.time")
                }
                nearbyFilterSection
                categoryFilterSection
                personFilterSection
                Section {
                    if area != nil {
                        Toggle("Keep drawn area", isOn: Binding(get: { !draftClearsArea }, set: { draftClearsArea = !$0 }))
                    }
                    Text("Filters apply to your people’s activity before each page loads. Map and Feed show the same matching updates.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Time window ends \(selection.committedAt.formatted(date: .abbreviated, time: .shortened)). Apply or refresh updates the window.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Reset filters") {
                        let cityID = draftSelection.cityID
                        draftSelection = LiveBrowseSelection(now: selection.committedAt)
                        draftSelection.cityID = cityID
                        draftClearsArea = true
                    }.accessibilityIdentifier("live.filter.reset")
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
                        if draftClearsArea { area = nil }
                        commitSelection(draftSelection)
                        filtersPresented = false
                    }.disabled(!draftSelection.isValid).accessibilityIdentifier("live.applyFilters")
                }
            }
        }.presentationDetents([.large])
    }

    private var nearbyFilterSection: some View {
        Section("Area") {
            Picker("Scope", selection: $draftSelection.scope) {
                ForEach(LiveBrowseSelection.Scope.allCases) { Text($0.rawValue).tag($0) }
            }.accessibilityIdentifier("live.filter.scope")
            if draftSelection.scope == .nearby {
                Picker("City center", selection: $draftSelection.cityID) {
                    Text("Choose a city").tag(nil as String?)
                    ForEach(HomeMetro.all) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.navigationLink).accessibilityIdentifier("live.filter.city")
                Picker("Radius", selection: $draftSelection.radius) {
                    ForEach(LiveBrowseSelection.Radius.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).accessibilityIdentifier("live.filter.radius")
                Text("Around the selected city's public center. Panning does not change this area. A drawn boundary narrows it further.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var categoryFilterSection: some View {
        Section("Categories") {
            let categories = WanderPlaceCategory.allowedCategories
            ForEach(categories, id: \.self) { category in
                Toggle(WanderPlaceCategory.broadCategory(for: category),
                       isOn: Binding(get: { draftSelection.categoryIDs.contains(category) }, set: { selected in
                    if selected { draftSelection.categoryIDs.insert(category) }
                    else { draftSelection.categoryIDs.remove(category) }
                })).accessibilityIdentifier("live.filter.category.\(category)")
            }
            if !draftSelection.categoryIDs.isEmpty {
                Button("Clear category selection") { draftSelection.categoryIDs = [] }
            }
        }
    }

    private var personFilterSection: some View {
        Section("People") {
            let people = [store.currentUser] + store.following(of: store.currentUser.id)
            ForEach(people) { person in
                Toggle(person.displayName, isOn: Binding(get: { draftSelection.personIDs.contains(person.id) }, set: { selected in
                    // REC636-V39-LIVE-DIAGNOSTIC-BEGIN
                    #if DEBUG && targetEnvironment(simulator)
                    NativeInputRecipientDiagnostic.record(.livePersonFilterSetEntered)
                    #endif
                    // REC636-V39-LIVE-DIAGNOSTIC-END
                    if selected { draftSelection.personIDs.insert(person.id) }
                    else { draftSelection.personIDs.remove(person.id) }
                    // REC636-V39-LIVE-DIAGNOSTIC-BEGIN
                    #if DEBUG && targetEnvironment(simulator)
                    NativeInputRecipientDiagnostic.record(selected ? .livePersonFilterEnabled : .livePersonFilterDisabled)
                    NativeInputRecipientDiagnostic.record(.livePersonFilterSetApplied)
                    #endif
                    // REC636-V39-LIVE-DIAGNOSTIC-END
                })).accessibilityIdentifier("live.filter.person.\(person.id)")
            }
            if !draftSelection.personIDs.isEmpty {
                Button("Clear person selection") { draftSelection.personIDs = [] }
            }
        }
    }

    private func openFilters(nearby: Bool = false) {
        draftSelection = selection
        if draftSelection.cityID == nil { draftSelection.cityID = HomeMetro.find(homeMetroID)?.id }
        if nearby {
            draftSelection.scope = .nearby
            if selection.scope != .nearby { draftSelection.radius = .fiveKilometers }
        }
        draftAudience = store.feedAudience
        draftClearsArea = false
        filtersPresented = true
    }

    private func commitSelection(_ next: LiveBrowseSelection) {
        guard next.isValid else { return }
        let changedNearby = next.scope == .nearby && (selection.scope != .nearby
            || next.center != selection.center || next.radius != selection.radius)
        selection = next.committed(at: .now)
        selectedPlaceID = nil
        installCommittedQuery()
        if changedNearby, let center = selection.center {
            camera = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: Double(selection.radius.rawValue) * 2.8,
                longitudinalMeters: Double(selection.radius.rawValue) * 2.8
            ))
            didFrame = true
        }
    }

    private var filterSummary: String {
        ([selection.summary] + (store.feedAudience == .everyone ? [] : [store.feedAudience.title])
            + (area == nil ? [] : ["Drawn area"])).joined(separator: " · ")
    }

    private func installCommittedQuery(refresh: Bool = true) {
        guard selection.isValid else { return }
        store.selectLiveFeedQuery(selection.query(area: area))
        store.refreshLiveFeedDisplayLease()
        if refresh {
            let userID = store.currentUser.id, query = store.liveFeedQuery
            Task {
                guard store.currentUser.id == userID, store.liveFeedQuery == query else { return }
                await store.refreshFeedSurface(backend: auth.isSignedIn ? backend : nil, force: false)
            }
        }
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
        switch detent { case 0: 70; case 2: max(70, available - 8); default: max(70, available * 0.48) }
    }
    private func changeDetent(_ value: Int) {
        // REC636-V39-LIVE-DIAGNOSTIC-BEGIN
        #if DEBUG && targetEnvironment(simulator)
        NativeInputRecipientDiagnostic.record(.liveDrawerChangeEntered)
        #endif
        // REC636-V39-LIVE-DIAGNOSTIC-END
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { detent = min(2, max(0, value)) }
        // REC636-V39-LIVE-DIAGNOSTIC-BEGIN
        #if DEBUG && targetEnvironment(simulator)
        NativeInputRecipientDiagnostic.record(.liveDrawerChangeApplied)
        #endif
        // REC636-V39-LIVE-DIAGNOSTIC-END
    }
    private func startDrawing() {
        guard let viewport, viewport.span.longitudeDelta < 180 else { areaNotice = true; return }
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
        let homeAnchor = HomeMetro.find(homeMetroID).map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard !didFrame, !camera.positionedByUser, !pins.isEmpty,
              let region = LiveMapCameraPolicy.region(coordinates: pins.map { coordinate($0.place) },
                                                      anchor: homeAnchor ?? activity.compactMap(\.place).first.map(coordinate)) else { return }
        camera = .region(region); didFrame = true
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

/// Shared copy for Live's map and selection chooser; Feed cards keep their own presentation.
enum LiveActivityPresentation {
    static func shownUpdateCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "update" : "updates") shown"
    }

    static func loadedUpdateCount(_ count: Int) -> String {
        "\(count) loaded \(count == 1 ? "update" : "updates")"
    }

    static func title(for activity: FeedActivity) -> String {
        switch activity.resolvedTicketKind {
        case .wanna: "Wanna"
        case .checkIn: "Check-in"
        case .list: "List update"
        case .saved: "Saved place"
        }
    }
}

private struct LivePlacePin: Identifiable {
    let id: String
    let place: VisiblePlace
    let activities: [FeedActivity]
    var isWanna: Bool { activities.allSatisfy { $0.resolvedTicketKind == .wanna } }

    var accessibilityLabel: String {
        // Pin activities are already ordered by FeedPresentation.newestFirst.
        guard let latest = activities.first else { return place.place.canonicalName }
        let kind = LiveActivityPresentation.title(for: latest)
        let latestSummary = "\(latest.actor.displayName), \(kind), \(FeedPresentation.timestampText(for: latest.occurredAt))"
        guard activities.count > 1 else {
            return "\(place.place.canonicalName), \(latestSummary)"
        }
        let peopleCount = Set(activities.map { $0.actor.id }).count
        return "\(place.place.canonicalName), \(activities.count) updates from \(peopleCount) \(peopleCount == 1 ? "person" : "people"). Latest: \(latestSummary)"
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
