@preconcurrency import MapKit
import SwiftUI
import UIKit

struct MapScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedPlaceID: String?
    @State private var selectedSearchCandidateID: String?
    @State private var selectedMapFeature: MapFeature?
    @State private var ignoreNextMapFeatureClear = false
    @State private var mapSaveFlow: MapPlaceSaveContext?
    @State private var isPlaceSheetExpanded: Bool
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
        startsExpanded: Bool = ProcessInfo.processInfo.arguments.contains("-WanderMapSheetExpanded")
    ) {
        self.initialPlaceQuery = initialPlaceQuery
        _isPlaceSheetExpanded = State(initialValue: startsExpanded)
    }

    private var visiblePlaces: [VisiblePlace] {
        let places = baseVisiblePlaces
        let normalizedQuery = mapQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return places }

        return places.filter { visiblePlace in
            visiblePlace.place.canonicalName.lowercased().contains(normalizedQuery)
                || visiblePlace.place.category.lowercased().contains(normalizedQuery)
                || (visiblePlace.place.locality?.lowercased().contains(normalizedQuery) ?? false)
                || visiblePlace.owner.displayName.lowercased().contains(normalizedQuery)
                || visiblePlace.owner.handle.lowercased().contains(normalizedQuery)
                || (visiblePlace.userPlace.note?.lowercased().contains(normalizedQuery) ?? false)
                || (visiblePlace.userPlace.ratingSignal?.lowercased().contains(normalizedQuery) ?? false)
        }
    }

    private var mapAnnotationPlaces: [VisiblePlace] {
        var orderedPlaceIDs: [String] = []
        var representatives: [String: VisiblePlace] = [:]

        for visiblePlace in visiblePlaces {
            let placeID = visiblePlace.place.id
            if let current = representatives[placeID] {
                if shouldPreferMapRepresentative(visiblePlace, over: current) {
                    representatives[placeID] = visiblePlace
                }
            } else {
                orderedPlaceIDs.append(placeID)
                representatives[placeID] = visiblePlace
            }
        }

        return orderedPlaceIDs.compactMap { representatives[$0] }
    }

    private var visiblePlaceIDs: [String] {
        visiblePlaces.map(\.id)
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
        guard let selectedPlaceID else { return nil }
        return visiblePlaces.first { $0.id == selectedPlaceID }
    }

    private var selectedSearchCandidate: PlaceCandidate? {
        guard let selectedSearchCandidateID else { return nil }
        return mapSearchCandidates.first { $0.id == selectedSearchCandidateID }
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
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: $selectedMapFeature) {
                UserAnnotation()

                ForEach(mapAnnotationPlaces) { visiblePlace in
                    Annotation(
                        visiblePlace.place.canonicalName,
                        coordinate: CLLocationCoordinate2D(latitude: visiblePlace.place.latitude, longitude: visiblePlace.place.longitude)
                    ) {
                        Button {
                            clearNativeMapFeatureSelection()
                            selectedPlaceID = visiblePlace.id
                            selectedSearchCandidateID = nil
                            isPlaceSheetExpanded = false
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
                                clearNativeMapFeatureSelection()
                                selectedSearchCandidateID = candidate.id
                                selectedPlaceID = nil
                                isPlaceSheetExpanded = false
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

            VStack(spacing: 0) {
                VStack(spacing: WanderTheme.spacing2) {
                    SearchBar(
                        query: $mapQuery,
                        userInitials: store.currentUser.initials,
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
                .padding(.top, WanderTheme.spacing2)

                Spacer()

                HStack {
                    Spacer()
                    RecenterButton(isLoading: isRecenteringOnUser) {
                        recenterOnUser()
                    }
                    .padding(.trailing, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing2)
                }

                if let selectedSearchCandidate {
                    PlaceSheet(
                        place: PlaceSheetPlace(candidate: selectedSearchCandidate),
                        saves: saveSummaries(for: selectedSearchCandidate),
                        currentUserID: store.currentUser.id,
                        action: .add,
                        isExpanded: $isPlaceSheetExpanded
                    ) {
                        mapSaveFlow = MapPlaceSaveContext.addCandidate(
                            selectedSearchCandidate,
                            sourceType: .manual,
                            defaultVisibility: store.defaultVisibility
                        )
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing2)
                } else if let selectedPlace {
                    PlaceSheet(
                        place: PlaceSheetPlace(visiblePlace: selectedPlace),
                        saves: saveSummaries(for: selectedPlace),
                        currentUserID: store.currentUser.id,
                        action: action(for: selectedPlace),
                        isExpanded: $isPlaceSheetExpanded
                    ) {
                        performAction(for: selectedPlace)
                    }
                    .padding(.horizontal, WanderTheme.spacing3)
                    .padding(.bottom, WanderTheme.spacing2)
                }
            }
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
        .onChange(of: visiblePlaceIDs) { _, ids in
            if let current = selectedPlaceID, !ids.contains(current) {
                selectedPlaceID = nil
                isPlaceSheetExpanded = false
            }
            centerMapOnInitialPlacesIfNeeded()
        }
        .onChange(of: mapQuery) { _, _ in
            handleMapQueryChange()
            if let firstVisibleID = visiblePlaceIDs.first, !visiblePlaceIDs.contains(selectedPlaceID ?? "") {
                selectedPlaceID = firstVisibleID
                isPlaceSheetExpanded = false
            }
        }
        .onDisappear {
            typeaheadTask?.cancel()
            mapFeatureResolutionTask?.cancel()
        }
        .sheet(item: $mapSaveFlow) { context in
            MapPlaceSaveFlowSheet(context: context) { submission in
                await saveMapFlowSubmission(submission)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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
        selectedPlaceID = nil
        selectedSearchCandidateID = nil
        isPlaceSheetExpanded = false
    }

    private func clearNativeMapFeatureSelection() {
        mapFeatureResolutionTask?.cancel()
        mapFeatureResolutionTask = nil

        guard selectedMapFeature != nil else { return }
        ignoreNextMapFeatureClear = true
        selectedMapFeature = nil
    }

    private func clearMapFeatureCandidateSelection() {
        mapFeatureResolutionTask?.cancel()
        mapFeatureResolutionTask = nil
        selectedPlaceID = nil
        selectedSearchCandidateID = nil
        mapSearchCandidates = []
        mapSearchMessage = nil
        isPlaceSheetExpanded = false
    }

    private func resolveInitialSelection() {
        guard selectedPlaceID == nil else { return }

        if let initialPlaceQuery {
            let normalized = initialPlaceQuery.lowercased()
            selectedPlaceID = visiblePlaces.first { visiblePlace in
                visiblePlace.id.lowercased().contains(normalized)
                    || visiblePlace.place.id.lowercased().contains(normalized)
                    || visiblePlace.place.canonicalName.lowercased().contains(normalized)
            }?.id
        }

        if selectedPlaceID == nil {
            selectedPlaceID = visiblePlaces.first?.id
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

    private func shouldPreferMapRepresentative(_ candidate: VisiblePlace, over current: VisiblePlace) -> Bool {
        let candidateIsCurrentUser = candidate.owner.id == store.currentUser.id
        let currentIsCurrentUser = current.owner.id == store.currentUser.id

        if candidateIsCurrentUser != currentIsCurrentUser {
            return candidateIsCurrentUser
        }

        if candidate.id == selectedPlaceID {
            return true
        }

        if current.id == selectedPlaceID {
            return false
        }

        return false
    }

    private func isSelectedMapRepresentative(_ visiblePlace: VisiblePlace) -> Bool {
        selectedPlace?.place.id == visiblePlace.place.id
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()
        let summaries = store.visiblePlaces()
            .filter { $0.place.id == selectedPlace.place.id }
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

            if let firstVisibleID = visiblePlaceIDs.first {
                selectedPlaceID = firstVisibleID
                selectedSearchCandidateID = nil
                mapSearchMessage = mapSearchCandidates.isEmpty ? nil : "Also showing unsaved map results."
            } else if let firstCandidate = mapSearchCandidates.first {
                selectedPlaceID = nil
                selectedSearchCandidateID = firstCandidate.id
                center(on: firstCandidate)
                mapSearchMessage = "Map result. Tap + to add it."
            } else {
                selectedPlaceID = nil
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
                clearMapFeatureCandidateSelection()
            }
            return
        }

        ignoreNextMapFeatureClear = false
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
            selectedPlaceID = visiblePlace.id
            selectedSearchCandidateID = nil
            mapSearchCandidates = []
            isPlaceSheetExpanded = false
            mapSearchMessage = nil
            return
        }

        mapSearchCandidates = [candidate]
        selectedPlaceID = nil
        selectedSearchCandidateID = candidate.id
        isPlaceSheetExpanded = false
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
        if visiblePlace.owner.id == store.currentUser.id {
            return .edit
        }

        return isSavedByCurrentUser(visiblePlace) ? .none : .add
    }

    private func performAction(for visiblePlace: VisiblePlace) {
        switch action(for: visiblePlace) {
        case .add:
            mapSaveFlow = MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.defaultVisibility,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        case .edit:
            mapSaveFlow = MapPlaceSaveContext.editVisiblePlace(
                visiblePlace,
                attributes: store.attributes(for: visiblePlace.userPlace.id)
            )
        case .none:
            break
        }
    }

    private func isSavedByCurrentUser(_ visiblePlace: VisiblePlace) -> Bool {
        store.currentUserVisiblePlaces.contains { mine in
            mine.place.id == visiblePlace.place.id
                || mine.place.canonicalName.caseInsensitiveCompare(visiblePlace.place.canonicalName) == .orderedSame
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
                submission.context.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: sourceType,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            clearNativeMapFeatureSelection()
            selectedSearchCandidateID = nil
            selectedPlaceID = result.userPlaceID
            mapSearchCandidates.removeAll { $0.id == submission.context.candidate.id }
            showTransientMapSearchMessage("Added to your map.")

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            return result
        case .edit(let visiblePlace):
            let result = await store.saveCandidate(
                submission.context.candidate,
                status: submission.status,
                visibility: submission.visibility,
                note: submission.note,
                sourceType: AddSourceType(rawValue: visiblePlace.userPlace.sourceType) ?? .manual,
                attributes: submission.attributes,
                backend: auth.isSignedIn ? backend : nil
            )
            selectedSearchCandidateID = nil
            selectedPlaceID = result.userPlaceID
            showTransientMapSearchMessage("Updated saved place.")

            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }

            return result
        }
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
        baseVisiblePlaces.first { visiblePlace in
            visiblePlace.place.sourceProviderPlaceID == candidate.sourceProviderPlaceID
                || visiblePlace.place.canonicalName.caseInsensitiveCompare(candidate.name) == .orderedSame
        }
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
            visiblePlace.place.category,
            visiblePlace.place.locality,
            visiblePlace.owner.displayName,
            "@\(visiblePlace.owner.handle)",
            visiblePlace.userPlace.note,
            visiblePlace.userPlace.ratingSignal
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
            selectedPlaceID = visiblePlace.id
            selectedSearchCandidateID = nil
            mapSearchCandidates = []
            center(on: visiblePlace)
        case .mapKit(let candidate):
            selectedPlaceID = nil
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

    private static func resolvedInitialMapPlaceQuery(from arguments: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let flagIndex = arguments.firstIndex(of: "-WanderMapPlace") else {
            return nil
        }

        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else {
            return nil
        }

        return arguments[valueIndex]
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
            visiblePlace.place.category
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
            category: visiblePlace.place.category,
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
    let userInitials: String
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
            if query.isEmpty {
                WanderAvatar(initials: userInitials, size: 28, color: WanderTheme.terracotta.color)
            } else {
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
            .font(.system(size: isSelected ? 17 : 16, weight: .bold))
            .frame(width: isSelected ? 42 : 38, height: isSelected ? 42 : 38)
            .background(WanderTheme.surfaceRaised.color)
            .clipShape(Circle())
            .overlay(outlineLayer)
            .overlay(
                Circle()
                    .stroke(WanderTheme.textInk.color.opacity(isSelected ? 0.2 : 0), lineWidth: 1)
                    .padding(-4)
            )
            .shadow(color: WanderTheme.textInk.color.opacity(0.22), radius: isSelected ? 9 : 6, x: 0, y: 2)
            .accessibilityLabel("\(accessibilityOwnershipLabel) \(visiblePlace.place.category), \(visiblePlace.place.canonicalName)")
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
        WanderPlaceCategory.symbolName(for: visiblePlace.place.category)
    }

    private var outlineLineWidth: CGFloat {
        outlines.count > 1 ? (isSelected ? 3 : 2.5) : (isSelected ? 4 : 3)
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
            firstOutline(for: .currentUser, in: states),
            firstOutline(for: .social, in: states)
        ]
        .compactMap { $0 }
    }

    private static func firstOutline(
        for ownership: MapPinSaveOwnership,
        in states: [MapPinSaveState]
    ) -> MapPinOutline? {
        guard let state = states.first(where: { $0.ownership == ownership }) else { return nil }
        return MapPinOutline(ownership: ownership, status: state.status)
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

struct PlaceSaveSummary: Identifiable {
    let visiblePlace: VisiblePlace
    let attributes: [LocalPlaceAttribute]

    var id: String { visiblePlace.userPlace.id }
}

struct PlaceSheetPlace {
    let id: String
    let name: String
    let category: String
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

    init(visiblePlace: VisiblePlace) {
        self.id = visiblePlace.place.id
        self.name = visiblePlace.place.canonicalName
        self.category = visiblePlace.place.category
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
    let initialNote: String
    let initialAnswers: [String: Set<String>]

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
            "pick status, visibility, and a few details."
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
            initialNote: "",
            initialAnswers: [:]
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
            initialNote: "",
            initialAnswers: initialAnswers(from: attributes)
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
            initialNote: visiblePlace.userPlace.note ?? "",
            initialAnswers: initialAnswers(from: attributes)
        )
    }

    private static func candidate(from visiblePlace: VisiblePlace) -> PlaceCandidate {
        PlaceCandidate(
            id: visiblePlace.place.id,
            name: visiblePlace.place.canonicalName,
            category: visiblePlace.place.category,
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
            guard let data = attribute.valueJSON.data(using: .utf8) else { continue }
            if let values = try? decoder.decode([String].self, from: data) {
                answers[attribute.questionKey] = Set(values)
            } else if let value = try? decoder.decode(String.self, from: data) {
                answers[attribute.questionKey] = [value]
            }
        }

        return answers
    }
}

struct MapPlaceSaveSubmission {
    let context: MapPlaceSaveContext
    let status: PlaceStatus
    let visibility: PlaceVisibility
    let note: String?
    let attributes: [PlaceAttributeDraft]
}

private enum MapPlaceSaveStep {
    case confirm
    case details
}

struct MapPlaceSaveFlowSheet: View {
    let context: MapPlaceSaveContext
    let onSave: @MainActor (MapPlaceSaveSubmission) async -> SaveResult?
    @Environment(\.dismiss) private var dismiss
    @State private var step: MapPlaceSaveStep = .confirm
    @State private var selectedStatus: PlaceStatus
    @State private var selectedVisibility: PlaceVisibility
    @State private var selectedAnswers: [String: Set<String>]
    @State private var note: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(context: MapPlaceSaveContext, onSave: @escaping @MainActor (MapPlaceSaveSubmission) async -> SaveResult?) {
        self.context = context
        self.onSave = onSave
        _selectedStatus = State(initialValue: context.initialStatus)
        _selectedVisibility = State(initialValue: context.initialVisibility)
        _selectedAnswers = State(initialValue: context.initialAnswers)
        _note = State(initialValue: context.initialNote)
    }

    private var questionBlocks: [AddQuestionBlock] {
        AddQuestionTemplates.blocks(category: context.candidate.category, status: selectedStatus)
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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            HStack {
                if step == .details {
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

            MapSavePickerBlock(title: "who can see this") {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(PlaceVisibility.allCases, id: \.rawValue) { visibility in
                            MapSaveChoicePill(title: visibility.displayTitle, isSelected: selectedVisibility == visibility) {
                                selectedVisibility = visibility
                            }
                        }
                    }
                    Text(selectedVisibility.helperCopy)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WanderTheme.textMuted.color)
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

            WanderPrimaryButton(
                title: isSaving ? "saving..." : context.saveTitle,
                systemImage: "checkmark",
                isDisabled: isSaving
            ) {
                save()
            }
        }
    }

    private var candidateCard: some View {
        HStack(spacing: WanderTheme.spacing3) {
            CategoryThumb(category: context.candidate.category)

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
                Text("\(selectedStatus.displayTitle) · \(selectedVisibility.displayTitle)")
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
        context.candidate.previewSubtitle(includeDistance: false)
    }

    private func prepareDetails() {
        let allowedKeys = Set(questionBlocks.map(\.key))
        var nextAnswers = selectedAnswers.filter { allowedKeys.contains($0.key) }

        for block in questionBlocks where nextAnswers[block.key] == nil {
            nextAnswers[block.key] = Set(block.defaultValues)
        }

        selectedAnswers = nextAnswers
        errorMessage = nil
        step = .details
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

    private func attributeDrafts() -> [PlaceAttributeDraft] {
        questionBlocks.compactMap { block in
            let values = orderedSelections(for: block)
            guard !values.isEmpty else { return nil }

            switch block.kind {
            case .singleChoice:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValue: values[0])
            case .multiTag:
                return PlaceAttributeDraft(questionKey: block.key, valueType: block.valueType, stringValues: values)
            }
        }
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

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let submission = MapPlaceSaveSubmission(
            context: context,
            status: selectedStatus,
            visibility: selectedVisibility,
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
    let currentUserID: String
    let action: PlaceSheetAction
    @Binding var isExpanded: Bool
    let onAction: () -> Void
    @Environment(\.openURL) private var openURL

    init(
        place: PlaceSheetPlace,
        saves: [PlaceSaveSummary],
        currentUserID: String,
        action: PlaceSheetAction,
        isExpanded: Binding<Bool>,
        onAction: @escaping () -> Void
    ) {
        self.place = place
        self.saves = saves
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
                CategoryThumb(category: place.category)

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

            if !savers.isEmpty {
                SocialProofRow(savers: savers, currentUserID: currentUserID, visibility: place.visibility)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            expandedHeader
            if !savers.isEmpty {
                SocialProofRow(savers: savers, currentUserID: currentUserID, visibility: place.visibility)
            }
            externalActions

            if !placeFacts.isEmpty {
                factSection(title: "place", facts: placeFacts)
            }

            if let ownSave {
                VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                    sectionTitle("MY NOTES")
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
            CategoryThumb(category: place.category)
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
        } else {
            Text("not saved yet")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.terracotta.color)
                .padding(.horizontal, WanderTheme.spacing2)
                .padding(.vertical, WanderTheme.spacing1)
                .background(WanderTheme.terracottaTint.color)
                .clipShape(Capsule())
        }
    }

    private var externalActions: some View {
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
        let category = trimmed(place.category)
        return category == "place" ? nil : category
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
            facts.append(PlaceFact(title: categoryDisplay, systemImage: WanderPlaceCategory.symbolName(for: place.category)))
        }
        return facts
    }

    private var externalActionItems: [PlaceExternalAction] {
        var actions = PlaceExternalLinks.visibleBusinessActions(
            websiteURLString: place.websiteURLString,
            phoneNumber: place.phoneNumber,
            actionLinksJSON: place.actionLinksJSON
        )
        if let latitude = place.latitude,
           let longitude = place.longitude,
           let directionsAction = PlaceExternalLinks.directionsAction(placeName: place.name, latitude: latitude, longitude: longitude) {
            actions.append(directionsAction)
        }
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
                WanderAvatar(initials: owner.initials, size: 34, color: avatarColor)
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
                if owner.id == currentUserID {
                    PlaceVisibilityIconPill(visibility: userPlace.visibility, size: 30)
                }
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

        facts.append(contentsOf: summary.attributes.flatMap(attributeFacts(for:)))
        return facts
    }

    private var avatarColor: Color {
        if owner.id == currentUserID { return WanderTheme.terracotta.color }
        return owner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }

    private func attributeFacts(for attribute: LocalPlaceAttribute) -> [PlaceFact] {
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
                WanderAvatar(initials: profile.initials, size: 26, color: color(for: profile))
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
