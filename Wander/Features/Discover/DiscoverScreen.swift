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
    @State private var placesQuery = ""
    @State private var memberQuery = ""
    @State private var placeResults = DiscoverResults(places: [], profiles: [])
    @State private var memberResults: [ProfileShell] = []
    @State private var selectedProfile: SelectedProfile?
    @State private var selectedPlace: SelectedDiscoverPlace?
    @State private var placeSaveFlow: MapPlaceSaveContext?
    @State private var savedMessage: String?
    @State private var selectedOwnerCandidateID: String?
    @State private var lastHandledAuthState: Bool?
    @State private var lastHandledVisiblePlaceSignature: [DiscoverVisiblePlaceSignature]?
    @FocusState private var searchFieldFocused: Bool
    @Binding private var requestedSection: DiscoverSection?

    init(requestedSection: Binding<DiscoverSection?> = .constant(nil)) {
        _requestedSection = requestedSection
    }

    private let tickerSuggestions = [
        "Joe's favorite coffee shops in LA",
        "Maya's date night spots",
        "quiet work cafes with wifi",
        "friends' sunset hikes"
    ]

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
        !placesQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            profile.handle.lowercased().contains(ownerQuery)
                || profile.displayName.lowercased().contains(ownerQuery)
        }
        return candidates.count > 1 ? candidates : []
    }

    private var selectedOwnerCandidate: ProfileShell? {
        guard let selectedOwnerCandidateID else { return nil }
        return friendProfiles.first { $0.id == selectedOwnerCandidateID }
    }

    private func resultExplanation(groupCount count: Int, selectedOwner: ProfileShell?) -> String {
        if let selectedOwner {
            return "\(count) \(count == 1 ? "place" : "places") filtered from \(selectedOwner.displayName)"
        }
        if let owner = store.lastDiscoverFilters.ownerQuery,
           !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(count) \(count == 1 ? "place" : "places") filtered from \(owner.capitalized)"
        }
        return "\(count) \(count == 1 ? "place" : "places") from people you follow"
    }

    private var placeResultTitle: String {
        let trimmed = placesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "places" : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
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
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .scrollDismissesKeyboard(.interactively)
            .wanderScreen()
            .task {
                applyRequestedSection()
            }
            .task(id: auth.isSignedIn) {
                let requestedAuthState = auth.isSignedIn
                let previousAuthState = lastHandledAuthState
                lastHandledAuthState = requestedAuthState
                await refreshRemotePlacesIfNeeded()
                guard !Task.isCancelled,
                      auth.isSignedIn == requestedAuthState
                else {
                    return
                }
                lastHandledVisiblePlaceSignature = visiblePlaceSignature
                guard let previousAuthState,
                      previousAuthState != requestedAuthState
                else {
                    return
                }
                await refreshPlaces(query: placesQuery)
                guard !Task.isCancelled else { return }
                await refreshMembers(query: memberQuery)
            }
            .task(id: placesQuery) {
                selectedOwnerCandidateID = nil
                await refreshPlaces(query: placesQuery, debounce: true)
            }
            .task(id: memberQuery) {
                await refreshMembers(query: memberQuery, debounce: true)
            }
            .onChange(of: requestedSection) { _, _ in
                applyRequestedSection()
            }
            .task(id: visiblePlaceSignature) {
                let signature = visiblePlaceSignature
                guard let previousSignature = lastHandledVisiblePlaceSignature else {
                    lastHandledVisiblePlaceSignature = signature
                    return
                }
                guard previousSignature != signature else { return }
                lastHandledVisiblePlaceSignature = signature
                await refreshPlaces(query: placesQuery)
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
            .sheet(item: $placeSaveFlow) { context in
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
        }
    }

    private func applyRequestedSection() {
        guard let requestedSection else { return }
        selectedMode = requestedSection == .members ? .members : .places
        self.requestedSection = nil
        searchFieldFocused = false
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
            accessibilityLabel: "Search places"
        )
        .focused($searchFieldFocused)
    }

    private var membersSearchField: some View {
        DiscoverSearchField(
            text: $memberQuery,
            placeholders: ["Search rec.me members"],
            isTicker: false,
            accessibilityLabel: "Search rec.me members"
        )
        .focused($searchFieldFocused)
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
                EmptyPanel(title: "No matching places yet", action: "try another person, place type, or area")
            } else {
                ForEach(groups) { group in
                    let primary = group.primary
                    DiscoverPlaceResultCard(
                        group: group,
                        isSavedByCurrentUser: primary.owner.id == store.currentUser.id
                            || !group.aliases.isDisjoint(with: savedAliases),
                        matchedOwnerName: selectedOwner?.displayName ?? primary.owner.displayName,
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

    private var latestActivitySection: some View {
        let activity = latestActivityPlaces
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                SectionTitle("Latest Activity")
                Spacer()
                Text("Network")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if activity.isEmpty {
                EmptyPanel(title: "No activity yet", action: "follow more people to fill this in")
            } else {
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
        }

        friendsSection
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

    private var friendsSection: some View {
        let friends = friendProfiles
        let recommendationCounts = store.visiblePlaceCountsByOwnerID()
        return LazyVStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack {
                SectionTitle("Friends")
                Spacer()
                Text("\(friends.count)")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }

            if friends.isEmpty {
                EmptyPanel(title: "No friends yet", action: "search members to follow people")
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
            return "Visit saved." + suffix
        case .sharedVisit:
            return "Shared visit saved." + suffix
        case .editVisit:
            return "Visit updated." + suffix
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
            savedMessage = "Visit deleted."
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

    private func refreshPlaces(query: String, debounce: Bool = false) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            placeResults = DiscoverResults(places: [], profiles: [])
            selectedOwnerCandidateID = nil
            return
        }

        guard await waitForSearchDebounceIfNeeded(debounce) else { return }
        let results = await store.discover(query: query, scope: .everyone, backend: backend)
        guard !Task.isCancelled, query == placesQuery else { return }
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

    private func refreshRemotePlacesIfNeeded() async {
        guard auth.isSignedIn else { return }
        await store.refreshRemoteSocialSurfaces(backend: backend)
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

private enum DiscoverMode: String, CaseIterable, Identifiable {
    case places
    case members

    var id: String { rawValue }

    var title: String {
        switch self {
        case .places: "Places"
        case .members: "Members"
        }
    }

    var systemImage: String {
        switch self {
        case .places: "mappin.and.ellipse"
        case .members: "person.2"
        }
    }
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

private struct DiscoverSearchField: View {
    @Binding var text: String
    let placeholders: [String]
    let isTicker: Bool
    let accessibilityLabel: String
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
            }

            if !text.isEmpty {
                Button {
                    text = ""
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
    let matchedOwnerName: String
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

                            if let score = group.recommendedScore {
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
                                .lineLimit(1)
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
            .accessibilityLabel(isSavedByCurrentUser ? "Add visit" : "Save place")
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
        guard let note = visiblePlace.userPlace.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty
        else {
            return nil
        }
        return "\(matchedOwnerName): \(note)"
    }

    private var matchLine: String {
        [
            matchedOwnerName,
            visiblePlace.effectiveCategoryDisplay.compactTitle,
            visiblePlace.userPlace.status.displayTitle,
            visiblePlace.place.locality
        ]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
            .joined(separator: " · ")
    }

    private var displayOwner: LocalProfile {
        group.places.first { visiblePlace in
            visiblePlace.owner.displayName == matchedOwnerName
                || visiblePlace.owner.handle == matchedOwnerName
        }?.owner ?? visiblePlace.owner
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
