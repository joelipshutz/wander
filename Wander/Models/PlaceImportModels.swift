import Foundation

enum PlaceImportSource: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case googleMaps = "google_maps"
    case instagram
    case tiktok
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

enum PlaceImportReviewSurface: String, Equatable {
    case resolving
    case quickAdd
    case duplicate
    case compact
    case batch
    case recovery
    case complete
}

struct PlaceImportReviewPlan: Equatable {
    let surface: PlaceImportReviewSurface
    let totalCount: Int
    let processingCount: Int
    let readyCount: Int
    let duplicateCount: Int
    let needsHelpCount: Int

    init(items: [PlaceImportItem]) {
        let activeItems = items.filter { ![.saved, .dismissed].contains($0.state) }
        totalCount = activeItems.count
        processingCount = activeItems.filter { [.queued, .resolving].contains($0.state) }.count
        readyCount = activeItems.filter { $0.state == .ready && $0.selectedCandidate != nil }.count
        duplicateCount = activeItems.filter {
            $0.state == .duplicate && $0.duplicateUserPlaceID != nil
        }.count
        needsHelpCount = activeItems.filter {
            [.ambiguous, .needsHelp, .failed].contains($0.state)
        }.count

        if totalCount == 0 {
            surface = .complete
        } else if processingCount > 0 {
            surface = .resolving
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
        readyCount + duplicateCount
    }

    var primaryActionTitle: String? {
        guard committableCount > 0 else { return nil }
        if surface == .quickAdd {
            return "Add as Wanna"
        }
        if surface == .duplicate {
            return "Add to imported list"
        }
        if needsHelpCount > 0 {
            let denominatorNoun = totalCount == 1 ? "place" : "places"
            return "Add \(committableCount) of \(totalCount) \(denominatorNoun)"
        }
        let noun = committableCount == 1 ? "place" : "places"
        return "Add \(committableCount) \(noun)"
    }
}

enum PlaceImportReceiptOutcome: String, Codable, Equatable {
    case added
    case existing
    case needsReview = "needs_review"
    case failed
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
    var presentedAt: Date?

    init(
        id: String = UUID().uuidString.lowercased(),
        batchID: String,
        sourceName: String?,
        createdAt: Date = .now,
        entries: [PlaceImportReceiptEntry],
        destinationListID: String?,
        presentedAt: Date? = nil
    ) {
        self.id = id
        self.batchID = batchID
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.entries = entries
        self.destinationListID = destinationListID
        self.presentedAt = presentedAt
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

struct PlaceImportSeed: Codable, Equatable, Identifiable {
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
        sourceProviderPlaceID: String? = nil
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
        receipt: PlaceImportReceipt? = nil
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
    }
}

struct PlaceImportItem: Codable, Equatable, Identifiable {
    static let currentResolverVersion = 7

    let id: String
    let batchID: String
    let source: PlaceImportSource
    var seed: PlaceImportSeed
    var state: PlaceImportItemState
    var candidates: [PlaceCandidate]
    var selectedCandidateID: String?
    var helpMessage: String?
    var savedUserPlaceID: String?
    var duplicateUserPlaceID: String?
    var resolverVersion: Int?
    var pendingManualSearch: Bool?
    var stagedStatusRaw: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        batchID: String,
        source: PlaceImportSource,
        seed: PlaceImportSeed,
        state: PlaceImportItemState = .queued,
        candidates: [PlaceCandidate] = [],
        selectedCandidateID: String? = nil,
        helpMessage: String? = nil,
        savedUserPlaceID: String? = nil,
        duplicateUserPlaceID: String? = nil,
        resolverVersion: Int? = PlaceImportItem.currentResolverVersion,
        pendingManualSearch: Bool? = nil,
        stagedStatus: PlaceStatus? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.batchID = batchID
        self.source = source
        self.seed = seed
        self.state = state
        self.candidates = candidates
        self.selectedCandidateID = selectedCandidateID
        self.helpMessage = helpMessage
        self.savedUserPlaceID = savedUserPlaceID
        self.duplicateUserPlaceID = duplicateUserPlaceID
        self.resolverVersion = resolverVersion
        self.pendingManualSearch = pendingManualSearch
        stagedStatusRaw = stagedStatus?.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var selectedCandidate: PlaceCandidate? {
        if let selectedCandidateID,
           let selected = candidates.first(where: { $0.id == selectedCandidateID }) {
            return selected
        }
        return state == .ready && candidates.count == 1 ? candidates[0] : nil
    }

    var stagedStatus: PlaceStatus {
        get { stagedStatusRaw.flatMap(PlaceStatus.init(rawValue:)) ?? .wannaGo }
        set { stagedStatusRaw = newValue.rawValue }
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

    private var sourceURLString: String? {
        seed.sourceURLString
    }
}

struct PlaceImportSnapshot: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    var batches: [PlaceImportBatch]
    var items: [PlaceImportItem]

    init(
        version: Int = PlaceImportSnapshot.currentVersion,
        batches: [PlaceImportBatch] = [],
        items: [PlaceImportItem] = []
    ) {
        self.version = version
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

    static let empty = PlaceImportSummary(
        batchID: nil,
        totalCount: 0,
        processedCount: 0,
        processingCount: 0,
        readyCount: 0,
        needsHelpCount: 0,
        duplicateCount: 0,
        savedCount: 0
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
        processingCount > 0 || remainingCount > 0
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
