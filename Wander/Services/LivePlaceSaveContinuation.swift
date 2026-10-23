import Foundation

/// Resolve Live's public/native place identity against the viewer's existing
/// saves before choosing an editor. No public place is turned into a fake save.
@MainActor
enum LivePlaceSaveContinuation {
    static func matchingOwnPlaces(candidate: PlaceCandidate, store: WanderStore) -> [VisiblePlace] {
        var seen = Set<String>()
        return store.currentUserVisiblePlaces.filter {
            $0.owner.id == store.currentUser.id && $0.userPlace.userID == store.currentUser.id
                && $0.owner.deletedAt == nil && $0.userPlace.deletedAt == nil
                && VisiblePlaceGrouping.matches($0, candidate: candidate, allowingProviderIdentityFallback: true)
                && seen.insert($0.userPlace.id).inserted
        }.sorted { $0.userPlace.id < $1.userPlace.id }
    }

    static func context(candidate: PlaceCandidate, visiblePlace: VisiblePlace? = nil,
                        store: WanderStore) -> MapPlaceSaveContext {
        let ownPlaces = matchingOwnPlaces(candidate: candidate, store: store)
        let sources = ownPlaces.compactMap { place -> (VisiblePlace, PlaceWannaSave?, Date)? in
            let wanna = latestWanna(for: place, store: store)
            guard let date = wanna?.occurredAt ?? originalWannaDate(for: place, store: store) else { return nil }
            return (place, wanna, date)
        }.sorted { $0.2 == $1.2 ? $0.0.id < $1.0.id : $0.2 > $1.2 }
        if let (own, wanna, _) = sources.first {
            return .addFromExistingWanna(own, attributes: store.attributes(for: own.userPlace.id),
                latestVisit: store.visits(for: own.userPlace.id).first, wanna: wanna)
        }
        if let own = ownPlaces.first {
            return .addToExistingPlaceFromLive(own, attributes: store.attributes(for: own.userPlace.id),
                latestVisit: store.visits(for: own.userPlace.id).first)
        }
        if let visiblePlace {
            return .addVisiblePlace(visiblePlace, defaultVisibility: store.effectiveDefaultVisibility)
        }
        return .addCandidate(candidate, sourceType: .manual, defaultVisibility: store.effectiveDefaultVisibility)
    }

    static func latestWanna(for place: VisiblePlace, store: WanderStore) -> PlaceWannaSave? {
        let stored = store.wannaSaves(for: place.userPlace)
        if let newest = stored.first { return newest }
        let parent = place.userPlace
        guard parent.status == .been, let date = originalWannaDate(for: place, store: store) else { return nil }
        return PlaceWannaSave(id: UUID().uuidString.lowercased(), ownerID: parent.userID,
            userPlaceID: parent.id, occurredAt: date, note: parent.historicalWantNote,
            visibility: parent.visibility, plannedDate: nil,
            attributeAnswersJSON: parent.historicalWantAttributeAnswersJSON ?? "[]", isHistoricalOriginal: true)
    }

    static func originalWannaDate(for place: VisiblePlace, store: WanderStore) -> Date? {
        let parent = place.userPlace
        let ids = Set([parent.id, parent.localID, parent.serverID].compactMap { $0 })
        let originals = store.placeWannaSaves.filter {
            $0.ownerID == parent.userID && ids.contains($0.userPlaceID) && $0.isHistoricalOriginal == true
        }
        if let existing = originals.first(where: { $0.deletedAt == nil }) { return existing.occurredAt }
        // A list-only place container or stale summary must not resurrect a
        // previously removed Wanna when the place is revisited.
        guard originals.isEmpty else { return nil }
        return parent.historicalWantedAt
            ?? (parent.status == .wannaGo && !parent.isPrivateListCompanion ? parent.savedAt : nil)
    }
}
