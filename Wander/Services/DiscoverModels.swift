import Foundation

struct DiscoverFilters: Equatable {
    var query: String
    var categories: Set<String> = []
    var area: String?
    var statuses: Set<PlaceStatus> = []
    var relationship: ViewerRelationship?
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

        if let area {
            chips.append(DiscoverFilterChip(id: "area_\(area)", title: area))
        }

        chips.append(contentsOf: tags.sorted().map { tag in
            DiscoverFilterChip(id: "tag_\(tag)", title: tag)
        })

        return chips
    }
}

struct DiscoverFilterSchema: Equatable {
    let allowedCategories: [String]
    let allowedStatuses: [PlaceStatus]
    let allowedRelationships: [ViewerRelationship]
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
    let aliases: Set<String>
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
        var aliasesByKey: [String: Set<String>] = [:]
        var keyByAlias: [String: String] = [:]

        func mergeGroup(_ sourceKey: String, into destinationKey: String) {
            guard sourceKey != destinationKey else { return }

            grouped[destinationKey, default: []].append(contentsOf: grouped[sourceKey] ?? [])
            grouped[sourceKey] = nil

            aliasesByKey[destinationKey, default: []].formUnion(aliasesByKey[sourceKey] ?? [])
            aliasesByKey[sourceKey] = nil

            orderedKeys.removeAll { $0 == sourceKey }
            for alias in aliasesByKey[destinationKey, default: []] {
                keyByAlias[alias] = destinationKey
            }
        }

        for visiblePlace in places {
            let aliases = keys(for: visiblePlace)
            var existingKeys: [String] = []
            for alias in aliases {
                guard let existingKey = keyByAlias[alias],
                      !existingKeys.contains(existingKey)
                else { continue }
                existingKeys.append(existingKey)
            }

            let key = existingKeys.first ?? key(for: visiblePlace)
            if grouped[key] == nil {
                orderedKeys.append(key)
                grouped[key] = []
                aliasesByKey[key] = []
            }

            for existingKey in existingKeys.dropFirst() {
                mergeGroup(existingKey, into: key)
            }

            grouped[key]?.append(visiblePlace)
            aliasesByKey[key, default: []].formUnion(aliases)
            for alias in aliasesByKey[key, default: []] {
                keyByAlias[alias] = key
            }
        }

        return orderedKeys.compactMap { key in
            guard let places = grouped[key], !places.isEmpty else { return nil }
            let sortedPlaces = places.sorted { lhs, rhs in
                if lhs.owner.id == currentUserID { return true }
                if rhs.owner.id == currentUserID { return false }
                return lhs.owner.displayName.localizedCaseInsensitiveCompare(rhs.owner.displayName) == .orderedAscending
            }
            let primary = sortedPlaces.first { $0.owner.id == currentUserID } ?? sortedPlaces[0]
            let primaryKey = Self.key(for: primary)
            let aliases = aliasesByKey[key, default: []].union([primaryKey])

            return VisiblePlaceGroup(
                key: primaryKey,
                aliases: aliases,
                places: sortedPlaces,
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
        let selectedAliases = Set(keys(for: selectedPlace))
        return groups(from: places, currentUserID: currentUserID)
            .first { !$0.aliases.isDisjoint(with: selectedAliases) }
    }

    static func key(for visiblePlace: VisiblePlace) -> String {
        keys(for: visiblePlace)[0]
    }

    static func matches(_ lhs: VisiblePlace, _ rhs: VisiblePlace) -> Bool {
        !Set(keys(for: lhs)).isDisjoint(with: Set(keys(for: rhs)))
    }

    private static func keys(for visiblePlace: VisiblePlace) -> [String] {
        let place = visiblePlace.place
        var keys: [String] = []

        func append(_ key: String) {
            guard !keys.contains(key) else { return }
            keys.append(key)
        }

        let name = normalizedText(place.canonicalName)
        if !name.isEmpty {
            let address = normalizedText(place.address)
            if !address.isEmpty {
                append("address:\([name, address, normalizedText(place.locality), normalizedText(place.region), normalizedText(place.country)].joined(separator: "|"))")
            }
            append("place:\([name, coordinateBucket(for: place)].joined(separator: "|"))")
        }

        let providerID = normalizedIdentifier(place.sourceProviderPlaceID)
        if !providerID.isEmpty {
            append("provider:\(normalizedIdentifier(place.sourceProvider)):\(providerID)")
        }

        if keys.isEmpty {
            append("coordinate:\(coordinateBucket(for: place))")
        }
        return keys
    }

    private static func normalizedText(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedIdentifier(_ value: String?) -> String {
        (value ?? "")
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func coordinateBucket(for place: LocalPlace) -> String {
        let roundedLatitude = (place.latitude * 1_000).rounded() / 1_000
        let roundedLongitude = (place.longitude * 1_000).rounded() / 1_000
        return "\(roundedLatitude)|\(roundedLongitude)"
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

        if normalized.contains("been") || normalized.contains("went") || normalized.contains("tried") || normalized.contains("liked") {
            filters.statuses.insert(.been)
        }

        if normalized.contains("wanna") || normalized.contains("want") || normalized.contains("try") || normalized.contains("saved") {
            filters.statuses.insert(.wannaGo)
        }

        if normalized.contains("friend") || normalized.contains("mutual") {
            filters.relationship = .mutual
        } else if normalized.contains("following") || normalized.contains("people") {
            filters.relationship = .follower
        }

        if normalized.contains("la") || normalized.contains("los angeles") {
            filters.area = "LA"
        }

        for area in ["eastside", "silver lake", "larchmont", "echo park", "los feliz"] where normalized.contains(area) {
            filters.area = area
        }

        for tag in Self.knownTags where normalized.contains(tag) {
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

    private static let knownTags = [
        "wifi",
        "work",
        "patio",
        "quiet",
        "cozy",
        "views",
        "sunset",
        "group",
        "date",
        "dog friendly"
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
