import SwiftUI

enum DiscoverSection: String, Equatable {
    case places
    case members
}

struct DiscoverScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var selectedMode: DiscoverMode = .places
    @State private var placesQuery: String
    @State private var submittedPlacesQuery: String?
    @State private var isPlaceSearchPresented: Bool
    @State private var isPlaceSearchLoading = false
    @State private var placeSearchTask: Task<Void, Never>?
    @State private var activePlaceSearchSubmissionID: UUID?
    @State private var didTrackPlaceSearchOpen = false
    @State private var memberQuery = ""
    @State private var placeResults = DiscoverResults(places: [], profiles: [])
    @State private var memberResults: [ProfileShell] = []
    @State private var selectedProfile: SelectedProfile?
    @State private var selectedPlace: SelectedDiscoverPlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?
    @State private var savedMessage: String?
    @State private var selectedOwnerCandidateID: String?
    @State private var activityLoadState: DiscoverActivityLoadState = .loading
    @State private var followInFlightProfileIDs: Set<String> = []
    @State private var followFailedProfileIDs: Set<String> = []
    @State private var lastHandledAuthState: Bool?
    @State private var lastHandledVisiblePlaceSignature: [DiscoverVisiblePlaceSignature]?
    @FocusState private var searchFieldFocused: Bool
    @Binding private var requestedSection: DiscoverSection?
    private let onClose: (() -> Void)?

    init(
        requestedSection: Binding<DiscoverSection?> = .constant(nil),
        startsInPlaceSearch: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        let initialQuery = Self.resolvedInitialPlaceSearchQuery()
        _requestedSection = requestedSection
        _placesQuery = State(initialValue: initialQuery)
        _isPlaceSearchPresented = State(initialValue: startsInPlaceSearch || !initialQuery.isEmpty)
        self.onClose = onClose
    }

    private let placeSearchExamples = [
        DiscoverSearchExample(
            analyticsID: "owner_favorite_coffee",
            query: "Ryan's favorite coffee spots",
            detail: "Ryan · favorites · coffee",
            systemImage: "mug.fill",
            tint: WanderTheme.categorySun.color
        ),
        DiscoverSearchExample(
            analyticsID: "quiet_work_cafe",
            query: "quiet cafes for getting work done",
            detail: "coffee · quiet · work",
            systemImage: "laptopcomputer",
            tint: WanderTheme.pinSocial.color
        ),
        DiscoverSearchExample(
            analyticsID: "friends_sunset_hikes",
            query: "friends' sunset hikes",
            detail: "friends · outdoors · sunset",
            systemImage: "sun.max.fill",
            tint: WanderTheme.pinSocial.color
        ),
        DiscoverSearchExample(
            analyticsID: "date_night_neighborhood",
            query: "date-night spots in Silver Lake",
            detail: "date · Silver Lake",
            systemImage: "heart.fill",
            tint: WanderTheme.terracotta.color
        )
    ]

    private var tickerSuggestions: [String] {
        placeSearchExamples.map(\.query)
    }

    private var profileResults: [ProfileShell] {
        memberResults.map(latestProfileShell)
    }

    private var friendProfiles: [ProfileShell] {
        store.following(of: store.currentUser.id)
            .map(store.shell(for:))
    }

    private var visiblePlaceSignature: [DiscoverVisiblePlaceSignature] {
        store.visiblePlaces().map(DiscoverVisiblePlaceSignature.init)
    }

    private var placeGroups: [VisiblePlaceGroup] {
        VisiblePlaceGrouping.groups(from: filteredPlaceResults, currentUserID: store.currentUser.id)
    }

    private var currentUserSavedPlaceAliases: Set<String> {
        Set(
            VisiblePlaceGrouping.groups(
                from: store.currentUserVisiblePlaces,
                currentUserID: store.currentUser.id
            )
            .flatMap(\.aliases)
        )
    }

    private var filteredPlaceResults: [VisiblePlace] {
        guard let selectedOwnerCandidateID else {
            return placeResults.places
        }
        return placeResults.places.filter { $0.owner.id == selectedOwnerCandidateID }
    }

    private var isPlacesSearchActive: Bool {
        submittedPlacesQuery != nil
    }

    private var isMemberSearchActive: Bool {
        !memberQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var latestActivityPlaces: [VisiblePlace] {
        DiscoverLatestActivityPresentation.places(
            from: store.visiblePlaces(filters: PlaceFilters(ownerScopes: ["following"]))
                .filter { $0.owner.id != store.currentUser.id }
                .filter { !store.isMuted(userID: $0.owner.id) }
        )
    }

    private var ambiguousOwnerCandidates: [ProfileShell] {
        guard isPlacesSearchActive,
              selectedOwnerCandidateID == nil,
              let ownerQuery = store.lastDiscoverFilters.ownerQuery?
                .lowercased()
                .replacingOccurrences(of: "@", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !ownerQuery.isEmpty
        else {
            return []
        }

        let candidates = friendProfiles.filter { profile in
            profile.handle.lowercased() == ownerQuery
                || profile.displayName.lowercased() == ownerQuery
        }
        return candidates.count > 1 ? candidates : []
    }

    private var selectedOwnerCandidate: ProfileShell? {
        guard let selectedOwnerCandidateID else { return nil }
        return friendProfiles.first { $0.id == selectedOwnerCandidateID }
    }

    private func resultExplanation(groupCount count: Int, selectedOwner: ProfileShell?) -> String {
        if placeResults.filters.opinion == .favorite,
           let owner = placeResults.filters.ownerQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !owner.isEmpty {
            return "Places \(owner.capitalized) saved and rated highly"
        }
        if let selectedOwner {
            return "\(count) \(count == 1 ? "place" : "places") filtered from \(selectedOwner.displayName)"
        }
        if let owner = store.lastDiscoverFilters.ownerQuery,
           !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(count) \(count == 1 ? "place" : "places") filtered from \(owner.capitalized)"
        }
        return "\(count) \(count == 1 ? "place" : "places") from people you follow"
    }

    private func matchEvidence(for group: VisiblePlaceGroup) -> DiscoverMatchEvidence {
        if let evidence = group.places
            .compactMap({ placeResults.evidenceByUserPlaceID[$0.userPlace.id] })
            .first {
            return evidence
        }

        let primary = group.primary
        return DiscoverMatchEvidence(
            userPlaceID: primary.userPlace.id,
            ownerID: primary.owner.id,
            ownerName: primary.owner.displayName,
            note: primary.userPlace.note,
            ratingScore: primary.userPlace.ratingScore,
            items: [
                DiscoverEvidenceItem(
                    kind: .owner,
                    displayValue: primary.owner.displayName,
                    sourceOwnerID: primary.owner.id
                ),
                DiscoverEvidenceItem(
                    kind: .category,
                    displayValue: primary.effectiveCategoryDisplay.compactTitle,
                    sourceOwnerID: primary.owner.id
                )
            ]
        )
    }

    private var placeResultTitle: String {
        if placeResults.filters.opinion == .favorite,
           let owner = placeResults.filters.ownerQuery?.trimmingCharacters(in: .whitespacesAndNewlines),
           !owner.isEmpty {
            let category = placeResults.filters.categories
                .map(WanderPlaceCategory.broadCategory)
                .sorted()
                .first?
                .lowercased() ?? "place"
            return "\(owner.capitalized)'s \(category) favorites"
        }
        let trimmed = placesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "places" : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    if selectedMode == .places, isPlaceSearchPresented {
                        activePlaceSearchHeader
                            .id("discover-place-search-top")
                        activePlaceSearchContent
                    } else {
                        modeTabs

                        switch selectedMode {
                        case .places:
                            placesSearchField
                            placesContent
                        case .members:
                            membersSearchField
                            membersContent
                        }
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .scrollDismissesKeyboard(.interactively)
            .wanderScreen()
            .modifier(
                DiscoverScrollToTopModifier(
                    isActive: isPlaceSearchPresented,
                    trigger: "\(submittedPlacesQuery ?? "draft")|\(isPlaceSearchLoading)"
                )
            )
            .task {
                applyRequestedSection()
                if isPlaceSearchPresented, !didTrackPlaceSearchOpen {
                    didTrackPlaceSearchOpen = true
                    store.trackDiscoverSearchEvent(
                        WanderAnalyticsEvents.discoverSearchOpened,
                        properties: ["entry_surface": onClose == nil ? "discover" : "feed"]
                    )
                }
                if isPlaceSearchPresented,
                   !ProcessInfo.processInfo.arguments.contains("-WanderDisableSearchAutofocus") {
                    await Task.yield()
                    searchFieldFocused = true
                }
                if !placesQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    submitPlaceSearch()
                }
                activityLoadState = .loading
                await refreshDiscoverDefaultContent()
                lastHandledAuthState = auth.isSignedIn
                lastHandledVisiblePlaceSignature = visiblePlaceSignature
            }
            .task(id: auth.isSignedIn) {
                let requestedAuthState = auth.isSignedIn
                let previousAuthState = lastHandledAuthState
                lastHandledAuthState = requestedAuthState
                guard !Task.isCancelled,
                      auth.isSignedIn == requestedAuthState
                else {
                    return
                }
                guard let previousAuthState,
                      previousAuthState != requestedAuthState
                else {
                    return
                }
                activityLoadState = .loading
                await refreshDiscoverDefaultContent(forceRecommendations: true)
                guard !Task.isCancelled,
                      auth.isSignedIn == requestedAuthState
                else {
                    return
                }
                if submittedPlacesQuery != nil {
                    await refreshPlaces(query: placesQuery)
                }
                guard !Task.isCancelled else { return }
                await refreshMembers(query: memberQuery)
            }
            .task(id: memberQuery) {
                await refreshMembers(query: memberQuery, debounce: true)
            }
            .onChange(of: placesQuery) { _, newValue in
                guard let submittedPlacesQuery,
                      normalizedSearchQuery(newValue) != normalizedSearchQuery(submittedPlacesQuery)
                else { return }
                cancelPlaceSearchWork()
                self.submittedPlacesQuery = nil
                selectedOwnerCandidateID = nil
                placeResults = DiscoverResults(places: [], profiles: [])
            }
            .onChange(of: requestedSection) { _, _ in
                applyRequestedSection()
            }
            .onChange(of: searchFieldFocused) { _, isFocused in
                if isFocused, selectedMode == .places, !isPlaceSearchPresented {
                    activatePlaceSearch()
                }
            }
            .task(id: visiblePlaceSignature) {
                let signature = visiblePlaceSignature
                guard let previousSignature = lastHandledVisiblePlaceSignature else {
                    lastHandledVisiblePlaceSignature = signature
                    return
                }
                guard previousSignature != signature else { return }
                lastHandledVisiblePlaceSignature = signature
                if submittedPlacesQuery != nil {
                    await refreshPlaces(query: placesQuery)
                }
                guard !Task.isCancelled else { return }
                await refreshMembers(query: memberQuery)
            }
            .navigationDestination(isPresented: selectedPlaceDestinationBinding) {
                selectedPlaceDestination
            }
            .fullScreenCover(item: $selectedProfile) { profile in
                ProfileDetailView(profileID: profile.id) { blockedProfileID in
                    handleMemberBlocked(profileID: blockedProfileID)
                }
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $placeSaveFlow, onDismiss: {
                store.saveFlowDidDismiss(.saveSheet)
            }) { context in
                MapPlaceSaveFlowSheet(context: context) { submission in
                    await saveDiscoverFlowSubmission(submission)
                } onRemove: { context in
                    await removeDiscoverSave(context)
                }
            }
            .alert("Saved to your map", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("OK", role: .cancel) { savedMessage = nil }
            } message: {
                Text(savedMessage ?? "")
            }
            .onDisappear(perform: cancelPlaceSearchWork)
        }
    }

    private func applyRequestedSection() {
        guard let requestedSection else { return }
        selectedMode = requestedSection == .members ? .members : .places
        self.requestedSection = nil
        if requestedSection == .members {
            exitPlaceSearch()
        }
        searchFieldFocused = false
    }

    private func activatePlaceSearch() {
        guard !isPlaceSearchPresented else { return }
        isPlaceSearchPresented = true
        if !didTrackPlaceSearchOpen {
            didTrackPlaceSearchOpen = true
            store.trackDiscoverSearchEvent(
                WanderAnalyticsEvents.discoverSearchOpened,
                properties: ["entry_surface": "discover"]
            )
        }
        Task { @MainActor in
            await Task.yield()
            searchFieldFocused = true
        }
    }

    private func exitPlaceSearch() {
        let exitState: String
        if isPlaceSearchLoading {
            exitState = "loading"
        } else if submittedPlacesQuery != nil {
            exitState = "results"
        } else if placesQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exitState = "empty"
        } else {
            exitState = "draft"
        }
        if isPlaceSearchPresented {
            store.trackDiscoverSearchEvent(
                WanderAnalyticsEvents.discoverSearchExited,
                properties: ["state": exitState, "cancelled": isPlaceSearchLoading ? "true" : "false"]
            )
        }
        didTrackPlaceSearchOpen = false
        cancelPlaceSearchWork()
        if let onClose {
            searchFieldFocused = false
            onClose()
            return
        }
        isPlaceSearchPresented = false
        isPlaceSearchLoading = false
        submittedPlacesQuery = nil
        selectedOwnerCandidateID = nil
        placesQuery = ""
        placeResults = DiscoverResults(places: [], profiles: [])
        searchFieldFocused = false
    }

    private func clearPlaceSearch() {
        cancelPlaceSearchWork()
        placesQuery = ""
        submittedPlacesQuery = nil
        selectedOwnerCandidateID = nil
        placeResults = DiscoverResults(places: [], profiles: [])
        isPlaceSearchLoading = false
        searchFieldFocused = true
    }

    private func submitPlaceSearch() {
        submitPlaceSearch(source: "typed")
    }

    private func submitPlaceSearch(source: String) {
        let query = placesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        cancelPlaceSearchWork()
        let submissionID = UUID()
        activePlaceSearchSubmissionID = submissionID
        placesQuery = query
        submittedPlacesQuery = query
        selectedOwnerCandidateID = nil
        isPlaceSearchLoading = true
        searchFieldFocused = false
        store.trackDiscoverSearchEvent(
            WanderAnalyticsEvents.discoverSearchSubmitted,
            properties: [
                "query_length": discoverQueryLengthBucket(query.count),
                "source": source,
                "schema_version": "2"
            ]
        )

        placeSearchTask = Task { @MainActor in
            let results = await store.discover(query: query, scope: .everyone, backend: backend)
            guard !Task.isCancelled,
                  isPlaceSearchPresented,
                  activePlaceSearchSubmissionID == submissionID,
                  submittedPlacesQuery == query,
                  normalizedSearchQuery(placesQuery) == normalizedSearchQuery(query)
            else { return }
            placeResults = results
            isPlaceSearchLoading = false
            placeSearchTask = nil
            store.trackDiscoverSearchEvent(
                WanderAnalyticsEvents.discoverSearchResults,
                properties: [
                    "result_count": discoverResultCountBucket(results.places.count),
                    "exact_zero": results.places.isEmpty ? "true" : "false",
                    "parse_source": results.parseSource.rawValue
                ]
            )
        }
    }

    private func discoverQueryLengthBucket(_ count: Int) -> String {
        switch count {
        case 0...20: "0_20"
        case 21...60: "21_60"
        case 61...120: "61_120"
        default: "121_160"
        }
    }

    private func discoverResultCountBucket(_ count: Int) -> String {
        switch count {
        case 0: "0"
        case 1: "1"
        case 2...5: "2_5"
        case 6...10: "6_10"
        default: "11_plus"
        }
    }

    private func cancelPlaceSearchWork() {
        placeSearchTask?.cancel()
        placeSearchTask = nil
        activePlaceSearchSubmissionID = nil
        isPlaceSearchLoading = false
    }

    private func normalizedSearchQuery(_ query: String) -> String {
        query
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolvedInitialPlaceSearchQuery(
        from arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String {
        guard let flagIndex = arguments.firstIndex(of: "-WanderDiscoverSearchQuery") else {
            return ""
        }
        let valueIndex = arguments.index(after: flagIndex)
        guard arguments.indices.contains(valueIndex) else { return "" }
        return arguments[valueIndex]
    }

    private var selectedPlaceDestinationBinding: Binding<Bool> {
        Binding(
            get: {
                selectedPlace != nil
            },
            set: { isPresented in
                if !isPresented {
                    selectedPlace = nil
                }
            }
        )
    }

    @ViewBuilder
    private var selectedPlaceDestination: some View {
        if let selection = selectedPlace {
            let visiblePlace = selection.visiblePlace
            PlaceProfileFullScreen(
                place: PlaceSheetPlace(visiblePlace: visiblePlace),
                saves: saveSummaries(for: visiblePlace),
                tasteSaves: tasteSummaries,
                currentUserID: store.currentUser.id,
                action: PlaceSheetAction.topLevelAction(currentUserSave: currentUserSave(matching: visiblePlace)),
                onBack: {
                    selectedPlace = nil
                },
                onAction: {
                    if isSavedByCurrentUser(visiblePlace) {
                        beginAddVisitDiscoverPlace(visiblePlace)
                    } else {
                        beginSaveDiscoverPlace(visiblePlace)
                    }
                }
            )
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 0) {
            ForEach(DiscoverMode.allCases) { mode in
                Button {
                    selectedMode = mode
                    searchFieldFocused = false
                } label: {
                    VStack(spacing: WanderTheme.spacing2) {
                        HStack(spacing: WanderTheme.spacing2) {
                            Image(systemName: mode.systemImage)
                                .font(.system(size: 16, weight: .black))
                            Text(mode.title)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(selectedMode == mode ? WanderTheme.textInk.color : WanderTheme.textMuted.color)
                        .frame(maxWidth: .infinity, minHeight: 42)

                        Rectangle()
                            .fill(selectedMode == mode ? WanderTheme.textInk.color : Color.clear)
                            .frame(height: 3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }
        }
        .padding(.top, WanderTheme.spacing1)
    }

    private var placesSearchField: some View {
        DiscoverSearchField(
            text: $placesQuery,
            placeholders: tickerSuggestions,
            isTicker: true,
            accessibilityLabel: "Search places",
            onFocus: activatePlaceSearch,
            onSubmit: submitPlaceSearch,
            onClear: clearPlaceSearch
        )
        .focused($searchFieldFocused)
    }

    private var membersSearchField: some View {
        DiscoverSearchField(
            text: $memberQuery,
            placeholders: ["Search name or @handle"],
            isTicker: false,
            accessibilityLabel: "Search people",
            onFocus: {},
            onSubmit: {},
            onClear: {}
        )
        .focused($searchFieldFocused)
    }

    private var activePlaceSearchHeader: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Button(action: exitPlaceSearch) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(WanderTheme.terracottaDark.color)
                    .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
            }
            .accessibilityLabel("Back to Discover")

            DiscoverSearchField(
                text: $placesQuery,
                placeholders: ["Ask about a place…"],
                isTicker: false,
                accessibilityLabel: "Ask about a place",
                onFocus: {},
                onSubmit: submitPlaceSearch,
                onClear: clearPlaceSearch
            )
            .focused($searchFieldFocused)
        }
    }

    @ViewBuilder
    private var activePlaceSearchContent: some View {
        if isPlaceSearchLoading {
            DiscoverLoadingPanel(label: "Understanding your search")
        } else if submittedPlacesQuery != nil {
            placeSearchInterpretation
            placeResultsSection
        } else {
            placeSearchTeachingState
        }
    }

    private var placeSearchTeachingState: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
            VStack(spacing: WanderTheme.spacing2) {
                ZStack {
                    RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                        .fill(WanderTheme.surfaceBone.color)
                        .frame(width: 92, height: 78)
                        .rotationEffect(.degrees(-4))
                    Image(systemName: "mappin.circle")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(WanderTheme.terracotta.color)
                }
                .accessibilityHidden(true)

                Text("Ask for a place the way you'd ask a friend")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("People, neighborhoods, moods, and moments can all go in one sentence.")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, WanderTheme.spacing2)

            Text("TRY ONE")
                .font(.system(size: 12, weight: .black))
                .tracking(2)
                .foregroundStyle(WanderTheme.textMuted.color)

            ForEach(placeSearchExamples) { example in
                Button {
                    placesQuery = example.query
                    store.trackDiscoverSearchEvent(
                        WanderAnalyticsEvents.discoverSearchExampleSelected,
                        properties: ["example_id": example.analyticsID]
                    )
                    submitPlaceSearch(source: "example")
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        Image(systemName: example.systemImage)
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(example.tint)
                            .frame(width: 48, height: 48)
                            .background(example.tint.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(example.query)
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                                .multilineTextAlignment(.leading)
                            Text(example.detail)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: WanderTheme.spacing2)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WanderTheme.terracotta.color)
                    }
                    .padding(WanderTheme.spacing3)
                    .frame(maxWidth: .infinity, minHeight: 76)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                    .overlay {
                        RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                            .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(example.query)
                .accessibilityHint("Example search: \(example.detail)")
            }
        }
    }

    @ViewBuilder
    private var placeSearchInterpretation: some View {
        let filters = placeResults.filters
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text("Understood as")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            if filters.chips.isEmpty {
                Text("places matching your words")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(filters.chips) { chip in
                            Text(chip.title)
                                .font(.system(size: 12, weight: .black))
                                .padding(.horizontal, WanderTheme.spacing3)
                                .frame(minHeight: 32)
                                .background(WanderTheme.terracottaTint.color)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if !filters.resolvedUnsupportedConcepts.isEmpty {
                let concepts = filters.resolvedUnsupportedConcepts
                    .map(\.displayTitle)
                    .sorted()
                    .joined(separator: ", ")
                Text("We can't reliably filter by \(concepts) yet, so those words weren't applied.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.stateWarning.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if placeResults.parseSource == .deterministicFallback {
                Text("Using basic matching because smart search is temporarily unavailable.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var placesContent: some View {
        let candidates = ambiguousOwnerCandidates
        if !candidates.isEmpty {
            OwnerDisambiguationSection(
                candidates: candidates,
                recommendationCounts: store.visiblePlaceCountsByOwnerID()
            ) { profile in
                selectedOwnerCandidateID = profile.id
            }
            latestActivitySection
        } else if isPlacesSearchActive {
            placeResultsSection
        } else {
            latestActivitySection
        }
    }

    private var placeResultsSection: some View {
        let groups = placeGroups
        let selectedOwner = selectedOwnerCandidate
        let savedAliases = currentUserSavedPlaceAliases
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(placeResultTitle)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(resultExplanation(groupCount: groups.count, selectedOwner: selectedOwner))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if groups.isEmpty {
                VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                    EmptyPanel(
                        title: "No exact matches yet",
                        action: "Nothing was broadened automatically. Remove one detail or try the explicit option below."
                    )

                    if let relaxedQuery = favoriteRelaxationQuery {
                        WanderPrimaryButton(
                            title: "Search visited instead",
                            systemImage: "arrow.right"
                        ) {
                            placesQuery = relaxedQuery
                            submitPlaceSearch(source: "relaxation")
                        }
                        .accessibilityHint("Submits \(relaxedQuery)")
                    }
                }
            } else {
                ForEach(groups) { group in
                    let primary = group.primary
                    DiscoverPlaceResultCard(
                        group: group,
                        isSavedByCurrentUser: primary.owner.id == store.currentUser.id
                            || !group.aliases.isDisjoint(with: savedAliases),
                        evidence: matchEvidence(for: group),
                        currentUserID: store.currentUser.id
                    ) {
                        selectedPlace = SelectedDiscoverPlace(visiblePlace: primary)
                    } save: {
                        beginSaveDiscoverPlace(primary)
                    } edit: {
                        beginAddVisitDiscoverPlace(primary)
                    }
                }
            }
        }
    }

    private var favoriteRelaxationQuery: String? {
        guard placeResults.filters.opinion == .favorite,
              let submittedPlacesQuery
        else { return nil }
        let relaxed = submittedPlacesQuery
            .replacingOccurrences(
                of: #"\b(favou?rite|best|loved|highly\s+rated)\b"#,
                with: "visited",
                options: [.regularExpression, .caseInsensitive]
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedSearchQuery(relaxed) == normalizedSearchQuery(submittedPlacesQuery)
            ? nil
            : relaxed
    }

    private var latestActivitySection: some View {
        let activity = latestActivityPlaces
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                SectionTitle("Activity")
                Spacer()
                Text("Network")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            switch activityLoadState {
            case .loading:
                DiscoverLoadingPanel(label: "Loading activity")
            case .failed:
                DiscoverActionPanel(
                    icon: "wifi.exclamationmark",
                    title: "Activity couldn't load",
                    message: "Check your connection and try again.",
                    actionTitle: "Try again"
                ) {
                    Task { await refreshActivity() }
                }
            case .loaded where latestActivityPlaces.isEmpty:
                DiscoverActivityEmptyPanel {
                    selectedMode = .members
                    searchFieldFocused = false
                }
            case .loaded:
                ForEach(activity) { visiblePlace in
                    LatestActivityRow(
                        visiblePlace: visiblePlace,
                        openPlace: { selectedPlace = SelectedDiscoverPlace(visiblePlace: visiblePlace) },
                        openProfile: { selectedProfile = SelectedProfile(id: visiblePlace.owner.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var membersContent: some View {
        if isMemberSearchActive {
            memberSearchResultsSection
        } else {
            peopleValueNote
            peopleRecommendationsSection
        }

        peopleSection
    }

    private var peopleValueNote: some View {
        HStack(alignment: .top, spacing: WanderTheme.spacing3) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 28, height: 28)

            Text("Follow people whose taste you trust. Places they choose to share can appear in Activity and on your map.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WanderTheme.textInk.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.skyTint.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
    }

    @ViewBuilder
    private var peopleRecommendationsSection: some View {
        switch store.discoverPeopleRecommendationsState {
        case .idle where !auth.isSignedIn:
            DiscoverActionPanel(
                icon: "person.crop.circle.badge.plus",
                title: "Find people you trust",
                message: "Sign in to see people worth following.",
                actionTitle: "Sign in"
            ) {
                auth.presentGate(for: .followPeople)
            }
        case .idle, .loading:
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                SectionTitle("People worth following")
                DiscoverLoadingPanel(label: "Finding people")
            }
        case .failed:
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                SectionTitle("People worth following")
                DiscoverActionPanel(
                    icon: "arrow.clockwise",
                    title: "Suggestions couldn't load",
                    message: "Search still works, or try these suggestions again.",
                    actionTitle: "Try again"
                ) {
                    Task {
                        await store.refreshDiscoverPeopleRecommendations(backend: backend, force: true)
                    }
                }
            }
        case .loaded(let recommendations) where recommendations.isEmpty:
            VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
                SectionTitle("People worth following")
                EmptyPanel(title: "No suggestions yet", action: "search a name or @handle above")
            }
        case .loaded(let recommendations):
            PeopleRecommendationShelf(
                recommendations: recommendations,
                isFollowing: { store.hasAcknowledgedFollow(to: $0) },
                isFollowInFlight: { followInFlightProfileIDs.contains($0) },
                didFollowFail: { followFailedProfileIDs.contains($0) },
                open: { selectedProfile = SelectedProfile(id: $0.profile.id) },
                follow: followRecommendation
            )
        }
    }

    private var memberSearchResultsSection: some View {
        let results = profileResults
        let recommendationCounts = store.visiblePlaceCountsByOwnerID()
        return VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SectionTitle("Member results")

            if results.isEmpty {
                EmptyPanel(title: "No members found", action: "try a handle or full first name")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: WanderTheme.spacing3) {
                        ForEach(results) { profile in
                            MemberResultTile(
                                profile: profile,
                                recCount: recommendationCounts[profile.id, default: 0]
                            ) {
                                selectedProfile = SelectedProfile(id: profile.id)
                            }
                        }
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
            }
        }
    }

    private var peopleSection: some View {
        let friends = friendProfiles
        let recommendationCounts = store.visiblePlaceCountsByOwnerID()
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                SectionTitle("People")
                Spacer()
                Text("\(friends.count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if friends.isEmpty {
                EmptyPanel(title: "No one followed yet", action: "search or follow someone above")
            } else {
                ForEach(friends) { profile in
                    FriendListRow(
                        profile: profile,
                        recCount: recommendationCounts[profile.id, default: 0]
                    ) {
                        selectedProfile = SelectedProfile(id: profile.id)
                    }
                }
            }
        }
    }

    private func beginSaveDiscoverPlace(_ visiblePlace: VisiblePlace) {
        auth.requireSignIn(for: .socialSave) {
            presentPlaceSaveFlow(MapPlaceSaveContext.addVisiblePlace(
                visiblePlace,
                defaultVisibility: store.effectiveDefaultVisibility,
                attributes: attributes(for: visiblePlace)
            ))
        }
    }

    private func beginAddVisitDiscoverPlace(_ visiblePlace: VisiblePlace) {
        guard let currentUserSave = currentUserSave(matching: visiblePlace) else {
            beginSaveDiscoverPlace(visiblePlace)
            return
        }

        presentPlaceSaveFlow(MapPlaceSaveContext.addVisitVisiblePlace(
            currentUserSave,
            attributes: store.attributes(for: currentUserSave.userPlace.id),
            latestVisit: store.visits(for: currentUserSave.userPlace.id).first
        ))
    }

    private func presentPlaceSaveFlow(_ context: MapPlaceSaveContext) {
        guard selectedPlace != nil else {
            placeSaveFlow = context
            return
        }

        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            placeSaveFlow = context
        }
    }

    @MainActor
    private func saveDiscoverFlowSubmission(_ submission: MapPlaceSaveSubmission) async -> SaveResult? {
        let visitBackend = auth.isSignedIn ? backend : nil
        switch submission.context.mode {
        case .sharedVisit:
            return nil
        case .add(let sourceType):
            if sourceType == .socialSave, !auth.isSignedIn {
                placeSaveFlow = nil
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
            let targetVisit = submission.status == .been ? store.visits(for: result.userPlaceID).first : nil
            await persistVisitPhotoAttachments(
                submission.photoAttachments,
                to: targetVisit,
                store: store,
                backend: visitBackend
            )
            await refreshPlaces(query: placesQuery)
            await refreshMembers(query: memberQuery)
            savedMessage = result.syncState == .synced ? "Saved." : "Queued locally. We'll retry sync."
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
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
            await refreshPlaces(query: placesQuery)
            await refreshMembers(query: memberQuery)
            savedMessage = scopedDiscoverMessage(for: submission.context, syncState: result.syncState)
            if !auth.isSignedIn {
                auth.presentGate(for: .syncPlace)
            }
            return result
        }
    }

    private func scopedDiscoverMessage(for context: MapPlaceSaveContext, syncState: SyncState) -> String {
        let suffix = syncState == .synced ? "" : " We'll retry sync."
        switch context.mode {
        case .add:
            return syncState == .synced ? "Saved." : "Queued locally. We'll retry sync."
        case .addVisit:
            return "Check-in saved." + suffix
        case .sharedVisit:
            return "Shared check-in saved." + suffix
        case .editVisit:
            return "Check-in updated." + suffix
        case .editWant:
            return "Want updated." + suffix
        }
    }

    @MainActor
    private func removeDiscoverSave(_ context: MapPlaceSaveContext) async -> Bool {
        switch context.mode {
        case .editVisit(_, let visit):
            guard await store.deleteVisit(visitID: visit.id, backend: auth.isSignedIn ? backend : nil) else {
                return false
            }
            await refreshPlaces(query: placesQuery)
            await refreshMembers(query: memberQuery)
            savedMessage = "Check-in deleted."
            return true
        case .editWant(let visiblePlace):
            guard await store.removeSave(userPlaceID: visiblePlace.userPlace.id, backend: auth.isSignedIn ? backend : nil) != nil else {
                return false
            }

            await refreshPlaces(query: placesQuery)
            await refreshMembers(query: memberQuery)
            selectedPlace = nil
            savedMessage = "Want removed."
            return true
        case .add, .addVisit, .sharedVisit:
            return false
        }
    }

    private func currentUserSave(matching visiblePlace: VisiblePlace) -> VisiblePlace? {
        return store.currentUserVisiblePlaces.first { currentUserPlace in
            VisiblePlaceGrouping.matches(currentUserPlace, visiblePlace)
        }
    }

    private func openProfileFromPlace(_ profileID: String) {
        selectedPlace = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            selectedProfile = SelectedProfile(id: profileID)
        }
    }

    private func attributes(for visiblePlace: VisiblePlace) -> [LocalPlaceAttribute] {
        let storeAttributes = store.attributes(for: visiblePlace.userPlace.id)
        return storeAttributes.isEmpty ? visiblePlace.attributes : storeAttributes
    }

    private func saveSummaries(for selectedPlace: VisiblePlace) -> [PlaceSaveSummary] {
        var seen = Set<String>()

        return (store.visiblePlaces() + placeResults.places)
            .filter { VisiblePlaceGrouping.matches($0, selectedPlace) }
            .filter { visiblePlace in
                guard !seen.contains(visiblePlace.userPlace.id) else { return false }
                seen.insert(visiblePlace.userPlace.id)
                return true
            }
            .map { visiblePlace in
                PlaceSaveSummary(visiblePlace: visiblePlace, attributes: attributes(for: visiblePlace))
            }
            .sorted { lhs, rhs in
                if lhs.visiblePlace.owner.id == store.currentUser.id { return true }
                if rhs.visiblePlace.owner.id == store.currentUser.id { return false }
                if lhs.visiblePlace.id == selectedPlace.id { return true }
                if rhs.visiblePlace.id == selectedPlace.id { return false }
                return lhs.visiblePlace.owner.displayName.localizedCaseInsensitiveCompare(rhs.visiblePlace.owner.displayName) == .orderedAscending
            }
    }

    private var tasteSummaries: [PlaceSaveSummary] {
        store.currentUserVisiblePlaces.map { visiblePlace in
            PlaceSaveSummary(visiblePlace: visiblePlace, attributes: store.attributes(for: visiblePlace.userPlace.id))
        }
    }

    private func isSavedByCurrentUser(_ visiblePlace: VisiblePlace) -> Bool {
        if visiblePlace.owner.id == store.currentUser.id {
            return true
        }

        return store.currentUserVisiblePlaces.contains { currentUserPlace in
            VisiblePlaceGrouping.matches(currentUserPlace, visiblePlace)
        }
    }

    private func refreshPlaces(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty,
              let submittedPlacesQuery,
              normalizedSearchQuery(submittedPlacesQuery) == normalizedSearchQuery(trimmedQuery)
        else { return }

        let results = await store.discover(query: query, scope: .everyone, backend: backend)
        guard !Task.isCancelled,
              submittedPlacesQuery == self.submittedPlacesQuery,
              normalizedSearchQuery(query) == normalizedSearchQuery(placesQuery)
        else { return }
        placeResults = results
    }

    private func refreshMembers(query: String, debounce: Bool = false) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            memberResults = []
            return
        }

        guard await waitForSearchDebounceIfNeeded(debounce) else { return }
        let results = await store.discoverMembers(query: query, backend: backend)
        guard !Task.isCancelled, query == memberQuery else { return }
        memberResults = results
    }

    private func waitForSearchDebounceIfNeeded(_ debounce: Bool) async -> Bool {
        guard debounce else { return !Task.isCancelled }
        do {
            try await Task.sleep(for: .milliseconds(225))
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private func handleMemberBlocked(profileID: String) {
        selectedProfile = nil
        memberQuery = ""
        memberResults = []
        searchFieldFocused = false
    }

    private func refreshDiscoverDefaultContent(forceRecommendations: Bool = false) async {
        let didLoadActivity = await refreshRemotePlacesIfNeeded()
        await refreshRecommendationsIfNeeded(force: forceRecommendations)
        activityLoadState = didLoadActivity ? .loaded : .failed
    }

    private func refreshActivity() async {
        activityLoadState = .loading
        activityLoadState = await refreshRemotePlacesIfNeeded() ? .loaded : .failed
    }

    private func refreshRemotePlacesIfNeeded() async -> Bool {
        guard auth.isSignedIn else { return true }
        guard backend.followRepository != nil, backend.placeRepository != nil else { return true }
        return await store.refreshRemoteSocialSurfaces(backend: backend)
    }

    private func refreshRecommendationsIfNeeded(force: Bool) async {
        guard auth.isSignedIn else { return }
        await store.refreshDiscoverPeopleRecommendations(backend: backend, force: force)
    }

    private func followRecommendation(_ recommendation: DiscoverPeopleRecommendation) {
        auth.requireSignIn(for: .followPeople) {
            let profileID = recommendation.profile.id
            guard !followInFlightProfileIDs.contains(profileID) else { return }
            followInFlightProfileIDs.insert(profileID)
            followFailedProfileIDs.remove(profileID)

            Task {
                let succeeded = await store.follow(
                    userID: profileID,
                    source: .profile,
                    backend: backend
                )
                followInFlightProfileIDs.remove(profileID)
                if succeeded {
                    followFailedProfileIDs.remove(profileID)
                } else {
                    followFailedProfileIDs.insert(profileID)
                }
            }
        }
    }

    private func latestProfileShell(for profile: ProfileShell) -> ProfileShell {
        guard let localProfile = store.profiles.first(where: { $0.id == profile.id }) else {
            return profile
        }

        return store.shell(for: localProfile)
    }

}

private struct DiscoverVisiblePlaceSignature: Equatable {
    let id: String
    let ownerID: String
    let ownerAvatarURL: String?
    let status: PlaceStatus
    let visibility: PlaceVisibility

    init(_ visiblePlace: VisiblePlace) {
        id = visiblePlace.id
        ownerID = visiblePlace.owner.id
        ownerAvatarURL = visiblePlace.owner.avatarURL
        status = visiblePlace.userPlace.status
        visibility = visiblePlace.userPlace.visibility
    }
}

private struct DiscoverSearchExample: Identifiable {
    let analyticsID: String
    let query: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { query }
}

private enum DiscoverMode: String, CaseIterable, Identifiable {
    case places
    case members

    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: "Places"
        case .members: "People"
        }
    }

    var systemImage: String {
        switch self {
        case .places: "mappin.and.ellipse"
        case .members: "person.2"
        }
    }
}

private enum DiscoverActivityLoadState: Equatable {
    case loading
    case loaded
    case failed
}

private struct SelectedProfile: Identifiable {
    let id: String
}

private struct SelectedDiscoverPlace: Identifiable {
    let visiblePlace: VisiblePlace

    var id: String {
        visiblePlace.id
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .black))
    }
}

private struct EmptyPanel: View {
    let title: String
    let action: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                Text(action)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            Spacer()
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct DiscoverLoadingPanel: View {
    let label: String

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            ProgressView()
                .tint(WanderTheme.terracotta.color)
            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WanderTheme.textMuted.color)
            Spacer()
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .accessibilityElement(children: .combine)
    }
}

private struct DiscoverActionPanel: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: WanderTheme.spacing3) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(WanderTheme.textInk.color)
                .frame(width: 48, height: 48)
                .background(WanderTheme.skyTint.color)
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(WanderTheme.textOnAction.color)
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
                .background(WanderTheme.terracotta.color)
                .clipShape(Capsule())
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct DiscoverActivityEmptyPanel: View {
    let findPeople: () -> Void

    var body: some View {
        DiscoverActionPanel(
            icon: "person.2.fill",
            title: "Your Activity starts with people",
            message: "Follow people you trust and places they choose to share can show up here.",
            actionTitle: "Find people to follow",
            action: findPeople
        )
    }
}

struct PeopleRecommendationShelf: View {
    let recommendations: [DiscoverPeopleRecommendation]
    let isFollowing: (String) -> Bool
    let isFollowInFlight: (String) -> Bool
    let didFollowFail: (String) -> Bool
    let open: (DiscoverPeopleRecommendation) -> Void
    let follow: (DiscoverPeopleRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SectionTitle("People worth following")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: WanderTheme.spacing3) {
                    ForEach(recommendations) { recommendation in
                        PeopleRecommendationCard(
                            recommendation: recommendation,
                            isFollowing: isFollowing(recommendation.id),
                            isFollowInFlight: isFollowInFlight(recommendation.id),
                            didFollowFail: didFollowFail(recommendation.id),
                            open: { open(recommendation) },
                            follow: { follow(recommendation) }
                        )
                    }
                }
                .padding(.vertical, WanderTheme.spacing1)
            }
        }
    }
}

private struct PeopleRecommendationCard: View {
    let recommendation: DiscoverPeopleRecommendation
    let isFollowing: Bool
    let isFollowInFlight: Bool
    let didFollowFail: Bool
    let open: () -> Void
    let follow: () -> Void

    private var profile: ProfileShell { recommendation.profile }

    private var bioText: String {
        guard let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty else {
            return "Follow to see the places they choose to share."
        }
        return bio
    }

    var body: some View {
        VStack(spacing: WanderTheme.spacing2) {
            Button(action: open) {
                VStack(spacing: WanderTheme.spacing2) {
                    WanderAvatar(
                        initials: String(profile.displayName.prefix(1)),
                        avatarURL: profile.avatarURL,
                        size: 52,
                        color: WanderTheme.pinSocial.color
                    )

                    Text(profile.displayName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)

                    Text("@\(profile.handle)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Text(recommendation.reason.displayText(for: profile))
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(WanderTheme.terracottaDark.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 28, alignment: .top)

            Text(bioText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32, alignment: .top)

            Spacer(minLength: 0)

            Button(action: follow) {
                Group {
                    if isFollowInFlight {
                        ProgressView()
                            .tint(WanderTheme.textOnAction.color)
                    } else {
                        Text(isFollowing ? "Following" : "Follow")
                    }
                }
                .font(.system(size: 13, weight: .black))
                .frame(maxWidth: .infinity, minHeight: WanderTheme.tapMinimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isFollowing ? WanderTheme.textInk.color : WanderTheme.textOnAction.color)
            .background(isFollowing ? WanderTheme.surfaceSand.color : WanderTheme.terracotta.color)
            .clipShape(Capsule())
            .disabled(isFollowing || isFollowInFlight)
            .accessibilityLabel(isFollowInFlight ? "Following \(profile.displayName)" : (isFollowing ? "Following \(profile.displayName)" : "Follow \(profile.displayName)"))

            if didFollowFail {
                Text("Couldn't follow. Try again.")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WanderTheme.stateError.color)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(WanderTheme.spacing3)
        .frame(width: 172)
        .frame(minHeight: 238)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay {
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        }
    }
}

private struct DiscoverScrollToTopModifier: ViewModifier {
    let isActive: Bool
    let trigger: String

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .onChange(of: trigger) { _, _ in
                    guard isActive else { return }
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo("discover-place-search-top", anchor: .top)
                    }
                }
        }
    }
}

private struct DiscoverSearchField: View {
    @Binding var text: String
    let placeholders: [String]
    let isTicker: Bool
    let accessibilityLabel: String
    let onFocus: () -> Void
    let onSubmit: () -> Void
    let onClear: () -> Void
    @State private var placeholderIndex = 0

    private var placeholder: String {
        guard !placeholders.isEmpty else { return "" }
        return placeholders[placeholderIndex % placeholders.count]
    }

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(WanderTheme.textMuted.color)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .id(placeholder)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .lineLimit(1)
                        .transition(isTicker ? .push(from: .bottom).combined(with: .opacity) : .opacity)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text)
                    .font(.system(size: 17, weight: .bold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .onTapGesture(perform: onFocus)
                    .onSubmit(onSubmit)
            }

            if !text.isEmpty {
                Button {
                    text = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WanderTheme.textFaint.color)
                        .frame(width: WanderTheme.tapMinimum, height: WanderTheme.tapMinimum)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, WanderTheme.spacing4)
        .padding(.trailing, text.isEmpty ? WanderTheme.spacing4 : WanderTheme.spacing1)
        .frame(minHeight: 58)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusMedium)
                .stroke(WanderTheme.borderHairline.color, lineWidth: 1)
        )
        .accessibilityLabel(accessibilityLabel)
        .task {
            await runPlaceholderTicker()
        }
    }

    private func runPlaceholderTicker() async {
        guard isTicker, placeholders.count > 1 else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 2_600_000_000)
            } catch {
                return
            }
            guard text.isEmpty else { continue }
            withAnimation(.easeInOut(duration: 0.24)) {
                placeholderIndex = (placeholderIndex + 1) % placeholders.count
            }
        }
    }
}

private struct DiscoverPlaceResultCard: View {
    let group: VisiblePlaceGroup
    let isSavedByCurrentUser: Bool
    let evidence: DiscoverMatchEvidence
    let currentUserID: String
    let openPlace: () -> Void
    let save: () -> Void
    let edit: () -> Void

    private var visiblePlace: VisiblePlace { group.primary }

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            Button(action: openPlace) {
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    DiscoverCategoryThumb(emoji: visiblePlace.categoryEmoji, size: 62, iconSize: 24)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        HStack(spacing: WanderTheme.spacing2) {
                            Text(visiblePlace.place.canonicalName)
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                                .lineLimit(1)

                            if let score = evidence.ratingScore {
                                Text(PlaceRating.averageDisplay(score))
                                    .font(.system(size: 12, weight: .black))
                                    .foregroundStyle(WanderTheme.textOnAction.color)
                                    .padding(.horizontal, WanderTheme.spacing2)
                                    .frame(minHeight: 24)
                                    .background(WanderTheme.textInk.color)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(subtitle)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)

                        if let noteLine {
                            Text(noteLine)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }

                        HStack(spacing: WanderTheme.spacing2) {
                            WanderAvatar(
                                initials: displayOwner.initials,
                                avatarURL: displayOwner.avatarURL,
                                size: 24,
                                color: displayOwnerColor
                            )

                            Text(matchLine)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(WanderTheme.terracotta.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: WanderTheme.spacing2)

            Button(action: isSavedByCurrentUser ? edit : save) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 48, height: 48)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel(isSavedByCurrentUser ? CheckInCopy.againAction : "Save place")
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .overlay(
            RoundedRectangle(cornerRadius: WanderTheme.radiusLarge)
                .stroke(WanderTheme.borderHairline.color.opacity(0.65), lineWidth: 1)
        )
    }

    private var subtitle: String {
        [
            visiblePlace.place.locality,
            visiblePlace.place.region,
            visiblePlace.effectiveCategoryDisplay.compactTitle
        ]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
    }

    private var noteLine: String? {
        guard let note = evidence.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else {
            return nil
        }
        return "\(evidence.ownerName): \(note)"
    }

    private var matchLine: String {
        evidence.summary
    }

    private var displayOwner: LocalProfile {
        group.places.first { $0.owner.id == evidence.ownerID }?.owner ?? visiblePlace.owner
    }

    private var displayOwnerColor: Color {
        if displayOwner.id == currentUserID { return WanderTheme.terracotta.color }
        return displayOwner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }
}

private struct LatestActivityRow: View {
    let visiblePlace: VisiblePlace
    let openPlace: () -> Void
    let openProfile: () -> Void

    var body: some View {
        HStack(spacing: WanderTheme.spacing3) {
            Button(action: openProfile) {
                WanderAvatar(
                    initials: visiblePlace.owner.initials,
                    avatarURL: visiblePlace.owner.avatarURL,
                    size: 42,
                    color: avatarColor
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(visiblePlace.owner.displayName)'s profile")

            Button(action: openPlace) {
                HStack(spacing: WanderTheme.spacing3) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text("\(visiblePlace.owner.displayName) saved \(visiblePlace.place.canonicalName)")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(1)

                    HStack(spacing: WanderTheme.spacing1) {
                        if !metadataSubtitle.isEmpty {
                            Text(metadataSubtitle)
                                .lineLimit(1)

                            Text("·")
                                .accessibilityHidden(true)
                        }

                        Text(savedTimeText)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .accessibilityElement(children: .combine)
                }

                Spacer()

                Text(visiblePlace.userPlace.status.displayTitle)
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }

    private var metadataSubtitle: String {
        [
            visiblePlace.place.locality,
            visiblePlace.place.region,
            visiblePlace.effectiveCategoryDisplay.compactTitle
        ]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
    }

    private var savedTimeText: String {
        DiscoverLatestActivityPresentation.timestampText(for: visiblePlace.userPlace.savedAt)
    }

    private var avatarColor: Color {
        visiblePlace.owner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }
}

private struct OwnerDisambiguationSection: View {
    let candidates: [ProfileShell]
    let recommendationCounts: [String: Int]
    let select: (ProfileShell) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text("Which person?")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(WanderTheme.textInk.color)
                Text("Pick who you want to search.")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            ForEach(candidates) { profile in
                Button {
                    select(profile)
                } label: {
                    HStack(spacing: WanderTheme.spacing3) {
                        WanderAvatar(
                            initials: String(profile.displayName.prefix(1)),
                            avatarURL: profile.avatarURL,
                            size: 50,
                            color: WanderTheme.pinSocial.color
                        )

                        VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                            Text(profile.displayName)
                                .font(.system(size: 17, weight: .black))
                                .foregroundStyle(WanderTheme.textInk.color)
                            Text("@\(profile.handle)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                            Text("\(recommendationCounts[profile.id, default: 0]) rec matches")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WanderTheme.textMuted.color)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(WanderTheme.textFaint.color)
                    }
                    .padding(WanderTheme.spacing3)
                    .background(WanderTheme.surfaceBone.color)
                    .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MemberResultTile: View {
    let profile: ProfileShell
    let recCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                WanderAvatar(
                    initials: String(profile.displayName.prefix(1)),
                    avatarURL: profile.avatarURL,
                    size: 46,
                    color: WanderTheme.pinSocial.color
                )
                Text(profile.displayName)
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WanderTheme.textInk.color)
                    .lineLimit(1)
                Text("@\(profile.handle)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
                Spacer()
                Text("\(recCount) rec matches")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .frame(width: 148, height: 142, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct FriendListRow: View {
    let profile: ProfileShell
    let recCount: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: WanderTheme.spacing3) {
                WanderAvatar(
                    initials: String(profile.displayName.prefix(1)),
                    avatarURL: profile.avatarURL,
                    size: 42,
                    color: WanderTheme.pinSocial.color
                )

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(profile.displayName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(profile.handle)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }

                Spacer()

                Text("\(recCount) recs")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
    }
}

private struct DiscoverCategoryThumb: View {
    let emoji: String
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        WanderCategoryEmoji(emoji: emoji, size: iconSize)
            .frame(width: size, height: size)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())
    }
}
