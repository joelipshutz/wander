import Foundation

struct PlaceImportAutoSaveResult: Equatable {
    let batchIDs: [String]
    let addedCount: Int
    let existingCount: Int
    let needsReviewCount: Int
    let sourceRetryCount: Int
    var retryBatchIDs: [String] = []

    var savedCount: Int { addedCount + existingCount }
    var hasResult: Bool { savedCount > 0 || needsReviewCount > 0 || sourceRetryCount > 0 }
}

struct PlaceImportFinishedNotificationCopy: Equatable {
    let title: String
    let body: String

    static func make(
        savedCount: Int,
        needsReviewCount: Int,
        sourceRetryCount: Int
    ) -> PlaceImportFinishedNotificationCopy {
        let sourceRetryCopy = sourceRetryCount == 1
            ? "retry the incomplete source scan"
            : "retry \(sourceRetryCount) incomplete source scans"
        let title: String
        if savedCount == 0 {
            if sourceRetryCount > 0, needsReviewCount == 0 {
                title = sourceRetryCount == 1
                    ? "Your source scan needs a retry"
                    : "\(sourceRetryCount) source scans need a retry"
            } else {
                title = "Your import needs a quick review"
            }
        } else {
            title = savedCount == 1
                ? "1 place saved"
                : "\(savedCount) places saved"
        }

        let body: String
        switch (needsReviewCount > 0, sourceRetryCount > 0) {
        case (true, true):
            body = "Open Astir to verify what was saved, review \(needsReviewCount) more, and \(sourceRetryCopy)."
        case (true, false):
            body = "Open Astir to verify what was saved and review \(needsReviewCount) more."
        case (false, true):
            body = savedCount > 0
                ? "Open Astir to verify what was saved and \(sourceRetryCopy)."
                : "Open Astir to \(sourceRetryCopy)."
        case (false, false):
            body = "Open Astir to verify the places from your import."
        }
        return PlaceImportFinishedNotificationCopy(title: title, body: body)
    }
}

enum PlaceImportAutoSavePolicy {
    static func pendingVerificationBatchIDs(
        in batches: [PlaceImportBatch]
    ) -> [String] {
        batches
            .filter { batch in
                batch.automaticSaveCompletedAt != nil
                    && batch.receipt?.presentedAt == nil
                    && batch.receipt?.hasContent == true
            }
            .sorted { $0.createdAt < $1.createdAt }
            .map(\.id)
    }

    static func committableItemIDs(
        batchItems: [(batch: PlaceImportBatch, items: [PlaceImportItem])]
    ) -> Set<String> {
        let automatic = batchItems.filter {
            $0.batch.shouldSaveAutomatically && $0.batch.state != .cancelled
        }
        let captures = Dictionary(grouping: automatic) { pair in
            captureID(for: pair.batch)
        }
        var committable = Set<String>()
        for capture in captures.values {
            committable.formUnion(
                capture
                    .filter { $0.batch.requestedStatus == .wannaGo }
                    .flatMap { confidentItems(in: $0.items).map(\.id) }
            )
            let checkInCandidates = capture
                .filter { $0.batch.requestedStatus == .been }
                .flatMap { confidentItems(in: $0.items) }
            if checkInCandidates.count == 1, let item = checkInCandidates.first {
                committable.insert(item.id)
            }
        }
        return committable
    }

    private static func captureID(for batch: PlaceImportBatch) -> String {
        guard let deliveryID = batch.captureDeliveryID,
              let separator = deliveryID.lastIndex(of: ":")
        else { return batch.id }
        return String(deliveryID[..<separator])
    }

    private static func confidentItems(in items: [PlaceImportItem]) -> [PlaceImportItem] {
        items.filter {
            !$0.isSourceRetry
                && $0.isSelectedForImport
                && (($0.state == .ready && $0.selectedCandidate != nil)
                    || ($0.state == .duplicate && $0.duplicateUserPlaceID != nil))
        }
    }
}

@MainActor
enum PlaceImportAutoSaveCoordinator {
    static func process(
        batchIDs: [String],
        importStore: PlaceImportStore,
        store: WanderStore,
        expectedUserID: String,
        chunkPolicy: PlaceImportAutoSaveChunkPolicy = .init(),
        afterLibraryCheckpoint: (@MainActor () throws -> Void)? = nil,
        betweenChunks: (@MainActor () async -> Void)? = nil,
        isAuthorized: @MainActor () -> Bool
    ) async -> PlaceImportAutoSaveResult {
        let orderedIDs = Array(Set(batchIDs)).sorted { lhs, rhs in
            let lhsDate = importStore.batches.first(where: { $0.id == lhs })?.createdAt ?? .distantPast
            let rhsDate = importStore.batches.first(where: { $0.id == rhs })?.createdAt ?? .distantPast
            return lhsDate == rhsDate ? lhs < rhs : lhsDate < rhsDate
        }
        for batchID in orderedIDs {
            guard canContinue(expectedUserID: expectedUserID, store: store, isAuthorized: isAuthorized) else {
                return emptyResult
            }
            await importStore.waitForProcessing(batchID: batchID)
        }
        guard canContinue(expectedUserID: expectedUserID, store: store, isAuthorized: isAuthorized) else {
            return emptyResult
        }
        guard let projectionContext = store.makeAutomaticImportProjectionContext(ownerUserID: expectedUserID) else {
            return emptyResult
        }
        defer { projectionContext.finish() }

        var leases: [String: PlaceImportAutoSaveLease] = [:]
        for batchID in orderedIDs {
            leases[batchID] = importStore.beginAutomaticSaveLease(batchID: batchID, ownerUserID: expectedUserID)
        }
        defer { for lease in leases.values { importStore.endAutomaticSaveLease(lease) } }
        func owns(_ lease: PlaceImportAutoSaveLease) -> Bool {
            canContinue(expectedUserID: expectedUserID, store: store, isAuthorized: isAuthorized)
                && importStore.ownsAutomaticSaveLease(lease)
        }
        var completedBatchIDs: [String] = []
        func result() -> PlaceImportAutoSaveResult {
            let receipts = completedBatchIDs.compactMap { id in
                importStore.batches.first { $0.id == id }?.receipt
            }
            let retryIDs = canContinue(expectedUserID: expectedUserID, store: store, isAuthorized: isAuthorized)
                ? orderedIDs.filter { id in
                    leases[id].map { importStore.canRetryAutomaticSave(after: $0) } == true
                } : []
            return PlaceImportAutoSaveResult(batchIDs: completedBatchIDs,
                addedCount: receipts.reduce(0) { $0 + $1.addedCount },
                existingCount: receipts.reduce(0) { $0 + $1.existingCount },
                needsReviewCount: receipts.reduce(0) { $0 + $1.needsReviewCount },
                sourceRetryCount: receipts.reduce(0) { $0 + $1.sourceRetryCount },
                retryBatchIDs: retryIDs)
        }

        // A previous library write may have succeeded while its import-file
        // projection failed. Confirm the exact library snapshot before replay.
        let recoveries = orderedIDs.compactMap { batchID -> PlaceImportAutoSaveCheckpoint? in
            guard let lease = leases[batchID], owns(lease),
                  let batch = importStore.batches.first(where: { $0.id == batchID }),
                  let checkpoint = store.automaticImportCheckpoint(ownerUserID: expectedUserID, batchID: batchID),
                  checkpoint.belongs(to: batch, ownerUserID: expectedUserID) else { return nil }
            return checkpoint
        }
        if !recoveries.isEmpty {
            do { try await store.commitAutomaticImportCheckpointDurablyAsync() }
            catch {
                if recoveries.contains(where: { checkpoint in
                    leases[checkpoint.batchID].map(owns) == true
                }) {
                    importStore.reportAutomaticSaveCheckpointFailure()
                }
                return result()
            }
            for checkpoint in recoveries {
                guard let lease = leases[checkpoint.batchID], owns(lease) else { continue }
                guard importStore.applyAutomaticSaveCheckpoint(checkpoint, lease: lease) else { return result() }
                if checkpoint.isComplete {
                    store.retireCompletedAutomaticImportCheckpoint(checkpoint)
                    completedBatchIDs.append(checkpoint.batchID)
                }
            }
        }
        guard leases.values.contains(where: owns) else { return result() }

        importStore.reconcileDuplicates(with: existingPlaces(from: store.currentUserVisiblePlaces))
        let batchItems = orderedIDs.compactMap { id -> (batch: PlaceImportBatch, items: [PlaceImportItem])? in
            guard let lease = leases[id], owns(lease), let batch = importStore.batches.first(where: { $0.id == id }) else { return nil }
            return (batch, importStore.items(for: id))
        }
        let eligibleIDs = PlaceImportAutoSavePolicy.committableItemIDs(batchItems: batchItems)
        var newPlans: [PlaceImportAutoSaveCheckpoint] = []
        for pair in batchItems where store.automaticImportCheckpoint(ownerUserID: expectedUserID, batchID: pair.batch.id) == nil {
            newPlans.append(PlaceImportAutoSaveCheckpoint(ownerUserID: expectedUserID, batch: pair.batch,
                eligibleItemIDs: pair.items.filter { eligibleIDs.contains($0.id) }.map(\.id), items: pair.items))
        }

        var committedUserPlaceIDs = Set(recoveries.flatMap(\.completedItems)
            .filter { $0.entry.outcome == .added }.compactMap(\.entry.userPlaceID))
        var recordedNewPlans = false
        for batchID in orderedIDs where !completedBatchIDs.contains(batchID) {
            guard let lease = leases[batchID], owns(lease),
                  let initialBatch = importStore.batches.first(where: { $0.id == batchID }),
                  var checkpoint = store.automaticImportCheckpoint(ownerUserID: expectedUserID, batchID: batchID)
                    ?? newPlans.first(where: { $0.batchID == batchID }),
                  checkpoint.belongs(to: initialBatch, ownerUserID: expectedUserID) else { continue }
            let plannedInputs = Dictionary(checkpoint.plannedItems.map { ($0.itemID, $0) },
                uniquingKeysWith: { first, _ in first })
            while owns(lease) {
                guard let batch = importStore.batches.first(where: { $0.id == batchID }) else { break }
                let completedIDs = Set(checkpoint.completedItems.map(\.itemID))
                let overriddenIDs = Set(batch.automaticSaveReceiptOverrideItemIDs ?? [])
                let plannedIDs = Set(checkpoint.eligibleItemIDs).subtracting(completedIDs).subtracting(overriddenIDs)
                let manualOverrides = manualSaveOverrides(in: batch, checkpoint: checkpoint)
                // Inspect only enough matching rows for this chunk plus one
                // lookahead. Revalidating every remaining seed each time makes
                // a large import needlessly repeat the same comparisons.
                let rowLimit = min(chunkPolicy.maximumRows, Int.max - 1) + 1
                let plannedRows = Array(importStore.items(for: batchID).lazy.filter { item in
                    plannedIDs.contains(item.id) && isCommittable(item) && plannedInputs[item.id]?.matches(item) == true
                        && !manualOverrides.contains { adjustment in
                            adjustment.selection.status != checkpoint.requestedStatus
                                && matches(adjustment, candidate: item.selectedCandidate, store: store)
                        }
                }.prefix(rowLimit))
                // A changed batch intent must not replace completed outcomes or
                // silently apply the old intent to the remaining rows.
                let changedIntent = checkpoint.requestedStatus != batch.requestedStatus
                    || checkpoint.requestedRatingScore != batch.requestedRatingScore
                let changedDestination = batch.automaticSaveDestinationOverrideID.map { selectedID in
                    guard let plannedID = checkpoint.destinationListID else { return true }
                    return selectedID != plannedID && !store.visiblePlaceLists.contains { list in
                        let aliases = [list.id, list.localID, list.serverID]
                        return aliases.contains(selectedID) && aliases.contains(plannedID)
                    }
                } ?? false
                let lostDestination = checkpoint.destinationListID != nil && !checkpoint.completedItems.isEmpty
                    && !store.visiblePlaceLists.contains {
                        [$0.id, $0.localID, $0.serverID].contains(checkpoint.destinationListID)
                            && store.canAddPlaces(to: $0)
                    }
                do {
                    try await store.performCheckpointedImportMutationsAsync(using: projectionContext) {
                        // Freeze every capture's original eligibility together
                        // with the first chunk, including ineligible Been rows.
                        if !recordedNewPlans {
                            for plan in newPlans {
                                if store.automaticImportCheckpoint(ownerUserID: expectedUserID, batchID: plan.batchID) == nil {
                                    store.recordAutomaticImportCheckpoint(plan)
                                }
                            }
                            recordedNewPlans = true
                        }
                        if !changedIntent && !changedDestination && !lostDestination && !plannedRows.isEmpty {
                            let destination = destinationList(for: batch, checkpoint: checkpoint, store: store)
                            checkpoint.destinationListID = destination?.id
                            if checkpoint.completedItems.isEmpty {
                                let policy = store.beginImportNotificationCommit(batch, silent: true,
                                    selectedItemIDs: Set(checkpoint.eligibleItemIDs))
                                store.completeImportNotificationCommit(policy)
                            }
                            let started = ProcessInfo.processInfo.systemUptime
                            var processedRows = 0
                            store.withBatchedCurrentUserPlaceListInsertions(to: destination,
                                senderNotificationPolicy: .silent, using: projectionContext) { insert in
                                for planned in plannedRows {
                                    guard owns(lease), let item = importStore.item(id: planned.id),
                                          isCommittable(item), plannedInputs[item.id]?.matches(item) == true,
                                          let candidate = item.selectedCandidate else { break }
                                    let matchingOverrides = manualOverrides.filter {
                                        matches($0, candidate: candidate, store: store)
                                    }
                                    guard !matchingOverrides.contains(where: {
                                        $0.selection.status != checkpoint.requestedStatus
                                    }) else { continue }
                                    let existing = store.existingImportSave(matching: candidate)
                                        ?? item.duplicateUserPlaceID.flatMap { store.existingImportSave(userPlaceID: $0) }
                                    let upgrades = existing?.status == .wannaGo && batch.requestedStatus == .been
                                    let saved: SaveResult
                                    if let existing, !upgrades {
                                        saved = SaveResult(userPlaceID: existing.userPlaceID,
                                            syncState: existing.syncState, placeID: existing.placeID)
                                    } else {
                                        saved = store.saveImportedCandidate(candidate, status: batch.requestedStatus,
                                            visibility: .selfOnly, note: item.stagedNote, sourceType: item.source.addSourceType,
                                            ratingScore: batch.requestedStatus == .been
                                                ? (item.stagedRatingScore ?? batch.requestedRatingScore) : nil,
                                            visitedAt: item.stagedVisitedAt ?? .now)
                                    }
                                    if let destination, !matchingOverrides.contains(where: {
                                        $0.selection.listIDs.isDisjoint(with:
                                            [destination.id, destination.localID, destination.serverID].compactMap { $0 })
                                    }) { _ = insert(saved.userPlaceID) }
                                    let wasAdded = existing == nil && committedUserPlaceIDs.insert(saved.userPlaceID).inserted
                                    let outcome: PlaceImportReceiptOutcome = wasAdded ? .added : .existing
                                    let entry = PlaceImportReceiptEntry(itemID: item.id, displayName: item.displayName,
                                        displayArea: item.displayArea,
                                        status: upgrades ? .been : (existing?.status ?? batch.requestedStatus),
                                        outcome: outcome, userPlaceID: saved.userPlaceID)
                                    checkpoint.completedItems.append(PlaceImportAutoSaveCompletedItem(
                                        item: item, candidate: candidate, entry: entry))
                                    processedRows += 1
                                    if processedRows >= chunkPolicy.maximumRows
                                        || ProcessInfo.processInfo.systemUptime - started >= chunkPolicy.budgetSeconds { break }
                                }
                            }
                        }
                        let finishedIDs = Set(checkpoint.completedItems.map(\.itemID))
                        checkpoint.isComplete = changedIntent || changedDestination || lostDestination
                            || !plannedRows.contains { !finishedIDs.contains($0.id) }
                        store.recordAutomaticImportCheckpoint(checkpoint)
                    }
                    try afterLibraryCheckpoint?()
                } catch {
                    if owns(lease) {
                        importStore.reportAutomaticSaveCheckpointFailure()
                    }
                    return result()
                }
                // No deferred persistence or lookup/list projection survives the
                // awaited writer acknowledgement. Every mutable owner is fresh.
                guard owns(lease) else { return result() }
                guard importStore.applyAutomaticSaveCheckpoint(checkpoint, lease: lease) else { return result() }
                if checkpoint.isComplete {
                    store.retireCompletedAutomaticImportCheckpoint(checkpoint)
                    completedBatchIDs.append(batchID)
                    break
                }
                if let betweenChunks { await betweenChunks() } else { await Task.yield() }
            }
            if let betweenChunks { await betweenChunks() } else { await Task.yield() }
        }
        return result()
    }

    private static func isCommittable(_ item: PlaceImportItem) -> Bool {
        !item.isSourceRetry && item.isSelectedForImport && item.selectedCandidate != nil
            && (item.state == .ready || (item.state == .duplicate && item.duplicateUserPlaceID != nil))
    }

    private struct ManualSaveOverride {
        let originalUserPlaceID: String
        let currentUserPlaceID: String
        let selection: PlaceImportSavedSelection
    }

    private static func manualSaveOverrides(in batch: PlaceImportBatch,
                                            checkpoint: PlaceImportAutoSaveCheckpoint) -> [ManualSaveOverride] {
        let overriddenIDs = Set(batch.automaticSaveReceiptOverrideItemIDs ?? [])
        guard !overriddenIDs.isEmpty else { return [] }
        let entries = Dictionary(grouping: batch.receipt?.entries ?? [], by: \.itemID)
        return checkpoint.completedItems.flatMap { completed -> [ManualSaveOverride] in
            guard overriddenIDs.contains(completed.itemID),
                  let originalID = completed.entry.userPlaceID else { return [] }
            return (entries[completed.itemID] ?? []).compactMap { entry in
                guard let currentID = entry.userPlaceID, let selection = entry.savedSelection else { return nil }
                return ManualSaveOverride(originalUserPlaceID: originalID, currentUserPlaceID: currentID,
                    selection: selection)
            }
        }
    }

    private static func matches(_ adjustment: ManualSaveOverride, candidate: PlaceCandidate?, store: WanderStore) -> Bool {
        guard let candidate, store.importCandidate(candidate, matchesUserPlaceID: adjustment.originalUserPlaceID) else {
            return false
        }
        return adjustment.currentUserPlaceID == adjustment.originalUserPlaceID
            || store.importCandidate(candidate, matchesUserPlaceID: adjustment.currentUserPlaceID)
    }

    private static var emptyResult: PlaceImportAutoSaveResult {
        PlaceImportAutoSaveResult(
            batchIDs: [],
            addedCount: 0,
            existingCount: 0,
            needsReviewCount: 0,
            sourceRetryCount: 0
        )
    }

    private static func canContinue(
        expectedUserID: String,
        store: WanderStore,
        isAuthorized: @MainActor () -> Bool
    ) -> Bool {
        PlaceImportCommitAuthorization.isValid(
            expectedUserID: expectedUserID,
            authUserID: isAuthorized() ? expectedUserID : nil,
            currentUserID: store.currentUser.id,
            isCancelled: Task.isCancelled
        )
    }

    private static func existingPlaces(
        from visiblePlaces: [VisiblePlace]
    ) -> [PlaceImportExistingPlace] {
        visiblePlaces.map { visiblePlace in
            PlaceImportExistingPlace(
                userPlaceID: visiblePlace.userPlace.id,
                name: visiblePlace.place.canonicalName,
                latitude: visiblePlace.place.latitude,
                longitude: visiblePlace.place.longitude,
                sourceProvider: visiblePlace.place.sourceProvider,
                sourceProviderPlaceID: visiblePlace.place.sourceProviderPlaceID
            )
        }
    }

    private static func destinationList(
        for batch: PlaceImportBatch,
        checkpoint: PlaceImportAutoSaveCheckpoint,
        store: WanderStore
    ) -> LocalPlaceList? {
        guard batch.source == .googleMaps,
              let sourceListName = batch.sourceListName
        else { return nil }
        if let listID = checkpoint.destinationListID ?? batch.destinationListID,
           let existing = store.visiblePlaceLists.first(where: { [$0.id, $0.localID, $0.serverID].contains(listID) }) {
            return existing
        }
        let existingNames = Set(
            store.visiblePlaceLists
                .filter { $0.ownerUserID == store.currentUser.id }
                .map(\.name)
        )
        let name = PlaceImportDestinationListName.unique(
            sourceListName,
            existingNames: existingNames
        )
        guard let list = store.createPlaceList(
            name: name,
            description: "Imported from Google Maps",
            visibility: .stealth
        ) else { return nil }
        return list
    }
}
