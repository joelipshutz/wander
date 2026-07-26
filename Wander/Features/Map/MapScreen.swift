@preconcurrency import MapKit
import PhotosUI
import SwiftUI
import UIKit

struct MapScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var pushNotifications: PushNotificationManager
    @State private var selectedPlaceGroupKey: String?
    @State private var selectedSearchCandidateID: String?
    @State private var selectedMapFeature: MapFeature?
    @State private var ignoreNextMapFeatureClear = false
    @State private var ignoreNextMapTap = false
    @State private var lastMapPressPoint: CGPoint?
    @State private var mapSelectionRevision = 0
    @State private var mapSaveFlow: MapPlaceSaveContext?
    @State private var isPlaceProfilePresented: Bool
    @State private var mapQuery = ""
    @State private var mapSearchMessage: String?
    @State private var mapSearchCandidates: [PlaceCandidate] = []
    @State private var mapFeatureResolutionTask: Task<Void, Never>?
    @State private var typeaheadSuggestions: [MapSearchSuggestion] = []
    @State private var isLoadingTypeahead = false
    @State private var typeaheadTask: Task<Void, Never>?
    @State private var suppressedTypeaheadQuery: String?
    @State private var isSearchingMapKit = false
    @State private var mapSearchRevision: UInt64 = 0
    @State private var mapSearchTask: Task<Void, Never>?
    @State private var selectedFilters: Set<MapFilter> = [.you, .social, .been, .wanna]
    @State private var selectedSocialOwnerID: String?
    @State private var currentSearchRegion = Self.defaultRegion
    @State private var position: MapCameraPosition = .region(Self.defaultRegion)
    @State private var isRecenteringOnUser = false
    @State private var suppressNextQueryAutoSelection = false
    @State private var didResolveInitialCamera = false
    @State private var handlingNotificationRequestID: UUID?
    @State private var handledPresentationResetRequestID: UUID?
    @State private var mapSearchFocusRequestID: UUID?
    @FocusState private var isMapSearchFocused: Bool

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
    )
    private static let recenterCameraDistance: CLLocationDistance = 1_500
    private static let currentLocationTint = Color(uiColor: .systemBlue)

    private let initialPlaceQuery: String?
    private let presentationResetRequest: WanderPresentationResetRequest?
    private let searchLaunchRequest: WanderMapSearchLaunchRequest?
    private let onSearchLaunchRequestHandled: (UUID) -> Void

    private var baseVisiblePlaces: [VisiblePlace] {
        guard let mapPlaceFilters else { return [] }
        return store.visiblePlaces(filters: mapPlaceFilters)
    }

    init(
        initialPlaceQuery: String? = Self.resolvedInitialMapPlaceQuery(),
        startsExpanded: Bool = Self.resolvedInitialPlaceProfilePresentation(),
        presentationResetRequest: WanderPresentationResetRequest? = nil,
        searchLaunchRequest: WanderMapSearchLaunchRequest? = nil,
        onSearchLaunchRequestHandled: @escaping (UUID) -> Void = { _ in }
    ) {
        self.initialPlaceQuery = initialPlaceQuery
        self.presentationResetRequest = presentationResetRequest
        self.searchLaunchRequest = searchLaunchRequest
        self.onSearchLaunchRequestHandled = onSearchLaunchRequestHandled
        _isPlaceProfilePresented = State(initialValue: startsExpanded)
    }

    private var visiblePlaces: [VisiblePlace] {
        let places = baseVisiblePlaces
        let normalizedQuery = mapQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return places }

        return places.filter { visiblePlace in
            visiblePlace.place.canonicalName.lowercased().contains(normalizedQuery)
                || visiblePlace.effectiveCategoryDisplay.compactTitle.lowercased().contains(normalizedQuery)
                || (visiblePlace.place.locality?.lowercased().contains(normalizedQuery) ?? false)
                || visiblePlace.owner.displayName.lowercased().contains(normalizedQuery)
                || visiblePlace.owner.handle.lowercased().contains(normalizedQuery)
                || (visiblePlace.userPlace.note?.lowercased().contains(normalizedQuery) ?? false)
                || (visiblePlace.userPlace.ratingSignal?.lowercased().contains(normalizedQuery) ?? false)
                || (visiblePlace.recommendedScore.map(PlaceRating.averageDisplay)?.lowercased().contains(normalizedQuery) ?? false)
        }
    }

    private var visiblePlaceGroups: [VisiblePlaceGroup] {
        VisiblePlaceGrouping.groups(
            from: visiblePlaces,
            currentUserID: store.currentUser.id
        )
    }

    private var mapAnnotationPlaces: [VisiblePlace] {
        visiblePlaceGroups.map(\.primary)
    }

    private var visiblePlaceGroupKeys: [String] {
        visiblePlaceGroups.map(\.key)
    }

    private var mapPlaceFilters: PlaceFilters? {
        MapFilterSelection.placeFilters(
            selectedFilters: selectedFilters,
            selectedSocialOwnerID: selectedSocialOwnerID
        )
    }

    private var socialOwnerOptions: [MapSocialOwnerOption] {
        let socialPlaces = store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["social"]))
        var seen = Set<String>()
        return socialPlaces.compactMap { visiblePlace in
            let owner = visiblePlace.owner
            guard owner.id != store.currentUser.id, !seen.contains(owner.id) else { return nil }
            seen.insert(owner.id)
            return MapSocialOwnerOption(
                id: owner.id,
                displayName: owner.displayName,
                handle: owner.handle
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var selectedSocialOwner: MapSocialOwnerOption? {
        guard let selectedSocialOwnerID else { return nil }
        return socialOwnerOptions.first { $0.id == selectedSocialOwnerID }
    }

    private var selectedPlace: VisiblePlace? {
        guard let selectedPlaceGroupKey else { return nil }
        return visiblePlaceGroups.first { $0.key == selectedPlaceGroupKey }?.primary
    }

    private var selectedSearchCandidate: PlaceCandidate? {
        guard let selectedSearchCandidateID else { return nil }
        return mapSearchCandidates.first { $0.id == selectedSearchCandidateID }
    }

    private var hasSelectedProfile: Bool {
        selectedPlace != nil || selectedSearchCandidate != nil
    }

    private var mappableSearchCandidates: [PlaceCandidate] {
        mapSearchCandidates.filter { candidate in
            guard candidate.latitude != nil, candidate.longitude != nil else { return false }
            return !isNativeSelectedFeatureCandidate(candidate)
        }
    }

    private var currentViewport: MapViewport {
        MapViewport(minLatitude: 33.95, minLongitude: -118.45, maxLatitude: 34.2, maxLongitude: -118.12)
    }

    private var shouldShowTypeahead: Bool {
        let normalized = Self.normalized(mapQuery)
        return normalized.count >= 2
            && suppressedTypeaheadQuery != normalized
            && (isLoadingTypeahead || !typeaheadSuggestions.isEmpty)
    }

    var body: some View {
        let annotationGroups = visiblePlaceGroups.enumerated()
            .sorted { lhs, rhs in
                let lhsIsSelected = isSelectedMapRepresentative(lhs.element.primary)
                let rhsIsSelected = isSelectedMapRepresentative(rhs.element.primary)
                if lhsIsSelected != rhsIsSelected {
                    return !lhsIsSelected && rhsIsSelected
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position, selection: $selectedMapFeature) {
                        UserAnnotation()

                        ForEach(annotationGroups) { group in
                            Annotation(
                                group.primary.place.canonicalName,
                                coordinate: CLLocationCoordinate2D(
                                    latitude: group.primary.place.latitude,
                                    longitude: group.primary.place.longitude
                                )
                            ) {
                                Button {
                                    selectVisiblePlaceFromMapTap(group.primary)
                                } label: {
                                    MapPlaceMarker(
                                        visiblePlace: group.primary,
                                        saves: saveSummaries(for: group),
                                        currentUserID: store.currentUser.id,
                                        isSelected: isSelectedMapRepresentative(group.primary)
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(minWidth: 44, minHeight: 44)
                                .zIndex(isSelectedMapRepresentative(group.primary) ? 1 : 0)
                            }
                        }

                        ForEach(mappableSearchCandidates) { candidate in
                            if let latitude = candidate.latitude,
                               let longitude = candidate.longitude {
                                Annotation(
                                    candidate.name,
                                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                                ) {
                                    Button {
                                        selectSearchCandidateFromMapTap(candidate)
                                    } label: {
                                        SearchResultMarker(candidate: candidate, isSelected: selectedSearchCandidateID == candidate.id)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(minWidth: 44, minHeight: 44)
                                }
                            }
                        }
                    }
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted))
                    .mapFeatureSelectionDisabled { feature in
                        feature.kind != .pointOfInterest || Self.normalized(feature.title ?? "").isEmpty
                    }
                    .mapFeatureSelectionContent { _ in }
                    .modifier(HideNativeMapFeatureAccessory())
                    .tint(Self.currentLocationTint)
                    .ignoresSafeArea()
                    .onChange(of: selectedMapFeature) { _, feature in
                        handleMapFeatureSelection(feature)
                    }
                    .onMapCameraChange(frequency: .onEnd) { context in
                        currentSearchRegion = context.region
                    }
                    .onTapGesture(coordinateSpace: .local) { point in
                        handleMapTap(at: point, proxy: proxy)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { value in
                                lastMapPressPoint = value.location
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.48)
                            .onEnded { didComplete in
                                guard didComplete, let point = lastMapPressPoint else { return }
                                if handleMapLongPress(at: point, proxy: proxy) {
                                    ignoreNextMapTap = true
                                }
                                lastMapPressPoint = nil
                            }
                    )
                }

                VStack(spacing: 0) {
                    VStack(spacing: WanderTheme.spacing2) {
                        SearchBar(
                            query: $mapQuery,
                            isFocused: $isMapSearchFocused,
                            focusRequestID: mapSearchFocusRequestID,
                            onFocusRequestHandled: { requestID in
                                guard mapSearchFocusRequestID == requestID else { return }
                                mapSearchFocusRequestID = nil
                            },
                            onSubmit: submitMapSearch
                        )
                        if shouldShowTypeahead {
                            MapTypeaheadList(
                                suggestions: typeaheadSuggestions,
                                isLoading: isLoadingTypeahead,
                                onSelect: selectTypeaheadSuggestion,
                                onAdd: addTypeaheadSuggestion
                            )
                            .padding(.horizontal, WanderTheme.spacing3)
                        } else if let mapSearchMessage {
                            MapSearchMessage(text: mapSearchMessage)
                                .padding(.horizontal, WanderTheme.spacing3)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: WanderTheme.spacing1) {
                                ForEach(MapFilter.allCases) { filter in
                                    if filter == .social {
                                        MapSocialFilterMenu(
                                            isSelected: selectedFilters.contains(.social),
                                            selectedOwner: selectedSocialOwner,
                                            ownerOptions: socialOwnerOptions,
                                            showAll: showAllSocialPlaces,
                                            hideSocial: hideSocialPlaces,
                                            selectOwner: showSocialPlaces
                                        )
                                    } else {
                                        Button {
                                            toggle(filter)
                                        } label: {
                                            MapFilterChip(filter: filter, isSelected: selectedFilters.contains(filter))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, WanderTheme.spacing3)
                            .padding(.vertical, WanderTheme.spacing1)
                        }
                        .frame(height: 48)

                    }

                    Spacer()

                    if !isPlaceProfilePresented {
                        HStack {
                            Spacer()
                            RecenterButton(isLoading: isRecenteringOnUser) {
                                recenterOnUser()
                            }
                            .padding(.trailing, WanderTheme.spacing3)
                            .padding(.bottom, hasSelectedProfile ? 154 : WanderTheme.spacing2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaPadding(.top, WanderTheme.spacing2)

                selectedPlaceProfileSurface
            }
            .background(WanderTheme.canvasWarm.color)
            .onAppear {
                resolveInitialSelection()
            }
            .task {
                await centerMapOnCurrentCityIfNeeded()
            }
            .task(id: presentationResetRequest?.id) {
                handlePresentationResetRequest(presentationResetRequest)
            }
            .task(id: searchLaunchRequest?.id) {
                await handleMapSearchLaunchRequest(searchLaunchRequest)
            }
            .task {
                await store.refreshRemoteSocialSurfaces(in: currentViewport, backend: backend)
                if auth.isSignedIn {
                    await store.refreshSharedVisitInbox(backend: backend)
                }
                resolveInitialSelection()
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                guard isSignedIn else { return }
                Task {
                    await store.refreshRemoteSocialSurfaces(in: currentViewport, backend: backend)
                    await store.refreshSharedVisitInbox(backend: backend)
                    await handleNotificationRoute(pushNotifications.navigationRequest)
                    resolveInitialSelection()
                }
            }
            .onChange(of: visiblePlaceGroupKeys) { _, keys in
                if let current = selectedPlaceGroupKey, !keys.contains(current) {
                    selectedPlaceGroupKey = nil
                    isPlaceProfilePresented = false
                }
                resolveInitialSelection()
            }
            .onChange(of: mapQuery) { _, _ in
                let shouldSuppressAutoSelection = suppressNextQueryAutoSelection
                handleMapQueryChange()
                if shouldSuppressAutoSelection {
                    suppressNextQueryAutoSelection = false
                    return
                }
                if let firstGroupKey = visiblePlaceGroupKeys.first,
                   !visiblePlaceGroupKeys.contains(selectedPlaceGroupKey ?? "") {
                    selectedPlaceGroupKey = firstGroupKey
                    isPlaceProfilePresented = false
                }
            }
            .onDisappear {
                typeaheadTask?.cancel()
                mapFeatureResolutionTask?.cancel()
                mapSearchTask?.cancel()
            }
            .sheet(item: $mapSaveFlow, onDismiss: {
                store.saveFlowDidDismiss(.saveSheet)
            }) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveMapFlowSubmission(submission)
                } onRemove: { context in
                    await removeMapSave(context)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(isPresented: placeProfileDestinationBinding) {
                selectedPlaceProfileDestination
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await handleNotificationRoute(pushNotifications.navigationRequest)
        }
        .onChange(of: pushNotifications.navigationRequest) { _, request in
            Task {
                await handleNotificationRoute(request)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await handleNotificationRoute(pushNotifications.navigationRequest)
            }
        }
    }

    private func handleNotificationRoute(_ request: NotificationNavigationRequest?) async {
        guard let request,
              auth.isSignedIn,
              handlingNotificationRequestID != request.id
        else { return }
        handlingNotificationRequestID = request.id
        defer {
            if handlingNotificationRequestID == request.id {
                handlingNotificationRequestID = nil
            }
        }

        switch request.destination {
        case .place(let placeID):
            await openNotificationPlace(placeID, requestID: request.id)
        case .sharedVisit(let participantID, let generation):
            let resolution = await resolveSharedVisitDestinationWithRetry(
                participantID: participantID,
                generation: generation
            )
            guard case .resolved(let destination) = resolution else {
                if resolution == .unavailable {
                    mapSearchMessage = "That shared check-in is no longer available."
                    pushNotifications.consumeNavigationRequest(id: request.id)
                } else {
                    mapSearchMessage = "Could not open that shared check-in yet. It will retry when the app becomes active."
                }
                return
            }

            if destination.status == SharedVisitParticipantStatus.pending.rawValue {
                let invitation = await sharedVisitContextWithRetry(
                    participantID: participantID,
                    generation: destination.currentGeneration
                )
                guard let invitation else {
                    mapSearchMessage = "Could not open that shared check-in yet. It will retry when the app becomes active."
                    return
                }
                mapSaveFlow = .sharedVisit(invitation, defaultVisibility: store.effectiveDefaultVisibility)
                pushNotifications.consumeNavigationRequest(id: request.id)
            } else if destination.status == SharedVisitParticipantStatus.accepted.rawValue {
                await openNotificationPlace(destination.placeID, requestID: request.id)
            } else {
                mapSearchMessage = "That shared check-in is no longer available."
                pushNotifications.consumeNavigationRequest(id: request.id)
            }
        default:
            return
        }
    }

    private func resolveSharedVisitDestinationWithRetry(
        participantID: String,
        generation: Int
    ) async -> SharedVisitDestinationResolution {
        for attempt in 0..<3 {
            let resolution = await store.resolveSharedVisitDestination(
                participantID: participantID,
                generation: generation,
                backend: backend
            )
            if resolution != .retryableFailure {
                return resolution
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
            }
        }
        return .retryableFailure
    }

    private func sharedVisitContextWithRetry(
        participantID: String,
        generation: Int
    ) async -> SharedVisitInvitation? {
        for attempt in 0..<3 {
            if let invitation = await store.refreshSharedVisitContext(
                participantID: participantID,
                generation: generation,
                backend: backend
            ) {
                return invitation
            }
            await store.refreshSharedVisitInbox(backend: backend)
            if let invitation = store.sharedVisitInvitations.first(where: {
                $0.participantID == participantID && $0.invitationGeneration == generation
            }) {
                return invitation
            }
            if attempt < 2 {
                try? await Task.sleep(for: .milliseconds(350 * (attempt + 1)))
            }
        }
        return nil
    }

    private func openNotificationPlace(_ placeID: String, requestID: UUID) async {

        let notificationLookupViewport = MapViewport(
            minLatitude: -90,
            minLongitude: -180,
            maxLatitude: 90,
            maxLongitude: 180
        )
        await store.refreshRemoteSocialSurfaces(in: notificationLookupViewport, backend: backend)
        guard let visiblePlace = store.visiblePlaces().first(where: {
            $0.place.id == placeID || $0.place.localID == placeID || $0.place.serverID == placeID
        }) else {
            mapSearchMessage = "That place is not available on your map."
            pushNotifications.consumeNavigationRequest(id: requestID)
            return
        }

        selectedFilters = [.you, .social, .been, .wanna]
        selectedSocialOwnerID = nil
        mapQuery = ""
        selectVisiblePlace(visiblePlace)
        isPlaceProfilePresented = false
        didResolveInitialCamera = true
        let notificationRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        position = .region(notificationRegion)
        currentSearchRegion = notificationRegion
        pushNotifications.consumeNavigationRequest(id: requestID)
    }

    private func toggle(_ filter: MapFilter) {
        if selectedFilters.contains(filter) {
            selectedFilters.remove(filter)
            if filter == .social {
                selectedSocialOwnerID = nil
            }
        } else {
            selectedFilters.insert(filter)
        }
    }

    private func showAllSocialPlaces() {
        selectedFilters.insert(.social)
        selectedSocialOwnerID = nil
    }

    private func hideSocialPlaces() {
        selectedFilters.remove(.social)
        selectedSocialOwnerID = nil
    }

    private func showSocialPlaces(for ownerID: String) {
        selectedFilters.insert(.social)
        selectedSocialOwnerID = ownerID
    }

    private func clearMapSelection() {
        mapFeatureResolutionTask?.cancel()
        mapFeatureResolutionTask = nil
        selectedMapFeature = nil
        selectedPlaceGroupKey = nil
        selectedSearchCandidateID = nil
        isPlaceProfilePresented = false
    }

    private func clearMapSelectionAndSearch() {
        mapSelectionRevision += 1
        mapFeatureResolutionTask?.cancel()
        mapFeatureResolutionTask = nil
        clearSearchTextForMapInteraction()
        selectedPlaceGroupKey = nil
        selectedSearchCandidateID = nil
        mapSearchCandidates = []
        mapSearchMessage = nil
        isPlaceProfilePresented = false
    }

    private func clearNativeMapFeatureSelection() {
        mapFeatureResolutionTask?.cancel()
        mapFeatureResolutionTask = nil

        guard selectedMapFeature != nil else { return }
        ignoreNextMapFeatureClear = true
        selectedMapFeature = nil
    }

    private func clearSearchTextForMapInteraction() {
        typeaheadTask?.cancel()
        typeaheadTask = nil
        typeaheadSuggestions = []
        isLoadingTypeahead = false
        suppressedTypeaheadQuery = ""

        if !mapQuery.isEmpty {
            suppressNextQueryAutoSelection = true
            mapQuery = ""
        }

        mapSearchMessage = nil
    }

    private func selectVisiblePlaceFromMapTap(_ visiblePlace: VisiblePlace) {
        mapSelectionRevision += 1
        clearNativeMapFeatureSelection()
        clearSearchTextForMapInteraction()
        selectVisiblePlace(visiblePlace)
        selectedSearchCandidateID = nil
        mapSearchCandidates = []
        isPlaceProfilePresented = false
    }

    private func selectSearchCandidateFromMapTap(_ candidate: PlaceCandidate) {
        mapSelectionRevision += 1
        clearNativeMapFeatureSelection()
        clearSearchTextForMapInteraction()
        mapSearchCandidates = [candidate]
        selectedSearchCandidateID = candidate.id
        selectedPlaceGroupKey = nil
        isPlaceProfilePresented = false
    }

    private func handleMapTap(at point: CGPoint, proxy: MapProxy) {
        if ignoreNextMapTap {
            ignoreNextMapTap = false
            return
        }
        guard !isTapNearSelectableMarker(point, proxy: proxy) else { return }

        let revision = mapSelectionRevision
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard revision == mapSelectionRevision,
                  selectedMapFeature == nil
            else { return }

            clearMapSelectionAndSearch()
        }
    }

    private func handleMapLongPress(at point: CGPoint, proxy: MapProxy) -> Bool {
        guard !isTapNearSelectableMarker(point, proxy: proxy),
              let coordinate = proxy.convert(point, from: .local),
              CLLocationCoordinate2DIsValid(coordinate)
        else { return false }

        let candidate = Self.coordinateCandidate(at: coordinate)
        mapSelectionRevision += 1
        clearNativeMapFeatureSelection()
        clearSearchTextForMapInteraction()
        mapSearchCandidates = [candidate]
        selectedPlaceGroupKey = nil
        selectedSearchCandidateID = candidate.id
        isPlaceProfilePresented = false
        mapSearchMessage = "Dropped pin. Tap + to add it."
        return true
    }

    private func isTapNearSelectableMarker(_ point: CGPoint, proxy: MapProxy) -> Bool {
        let savedPlaceCoordinates = mapAnnotationPlaces.map { visiblePlace in
            CLLocationCoordinate2D(latitude: visiblePlace.place.latitude, longitude: visiblePlace.place.longitude)
        }
        let searchCandidateCoordinates = mappableSearchCandidates.compactMap { candidate -> CLLocationCoordinate2D? in
            guard let latitude = candidate.latitude,
                  let longitude = candidate.longitude
            else { return nil }

            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let markerPoints = (savedPlaceCoordinates + searchCandidateCoordinates).compactMap { markerCoordinate in
            proxy.convert(markerCoordinate, to: .local)
        }

        return MapHitTesting.isScreenPoint(point, nearAny: markerPoints)
    }

    private func resolveInitialSelection() {
        guard selectedPlaceGroupKey == nil,
              let initialPlaceQuery
        else { return }

        let normalized = initialPlaceQuery.lowercased()
        guard let initialPlace = visiblePlaces.first(where: { visiblePlace in
            visiblePlace.id.lowercased().contains(normalized)
                || visiblePlace.place.id.lowercased().contains(normalized)
                || visiblePlace.place.canonicalName.lowercased().contains(normalized)
        }) else { return }

        selectVisiblePlace(initialPlace)
        center(on: initialPlace)
        didResolveInitialCamera = true
    }

    private func centerMapOnCurrentCityIfNeeded() async {
        guard !didResolveInitialCamera,
              initialPlaceQuery == nil
        else { return }

        let coordinate = await currentUserCoordinate()
        guard !Task.isCancelled,
              !didResolveInitialCamera,
              initialPlaceQuery == nil
        else { return }

        didResolveInitialCamera = true
        guard let coordinate else { return }

        let region = Self.initialCityRegion(
            center: CLLocationCoordinate2D(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        )
        position = .region(region)
        currentSearchRegion = region
    }

    private func savers(for selectedPlace: VisiblePlace) -> [LocalProfile] {
        saveSummaries(for: selectedPlace).map(\.visiblePlace.owner)
    }

    private func isSelectedMapRepresentative(_ visiblePlace: VisiblePlace) -> Bool {
        guard let selectedPlaceGroupKey else { return false }
        return VisiblePlaceGrouping.matchingGroup(
            for: visiblePlace,
            in: visiblePlaces,
            currentUserID: store.currentUser.id
        )?.key == selectedPlaceGroupKey
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        guard let group = VisiblePlaceGrouping.matchingGroup(
            for: selectedPlace,
            in: visiblePlaces,
            currentUserID: store.currentUser.id
        ) else {
            return [
                PlaceSaveSummary(visiblePlace: selectedPlace, attributes: selectedPlace.attributes)
            ]
        }
        return saveSummaries(for: group)
    }

    private func saveSummaries(for group: VisiblePlaceGroup) -> [PlaceSaveSummary] {
        group.places.map { visiblePlace in
            PlaceSaveSummary(visiblePlace: visiblePlace, attributes: visiblePlace.attributes)
        }
    }

    private func saveSummaries(for candidate: PlaceCandidate) -> [PlaceSaveSummary] {
        guard let matchingPlace = visiblePlace(matching: candidate) else { return [] }
        return saveSummaries(for: matchingPlace)
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
        }
    }

    private func selectVisiblePlace(_ visiblePlace: VisiblePlace) {
        selectedPlaceGroupKey = VisiblePlaceGrouping.matchingGroup(
            for: visiblePlace,
            in: visiblePlaces,
            currentUserID: store.currentUser.id
        )?.key ?? VisiblePlaceGrouping.key(for: visiblePlace)
    }

    private func selectSavedResult(_ result: SaveResult) {
        guard let visiblePlace = store.visiblePlaces().first(where: { $0.userPlace.id == result.userPlaceID }) else {
            return
        }

        selectVisiblePlace(visiblePlace)
    }

    private var placeProfileDestinationBinding: Binding<Bool> {
        Binding(
            get: {
                isPlaceProfilePresented && hasSelectedProfile
            },
            set: { isPresented in
                if !isPresented {
                    isPlaceProfilePresented = false
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceProfileSurface: some View {
        if let selectedSearchCandidate {
            PlaceProfileMapSurface(
                place: PlaceSheetPlace(candidate: selectedSearchCandidate),
                saves: saveSummaries(for: selectedSearchCandidate),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: .add,
                onOpen: openSelectedPlaceProfile
            ) {
                mapSaveFlow = MapPlaceSaveContext.addCandidate(
                    selectedSearchCandidate,
                    sourceType: .manual,
                    defaultVisibility: store.effectiveDefaultVisibility
                )
            }
            .zIndex(30)
        } else if let selectedPlace {
            PlaceProfileMapSurface(
                place: PlaceSheetPlace(visiblePlace: selectedPlace),
                saves: saveSummaries(for: selectedPlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: action(for: selectedPlace),
                onOpen: openSelectedPlaceProfile
            ) {
                performAction(for: selectedPlace)
            }
            .zIndex(30)
        }
    }

    @ViewBuilder
    private var selectedPlaceProfileDestination: some View {
        if let selectedSearchCandidate {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(candidate: selectedSearchCandidate),
                saves: saveSummaries(for: selectedSearchCandidate),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: .add,
                onBack: {
                    isPlaceProfilePresented = false
                },
                onAction: {
                    dismissPlaceProfileThen {
                        mapSaveFlow = MapPlaceSaveContext.addCandidate(
                            selectedSearchCandidate,
                            sourceType: .manual,
                            defaultVisibility: store.defaultVisibility
                        )
                    }
                }
            )
        } else if let selectedPlace {
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: selectedPlace),
                saves: saveSummaries(for: selectedPlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: action(for: selectedPlace),
                onBack: {
                    isPlaceProfilePresented = false
                },
                onAction: {
                    dismissPlaceProfileThen {
                        performAction(for: selectedPlace)
                    }
                }
            )
        }
    }

    private func openSelectedPlaceProfile() {
        guard hasSelectedProfile else { return }
        isPlaceProfilePresented = true
    }

    private func dismissPlaceProfileThen(_ action: @MainActor @escaping () -> Void) {
        isPlaceProfilePresented = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            action()
        }
    }

    private func submitMapSearch() {
        dismissKeyboard()
        suppressedTypeaheadQuery = Self.normalized(mapQuery)
        typeaheadTask?.cancel()
        typeaheadSuggestions = []
        isLoadingTypeahead = false
        mapSearchTask?.cancel()

        let requestedQuery = mapQuery
        let requestRevision = beginMapSearchRequest()
        mapSearchTask = Task { @MainActor in
            await runMapSearch(
                requestedQuery: requestedQuery,
                requestRevision: requestRevision
            )
            if requestRevision == mapSearchRevision {
                mapSearchTask = nil
            }
        }
    }

    @MainActor
    private func handlePresentationResetRequest(_ request: WanderPresentationResetRequest?) {
        guard let request,
              handledPresentationResetRequestID != request.id
        else { return }

        handledPresentationResetRequestID = request.id
        resetMapPresentations()
    }

    @MainActor
    private func resetMapPresentations() {
        invalidateMapSearchRequest()
        mapSearchFocusRequestID = nil
        isMapSearchFocused = false
        mapSelectionRevision += 1
        mapSaveFlow = nil
        isPlaceProfilePresented = false
        selectedPlaceGroupKey = nil
        selectedSearchCandidateID = nil
        clearNativeMapFeatureSelection()
    }

    @MainActor
    private func handleMapSearchLaunchRequest(_ request: WanderMapSearchLaunchRequest?) async {
        guard let request else { return }
        defer {
            if !Task.isCancelled {
                onSearchLaunchRequestHandled(request.id)
            }
        }

        handlePresentationResetRequest(presentationResetRequest)
        resetMapPresentations()
        mapSearchCandidates = []
        mapSearchMessage = nil
        typeaheadTask?.cancel()
        typeaheadSuggestions = []
        isLoadingTypeahead = false

        guard let query = request.query else {
            suppressedTypeaheadQuery = nil
            if !mapQuery.isEmpty {
                suppressNextQueryAutoSelection = true
                mapQuery = ""
            }
            mapSearchFocusRequestID = request.id
            return
        }

        await centerMapOnCurrentCityIfNeeded()
        guard !Task.isCancelled else { return }
        isMapSearchFocused = false
        suppressedTypeaheadQuery = Self.normalized(query)
        suppressNextQueryAutoSelection = true
        mapQuery = query
        let requestRevision = beginMapSearchRequest()
        await runMapSearch(
            requestedQuery: query,
            requestRevision: requestRevision
        )
    }

    @MainActor
    private func runMapSearch(
        requestedQuery: String,
        requestRevision: UInt64
    ) async {
        let query = requestedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            guard Self.shouldApplyMapSearchCompletion(
                requestRevision: requestRevision,
                currentRevision: mapSearchRevision,
                requestedQuery: requestedQuery,
                currentQuery: mapQuery,
                isCancelled: Task.isCancelled
            ) else {
                return
            }
            mapSearchMessage = nil
            mapSearchCandidates = []
            selectedSearchCandidateID = nil
            return
        }

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
        defer {
            if requestRevision == mapSearchRevision {
                isSearchingMapKit = false
            }
        }

        do {
            let candidates = try await mapKitCandidates(for: query)
            guard Self.shouldApplyMapSearchCompletion(
                requestRevision: requestRevision,
                currentRevision: mapSearchRevision,
                requestedQuery: requestedQuery,
                currentQuery: mapQuery,
                isCancelled: Task.isCancelled
            ) else {
                return
            }
            mapSearchCandidates = candidates.filter { !isAlreadyVisible(candidate: $0) }

            if let firstVisiblePlace = visiblePlaces.first {
                selectVisiblePlace(firstVisiblePlace)
                selectedSearchCandidateID = nil
                mapSearchMessage = mapSearchCandidates.isEmpty ? nil : "Also showing new map results."
            } else if let firstCandidate = mapSearchCandidates.first {
                selectedPlaceGroupKey = nil
                selectedSearchCandidateID = firstCandidate.id
                center(on: firstCandidate)
                mapSearchMessage = "Map result. Tap + to add it."
            } else {
                selectedPlaceGroupKey = nil
                selectedSearchCandidateID = nil
                mapSearchMessage = "No places on your map or map results found."
            }
        } catch {
            guard Self.shouldApplyMapSearchCompletion(
                requestRevision: requestRevision,
                currentRevision: mapSearchRevision,
                requestedQuery: requestedQuery,
                currentQuery: mapQuery,
                isCancelled: Task.isCancelled
            ) else {
                return
            }
            mapSearchCandidates = []
            mapSearchMessage = visiblePlaces.isEmpty
                ? "No places on your map match yet. Try a more specific search."
                : nil
        }
    }

    private func beginMapSearchRequest() -> UInt64 {
        mapSearchRevision &+= 1
        return mapSearchRevision
    }

    private func invalidateMapSearchRequest() {
        mapSearchTask?.cancel()
        mapSearchTask = nil
        mapSearchRevision &+= 1
        isSearchingMapKit = false
    }

    static func shouldApplyMapSearchCompletion(
        requestRevision: UInt64,
        currentRevision: UInt64,
        requestedQuery: String,
        currentQuery: String,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && requestRevision == currentRevision
            && normalized(requestedQuery) == normalized(currentQuery)
    }

    private func handleMapFeatureSelection(_ feature: MapFeature?) {
        guard let feature else {
            if ignoreNextMapFeatureClear {
                ignoreNextMapFeatureClear = false
            } else {
                clearMapSelectionAndSearch()
            }
            return
        }

        ignoreNextMapFeatureClear = false
        mapSelectionRevision += 1
        resolveSelectedMapFeature(feature)
    }

    private func resolveSelectedMapFeature(_ feature: MapFeature) {
        guard feature.kind == .pointOfInterest,
              let fallbackCandidate = placeCandidate(from: feature)
        else {
            clearMapSelection()
            return
        }

        mapFeatureResolutionTask?.cancel()
        mapSearchMessage = "Loading place..."

        let request = MKMapItemRequest(feature: feature)
        let origin = currentMapCenterLocation()
        mapFeatureResolutionTask = Task { @MainActor in
            do {
                let mapItem = try await request.mapItem
                guard !Task.isCancelled else { return }
                let candidate = mapKitCandidates(from: [mapItem], query: nil, origin: origin, limit: 1).first ?? fallbackCandidate
                selectMapFeatureCandidate(candidate)
            } catch {
                guard !Task.isCancelled else { return }
                selectMapFeatureCandidate(fallbackCandidate)
            }
        }
    }

    private func selectMapFeatureCandidate(_ candidate: PlaceCandidate) {
        mapFeatureResolutionTask = nil

        if let visiblePlace = visiblePlace(matching: candidate) {
            clearNativeMapFeatureSelection()
            clearSearchTextForMapInteraction()
            selectVisiblePlace(visiblePlace)
            selectedSearchCandidateID = nil
            mapSearchCandidates = []
            isPlaceProfilePresented = false
            mapSearchMessage = nil
            return
        }

        clearSearchTextForMapInteraction()
        mapSearchCandidates = [candidate]
        selectedPlaceGroupKey = nil
        selectedSearchCandidateID = candidate.id
        isPlaceProfilePresented = false
        mapSearchMessage = "Map place. Tap + to add it."
    }

    private func isNativeSelectedFeatureCandidate(_ candidate: PlaceCandidate) -> Bool {
        guard selectedMapFeature != nil,
              selectedSearchCandidateID == candidate.id
        else { return false }

        return true
    }

    private func mapKitCandidates(for query: String, limit: Int = 8) async throws -> [PlaceCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = currentSearchRegion
        request.resultTypes = [.pointOfInterest, .address]

        let response = try await MKLocalSearch(request: request).start()
        let origin = await searchOriginLocation()
        return mapKitCandidates(from: response.mapItems, query: query, origin: origin, limit: limit)
    }

    private func mapKitCandidates(from items: [MKMapItem], query: String?, origin: CLLocation, limit: Int) -> [PlaceCandidate] {
        var seen = Set<String>()
        return items
            .sorted {
                mapSearchRankingScore(for: $0, query: query, origin: origin)
                    > mapSearchRankingScore(for: $1, query: query, origin: origin)
            }
            .compactMap { item in
            guard let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty,
                  CLLocationCoordinate2DIsValid(item.placemark.coordinate)
            else { return nil }

            let duplicateKey = mapKitDuplicateKey(for: item, name: name)
            guard !seen.contains(duplicateKey) else { return nil }
            seen.insert(duplicateKey)

            let sourceID = mapKitSourceID(for: item, name: name)
            return PlaceCandidate(
                id: sourceID,
                name: name,
                category: category(for: item),
                categorySource: PlaceCategorySource.provider.rawValue,
                categoryConfidence: item.pointOfInterestCategory == nil ? 0.72 : 0.86,
                rawProviderType: item.pointOfInterestCategory?.rawValue,
                address: address(for: item.placemark),
                locality: item.placemark.locality,
                region: item.placemark.administrativeArea,
                country: item.placemark.country,
                latitude: item.placemark.coordinate.latitude,
                longitude: item.placemark.coordinate.longitude,
                sourceProvider: "mapkit",
                sourceProviderPlaceID: sourceID,
                distanceMeters: distanceMeters(from: origin, to: item),
                websiteURLString: item.url?.absoluteString,
                phoneNumber: item.phoneNumber,
                timeZoneIdentifier: item.timeZone?.identifier,
                confidence: item.pointOfInterestCategory == nil ? 0.72 : 0.86
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    private func action(for visiblePlace: VisiblePlace) -> PlaceSheetAction {
        PlaceSheetAction.topLevelAction(currentUserSave: currentUserSave(matching: visiblePlace))
    }

    private func performAction(for visiblePlace: VisiblePlace) {
        switch action(for: visiblePlace) {
        case .add:
            mapSaveFlow = MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.effectiveDefaultVisibility,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        case .addVisit:
            let placeToEdit = currentUserSave(matching: visiblePlace) ?? visiblePlace
            mapSaveFlow = MapPlaceSaveContext.addVisitVisiblePlace(
                placeToEdit,
                attributes: store.attributes(for: placeToEdit.userPlace.id),
                latestVisit: store.visits(for: placeToEdit.userPlace.id).first
            )
        case .choose, .none:
            break
        }
    }

    private func isSavedByCurrentUser(_ visiblePlace: VisiblePlace) -> Bool {
        currentUserSave(matching: visiblePlace) != nil
    }

    private func currentUserSave(matching visiblePlace: VisiblePlace) -> VisiblePlace? {
        return store.currentUserVisiblePlaces.first { mine in
            VisiblePlaceGrouping.matches(mine, visiblePlace)
        }
    }

    @MainActor
    private func saveMapFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let visitBackend = auth.isSignedIn ? backend : nil
        switch submission.context.mode {
        case .add(let sourceType):
            if sourceType == .socialSave, !auth.isSignedIn {
                mapSaveFlow = nil
                auth.presentGate(for: .socialSave)
                return nil
            }

            guard let result = await persistNewPlaceSaveSubmission(
                submission,
                store: store,
                backend: visitBackend
            ) else { return nil }
            let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
            clearNativeMapFeatureSelection()
            selectedSearchCandidateID = nil
            selectSavedResult(result)
            mapSearchCandidates.removeAll { $0.id == submission.candidate.id }
            showMapSaveFeedback(
                SaveSyncFeedback(syncState: result.syncState, canSignIn: !auth.isSignedIn),
                successMessage: "Added to your map."
            )

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            await createSharedVisitInvitesIfNeeded(
                inviteeUserIDs: submission.inviteeUserIDs,
                sourceVisit: targetVisit
            )
            await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems)
            return result
        case .sharedVisit(let invitation):
            return await acceptSharedVisit(invitation, submission: submission)
        case .addVisit, .editVisit, .editWant:
            let (result, targetVisit) = await persistScopedVisitOrWantSubmission(
                submission,
                store: store,
                backend: auth.isSignedIn ? backend : nil
            )
            guard let result else { return nil }
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            if submission.reconcilesSharedVisitInvitees {
                await reconcileSharedVisitInvitees(submission, sourceVisit: targetVisit)
            } else {
                await createSharedVisitInvitesIfNeeded(
                    inviteeUserIDs: submission.inviteeUserIDs,
                    sourceVisit: targetVisit
                )
            }
            selectedSearchCandidateID = nil
            selectSavedResult(result)
            showMapSaveFeedback(
                SaveSyncFeedback(syncState: result.syncState, canSignIn: !auth.isSignedIn),
                successMessage: scopedSaveMessage(for: submission.context, status: submission.status)
            )

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems)
            return result
        }
    }

    private func scopedSaveMessage(for context: MapPlaceSaveContext, status: PlaceStatus) -> String {
        switch context.mode {
        case .add:
            status == .been ? "Checked in." : "Added to Wanna."
        case .addVisit:
            "Checked in again."
        case .sharedVisit:
            "Shared check-in is on your map."
        case .editVisit:
            "Check-in updated."
        case .editWant:
            "Want updated."
        }
    }

    private func createSharedVisitInvitesIfNeeded(
        inviteeUserIDs: [String],
        sourceVisit: LocalPlaceVisit?
    ) async {
        guard !inviteeUserIDs.isEmpty, auth.isSignedIn, let sourceVisit else { return }
        store.queueSharedVisitInvites(sourceVisitID: sourceVisit.id, inviteeUserIDs: inviteeUserIDs)
        _ = await store.retryPendingVisitPhotoUploads(backend: backend)
        _ = await store.retryPendingSharedVisitInvites(backend: backend)
        if store.pendingSharedVisitInvites.contains(where: {
            $0.ownerUserID == store.currentUser.id && $0.sourceVisitID == sourceVisit.id
        }) {
            mapSearchMessage = "Checked in. Friend invites are queued and will retry automatically."
        }
    }

    private func reconcileSharedVisitInvitees(
        _ submission: MapPlaceSaveSubmission,
        sourceVisit: LocalPlaceVisit?
    ) async {
        guard auth.isSignedIn, let sourceVisit else { return }
        store.queueSharedVisitInviteeReconciliation(
            sourceVisitID: sourceVisit.id,
            inviteeUserIDs: submission.inviteeUserIDs
        )
        _ = await store.retryPendingSharedVisitInvites(backend: backend)
        if store.pendingSharedVisitInvites.contains(where: {
            $0.ownerUserID == store.currentUser.id && $0.sourceVisitID == sourceVisit.id
        }) {
            mapSearchMessage = "Check-in updated. Friend changes are queued and will retry automatically."
        }
    }

    private func acceptSharedVisit(
        _ invitation: SharedVisitInvitation,
        submission: MapPlaceSaveSubmission
    ) async -> SaveResult? {
        guard case .signedIn(let acceptingSession) = auth.state,
              store.currentUser.id == acceptingSession.userID
        else {
            auth.presentGate(for: .syncPlace)
            return nil
        }

        let identifiers = SharedVisitAcceptanceIdentifiers.deterministic(
            participantID: invitation.participantID,
            generation: invitation.invitationGeneration
        )
        let inheritedPhotoPayloads: [(
            sourcePhotoID: String,
            attachment: MapPlaceSavePhotoAttachment,
            data: Data
        )] = submission.photoAttachments.compactMap { attachment in
            guard let sourcePhotoID = attachment.sourcePhotoID,
                  let data = attachment.data()
            else { return nil }
            return (sourcePhotoID, attachment, data)
        }
        let requestedInheritedPhotoCount = submission.photoAttachments.filter {
            $0.sourcePhotoID != nil
        }.count
        let draft = SharedVisitAcceptanceDraft(
            participantID: invitation.participantID,
            invitationGeneration: invitation.invitationGeneration,
            snapshotRevision: invitation.snapshotRevision,
            operationID: identifiers.operationID,
            userPlaceID: identifiers.userPlaceID,
            visitID: identifiers.visitID,
            visibility: submission.visibility,
            visitedAt: invitation.visitedAt,
            note: submission.note,
            ratingScore: submission.ratingScore,
            attributes: submission.attributes,
            selectedPhotoIDs: inheritedPhotoPayloads.map(\.sourcePhotoID)
        )

        do {
            let result = try await backend.acceptSharedVisit(draft)
            guard case .signedIn(let currentSession) = auth.state,
                  currentSession.userID == acceptingSession.userID,
                  store.currentUser.id == acceptingSession.userID
            else { return nil }
            let visit = store.applySharedVisitAcceptance(
                invitation: invitation,
                draft: draft,
                result: result
            )
            var photoCopyFailed = inheritedPhotoPayloads.count != requestedInheritedPhotoCount
            for copy in result.photoCopies {
                guard case .signedIn(let currentSession) = auth.state,
                      currentSession.userID == acceptingSession.userID,
                      store.currentUser.id == acceptingSession.userID
                else { return nil }
                guard let payload = inheritedPhotoPayloads.first(where: {
                    $0.sourcePhotoID == copy.sourcePhotoID
                }) else {
                    photoCopyFailed = true
                    continue
                }

                store.recordAcceptedSharedVisitPhoto(
                    copy: copy,
                    visitID: visit.id,
                    localAssetRef: payload.attachment.localAssetRef,
                    byteSize: payload.attachment.byteSize,
                    width: payload.attachment.width,
                    height: payload.attachment.height,
                    uploaded: false
                )
                do {
                    try await backend.uploadSharedVisitPhoto(
                        bucket: copy.destinationBucket,
                        path: copy.destinationPath,
                        data: payload.data,
                        contentType: copy.contentType
                    )
                    guard case .signedIn(let currentSession) = auth.state,
                          currentSession.userID == acceptingSession.userID,
                          store.currentUser.id == acceptingSession.userID
                    else { return nil }
                    try await backend.markSharedVisitPhotoUploaded(photoID: copy.destinationPhotoID)
                    store.recordAcceptedSharedVisitPhoto(
                        copy: copy,
                        visitID: visit.id,
                        localAssetRef: payload.attachment.localAssetRef,
                        byteSize: payload.attachment.byteSize,
                        width: payload.attachment.width,
                        height: payload.attachment.height,
                        uploaded: true
                    )
                } catch {
                    photoCopyFailed = true
                }
            }
            if photoCopyFailed {
                mapSearchMessage = "Checked in. One shared photo will retry when you reopen rec.me."
            }
            await store.refreshSharedVisitInbox(backend: backend)
            await store.refreshRemoteVisiblePlaces(backend: backend)
            return SaveResult(userPlaceID: result.userPlaceID, syncState: .synced)
        } catch {
            mapSearchMessage = "That shared check-in changed before it reached your map. Open the invitation again."
            return nil
        }
    }

    @MainActor
    private func removeMapSave(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            guard await store.deleteVisit(visitID: visit.id, backend: auth.isSignedIn ? backend : nil) else {
                return false
            }
            showTransientMapSearchMessage("Check-in deleted.")
            return true
        case .editWant(let visiblePlace):
            let removal = await store.removeSave(
                userPlaceID: visiblePlace.userPlace.id,
                backend: auth.isSignedIn ? backend : nil
            )
            guard removal != nil else {
                return false
            }
            await pushNotifications.reconcileWannaGoReminders(store.wannaGoReminderItems)

            clearNativeMapFeatureSelection()
            selectedSearchCandidateID = nil
            if let remainingGroup = VisiblePlaceGrouping.matchingGroup(
                for: visiblePlace,
                in: visiblePlaces,
                currentUserID: store.currentUser.id
            ) {
                selectedPlaceGroupKey = remainingGroup.key
            } else {
                selectedPlaceGroupKey = nil
            }
            isPlaceProfilePresented = false
            showTransientMapSearchMessage("Want removed.")
            return true
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }

    private func showMapSaveFeedback(_ feedback: SaveSyncFeedback, successMessage: String) {
        let feedbackGenerator = UINotificationFeedbackGenerator()
        feedbackGenerator.notificationOccurred(feedback.usesWarningHaptic ? .warning : .success)
        showTransientMapSearchMessage(
            feedback.mapMessage(successMessage: successMessage),
            dismissDelayNanoseconds: feedback.dismissDelayNanoseconds
        )
    }

    private func showTransientMapSearchMessage(
        _ message: String,
        dismissDelayNanoseconds: UInt64 = 2_000_000_000
    ) {
        mapSearchMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: dismissDelayNanoseconds)
            if mapSearchMessage == message {
                mapSearchMessage = nil
            }
        }
    }

    private func isAlreadyVisible(candidate: PlaceCandidate) -> Bool {
        visiblePlace(matching: candidate) != nil
    }

    private func visiblePlace(matching candidate: PlaceCandidate) -> VisiblePlace? {
        guard let match = baseVisiblePlaces.first(where: { visiblePlace in
            visiblePlace.place.sourceProviderPlaceID == candidate.sourceProviderPlaceID
                || visiblePlace.place.canonicalName.caseInsensitiveCompare(candidate.name) == .orderedSame
        }) else {
            return nil
        }

        return VisiblePlaceGrouping.matchingGroup(
            for: match,
            in: baseVisiblePlaces,
            currentUserID: store.currentUser.id
        )?.primary ?? match
    }

    private func upsertMapSearchCandidate(_ candidate: PlaceCandidate) {
        if let index = mapSearchCandidates.firstIndex(where: { $0.id == candidate.id }) {
            mapSearchCandidates[index] = candidate
        } else {
            mapSearchCandidates.insert(candidate, at: 0)
        }
    }

    private func handleMapQueryChange() {
        let normalized = Self.normalized(mapQuery)
        let isSuppressedProgrammaticQuery = normalized == suppressedTypeaheadQuery
        if !isSuppressedProgrammaticQuery {
            invalidateMapSearchRequest()
        }
        mapSearchMessage = nil
        clearNativeMapFeatureSelection()

        if isSuppressedProgrammaticQuery {
            typeaheadTask?.cancel()
            typeaheadSuggestions = []
            isLoadingTypeahead = false
            return
        }

        suppressedTypeaheadQuery = nil
        mapSearchCandidates = []
        selectedSearchCandidateID = nil
        scheduleTypeahead(for: mapQuery)
    }

    private func scheduleTypeahead(for query: String) {
        typeaheadTask?.cancel()
        let normalized = Self.normalized(query)

        guard normalized.count >= 2 else {
            typeaheadSuggestions = []
            isLoadingTypeahead = false
            return
        }

        typeaheadSuggestions = savedTypeaheadSuggestions(for: query)
        isLoadingTypeahead = true

        typeaheadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }

            let candidates = (try? await mapKitCandidates(for: query, limit: 6)) ?? []
            guard !Task.isCancelled, Self.normalized(mapQuery) == normalized else { return }

            let savedSuggestions = savedTypeaheadSuggestions(for: query)
            let seenTitles = Set(savedSuggestions.map { Self.normalized($0.title) })
            let mapSuggestions = candidates
                .filter { !isAlreadyVisible(candidate: $0) }
                .filter { !seenTitles.contains(Self.normalized($0.name)) }
                .prefix(max(0, 6 - savedSuggestions.count))
                .map(MapSearchSuggestion.mapKit)

            typeaheadSuggestions = Array((savedSuggestions + mapSuggestions).prefix(6))
            isLoadingTypeahead = false
        }
    }

    private func savedTypeaheadSuggestions(for query: String) -> [MapSearchSuggestion] {
        let normalized = Self.normalized(query)
        guard !normalized.isEmpty else { return [] }

        let sortedMatches = baseVisiblePlaces
            .filter { visiblePlace in
                matchesTypeahead(visiblePlace, normalizedQuery: normalized)
            }
            .sorted { lhs, rhs in
                let lhsIsMine = lhs.owner.id == store.currentUser.id
                let rhsIsMine = rhs.owner.id == store.currentUser.id
                if lhsIsMine != rhsIsMine { return lhsIsMine }
                return lhs.place.canonicalName.localizedCaseInsensitiveCompare(rhs.place.canonicalName) == .orderedAscending
            }

        return VisiblePlaceGrouping.groups(
            from: sortedMatches,
            currentUserID: store.currentUser.id
        )
            .map { group in
                let saveStates = group.places.map { visiblePlace in
                    MapPinSaveState(
                        ownership: visiblePlace.owner.id == store.currentUser.id ? .currentUser : .social,
                        status: visiblePlace.userPlace.status
                    )
                }
                return MapSearchSuggestion.saved(group.primary, saveCount: group.saveCount, saveStates: saveStates)
            }
            .prefix(3)
            .map { $0 }
    }

    private func matchesTypeahead(_ visiblePlace: VisiblePlace, normalizedQuery: String) -> Bool {
        [
            visiblePlace.place.canonicalName,
            visiblePlace.effectiveCategoryDisplay.compactTitle,
            visiblePlace.place.locality,
            visiblePlace.owner.displayName,
            "@\(visiblePlace.owner.handle)",
            visiblePlace.userPlace.note,
            visiblePlace.userPlace.ratingSignal,
            visiblePlace.recommendedScore.map(PlaceRating.averageDisplay)
        ]
        .compactMap { $0 }
        .contains { Self.normalized($0).contains(normalizedQuery) }
    }

    private func selectTypeaheadSuggestion(_ suggestion: MapSearchSuggestion) {
        dismissKeyboard()
        typeaheadTask?.cancel()
        isLoadingTypeahead = false
        typeaheadSuggestions = []
        clearNativeMapFeatureSelection()
        suppressedTypeaheadQuery = Self.normalized(suggestion.title)
        mapQuery = suggestion.title
        mapSearchMessage = nil

        switch suggestion.source {
        case .saved(let visiblePlace, _):
            selectVisiblePlace(visiblePlace)
            selectedSearchCandidateID = nil
            mapSearchCandidates = []
            center(on: visiblePlace)
        case .mapKit(let candidate):
            selectedPlaceGroupKey = nil
            selectedSearchCandidateID = candidate.id
            mapSearchCandidates = isAlreadyVisible(candidate: candidate) ? [] : [candidate]
            center(on: candidate)
            mapSearchMessage = "Map result. Tap + to add it."
        }
    }

    private func addTypeaheadSuggestion(_ suggestion: MapSearchSuggestion) {
        dismissKeyboard()
        typeaheadTask?.cancel()
        isLoadingTypeahead = false
        typeaheadSuggestions = []
        clearNativeMapFeatureSelection()
        suppressedTypeaheadQuery = Self.normalized(suggestion.title)
        mapQuery = suggestion.title
        mapSearchMessage = nil

        switch suggestion.source {
        case .saved(let visiblePlace, _):
            selectVisiblePlace(visiblePlace)
            selectedSearchCandidateID = nil
            mapSearchCandidates = []
            center(on: visiblePlace)
            mapSaveFlow = MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.effectiveDefaultVisibility,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        case .mapKit(let candidate):
            selectedPlaceGroupKey = nil
            selectedSearchCandidateID = candidate.id
            mapSearchCandidates = isAlreadyVisible(candidate: candidate) ? [] : [candidate]
            center(on: candidate)
            mapSaveFlow = MapPlaceSaveContext.addCandidate(
                candidate,
                sourceType: .manual,
                defaultVisibility: store.effectiveDefaultVisibility
            )
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func center(on candidate: PlaceCandidate) {
        guard let latitude = candidate.latitude,
              let longitude = candidate.longitude
        else { return }

        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.04)
            )
        )
    }

    private func center(on visiblePlace: VisiblePlace) {
        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: visiblePlace.place.latitude, longitude: visiblePlace.place.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.04)
            )
        )
    }

    private func recenterOnUser() {
        guard !isRecenteringOnUser else { return }

        isRecenteringOnUser = true
        Task {
            let coordinate = await currentUserCoordinate()
            await MainActor.run {
                isRecenteringOnUser = false
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if let coordinate {
                        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        position = .camera(
                            MapCamera(
                                centerCoordinate: center,
                                distance: Self.recenterCameraDistance,
                                heading: 0,
                                pitch: 0
                            )
                        )
                        currentSearchRegion = MKCoordinateRegion(
                            center: center,
                            latitudinalMeters: Self.recenterCameraDistance * 2,
                            longitudinalMeters: Self.recenterCameraDistance * 2
                        )
                    } else {
                        position = .region(
                            MKCoordinateRegion(
                                center: Self.defaultRegion.center,
                                latitudinalMeters: Self.recenterCameraDistance * 2,
                                longitudinalMeters: Self.recenterCameraDistance * 2
                            )
                        )
                    }
                }
            }
        }
    }

    private func currentUserCoordinate() async -> (latitude: Double, longitude: Double)? {
        do {
            let location = try await CoreLocationProvider().currentLocation()
            return (location.coordinate.latitude, location.coordinate.longitude)
        } catch {
            return nil
        }
    }

    private func searchOriginLocation() async -> CLLocation {
        if let coordinate = await currentUserCoordinate() {
            return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }

        return CLLocation(
            latitude: currentSearchRegion.center.latitude,
            longitude: currentSearchRegion.center.longitude
        )
    }

    private func currentMapCenterLocation() -> CLLocation {
        CLLocation(
            latitude: currentSearchRegion.center.latitude,
            longitude: currentSearchRegion.center.longitude
        )
    }

    static func initialCityRegion(center: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: defaultRegion.span)
    }

    private func mapSearchRankingScore(for item: MKMapItem, query: String?, origin: CLLocation) -> Double {
        let normalizedQuery = Self.normalized(query ?? "")
        let normalizedName = Self.normalized(item.name ?? "")
        var score = 0.0

        if !normalizedQuery.isEmpty {
            if normalizedName == normalizedQuery {
                score += 1_000
            } else if normalizedName.hasPrefix(normalizedQuery) {
                score += 750
            } else if normalizedName.contains(normalizedQuery) {
                score += 500
            }
        }

        if item.pointOfInterestCategory != nil {
            score += 120
        }

        let distance = distanceMeters(from: origin, to: item) ?? 25_000
        score += max(0, 250 - min(distance, 10_000) / 40)

        return score
    }

    private func distanceMeters(from origin: CLLocation?, to item: MKMapItem) -> Double? {
        guard let origin else { return nil }

        return CLLocation(
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        ).distance(from: origin)
    }

    private func mapKitSourceID(for item: MKMapItem, name: String) -> String {
        let latitude = Int((item.placemark.coordinate.latitude * 100_000).rounded())
        let longitude = Int((item.placemark.coordinate.longitude * 100_000).rounded())
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "mapkit_\(slug)_\(latitude)_\(longitude)"
    }

    private func mapKitDuplicateKey(for item: MKMapItem, name: String) -> String {
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "\(slug)_\(item.placemark.locality?.lowercased() ?? "")"
    }

    private func category(for item: MKMapItem) -> String {
        WanderPlaceCategory.primary(for: item.pointOfInterestCategory, name: item.name) ?? "place"
    }

    private func placeCandidate(from feature: MapFeature) -> PlaceCandidate? {
        guard let title = feature.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty,
              CLLocationCoordinate2DIsValid(feature.coordinate)
        else { return nil }

        let sourceID = mapFeatureSourceID(for: feature, name: title)
        return PlaceCandidate(
            id: sourceID,
            name: title,
            category: category(for: feature),
            categorySource: PlaceCategorySource.provider.rawValue,
            categoryConfidence: 0.78,
            rawProviderType: feature.pointOfInterestCategory?.rawValue,
            address: nil,
            locality: nil,
            region: nil,
            country: nil,
            latitude: feature.coordinate.latitude,
            longitude: feature.coordinate.longitude,
            sourceProvider: "mapkit",
            sourceProviderPlaceID: sourceID,
            distanceMeters: CLLocation(latitude: feature.coordinate.latitude, longitude: feature.coordinate.longitude)
                .distance(from: currentMapCenterLocation()),
            confidence: 0.78
        )
    }

    private func mapFeatureSourceID(for feature: MapFeature, name: String) -> String {
        let latitude = Int((feature.coordinate.latitude * 100_000).rounded())
        let longitude = Int((feature.coordinate.longitude * 100_000).rounded())
        let slug = name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return "mapkit_\(slug)_\(latitude)_\(longitude)"
    }

    private func category(for feature: MapFeature) -> String {
        WanderPlaceCategory.primary(for: feature.pointOfInterestCategory, name: feature.title) ?? "place"
    }

    private func address(for placemark: MKPlacemark) -> String? {
        let street = [
            placemark.subThoroughfare,
            placemark.thoroughfare
        ].compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        .joined(separator: " ")

        guard !street.isEmpty else {
            return placemark.title?
                .components(separatedBy: ",")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return street
    }

    static func resolvedInitialMapPlaceQuery(from arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderMapPlace") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
    }

    static func resolvedInitialPlaceProfilePresentation(from arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-WanderMapSheetExpanded")
    }

    static func coordinateCandidate(at coordinate: CLLocationCoordinate2D) -> PlaceCandidate {
        let display = coordinateDisplay(for: coordinate)
        let latitude = Int((coordinate.latitude * 100_000).rounded())
        let longitude = Int((coordinate.longitude * 100_000).rounded())
        let sourceID = "coordinate_\(latitude)_\(longitude)"

        return PlaceCandidate(
            id: sourceID,
            name: "Dropped pin",
            category: WanderPlaceCategory.fallbackPlace,
            primaryCategory: WanderPlaceCategory.fallbackPlace,
            subcategory: nil,
            categorySource: PlaceCategorySource.unknown.rawValue,
            categoryConfidence: nil,
            rawProviderType: nil,
            address: display,
            locality: nil,
            region: nil,
            country: nil,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            sourceProvider: "coordinate",
            sourceProviderPlaceID: sourceID,
            confidence: 0.35
        )
    }

    static func coordinateDisplay(for coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct HideNativeMapFeatureAccessory: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapFeatureSelectionAccessory(nil)
        } else {
            content
        }
    }
}

enum MapHitTesting {
    static let markerTapRadius: CGFloat = 34

    static func isScreenPoint(_ point: CGPoint, nearAny markerPoints: [CGPoint], radius: CGFloat = markerTapRadius) -> Bool {
        markerPoints.contains { markerPoint in
            hypot(markerPoint.x - point.x, markerPoint.y - point.y) <= radius
        }
    }
}

enum MapFilter: String, CaseIterable, Identifiable {
    case you
    case social
    case been
    case wanna

    var id: String { rawValue }

    var title: String {
        switch self {
        case .you: "You"
        case .social: "Social"
        case .been: CheckInCopy.pluralTitle
        case .wanna: "Wanna"
        }
    }

    var systemImage: String {
        switch self {
        case .you: "person.fill"
        case .social: "person.2.fill"
        case .been: "circle.fill"
        case .wanna: "circle.dotted"
        }
    }

    func trimColor(isSelected: Bool) -> Color {
        semanticColor.opacity(isSelected ? 1 : 0.42)
    }

    func iconColor(isSelected: Bool) -> Color {
        semanticColor.opacity(isSelected ? 1 : 0.58)
    }

    func trimStyle(isSelected: Bool) -> StrokeStyle {
        StrokeStyle(
            lineWidth: isSelected ? 2 : 1.25,
            lineCap: .round,
            dash: self == .wanna ? MapPinVisualMetrics.wannaDashPattern : []
        )
    }

    private var semanticColor: Color {
        switch self {
        case .you:
            WanderTheme.pinYou.color
        case .social:
            WanderTheme.pinSocial.color
        case .been, .wanna:
            WanderTheme.textInk.color
        }
    }
}

enum MapFilterSelection {
    static func placeFilters(selectedFilters: Set<MapFilter>, selectedSocialOwnerID: String?) -> PlaceFilters? {
        let includesBeen = selectedFilters.contains(.been)
        let includesWanna = selectedFilters.contains(.wanna)
        guard includesBeen || includesWanna else { return nil }

        let includesYou = selectedFilters.contains(.you)
        let includesSocial = selectedFilters.contains(.social)
        guard includesYou || includesSocial else { return nil }

        var filters = PlaceFilters()
        if includesBeen && !includesWanna {
            filters.statuses = [.been]
        } else if includesWanna && !includesBeen {
            filters.statuses = [.wannaGo]
        }

        var scopes: Set<String> = []
        if includesYou { scopes.insert("you") }
        if includesSocial { scopes.insert("social") }
        filters.ownerScopes = scopes

        if let selectedSocialOwnerID, includesSocial {
            filters.ownerIDs = [selectedSocialOwnerID]
        }

        return filters
    }
}

private struct MapSearchSuggestion: Identifiable {
    enum Source {
        case saved(VisiblePlace, saveStates: [MapPinSaveState])
        case mapKit(PlaceCandidate)
    }

    let id: String
    let title: String
    let subtitle: String
    let category: String
    let source: Source

    var emoji: String {
        switch source {
        case .saved(let visiblePlace, _):
            return visiblePlace.categoryEmoji
        case .mapKit(let candidate):
            return candidate.categoryEmoji
        }
    }

    static func saved(
        _ visiblePlace: VisiblePlace,
        saveCount: Int = 1,
        saveStates: [MapPinSaveState]
    ) -> MapSearchSuggestion {
        let statusLabel = statusLabel(
            ownerName: visiblePlace.owner.displayName,
            placeCount: saveCount,
            saveStates: saveStates
        )

        let subtitle = [
            statusLabel,
            visiblePlace.place.locality,
            visiblePlace.effectiveCategoryDisplay.compactTitle
        ]
        .compactMap { value -> String? in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        .joined(separator: " · ")

        return MapSearchSuggestion(
            id: "saved_\(visiblePlace.id)",
            title: visiblePlace.place.canonicalName,
            subtitle: subtitle.isEmpty ? "On \(AppBrand.displayName)" : subtitle,
            category: visiblePlace.effectiveCategory,
            source: .saved(visiblePlace, saveStates: saveStates)
        )
    }

    static func mapKit(_ candidate: PlaceCandidate) -> MapSearchSuggestion {
        return MapSearchSuggestion(
            id: "mapkit_\(candidate.id)",
            title: candidate.name,
            subtitle: candidate.previewSubtitle(trailingParts: ["new to your map"]),
            category: candidate.category,
            source: .mapKit(candidate)
        )
    }

    private static func statusLabel(
        ownerName: String,
        placeCount: Int,
        saveStates: [MapPinSaveState]
    ) -> String {
        let ownerLabel = placeCount > 1
            ? "\(ownerName) + \(placeCount - 1) \(placeCount == 2 ? "other" : "others")"
            : ownerName
        let hasCheckIn = saveStates.contains { $0.status == .been }
        let hasWanna = saveStates.contains { $0.status == .wannaGo }

        if hasCheckIn, hasWanna { return "\(ownerLabel) · check-in + Wanna" }
        if hasCheckIn { return "\(ownerLabel) checked in" }
        if hasWanna { return "\(ownerLabel) · Wanna" }
        return "On \(AppBrand.displayName)"
    }
}

private struct MapSocialOwnerOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let handle: String

    var menuTitle: String {
        handle.isEmpty ? displayName : "\(displayName) @\(handle)"
    }
}

private struct SearchBar: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var query: String
    let isFocused: FocusState<Bool>.Binding
    let focusRequestID: UUID?
    let onFocusRequestHandled: (UUID) -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("search your map or people...", text: $query)
                .focused(isFocused)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .task(id: focusRequestID) {
                    await focusIfRequested()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, focusRequestID != nil else { return }
                    Task {
                        await focusIfRequested()
                    }
                }
            Spacer()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
                .accessibilityLabel("Clear map search")
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(height: 46)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        .shadow(color: WanderTheme.textInk.color.opacity(0.08), radius: 10, x: 0, y: 5)
        .padding(.horizontal, WanderTheme.spacing3)
    }

    @MainActor
    private func focusIfRequested() async {
        guard let focusRequestID, scenePhase == .active else { return }

        // Run from the TextField's own lifecycle so the selected Map tab and
        // its navigation hierarchy are attached before becoming first
        // responder. A second yield makes cold widget launches deterministic
        // without relying on a device-speed-specific delay.
        await Task.yield()
        guard !Task.isCancelled else { return }
        isFocused.wrappedValue = false
        await Task.yield()
        guard !Task.isCancelled else { return }
        isFocused.wrappedValue = true
        onFocusRequestHandled(focusRequestID)
    }
}

private struct MapTypeaheadList: View {
    let suggestions: [MapSearchSuggestion]
    let isLoading: Bool
    let onSelect: (MapSearchSuggestion) -> Void
    let onAdd: (MapSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                MapTypeaheadRow(
                    suggestion: suggestion,
                    onSelect: {
                        onSelect(suggestion)
                    },
                    onAdd: {
                        onAdd(suggestion)
                    }
                )

                if suggestion.id != suggestions.last?.id {
                    Divider()
                        .overlay(WanderTheme.borderHairline.color)
                        .padding(.leading, 52)
                }
            }

            if isLoading {
                HStack(spacing: WanderTheme.spacing2) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WanderTheme.terracotta.color)
                    Text(suggestions.isEmpty ? "looking nearby..." : "checking nearby...")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                    Spacer()
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.vertical, WanderTheme.spacing2)
                .accessibilityLabel("Looking for nearby places")
            }
        }
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .shadow(color: WanderTheme.textInk.color.opacity(0.1), radius: 12, x: 0, y: 6)
    }
}

private struct MapTypeaheadRow: View {
    let suggestion: MapSearchSuggestion
    let onSelect: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Button(action: onSelect) {
                HStack(spacing: WanderTheme.spacing2) {
                    WanderCategoryEmoji(emoji: suggestion.emoji, size: 14)
                        .frame(width: 38, height: 38)
                        .background(iconBackground)
                        .clipShape(Circle())
                        .overlay(savedOutlineLayer)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)
                        Text(suggestion.subtitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WanderTheme.pinSocial.color)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Check in at \(suggestion.title)")
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .contentShape(Rectangle())
        .accessibilityLabel("\(suggestion.title), \(suggestion.subtitle)")
    }

    @ViewBuilder
    private var savedOutlineLayer: some View {
        ForEach(Array(savedOutlines.indices), id: \.self) { index in
            MapPinOutlineStroke(
                outline: savedOutlines[index],
                lineWidth: MapPinVisualMetrics.outlineWidth
            )
                .padding(typeaheadOutlinePadding(for: index))
        }
    }

    private func typeaheadOutlinePadding(for index: Int) -> CGFloat {
        guard savedOutlines.count > 1 else { return 0 }
        return index == 0 ? 0 : MapPinVisualMetrics.secondaryOutlinePadding
    }

    private var isSavedSuggestion: Bool {
        if case .saved = suggestion.source { return true }
        return false
    }

    private var savedOutlines: [MapPinOutline] {
        if case let .saved(_, saveStates) = suggestion.source {
            return MapPinOutlineBuilder.outlines(for: saveStates)
        }
        return []
    }

    private var iconBackground: Color {
        isSavedSuggestion ? WanderTheme.surfaceRaised.color : Color(uiColor: .systemGray5)
    }
}

private struct MapSearchMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(WanderTheme.textInk.color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WanderTheme.spacing3)
            .padding(.vertical, WanderTheme.spacing2)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
    }
}

private struct RecenterButton: View {
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLoading ? "location.circle.fill" : "location.fill")
                .font(.system(size: 16, weight: .black))
                .frame(width: 44, height: 44)
                .background(WanderTheme.skyTint.color)
                .foregroundStyle(WanderTheme.pinSocial.color)
                .clipShape(Circle())
                .overlay(Circle().stroke(WanderTheme.pinSocial.color, lineWidth: 2))
                .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 10, x: 0, y: 5)
        }
        .disabled(isLoading)
        .accessibilityLabel("Center on my location")
    }
}

private struct MapFilterChip: View {
    let filter: MapFilter
    let isSelected: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: filter.systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(filter.iconColor(isSelected: isSelected))
            Text(filter.title)
                .lineLimit(1)
        }
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(height: 44)
        .background(WanderTheme.surfaceRaised.color)
        .foregroundStyle(WanderTheme.textInk.color)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(
                    filter.trimColor(isSelected: isSelected),
                    style: filter.trimStyle(isSelected: isSelected)
                )
        )
        .shadow(color: WanderTheme.textInk.color.opacity(isSelected ? 0.12 : 0), radius: 8, x: 0, y: 3)
        .contentShape(Capsule())
        .accessibilityLabel("\(filter.title) places filter")
        .accessibilityValue(isSelected ? "On" : "Off")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct MapSocialFilterMenu: View {
    let isSelected: Bool
    let selectedOwner: MapSocialOwnerOption?
    let ownerOptions: [MapSocialOwnerOption]
    let showAll: () -> Void
    let hideSocial: () -> Void
    let selectOwner: (String) -> Void

    var body: some View {
        Menu {
            Button {
                showAll()
            } label: {
                Label("All social places", systemImage: selectedOwner == nil && isSelected ? "checkmark" : "person.2")
            }

            if !ownerOptions.isEmpty {
                Divider()

                ForEach(ownerOptions) { owner in
                    Button {
                        selectOwner(owner.id)
                    } label: {
                        Label(owner.menuTitle, systemImage: selectedOwner?.id == owner.id ? "checkmark" : "person")
                    }
                }
            }

            Divider()

            Button {
                hideSocial()
            } label: {
                Label("Hide social places", systemImage: !isSelected ? "checkmark" : "eye.slash")
            }
        } label: {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(MapFilter.social.iconColor(isSelected: isSelected))
                Text(selectedOwner?.displayName ?? MapFilter.social.title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 44)
            .background(WanderTheme.surfaceRaised.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        MapFilter.social.trimColor(isSelected: isSelected),
                        style: MapFilter.social.trimStyle(isSelected: isSelected)
                    )
            )
            .shadow(color: WanderTheme.textInk.color.opacity(isSelected ? 0.12 : 0), radius: 8, x: 0, y: 3)
            .contentShape(Capsule())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .accessibilityLabel(selectedOwner.map { "Social places filtered to \($0.displayName)" } ?? "Social places filter")
        .accessibilityValue(isSelected ? "On" : "Off")
    }
}

private struct SearchResultMarker: View {
    let candidate: PlaceCandidate
    let isSelected: Bool

    var body: some View {
        WanderCategoryEmoji(emoji: candidate.categoryEmoji, size: isSelected ? 17 : 15)
            .frame(width: isSelected ? 42 : 38, height: isSelected ? 42 : 38)
            .background(WanderTheme.pinSocial.color)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(WanderTheme.surfaceRaised.color, lineWidth: isSelected ? 4 : 3)
            )
            .overlay(
                Circle()
                    .stroke(WanderTheme.pinSocial.color, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .padding(-5)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.18), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isSelected)
            .accessibilityLabel("Map search result, \(candidate.name)")
    }

}

private struct MapPlaceMarker: View {
    let visiblePlace: VisiblePlace
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    let isSelected: Bool

    var body: some View {
        WanderMapPin(
            visiblePlace: visiblePlace,
            outlines: MapPinOutlineBuilder.outlines(for: saveStates),
            isSelected: isSelected
        )
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isSelected)
    }

    private var saveStates: [MapPinSaveState] {
        let states = saves.map { summary in
            MapPinSaveState(
                ownership: summary.visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                status: summary.visiblePlace.userPlace.status
            )
        }

        if states.isEmpty {
            return [
                MapPinSaveState(
                    ownership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                    status: visiblePlace.userPlace.status
                )
            ]
        }

        return states
    }
}

private struct WanderMapPin: View {
    let visiblePlace: VisiblePlace
    let outlines: [MapPinOutline]
    let isSelected: Bool

    var body: some View {
        WanderCategoryEmoji(emoji: visiblePlace.categoryEmoji, size: 16)
            .frame(width: MapPinVisualMetrics.discDiameter, height: MapPinVisualMetrics.discDiameter)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .background(selectionHalo)
            .overlay(outlineLayer)
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .accessibilityLabel(
                MapPinAccessibility.label(
                    outlines: outlines,
                    category: visiblePlace.effectiveCategoryDisplay.compactTitle,
                    placeName: visiblePlace.place.canonicalName
                )
            )
    }

    @ViewBuilder
    private var selectionHalo: some View {
        if isSelected {
            ZStack {
                Circle()
                    .fill(WanderTheme.surfaceBone.color.opacity(0.96))
                    .padding(MapPinVisualMetrics.selectionHaloPadding)
                Circle()
                    .stroke(WanderTheme.textInk.color.opacity(0.16), lineWidth: 1)
                    .padding(MapPinVisualMetrics.selectionHaloPadding)
            }
        }
    }

    private var outlineLayer: some View {
        ForEach(Array(outlines.indices), id: \.self) { index in
            MapPinOutlineStroke(
                outline: outlines[index],
                lineWidth: outlineLineWidth
            )
                .padding(outlinePadding(for: index))
        }
    }

    private var outlineLineWidth: CGFloat {
        MapPinVisualMetrics.outlineWidth
    }

    private func outlinePadding(for index: Int) -> CGFloat {
        guard outlines.count > 1 else { return 0 }
        return index == 0 ? 0 : MapPinVisualMetrics.secondaryOutlinePadding
    }
}

struct MapPinOutlineStroke: View {
    let outline: MapPinOutline
    let lineWidth: CGFloat

    var body: some View {
        Group {
            if outline.secondaryStatus == nil {
                Circle()
                    .stroke(
                        outline.color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            dash: outline.dashPattern
                        )
                    )
            } else {
                ZStack {
                    ForEach(Array(outline.arcs.enumerated()), id: \.offset) { _, arc in
                        Circle()
                            .trim(from: arc.trimFrom, to: arc.trimTo)
                            .stroke(
                                outline.color,
                                style: StrokeStyle(
                                    lineWidth: lineWidth,
                                    lineCap: .round,
                                    dash: arc.dashPattern
                                )
                            )
                            .rotationEffect(.degrees(arc.rotationDegrees))
                    }
                }
            }
        }
    }
}

enum MapPinSaveOwnership: Equatable {
    case currentUser
    case social

    var key: String {
        switch self {
        case .currentUser: "current_user"
        case .social: "social"
        }
    }

    var color: Color {
        switch self {
        case .currentUser: WanderTheme.pinYou.color
        case .social: WanderTheme.pinSocial.color
        }
    }
}

struct MapPinSaveState: Equatable {
    let ownership: MapPinSaveOwnership
    let status: PlaceStatus
}

enum MapPinVisualMetrics {
    static let discDiameter: CGFloat = 38
    static let outlineWidth: CGFloat = 3
    static let secondaryOutlinePadding: CGFloat = -6
    static let selectionHaloPadding: CGFloat = -10
    static let wannaDashPattern: [CGFloat] = [1.5, 3.5]
}

struct MapPinOutline: Identifiable, Equatable {
    let ownership: MapPinSaveOwnership
    let status: PlaceStatus
    let secondaryStatus: PlaceStatus?

    init(
        ownership: MapPinSaveOwnership,
        status: PlaceStatus,
        secondaryStatus: PlaceStatus? = nil
    ) {
        self.ownership = ownership
        self.status = status
        self.secondaryStatus = secondaryStatus
    }

    var id: String {
        [ownership.key, status.rawValue, secondaryStatus?.rawValue]
            .compactMap { $0 }
            .joined(separator: "-")
    }

    var color: Color {
        ownership.color
    }

    var dashPattern: [CGFloat] {
        status == .wannaGo ? MapPinVisualMetrics.wannaDashPattern : []
    }

    var arcs: [MapPinOutlineArc] {
        guard let secondaryStatus else {
            return [
                MapPinOutlineArc(
                    status: status,
                    trimFrom: 0,
                    trimTo: 1,
                    rotationDegrees: 0,
                    dashPattern: status == .wannaGo ? MapPinVisualMetrics.wannaDashPattern : []
                )
            ]
        }

        return [
            MapPinOutlineArc(
                status: status,
                trimFrom: 0.028,
                trimTo: 0.472,
                rotationDegrees: -90,
                dashPattern: []
            ),
            MapPinOutlineArc(
                status: secondaryStatus,
                trimFrom: 0.528,
                trimTo: 0.972,
                rotationDegrees: -90,
                dashPattern: MapPinVisualMetrics.wannaDashPattern
            )
        ]
    }
}

struct MapPinOutlineArc: Equatable {
    let status: PlaceStatus
    let trimFrom: CGFloat
    let trimTo: CGFloat
    let rotationDegrees: Double
    let dashPattern: [CGFloat]
}

enum MapPinOutlineBuilder {
    static func outlines(for states: [MapPinSaveState]) -> [MapPinOutline] {
        [
            outline(for: .currentUser, in: states),
            outline(for: .social, in: states)
        ]
        .compactMap { $0 }
    }

    static func outlineCatalog(
        for visiblePlaces: [VisiblePlace],
        currentUserID: String
    ) -> [String: [MapPinOutline]] {
        var catalog: [String: [MapPinOutline]] = [:]

        for group in VisiblePlaceGrouping.groups(
            from: visiblePlaces,
            currentUserID: currentUserID
        ) {
            let outlines = outlines(
                for: group.places.map { visiblePlace in
                    MapPinSaveState(
                        ownership: visiblePlace.owner.id == currentUserID ? .currentUser : .social,
                        status: visiblePlace.userPlace.status
                    )
                }
            )

            for visiblePlace in group.places {
                catalog[visiblePlace.id] = outlines
            }
        }

        return catalog
    }

    private static func outline(
        for ownership: MapPinSaveOwnership,
        in states: [MapPinSaveState]
    ) -> MapPinOutline? {
        let matchingStates = states.filter { $0.ownership == ownership }
        guard !matchingStates.isEmpty else { return nil }

        let hasBeen = matchingStates.contains { $0.status == .been }
        let hasWanna = matchingStates.contains { $0.status == .wannaGo }

        if ownership == .social && hasBeen && hasWanna {
            return MapPinOutline(
                ownership: ownership,
                status: .been,
                secondaryStatus: .wannaGo
            )
        }

        let status: PlaceStatus = hasBeen ? .been : .wannaGo
        return MapPinOutline(ownership: ownership, status: status)
    }
}

enum MapPinAccessibility {
    static func label(outlines: [MapPinOutline], category: String, placeName: String) -> String {
        let stateSummaries = outlines.map { outline in
            let owner = outline.ownership == .currentUser ? "you" : "social"
            let primaryStatus = outline.status == .been ? CheckInCopy.pastTense : "wanna"

            if outline.secondaryStatus == .wannaGo {
                return "\(owner) \(primaryStatus) and wanna"
            }

            return "\(owner) \(primaryStatus)"
        }

        return ([placeName, category] + stateSummaries).joined(separator: ", ")
    }
}

enum PlaceSheetAction {
    case add
    case addVisit
    case choose
    case none

    static func topLevelAction(currentUserSave: VisiblePlace?) -> PlaceSheetAction {
        currentUserSave == nil ? .add : .addVisit
    }

    var systemImage: String {
        switch self {
        case .add: "plus"
        case .addVisit: "plus"
        case .choose: "checkmark"
        case .none: ""
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .add: CheckInCopy.action
        case .addVisit: CheckInCopy.againAction
        case .choose: "Choose this place"
        case .none: ""
        }
    }

    var displayTitle: String {
        accessibilityLabel
    }

    var isPrimaryAction: Bool {
        switch self {
        case .add, .addVisit, .choose:
            true
        case .none:
            false
        }
    }
}

struct PlaceSheetPlace {
    let id: String
    let name: String
    let category: String
    let primaryCategory: String
    let subcategory: String?
    let categorySource: String
    let categoryConfidence: Double?
    let rawProviderType: String?
    let cuisine: String?
    let address: String?
    let locality: String?
    let region: String?
    let latitude: Double?
    let longitude: Double?
    let websiteURLString: String?
    let phoneNumber: String?
    let actionLinksJSON: String?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?
    let compactSubtitleOverride: String?
    let status: PlaceStatus?
    let visibility: PlaceVisibility?
    let note: String?
    let noteOwnerID: String?
    let noteOwnerName: String?

    var categoryAssignment: PlaceCategoryAssignment {
        PlaceCategoryAssignment(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            source: categorySource,
            confidence: categoryConfidence,
            rawProviderType: rawProviderType
        )
    }

    var categoryEmoji: String {
        WanderPlaceCategory.emoji(
            for: categoryAssignment,
            cuisine: cuisine,
            name: name
        )
    }

    var photoRequest: PlacePhotoRequest {
        PlacePhotoRequest(
            placeID: id,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            sourceProvider: sourceProvider,
            sourceProviderPlaceID: sourceProviderPlaceID
        )
    }

    var photoLookupKey: String { photoRequest.lookupKey }

    init(visiblePlace: VisiblePlace) {
        self.id = visiblePlace.place.id
        self.name = visiblePlace.place.canonicalName
        self.category = visiblePlace.effectiveCategory
        self.primaryCategory = visiblePlace.effectiveCategory
        self.subcategory = visiblePlace.effectiveSubcategory
        self.categorySource = visiblePlace.categoryAssignment.source
        self.categoryConfidence = visiblePlace.categoryAssignment.confidence
        self.rawProviderType = visiblePlace.place.rawProviderType
        self.cuisine = visiblePlace.restaurantCuisine
        self.address = visiblePlace.place.address
        self.locality = visiblePlace.place.locality
        self.region = visiblePlace.place.region
        self.latitude = visiblePlace.place.latitude
        self.longitude = visiblePlace.place.longitude
        self.websiteURLString = visiblePlace.place.websiteURLString
        self.phoneNumber = visiblePlace.place.phoneNumber
        self.actionLinksJSON = visiblePlace.place.actionLinksJSON
        self.sourceProvider = visiblePlace.place.sourceProvider
        self.sourceProviderPlaceID = visiblePlace.place.sourceProviderPlaceID
        self.compactSubtitleOverride = nil
        self.status = visiblePlace.userPlace.status
        self.visibility = visiblePlace.userPlace.visibility
        self.note = visiblePlace.userPlace.note
        self.noteOwnerID = visiblePlace.owner.id
        self.noteOwnerName = visiblePlace.owner.displayName
    }

    init(candidate: PlaceCandidate) {
        self.id = candidate.id
        self.name = candidate.name
        self.category = candidate.category
        self.primaryCategory = candidate.primaryCategory
        self.subcategory = candidate.subcategory
        self.categorySource = candidate.categorySource
        self.categoryConfidence = candidate.categoryConfidence
        self.rawProviderType = candidate.rawProviderType
        self.cuisine = WanderPlaceCategory.restaurantCuisineInference(for: candidate)?.cuisine
        self.address = candidate.address
        self.locality = candidate.locality
        self.region = candidate.region
        self.latitude = candidate.latitude
        self.longitude = candidate.longitude
        self.websiteURLString = candidate.websiteURLString
        self.phoneNumber = candidate.phoneNumber
        self.actionLinksJSON = candidate.actionLinksJSON
        self.sourceProvider = candidate.sourceProvider
        self.sourceProviderPlaceID = candidate.sourceProviderPlaceID
        self.compactSubtitleOverride = candidate.previewSubtitle()
        self.status = nil
        self.visibility = nil
        self.note = nil
        self.noteOwnerID = nil
        self.noteOwnerName = nil
    }
}

enum MapPlaceSaveMode {
    case add(AddSourceType)
    case addVisit(VisiblePlace)
    case sharedVisit(SharedVisitInvitation)
    case editVisit(VisiblePlace, LocalPlaceVisit)
    case editWant(VisiblePlace)
}

struct MapPlaceSaveContext: Identifiable {
    let id = UUID()
    let candidate: PlaceCandidate
    let mode: MapPlaceSaveMode
    let requiresStatusConfirmation: Bool
    let initialStatus: PlaceStatus
    let initialVisibility: PlaceVisibility
    let initialRatingScore: Double?
    let initialNote: String
    let initialPlannedDate: Date?
    let initialAnswers: [String: Set<String>]
    let initialPersonalLabels: Set<String>
    let initialCuisine: String?
    let initialPhotoAttachments: [MapPlaceSavePhotoAttachment]

    var isEditing: Bool {
        switch mode {
        case .editVisit, .editWant:
            return true
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }

    var isNewPlaceAdd: Bool {
        if case .add = mode {
            return true
        }
        return false
    }

    var startsOnDetails: Bool {
        !requiresStatusConfirmation
    }

    var allowsPhotoAttachments: Bool {
        switch mode {
        case .add, .addVisit, .sharedVisit:
            true
        case .editVisit, .editWant:
            false
        }
    }

    var showsRemoveControl: Bool {
        switch mode {
        case .editVisit, .editWant:
            true
        case .add, .addVisit, .sharedVisit:
            false
        }
    }

    var sourceVisiblePlace: VisiblePlace? {
        switch mode {
        case .add, .sharedVisit:
            nil
        case .addVisit(let visiblePlace),
             .editVisit(let visiblePlace, _),
             .editWant(let visiblePlace):
            visiblePlace
        }
    }

    var editedVisit: LocalPlaceVisit? {
        if case .editVisit(_, let visit) = mode {
            return visit
        }
        return nil
    }

    var sharedVisitInvitation: SharedVisitInvitation? {
        if case .sharedVisit(let invitation) = mode {
            return invitation
        }
        return nil
    }

    var title: String {
        switch mode {
        case .add:
            "Check in or Wanna"
        case .addVisit:
            CheckInCopy.againAction
        case .sharedVisit:
            "Check in from invite"
        case .editVisit:
            CheckInCopy.editAction
        case .editWant:
            "Edit Wanna"
        }
    }

    var subtitle: String {
        switch mode {
        case .add:
            "Choose whether to check in or mark it Wanna."
        case .addVisit:
            "capture what happened this time."
        case .sharedVisit(let invitation):
            "\(invitation.sourceOwnerDisplayName) shared their version. Make yours your own."
        case .editVisit:
            "adjust this check-in."
        case .editWant:
            "update why this is on your radar."
        }
    }

    var saveTitle: String {
        switch mode {
        case .add:
            CheckInCopy.action
        case .addVisit:
            CheckInCopy.action
        case .sharedVisit:
            CheckInCopy.action
        case .editVisit:
            "Update check-in"
        case .editWant:
            "Update Wanna"
        }
    }

    var removeTitle: String {
        switch mode {
        case .editVisit:
            CheckInCopy.deleteAction
        case .editWant:
            "Remove from Wanna"
        case .add, .addVisit, .sharedVisit:
            "Remove place"
        }
    }

    var removeConfirmationTitle: String {
        switch mode {
        case .editVisit:
            "Delete check-in?"
        case .editWant:
            "Remove from Wanna?"
        case .add, .addVisit, .sharedVisit:
            "Remove place?"
        }
    }

    var removeConfirmationMessage: String {
        switch mode {
        case .editVisit:
            "This removes this check-in and its photos from your place history."
        case .editWant:
            "This removes this place from Wanna."
        case .add, .addVisit, .sharedVisit:
            "This removes the place from your map."
        }
    }

    static func addCandidate(
        _ candidate: PlaceCandidate,
        sourceType: AddSourceType,
        defaultVisibility: PlaceVisibility,
        initialPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate,
            mode: .add(sourceType),
            requiresStatusConfirmation: true,
            initialStatus: .wannaGo,
            initialVisibility: defaultVisibility,
            initialRatingScore: nil,
            initialNote: "",
            initialPlannedDate: nil,
            initialAnswers: [:],
            initialPersonalLabels: [],
            initialCuisine: nil,
            initialPhotoAttachments: initialPhotoAttachments
        )
    }

    static func importCandidate(
        _ candidate: PlaceCandidate,
        sourceType: AddSourceType,
        status: PlaceStatus,
        defaultVisibility: PlaceVisibility
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate,
            mode: .add(sourceType),
            requiresStatusConfirmation: false,
            initialStatus: status,
            initialVisibility: defaultVisibility,
            initialRatingScore: nil,
            initialNote: "",
            initialPlannedDate: nil,
            initialAnswers: [:],
            initialPersonalLabels: [],
            initialCuisine: nil,
            initialPhotoAttachments: []
        )
    }

    static func addVisiblePlace(
        _ visiblePlace: VisiblePlace,
        defaultVisibility: PlaceVisibility,
        attributes: [LocalPlaceAttribute] = []
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate(from: visiblePlace),
            mode: .add(.socialSave),
            requiresStatusConfirmation: true,
            initialStatus: visiblePlace.userPlace.status,
            initialVisibility: defaultVisibility,
            initialRatingScore: nil,
            initialNote: "",
            initialPlannedDate: nil,
            initialAnswers: initialNewSaveAnswers(from: attributes),
            initialPersonalLabels: [],
            initialCuisine: initialCuisine(from: attributes),
            initialPhotoAttachments: []
        )
    }

    static func addVisitVisiblePlace(
        _ visiblePlace: VisiblePlace,
        attributes: [LocalPlaceAttribute],
        latestVisit: LocalPlaceVisit?
    ) -> MapPlaceSaveContext {
        let defaultAttributes = latestVisit.map { VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: $0.attributeAnswersJSON) }
            ?? attributes.map { PlaceAttributeDraft(questionKey: $0.questionKey, valueType: $0.valueType, valueJSON: $0.valueJSON) }
        let note = visiblePlace.userPlace.status == .wannaGo ? visiblePlace.userPlace.note ?? "" : ""
        return MapPlaceSaveContext(
            candidate: candidate(from: visiblePlace),
            mode: .addVisit(visiblePlace),
            requiresStatusConfirmation: false,
            initialStatus: .been,
            initialVisibility: visiblePlace.userPlace.visibility,
            initialRatingScore: latestVisit?.ratingScore,
            initialNote: note,
            initialPlannedDate: nil,
            initialAnswers: initialNewSaveAnswers(from: defaultAttributes),
            initialPersonalLabels: [],
            initialCuisine: initialCuisine(from: defaultAttributes),
            initialPhotoAttachments: []
        )
    }

    static func sharedVisit(
        _ invitation: SharedVisitInvitation,
        defaultVisibility: PlaceVisibility
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: invitation.candidate,
            mode: .sharedVisit(invitation),
            requiresStatusConfirmation: false,
            initialStatus: .been,
            initialVisibility: defaultVisibility,
            initialRatingScore: nil,
            initialNote: "",
            initialPlannedDate: nil,
            initialAnswers: [:],
            initialPersonalLabels: [],
            initialCuisine: initialCuisine(from: invitation.attributeDrafts),
            initialPhotoAttachments: []
        )
    }

    static func editVisit(
        _ visit: LocalPlaceVisit,
        visiblePlace: VisiblePlace
    ) -> MapPlaceSaveContext {
        let attributes = VisitAttributeAnswers.drafts(fromAttributeAnswersJSON: visit.attributeAnswersJSON)
        return MapPlaceSaveContext(
            candidate: candidate(from: visiblePlace),
            mode: .editVisit(visiblePlace, visit),
            requiresStatusConfirmation: false,
            initialStatus: .been,
            initialVisibility: visiblePlace.userPlace.visibility,
            initialRatingScore: visit.ratingScore,
            initialNote: visit.note ?? "",
            initialPlannedDate: nil,
            initialAnswers: initialAnswers(from: attributes),
            initialPersonalLabels: initialPersonalLabels(from: attributes),
            initialCuisine: initialCuisine(from: attributes),
            initialPhotoAttachments: []
        )
    }

    static func editWant(
        _ visiblePlace: VisiblePlace,
        attributes: [LocalPlaceAttribute]
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate(from: visiblePlace),
            mode: .editWant(visiblePlace),
            requiresStatusConfirmation: false,
            initialStatus: .wannaGo,
            initialVisibility: visiblePlace.userPlace.visibility,
            initialRatingScore: nil,
            initialNote: visiblePlace.userPlace.note ?? "",
            initialPlannedDate: visiblePlace.userPlace.plannedDate,
            initialAnswers: initialAnswers(from: attributes),
            initialPersonalLabels: initialPersonalLabels(from: attributes),
            initialCuisine: initialCuisine(from: attributes),
            initialPhotoAttachments: []
        )
    }

    private static func candidate(from visiblePlace: VisiblePlace) -> PlaceCandidate {
        PlaceCandidate(
            id: visiblePlace.place.id,
            name: visiblePlace.place.canonicalName,
            category: visiblePlace.effectiveCategory,
            primaryCategory: visiblePlace.effectiveCategory,
            subcategory: visiblePlace.effectiveSubcategory,
            categorySource: visiblePlace.categoryAssignment.source,
            categoryConfidence: visiblePlace.categoryAssignment.confidence,
            rawProviderType: visiblePlace.place.rawProviderType,
            address: visiblePlace.place.address,
            locality: visiblePlace.place.locality,
            region: visiblePlace.place.region,
            country: visiblePlace.place.country,
            latitude: visiblePlace.place.latitude,
            longitude: visiblePlace.place.longitude,
            sourceProvider: visiblePlace.place.sourceProvider,
            sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID,
            websiteURLString: visiblePlace.place.websiteURLString,
            phoneNumber: visiblePlace.place.phoneNumber,
            timeZoneIdentifier: visiblePlace.place.timeZoneIdentifier,
            actionLinksJSON: visiblePlace.place.actionLinksJSON,
            confidence: visiblePlace.place.confidence ?? 1
        )
    }

    private static func initialAnswers(from attributes: [LocalPlaceAttribute]) -> [String: Set<String>] {
        var answers: [String: Set<String>] = [:]
        let decoder = JSONDecoder()

        for attribute in attributes {
            guard attribute.questionKey != PlaceMemoryAttributeKeys.personalLabels,
                  attribute.questionKey != PlaceMemoryAttributeKeys.restaurantCuisine
            else { continue }
            guard let data = attribute.valueJSON.data(using: .utf8) else { continue }
            if let values = try? decoder.decode([String].self, from: data) {
                answers[attribute.questionKey] = Set(values)
            } else if let value = try? decoder.decode(String.self, from: data) {
                answers[attribute.questionKey] = [value]
            }
        }

        return answers
    }

    private static func initialAnswers(from attributes: [PlaceAttributeDraft]) -> [String: Set<String>] {
        var answers: [String: Set<String>] = [:]
        let decoder = JSONDecoder()

        for attribute in attributes {
            guard attribute.questionKey != PlaceMemoryAttributeKeys.personalLabels,
                  attribute.questionKey != PlaceMemoryAttributeKeys.restaurantCuisine
            else { continue }
            guard let data = attribute.valueJSON.data(using: .utf8) else { continue }
            if let values = try? decoder.decode([String].self, from: data) {
                answers[attribute.questionKey] = Set(values)
            } else if let value = try? decoder.decode(String.self, from: data) {
                answers[attribute.questionKey] = [value]
            }
        }

        return answers
    }

    private static func initialNewSaveAnswers(
        from attributes: [LocalPlaceAttribute]
    ) -> [String: Set<String>] {
        initialAnswers(
            from: attributes.filter {
                $0.valueType != "multi_tag" && $0.valueType != "price_scale"
            }
        )
    }

    private static func initialNewSaveAnswers(
        from attributes: [PlaceAttributeDraft]
    ) -> [String: Set<String>] {
        initialAnswers(
            from: attributes.filter {
                $0.valueType != "multi_tag" && $0.valueType != "price_scale"
            }
        )
    }

    private static func initialPersonalLabels(from attributes: [LocalPlaceAttribute]) -> Set<String> {
        guard let attribute = attributes.first(where: { $0.questionKey == PlaceMemoryAttributeKeys.personalLabels }),
              let data = attribute.valueJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(values)
    }

    private static func initialPersonalLabels(from attributes: [PlaceAttributeDraft]) -> Set<String> {
        guard let attribute = attributes.first(where: { $0.questionKey == PlaceMemoryAttributeKeys.personalLabels }),
              let data = attribute.valueJSON.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return Set(values)
    }

    private static func initialCuisine(from attributes: [LocalPlaceAttribute]) -> String? {
        guard let attribute = attributes.first(where: { $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine }),
              let data = attribute.valueJSON.data(using: .utf8)
        else {
            return nil
        }

        if let value = try? JSONDecoder().decode(String.self, from: data) {
            return WanderPlaceCategory.cuisineGuess(forRawValue: value)
                ?? WanderPlaceCategory.normalizedSubcategory(value)
        }

        if let values = try? JSONDecoder().decode([String].self, from: data),
           let value = values.first {
            return WanderPlaceCategory.cuisineGuess(forRawValue: value)
                ?? WanderPlaceCategory.normalizedSubcategory(value)
        }

        return nil
    }

    private static func initialCuisine(from attributes: [PlaceAttributeDraft]) -> String? {
        guard let attribute = attributes.first(where: { $0.questionKey == PlaceMemoryAttributeKeys.restaurantCuisine }),
              let data = attribute.valueJSON.data(using: .utf8)
        else {
            return nil
        }

        if let value = try? JSONDecoder().decode(String.self, from: data) {
            return WanderPlaceCategory.cuisineGuess(forRawValue: value)
                ?? WanderPlaceCategory.normalizedSubcategory(value)
        }

        if let values = try? JSONDecoder().decode([String].self, from: data),
           let value = values.first {
            return WanderPlaceCategory.cuisineGuess(forRawValue: value)
                ?? WanderPlaceCategory.normalizedSubcategory(value)
        }

        return nil
    }
}

struct MapPlaceSaveSubmission {
    let context: MapPlaceSaveContext
    let candidate: PlaceCandidate
    let status: PlaceStatus
    let visibility: PlaceVisibility
    let ratingScore: Double?
    let note: String?
    let attributes: [PlaceAttributeDraft]
    let photoAttachments: [MapPlaceSavePhotoAttachment]
    let inviteeUserIDs: [String]
    let reconcilesSharedVisitInvitees: Bool
    var visitedAt: Date = .now
    var plannedDate: Date? = nil
}

struct MapPlaceSavePhotoAttachment: Identifiable {
    static let maximumCount = 10
    static let maximumBytesPerPhoto = 10 * 1024 * 1024
    static let maximumTotalBytes = 75 * 1024 * 1024

    let id: UUID
    let image: UIImage
    let contentType: String
    let localAssetRef: String?
    let sourcePhotoID: String?
    let byteSize: Int

    var width: Int? {
        image.cgImage?.width
    }

    var height: Int? {
        image.cgImage?.height
    }

    static func make(
        image: UIImage,
        data: Data? = nil,
        contentType: String = "image/jpeg",
        fallbackAssetRef: String? = nil,
        sourcePhotoID: String? = nil
    ) -> MapPlaceSavePhotoAttachment? {
        guard let payload = data ?? image.jpegData(compressionQuality: 0.86) else {
            return nil
        }
        guard payload.count <= maximumBytesPerPhoto else { return nil }

        let id = UUID()
        guard let fileRef = VisitPhotoLocalFileStore.save(data: payload, id: id, contentType: contentType) else {
            return nil
        }
        return MapPlaceSavePhotoAttachment(
            id: id,
            image: thumbnail(from: image),
            contentType: contentType,
            localAssetRef: fileRef,
            sourcePhotoID: sourcePhotoID,
            byteSize: payload.count
        )
    }

    func data() -> Data? {
        VisitPhotoLocalFileStore.data(from: localAssetRef)
    }

    private static func thumbnail(from image: UIImage) -> UIImage {
        let maximumDimension: CGFloat = 320
        let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
        guard scale < 1 else { return image }
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

@MainActor
func createExplicitVisitIfNeeded(
    for submission: MapPlaceSaveSubmission,
    store: WanderStore
) -> LocalPlaceVisit? {
    guard case .addVisit(let visiblePlace) = submission.context.mode,
          submission.status == .been
    else {
        return nil
    }

    return store.createVisit(
        userPlaceID: visiblePlace.userPlace.id,
        visitedAt: submission.visitedAt,
        note: submission.note,
        ratingScore: submission.ratingScore,
        attributes: submission.attributes,
        visibility: submission.visibility
    )
}

@MainActor
func persistNewPlaceSaveSubmission(
    _ submission: MapPlaceSaveSubmission,
    store: WanderStore,
    backend: WanderBackend?
) async -> SaveResult? {
    guard case .add(let sourceType) = submission.context.mode else {
        return nil
    }

    let result = await store.saveCandidate(
        submission.candidate,
        status: submission.status,
        visibility: submission.visibility,
        note: submission.note,
        sourceType: sourceType,
        ratingScore: submission.ratingScore,
        visitedAt: submission.visitedAt,
        plannedDate: submission.plannedDate,
        attributes: submission.attributes,
        backend: backend
    )
    let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
    await persistVisitPhotoAttachments(
        submission.photoAttachments,
        to: targetVisit,
        store: store,
        backend: backend
    )
    return result
}

@MainActor
func persistScopedVisitOrWantSubmission(
    _ submission: MapPlaceSaveSubmission,
    store: WanderStore,
    backend: WanderBackend?
) async -> (SaveResult?, LocalPlaceVisit?) {
    switch submission.context.mode {
    case .add:
        return (nil, nil)
    case .sharedVisit:
        return (nil, nil)
    case .addVisit:
        guard let visit = createExplicitVisitIfNeeded(for: submission, store: store) else {
            return (nil, nil)
        }
        if let backend {
            _ = await store.syncVisit(visitID: visit.id, backend: backend)
        }
        return (SaveResult(userPlaceID: visit.userPlaceID, syncState: visit.syncState), visit)
    case .editVisit(_, let visit):
        guard let updatedVisit = store.updateVisit(
            visitID: visit.id,
            visitedAt: submission.visitedAt,
            note: submission.note,
            ratingScore: submission.ratingScore,
            attributes: submission.attributes,
            categoryCandidate: submission.candidate,
            visibility: submission.visibility,
            replacesNote: true,
            replacesRating: true
        ) else {
            return (nil, nil)
        }
        if let backend {
            _ = await store.syncVisit(visitID: updatedVisit.id, backend: backend)
        }
        return (SaveResult(userPlaceID: updatedVisit.userPlaceID, syncState: updatedVisit.syncState), updatedVisit)
    case .editWant(let visiblePlace):
        let result = await store.saveCandidate(
            submission.candidate,
            status: .wannaGo,
            visibility: submission.visibility,
            note: submission.note,
            sourceType: AddSourceType(rawValue: visiblePlace.userPlace.sourceType) ?? .manual,
            ratingScore: nil,
            plannedDate: submission.plannedDate,
            attributes: submission.attributes,
            backend: backend
        )
        return (result, nil)
    }
}

@MainActor
func persistVisitPhotoAttachments(
    _ attachments: [MapPlaceSavePhotoAttachment],
    to visit: LocalPlaceVisit?,
    store: WanderStore,
    backend: WanderBackend?
) async {
    guard let visit, !attachments.isEmpty else { return }

    for attachment in attachments {
        guard let data = attachment.data() else { continue }
        _ = await store.createVisitPhoto(
            visitID: visit.id,
            data: data,
            localAssetRef: attachment.localAssetRef,
            contentType: attachment.contentType,
            width: attachment.width,
            height: attachment.height,
            backend: backend
        )
    }
}

private enum MapPlaceSaveStep {
    case confirm
    case details
}

enum MapPlaceSaveDetailsPolicy {
    static func usesCompactWannaGoLayout(
        context: MapPlaceSaveContext,
        status: PlaceStatus
    ) -> Bool {
        context.isNewPlaceAdd && status == .wannaGo
    }

    static func suggestedSelections(
        for block: AddQuestionBlock,
        context: MapPlaceSaveContext,
        status: PlaceStatus
    ) -> Set<String> {
        guard block.kind != .multiTag,
              block.valueType != "price_scale"
        else {
            return []
        }

        return usesCompactWannaGoLayout(context: context, status: status)
            ? []
            : Set(block.defaultValues)
    }

    static func synchronizedSelections(
        existing: [String: Set<String>],
        blocks: [AddQuestionBlock],
        context: MapPlaceSaveContext,
        status: PlaceStatus
    ) -> [String: Set<String>] {
        var selections = existing

        for block in blocks where selections[block.key] == nil {
            selections[block.key] = suggestedSelections(
                for: block,
                context: context,
                status: status
            )
        }

        return selections
    }
}

enum PlaceTypePickerMode {
    case category
    case subcategory
    case cuisine
}

struct MapPlaceSaveFlowSheet: View {
    let context: MapPlaceSaveContext
    let onSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?
    let onRemove: @MainActor (MapPlaceSaveContext) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var step: MapPlaceSaveStep = .confirm
    @State private var selectedAssignment: PlaceCategoryAssignment
    @State private var selectedStatus: PlaceStatus
    @State private var selectedVisibility: PlaceVisibility
    @State private var selectedRatingScore: Double
    @State private var selectedAnswers: [String: Set<String>]
    @State private var personalLabels: Set<String>
    @State private var selectedCuisine: String?
    @State private var isChoosingPlaceType = false
    @State private var placeTypePickerMode: PlaceTypePickerMode = .subcategory
    @State private var note: String
    @State private var visitedAt: Date
    @State private var plannedDate: Date?
    @State private var isShowingPlannedDatePicker = false
    @State private var isSaving = false
    @State private var isRemoving = false
    @State private var isShowingRemoveConfirmation = false
    @State private var visitPhotoAttachments: [MapPlaceSavePhotoAttachment] = []
    @State private var selectedInviteeUserIDs: [String] = []
    @State private var isLoadingSharedVisitInvitees = false
    @State private var didLoadSharedVisitInvitees = false
    @State private var sharedVisitInviteesError: String?
    @State private var errorMessage: String?
    @State private var isShowingOptionalDetails = false

    init(
        context: MapPlaceSaveContext,
        onSave: @escaping @MainActor (MapPlaceSaveSubmission) async -> SaveResult?,
        onRemove: @escaping @MainActor (MapPlaceSaveContext) async -> Bool
    ) {
        self.context = context
        self.onSave = onSave
        self.onRemove = onRemove
        _step = State(initialValue: context.startsOnDetails ? .details : .confirm)
        _selectedAssignment = State(initialValue: context.candidate.categoryAssignment)
        _selectedStatus = State(initialValue: context.initialStatus)
        _selectedVisibility = State(initialValue: context.initialVisibility.normalizedForStealthMode)
        _selectedRatingScore = State(initialValue: context.initialRatingScore ?? PlaceRating.defaultScore)
        _selectedAnswers = State(initialValue: context.initialAnswers)
        _personalLabels = State(initialValue: context.initialPersonalLabels)
        _selectedCuisine = State(initialValue: Self.initialCuisine(for: context))
        _note = State(initialValue: context.initialNote)
        _visitedAt = State(initialValue: context.editedVisit?.visitedAt ?? .now)
        let today = WannaGoDate.normalized(.now)
        let initialPlannedDate = context.initialPlannedDate
            .map { WannaGoDate.normalized($0) }
            .flatMap { $0 >= today ? $0 : nil }
        _plannedDate = State(initialValue: initialPlannedDate)
        _visitPhotoAttachments = State(initialValue: context.initialPhotoAttachments)
    }

    private var questionBlocks: [AddQuestionBlock] {
        AddQuestionTemplates.blocks(
            primaryCategory: selectedAssignment.primaryCategory,
            subcategory: selectedAssignment.subcategory,
            cuisine: selectedCuisine,
            status: selectedStatus,
            localTagOptions: localCustomTagOptions()
        )
    }

    private var selectedCandidate: PlaceCandidate {
        context.candidate.recategorized(as: selectedAssignmentForSave)
    }

    private var selectedAssignmentForSave: PlaceCategoryAssignment {
        if selectedAssignment.comparableKey == context.candidate.categoryAssignment.comparableKey,
           context.candidate.categorySource != PlaceCategorySource.user.rawValue {
            return context.candidate.categoryAssignment
        }

        return selectedAssignment.withSource(.user, confidence: 1)
    }

    private var personalLabelBlock: AddQuestionBlock {
        AddQuestionBlock(
            key: PlaceMemoryAttributeKeys.personalLabels,
            title: "my labels",
            tag: "labels",
            kind: .multiTag,
            valueType: "personal_label",
            options: PlacePersonalLabelSuggestions.options(
                category: selectedAssignment.primaryCategory,
                subcategory: selectedAssignment.subcategory,
                cuisine: selectedCuisine,
                status: selectedStatus,
                locality: context.candidate.locality,
                localOptions: localCustomPersonalLabelOptions()
            ),
            defaultValues: PlacePersonalLabelSuggestions.defaultValues(
                category: selectedAssignment.primaryCategory,
                subcategory: selectedAssignment.subcategory,
                cuisine: selectedCuisine,
                status: selectedStatus,
                locality: context.candidate.locality
            ),
            minimumOptionWidth: 104
        )
    }

    private var isRestaurantsFoodSelected: Bool {
        selectedAssignmentForSave.primaryCategory == WanderPlaceCategory.restaurantsFood
    }

    private var saveVisibility: PlaceVisibility {
        store.isPrivateProfile ? .selfOnly : selectedVisibility
    }

    private var selectedVisibilityForStealthToggle: Binding<PlaceVisibility> {
        Binding(
            get: { store.isPrivateProfile ? .selfOnly : selectedVisibility },
            set: { newVisibility in
                selectedVisibility = store.isPrivateProfile ? .selfOnly : newVisibility
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: step == .details ? WanderTheme.spacing3 : WanderTheme.spacing4) {
                    header

                    switch step {
                    case .confirm:
                        confirmContent
                    case .details:
                        detailsContent
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WanderTheme.canvasWarm.color)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if step == .details {
                    saveFooter
                }
            }
            .sheet(isPresented: $isChoosingPlaceType) {
                PlaceTypePickerSheet(
                    selectedAssignment: $selectedAssignment,
                    selectedCuisine: $selectedCuisine,
                    placeName: context.candidate.name,
                    suggestedCuisine: cuisineSuggestionValue,
                    suggestionReason: cuisineSuggestionReason,
                    recentCuisines: recentRestaurantCuisines,
                    initialMode: placeTypePickerMode
                ) {
                    handlePlaceTypeSelection()
                }
                .id(placeTypePickerMode)
            }
            .onAppear {
                store.saveFlowDidPresent(.saveSheet)
                if store.isPrivateProfile {
                    selectedVisibility = .selfOnly
                }
                if step == .details {
                    syncAnswersForCurrentQuestions()
                }
            }
            .task {
                await loadSharedVisitInviteesIfNeeded()
            }
            .onChange(of: store.isPrivateProfile) { _, isPrivateProfile in
                if isPrivateProfile {
                    selectedVisibility = .selfOnly
                    selectedInviteeUserIDs = []
                }
            }
            .onChange(of: canInviteFriends) { _, canInvite in
                if !canInvite {
                    selectedInviteeUserIDs = []
                }
            }
            .alert(context.removeConfirmationTitle, isPresented: $isShowingRemoveConfirmation) {
                Button(context.removeTitle, role: .destructive) {
                    removeSave()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(context.removeConfirmationMessage)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                if step == .details && context.requiresStatusConfirmation {
                    Button {
                        errorMessage = nil
                        step = .confirm
                    } label: {
                        Label("back", systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .background(WanderTheme.surfaceSand.color)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            Text(flowTitle)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            if step == .confirm {
                Text(context.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
        }
    }

    private var flowTitle: String {
        guard step == .details, selectedStatus == .been else {
            return context.title
        }

        switch context.mode {
        case .add:
            return "Check in at \(context.candidate.name)"
        case .addVisit:
            return CheckInCopy.againAction
        case .sharedVisit:
            return "Check in from invite"
        case .editVisit:
            return CheckInCopy.editAction
        case .editWant:
            return context.title
        }
    }

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            candidateCard

            MapSavePickerBlock(title: "what do you want to do?") {
                HStack(spacing: WanderTheme.spacing2) {
                    MapSaveChoicePill(title: CheckInCopy.verb, isSelected: selectedStatus == .been) {
                        selectedStatus = .been
                    }
                    MapSaveChoicePill(title: "wanna go", isSelected: selectedStatus == .wannaGo) {
                        selectedStatus = .wannaGo
                    }
                }
            }

            WanderPrimaryButton(title: "continue to details", systemImage: "arrow.right") {
                prepareDetails()
            }
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            candidateCard

            if selectedStatus == .been {
                checkInDateSection
            }

            placeTypeSection

            if selectedStatus == .been {
                ratingSection

                if canInviteFriends {
                    sharedVisitInviteSection
                }

                if context.allowsPhotoAttachments {
                    MapSaveVisitPhotoSection(
                        canAddPhotos: true,
                        photos: $visitPhotoAttachments
                    )
                }
            }

            optionalDetailsDisclosure

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

            if context.showsRemoveControl {
                removeSaveSection
            }
        }
    }

    private var saveFooter: some View {
        WanderPrimaryButton(
            title: isSaving ? progressActionTitle : primaryActionTitle,
            systemImage: selectedStatus == .been ? "ticket.fill" : "checkmark",
            isDisabled: isSaving || isRemoving
        ) {
            save()
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing2)
        .background(WanderTheme.canvasWarm.color)
    }

    private var primaryActionTitle: String {
        if selectedStatus == .wannaGo {
            if case .editWant = context.mode {
                return "Update Wanna"
            }
            return "Add to Wanna"
        }
        return context.saveTitle
    }

    private var progressActionTitle: String {
        selectedStatus == .been ? "Checking in..." : "Adding to Wanna..."
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("a note for future you")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("what you'll want to remember, who told you...", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .lineLimit(3, reservesSpace: true)
                .padding(WanderTheme.spacing3)
                .background(WanderTheme.surfaceRaised.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }

    private var plannedDateSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("when do you wanna go?")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isShowingPlannedDatePicker.toggle()
                    }
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .frame(width: 38, height: 38)
                            .background(WanderTheme.terracottaTint.color)
                            .clipShape(Circle())

                        if let plannedDate {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("planned for")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(WanderTheme.textMuted.color)
                                Text(WannaGoDate.displayString(for: plannedDate))
                                    .font(.system(size: 14, weight: .black))
                                    .foregroundStyle(WanderTheme.textInk.color)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                            }
                        } else {
                            Text("add a date")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .rotationEffect(.degrees(isShowingPlannedDatePicker ? 180 : 0))
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .frame(minHeight: 58)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(plannedDate == nil ? "Add a Wanna go date" : "Change Wanna go date")
                .accessibilityValue(plannedDate.map { WannaGoDate.displayString(for: $0) } ?? "No date selected")

                if isShowingPlannedDatePicker {
                    Divider().background(WanderTheme.borderHairline.color)

                    MultiDatePicker(
                        "Wanna go date",
                        selection: Binding(
                            get: {
                                WannaGoDate.calendarSelection(for: plannedDate)
                            },
                            set: { nextSelection in
                                plannedDate = WannaGoDate.singleDate(
                                    from: nextSelection,
                                    replacing: plannedDate
                                )
                            }
                        ),
                        in: WannaGoDate.normalized(.now)...
                    )
                    .labelsHidden()
                    .tint(WanderTheme.terracotta.color)
                    .padding(.horizontal, WanderTheme.spacing2)

                    HStack {
                        Label("Past dates are unavailable", systemImage: "calendar.badge.exclamationmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)

                        Spacer()

                        if plannedDate != nil {
                            Button("clear") {
                                plannedDate = nil
                                isShowingPlannedDatePicker = false
                            }
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracottaDark.color)
                        }
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing3)
                }
            }
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )

            Text("If notifications are on, rec.me will remind you three days before.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var questionAndLabelSections: some View {
        ForEach(questionBlocks) { block in
            MapSaveQuestionBlock(title: block.title, tag: block.tag) {
                MapSaveQuestionOptions(
                    block: block,
                    selectedValues: selections(for: block)
                ) { option in
                    toggleAnswer(option, in: block)
                }
            }
        }

        MapSaveQuestionBlock(title: personalLabelBlock.title, tag: personalLabelBlock.tag) {
            MapSaveQuestionOptions(
                block: personalLabelBlock,
                selectedValues: personalLabels
            ) { option in
                togglePersonalLabel(option)
            }
        }
    }

    private var sharedVisitInviteSection: some View {
        SharedVisitInviteSection(
            selectedUserIDs: $selectedInviteeUserIDs,
            isLoading: isLoadingSharedVisitInvitees,
            errorMessage: sharedVisitInviteesError,
            onRetry: context.editedVisit == nil ? nil : {
                didLoadSharedVisitInvitees = false
                Task { await loadSharedVisitInviteesIfNeeded() }
            }
        )
    }

    private var visibilitySection: some View {
        PlaceVisibilityStealthToggle(
            title: store.isPrivateProfile ? "stealth mode locked on" : "stealth mode",
            visibility: selectedVisibilityForStealthToggle,
            helperCopy: { visibility in
                store.isPrivateProfile
                    ? "Locked on by Private Profile. This place stays hidden while your profile is private."
                    : visibility.stealthModeHelperCopy
            }
        )
        .disabled(store.isPrivateProfile)
    }

    private var optionalDetailsDisclosure: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isShowingOptionalDetails.toggle()
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Text("more options")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Text(optionalDetailsSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .rotationEffect(.degrees(isShowingOptionalDetails ? 180 : 0))
                }
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(WanderTheme.surfaceBone.color)
                .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .stroke(WanderTheme.borderHairline.color)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShowingOptionalDetails ? "Hide more options" : "Show more options")
            .accessibilityValue(isShowingOptionalDetails ? "Expanded" : "Collapsed")
            .accessibilityHint("Optional. Continue without opening this section.")

            if isShowingOptionalDetails {
                if selectedStatus == .wannaGo {
                    plannedDateSection
                }
                noteSection
                questionAndLabelSections
                visibilitySection
            }
        }
    }

    private var optionalDetailsSummary: String {
        if selectedStatus == .wannaGo, let plannedDate {
            return "planned \(plannedDate.formatted(.dateTime.month(.abbreviated).day())) · note & privacy"
        }
        return selectedStatus == .wannaGo
            ? "date, note, tags & privacy"
            : "note, tags, labels & privacy"
    }

    private var removeSaveSection: some View {
        MapSaveDestructiveButton(
            title: isRemoving ? "removing..." : context.removeTitle,
            systemImage: "trash",
            isDisabled: isSaving || isRemoving
        ) {
            isShowingRemoveConfirmation = true
        }
        .padding(.top, WanderTheme.spacing1)
    }

    private var ratingSection: some View {
        PlaceRatingSlider(score: $selectedRatingScore, isCompact: true)
    }

    private var checkInDateSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("when")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

            DatePicker(
                "Check-in date",
                selection: $visitedAt,
                in: ...Date.now,
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .font(.system(size: 14, weight: .bold))
            .tint(WanderTheme.terracotta.color)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )
        }
    }

    private var canInviteFriends: Bool {
        guard selectedStatus == .been,
              auth.isSignedIn,
              !store.isPrivateProfile,
              saveVisibility != .selfOnly
        else { return false }

        switch context.mode {
        case .add, .addVisit, .editVisit:
            return true
        case .sharedVisit, .editWant:
            return false
        }
    }

    private var placeTypeSection: some View {
        let display = WanderPlaceCategory.display(for: selectedAssignmentForSave)
        let categoryValue = selectedAssignmentForSave.primaryCategory == WanderPlaceCategory.fallbackPlace
            ? "choose category"
            : display.category

        return VStack(alignment: .leading, spacing: 0) {
            Text("place type")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 36)

            Divider().background(WanderTheme.borderHairline.color)

            VStack(spacing: 0) {
                Button {
                    placeTypePickerMode = .category
                    isChoosingPlaceType = true
                } label: {
                    PlaceTypeRow(title: "category", value: categoryValue)
                }
                .buttonStyle(.plain)

                Divider().background(WanderTheme.borderHairline.color)

                if isRestaurantsFoodSelected {
                    Button {
                        placeTypePickerMode = .cuisine
                        isChoosingPlaceType = true
                    } label: {
                        PlaceTypeRow(
                            title: "cuisine",
                            value: selectedCuisine ?? "optional",
                            isPlaceholderValue: selectedCuisine == nil
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        placeTypePickerMode = .subcategory
                        isChoosingPlaceType = true
                    } label: {
                        PlaceTypeRow(title: "subcategory", value: display.subcategory ?? "choose one")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color)
        )
    }

    private var candidateCard: some View {
        HStack(spacing: WanderTheme.spacing2) {
            CategoryThumb(
                emoji: WanderPlaceCategory.emoji(
                    for: selectedAssignment,
                    cuisine: selectedCuisine,
                    name: context.candidate.name
                ),
                size: 40
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: WanderTheme.spacing2) {
                    Text(context.candidate.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.84)

                    Spacer(minLength: WanderTheme.spacing1)

                    Text(selectedStatus.displayTitle)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.terracotta.color)
                        .padding(.horizontal, WanderTheme.spacing2)
                        .padding(.vertical, WanderTheme.spacing1)
                        .background(WanderTheme.terracottaTint.color)
                        .clipShape(Capsule())
                }

                Text(candidateSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var candidateSubtitle: String {
        selectedCandidate.previewSubtitle(
            includeDistance: false,
            includeCategory: false
        )
    }

    private var cuisineSuggestionValue: String? {
        Self.initialCuisine(for: context)
    }

    private var cuisineSuggestionReason: String? {
        guard let suggestion = cuisineSuggestionValue else { return nil }

        if let inference = WanderPlaceCategory.restaurantCuisineInference(for: context.candidate),
           inference.cuisine.caseInsensitiveCompare(suggestion) == .orderedSame {
            return inference.reason
        }

        return "Already on your map"
    }

    private var recentRestaurantCuisines: [String] {
        let uses = store
            .visiblePlaces(
                filters: PlaceFilters(
                    categories: [WanderPlaceCategory.restaurantsFood],
                    ownerScopes: ["you"]
                )
            )
            .compactMap { visiblePlace -> RestaurantCuisineUse? in
                guard let cuisine = visiblePlace.restaurantCuisine else { return nil }
                return RestaurantCuisineUse(
                    cuisine: cuisine,
                    savedAt: visiblePlace.userPlace.savedAt
                )
            }

        return WanderPlaceCategory.recentRestaurantCuisines(from: uses)
    }

    private static func initialCuisine(for context: MapPlaceSaveContext) -> String? {
        guard context.candidate.primaryCategory == WanderPlaceCategory.restaurantsFood else {
            return nil
        }

        return context.initialCuisine
            ?? WanderPlaceCategory.restaurantCuisineInference(for: context.candidate)?.cuisine
    }

    private func prepareDetails() {
        syncAnswersForCurrentQuestions()
        errorMessage = nil
        step = .details
    }

    private func syncAnswersForCurrentQuestions() {
        selectedAnswers = MapPlaceSaveDetailsPolicy.synchronizedSelections(
            existing: selectedAnswers,
            blocks: questionBlocks,
            context: context,
            status: selectedStatus
        )
    }

    private func handlePlaceTypeSelection() {
        if selectedAssignment.primaryCategory != WanderPlaceCategory.restaurantsFood {
            selectedCuisine = nil
        }

        syncAnswersForCurrentQuestions()
    }

    private func toggleAnswer(_ option: String, in block: AddQuestionBlock) {
        var values = selections(for: block)

        switch block.kind {
        case .singleChoice:
            values = [option]
        case .multiTag:
            if values.contains(option) {
                values.remove(option)
            } else {
                values.insert(option)
            }
        }

        selectedAnswers[block.key] = values
    }

    private func selections(for block: AddQuestionBlock) -> Set<String> {
        selectedAnswers[block.key] ?? MapPlaceSaveDetailsPolicy.suggestedSelections(
            for: block,
            context: context,
            status: selectedStatus
        )
    }

    private func togglePersonalLabel(_ option: String) {
        if personalLabels.contains(option) {
            personalLabels.remove(option)
        } else {
            personalLabels.insert(option)
        }
    }

    private func attributeDrafts() -> [PlaceAttributeDraft] {
        var drafts: [PlaceAttributeDraft] = questionBlocks.compactMap { block -> PlaceAttributeDraft? in
            let values = orderedSelections(for: block)
            guard !values.isEmpty else { return nil }

            switch block.kind {
            case .singleChoice:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValue: values[0])
            case .multiTag:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValues: values)
            }
        }

        let orderedPersonalLabels = orderedPersonalLabelSelections()
        if !orderedPersonalLabels.isEmpty {
            drafts.append(
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.personalLabels,
                    valueType: "personal_label",
                    stringValues: orderedPersonalLabels
                )
            )
        }

        let currentKeys = Set(questionBlocks.map(\.key))
        let preservedTagDrafts = selectedAnswers
            .filter { key, values in
                !currentKeys.contains(key) && shouldPreserveHiddenTagAttribute(key) && !values.isEmpty
            }
            .sorted { $0.key < $1.key }
            .map { key, values in
                PlaceAttributeDraft(questionKey: key, valueType: "multi_tag", stringValues: values.sorted())
            }
        drafts.append(contentsOf: preservedTagDrafts)

        if selectedAssignmentForSave.primaryCategory == WanderPlaceCategory.restaurantsFood,
           let selectedCuisine {
            drafts.append(
                PlaceAttributeDraft(
                    questionKey: PlaceMemoryAttributeKeys.restaurantCuisine,
                    valueType: "restaurant_cuisine",
                    stringValue: selectedCuisine
                )
            )
        }

        return drafts
    }

    private func orderedSelections(for block: AddQuestionBlock) -> [String] {
        let values = selections(for: block)
        let optionSelections = block.options.filter { values.contains($0) }
        let customSelections = values
            .filter { value in
                !block.options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            .sorted()
        return optionSelections + customSelections
    }

    private func localCustomTagOptions() -> [String] {
        localAttributeSuggestions { attribute in
            attribute.valueType == "multi_tag" && shouldPreserveHiddenTagAttribute(attribute.questionKey)
        }
    }

    private func localCustomPersonalLabelOptions() -> [String] {
        localAttributeSuggestions { attribute in
            attribute.questionKey == PlaceMemoryAttributeKeys.personalLabels
        }
    }

    private func localAttributeSuggestions(
        matching predicate: (LocalPlaceAttribute) -> Bool
    ) -> [String] {
        let visiblePlaces = store.currentUserVisiblePlaces.filter { visiblePlace in
            if let currentPlace = context.sourceVisiblePlace,
               currentPlace.userPlace.id == visiblePlace.userPlace.id {
                return false
            }
            return visiblePlace.effectiveCategory == selectedAssignment.primaryCategory
        }
        let exactSubcategory = selectedAssignment.subcategory.map { WanderPlaceCategory.normalizedCategoryText($0) }
        let exactPlaces = visiblePlaces.filter { visiblePlace in
            guard let exactSubcategory else { return true }
            return WanderPlaceCategory.normalizedCategoryText(visiblePlace.effectiveSubcategory) == exactSubcategory
        }
        let similarPlaces = visiblePlaces.filter { visiblePlace in
            guard let exactSubcategory else { return false }
            return WanderPlaceCategory.normalizedCategoryText(visiblePlace.effectiveSubcategory) != exactSubcategory
        }
        let exactValues = attributeValues(from: exactPlaces, matching: predicate)
        let similarValues = attributeValues(from: similarPlaces, matching: predicate)

        return uniqueOptionValues(exactValues + similarValues, limit: 8)
    }

    private func attributeValues(
        from visiblePlaces: [VisiblePlace],
        matching predicate: (LocalPlaceAttribute) -> Bool
    ) -> [String] {
        visiblePlaces.flatMap { visiblePlace in
            store.attributes(for: visiblePlace.userPlace.id)
                .filter(predicate)
                .flatMap(Self.stringValues(from:))
        }
    }

    private func uniqueOptionValues(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = WanderPlaceCategory.normalizedCategoryText(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == limit {
                break
            }
        }

        return result
    }

    private func shouldPreserveHiddenTagAttribute(_ key: String) -> Bool {
        key.hasSuffix("_tags") || key == "best_for"
    }

    private static func stringValues(from attribute: LocalPlaceAttribute) -> [String] {
        guard let data = attribute.valueJSON.data(using: .utf8) else { return [] }
        let decoder = JSONDecoder()
        if let values = try? decoder.decode([String].self, from: data) {
            return values
        }
        if let value = try? decoder.decode(String.self, from: data) {
            return [value]
        }
        return []
    }

    private func orderedPersonalLabelSelections() -> [String] {
        let options = personalLabelBlock.options
        let optionSelections = options.filter { personalLabels.contains($0) }
        let customSelections = personalLabels
            .filter { value in
                !options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            .sorted()
        return optionSelections + customSelections
    }

    private func save() {
        guard !isSaving else { return }
        guard selectedStatus != .been || visitedAt <= Date.now else {
            errorMessage = "A check-in date can’t be in the future."
            return
        }
        isSaving = true
        errorMessage = nil

        let submission = MapPlaceSaveSubmission(
            context: context,
            candidate: selectedCandidate,
            status: selectedStatus,
            visibility: saveVisibility,
            ratingScore: selectedStatus == .been ? selectedRatingScore : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            attributes: attributeDrafts(),
            photoAttachments: visitPhotoAttachments,
            inviteeUserIDs: canInviteFriends ? selectedInviteeUserIDs : [],
            reconcilesSharedVisitInvitees: context.editedVisit != nil
                && canInviteFriends
                && didLoadSharedVisitInvitees,
            visitedAt: visitedAt,
            plannedDate: selectedStatus == .wannaGo ? plannedDate : nil
        )

        Task {
            let result = await onSave(submission)
            await MainActor.run {
                isSaving = false
                if result != nil {
                    dismiss()
                } else if auth.isSignedIn {
                    if context.sharedVisitInvitation != nil {
                        errorMessage = "Could not add this shared check-in. Open the invitation and try again."
                    } else {
                        errorMessage = selectedStatus == .been
                            ? "Could not check in. Try again."
                            : "Could not add this to Wanna. Try again."
                    }
                } else {
                    errorMessage = selectedStatus == .been
                        ? "Sign in to finish your check-in."
                        : "Sign in to add this to Wanna."
                }
            }
        }
    }

    private func loadSharedVisitInviteesIfNeeded() async {
        guard !didLoadSharedVisitInvitees,
              let visit = context.editedVisit,
              canInviteFriends
        else { return }

        isLoadingSharedVisitInvitees = true
        sharedVisitInviteesError = nil
        do {
            selectedInviteeUserIDs = try await store.sharedVisitInviteeUserIDs(
                sourceVisitID: visit.id,
                backend: backend
            )
            didLoadSharedVisitInvitees = true
        } catch {
            sharedVisitInviteesError = "Could not load shared friends. Your check-in can still be edited without changing them."
        }
        isLoadingSharedVisitInvitees = false
    }

    private var removeSaveConfirmationMessage: String {
        context.removeConfirmationMessage
    }

    private func removeSave() {
        guard context.showsRemoveControl, !isSaving, !isRemoving else { return }

        isRemoving = true
        errorMessage = nil

        Task {
            let removed = await onRemove(context)
            await MainActor.run {
                isRemoving = false
                if removed {
                    dismiss()
                } else {
                    errorMessage = "Could not remove this place from your map. Try again."
                }
            }
        }
    }
}

private struct MapSaveVisitPhotoSection: View {
    let canAddPhotos: Bool
    @Binding var photos: [MapPlaceSavePhotoAttachment]
    @State private var isShowingPhotoMenu = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Button {
                if canAddPhotos && photos.count < MapPlaceSavePhotoAttachment.maximumCount {
                    isShowingPhotoMenu = true
                }
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.pinSocial.color)
                    Text("photos")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Spacer()

                    Text(photos.isEmpty ? "add" : "\(photos.count) added")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)

                    if canAddPhotos && photos.count < MapPlaceSavePhotoAttachment.maximumCount {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .disabled(!canAddPhotos || photos.count >= MapPlaceSavePhotoAttachment.maximumCount)
            .confirmationDialog("Add photos to your check-in", isPresented: $isShowingPhotoMenu, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        isShowingCamera = true
                    }
                }
                Button("Choose from Library") {
                    isShowingPhotoMenu = false
                    isShowingPhotoPicker = true
                }
                Button("Cancel", role: .cancel) {}
            }

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, attachment in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: attachment.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 82, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

                                Button {
                                    photos.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(WanderTheme.textInk.color)
                                        .frame(width: 24, height: 24)
                                        .background(WanderTheme.surfaceRaised.color)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(5)
                                .accessibilityLabel("Remove photo")
                            }
                        }
                    }
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .padding(.bottom, WanderTheme.spacing3)
            }

            if !canAddPhotos {
                Text("Photos can be added after you check in.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing3)
            }

            if let photoError {
                Text(photoError)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing3)
            }
        }
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color)
        )
        .sheet(isPresented: $isShowingCamera) {
            PlaceActivityCameraPicker { image in
                if let attachment = MapPlaceSavePhotoAttachment.make(image: image) {
                    appendIfWithinLimits(attachment)
                } else {
                    photoError = "That photo is too large or could not be prepared."
                }
                isShowingPhotoMenu = false
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(1, MapPlaceSavePhotoAttachment.maximumCount - photos.count),
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            isShowingPhotoMenu = false
            Task {
                await importPhotos(from: items)
            }
        }
        .onChange(of: canAddPhotos) { _, nextCanAddPhotos in
            if !nextCanAddPhotos {
                isShowingPhotoMenu = false
            }
        }
    }

    private func importPhotos(from items: [PhotosPickerItem]) async {
        var imported: [MapPlaceSavePhotoAttachment] = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    continue
                }
                let assetRef = item.itemIdentifier.map { "photos_picker:\($0)" }
                if let attachment = MapPlaceSavePhotoAttachment.make(
                    image: image,
                    data: data,
                    fallbackAssetRef: assetRef
                ) {
                    imported.append(attachment)
                }
            } catch {
                await MainActor.run {
                    photoError = "Could not use one of those photos."
                }
            }
        }

        await MainActor.run {
            for attachment in imported {
                appendIfWithinLimits(attachment)
            }
            selectedPhotoItems = []
        }
    }

    private func appendIfWithinLimits(_ attachment: MapPlaceSavePhotoAttachment) {
        guard photos.count < MapPlaceSavePhotoAttachment.maximumCount else {
            photoError = "A check-in can have up to 10 photos."
            return
        }
        guard photos.reduce(0, { $0 + $1.byteSize }) + attachment.byteSize <= MapPlaceSavePhotoAttachment.maximumTotalBytes else {
            photoError = "Those photos are over the 75 MB check-in limit."
            return
        }
        photoError = nil
        photos.append(attachment)
    }
}

private struct MapSavePickerBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            content
        }
    }
}

private struct MapSaveChoicePill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .frame(minHeight: WanderTheme.tapMinimum)
                .padding(.horizontal, WanderTheme.spacing3)
                .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
                .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
    }
}

private struct MapSaveDestructiveButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WanderTheme.stateError.color)
            .foregroundStyle(WanderTheme.textOnAction.color)
            .clipShape(Capsule())
            .opacity(isDisabled ? 0.52 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title)
    }
}

private struct PlaceTypeRow: View {
    let title: String
    let value: String
    var isPlaceholderValue = false

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isPlaceholderValue ? WanderTheme.textFaint.color : WanderTheme.textInk.color)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: WanderTheme.tapMinimum)
    }
}

struct PlaceTypePickerSheet: View {
    @Binding var selectedAssignment: PlaceCategoryAssignment
    @Binding var selectedCuisine: String?
    let placeName: String
    let suggestedCuisine: String?
    let suggestionReason: String?
    let initialMode: PlaceTypePickerMode
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlaceTypePickerMode
    @State private var query = ""
    @State private var recentCuisines: [String]
    @State private var selectedCuisineRegion = "Popular"
    @State private var selectedSubcategoryGroup = "All"

    init(
        selectedAssignment: Binding<PlaceCategoryAssignment>,
        selectedCuisine: Binding<String?>,
        placeName: String,
        suggestedCuisine: String?,
        suggestionReason: String?,
        recentCuisines: [String],
        initialMode: PlaceTypePickerMode,
        onSelect: @escaping () -> Void
    ) {
        _selectedAssignment = selectedAssignment
        _selectedCuisine = selectedCuisine
        self.placeName = placeName
        self.suggestedCuisine = suggestedCuisine
        self.suggestionReason = suggestionReason
        self.initialMode = initialMode
        self.onSelect = onSelect
        _recentCuisines = State(initialValue: recentCuisines)

        let primaryCategory = selectedAssignment.wrappedValue.primaryCategory
        let hasEditableSelection = WanderPlaceCategory.editableCategories.contains(primaryCategory)
        let startingMode: PlaceTypePickerMode
        if !hasEditableSelection {
            startingMode = .category
        } else if primaryCategory == WanderPlaceCategory.restaurantsFood,
                  initialMode == .subcategory {
            startingMode = .cuisine
        } else if primaryCategory != WanderPlaceCategory.restaurantsFood,
                  initialMode == .cuisine {
            startingMode = .subcategory
        } else {
            startingMode = initialMode
        }
        _mode = State(initialValue: startingMode)
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredCategories: [String] {
        let queryText = normalizedQuery.lowercased()
        guard !queryText.isEmpty else {
            return WanderPlaceCategory.editableCategories
        }

        return WanderPlaceCategory.editableCategories.filter { category in
            WanderPlaceCategory.broadCategory(for: category).localizedCaseInsensitiveContains(queryText)
                || WanderPlaceCategory.categoryDetail(for: category).localizedCaseInsensitiveContains(queryText)
                || WanderPlaceCategory.subcategorySuggestions(for: category).contains { subcategory in
                    subcategory.localizedCaseInsensitiveContains(queryText)
                }
        }
    }

    private var selectedPrimaryCategory: String {
        selectedAssignment.primaryCategory
    }

    private var hasEditableSelection: Bool {
        WanderPlaceCategory.editableCategories.contains(selectedPrimaryCategory)
    }

    private var subcategoryGroupsForCurrentSelection: [PlaceCategorySubcategoryGroup] {
        WanderPlaceCategory.subcategoryGroups(for: selectedPrimaryCategory)
    }

    private var selectedCategoryTitle: String {
        WanderPlaceCategory.broadCategory(for: selectedPrimaryCategory)
    }

    private var subcategoryFilterTitles: [String] {
        ["All"] + groupsForCurrentSelection(role: .type).map(\.title)
    }

    private var filteredSubcategoryOptions: [String] {
        let groups = groupsForCurrentSelection(role: .type)
        let queryText = normalizedQuery

        if !queryText.isEmpty {
            return groups.flatMap { group in
                if group.title.localizedCaseInsensitiveContains(queryText) {
                    return group.subcategories
                }
                return group.subcategories.filter {
                    $0.localizedCaseInsensitiveContains(queryText)
                }
            }
        }

        guard selectedSubcategoryGroup != "All" else {
            return groups.flatMap(\.subcategories)
        }

        return groups
            .first(where: { $0.title == selectedSubcategoryGroup })?
            .subcategories ?? groups.flatMap(\.subcategories)
    }

    private var filteredCuisineOptions: [String] {
        let groups = WanderPlaceCategory.restaurantCuisineGroups()
        let queryText = normalizedQuery

        if !queryText.isEmpty {
            return groups.flatMap { group in
                if group.title.localizedCaseInsensitiveContains(queryText) {
                    return group.subcategories
                }
                return group.subcategories.filter {
                    $0.localizedCaseInsensitiveContains(queryText)
                }
            }
        }

        guard let selectedFilter = RestaurantCuisineRegionFilter.options.first(where: {
            $0.id == selectedCuisineRegion
        }) else {
            return groups.flatMap(\.subcategories)
        }

        if let cuisines = selectedFilter.cuisines {
            return cuisines
        }

        let groupTitles = Set(selectedFilter.groupTitles)
        return groups
            .filter { groupTitles.contains($0.title) }
            .flatMap(\.subcategories)
    }

    private var customSearchSubcategory: String? {
        guard mode == .subcategory,
              hasEditableSelection,
              let custom = WanderPlaceCategory.normalizedSubcategory(normalizedQuery),
              custom.count > 1
        else { return nil }

        let optionRole: PlaceCategorySubcategoryRole? = selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood ? .type : nil
        let alreadyExists = optionsForCurrentSelection(role: optionRole).contains { subcategory in
            subcategory.caseInsensitiveCompare(custom) == .orderedSame
        }
        return alreadyExists ? nil : custom
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                switch mode {
                case .category:
                    categoryPickerContent
                case .subcategory:
                    subcategoryPickerContent
                case .cuisine:
                    cuisinePickerContent
                }
            }
            .padding(.horizontal, WanderTheme.spacing4)
            .padding(.top, WanderTheme.spacing4)
            .padding(.bottom, WanderTheme.spacing8)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(WanderTheme.canvasWarm.color.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode == .subcategory,
               hasEditableSelection,
               selectedPrimaryCategory != WanderPlaceCategory.restaurantsFood {
                PlaceTypeSelectionFooter(
                    label: "TYPE",
                    value: selectedAssignment.subcategory ?? "Choose a type"
                ) {
                    dismiss()
                }
            } else if mode == .cuisine,
                      selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood {
                RestaurantCuisineSelectionFooter(cuisine: selectedCuisine) {
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var categoryPickerContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            CategoryPickerHeader(title: "choose category", subtitle: "\(WanderPlaceCategory.editableCategories.count) primary categories")

            CategoryPickerSearchField(placeholder: "Search primary categories", text: $query)

            if filteredCategories.isEmpty {
                CategoryPickerEmptyState(title: "No category found", message: "Try restaurant, trail, gym, hotel, shop, or transit.")
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: WanderTheme.spacing2),
                        GridItem(.flexible(), spacing: WanderTheme.spacing2)
                    ],
                    spacing: WanderTheme.spacing2
                ) {
                    ForEach(filteredCategories, id: \.self) { category in
                        PrimaryCategoryPickerTile(
                            category: category,
                            isSelected: category == selectedAssignment.primaryCategory
                        ) {
                            selectPrimaryCategory(category)
                        }
                    }
                }
            }
        }
    }

    private var subcategoryPickerContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            CategoryPickerHeader(
                title: "explore types",
                subtitle: "Pick the closest match. You can change it anytime."
            )

            selectedCategoryPills

            CategoryPickerSearchField(placeholder: "Search types", text: $query)

            if !hasEditableSelection {
                CategoryPickerEmptyState(title: "Choose a category first", message: "Pick one of the 14 primary categories, then choose its type.")
            } else {
                SubcategoryAtlasFilters(
                    titles: subcategoryFilterTitles,
                    selectedTitle: $selectedSubcategoryGroup
                ) {
                    query = ""
                }
            }

            if hasEditableSelection, filteredSubcategoryOptions.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    CategoryPickerEmptyState(title: "No matching type", message: "Try a broader search, or add your custom type below.")
                    customSubcategoryControl
                }
            } else if hasEditableSelection {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: WanderTheme.spacing2),
                        GridItem(.flexible(), spacing: WanderTheme.spacing2)
                    ],
                    spacing: WanderTheme.spacing2
                ) {
                    ForEach(filteredSubcategoryOptions, id: \.self) { subcategory in
                        PlaceTypeAtlasTile(
                            category: selectedPrimaryCategory,
                            subcategory: subcategory,
                            isSelected: selectedAssignment.subcategory?.caseInsensitiveCompare(subcategory) == .orderedSame
                        ) {
                            selectSubcategory(subcategory)
                        }
                    }
                }

                customSubcategoryControl
            }
        }
    }

    private var cuisinePickerContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            CategoryPickerHeader(
                title: "explore cuisines",
                subtitle: "We’ll start with our best guess. Change it only if we missed."
            )

            if selectedPrimaryCategory != WanderPlaceCategory.restaurantsFood {
                CategoryPickerEmptyState(title: "Choose Restaurants & Food first", message: "Cuisine only applies to restaurants and food places.")
            } else {
                selectedCategoryPills

                if let suggestedCuisine,
                   WanderPlaceCategory.isRestaurantCuisine(suggestedCuisine) {
                    RestaurantCuisineSuggestionCard(
                        placeName: placeName,
                        cuisine: suggestedCuisine,
                        reason: suggestionReason ?? "Best match from the place details",
                        isSelected: selectedCuisine?.caseInsensitiveCompare(suggestedCuisine) == .orderedSame
                    ) {
                        selectCuisine(suggestedCuisine)
                    }
                }

                CategoryPickerSearchField(placeholder: "Search cuisines", text: $query)

                if !recentCuisines.isEmpty {
                    RestaurantCuisineRecentsStrip(
                        cuisines: recentCuisines,
                        selectedCuisine: selectedCuisine,
                        onSelect: selectCuisine
                    )
                }

                RestaurantCuisineRegionFilters(
                    selectedRegion: $selectedCuisineRegion
                ) {
                    query = ""
                }

                if filteredCuisineOptions.isEmpty {
                    CategoryPickerEmptyState(
                        title: "No matching cuisine",
                        message: "Try Thai, Mexican, Korean BBQ, or South American."
                    )
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: WanderTheme.spacing2),
                            GridItem(.flexible(), spacing: WanderTheme.spacing2)
                        ],
                        spacing: WanderTheme.spacing2
                    ) {
                        ForEach(filteredCuisineOptions, id: \.self) { cuisine in
                            RestaurantCuisineAtlasTile(
                                cuisine: cuisine,
                                isSelected: selectedCuisine?.caseInsensitiveCompare(cuisine) == .orderedSame
                            ) {
                                selectCuisine(cuisine)
                            }
                        }
                    }
                }

                clearCuisineControl
            }
        }
    }

    private var selectedCategoryPills: some View {
        HStack(spacing: WanderTheme.spacing2) {
            CategoryPickerModePill(
                title: selectedCategoryTitle,
                category: selectedPrimaryCategory,
                isSelected: true
            )
            Button {
                query = ""
                mode = .category
            } label: {
                CategoryPickerModePill(title: "change", systemImage: "square.grid.2x2", isSelected: false)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    @ViewBuilder
    private var clearCuisineControl: some View {
        if selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood,
           selectedCuisine != nil {
            Button {
                selectedCuisine = nil
                onSelect()
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                    Text("No cuisine")
                        .font(.system(size: 13, weight: .black))
                }
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 42)
                .background(WanderTheme.surfaceRaised.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear cuisine")
        }
    }

    @ViewBuilder
    private var customSubcategoryControl: some View {
        if let customSearchSubcategory {
            Button {
                selectSubcategory(customSearchSubcategory)
            } label: {
                HStack(spacing: WanderTheme.spacing2) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .black))
                    Text("Use \"\(customSearchSubcategory)\"")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .font(.system(size: 13, weight: .black))
                .padding(.horizontal, WanderTheme.spacing3)
                .frame(minHeight: 42)
                .background(WanderTheme.surfaceRaised.color)
                .foregroundStyle(WanderTheme.textInk.color)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use custom subcategory \(customSearchSubcategory)")
        }
    }

    private func selectPrimaryCategory(_ category: String) {
        selectedAssignment = WanderPlaceCategory.assignment(
            primaryCategory: category,
            subcategory: WanderPlaceCategory.defaultSubcategory(for: category),
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: selectedAssignment.rawProviderType
        )

        if category == WanderPlaceCategory.restaurantsFood {
            selectedCuisine = selectedCuisine
                ?? WanderPlaceCategory.cuisineGuess(forRawValue: selectedAssignment.rawProviderType)
        } else {
            selectedCuisine = nil
        }

        query = ""
        selectedSubcategoryGroup = "All"
        mode = category == WanderPlaceCategory.restaurantsFood ? .cuisine : .subcategory
        onSelect()
    }

    private func selectCuisine(_ cuisine: String) {
        selectedCuisine = cuisine
        recentCuisines = WanderPlaceCategory.updatingRecentRestaurantCuisines(
            recentCuisines,
            selecting: cuisine
        )
        onSelect()
    }

    private func selectSubcategory(_ subcategory: String) {
        selectedAssignment = PlaceCategoryAssignment(
            primaryCategory: selectedPrimaryCategory,
            subcategory: subcategory,
            source: PlaceCategorySource.user.rawValue,
            confidence: 1,
            rawProviderType: selectedAssignment.rawProviderType
        )
        onSelect()
    }

    private func optionsForCurrentSelection(role: PlaceCategorySubcategoryRole?) -> [String] {
        groupsForCurrentSelection(role: role).flatMap(\.subcategories)
    }

    private func groupsForCurrentSelection(role: PlaceCategorySubcategoryRole?) -> [PlaceCategorySubcategoryGroup] {
        let groups = subcategoryGroupsForCurrentSelection
        guard let role else {
            return groups
        }

        if selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood {
            return groups.filter { $0.role == role }
        }

        return role == .type ? groups : []
    }
}

private struct RestaurantCuisineRegionFilter: Identifiable {
    let id: String
    let groupTitles: [String]
    let cuisines: [String]?

    static let options = [
        RestaurantCuisineRegionFilter(
            id: "Popular",
            groupTitles: [],
            cuisines: WanderPlaceCategory.restaurantPopularCuisineOptions
        ),
        RestaurantCuisineRegionFilter(id: "Asia", groupTitles: ["Asian"], cuisines: nil),
        RestaurantCuisineRegionFilter(id: "Europe", groupTitles: ["Europe"], cuisines: nil),
        RestaurantCuisineRegionFilter(
            id: "Americas & Pacific",
            groupTitles: ["Americas & Pacific"],
            cuisines: nil
        ),
        RestaurantCuisineRegionFilter(
            id: "Mideast & Africa",
            groupTitles: ["Middle East & Africa"],
            cuisines: nil
        ),
        RestaurantCuisineRegionFilter(id: "More", groupTitles: ["Misc"], cuisines: nil)
    ]
}

private struct RestaurantCuisineSuggestionCard: View {
    let placeName: String
    let cuisine: String
    let reason: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing3) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                        .fill(WanderTheme.terracotta.color)
                    WanderCategoryEmoji(
                        category: WanderPlaceCategory.restaurantsFood,
                        cuisine: cuisine,
                        name: placeName,
                        size: 26
                    )
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Label("BEST GUESS", systemImage: "sparkles")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(WanderTheme.terracottaDark.color)

                    Text(cuisine)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)

                    Text(reason)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .black))
                    .foregroundStyle(isSelected ? WanderTheme.terracotta.color : WanderTheme.textFaint.color)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.terracotta.color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Best guess for \(placeName): \(cuisine)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(reason)
    }
}

private struct RestaurantCuisineRecentsStrip: View {
    let cuisines: [String]
    let selectedCuisine: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("recent")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(cuisines, id: \.self) { cuisine in
                        RestaurantCuisineCompactChoice(
                            cuisine: cuisine,
                            isSelected: selectedCuisine?.caseInsensitiveCompare(cuisine) == .orderedSame
                        ) {
                            onSelect(cuisine)
                        }
                    }
                }
            }
        }
    }
}

private struct RestaurantCuisineCompactChoice: View {
    let cuisine: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing2) {
                WanderCategoryEmoji(
                    category: WanderPlaceCategory.restaurantsFood,
                    cuisine: cuisine,
                    size: 15
                )
                Text(cuisine)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .black))
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(minHeight: WanderTheme.tapMinimum)
            .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceBone.color)
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cuisine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct RestaurantCuisineRegionFilters: View {
    @Binding var selectedRegion: String
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("filter")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(RestaurantCuisineRegionFilter.options) { filter in
                        Button {
                            selectedRegion = filter.id
                            onSelect()
                        } label: {
                            Text(filter.id)
                                .font(.system(size: 13, weight: .black))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, WanderTheme.spacing3)
                                .frame(minHeight: WanderTheme.tapMinimum)
                                .background(
                                    selectedRegion == filter.id
                                        ? WanderTheme.textInk.color
                                        : WanderTheme.surfaceBone.color
                                )
                                .foregroundStyle(
                                    selectedRegion == filter.id
                                        ? WanderTheme.textOnAction.color
                                        : WanderTheme.textInk.color
                                )
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(filter.id) cuisines")
                        .accessibilityValue(selectedRegion == filter.id ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }
}

private struct RestaurantCuisineAtlasTile: View {
    let cuisine: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack {
                    ZStack {
                        Circle().fill(WanderTheme.terracottaTint.color)
                        WanderCategoryEmoji(
                            category: WanderPlaceCategory.restaurantsFood,
                            cuisine: cuisine,
                            size: 21
                        )
                    }
                    .frame(width: 44, height: 44)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }

                Text(cuisine)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(isSelected ? WanderTheme.terracottaTint.color : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cuisine)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct RestaurantCuisineSelectionFooter: View {
    let cuisine: String?
    let onDone: () -> Void

    var body: some View {
        PlaceTypeSelectionFooter(
            label: "CUISINE",
            value: cuisine ?? "No cuisine",
            onDone: onDone
        )
    }
}

private struct PlaceTypeSelectionFooter: View {
    let label: String
    let value: String
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                Text(value)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 0)

            Button("done", action: onDone)
                .font(.system(size: 16, weight: .black))
                .padding(.horizontal, WanderTheme.spacing4)
                .frame(minHeight: 48)
                .background(WanderTheme.terracotta.color)
                .foregroundStyle(WanderTheme.textOnAction.color)
                .clipShape(Capsule())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, WanderTheme.spacing4)
        .padding(.vertical, WanderTheme.spacing3)
        .background {
            WanderTheme.canvasWarm.color
                .ignoresSafeArea(.container, edges: .bottom)
                .overlay(alignment: .top) {
                    WanderTheme.borderHairline.color.frame(height: 1)
                }
        }
    }
}

private struct SubcategoryAtlasFilters: View {
    let titles: [String]
    @Binding var selectedTitle: String
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("filter")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(titles, id: \.self) { title in
                        Button {
                            selectedTitle = title
                            onSelect()
                        } label: {
                            Text(title)
                                .font(.system(size: 13, weight: .black))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, WanderTheme.spacing3)
                                .frame(minHeight: WanderTheme.tapMinimum)
                                .background(
                                    selectedTitle == title
                                        ? WanderTheme.textInk.color
                                        : WanderTheme.surfaceBone.color
                                )
                                .foregroundStyle(
                                    selectedTitle == title
                                        ? WanderTheme.textOnAction.color
                                        : WanderTheme.textInk.color
                                )
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) types")
                        .accessibilityValue(selectedTitle == title ? "Selected" : "Not selected")
                    }
                }
            }
        }
    }
}

private struct PlaceTypeAtlasTile: View {
    let category: String
    let subcategory: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                HStack {
                    ZStack {
                        Circle().fill(WanderTheme.terracottaTint.color)
                        WanderCategoryEmoji(
                            category: category,
                            subcategory: subcategory,
                            size: 21
                        )
                    }
                    .frame(width: 44, height: 44)

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }

                Text(subcategory)
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(isSelected ? WanderTheme.terracottaTint.color : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(
                        isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subcategory)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct CategoryPickerHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(subtitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CategoryPickerSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(WanderTheme.textFaint.color)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 56)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color)
        )
    }
}

struct PrimaryCategoryPickerTile: View {
    let category: String
    let isSelected: Bool
    let action: () -> Void

    private var accent: Color {
        CategoryPickerVisuals.accentColor(for: category)
    }

    private var optionCountLabel: String {
        let count = WanderPlaceCategory.subcategorySuggestions(for: category).count
        let noun = category == WanderPlaceCategory.restaurantsFood ? "cuisines" : "types"
        return "\(count) \(noun)"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                HStack {
                    ZStack {
                        Circle().fill(accent.opacity(0.16))
                        WanderCategoryEmoji(category: category, size: 17)
                    }
                    .frame(width: 42, height: 42)

                    Spacer(minLength: WanderTheme.spacing2)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                }

                Text(WanderPlaceCategory.broadCategory(for: category))
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(height: 44, alignment: .topLeading)

                Text(CategoryPickerVisuals.tileDetail(for: category))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(height: 34, alignment: .topLeading)

                Text(optionCountLabel)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(isSelected ? WanderTheme.surfaceRaised.color : WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(isSelected ? WanderTheme.terracotta.color : WanderTheme.borderHairline.color, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(WanderPlaceCategory.broadCategory(for: category)), \(optionCountLabel)")
    }
}

struct CategoryPickerModePill: View {
    let title: String
    let systemImage: String?
    let emoji: String?
    let isSelected: Bool

    init(title: String, systemImage: String, isSelected: Bool) {
        self.title = title
        self.systemImage = systemImage
        emoji = nil
        self.isSelected = isSelected
    }

    init(title: String, category: String, isSelected: Bool) {
        self.title = title
        systemImage = nil
        emoji = WanderPlaceCategory.emoji(for: category)
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            if let emoji {
                Text(emoji)
                    .font(.system(size: 14))
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 14, weight: .black))
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 44)
        .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
        .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
    }
}

struct SubcategoryGroupSection: View {
    let group: PlaceCategorySubcategoryGroup
    let selectedSubcategory: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(group.title)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            MapSaveWrappingChipLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
                ForEach(group.subcategories, id: \.self) { subcategory in
                    Button {
                        onSelect(subcategory)
                    } label: {
                        SubcategoryPickerChip(
                            title: subcategory,
                            isSelected: selectedSubcategory?.caseInsensitiveCompare(subcategory) == .orderedSame
                        )
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
    }
}

private struct SubcategoryPickerChip: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .black))
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 40)
            .background(isSelected ? WanderTheme.textInk.color : WanderTheme.surfaceRaised.color)
            .foregroundStyle(isSelected ? WanderTheme.textOnAction.color : WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
    }
}

private struct CategoryPickerEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
            Text(title)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private enum CategoryPickerVisuals {
    static func accentColor(for category: String) -> Color {
        switch category {
        case WanderPlaceCategory.restaurantsFood:
            WanderTheme.terracotta.color
        case WanderPlaceCategory.coffeeTeaSweets:
            WanderTheme.categorySun.color
        case WanderPlaceCategory.barsNightlife:
            WanderTheme.terracottaDark.color
        case WanderPlaceCategory.outdoorsNature:
            WanderTheme.categoryMoss.color
        case WanderPlaceCategory.thingsToDo:
            WanderTheme.avatarSofia.color
        case WanderPlaceCategory.wellnessFitness:
            WanderTheme.stateSuccess.color
        case WanderPlaceCategory.shopping:
            WanderTheme.categorySage.color
        case WanderPlaceCategory.servicesErrands:
            WanderTheme.stateInfo.color
        case WanderPlaceCategory.stays:
            WanderTheme.textMuted.color
        case WanderPlaceCategory.travelTransit:
            WanderTheme.pinSocial.color
        case WanderPlaceCategory.workEducation:
            WanderTheme.avatarAndrew.color
        case WanderPlaceCategory.civicFaith:
            WanderTheme.borderStrong.color
        case WanderPlaceCategory.areasAddresses:
            WanderTheme.stateWarning.color
        case WanderPlaceCategory.facilitiesOther:
            WanderTheme.textFaint.color
        default:
            WanderTheme.textInk.color
        }
    }

    static func tileDetail(for category: String) -> String {
        switch category {
        case WanderPlaceCategory.restaurantsFood:
            "Restaurants, cuisines, quick bites"
        case WanderPlaceCategory.coffeeTeaSweets:
            "Coffee, tea, bakeries"
        case WanderPlaceCategory.barsNightlife:
            "Bars, lounges, clubs"
        case WanderPlaceCategory.outdoorsNature:
            "Parks, trails, water"
        case WanderPlaceCategory.thingsToDo:
            "Attractions, arts, venues"
        case WanderPlaceCategory.shopping:
            "Stores, markets, supplies"
        case WanderPlaceCategory.wellnessFitness:
            "Health, beauty, fitness"
        case WanderPlaceCategory.stays:
            "Hotels, rentals, camping"
        case WanderPlaceCategory.servicesErrands:
            "Salons, repairs, pet care"
        case WanderPlaceCategory.travelTransit:
            "Airports, stations, parking"
        case WanderPlaceCategory.workEducation:
            "Offices, schools, libraries"
        case WanderPlaceCategory.civicFaith:
            "Government, worship, safety"
        case WanderPlaceCategory.areasAddresses:
            "Cities, addresses, regions"
        case WanderPlaceCategory.facilitiesOther:
            "Restrooms, facilities, unknown"
        default:
            WanderPlaceCategory.categoryDetail(for: category)
        }
    }
}

private struct MapSaveQuestionBlock<Content: View>: View {
    let title: String
    let tag: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                Spacer()
                Text(tag)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            content
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct MapSaveQuestionOptions: View {
    let block: AddQuestionBlock
    let selectedValues: Set<String>
    let onSelect: (String) -> Void
    @State private var isAddingCustomTag = false
    @State private var customTagText = ""
    @FocusState private var isCustomTagFocused: Bool

    var body: some View {
        MapSaveWrappingChipLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
            ForEach(displayOptions, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    WanderChip(title: option, isSelected: selectedValues.contains(option))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }

            if block.kind == .multiTag {
                customTagControl
            }
        }
    }

    private var displayOptions: [String] {
        let customOptions = selectedValues
            .filter { value in
                !block.options.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            .sorted()

        return block.options + customOptions
    }

    @ViewBuilder
    private var customTagControl: some View {
        if isAddingCustomTag {
            HStack(spacing: WanderTheme.spacing1) {
                TextField("tag", text: $customTagText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .tint(WanderTheme.terracotta.color)
                    .frame(width: 86)
                    .submitLabel(.done)
                    .focused($isCustomTagFocused)
                    .onSubmit(addCustomTag)

                Button(action: addCustomTag) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add custom tag")
            }
            .frame(minHeight: WanderTheme.tapMinimum)
            .padding(.horizontal, WanderTheme.spacing2)
            .background(WanderTheme.surfaceRaised.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
            .fixedSize(horizontal: true, vertical: false)
            .onAppear {
                isCustomTagFocused = true
            }
        } else {
            Button {
                isAddingCustomTag = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .black))
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                    .background(WanderTheme.surfaceRaised.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add custom tag")
        }
    }

    private func addCustomTag() {
        let tag = customTagText
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !tag.isEmpty else {
            isAddingCustomTag = false
            customTagText = ""
            return
        }

        if let existing = displayOptions.first(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            if !selectedValues.contains(existing) {
                onSelect(existing)
            }
        } else {
            onSelect(tag)
        }

        customTagText = ""
        isAddingCustomTag = false
    }
}

private struct MapSaveWrappingChipLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows.items {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(for subviews: Subviews, maxWidth: CGFloat) -> ChipRows {
        var rows: [ChipRow] = []
        var currentItems: [ChipItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0
        let effectiveMaxWidth = max(1, maxWidth)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentItems.isEmpty ? size.width : currentWidth + horizontalSpacing + size.width

            if nextWidth > effectiveMaxWidth, !currentItems.isEmpty {
                rows.append(ChipRow(items: currentItems, width: currentWidth, height: currentHeight))
                currentItems = [ChipItem(index: index, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(ChipItem(index: index, size: size))
                currentWidth = nextWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(ChipRow(items: currentItems, width: currentWidth, height: currentHeight))
        }

        return ChipRows(items: rows, horizontalSpacing: horizontalSpacing, verticalSpacing: verticalSpacing)
    }

    private struct ChipItem {
        let index: Int
        let size: CGSize
    }

    private struct ChipRow {
        let items: [ChipItem]
        let width: CGFloat
        let height: CGFloat
    }

    private struct ChipRows {
        let items: [ChipRow]
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat

        var width: CGFloat {
            items.map(\.width).max() ?? 0
        }

        var height: CGFloat {
            guard !items.isEmpty else { return 0 }
            return items.reduce(0) { $0 + $1.height } + verticalSpacing * CGFloat(max(0, items.count - 1))
        }
    }
}

struct PlaceSheet: View {
    let place: PlaceSheetPlace
    let saves: [PlaceSaveSummary]
    let tasteSaves: [PlaceSaveSummary]
    let currentUserID: String
    let action: PlaceSheetAction
    @Binding var isExpanded: Bool
    let onAction: () -> Void
    @Environment(\.openURL) private var openURL

    init(
        place: PlaceSheetPlace,
        saves: [PlaceSaveSummary],
        tasteSaves: [PlaceSaveSummary],
        currentUserID: String,
        action: PlaceSheetAction,
        isExpanded: Binding<Bool>,
        onAction: @escaping () -> Void
    ) {
        self.place = place
        self.saves = saves
        self.tasteSaves = tasteSaves
        self.currentUserID = currentUserID
        self.action = action
        self._isExpanded = isExpanded
        self.onAction = onAction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            Capsule()
                .fill(WanderTheme.borderStrong.color)
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, WanderTheme.spacing1)
                .accessibilityLabel(isExpanded ? "Place details expanded" : "Swipe up for place details")

            if isExpanded {
                ScrollView(showsIndicators: false) {
                    expandedContent
                }
                .frame(maxHeight: 560)
            } else {
                compactContent
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
        .shadow(color: WanderTheme.textInk.color.opacity(0.14), radius: 20, x: 0, y: 10)
        .simultaneousGesture(
            DragGesture(minimumDistance: 14, coordinateSpace: .local)
                .onEnded(handleSheetDrag)
        )
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                CategoryThumb(emoji: place.categoryEmoji)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    HStack {
                        Text(place.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    if let subtitle = compactSubtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                    }
                    if let noteLine = selectedNoteLine {
                        Text(noteLine)
                            .font(.system(size: 13))
                            .italic()
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }
                }

                Spacer()

                actionButton(size: 46, iconSize: 21)
            }

            if hasRatings {
                PlaceProfileRatingStrip(presentation: presentation, compact: true)
            }

            if !presentation.commonTags.isEmpty {
                PlaceCommonTagScroller(tags: presentation.commonTags)
            }

            if !savers.isEmpty {
                SocialProofRow(savers: savers, currentUserID: currentUserID, visibility: place.visibility)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            expandedHeader
            if hasRatings {
                PlaceProfileRatingStrip(presentation: presentation, compact: false)
            }
            if !presentation.commonTags.isEmpty {
                PlaceCommonTagScroller(tags: presentation.commonTags)
            }
            if !savers.isEmpty {
                SocialProofRow(savers: savers, currentUserID: currentUserID, visibility: place.visibility)
            }
            externalActions
            if !presentation.whyItFits.isEmpty {
                whyItFitsSection
            }

            PlaceActivitySection(saves: saves, currentUserID: currentUserID)

            if !placeFacts.isEmpty {
                factSection(title: "place", facts: placeFacts)
            }
        }
        .padding(.bottom, WanderTheme.spacing1)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            CategoryThumb(emoji: place.categoryEmoji, status: ownSave?.visiblePlace.userPlace.status)
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(place.name)
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(3)
                    .minimumScaleFactor(0.78)

                if let subtitle = expandedSubtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(2)
                }

                statusBadge

                if let noteLine = selectedNoteLine {
                    Text(noteLine)
                        .font(.system(size: 13, weight: .medium))
                        .italic()
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: WanderTheme.spacing2)
            VStack(spacing: WanderTheme.spacing2) {
                shareButton
                actionButton(size: 42, iconSize: 18)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let status = place.status {
            StatusBadge(status: status)
        }
    }

    @ViewBuilder
    private var externalActions: some View {
        if !externalActionItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(externalActionItems) { item in
                        PlaceExternalActionButton(title: item.title, systemImage: item.systemImage) {
                            openURL(item.url)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            WanderShareButton(content: .place(item: shareURL, name: place.name, message: shareText)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 42, height: 42)
                    .background(WanderTheme.surfaceSand.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Share place")
        }
    }

    private func factSection(title: String, facts: [PlaceFact]) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            sectionTitle(title)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 106), spacing: WanderTheme.spacing2)],
                alignment: .leading,
                spacing: WanderTheme.spacing2
            ) {
                ForEach(facts) { fact in
                    PlaceFactPill(fact: fact)
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .black))
            .textCase(.uppercase)
            .foregroundStyle(WanderTheme.textMuted.color)
    }

    private var savers: [LocalProfile] {
        saves.map(\.visiblePlace.owner)
    }

    private var presentation: PlaceProfilePresentation {
        PlaceProfilePresenter.presentation(
            placeID: place.id,
            category: place.primaryCategory,
            saves: saves,
            tasteSaves: tasteSaves,
            currentUserID: currentUserID
        )
    }

    private var hasRatings: Bool {
        !saves.isEmpty || presentation.fitRating != nil || presentation.overallRating != nil || presentation.ownRating != nil
    }

    private var whyItFitsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            sectionTitle("why it fits")
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                ForEach(presentation.whyItFits, id: \.self) { reason in
                    HStack(alignment: .top, spacing: WanderTheme.spacing2) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .frame(width: 18, height: 18)
                        Text(reason)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(WanderTheme.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
        }
    }

    private var ownSave: PlaceSaveSummary? {
        saves.first { $0.visiblePlace.owner.id == currentUserID }
    }

    private var friendSaves: [PlaceSaveSummary] {
        saves.filter { $0.visiblePlace.owner.id != currentUserID }
    }

    private var compactSubtitle: String? {
        trimmed(place.compactSubtitleOverride) ?? joinedText([place.locality, categoryDisplay])
    }

    private var expandedSubtitle: String? {
        joinedText([addressLine, categoryDisplay])
    }

    private var addressLine: String? {
        let address = trimmed(place.address)
        if let address {
            return address
        }
        return joinedText([place.locality, place.region])
    }

    private var categoryDisplay: String? {
        let display = WanderPlaceCategory.display(for: place.categoryAssignment).compactTitle
        let trimmedDisplay = trimmed(display)
        return place.primaryCategory == "place" ? nil : trimmedDisplay
    }

    private var selectedNote: String? {
        trimmed(place.note)
    }

    private var selectedNoteLine: String? {
        guard let selectedNote else { return nil }
        let ownerLabel = place.noteOwnerID == currentUserID ? "your note" : "\(place.noteOwnerName ?? "their") note"
        return "\(ownerLabel): \"\(selectedNote)\""
    }

    private var placeFacts: [PlaceFact] {
        var facts: [PlaceFact] = []
        if let categoryDisplay {
            facts.append(PlaceFact(title: categoryDisplay, emoji: place.categoryEmoji))
        }
        return facts
    }

    private var externalActionItems: [PlaceExternalAction] {
        var actions: [PlaceExternalAction] = []
        if let latitude = place.latitude,
           let longitude = place.longitude,
           let directionsAction = PlaceExternalLinks.directionsAction(placeName: place.name, latitude: latitude, longitude: longitude) {
            actions.append(directionsAction)
        }
        actions.append(contentsOf: PlaceExternalLinks.visibleBusinessActions(
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            actionLinksJSON: place.actionLinksJSON
        ))
        return actions
    }

    private var shareURL: URL? {
        PlaceExternalLinks.googleMapsSearchURL(
            placeName: place.name,
            address: place.address,
            locality: place.locality
        )
    }

    private var shareText: String {
        PlaceExternalLinks.shareSummary(
            placeName: place.name,
            locality: place.locality,
            status: place.status
        )
    }

    private func joinedText(_ values: [String?]) -> String? {
        let parts = values.compactMap(trimmed)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private static func facts(for attribute: LocalPlaceAttribute) -> [PlaceFact] {
        PlaceAttributeValuePresentation.strings(from: attribute.valueJSON).map { value in
            PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
        }
    }

    private static func icon(for questionKey: String) -> String {
        switch questionKey {
        case "interest_signal": "heart.fill"
        case "rating_signal": "heart.fill"
        case "work_setup": "laptopcomputer"
        case "strenuousness": "figure.hiking"
        case "price": "dollarsign.circle.fill"
        case "occasion", "best_for": "sparkles"
        case PlaceMemoryAttributeKeys.restaurantCuisine: "fork.knife"
        default: "tag.fill"
        }
    }

    private func handleSheetDrag(_ value: DragGesture.Value) {
        let verticalIntent = value.translation.height
        guard abs(verticalIntent) > abs(value.translation.width), abs(verticalIntent) > 24 else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            isExpanded = verticalIntent < 0
        }
    }

    @ViewBuilder
    private func actionButton(size: CGFloat, iconSize: CGFloat) -> some View {
        if action != .none {
            Button(action: onAction) {
                if action == .addVisit {
                    Label(CheckInCopy.againAction, systemImage: action.systemImage)
                        .font(.system(size: 14, weight: .black))
                        .padding(.horizontal, WanderTheme.spacing3)
                        .frame(minHeight: max(size, WanderTheme.tapMinimum))
                        .background(WanderTheme.terracotta.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: action.systemImage)
                        .font(.system(size: iconSize, weight: .black))
                        .frame(width: size, height: size)
                        .background(action.isPrimaryAction ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Circle())
                }
            }
            .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

private struct PlaceFact: Identifiable {
    var id: String { "\(emoji ?? systemImage ?? "")-\(title)" }
    let title: String
    let systemImage: String?
    let emoji: String?

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        emoji = nil
    }

    init(title: String, emoji: String) {
        self.title = title
        systemImage = nil
        self.emoji = emoji
    }
}

private struct PlaceProfileRatingStrip: View {
    let presentation: PlaceProfilePresentation
    let compact: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            PlaceProfileMetricCard(
                title: "Your rating",
                value: presentation.ownRating?.displayScore ?? "No check-ins yet",
                suffix: presentation.ownRating == nil ? nil : "/5",
                subtitle: presentation.ownRating?.subtitle ?? "0 check-ins",
                systemImage: "star.fill",
                tint: WanderTheme.stateWarning.color,
                explanation: nil,
                compact: compact
            )

            PlaceProfileMetricCard(
                title: "rec.me rating",
                value: presentation.overallRating?.displayScore ?? "No ratings yet",
                suffix: presentation.overallRating == nil ? nil : "/5",
                subtitle: presentation.overallRating?.subtitle ?? "0 ratings",
                systemImage: "person.2.fill",
                tint: WanderTheme.pinSocial.color,
                explanation: .recMe,
                compact: compact
            )

            PlaceProfileMetricCard(
                title: "Fit Rating",
                value: presentation.fitRating?.displayScore ?? "Not enough yet",
                suffix: presentation.fitRating == nil ? nil : "/10",
                subtitle: presentation.fitRating == nil ? "keep saving" : (compact ? "for you" : "compared to places you like"),
                systemImage: "sparkles",
                tint: WanderTheme.terracotta.color,
                explanation: .fit,
                compact: compact
            )
        }
    }
}

private struct PlaceProfileMetricCard: View {
    let title: String
    let value: String
    let suffix: String?
    let subtitle: String
    let systemImage: String
    let tint: Color
    let explanation: PlaceRatingExplanation?
    let compact: Bool

    var body: some View {
        VStack(alignment: .center, spacing: compact ? 4 : WanderTheme.spacing1) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 12 : 15, weight: .black))
                .foregroundStyle(tint)
                .frame(width: compact ? 24 : 32, height: compact ? 24 : 32)
                .background(tint.opacity(0.12))
                .clipShape(Circle())
                .offset(x: ratingHeaderHorizontalOffset)

            Text(title)
                .font(.system(size: compact ? 11 : 13, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
                .textCase(.uppercase)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, minHeight: compact ? 28 : 34, alignment: .center)
                .offset(x: ratingHeaderHorizontalOffset)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: valueFontSize, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(suffix == nil ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.62)
                if let suffix {
                    Text(suffix)
                        .font(.system(size: compact ? 11 : 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 25 : 30, alignment: .center)

            Text(subtitle)
                .font(.system(size: compact ? 9.5 : 11, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, minHeight: compact ? 16 : 24, alignment: .center)
        }
        .padding(.horizontal, compact ? 6 : WanderTheme.spacing2)
        .padding(.vertical, compact ? 7 : WanderTheme.spacing2)
        .frame(maxWidth: .infinity, minHeight: compact ? 118 : 136, alignment: .center)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if let explanation {
                PlaceRatingInfoButton(explanation: explanation, tint: tint)
                    .offset(x: infoButtonHorizontalOffset, y: compact ? -1 : 1)
            }
        }
    }

    private var ratingHeaderHorizontalOffset: CGFloat {
        explanation == nil ? -5 : -10
    }

    private var infoButtonHorizontalOffset: CGFloat {
        explanation == .recMe ? 9 : 6
    }

    private var valueFontSize: CGFloat {
        if suffix != nil {
            return compact ? 20 : 24
        }

        return compact ? 11 : 13
    }
}

enum PlaceActivityFilter: String, CaseIterable, Identifiable {
    case all
    case myVisits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "ALL"
        case .myVisits: "MY CHECK-INS"
        }
    }
}

enum PlaceActivityEntryKind: Equatable {
    case visit
    case currentWant
    case historicalWant
    case legacyBeenSummary

    var sortBucket: Int {
        self == .historicalWant ? 1 : 0
    }
}

struct PlaceActivityEntry: Identifiable {
    let summary: PlaceSaveSummary
    let visit: LocalPlaceVisit?
    let kind: PlaceActivityEntryKind
    let currentUserID: String

    var id: String {
        switch kind {
        case .visit:
            visit?.id ?? "\(summary.id)_visit"
        case .currentWant:
            "\(summary.id)_current_want"
        case .historicalWant:
            "\(summary.id)_historical_want"
        case .legacyBeenSummary:
            "\(summary.id)_legacy_been"
        }
    }

    var owner: LocalProfile {
        summary.visiblePlace.owner
    }

    var userPlace: LocalUserPlace {
        summary.visiblePlace.userPlace
    }

    var isCurrentUser: Bool {
        owner.id == currentUserID
    }

    var displayName: String {
        isCurrentUser ? "You" : owner.displayName
    }

    var timestamp: Date {
        switch kind {
        case .visit:
            visit?.visitedAt ?? userPlace.visitedAt ?? userPlace.savedAt
        case .currentWant:
            userPlace.updatedAt
        case .historicalWant:
            userPlace.historicalWantedAt ?? userPlace.savedAt
        case .legacyBeenSummary:
            userPlace.visitedAt ?? userPlace.savedAt
        }
    }

    var timestampText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var note: String? {
        let sourceNote: String? = switch kind {
        case .visit:
            visit?.note
        case .currentWant, .legacyBeenSummary:
            userPlace.note
        case .historicalWant:
            userPlace.historicalWantNote
        }
        let trimmed = sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    var ratingText: String? {
        let ratingScore: Double? = switch kind {
        case .visit:
            visit?.ratingScore
        case .legacyBeenSummary:
            userPlace.ratingScore
        case .currentWant, .historicalWant:
            nil
        }
        guard let ratingScore else {
            return nil
        }
        return "\(PlaceRating.display(ratingScore))/5"
    }

    var canAddPhotos: Bool {
        isCurrentUser && kind == .visit && visit != nil
    }

    var canEdit: Bool {
        isCurrentUser && (kind == .visit || kind == .currentWant)
    }

    var editAccessibilityLabel: String {
        kind == .currentWant ? "Edit want" : CheckInCopy.editAction
    }

    var status: PlaceStatus {
        switch kind {
        case .currentWant, .historicalWant:
            .wannaGo
        case .visit, .legacyBeenSummary:
            .been
        }
    }

    var tags: [String] {
        if let visit, !visit.tags.isEmpty {
            return uniqueTags(visit.tags)
        }

        if kind == .historicalWant {
            return uniqueTags(userPlace.historicalWantTags)
        }

        var seen = Set<String>()
        return summary.attributes
            .flatMap(PlaceProfileTagParser.tags(from:))
            .compactMap { tag in
                guard !seen.contains(tag.normalized) else { return nil }
                seen.insert(tag.normalized)
                return tag.displayTitle
            }
    }

    var avatarColor: Color {
        if isCurrentUser { return WanderTheme.terracotta.color }
        return owner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }

    private func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = trimmed.lowercased()
            guard !seen.contains(normalized) else { return nil }
            seen.insert(normalized)
            return trimmed
        }
    }
}

struct PlaceActivityPhoto: Identifiable {
    let metadata: LocalVisitPhoto
    let entryID: String

    var id: String { metadata.id }
    var localImage: UIImage? { VisitPhotoLocalFileStore.image(from: metadata.localAssetRef) }
    var remoteURL: URL? { metadata.remoteURLString.flatMap { URL(string: $0) } }
    var uploadState: VisitPhotoUploadState { metadata.uploadState }
}

private struct PlaceActivityPhotoViewerRoute: Identifiable {
    let photoID: String

    var id: String { photoID }
}

struct PlaceActivitySection: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let saves: [PlaceSaveSummary]
    let currentUserID: String
    @State private var filter: PlaceActivityFilter = .all
    @State private var viewerRoute: PlaceActivityPhotoViewerRoute?
    @State private var editFlow: MapPlaceSaveContext?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("check-in history")
                .font(.system(size: 12, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(WanderTheme.textMuted.color)

            PlaceActivityFilterControl(selection: $filter)
                .frame(maxWidth: .infinity)

            if filteredEntries.isEmpty {
                PlaceActivityEmptyState(text: emptyStateText)
            } else {
                LazyVStack(spacing: WanderTheme.spacing2) {
                    ForEach(filteredEntries) { entry in
                        PlaceActivityCard(
                            entry: entry,
                            photos: photos(for: entry),
                            companions: companions(for: entry),
                            onOpenPhoto: { photo in
                                viewerRoute = PlaceActivityPhotoViewerRoute(photoID: photo.id)
                            },
                            onEdit: {
                                edit(entry)
                            }
                        )
                    }
                }
            }
        }
        .fullScreenCover(item: $viewerRoute) { route in
            PlaceActivityPhotoViewer(
                photos: allPhotos,
                initialPhotoID: route.photoID,
                entriesByID: entriesByID
            )
        }
        .sheet(item: $editFlow, onDismiss: {
            store.saveFlowDidDismiss(.saveSheet)
        }) { context in
            MapPlaceSaveFlowSheet(context: context) { submission in
                await saveActivityEdit(submission)
            } onRemove: { context in
                await removeActivityEdit(context)
            }
        }
        .task(id: companionVisitIDs) {
            guard auth.isSignedIn else { return }
            await store.refreshSharedVisitCompanions(visitIDs: companionVisitIDs, backend: backend)
        }
    }

    private var entries: [PlaceActivityEntry] {
        saves
            .flatMap { summary -> [PlaceActivityEntry] in
                let userPlace = summary.visiblePlace.userPlace
                let visits = store.visits(for: summary.visiblePlace.userPlace.id)

                if userPlace.status == .been {
                    var entries = visits.map { visit in
                        PlaceActivityEntry(summary: summary, visit: visit, kind: .visit, currentUserID: currentUserID)
                    }

                    if entries.isEmpty {
                        entries.append(
                            PlaceActivityEntry(summary: summary, visit: nil, kind: .legacyBeenSummary, currentUserID: currentUserID)
                        )
                    }

                    if userPlace.hasHistoricalWant {
                        entries.append(
                            PlaceActivityEntry(summary: summary, visit: nil, kind: .historicalWant, currentUserID: currentUserID)
                        )
                    }

                    return entries
                }

                return [PlaceActivityEntry(summary: summary, visit: nil, kind: .currentWant, currentUserID: currentUserID)]
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortBucket != rhs.kind.sortBucket {
                    return lhs.kind.sortBucket < rhs.kind.sortBucket
                }
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp > rhs.timestamp
                }
                if lhs.isCurrentUser != rhs.isCurrentUser {
                    return lhs.isCurrentUser
                }
                return lhs.owner.displayName.localizedCaseInsensitiveCompare(rhs.owner.displayName) == .orderedAscending
            }
    }

    private var filteredEntries: [PlaceActivityEntry] {
        switch filter {
        case .all:
            entries
        case .myVisits:
            entries.filter { $0.isCurrentUser }
        }
    }

    private var entriesByID: [String: PlaceActivityEntry] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
    }

    private var allPhotos: [PlaceActivityPhoto] {
        entries.flatMap(photos(for:))
    }

    private var companionVisitIDs: [String] {
        entries.compactMap { $0.visit?.serverID }.sorted()
    }

    private func companions(for entry: PlaceActivityEntry) -> [SharedVisitCompanion] {
        guard let visit = entry.visit else { return [] }
        return store.sharedVisitCompanions(for: visit.id)
    }

    private func photos(for entry: PlaceActivityEntry) -> [PlaceActivityPhoto] {
        guard let visit = entry.visit else { return [] }
        return store.photos(for: visit.id).map { photo in
            PlaceActivityPhoto(metadata: photo, entryID: entry.id)
        }
    }

    private var emptyStateText: String {
        switch filter {
        case .all:
            "No activity yet."
        case .myVisits:
            "No check-ins yet."
        }
    }

    private func edit(_ entry: PlaceActivityEntry) {
        guard entry.canEdit else { return }

        if entry.kind == .visit, let visit = entry.visit {
            editFlow = MapPlaceSaveContext.editVisit(visit, visiblePlace: entry.summary.visiblePlace)
        } else if entry.kind == .currentWant {
            editFlow = MapPlaceSaveContext.editWant(
                entry.summary.visiblePlace,
                attributes: store.attributes(for: entry.userPlace.id)
            )
        }
    }

    @MainActor
    private func saveActivityEdit(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let (result, targetVisit) = await persistScopedVisitOrWantSubmission(
            submission,
            store: store,
            backend: auth.isSignedIn ? backend : nil
        )
        await persistVisitPhotoAttachments(
            submission.photoAttachments,
            to: targetVisit,
            store: store,
            backend: auth.isSignedIn ? backend : nil
        )
        if submission.reconcilesSharedVisitInvitees, let targetVisit, auth.isSignedIn {
            store.queueSharedVisitInviteeReconciliation(
                sourceVisitID: targetVisit.id,
                inviteeUserIDs: submission.inviteeUserIDs
            )
            _ = await store.retryPendingSharedVisitInvites(backend: backend)
        }
        if result != nil, !auth.isSignedIn {
            auth.presentGate(for: .syncPlace)
        }
        return result
    }

    @MainActor
    private func removeActivityEdit(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            return await store.deleteVisit(visitID: visit.id, backend: auth.isSignedIn ? backend : nil)
        case .editWant(let visiblePlace):
            return await store.removeSave(userPlaceID: visiblePlace.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }
}

private struct PlaceActivityFilterControl: View {
    @Binding var selection: PlaceActivityFilter

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PlaceActivityFilter.allCases) { filter in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = filter
                    }
                } label: {
                    Text(filter.title)
                        .font(.system(size: 12, weight: .black))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selection == filter ? WanderTheme.terracottaDark.color : WanderTheme.textInk.color)
                        .background(selection == filter ? WanderTheme.surfaceRaised.color : WanderTheme.surfaceSand.color)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selection == filter ? WanderTheme.terracotta.color : Color.clear, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(WanderTheme.surfaceSand.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
    }
}

private struct PlaceActivityEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(WanderTheme.textMuted.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
            )
    }
}

private struct PlaceActivityCard: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let entry: PlaceActivityEntry
    let photos: [PlaceActivityPhoto]
    let companions: [SharedVisitCompanion]
    let onOpenPhoto: (PlaceActivityPhoto) -> Void
    let onEdit: () -> Void
    @State private var isShowingPhotoMenu = false
    @State private var isShowingCamera = false
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var photoError: String?
    @State private var selectedProfileID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            header

            SharedVisitCompanionLabel(
                companions: companions,
                currentUserID: store.currentUser.id
            ) { profileID in
                selectedProfileID = profileID
            }

            if let note = entry.note {
                Text("\"\(note)\"")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !entry.tags.isEmpty || entry.ratingText != nil {
                MapSaveWrappingChipLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
                    if let ratingText = entry.ratingText {
                        PlaceFactPill(title: "Rated \(ratingText)", systemImage: "star.fill")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    ForEach(entry.tags.prefix(6), id: \.self) { tag in
                        PlaceFactPill(title: tag, systemImage: "tag.fill")
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            photoThumbnails

            addPhotoControl

            if let photoError {
                Text(photoError)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .checkInTicketSurface(
            accent: ticketAccentColor,
            surface: WanderTheme.surfaceRaised.color,
            surroundingSurface: WanderTheme.surfaceBone.color,
            notchEdges: .trailing
        )
        .sheet(isPresented: $isShowingCamera) {
            PlaceActivityCameraPicker { image in
                if let attachment = MapPlaceSavePhotoAttachment.make(image: image) {
                    Task {
                        await addPhoto(attachment)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 8,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            isShowingPhotoMenu = false
            Task {
                await importPhotos(from: items)
            }
        }
        .fullScreenCover(isPresented: profileDestinationBinding) {
            if let selectedProfileID {
                ProfileDetailView(profileID: selectedProfileID)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing2) {
            activityIdentity
            Spacer()
            if entry.canEdit {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .black))
                        .frame(width: 44, height: 44)
                        .background(WanderTheme.surfaceSand.color)
                        .foregroundStyle(WanderTheme.textInk.color)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.editAccessibilityLabel)
            }
            StatusBadge(status: entry.status)
        }
    }

    private var ticketAccentColor: Color {
        entry.isCurrentUser ? WanderTheme.terracotta.color : WanderTheme.pinSocial.color
    }

    @ViewBuilder
    private var activityIdentity: some View {
        if entry.isCurrentUser {
            activityIdentityLabel
                .accessibilityElement(children: .combine)
                .accessibilityLabel(entry.status == .been ? "Your check-in" : "Your Wanna")
        } else {
            Button {
                selectedProfileID = entry.owner.id
            } label: {
                activityIdentityLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(entry.owner.displayName)'s profile")
        }
    }

    private var activityIdentityLabel: some View {
        HStack(spacing: WanderTheme.spacing2) {
            WanderAvatar(
                initials: entry.owner.initials,
                avatarURL: entry.owner.avatarURL,
                size: 40,
                color: entry.avatarColor
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.status == .been ? "CHECKED IN" : "WANNA")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.05)
                    .foregroundStyle(ticketAccentColor)
                    .lineLimit(1)
                Text(entry.displayName)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Text(entry.isCurrentUser ? entry.timestampText : "@\(entry.owner.handle) · \(entry.timestampText)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var profileDestinationBinding: Binding<Bool> {
        Binding(
            get: { selectedProfileID != nil },
            set: { if !$0 { selectedProfileID = nil } }
        )
    }

    @ViewBuilder
    private var photoThumbnails: some View {
        if !photos.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(photos) { photo in
                        Button {
                            onOpenPhoto(photo)
                        } label: {
                            VisitPhotoThumbnail(photo: photo, size: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var addPhotoControl: some View {
        if entry.canAddPhotos {
            VStack(spacing: WanderTheme.spacing1) {
                Button {
                    isShowingPhotoMenu = true
                } label: {
                    Label("Add photo", systemImage: "photo.badge.plus")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(WanderTheme.pinSocial.color)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(WanderTheme.skyTint.color)
                        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                                .stroke(WanderTheme.pinSocial.color, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        )
                }
                .buttonStyle(.plain)
                .confirmationDialog("Add photos to your check-in", isPresented: $isShowingPhotoMenu, titleVisibility: .visible) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") {
                            isShowingCamera = true
                        }
                    }
                    Button("Choose from Library") {
                        isShowingPhotoMenu = false
                        isShowingPhotoPicker = true
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
    }

    private func addPhoto(_ attachment: MapPlaceSavePhotoAttachment) async {
        guard let visit = entry.visit else { return }
        guard let data = attachment.data() else {
            photoError = "Could not read that photo."
            return
        }
        photoError = nil
        isShowingPhotoMenu = false
        _ = await store.createVisitPhoto(
            visitID: visit.id,
            data: data,
            localAssetRef: attachment.localAssetRef,
            contentType: attachment.contentType,
            width: attachment.width,
            height: attachment.height,
            backend: auth.isSignedIn ? backend : nil
        )
    }

    private func importPhotos(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    continue
                }
                let assetRef = item.itemIdentifier.map { "photos_picker:\($0)" }
                if let attachment = MapPlaceSavePhotoAttachment.make(
                    image: image,
                    data: data,
                    fallbackAssetRef: assetRef
                ) {
                    await addPhoto(attachment)
                }
            } catch {
                await MainActor.run {
                    photoError = "Could not use one of those photos."
                }
            }
        }

        await MainActor.run {
            selectedPhotoItems = []
        }
    }
}

private struct VisitPhotoThumbnail: View {
    let photo: PlaceActivityPhoto
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image = photo.localImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let remoteURL = photo.remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder(systemImage: "exclamationmark.triangle.fill")
                    case .empty:
                        placeholder(systemImage: "arrow.triangle.2.circlepath")
                    @unknown default:
                        placeholder(systemImage: "photo")
                    }
                }
            } else {
                placeholder(systemImage: photo.uploadState == .failed ? "exclamationmark.triangle.fill" : "photo")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(alignment: .bottomTrailing) {
            if photo.uploadState != .uploaded {
                Image(systemName: photo.uploadState == .failed ? "exclamationmark.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(photo.uploadState == .failed ? WanderTheme.stateError.color : WanderTheme.pinSocial.color)
                    .padding(4)
                    .background(WanderTheme.surfaceRaised.color, in: Circle())
                    .padding(5)
            }
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            WanderTheme.surfaceSand.color
            Image(systemName: systemImage)
                .font(.system(size: max(18, size * 0.28), weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
    }
}

private struct PlaceActivityPhotoViewer: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    let photos: [PlaceActivityPhoto]
    let entriesByID: [String: PlaceActivityEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhotoID: String

    init(
        photos: [PlaceActivityPhoto],
        initialPhotoID: String,
        entriesByID: [String: PlaceActivityEntry]
    ) {
        self.photos = photos
        self.entriesByID = entriesByID
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    viewerButton(systemImage: "xmark", action: dismiss.callAsFunction)
                    Spacer()
                    if canDeleteSelectedPhoto {
                        viewerButton(systemImage: "trash", action: deleteSelectedPhoto)
                    }
                }
                .padding(.horizontal, WanderTheme.spacing4)
                .padding(.top, WanderTheme.spacing4)

                TabView(selection: $selectedPhotoID) {
                    ForEach(photos) { photo in
                        ZoomablePhoto {
                            VisitPhotoFullScreenImage(photo: photo)
                        }
                        .tag(photo.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, WanderTheme.spacing2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))

                if let selectedEntry {
                    PlaceActivityViewerContext(entry: selectedEntry)
                        .padding(.horizontal, WanderTheme.spacing4)
                        .padding(.bottom, WanderTheme.spacing4)
                }
            }
        }
        .onChange(of: photos.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                dismiss()
                return
            }
            if !ids.contains(selectedPhotoID), let firstID = ids.first {
                selectedPhotoID = firstID
            }
        }
    }

    private var selectedPhoto: PlaceActivityPhoto? {
        photos.first { $0.id == selectedPhotoID } ?? photos.first
    }

    private var selectedEntry: PlaceActivityEntry? {
        selectedPhoto.flatMap { entriesByID[$0.entryID] }
    }

    private var canDeleteSelectedPhoto: Bool {
        selectedEntry?.isCurrentUser == true
    }

    private func viewerButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.18))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func deleteSelectedPhoto() {
        guard let selectedPhoto else { return }
        Task {
            _ = await store.deleteVisitPhoto(
                photoID: selectedPhoto.id,
                backend: auth.isSignedIn ? backend : nil
            )
        }
    }
}

private struct VisitPhotoFullScreenImage: View {
    let photo: PlaceActivityPhoto

    var body: some View {
        if let image = photo.localImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else if let remoteURL = photo.remoteURL {
            AsyncImage(url: remoteURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    fullScreenPlaceholder(systemImage: "exclamationmark.triangle.fill", title: "Photo unavailable")
                case .empty:
                    fullScreenPlaceholder(systemImage: "arrow.triangle.2.circlepath", title: "Loading photo")
                @unknown default:
                    fullScreenPlaceholder(systemImage: "photo", title: "Photo")
                }
            }
        } else {
            fullScreenPlaceholder(
                systemImage: photo.uploadState == .failed ? "exclamationmark.triangle.fill" : "photo",
                title: photo.uploadState == .failed ? "Upload failed" : "Waiting to upload"
            )
        }
    }

    private func fullScreenPlaceholder(systemImage: String, title: String) -> some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .black))
            Text(title)
                .font(.system(size: 15, weight: .black))
        }
        .foregroundStyle(.white.opacity(0.76))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlaceActivityViewerContext: View {
    let entry: PlaceActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: entry.owner.initials,
                    avatarURL: entry.owner.avatarURL,
                    size: 30,
                    color: entry.avatarColor
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.displayName)
                        .font(.system(size: 14, weight: .black))
                    Text(entry.timestampText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                StatusBadge(status: entry.userPlace.status)
            }

            if let note = entry.note {
                Text("\"\(note)\"")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(WanderTheme.textInk.color)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct PlaceActivityCameraPicker: UIViewControllerRepresentable {
    let onImage: @MainActor (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage) {
            dismiss()
        }
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: @MainActor (UIImage) -> Void
        private let dismiss: () -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            if let image {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private struct PlaceCommonTagScroller: View {
    let tags: [PlaceCommonTag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: WanderTheme.spacing2) {
                ForEach(tags) { tag in
                    PlaceCommonTagChip(tag: tag)
                }
            }
        }
    }
}

private struct PlaceCommonTagChip: View {
    let tag: PlaceCommonTag

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: tag.hasOwnSupport ? "checkmark.circle.fill" : "person.2.fill")
                .font(.system(size: 11, weight: .black))
            Text(tag.title)
                .font(.system(size: 12, weight: .black))
                .lineLimit(1)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(height: 34)
        .background(tag.hasOwnSupport ? WanderTheme.terracottaTint.color : WanderTheme.surfaceSand.color)
        .foregroundStyle(tag.hasOwnSupport ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
        .clipShape(Capsule())
    }
}

private struct PlaceExternalActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: WanderTheme.spacing1) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .black))
                Text(title)
                    .font(.system(size: 13, weight: .black))
                    .lineLimit(1)
            }
            .frame(minHeight: 42)
            .padding(.horizontal, WanderTheme.spacing4)
            .background(WanderTheme.surfaceRaised.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(WanderTheme.borderHairline.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct SaveReviewCard: View {
    let summary: PlaceSaveSummary
    let currentUserID: String
    let emphasis: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack(alignment: .center, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: owner.initials,
                    avatarURL: owner.avatarURL,
                    size: 34,
                    color: avatarColor
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(owner.id == currentUserID ? "You" : owner.displayName)
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(owner.handle)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                StatusBadge(status: userPlace.status)
            }

            if let note {
                Text("\"\(note)\"")
                    .font(.system(size: 14, weight: .medium))
                    .italic()
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !facts.isEmpty {
                MapSaveWrappingChipLayout(horizontalSpacing: WanderTheme.spacing2, verticalSpacing: WanderTheme.spacing2) {
                    ForEach(facts) { fact in
                        PlaceFactPill(fact: fact)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasis ? WanderTheme.surfaceSand.color : WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(emphasis ? WanderTheme.borderStrong.color.opacity(0.5) : WanderTheme.borderHairline.color, lineWidth: 1)
        )
    }

    private var owner: LocalProfile {
        summary.visiblePlace.owner
    }

    private var userPlace: LocalUserPlace {
        summary.visiblePlace.userPlace
    }

    private var note: String? {
        let trimmed = userPlace.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private var facts: [PlaceFact] {
        var facts: [PlaceFact] = []

        if let ratingSignal = userPlace.ratingSignal,
           !summary.attributes.contains(where: { $0.questionKey == "rating_signal" }) {
            facts.append(PlaceFact(title: ratingSignal, systemImage: "heart.fill"))
        }

        if let ratingScore = userPlace.ratingScore {
            facts.append(PlaceFact(title: "Rated \(PlaceRating.display(ratingScore))/5", systemImage: "star.fill"))
        }

        facts.append(contentsOf: summary.attributes.flatMap(attributeFacts(for:)))
        return facts
    }

    private var avatarColor: Color {
        if owner.id == currentUserID { return WanderTheme.terracotta.color }
        return owner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }

    private func attributeFacts(for attribute: LocalPlaceAttribute) -> [PlaceFact] {
        PlaceAttributeValuePresentation.strings(from: attribute.valueJSON).map { value in
            PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
        }
    }

    private func icon(for questionKey: String) -> String {
        switch questionKey {
        case "interest_signal": "heart.fill"
        case "rating_signal": "heart.fill"
        case "work_setup": "laptopcomputer"
        case "strenuousness": "figure.hiking"
        case "price": "dollarsign.circle.fill"
        case "occasion", "best_for": "sparkles"
        case PlaceMemoryAttributeKeys.restaurantCuisine: "fork.knife"
        default: "tag.fill"
        }
    }
}

private struct SocialProofRow: View {
    let savers: [LocalProfile]
    let currentUserID: String
    let visibility: PlaceVisibility?

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Facepile(profiles: savers, currentUserID: currentUserID)
            Text(proofText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
            Spacer()
            if let visibility {
                PlaceVisibilityIconPill(visibility: visibility, size: 30)
            }
        }
    }

    private var proofText: String {
        guard let first = savers.first else { return "On \(AppBrand.displayName)" }
        let name = first.id == currentUserID ? "you" : first.displayName
        guard savers.count > 1 else {
            return first.id == currentUserID
                ? "you have this on your map"
                : "\(name) has this on their map"
        }
        return "\(name) +\(savers.count - 1) others have this on their maps"
    }
}

private struct Facepile: View {
    let profiles: [LocalProfile]
    let currentUserID: String

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(profiles.prefix(3).enumerated()), id: \.element.id) { index, profile in
                WanderAvatar(
                    initials: profile.initials,
                    avatarURL: profile.avatarURL,
                    size: 26,
                    color: color(for: profile)
                )
                    .zIndex(Double(3 - index))
            }
        }
        .frame(minWidth: profiles.isEmpty ? 0 : 26 + CGFloat(max(0, min(profiles.count, 3) - 1)) * 18, alignment: .leading)
    }

    private func color(for profile: LocalProfile) -> Color {
        if profile.id == currentUserID { return WanderTheme.terracotta.color }
        return profile.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }
}

private struct PlaceFactPill: View {
    let title: String
    let systemImage: String?
    let emoji: String?

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        emoji = nil
    }

    init(fact: PlaceFact) {
        title = fact.title
        systemImage = fact.systemImage
        emoji = fact.emoji
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            if let emoji {
                Text(emoji)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .font(.system(size: 12, weight: .bold))
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 36)
        .background(WanderTheme.surfaceSand.color)
        .foregroundStyle(WanderTheme.textInk.color)
        .clipShape(Capsule())
    }
}

private struct CategoryThumb: View {
    let emoji: String
    var status: PlaceStatus? = nil
    var size: CGFloat = 46

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WanderCategoryEmoji(emoji: emoji, size: size * 0.42)
                .frame(width: size, height: size)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Circle())

            if let status {
                SavedStatusBadge(status: status, size: size * 0.42)
                    .offset(x: 4, y: -4)
            }
        }
    }

}

struct SavedStatusBadge: View {
    let status: PlaceStatus
    var size: CGFloat

    var body: some View {
        Group {
            switch status {
            case .been:
                Circle()
                    .fill(WanderTheme.stateSuccess.color)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: size * 0.56, weight: .black))
                            .foregroundStyle(WanderTheme.surfaceRaised.color)
                    )
            case .wannaGo:
                Circle()
                    .fill(WanderTheme.surfaceRaised.color)
                    .overlay(
                        Circle()
                            .stroke(
                                WanderTheme.stateSuccess.color,
                                style: StrokeStyle(lineWidth: max(2, size * 0.14), lineCap: .round, dash: [1.5, 3.4])
                            )
                    )
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(WanderTheme.surfaceRaised.color, lineWidth: max(2, size * 0.12)))
        .accessibilityHidden(true)
    }
}

private struct StatusBadge: View {
    let status: PlaceStatus

    var body: some View {
        Text(status == .been ? CheckInCopy.noun : "wanna")
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, WanderTheme.spacing2)
            .padding(.vertical, WanderTheme.spacing1)
            .background(status == .been ? WanderTheme.stateSuccess.color.opacity(0.16) : WanderTheme.sunTint.color)
            .foregroundStyle(status == .been ? WanderTheme.stateSuccess.color : WanderTheme.stateWarning.color)
            .clipShape(Capsule())
    }
}
