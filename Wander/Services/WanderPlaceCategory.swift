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
        let normalizedPrimary = WanderPlaceCategory.normalizedPrimaryCategory(primaryCategory)
        self.primaryCategory = normalizedPrimary
        self.subcategory = WanderPlaceCategory.normalizedSubcategory(subcategory)
            ?? WanderPlaceCategory.defaultSubcategory(forRawCategory: primaryCategory, normalizedPrimary: normalizedPrimary)
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
    static func options(category: String, status: PlaceStatus, locality: String? = nil) -> [String] {
        let normalized = WanderPlaceCategory.questionCategory(for: category)
        let locationFavorite = favoriteLabel(for: locality)
        let statusLabel = status == .wannaGo ? "shortlist" : "go-to"

        switch normalized {
        case "coffee":
            return [locationFavorite, "work rotation", "Joe rec", statusLabel, "neighborhood staple"]
        case "hike", "park":
            return [locationFavorite, "weekend list", "bring visitors", statusLabel, "reset spot"]
        case "restaurant", "bar":
            return [locationFavorite, "birthday list", "Joe rec", statusLabel, "client friendly"]
        default:
            return [locationFavorite, "Joe rec", "weekend list", statusLabel, "bring visitors"]
        }
    }

    private static func favoriteLabel(for locality: String?) -> String {
        let normalized = locality?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "los angeles", "la":
            return "LA favorite"
        case "new york", "new york city", "nyc":
            return "NYC favorite"
        case let value? where !value.isEmpty:
            let titleized = value
                .split(separator: " ")
                .map { word in word.prefix(1).uppercased() + word.dropFirst() }
                .joined(separator: " ")
            return "\(titleized) favorite"
        default:
            return "local favorite"
        }
    }
}

struct PlaceCategoryTaxonomyEntry: Equatable {
    let id: String
    let group: String
    let detail: String
    let defaultSubcategory: String?
    let symbolName: String
    let aliases: [String]
    let subcategories: [String]
    let isEditable: Bool
}

enum WanderPlaceCategory {
    static let foodDrink = "food_drink"
    static let outdoorsNature = "outdoors_nature"
    static let artsCultureFaith = "arts_culture_faith"
    static let entertainment = "entertainment"
    static let healthWellness = "health_wellness"
    static let sportsFitness = "sports_fitness"
    static let shopping = "shopping"
    static let services = "services"
    static let lodging = "lodging"
    static let transportationTransit = "transportation_transit"
    static let education = "education"
    static let workVenues = "work_venues"
    static let homeNeighborhood = "home_neighborhood"
    static let publicServices = "public_services"
    static let fallbackPlace = "place"

    static let taxonomy: [PlaceCategoryTaxonomyEntry] = [
        PlaceCategoryTaxonomyEntry(
            id: foodDrink,
            group: "Food & drink",
            detail: "Restaurants, coffee, bars, markets",
            defaultSubcategory: "Restaurant",
            symbolName: "fork.knife",
            aliases: [
                foodDrink, "food and drink", "food & drink", "food", "drink",
                "coffee", "coffee shop", "cafe", "espresso", "roaster", "bakery", "tea shop",
                "restaurant", "thai restaurant", "fast food restaurant", "taqueria", "ramen",
                "sushi", "pizza", "diner", "kitchen", "grill", "noodle", "taco", "food market",
                "bar", "brewery", "winery", "cocktail", "pub", "nightlife"
            ],
            subcategories: [
                "Restaurant", "Coffee shop", "Cafe", "Bakery", "Tea shop", "Juice bar",
                "Ice cream shop", "Dessert shop", "Donut shop", "Bagel shop", "Sandwich shop",
                "Fast food restaurant", "Food truck", "Food court", "Food market", "Farmers market",
                "Thai restaurant", "Mexican restaurant", "Japanese restaurant", "Sushi restaurant",
                "Ramen restaurant", "Chinese restaurant", "Korean restaurant", "Vietnamese restaurant",
                "Indian restaurant", "Italian restaurant", "Pizza restaurant", "Mediterranean restaurant",
                "Seafood restaurant", "Steakhouse", "Diner", "Brunch spot", "Bar", "Cocktail bar",
                "Wine bar", "Brewery", "Pub", "Dive bar", "Rooftop bar", "Nightlife"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: outdoorsNature,
            group: "Outdoors & nature",
            detail: "Parks, trails, beaches, overlooks",
            defaultSubcategory: "Park",
            symbolName: "tree.fill",
            aliases: [
                outdoorsNature, "outdoors", "nature", "hike", "hiking", "trail", "waterfall",
                "hot spring", "canyon", "mountain", "observatory", "park", "national park",
                "playground", "garden", "plaza", "beach", "lake", "campground"
            ],
            subcategories: [
                "Park", "National park", "State park", "Garden", "Botanical garden", "Beach",
                "Lake", "River", "Waterfall", "Hot spring", "Hike or trail", "Trailhead",
                "Scenic overlook", "Canyon", "Mountain", "Campground", "Picnic area",
                "Dog park", "Playground", "Pier", "Marina", "Nature preserve", "Observatory"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: artsCultureFaith,
            group: "Arts, culture & faith",
            detail: "Museums, galleries, temples, landmarks",
            defaultSubcategory: "Museum",
            symbolName: "sparkles",
            aliases: [
                artsCultureFaith, "arts", "culture", "faith", "museum", "gallery", "art gallery",
                "theater", "theatre", "historic", "landmark", "monument", "library", "church",
                "temple", "shrine", "mosque", "synagogue", "chapel", "cathedral", "meditation"
            ],
            subcategories: [
                "Museum", "Art museum", "Gallery", "Art gallery", "Public art", "Theater",
                "Historic site", "Landmark", "Monument", "Cultural center", "Library",
                "Bookstore", "Temple", "Shrine", "Church", "Cathedral", "Mosque",
                "Synagogue", "Chapel", "Meditation center", "Spiritual place"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: entertainment,
            group: "Entertainment",
            detail: "Venues, movies, games, attractions",
            defaultSubcategory: "Entertainment venue",
            symbolName: "ticket.fill",
            aliases: [
                entertainment, "entertainment", "tourist attraction", "attraction", "venue",
                "movie", "cinema", "concert", "music venue", "arena", "stadium", "arcade",
                "bowling", "zoo", "aquarium", "amusement", "theme park", "comedy"
            ],
            subcategories: [
                "Entertainment venue", "Tourist attraction", "Movie theater", "Music venue",
                "Concert hall", "Comedy club", "Theater", "Arena", "Stadium", "Arcade",
                "Bowling alley", "Karaoke", "Pool hall", "Casino", "Zoo", "Aquarium",
                "Amusement park", "Theme park", "Escape room", "Event venue"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: healthWellness,
            group: "Health & wellness",
            detail: "Care, spas, pharmacies, recovery",
            defaultSubcategory: "Wellness studio",
            symbolName: "cross.case.fill",
            aliases: [
                healthWellness, "health", "wellness", "wellness studio", "spa", "massage",
                "meditation", "hospital", "urgent care", "medical center", "health center",
                "clinic", "doctor", "dentist", "pharmacy", "drugstore", "therapy", "salon"
            ],
            subcategories: [
                "Wellness studio", "Spa", "Massage", "Sauna", "Bathhouse", "Meditation center",
                "Therapy office", "Hospital", "Urgent care", "Medical center", "Clinic",
                "Doctor", "Dentist", "Optometrist", "Pharmacy", "Drugstore", "Chiropractor",
                "Acupuncture", "Physical therapy", "Recovery studio"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: sportsFitness,
            group: "Sports & fitness",
            detail: "Gyms, courts, studios, fields",
            defaultSubcategory: "Gym",
            symbolName: "dumbbell.fill",
            aliases: [
                sportsFitness, "sports", "fitness", "gym", "fitness center", "training",
                "strength", "workout", "pilates", "reformer", "lagree", "yoga", "barre",
                "climbing gym", "boxing gym", "court", "field", "skate", "swim", "surf"
            ],
            subcategories: [
                "Gym", "Fitness center", "Training studio", "Pilates studio", "Reformer pilates",
                "Lagree studio", "Yoga studio", "Barre studio", "Boxing gym", "Martial arts gym",
                "Climbing gym", "Dance studio", "Spin studio", "Tennis court", "Basketball court",
                "Soccer field", "Baseball field", "Golf course", "Pool", "Skate park",
                "Ski area", "Surf spot"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: shopping,
            group: "Shopping",
            detail: "Stores, markets, supplies, malls",
            defaultSubcategory: "Shop",
            symbolName: "bag.fill",
            aliases: [
                shopping, "shopping", "shop", "store", "retail", "art supply store", "mall",
                "boutique", "market", "grocery", "bookstore", "flower", "hardware", "furniture"
            ],
            subcategories: [
                "Shop", "Store", "Boutique", "Market", "Mall", "Grocery store", "Convenience store",
                "Art supply store", "Bookstore", "Record store", "Clothing store", "Shoe store",
                "Jewelry store", "Gift shop", "Flower shop", "Home goods store", "Furniture store",
                "Hardware store", "Electronics store", "Vintage store", "Thrift store", "Pet store"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: services,
            group: "Services",
            detail: "Salons, repairs, pet care, errands",
            defaultSubcategory: "Service business",
            symbolName: "scissors",
            aliases: [
                services, "service", "services", "salon", "barber", "nail", "laundry",
                "dry cleaner", "tailor", "repair", "bank", "atm", "post office", "shipping",
                "veterinarian", "veterinary", "animal hospital", "animal service", "pet clinic"
            ],
            subcategories: [
                "Service business", "Hair salon", "Barber", "Nail salon", "Beauty salon",
                "Laundry", "Dry cleaner", "Tailor", "Shoe repair", "Phone repair", "Auto repair",
                "Car wash", "Bank", "ATM", "Post office", "Shipping center", "Veterinarian",
                "Veterinary clinic", "Animal hospital", "Pet clinic", "Pet groomer"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: lodging,
            group: "Lodging",
            detail: "Hotels, resorts, stays",
            defaultSubcategory: "Hotel",
            symbolName: "bed.double.fill",
            aliases: [
                lodging, "lodging", "hotel", "motel", "resort", "inn", "hostel", "bnb",
                "bed and breakfast", "boutique hotel", "3 star hotel", "4 star hotel", "5 star hotel"
            ],
            subcategories: [
                "Hotel", "Motel", "Resort", "Boutique hotel", "Inn", "Hostel", "Bed and breakfast",
                "Vacation rental", "Cabin", "Camp stay", "3-star hotel", "4-star hotel", "5-star hotel"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: transportationTransit,
            group: "Transportation & transit",
            detail: "Airports, stations, parking, rides",
            defaultSubcategory: "Transit stop",
            symbolName: "tram.fill",
            aliases: [
                transportationTransit, "transportation", "transportation and transit", "transit",
                "transit station", "airport", "train station", "bus station", "ferry", "subway",
                "station", "parking", "garage", "rental car", "gas station", "ev charging"
            ],
            subcategories: [
                "Transit stop", "Airport", "Train station", "Bus station", "Subway station",
                "Light rail station", "Ferry terminal", "Taxi stand", "Ride pickup", "Parking lot",
                "Parking garage", "Rental car", "Gas station", "EV charging station", "Bike share",
                "Car share", "Rest stop"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: education,
            group: "Education",
            detail: "Schools, campuses, classes, learning",
            defaultSubcategory: "School",
            symbolName: "graduationcap.fill",
            aliases: [
                education, "education", "school", "university", "college", "campus", "class",
                "learning", "tutor", "academy", "library"
            ],
            subcategories: [
                "School", "Elementary school", "High school", "College", "University", "Campus",
                "Preschool", "Daycare", "Tutoring center", "Language school", "Music school",
                "Art class", "Cooking class", "Workshop", "Library", "Study spot"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: workVenues,
            group: "Work & venues",
            detail: "Offices, coworking, meetings, events",
            defaultSubcategory: "Coworking space",
            symbolName: "building.2.fill",
            aliases: [
                workVenues, "work", "venue", "office", "coworking", "co working", "conference",
                "meeting", "event space", "studio", "warehouse", "production"
            ],
            subcategories: [
                "Coworking space", "Office", "Meeting room", "Conference center", "Event space",
                "Studio", "Production studio", "Photo studio", "Warehouse", "Workshop space",
                "Convention center", "Business center", "Rooftop venue", "Private event room"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: homeNeighborhood,
            group: "Home & neighborhood",
            detail: "Homes, buildings, blocks, local anchors",
            defaultSubcategory: "Neighborhood spot",
            symbolName: "house.fill",
            aliases: [
                homeNeighborhood, "home", "neighborhood", "apartment", "condo", "house",
                "building", "block", "local spot", "landmark"
            ],
            subcategories: [
                "Neighborhood spot", "Home", "Apartment building", "Condo", "House", "Block",
                "Courtyard", "Community garden", "Neighborhood landmark", "Local shortcut",
                "Viewpoint", "Meetup spot", "Building", "Lobby"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: publicServices,
            group: "Public services",
            detail: "Civic, safety, government, utilities",
            defaultSubcategory: "Public service",
            symbolName: "building.columns.fill",
            aliases: [
                publicServices, "public service", "public services", "government", "city hall",
                "courthouse", "police", "fire station", "embassy", "dmv", "utility"
            ],
            subcategories: [
                "Public service", "Government office", "City hall", "Courthouse", "Police station",
                "Fire station", "Embassy", "Consulate", "DMV", "Public restroom", "Recycling center",
                "Utility office", "Community center", "Civic building"
            ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: fallbackPlace,
            group: "Place",
            detail: "Internal fallback for weak provider data",
            defaultSubcategory: nil,
            symbolName: "mappin",
            aliases: [fallbackPlace, "point of interest", "unknown"],
            subcategories: [],
            isEditable: false
        )
    ]

    static let allowedCategories = taxonomy.map(\.id)
    static let editableCategories = taxonomy.filter(\.isEditable).map(\.id)

    private static let legacyDefaultSubcategories: [String: String] = [
        "coffee": "Coffee shop",
        "coffee shop": "Coffee shop",
        "cafe": "Cafe",
        "bakery": "Bakery",
        "restaurant": "Restaurant",
        "bar": "Bar",
        "hike": "Hike or trail",
        "trail": "Trail",
        "park": "Park",
        "gym": "Gym",
        "fitness studio": "Fitness studio",
        "pilates studio": "Pilates studio",
        "spiritual": "Spiritual place",
        "hospital": "Hospital",
        "pharmacy": "Pharmacy",
        "veterinarian": "Veterinarian",
        "hotel": "Hotel",
        "shop": "Shop",
        "transportation": "Transit stop"
    ]

    private static let legacyPrimaryCategories: [String: String] = [
        "coffee": foodDrink,
        "coffee shop": foodDrink,
        "cafe": foodDrink,
        "bakery": foodDrink,
        "restaurant": foodDrink,
        "bar": foodDrink,
        "hike": outdoorsNature,
        "trail": outdoorsNature,
        "park": outdoorsNature,
        "gym": sportsFitness,
        "fitness studio": sportsFitness,
        "pilates studio": sportsFitness,
        "spiritual": artsCultureFaith,
        "hospital": healthWellness,
        "pharmacy": healthWellness,
        "veterinarian": services,
        "hotel": lodging,
        "shop": shopping,
        "transportation": transportationTransit
    ]

    static func primary(for pointCategory: MKPointOfInterestCategory?, name: String? = nil) -> String? {
        if let nameCategory = primaryFromName(name, pointCategory: pointCategory) {
            return nameCategory
        }

        if #available(iOS 18.0, *) {
            switch pointCategory {
            case .animalService:
                return services
            case .hiking:
                return outdoorsNature
            case .rockClimbing, .skatePark, .skating, .skiing, .surfing, .swimming:
                return sportsFitness
            default:
                break
            }
        }

        switch pointCategory {
        case .cafe, .bakery, .restaurant, .foodMarket, .brewery, .winery, .nightlife:
            return foodDrink
        case .park, .nationalPark:
            return outdoorsNature
        case .hospital:
            return healthWellness
        case .fitnessCenter:
            return sportsFitness
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
        let subcategory = subcategory(forRawValue: raw ?? rawCategory, primaryCategory: primary)

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
            subcategory: normalizedSubcategory(subcategory) ?? Self.subcategory(forRawValue: primaryCategory, primaryCategory: primary),
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
            subcategory: primary == fallbackPlace ? nil : subcategory,
            sourceLabel: label
        )
    }

    static func display(for category: String, sourceLabel: String = "suggested") -> PlaceCategoryDisplay {
        display(for: assignment(forRawCategory: category), sourceLabel: sourceLabel)
    }

    static func questionCategory(for category: String) -> String {
        let normalized = normalizedCategoryText(category)
        guard !normalized.isEmpty else { return fallbackPlace }

        if containsAny(normalized, ["coffee", "cafe", "espresso", "roaster", "tea shop"]) {
            return "coffee"
        }

        if containsAny(normalized, ["hike", "trail", "waterfall", "hot spring", "canyon", "mountain", "trailhead"]) {
            return "hike"
        }

        if containsAny(normalized, ["bar", "brewery", "winery", "cocktail", "pub", "nightlife", "dive bar"]) {
            return "bar"
        }

        if containsAny(normalized, ["restaurant", "taqueria", "ramen", "sushi", "pizza", "diner", "kitchen", "grill", "noodle", "taco", "brunch", "fast food", "food truck"]) {
            return "restaurant"
        }

        if containsAny(normalized, ["park", "garden", "beach", "playground", "dog park", "picnic", "plaza"]) {
            return "park"
        }

        switch primaryCategory(for: category) {
        case foodDrink:
            return "restaurant"
        case outdoorsNature:
            return "park"
        case sportsFitness:
            return "gym"
        default:
            return primaryCategory(for: category)
        }
    }

    static func questionCategory(for assignment: PlaceCategoryAssignment) -> String {
        questionCategory(for: assignment.subcategory ?? assignment.primaryCategory)
    }

    static func primaryCategory(for category: String) -> String {
        let normalized = normalizedCategoryText(category)
        guard !normalized.isEmpty else { return fallbackPlace }
        if let legacyPrimary = legacyPrimaryCategories[normalized] {
            return legacyPrimary
        }

        if let entry = entry(for: normalized) {
            return entry.id
        }

        let padded = " \(normalized) "
        for entry in taxonomy where entry.id != fallbackPlace {
            if entry.aliases.contains(where: { alias in
                let normalizedAlias = normalizedCategoryText(alias)
                return normalizedAlias == normalized || (!normalizedAlias.isEmpty && padded.contains(" \(normalizedAlias) "))
            }) {
                return entry.id
            }
        }

        return fallbackPlace
    }

    static func normalizedPrimaryCategory(_ value: String) -> String {
        let normalized = normalizedCategoryText(value)
        if let entry = entry(for: normalized) {
            return entry.id
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

    static func categoryDetail(for category: String) -> String {
        entry(for: category)?.detail ?? ""
    }

    static func defaultSubcategory(for category: String) -> String? {
        entry(for: category)?.defaultSubcategory
    }

    static func defaultSubcategory(forRawCategory rawCategory: String, normalizedPrimary primary: String) -> String? {
        if primary == fallbackPlace {
            return nil
        }

        let normalized = normalizedCategoryText(rawCategory)
        return legacyDefaultSubcategories[normalized] ?? defaultSubcategory(for: primary)
    }

    static func categoryInferenceInput(category: String, rawProviderType: String?) -> String {
        guard let rawProviderType,
              primaryCategory(for: rawProviderType) != fallbackPlace
        else {
            return category
        }

        return rawProviderType
    }

    static func normalizedCategoryText(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/ ")).inverted)
            .joined(separator: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func subcategory(forRawValue rawValue: String, primaryCategory: String) -> String? {
        if primaryCategory == fallbackPlace {
            return nil
        }

        let normalized = normalizedCategoryText(rawValue)
        guard !normalized.isEmpty else {
            return defaultSubcategory(for: primaryCategory)
        }

        if let legacyDefault = legacyDefaultSubcategories[normalized] {
            return legacyDefault
        }

        if let entry = entry(for: primaryCategory),
           normalized == normalizedCategoryText(entry.id) || normalized == normalizedCategoryText(entry.group) {
            return entry.defaultSubcategory
        }

        return normalizedSubcategory(rawValue) ?? defaultSubcategory(for: primaryCategory)
    }

    private static func entry(for category: String) -> PlaceCategoryTaxonomyEntry? {
        let normalized = normalizedCategoryText(category)
        return taxonomy.first { entry in
            entry.id == category
                || normalizedCategoryText(entry.id) == normalized
                || normalizedCategoryText(entry.group) == normalized
        }
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
            return services
        }

        if containsAny(normalizedName, ["temple", "shrine", "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue"]) {
            return artsCultureFaith
        }

        if containsAny(normalizedName, ["hospital", "medical center", "health center", "urgent care", "pharmacy", "drugstore", "wellness studio", "spa"]) {
            return healthWellness
        }

        if containsAny(normalizedName, ["pilates", "plankhaus", "lagree", "reformer", " gym ", "fitness", "training", "strength", "workout"]) {
            return sportsFitness
        }

        let isFitnessCategory = pointCategory == .fitnessCenter
        if isFitnessCategory, containsAny(normalizedName, ["studio", "barre", "yoga", "stretch"]) {
            return sportsFitness
        }

        return nil
    }

    private static func containsAny(_ normalizedName: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            normalizedName.contains(normalizedCategoryText(needle))
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
