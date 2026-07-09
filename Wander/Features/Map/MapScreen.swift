@preconcurrency import MapKit
import SwiftUI
import UIKit

struct MapScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
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
    @State private var selectedFilters: Set<MapFilter> = [.you, .social, .been, .wanna]
    @State private var selectedSocialOwnerID: String?
    @State private var currentSearchRegion = Self.defaultRegion
    @State private var position: MapCameraPosition = .region(Self.defaultRegion)
    @State private var isRecenteringOnUser = false
    @State private var suppressNextQueryAutoSelection = false
    @State private var didCenterInitialPlaces = false

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 34.075, longitude: -118.285),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.14)
    )
    private static let recenterCameraDistance: CLLocationDistance = 1_500
    private static let currentLocationTint = Color(uiColor: .systemBlue)

    private let initialPlaceQuery: String?

    private var baseVisiblePlaces: [VisiblePlace] {
        guard let mapPlaceFilters else { return [] }
        return store.visiblePlaces(filters: mapPlaceFilters)
    }

    init(
        initialPlaceQuery: String? = Self.resolvedInitialMapPlaceQuery(),
        startsExpanded: Bool = Self.resolvedInitialPlaceProfilePresentation()
    ) {
        self.initialPlaceQuery = initialPlaceQuery
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

    private var initialCameraPlaces: [VisiblePlace] {
        guard mapPlaceFilters != nil else { return [] }

        if selectedFilters.contains(.social) {
            let socialPlaces = visiblePlaces.filter { $0.owner.id != store.currentUser.id }
            if !socialPlaces.isEmpty {
                return visiblePlaces
            }
        }

        let ownPlaces = store.currentUserVisiblePlaces
        return ownPlaces.isEmpty ? visiblePlaces : ownPlaces
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
        NavigationStack {
            ZStack(alignment: .bottom) {
                MapReader { proxy in
                    Map(position: $position, selection: $selectedMapFeature) {
                        UserAnnotation()

                        ForEach(mapAnnotationPlaces) { visiblePlace in
                            Annotation(
                                visiblePlace.place.canonicalName,
                                coordinate: CLLocationCoordinate2D(latitude: visiblePlace.place.latitude, longitude: visiblePlace.place.longitude)
                            ) {
                                Button {
                                    selectVisiblePlaceFromMapTap(visiblePlace)
                                } label: {
                                    MapPlaceMarker(
                                        visiblePlace: visiblePlace,
                                        saves: saveSummaries(for: visiblePlace),
                                        currentUserID: store.currentUser.id,
                                        isSelected: isSelectedMapRepresentative(visiblePlace)
                                    )
                                }
                                .buttonStyle(.plain)
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
                            onSubmit: submitMapSearch
                        )
                        if shouldShowTypeahead {
                            MapTypeaheadList(
                                suggestions: typeaheadSuggestions,
                                isLoading: isLoadingTypeahead,
                                onSelect: selectTypeaheadSuggestion
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
                centerMapOnInitialPlacesIfNeeded()
            }
            .task {
                await store.refreshRemoteSocialSurfaces(in: currentViewport, backend: backend)
                centerMapOnInitialPlacesIfNeeded()
            }
            .onChange(of: auth.isSignedIn) { _, isSignedIn in
                guard isSignedIn else { return }
                Task {
                    await store.refreshRemoteSocialSurfaces(in: currentViewport, backend: backend)
                    centerMapOnInitialPlacesIfNeeded()
                }
            }
            .onChange(of: visiblePlaceGroupKeys) { _, keys in
                if let current = selectedPlaceGroupKey, !keys.contains(current) {
                    selectedPlaceGroupKey = nil
                    isPlaceProfilePresented = false
                }
                centerMapOnInitialPlacesIfNeeded()
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
            }
            .sheet(item: $mapSaveFlow) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveMapFlowSubmission(submission)
                } onRemove: { context in
                    await removeMapSave(context)
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .navigationDestination(isPresented: placeProfileDestinationBinding) {
                selectedPlaceProfileDestination
            }
            .toolbar(.hidden, for: .navigationBar)
        }
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
        guard selectedPlaceGroupKey == nil else { return }

        if let initialPlaceQuery {
            let normalized = initialPlaceQuery.lowercased()
            if let initialPlace = visiblePlaces.first(where: { visiblePlace in
                visiblePlace.id.lowercased().contains(normalized)
                    || visiblePlace.place.id.lowercased().contains(normalized)
                    || visiblePlace.place.canonicalName.lowercased().contains(normalized)
            }) {
                selectVisiblePlace(initialPlace)
            }
        }

        if selectedPlaceGroupKey == nil, let firstVisiblePlace = visiblePlaces.first {
            selectVisiblePlace(firstVisiblePlace)
        }
    }

    private func centerMapOnInitialPlacesIfNeeded() {
        guard !didCenterInitialPlaces else { return }
        let coordinates = initialCameraPlaces.map { visiblePlace in
            CLLocationCoordinate2D(
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude
            )
        }
        guard let region = MapRegionFitter.region(fitting: coordinates) else { return }

        didCenterInitialPlaces = true
        position = .region(region)
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
        var seen = Set<String>()
        let summaries = store.visiblePlaces()
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard !seen.contains(visiblePlace.userPlace.id) else { return false }
                seen.insert(visiblePlace.userPlace.id)
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
            }

        return summaries.sorted { lhs, rhs in
            if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
            if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
            if lhs.visiblePlace.id == selectedPlace.id { return true }
            if rhs.visiblePlace.id == selectedPlace.id { return false }
            return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(rhs.visiblePlace.owner.displayName) == .orderedAscending
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
        Task {
            await runMapSearch()
        }
    }

    @MainActor
    private func runMapSearch() async {
        let query = mapQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            mapSearchMessage = nil
            mapSearchCandidates = []
            selectedSearchCandidateID = nil
            return
        }

        isSearchingMapKit = true
        defer { isSearchingMapKit = false }

        do {
            let candidates = try await mapKitCandidates(for: query)
            mapSearchCandidates = candidates.filter { !isAlreadyVisible(candidate: $0) }

            if let firstVisiblePlace = visiblePlaces.first {
                selectVisiblePlace(firstVisiblePlace)
                selectedSearchCandidateID = nil
                mapSearchMessage = mapSearchCandidates.isEmpty ? nil : "Also showing unsaved map results."
            } else if let firstCandidate = mapSearchCandidates.first {
                selectedPlaceGroupKey = nil
                selectedSearchCandidateID = firstCandidate.id
                center(on: firstCandidate)
                mapSearchMessage = "Map result. Tap + to add it."
            } else {
                selectedPlaceGroupKey = nil
                selectedSearchCandidateID = nil
                mapSearchMessage = "No saved places or map results found."
            }
        } catch {
            mapSearchCandidates = []
            mapSearchMessage = visiblePlaces.isEmpty
                ? "No saved places match yet. Try a more specific search."
                : nil
        }
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
        if currentUserSave(matching: visiblePlace) != nil {
            return .edit
        }

        return .add
    }

    private func performAction(for visiblePlace: VisiblePlace) {
        switch action(for: visiblePlace) {
        case .add:
            mapSaveFlow = MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.effectiveDefaultVisibility,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        case .edit:
            let placeToEdit = currentUserSave(matching: visiblePlace) ?? visiblePlace
            mapSaveFlow = MapPlaceSaveContext.editVisiblePlace(
                placeToEdit,
                attributes: store.attributes(for: placeToEdit.userPlace.id)
            )
        case .none:
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
        switch submission.context.mode {
        case .add(let sourceType):
            if sourceType == .socialSave, !auth.isSignedIn {
                mapSaveFlow = nil
                auth.presentGate(for: .socialSave)
                return nil
            }

            let result = await store.saveCandidate(
                submission.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: sourceType,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            clearNativeMapFeatureSelection()
            selectedSearchCandidateID = nil
            selectSavedResult(result)
            mapSearchCandidates.removeAll { $0.id == submission.candidate.id }
            showTransientMapSearchMessage("Added to your map.")

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            return result
        case .edit(let visiblePlace):
            let result = await store.saveCandidate(
                submission.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: AddSourceType(rawValue: visiblePlace.userPlace.sourceType) ?? .manual,
                ratingScore: submission.ratingScore,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            selectedSearchCandidateID = nil
            selectSavedResult(result)
            showTransientMapSearchMessage("Updated saved place.")

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            return result
        }
    }

    @MainActor
    private func removeMapSave(_ context: MapPlaceSaveContext) async -> Bool {
        guard case .edit(let visiblePlace) = context.mode else {
            return false
        }

        let removal = await store.removeSave(
            userPlaceID: visiblePlace.userPlace.id,
            backend: auth.isSignedIn ? backend : nil
        )
        guard removal != nil else {
            return false
        }

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
        showTransientMapSearchMessage("Removed from your map.")
        return true
    }

    private func showTransientMapSearchMessage(_ message: String) {
        mapSearchMessage = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
        mapSearchMessage = nil
        clearNativeMapFeatureSelection()

        if normalized == suppressedTypeaheadQuery {
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
                MapSearchSuggestion.saved(group.primary, saveCount: group.saveCount)
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
        case .saved(let visiblePlace):
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
        case .you: "you"
        case .social: "social"
        case .been: "been"
        case .wanna: "wanna"
        }
    }

    var systemImage: String {
        switch self {
        case .you: "location.circle.fill"
        case .social: "person.2.fill"
        case .been: "checkmark.circle.fill"
        case .wanna: "circle.dashed"
        }
    }

    func trimColor(isSelected: Bool) -> Color {
        guard isSelected else {
            switch self {
            case .social:
                return WanderTheme.pinSocial.color.opacity(0.45)
            case .been, .wanna:
                return WanderTheme.textMuted.color.opacity(0.42)
            case .you:
                return WanderTheme.surfaceRaised.color.opacity(0.55)
            }
        }

        switch self {
        case .social:
            return WanderTheme.pinSocial.color
        case .been, .wanna:
            return WanderTheme.textInk.color.opacity(0.82)
        case .you:
            return WanderTheme.terracotta.color
        }
    }

    func iconColor(isSelected: Bool) -> Color {
        switch self {
        case .social:
            return isSelected ? WanderTheme.pinSocial.color : WanderTheme.textInk.color
        case .been, .wanna:
            return trimColor(isSelected: isSelected)
        case .you:
            return isSelected ? WanderTheme.terracotta.color : WanderTheme.textInk.color
        }
    }

    func trimStyle(isSelected: Bool) -> StrokeStyle {
        StrokeStyle(
            lineWidth: isSelected ? 2 : 1,
            lineCap: .round,
            dash: self == .wanna ? [1, 4] : []
        )
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
        case saved(VisiblePlace)
        case mapKit(PlaceCandidate)
    }

    let id: String
    let title: String
    let subtitle: String
    let category: String
    let source: Source

    static func saved(_ visiblePlace: VisiblePlace, saveCount: Int = 1) -> MapSearchSuggestion {
        let saveLabel: String
        if saveCount > 1 {
            saveLabel = "\(visiblePlace.owner.displayName) + \(saveCount - 1) \(saveCount == 2 ? "other" : "others") saved"
        } else {
            saveLabel = "\(visiblePlace.owner.displayName) saved it"
        }

        let subtitle = [
            saveLabel,
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
            subtitle: subtitle.isEmpty ? "saved on Wander" : subtitle,
            category: visiblePlace.effectiveCategory,
            source: .saved(visiblePlace)
        )
    }

    static func mapKit(_ candidate: PlaceCandidate) -> MapSearchSuggestion {
        return MapSearchSuggestion(
            id: "mapkit_\(candidate.id)",
            title: candidate.name,
            subtitle: candidate.previewSubtitle(trailingParts: ["not saved"]),
            category: candidate.category,
            source: .mapKit(candidate)
        )
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
    @Binding var query: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("search your map or people...", text: $query)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textInk.color)
                .tint(WanderTheme.terracotta.color)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
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
}

private struct MapTypeaheadList: View {
    let suggestions: [MapSearchSuggestion]
    let isLoading: Bool
    let onSelect: (MapSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    MapTypeaheadRow(suggestion: suggestion)
                }
                .buttonStyle(.plain)

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

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: WanderPlaceCategory.symbolName(for: suggestion.category))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(iconBackground)
                .clipShape(Circle())

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

            Spacer()

            Image(systemName: isSavedSuggestion ? "checkmark.circle.fill" : "plus.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isSavedSuggestion ? WanderTheme.stateSuccess.color : WanderTheme.pinSocial.color)
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .padding(.vertical, WanderTheme.spacing2)
        .contentShape(Rectangle())
        .accessibilityLabel("\(suggestion.title), \(suggestion.subtitle)")
    }

    private var isSavedSuggestion: Bool {
        if case .saved = suggestion.source { return true }
        return false
    }

    private var iconColor: Color {
        isSavedSuggestion ? WanderTheme.terracotta.color : WanderTheme.pinSocial.color
    }

    private var iconBackground: Color {
        isSavedSuggestion ? WanderTheme.terracottaTint.color : WanderTheme.skyTint.color
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
        .frame(height: 38)
        .background(WanderTheme.surfaceSand.color)
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
                Text(selectedOwner?.displayName ?? "social")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, WanderTheme.spacing3)
            .frame(height: 38)
            .background(WanderTheme.surfaceSand.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        selectedOwner == nil
                            ? MapFilter.social.trimColor(isSelected: isSelected)
                            : WanderTheme.textInk.color.opacity(0.82),
                        lineWidth: selectedOwner == nil ? (isSelected ? 2 : 1) : 2
                    )
            )
            .shadow(color: WanderTheme.textInk.color.opacity(isSelected ? 0.12 : 0), radius: 8, x: 0, y: 3)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .accessibilityLabel(selectedOwner.map { "Social places filtered to \($0.displayName)" } ?? "Social places filter")
    }
}

private struct SearchResultMarker: View {
    let candidate: PlaceCandidate
    let isSelected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: isSelected ? 17 : 15, weight: .black))
            .frame(width: isSelected ? 42 : 38, height: isSelected ? 42 : 38)
            .background(WanderTheme.pinSocial.color)
            .foregroundStyle(WanderTheme.surfaceRaised.color)
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
            .accessibilityLabel("Unsaved map result, \(candidate.name)")
    }

    private var symbol: String {
        WanderPlaceCategory.symbolName(for: candidate.category)
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
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .frame(width: 38, height: 38)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(outlineLayer)
            .overlay(
                Circle()
                    .stroke(WanderTheme.textInk.color.opacity(isSelected ? 0.2 : 0), lineWidth: 1)
                    .padding(-4)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .accessibilityLabel("\(accessibilityOwnershipLabel) \(visiblePlace.effectiveCategoryDisplay.compactTitle), \(visiblePlace.place.canonicalName)")
    }

    private var outlineLayer: some View {
        ForEach(Array(outlines.indices), id: \.self) { index in
            Circle()
                .stroke(
                    outlines[index].color,
                    style: StrokeStyle(
                        lineWidth: outlineLineWidth,
                        lineCap: .round,
                        dash: outlines[index].dashPattern
                    )
                )
                .padding(outlinePadding(for: index))
        }
    }

    private var symbol: String {
        WanderPlaceCategory.symbolName(for: visiblePlace.categoryAssignment)
    }

    private var outlineLineWidth: CGFloat {
        outlines.count > 1 ? 2.5 : 3
    }

    private func outlinePadding(for index: Int) -> CGFloat {
        guard outlines.count > 1 else { return 0 }
        return index == 0 ? 0 : -5
    }

    private var accessibilityOwnershipLabel: String {
        let hasCurrentUser = outlines.contains { $0.ownership == .currentUser }
        let hasSocial = outlines.contains { $0.ownership == .social }

        if hasCurrentUser && hasSocial {
            return "Your and social saved place"
        }

        return hasCurrentUser ? "Your saved place" : "Social saved place"
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

struct MapPinOutline: Identifiable, Equatable {
    let ownership: MapPinSaveOwnership
    let status: PlaceStatus

    var id: String {
        "\(ownership.key)-\(status.rawValue)"
    }

    var color: Color {
        ownership.color
    }

    var dashPattern: [CGFloat] {
        status == .wannaGo ? [5, 4] : []
    }
}

enum MapPinOutlineBuilder {
    static func outlines(for states: [MapPinSaveState]) -> [MapPinOutline] {
        [
            outline(for: .currentUser, in: states),
            outline(for: .social, in: states)
        ]
        .compactMap { $0 }
    }

    private static func outline(
        for ownership: MapPinSaveOwnership,
        in states: [MapPinSaveState]
    ) -> MapPinOutline? {
        let matchingStates = states.filter { $0.ownership == ownership }
        guard !matchingStates.isEmpty else { return nil }

        let status: PlaceStatus = matchingStates.contains { $0.status == .been } ? .been : .wannaGo
        return MapPinOutline(ownership: ownership, status: status)
    }
}

enum PlaceSheetAction {
    case add
    case edit
    case none

    var systemImage: String {
        switch self {
        case .add: "plus"
        case .edit: "pencil"
        case .none: ""
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .add: "Save to my map"
        case .edit: "Edit saved place"
        case .none: ""
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
    let address: String?
    let locality: String?
    let region: String?
    let latitude: Double?
    let longitude: Double?
    let websiteURLString: String?
    let phoneNumber: String?
    let actionLinksJSON: String?
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

    init(visiblePlace: VisiblePlace) {
        self.id = visiblePlace.place.id
        self.name = visiblePlace.place.canonicalName
        self.category = visiblePlace.effectiveCategory
        self.primaryCategory = visiblePlace.effectiveCategory
        self.subcategory = visiblePlace.effectiveSubcategory
        self.categorySource = visiblePlace.categoryAssignment.source
        self.categoryConfidence = visiblePlace.categoryAssignment.confidence
        self.rawProviderType = visiblePlace.place.rawProviderType
        self.address = visiblePlace.place.address
        self.locality = visiblePlace.place.locality
        self.region = visiblePlace.place.region
        self.latitude = visiblePlace.place.latitude
        self.longitude = visiblePlace.place.longitude
        self.websiteURLString = visiblePlace.place.websiteURLString
        self.phoneNumber = visiblePlace.place.phoneNumber
        self.actionLinksJSON = visiblePlace.place.actionLinksJSON
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
        self.address = candidate.address
        self.locality = candidate.locality
        self.region = candidate.region
        self.latitude = candidate.latitude
        self.longitude = candidate.longitude
        self.websiteURLString = candidate.websiteURLString
        self.phoneNumber = candidate.phoneNumber
        self.actionLinksJSON = candidate.actionLinksJSON
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
    case edit(VisiblePlace)
}

struct MapPlaceSaveContext: Identifiable {
    let id = UUID()
    let candidate: PlaceCandidate
    let mode: MapPlaceSaveMode
    let initialStatus: PlaceStatus
    let initialVisibility: PlaceVisibility
    let initialRatingScore: Double
    let initialNote: String
    let initialAnswers: [String: Set<String>]
    let initialPersonalLabels: Set<String>
    let initialCuisine: String?

    var isEditing: Bool {
        if case .edit = mode {
            return true
        }
        return false
    }

    var title: String {
        switch mode {
        case .add:
            "save this place"
        case .edit:
            "edit this place"
        }
    }

    var subtitle: String {
        switch mode {
        case .add:
            "pick status and a few details."
        case .edit:
            "update what future you sees on the map."
        }
    }

    var saveTitle: String {
        switch mode {
        case .add:
            "save to my map"
        case .edit:
            "update my map"
        }
    }

    static func addCandidate(
        _ candidate: PlaceCandidate,
        sourceType: AddSourceType,
        defaultVisibility: PlaceVisibility
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate,
            mode: .add(sourceType),
            initialStatus: .wannaGo,
            initialVisibility: defaultVisibility,
            initialRatingScore: PlaceRating.defaultScore,
            initialNote: "",
            initialAnswers: [:],
            initialPersonalLabels: [],
            initialCuisine: nil
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
            initialStatus: visiblePlace.userPlace.status,
            initialVisibility: defaultVisibility,
            initialRatingScore: visiblePlace.userPlace.ratingScore ?? PlaceRating.defaultScore,
            initialNote: "",
            initialAnswers: initialAnswers(from: attributes),
            initialPersonalLabels: initialPersonalLabels(from: attributes),
            initialCuisine: initialCuisine(from: attributes)
        )
    }

    static func editVisiblePlace(
        _ visiblePlace: VisiblePlace,
        attributes: [LocalPlaceAttribute]
    ) -> MapPlaceSaveContext {
        MapPlaceSaveContext(
            candidate: candidate(from: visiblePlace),
            mode: .edit(visiblePlace),
            initialStatus: visiblePlace.userPlace.status,
            initialVisibility: visiblePlace.userPlace.visibility,
            initialRatingScore: visiblePlace.userPlace.ratingScore ?? PlaceRating.defaultScore,
            initialNote: visiblePlace.userPlace.note ?? "",
            initialAnswers: initialAnswers(from: attributes),
            initialPersonalLabels: initialPersonalLabels(from: attributes),
            initialCuisine: initialCuisine(from: attributes)
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

    private static func initialPersonalLabels(from attributes: [LocalPlaceAttribute]) -> Set<String> {
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
}

struct MapPlaceSaveSubmission {
    let context: MapPlaceSaveContext
    let candidate: PlaceCandidate
    let status: PlaceStatus
    let visibility: PlaceVisibility
    let ratingScore: Double?
    let note: String?
    let attributes: [PlaceAttributeDraft]
}

private enum MapPlaceSaveStep {
    case confirm
    case details
}

private enum PlaceTypePickerMode {
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
    @State private var isSaving = false
    @State private var isRemoving = false
    @State private var isShowingRemoveConfirmation = false
    @State private var errorMessage: String?

    init(
        context: MapPlaceSaveContext,
        onSave: @escaping @MainActor (MapPlaceSaveSubmission) async -> SaveResult?,
        onRemove: @escaping @MainActor (MapPlaceSaveContext) async -> Bool
    ) {
        self.context = context
        self.onSave = onSave
        self.onRemove = onRemove
        _step = State(initialValue: context.isEditing ? .details : .confirm)
        _selectedAssignment = State(initialValue: context.candidate.categoryAssignment)
        _selectedStatus = State(initialValue: context.initialStatus)
        _selectedVisibility = State(initialValue: context.initialVisibility.normalizedForStealthMode)
        _selectedRatingScore = State(initialValue: context.initialRatingScore)
        _selectedAnswers = State(initialValue: context.initialAnswers)
        _personalLabels = State(initialValue: context.initialPersonalLabels)
        _selectedCuisine = State(initialValue: Self.initialCuisine(for: context))
        _note = State(initialValue: context.initialNote)
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

    private var placeTypeCompactTitle: String {
        let display = WanderPlaceCategory.display(for: selectedAssignmentForSave)
        guard isRestaurantsFoodSelected, let selectedCuisine else {
            return display.compactTitle
        }

        return [selectedCuisine, display.subcategory, display.category]
            .compactMap { $0 }
            .joined(separator: " · ")
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
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header

                    switch step {
                    case .confirm:
                        confirmContent
                    case .details:
                        detailsContent
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(WanderTheme.canvasWarm.color)
            .sheet(isPresented: $isChoosingPlaceType) {
                PlaceTypePickerSheet(
                    selectedAssignment: $selectedAssignment,
                    selectedCuisine: $selectedCuisine,
                    initialMode: placeTypePickerMode
                ) {
                    handlePlaceTypeSelection()
                }
                .id(placeTypePickerMode)
            }
            .onAppear {
                if store.isPrivateProfile {
                    selectedVisibility = .selfOnly
                }
                if step == .details {
                    syncAnswersForCurrentQuestions()
                }
            }
            .onChange(of: store.isPrivateProfile) { _, isPrivateProfile in
                if isPrivateProfile {
                    selectedVisibility = .selfOnly
                }
            }
            .alert("Remove save?", isPresented: $isShowingRemoveConfirmation) {
                Button("Remove save", role: .destructive) {
                    removeSave()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(removeSaveConfirmationMessage)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                if step == .details && !context.isEditing {
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

            Text(context.title)
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
            Text(context.subtitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
        }
    }

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            candidateCard

            MapSavePickerBlock(title: "save as") {
                HStack(spacing: WanderTheme.spacing2) {
                    MapSaveChoicePill(title: "been", isSelected: selectedStatus == .been) {
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
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            candidateCard
            placeTypeSection

            if context.isEditing {
                saveAsSection
            }

            if selectedStatus == .been {
                PlaceRatingSlider(score: $selectedRatingScore)
            }

            ForEach(questionBlocks) { block in
                MapSaveQuestionBlock(title: block.title, tag: block.tag) {
                    MapSaveQuestionOptions(
                        block: block,
                        selectedValues: selectedAnswers[block.key] ?? Set(block.defaultValues)
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

            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Text("a note for future you")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                TextField("best table, what to order, who told you...", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .tint(WanderTheme.terracotta.color)
                    .lineLimit(3, reservesSpace: true)
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceRaised.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
            }

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
            .opacity(store.isPrivateProfile ? 0.56 : 1)

            WanderPrimaryButton(
                title: isSaving ? "saving..." : context.saveTitle,
                systemImage: "checkmark",
                isDisabled: isSaving || isRemoving
            ) {
                save()
            }

            if context.isEditing {
                removeSaveSection
            }
        }
    }

    private var removeSaveSection: some View {
        MapSaveDestructiveButton(
            title: isRemoving ? "removing..." : "Remove save",
            systemImage: "trash",
            isDisabled: isSaving || isRemoving
        ) {
            isShowingRemoveConfirmation = true
        }
        .padding(.top, WanderTheme.spacing1)
    }

    private var placeTypeSection: some View {
        let display = WanderPlaceCategory.display(for: selectedAssignmentForSave)
        let categoryValue = selectedAssignmentForSave.primaryCategory == WanderPlaceCategory.fallbackPlace
            ? "choose category"
            : display.category

        return VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("place type")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)

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

                    Divider().background(WanderTheme.borderHairline.color)
                }

                Button {
                    placeTypePickerMode = .subcategory
                    isChoosingPlaceType = true
                } label: {
                    PlaceTypeRow(title: "subcategory", value: display.subcategory ?? "choose one")
                }
                .buttonStyle(.plain)
            }
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
            .overlay(
                RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                    .stroke(WanderTheme.borderHairline.color)
            )
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var saveAsSection: some View {
        MapSavePickerBlock(title: "save as") {
            HStack(spacing: WanderTheme.spacing2) {
                MapSaveChoicePill(title: "been", isSelected: selectedStatus == .been) {
                    selectedStatus = .been
                    syncAnswersForCurrentQuestions()
                }
                MapSaveChoicePill(title: "wanna go", isSelected: selectedStatus == .wannaGo) {
                    selectedStatus = .wannaGo
                    syncAnswersForCurrentQuestions()
                }
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var candidateCard: some View {
        HStack(spacing: WanderTheme.spacing3) {
            CategoryThumb(category: selectedAssignment.primaryCategory)

            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(context.candidate.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
                Text(candidateSubtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(2)
                Text(selectedStatus.displayTitle)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }

            Spacer()
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var candidateSubtitle: String {
        selectedCandidate.previewSubtitle(
            includeDistance: false,
            includeCategory: false,
            trailingParts: [placeTypeCompactTitle]
        )
    }

    private static func initialCuisine(for context: MapPlaceSaveContext) -> String? {
        guard context.candidate.primaryCategory == WanderPlaceCategory.restaurantsFood else {
            return nil
        }

        return context.initialCuisine
            ?? WanderPlaceCategory.cuisineGuess(forRawValue: context.candidate.rawProviderType)
            ?? WanderPlaceCategory.cuisineGuess(forRawValue: context.candidate.subcategory)
            ?? WanderPlaceCategory.cuisineGuess(forRawValue: context.candidate.category)
    }

    private func prepareDetails() {
        syncAnswersForCurrentQuestions()
        errorMessage = nil
        step = .details
    }

    private func syncAnswersForCurrentQuestions() {
        var nextAnswers = selectedAnswers

        for block in questionBlocks {
            var values = nextAnswers[block.key] ?? []
            if values.isEmpty {
                values = Set(block.defaultValues)
            } else if block.kind == .multiTag {
                values.formUnion(block.defaultValues)
            }
            nextAnswers[block.key] = values
        }

        selectedAnswers = nextAnswers
        personalLabels.formUnion(personalLabelBlock.defaultValues)
    }

    private func handlePlaceTypeSelection() {
        if selectedAssignment.primaryCategory != WanderPlaceCategory.restaurantsFood {
            selectedCuisine = nil
        }

        syncAnswersForCurrentQuestions()
    }

    private func toggleAnswer(_ option: String, in block: AddQuestionBlock) {
        var values = selectedAnswers[block.key] ?? Set(block.defaultValues)

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
        let values = selectedAnswers[block.key] ?? Set(block.defaultValues)
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
            if case let .edit(currentPlace) = context.mode,
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
        isSaving = true
        errorMessage = nil

        let submission = MapPlaceSaveSubmission(
            context: context,
            candidate: selectedCandidate,
            status: selectedStatus,
            visibility: saveVisibility,
            ratingScore: selectedStatus == .been ? selectedRatingScore : nil,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
            attributes: attributeDrafts()
        )

        Task {
            let result = await onSave(submission)
            await MainActor.run {
                isSaving = false
                if result != nil {
                    dismiss()
                } else {
                    errorMessage = "Sign in to finish this save."
                }
            }
        }
    }

    private var removeSaveConfirmationMessage: String {
        "This removes \(context.candidate.name) from your map and deletes your note, rating, tags, labels, and answers. It will not remove the place for anyone else."
    }

    private func removeSave() {
        guard context.isEditing, !isSaving, !isRemoving else { return }

        isRemoving = true
        errorMessage = nil

        Task {
            let removed = await onRemove(context)
            await MainActor.run {
                isRemoving = false
                if removed {
                    dismiss()
                } else {
                    errorMessage = "Could not remove this save. Try again."
                }
            }
        }
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
        .frame(minHeight: 48)
    }
}

private struct PlaceTypePickerSheet: View {
    @Binding var selectedAssignment: PlaceCategoryAssignment
    @Binding var selectedCuisine: String?
    let initialMode: PlaceTypePickerMode
    let onSelect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: PlaceTypePickerMode
    @State private var query = ""

    init(
        selectedAssignment: Binding<PlaceCategoryAssignment>,
        selectedCuisine: Binding<String?>,
        initialMode: PlaceTypePickerMode,
        onSelect: @escaping () -> Void
    ) {
        _selectedAssignment = selectedAssignment
        _selectedCuisine = selectedCuisine
        self.initialMode = initialMode
        self.onSelect = onSelect

        let primaryCategory = selectedAssignment.wrappedValue.primaryCategory
        let hasEditableSelection = WanderPlaceCategory.editableCategories.contains(primaryCategory)
        let startingMode: PlaceTypePickerMode
        if !hasEditableSelection {
            startingMode = .category
        } else if initialMode == .cuisine,
                  primaryCategory != WanderPlaceCategory.restaurantsFood {
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

    private var selectedSubcategories: [String] {
        WanderPlaceCategory.subcategorySuggestions(for: selectedPrimaryCategory)
    }

    private var selectedSubcategoryGroups: [PlaceCategorySubcategoryGroup] {
        filteredGroupsForCurrentSelection(
            role: selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood ? .type : nil
        )
    }

    private var selectedCuisineGroups: [PlaceCategorySubcategoryGroup] {
        filteredGroupsForCurrentSelection(role: .cuisine)
    }

    private var subcategoryGroupsForCurrentSelection: [PlaceCategorySubcategoryGroup] {
        WanderPlaceCategory.subcategoryGroups(for: selectedPrimaryCategory)
    }

    private var restaurantTypeCount: Int {
        WanderPlaceCategory.restaurantTypeGroups().flatMap(\.subcategories).count
    }

    private var restaurantCuisineCount: Int {
        WanderPlaceCategory.restaurantCuisineOptions.count
    }

    private var selectedCategoryTitle: String {
        WanderPlaceCategory.broadCategory(for: selectedPrimaryCategory)
    }

    private var selectedCategoryCount: Int {
        if selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood {
            return restaurantTypeCount
        }

        return selectedSubcategories.count
    }

    private var selectedSubcategorySubtitle: String {
        if selectedPrimaryCategory == WanderPlaceCategory.restaurantsFood {
            return "\(selectedCategoryTitle) - \(restaurantTypeCount) types"
        }

        return "\(selectedCategoryTitle) - \(selectedCategoryCount) types"
    }

    private var selectedCuisineSubtitle: String {
        "\(selectedCategoryTitle) - \(restaurantCuisineCount) cuisines"
    }

    private var selectedCategorySearchName: String {
        selectedCategoryTitle.lowercased()
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
            CategoryPickerHeader(title: "choose subcategory", subtitle: selectedSubcategorySubtitle)

            CategoryPickerSearchField(placeholder: "Search \(selectedCategorySearchName) types", text: $query)

            selectedCategoryPills

            if !hasEditableSelection {
                CategoryPickerEmptyState(title: "Choose a category first", message: "Pick one of the 14 primary categories, then choose its type.")
            } else if selectedSubcategoryGroups.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    CategoryPickerEmptyState(title: "No matching type", message: "Try a broader search, or add your custom type below.")
                    customSubcategoryControl
                }
            } else {
                ForEach(selectedSubcategoryGroups, id: \.title) { group in
                    SubcategoryGroupSection(
                        group: group,
                        selectedSubcategory: selectedAssignment.subcategory
                    ) { subcategory in
                        selectSubcategory(subcategory)
                        dismiss()
                    }
                }

                customSubcategoryControl
            }
        }
    }

    private var cuisinePickerContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            CategoryPickerHeader(title: "choose cuisine", subtitle: selectedCuisineSubtitle)

            CategoryPickerSearchField(placeholder: "Search cuisines", text: $query)

            selectedCategoryPills

            if selectedPrimaryCategory != WanderPlaceCategory.restaurantsFood {
                CategoryPickerEmptyState(title: "Choose Restaurants & Food first", message: "Cuisine only applies to restaurants and food places.")
            } else if selectedCuisineGroups.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    CategoryPickerEmptyState(title: "No matching cuisine", message: "Try Thai, Mexican, Korean BBQ, or South American.")
                    clearCuisineControl
                }
            } else {
                ForEach(selectedCuisineGroups, id: \.title) { group in
                    SubcategoryGroupSection(
                        group: group,
                        selectedSubcategory: selectedCuisine
                    ) { cuisine in
                        selectCuisine(cuisine)
                        dismiss()
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
                systemImage: WanderPlaceCategory.symbolName(for: selectedPrimaryCategory),
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
                dismiss()
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
                dismiss()
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
        mode = .subcategory
        onSelect()
    }

    private func selectCuisine(_ cuisine: String) {
        selectedCuisine = cuisine
        query = ""
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

    private func filteredGroupsForCurrentSelection(role: PlaceCategorySubcategoryRole?) -> [PlaceCategorySubcategoryGroup] {
        let groups = groupsForCurrentSelection(role: role)
        let queryText = normalizedQuery
        guard !queryText.isEmpty else {
            return groups
        }

        return groups.compactMap { group in
            let groupMatches = group.title.localizedCaseInsensitiveContains(queryText)
            let subcategories = groupMatches
                ? group.subcategories
                : group.subcategories.filter { $0.localizedCaseInsensitiveContains(queryText) }

            guard !subcategories.isEmpty else { return nil }
            return PlaceCategorySubcategoryGroup(title: group.title, subcategories: subcategories, role: group.role)
        }
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

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                HStack {
                    ZStack {
                        Circle().fill(accent.opacity(0.16))
                        Image(systemName: WanderPlaceCategory.symbolName(for: category))
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(accent)
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

                Text("\(WanderPlaceCategory.subcategorySuggestions(for: category).count) types")
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
        .accessibilityLabel("\(WanderPlaceCategory.broadCategory(for: category)), \(WanderPlaceCategory.subcategorySuggestions(for: category).count) types")
    }
}

struct CategoryPickerModePill: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .black))
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
                .accessibilityLabel("Save custom tag")
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
                CategoryThumb(category: place.primaryCategory)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    HStack {
                        Text(place.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        statusBadge
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

            if !placeFacts.isEmpty {
                factSection(title: "place", facts: placeFacts)
            }

            if let ownSave {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    sectionTitle("your note")
                    SaveReviewCard(summary: ownSave, currentUserID: currentUserID, emphasis: true)
                }
            }

            if !friendSaves.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    sectionTitle("friends' notes")
                    ForEach(friendSaves) { summary in
                        SaveReviewCard(summary: summary, currentUserID: currentUserID, emphasis: false)
                    }
                }
            }
        }
        .padding(.bottom, WanderTheme.spacing1)
    }

    private var expandedHeader: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            CategoryThumb(category: place.primaryCategory)
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
            ShareLink(item: shareURL, subject: Text(place.name), message: Text(shareText)) {
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
                    PlaceFactPill(title: fact.title, systemImage: fact.systemImage)
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
        presentation.fitRating != nil || presentation.overallRating != nil || presentation.ownRating != nil
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
            facts.append(PlaceFact(title: categoryDisplay, systemImage: WanderPlaceCategory.symbolName(for: place.categoryAssignment)))
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
        guard attribute.questionKey != PlaceMemoryAttributeKeys.restaurantCuisine else { return [] }

        if attribute.valueType == "multi_tag" {
            return decodedStringArray(from: attribute.valueJSON).map { value in
                PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
            }
        }

        guard let value = decodedString(from: attribute.valueJSON) else { return [] }
        return [PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))]
    }

    private static func icon(for questionKey: String) -> String {
        switch questionKey {
        case "interest_signal": "heart.fill"
        case "rating_signal": "heart.fill"
        case "work_setup": "laptopcomputer"
        case "strenuousness": "figure.hiking"
        case "price": "dollarsign.circle.fill"
        case "occasion", "best_for": "sparkles"
        default: "tag.fill"
        }
    }

    private static func decodedString(from valueJSON: String) -> String? {
        guard let data = valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func decodedStringArray(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
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
                Image(systemName: action.systemImage)
                    .font(.system(size: iconSize, weight: .black))
                    .frame(width: size, height: size)
                    .background(action == .add ? WanderTheme.terracotta.color : WanderTheme.textInk.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel(action.accessibilityLabel)
        }
    }
}

private struct PlaceFact: Identifiable {
    var id: String { "\(systemImage)-\(title)" }
    let title: String
    let systemImage: String
}

private struct PlaceProfileRatingStrip: View {
    let presentation: PlaceProfilePresentation
    let compact: Bool

    var body: some View {
        HStack(spacing: WanderTheme.spacing2) {
            if let fitRating = presentation.fitRating {
                PlaceProfileMetricCard(
                    title: "Fit",
                    value: fitRating.displayScore,
                    suffix: "/10",
                    subtitle: compact ? "for you" : "compared to places you like",
                    systemImage: "sparkles",
                    tint: WanderTheme.terracotta.color,
                    compact: compact
                )
            }

            if let actualRating = presentation.overallRating ?? presentation.ownRating {
                PlaceProfileMetricCard(
                    title: actualRating.title,
                    value: actualRating.displayScore,
                    suffix: "/5",
                    subtitle: actualRating.subtitle,
                    systemImage: "star.fill",
                    tint: WanderTheme.stateWarning.color,
                    compact: compact
                )
            }
        }
    }
}

private struct PlaceProfileMetricCard: View {
    let title: String
    let value: String
    let suffix: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let compact: Bool

    var body: some View {
        HStack(alignment: .center, spacing: compact ? WanderTheme.spacing2 : WanderTheme.spacing3) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 13 : 15, weight: .black))
                .foregroundStyle(tint)
                .frame(width: compact ? 28 : 34, height: compact ? 28 : 34)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: compact ? 11 : 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .textCase(.uppercase)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: compact ? 20 : 24, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text(suffix)
                        .font(.system(size: compact ? 11 : 12, weight: .black))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Text(subtitle)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? WanderTheme.spacing2 : WanderTheme.spacing3)
        .frame(maxWidth: .infinity, minHeight: compact ? 62 : 76, alignment: .leading)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
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
                        PlaceFactPill(title: fact.title, systemImage: fact.systemImage)
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
        guard attribute.questionKey != PlaceMemoryAttributeKeys.restaurantCuisine else { return [] }

        if attribute.valueType == "multi_tag" {
            return decodedStringArray(from: attribute.valueJSON).map { value in
                PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
            }
        }

        guard let value = decodedString(from: attribute.valueJSON) else { return [] }
        return [PlaceFact(title: value, systemImage: icon(for: attribute.questionKey))]
    }

    private func icon(for questionKey: String) -> String {
        switch questionKey {
        case "interest_signal": "heart.fill"
        case "rating_signal": "heart.fill"
        case "work_setup": "laptopcomputer"
        case "strenuousness": "figure.hiking"
        case "price": "dollarsign.circle.fill"
        case "occasion", "best_for": "sparkles"
        default: "tag.fill"
        }
    }

    private func decodedString(from valueJSON: String) -> String? {
        guard let data = valueJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private func decodedStringArray(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
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
        guard let first = savers.first else { return "saved on Wander" }
        let name = first.id == currentUserID ? "you" : first.displayName
        guard savers.count > 1 else { return "\(name) saved it" }
        return "\(name) +\(savers.count - 1) others saved it"
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
    let systemImage: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing1) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
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
    let category: String

    var body: some View {
        Image(systemName: imageName)
            .font(.system(size: 19, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(width: 46, height: 46)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())
    }

    private var imageName: String {
        WanderPlaceCategory.symbolName(for: category)
    }
}

private struct StatusBadge: View {
    let status: PlaceStatus

    var body: some View {
        Text(status == .been ? "been" : "wanna")
            .font(.system(size: 12, weight: .bold))
            .padding(.horizontal, WanderTheme.spacing2)
            .padding(.vertical, WanderTheme.spacing1)
            .background(status == .been ? WanderTheme.stateSuccess.color.opacity(0.16) : WanderTheme.sunTint.color)
            .foregroundStyle(status == .been ? WanderTheme.stateSuccess.color : WanderTheme.stateWarning.color)
            .clipShape(Capsule())
    }
}
