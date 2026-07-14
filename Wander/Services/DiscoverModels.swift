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

        let normalizedCategories = Set(categories.map(WanderPlaceCategory.normalizedPrimaryCategory)).sorted()
        chips.append(contentsOf: normalizedCategories.map { category in
            DiscoverFilterChip(
                id: "category_\(category)",
                title: WanderPlaceCategory.broadCategory(for: category)
            )
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

    static let defaultAllowedCategories = WanderPlaceCategory.editableCategories.filter { $0 != "place" }

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
        return ratingScore
    }

    var recommendedCount: Int {
        if userPlace.recommendedCount > 0 {
            return userPlace.recommendedCount
        }
        return userPlace.status == .been && userPlace.ratingScore != nil ? 1 : 0
    }

    var categoryAssignment: PlaceCategoryAssignment {
        if let override = userPlace.categoryOverride {
            return PlaceCategoryAssignment(
                primaryCategory: override,
                subcategory: userPlace.subcategoryOverride,
                source: userPlace.categoryOverrideSource ?? PlaceCategorySource.user.rawValue,
                confidence: userPlace.categoryOverrideConfidence,
                rawProviderType: place.rawProviderType
            )
        }

        return place.categoryAssignment
    }

    var effectiveCategory: String {
        categoryAssignment.primaryCategory
    }

    var effectiveSubcategory: String? {
        categoryAssignment.subcategory
    }

    var effectiveCategoryDisplay: PlaceCategoryDisplay {
        WanderPlaceCategory.display(for: categoryAssignment)
    }
}

extension LocalPlace {
    var categoryAssignment: PlaceCategoryAssignment {
        PlaceCategoryAssignment(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            source: categorySource,
            confidence: categoryConfidence,
            rawProviderType: rawProviderType
        )
    }
}

struct DiscoverResults {
    let places: [VisiblePlace]
    let profiles: [ProfileShell]
}

enum DiscoverLatestActivityPresentation {
    private static let futureClockSkewTolerance: TimeInterval = 5 * 60

    static func places(
        from places: [VisiblePlace],
        limit: Int = 10,
        relativeTo now: Date = .now
    ) -> [VisiblePlace] {
        Array(
            places
                .sorted { lhs, rhs in
                    let lhsDate = sortDate(for: lhs.userPlace.savedAt, relativeTo: now)
                    let rhsDate = sortDate(for: rhs.userPlace.savedAt, relativeTo: now)
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                    return lhs.userPlace.id < rhs.userPlace.id
                }
                .prefix(max(0, limit))
        )
    }

    static func timestampText(
        for savedAt: Date,
        relativeTo now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if savedAt.timeIntervalSince(now) > futureClockSkewTolerance {
            return absoluteDateText(for: savedAt, relativeTo: now, calendar: calendar)
        }

        let elapsed = max(0, now.timeIntervalSince(savedAt))

        if elapsed < 60 {
            return "just now"
        }
        if elapsed < 60 * 60 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 24 * 60 * 60 {
            return "\(Int(elapsed / (60 * 60)))h ago"
        }
        if elapsed < 7 * 24 * 60 * 60 {
            return "\(Int(elapsed / (24 * 60 * 60)))d ago"
        }

        return absoluteDateText(for: savedAt, relativeTo: now, calendar: calendar)
    }

    private static func sortDate(for savedAt: Date, relativeTo now: Date) -> Date {
        savedAt.timeIntervalSince(now) > futureClockSkewTolerance ? .distantPast : min(savedAt, now)
    }

    private static func absoluteDateText(for savedAt: Date, relativeTo now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = calendar.isDate(savedAt, equalTo: now, toGranularity: .year)
            ? "MMM d"
            : "MMM d, yyyy"
        return formatter.string(from: savedAt)
    }
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

        return scores.reduce(0, +) / Double(scores.count)
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
        "restaurants_food": ["restaurant", "restaurants", "food", "fast food", "noodle", "noodles", "dinner", "lunch", "brunch", "sushi", "thai", "taco", "pizza"],
        "coffee_tea_sweets": ["coffee", "cafe", "cafes", "work from", "tea", "bakery", "dessert", "ice cream", "juice", "smoothie"],
        "bars_nightlife": ["bar", "bars", "drink", "drinks", "patio", "cocktail", "pub", "brewery", "wine bar", "nightlife", "club"],
        "outdoors_nature": ["hike", "hikes", "trail", "trails", "park", "parks", "beach", "waterfall"],
        "things_to_do": ["museum", "gallery", "movie", "concert", "venue", "arcade", "tourist attraction", "landmark", "bowling", "zoo"],
        "shopping": ["shop", "shops", "store", "stores", "boutique", "market"],
        "wellness_fitness": ["wellness", "spa", "hospital", "pharmacy", "clinic", "gym", "fitness", "pilates", "yoga", "court", "vet", "veterinarian"],
        "stays": ["hotel", "motel", "resort", "stay", "stays"],
        "services_errands": ["salon", "barber", "repair", "bank", "atm", "laundry", "tailor", "plumber", "pet care"],
        "travel_transit": ["airport", "train", "bus", "transit", "parking", "taxi", "gas station", "ev charging"],
        "work_education": ["school", "university", "library", "office", "coworking", "work"],
        "civic_faith": ["temple", "church", "shrine", "mosque", "synagogue", "government", "post office", "police"],
        "areas_addresses": ["city", "address", "neighborhood", "region", "street"],
        "facilities_other": ["restroom", "bathroom", "public bath", "unknown"],
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
