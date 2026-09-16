#if DEBUG
import Foundation

/// A normalized mock snapshot, not a production visibility or identity policy.
/// Resolve canonical place aliases and authorize each event before mapping it.
/// REC-497 Wanna events keep their own IDs even when their parent is Been.
struct CommonGroundEvidenceRecord: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case wanna
        case checkIn
        case legacyWanna
        case historicalWanna
    }

    let id: String
    let ownerID: String
    let canonicalPlaceID: String
    let kind: Kind
    let isVisible: Bool
    let isDeleted: Bool

    init(
        id: String,
        ownerID: String,
        canonicalPlaceID: String,
        kind: Kind,
        isVisible: Bool = true,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.ownerID = ownerID
        self.canonicalPlaceID = canonicalPlaceID
        self.kind = kind
        self.isVisible = isVisible
        self.isDeleted = isDeleted
    }
}

struct CommonGroundPersonEvidence: Hashable, Sendable {
    let wannaRecordIDs: Set<String>
    let visitRecordIDs: Set<String>

    var hasWanna: Bool { !wannaRecordIDs.isEmpty }
    var wannaCount: Int { wannaRecordIDs.count }
    var visitCount: Int { visitRecordIDs.count }

    static func aggregate(
        personID: String,
        canonicalPlaceID: String,
        records: [CommonGroundEvidenceRecord]
    ) -> Self {
        var wannaIDs = Set<String>()
        var visitIDs = Set<String>()
        for record in records where record.ownerID == personID
            && record.canonicalPlaceID == canonicalPlaceID
            && record.isVisible && !record.isDeleted {
            switch record.kind {
            case .wanna, .legacyWanna:
                wannaIDs.insert(record.id)
            case .checkIn:
                visitIDs.insert(record.id)
            case .historicalWanna:
                // A fulfilled legacy snapshot is not renewed interest.
                break
            }
        }
        // Visits never erase explicit Wanna events, regardless of record order.
        return Self(wannaRecordIDs: wannaIDs, visitRecordIDs: visitIDs)
    }
}
#endif
