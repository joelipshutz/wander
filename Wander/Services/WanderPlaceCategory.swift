import MapKit

enum PlaceCategorySource: String, Codable {
    case provider
    case deterministic
    case ai
    case user
    case legacy
    case unknown
}

struct PlaceCategoryAssignment: Equatable, Codable {
    var primaryCategory: String
    var subcategory: String?
    var source: String
    var confidence: Double?
    var rawProviderType: String?

    init(
        primaryCategory: String,
        subcategory: String? = nil,
        source: String = PlaceCategorySource.provider.rawValue,
        confidence: Double? = nil,
        rawProviderType: String? = nil
    ) {
        self.primaryCategory = WanderPlaceCategory.normalizedPrimaryCategory(primaryCategory)
        self.subcategory = WanderPlaceCategory.normalizedSubcategory(subcategory)
        self.source = PlaceCategorySource(rawValue: source)?.rawValue ?? PlaceCategorySource.unknown.rawValue
        self.confidence = confidence.map { max(0, min(1, $0)) }
        self.rawProviderType = WanderPlaceCategory.normalizedProviderType(rawProviderType)
    }

    var legacyCategory: String {
        primaryCategory
    }

    var isUserEdited: Bool {
        source == PlaceCategorySource.user.rawValue
    }

    var comparableKey: String {
        [
            primaryCategory,
            subcategory?.lowercased() ?? ""
        ].joined(separator: "|")
    }

    func withSource(_ source: PlaceCategorySource, confidence: Double? = nil) -> PlaceCategoryAssignment {
        PlaceCategoryAssignment(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            source: source.rawValue,
            confidence: confidence ?? self.confidence,
            rawProviderType: rawProviderType
        )
    }
}

struct PlaceCategoryDisplay: Equatable {
    let rawCategory: String
    let primaryCategory: String
    let category: String
    let subcategory: String?
    let sourceLabel: String

    var compactTitle: String {
        var parts: [String] = []
        if let subcategory, !subcategory.isEmpty {
            parts.append(subcategory)
        }
        if !category.isEmpty {
            parts.append(category)
        }
        return parts.joined(separator: " · ")
    }
}

enum PlaceMemoryAttributeKeys {
    static let personalLabels = "personal_labels"
}

enum PlacePersonalLabelSuggestions {
    static func options(category: String, status: PlaceStatus) -> [String] {
        let normalized = WanderPlaceCategory.questionCategory(for: category)

        if status == .wannaGo {
            switch normalized {
            case "coffee":
                return ["work maybe", "cute", "nearby", "recommended", "solo"]
            case "hike":
                return ["sunset", "views", "weekend", "dog friendly", "recommended"]
            case "restaurant":
                return ["date night", "group", "spicy", "recommended", "rainy night"]
            case "bar":
                return ["date", "group", "late", "patio", "recommended"]
            case "park":
                return ["walk", "picnic", "reset", "views", "dog friendly"]
            default:
                return ["worth checking", "recommended", "nearby", "bring friends"]
            }
        }

        switch normalized {
        case "coffee":
            return ["work-friendly", "quiet", "cute", "outlets", "solo"]
        case "hike":
            return ["sunset", "views", "shade", "dog friendly", "bring water"]
        case "restaurant":
            return ["date night", "group", "spicy", "cozy", "worth it"]
        case "bar":
            return ["patio", "good music", "not too loud", "late", "date"]
        case "park":
            return ["walk", "picnic", "quiet", "dog friendly", "reset"]
        default:
            return ["worth it", "easy", "cozy", "bring friends"]
        }
    }
}

struct PlaceCategoryTaxonomyEntry: Equatable {
    let id: String
    let group: String
    let defaultSubcategory: String?
    let symbolName: String
    let aliases: [String]
    let subcategories: [String]
}

enum WanderPlaceCategory {
    static let taxonomy: [PlaceCategoryTaxonomyEntry] = [
        PlaceCategoryTaxonomyEntry(id: "coffee", group: "Food & drink", defaultSubcategory: "Coffee shop", symbolName: "cup.and.saucer.fill", aliases: ["coffee", "coffee shop", "cafe", "espresso", "roaster", "bakery"], subcategories: ["Coffee shop", "Cafe", "Bakery", "Roaster", "Tea shop"]),
        PlaceCategoryTaxonomyEntry(id: "restaurant", group: "Food & drink", defaultSubcategory: "Restaurant", symbolName: "fork.knife", aliases: ["restaurant", "thai restaurant", "fast food restaurant", "food", "food market", "taqueria", "ramen", "sushi", "pizza", "diner", "kitchen"], subcategories: ["Restaurant", "Thai restaurant", "Fast food restaurant", "Sushi restaurant", "Pizza restaurant", "Ramen restaurant", "Taqueria", "Diner"]),
        PlaceCategoryTaxonomyEntry(id: "bar", group: "Food & drink", defaultSubcategory: "Bar", symbolName: "wineglass.fill", aliases: ["bar", "brewery", "winery", "nightlife", "cocktail", "pub"], subcategories: ["Bar", "Cocktail bar", "Wine bar", "Brewery", "Pub", "Nightlife"]),
        PlaceCategoryTaxonomyEntry(id: "hike", group: "Outdoors & nature", defaultSubcategory: "Hike or trail", symbolName: "figure.hiking", aliases: ["hike", "trail", "waterfall", "hot spring", "canyon", "mountain", "observatory"], subcategories: ["Hike or trail", "Trail", "Waterfall", "Hot spring", "Canyon", "Scenic overlook"]),
        PlaceCategoryTaxonomyEntry(id: "park", group: "Outdoors & nature", defaultSubcategory: "Park", symbolName: "tree.fill", aliases: ["park", "national park", "playground", "garden", "plaza", "beach", "lake"], subcategories: ["Park", "National park", "Garden", "Beach", "Playground", "Dog park"]),
        PlaceCategoryTaxonomyEntry(id: "gym", group: "Health & wellness", defaultSubcategory: "Gym", symbolName: "dumbbell.fill", aliases: ["gym", "fitness center", "training", "strength", "workout"], subcategories: ["Gym", "Fitness center", "Climbing gym", "Boxing gym", "Training studio"]),
        PlaceCategoryTaxonomyEntry(id: "fitness studio", group: "Health & wellness", defaultSubcategory: "Fitness studio", symbolName: "figure.strengthtraining.traditional", aliases: ["fitness studio", "yoga studio", "barre", "wellness studio", "stretch", "studio"], subcategories: ["Fitness studio", "Yoga studio", "Barre studio", "Wellness studio", "Stretch studio"]),
        PlaceCategoryTaxonomyEntry(id: "pilates studio", group: "Health & wellness", defaultSubcategory: "Pilates studio", symbolName: "figure.mind.and.body", aliases: ["pilates studio", "pilates", "reformer", "lagree"], subcategories: ["Pilates studio", "Reformer pilates", "Lagree studio"]),
        PlaceCategoryTaxonomyEntry(id: "spiritual", group: "Arts, culture & faith", defaultSubcategory: "Spiritual place", symbolName: "sparkles", aliases: ["spiritual", "church", "temple", "shrine", "mosque", "synagogue", "chapel", "cathedral", "meditation"], subcategories: ["Spiritual place", "Temple", "Shrine", "Church", "Mosque", "Synagogue", "Meditation center"]),
        PlaceCategoryTaxonomyEntry(id: "hospital", group: "Health & wellness", defaultSubcategory: "Hospital", symbolName: "cross.case.fill", aliases: ["hospital", "urgent care", "medical center", "health center"], subcategories: ["Hospital", "Urgent care", "Medical center", "Clinic"]),
        PlaceCategoryTaxonomyEntry(id: "pharmacy", group: "Health & wellness", defaultSubcategory: "Pharmacy", symbolName: "pills.fill", aliases: ["pharmacy", "drugstore"], subcategories: ["Pharmacy", "Drugstore"]),
        PlaceCategoryTaxonomyEntry(id: "veterinarian", group: "Services", defaultSubcategory: "Veterinarian", symbolName: "pawprint.fill", aliases: ["veterinarian", "veterinary clinic", "animal hospital", "animal service", "pet clinic", "pet hospital"], subcategories: ["Veterinarian", "Veterinary clinic", "Animal hospital", "Pet clinic"]),
        PlaceCategoryTaxonomyEntry(id: "hotel", group: "Lodging", defaultSubcategory: "Hotel", symbolName: "bed.double.fill", aliases: ["hotel", "motel", "resort", "3 star hotel", "4 star hotel", "5 star hotel", "lodging"], subcategories: ["Hotel", "Motel", "Resort", "Boutique hotel", "3-star hotel", "4-star hotel", "5-star hotel"]),
        PlaceCategoryTaxonomyEntry(id: "shop", group: "Shopping", defaultSubcategory: "Shop", symbolName: "bag.fill", aliases: ["shop", "store", "art supply store", "mall", "boutique", "market"], subcategories: ["Shop", "Store", "Art supply store", "Boutique", "Market", "Mall"]),
        PlaceCategoryTaxonomyEntry(id: "transportation", group: "Transportation & transit", defaultSubcategory: "Transit stop", symbolName: "tram.fill", aliases: ["transportation", "transit", "transit station", "airport", "train station", "bus station", "ferry", "subway"], subcategories: ["Transit stop", "Airport", "Train station", "Bus station", "Ferry terminal", "Subway station"]),
        PlaceCategoryTaxonomyEntry(id: "place", group: "Place", defaultSubcategory: nil, symbolName: "mappin", aliases: ["place", "point of interest", "tourist attraction"], subcategories: [])
    ]

    static let editableCategories = taxonomy.map(\.id)

    static func primary(for pointCategory: MKPointOfInterestCategory?, name: String? = nil) -> String? {
        if let nameCategory = primaryFromName(name, pointCategory: pointCategory) {
            return nameCategory
        }

        if #available(iOS 18.0, *) {
            switch pointCategory {
            case .animalService:
                return "veterinarian"
            case .hiking:
                return "hike"
            case .rockClimbing, .skatePark, .skating, .skiing, .surfing, .swimming:
                return "fitness studio"
            default:
                break
            }
        }

        switch pointCategory {
        case .cafe, .bakery:
            return "coffee"
        case .restaurant, .foodMarket:
            return "restaurant"
        case .brewery, .winery, .nightlife:
            return "bar"
        case .park, .nationalPark:
            return "park"
        case .hospital:
            return "hospital"
        case .fitnessCenter:
            return "gym"
        default:
            return nil
        }
    }

    static func assignment(
        forRawCategory rawCategory: String,
        source: String = PlaceCategorySource.provider.rawValue,
        confidence: Double? = nil,
        rawProviderType: String? = nil
    ) -> PlaceCategoryAssignment {
        let raw = normalizedSubcategory(rawProviderType) ?? normalizedSubcategory(rawCategory)
        let primary = primaryCategory(for: rawCategory)
        let defaultSubcategory = defaultSubcategory(for: primary)
        let subcategory: String?

        if primary == "place" {
            subcategory = nil
        } else if normalizedCategoryText(raw) == primary {
            subcategory = defaultSubcategory
        } else {
            subcategory = raw ?? defaultSubcategory
        }

        return PlaceCategoryAssignment(
            primaryCategory: primary,
            subcategory: subcategory,
            source: source,
            confidence: confidence,
            rawProviderType: rawProviderType ?? rawCategory
        )
    }

    static func assignment(
        primaryCategory: String,
        subcategory: String?,
        source: String = PlaceCategorySource.user.rawValue,
        confidence: Double? = nil,
        rawProviderType: String? = nil
    ) -> PlaceCategoryAssignment {
        let primary = normalizedPrimaryCategory(primaryCategory)
        return PlaceCategoryAssignment(
            primaryCategory: primary,
            subcategory: normalizedSubcategory(subcategory) ?? defaultSubcategory(for: primary),
            source: source,
            confidence: confidence,
            rawProviderType: rawProviderType
        )
    }

    static func display(for assignment: PlaceCategoryAssignment, sourceLabel: String? = nil) -> PlaceCategoryDisplay {
        let primary = normalizedPrimaryCategory(assignment.primaryCategory)
        let subcategory = normalizedSubcategory(assignment.subcategory) ?? defaultSubcategory(for: primary)
        let label = sourceLabel ?? sourceDisplayLabel(assignment.source)
        return PlaceCategoryDisplay(
            rawCategory: assignment.rawProviderType ?? assignment.legacyCategory,
            primaryCategory: primary,
            category: broadCategory(for: primary),
            subcategory: primary == "place" ? nil : subcategory,
            sourceLabel: label
        )
    }

    static func display(for category: String, sourceLabel: String = "suggested") -> PlaceCategoryDisplay {
        display(for: assignment(forRawCategory: category), sourceLabel: sourceLabel)
    }

    static func questionCategory(for category: String) -> String {
        primaryCategory(for: category)
    }

    static func primaryCategory(for category: String) -> String {
        let normalized = normalizedCategoryText(category)
        guard !normalized.isEmpty else { return "place" }
        if taxonomy.contains(where: { $0.id == normalized }) {
            return normalized
        }

        for entry in taxonomy where entry.id != "place" {
            if entry.aliases.contains(where: { normalizedCategoryText($0) == normalized }) {
                return entry.id
            }
        }

        let padded = " \(normalized) "
        for entry in taxonomy where entry.id != "place" {
            if entry.aliases.contains(where: { alias in
                let normalizedAlias = normalizedCategoryText(alias)
                return !normalizedAlias.isEmpty && padded.contains(" \(normalizedAlias) ")
            }) {
                return entry.id
            }
        }

        return "place"
    }

    static func normalizedPrimaryCategory(_ value: String) -> String {
        let normalized = normalizedCategoryText(value)
        if taxonomy.contains(where: { $0.id == normalized }) {
            return normalized
        }
        return primaryCategory(for: normalized)
    }

    static func normalizedSubcategory(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !trimmed.isEmpty else { return nil }
        return sentenceTitleized(trimmed)
    }

    static func normalizedProviderType(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func subcategorySuggestions(for primaryCategory: String) -> [String] {
        entry(for: primaryCategory)?.subcategories ?? []
    }

    static func symbolName(for category: String) -> String {
        entry(for: primaryCategory(for: category))?.symbolName ?? "mappin"
    }

    static func symbolName(for assignment: PlaceCategoryAssignment) -> String {
        entry(for: assignment.primaryCategory)?.symbolName ?? "mappin"
    }

    static func broadCategory(for category: String) -> String {
        entry(for: category)?.group ?? "Place"
    }

    static func defaultSubcategory(for category: String) -> String? {
        entry(for: category)?.defaultSubcategory
    }

    static func normalizedCategoryText(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "&/ -")).inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func entry(for category: String) -> PlaceCategoryTaxonomyEntry? {
        let primary = normalizedCategoryText(category)
        return taxonomy.first { $0.id == primary }
    }

    private static func sourceDisplayLabel(_ source: String) -> String {
        switch PlaceCategorySource(rawValue: source) {
        case .user:
            "edited"
        case .ai:
            "smart guess"
        case .legacy:
            "migrated"
        default:
            "suggested"
        }
    }

    private static func primaryFromName(_ name: String?, pointCategory: MKPointOfInterestCategory?) -> String? {
        guard let normalizedName = normalizedSearchText(name), !normalizedName.isEmpty else { return nil }

        if containsAny(normalizedName, ["veterinary", "veterinarian", " vet ", "animal hospital", "pet hospital", "pet clinic", "dog dental", "cat clinic"]) {
            return "veterinarian"
        }

        if containsAny(normalizedName, ["temple", "shrine", "meditation", "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue"]) {
            return "spiritual"
        }

        if containsAny(normalizedName, ["hospital", "medical center", "health center", "urgent care"]) {
            return "hospital"
        }

        if containsAny(normalizedName, ["pilates", "plankhaus", "lagree", "reformer"]) {
            return "pilates studio"
        }

        let isFitnessCategory = pointCategory == .fitnessCenter
        if isFitnessCategory, containsAny(normalizedName, ["studio", "barre", "yoga", "stretch"]) {
            return "fitness studio"
        }

        if containsAny(normalizedName, [" gym ", "fitness", "training", "strength", "workout"]) {
            return "gym"
        }

        return nil
    }

    private static func containsAny(_ normalizedName: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            normalizedName.contains(needle.lowercased())
        }
    }

    private static func normalizedSearchText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = " "
            + value
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            + " "
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : normalized
    }

    private static func sentenceTitleized(_ value: String) -> String {
        let lowercased = value.lowercased()
        guard let first = lowercased.first else { return lowercased }
        return first.uppercased() + String(lowercased.dropFirst())
    }
}
