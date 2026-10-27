import SwiftUI

enum LivePlanSourceContext { case wannaActivity, placeProfile }

/// Chooses a mutual friend for the existing invitation composer. Selecting a
/// person never creates, publishes, or sends a plan.
struct LivePlanPeoplePicker: View {
    @EnvironmentObject private var store: WanderStore
    @EnvironmentObject private var backend: WanderBackend
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.astirBrandMode) private var brand
    @State private var loading = false
    @State private var checkingID: String?
    @State private var notice: String?
    @State private var needsOwnSave = false
    @State private var requestID = UUID()
    // A distinct route prevents this demo destination from shadowing the
    // production composer registered by the parent NavigationStack.
    private struct DemoRoute: Hashable { let place: CommonGroundMockPlace }
    @State private var demoPlan: DemoRoute?
    @State private var people: [LivePlanPeoplePolicy.PersonChoice] = []
    @State private var peopleViewerID: String?

    let place: VisiblePlace
    let onSelect: (CommonGroundMockPlace) -> Void
    var sourceContext: LivePlanSourceContext = .wannaActivity
    var onFindPeople: (() -> Void)?
    var onOpenPlace: ((VisiblePlace) -> Void)?
    private var isDemo: Bool { LivePlanDemoPolicy.isEnabled() }

    private var targetFriendID: String? {
        sourceContext == .placeProfile || place.owner.id == store.currentUser.id ? nil : place.owner.id
    }

    private var friends: [LocalProfile] {
        guard peopleViewerID == store.currentUser.id else { return [] }
        return people.map(\.profile).filter {
            $0.id != store.currentUser.id && $0.deletedAt == nil
                && store.relationship(to: $0.id) == .mutual
                && store.profile(for: $0.id) != nil
                && (targetFriendID == nil || $0.id == targetFriendID)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if isDemo {
                    Label("Demo plan · nothing is saved or sent", systemImage: "testtube.2")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                        .accessibilityIdentifier("live.plan.demo")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(targetFriendID == nil ? "Who’s coming?" : "Go together")
                        .font(AstirTypography.screenTitle).foregroundStyle(brand.primaryText)
                    Text(targetFriendID == nil
                         ? "Make a plan for \(place.place.canonicalName) with a mutual friend."
                         : "Make a plan for \(place.place.canonicalName) with \(place.owner.displayName).")
                        .font(AstirTypography.body).foregroundStyle(brand.secondaryText)
                    Text("You’ll choose the details before sharing an invitation.")
                        .font(AstirTypography.caption).foregroundStyle(brand.secondaryText)
                }
                if loading && friends.isEmpty {
                    ProgressView("Finding your friends…").frame(maxWidth: .infinity, minHeight: 100)
                } else if friends.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(targetFriendID == nil ? "Find someone to go with" : "A plan between mutual friends")
                            .font(AstirTypography.cardTitle)
                        Text(targetFriendID == nil
                             ? "Friends appear when you follow each other. Choose someone to invite to this place."
                             : "You need to follow each other before making this plan. This person may also no longer be available.")
                            .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        if let onFindPeople {
                            Button("Find people", action: onFindPeople).font(AstirTypography.control)
                                .frame(minHeight: 44).foregroundStyle(brand.accentText)
                                .accessibilityIdentifier("live.plan.findPeople")
                        }
                    }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(friends, id: \.id) { friend in
                            personRow(friend)
                            Divider().overlay(brand.border.opacity(0.2))
                        }
                    }
                }
                if let notice {
                    Text(notice).font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("live.plan.notice")
                }
                if needsOwnSave && (isDemo || onOpenPlace != nil) {
                    Button { openWannaRecovery() } label: {
                        Label(isDemo ? "Save Wanna in demo" : "Open place to save Wanna", systemImage: "bookmark")
                            .frame(minHeight: 44)
                    }.font(AstirTypography.control).foregroundStyle(brand.accentText)
                        .accessibilityIdentifier("live.plan.saveWanna")
                }
            }.padding(22)
        }
        .background(brand.background.ignoresSafeArea())
        .navigationTitle("Make a plan").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $demoPlan) { plan in
            #if DEBUG && targetEnvironment(simulator)
            LivePlanDemoComposer(place: plan.place)
            #else
            EmptyView()
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await refreshAndCheckTarget() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.foregroundStyle(brand.accentText).disabled(loading || checkingID != nil)
                    .accessibilityLabel("Refresh friends").accessibilityIdentifier("live.plan.refresh")
            }
        }
        .task(id: store.currentUser.id) {
            requestID = UUID(); checkingID = nil; notice = nil; needsOwnSave = false; demoPlan = nil
            rebuildPeople()
            if let targetFriendID, candidate(for: targetFriendID) != nil {
                await select(targetFriendID)
                return
            }
            await refreshAndCheckTarget()
        }
        .onDisappear { requestID = UUID() }
    }

    private func personRow(_ friend: LocalProfile) -> some View {
        let available = people.first(where: { $0.profile.id == friend.id })?.hasRequestedPlace == true
        return Button { Task { await select(friend.id) } } label: {
            HStack(spacing: 13) {
                WanderAvatar(initials: String(friend.displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)),
                             avatarURL: isDemo ? nil : friend.avatarURL, size: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(friend.displayName).font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    Text(available ? "Choose invitation details" : "Check place availability")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                Spacer(minLength: 8)
                if checkingID == friend.id { ProgressView() }
                else { Image(systemName: "chevron.right").foregroundStyle(brand.secondaryText) }
            }.frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(checkingID != nil)
            .accessibilityIdentifier("live.plan.person.\(friend.id)")
            .accessibilityHint("Opens invitation details without sending anything")
    }

    private func candidate(for partnerID: String) -> CommonGroundMockPlace? {
        guard peopleViewerID == store.currentUser.id,
              let cached = people.first(where: { $0.profile.id == partnerID })?.candidate else { return nil }
        return LivePlanPeoplePolicy.revalidatedCandidate(cached, source: place, store: store, sourceContext: sourceContext)
    }

    private func refreshFriends() async {
        guard !loading else { return }
        guard !isDemo else { notice = nil; return }
        let viewerID = store.currentUser.id
        loading = true
        await store.refreshRemoteSocialGraph(userID: viewerID, backend: backend)
        guard store.currentUser.id == viewerID, !Task.isCancelled else { loading = false; return }
        loading = false
        rebuildPeople()
        if store.lastRemoteError != nil { notice = "Couldn’t refresh friends. Try again when you’re connected." }
    }

    private func refreshAndCheckTarget() async {
        let viewerID = store.currentUser.id
        let sessionID = auth.state.session?.userID
        let request = requestID
        await refreshFriends()
        guard requestID == request, store.currentUser.id == viewerID,
              auth.state.session?.userID == sessionID, !Task.isCancelled,
              let targetFriendID, friends.contains(where: { $0.id == targetFriendID }) else { return }
        await select(targetFriendID)
    }

    private func select(_ partnerID: String) async {
        guard checkingID == nil, store.relationship(to: partnerID) == .mutual,
              targetFriendID == nil || partnerID == targetFriendID else { return }
        let viewerID = store.currentUser.id
        let sessionID = auth.state.session?.userID
        let request = UUID(); requestID = request
        checkingID = partnerID; notice = nil; needsOwnSave = false
        defer { if requestID == request { checkingID = nil } }
        // Opening a composer is local and sends nothing. Use current authorized
        // evidence immediately; only a missing mapping needs a network refresh.
        // The invitation's share path still verifies eligibility on the server.
        var selected = candidate(for: partnerID)
        if selected == nil && !isDemo {
            await store.refreshRemoteProfileVisiblePlaces(profileID: partnerID, backend: backend)
            guard requestID == request, store.currentUser.id == viewerID,
                  auth.state.session?.userID == sessionID, !Task.isCancelled else { return }
            guard store.lastRemoteError == nil else {
                notice = "Couldn’t check shared places. Try again when you’re connected."
                return
            }
            rebuildPeople()
            selected = candidate(for: partnerID)
        }
        guard requestID == request, store.currentUser.id == viewerID,
              auth.state.session?.userID == sessionID, !Task.isCancelled else { return }
        guard let selected else {
            needsOwnSave = (targetFriendID != nil || sourceContext == .placeProfile) && !LivePlanPeoplePolicy.hasViewerSave(
                for: place, authorizedPlaces: store.currentUserVisiblePlaces, viewerID: viewerID)
            if needsOwnSave {
                notice = "Save this place to your Wannas first, then come back to make a plan together. Nothing has been sent."
            } else if targetFriendID != nil {
                notice = "This Wanna isn’t available in your shared places right now. Refresh to check again. Nothing has been sent."
            } else {
                notice = "This place is no longer available. Save it to your Wannas or refresh and try again. Nothing has been sent."
            }
            return
        }
        #if DEBUG && targetEnvironment(simulator)
        if isDemo {
            demoPlan = DemoRoute(place: LivePlanDemoPolicy.detachedPreview(selected))
            return
        }
        #endif
        onSelect(selected)
    }

    private func rebuildPeople() {
        let viewerID = store.currentUser.id
        let profiles = store.friends(of: viewerID).filter {
            $0.id != viewerID && $0.deletedAt == nil && store.relationship(to: $0.id) == .mutual
                && (targetFriendID == nil || $0.id == targetFriendID)
        }
        let own = store.currentUserVisiblePlaces
        let evidence = CommonGroundEvidenceIndex(store: store)
        let rowsByFriend = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, own + store.visiblePlaces(for: $0.id)) })
        people = LivePlanPeoplePolicy.peopleSnapshot(profiles: profiles, project: { friend in
            CommonGroundLiveData.snapshot(store: store, profileID: friend.id, evidence: evidence,
                                          authorizedPlaces: rowsByFriend[friend.id] ?? [], includeOneSidedPlaces: true).places
        }, requestedPlace: { friend, candidates in
            LivePlanPeoplePolicy.matchingPlace(for: place, candidates: candidates,
                authorizedPlaces: rowsByFriend[friend.id] ?? [],
                viewerID: viewerID, partnerID: friend.id, relationship: store.relationship(to: friend.id),
                sourceContext: sourceContext)
        })
        peopleViewerID = viewerID
    }

    private func openWannaRecovery() {
        #if DEBUG && targetEnvironment(simulator)
        if isDemo {
            demoPlan = LivePlanDemoPolicy.savedWannaPreview(source: place, viewer: store.currentUser,
                relationship: store.relationship(to: place.owner.id)).map { DemoRoute(place: $0) }
            return
        }
        #endif
        onOpenPlace?(place)
    }
}

@MainActor
enum LivePlanPeoplePolicy {
    struct PersonChoice {
        let profile: LocalProfile
        let sharedActivityScore: Int
        let candidate: CommonGroundMockPlace?
        var hasRequestedPlace: Bool { candidate != nil }
    }

    /// Project each friend's authorized evidence once per refresh, not once per
    /// row and every SwiftUI body evaluation while a request is in flight.
    static func peopleSnapshot(profiles: [LocalProfile],
                               project: (LocalProfile) -> [CommonGroundMockPlace],
                               requestedPlace: (LocalProfile, [CommonGroundMockPlace]) -> CommonGroundMockPlace?) -> [PersonChoice] {
        profiles.map { profile in
            let places = project(profile)
            return PersonChoice(profile: profile, sharedActivityScore: sharedActivityScore(places),
                                candidate: requestedPlace(profile, places))
        }.sorted {
            if $0.sharedActivityScore != $1.sharedActivityScore { return $0.sharedActivityScore > $1.sharedActivityScore }
            let names = $0.profile.displayName.localizedCaseInsensitiveCompare($1.profile.displayName)
            return names == .orderedSame ? $0.profile.id < $1.profile.id : names == .orderedAscending
        }
    }

    /// Recheck only the selected physical place against current access. The
    /// cached candidate is a routing hint, never an authorization receipt.
    static func revalidatedCandidate(_ cached: CommonGroundMockPlace, source: VisiblePlace, store: WanderStore,
                                     sourceContext: LivePlanSourceContext) -> CommonGroundMockPlace? {
        guard cached.viewer.id == store.currentUser.id,
              store.relationship(to: cached.partner.id) == .mutual else { return nil }
        let authorized = store.currentUserVisiblePlaces + store.visiblePlaces(for: cached.partner.id)
        guard let group = VisiblePlaceGrouping.matchingGroup(for: source, in: authorized,
            currentUserID: store.currentUser.id) else { return nil }
        // Preserve transitive canonical aliases while limiting event projection
        // to this one physical place.
        let rows = group.places
        let candidates = CommonGroundLiveData.snapshot(store: store, profileID: cached.partner.id,
            evidence: CommonGroundEvidenceIndex(store: store), authorizedPlaces: rows, includeOneSidedPlaces: true).places
        return matchingPlace(for: source, candidates: candidates, authorizedPlaces: rows,
            viewerID: store.currentUser.id, partnerID: cached.partner.id,
            relationship: store.relationship(to: cached.partner.id), sourceContext: sourceContext)
    }

    static func canShare(_ candidate: CommonGroundMockPlace, store: WanderStore) -> Bool {
        guard candidate.viewer.id == store.currentUser.id,
              store.relationship(to: candidate.partner.id) == .mutual else { return false }
        let rows = store.currentUserVisiblePlaces + store.visiblePlaces(for: candidate.partner.id)
        guard let source = rows.first(where: {
            $0.id == candidate.sourcePlaceID || ($0.place.serverID != nil && $0.place.serverID == candidate.photoReference?.placeID)
        }) else { return false }
        guard let current = revalidatedCandidate(candidate, source: source, store: store, sourceContext: .placeProfile) else { return false }
        // Ratings, counts, and avatars may refresh while composing. They are
        // presentation data, not permission to invite a different person/place.
        return current.viewer.id == candidate.viewer.id && current.partner.id == candidate.partner.id
            && current.photoReference?.placeID == candidate.photoReference?.placeID
    }

    /// Rank only from currently authorized shared-place evidence. One-sided
    /// recommendations do not inflate the relationship, and no private message
    /// contents or unavailable profile records are inspected.
    static func sharedActivityScore(_ places: [CommonGroundMockPlace]) -> Int {
        places.filter { !$0.isOneSidedRecommendation }.reduce(0) {
            $0 + $1.youEvidence.visitCount + $1.joeEvidence.visitCount
                + $1.youEvidence.wannaCount + $1.joeEvidence.wannaCount
        }
    }

    static func hasViewerSave(for requested: VisiblePlace, authorizedPlaces: [VisiblePlace], viewerID: String) -> Bool {
        let rows = authorizedPlaces.filter {
            $0.owner.id == viewerID && $0.userPlace.userID == viewerID
                && $0.userPlace.deletedAt == nil && $0.owner.deletedAt == nil && !$0.isCommunityAggregate
        }
        return VisiblePlaceGrouping.matchingGroup(for: requested, in: rows, currentUserID: viewerID) != nil
    }

    static func matchingPlace(for requested: VisiblePlace, candidates: [CommonGroundMockPlace],
                              authorizedPlaces: [VisiblePlace], viewerID: String,
                              partnerID: String, relationship: ViewerRelationship,
                              sourceContext: LivePlanSourceContext = .wannaActivity) -> CommonGroundMockPlace? {
        let isOwnSource = requested.owner.id == viewerID
        guard relationship == .mutual, viewerID != partnerID,
              sourceContext == .placeProfile || isOwnSource || requested.owner.id == partnerID,
              requested.owner.id == requested.userPlace.userID,
              requested.userPlace.deletedAt == nil, requested.owner.deletedAt == nil,
              !requested.isCommunityAggregate,
              isOwnSource || requested.userPlace.visibility != .selfOnly else { return nil }
        let rows = authorizedPlaces.filter {
            ($0.owner.id == viewerID || $0.owner.id == partnerID)
                && $0.owner.id == $0.userPlace.userID && $0.owner.deletedAt == nil
                && $0.userPlace.deletedAt == nil && !$0.isCommunityAggregate
                && ($0.owner.id == viewerID || $0.userPlace.visibility != .selfOnly)
        }
        guard let group = VisiblePlaceGrouping.matchingGroup(for: requested, in: rows, currentUserID: viewerID) else { return nil }
        let sourceIDs = Set(group.places.map(\.id))
        return candidates.first {
            $0.viewer.id == viewerID && $0.partner.id == partnerID
                && (sourceContext == .placeProfile
                    ? true : (isOwnSource ? $0.youWanna : $0.joeWanna))
                && ($0.id == group.key || $0.sourcePlaceID.map(sourceIDs.contains) == true)
        }
    }
}
