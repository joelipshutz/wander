import Foundation

/// Presentation evidence for an already-authorized canonical place. Event
/// counts and list contents remain owned by their original projections.
struct LiveTotemState: Equatable {
    let rails: [MapPinOutline]
    let hasListMembership: Bool
    let hasSavedStatus: Bool
    let isFeatured: Bool

    static let empty = Self(rails: [], hasListMembership: false, hasSavedStatus: false, isFeatured: false)

    var accessibilitySummary: String {
        var labels = rails.map { rail in
            if rail.ownership == .featured { return "Featured" }
            let owner = rail.ownership == .currentUser ? "You" : "Social"
            let status = rail.secondaryStatus == nil
                ? (rail.status == .been ? "Been" : "Wanna") : "Been and Wanna"
            return "\(owner), \(status)"
        }
        if hasListMembership { labels.append("On a list") }
        return labels.joined(separator: ", ")
    }
}

/// Current readable saves and membership are independent of the selected Feed
/// time window. Callers must supply viewer-authorized rows, never raw cache or
/// historical list events. This context cannot create activities or map pins.
struct LiveTotemContext {
    let currentUserID: String
    let query: LiveFeedQuery
    let audience: FeedAudience
    let friendIDs: Set<String>
    let currentSavedPlaces: [VisiblePlace]
    let currentListPlaces: [LocalPlace]
    let currentListPlaceIDs: Set<String>
    let currentStateIsComplete: Bool
    let authoritativeState: LiveMapPinStateSnapshot?
    let allowsCachedAssociations: Bool
    private let pendingOwnListPlaceIDs: Set<String>
    private let savesByAlias: [String: Set<Int>]
    private let listIdentity: LivePlaceIdentity
    private let pendingOwnListIdentity: LivePlaceIdentity
    private let authoritativeStatesByID: [String: LiveMapPinState]

    init(currentUserID: String, query: LiveFeedQuery,
         currentSavedPlaces: [VisiblePlace], currentListPlaces: [LocalPlace],
         currentListPlaceIDs: Set<String> = [], audience: FeedAudience = .everyone,
         friendIDs: Set<String> = [], currentStateIsComplete: Bool = false,
         authoritativeState: LiveMapPinStateSnapshot? = nil, allowsCachedAssociations: Bool = true,
         pendingOwnListPlaceIDs: Set<String> = []) {
        self.currentUserID = currentUserID
        self.query = query
        self.audience = audience
        self.friendIDs = friendIDs
        self.currentStateIsComplete = currentStateIsComplete
        self.authoritativeState = authoritativeState
        self.allowsCachedAssociations = allowsCachedAssociations
        self.currentSavedPlaces = currentSavedPlaces.filter(Self.isActiveSave)
        self.currentListPlaces = currentListPlaces
        self.currentListPlaceIDs = Set(currentListPlaceIDs.map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 })
        self.listIdentity = LivePlaceIdentity(places: currentListPlaces)
        let pendingIDs = Set(pendingOwnListPlaceIDs.map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 })
            .intersection(self.currentListPlaceIDs.union(self.listIdentity.placeIDs))
        self.pendingOwnListPlaceIDs = pendingIDs
        self.pendingOwnListIdentity = LivePlaceIdentity(places: currentListPlaces.filter { place in
            [place.id, place.localID, place.serverID].compactMap { $0 }
                .map { UUID(uuidString: $0)?.uuidString.lowercased() ?? $0 }.contains(where: pendingIDs.contains)
        })
        var index: [String: Set<Int>] = [:]
        for (offset, place) in self.currentSavedPlaces.enumerated() {
            for alias in LivePlaceIdentity.aliases(for: place.place) { index[alias, default: []].insert(offset) }
        }
        self.savesByAlias = index
        var authoritative: [String: LiveMapPinState] = [:]
        var valid = authoritativeState?.complete == true
        for state in authoritativeState?.states ?? [] {
            guard let id = UUID(uuidString: state.placeID)?.uuidString.lowercased(), authoritative[id] == nil else {
                valid = false
                continue
            }
            authoritative[id] = state
        }
        self.authoritativeStatesByID = valid ? authoritative : [:]
    }

    /// Evidence-only vertices allow canonical aliases to bridge query windows
    /// without introducing an extra visible result or a synthetic activity.
    var identityPlaces: [LocalPlace] { currentSavedPlaces.filter(Self.isActiveSave).map(\.place) + currentListPlaces }

    func state(for identity: LivePlaceIdentity, activities: [FeedActivity], featured: Bool,
               additionalSavedPlaces: [VisiblePlace] = [], hasPriorOwnCheckIn: Bool = false) -> LiveTotemState {
        if let authoritative = authoritativeState(for: identity, featured: featured) { return authoritative }
        // Remote caches and event envelopes can outlive revoked saves/list
        // entries. Once current authorization is unknown, display no inferred
        // association until a complete covering response arrives.
        guard allowsCachedAssociations else {
            let pending = pendingOwnSaveEvidence(for: identity)
            return LiveTotemState(
                rails: MapPinOutlineBuilder.outlines(for: pending.filter { includes($0) }.map(saveState)),
                hasListMembership: hasPendingOwnListMembership(for: identity),
                hasSavedStatus: !pending.isEmpty, isFeatured: false)
        }
        let matchingSaves = Set(identity.aliases.flatMap { savesByAlias[$0] ?? [] })
            .map { currentSavedPlaces[$0] }.filter { Self.isActiveSave($0) && identity.matches($0.place) }
            + additionalSavedPlaces.filter { Self.isActiveSave($0) && identity.matches($0.place) }
        var currentStates = matchingSaves.flatMap { place -> [Evidence] in
            var states = [Evidence(ownerID: place.owner.id, status: place.userPlace.status)]
            if place.userPlace.status != .been,
               place.userPlace.visitedAt != nil || place.userPlace.recommendedCount > 0 {
                states.append(Evidence(ownerID: place.owner.id, status: .been))
            }
            return states
        }
        if hasPriorOwnCheckIn { currentStates.append(Evidence(ownerID: currentUserID, status: .been)) }
        var allStates = currentStates
        // A list event's place is only a display container. Its required status
        // field is not proof of a Been/Wanna save by the actor or source owner.
        let eventStates = activities.compactMap { activity -> (Evidence, FeedActivity)? in
            guard let place = activity.place, Self.isActiveSave(place),
                  !place.isCommunityAggregate else { return nil }
            let status: PlaceStatus
            switch activity.resolvedTicketKind {
            case .checkIn: status = .been
            case .wanna: status = .wannaGo
            case .list, .saved: return nil
            }
            return (Evidence(ownerID: activity.actor.id, status: status), activity)
        }
        allStates += eventStates.map(\.0)
        var selected = currentStates.compactMap { evidence -> MapPinSaveState? in
            guard includes(evidence) else { return nil }
            return saveState(evidence)
        }
        selected += eventStates.compactMap { evidence, activity in
            guard query.includes(activity), includes(evidence, relationship: activity.actor.relationship) else { return nil }
            return saveState(evidence)
        }
        let membership = identity.intersects(listIdentity) || !identity.placeIDs.isDisjoint(with: currentListPlaceIDs)
        let hasSavedStatus = !allStates.isEmpty
        // Neither an empty cache nor the absence of in-window activity proves
        // there are no authorized saves/list memberships. Unknown stays neutral.
        let isFeatured = featured && currentStateIsComplete && authoritativeState == nil && !hasSavedStatus && !membership
        let rails = isFeatured ? [MapPinOutline(ownership: .featured, status: .been)]
            : MapPinOutlineBuilder.outlines(for: selected)
        return LiveTotemState(rails: rails, hasListMembership: membership,
                              hasSavedStatus: hasSavedStatus, isFeatured: isFeatured)
    }

    private func authoritativeState(for identity: LivePlaceIdentity, featured: Bool) -> LiveTotemState? {
        let ids = identity.persistedPlaceIDs
        guard !ids.isEmpty, ids.allSatisfy({ authoritativeStatesByID[$0] != nil }) else { return nil }
        let records = ids.compactMap { authoritativeStatesByID[$0] }
        let facets = records.flatMap(\.saves)
        let pendingOwn = pendingOwnSaveEvidence(for: identity)
        // Server absence cannot cover an active own write that has not synced.
        // This viewer's local intent is visible while queued/retrying. Other
        // people's cached writes never override the authorized server response.
        let hasSavedStatus = !pendingOwn.isEmpty || facets.contains { $0.hasBeen || $0.hasWanna }
        let membership = records.contains(where: \.hasListMembership) || hasPendingOwnListMembership(for: identity)
        let isFeatured = featured && !hasSavedStatus && !membership
        var selected = facets.flatMap { facet -> [MapPinSaveState] in
            var states: [MapPinSaveState] = []
            for status in [PlaceStatus.been, .wannaGo] {
                guard (status == .been ? facet.hasBeen : facet.hasWanna) else { continue }
                let evidence = Evidence(ownerID: facet.ownerID, status: status)
                guard includes(evidence, relationship: facet.isFriend ? .mutual : .nonFollower) else { continue }
                states.append(saveState(evidence))
            }
            return states
        }
        selected += pendingOwn.filter { includes($0) }.map(saveState)
        // Complete current facts replace synced cache/event associations,
        // including false membership and a removed prior own check-in.
        return LiveTotemState(
            rails: isFeatured ? [MapPinOutline(ownership: .featured, status: .been)]
                : MapPinOutlineBuilder.outlines(for: selected),
            hasListMembership: membership, hasSavedStatus: hasSavedStatus, isFeatured: isFeatured)
    }

    private func hasPendingOwnListMembership(for identity: LivePlaceIdentity) -> Bool {
        identity.intersects(pendingOwnListIdentity) || !identity.placeIDs.isDisjoint(with: pendingOwnListPlaceIDs)
    }

    private func pendingOwnSaveEvidence(for identity: LivePlaceIdentity) -> [Evidence] {
        Set(identity.aliases.flatMap { savesByAlias[$0] ?? [] }).flatMap { index -> [Evidence] in
            let place = currentSavedPlaces[index]
            guard Self.isActiveSave(place), place.owner.id == currentUserID,
                  identity.matches(place.place) else { return [] }
            switch place.userPlace.syncState {
            case .localOnly, .pendingCreate, .pendingUpdate, .failed: break
            case .synced, .pendingDelete, .serverDenied, .tombstoned: return []
            }
            var result = [Evidence(ownerID: currentUserID, status: place.userPlace.status)]
            if place.userPlace.status != .been,
               place.userPlace.visitedAt != nil || place.userPlace.recommendedCount > 0 {
                result.append(Evidence(ownerID: currentUserID, status: .been))
            }
            return result
        }
    }

    private struct Evidence { let ownerID: String; let status: PlaceStatus }

    private func includes(_ evidence: Evidence, relationship: ViewerRelationship? = nil) -> Bool {
        guard query.isValid,
              query.personIDs.isEmpty || query.personIDs.contains(evidence.ownerID),
              audience.includes(actorID: evidence.ownerID, currentUserID: currentUserID,
                                relationship: relationship ?? (friendIDs.contains(evidence.ownerID) ? .mutual : .nonFollower))
        else { return false }
        switch query.activityType {
        case .all, .lists: return true
        case .checkIns: return evidence.status == .been
        case .wannas: return evidence.status == .wannaGo
        }
    }

    private func saveState(_ evidence: Evidence) -> MapPinSaveState {
        MapPinSaveState(ownership: evidence.ownerID == currentUserID ? .currentUser : .social, status: evidence.status)
    }

    private static func isActiveSave(_ place: VisiblePlace) -> Bool {
        !place.isCommunityAggregate && place.owner.deletedAt == nil && place.userPlace.deletedAt == nil
            && place.owner.id == place.userPlace.userID
    }
}

extension WanderStore {
    /// The store owns list authorization and tombstone collapse. Resolving a
    /// list item needs only a canonical place, not a companion Been/Wanna save.
    @MainActor
    func liveTotemContext(query: LiveFeedQuery, currentStateIsComplete: Bool = false,
                          authoritativeState: LiveMapPinStateSnapshot? = nil,
                          allowsCachedAssociations: Bool = true) -> LiveTotemContext {
        let currentUserID = currentUser.id
        let audience = feedAudience
        let items = liveReadableListItems()
        let placeIDs = Set(items.map(\.placeID))
        // Only this viewer's current readable, active local writes may survive
        // a remote absence result. Collapse/removal precedence is owned by the
        // store's list resolver; no event or another user's cache is proof.
        let pendingOwnPlaceIDs = Set(items.filter { item in
            guard item.deletedAt == nil, item.addedByUserID == currentUserID else { return false }
            switch item.syncState {
            case .localOnly, .pendingCreate, .pendingUpdate, .failed: return true
            case .synced, .pendingDelete, .serverDenied, .tombstoned: return false
            }
        }.map(\.placeID))
        let listPlaces = places.filter { place in
            [place.id, place.localID, place.serverID].compactMap { $0 }.contains(where: placeIDs.contains)
        }
        let wannasByParent = Dictionary(grouping: placeWannaSaves, by: \.userPlaceID)
        let saved = visiblePlaces().filter { place in
            guard place.userPlace.status == .wannaGo else { return true }
            let parent = place.userPlace
            // A private-list container's initial summary is not an explicit
            // Wanna. The flag survives later real saves, so retain independently
            // authorized Wanna history or an actual visit instead of dropping
            // every flagged parent. Explicit Feed events remain separate proof.
            if parent.isPrivateListCompanion, parent.visitedAt == nil, parent.recommendedCount == 0,
               wannaSaves(for: parent).isEmpty,
               (place.owner.id != currentUserID || visits(for: parent.id).isEmpty) {
                return false
            }
            let ids = Set([parent.id, parent.localID, parent.serverID].compactMap { $0 })
            let originals = ids.flatMap { wannasByParent[$0] ?? [] }.filter {
                $0.ownerID == parent.userID && $0.isHistoricalOriginal == true
            }
            // Removing the last Wanna can leave its parent for a list. A
            // mutable summary status must not resurrect that deleted action.
            return originals.isEmpty || originals.contains { $0.deletedAt == nil }
                || !wannaSaves(for: parent).isEmpty || !visits(for: parent.id).isEmpty
        }
        let friendIDs: Set<String> = audience == .onlyFriends
            ? Set(profiles.filter { relationship(to: $0.id) == .mutual }.map(\.id)) : []
        return LiveTotemContext(currentUserID: currentUserID, query: query,
            currentSavedPlaces: saved, currentListPlaces: listPlaces, currentListPlaceIDs: placeIDs,
            audience: audience, friendIDs: friendIDs,
            currentStateIsComplete: currentStateIsComplete, authoritativeState: authoritativeState,
            allowsCachedAssociations: allowsCachedAssociations, pendingOwnListPlaceIDs: pendingOwnPlaceIDs)
    }
}
