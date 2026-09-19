import MapKit

enum PlaceCategorySource: String, Codable {
    case provider
    case deterministic
    case ai
    case user
    case snapshot
    case consensus
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
        let normalizedSource = PlaceCategorySource(rawValue: source) ?? .unknown
        let requestedPrimary = WanderPlaceCategory.normalizedPrimaryCategory(primaryCategory)
        let keepsRequestedTaxonomy = normalizedSource == .user
            || normalizedSource == .snapshot
            || normalizedSource == .consensus
        let evidenceAssignment = keepsRequestedTaxonomy
            ? nil
            : WanderPlaceCategory.categoryEvidenceAssignment(
                subcategory: subcategory,
                rawProviderType: rawProviderType
            )
        let normalizedPrimary = evidenceAssignment?.primaryCategory ?? requestedPrimary
        let requestedSubcategory = WanderPlaceCategory.canonicalSubcategory(
            subcategory,
            primaryCategory: requestedPrimary
        )
        let inferredSubcategory: String?
        if keepsRequestedTaxonomy {
            inferredSubcategory = requestedSubcategory
        } else if normalizedPrimary != requestedPrimary
                    || WanderPlaceCategory.isDefaultSubcategory(
                        requestedSubcategory,
                        primaryCategory: requestedPrimary
                    ) {
            inferredSubcategory = evidenceAssignment?.subcategory ?? requestedSubcategory
        } else {
            inferredSubcategory = requestedSubcategory ?? evidenceAssignment?.subcategory
        }

        self.primaryCategory = normalizedPrimary
        self.subcategory = WanderPlaceCategory.canonicalSubcategory(
            inferredSubcategory,
            primaryCategory: normalizedPrimary
        ) ?? WanderPlaceCategory.defaultSubcategory(
            forRawCategory: rawProviderType ?? primaryCategory,
            normalizedPrimary: normalizedPrimary
        )
        self.source = normalizedSource.rawValue
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

    func compactType(foodType: String? = nil) -> String {
        if primaryCategory == WanderPlaceCategory.restaurantsFood {
            let broadCategoryKeys = Set([
                primaryCategory,
                category,
                "Restaurants & Food",
                "food_drink",
                "food and drink"
            ].map(WanderPlaceCategory.normalizedCategoryText))
            return uniqueDisplayValues([foodType, subcategory])
                .first { !broadCategoryKeys.contains(WanderPlaceCategory.normalizedCategoryText($0)) }
                ?? "Restaurant"
        }
        let compactType = uniqueDisplayValues([subcategory, category]).first ?? ""
        if primaryCategory == WanderPlaceCategory.coffeeTeaSweets {
            switch WanderPlaceCategory.normalizedCategoryText(compactType) {
            case "cafe", "coffee", "coffeehouse":
                return "Coffee shop"
            default:
                break
            }
        }
        return compactType
    }

    private func uniqueDisplayValues(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            let key = WanderPlaceCategory.normalizedCategoryText(value)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return value
        }
    }
}

enum RestaurantCuisineInferenceSource: String, Equatable {
    case providerType
    case subcategory
    case category
    case placeName
    case website
}

struct RestaurantCuisineInference: Equatable {
    let cuisine: String
    let confidence: Double
    let source: RestaurantCuisineInferenceSource

    var reason: String {
        switch source {
        case .providerType:
            "Suggested from the place type"
        case .subcategory:
            "Suggested from the restaurant type"
        case .category:
            "Suggested from category details"
        case .placeName:
            "Suggested from the place name"
        case .website:
            "Suggested from the restaurant website"
        }
    }
}

struct RestaurantCuisineUse: Equatable {
    let cuisine: String
    let savedAt: Date
}

enum PlaceMemoryAttributeKeys {
    static let personalLabels = "personal_labels"
    static let restaurantCuisine = "restaurant_cuisine"
    static let droppedPinName = "dropped_pin_name"
}

enum DroppedPinNamePolicy {
    static let fallbackName = "Dropped Pin"
    static let maximumLength = 80

    static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    static func customName(from attributes: [LocalPlaceAttribute]) -> String? {
        guard let attribute = attributes.last(where: {
            $0.questionKey == PlaceMemoryAttributeKeys.droppedPinName
        }) else { return nil }
        return decodedName(from: attribute.valueJSON)
    }

    static func customName(from attributes: [PlaceAttributeDraft]) -> String? {
        guard let attribute = attributes.last(where: {
            $0.questionKey == PlaceMemoryAttributeKeys.droppedPinName
        }) else { return nil }
        return decodedName(from: attribute.valueJSON)
    }

    static func displayName(
        canonicalName: String,
        sourceProvider: String?,
        attributes: [LocalPlaceAttribute]
    ) -> String {
        guard sourceProvider == "coordinate" else { return canonicalName }
        return customName(from: attributes) ?? fallbackName
    }

    private static func decodedName(from valueJSON: String) -> String? {
        guard let data = valueJSON.data(using: .utf8),
              let value = try? JSONDecoder().decode(String.self, from: data)
        else { return nil }
        return normalized(value)
    }
}

struct PlaceMemoryDefaultSuggestions: Equatable {
    let tagOptions: [String]
    let defaultTags: [String]
    let labelOptions: [String]
    let defaultLabels: [String]

    var unifiedTagOptions: [String] {
        PlaceMemoryTagPresentation.suggestions(tagOptions + labelOptions)
    }

    var unifiedDefaultTags: [String] {
        let optionKeys = Set(unifiedTagOptions.map(WanderPlaceCategory.normalizedCategoryText))
        return Self.unique(defaultTags + defaultLabels).filter {
            optionKeys.contains(WanderPlaceCategory.normalizedCategoryText($0))
        }
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()

        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = WanderPlaceCategory.normalizedCategoryText(trimmed)
            return seen.insert(key).inserted ? trimmed : nil
        }
    }
}

enum PlaceMemoryDefaultCatalog {
    static func suggestions(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        locality: String? = nil,
        localTagOptions: [String] = [],
        localLabelOptions: [String] = []
    ) -> PlaceMemoryDefaultSuggestions {
        let primary = WanderPlaceCategory.normalizedPrimaryCategory(primaryCategory)
        let curated = curatedOptions(primaryCategory: primary, subcategory: subcategory, cuisine: cuisine, status: status)
        // Keep learned wording available without rebuilding the old, sprawling
        // tag + label catalog. Selected values are included separately by the UI.
        let learned = PlaceMemoryTagPresentation.suggestions(localTagOptions + localLabelOptions, limit: 2)
        let options = PlaceMemoryTagPresentation.suggestions(learned + curated)
        // Locality already belongs to the place. Do not suggest redundant city
        // labels or automatically assign a reason, favorite, or occasion.
        _ = locality
        return PlaceMemoryDefaultSuggestions(
            tagOptions: options,
            defaultTags: [],
            labelOptions: [],
            defaultLabels: []
        )
    }

    static func tagOptions(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        localOptions: [String] = []
    ) -> [String] {
        suggestions(primaryCategory: primaryCategory, subcategory: subcategory, cuisine: cuisine,
                    status: status, localTagOptions: localOptions).tagOptions
    }

    static func defaultTags(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus
    ) -> [String] {
        []
    }

    private static func curatedOptions(
        primaryCategory: String, subcategory: String?, cuisine: String?, status: PlaceStatus
    ) -> [String] {
        let detail = WanderPlaceCategory.normalizedCategoryText(subcategory)
        let foodType = WanderPlaceCategory.normalizedCategoryText(cuisine)
        let returning = status == .been ? "regular spot" : "try soon"
        let options: [String]

        switch primaryCategory {
        case WanderPlaceCategory.restaurantsFood:
            let restaurant = [detail, foodType].joined(separator: " ")
            if containsAny(restaurant, ["breakfast", "brunch", "bagel", "bakery"]) {
                options = ["morning stop", "weekend brunch", "quick bite", "solo meal", "bring visitors", "catch up", returning]
            } else if containsAny(restaurant, ["steakhouse", "fine dining", "oyster bar", "fondue"]) {
                options = ["special occasion", "date night", "dinner with friends", "work dinner", "bring visitors", "treat myself", returning]
            } else {
                options = ["quick bite", "date night", "dinner with friends", "solo meal", "bring visitors", "special occasion", returning]
            }
            if let cuisine = cuisine?.trimmingCharacters(in: .whitespacesAndNewlines), !cuisine.isEmpty {
                return PlaceMemoryTagPresentation.suggestions(["\(cuisine) craving"] + options, limit: 8)
            }
        case WanderPlaceCategory.coffeeTeaSweets:
            if containsAny(detail, ["bakery", "bagel", "donut", "cake", "pastry", "dessert", "ice cream", "gelato", "candy", "chocolate", "confectionery", "acai", "smoothie", "juice"]) {
                options = ["sweet treat", "bring home", "gift idea", "after dinner", "bring visitors", returning]
            } else {
                options = ["morning stop", "work session", "catch up", "solo time", "sweet treat", "bring visitors", returning]
            }
        case WanderPlaceCategory.barsNightlife:
            if containsAny(detail, ["club", "disco", "karaoke", "dance hall"]) {
                options = ["night out", "dancing", "celebration", "bring friends", "weekend plan", "after dinner", returning]
            } else {
                options = ["date drinks", "drinks with friends", "after dinner", "celebration", "late night", "bring visitors", returning]
            }
        case WanderPlaceCategory.outdoorsNature:
            if containsAny(detail, ["beach", "lake", "river", "hot spring", "marina"]) {
                options = ["water day", "sunset outing", "solo reset", "bring friends", "bring visitors", "photo outing", returning]
            } else if containsAny(detail, ["hike", "trail", "hiking", "mountain", "waterfall", "nature preserve"]) {
                options = ["day hike", "weekend plan", "solo reset", "bring friends", "bring visitors", "photo outing", returning]
            } else {
                options = ["weekend plan", "sunset outing", "solo reset", "bring friends", "bring visitors", "photo outing", returning]
            }
        case WanderPlaceCategory.thingsToDo:
            options = ["date idea", "bring visitors", "rainy day", "with friends", "solo outing", "weekend plan", returning]
        case WanderPlaceCategory.shopping:
            options = ["gift idea", "browse day", "errand stop", "home project", "treat myself", "bring visitors", returning]
        case WanderPlaceCategory.wellnessFitness:
            let isAdditionalSportsSubtype = ["beach tennis", "beach volleyball", "surf school"].contains(detail)
            if isAdditionalSportsSubtype || containsAny(detail, ["gym", "fitness", "crossfit", "pilates", "yoga", "studio", "court", "sport", "field", "pool", "climbing", "boxing", "dance", "golf", "rink"]) {
                options = ["workout", "with friends", "practice", "try a class", "while traveling", returning]
            } else {
                options = ["self-care", "recovery", "with a friend", "while traveling", "backup option", returning]
            }
        case WanderPlaceCategory.stays:
            options = ["weekend away", "work trip", "family trip", "trip base", "special occasion", "longer stay", status == .been ? "stay again" : "next trip"]
        case WanderPlaceCategory.servicesErrands:
            options = ["errand stop", "home project", "life admin", "while traveling", "backup option", returning]
        case WanderPlaceCategory.travelTransit:
            options = ["road trip", "airport trip", "commute", "route stop", "meet here", "backup route", status == .been ? "usual route" : "next trip"]
        case WanderPlaceCategory.workEducation:
            options = ["study session", "work session", "meeting", "research", "learning", returning]
        case WanderPlaceCategory.civicFaith:
            options = ["community", "service visit", "faith", "bring visitors", "research", "family visit", returning]
        case WanderPlaceCategory.areasAddresses:
            options = ["meet here", "area to explore", "trip base", "neighborhood walk", "bring visitors", "address to keep", returning]
        default:
            options = ["route stop", "while traveling", "meet here", "backup option", "address to keep", returning]
        }
        return options
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }
}

enum PlacePersonalLabelSuggestions {
    static func options(
        category: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        locality: String? = nil,
        localOptions: [String] = []
    ) -> [String] {
        PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: category,
            subcategory: subcategory,
            cuisine: cuisine,
            status: status,
            locality: locality,
            localLabelOptions: localOptions
        ).labelOptions
    }

    static func defaultValues(
        category: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        locality: String? = nil
    ) -> [String] {
        PlaceMemoryDefaultCatalog.suggestions(
            primaryCategory: category,
            subcategory: subcategory,
            cuisine: cuisine,
            status: status,
            locality: locality
        ).defaultLabels
    }
}

private extension Array where Element == String {
    func containsCaseInsensitive(_ value: String) -> Bool {
        contains { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}

struct PlaceCategoryTaxonomyEntry: Equatable {
    let id: String
    let group: String
    let detail: String
    let defaultSubcategory: String?
    let emoji: String
    let aliases: [String]
    let subcategories: [String]
    let isEditable: Bool
}

enum PlaceCategorySubcategoryRole: String, Equatable {
    case type
    case cuisine
}

struct PlaceCategorySubcategoryGroup: Equatable {
    let title: String
    let subcategories: [String]
    let role: PlaceCategorySubcategoryRole

    init(
        title: String,
        subcategories: [String],
        role: PlaceCategorySubcategoryRole = .type
    ) {
        self.title = title
        self.subcategories = subcategories
        self.role = role
    }
}

enum WanderPlaceCategory {
    private struct ProviderCategoryMetadata {
        let canonicalType: String
        let primaryCategory: String
        let subcategory: String
    }

    static let restaurantsFood = "restaurants_food"
    static let coffeeTeaSweets = "coffee_tea_sweets"
    static let barsNightlife = "bars_nightlife"
    static let outdoorsNature = "outdoors_nature"
    static let thingsToDo = "things_to_do"
    static let shopping = "shopping"
    static let wellnessFitness = "wellness_fitness"
    static let stays = "stays"
    static let servicesErrands = "services_errands"
    static let travelTransit = "travel_transit"
    static let workEducation = "work_education"
    static let civicFaith = "civic_faith"
    static let areasAddresses = "areas_addresses"
    static let facilitiesOther = "facilities_other"
    static let fallbackPlace = "place"

    // Legacy constants retained so older saved filters and call sites normalize into the new taxonomy.
    static let foodDrink = restaurantsFood
    static let artsCultureFaith = thingsToDo
    static let entertainment = thingsToDo
    static let healthWellness = wellnessFitness
    static let sportsFitness = wellnessFitness
    static let services = servicesErrands
    static let lodging = stays
    static let transportationTransit = travelTransit
    static let education = workEducation
    static let workVenues = workEducation
    static let homeNeighborhood = areasAddresses
    static let publicServices = civicFaith

    static let taxonomy: [PlaceCategoryTaxonomyEntry] = [
        PlaceCategoryTaxonomyEntry(
            id: restaurantsFood,
            group: "Restaurants & Food",
            detail: "Restaurants, food types, quick bites",
            defaultSubcategory: "Restaurant",
            emoji: "🍽️",
            aliases: [
            "restaurants_food", "restaurants food", "restaurants and food", "food_drink", "food drink",
            "food and drink", "restaurant", "restaurants", "fast food", "fine dining", "casual family", "diner",
            "bistro", "buffet", "food court", "takeout", "cafeteria", "breakfast", "brunch", "sandwich", "deli",
            "pizza", "burger", "barbecue", "ramen", "noodle", "dumpling", "bao", "bao bun", "bao buns", "baozi", "dim sum", "hot pot", "taco", "taqueria",
            "thai restaurant", "sushi restaurant", "korean bbq"
        ],
            subcategories: [
            "Thai", "Vietnamese", "Chinese", "Korean", "Japanese", "Indian", "Asian fusion", "Sushi", "Ramen",
            "Dumplings", "Bao buns", "Noodles", "Dim sum", "Hot pot", "Cantonese", "Taiwanese", "Izakaya", "Yakitori",
            "Yakiniku", "North Indian", "South Indian", "Pakistani", "Sri Lankan", "Bangladeshi", "Nepalese",
            "Malaysian", "Singaporean", "Indonesian", "Filipino", "Burmese", "Cambodian", "Laotian", "Asian",
            "Tibetan", "Mongolian", "Georgian", "Armenian", "Uzbek", "Mongolian BBQ", "Korean BBQ",
            "Japanese BBQ", "Japanese curry", "Tonkatsu", "Afghan", "Middle Eastern", "Lebanese", "Persian",
            "Turkish", "Israeli", "Palestinian", "Syrian", "Iraqi", "Jordanian", "Yemeni", "Egyptian",
            "Moroccan", "Tunisian", "Algerian", "Ethiopian", "Eritrean", "Somali", "Kenyan", "Nigerian",
            "Ghanaian", "Senegalese", "South African", "African", "Falafel", "Gyro", "Kebab", "Shawarma",
            "Halal", "Italian", "Mediterranean", "Greek", "French", "Spanish", "Tapas", "Portuguese", "Basque",
            "German", "Austrian", "Bavarian", "Swiss", "Dutch", "Belgian", "British", "Irish", "Scandinavian",
            "Swedish", "Norwegian", "Finnish", "Danish", "Polish", "Ukrainian", "Russian", "Czech", "Slovak",
            "Hungarian", "Romanian", "Croatian", "Serbian", "Bosnian", "Bulgarian", "Albanian", "Slovenian",
            "Lithuanian", "European", "Eastern European", "Pizza", "Fish & chips", "Fondue", "American",
            "Canadian", "Mexican", "Tex-Mex", "Caribbean", "Jamaican", "Puerto Rican", "Dominican", "Haitian",
            "Panamanian", "Cuban", "Brazilian", "Argentinian", "Colombian", "Chilean", "Peruvian",
            "Venezuelan", "Ecuadorian", "Bolivian", "Uruguayan", "Salvadoran", "Guatemalan", "South American",
            "Latin American", "Southwestern", "Cajun", "Californian", "Hawaiian", "Poke", "Australian",
            "New Zealand", "Fijian", "Samoan", "Tongan", "Burgers", "Diner", "Hot dogs", "Barbecue", "Wings",
            "Steakhouse", "Bar & grill", "Taco stand", "Taco truck", "Burrito", "Taco", "Sandwich", "Bagel",
            "Deli", "Salad", "Bistro", "Food court", "Breakfast", "Brunch", "Soup", "Chicken", "Seafood",
            "Oyster bar", "Vegetarian", "Vegan", "Gluten-free", "Snack bar", "Gastropub"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: coffeeTeaSweets,
            group: "Coffee, Tea, & Sweets",
            detail: "Coffee, tea, bakeries",
            defaultSubcategory: "Coffee shop",
            emoji: "☕️",
            aliases: [
            "coffee_tea_sweets", "coffee tea sweets", "coffee tea and sweets", "coffee", "coffee shop", "cafe",
            "espresso", "roaster", "roastery", "tea", "tea house", "tea store", "bakery", "dessert", "sweets",
            "juice", "smoothie", "acai", "ice cream", "gelato", "candy", "chocolate", "cat cafe", "dog cafe"
        ],
            subcategories: [
            "Coffee shop", "Cafe", "Coffee stand", "Coffee lounge", "Roastery", "Tea house", "Tea store", "Juice shop",
            "Smoothie shop", "Acai", "Bakery", "Bagel shop", "Donut shop", "Cake shop", "Pastry shop",
            "Dessert shop", "Dessert restaurant", "Ice cream", "Gelato", "Candy store", "Chocolate shop",
            "Chocolate factory", "Chocolate lounge", "Confectionery", "Cat cafe", "Dog cafe"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: barsNightlife,
            group: "Bars & Nightlife",
            detail: "Bars, lounges, clubs",
            defaultSubcategory: "Bar",
            emoji: "🍸",
            aliases: [
            "bars_nightlife", "bars nightlife", "bars and nightlife", "bar", "bars", "nightlife",
            "mkpoicategorynightlife", "cocktail", "pub", "sports bar", "wine bar", "cider bar", "sake bar",
            "game bar", "lounge", "club", "disco",
            "brewery", "brewpub", "distillery", "winery", "vineyard", "nightclub", "karaoke", "live music", "comedy club",
            "casino"
        ],
            subcategories: [
                "Bar", "Cocktail bar", "Pub", "Irish pub", "Billiards", "Sports bar", "Wine bar", "Cider bar",
                "Sake bar", "Game bar", "Gastropub", "Bar & grill", "Dance hall", "Club", "Disco", "Lounge",
                "Hookah bar", "Beer garden", "Jazz club", "Hi-fi lounge", "Brewery", "Brewpub", "Winery",
                "Vineyard", "Nightclub", "Karaoke", "Live music", "Comedy club", "Casino", "Distillery"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: outdoorsNature,
            group: "Outdoors & Nature",
            detail: "Parks, trails, water",
            defaultSubcategory: "Park",
            emoji: "🌲",
            aliases: [
            "outdoors_nature", "outdoors nature", "outdoors and nature", "outdoors", "nature", "hike", "hiking",
            "trail", "trailhead", "waterfall", "hot spring", "canyon", "mountain", "park", "national park",
            "playground", "garden", "beach", "dog beach", "lake", "campground", "rv park", "marina", "ski resort", "skate park"
        ],
            subcategories: [
            "Park", "City park", "State park", "National park", "Hiking area", "Trail", "Hike", "Beach", "Dog beach", "Lake",
            "River", "Island", "Woods/forest", "Mountain peak", "Scenic spot", "Viewpoint", "Overlook",
            "Waterfall", "Hot spring", "Cave", "Nature preserve", "Wildlife refuge", "Wildlife park",
            "Botanical garden", "Garden", "Picnic area", "Dog park", "Playground", "Campground", "RV park",
            "Dispersed camping", "Cabin", "Cottage", "Marina", "Fishing pier", "Fishing pond", "Fishing charter",
            "Ski resort", "Cycling park", "Skate park", "Off-roading area", "Adventure sports",
            "Surf", "Surf break", "Kayak/canoe rental"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: thingsToDo,
            group: "Things To Do",
            detail: "Attractions, arts, venues",
            defaultSubcategory: "Tourist attraction",
            emoji: "🎟️",
            aliases: [
            "things_to_do", "things to do", "arts_culture_faith", "arts culture faith", "entertainment",
            "tourist attraction", "attraction", "landmark", "museum", "gallery", "art gallery", "theater",
            "theatre", "historic", "monument", "movie", "cinema", "concert", "music venue", "arcade", "bowling",
            "zoo", "aquarium", "amusement", "theme park", "event venue"
        ],
            subcategories: [
            "Tourist attraction", "Landmark", "Historical place", "Historical landmark", "Monument", "Sculpture",
            "Fountain", "Castle", "Plaza", "Town square", "Visitor center", "Museum", "Art museum",
            "History museum", "Art gallery", "Art studio", "Cultural landmark", "Cultural center", "Theater",
            "Performing arts theater", "Concert hall", "Opera house", "Philharmonic hall", "Amphitheater",
            "Auditorium", "Movie theater", "Planetarium", "Observation deck", "Aquarium", "Zoo", "Amusement park",
            "Water park", "Ferris wheel", "Roller coaster", "Arcade", "Bowling", "Mini golf", "Billiards", "Darts",
            "Axe throwing", "Board game lounge", "Go-karting", "Paintball", "Indoor playground", "Event venue",
            "Convention center", "Banquet hall", "Wedding venue", "Community center", "Internet cafe",
            "Dance hall", "Barbecue area",
            "Stadium", "Arena"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: shopping,
            group: "Shopping",
            detail: "Stores, markets, supplies",
            defaultSubcategory: "Store",
            emoji: "🛍️",
            aliases: [
            "shopping", "shop", "store", "retail", "market", "mall", "grocery", "supermarket", "book store",
            "bookstore", "art supply store", "craft store", "gift shop", "clothing", "shoe store", "jewelry",
            "cosmetics", "hardware", "furniture", "pet store", "thrift"
        ],
            subcategories: [
            "Store", "Market", "Shopping mall", "Department store", "General store", "Convenience store",
            "Discount store", "Warehouse store", "Wholesaler", "Grocery store", "Supermarket", "Hypermarket",
            "Food store", "Farmers market", "Flea market", "Asian grocery", "Butcher", "Health food store",
            "Liquor store", "Book store", "Art supply store", "Craft store", "Gift shop", "Toy store",
            "Clothing store", "Women's clothing", "Shoe store", "Jewelry store", "Cosmetics store",
            "Beauty supply", "Sporting goods", "Sportswear", "Bicycle store", "Electronics", "Cell phone store",
            "Home goods", "Home improvement", "Hardware", "Building materials", "Furniture", "Garden center",
            "Pet store", "Auto parts", "Thrift store", "Discount supermarket", "Cosmetics",
            "Surf shop"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: wellnessFitness,
            group: "Wellness & Fitness",
            detail: "Health, beauty, fitness",
            defaultSubcategory: "Gym",
            emoji: "💪",
            aliases: [
            "wellness_fitness", "wellness fitness", "wellness and fitness", "health_wellness", "health wellness",
            "sports_fitness", "sports fitness", "health", "wellness", "fitness", "gym", "fitness center", "yoga",
            "sports club", "sports complex", "hospital", "medical", "clinic", "doctor", "dentist", "pharmacy",
            "drugstore", "spa", "massage", "sauna", "therapy", "veterinary care", "veterinarian", "urgent care",
            "optometrist", "ophthalmologist", "eye doctor", "eye care center", "vision center", "physical therapy",
            "dermatologist", "pediatrician", "podiatrist", "pilates", "pilates studio", "crossfit",
            "crossfit gym", "functional fitness", "functional fitness studio"
        ],
            subcategories: [
            "Gym", "Fitness center", "Yoga studio", "Pilates studio", "CrossFit gym", "Functional fitness studio",
            "Wellness studio", "Wellness center", "Sports club",
            "Sports complex", "Sports coaching", "Sports school", "Athletic field", "Swimming pool",
            "Tennis court", "Golf course", "Indoor golf", "Ice skating rink", "Volleyball court", "Soccer field",
            "Basketball court", "Pickleball court", "Spa", "Massage", "Massage spa", "Sauna", "Chiropractor",
            "Dentist", "Dental clinic", "Optometrist", "Ophthalmologist", "Eye care center", "Doctor",
            "Dermatologist", "Pediatrician", "Urgent care", "Medical clinic", "Medical center", "Hospital",
            "Medical lab", "Pharmacy", "Drugstore", "Physiotherapist", "Physical therapy", "Foot care",
            "Podiatrist", "Veterinary care", "Mental health/therapy", "Retreat",
            "Beach tennis", "Beach volleyball", "Padel court", "Climbing gym", "Surf school"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: stays,
            group: "Stays",
            detail: "Hotels, rentals, camping",
            defaultSubcategory: "Hotel",
            emoji: "🛏️",
            aliases: [
            "stays", "stay", "lodging", "hotel", "motel", "resort", "inn", "hostel", "bnb", "bed and breakfast",
            "guest house", "airbnb", "vrbo", "extended stay", "cottage", "cabin", "campground", "rv park",
            "2 star hotel", "3 star hotel", "4 star hotel", "5 star hotel"
        ],
            subcategories: [
            "Hotel", "Resort", "Motel", "Hostel", "Inn", "Bed & breakfast", "Guest house", "Private guest room",
            "Airbnb", "Vrbo", "Extended stay", "Cottage", "Cabin", "Campground", "RV park", "Farm-stay",
            "Japanese inn", "Mobile home park"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: servicesErrands,
            group: "Services & Errands",
            detail: "Errands, repairs, pet care",
            defaultSubcategory: "Consultant",
            emoji: "🧰",
            aliases: [
            "services_errands", "services errands", "services and errands", "services", "service", "bank", "atm",
            "accounting", "insurance", "real estate", "lawyer", "consultant", "florist", "catering", "child care",
            "laundry", "tailor", "courier", "shipping", "storage", "moving", "electrician", "plumber", "locksmith",
            "contractor", "pet care", "pet boarding", "beauty", "beauty service", "salon", "barber", "nail salon", "tattoo"
        ],
            subcategories: [
            "Bank", "ATM", "Accounting", "Insurance", "Real estate", "Lawyer", "Consultant",
            "Marketing consultant", "Employment agency", "Nonprofit", "Association", "Florist", "Catering",
            "Food delivery", "Child care", "Summer camp", "Laundry", "Tailor", "Courier", "Shipping", "Storage",
            "Moving", "Electrician", "Plumber", "Locksmith", "Painter", "Roofing contractor", "General contractor",
            "Pet care", "Pet boarding", "Funeral home", "Cemetery", "Astrologer", "Psychic", "Tour agency",
            "Travel agency", "Tourist information", "Chauffeur", "Aircraft rental", "Telecommunications",
            "Beauty service", "Skin care clinic", "Tanning studio", "Hair salon", "Barber", "Nail salon", "Makeup artist",
            "Body art", "Tattoo/piercing"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: travelTransit,
            group: "Travel & Transit",
            detail: "Airports, stations, parking",
            defaultSubcategory: "Transit stop",
            emoji: "🚆",
            aliases: [
            "travel_transit", "travel transit", "travel and transit", "transportation_transit",
            "transportation transit", "transportation and transit", "transportation", "transit", "airport",
            "train station", "subway station", "light rail", "tram stop", "bus stop", "bus station", "ferry",
            "station", "parking", "garage", "taxi", "bike share", "gas station", "ev charging", "car rental",
            "car repair", "car wash"
        ],
            subcategories: [
            "Airport", "International airport", "Airstrip", "Heliport", "Train station", "Subway station",
            "Light rail", "Tram stop", "Bus stop", "Bus station", "Ferry terminal", "Ferry service",
            "Transit station", "Transit stop", "Transit depot", "Taxi stand", "Taxi service", "Bike share station",
            "Parking", "Parking lot", "Parking garage", "Park & ride", "Gas station", "EV charging",
            "E-bike charging", "Rest stop", "Truck stop", "Toll station", "Bridge", "Car dealer", "Car rental",
            "Car repair", "Car wash", "Tire shop", "Truck dealer", "Transportation service", "Dump station",
            "RV water refill"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: workEducation,
            group: "Work & Education",
            detail: "Offices, schools, libraries",
            defaultSubcategory: "Co-working space",
            emoji: "🎓",
            aliases: [
            "work_education", "work education", "work and education", "education", "work_venues", "work venues",
            "work and venues", "work", "school", "university", "college", "campus", "preschool", "library",
            "research institute", "coworking", "co working", "office", "business center", "corporate office",
            "manufacturer", "supplier", "farm", "ranch", "television studio"
        ],
            subcategories: [
            "Co-working space", "Business center", "Corporate office", "Manufacturer", "Supplier", "Farm", "Ranch",
            "Television studio", "Library", "University", "School", "Preschool", "Primary school",
            "Secondary school", "Academic department", "Educational institution", "Research institute"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: civicFaith,
            group: "Civic & Faith",
            detail: "Government, worship, safety",
            defaultSubcategory: "Government office",
            emoji: "🏛️",
            aliases: [
            "civic_faith", "civic faith", "civic and faith", "public_services", "public service",
            "public services", "government", "city hall", "courthouse", "embassy", "post office", "police",
            "fire station", "faith", "worship", "spiritual", "church", "mosque", "synagogue", "hindu temple",
            "buddhist temple", "shinto shrine", "temple", "shrine", "place of worship"
        ],
            subcategories: [
            "City hall", "Government office", "Local government office", "Courthouse", "Embassy", "Post office",
            "Police", "Neighborhood police station", "Fire station", "Church", "Mosque", "Synagogue",
            "Hindu temple", "Buddhist temple", "Shinto shrine", "Place of worship"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: areasAddresses,
            group: "Areas & Addresses",
            detail: "Cities, addresses, regions",
            defaultSubcategory: "Address",
            emoji: "🗺️",
            aliases: [
            "areas_addresses", "areas addresses", "areas and addresses", "home_neighborhood", "home neighborhood",
            "home and neighborhood", "area", "address", "neighborhood", "locality", "city", "postal area", "town",
            "region", "country", "route", "street", "intersection", "plus code", "apartment building",
            "condominium complex", "housing complex"
        ],
            subcategories: [
            "Apartment building", "Apartment complex", "Condominium complex", "Housing complex", "Neighborhood",
            "Locality/city", "Postal area", "Town", "Region", "Country", "Route/street", "Address", "Intersection",
            "Landmark", "Plus code"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: facilitiesOther,
            group: "Facilities & Other",
            detail: "Restrooms, facilities, unknown",
            defaultSubcategory: "Point of interest",
            emoji: "📍",
            aliases: [
            "facilities_other", "facilities other", "facilities and other", "facility", "facilities", "other",
            "public bathroom", "public bath", "public restroom", "restroom", "stable", "generic establishment",
            "establishment", "point of interest", "poi", "unknown"
        ],
            subcategories: [
            "Public bathroom", "Public bath", "Restroom", "Stable", "Generic establishment", "Point of interest",
            "Unknown"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: fallbackPlace,
            group: "Place",
            detail: "Internal fallback for weak provider data",
            defaultSubcategory: nil,
            emoji: "📍",
            aliases: [
            "place"
        ],
            subcategories: [],
            isEditable: false
        )
    ]

    static let allowedCategories = taxonomy.map(\.id)
    static let editableCategories = taxonomy.filter(\.isEditable).map(\.id)

    // Normalize the fixed catalog once, not once per restored place or lookup.
    // Keep first-match taxonomy order, including aliases shared by categories.
    private struct IndexedTaxonomyEntry {
        let entry: PlaceCategoryTaxonomyEntry
        let idKey: String
        let groupKey: String
        let aliases: [(key: String, phrase: String)]
        let subcategories: [String: String]
    }

    private static let indexedTaxonomy: [IndexedTaxonomyEntry] = taxonomy.map { entry in
        var subcategories: [String: String] = [:]
        for value in entry.subcategories {
            let key = normalizedCategoryText(value)
            if subcategories[key] == nil { subcategories[key] = value }
        }
        return IndexedTaxonomyEntry(
            entry: entry,
            idKey: normalizedCategoryText(entry.id),
            groupKey: normalizedCategoryText(entry.group),
            aliases: entry.aliases.map {
                let key = normalizedCategoryText($0)
                return (key, " \(key) ")
            },
            subcategories: subcategories
        )
    }

    private static let taxonomyByKey: [String: IndexedTaxonomyEntry] = {
        var result: [String: IndexedTaxonomyEntry] = [:]
        for indexed in indexedTaxonomy {
            for key in [indexed.entry.id, indexed.idKey, indexed.groupKey] where result[key] == nil {
                result[key] = indexed
            }
        }
        return result
    }()
    static var supportedMapKitProviderTypes: [String] {
        mapKitProviderCategories.keys.sorted().map { "mkpoicategory\($0)" }
    }

    // MapKit persists these as lowercased raw strings (for example,
    // "mkpoicategoryfitnesscenter"), which removes the original word boundary.
    // Keep an explicit compatibility table instead of guessing from substrings.
    private static let mapKitProviderCategories: [String: ProviderCategoryMetadata] = [
        "animalservice": ProviderCategoryMetadata(canonicalType: "animal service", primaryCategory: servicesErrands, subcategory: "Pet care"),
        "airport": ProviderCategoryMetadata(canonicalType: "airport", primaryCategory: travelTransit, subcategory: "Airport"),
        "amusementpark": ProviderCategoryMetadata(canonicalType: "amusement park", primaryCategory: thingsToDo, subcategory: "Amusement park"),
        "aquarium": ProviderCategoryMetadata(canonicalType: "aquarium", primaryCategory: thingsToDo, subcategory: "Aquarium"),
        "atm": ProviderCategoryMetadata(canonicalType: "atm", primaryCategory: servicesErrands, subcategory: "ATM"),
        "automotiverepair": ProviderCategoryMetadata(canonicalType: "automotive repair", primaryCategory: travelTransit, subcategory: "Car repair"),
        "bakery": ProviderCategoryMetadata(canonicalType: "bakery", primaryCategory: coffeeTeaSweets, subcategory: "Bakery"),
        "bank": ProviderCategoryMetadata(canonicalType: "bank", primaryCategory: servicesErrands, subcategory: "Bank"),
        "baseball": ProviderCategoryMetadata(canonicalType: "baseball", primaryCategory: wellnessFitness, subcategory: "Athletic field"),
        "basketball": ProviderCategoryMetadata(canonicalType: "basketball", primaryCategory: wellnessFitness, subcategory: "Basketball court"),
        "beach": ProviderCategoryMetadata(canonicalType: "beach", primaryCategory: outdoorsNature, subcategory: "Beach"),
        "beauty": ProviderCategoryMetadata(canonicalType: "beauty service", primaryCategory: servicesErrands, subcategory: "Beauty service"),
        "bowling": ProviderCategoryMetadata(canonicalType: "bowling", primaryCategory: thingsToDo, subcategory: "Bowling"),
        "brewery": ProviderCategoryMetadata(canonicalType: "brewery", primaryCategory: barsNightlife, subcategory: "Brewery"),
        "cafe": ProviderCategoryMetadata(canonicalType: "cafe", primaryCategory: coffeeTeaSweets, subcategory: "Cafe"),
        "campground": ProviderCategoryMetadata(canonicalType: "campground", primaryCategory: outdoorsNature, subcategory: "Campground"),
        "carrental": ProviderCategoryMetadata(canonicalType: "car rental", primaryCategory: travelTransit, subcategory: "Car rental"),
        "castle": ProviderCategoryMetadata(canonicalType: "castle", primaryCategory: thingsToDo, subcategory: "Castle"),
        "conventioncenter": ProviderCategoryMetadata(canonicalType: "convention center", primaryCategory: thingsToDo, subcategory: "Convention center"),
        "distillery": ProviderCategoryMetadata(canonicalType: "distillery", primaryCategory: barsNightlife, subcategory: "Distillery"),
        "evcharger": ProviderCategoryMetadata(canonicalType: "ev charger", primaryCategory: travelTransit, subcategory: "EV charging"),
        "fairground": ProviderCategoryMetadata(canonicalType: "fairground", primaryCategory: thingsToDo, subcategory: "Amusement park"),
        "firestation": ProviderCategoryMetadata(canonicalType: "fire station", primaryCategory: civicFaith, subcategory: "Fire station"),
        "fishing": ProviderCategoryMetadata(canonicalType: "fishing", primaryCategory: outdoorsNature, subcategory: "Fishing pier"),
        "fitnesscenter": ProviderCategoryMetadata(canonicalType: "fitness center", primaryCategory: wellnessFitness, subcategory: "Fitness center"),
        "foodmarket": ProviderCategoryMetadata(canonicalType: "grocery store", primaryCategory: shopping, subcategory: "Grocery store"),
        "fortress": ProviderCategoryMetadata(canonicalType: "fortress", primaryCategory: thingsToDo, subcategory: "Castle"),
        "gasstation": ProviderCategoryMetadata(canonicalType: "gas station", primaryCategory: travelTransit, subcategory: "Gas station"),
        "golf": ProviderCategoryMetadata(canonicalType: "golf", primaryCategory: wellnessFitness, subcategory: "Golf course"),
        "gokart": ProviderCategoryMetadata(canonicalType: "go kart", primaryCategory: thingsToDo, subcategory: "Go-karting"),
        "hiking": ProviderCategoryMetadata(canonicalType: "hiking", primaryCategory: outdoorsNature, subcategory: "Hiking area"),
        "hospital": ProviderCategoryMetadata(canonicalType: "hospital", primaryCategory: wellnessFitness, subcategory: "Hospital"),
        "hotel": ProviderCategoryMetadata(canonicalType: "hotel", primaryCategory: stays, subcategory: "Hotel"),
        "kayaking": ProviderCategoryMetadata(canonicalType: "kayaking", primaryCategory: outdoorsNature, subcategory: "Adventure sports"),
        "landmark": ProviderCategoryMetadata(canonicalType: "landmark", primaryCategory: thingsToDo, subcategory: "Landmark"),
        "laundry": ProviderCategoryMetadata(canonicalType: "laundry", primaryCategory: servicesErrands, subcategory: "Laundry"),
        "library": ProviderCategoryMetadata(canonicalType: "library", primaryCategory: workEducation, subcategory: "Library"),
        "mailbox": ProviderCategoryMetadata(canonicalType: "mailbox", primaryCategory: civicFaith, subcategory: "Post office"),
        "marina": ProviderCategoryMetadata(canonicalType: "marina", primaryCategory: outdoorsNature, subcategory: "Marina"),
        "minigolf": ProviderCategoryMetadata(canonicalType: "mini golf", primaryCategory: thingsToDo, subcategory: "Mini golf"),
        "movietheater": ProviderCategoryMetadata(canonicalType: "movie theater", primaryCategory: thingsToDo, subcategory: "Movie theater"),
        "museum": ProviderCategoryMetadata(canonicalType: "museum", primaryCategory: thingsToDo, subcategory: "Museum"),
        "musicvenue": ProviderCategoryMetadata(canonicalType: "music venue", primaryCategory: thingsToDo, subcategory: "Concert hall"),
        "nationalmonument": ProviderCategoryMetadata(canonicalType: "national monument", primaryCategory: thingsToDo, subcategory: "Monument"),
        "nationalpark": ProviderCategoryMetadata(canonicalType: "national park", primaryCategory: outdoorsNature, subcategory: "National park"),
        "nightlife": ProviderCategoryMetadata(canonicalType: "nightlife", primaryCategory: barsNightlife, subcategory: "Bar"),
        "park": ProviderCategoryMetadata(canonicalType: "park", primaryCategory: outdoorsNature, subcategory: "Park"),
        "parking": ProviderCategoryMetadata(canonicalType: "parking", primaryCategory: travelTransit, subcategory: "Parking"),
        "pharmacy": ProviderCategoryMetadata(canonicalType: "pharmacy", primaryCategory: wellnessFitness, subcategory: "Pharmacy"),
        "planetarium": ProviderCategoryMetadata(canonicalType: "planetarium", primaryCategory: thingsToDo, subcategory: "Planetarium"),
        "police": ProviderCategoryMetadata(canonicalType: "police", primaryCategory: civicFaith, subcategory: "Police"),
        "postoffice": ProviderCategoryMetadata(canonicalType: "post office", primaryCategory: civicFaith, subcategory: "Post office"),
        "publictransport": ProviderCategoryMetadata(canonicalType: "public transport", primaryCategory: travelTransit, subcategory: "Transit station"),
        "restaurant": ProviderCategoryMetadata(canonicalType: "restaurant", primaryCategory: restaurantsFood, subcategory: "Restaurant"),
        "restroom": ProviderCategoryMetadata(canonicalType: "restroom", primaryCategory: facilitiesOther, subcategory: "Restroom"),
        "rockclimbing": ProviderCategoryMetadata(canonicalType: "rock climbing", primaryCategory: outdoorsNature, subcategory: "Adventure sports"),
        "rvpark": ProviderCategoryMetadata(canonicalType: "rv park", primaryCategory: outdoorsNature, subcategory: "RV park"),
        "school": ProviderCategoryMetadata(canonicalType: "school", primaryCategory: workEducation, subcategory: "School"),
        "skatepark": ProviderCategoryMetadata(canonicalType: "skate park", primaryCategory: outdoorsNature, subcategory: "Skate park"),
        "skating": ProviderCategoryMetadata(canonicalType: "skating", primaryCategory: wellnessFitness, subcategory: "Ice skating rink"),
        "skiing": ProviderCategoryMetadata(canonicalType: "skiing", primaryCategory: outdoorsNature, subcategory: "Ski resort"),
        "soccer": ProviderCategoryMetadata(canonicalType: "soccer", primaryCategory: wellnessFitness, subcategory: "Soccer field"),
        "spa": ProviderCategoryMetadata(canonicalType: "spa", primaryCategory: wellnessFitness, subcategory: "Spa"),
        "stadium": ProviderCategoryMetadata(canonicalType: "stadium", primaryCategory: thingsToDo, subcategory: "Stadium"),
        "store": ProviderCategoryMetadata(canonicalType: "store", primaryCategory: shopping, subcategory: "Store"),
        "surfing": ProviderCategoryMetadata(canonicalType: "surfing", primaryCategory: outdoorsNature, subcategory: "Surf"),
        "swimming": ProviderCategoryMetadata(canonicalType: "swimming", primaryCategory: wellnessFitness, subcategory: "Swimming pool"),
        "tennis": ProviderCategoryMetadata(canonicalType: "tennis", primaryCategory: wellnessFitness, subcategory: "Tennis court"),
        "theater": ProviderCategoryMetadata(canonicalType: "theater", primaryCategory: thingsToDo, subcategory: "Theater"),
        "university": ProviderCategoryMetadata(canonicalType: "university", primaryCategory: workEducation, subcategory: "University"),
        "volleyball": ProviderCategoryMetadata(canonicalType: "volleyball", primaryCategory: wellnessFitness, subcategory: "Volleyball court"),
        "winery": ProviderCategoryMetadata(canonicalType: "winery", primaryCategory: barsNightlife, subcategory: "Winery"),
        "zoo": ProviderCategoryMetadata(canonicalType: "zoo", primaryCategory: thingsToDo, subcategory: "Zoo")
    ]

    private static let legacyDefaultSubcategories: [String: String] = [
        "coffee": "Coffee shop",
        "coffee shop": "Coffee shop",
        "cafe": "Cafe",
        "bakery": "Bakery",
        "restaurant": "Restaurant",
        "thai restaurant": "Restaurant",
        "sushi restaurant": "Restaurant",
        "fast food restaurant": "Fast food",
        "bar": "Bar",
        "nightlife": "Bar",
        "mkpoicategorynightlife": "Bar",
        "brewery": "Brewery",
        "winery": "Winery",
        "hike": "Hike",
        "trail": "Trail",
        "park": "Park",
        "gym": "Gym",
        "fitness studio": "Fitness center",
        "pilates studio": "Pilates studio",
        "spiritual": "Place of worship",
        "hospital": "Hospital",
        "urgent care": "Urgent care",
        "optometrist": "Optometrist",
        "ophthalmologist": "Ophthalmologist",
        "eye doctor": "Optometrist",
        "eye care center": "Eye care center",
        "vision center": "Eye care center",
        "dermatologist": "Dermatologist",
        "pediatrician": "Pediatrician",
        "physical therapy": "Physical therapy",
        "podiatrist": "Podiatrist",
        "pharmacy": "Pharmacy",
        "veterinarian": "Veterinary care",
        "hotel": "Hotel",
        "2 star hotel": "Hotel",
        "3 star hotel": "Hotel",
        "4 star hotel": "Hotel",
        "5 star hotel": "Hotel",
        "shop": "Store",
        "transportation": "Transit stop",
        "public restroom": "Restroom",
        "unknown": "Unknown"
    ]

    private static let legacyPrimaryCategories: [String: String] = [
        "food_drink": restaurantsFood,
        "food drink": restaurantsFood,
        "food and drink": restaurantsFood,
        "coffee": coffeeTeaSweets,
        "coffee shop": coffeeTeaSweets,
        "cafe": coffeeTeaSweets,
        "bakery": coffeeTeaSweets,
        "restaurant": restaurantsFood,
        "thai restaurant": restaurantsFood,
        "fast food restaurant": restaurantsFood,
        "bar": barsNightlife,
        "nightlife": barsNightlife,
        "mkpoicategorynightlife": barsNightlife,
        "brewery": barsNightlife,
        "winery": barsNightlife,
        "hike": outdoorsNature,
        "trail": outdoorsNature,
        "park": outdoorsNature,
        "arts_culture_faith": thingsToDo,
        "arts culture faith": thingsToDo,
        "entertainment": thingsToDo,
        "spiritual": civicFaith,
        "church": civicFaith,
        "temple": civicFaith,
        "shrine": civicFaith,
        "mosque": civicFaith,
        "synagogue": civicFaith,
        "health_wellness": wellnessFitness,
        "sports_fitness": wellnessFitness,
        "gym": wellnessFitness,
        "fitness studio": wellnessFitness,
        "pilates studio": wellnessFitness,
        "hospital": wellnessFitness,
        "pharmacy": wellnessFitness,
        "veterinarian": wellnessFitness,
        "services": servicesErrands,
        "hotel": stays,
        "lodging": stays,
        "shop": shopping,
        "transportation": travelTransit,
        "transportation_transit": travelTransit,
        "education": workEducation,
        "work_venues": workEducation,
        "home_neighborhood": areasAddresses,
        "public_services": civicFaith,
        "public service": civicFaith,
        "point of interest": facilitiesOther,
        "unknown": facilitiesOther
    ]

    private static let curatedSubcategoryGroups: [String: [PlaceCategorySubcategoryGroup]] = [
        restaurantsFood: [
            PlaceCategorySubcategoryGroup(title: "Asian", subcategories: [
                "Thai", "Vietnamese", "Chinese", "Korean", "Japanese", "Indian", "Asian fusion", "Sushi",
                "Ramen", "Dumplings", "Bao buns", "Noodles", "Dim sum", "Hot pot", "Cantonese", "Taiwanese", "Izakaya",
                "Yakitori", "Yakiniku", "North Indian", "South Indian", "Pakistani", "Sri Lankan",
                "Bangladeshi", "Nepalese", "Malaysian", "Singaporean", "Indonesian", "Filipino", "Burmese",
                "Cambodian", "Laotian", "Asian", "Tibetan", "Mongolian", "Georgian", "Armenian", "Uzbek",
                "Mongolian BBQ", "Korean BBQ", "Japanese BBQ", "Japanese curry", "Tonkatsu"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Middle East & Africa", subcategories: [
                "Afghan", "Middle Eastern", "Lebanese", "Persian", "Turkish", "Israeli", "Palestinian",
                "Syrian", "Iraqi", "Jordanian", "Yemeni", "Egyptian", "Moroccan", "Tunisian", "Algerian",
                "Ethiopian", "Eritrean", "Somali", "Kenyan", "Nigerian", "Ghanaian", "Senegalese",
                "South African", "African", "Falafel", "Gyro", "Kebab", "Shawarma", "Halal"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Europe", subcategories: [
                "Italian", "Mediterranean", "Greek", "French", "Spanish", "Tapas", "Portuguese", "Basque",
                "German", "Austrian", "Bavarian", "Swiss", "Dutch", "Belgian", "British", "Irish",
                "Scandinavian", "Swedish", "Norwegian", "Finnish", "Danish", "Polish", "Ukrainian", "Russian",
                "Czech", "Slovak", "Hungarian", "Romanian", "Croatian", "Serbian", "Bosnian", "Bulgarian",
                "Albanian", "Slovenian", "Lithuanian", "European", "Eastern European", "Pizza",
                "Fish & chips", "Fondue"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Americas & Pacific", subcategories: [
                "American", "Canadian", "Mexican", "Tex-Mex", "Caribbean", "Jamaican", "Puerto Rican",
                "Dominican", "Haitian", "Panamanian", "Cuban", "Brazilian", "Argentinian", "Colombian",
                "Chilean", "Peruvian", "Venezuelan", "Ecuadorian", "Bolivian", "Uruguayan", "Salvadoran",
                "Guatemalan", "South American", "Latin American", "Southwestern", "Cajun", "Californian",
                "Hawaiian", "Poke", "Australian", "New Zealand", "Fijian", "Samoan", "Tongan", "Burgers",
                "Diner", "Hot dogs", "Barbecue", "Wings", "Steakhouse", "Bar & grill", "Taco stand",
                "Taco truck", "Burrito", "Taco"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Misc", subcategories: [
                "Sandwich", "Bagel", "Deli", "Salad", "Bistro", "Food court", "Breakfast", "Brunch", "Soup",
                "Chicken", "Seafood", "Oyster bar", "Vegetarian", "Vegan", "Gluten-free", "Snack bar", "Gastropub"
            ], role: .cuisine)
        ],
        coffeeTeaSweets: [
            PlaceCategorySubcategoryGroup(title: "Coffee & tea", subcategories: [
                "Coffee shop", "Cafe", "Coffee stand", "Coffee lounge", "Roastery", "Tea house", "Tea store"
            ]),
            PlaceCategorySubcategoryGroup(title: "Juice & light treats", subcategories: [
                "Juice shop", "Smoothie shop", "Acai", "Cat cafe", "Dog cafe"
            ]),
            PlaceCategorySubcategoryGroup(title: "Bakeries & sweets", subcategories: [
                "Bakery", "Bagel shop", "Donut shop", "Cake shop", "Pastry shop", "Dessert shop",
                "Dessert restaurant", "Ice cream", "Gelato", "Candy store", "Chocolate shop", "Chocolate factory",
                "Chocolate lounge", "Confectionery"
            ])
        ],
        barsNightlife: [
            PlaceCategorySubcategoryGroup(title: "Bars & pubs", subcategories: [
                "Bar", "Cocktail bar", "Pub", "Irish pub", "Sports bar", "Wine bar", "Gastropub", "Bar & grill",
                "Cider bar", "Sake bar", "Beer garden", "Brewery", "Brewpub"
            ]),
            PlaceCategorySubcategoryGroup(title: "Lounges & clubs", subcategories: [
                "Dance hall", "Club", "Disco", "Lounge", "Hookah bar", "Jazz club", "Hi-fi lounge", "Nightclub",
                "Karaoke", "Live music", "Comedy club"
            ]),
            PlaceCategorySubcategoryGroup(title: "Wine & gaming", subcategories: [
                "Winery", "Vineyard", "Billiards", "Game bar", "Casino"
            ])
        ],
        outdoorsNature: [
            PlaceCategorySubcategoryGroup(title: "Parks & gardens", subcategories: [
                "Park", "City park", "State park", "National park", "Botanical garden", "Garden", "Picnic area",
                "Dog park", "Playground"
            ]),
            PlaceCategorySubcategoryGroup(title: "Trails & scenery", subcategories: [
                "Hiking area", "Trail", "Hike", "Island", "Woods/forest", "Mountain peak", "Scenic spot",
                "Viewpoint", "Overlook", "Waterfall", "Cave", "Nature preserve", "Wildlife refuge", "Wildlife park"
            ]),
            PlaceCategorySubcategoryGroup(title: "Water & camping", subcategories: [
                "Beach", "Dog beach", "Lake", "River", "Hot spring", "Campground", "RV park", "Dispersed camping", "Cabin",
                "Cottage", "Marina", "Fishing pier", "Fishing pond", "Fishing charter"
            ]),
            PlaceCategorySubcategoryGroup(title: "Outdoor sports", subcategories: [
                "Ski resort", "Cycling park", "Skate park", "Off-roading area", "Adventure sports",
                "Surf", "Surf break", "Kayak/canoe rental"
            ])
        ],
        thingsToDo: [
            PlaceCategorySubcategoryGroup(title: "Landmarks & culture", subcategories: [
                "Tourist attraction", "Landmark", "Historical place", "Historical landmark", "Monument",
                "Sculpture", "Fountain", "Castle", "Plaza", "Town square", "Visitor center", "Cultural landmark",
                "Cultural center"
            ]),
            PlaceCategorySubcategoryGroup(title: "Museums & arts", subcategories: [
                "Museum", "Art museum", "History museum", "Art gallery", "Art studio"
            ]),
            PlaceCategorySubcategoryGroup(title: "Shows & venues", subcategories: [
                "Theater", "Performing arts theater", "Concert hall", "Opera house", "Philharmonic hall",
                "Amphitheater", "Auditorium", "Movie theater", "Planetarium", "Observation deck", "Stadium", "Arena"
            ]),
            PlaceCategorySubcategoryGroup(title: "Attractions & games", subcategories: [
                "Aquarium", "Zoo", "Amusement park", "Water park", "Ferris wheel", "Roller coaster", "Arcade",
                "Bowling", "Mini golf", "Billiards", "Darts", "Axe throwing", "Board game lounge", "Go-karting",
                "Paintball", "Indoor playground", "Internet cafe", "Dance hall", "Barbecue area"
            ]),
            PlaceCategorySubcategoryGroup(title: "Events", subcategories: [
                "Event venue", "Convention center", "Banquet hall", "Wedding venue", "Community center"
            ])
        ],
        shopping: [
            PlaceCategorySubcategoryGroup(title: "General retail", subcategories: [
                "Store", "Market", "Shopping mall", "Department store", "General store", "Convenience store",
                "Discount store", "Warehouse store", "Wholesaler"
            ]),
            PlaceCategorySubcategoryGroup(title: "Food shopping", subcategories: [
                "Grocery store", "Supermarket", "Hypermarket", "Food store", "Farmers market", "Flea market",
                "Asian grocery", "Butcher", "Health food store", "Liquor store", "Discount supermarket"
            ]),
            PlaceCategorySubcategoryGroup(title: "Specialty shops", subcategories: [
                "Surf shop",
                "Book store", "Art supply store", "Craft store", "Gift shop", "Toy store", "Sporting goods",
                "Sportswear", "Bicycle store", "Electronics", "Cell phone store", "Pet store", "Auto parts",
                "Thrift store"
            ]),
            PlaceCategorySubcategoryGroup(title: "Fashion & home", subcategories: [
                "Clothing store", "Women's clothing", "Shoe store", "Jewelry store", "Cosmetics store",
                "Beauty supply", "Cosmetics", "Home goods", "Home improvement", "Hardware", "Building materials",
                "Furniture", "Garden center"
            ])
        ],
        wellnessFitness: [
            PlaceCategorySubcategoryGroup(title: "Fitness & sports", subcategories: [
                "Beach tennis", "Beach volleyball", "Padel court", "Climbing gym", "Surf school",
                "Gym", "Fitness center", "Yoga studio", "Pilates studio", "CrossFit gym", "Functional fitness studio",
                "Wellness studio", "Wellness center", "Sports club",
                "Sports complex", "Sports coaching", "Sports school", "Athletic field", "Swimming pool",
                "Tennis court", "Golf course", "Indoor golf", "Ice skating rink", "Volleyball court",
                "Soccer field", "Basketball court", "Pickleball court"
            ]),
            PlaceCategorySubcategoryGroup(title: "Wellness & recovery", subcategories: [
                "Spa", "Massage", "Massage spa", "Sauna", "Chiropractor", "Physiotherapist", "Foot care",
                "Mental health/therapy", "Retreat"
            ]),
            PlaceCategorySubcategoryGroup(title: "Medical care", subcategories: [
                "Dentist", "Dental clinic", "Optometrist", "Ophthalmologist", "Eye care center", "Doctor",
                "Dermatologist", "Pediatrician", "Urgent care", "Medical clinic", "Medical center", "Hospital",
                "Medical lab", "Pharmacy", "Drugstore", "Physiotherapist", "Physical therapy", "Foot care",
                "Podiatrist", "Veterinary care"
            ])
        ],
        stays: [
            PlaceCategorySubcategoryGroup(title: "Hotels & inns", subcategories: [
                "Hotel", "Resort", "Motel", "Hostel", "Inn", "Bed & breakfast", "Guest house", "Japanese inn"
            ]),
            PlaceCategorySubcategoryGroup(title: "Rentals & longer stays", subcategories: [
                "Private guest room", "Airbnb", "Vrbo", "Extended stay", "Farm-stay", "Mobile home park"
            ]),
            PlaceCategorySubcategoryGroup(title: "Cabins & camping", subcategories: [
                "Cottage", "Cabin", "Campground", "RV park"
            ])
        ],
        servicesErrands: [
            PlaceCategorySubcategoryGroup(title: "Money & professional", subcategories: [
                "Bank", "ATM", "Accounting", "Insurance", "Real estate", "Lawyer", "Consultant",
                "Marketing consultant", "Employment agency", "Nonprofit", "Association"
            ]),
            PlaceCategorySubcategoryGroup(title: "Errands & family", subcategories: [
                "Florist", "Catering", "Food delivery", "Child care", "Summer camp", "Laundry", "Tailor",
                "Courier", "Shipping", "Storage", "Moving"
            ]),
            PlaceCategorySubcategoryGroup(title: "Home & repairs", subcategories: [
                "Electrician", "Plumber", "Locksmith", "Painter", "Roofing contractor", "General contractor",
                "Telecommunications"
            ]),
            PlaceCategorySubcategoryGroup(title: "Pet & sensitive services", subcategories: [
                "Pet care", "Pet boarding", "Funeral home", "Cemetery", "Astrologer", "Psychic"
            ]),
            PlaceCategorySubcategoryGroup(title: "Travel & concierge", subcategories: [
                "Tour agency", "Travel agency", "Tourist information", "Chauffeur", "Aircraft rental"
            ]),
            PlaceCategorySubcategoryGroup(title: "Beauty & body", subcategories: [
                "Skin care clinic", "Tanning studio", "Hair salon", "Barber", "Nail salon", "Makeup artist",
                "Body art", "Tattoo/piercing"
            ])
        ],
        travelTransit: [
            PlaceCategorySubcategoryGroup(title: "Air & rail", subcategories: [
                "Airport", "International airport", "Airstrip", "Heliport", "Train station", "Subway station",
                "Light rail", "Tram stop"
            ]),
            PlaceCategorySubcategoryGroup(title: "Bus, ferry & taxi", subcategories: [
                "Bus stop", "Bus station", "Ferry terminal", "Ferry service", "Transit station", "Transit stop",
                "Transit depot", "Taxi stand", "Taxi service", "Transportation service"
            ]),
            PlaceCategorySubcategoryGroup(title: "Parking & charging", subcategories: [
                "Bike share station", "Parking", "Parking lot", "Parking garage", "Park & ride", "Gas station",
                "EV charging", "E-bike charging"
            ]),
            PlaceCategorySubcategoryGroup(title: "Road & vehicle", subcategories: [
                "Rest stop", "Truck stop", "Toll station", "Bridge", "Car dealer", "Car rental", "Car repair",
                "Car wash", "Tire shop", "Truck dealer", "Dump station", "RV water refill"
            ])
        ],
        workEducation: [
            PlaceCategorySubcategoryGroup(title: "Work", subcategories: [
                "Co-working space", "Business center", "Corporate office", "Manufacturer", "Supplier", "Farm",
                "Ranch", "Television studio"
            ]),
            PlaceCategorySubcategoryGroup(title: "Education", subcategories: [
                "Library", "University", "School", "Preschool", "Primary school", "Secondary school",
                "Academic department", "Educational institution", "Research institute"
            ])
        ],
        civicFaith: [
            PlaceCategorySubcategoryGroup(title: "Government & safety", subcategories: [
                "City hall", "Government office", "Local government office", "Courthouse", "Embassy",
                "Post office", "Police", "Neighborhood police station", "Fire station"
            ]),
            PlaceCategorySubcategoryGroup(title: "Faith", subcategories: [
                "Church", "Mosque", "Synagogue", "Hindu temple", "Buddhist temple", "Shinto shrine",
                "Place of worship"
            ])
        ],
        areasAddresses: [
            PlaceCategorySubcategoryGroup(title: "Buildings & housing", subcategories: [
                "Apartment building", "Apartment complex", "Condominium complex", "Housing complex"
            ]),
            PlaceCategorySubcategoryGroup(title: "Areas", subcategories: [
                "Neighborhood", "Locality/city", "Postal area", "Town", "Region", "Country"
            ]),
            PlaceCategorySubcategoryGroup(title: "Addresses", subcategories: [
                "Route/street", "Address", "Intersection", "Landmark", "Plus code"
            ])
        ],
        facilitiesOther: [
            PlaceCategorySubcategoryGroup(title: "Facilities", subcategories: [
                "Public bathroom", "Public bath", "Restroom", "Stable"
            ]),
            PlaceCategorySubcategoryGroup(title: "Fallbacks", subcategories: [
                "Generic establishment", "Point of interest", "Unknown"
            ])
        ]
    ]
    static func primary(for pointCategory: MKPointOfInterestCategory?, name: String? = nil) -> String? {
        if let nameCategory = primaryFromName(name, pointCategory: pointCategory) {
            return nameCategory
        }
        return providerCategoryAssignment(for: pointCategory?.rawValue)?.primaryCategory
    }

    static func assignment(
        forRawCategory rawCategory: String,
        source: String = PlaceCategorySource.provider.rawValue,
        confidence: Double? = nil,
        rawProviderType: String? = nil
    ) -> PlaceCategoryAssignment {
        let providerAssignment = providerCategoryAssignment(for: rawProviderType ?? rawCategory)
        let raw = normalizedSubcategory(rawProviderType) ?? normalizedSubcategory(rawCategory)
        let primary = providerAssignment?.primaryCategory ?? primaryCategory(for: rawCategory)
        let subcategory = providerAssignment?.subcategory
            ?? subcategory(forRawValue: raw ?? rawCategory, primaryCategory: primary)

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
            subcategory: subcategory ?? Self.subcategory(forRawValue: primaryCategory, primaryCategory: primary),
            source: source,
            confidence: confidence,
            rawProviderType: rawProviderType
        )
    }

    static func display(for assignment: PlaceCategoryAssignment, sourceLabel: String? = nil) -> PlaceCategoryDisplay {
        let primary = normalizedPrimaryCategory(assignment.primaryCategory)
        let subcategory = canonicalSubcategory(assignment.subcategory, primaryCategory: primary) ?? defaultSubcategory(for: primary)
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
        case restaurantsFood:
            return "restaurant"
        case coffeeTeaSweets:
            return "coffee"
        case barsNightlife:
            return "bar"
        case outdoorsNature:
            return "park"
        case wellnessFitness:
            return "gym"
        default:
            return primaryCategory(for: category)
        }
    }

    static func questionCategory(for assignment: PlaceCategoryAssignment) -> String {
        questionCategory(for: assignment.subcategory ?? assignment.primaryCategory)
    }

    static func primaryCategory(for category: String) -> String {
        if let providerCategory = providerCategoryAssignment(for: category) {
            return providerCategory.primaryCategory
        }
        let normalized = normalizedCategoryText(category)
        guard !normalized.isEmpty else { return fallbackPlace }
        if let legacyPrimary = legacyPrimaryCategories[normalized] {
            return legacyPrimary
        }

        if let entry = entry(for: normalized) {
            return entry.id
        }

        let padded = " \(normalized) "
        for indexed in indexedTaxonomy where indexed.entry.id != fallbackPlace {
            if indexed.aliases.contains(where: { alias in
                alias.key == normalized || (!alias.key.isEmpty && padded.contains(alias.phrase))
            }) {
                return indexed.entry.id
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

    static func canonicalSubcategory(_ value: String?, primaryCategory: String) -> String? {
        if let providerCategory = providerCategoryAssignment(for: value),
           providerCategory.primaryCategory == normalizedPrimaryCategory(primaryCategory) {
            return providerCategory.subcategory
        }
        guard let normalized = normalizedSubcategory(value) else { return nil }
        let key = normalizedCategoryText(normalized)
        let primary = normalizedPrimaryCategory(primaryCategory)

        return taxonomyByKey[primary]?.subcategories[key] ?? normalized
    }

    static func isDefaultSubcategory(_ value: String?, primaryCategory: String) -> Bool {
        guard let value,
              let defaultValue = defaultSubcategory(for: normalizedPrimaryCategory(primaryCategory))
        else {
            return value == nil
        }
        return normalizedCategoryText(value) == normalizedCategoryText(defaultValue)
    }

    static func categoryEvidenceAssignment(
        subcategory: String?,
        rawProviderType: String?
    ) -> (primaryCategory: String, subcategory: String)? {
        let candidates = [
            (value: rawProviderType, isRawProviderType: true),
            (value: subcategory, isRawProviderType: false)
        ].compactMap { candidate -> (
            assignment: (primaryCategory: String, subcategory: String),
            score: Int,
            isRawProviderType: Bool
        )? in
            guard let value = candidate.value else { return nil }
            let primary = primaryCategory(for: value)
            guard primary != fallbackPlace else { return nil }
            let resolvedSubcategory = providerCategoryAssignment(for: value)?.subcategory
                ?? Self.subcategory(forRawValue: value, primaryCategory: primary)
                ?? defaultSubcategory(for: primary)
            guard let resolvedSubcategory else { return nil }
            return (
                assignment: (primary, resolvedSubcategory),
                score: categoryEvidenceSpecificity(
                    value,
                    primaryCategory: primary,
                    subcategory: resolvedSubcategory
                ),
                isRawProviderType: candidate.isRawProviderType
            )
        }

        return candidates.max { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score
            }
            return !lhs.isRawProviderType && rhs.isRawProviderType
        }?.assignment
    }

    static func normalizedProviderType(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    static func subcategorySuggestions(for primaryCategory: String) -> [String] {
        entry(for: primaryCategory)?.subcategories ?? []
    }

    static func subcategoryGroups(for primaryCategory: String) -> [PlaceCategorySubcategoryGroup] {
        let primary = normalizedPrimaryCategory(primaryCategory)
        let suggestions = subcategorySuggestions(for: primary)
        guard !suggestions.isEmpty else { return [] }

        var used = Set<String>()
        var groups: [PlaceCategorySubcategoryGroup] = []

        for group in curatedSubcategoryGroups[primary] ?? [] {
            let values = group.subcategories.filter { subcategory in
                let key = normalizedCategoryText(subcategory)
                guard suggestions.contains(where: { normalizedCategoryText($0) == key }) else {
                    return false
                }
                return used.insert(key).inserted
            }

            if !values.isEmpty {
                groups.append(PlaceCategorySubcategoryGroup(title: group.title, subcategories: values, role: group.role))
            }
        }

        let remaining = suggestions.filter { subcategory in
            !used.contains(normalizedCategoryText(subcategory))
        }

        if !remaining.isEmpty {
            groups.append(PlaceCategorySubcategoryGroup(title: "More types", subcategories: remaining))
        }

        return groups
    }

    static func restaurantCuisineGroups() -> [PlaceCategorySubcategoryGroup] {
        subcategoryGroups(for: restaurantsFood).filter { $0.role == .cuisine }
    }

    static let restaurantPopularCuisineOptions = [
        "American", "Mexican", "Thai", "Vietnamese", "Chinese", "Korean", "Japanese", "Indian",
        "Italian", "Mediterranean", "Greek", "French", "Spanish", "Tex-Mex", "Asian fusion"
    ]

    static let restaurantCuisineOptions: [String] = {
        restaurantCuisineGroups().flatMap(\.subcategories)
    }()

    static func recentRestaurantCuisines(
        from uses: [RestaurantCuisineUse],
        limit: Int = 4
    ) -> [String] {
        guard limit > 0 else { return [] }

        var seen = Set<String>()
        return uses
            .sorted { $0.savedAt > $1.savedAt }
            .compactMap { use -> String? in
                guard let cuisine = cuisineGuess(forRawValue: use.cuisine) else {
                    return nil
                }

                let key = normalizedCategoryText(cuisine)
                guard seen.insert(key).inserted else { return nil }
                return cuisine
            }
            .prefix(limit)
            .map { $0 }
    }

    static func updatingRecentRestaurantCuisines(
        _ cuisines: [String],
        selecting selection: String,
        limit: Int = 4
    ) -> [String] {
        guard limit > 0,
              let selectedCuisine = cuisineGuess(forRawValue: selection)
        else { return [] }

        var seen = Set([normalizedCategoryText(selectedCuisine)])
        var updated = [selectedCuisine]

        for cuisine in cuisines {
            guard let canonicalCuisine = cuisineGuess(forRawValue: cuisine) else {
                continue
            }

            let key = normalizedCategoryText(canonicalCuisine)
            guard seen.insert(key).inserted else { continue }
            updated.append(canonicalCuisine)
            if updated.count == limit {
                break
            }
        }

        return updated
    }

    private static let normalizedRestaurantCuisineOptions: [(name: String, normalized: String, phrase: String)] = {
        restaurantCuisineOptions
            .map { cuisine in
                let normalized = normalizedCategoryText(cuisine)
                return (name: cuisine, normalized: normalized, phrase: " \(normalized) ")
            }
            .sorted { $0.normalized.count > $1.normalized.count }
    }()

    static func isRestaurantCuisine(_ value: String?) -> Bool {
        cuisineGuess(forRawValue: value) != nil
    }

    static func cuisineGuess(forRawValue rawValue: String?) -> String? {
        let normalized = normalizedCategoryText(rawValue)
        guard !normalized.isEmpty else { return nil }
        let withoutCuisineSuffix = normalized.replacingOccurrences(of: " cuisine", with: "")
        let padded = " \(normalized) "

        return normalizedRestaurantCuisineOptions.first { cuisine in
            normalized == cuisine.normalized
                || padded.contains(cuisine.phrase)
                || withoutCuisineSuffix == cuisine.normalized
        }?.name
    }

    static func restaurantCuisineInference(
        name: String?,
        rawProviderType: String?,
        subcategory: String?,
        category: String?,
        websiteURLString: String? = nil
    ) -> RestaurantCuisineInference? {
        let evidence: [(value: String?, source: RestaurantCuisineInferenceSource, confidence: Double)] = [
            (rawProviderType, .providerType, 0.98),
            (subcategory, .subcategory, 0.95),
            (category, .category, 0.92),
            (name, .placeName, 0.90),
            (websiteURLString, .website, 0.86)
        ]

        for item in evidence {
            if let cuisine = cuisineGuess(forRawValue: item.value) {
                return RestaurantCuisineInference(
                    cuisine: cuisine,
                    confidence: item.confidence,
                    source: item.source
                )
            }

            if let cuisine = cuisineAliasGuess(forRawValue: item.value) {
                return RestaurantCuisineInference(
                    cuisine: cuisine,
                    confidence: item.confidence - 0.04,
                    source: item.source
                )
            }
        }

        return nil
    }

    static func restaurantCuisineInference(for candidate: PlaceCandidate) -> RestaurantCuisineInference? {
        guard candidate.primaryCategory == restaurantsFood else { return nil }

        return restaurantCuisineInference(
            name: candidate.name,
            rawProviderType: candidate.rawProviderType,
            subcategory: candidate.subcategory,
            category: candidate.category,
            websiteURLString: candidate.websiteURLString
        )
    }

    private static func cuisineAliasGuess(forRawValue rawValue: String?) -> String? {
        let normalized = normalizedCategoryText(rawValue)
        guard !normalized.isEmpty else { return nil }

        let aliases: [(cuisine: String, terms: [String])] = [
            ("Mexican", ["taqueria", "tortilleria"]),
            ("Italian", ["trattoria", "osteria", "ristorante", "cafeugo"]),
            ("Pizza", ["pizzeria"]),
            ("Japanese", ["udon", "soba", "teppanyaki"]),
            ("Vietnamese", ["banh mi"]),
            ("Bao buns", ["bao", "bao bun", "baozi"]),
            ("Indian", ["tandoor", "tandoori", "masala"]),
            ("Middle Eastern", ["mezze"]),
            ("Mediterranean", ["mediterranean grill"])
        ]

        return aliases.first { alias in
            alias.terms.contains { term in
                let normalizedTerm = normalizedCategoryText(term)
                return " \(normalized) ".contains(" \(normalizedTerm) ")
            }
        }?.cuisine
    }

    static func preferredProviderType(
        primaryType: String?,
        types: [String],
        matchingPrimaryCategory primaryCategory: String
    ) -> String? {
        let requiredPrimary = normalizedPrimaryCategory(primaryCategory)
        var seen = Set<String>()
        let candidates = ([primaryType] + types.map(Optional.some))
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert(normalizedCategoryText($0)).inserted }

        return candidates.enumerated().max { lhs, rhs in
            providerTypeSpecificity(
                lhs.element,
                preferred: lhs.offset == 0,
                matchingPrimaryCategory: requiredPrimary
            ) < providerTypeSpecificity(
                rhs.element,
                preferred: rhs.offset == 0,
                matchingPrimaryCategory: requiredPrimary
            )
        }.flatMap { candidate in
            providerTypeSpecificity(
                candidate.element,
                preferred: candidate.offset == 0,
                matchingPrimaryCategory: requiredPrimary
            ) >= 0 ? candidate.element : nil
        }
    }

    static func correctiveProviderPrimaryType(
        _ primaryType: String?,
        for existingAssignment: PlaceCategoryAssignment
    ) -> String? {
        guard !existingAssignment.isUserEdited,
              providerAssignmentIsGeneric(existingAssignment),
              let primaryType,
              !primaryType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let candidate = assignment(
            forRawCategory: primaryType,
            source: PlaceCategorySource.provider.rawValue,
            confidence: 0.98,
            rawProviderType: primaryType
        )
        let existingPrimary = normalizedPrimaryCategory(existingAssignment.primaryCategory)
        let candidatePrimary = normalizedPrimaryCategory(candidate.primaryCategory)
        guard candidatePrimary != fallbackPlace,
              candidatePrimary != existingPrimary
        else {
            return nil
        }

        if existingPrimary == fallbackPlace {
            return primaryType
        }

        let normalizedType = normalizedCategoryText(primaryType)
        let adjacentFoodCategories = Set([restaurantsFood, coffeeTeaSweets, barsNightlife])
        if adjacentFoodCategories.contains(existingPrimary),
           adjacentFoodCategories.contains(candidatePrimary) {
            return primaryType
        }

        if existingPrimary == restaurantsFood,
           candidatePrimary == shopping,
           containsAny(normalizedType, [
               "food market", "grocery", "supermarket", "hypermarket", "warehouse store", "wholesaler"
           ]) {
            return primaryType
        }

        let adjacentCareCategories = Set([wellnessFitness, servicesErrands])
        if adjacentCareCategories.contains(existingPrimary),
           adjacentCareCategories.contains(candidatePrimary) {
            return primaryType
        }

        return nil
    }

    static func providerAssignmentNeedsEnrichment(_ assignment: PlaceCategoryAssignment) -> Bool {
        guard !assignment.isUserEdited else { return false }
        if assignment.confidence == 0.99 {
            return false
        }
        return providerAssignmentIsGeneric(assignment)
    }

    static func isMoreSpecificProviderType(
        _ candidate: String,
        than existing: String?,
        matchingPrimaryCategory primaryCategory: String
    ) -> Bool {
        providerTypeSpecificity(
            candidate,
            preferred: false,
            matchingPrimaryCategory: primaryCategory
        ) > providerTypeSpecificity(
            existing,
            preferred: false,
            matchingPrimaryCategory: primaryCategory
        )
    }

    static func emoji(
        for category: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        rawProviderType: String? = nil,
        name: String? = nil
    ) -> String {
        WanderPlaceEmojiResolver.emoji(
            forRawCategory: category,
            subcategory: subcategory,
            cuisine: cuisine,
            rawProviderType: rawProviderType,
            name: name
        )
    }

    static func emoji(
        for assignment: PlaceCategoryAssignment,
        cuisine: String? = nil,
        name: String? = nil
    ) -> String {
        WanderPlaceEmojiResolver.emoji(for: assignment, cuisine: cuisine, name: name)
    }

    static func broadEmoji(for category: String) -> String {
        entry(for: normalizedPrimaryCategory(category))?.emoji ?? "📍"
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

        if let providerCategory = providerCategoryAssignment(for: rawCategory),
           providerCategory.primaryCategory == primary {
            return providerCategory.subcategory
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
        let canonicalValue = mapKitProviderMetadata(for: value)?.canonicalType ?? value
        return canonicalValue
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .joined(separator: " ")
    }

    private static func subcategory(forRawValue rawValue: String, primaryCategory: String) -> String? {
        if primaryCategory == fallbackPlace {
            return nil
        }

        if let providerCategory = providerCategoryAssignment(for: rawValue),
           providerCategory.primaryCategory == primaryCategory {
            return providerCategory.subcategory
        }
        let normalized = normalizedCategoryText(rawValue)
        guard !normalized.isEmpty else {
            return defaultSubcategory(for: primaryCategory)
        }

        if let legacyDefault = legacyDefaultSubcategories[normalized] {
            return legacyDefault
        }

        if primaryCategory == restaurantsFood,
           cuisineGuess(forRawValue: rawValue) != nil {
            return defaultSubcategory(for: restaurantsFood)
        }

        if let indexed = taxonomyByKey[primaryCategory] {
            if let exactSuggestion = indexed.subcategories[normalized] {
                return exactSuggestion
            }

            if normalized == indexed.idKey || normalized == indexed.groupKey {
                return indexed.entry.defaultSubcategory
            }

            if indexed.aliases.contains(where: { $0.key == normalized }) {
                return indexed.entry.defaultSubcategory
            }
        }

        return normalizedSubcategory(rawValue) ?? defaultSubcategory(for: primaryCategory)
    }

    private static func entry(for category: String) -> PlaceCategoryTaxonomyEntry? {
        (taxonomyByKey[category] ?? taxonomyByKey[normalizedCategoryText(category)])?.entry
    }

    private static func sourceDisplayLabel(_ source: String) -> String {
        switch PlaceCategorySource(rawValue: source) {
        case .user:
            "edited"
        case .snapshot:
            "saved"
        case .consensus:
            "community"
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
        let normalizedNameKey = normalizedCategoryText(normalizedName)

        if pointCategory == .restaurant {
            if normalizedNameKey == "caffenio" {
                return coffeeTeaSweets
            }

            if normalizedNameKey == "whole foods market"
                || normalizedNameKey.hasPrefix("whole foods market ") {
                return shopping
            }
        }

        if containsAny(normalizedName, ["veterinary", "veterinarian", " vet ", "animal hospital", "pet hospital", "pet clinic", "dog dental", "cat clinic"]) {
            return wellnessFitness
        }

        if containsAny(normalizedName, ["optometrist", "ophthalmologist", "eye doctor", "eye care", "vision center", "optical"]) {
            return wellnessFitness
        }

        if containsAny(normalizedName, ["temple", "shrine", "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue"]) {
            return civicFaith
        }

        if containsAny(normalizedName, [
            "hospital", "medical center", "health center", "urgent care", "pharmacy", "drugstore",
            "dermatology", "pediatrics", "physical therapy", "chiropractor", "wellness studio", "spa"
        ]) {
            return wellnessFitness
        }

        if containsAny(normalizedName, ["pilates", "plankhaus", "lagree", "reformer", " gym ", "fitness", "training", "strength", "workout"]) {
            return wellnessFitness
        }

        if containsAny(normalizedName, [
            "nail salon", "nails", "manicure", "pedicure", "hair salon", "barbershop", "barber shop", "barber", "tattoo"
        ]) {
            return servicesErrands
        }

        let isFitnessCategory = pointCategory == .fitnessCenter
        if isFitnessCategory, containsAny(normalizedName, ["studio", "barre", "yoga", "stretch"]) {
            return wellnessFitness
        }

        return nil
    }

    private static func containsAny(_ normalizedName: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            let normalizedNeedle = normalizedCategoryText(needle)
            return !normalizedNeedle.isEmpty && " \(normalizedName) ".contains(" \(normalizedNeedle) ")
        }
    }

    private static func providerTypeSpecificity(
        _ value: String?,
        preferred: Bool,
        matchingPrimaryCategory primaryCategory: String
    ) -> Int {
        guard let value else { return -1 }
        let normalized = normalizedCategoryText(value)
        guard !normalized.isEmpty else { return -1 }

        let assignment = assignment(
            forRawCategory: value,
            source: PlaceCategorySource.provider.rawValue,
            rawProviderType: value
        )
        let requiredPrimary = normalizedPrimaryCategory(primaryCategory)
        guard assignment.primaryCategory != fallbackPlace,
              requiredPrimary == fallbackPlace || assignment.primaryCategory == requiredPrimary
        else {
            return -1
        }

        let ignoredGenericTypes: Set<String> = [
            "establishment", "point of interest", "premise", "geocode", "political"
        ]
        guard !ignoredGenericTypes.contains(normalized) else { return -1 }

        let lowInformationTypes: Set<String> = [
            "place", "food", "restaurant", "bar", "cafe", "store", "service"
        ]
        var score = lowInformationTypes.contains(normalized) ? 10 : 30
        if cuisineGuess(forRawValue: value) != nil {
            score += 200
        }
        if let subcategory = assignment.subcategory,
           normalizedCategoryText(subcategory) != normalizedCategoryText(defaultSubcategory(for: assignment.primaryCategory)) {
            score += 80
        }
        if preferred {
            score += 5
        }
        return score
    }

    private static func categoryEvidenceSpecificity(
        _ value: String,
        primaryCategory: String,
        subcategory: String
    ) -> Int {
        let normalized = normalizedCategoryText(value)
        let ignoredGenericTypes: Set<String> = [
            "establishment", "point of interest", "premise", "geocode", "political"
        ]
        guard !normalized.isEmpty, !ignoredGenericTypes.contains(normalized) else {
            return -1
        }

        let lowInformationTypes: Set<String> = [
            "place", "food", "restaurant", "bar", "cafe", "store", "service",
            normalizedCategoryText(primaryCategory),
            normalizedCategoryText(broadCategory(for: primaryCategory))
        ]
        var score = lowInformationTypes.contains(normalized) ? 10 : 30
        if cuisineGuess(forRawValue: value) != nil {
            score += 200
        }
        if normalizedCategoryText(subcategory)
            != normalizedCategoryText(defaultSubcategory(for: primaryCategory)) {
            score += 80
        }
        return score
    }

    private static func providerAssignmentIsGeneric(_ assignment: PlaceCategoryAssignment) -> Bool {
        let primary = normalizedPrimaryCategory(assignment.primaryCategory)
        if primary == fallbackPlace {
            return true
        }

        let normalizedType = normalizedCategoryText(assignment.rawProviderType)
        let normalizedSubcategory = normalizedCategoryText(assignment.subcategory)
        let genericValues = Set([
            normalizedCategoryText(primary),
            normalizedCategoryText(broadCategory(for: primary)),
            normalizedCategoryText(defaultSubcategory(for: primary)),
            "place",
            "establishment",
            "point of interest",
            "food",
            "restaurant",
            "bar",
            "cafe",
            "store",
            "service"
        ])
        return genericValues.contains(normalizedType)
            && genericValues.contains(normalizedSubcategory)
    }

    static func providerCategoryAssignment(
        for value: String?
    ) -> (primaryCategory: String, subcategory: String)? {
        guard let key = providerTypeKey(value),
              let metadata = mapKitProviderCategories[key] ?? explicitProviderCategories[key] else { return nil }
        return (metadata.primaryCategory, metadata.subcategory)
    }

    /// Exact provider type tokens only. Generic gyms and business names never
    /// become CrossFit, Pilates or surf-break evidence. These are not MapKit enum cases.
    private static let explicitProviderCategories: [String: ProviderCategoryMetadata] = [
        "beachtennis": ProviderCategoryMetadata(canonicalType: "beach tennis", primaryCategory: wellnessFitness, subcategory: "Beach tennis"),
        "beachtenniscourt": ProviderCategoryMetadata(canonicalType: "beach tennis", primaryCategory: wellnessFitness, subcategory: "Beach tennis"),
        "beachvolleyball": ProviderCategoryMetadata(canonicalType: "beach volleyball", primaryCategory: wellnessFitness, subcategory: "Beach volleyball"),
        "beachvolleyballcourt": ProviderCategoryMetadata(canonicalType: "beach volleyball", primaryCategory: wellnessFitness, subcategory: "Beach volleyball"),
        "padel": ProviderCategoryMetadata(canonicalType: "padel court", primaryCategory: wellnessFitness, subcategory: "Padel court"),
        "padelcourt": ProviderCategoryMetadata(canonicalType: "padel court", primaryCategory: wellnessFitness, subcategory: "Padel court"),
        "climbinggym": ProviderCategoryMetadata(canonicalType: "climbing gym", primaryCategory: wellnessFitness, subcategory: "Climbing gym"),
        "rockclimbinggym": ProviderCategoryMetadata(canonicalType: "climbing gym", primaryCategory: wellnessFitness, subcategory: "Climbing gym"),
        "arena": ProviderCategoryMetadata(canonicalType: "arena", primaryCategory: thingsToDo, subcategory: "Arena"),
        "surf": ProviderCategoryMetadata(canonicalType: "surf", primaryCategory: outdoorsNature, subcategory: "Surf"),
        "surfbreak": ProviderCategoryMetadata(canonicalType: "surf break", primaryCategory: outdoorsNature, subcategory: "Surf break"),
        "surfschool": ProviderCategoryMetadata(canonicalType: "surf school", primaryCategory: wellnessFitness, subcategory: "Surf school"),
        "surfshop": ProviderCategoryMetadata(canonicalType: "surf shop", primaryCategory: shopping, subcategory: "Surf shop"),
        "kayakrental": ProviderCategoryMetadata(canonicalType: "kayak/canoe rental", primaryCategory: outdoorsNature, subcategory: "Kayak/canoe rental"),
        "canoerental": ProviderCategoryMetadata(canonicalType: "kayak/canoe rental", primaryCategory: outdoorsNature, subcategory: "Kayak/canoe rental"),
        "kayakcanoerental": ProviderCategoryMetadata(canonicalType: "kayak/canoe rental", primaryCategory: outdoorsNature, subcategory: "Kayak/canoe rental"),

        "volleyballcourt": ProviderCategoryMetadata(canonicalType: "volleyball court", primaryCategory: wellnessFitness, subcategory: "Volleyball court"),
        "pilates": ProviderCategoryMetadata(canonicalType: "pilates studio", primaryCategory: wellnessFitness, subcategory: "Pilates studio"),
        "pilatesstudio": ProviderCategoryMetadata(canonicalType: "pilates studio", primaryCategory: wellnessFitness, subcategory: "Pilates studio"),
        "crossfit": ProviderCategoryMetadata(canonicalType: "crossfit gym", primaryCategory: wellnessFitness, subcategory: "CrossFit gym"),
        "crossfitgym": ProviderCategoryMetadata(canonicalType: "crossfit gym", primaryCategory: wellnessFitness, subcategory: "CrossFit gym"),
        "functionalfitness": ProviderCategoryMetadata(canonicalType: "functional fitness studio", primaryCategory: wellnessFitness, subcategory: "Functional fitness studio"),
        "functionalfitnessstudio": ProviderCategoryMetadata(canonicalType: "functional fitness studio", primaryCategory: wellnessFitness, subcategory: "Functional fitness studio")
    ]

    private static func mapKitProviderMetadata(for value: String?) -> ProviderCategoryMetadata? {
        guard let key = providerTypeKey(value) else { return nil }
        return mapKitProviderCategories[key]
    }

    private static func providerTypeKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let key = value
            .lowercased()
            .replacingOccurrences(of: "mkpoicategory", with: "")
            .filter { $0.isLetter || $0.isNumber }
        return key.isEmpty ? nil : key
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
