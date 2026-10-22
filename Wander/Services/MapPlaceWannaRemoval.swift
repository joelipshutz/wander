import Foundation

/// Captured before the visit changes the place summary. Never infer a removal
/// target from whichever Wanna happens to be newest when an async save finishes.
struct MapPlaceWannaRemovalTarget: Equatable {
    let ownerID: String
    let userPlaceID: String
    let wannaID: String?
    let isOriginal: Bool
}

@MainActor
func completeSourceWannaRemovalAfterCheckIn(
    _ result: SaveResult,
    visit: LocalPlaceVisit,
    submission: MapPlaceSaveSubmission,
    store: WanderStore,
    backend: WanderBackend?
) -> SaveResult {
    guard submission.removesSourceWannaAfterCheckIn, submission.status == .been,
          case .addVisit = submission.context.mode,
          let target = submission.context.wannaRemovalTarget,
          target.ownerID == store.currentUser.id,
          submission.ownerUserID.map({ $0 == target.ownerID }) ?? true,
          let parent = store.currentUserVisiblePlaces.first(where: {
              $0.userPlace.userID == target.ownerID
                  && [$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].contains(target.userPlaceID)
          })?.userPlace
    else { return result }
    let parentIDs = Set([parent.id, parent.localID, parent.serverID].compactMap { $0 })
    guard parentIDs.contains(result.userPlaceID), parentIDs.contains(visit.userPlaceID),
          store.visits(for: parent.id).contains(where: { $0.id == visit.id }),
          [.synced, .localOnly, .pendingCreate, .pendingUpdate].contains(result.syncState),
          [.synced, .localOnly, .pendingCreate, .pendingUpdate].contains(visit.syncState)
    else {
        return warning(result, "Your Wanna was kept because the check-in has not finished saving.")
    }
    // Commit the replacement first. The existing deletion outbox also refuses
    // remote Wanna removal until every replacement visit is acknowledged.
    store.flushPersistence()
    guard store.removeImportedWanna(userPlaceID: parent.id, wannaID: target.wannaID,
                                    isOriginal: target.isOriginal) else {
        return warning(result, "Your check-in was saved, but the original Wanna could not be removed. You can remove it from Your Map.")
    }
    store.flushPersistence()
    if let backend {
        Task { @MainActor [weak store] in
            guard let store, store.currentUser.id == target.ownerID else { return }
            _ = await store.syncPendingWannaSaves(backend: backend)
        }
    }
    return result
}

private func warning(_ result: SaveResult, _ message: String) -> SaveResult {
    var result = result
    result.localDetailsWarning = [result.localDetailsWarning, message].compactMap { $0 }.joined(separator: "\n\n")
    return result
}
