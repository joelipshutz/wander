import Foundation

struct PlaceImportAutoSaveResult: Equatable {
    let batchIDs: [String]
    let addedCount: Int
    let existingCount: Int
    let needsReviewCount: Int
    let sourceRetryCount: Int

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
            body = "Open rec.me to verify what was saved, review \(needsReviewCount) more, and \(sourceRetryCopy)."
        case (true, false):
            body = "Open rec.me to verify what was saved and review \(needsReviewCount) more."
        case (false, true):
            body = savedCount > 0
                ? "Open rec.me to verify what was saved and \(sourceRetryCopy)."
                : "Open rec.me to \(sourceRetryCopy)."
        case (false, false):
            body = "Open rec.me to verify the places from your import."
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
        let automatic = batchItems.filter { $0.batch.shouldSaveAutomatically }
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
        isAuthorized: @MainActor () -> Bool
    ) async -> PlaceImportAutoSaveResult {
        let orderedIDs = Array(Set(batchIDs)).sorted { lhs, rhs in
            let lhsDate = importStore.batches.first(where: { $0.id == lhs })?.createdAt ?? .distantPast
            let rhsDate = importStore.batches.first(where: { $0.id == rhs })?.createdAt ?? .distantPast
            return lhsDate < rhsDate
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

        return store.performBatchedLocalMutations {
            importStore.performBatchedMutations {
                let visiblePlaces = store.currentUserVisiblePlaces
                let visiblePlacesByUserPlaceID = visiblePlaces.reduce(
                    into: [String: VisiblePlace]()
                ) { result, visiblePlace in
                    result[visiblePlace.userPlace.id] = visiblePlace
                }
                importStore.reconcileDuplicates(
                    with: existingPlaces(from: visiblePlaces)
                )
                let batchItems = orderedIDs.compactMap { batchID -> (batch: PlaceImportBatch, items: [PlaceImportItem])? in
                    guard let batch = importStore.batches.first(where: { $0.id == batchID }) else {
                        return nil
                    }
                    return (batch, importStore.items(for: batchID))
                }
                let allCommittableIDs = PlaceImportAutoSavePolicy.committableItemIDs(
                    batchItems: batchItems
                )

                var completedBatchIDs: [String] = []
                var addedCount = 0
                var existingCount = 0
                var needsReviewCount = 0
                var sourceRetryCount = 0
                var committedUserPlaceIDs = Set<String>()

                for batchID in orderedIDs {
                    guard let batch = importStore.batches.first(where: { $0.id == batchID }),
                          batch.shouldSaveAutomatically
                    else { continue }

                    let items = importStore.items(for: batchID)
                    let placeItems = items.filter { !$0.isSourceRetry }
                    let batchSourceRetryCount = items.filter {
                        $0.isSourceRetry && ![.saved, .dismissed].contains($0.state)
                    }.count
                    sourceRetryCount += batchSourceRetryCount
                    let committableIDs = allCommittableIDs.intersection(Set(placeItems.map(\.id)))
                    let destination = committableIDs.isEmpty
                        ? nil
                        : destinationList(
                            for: batch,
                            itemCount: placeItems.count,
                            importStore: importStore,
                            store: store
                        )
                    var entries: [PlaceImportReceiptEntry] = []

                    for item in items where committableIDs.contains(item.id) {
                        guard let candidate = item.selectedCandidate else { continue }
                        let reconciledExistingSave = item.duplicateUserPlaceID.flatMap {
                            visiblePlacesByUserPlaceID[$0]
                        }.map {
                            ExistingImportSave(
                                userPlaceID: $0.userPlace.id,
                                status: $0.userPlace.status,
                                syncState: $0.userPlace.syncState,
                                placeID: $0.place.serverID
                            )
                        }
                        // Use the exact same identity matcher as the save path.
                        // Reconciliation is UI-oriented and intentionally looser;
                        // it must never decide whether a prior memory can be deleted.
                        let existingSave = store.existingImportSave(matching: candidate)
                            ?? reconciledExistingSave
                        let upgradesExistingWanna = existingSave?.status == .wannaGo
                            && batch.requestedStatus == .been
                        let result: SaveResult
                        if let existingSave, !upgradesExistingWanna {
                            // An import never rewrites a pre-existing personal memory.
                            // It can still add the place to the imported Google list.
                            result = SaveResult(
                                userPlaceID: existingSave.userPlaceID,
                                syncState: existingSave.syncState,
                                placeID: existingSave.placeID
                            )
                        } else {
                            result = store.saveImportedCandidate(
                                candidate,
                                status: batch.requestedStatus,
                                visibility: .selfOnly,
                                note: item.stagedNote,
                                sourceType: item.source.addSourceType,
                                ratingScore: batch.requestedStatus == .been
                                    ? (item.stagedRatingScore ?? batch.requestedRatingScore)
                                    : nil,
                                visitedAt: item.stagedVisitedAt ?? .now
                            )
                        }
                        if let destination {
                            _ = store.addCurrentUserPlace(
                                userPlaceID: result.userPlaceID,
                                to: destination
                            )
                        }
                        importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
                        let wasAddedByThisItem = existingSave == nil
                            && committedUserPlaceIDs.insert(result.userPlaceID).inserted
                        let outcome: PlaceImportReceiptOutcome = wasAddedByThisItem ? .added : .existing
                        if outcome == .added { addedCount += 1 } else { existingCount += 1 }
                        entries.append(
                            PlaceImportReceiptEntry(
                                itemID: item.id,
                                displayName: item.displayName,
                                displayArea: item.displayArea,
                                status: upgradesExistingWanna
                                    ? .been
                                    : (existingSave?.status ?? batch.requestedStatus),
                                outcome: outcome,
                                userPlaceID: result.userPlaceID
                            )
                        )
                    }

                    let pending = importStore.items(for: batchID).filter {
                        !$0.isSourceRetry && ![.saved, .dismissed].contains($0.state)
                    }
                    needsReviewCount += pending.count
                    entries.append(contentsOf: pending.map { item in
                        PlaceImportReceiptEntry(
                            itemID: item.id,
                            displayName: item.displayName,
                            displayArea: item.displayArea,
                            status: item.state == .ready ? item.stagedStatus : nil,
                            outcome: .needsReview,
                            userPlaceID: item.duplicateUserPlaceID
                        )
                    })

                    importStore.recordReceipt(
                        batchID: batchID,
                        entries: entries,
                        destinationListID: destination?.id
                    )
                    importStore.markAutomaticSaveCompleted(batchID: batchID)
                    completedBatchIDs.append(batchID)
                }

                return PlaceImportAutoSaveResult(
                    batchIDs: completedBatchIDs,
                    addedCount: addedCount,
                    existingCount: existingCount,
                    needsReviewCount: needsReviewCount,
                    sourceRetryCount: sourceRetryCount
                )
            }
        }
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
        itemCount: Int,
        importStore: PlaceImportStore,
        store: WanderStore
    ) -> LocalPlaceList? {
        guard batch.source == .googleMaps,
              batch.sourceName != nil || itemCount > 1
        else { return nil }
        if let listID = batch.destinationListID,
           let existing = store.visiblePlaceLists.first(where: { $0.id == listID }) {
            return existing
        }
        let existingNames = Set(
            store.visiblePlaceLists
                .filter { $0.ownerUserID == store.currentUser.id }
                .map(\.name)
        )
        let name = PlaceImportDestinationListName.unique(
            batch.sourceName,
            existingNames: existingNames
        )
        guard let list = store.createPlaceList(
            name: name,
            description: "Imported from Google Maps",
            visibility: .stealth
        ) else { return nil }
        importStore.setDestinationListID(list.id, batchID: batch.id)
        return list
    }
}
