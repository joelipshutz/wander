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
        self.subcategory = WanderPlaceCategory.canonicalSubcategory(subcategory, primaryCategory: normalizedPrimary)
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
    static let restaurantCuisine = "restaurant_cuisine"
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
            detail: "Restaurants, cuisines, quick bites",
            defaultSubcategory: "Restaurant",
            symbolName: "fork.knife",
            aliases: [
            "restaurants_food", "restaurants food", "restaurants and food", "food_drink", "food drink",
            "food and drink", "restaurant", "restaurants", "fast food", "fine dining", "casual family", "diner",
            "bistro", "buffet", "food court", "takeout", "cafeteria", "breakfast", "brunch", "sandwich", "deli",
            "pizza", "burger", "barbecue", "ramen", "noodle", "dumpling", "dim sum", "hot pot", "taco", "taqueria",
            "thai restaurant", "sushi restaurant", "korean bbq"
        ],
            subcategories: [
            "Restaurant", "Fast food", "Fine dining", "Casual/family", "Diner", "Bistro", "Buffet", "Food court",
            "Takeout", "Cafeteria", "Breakfast", "Brunch", "Sandwich", "Bagel", "Deli", "Salad", "Soup", "Pizza",
            "Burgers", "Hot dogs", "Barbecue", "Chicken", "Wings", "Seafood", "Oyster bar", "Fish & chips",
            "Taco stand", "Taco truck", "Steakhouse", "Vegetarian", "Vegan", "Halal", "Ramen", "Noodles",
            "Dumplings", "Dim sum", "Hot pot", "Fondue", "Burrito", "Taco", "Falafel", "Gyro", "Kebab", "Shawarma",
            "Bar & grill", "Snack bar", "Gastropub", "American", "Mexican", "Thai", "Vietnamese", "Chinese",
            "Cantonese", "Taiwanese", "Korean", "Japanese", "Sushi", "Izakaya", "Yakitori", "Yakiniku", "Indian",
            "North Indian", "South Indian", "Pakistani", "Sri Lankan", "Bangladeshi", "Afghan", "Middle Eastern",
            "Lebanese", "Persian", "Turkish", "Israeli", "Moroccan", "Mediterranean", "Greek", "Italian", "French",
            "Spanish", "Tapas", "Portuguese", "Basque", "German", "Austrian", "Bavarian", "Swiss", "Dutch",
            "Belgian", "British", "Irish", "Scandinavian", "Polish", "Ukrainian", "Russian", "Czech", "Hungarian",
            "Romanian", "Croatian", "Ethiopian", "African", "Caribbean", "Jamaican", "Panamanian", "Cuban",
            "Brazilian", "Argentinian", "Colombian", "Chilean", "Peruvian", "South American", "Latin American",
            "Tex-Mex", "Southwestern", "Cajun", "Californian", "Hawaiian", "Australian", "Malaysian", "Indonesian",
            "Filipino", "Burmese", "Cambodian", "Asian", "Asian fusion", "European", "Eastern European", "Danish",
            "Tibetan", "Mongolian BBQ", "Korean BBQ", "Japanese BBQ", "Japanese curry", "Tonkatsu"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: coffeeTeaSweets,
            group: "Coffee, Tea, & Sweets",
            detail: "Coffee, tea, bakeries",
            defaultSubcategory: "Coffee shop",
            symbolName: "cup.and.saucer.fill",
            aliases: [
            "coffee_tea_sweets", "coffee tea sweets", "coffee tea and sweets", "coffee", "coffee shop", "cafe",
            "espresso", "roaster", "roastery", "tea", "tea house", "tea store", "bakery", "dessert", "sweets",
            "juice", "smoothie", "acai", "ice cream", "candy", "chocolate", "cat cafe", "dog cafe"
        ],
            subcategories: [
            "Coffee shop", "Cafe", "Coffee stand", "Coffee lounge", "Roastery", "Tea house", "Tea store", "Juice shop",
            "Smoothie shop", "Acai", "Bakery", "Bagel shop", "Donut shop", "Cake shop", "Pastry shop",
            "Dessert shop", "Dessert restaurant", "Ice cream", "Candy store", "Chocolate shop",
            "Chocolate factory", "Chocolate lounge", "Confectionery", "Cat cafe", "Dog cafe"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: barsNightlife,
            group: "Bars & Nightlife",
            detail: "Bars, lounges, clubs",
            defaultSubcategory: "Bar",
            symbolName: "wineglass.fill",
            aliases: [
            "bars_nightlife", "bars nightlife", "bars and nightlife", "bar", "bars", "nightlife",
            "mkpoicategorynightlife", "cocktail", "pub", "sports bar", "wine bar", "lounge", "club", "disco",
            "brewery", "brewpub", "winery", "vineyard", "nightclub", "karaoke", "live music", "comedy club",
            "casino"
        ],
            subcategories: [
            "Bar", "Cocktail bar", "Pub", "Irish pub", "Billiards", "Sports bar", "Wine bar", "Gastropub",
            "Bar & grill", "Dance hall", "Club", "Disco", "Lounge", "Hookah bar", "Beer garden", "Jazz club",
            "Hi-fi lounge", "Brewery", "Brewpub", "Winery", "Vineyard", "Nightclub", "Karaoke", "Live music",
            "Comedy club", "Casino"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: outdoorsNature,
            group: "Outdoors & Nature",
            detail: "Parks, trails, water",
            defaultSubcategory: "Park",
            symbolName: "tree.fill",
            aliases: [
            "outdoors_nature", "outdoors nature", "outdoors and nature", "outdoors", "nature", "hike", "hiking",
            "trail", "trailhead", "waterfall", "hot spring", "canyon", "mountain", "park", "national park",
            "playground", "garden", "beach", "lake", "campground", "rv park", "marina", "ski resort", "skate park"
        ],
            subcategories: [
            "Park", "City park", "State park", "National park", "Hiking area", "Trail", "Hike", "Beach", "Lake",
            "River", "Island", "Woods/forest", "Mountain peak", "Scenic spot", "Viewpoint", "Overlook",
            "Waterfall", "Hot spring", "Cave", "Nature preserve", "Wildlife refuge", "Wildlife park",
            "Botanical garden", "Garden", "Picnic area", "Dog park", "Playground", "Campground", "RV park",
            "Dispersed camping", "Cabin", "Cottage", "Marina", "Fishing pier", "Fishing pond", "Fishing charter",
            "Ski resort", "Cycling park", "Skate park", "Off-roading area", "Adventure sports"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: thingsToDo,
            group: "Things To Do",
            detail: "Attractions, arts, venues",
            defaultSubcategory: "Tourist attraction",
            symbolName: "ticket.fill",
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
            "Dance hall", "Barbecue area"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: shopping,
            group: "Shopping",
            detail: "Stores, markets, supplies",
            defaultSubcategory: "Store",
            symbolName: "bag.fill",
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
            "Pet store", "Auto parts", "Thrift store", "Discount supermarket", "Cosmetics"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: wellnessFitness,
            group: "Wellness & Fitness",
            detail: "Health, beauty, fitness",
            defaultSubcategory: "Gym",
            symbolName: "heart.fill",
            aliases: [
            "wellness_fitness", "wellness fitness", "wellness and fitness", "health_wellness", "health wellness",
            "sports_fitness", "sports fitness", "health", "wellness", "fitness", "gym", "fitness center", "yoga",
            "sports club", "sports complex", "hospital", "medical", "clinic", "doctor", "dentist", "pharmacy",
            "drugstore", "spa", "massage", "sauna", "therapy", "veterinary care", "veterinarian"
        ],
            subcategories: [
            "Gym", "Fitness center", "Yoga studio", "Wellness studio", "Wellness center", "Sports club",
            "Sports complex", "Sports coaching", "Sports school", "Athletic field", "Swimming pool",
            "Tennis court", "Golf course", "Indoor golf", "Ice skating rink", "Volleyball court", "Soccer field",
            "Basketball court", "Pickleball court", "Spa", "Massage", "Massage spa", "Sauna", "Chiropractor",
            "Dentist", "Dental clinic", "Doctor", "Medical clinic", "Medical center", "Hospital", "Medical lab",
            "Pharmacy", "Drugstore", "Physiotherapist", "Foot care", "Veterinary care", "Mental health/therapy",
            "Retreat"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: stays,
            group: "Stays",
            detail: "Hotels, rentals, camping",
            defaultSubcategory: "Hotel",
            symbolName: "bed.double.fill",
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
            symbolName: "scissors",
            aliases: [
            "services_errands", "services errands", "services and errands", "services", "service", "bank", "atm",
            "accounting", "insurance", "real estate", "lawyer", "consultant", "florist", "catering", "child care",
            "laundry", "tailor", "courier", "shipping", "storage", "moving", "electrician", "plumber", "locksmith",
            "contractor", "pet care", "pet boarding", "salon", "barber", "nail salon", "tattoo"
        ],
            subcategories: [
            "Bank", "ATM", "Accounting", "Insurance", "Real estate", "Lawyer", "Consultant",
            "Marketing consultant", "Employment agency", "Nonprofit", "Association", "Florist", "Catering",
            "Food delivery", "Child care", "Summer camp", "Laundry", "Tailor", "Courier", "Shipping", "Storage",
            "Moving", "Electrician", "Plumber", "Locksmith", "Painter", "Roofing contractor", "General contractor",
            "Pet care", "Pet boarding", "Funeral home", "Cemetery", "Astrologer", "Psychic", "Tour agency",
            "Travel agency", "Tourist information", "Chauffeur", "Aircraft rental", "Telecommunications",
            "Skin care clinic", "Tanning studio", "Hair salon", "Barber", "Nail salon", "Makeup artist",
            "Body art", "Tattoo/piercing"
        ],
            isEditable: true
        ),
        PlaceCategoryTaxonomyEntry(
            id: travelTransit,
            group: "Travel & Transit",
            detail: "Airports, stations, parking",
            defaultSubcategory: "Transit stop",
            symbolName: "tram.fill",
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
            symbolName: "graduationcap.fill",
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
            symbolName: "building.columns.fill",
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
            symbolName: "map.fill",
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
            symbolName: "mappin",
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
            symbolName: "mappin",
            aliases: [
            "place"
        ],
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
        "pilates studio": "Fitness center",
        "spiritual": "Place of worship",
        "hospital": "Hospital",
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
            PlaceCategorySubcategoryGroup(title: "Restaurant type", subcategories: [
                "Restaurant", "Fast food", "Fine dining", "Casual/family", "Diner", "Bistro", "Buffet",
                "Food court", "Takeout", "Cafeteria", "Breakfast", "Brunch", "Sandwich", "Bagel", "Deli", "Salad",
                "Soup", "Pizza", "Burgers", "Hot dogs", "Barbecue", "Chicken", "Wings", "Seafood", "Oyster bar",
                "Fish & chips", "Taco stand", "Taco truck", "Steakhouse", "Vegetarian", "Vegan", "Halal", "Ramen",
                "Noodles", "Dumplings", "Dim sum", "Hot pot", "Fondue", "Burrito", "Taco", "Falafel", "Gyro",
                "Kebab", "Shawarma", "Bar & grill", "Snack bar", "Gastropub"
            ]),
            PlaceCategorySubcategoryGroup(title: "Popular cuisines", subcategories: [
                "American", "Mexican", "Thai", "Vietnamese", "Chinese", "Korean", "Japanese", "Sushi", "Indian",
                "Italian", "Mediterranean", "Greek", "French", "Spanish", "Tex-Mex", "Asian fusion"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Asian cuisines", subcategories: [
                "Cantonese", "Taiwanese", "Izakaya", "Yakitori", "Yakiniku", "North Indian", "South Indian",
                "Malaysian", "Indonesian", "Filipino", "Burmese", "Cambodian", "Asian", "Tibetan", "Mongolian BBQ",
                "Korean BBQ", "Japanese BBQ", "Japanese curry", "Tonkatsu"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Middle East & Africa", subcategories: [
                "Pakistani", "Sri Lankan", "Bangladeshi", "Afghan", "Middle Eastern", "Lebanese", "Persian",
                "Turkish", "Israeli", "Moroccan", "Ethiopian", "African"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "European cuisines", subcategories: [
                "Tapas", "Portuguese", "Basque", "German", "Austrian", "Bavarian", "Swiss", "Dutch", "Belgian",
                "British", "Irish", "Scandinavian", "Polish", "Ukrainian", "Russian", "Czech", "Hungarian",
                "Romanian", "Croatian", "European", "Eastern European", "Danish"
            ], role: .cuisine),
            PlaceCategorySubcategoryGroup(title: "Americas & Pacific", subcategories: [
                "Caribbean", "Jamaican", "Panamanian", "Cuban", "Brazilian", "Argentinian", "Colombian", "Chilean",
                "Peruvian", "South American", "Latin American", "Southwestern", "Cajun", "Californian", "Hawaiian",
                "Australian"
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
                "Dessert restaurant", "Ice cream", "Candy store", "Chocolate shop", "Chocolate factory",
                "Chocolate lounge", "Confectionery"
            ])
        ],
        barsNightlife: [
            PlaceCategorySubcategoryGroup(title: "Bars & pubs", subcategories: [
                "Bar", "Cocktail bar", "Pub", "Irish pub", "Sports bar", "Wine bar", "Gastropub", "Bar & grill",
                "Beer garden", "Brewery", "Brewpub"
            ]),
            PlaceCategorySubcategoryGroup(title: "Lounges & clubs", subcategories: [
                "Dance hall", "Club", "Disco", "Lounge", "Hookah bar", "Jazz club", "Hi-fi lounge", "Nightclub",
                "Karaoke", "Live music", "Comedy club"
            ]),
            PlaceCategorySubcategoryGroup(title: "Wine & gaming", subcategories: [
                "Winery", "Vineyard", "Billiards", "Casino"
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
                "Beach", "Lake", "River", "Hot spring", "Campground", "RV park", "Dispersed camping", "Cabin",
                "Cottage", "Marina", "Fishing pier", "Fishing pond", "Fishing charter"
            ]),
            PlaceCategorySubcategoryGroup(title: "Outdoor sports", subcategories: [
                "Ski resort", "Cycling park", "Skate park", "Off-roading area", "Adventure sports"
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
                "Amphitheater", "Auditorium", "Movie theater", "Planetarium", "Observation deck"
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
                "Gym", "Fitness center", "Yoga studio", "Wellness studio", "Wellness center", "Sports club",
                "Sports complex", "Sports coaching", "Sports school", "Athletic field", "Swimming pool",
                "Tennis court", "Golf course", "Indoor golf", "Ice skating rink", "Volleyball court",
                "Soccer field", "Basketball court", "Pickleball court"
            ]),
            PlaceCategorySubcategoryGroup(title: "Wellness & recovery", subcategories: [
                "Spa", "Massage", "Massage spa", "Sauna", "Chiropractor", "Physiotherapist", "Foot care",
                "Mental health/therapy", "Retreat"
            ]),
            PlaceCategorySubcategoryGroup(title: "Medical care", subcategories: [
                "Dentist", "Dental clinic", "Doctor", "Medical clinic", "Medical center", "Hospital",
                "Medical lab", "Pharmacy", "Drugstore", "Veterinary care"
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

        if #available(iOS 18.0, *) {
            switch pointCategory {
            case .animalService:
                return servicesErrands
            case .hiking:
                return outdoorsNature
            case .rockClimbing, .skatePark, .skiing, .surfing:
                return outdoorsNature
            case .skating, .swimming:
                return wellnessFitness
            default:
                break
            }
        }

        switch pointCategory {
        case .cafe, .bakery:
            return coffeeTeaSweets
        case .restaurant, .foodMarket:
            return restaurantsFood
        case .brewery, .winery, .nightlife:
            return barsNightlife
        case .park, .nationalPark:
            return outdoorsNature
        case .hospital:
            return wellnessFitness
        case .fitnessCenter:
            return wellnessFitness
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

    static func canonicalSubcategory(_ value: String?, primaryCategory: String) -> String? {
        guard let normalized = normalizedSubcategory(value) else { return nil }
        let key = normalizedCategoryText(normalized)
        let primary = normalizedPrimaryCategory(primaryCategory)

        return entry(for: primary)?.subcategories.first { subcategory in
            normalizedCategoryText(subcategory) == key
        } ?? normalized
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

    static func restaurantTypeGroups() -> [PlaceCategorySubcategoryGroup] {
        subcategoryGroups(for: restaurantsFood).filter { $0.role == .type }
    }

    static func restaurantCuisineGroups() -> [PlaceCategorySubcategoryGroup] {
        subcategoryGroups(for: restaurantsFood).filter { $0.role == .cuisine }
    }

    static var restaurantCuisineOptions: [String] {
        restaurantCuisineGroups().flatMap(\.subcategories)
    }

    static func isRestaurantCuisine(_ value: String?) -> Bool {
        cuisineGuess(forRawValue: value) != nil
    }

    static func cuisineGuess(forRawValue rawValue: String?) -> String? {
        let normalized = normalizedCategoryText(rawValue)
        guard !normalized.isEmpty else { return nil }

        return restaurantCuisineOptions
            .sorted { normalizedCategoryText($0).count > normalizedCategoryText($1).count }
            .first { cuisine in
                let normalizedCuisine = normalizedCategoryText(cuisine)
                return normalized == normalizedCuisine
                    || normalized.contains(normalizedCuisine)
                    || normalized.replacingOccurrences(of: " cuisine", with: "") == normalizedCuisine
            }
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
            .replacingOccurrences(of: "mkpoicategory", with: " ")
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

        if primaryCategory == restaurantsFood,
           cuisineGuess(forRawValue: rawValue) != nil {
            return defaultSubcategory(for: restaurantsFood)
        }

        if let entry = entry(for: primaryCategory) {
            if let exactSuggestion = entry.subcategories.first(where: { normalizedCategoryText($0) == normalized }) {
                return exactSuggestion
            }

            if normalized == normalizedCategoryText(entry.id) || normalized == normalizedCategoryText(entry.group) {
                return entry.defaultSubcategory
            }
        }

        if let entry = entry(for: primaryCategory),
           entry.aliases.contains(where: { normalizedCategoryText($0) == normalized }) {
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
            return wellnessFitness
        }

        if containsAny(normalizedName, ["temple", "shrine", "spiritual", "church", "chapel", "cathedral", "mosque", "synagogue"]) {
            return civicFaith
        }

        if containsAny(normalizedName, ["hospital", "medical center", "health center", "urgent care", "pharmacy", "drugstore", "wellness studio", "spa"]) {
            return wellnessFitness
        }

        if containsAny(normalizedName, ["pilates", "plankhaus", "lagree", "reformer", " gym ", "fitness", "training", "strength", "workout"]) {
            return wellnessFitness
        }

        let isFitnessCategory = pointCategory == .fitnessCenter
        if isFitnessCategory, containsAny(normalizedName, ["studio", "barre", "yoga", "stretch"]) {
            return wellnessFitness
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
