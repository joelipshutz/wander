import SwiftUI

struct DiscoverScreen: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var auth: AuthSessionStore
    @EnvironmentObject private var backend: WanderBackend
    @State private var query = ""
    @State private var results = DiscoverResults(places: [], profiles: [])
    @State private var contacts: [ContactMatch] = []
    @State private var selectedProfile: SelectedProfile?
    @State private var selectedPlace: SelectedDiscoverPlace?
    @State private var savedMessage: String?
    @State private var selectedScope: DiscoverPlaceScope = .everyone
    @State private var parsedChips: [DiscoverFilterChip] = []
    @FocusState private var searchFieldFocused: Bool

    private var matchedContacts: [ContactMatch] {
        contacts.filter(\.isMatchedUser)
    }

    private var contactUserIDs: Set<String> {
        Set(matchedContacts.compactMap(\.userID))
    }

    private var profileResults: [ProfileShell] {
        results.profiles.filter { !contactUserIDs.contains($0.id) }
    }

    private var followedProfiles: [ProfileShell] {
        let hiddenIDs = contactUserIDs.union(profileResults.map(\.id))
        return store.following(of: store.currentUser.id)
            .map(store.shell(for:))
            .filter { !hiddenIDs.contains($0.id) }
    }

    private var visiblePlaceSignature: String {
        store.visiblePlaces()
            .map { visiblePlace in
                [
                    visiblePlace.id,
                    visiblePlace.owner.id,
                    visiblePlace.userPlace.status.rawValue,
                    visiblePlace.userPlace.visibility.rawValue
                ].joined(separator: ":")
            }
            .joined(separator: "|")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    header
                    searchField
                    parsedFilterRow
                    peopleSection
                    resultsSection
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing8)
            }
            .scrollDismissesKeyboard(.interactively)
            .wanderScreen()
            .task {
                contacts = await store.contactMatches()
                await refreshRemotePlacesIfNeeded()
                await refresh()
            }
            .onChange(of: auth.isSignedIn) { _, _ in
                Task {
                    await refreshRemotePlacesIfNeeded()
                    await refresh()
                }
            }
            .onChange(of: query) { _, _ in
                Task { await refresh() }
            }
            .onChange(of: selectedScope) { _, _ in
                Task { await refresh() }
            }
            .onChange(of: visiblePlaceSignature) { _, _ in
                Task { await refresh() }
            }
            .sheet(item: $selectedProfile) { profile in
                ProfileDetailView(profileID: profile.id)
                    .environmentObject(store)
                    .environmentObject(auth)
                    .environmentObject(backend)
            }
            .sheet(item: $selectedPlace) { selection in
                DiscoverPlaceDetailSheet(
                    visiblePlace: selection.visiblePlace,
                    attributes: attributes(for: selection.visiblePlace),
                    isSavedByCurrentUser: isSavedByCurrentUser(selection.visiblePlace),
                    currentUserID: store.currentUser.id
                ) {
                    saveDiscoverPlace(selection.visiblePlace)
                } openProfile: {
                    openProfileFromPlace(selection.visiblePlace.owner.id)
                }
            }
            .alert("Saved to your map", isPresented: Binding(get: { savedMessage != nil }, set: { if !$0 { savedMessage = nil } })) {
                Button("OK", role: .cancel) { savedMessage = nil }
            } message: {
                Text(savedMessage ?? "")
            }
        }
    }

    private var header: some View {
        Text("discover")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineLimit(1)
    }

    private var searchField: some View {
        HStack(spacing: WanderTheme.spacing2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WanderTheme.textMuted.color)
            TextField("hikes in LA, @maya, coffee...", text: $query)
                .font(.system(size: 15, weight: .medium))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($searchFieldFocused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(WanderTheme.textFaint.color)
                }
            }
        }
        .padding(.horizontal, WanderTheme.spacing3)
        .frame(minHeight: 50)
        .background(WanderTheme.surfaceRaised.color)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WanderTheme.borderHairline.color))
    }

    @ViewBuilder
    private var parsedFilterRow: some View {
        if !parsedChips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    ForEach(parsedChips) { chip in
                        Text(chip.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WanderTheme.terracotta.color)
                            .frame(minHeight: 34)
                            .padding(.horizontal, WanderTheme.spacing3)
                            .background(WanderTheme.surfaceBone.color)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(WanderTheme.terracotta.color.opacity(0.7), lineWidth: 1))
                    }
                }
                .padding(.vertical, WanderTheme.spacing1)
            }
            .accessibilityLabel("Parsed search filters")
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SectionTitle("people")

            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                AddPersonCard {
                    query = "@"
                    searchFieldFocused = true
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: WanderTheme.spacing2) {
                        ForEach(matchedContacts) { contact in
                            ContactCard(contact: contact) {
                                if let userID = contact.userID {
                                    selectedProfile = SelectedProfile(id: userID)
                                }
                            } follow: {
                                if let userID = contact.userID {
                                    auth.requireSignIn(for: .followPeople) {
                                        Task {
                                            await store.follow(userID: userID, source: .contacts, backend: backend)
                                            await store.refreshRemoteSocialSurfaces(backend: backend)
                                            await refresh()
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(profileResults) { profile in
                            ProfileMiniCard(profile: profile) {
                                selectedProfile = SelectedProfile(id: profile.id)
                            } follow: {
                                auth.requireSignIn(for: .followPeople) {
                                    Task {
                                        await store.follow(userID: profile.id, source: .username, backend: backend)
                                        await store.refreshRemoteSocialSurfaces(backend: backend)
                                        await refresh()
                                    }
                                }
                            }
                        }

                        ForEach(followedProfiles) { profile in
                            ProfileMiniCard(profile: profile) {
                                selectedProfile = SelectedProfile(id: profile.id)
                            } follow: {
                                selectedProfile = SelectedProfile(id: profile.id)
                            }
                        }
                    }
                    .padding(.vertical, WanderTheme.spacing1)
                }
            }
        }
    }

    private var scopeToggle: some View {
        WanderSegmentedSwitch(
            options: DiscoverPlaceScope.allCases.map { scope in
                WanderSegmentOption(id: scope.rawValue, title: scope.title)
            },
            selection: Binding(
                get: { selectedScope.rawValue },
                set: { selectedScope = DiscoverPlaceScope(rawValue: $0) ?? .everyone }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Discover place source")
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            SectionTitle("places")
            scopeToggle

            if results.places.isEmpty {
                EmptyPanel(title: "No places here yet", action: selectedScope == .myPlaces ? "try friends or everyone" : "try another search")
            } else {
                ForEach(results.places) { visiblePlace in
                    DiscoverPlaceRow(
                        visiblePlace: visiblePlace,
                        isSavedByCurrentUser: isSavedByCurrentUser(visiblePlace)
                    ) {
                        selectedPlace = SelectedDiscoverPlace(visiblePlace: visiblePlace)
                    } save: {
                        saveDiscoverPlace(visiblePlace)
                    }
                }
            }
        }
    }

    private func saveDiscoverPlace(_ visiblePlace: VisiblePlace) {
        auth.requireSignIn(for: .socialSave) {
            Task {
                let result = await store.saveVisiblePlace(visiblePlace, backend: backend)
                selectedPlace = nil
                await refresh()
                savedMessage = result.syncState == .synced ? "Saved." : "Queued locally. We'll retry sync."
            }
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

    private func isSavedByCurrentUser(_ visiblePlace: VisiblePlace) -> Bool {
        if visiblePlace.owner.id == store.currentUser.id {
            return true
        }

        return store.currentUserVisiblePlaces.contains { currentUserPlace in
            currentUserPlace.place.id == visiblePlace.place.id ||
                currentUserPlace.place.canonicalName.caseInsensitiveCompare(visiblePlace.place.canonicalName) == .orderedSame
        }
    }

    private func refresh() async {
        results = await store.discover(query: query, scope: selectedScope, backend: backend)
        parsedChips = store.lastDiscoverFilters.chips
    }

    private func refreshRemotePlacesIfNeeded() async {
        guard auth.isSignedIn else { return }
        await store.refreshRemoteSocialSurfaces(backend: backend)
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

private struct AddPersonCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())

                Text("add")
                    .font(.system(size: 14, weight: .bold))
                Text("username")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)

                Spacer()

                Text("find")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WanderTheme.terracotta.color)
            }
            .frame(width: 82, height: 116, alignment: .leading)
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceSand.color)
            .foregroundStyle(WanderTheme.textInk.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a person by username")
    }
}

private struct ContactCard: View {
    let contact: ContactMatch
    let open: () -> Void
    let follow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            WanderAvatar(initials: initials, size: 36, color: WanderTheme.avatarRyan.color)
            VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                Text(contact.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                Text(contact.handle.map { "@\($0)" } ?? "on Wander")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .lineLimit(1)
            }
            Spacer()
            Button(contact.isAlreadyFollowing ? "view" : "follow") {
                contact.isAlreadyFollowing ? open() : follow()
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
        }
        .frame(width: 122, height: 116, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .onTapGesture {
            open()
        }
    }

    private var initials: String {
        contact.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

private struct ProfileMiniCard: View {
    let profile: ProfileShell
    let open: () -> Void
    let follow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            WanderAvatar(initials: String(profile.displayName.prefix(2)).uppercased(), size: 36, color: WanderTheme.pinSocial.color)
            Text(profile.displayName)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Text("@\(profile.handle) · \(profile.relationship.displayTitle)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WanderTheme.textMuted.color)
                .lineLimit(1)
            Spacer()
            Button(profile.relationship == .nonFollower ? "follow" : "view") {
                profile.relationship == .nonFollower ? follow() : open()
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
        }
        .frame(width: 122, height: 116, alignment: .leading)
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        .onTapGesture(perform: open)
    }
}

private struct DiscoverPlaceRow: View {
    let visiblePlace: VisiblePlace
    let isSavedByCurrentUser: Bool
    let openPlace: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: WanderTheme.spacing3) {
            Button(action: openPlace) {
                HStack(alignment: .center, spacing: WanderTheme.spacing3) {
                    DiscoverCategoryThumb(category: visiblePlace.place.category, size: 42, iconSize: 18)

                    VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                        Text(visiblePlace.place.canonicalName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WanderTheme.textInk.color)
                            .lineLimit(1)
                        Text("\(visiblePlace.owner.displayName) saved it · \(visiblePlace.userPlace.status.displayTitle)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(1)
                        if let note = visiblePlace.userPlace.note {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(WanderTheme.textMuted.color)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if isSavedByCurrentUser {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .black))
                    .frame(width: 38, height: 38)
                    .background(WanderTheme.surfaceSand.color)
                    .foregroundStyle(WanderTheme.terracotta.color)
                    .clipShape(Circle())
                    .accessibilityLabel("\(visiblePlace.place.canonicalName) is already on my map")
            } else {
                Button(action: save) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .black))
                        .frame(width: 38, height: 38)
                        .background(WanderTheme.terracotta.color)
                        .foregroundStyle(WanderTheme.textOnAction.color)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Save \(visiblePlace.place.canonicalName) to my map")
            }
        }
        .padding(WanderTheme.spacing3)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
    }
}

private struct DiscoverPlaceDetailSheet: View {
    let visiblePlace: VisiblePlace
    let attributes: [LocalPlaceAttribute]
    let isSavedByCurrentUser: Bool
    let currentUserID: String
    let save: () -> Void
    let openProfile: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: WanderTheme.spacing4) {
                    headerCard
                    externalActions

                    if !placeFacts.isEmpty {
                        factSection(title: "place", facts: placeFacts)
                    }

                    savedByCard

                    if !answerFacts.isEmpty {
                        factSection(title: "answers", facts: answerFacts)
                    }
                }
                .padding(WanderTheme.spacing4)
                .padding(.bottom, WanderTheme.spacing6)
            }
            .wanderScreen()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("done") {
                        dismiss()
                    }
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(WanderTheme.terracotta.color)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    shareButton
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing3) {
            HStack(alignment: .top, spacing: WanderTheme.spacing3) {
                DiscoverCategoryThumb(category: visiblePlace.place.category, size: 50, iconSize: 20)

                VStack(alignment: .leading, spacing: WanderTheme.spacing1) {
                    Text(visiblePlace.place.canonicalName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(WanderTheme.textInk.color)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WanderTheme.textMuted.color)
                            .lineLimit(2)
                    }

                    DiscoverStatusPill(status: visiblePlace.userPlace.status)
                }

                Spacer(minLength: WanderTheme.spacing2)

                mapAction
            }

            if let noteLine {
                Text(noteLine)
                    .font(.system(size: 15, weight: .medium))
                    .italic()
                    .foregroundStyle(WanderTheme.textMuted.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(WanderTheme.spacing4)
        .background(WanderTheme.surfaceBone.color)
        .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusSheet))
    }

    @ViewBuilder
    private var mapAction: some View {
        if isSavedByCurrentUser {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .black))
                .frame(width: 44, height: 44)
                .background(WanderTheme.surfaceSand.color)
                .foregroundStyle(WanderTheme.terracotta.color)
                .clipShape(Circle())
                .accessibilityLabel("Already on your map")
        } else {
            Button(action: save) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .black))
                    .frame(width: 44, height: 44)
                    .background(WanderTheme.terracotta.color)
                    .foregroundStyle(WanderTheme.textOnAction.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Save \(visiblePlace.place.canonicalName) to my map")
        }
    }

    @ViewBuilder
    private var externalActions: some View {
        if let directionsURL {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: WanderTheme.spacing2) {
                    DiscoverExternalActionButton(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") {
                        openURL(directionsURL)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if let shareURL {
            ShareLink(item: shareURL, subject: Text(visiblePlace.place.canonicalName), message: Text(shareText)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 38, height: 38)
                    .background(WanderTheme.surfaceSand.color)
                    .foregroundStyle(WanderTheme.textInk.color)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Share place")
        }
    }

    private var savedByCard: some View {
        Button(action: openProfile) {
            HStack(spacing: WanderTheme.spacing2) {
                WanderAvatar(initials: visiblePlace.owner.initials, size: 38, color: avatarColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(visiblePlace.owner.displayName) saved it")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(WanderTheme.textInk.color)
                    Text("@\(visiblePlace.owner.handle) · \(visiblePlace.userPlace.visibility.displayTitle)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WanderTheme.textMuted.color)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(WanderTheme.textMuted.color)
            }
            .padding(WanderTheme.spacing3)
            .background(WanderTheme.surfaceBone.color)
            .clipShape(RoundedRectangle(cornerRadius: WanderTheme.radiusLarge))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(visiblePlace.owner.displayName)'s profile")
    }

    private func factSection(title: String, facts: [DiscoverPlaceFact]) -> some View {
        VStack(alignment: .leading, spacing: WanderTheme.spacing2) {
            Text(title)
                .font(.system(size: 12, weight: .black))
                .textCase(.uppercase)
                .foregroundStyle(WanderTheme.textMuted.color)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 106), spacing: WanderTheme.spacing2)],
                alignment: .leading,
                spacing: WanderTheme.spacing2
            ) {
                ForEach(facts) { fact in
                    DiscoverFactPill(title: fact.title, systemImage: fact.systemImage)
                }
            }
        }
    }

    private var subtitle: String? {
        joinedText([addressLine, categoryDisplay])
    }

    private var addressLine: String? {
        let address = trimmed(visiblePlace.place.address)
        if let address {
            return address
        }
        return joinedText([visiblePlace.place.locality, visiblePlace.place.region])
    }

    private var categoryDisplay: String? {
        let category = trimmed(visiblePlace.place.category)
        return category == "place" ? nil : category
    }

    private var note: String? {
        trimmed(visiblePlace.userPlace.note)
    }

    private var noteLine: String? {
        guard let note else { return nil }
        let ownerLabel = visiblePlace.owner.id == currentUserID ? "your note" : "\(visiblePlace.owner.displayName)'s note"
        return "\(ownerLabel): \"\(note)\""
    }

    private var placeFacts: [DiscoverPlaceFact] {
        var facts: [DiscoverPlaceFact] = []
        if let categoryDisplay {
            facts.append(DiscoverPlaceFact(title: categoryDisplay, systemImage: WanderPlaceCategory.symbolName(for: visiblePlace.place.category)))
        }
        return facts
    }

    private var answerFacts: [DiscoverPlaceFact] {
        var facts: [DiscoverPlaceFact] = []

        if let ratingSignal = visiblePlace.userPlace.ratingSignal,
           !attributes.contains(where: { $0.questionKey == "rating_signal" }) {
            facts.append(DiscoverPlaceFact(title: ratingSignal, systemImage: "heart.fill"))
        }

        facts.append(contentsOf: attributes.flatMap(attributeFacts(for:)))
        return facts
    }

    private var directionsURL: URL? {
        PlaceExternalLinks.googleMapsDirectionsURL(
            placeName: visiblePlace.place.canonicalName,
            latitude: visiblePlace.place.latitude,
            longitude: visiblePlace.place.longitude
        )
    }

    private var shareURL: URL? {
        PlaceExternalLinks.googleMapsSearchURL(
            placeName: visiblePlace.place.canonicalName,
            address: visiblePlace.place.address,
            locality: visiblePlace.place.locality
        )
    }

    private var shareText: String {
        PlaceExternalLinks.shareSummary(
            placeName: visiblePlace.place.canonicalName,
            locality: visiblePlace.place.locality,
            status: visiblePlace.userPlace.status
        )
    }

    private var avatarColor: Color {
        visiblePlace.owner.handle == "ryan" ? WanderTheme.avatarRyan.color : WanderTheme.pinSocial.color
    }

    private func attributeFacts(for attribute: LocalPlaceAttribute) -> [DiscoverPlaceFact] {
        decodedValues(from: attribute.valueJSON).map { value in
            DiscoverPlaceFact(title: value, systemImage: icon(for: attribute.questionKey))
        }
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

    private func decodedValues(from valueJSON: String) -> [String] {
        guard let data = valueJSON.data(using: .utf8) else { return [] }
        if let values = try? JSONDecoder().decode([String].self, from: data) {
            return values
        }
        if let value = try? JSONDecoder().decode(String.self, from: data) {
            return [value]
        }
        if let value = try? JSONDecoder().decode(Bool.self, from: data) {
            return [value ? "yes" : "no"]
        }
        if let value = try? JSONDecoder().decode(Int.self, from: data) {
            return ["\(value)"]
        }
        if let value = try? JSONDecoder().decode(Double.self, from: data) {
            return [value.formatted()]
        }
        return []
    }

    private func joinedText(_ values: [String?]) -> String? {
        let parts = values.compactMap(trimmed)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct DiscoverPlaceFact: Identifiable {
    var id: String { "\(systemImage)-\(title)" }
    let title: String
    let systemImage: String
}

private struct DiscoverExternalActionButton: View {
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

private struct DiscoverFactPill: View {
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

private struct DiscoverCategoryThumb: View {
    let category: String
    let size: CGFloat
    let iconSize: CGFloat

    var body: some View {
        Image(systemName: WanderPlaceCategory.symbolName(for: category))
            .font(.system(size: iconSize, weight: .bold))
            .foregroundStyle(WanderTheme.terracotta.color)
            .frame(width: size, height: size)
            .background(WanderTheme.terracottaTint.color)
            .clipShape(Circle())
    }
}

private struct DiscoverStatusPill: View {
    let status: PlaceStatus

    var body: some View {
        Text(status == .been ? "been" : "wanna")
            .font(.system(size: 12, weight: .black))
            .padding(.horizontal, WanderTheme.spacing2)
            .frame(minHeight: 28)
            .background(status == .been ? WanderTheme.categorySage.color.opacity(0.22) : WanderTheme.sunTint.color)
            .foregroundStyle(status == .been ? WanderTheme.stateSuccess.color : WanderTheme.stateWarning.color)
            .clipShape(Capsule())
    }
}
