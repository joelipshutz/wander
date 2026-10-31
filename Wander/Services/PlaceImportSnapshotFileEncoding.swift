import Foundation
import Darwin

/// Reuses only byte encodings of identical immutable rows. Each prepared value
/// is still a complete ordinary JSON snapshot for the existing file reader.
final class PlaceImportSnapshotFileEncoding {
    struct PreparedSnapshot {
        let data: Data
        let encodedItemCount: Int
        let reusedItemCount: Int
        fileprivate let ownerUserID: String?
        fileprivate let version: Int
        fileprivate let cachedItems: [CachedItem]
        fileprivate let cachedByteCount: Int
        fileprivate let prefersGroupedProcessingCheckpoints: Bool
    }

    fileprivate struct CachedItem {
        let value: PlaceImportItem
        let data: Data
    }

    private let maximumCachedItems: Int
    private let maximumCachedBytes: Int
    private var ownerUserID: String?
    private var version: Int?
    private var cachedItems: [CachedItem] = []
    private(set) var cachedByteCount = 0
    private(set) var prefersGroupedProcessingCheckpoints = false
    var cachedItemCount: Int { cachedItems.count }

    init(maximumCachedItems: Int = 4_096, maximumCachedBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumCachedItems = max(0, maximumCachedItems)
        self.maximumCachedBytes = max(0, maximumCachedBytes)
    }

    func prepare(_ snapshot: PlaceImportSnapshot) throws -> PreparedSnapshot {
        if !Self.sameText(ownerUserID, snapshot.ownerUserID) || version != snapshot.version {
            // A failed write for a new account must not retain the old account's
            // row values in this encoder. No asynchronously queued work exists.
            cachedItems.removeAll()
            cachedByteCount = 0
            ownerUserID = snapshot.ownerUserID
            version = snapshot.version
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard snapshot.items.count <= maximumCachedItems, maximumCachedBytes > 0 else {
            return PreparedSnapshot(data: try encoder.encode(snapshot),
                encodedItemCount: snapshot.items.count, reusedItemCount: 0,
                ownerUserID: snapshot.ownerUserID, version: snapshot.version,
                cachedItems: [], cachedByteCount: 0, prefersGroupedProcessingCheckpoints: true)
        }

        // Keep these root fields aligned with PlaceImportSnapshot. All variable
        // values, including batches/receipts, are encoded by JSONEncoder; only
        // the fixed object/array punctuation is assembled here. Schema parity
        // tests compare the complete document with the ordinary snapshot encoder.
        let encodedBatches = try encoder.encode(snapshot.batches)
        var data = Data()
        data.reserveCapacity(cachedByteCount + encodedBatches.count + snapshot.items.count + 128)
        data.append(contentsOf: #"{"batches":"#.utf8)
        data.append(encodedBatches)
        data.append(contentsOf: #","items":["#.utf8)
        var nextCache: [CachedItem] = []
        nextCache.reserveCapacity(snapshot.items.count)
        var nextByteCount = 0
        var encodedItemCount = 0
        var reusedItemCount = 0
        var cacheFits = true
        for (index, item) in snapshot.items.enumerated() {
            if index > 0 { data.append(44) }
            let encoded: Data
            if index < cachedItems.count, Self.hasSameEncoding(cachedItems[index].value, item) {
                encoded = cachedItems[index].data
                reusedItemCount += 1
            } else {
                encoded = try encoder.encode(item)
                encodedItemCount += 1
            }
            data.append(encoded)
            if cacheFits, encoded.count <= maximumCachedBytes - nextByteCount {
                nextByteCount += encoded.count
                nextCache.append(CachedItem(value: item, data: encoded))
            } else if cacheFits {
                // Oversized snapshots are written in full but retain no row
                // cache. A partial cache must not shift positional identities.
                nextCache.removeAll()
                nextByteCount = 0
                cacheFits = false
            }
        }
        data.append(93)
        if let ownerUserID = snapshot.ownerUserID {
            data.append(contentsOf: #","ownerUserID":"#.utf8)
            data.append(try encoder.encode(ownerUserID))
        }
        data.append(contentsOf: #","version":"#.utf8)
        data.append(try encoder.encode(snapshot.version))
        data.append(125)
        return PreparedSnapshot(data: data, encodedItemCount: encodedItemCount,
            reusedItemCount: reusedItemCount, ownerUserID: snapshot.ownerUserID,
            version: snapshot.version, cachedItems: nextCache, cachedByteCount: nextByteCount,
            prefersGroupedProcessingCheckpoints: !cacheFits || data.count > maximumCachedBytes)
    }

    /// Called only after the full atomic file write succeeds. A failed encode or
    /// write cannot make an unpersisted row the source of the next cache hit.
    func didPersist(_ prepared: PreparedSnapshot) {
        ownerUserID = prepared.ownerUserID
        version = prepared.version
        cachedItems = prepared.cachedItems
        cachedByteCount = prepared.cachedByteCount
        prefersGroupedProcessingCheckpoints = prepared.prefersGroupedProcessingCheckpoints
    }

    /// Equatable covers all fields, but Unicode canonical equivalence and signed
    /// zero can compare equal while JSON encodes different scalar values. Keep
    /// their exact representations too; dates with equal values encode alike.
    private static func hasSameEncoding(_ lhs: PlaceImportItem, _ rhs: PlaceImportItem) -> Bool {
        guard lhs == rhs else { return false }
        return sameText(lhs.id, rhs.id) && sameText(lhs.batchID, rhs.batchID)
            && sameText(lhs.selectedCandidateID, rhs.selectedCandidateID)
            && sameTexts(lhs.selectedCandidateIDsRaw, rhs.selectedCandidateIDsRaw)
            && sameText(lhs.helpMessage, rhs.helpMessage)
            && sameText(lhs.savedUserPlaceID, rhs.savedUserPlaceID)
            && sameText(lhs.duplicateUserPlaceID, rhs.duplicateUserPlaceID)
            && sameText(lhs.stagedStatusRaw, rhs.stagedStatusRaw)
            && sameText(lhs.stagedNote, rhs.stagedNote)
            && lhs.stagedRatingScore?.bitPattern == rhs.stagedRatingScore?.bitPattern
            && sameSeedEncoding(lhs.seed, rhs.seed)
            && zip(lhs.candidates, rhs.candidates).allSatisfy { sameCandidateEncoding($0.0, $0.1) }
    }

    private static func sameSeedEncoding(_ lhs: PlaceImportSeed, _ rhs: PlaceImportSeed) -> Bool {
        sameText(lhs.id, rhs.id) && sameText(lhs.rawText, rhs.rawText)
            && sameText(lhs.nameHint, rhs.nameHint) && sameText(lhs.areaHint, rhs.areaHint)
            && sameText(lhs.sourceURLString, rhs.sourceURLString)
            && sameText(lhs.sourceProvider, rhs.sourceProvider)
            && sameText(lhs.sourceProviderPlaceID, rhs.sourceProviderPlaceID)
            && sameText(lhs.socialCaptionHint, rhs.socialCaptionHint)
            && sameText(lhs.sourceThumbnailURLString, rhs.sourceThumbnailURLString)
            && sameText(lhs.socialUnderstandingRequestID, rhs.socialUnderstandingRequestID)
            && lhs.latitude?.bitPattern == rhs.latitude?.bitPattern
            && lhs.longitude?.bitPattern == rhs.longitude?.bitPattern
    }

    private static func sameCandidateEncoding(_ lhs: PlaceCandidate, _ rhs: PlaceCandidate) -> Bool {
        sameText(lhs.id, rhs.id) && sameText(lhs.name, rhs.name)
            && sameText(lhs.category, rhs.category) && sameText(lhs.primaryCategory, rhs.primaryCategory)
            && sameText(lhs.subcategory, rhs.subcategory) && sameText(lhs.categorySource, rhs.categorySource)
            && sameText(lhs.rawProviderType, rhs.rawProviderType) && sameText(lhs.address, rhs.address)
            && sameText(lhs.locality, rhs.locality) && sameText(lhs.region, rhs.region)
            && sameText(lhs.country, rhs.country) && sameTexts(lhs.areaComponents, rhs.areaComponents)
            && sameText(lhs.sourceProvider, rhs.sourceProvider)
            && sameText(lhs.sourceProviderPlaceID, rhs.sourceProviderPlaceID)
            && sameText(lhs.websiteURLString, rhs.websiteURLString)
            && sameText(lhs.phoneNumber, rhs.phoneNumber)
            && sameText(lhs.timeZoneIdentifier, rhs.timeZoneIdentifier)
            && sameText(lhs.actionLinksJSON, rhs.actionLinksJSON)
            && lhs.categoryConfidence?.bitPattern == rhs.categoryConfidence?.bitPattern
            && lhs.latitude?.bitPattern == rhs.latitude?.bitPattern
            && lhs.longitude?.bitPattern == rhs.longitude?.bitPattern
            && lhs.distanceMeters?.bitPattern == rhs.distanceMeters?.bitPattern
            && lhs.confidence.bitPattern == rhs.confidence.bitPattern
    }

    static func sameText(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(lhs), .some(rhs)):
            // Most immutable strings retain the same storage between checkpoints.
            // Compare that storage directly, avoiding a generic Swift byte loop
            // for every field of every unchanged row (particularly costly in Debug).
            let comparison: Bool?? = lhs.utf8.withContiguousStorageIfAvailable { left in
                rhs.utf8.withContiguousStorageIfAvailable { right in
                    guard left.count == right.count else { return false }
                    guard !left.isEmpty else { return true }
                    guard let leftStart = left.baseAddress, let rightStart = right.baseAddress else { return false }
                    return leftStart == rightStart || memcmp(leftStart, rightStart, left.count) == 0
                }
            }
            if let available = comparison, let matches = available { return matches }
            // Bridged strings need not expose contiguous UTF8. Literal comparison
            // preserves exact scalar representation instead of canonical equality.
            return lhs.compare(rhs, options: .literal) == .orderedSame
        default: return false
        }
    }

    private static func sameTexts(_ lhs: [String]?, _ rhs: [String]?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case let (.some(lhs), .some(rhs)):
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { sameText($0.0, $0.1) }
        default: false
        }
    }
}
