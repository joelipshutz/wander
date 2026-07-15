import Foundation

enum PlaceImportSource: String, Codable, CaseIterable, Equatable, Identifiable {
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

struct PlaceImportSeed: Codable, Equatable, Identifiable {
    let id: String
    let rawText: String
    let nameHint: String?
    let areaHint: String?
    let sourceURLString: String?
    let sourceLine: Int

    init(
        id: String = UUID().uuidString.lowercased(),
        rawText: String,
        nameHint: String?,
        areaHint: String?,
        sourceURLString: String?,
        sourceLine: Int
    ) {
        self.id = id
        self.rawText = rawText
        self.nameHint = nameHint
        self.areaHint = areaHint
        self.sourceURLString = sourceURLString
        self.sourceLine = sourceLine
    }
}

struct PlaceImportBatch: Codable, Equatable, Identifiable {
    let id: String
    let source: PlaceImportSource
    let sourceName: String?
    let createdAt: Date
    var updatedAt: Date
    var state: PlaceImportBatchState
    var totalCount: Int
    var processedCount: Int

    init(
        id: String = UUID().uuidString.lowercased(),
        source: PlaceImportSource,
        sourceName: String?,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        state: PlaceImportBatchState = .queued,
        totalCount: Int,
        processedCount: Int = 0
    ) {
        self.id = id
        self.source = source
        self.sourceName = sourceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.totalCount = totalCount
        self.processedCount = processedCount
    }
}

struct PlaceImportItem: Codable, Equatable, Identifiable {
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

    var displayName: String {
        selectedCandidate?.name
            ?? candidates.first?.name
            ?? seed.nameHint
            ?? sourceURLHost
            ?? "Imported place"
    }

    var displayArea: String? {
        guard let candidate = selectedCandidate ?? candidates.first else {
            return seed.areaHint
        }
        return [candidate.locality, candidate.region]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
            .nilIfEmpty
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
