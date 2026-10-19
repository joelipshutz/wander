import SwiftUI

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
    @State private var demoPlan: CommonGroundMockPlace?

    let place: VisiblePlace
    let onSelect: (CommonGroundMockPlace) -> Void
    var onFindPeople: (() -> Void)?
    var onOpenPlace: ((VisiblePlace) -> Void)?
    private var isDemo: Bool { LivePlanDemoPolicy.isEnabled() }

    private var targetFriendID: String? {
        place.owner.id == store.currentUser.id ? nil : place.owner.id
    }

    private var friends: [LocalProfile] {
        store.friends(of: store.currentUser.id).filter {
            $0.id != store.currentUser.id && $0.deletedAt == nil
                && store.relationship(to: $0.id) == .mutual
                && store.profileState(for: $0.id)?.isBlocked == false
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
                         ? "Make a plan for \(place.place.canonicalName) with a mutual friend who has this place in common."
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
                             ? "Friends appear when you follow each other. An invitation is available when this place is in your shared places."
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
            LivePlanDemoComposer(place: plan)
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
            await refreshAndCheckTarget()
        }
        .onDisappear { requestID = UUID() }
    }

    private func personRow(_ friend: LocalProfile) -> some View {
        let available = candidate(for: friend.id) != nil
        return Button { Task { await select(friend.id) } } label: {
            HStack(spacing: 13) {
                WanderAvatar(initials: String(friend.displayName.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)),
                             avatarURL: isDemo ? nil : friend.avatarURL, size: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(friend.displayName).font(AstirTypography.cardTitle).foregroundStyle(brand.primaryText)
                    Text(available ? "Place in common · choose details" : "Check shared places")
                        .font(AstirTypography.bodySmall).foregroundStyle(brand.secondaryText)
                }
                Spacer(minLength: 8)
                if checkingID == friend.id { ProgressView() }
                else { Image(systemName: "chevron.right").foregroundStyle(brand.secondaryText) }
            }.frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(checkingID != nil || loading)
            .accessibilityIdentifier("live.plan.person.\(friend.id)")
            .accessibilityHint("Checks current shared-place access before opening invitation details")
    }

    private func candidate(for partnerID: String) -> CommonGroundMockPlace? {
        LivePlanPeoplePolicy.matchingPlace(for: place,
            candidates: CommonGroundLiveData.places(store: store, profileID: partnerID),
            authorizedPlaces: store.currentUserVisiblePlaces + store.visiblePlaces(for: partnerID),
            viewerID: store.currentUser.id, partnerID: partnerID, relationship: store.relationship(to: partnerID))
    }

    private func refreshFriends() async {
        guard !loading else { return }
        guard !isDemo else { notice = nil; return }
        let viewerID = store.currentUser.id
        loading = true
        await store.refreshRemoteSocialGraph(userID: viewerID, backend: backend)
        guard store.currentUser.id == viewerID, !Task.isCancelled else { loading = false; return }
        loading = false
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
        if !isDemo { await store.refreshRemoteProfileData(profileID: partnerID, backend: backend) }
        guard requestID == request, store.currentUser.id == viewerID,
              auth.state.session?.userID == sessionID, !Task.isCancelled else { return }
        guard isDemo || store.lastRemoteError == nil else {
            notice = "Couldn’t check shared places. Try again when you’re connected."
            return
        }
        guard let selected = candidate(for: partnerID) else {
            needsOwnSave = targetFriendID != nil && !LivePlanPeoplePolicy.hasViewerSave(
                for: place, authorizedPlaces: store.currentUserVisiblePlaces, viewerID: viewerID)
            if needsOwnSave {
                notice = "Save this place to your Wannas first, then come back to make a plan together. Nothing has been sent."
            } else if targetFriendID != nil {
                notice = "This Wanna isn’t available in your shared places right now. Refresh to check again. Nothing has been sent."
            } else {
                notice = "This place isn’t available in your shared places with this friend. Choose someone else, or try again after you’ve both saved it."
            }
            return
        }
        #if DEBUG && targetEnvironment(simulator)
        if isDemo {
            demoPlan = LivePlanDemoPolicy.detachedPreview(selected)
            return
        }
        #endif
        onSelect(selected)
    }

    private func openWannaRecovery() {
        #if DEBUG && targetEnvironment(simulator)
        if isDemo {
            demoPlan = LivePlanDemoPolicy.savedWannaPreview(source: place, viewer: store.currentUser,
                relationship: store.relationship(to: place.owner.id))
            return
        }
        #endif
        onOpenPlace?(place)
    }
}

@MainActor
enum LivePlanPeoplePolicy {
    static func hasViewerSave(for requested: VisiblePlace, authorizedPlaces: [VisiblePlace], viewerID: String) -> Bool {
        let rows = authorizedPlaces.filter {
            $0.owner.id == viewerID && $0.userPlace.userID == viewerID
                && $0.userPlace.deletedAt == nil && $0.owner.deletedAt == nil && !$0.isCommunityAggregate
        }
        return VisiblePlaceGrouping.matchingGroup(for: requested, in: rows, currentUserID: viewerID) != nil
    }

    static func matchingPlace(for requested: VisiblePlace, candidates: [CommonGroundMockPlace],
                              authorizedPlaces: [VisiblePlace], viewerID: String,
                              partnerID: String, relationship: ViewerRelationship) -> CommonGroundMockPlace? {
        let isOwnSource = requested.owner.id == viewerID
        guard relationship == .mutual, viewerID != partnerID,
              isOwnSource || requested.owner.id == partnerID,
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
            $0.viewer.id == viewerID && $0.partner.id == partnerID && (isOwnSource ? $0.youWanna : $0.joeWanna)
                && ($0.id == group.key || $0.sourcePlaceID.map(sourceIDs.contains) == true)
        }
    }
}
