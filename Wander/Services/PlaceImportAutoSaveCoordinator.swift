import Foundation

struct PlaceImportAutoSaveResult: Equatable {
    let batchIDs: [String]
    let addedCount: Int
    let existingCount: Int
    let needsReviewCount: Int

    var savedCount: Int { addedCount + existingCount }
    var hasResult: Bool { savedCount > 0 || needsReviewCount > 0 }
}

enum PlaceImportAutoSavePolicy {
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
            $0.isSelectedForImport
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
        store: WanderStore
    ) async -> PlaceImportAutoSaveResult {
        let orderedIDs = Array(Set(batchIDs)).sorted { lhs, rhs in
            let lhsDate = importStore.batches.first(where: { $0.id == lhs })?.createdAt ?? .distantPast
            let rhsDate = importStore.batches.first(where: { $0.id == rhs })?.createdAt ?? .distantPast
            return lhsDate < rhsDate
        }

        for batchID in orderedIDs {
            await importStore.waitForProcessing(batchID: batchID)
        }
        importStore.reconcileDuplicates(with: existingPlaces(in: store))
        let batchItems = orderedIDs.compactMap { batchID -> (batch: PlaceImportBatch, items: [PlaceImportItem])? in
            guard let batch = importStore.batches.first(where: { $0.id == batchID }) else {
                return nil
            }
            return (batch, importStore.items(for: batchID))
        }
        let allCommittableIDs = PlaceImportAutoSavePolicy.committableItemIDs(
            batchItems: batchItems
        )

        var addedCount = 0
        var existingCount = 0
        var needsReviewCount = 0

        for batchID in orderedIDs {
            guard let batch = importStore.batches.first(where: { $0.id == batchID }),
                  batch.shouldSaveAutomatically
            else { continue }

            let items = importStore.items(for: batchID)
            let committableIDs = allCommittableIDs.intersection(Set(items.map(\.id)))
            let destination = committableIDs.isEmpty
                ? nil
                : destinationList(
                    for: batch,
                    itemCount: items.count,
                    importStore: importStore,
                    store: store
                )
            var entries: [PlaceImportReceiptEntry] = []

            for item in items where committableIDs.contains(item.id) {
                guard let candidate = item.selectedCandidate else { continue }
                let existingSave = MapPlaceSaveContext.currentUserSave(
                    matching: candidate,
                    in: store.currentUserVisiblePlaces
                )
                let result: SaveResult
                if item.state == .duplicate,
                   let existingSave {
                    // An import never rewrites a pre-existing personal memory.
                    // It can still add the place to the imported Google list.
                    result = SaveResult(
                        userPlaceID: existingSave.userPlace.id,
                        syncState: existingSave.userPlace.syncState,
                        placeID: existingSave.place.serverID
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
                if let destination,
                   let visiblePlace = store.currentUserVisiblePlaces.first(where: {
                       $0.userPlace.id == result.userPlaceID
                   }) {
                    _ = await store.addVisiblePlace(visiblePlace, to: destination, backend: nil)
                }
                importStore.markSaved(itemID: item.id, userPlaceID: result.userPlaceID)
                let outcome: PlaceImportReceiptOutcome = existingSave == nil ? .added : .existing
                if outcome == .added { addedCount += 1 } else { existingCount += 1 }
                entries.append(
                    PlaceImportReceiptEntry(
                        itemID: item.id,
                        displayName: item.displayName,
                        displayArea: item.displayArea,
                        status: store.currentUserVisiblePlaces.first(where: {
                            $0.userPlace.id == result.userPlaceID
                        })?.userPlace.status ?? batch.requestedStatus,
                        outcome: outcome,
                        userPlaceID: result.userPlaceID
                    )
                )
            }

            let pending = importStore.items(for: batchID).filter {
                ![.saved, .dismissed].contains($0.state)
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
        }

        return PlaceImportAutoSaveResult(
            batchIDs: orderedIDs,
            addedCount: addedCount,
            existingCount: existingCount,
            needsReviewCount: needsReviewCount
        )
    }

    private static func existingPlaces(in store: WanderStore) -> [PlaceImportExistingPlace] {
        store.currentUserVisiblePlaces.map { visiblePlace in
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
