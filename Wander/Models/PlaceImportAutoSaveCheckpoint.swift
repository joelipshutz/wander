import Foundation

/// Local recovery evidence written atomically with the library rows it names.
/// Import-file progress can be replayed without saving rows again or changing
/// their original Added outcomes into Existing after a restart.
struct PlaceImportAutoSaveCheckpoint: Codable, Equatable, Identifiable {
    let id: String
    let ownerUserID: String
    let batchID: String
    let batchCreatedAt: Date
    let notificationImportID: String
    let receiptID: String
    let receiptCreatedAt: Date
    let eligibleItemIDs: [String]
    let plannedItems: [PlaceImportAutoSavePlannedItem]
    let requestedStatus: PlaceStatus
    let requestedRatingScore: Double?
    var destinationListID: String?
    var completedItems: [PlaceImportAutoSaveCompletedItem]
    var isComplete: Bool

    init(ownerUserID: String, batch: PlaceImportBatch, eligibleItemIDs: [String], items: [PlaceImportItem] = []) {
        id = UUID().uuidString.lowercased()
        self.ownerUserID = ownerUserID
        batchID = batch.id
        batchCreatedAt = PlaceImportAutoSaveWireDate.normalized(batch.createdAt)
        notificationImportID = batch.notificationImportID
        receiptID = UUID().uuidString.lowercased()
        receiptCreatedAt = PlaceImportAutoSaveWireDate.normalized(.now)
        self.eligibleItemIDs = eligibleItemIDs
        let eligible = Set(eligibleItemIDs)
        plannedItems = items.compactMap { item in
            guard eligible.contains(item.id), let candidate = item.selectedCandidate else { return nil }
            return PlaceImportAutoSavePlannedItem(item: item, candidate: candidate)
        }
        requestedStatus = batch.requestedStatus
        requestedRatingScore = batch.requestedRatingScore
        destinationListID = batch.destinationListID
        completedItems = []
        isComplete = false
    }

    func belongs(to batch: PlaceImportBatch, ownerUserID: String) -> Bool {
        self.ownerUserID == ownerUserID && batchID == batch.id
            && batchCreatedAt == PlaceImportAutoSaveWireDate.normalized(batch.createdAt)
            && notificationImportID == batch.notificationImportID
    }

    func matchesPlannedInput(_ item: PlaceImportItem) -> Bool {
        plannedItems.first { $0.itemID == item.id }?.matches(item) == true
    }
}

/// A frozen automatic intent. User edits remain review work after a pause;
/// automatic duplicate bookkeeping may change without changing this input.
struct PlaceImportAutoSavePlannedItem: Codable, Equatable {
    let itemID: String
    let seed: PlaceImportSeed
    let candidate: PlaceCandidate
    let selectedCandidateIDs: [String]
    let stagedStatus: PlaceStatus
    let stagedNote: String?
    let stagedRatingScore: Double?
    let stagedVisitedAt: Date?

    init(item: PlaceImportItem, candidate: PlaceCandidate) {
        itemID = item.id
        seed = Self.saveIntentSeed(item.seed)
        self.candidate = candidate
        selectedCandidateIDs = item.selectedCandidateIDs
        stagedStatus = item.stagedStatus
        stagedNote = item.stagedNote
        stagedRatingScore = item.stagedRatingScore
        stagedVisitedAt = item.stagedVisitedAt.map(PlaceImportAutoSaveWireDate.normalized)
    }

    func matches(_ item: PlaceImportItem) -> Bool {
        item.id == itemID && Self.saveIntentSeed(item.seed) == seed && item.selectedCandidate == candidate
            && item.selectedCandidateIDs == selectedCandidateIDs && item.isSelectedForImport
            && item.stagedStatus == stagedStatus && item.stagedNote == stagedNote
            && item.stagedRatingScore == stagedRatingScore
            && item.stagedVisitedAt.map(PlaceImportAutoSaveWireDate.normalized) == stagedVisitedAt
            && [.ready, .duplicate].contains(item.state)
    }

    private static func saveIntentSeed(_ seed: PlaceImportSeed) -> PlaceImportSeed {
        var result = seed
        // A late source-preview image changes presentation only. It must not
        // turn otherwise unchanged automatic save intent into review work.
        result.sourceThumbnailURLString = nil
        return result
    }
}

struct PlaceImportAutoSaveCompletedItem: Codable, Equatable {
    let itemID: String
    let itemUpdatedAt: Date
    let seedID: String
    let candidateID: String
    let entry: PlaceImportReceiptEntry

    init(item: PlaceImportItem, candidate: PlaceCandidate, entry: PlaceImportReceiptEntry) {
        itemID = item.id
        itemUpdatedAt = PlaceImportAutoSaveWireDate.normalized(item.updatedAt)
        seedID = item.seed.id
        candidateID = candidate.id
        self.entry = entry
    }
}

enum PlaceImportAutoSaveWireDate {
    /// FilePlaceImportPersistence uses JSONEncoder.iso8601, which omits
    /// fractional seconds. Floor also handles dates before the Unix epoch.
    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

struct PlaceImportAutoSaveLease: Equatable {
    let id: UUID
    let ownerUserID: String
    let batchID: String
    let batchCreatedAt: Date
}

struct PlaceImportAutoSaveChunkPolicy {
    let maximumRows: Int
    let budgetSeconds: TimeInterval

    init(maximumRows: Int = 8, budgetSeconds: TimeInterval = 0.010) {
        self.maximumRows = max(1, maximumRows)
        self.budgetSeconds = max(0, budgetSeconds)
    }
}
