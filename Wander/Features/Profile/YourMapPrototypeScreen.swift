import MapKit
import Observation
import SwiftUI
import UIKit

/// Uses the main Map's gesture classification and dismissal timing. Camera
/// samples live in a reference tracker so a pinch does not rebuild SwiftUI.
@MainActor
@Observable
final class YourMapInteractionState {
    let camera: MapCameraRegionTracker
    private(set) var cameraRequest: NativeMapCameraRequest
    private(set) var selectedPlaceID: String?
    var presentedPlaceID: String?
    var isMapChromeVisible: Bool { presentedPlaceID == nil }
    private(set) var bounceRevision: UInt64 = 0
    @ObservationIgnored private var pendingTap: Task<Void, Never>?
    @ObservationIgnored private var previousTapDate = Date.distantPast
    @ObservationIgnored private var suppressTapUntil = Date.distantPast
    @ObservationIgnored private var selectionRevision: UInt64 = 0
    @ObservationIgnored private var cameraSnapshot: MKMapCamera?

    init(region: MKCoordinateRegion) {
        camera = MapCameraRegionTracker(region: region)
        cameraRequest = NativeMapCameraRequest(region: region, revision: 0, animated: false)
    }

    func select(_ placeID: String) {
        cancelPendingTap()
        selectionRevision &+= 1
        if selectedPlaceID == placeID { bounceRevision &+= 1 }
        selectedPlaceID = placeID
    }

    func openSelectedPlace() {
        cancelPendingTap()
        presentedPlaceID = selectedPlaceID
    }

    func dismissSelection(trigger: MapSelectionDismissalTrigger) {
        guard MapSelectionLifetimePolicy.shouldDismiss(for: trigger) else { return }
        cancelPendingTap()
        selectionRevision &+= 1
        selectedPlaceID = nil
    }

    func tapEmptyMap(now: Date = .now) {
        cancelPendingTap()
        guard now >= suppressTapUntil, selectedPlaceID != nil else { return }
        if now.timeIntervalSince(previousTapDate) <= MapSelectionGesturePolicy.doubleTapRecognitionWindow {
            previousTapDate = .distantPast
            registerZoom(now: now)
            return
        }
        previousTapDate = now
        let revision = selectionRevision
        let tapRegion = camera.region
        pendingTap = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: MapSelectionGesturePolicy.tapDismissalDelayNanoseconds) }
            catch { return }
            guard let self else { return }
            if MapSelectionGesturePolicy.classify(from: tapRegion, to: self.camera.region) == .zoom {
                self.registerZoom()
                return
            }
            guard !Task.isCancelled, revision == self.selectionRevision,
                  !self.camera.isInteractionActive, Date.now >= self.suppressTapUntil,
                  self.presentedPlaceID == nil
            else { return }
            self.dismissSelection(trigger: .emptyMapTap)
        }
    }

    func finishCameraChange(_ region: MKCoordinateRegion, isUserInitiated: Bool) {
        switch camera.finishCameraChange(region, isUserInitiated: isUserInitiated) {
        case .stationary: break
        case .zoom: registerZoom()
        case .pan: dismissSelection(trigger: .oneFingerPan)
        }
    }

    func reconcile(placeIDs: Set<String>) {
        if let selectedPlaceID, !placeIDs.contains(selectedPlaceID) {
            dismissSelection(trigger: .emptyMapTap)
        }
        if let presentedPlaceID, !placeIDs.contains(presentedPlaceID) {
            self.presentedPlaceID = nil
        }
    }

    func recordCameraSnapshot(_ camera: MKMapCamera) {
        cameraSnapshot = camera
    }

    func suspend() {
        cancelPendingTap()
        // Navigation can recreate the native view. Restore the last viewport,
        // never the initial region, if that happens on the way back.
        cameraRequest = NativeMapCameraRequest(
            region: camera.region, revision: cameraRequest.revision &+ 1, animated: false,
            restoredCamera: cameraSnapshot
        )
    }

    private func registerZoom(now: Date = .now) {
        suppressTapUntil = now.addingTimeInterval(MapSelectionGesturePolicy.postZoomTapSuppressionDuration)
        cancelPendingTap()
    }

    private func cancelPendingTap() {
        pendingTap?.cancel()
        pendingTap = nil
    }
}

struct YourMapPrototypeScreen: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @StateObject private var snapshotCapture = MapSnapshotCapture()
    @State private var isCapturingSnapshot = false
    @State private var snapshotListID: String?
    @State private var editingSnapshotListID: String?
    @State private var snapshotError: String?

    let dataset: YourMapPrototypeDataset
    let viewerID: String?
    let sharedProfileID: String?
    let mapTitle: String
    let pinOwnership: MapPinSaveOwnership

    @State private var mode: YourMapPrototypeMode
    @State private var lens: YourMapPrototypeLens
    @State private var interaction: YourMapInteractionState
    @State private var showsFilters = false
    @State private var showsSharePreview: Bool
    @State private var savedLenses: [YourMapPrototypeSavedLens] = []

    init(
        dataset: YourMapPrototypeDataset,
        viewerID: String? = nil,
        sharedProfileID: String? = nil,
        mapTitle: String = "Your Map",
        pinOwnership: MapPinSaveOwnership = .currentUser,
        initialMode: YourMapPrototypeMode = .map,
        initialShowsSharePreview: Bool = false
    ) {
        self.dataset = dataset
        self.viewerID = viewerID
        self.sharedProfileID = sharedProfileID
        self.mapTitle = mapTitle
        self.pinOwnership = pinOwnership
        _mode = State(initialValue: initialMode)
        _showsSharePreview = State(initialValue: initialShowsSharePreview)
        _lens = State(initialValue: dataset.initialLens)
        let initialRegion = Self.initialRegion(for: dataset.places)
        _interaction = State(initialValue: YourMapInteractionState(region: initialRegion))
    }

    init(
        volume: YourMapPrototypeDataVolume = .medium,
        initialMode: YourMapPrototypeMode = .map,
        initialShowsSharePreview: Bool = false
    ) {
        self.init(
            dataset: YourMapPrototypeDataset.make(volume: volume),
            initialMode: initialMode,
            initialShowsSharePreview: initialShowsSharePreview
        )
    }

    var body: some View {
        ZStack {
            // Keep the native map mounted while viewing Patterns, retaining
            // its viewport, heading and pitch without a camera feedback loop.
            mapWorkspace
                .opacity(mode == .map ? 1 : 0)
                .allowsHitTesting(mode == .map)
                .accessibilityHidden(mode != .map)
            if mode == .patterns { patternsWorkspace }
        }
        .foregroundStyle(brandMode.primaryText)
        .tint(brandMode.accent)
        .sheet(isPresented: $showsFilters) {
            YourMapPrototypeFilterSheet(
                lens: $lens,
                savedLenses: $savedLenses,
                places: dataset.places,
                resultCount: filteredPlaces.count
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsSharePreview) { mapSharePreview }
        .sheet(isPresented: Binding(
            get: { editingSnapshotListID != nil },
            set: { if !$0 { editingSnapshotListID = nil } }
        )) {
            if let editingSnapshotListID {
                SnapshotListEditorScreen(listID: editingSnapshotListID)
            }
        }
        .alert("Couldn’t save snapshot", isPresented: Binding(
            get: { snapshotError != nil },
            set: { if !$0 { snapshotError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(snapshotError ?? "Please try again.")
        }
        .navigationTitle(interaction.isMapChromeVisible ? (mode == .map ? mapTitle : "Patterns") : "")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!interaction.isMapChromeVisible)
        .toolbar(interaction.isMapChromeVisible ? .visible : .hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if interaction.isMapChromeVisible {
                    Button {
                        if mode == .map {
                            showsSharePreview = true
                        } else {
                            showsFilters = true
                        }
                    } label: {
                        Image(systemName: mode == .map ? "square.and.arrow.up" : "slider.horizontal.3")
                    }
                    .disabled(mode == .map && sharedMapProfile?.serverID == nil)
                    .accessibilityLabel(mode == .map ? "Share this lens" : "Filters")
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { interaction.presentedPlaceID != nil },
            set: { if !$0 { interaction.presentedPlaceID = nil } }
        )) {
            if let id = interaction.presentedPlaceID,
               let place = dataset.visiblePlaceByPlaceID[id] {
                PlaceProfileFullScreen(
                    place: PlaceSheetPlace(visiblePlace: place),
                    saves: saveSummaries(for: place),
                    tasteSaves: [],
                    currentUserID: viewerID ?? store.currentUser.id,
                    action: .none,
                    onBack: { interaction.presentedPlaceID = nil },
                    onAction: {}
                )
            }
        }
        .onChange(of: filteredPlaces) { _, places in
            interaction.reconcile(placeIDs: Set(places.map(\.id)))
        }
        .onDisappear { interaction.suspend() }

    }

    @ViewBuilder
    private var mapSharePreview: some View {
            if let profile = sharedMapProfile,
               let content = WanderShareContent.profile(serverID: profile.serverID, displayName: profile.displayName, handle: profile.handle) {
                ActivitySharePreviewScreen(
                    card: ShareCardContent(kind: .map, name: mapShareTitle(profile), ownerName: profile.displayName, count: filteredPlaces.count),
                    content: content.withSubject(mapShareTitle(profile)),
                    loadImages: {
                        let points = filteredPlaces.map { place in
                            let statuses = lens.statuses.isEmpty ? place.statuses : place.statuses.intersection(lens.statuses)
                            return ProfileMapPoint(
                                id: place.id, name: place.name, city: place.city,
                                latitude: place.latitude, longitude: place.longitude,
                                status: statuses.contains(.been) ? .been : .wannaGo,
                                secondaryStatus: statuses.count > 1 ? .wannaGo : nil
                            )
                        }
                        let request = ProfileMapSnapshotRequest(points: points, size: CGSize(width: 390, height: 238), displayScale: 3, colorScheme: .dark)
                        return ShareCardImages(map: await ProfileMapSnapshotCache.shared.image(for: request))
                    }
                )
            }
    }

    private var sharedMapProfile: LocalProfile? {
        sharedProfileID.flatMap { store.profile(for: $0) } ?? (sharedProfileID == nil ? store.currentUser : nil)
    }

    private func mapShareTitle(_ profile: LocalProfile) -> String {
        if let city = lens.cities.sorted().first { return "\(profile.displayName)’s \(city) map" }
        if let category = lens.categories.sorted().first { return "\(profile.displayName)’s \(category.lowercased()) map" }
        return mapTitle == "Your Map" ? "\(profile.displayName)’s map" : mapTitle
    }

    private var filteredPlaces: [YourMapPrototypePlace] {
        dataset.places.filter { lens.matches($0, now: dataset.now) }
    }

    private var renderedPlaces: [YourMapPrototypePlace] {
        filteredPlaces
    }

    private var insights: YourMapPrototypeInsights {
        YourMapPrototypeInsights(places: filteredPlaces, now: dataset.now)
    }

    private var selectedVisiblePlace: VisiblePlace? {
        guard let selectedPlaceID = interaction.selectedPlaceID,
              renderedPlaces.contains(where: { $0.id == selectedPlaceID })
        else { return nil }
        return dataset.visiblePlaceByPlaceID[selectedPlaceID]
    }

    private var mapWorkspace: some View {
        ZStack(alignment: .bottom) {
            NativeMapView(
                attributionBottomClearance: 72,
                isInteractionEnabled: mode == .map && interaction.isMapChromeVisible,
                annotations: nativeAnnotations,
                cameraRequest: interaction.cameraRequest,
                nativeFeatureClearRevision: 0,
                showsUserLocation: false,
                isDark: brandMode.prefersDarkInterface,
                reduceMotion: reduceMotion,
                onAnnotationTap: { kind in
                    if case let .saved(id) = kind { interaction.select(id) }
                },
                onEmptyMapTap: { interaction.tapEmptyMap() },
                onLongPress: { _ in },
                onNativeFeatureSelection: { _ in },
                onUserInteraction: {},
                onCameraChange: { interaction.camera.recordCameraChange($0) },
                onCameraInteractionEnd: { interaction.finishCameraChange($0, isUserInitiated: $1) },
                allowsNativeFeatureSelection: false,
                usesAdaptivePinDetail: true,
                onCameraSnapshot: { interaction.recordCameraSnapshot($0) }
            )
            .overlay { MapSnapshotCaptureAnchor(capture: snapshotCapture).allowsHitTesting(false) }
            .ignoresSafeArea()
            .overlay {
                if filteredPlaces.isEmpty {
                    mapEmptyState
                }
            }

            mapControls
                // NavigationStack can retain the source during a push. Hide
                // its chrome in the same update that requests the destination,
                // without waiting for onDisappear or animating an opacity tail.
                .opacity(interaction.isMapChromeVisible ? 1 : 0)
                .allowsHitTesting(interaction.isMapChromeVisible)
                .accessibilityHidden(!interaction.isMapChromeVisible)
                .animation(nil, value: interaction.isMapChromeVisible)
        }
    }

    private var mapControls: some View {
        ZStack(alignment: .bottom) {
            selectedPlaceProfileSurface
                .padding(.bottom, 72)
                .zIndex(30)

            VStack(spacing: 0) {
                if let snapshotListID {
                    snapshotToast(listID: snapshotListID)
                }
                mapHeader
                Spacer(minLength: WanderTheme.spacing4)
                modePicker
                    .padding(.horizontal, WanderTheme.spacing4)
                    .padding(.bottom, WanderTheme.spacing4)
            }
            .zIndex(40)
        }
    }

    @ViewBuilder
    private var selectedPlaceProfileSurface: some View {
        if let selectedVisiblePlace {
            PlaceProfileMapSurface(
                place: PlaceSheetPlace(visiblePlace: selectedVisiblePlace),
                saves: saveSummaries(for: selectedVisiblePlace),
                tasteSaves: [],
                currentUserID: viewerID ?? store.currentUser.id,
                viewerLocation: nil,
                action: .none,
                onOpen: { interaction.openSelectedPlace() },
                onAction: {},
                onReady: {}
            )
        }
    }

    private var mapHeader: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Spacer(minLength: 0)

            if pinOwnership == .currentUser {
                Button(action: saveMapSnapshot) {
                    Group {
                        if isCapturingSnapshot {
                            ProgressView()
                        } else {
                            Label("Snapshot", systemImage: "camera")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: WanderTheme.tapMinimum)
                    .astirGlassSurface(cornerRadius: WanderTheme.tapMinimum / 2, castsShadow: true)
                }
                .buttonStyle(.plain)
                .disabled(isCapturingSnapshot)
                .accessibilityLabel("Save map snapshot as a list")
                .accessibilityHint("Includes the saved Check-in and Wanna pins in this view")
                .accessibilityIdentifier("yourMap.snapshot")
            }

            Button {
                showsFilters = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(brandMode.primaryText)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .astirGlassSurface(
                        cornerRadius: WanderTheme.tapMinimum / 2,
                        castsShadow: true
                    )
                    .overlay(alignment: .topTrailing) {
                        if lens.activeSectionCount > 0 {
                            Text("\(lens.activeSectionCount)")
                                .font(AstirTypography.metadata)
                                .foregroundStyle(brandMode.accentForeground)
                                .frame(width: 19, height: 19)
                                .background(brandMode.accent, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filters, \(lens.activeSectionCount) active")
            .accessibilityIdentifier("yourMap.prototype.filters")
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
        .padding(.bottom, WanderTheme.spacing3)
        .background(
            LinearGradient(
                colors: [brandMode.background.opacity(0.88), brandMode.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func saveMapSnapshot() {
        guard !isCapturingSnapshot else { return }
        isCapturingSnapshot = true
        do {
            let capture = try snapshotCapture.capture(places: filteredPlaces)
            guard let list = store.createMapSnapshotList(placeIDs: capture.placeIDs, coverData: capture.jpegData) else {
                throw MapSnapshotCapture.CaptureError.empty
            }
            snapshotListID = list.localID
            UIAccessibility.post(notification: .announcement, argument: "Snapshot list saved. View snapshot list.")
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                isCapturingSnapshot = false
                _ = await store.syncPendingPlaceLists(backend: backend)
            }
        } catch {
            snapshotError = error.localizedDescription
            isCapturingSnapshot = false
        }
    }

    private func snapshotToast(listID: String) -> some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WanderTheme.stateSuccess.color)
                .accessibilityHidden(true)

            Text("View snapshot list")
                .font(AstirTypography.bodySmall)
                .foregroundStyle(brandMode.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                editingSnapshotListID = listID
                snapshotListID = nil
            } label: {
                Text("Edit")
                    .font(AstirTypography.control)
                    .foregroundStyle(brandMode.accentText)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
            }
            .accessibilityIdentifier("yourMap.viewSnapshotList")
            .accessibilityHint("Edit the snapshot list's name, details, and places")
        }
        .buttonStyle(.plain)
        .padding(.leading, WanderTheme.spacing4)
        .padding(.trailing, WanderTheme.spacing1)
        .padding(.vertical, WanderTheme.spacing2)
        .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing2)
    }

    private var modePicker: some View {
        AstirEditorialSegmentedSwitch(
            options: YourMapPrototypeMode.allCases.map {
                WanderSegmentOption(id: $0.rawValue, title: $0.title)
            },
            selection: Binding(
                get: { mode.rawValue },
                set: { rawValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        mode = YourMapPrototypeMode(rawValue: rawValue) ?? .map
                    }
                }
            )
        )
        .accessibilityIdentifier("yourMap.prototype.mode")
    }

    private var patternsWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                if filteredPlaces.isEmpty {
                    patternsEmptyState
                } else {
                    HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                        categoryMixCard
                        repeatRateCard
                    }
                    locationFootprintCard
                    monthlyRhythmCard
                    returnMagnetsCard
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing3)
            .padding(.bottom, 104)
        }
        .scrollIndicators(.hidden)
        .background(brandMode.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            modePicker
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.vertical, WanderTheme.spacing3)
                .background(
                    LinearGradient(
                        colors: [brandMode.background.opacity(0), brandMode.background],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .accessibilityIdentifier("yourMap.prototype.patterns")
    }

    private var categoryMixCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("category mix", systemImage: "chart.bar.fill")
                .font(AstirTypography.label)
            ForEach(insights.categoryBreakdown.prefix(5)) { item in
                YourMapPrototypeBarRow(item: item)
            }
            Spacer(minLength: 0)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
    }

    private var repeatRateCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Label("repeat rate", systemImage: "arrow.triangle.2.circlepath")
                .font(AstirTypography.label)
            Text("\(repeatRatePercentage)%")
                .font(AstirTypography.screenTitle.monospacedDigit())
                .foregroundStyle(brandMode.accentText)
            Text("of checked-in places are somewhere you returned to")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            YourMapPrototypeSparkline()
                .frame(height: 32)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
    }


    private var locationFootprintCard: some View {
        YourMapGeographyCard(cities: insights.cityBreakdown, countries: insights.countryBreakdown)
    }

    private var monthlyRhythmCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Label("month by month", systemImage: "calendar")
                .font(AstirTypography.cardTitle)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                spacing: WanderTheme.spacing2
            ) {
                ForEach(insights.monthlyActivity) { month in
                    VStack(spacing: 5) {
                        Text(month.shortTitle)
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.secondaryText)
                        RoundedRectangle(cornerRadius: 7)
                            .fill(
                                brandMode.accent.opacity(
                                    month.count == 0 ? 0.10 : 0.28 + (0.72 * month.intensity)
                                )
                            )
                            .frame(height: 30)
                            .overlay {
                                Text("\(month.count)")
                                    .font(AstirTypography.metadata.monospacedDigit())
                                    .foregroundStyle(month.intensity > 0.55 ? brandMode.accentForeground : brandMode.primaryText)
                            }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(month.title), \(month.count) places")
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .accessibilityIdentifier("yourMap.prototype.monthHeatMap")
    }

    private var returnMagnetsCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Label("return magnets", systemImage: "arrow.triangle.2.circlepath")
                .font(AstirTypography.cardTitle)

            if insights.returnMagnets.isEmpty {
                Text("Places you revisit will collect here.")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
            } else {
                ForEach(Array(insights.returnMagnets.prefix(4).enumerated()), id: \.element.id) { index, place in
                    HStack(spacing: WanderTheme.spacing3) {
                        Text("\(index + 1)")
                            .font(AstirTypography.label.monospacedDigit())
                            .foregroundStyle(brandMode.accentText)
                            .frame(width: 24, height: 24)
                            .background(brandMode.accentWash, in: Circle())
                        WanderCategoryEmoji(category: place.category, name: place.name, size: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name)
                                .font(AstirTypography.label)
                                .lineLimit(1)
                            Text(place.city)
                                .font(AstirTypography.metadata)
                                .foregroundStyle(brandMode.secondaryText)
                        }
                        Spacer(minLength: 0)
                        Text("\(place.visitCount) visits")
                            .font(AstirTypography.metadata.monospacedDigit())
                            .foregroundStyle(brandMode.accentText)
                    }
                    .frame(minHeight: WanderTheme.tapMinimum)

                    if index < min(insights.returnMagnets.count, 4) - 1 {
                        Divider().overlay(brandMode.border)
                    }
                }
            }
        }
        .padding(WanderTheme.spacing4)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .accessibilityIdentifier("yourMap.prototype.returnMagnets")
    }

    private var mapEmptyState: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: dataset.places.isEmpty ? "mappin.and.ellipse" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(brandMode.accentText)
            Text(dataset.places.isEmpty ? "\(mapTitle) has no places you can see yet" : "No places match this lens")
                .font(AstirTypography.cardTitle)
                .multilineTextAlignment(.center)
            Text(dataset.places.isEmpty ? emptyMapDetail : "Keep the lens or loosen one filter. Your choices stay intact until you reset them.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .multilineTextAlignment(.center)
            if !dataset.places.isEmpty {
                Button("Reset lens") {
                    lens = YourMapPrototypeLens()
                }
                .font(AstirTypography.control)
                .foregroundStyle(brandMode.accentForeground)
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: WanderTheme.tapMinimum)
                .background(
                    brandMode.accent,
                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                )
            }
        }
        .padding(WanderTheme.spacing4)
        .frame(maxWidth: 300)
        .background(brandMode.raisedBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge).stroke(brandMode.border))
        .shadow(color: Color.black.opacity(0.18), radius: 16, y: 6)
        .padding(.bottom, 84)
    }

    private var emptyMapDetail: String {
        mapTitle == "Your Map"
            ? "Add a place worth remembering and it will appear here."
            : "Places they choose to share with you will appear here."
    }

    private var patternsEmptyState: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(brandMode.accentText)
            Text("No patterns in this slice yet")
                .font(AstirTypography.cardTitle)
            Text("Try a wider time range or reset one filter.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(WanderTheme.spacing6)
        .background(brandMode.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var repeatRatePercentage: Int {
        Int((insights.repeatRate * 100).rounded())
    }

    private var nativeAnnotations: [NativeMapAnnotationDescriptor] {
        renderedPlaces.map { place in
            let statuses = lens.statuses.isEmpty ? place.statuses : place.statuses.intersection(lens.statuses)
            let outlines = MapPinOutlineBuilder.outlines(for: statuses.map {
                MapPinSaveState(ownership: pinOwnership, status: $0 == .been ? .been : .wannaGo)
            })
            return NativeMapAnnotationDescriptor(
                id: place.id, kind: .saved(place.id), title: place.name,
                emoji: WanderPlaceCategory.emoji(for: place.category, name: place.name),
                coordinate: place.coordinate, outlines: outlines,
                isSearchResult: false, isSelected: interaction.selectedPlaceID == place.id,
                opacity: 1, animatesEntrance: false, entranceDelay: 0,
                accessibilityLabel: MapPinAccessibility.label(
                    outlines: outlines, category: place.category, placeName: place.name
                ),
                bounceRevision: interaction.selectedPlaceID == place.id ? interaction.bounceRevision : 0,
                accessibilityIdentifierOverride: "yourMap.prototype.pin.\(place.id)",
                keepsVisibleWhenColliding: true
            )
        }
    }

    private func saveSummaries(for visiblePlace: VisiblePlace) -> [PlaceSaveSummary] {
        [PlaceSaveSummary(visiblePlace: visiblePlace, attributes: visiblePlace.attributes)]
    }

    private static func initialRegion(for places: [YourMapPrototypePlace]) -> MKCoordinateRegion {
        let centerPlace = places.first { $0.city == "Los Angeles" }
        let center = centerPlace?.coordinate ?? CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.34, longitudeDelta: 0.34)
        )
    }
}

private struct YourMapPrototypeFilterSheet: View {
    @Environment(\.astirBrandMode) private var brandMode
    @Binding var lens: YourMapPrototypeLens
    @Binding var savedLenses: [YourMapPrototypeSavedLens]
    let places: [YourMapPrototypePlace]
    let resultCount: Int
    @Environment(\.dismiss) private var dismiss

    private var categories: [String] {
        sortedOptions(places.map(\.category), fallback: ["Coffee", "Restaurants", "Bars", "Bakeries", "Outdoors"])
    }

    private var cities: [String] {
        sortedOptions(places.map(\.city), fallback: ["Los Angeles", "San Francisco", "New York", "Portland"])
    }

    private var countries: [String] {
        sortedOptions(places.map(\.country), fallback: ["United States", "France"])
    }

    private var tags: [String] {
        sortedOptions(places.flatMap(\.tags), fallback: ["calm", "date night", "laptop", "morning", "weekend"])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing6) {
                    savedLensSection

                    filterSection(title: "Time", detail: "Choose one") {
                        optionGrid {
                            ForEach(YourMapPrototypeTimeRange.allCases) { range in
                                filterChip(
                                    title: range.title,
                                    systemImage: "calendar",
                                    isSelected: lens.timeRange == range
                                ) {
                                    lens.timeRange = range
                                }
                            }
                        }
                    }

                    filterSection(title: "Status", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(YourMapPrototypeStatus.allCases) { status in
                                filterChip(
                                    title: status.title,
                                    systemImage: status.systemImage,
                                    isSelected: lens.statuses.contains(status)
                                ) {
                                    lens.toggleStatus(status)
                                }
                            }
                        }
                    }

                    filterSection(title: "Category", detail: "Values combine together") {
                        optionGrid {
                            ForEach(categories, id: \.self) { category in
                                filterChip(
                                    title: category,
                                    systemImage: categorySystemImage(category),
                                    isSelected: lens.categories.contains(category)
                                ) {
                                    lens.toggleCategory(category)
                                }
                            }
                        }
                    }

                    filterSection(title: "City", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(cities, id: \.self) { city in
                                filterChip(
                                    title: city,
                                    systemImage: "mappin",
                                    isSelected: lens.cities.contains(city)
                                ) {
                                    lens.toggleCity(city)
                                }
                            }
                        }
                    }

                    filterSection(title: "Country", detail: "Choose one or more") {
                        optionGrid {
                            ForEach(countries, id: \.self) { country in
                                filterChip(
                                    title: country,
                                    systemImage: "globe.americas.fill",
                                    isSelected: lens.countries.contains(country)
                                ) {
                                    lens.toggleCountry(country)
                                }
                            }
                        }
                    }

                    filterSection(title: "Tags", detail: "Any selected tag can match") {
                        optionGrid {
                            ForEach(tags, id: \.self) { tag in
                                filterChip(
                                    title: tag,
                                    systemImage: "tag.fill",
                                    isSelected: lens.tags.contains(tag)
                                ) {
                                    lens.toggleTag(tag)
                                }
                            }
                        }
                    }

                    filterSection(title: "Rating", detail: "Choose one") {
                        optionGrid {
                            ForEach(YourMapPrototypeRatingOption.allCases) { option in
                                filterChip(
                                    title: option.title,
                                    systemImage: "star.fill",
                                    isSelected: lens.minimumRating == option.minimum
                                ) {
                                    lens.minimumRating = option.minimum
                                }
                            }
                        }
                    }

                    Toggle(isOn: $lens.repeatOnly) {
                        Label("Repeat visits only", systemImage: "arrow.triangle.2.circlepath")
                            .font(AstirTypography.label)
                    }
                    .tint(brandMode.accent)
                    .frame(minHeight: WanderTheme.tapMinimum)

                    Text("Values within a section combine. Sections narrow the map together. A zero-result lens stays selected until you change or reset it.")
                        .font(AstirTypography.caption)
                        .foregroundStyle(brandMode.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
            .background(brandMode.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        lens = YourMapPrototypeLens()
                    }
                    .disabled(lens.activeSectionCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider().overlay(brandMode.border)
                    HStack(spacing: WanderTheme.spacing2) {
                        Button {
                            guard !isCurrentLensSaved else { return }
                            savedLenses.append(
                                YourMapPrototypeSavedLens(
                                    lens: lens,
                                    ordinal: savedLenses.count + 1
                                )
                            )
                        } label: {
                            Label(isCurrentLensSaved ? "Saved" : "Save lens", systemImage: isCurrentLensSaved ? "checkmark" : "bookmark")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.primaryText)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    brandMode.recessedBackground,
                                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                        .stroke(brandMode.border)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(lens.activeSectionCount == 0 || isCurrentLensSaved)
                        .opacity(lens.activeSectionCount == 0 ? 0.5 : 1)
                        .accessibilityIdentifier("yourMap.prototype.saveLens")

                        Button {
                            dismiss()
                        } label: {
                            Text("Show \(resultCount)")
                                .font(AstirTypography.control)
                                .foregroundStyle(brandMode.accentForeground)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(
                                    brandMode.accent,
                                    in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(WanderTheme.spacing4)
                }
                .background(brandMode.raisedBackground)
            }
        }
        .foregroundStyle(brandMode.primaryText)
        .background(brandMode.background.ignoresSafeArea())
        .tint(brandMode.accent)
    }

    private var savedLensSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Saved lenses")
                    .font(AstirTypography.sectionTitle)
                Spacer()
                Text("Reusable filters")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
            }

            Text("Save lens stores this exact filter recipe. Tap it later to reapply the same slice; it does not share any places.")
                .font(AstirTypography.caption)
                .foregroundStyle(brandMode.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if savedLenses.isEmpty {
                Label("No saved lenses yet", systemImage: "bookmark")
                    .font(AstirTypography.caption)
                    .foregroundStyle(brandMode.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .background(
                        brandMode.recessedBackground,
                        in: RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: WanderTheme.radiusMedium, style: .continuous)
                            .stroke(brandMode.border)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(savedLenses) { savedLens in
                        YourMapPrototypeSavedLensRow(
                            savedLens: savedLens,
                            isSelected: savedLens.lens == lens,
                            onSelect: {
                                lens = savedLens.lens
                            },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    savedLenses.removeAll { $0.id == savedLens.id }
                                }
                            }
                        )

                        if savedLens.id != savedLenses.last?.id {
                            Divider()
                                .overlay(brandMode.border)
                        }
                    }
                }
                .background(brandMode.raisedBackground)
                .overlay(alignment: .top) {
                    Divider().overlay(brandMode.border)
                }
                .overlay(alignment: .bottom) {
                    Divider().overlay(brandMode.border)
                }
                .padding(.horizontal, -WanderTheme.spacing4)
            }
        }
    }

    private var isCurrentLensSaved: Bool {
        savedLenses.contains { $0.lens == lens }
    }

    private func filterSection<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(AstirTypography.sectionTitle)
                Spacer()
                Text(detail)
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
            }
            content()
        }
    }

    private func optionGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: WanderTheme.spacing2)],
            alignment: .leading,
            spacing: WanderTheme.spacing2,
            content: content
        )
    }

    private func filterChip(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: WanderTheme.spacing1) {
                    Image(systemName: systemImage)
                    Text(title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .font(AstirTypography.label)
                .foregroundStyle(isSelected ? brandMode.accent : brandMode.primaryText)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing2)

                Rectangle()
                    .fill(isSelected ? brandMode.accent : brandMode.border)
                    .frame(height: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sortedOptions(_ values: [String], fallback: [String]) -> [String] {
        let resolved = Set(values).sorted()
        return resolved.isEmpty ? fallback : resolved
    }
}

private struct YourMapPrototypeSavedLensRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let savedLens: YourMapPrototypeSavedLens
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var restingOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private var contentOffset: CGFloat {
        YourMapPrototypeLensSwipePolicy.clampedOffset(restingOffset + dragTranslation)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AstirTheme.paper.color)
                    .frame(
                        width: YourMapPrototypeLensSwipePolicy.revealWidth,
                        height: 68
                    )
                    .background(WanderTheme.stateError.color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(savedLens.title)")
            .accessibilityIdentifier("yourMap.prototype.deleteLens.\(savedLens.id.uuidString)")
            .allowsHitTesting(
                restingOffset <= -(YourMapPrototypeLensSwipePolicy.revealWidth / 2)
            )
            .zIndex(
                restingOffset <= -(YourMapPrototypeLensSwipePolicy.revealWidth / 2) ? 2 : 0
            )

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    restingOffset = 0
                }
                onSelect()
            } label: {
                HStack(spacing: WanderTheme.spacing3) {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(brandMode.accentText)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(savedLens.title)
                            .font(AstirTypography.label)
                            .lineLimit(1)
                        Text(savedLens.detail)
                            .font(AstirTypography.metadata)
                            .foregroundStyle(brandMode.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(brandMode.accentText)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                .background(brandMode.raisedBackground)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("yourMap.prototype.savedLens.\(savedLens.id.uuidString)")
            .offset(x: contentOffset)
            .allowsHitTesting(
                restingOffset > -(YourMapPrototypeLensSwipePolicy.revealWidth / 2)
            )
            .zIndex(1)
            .highPriorityGesture(swipeGesture)
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .clipped()
        .accessibilityAction(named: "Delete lens", onDelete)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($dragTranslation) { value, translation, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                translation = value.translation.width
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let predictedOffset = restingOffset + value.predictedEndTranslation.width
                withAnimation(.easeOut(duration: 0.18)) {
                    restingOffset = YourMapPrototypeLensSwipePolicy.settledOffset(
                        for: predictedOffset
                    )
                }
            }
    }
}

private struct YourMapPrototypeCircleButton: View {
    @Environment(\.astirBrandMode) private var brandMode
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(brandMode.primaryText)
                .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                .astirGlassSurface(
                    cornerRadius: WanderTheme.tapMinimum / 2,
                    castsShadow: true
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct YourMapGeographyCard: View {
    @Environment(\.astirBrandMode) private var brandMode
    let cities: [YourMapPrototypeBreakdownItem]
    let countries: [YourMapPrototypeBreakdownItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false

    private var canExpand: Bool { max(cities.count, countries.count) > 5 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: WanderTheme.spacing4) {
                column("cities", items: cities, identifier: "city")
                column("countries", items: countries, identifier: "country")
            }
            .overlay {
                Rectangle()
                    .fill(brandMode.border.opacity(0.7))
                    .frame(width: 1)
                    .accessibilityHidden(true)
            }

            if canExpand {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Text(isExpanded ? "See less" : "See more")
                                .font(AstirTypography.metadata)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 25, height: 25)
                                .background(brandMode.recessedBackground, in: Circle())
                        }
                        .foregroundStyle(brandMode.secondaryText)
                        .frame(minWidth: WanderTheme.tapMinimum, minHeight: WanderTheme.tapMinimum)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? "Show top five cities and countries" : "Show top ten cities and countries")
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .accessibilityHint("Updates this section in place")
                    .accessibilityIdentifier("yourMap.prototype.geography.expand")
                }
                .padding(.top, WanderTheme.spacing1)
            }
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.top, WanderTheme.spacing4)
        .padding(.bottom, canExpand ? 6 : WanderTheme.spacing4)
        .background(brandMode.raisedBackground, in: RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .strokeBorder(brandMode.border)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("yourMap.prototype.citiesCountries")
        .onChange(of: canExpand) { _, canExpand in
            if !canExpand { isExpanded = false }
        }
    }

    private func column(_ title: String, items: [YourMapPrototypeBreakdownItem], identifier: String) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: WanderTheme.spacing1) {
                    Text(title).font(AstirTypography.cardTitle)
                    Spacer(minLength: 0)
                    Text(items.count.formatted()).font(AstirTypography.metadata.monospacedDigit())
                        .foregroundStyle(brandMode.secondaryText)
                }
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(title).font(AstirTypography.cardTitle)
                    Text(items.count.formatted()).font(AstirTypography.metadata.monospacedDigit())
                        .foregroundStyle(brandMode.secondaryText)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if items.isEmpty {
                Text("No \(title) yet")
                    .font(AstirTypography.metadata)
                    .foregroundStyle(brandMode.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 14) {
                    ForEach(items.prefix(isExpanded ? 10 : 5)) { item in
                        YourMapPrototypeBarRow(item: item, minimumFraction: 0)
                            .accessibilityLabel("\(item.title), \(Int((item.fraction * 100).rounded())) percent, \(item.count) places")
                            .accessibilityIdentifier("yourMap.prototype.\(identifier)Row.\(item.id)")
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct YourMapPrototypeBarRow: View {
    @Environment(\.astirBrandMode) private var brandMode
    let item: YourMapPrototypeBreakdownItem
    var minimumFraction = 0.03

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(item.title)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("\(Int((item.fraction * 100).rounded()))%")
                    .monospacedDigit()
                    .fixedSize()
            }
            .font(AstirTypography.metadata)
            GeometryReader { geometry in
                Capsule()
                    .fill(brandMode.recessedBackground)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(categoryColor(item.title, brandMode: brandMode))
                            .frame(width: geometry.size.width * max(item.fraction, minimumFraction))
                    }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.count) places")
    }
}

private struct YourMapPrototypeSparkline: View {
    @Environment(\.astirBrandMode) private var brandMode

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let points: [CGPoint] = [
                    CGPoint(x: 0, y: 24),
                    CGPoint(x: geometry.size.width * 0.18, y: 18),
                    CGPoint(x: geometry.size.width * 0.32, y: 21),
                    CGPoint(x: geometry.size.width * 0.48, y: 10),
                    CGPoint(x: geometry.size.width * 0.62, y: 14),
                    CGPoint(x: geometry.size.width * 0.78, y: 5),
                    CGPoint(x: geometry.size.width, y: 9)
                ]
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(brandMode.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private enum YourMapPrototypeRatingOption: String, CaseIterable, Identifiable {
    case any
    case fourPlus
    case fourPointFivePlus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: "Any"
        case .fourPlus: "4+ stars"
        case .fourPointFivePlus: "4.5+ stars"
        }
    }

    var minimum: Double? {
        switch self {
        case .any: nil
        case .fourPlus: 4
        case .fourPointFivePlus: 4.5
        }
    }
}

extension YourMapPrototypePlace {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private func categorySystemImage(_ category: String) -> String {
    switch category.lowercased() {
    case "coffee": "cup.and.saucer.fill"
    case "restaurants": "fork.knife"
    case "bars": "wineglass.fill"
    case "bakeries": "birthday.cake.fill"
    case "outdoors": "leaf.fill"
    default: "mappin"
    }
}

private func categoryColor(_ category: String, brandMode: AstirBrandMode) -> Color {
    switch category.lowercased() {
    case "coffee": brandMode.accent
    case "restaurants": brandMode.accent.opacity(0.82)
    case "bars": brandMode.primaryText.opacity(0.78)
    case "bakeries": brandMode.accent.opacity(0.62)
    case "outdoors": brandMode.secondaryText
    default: brandMode.secondaryText.opacity(0.72)
    }
}

#Preview("Your Map Prototype") {
    NavigationStack {
        YourMapPrototypeScreen(volume: .medium)
    }
}

#Preview("Your Map Prototype Empty") {
    NavigationStack {
        YourMapPrototypeScreen(volume: .empty)
    }
}
