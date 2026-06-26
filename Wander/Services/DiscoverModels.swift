import Foundation

struct DiscoverFilters: Codable, Equatable {
    var query: String
    var categories: Set<String> = []
    var area: String?
    var statuses: Set<PlaceStatus> = []
    var relationship: ViewerRelationship?
    var ownerQuery: String?
    var tags: Set<String> = []
}

struct DiscoverFilterChip: Identifiable, Equatable {
    let id: String
    let title: String
}

extension DiscoverFilters {
    var chips: [DiscoverFilterChip] {
        var chips: [DiscoverFilterChip] = []

        chips.append(contentsOf: categories.sorted().map { category in
            DiscoverFilterChip(id: "category_\(category)", title: category)
        })

        chips.append(contentsOf: statuses.sorted { $0.rawValue < $1.rawValue }.map { status in
            DiscoverFilterChip(id: "status_\(status.rawValue)", title: status.displayTitle)
        })

        if let relationship {
            chips.append(DiscoverFilterChip(id: "relationship_\(relationship.rawValue)", title: relationship.discoverChipTitle))
        }

        if let area = trimmed(area) {
            chips.append(DiscoverFilterChip(id: "area_\(area)", title: area))
        }

        if let ownerQuery = trimmed(ownerQuery) {
            chips.append(DiscoverFilterChip(id: "owner_\(ownerQuery)", title: ownerQuery))
        }

        chips.append(contentsOf: tags.sorted().map { tag in
            DiscoverFilterChip(id: "tag_\(tag)", title: tag)
        })

        return chips
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

struct DiscoverFilterSchema: Codable, Equatable {
    let allowedCategories: [String]
    let allowedStatuses: [PlaceStatus]
    let allowedRelationships: [ViewerRelationship]
    let allowedTags: [String]

    init(
        allowedCategories: [String] = Self.defaultAllowedCategories,
        allowedStatuses: [PlaceStatus] = PlaceStatus.allCases,
        allowedRelationships: [ViewerRelationship] = [.owner, .follower, .mutual],
        allowedTags: [String] = Self.defaultAllowedTags
    ) {
        self.allowedCategories = allowedCategories
        self.allowedStatuses = allowedStatuses
        self.allowedRelationships = allowedRelationships
        self.allowedTags = allowedTags
    }

    static let defaultAllowedCategories = [
        "bar",
        "coffee",
        "fitness studio",
        "gym",
        "hike",
        "hospital",
        "park",
        "pharmacy",
        "pilates studio",
        "restaurant",
        "spiritual",
        "veterinarian"
    ]

    static let defaultAllowedTags = [
        "cozy",
        "date",
        "dog friendly",
        "group",
        "outlets",
        "patio",
        "quiet",
        "sunset",
        "views",
        "wifi",
        "wifi solid",
        "work"
    ]
}

struct VisiblePlace: Identifiable {
    let id: String
    let place: LocalPlace
    let userPlace: LocalUserPlace
    let owner: LocalProfile
    var attributes: [LocalPlaceAttribute] = []

    var recommendedScore: Double? {
        if let score = userPlace.recommendedScore, userPlace.recommendedCount > 0 {
            return score
        }
        guard userPlace.status == .been,
              let ratingScore = userPlace.ratingScore
        else { return nil }
        return Double(ratingScore)
    }

    var recommendedCount: Int {
        if userPlace.recommendedCount > 0 {
            return userPlace.recommendedCount
        }
        return userPlace.status == .been && userPlace.ratingScore != nil ? 1 : 0
    }
}

struct DiscoverResults {
    let places: [VisiblePlace]
    let profiles: [ProfileShell]
}

struct VisiblePlaceGroup: Identifiable {
    let key: String
    let places: [VisiblePlace]
    let currentUserID: String

    var id: String { key }

    var primary: VisiblePlace {
        places.first { $0.owner.id == currentUserID } ?? places[0]
    }

    var saveCount: Int {
        places.count
    }

    var otherSaveCount: Int {
        max(0, saveCount - 1)
    }

    var recommendedScore: Double? {
        let scores = places
            .filter { $0.userPlace.status == .been }
            .compactMap(\.userPlace.ratingScore)

        guard !scores.isEmpty else {
            return primary.recommendedScore
        }

        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var recommendedCount: Int {
        let localCount = places
            .filter { $0.userPlace.status == .been && $0.userPlace.ratingScore != nil }
            .count
        return max(localCount, primary.recommendedCount)
    }

    var isSavedByCurrentUser: Bool {
        places.contains { $0.owner.id == currentUserID }
    }
}

enum VisiblePlaceGrouping {
    static func groups(
        from places: [VisiblePlace],
        currentUserID: String
    ) -> [VisiblePlaceGroup] {
        var orderedKeys: [String] = []
        var grouped: [String: [VisiblePlace]] = [:]

        for visiblePlace in places {
            let key = key(for: visiblePlace)
            if grouped[key] == nil {
                orderedKeys.append(key)
                grouped[key] = []
            }
            grouped[key]?.append(visiblePlace)
        }

        return orderedKeys.compactMap { key in
            guard let places = grouped[key], !places.isEmpty else { return nil }
            return VisiblePlaceGroup(
                key: key,
                places: places.sorted { lhs, rhs in
                    if lhs.owner.id == currentUserID { return true }
                    if rhs.owner.id == currentUserID { return false }
                    return lhs.owner.displayName.localizedCaseInsensitiveCompare(rhs.owner.displayName) == .orderedAscending
                },
                currentUserID: currentUserID
            )
        }
    }

    static func representativePlaces(
        from places: [VisiblePlace],
        currentUserID: String
    ) -> [VisiblePlace] {
        groups(from: places, currentUserID: currentUserID).map(\.primary)
    }

    static func matchingGroup(
        for selectedPlace: VisiblePlace,
        in places: [VisiblePlace],
        currentUserID: String
    ) -> VisiblePlaceGroup? {
        let selectedKey = key(for: selectedPlace)
        return groups(from: places, currentUserID: currentUserID)
            .first { $0.key == selectedKey }
    }

    static func key(for visiblePlace: VisiblePlace) -> String {
        let place = visiblePlace.place

        let providerID = normalized(place.sourceProviderPlaceID)
        if !providerID.isEmpty {
            return "provider:\(normalized(place.sourceProvider)):\(providerID)"
        }

        let name = normalized(place.canonicalName)
        let category = normalized(place.category)
        let address = normalized(place.address)
        let locality = normalized(place.locality)
        let region = normalized(place.region)

        if !address.isEmpty || !locality.isEmpty || !region.isEmpty {
            return "text:\([name, category, address, locality, region].joined(separator: "|"))"
        }

        let roundedLatitude = (place.latitude * 10_000).rounded() / 10_000
        let roundedLongitude = (place.longitude * 10_000).rounded() / 10_000
        return "coordinate:\([name, category, "\(roundedLatitude)", "\(roundedLongitude)"].joined(separator: "|"))"
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DiscoverPlaceScope: String, CaseIterable, Identifiable, Equatable {
    case myPlaces = "my_places"
    case friendsPlaces = "friends_places"
    case everyone

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPlaces: "mine"
        case .friendsPlaces: "friends"
        case .everyone: "everyone"
        }
    }

    var ownerScopes: Set<String> {
        switch self {
        case .myPlaces: ["you"]
        case .friendsPlaces: ["friends"]
        case .everyone: ["you", "following", "friends"]
        }
    }
}

@MainActor
protocol LLMFilterParser {
    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters
}

struct DeterministicFilterParser: LLMFilterParser {
    func parse(query: String, schema: DiscoverFilterSchema) async throws -> DiscoverFilters {
        let normalized = query.lowercased()
        var filters = DiscoverFilters(query: query)

        for category in schema.allowedCategories where normalized.contains(category.lowercased()) {
            filters.categories.insert(category)
        }

        for (category, aliases) in Self.categoryAliases where schema.allowedCategories.contains(category) {
            if aliases.contains(where: { normalized.contains($0) }) {
                filters.categories.insert(category)
            }
        }

        if normalized.contains("been") || normalized.contains("went") || normalized.contains("tried") || normalized.contains("liked") || normalized.contains("favorite") || normalized.contains("best") || normalized.contains("recommended") {
            filters.statuses.insert(.been)
        }

        if normalized.contains("wanna") || normalized.contains("want") || normalized.contains("try") || normalized.contains("saved") {
            filters.statuses.insert(.wannaGo)
        }

        if normalized.contains("my ") || normalized.hasPrefix("my") {
            filters.relationship = .owner
        } else if normalized.contains("friend") || normalized.contains("mutual") {
            filters.relationship = .mutual
        } else if normalized.contains("following") || normalized.contains("people") {
            filters.relationship = .follower
        }

        filters.ownerQuery = Self.ownerQuery(from: normalized)

        if normalized.contains("la") || normalized.contains("los angeles") {
            filters.area = "LA"
        }

        for area in ["eastside", "silver lake", "larchmont", "echo park", "los feliz", "santa monica"] where normalized.contains(area) {
            filters.area = area
        }

        for tag in schema.allowedTags where normalized.contains(tag) {
            filters.tags.insert(tag)
        }

        return filters
    }

    private static let categoryAliases: [String: [String]] = [
        "coffee": ["coffee", "cafe", "cafes", "work from"],
        "restaurant": ["restaurant", "restaurants", "noodle", "noodles", "dinner", "lunch"],
        "hike": ["hike", "hikes", "trail", "trails"],
        "bar": ["bar", "bars", "drink", "drinks", "patio"],
        "park": ["park", "parks"]
    ]

    private static func ownerQuery(from normalized: String) -> String? {
        if let handle = firstCapture(in: normalized, pattern: #"@([a-z0-9_][a-z0-9_.-]{1,30})"#) {
            return handle
        }

        if let possessive = firstCapture(in: normalized, pattern: #"\b([a-z][a-z0-9_.-]{1,30})['’]s\b"#),
           !ignoredOwnerWords.contains(possessive) {
            return possessive
        }

        return nil
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = expression.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: value)
        else {
            return nil
        }
        return String(value[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let ignoredOwnerWords: Set<String> = [
        "friend",
        "friends",
        "people",
        "rec",
        "recme",
        "wander"
    ]
}

private extension ViewerRelationship {
    var discoverChipTitle: String {
        switch self {
        case .owner: "mine"
        case .mutual: "friends"
        case .follower: "following"
        case .nonFollower: "other people"
        }
    }
}
