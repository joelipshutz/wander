import Foundation

enum PlaceListVisibility: String, Codable, CaseIterable {
    case followers
    case stealth

    var isStealth: Bool { self == .stealth }
}

enum PlaceListRole: String, Codable, CaseIterable {
    case owner
    case collaborator
}

enum PlaceListScope: String, Codable, CaseIterable {
    case mine
    case friends
    case collabs
}

struct LocalPlaceList: Identifiable, Equatable, Hashable {
    static let maximumSnapshotCoverBytes = 1_048_576
    let localID: String
    var serverID: String?
    var ownerUserID: String
    var name: String
    var description: String
    var visibilityRaw: String
    var syncStateRaw: String
    var snapshotCoverData: Data?
    var snapshotCoverPath: String?
    var cachedItemCount: Int?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        ownerUserID: String,
        name: String,
        description: String,
        visibility: PlaceListVisibility = .followers,
        syncState: SyncState = .localOnly,
        cachedItemCount: Int? = nil,
        snapshotCoverData: Data? = nil,
        snapshotCoverPath: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.ownerUserID = ownerUserID
        self.name = name
        self.description = description
        self.visibilityRaw = visibility.rawValue
        self.syncStateRaw = syncState.rawValue
        self.snapshotCoverData = snapshotCoverData
        self.snapshotCoverPath = snapshotCoverPath
        self.cachedItemCount = cachedItemCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var visibility: PlaceListVisibility { PlaceListVisibility(rawValue: visibilityRaw) ?? .followers }
    var isStealth: Bool { visibility.isStealth }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

struct LocalPlaceListMember: Identifiable, Equatable, Hashable {
    let localID: String
    var serverID: String?
    var listID: String
    var userID: String
    var roleRaw: String
    var createdAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        listID: String,
        userID: String,
        role: PlaceListRole,
        createdAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.listID = listID
        self.userID = userID
        self.roleRaw = role.rawValue
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var role: PlaceListRole { PlaceListRole(rawValue: roleRaw) ?? .collaborator }
}

struct LocalPlaceListItem: Identifiable, Equatable, Hashable {
    let localID: String
    var serverID: String?
    var listID: String
    var placeID: String
    var ownerUserPlaceID: String?
    var sourceUserPlaceID: String?
    var addedByUserID: String
    var syncStateRaw: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        localID: String,
        serverID: String? = nil,
        listID: String,
        placeID: String,
        ownerUserPlaceID: String? = nil,
        sourceUserPlaceID: String? = nil,
        addedByUserID: String,
        syncState: SyncState = .localOnly,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.localID = localID
        self.serverID = serverID
        self.listID = listID
        self.placeID = placeID
        self.ownerUserPlaceID = ownerUserPlaceID
        self.sourceUserPlaceID = sourceUserPlaceID
        self.addedByUserID = addedByUserID
        self.syncStateRaw = syncState.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var id: String { serverID ?? localID }
    var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .localOnly }
}

struct ListPlaceSuggestion: Identifiable {
    let visiblePlace: VisiblePlace
    let reason: String
    let score: Double

    var id: String { visiblePlace.id }
}

enum ListSuggestionReasonFormatter {
    private static let genericValues = Set([
        "address",
        "addresses",
        "addresses areas",
        "area",
        "area address",
        "areas",
        "areas addresses",
        "categories",
        "category",
        "location",
        "locations",
        "and",
        "or",
        "plus",
        "with",
        "place",
        "places",
        "tag",
        "tags"
    ])

    static func displayText(_ rawReason: String, for visiblePlace: VisiblePlace) -> String {
        let trimmedReason = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonBody: String
        if let colonIndex = trimmedReason.firstIndex(of: ":"),
           trimmedReason[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Fits") == .orderedSame {
            reasonBody = String(trimmedReason[trimmedReason.index(after: colonIndex)...])
        } else if !trimmedReason.isEmpty {
            reasonBody = trimmedReason
        } else {
            return fallbackText(for: visiblePlace)
        }

        let values = usefulValues(
            reasonBody.components(separatedBy: CharacterSet(charactersIn: "+|,•;"))
        )
        guard !values.isEmpty else { return fallbackText(for: visiblePlace) }
        return "Fits: \(values.prefix(3).joined(separator: " + "))"
    }

    private static func fallbackText(for visiblePlace: VisiblePlace) -> String {
        let values = usefulValues([
            visiblePlace.place.locality,
            visiblePlace.effectiveCompactType,
            visiblePlace.place.region
        ].compactMap { $0 })
        guard !values.isEmpty else { return "Similar to this list" }
        return "Fits: \(values.prefix(3).joined(separator: " + "))"
    }

    private static func usefulValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.flatMap { rawValue in
            rawValue
                .replacingOccurrences(
                    of: #"\b(?:and|or|plus|with)\b"#,
                    with: "|",
                    options: [.regularExpression, .caseInsensitive]
                )
                .components(separatedBy: "|")
        }
        .compactMap { rawValue in
            let value = humanized(rawValue)
            let key = normalizedKey(value)
            guard !key.isEmpty,
                  !genericValues.contains(key),
                  seen.insert(key).inserted
            else { return nil }
            return value
        }
    }

    private static func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct ListSuggestionBatch {
    private(set) var suggestions: [ListPlaceSuggestion] = []
    private(set) var pendingSuggestionIDs = Set<String>()

    mutating func replace(with suggestions: [ListPlaceSuggestion]) {
        self.suggestions = suggestions
        pendingSuggestionIDs.formIntersection(suggestions.map(\.id))
    }

    mutating func beginAdding(suggestionID: String) -> Bool {
        guard suggestions.contains(where: { $0.id == suggestionID }) else { return false }
        return pendingSuggestionIDs.insert(suggestionID).inserted
    }

    mutating func finishAdding(
        suggestionID: String,
        outcome: ListPlaceAddResult.Outcome
    ) -> Bool {
        guard pendingSuggestionIDs.remove(suggestionID) != nil else { return false }

        guard outcome == .added || outcome == .alreadyInList else { return false }
        suggestions.removeAll { $0.id == suggestionID }
        return suggestions.isEmpty
    }

    func isAdding(suggestionID: String) -> Bool {
        pendingSuggestionIDs.contains(suggestionID)
    }

    mutating func cancelPendingAdditions() {
        pendingSuggestionIDs.removeAll()
    }
}

struct ListPlaceAddResult: Equatable {
    enum Outcome: Equatable {
        case added
        case alreadyInList
        case permissionDenied
    }

    enum CompanionSave: Equatable {
        case none
        case createdWanna(userPlaceID: String)
        case existingWanna(userPlaceID: String)

        var userPlaceID: String? {
            switch self {
            case .none:
                nil
            case .createdWanna(let userPlaceID),
                 .existingWanna(let userPlaceID):
                userPlaceID
            }
        }
    }

    let outcome: Outcome
    let companionSave: CompanionSave

    var createdWantSave: Bool {
        if case .createdWanna = companionSave {
            return true
        }
        return false
    }

    var shouldExplainAutoSave: Bool {
        outcome == .added && companionSave != .none
    }
}

struct ListSuggestionPayload: Codable, Equatable {
    let listID: String
    let title: String
    let description: String
    let existingPlaces: [ListSuggestionPlacePayload]
    let candidatePlaces: [ListSuggestionPlacePayload]
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case title
        case description
        case existingPlaces = "existing_places"
        case candidatePlaces = "candidate_places"
        case limit
    }
}

struct ListSuggestionPlacePayload: Codable, Equatable {
    let visiblePlaceID: String
    let placeID: String
    let name: String
    let category: String
    let locality: String?
    let region: String?
    let status: PlaceStatus
    let ratingScore: Double?
    let recommendedScore: Double?
    let recommendedCount: Int
    let attributesText: String

    enum CodingKeys: String, CodingKey {
        case visiblePlaceID = "visible_place_id"
        case placeID = "place_id"
        case name
        case category
        case locality
        case region
        case status
        case ratingScore = "rating_score"
        case recommendedScore = "recommended_score"
        case recommendedCount = "recommended_count"
        case attributesText = "attributes_text"
    }
}

struct ListSuggestionFunctionResponse: Codable, Equatable {
    let suggestions: [ListSuggestionFunctionItem]
}

struct ListSuggestionFunctionItem: Codable, Equatable {
    let visiblePlaceID: String
    let reason: String
    let score: Double?

    enum CodingKeys: String, CodingKey {
        case visiblePlaceID = "visible_place_id"
        case reason
        case score
    }
}
