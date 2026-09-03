import Foundation

enum PlaceImportSource: String, Codable, CaseIterable, Equatable, Hashable, Identifiable, Sendable {
    case googleMaps = "google_maps"
    case instagram
    case tiktok
    case snapchat
    case textNotes = "text_notes"

    var id: String { rawValue }
}

enum PlaceImportBatchState: String, Codable, Equatable {
    case queued
    case processing
    case ready
    case complete
    case cancelled
}

enum PlaceImportHistoryPresentation {
    static func statusLabel(
        batch: PlaceImportBatch,
        items: [PlaceImportItem]
    ) -> String {
        let placeCount = batch.receipt?.entries.count
            ?? items.filter { !$0.isSourceRetry }.count
        if batch.receipt != nil {
            return "\(placeCount) places"
        }
        if batch.state == .cancelled {
            return "Cancelled"
        }
        if [.queued, .processing].contains(batch.state)
            || items.contains(where: { [.queued, .resolving].contains($0.state) }) {
            return "Matching…"
        }
        return "Ready to review"
    }
}

enum PlaceImportItemState: String, Codable, Equatable {
    case queued
    case resolving
    case ready
    case ambiguous
    case needsHelp = "needs_help"
    case duplicate
    case saved
    case failed
    case dismissed
}

/// Distinguishes an actual place row from source-level import recovery UI.
///
/// `PlaceImportItem.kind` is optional so snapshots written before this field
/// existed continue to decode. A missing value means a normal place row.
enum PlaceImportItemKind: String, Codable, Equatable, Sendable {
    case place
    case sourceRetry = "source_retry"
}

enum PlaceImportReviewSurface: String, Equatable {
    case resolving
    case quickAdd
    case duplicate
    case compact
    case batch
    case recovery
    case complete
}

enum PlaceImportBulkStatusAction {
    static let idleSelectionID = "bulk_status_action_idle"

    static func status(for selectionID: String) -> PlaceStatus? {
        PlaceStatus(rawValue: selectionID)
    }
}

struct PlaceImportReviewPlan: Equatable {
    let surface: PlaceImportReviewSurface
    let totalCount: Int
    let selectedCount: Int
    let processingCount: Int
    let readyCount: Int
    let duplicateCount: Int
    let needsHelpCount: Int
    let selectedReadyCount: Int
    let selectedDuplicateCount: Int
    let selectedNeedsHelpCount: Int
    private let quickAddStatus: PlaceStatus?

    init(items: [PlaceImportItem]) {
        let activeItems = items.filter { ![.saved, .dismissed].contains($0.state) }
        let placeItems = activeItems.filter { !$0.isSourceRetry }
        let selectedItems = placeItems.filter(\.isSelectedForImport)
        totalCount = placeItems.count
        selectedCount = selectedItems.count
        processingCount = activeItems.filter { [.queued, .resolving].contains($0.state) }.count
        readyCount = placeItems.filter { $0.state == .ready && !$0.selectedCandidates.isEmpty }.count
        duplicateCount = placeItems.filter {
            $0.state == .duplicate && $0.duplicateUserPlaceID != nil
        }.count
        needsHelpCount = placeItems.filter {
            [.ambiguous, .needsHelp, .failed].contains($0.state)
        }.count
        selectedReadyCount = selectedItems.reduce(into: 0) { count, item in
            guard item.state == .ready else { return }
            count += item.selectedCandidates.count
        }
        selectedDuplicateCount = selectedItems.filter {
            $0.state == .duplicate && $0.duplicateUserPlaceID != nil
        }.count
        selectedNeedsHelpCount = selectedItems.filter {
            [.ambiguous, .needsHelp, .failed].contains($0.state)
        }.count
        quickAddStatus = placeItems.count == 1 && selectedItems.count == 1
            ? selectedItems.first?.stagedStatus
            : nil

        if activeItems.isEmpty {
            surface = .complete
        } else if processingCount > 0 {
            surface = .resolving
        } else if placeItems.isEmpty {
            surface = .recovery
        } else if activeItems.contains(where: \.isSourceRetry) {
            // Quick-add and duplicate screens render only one place card. Keep
            // the compact/batch surface whenever scan status is also present so
            // the retry action cannot disappear below a single-place shortcut.
            surface = totalCount <= 5 ? .compact : .batch
        } else if totalCount == 1, readyCount == 1 {
            surface = .quickAdd
        } else if totalCount == 1, duplicateCount == 1 {
            surface = .duplicate
        } else if readyCount == 0, duplicateCount == 0 {
            surface = .recovery
        } else if totalCount <= 5 {
            surface = .compact
        } else {
            surface = .batch
        }
    }

    var committableCount: Int {
        selectedReadyCount + selectedDuplicateCount
    }

    var primaryActionTitle: String? {
        guard processingCount == 0, committableCount > 0 else { return nil }
        if surface == .quickAdd, committableCount == 1 {
            return quickAddStatus == .been ? "Add as Been" : "Add as Wanna"
        }
        if surface == .duplicate {
            return "Add to imported list"
        }
        if selectedNeedsHelpCount > 0 {
            let denominatorNoun = selectedCount == 1 ? "place" : "places"
            return "Add \(committableCount) of \(selectedCount) \(denominatorNoun)"
        }
        let noun = committableCount == 1 ? "place" : "places"
        return "Add \(committableCount) \(noun)"
    }
}

enum PlaceImportReceiptPresentationPolicy {
    static func canUseStoredReceipt(activeItemCount: Int) -> Bool {
        activeItemCount == 0
    }
}

enum PlaceImportCommitAuthorization {
    static func isValid(
        expectedUserID: String,
        authUserID: String?,
        currentUserID: String,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled
            && authUserID == expectedUserID
            && currentUserID == expectedUserID
    }
}

enum PlaceImportReceiptOutcome: String, Codable, Equatable {
    case added
    case existing
    case needsReview = "needs_review"
    case failed
}

struct PlaceImportCompletionNotice: Equatable, Identifiable {
    let batchIDs: [String]
    let foundCount: Int
    let matchedCount: Int
    let needsReviewCount: Int
    let sourceRetryCount: Int
    let sourceName: String

    var id: String {
        batchIDs.sorted().joined(separator: "|")
    }

    var bannerTitle: String {
        "Your import is ready"
    }

    var bannerDetail: String {
        if foundCount == 0, sourceRetryCount > 0 {
            return sourceRetryCount == 1
                ? "Source scan needs a retry"
                : "\(sourceRetryCount) source scans need a retry"
        }
        if sourceRetryCount > 0 {
            let placeSummary = needsReviewCount > 0
                ? "\(matchedCount) matched · \(needsReviewCount) need a look"
                : matchedCount == 1 ? "1 place matched" : "\(matchedCount) places matched"
            return "\(placeSummary) · scan incomplete"
        }
        if needsReviewCount > 0 {
            return "\(matchedCount) matched · \(needsReviewCount) need a look"
        }
        return matchedCount == 1 ? "1 place matched" : "\(matchedCount) places matched"
    }

    static func resolved(
        batchIDs: [String],
        batches: [PlaceImportBatch],
        items: [PlaceImportItem]
    ) -> PlaceImportCompletionNotice? {
        let requestedIDs = Set(batchIDs)
        let scopedBatches = batches.filter { requestedIDs.contains($0.id) }
        let scopedItems = items.filter {
            requestedIDs.contains($0.batchID) && $0.state != .dismissed
        }
        guard !scopedBatches.isEmpty, !scopedItems.isEmpty else { return nil }
        let placeItems = scopedItems.filter { !$0.isSourceRetry }
        let sourceRetryCount = scopedItems.filter(\.isSourceRetry).count

        let matchedCount = placeItems.filter {
            [.ready, .duplicate, .saved].contains($0.state)
        }.count
        let needsReviewCount = placeItems.filter {
            [.ambiguous, .needsHelp, .failed].contains($0.state)
        }.count
        let foundCount = matchedCount + needsReviewCount
        guard foundCount > 0 || sourceRetryCount > 0 else { return nil }

        let sources = Set(scopedBatches.map(\.source))
        let sourceName: String
        if sources.count == 1, let source = sources.first {
            sourceName = switch source {
            case .googleMaps: "Google Maps"
            case .instagram: "Instagram"
            case .tiktok: "TikTok"
            case .snapchat: "Snapchat"
            case .textNotes: "Your notes"
            }
        } else {
            sourceName = "Multiple sources"
        }

        return PlaceImportCompletionNotice(
            batchIDs: scopedBatches.map(\.id),
            foundCount: foundCount,
            matchedCount: matchedCount,
            needsReviewCount: needsReviewCount,
            sourceRetryCount: sourceRetryCount,
            sourceName: sourceName
        )
    }
}

enum PlaceImportSaveSyncNoticeKind: Equatable {
    case pending
    case failed
}

/// A receipt-scoped view of the durable save queue. This intentionally keys
/// off the user-place IDs punched locally during import, so retry can never
/// re-run extraction or replace a newer import.
struct PlaceImportSaveSyncNotice: Equatable, Identifiable {
    let receiptID: String
    let userPlaceIDs: [String]
    let kind: PlaceImportSaveSyncNoticeKind

    var id: String { "\(receiptID)|\(kind == .failed ? "failed" : "pending")" }
    var count: Int { userPlaceIDs.count }

    static func resolved(
        batches: [PlaceImportBatch],
        syncStatesByUserPlaceID: [String: SyncState],
        excludingReceiptIDs: Set<String> = []
    ) -> PlaceImportSaveSyncNotice? {
        let receipts = batches
            .compactMap(\.receipt)
            .filter { !excludingReceiptIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }

        for receipt in receipts {
            let ids = Array(Set(receipt.entries.compactMap(\.userPlaceID))).sorted()
            let failed = ids.filter {
                guard let state = syncStatesByUserPlaceID[$0] else { return false }
                return state == .failed || state == .serverDenied
            }
            if !failed.isEmpty {
                return PlaceImportSaveSyncNotice(
                    receiptID: receipt.id,
                    userPlaceIDs: failed,
                    kind: .failed
                )
            }

            let pending = ids.filter {
                guard let state = syncStatesByUserPlaceID[$0] else { return false }
                return state == .localOnly
                    || state == .pendingCreate
                    || state == .pendingUpdate
                    || state == .pendingDelete
            }
            if !pending.isEmpty {
                return PlaceImportSaveSyncNotice(
                    receiptID: receipt.id,
                    userPlaceIDs: pending,
                    kind: .pending
                )
            }
        }
        return nil
    }
}

struct PlaceImportReceiptEntry: Codable, Equatable, Identifiable {
    let id: String
    let itemID: String
    let displayName: String
    let displayArea: String?
    let statusRaw: String?
    let outcome: PlaceImportReceiptOutcome
    let userPlaceID: String?

    init(
        id: String = UUID().uuidString.lowercased(),
        itemID: String,
        displayName: String,
        displayArea: String?,
        status: PlaceStatus?,
        outcome: PlaceImportReceiptOutcome,
        userPlaceID: String?
    ) {
        self.id = id
        self.itemID = itemID
        self.displayName = displayName
        self.displayArea = displayArea
        statusRaw = status?.rawValue
        self.outcome = outcome
        self.userPlaceID = userPlaceID
    }

    var status: PlaceStatus? {
        statusRaw.flatMap(PlaceStatus.init(rawValue:))
    }
}

struct PlaceImportReceipt: Codable, Equatable, Identifiable {
    let id: String
    let batchID: String
    let sourceName: String?
    let createdAt: Date
    let entries: [PlaceImportReceiptEntry]
    let destinationListID: String?
    private let sourceRetryCountRaw: Int?
    var presentedAt: Date?

    init(
        id: String = UUID().uuidString.lowercased(),
        batchID: String,
        sourceName: String?,
        createdAt: Date = .now,
        entries: [PlaceImportReceiptEntry],
        destinationListID: String?,
        sourceRetryCount: Int = 0,
        presentedAt: Date? = nil
    ) {
        self.id = id
        self.batchID = batchID
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.entries = entries
        self.destinationListID = destinationListID
        sourceRetryCountRaw = sourceRetryCount > 0 ? sourceRetryCount : nil
        self.presentedAt = presentedAt
    }

    /// Source-level retry markers are status, not receipt place rows.
    ///
    /// The stored value is optional so receipts persisted before scan status
    /// was introduced continue to decode without a snapshot migration.
    var sourceRetryCount: Int {
        sourceRetryCountRaw ?? 0
    }

    var hasContent: Bool {
        !entries.isEmpty || sourceRetryCount > 0
    }

    var addedCount: Int {
        entries.filter { $0.outcome == .added }.count
    }

    var existingCount: Int {
        entries.filter { $0.outcome == .existing }.count
    }

    var needsReviewCount: Int {
        entries.filter { $0.outcome == .needsReview }.count
    }
}

enum PlaceImportDestinationListName {
    static let maximumUnicodeScalarCount = 96

    static func normalized(_ sourceName: String?) -> String {
        let source = sourceName ?? ""
        let withoutControls = source.unicodeScalars.filter {
            $0.properties.generalCategory != .control
        }
        let collapsed = String(String.UnicodeScalarView(withoutControls))
            .precomposedStringWithCanonicalMapping
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let fallback = collapsed.isEmpty ? "Google Maps Import" : collapsed

        var output = ""
        for character in fallback {
            let proposed = output + String(character)
            guard proposed.unicodeScalars.count <= maximumUnicodeScalarCount else { break }
            output = proposed
        }
        return output.isEmpty ? "Google Maps Import" : output
    }

    static func unique(_ sourceName: String?, existingNames: Set<String>) -> String {
        let base = normalized(sourceName)
        guard !existingNames.contains(base) else {
            var suffixIndex = 1
            while true {
                let suffix = suffixIndex == 1 ? " — Google Maps" : " — Google Maps \(suffixIndex)"
                let availableScalars = maximumUnicodeScalarCount - suffix.unicodeScalars.count
                var truncatedBase = ""
                for character in base {
                    let proposed = truncatedBase + String(character)
                    guard proposed.unicodeScalars.count <= availableScalars else { break }
                    truncatedBase = proposed
                }
                let candidate = truncatedBase + suffix
                if !existingNames.contains(candidate) {
                    return candidate
                }
                suffixIndex += 1
            }
        }
        return base
    }
}

struct PlaceImportSeed: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let rawText: String
    let nameHint: String?
    let areaHint: String?
    let sourceURLString: String?
    let sourceLine: Int
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?
    let socialCaptionHint: String?
    var sourceThumbnailURLString: String?
    var socialUnderstandingRequestID: String?

    init(
        id: String = UUID().uuidString.lowercased(),
        rawText: String,
        nameHint: String?,
        areaHint: String?,
        sourceURLString: String?,
        sourceLine: Int,
        latitude: Double? = nil,
        longitude: Double? = nil,
        sourceProvider: String? = nil,
        sourceProviderPlaceID: String? = nil,
        socialCaptionHint: String? = nil,
        sourceThumbnailURLString: String? = nil,
        socialUnderstandingRequestID: String? = nil
    ) {
        self.id = id
        self.rawText = rawText
        self.nameHint = nameHint
        self.areaHint = areaHint
        self.sourceURLString = sourceURLString
        self.sourceLine = sourceLine
        self.latitude = latitude
        self.longitude = longitude
        self.sourceProvider = sourceProvider
        self.sourceProviderPlaceID = sourceProviderPlaceID
        self.socialCaptionHint = socialCaptionHint
        self.sourceThumbnailURLString = sourceThumbnailURLString
        self.socialUnderstandingRequestID = socialUnderstandingRequestID
    }

    var effectiveSocialUnderstandingRequestID: String {
        socialUnderstandingRequestID ?? id
    }
}

struct PlaceImportBatch: Codable, Equatable, Identifiable {
    let id: String
    let source: PlaceImportSource
    var sourceName: String?
    let captureDeliveryID: String?
    let createdAt: Date
    var updatedAt: Date
    var state: PlaceImportBatchState
    var totalCount: Int
    var processedCount: Int
    var destinationListID: String?
    var receipt: PlaceImportReceipt?
    var automaticSaveRequested: Bool?
    var automaticSaveCompletedAt: Date?
    var requestedStatusRaw: String?
    var requestedRatingScore: Double?

    init(
        id: String = UUID().uuidString.lowercased(),
        source: PlaceImportSource,
        sourceName: String?,
        captureDeliveryID: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        state: PlaceImportBatchState = .queued,
        totalCount: Int,
        processedCount: Int = 0,
        destinationListID: String? = nil,
        receipt: PlaceImportReceipt? = nil,
        automaticSaveRequested: Bool? = nil,
        automaticSaveCompletedAt: Date? = nil,
        requestedStatus: PlaceStatus? = nil,
        requestedRatingScore: Double? = nil
    ) {
        self.id = id
        self.source = source
        self.sourceName = sourceName
        self.captureDeliveryID = captureDeliveryID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.totalCount = totalCount
        self.processedCount = processedCount
        self.destinationListID = destinationListID
        self.receipt = receipt
        self.automaticSaveRequested = automaticSaveRequested
        self.automaticSaveCompletedAt = automaticSaveCompletedAt
        requestedStatusRaw = requestedStatus?.rawValue
        self.requestedRatingScore = requestedStatus == .been ? requestedRatingScore : nil
    }

    var requestedStatus: PlaceStatus {
        requestedStatusRaw.flatMap(PlaceStatus.init(rawValue:)) ?? .wannaGo
    }

    var shouldSaveAutomatically: Bool {
        automaticSaveRequested == true && automaticSaveCompletedAt == nil
    }
}

struct PlaceImportItem: Codable, Equatable, Identifiable {
    static let currentResolverVersion = 11

    let id: String
    let batchID: String
    let source: PlaceImportSource
    var kind: PlaceImportItemKind?
    var seed: PlaceImportSeed
    var state: PlaceImportItemState
    var candidates: [PlaceCandidate]
    var selectedCandidateID: String?
    /// Ordered candidate selections for a source place. Optional keeps import
    /// snapshots written before multi-match selection backward compatible.
    var selectedCandidateIDsRaw: [String]?
    var helpMessage: String?
    var savedUserPlaceID: String?
    var duplicateUserPlaceID: String?
    var resolverVersion: Int?
    var pendingManualSearch: Bool?
    var stagedStatusRaw: String?
    var stagedNote: String?
    var stagedRatingScore: Double?
    var stagedVisitedAt: Date?
    var isIncludedInImport: Bool?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        batchID: String,
        source: PlaceImportSource,
        kind: PlaceImportItemKind? = nil,
        seed: PlaceImportSeed,
        state: PlaceImportItemState = .queued,
        candidates: [PlaceCandidate] = [],
        selectedCandidateID: String? = nil,
        selectedCandidateIDs: [String]? = nil,
        helpMessage: String? = nil,
        savedUserPlaceID: String? = nil,
        duplicateUserPlaceID: String? = nil,
        resolverVersion: Int? = PlaceImportItem.currentResolverVersion,
        pendingManualSearch: Bool? = nil,
        stagedStatus: PlaceStatus? = nil,
        stagedNote: String? = nil,
        stagedRatingScore: Double? = nil,
        stagedVisitedAt: Date? = nil,
        isIncludedInImport: Bool? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.batchID = batchID
        self.source = source
        self.kind = kind
        self.seed = seed
        self.state = state
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
        selectedCandidateIDsRaw = selectedCandidateIDs
        self.helpMessage = helpMessage
        self.savedUserPlaceID = savedUserPlaceID
        self.duplicateUserPlaceID = duplicateUserPlaceID
        self.resolverVersion = resolverVersion
        self.pendingManualSearch = pendingManualSearch
        stagedStatusRaw = stagedStatus?.rawValue
        self.stagedNote = stagedNote
        self.stagedRatingScore = stagedRatingScore
        self.stagedVisitedAt = stagedVisitedAt
        self.isIncludedInImport = kind == .sourceRetry ? false : isIncludedInImport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isSelectedForImport: Bool {
        get { !isSourceRetry && (isIncludedInImport ?? true) }
        set { isIncludedInImport = isSourceRetry ? false : newValue }
    }

    var isSourceRetry: Bool {
        if kind == .sourceRetry {
            return true
        }
        // Compatibility for a partial-import retry row persisted by an older
        // build before `kind` was introduced.
        guard kind == nil,
              [.instagram, .tiktok].contains(source),
              seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
              candidates.isEmpty,
              helpMessage?.localizedCaseInsensitiveContains("some media") == true,
              helpMessage?.localizedCaseInsensitiveContains("retry automatic matching") == true
        else { return false }
        return true
    }

    var selectedCandidate: PlaceCandidate? {
        selectedCandidates.first
    }

    /// Every Apple Maps result the person chose for this one source mention.
    /// A single-selection snapshot naturally upgrades to a one-element array.
    var selectedCandidates: [PlaceCandidate] {
        let selectedIDs: [String]
        if let selectedCandidateIDsRaw, !selectedCandidateIDsRaw.isEmpty {
            selectedIDs = selectedCandidateIDsRaw
        } else if let selectedCandidateID {
            selectedIDs = [selectedCandidateID]
        } else if state == .ready, candidates.count == 1 {
            selectedIDs = [candidates[0].id]
        } else {
            selectedIDs = []
        }
        let order = Dictionary(uniqueKeysWithValues: selectedIDs.enumerated().map { ($1, $0) })
        return candidates
            .filter { order[$0.id] != nil }
            .sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    var selectedCandidateIDs: [String] {
        selectedCandidates.map(\.id)
    }

    var stagedStatus: PlaceStatus {
        get { stagedStatusRaw.flatMap(PlaceStatus.init(rawValue:)) ?? .wannaGo }
        set {
            stagedStatusRaw = newValue.rawValue
            if newValue == .wannaGo {
                stagedRatingScore = nil
                stagedVisitedAt = nil
            }
        }
    }

    var displayName: String {
        if source == .googleMaps,
           let sourceName = seed.nameHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceName.isEmpty {
            return sourceName
        }
        return selectedCandidate?.name
            ?? seed.nameHint
            ?? candidates.first?.name
            ?? socialSourceFallbackName
            ?? sourceURLHost
            ?? "Imported place"
    }

    var displayArea: String? {
        guard let candidate = selectedCandidate ?? candidates.first else {
            return seed.areaHint
        }
        let candidateArea = [candidate.locality, candidate.region]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
            .nilIfEmpty
        return candidateArea ?? seed.areaHint
    }

    private var sourceURLHost: String? {
        guard let sourceURLString,
              let host = URL(string: sourceURLString)?.host
        else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var socialSourceFallbackName: String? {
        switch source {
        case .instagram: "Instagram post"
        case .tiktok: "TikTok post"
        case .snapchat: "Snapchat post"
        case .googleMaps, .textNotes: nil
        }
    }

    private var sourceURLString: String? {
        seed.sourceURLString
    }
}

struct PlaceImportSnapshot: Codable, Equatable {
    static let currentVersion = 2

    let version: Int
    var ownerUserID: String?
    var batches: [PlaceImportBatch]
    var items: [PlaceImportItem]

    init(
        version: Int = PlaceImportSnapshot.currentVersion,
        ownerUserID: String? = nil,
        batches: [PlaceImportBatch] = [],
        items: [PlaceImportItem] = []
    ) {
        self.version = version
        self.ownerUserID = ownerUserID
        self.batches = batches
        self.items = items
    }
}

struct PlaceImportExistingPlace: Equatable {
    let userPlaceID: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let sourceProvider: String?
    let sourceProviderPlaceID: String?
}

struct PlaceImportSummary: Equatable {
    let batchID: String?
    let totalCount: Int
    let processedCount: Int
    let processingCount: Int
    let readyCount: Int
    let needsHelpCount: Int
    let duplicateCount: Int
    let savedCount: Int
    let sourceRetryCount: Int
    let sourceRetryProcessingCount: Int

    static let empty = PlaceImportSummary(
        batchID: nil,
        totalCount: 0,
        processedCount: 0,
        processingCount: 0,
        readyCount: 0,
        needsHelpCount: 0,
        duplicateCount: 0,
        savedCount: 0,
        sourceRetryCount: 0,
        sourceRetryProcessingCount: 0
    )

    var remainingCount: Int {
        readyCount + needsHelpCount
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(1, Double(processedCount) / Double(totalCount))
    }

    var hasImports: Bool {
        batchID != nil
    }

    var hasPendingImports: Bool {
        processingCount > 0 || remainingCount > 0 || sourceRetryCount > 0
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
