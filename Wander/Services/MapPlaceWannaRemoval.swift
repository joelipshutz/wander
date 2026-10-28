import Foundation

/// An immutable record identity captured before a check-in starts saving.
/// Occurrence time protects a legacy original from a later replacement.
struct MapPlaceWannaRemovalTarget: Equatable {
    let ownerID: String
    let userPlaceID: String
    let wannaID: String?
    let isOriginal: Bool
    let occurredAt: Date
    var userPlaceLocalID: String? = nil
}

@MainActor
extension MapPlaceSaveSubmission {
    func preparingPriorWannaRemoval(in store: WanderStore, backend: WanderBackend?) async throws -> Self {
        guard removesSourceWannaAfterCheckIn, status == .been, case .addVisit = context.mode else { return self }
        let ownerID = store.currentUser.id
        let generation = store.wannaRemovalAccountGeneration
        guard ownerUserID.map({ $0 == ownerID }) ?? true, context.saveOwnerUserID == ownerID else {
            throw MapPlaceWannaHistoryError.unavailable
        }
        guard let backend else { return capturingPriorWannas(in: store) }
        if priorWannaHistoryOwnerID == ownerID, priorWannaHistoryGeneration == generation,
           priorWannaRemovalTargets != nil { return self }
        do { try await store.refreshOwnWannaRemovalHistory(candidate: candidate, backend: backend) }
        catch { throw MapPlaceWannaHistoryError.unavailable }
        guard store.currentUser.id == ownerID, store.wannaRemovalAccountGeneration == generation,
              !Task.isCancelled else { throw MapPlaceWannaHistoryError.unavailable }
        var copy = self
        copy.priorWannaRemovalTargets = nil
        copy = copy.capturingPriorWannas(in: store)
        copy.priorWannaHistoryOwnerID = ownerID
        copy.priorWannaHistoryGeneration = generation
        return copy
    }

    func capturingPriorWannas(in store: WanderStore) -> Self {
        guard removesSourceWannaAfterCheckIn, status == .been,
              case .addVisit = context.mode, priorWannaRemovalTargets == nil,
              ownerUserID.map({ $0 == store.currentUser.id }) ?? true,
              context.saveOwnerUserID == store.currentUser.id else { return self }
        var copy = self
        copy.priorWannaRemovalTargets = LivePlaceSaveContinuation.matchingOwnPlaces(candidate: candidate, store: store)
            .flatMap { visible -> [MapPlaceWannaRemovalTarget] in
                let parent = visible.userPlace
                let wannas = store.wannaSaves(for: parent)
                var targets = wannas.map {
                    MapPlaceWannaRemovalTarget(ownerID: parent.userID, userPlaceID: parent.id,
                        wannaID: $0.id, isOriginal: $0.isHistoricalOriginal == true,
                        occurredAt: $0.occurredAt, userPlaceLocalID: parent.localID)
                }
                if !wannas.contains(where: { $0.isHistoricalOriginal == true }),
                   let date = LivePlaceSaveContinuation.originalWannaDate(for: visible, store: store) {
                    targets.append(MapPlaceWannaRemovalTarget(ownerID: parent.userID, userPlaceID: parent.id,
                        wannaID: nil, isOriginal: true, occurredAt: date, userPlaceLocalID: parent.localID))
                }
                return targets
            }
        return copy
    }
}

@MainActor
func completeSourceWannaRemovalAfterCheckIn(
    _ result: SaveResult,
    visit: LocalPlaceVisit,
    submission: MapPlaceSaveSubmission,
    store: WanderStore,
    backend: WanderBackend?
) async -> SaveResult {
    guard submission.removesSourceWannaAfterCheckIn, submission.status == .been,
          case .addVisit(let source) = submission.context.mode,
          let targets = submission.priorWannaRemovalTargets, !targets.isEmpty else { return result }
    let ownerID = source.userPlace.userID
    let sourceIDs = Set([source.userPlace.id, source.userPlace.localID, source.userPlace.serverID].compactMap { $0 })
    guard ownerID == store.currentUser.id,
          submission.ownerUserID.map({ $0 == ownerID }) ?? true,
          targets.allSatisfy({ $0.ownerID == ownerID }),
          let replacementParent = store.currentUserVisiblePlaces.first(where: {
              $0.userPlace.userID == ownerID && !sourceIDs.isDisjoint(with:
                  Set([$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].compactMap { $0 }))
          })?.userPlace else { return result }
    let replacementIDs = Set([replacementParent.id, replacementParent.localID, replacementParent.serverID].compactMap { $0 })
    guard replacementIDs.contains(result.userPlaceID), replacementIDs.contains(visit.userPlaceID),
          store.visits(for: replacementParent.id).contains(where: { $0.id == visit.id }),
          [.synced, .localOnly, .pendingCreate, .pendingUpdate].contains(result.syncState),
          [.synced, .localOnly, .pendingCreate, .pendingUpdate].contains(visit.syncState) else {
        return warning(result, "Your Wannas Were Kept Because The Check-In Has Not Finished Saving.")
    }
    // Validate the complete immutable set before any deletion. No await occurs
    // between this preflight and local tombstones, so another save cannot enter it.
    guard targets.allSatisfy({ target in
        if target.tombstone(in: store) != nil { return true }
        guard let visible = target.visibleParent(in: store),
              VisiblePlaceGrouping.matches(visible, candidate: submission.candidate,
                  allowingProviderIdentityFallback: true) else { return false }
        if let wannaID = target.wannaID {
            return store.wannaSaves(for: visible.userPlace).contains {
                $0.id == wannaID && $0.occurredAt == target.occurredAt
            }
        }
        return target.isOriginal
            && LivePlaceSaveContinuation.originalWannaDate(for: visible, store: store) == target.occurredAt
    }) else {
        return warning(result, "Your Check-In Was Saved. Your Wannas Changed While Saving, So They Were Kept. You Can Remove Them From Your Map.")
    }

    store.flushPersistence()
    var removedAll = true
    for target in targets where target.tombstone(in: store) == nil {
        guard let parent = target.visibleParent(in: store)?.userPlace,
              store.removeImportedWanna(userPlaceID: parent.id, wannaID: target.wannaID,
                  isOriginal: target.isOriginal, replacementVisitID: visit.localID) else {
            removedAll = false
            continue
        }
    }
    store.flushPersistence()
    if let backend {
        _ = await store.syncPendingWannaSaves(backend: backend)
        guard store.currentUser.id == ownerID else { return result }
        if !removedAll || targets.contains(where: { $0.tombstone(in: store)?.isSynced != true }) {
            return warning(result, "Your Check-In Was Saved. Some Wanna Removals Are Still Pending And Will Retry When Connected.")
        }
    } else if !removedAll {
        return warning(result, "Your Check-In Was Saved, But Some Wannas Could Not Be Removed. You Can Remove Them From Your Map.")
    }
    return result
}

@MainActor
private extension MapPlaceWannaRemovalTarget {
    func visibleParent(in store: WanderStore) -> VisiblePlace? {
        store.currentUserVisiblePlaces.first {
            $0.userPlace.userID == ownerID
                && ([$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].contains(userPlaceID)
                    || userPlaceLocalID == $0.userPlace.localID)
        }
    }

    func tombstone(in store: WanderStore) -> PlaceWannaSave? {
        let parent = store.userPlaces.first {
            $0.userID == ownerID
                && ([$0.id, $0.localID, $0.serverID].contains(userPlaceID) || userPlaceLocalID == $0.localID)
        }
        let ids = Set([userPlaceID, userPlaceLocalID, parent?.id, parent?.localID, parent?.serverID].compactMap { $0 })
        return store.placeWannaSaves.first { wanna in
            wanna.ownerID == ownerID && ids.contains(wanna.userPlaceID) && wanna.deletedAt != nil
                && (wannaID.map { $0 == wanna.id }
                    ?? (isOriginal && wanna.isHistoricalOriginal == true && wanna.occurredAt == occurredAt))
        }
    }
}

private func warning(_ result: SaveResult, _ message: String) -> SaveResult {
    var result = result
    result.localDetailsWarning = [result.localDetailsWarning, message].compactMap { $0 }.joined(separator: "\n\n")
    return result
}

/// Read failure is a pre-submit error, never a successful save warning.
enum MapPlaceWannaHistoryError: LocalizedError {
    case unavailable
    var errorDescription: String? {
        "Your Wanna History Couldn’t Be Checked. Connect And Try Again, Or Turn Off Remove From Wanna To Keep Your Wannas. Your Check-In Has Not Been Saved."
    }
}
