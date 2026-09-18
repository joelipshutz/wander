import Foundation

/// Resolves receipt identities after local saves and list IDs have synced.
/// Destructive changes use the selections captured by the confirmation, never
/// a fresh "latest visit" lookup at commit time.
@MainActor
extension WanderStore {
    func importCandidate(for entry: PlaceImportReceiptEntry, item: PlaceImportItem?) -> PlaceCandidate? {
        guard let item else { return nil }
        if let id = entry.savedSelection?.candidateID,
           let candidate = item.candidates.first(where: { $0.id == id }) { return candidate }
        if let id = entry.userPlaceID,
           let candidate = item.candidates.first(where: { candidate in
               guard let save = existingImportSave(matching: candidate) else { return false }
               return currentUserVisiblePlaces.contains {
                   $0.userPlace.id == save.userPlaceID
                       && [$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].contains(id)
               }
           }) { return candidate }
        return item.selectedCandidates.first(where: { $0.name == entry.displayName })
            ?? item.candidates.first(where: { $0.name == entry.displayName })
    }

    func importVisiblePlace(for entry: PlaceImportReceiptEntry, item: PlaceImportItem?) -> VisiblePlace? {
        if let id = entry.userPlaceID,
           let visible = currentUserVisiblePlaces.first(where: {
               [$0.userPlace.id, $0.userPlace.localID, $0.userPlace.serverID].contains(id)
           }) { return visible }
        guard let candidate = importCandidate(for: entry, item: item) else { return nil }
        return currentUserVisiblePlaces.first { VisiblePlaceGrouping.matches($0, candidate: candidate) }
    }

    func importSelection(for entry: PlaceImportReceiptEntry, item: PlaceImportItem?) -> PlaceImportSavedSelection {
        if let selection = entry.savedSelection { return selection }
        let visible = importVisiblePlace(for: entry, item: item)
        let candidate = importCandidate(for: entry, item: item)
        let status = visible?.userPlace.status ?? entry.status
        let lists = visiblePlaceLists.filter { list in
            if let visible { return hasPlace(visible, in: list) }
            return candidate.map { hasCandidate($0, in: list) } ?? false
        }
        return PlaceImportSavedSelection(
            status: status,
            visitID: status == .been ? visible.flatMap { visits(for: $0.userPlace.id).first?.id } : nil,
            listIDs: Set(lists.map(\.id)), candidateID: candidate?.id
        )
    }

    func importLists(for selection: PlaceImportSavedSelection) -> [LocalPlaceList] {
        visiblePlaceLists.filter {
            !selection.listIDs.isDisjoint(with: [$0.id, $0.localID, $0.serverID].compactMap { $0 })
        }
    }

    /// Create the replacement before removing its predecessor so the shared
    /// place container always has a surviving action. Receipts retain only the
    /// new action; unrelated visits and list memberships are never converted.
    func createImportedSelection(
        entry: PlaceImportReceiptEntry, item: PlaceImportItem, status: PlaceStatus,
        submission: MapPlaceSaveSubmission? = nil
    ) async -> (SaveResult, PlaceImportSavedSelection)? {
        guard let candidate = importCandidate(for: entry, item: item),
              CommunityContentPolicy.allows(submission?.note),
              (submission?.attributes ?? []).allSatisfy({
                  (try? CommunityContentPolicy.validateJSONText($0.valueJSON)) != nil
              }) else { return nil }
        var selection = importSelection(for: entry, item: item)
        let restored = entry.userPlaceID.map { restoreImportPlaceContainer(userPlaceID: $0) } ?? false
        let visible = importVisiblePlace(for: entry, item: item)
        let visibility = submission?.visibility ?? effectiveDefaultVisibility
        let result: SaveResult
        var visit: LocalPlaceVisit?
        if status == .wannaGo {
            let operationID = (submission?.wannaOperationID ?? UUID()).uuidString.lowercased()
            if visible == nil {
                _ = saveCandidate(candidate, status: .wannaGo, visibility: visibility,
                    note: nil, sourceType: item.source.canonicalAddSourceType, attributes: [])
            }
            result = await saveNewWanna(candidate, operationID: operationID, visibility: visibility,
                note: submission?.note, plannedDate: submission?.plannedDate,
                attributes: submission?.attributes ?? [], sourceType: item.source.canonicalAddSourceType, backend: nil)
            guard result.syncState != .failed else { return nil }
            selection.wannaIsOriginal = false
            selection.wannaID = operationID
            if restored || visible == nil {
                // Parent resurrection emits a legacy Wanna event. It is only a
                // container for this new independent action, so queue narrow
                // cleanup after the replacement event has reached the server.
                _ = removeImportedWanna(userPlaceID: result.userPlaceID,
                    wannaID: UUID().uuidString.lowercased(), isOriginal: true)
            }
            selection.visitID = nil
        } else if let visible {
            let projectedWanna = wannaSaves(for: visible.userPlace).first { $0.id == selection.wannaID }
            let replacesSummaryWanna = selection.status == .wannaGo
                && (selection.wannaIsOriginal == true || selection.wannaID == nil
                    || projectedWanna?.occurredAt == visible.userPlace.savedAt)
            guard let newVisit = createVisit(userPlaceID: visible.userPlace.id,
                visitedAt: submission?.visitedAt ?? .now, note: submission?.note,
                ratingScore: submission?.ratingScore, attributes: submission?.attributes ?? [],
                visibility: visibility,
                preservesPriorWanna: !replacesSummaryWanna) else { return nil }
            visit = newVisit
            result = SaveResult(userPlaceID: newVisit.userPlaceID, syncState: newVisit.syncState)
            selection.visitID = newVisit.id
            selection.wannaID = nil
        } else {
            result = saveImportedCandidate(candidate, status: .been, visibility: visibility,
                note: submission?.note, sourceType: item.source.canonicalAddSourceType,
                ratingScore: submission?.ratingScore, visitedAt: submission?.visitedAt ?? .now,
                attributes: submission?.attributes ?? [])
            visit = visits(for: result.userPlaceID).first
            selection.visitID = visit?.id
            selection.wannaID = nil
        }
        selection.status = status
        selection.candidateID = candidate.id
        if let submission {
            await queueSharedVisitInvitees(for: submission, sourceVisit: visit, store: self, backend: nil)
            await persistVisitPhotoAttachments(submission.photoAttachments, to: visit, store: self, backend: nil)
        }
        return (result, selection)
    }

    func removeImportedSelection(
        _ removal: PlaceImportSavedSelectionRemoval,
        entry: PlaceImportReceiptEntry,
        item: PlaceImportItem?
    ) -> Bool {
        let visible = importVisiblePlace(for: entry, item: item)
        let candidate = importCandidate(for: entry, item: item)
        var lists: [LocalPlaceList] = []
        for id in removal.listIDs {
            guard let list = placeLists.first(where: {
                [$0.id, $0.localID, $0.serverID].contains(id)
            }) else { return false }
            if list.deletedAt == nil && !lists.contains(where: { $0.id == list.id }) { lists.append(list) }
        }
        let place = visible?.place ?? candidate.flatMap { candidate in
            places.first { VisiblePlaceGrouping.matches($0, candidate: candidate) }
        }
        // Validate every target before applying any deletion. List membership
        // can outlive the Wanna, so resolve the canonical place independently
        // of the visible-save projection.
        guard lists.isEmpty || place != nil,
              lists.allSatisfy({ canManage($0) }) else { return false }
        if removal.status == .been, removal.visitID == nil { return false }
        for list in lists {
            let isMember = visible.map { hasPlace($0, in: list) }
                ?? candidate.map { hasCandidate($0, in: list) } ?? false
            guard isMember else { continue }
            guard let place,
                  removePlace(placeID: place.id, visiblePlaceID: visible?.id, from: list) else { return false }
        }
        if removal.status == .wannaGo, let visible {
            return removeImportedWanna(userPlaceID: visible.userPlace.id, wannaID: removal.wannaID, isOriginal: removal.wannaIsOriginal)
        }
        if removal.status == .been, let visitID = removal.visitID, let visible {
            // A visit already removed elsewhere is an idempotent success.
            if let visit = visits(for: visible.userPlace.id).first(where: {
                [$0.id, $0.localID, $0.serverID].contains(visitID)
            }) { return deleteImportedVisit(visitID: visit.id) }
        }
        return true
    }
}
