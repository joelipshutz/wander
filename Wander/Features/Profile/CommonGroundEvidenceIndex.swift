import Foundation

/// A synchronous, read-scoped index. It never authorizes a parent save: callers
/// still supply the store's currently visible rows to CommonGroundLiveData.
@MainActor
struct CommonGroundEvidenceIndex {
    private let referencesByAlias: [String: Set<String>]
    private let visitsByParent: [String: [LocalPlaceVisit]]
    private let wannasByParent: [String: [PlaceWannaSave]]

    init(store: WanderStore) {
        self.init(userPlaces: store.userPlaces, visits: store.placeVisits, wannas: store.placeWannaSaves,
                  viewerID: store.currentUser.id, relationship: store.relationship,
                  isBlocked: store.isBlockedBetweenCurrentUser)
    }

    init(userPlaces: [LocalUserPlace], visits: [LocalPlaceVisit], wannas: [PlaceWannaSave],
         viewerID: String, relationship: (String) -> ViewerRelationship, isBlocked: (String) -> Bool) {
        var aliases: [String: Set<String>] = [:]
        for parent in userPlaces {
            let references = Set([parent.id, parent.localID, parent.serverID].compactMap { $0 })
            // Match the store's first matching parent for any local/server alias.
            for reference in references where aliases[reference] == nil { aliases[reference] = references }
        }
        referencesByAlias = aliases
        visitsByParent = Dictionary(grouping: visits.filter { $0.deletedAt == nil }, by: \.userPlaceID)
        var access: [String: (ViewerRelationship, Bool)] = [:]
        let policy = VisibilityPolicy()
        let allowed = wannas.filter { wanna in
            guard wanna.deletedAt == nil else { return false }
            let ownerAccess: (ViewerRelationship, Bool)
            if let cached = access[wanna.ownerID] { ownerAccess = cached }
            else {
                ownerAccess = (relationship(wanna.ownerID), isBlocked(wanna.ownerID))
                access[wanna.ownerID] = ownerAccess
            }
            return policy.canSeePlace(viewerID: viewerID, ownerID: wanna.ownerID,
                visibility: wanna.visibility, relationship: ownerAccess.0, isBlocked: ownerAccess.1)
        }
        wannasByParent = Dictionary(grouping: allowed, by: \.userPlaceID)
    }

    func visits(for reference: String) -> [LocalPlaceVisit] {
        (referencesByAlias[reference] ?? [reference]).flatMap { visitsByParent[$0, default: []] }
            .sorted {
                if $0.visitedAt != $1.visitedAt { return $0.visitedAt > $1.visitedAt }
                return $0.createdAt > $1.createdAt
            }
    }

    func wannaIDs(for parent: LocalUserPlace) -> [String] {
        guard parent.deletedAt == nil else { return [] }
        return Set([parent.id, parent.localID, parent.serverID].compactMap { $0 })
            .flatMap { wannasByParent[$0, default: []] }
            .filter { $0.ownerID == parent.userID }
            .sorted { $0.occurredAt > $1.occurredAt }.map(\.id)
    }
}
