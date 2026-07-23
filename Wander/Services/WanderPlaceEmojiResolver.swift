import Foundation

enum WanderPlaceEmojiResolver {
    private struct Rule {
        let emoji: String
        let normalizedTerms: [String]

        init(emoji: String, terms: [String]) {
            self.emoji = emoji
            self.normalizedTerms = terms
                .map(WanderPlaceCategory.normalizedCategoryText)
                .filter { !$0.isEmpty }
        }
    }

    static func emoji(
        for assignment: PlaceCategoryAssignment,
        cuisine: String? = nil,
        name: String? = nil
    ) -> String {
        let primary = WanderPlaceCategory.normalizedPrimaryCategory(assignment.primaryCategory)
        let fallback = WanderPlaceCategory.broadEmoji(for: primary)

        if primary == WanderPlaceCategory.restaurantsFood {
            return restaurantEmoji(
                assignment: assignment,
                cuisine: cuisine,
                name: name,
                fallback: fallback
            )
        }

        let categoryRules = subcategoryRules[primary] ?? []
        let rules = universalSpecificRules + categoryRules

        let metadata = orderedMetadata(for: assignment)
        if assignment.isUserEdited {
            return firstMatch(in: metadata, rules: rules) ?? fallback
        }

        let specificMetadata = metadata.filter { !isGenericDetail($0, primaryCategory: primary) }

        if let emoji = firstMatch(in: specificMetadata, rules: rules) {
            return emoji
        }

        if let emoji = firstMatch(in: [name], rules: rules) {
            return emoji
        }

        return firstMatch(in: metadata, rules: rules) ?? fallback
    }

    static func emoji(
        forRawCategory category: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        rawProviderType: String? = nil,
        name: String? = nil
    ) -> String {
        let normalizedCategory = WanderPlaceCategory.normalizedCategoryText(category)
        let broadEntry = WanderPlaceCategory.taxonomy.first { entry in
            WanderPlaceCategory.normalizedCategoryText(entry.id) == normalizedCategory
                || WanderPlaceCategory.normalizedCategoryText(entry.group) == normalizedCategory
        }

        if subcategory == nil, cuisine == nil, rawProviderType == nil, name == nil, broadEntry != nil {
            return broadEntry?.emoji ?? "📍"
        }

        let assignment: PlaceCategoryAssignment
        if let subcategory {
            assignment = WanderPlaceCategory.assignment(
                primaryCategory: category,
                subcategory: subcategory,
                source: PlaceCategorySource.user.rawValue,
                confidence: 1,
                rawProviderType: rawProviderType
            )
        } else {
            assignment = WanderPlaceCategory.assignment(
                forRawCategory: rawProviderType ?? category,
                rawProviderType: rawProviderType ?? category
            )
        }

        return emoji(for: assignment, cuisine: cuisine, name: name)
    }

    private static func restaurantEmoji(
        assignment: PlaceCategoryAssignment,
        cuisine: String?,
        name: String?,
        fallback: String
    ) -> String {
        let metadata = orderedMetadata(for: assignment)
        let specificTypes = metadata.filter {
            !isGenericDetail($0, primaryCategory: WanderPlaceCategory.restaurantsFood)
                && WanderPlaceCategory.cuisineGuess(forRawValue: $0) == nil
        }

        if let emoji = cuisineEmoji(for: cuisine) {
            return emoji
        }

        if let emoji = firstMatch(in: specificTypes, rules: restaurantDetailRules) {
            return emoji
        }

        for value in [assignment.subcategory, assignment.rawProviderType] {
            if let emoji = cuisineEmoji(for: value) {
                return emoji
            }
        }

        if let emoji = firstMatch(in: [name], rules: restaurantDetailRules) {
            return emoji
        }

        if let emoji = cuisineEmoji(for: name) {
            return emoji
        }

        return firstMatch(in: metadata, rules: restaurantDetailRules) ?? fallback
    }

    private static func cuisineEmoji(for value: String?) -> String? {
        guard let cuisine = WanderPlaceCategory.cuisineGuess(forRawValue: value) else {
            return nil
        }
        return restaurantCuisineEmojis[WanderPlaceCategory.normalizedCategoryText(cuisine)]
            ?? firstMatch(in: [cuisine], rules: restaurantDetailRules)
    }

    private static func orderedMetadata(for assignment: PlaceCategoryAssignment) -> [String?] {
        if assignment.isUserEdited {
            return [assignment.subcategory]
        }
        return [assignment.rawProviderType, assignment.subcategory]
    }

    private static func firstMatch(in values: [String?], rules: [Rule]) -> String? {
        for value in values {
            let normalizedValue = WanderPlaceCategory.normalizedCategoryText(value)
            guard !normalizedValue.isEmpty else { continue }

            for rule in rules {
                if rule.normalizedTerms.contains(where: {
                    matches(normalizedValue: normalizedValue, normalizedTerm: $0)
                }) {
                    return rule.emoji
                }
            }
        }
        return nil
    }

    private static func matches(_ value: String?, term: String) -> Bool {
        let normalizedValue = WanderPlaceCategory.normalizedCategoryText(value)
        let normalizedTerm = WanderPlaceCategory.normalizedCategoryText(term)
        return matches(normalizedValue: normalizedValue, normalizedTerm: normalizedTerm)
    }

    private static func matches(normalizedValue: String, normalizedTerm: String) -> Bool {
        guard !normalizedValue.isEmpty, !normalizedTerm.isEmpty else { return false }

        if normalizedValue == normalizedTerm {
            return true
        }

        if " \(normalizedValue) ".contains(" \(normalizedTerm) ") {
            return true
        }

        return normalizedValue.replacingOccurrences(of: " ", with: "")
            == normalizedTerm.replacingOccurrences(of: " ", with: "")
    }

    private static func isGenericDetail(_ value: String?, primaryCategory: String) -> Bool {
        let normalized = WanderPlaceCategory.normalizedCategoryText(value)
        guard !normalized.isEmpty else { return true }

        let broadValues = [
            primaryCategory,
            WanderPlaceCategory.broadCategory(for: primaryCategory),
            WanderPlaceCategory.defaultSubcategory(for: primaryCategory)
        ]
        if broadValues.contains(where: {
            matches(
                normalizedValue: normalized,
                normalizedTerm: WanderPlaceCategory.normalizedCategoryText($0)
            )
        }) {
            return true
        }

        return genericDetails[primaryCategory]?.contains(where: {
            matches(normalizedValue: normalized, normalizedTerm: $0)
        }) == true
    }

    private static let genericDetails: [String: [String]] = {
        let values: [String: [String]] = [
            WanderPlaceCategory.restaurantsFood: ["restaurant", "casual family", "fine dining", "bistro"],
            WanderPlaceCategory.coffeeTeaSweets: ["coffee shop", "cafe"],
            WanderPlaceCategory.barsNightlife: ["bar", "lounge"],
            WanderPlaceCategory.outdoorsNature: ["park", "tourist attraction"],
            WanderPlaceCategory.thingsToDo: ["tourist attraction", "event venue"],
            WanderPlaceCategory.shopping: ["store", "market"],
            WanderPlaceCategory.wellnessFitness: [
                "gym", "wellness center", "wellness studio", "doctor", "medical clinic", "medical center"
            ],
            WanderPlaceCategory.stays: ["hotel", "lodging"],
            WanderPlaceCategory.servicesErrands: ["consultant", "service"],
            WanderPlaceCategory.travelTransit: ["transit stop", "transit station", "transportation service"],
            WanderPlaceCategory.workEducation: ["co working space", "business center"],
            WanderPlaceCategory.civicFaith: ["government office", "place of worship"],
            WanderPlaceCategory.areasAddresses: ["address", "area"],
            WanderPlaceCategory.facilitiesOther: ["point of interest", "generic establishment", "unknown"]
        ]

        return values.mapValues { terms in
            terms.map(WanderPlaceCategory.normalizedCategoryText)
        }
    }()

    private static let restaurantDetailRules: [Rule] = [
        Rule(emoji: "🌮", terms: ["taco stand", "taco truck", "taco"]),
        Rule(emoji: "🌯", terms: ["burrito"]),
        Rule(emoji: "🍕", terms: ["pizza", "pizzeria"]),
        Rule(emoji: "🍔", terms: ["burgers", "burger", "fast food"]),
        Rule(emoji: "🌭", terms: ["hot dogs", "hot dog"]),
        Rule(emoji: "🥪", terms: ["sandwich", "deli"]),
        Rule(emoji: "🥯", terms: ["bagel"]),
        Rule(emoji: "🥗", terms: ["salad", "vegetarian", "vegan", "gluten-free"]),
        Rule(emoji: "🥞", terms: ["breakfast", "brunch", "diner"]),
        Rule(emoji: "🍗", terms: ["chicken", "wings"]),
        Rule(emoji: "🦪", terms: ["oyster bar", "oyster"]),
        Rule(emoji: "🐟", terms: ["seafood", "fish and chips", "fish chips"]),
        Rule(emoji: "🥩", terms: ["steakhouse", "barbecue", "bbq"]),
        Rule(emoji: "🍜", terms: ["ramen", "noodles", "noodle"]),
        Rule(emoji: "🥟", terms: ["dumplings", "dumpling", "dim sum"]),
        Rule(emoji: "🍲", terms: ["hot pot", "fondue", "soup"]),
        Rule(emoji: "🧆", terms: ["falafel"]),
        Rule(emoji: "🥙", terms: ["gyro", "kebab", "shawarma", "halal"]),
        Rule(emoji: "🥡", terms: ["takeout"]),
        Rule(emoji: "🍱", terms: ["buffet", "food court", "cafeteria"]),
        Rule(emoji: "🍿", terms: ["snack bar"]),
        Rule(emoji: "🍷", terms: ["bistro"]),
        Rule(emoji: "🍺", terms: ["bar and grill", "gastropub"]),
        Rule(emoji: "🍽️", terms: ["fine dining", "casual family"])
    ]

    // These provider types are specific enough to survive an adjacent broad-category mismatch.
    // Map providers commonly place personal care under either services or wellness.
    private static let universalSpecificRules: [Rule] = [
        Rule(emoji: "🐾", terms: ["veterinary care", "veterinarian", "animal hospital", "pet hospital"]),
        Rule(emoji: "👁️", terms: [
            "optometrist", "ophthalmologist", "eye doctor", "eye care center", "vision center", "optical"
        ]),
        Rule(emoji: "🦷", terms: ["dentist", "dental clinic", "dental"]),
        Rule(emoji: "🏥", terms: ["urgent care", "hospital"]),
        Rule(emoji: "🧪", terms: ["medical lab", "laboratory"]),
        Rule(emoji: "💊", terms: ["pharmacy", "drugstore"]),
        Rule(emoji: "🧠", terms: ["mental health therapy", "mental health"]),
        Rule(emoji: "🩺", terms: ["dermatologist", "pediatrician", "medical clinic", "medical center"]),
        Rule(emoji: "🦴", terms: ["chiropractor", "physiotherapist", "physical therapy"]),
        Rule(emoji: "🦶", terms: ["foot care", "podiatrist"]),
        Rule(emoji: "💅", terms: ["nail salon", "manicure", "pedicure"]),
        Rule(emoji: "💈", terms: ["barber"]),
        Rule(emoji: "💇", terms: ["hair salon", "beauty salon"]),
        Rule(emoji: "💄", terms: ["makeup artist"]),
        Rule(emoji: "🖋️", terms: ["tattoo piercing", "body art", "tattoo"]),
        Rule(emoji: "☀️", terms: ["tanning studio"]),
        Rule(emoji: "💆", terms: ["massage spa", "massage", "spa"]),
        Rule(emoji: "🧖", terms: ["sauna"]),
        Rule(emoji: "🧘", terms: ["yoga studio", "pilates studio"]),
        Rule(emoji: "💪", terms: ["fitness center", "gym"]),
        Rule(emoji: "🥯", terms: ["bagel shop"]),
        Rule(emoji: "🍩", terms: ["donut shop", "doughnut shop"]),
        Rule(emoji: "🎂", terms: ["cake shop"]),
        Rule(emoji: "🥐", terms: ["bakery", "pastry shop", "patisserie", "bakehouse"]),
        Rule(emoji: "🫖", terms: ["tea house", "tea store", "tea room"]),
        Rule(emoji: "☕️", terms: ["coffee shop", "coffee stand", "coffee roaster", "roastery", "espresso bar"])
    ]

    private static let subcategoryRules: [String: [Rule]] = [
        WanderPlaceCategory.coffeeTeaSweets: [
            Rule(emoji: "🐈", terms: ["cat cafe"]),
            Rule(emoji: "🐕", terms: ["dog cafe"]),
            Rule(emoji: "🥯", terms: ["bagel shop", "bagel"]),
            Rule(emoji: "🍩", terms: ["donut shop", "doughnut", "donut"]),
            Rule(emoji: "🎂", terms: ["cake shop", "cake"]),
            Rule(emoji: "🥐", terms: ["bakery", "pastry shop", "patisserie", "bakehouse"]),
            Rule(emoji: "🍦", terms: ["ice cream", "gelato"]),
            Rule(emoji: "🍫", terms: ["chocolate shop", "chocolate factory", "chocolate lounge", "chocolate"]),
            Rule(emoji: "🍬", terms: ["candy store", "confectionery", "candy"]),
            Rule(emoji: "🍰", terms: ["dessert shop", "dessert restaurant", "dessert"]),
            Rule(emoji: "🧃", terms: ["juice shop", "juice bar"]),
            Rule(emoji: "🥤", terms: ["smoothie shop", "smoothie", "acai"]),
            Rule(emoji: "🫖", terms: ["tea house", "tea store", "tea room"]),
            Rule(emoji: "☕️", terms: [
                "coffee shop", "cafe", "coffee stand", "coffee lounge", "roastery", "coffee", "espresso"
            ])
        ],
        WanderPlaceCategory.barsNightlife: [
            Rule(emoji: "🎱", terms: ["billiards", "pool hall"]),
            Rule(emoji: "🍻", terms: ["sports bar"]),
            Rule(emoji: "🍷", terms: ["wine bar", "winery", "vineyard"]),
            Rule(emoji: "🥃", terms: ["distillery"]),
            Rule(emoji: "🍺", terms: ["brewery", "brewpub", "beer garden", "gastropub"]),
            Rule(emoji: "🍻", terms: ["irish pub", "pub"]),
            Rule(emoji: "🪩", terms: ["dance hall", "club", "disco", "nightclub"]),
            Rule(emoji: "💨", terms: ["hookah bar"]),
            Rule(emoji: "🎷", terms: ["jazz club"]),
            Rule(emoji: "🎧", terms: ["hi fi lounge"]),
            Rule(emoji: "🎤", terms: ["karaoke"]),
            Rule(emoji: "🎵", terms: ["live music"]),
            Rule(emoji: "🎙️", terms: ["comedy club"]),
            Rule(emoji: "🎰", terms: ["casino"]),
            Rule(emoji: "🍸", terms: ["cocktail bar", "lounge", "bar"]),
            Rule(emoji: "🍽️", terms: ["bar and grill"])
        ],
        WanderPlaceCategory.outdoorsNature: [
            Rule(emoji: "🏞️", terms: ["national park", "state park", "nature preserve"]),
            Rule(emoji: "🥾", terms: ["hiking area", "trail", "hike", "trailhead"]),
            Rule(emoji: "🏖️", terms: ["beach"]),
            Rule(emoji: "🏝️", terms: ["island"]),
            Rule(emoji: "🌊", terms: ["lake", "river"]),
            Rule(emoji: "🌲", terms: ["woods forest", "forest"]),
            Rule(emoji: "🏔️", terms: ["mountain peak", "mountain"]),
            Rule(emoji: "🌄", terms: ["scenic spot", "viewpoint", "overlook"]),
            Rule(emoji: "💦", terms: ["waterfall"]),
            Rule(emoji: "♨️", terms: ["hot spring"]),
            Rule(emoji: "🪨", terms: ["cave"]),
            Rule(emoji: "🦌", terms: ["wildlife refuge", "wildlife park"]),
            Rule(emoji: "🌻", terms: ["botanical garden", "garden"]),
            Rule(emoji: "🧺", terms: ["picnic area"]),
            Rule(emoji: "🐕", terms: ["dog park"]),
            Rule(emoji: "🛝", terms: ["playground"]),
            Rule(emoji: "⛺️", terms: ["campground", "rv park", "dispersed camping", "camping"]),
            Rule(emoji: "🛖", terms: ["cabin", "cottage"]),
            Rule(emoji: "⚓️", terms: ["marina"]),
            Rule(emoji: "🎣", terms: ["fishing pier", "fishing pond", "fishing charter"]),
            Rule(emoji: "🎣", terms: ["fishing"]),
            Rule(emoji: "🛶", terms: ["kayaking"]),
            Rule(emoji: "🏄", terms: ["surfing"]),
            Rule(emoji: "🎿", terms: ["ski resort"]),
            Rule(emoji: "🚴", terms: ["cycling park"]),
            Rule(emoji: "🛹", terms: ["skate park"]),
            Rule(emoji: "🚙", terms: ["off roading area"]),
            Rule(emoji: "🧗", terms: ["adventure sports", "rock climbing"]),
            Rule(emoji: "🌳", terms: ["city park", "park"])
        ],
        WanderPlaceCategory.thingsToDo: [
            Rule(emoji: "🏰", terms: ["castle"]),
            Rule(emoji: "🗿", terms: ["historical landmark", "historical place", "monument", "sculpture", "landmark"]),
            Rule(emoji: "⛲️", terms: ["fountain"]),
            Rule(emoji: "🏙️", terms: ["plaza", "town square"]),
            Rule(emoji: "ℹ️", terms: ["visitor center"]),
            Rule(emoji: "🎨", terms: ["art museum", "art gallery", "art studio"]),
            Rule(emoji: "🏛️", terms: ["history museum", "museum"]),
            Rule(emoji: "🎭", terms: [
                "cultural landmark", "cultural center", "performing arts theater", "theater", "opera house"
            ]),
            Rule(emoji: "🎶", terms: ["concert hall", "philharmonic hall"]),
            Rule(emoji: "🎵", terms: ["music venue"]),
            Rule(emoji: "🎪", terms: ["fairground"]),
            Rule(emoji: "🎟️", terms: ["amphitheater", "auditorium", "event venue", "convention center"]),
            Rule(emoji: "🎬", terms: ["movie theater", "cinema"]),
            Rule(emoji: "🔭", terms: ["planetarium", "observation deck"]),
            Rule(emoji: "🐠", terms: ["aquarium"]),
            Rule(emoji: "🦁", terms: ["zoo"]),
            Rule(emoji: "🎡", terms: ["ferris wheel"]),
            Rule(emoji: "🎢", terms: ["roller coaster", "amusement park"]),
            Rule(emoji: "🌊", terms: ["water park"]),
            Rule(emoji: "🕹️", terms: ["arcade"]),
            Rule(emoji: "🎳", terms: ["bowling"]),
            Rule(emoji: "⛳️", terms: ["mini golf"]),
            Rule(emoji: "🎱", terms: ["billiards"]),
            Rule(emoji: "🎯", terms: ["darts"]),
            Rule(emoji: "🪓", terms: ["axe throwing"]),
            Rule(emoji: "🎲", terms: ["board game lounge"]),
            Rule(emoji: "🏎️", terms: ["go karting"]),
            Rule(emoji: "🔫", terms: ["paintball"]),
            Rule(emoji: "🛝", terms: ["indoor playground"]),
            Rule(emoji: "💒", terms: ["wedding venue"]),
            Rule(emoji: "🍽️", terms: ["banquet hall"]),
            Rule(emoji: "👥", terms: ["community center"]),
            Rule(emoji: "💻", terms: ["internet cafe"]),
            Rule(emoji: "🪩", terms: ["dance hall"]),
            Rule(emoji: "🔥", terms: ["barbecue area"])
        ],
        WanderPlaceCategory.shopping: [
            Rule(emoji: "🏪", terms: ["convenience store"]),
            Rule(emoji: "🍚", terms: ["asian grocery"]),
            Rule(emoji: "🥩", terms: ["butcher"]),
            Rule(emoji: "🥬", terms: ["health food store"]),
            Rule(emoji: "🍾", terms: ["liquor store"]),
            Rule(emoji: "🛒", terms: [
                "discount supermarket", "grocery store", "supermarket", "hypermarket", "food store"
            ]),
            Rule(emoji: "🧺", terms: ["farmers market", "flea market", "market"]),
            Rule(emoji: "📚", terms: ["book store", "bookstore"]),
            Rule(emoji: "🎨", terms: ["art supply store", "craft store"]),
            Rule(emoji: "🎁", terms: ["gift shop"]),
            Rule(emoji: "🧸", terms: ["toy store"]),
            Rule(emoji: "👗", terms: ["women s clothing"]),
            Rule(emoji: "👕", terms: ["clothing store"]),
            Rule(emoji: "👟", terms: ["shoe store"]),
            Rule(emoji: "💍", terms: ["jewelry store"]),
            Rule(emoji: "💄", terms: ["cosmetics store", "beauty supply", "cosmetics"]),
            Rule(emoji: "🏀", terms: ["sporting goods", "sportswear"]),
            Rule(emoji: "🚲", terms: ["bicycle store"]),
            Rule(emoji: "📱", terms: ["cell phone store", "electronics"]),
            Rule(emoji: "🛋️", terms: ["furniture", "home goods"]),
            Rule(emoji: "🛠️", terms: [
                "home improvement", "hardware", "building materials"
            ]),
            Rule(emoji: "🪴", terms: ["garden center"]),
            Rule(emoji: "🐾", terms: ["pet store"]),
            Rule(emoji: "⚙️", terms: ["auto parts"]),
            Rule(emoji: "♻️", terms: ["thrift store"]),
            Rule(emoji: "🛍️", terms: [
                "shopping mall", "department store", "general store", "discount store", "warehouse store",
                "wholesaler", "store"
            ])
        ],
        WanderPlaceCategory.wellnessFitness: [
            Rule(emoji: "👁️", terms: [
                "optometrist", "ophthalmologist", "eye doctor", "eye care center", "vision center", "optical"
            ]),
            Rule(emoji: "🦷", terms: ["dentist", "dental clinic", "dental"]),
            Rule(emoji: "🐾", terms: ["veterinary care", "veterinarian", "animal hospital", "pet hospital"]),
            Rule(emoji: "🏥", terms: ["urgent care", "hospital"]),
            Rule(emoji: "🧪", terms: ["medical lab", "laboratory"]),
            Rule(emoji: "💊", terms: ["pharmacy", "drugstore"]),
            Rule(emoji: "🧠", terms: ["mental health therapy", "mental health", "therapy"]),
            Rule(emoji: "🩺", terms: [
                "dermatologist", "pediatrician", "doctor", "medical clinic", "medical center"
            ]),
            Rule(emoji: "🧘", terms: ["yoga studio", "retreat", "wellness studio", "wellness center"]),
            Rule(emoji: "💆", terms: ["massage spa", "massage", "spa"]),
            Rule(emoji: "🧖", terms: ["sauna"]),
            Rule(emoji: "🦴", terms: ["chiropractor", "physiotherapist", "physical therapy"]),
            Rule(emoji: "🦶", terms: ["foot care", "podiatrist"]),
            Rule(emoji: "🏊", terms: ["swimming pool"]),
            Rule(emoji: "🎾", terms: ["tennis court"]),
            Rule(emoji: "⛳️", terms: ["indoor golf", "golf course"]),
            Rule(emoji: "⛸️", terms: ["ice skating rink"]),
            Rule(emoji: "🏐", terms: ["volleyball court"]),
            Rule(emoji: "⚽️", terms: ["soccer field"]),
            Rule(emoji: "🏀", terms: ["basketball court"]),
            Rule(emoji: "🏓", terms: ["pickleball court"]),
            Rule(emoji: "🏟️", terms: ["athletic field", "sports complex"]),
            Rule(emoji: "⚾️", terms: ["baseball"]),
            Rule(emoji: "🏟️", terms: ["stadium"]),
            Rule(emoji: "🏅", terms: ["sports club", "sports coaching", "sports school"]),
            Rule(emoji: "💪", terms: ["fitness center", "gym", "fitness", "pilates", "training"])
        ],
        WanderPlaceCategory.stays: [
            Rule(emoji: "♨️", terms: ["japanese inn"]),
            Rule(emoji: "🛖", terms: ["farm stay", "cottage", "cabin"]),
            Rule(emoji: "⛺️", terms: ["campground", "rv park"]),
            Rule(emoji: "🚐", terms: ["mobile home park"]),
            Rule(emoji: "🏠", terms: ["private guest room", "airbnb", "vrbo", "guest house", "hostel"]),
            Rule(emoji: "🛏️", terms: ["bed and breakfast"]),
            Rule(emoji: "🏨", terms: ["resort", "motel", "extended stay", "hotel", "inn"])
        ],
        WanderPlaceCategory.servicesErrands: [
            Rule(emoji: "🏦", terms: ["bank", "atm"]),
            Rule(emoji: "🧮", terms: ["accounting"]),
            Rule(emoji: "🛡️", terms: ["insurance"]),
            Rule(emoji: "🏠", terms: ["real estate"]),
            Rule(emoji: "⚖️", terms: ["lawyer"]),
            Rule(emoji: "💼", terms: ["marketing consultant", "consultant"]),
            Rule(emoji: "🤝", terms: ["employment agency", "nonprofit", "association"]),
            Rule(emoji: "💐", terms: ["florist"]),
            Rule(emoji: "🍽️", terms: ["catering"]),
            Rule(emoji: "📦", terms: ["food delivery", "courier", "shipping", "storage"]),
            Rule(emoji: "👶", terms: ["child care"]),
            Rule(emoji: "⛺️", terms: ["summer camp"]),
            Rule(emoji: "🧺", terms: ["laundry"]),
            Rule(emoji: "🧵", terms: ["tailor"]),
            Rule(emoji: "🚚", terms: ["moving"]),
            Rule(emoji: "⚡️", terms: ["electrician"]),
            Rule(emoji: "🔧", terms: ["plumber"]),
            Rule(emoji: "🔑", terms: ["locksmith"]),
            Rule(emoji: "🖌️", terms: ["painter"]),
            Rule(emoji: "🔨", terms: ["roofing contractor", "general contractor"]),
            Rule(emoji: "🐾", terms: ["pet care", "pet boarding", "animal service"]),
            Rule(emoji: "🕊️", terms: ["funeral home", "cemetery"]),
            Rule(emoji: "♈️", terms: ["astrologer"]),
            Rule(emoji: "🔮", terms: ["psychic"]),
            Rule(emoji: "🧭", terms: ["tour agency", "travel agency", "tourist information"]),
            Rule(emoji: "🚘", terms: ["chauffeur"]),
            Rule(emoji: "✈️", terms: ["aircraft rental"]),
            Rule(emoji: "📡", terms: ["telecommunications"]),
            Rule(emoji: "💆", terms: ["skin care clinic"]),
            Rule(emoji: "🪞", terms: ["beauty service"]),
            Rule(emoji: "☀️", terms: ["tanning studio"]),
            Rule(emoji: "💇", terms: ["hair salon", "beauty salon"]),
            Rule(emoji: "💈", terms: ["barber"]),
            Rule(emoji: "💅", terms: ["nail salon", "manicure", "pedicure"]),
            Rule(emoji: "💄", terms: ["makeup artist"]),
            Rule(emoji: "🖋️", terms: ["tattoo piercing", "body art", "tattoo"])
        ],
        WanderPlaceCategory.travelTransit: [
            Rule(emoji: "🚁", terms: ["heliport"]),
            Rule(emoji: "✈️", terms: ["international airport", "airport", "airstrip"]),
            Rule(emoji: "🚇", terms: ["subway station"]),
            Rule(emoji: "🚋", terms: ["light rail", "tram stop"]),
            Rule(emoji: "🚆", terms: ["train station"]),
            Rule(emoji: "🚌", terms: ["bus stop", "bus station"]),
            Rule(emoji: "⛴️", terms: ["ferry terminal", "ferry service"]),
            Rule(emoji: "🚕", terms: ["taxi stand", "taxi service"]),
            Rule(emoji: "🚲", terms: ["bike share station"]),
            Rule(emoji: "🅿️", terms: ["parking garage", "parking lot", "park and ride", "parking"]),
            Rule(emoji: "⛽️", terms: ["gas station"]),
            Rule(emoji: "🔌", terms: ["ev charging", "e bike charging"]),
            Rule(emoji: "🚛", terms: ["truck stop", "truck dealer"]),
            Rule(emoji: "🛣️", terms: ["rest stop", "toll station"]),
            Rule(emoji: "🌉", terms: ["bridge"]),
            Rule(emoji: "🚙", terms: ["car dealer", "car rental"]),
            Rule(emoji: "🔧", terms: ["car repair"]),
            Rule(emoji: "🫧", terms: ["car wash"]),
            Rule(emoji: "🛞", terms: ["tire shop"]),
            Rule(emoji: "🚐", terms: ["transportation service"]),
            Rule(emoji: "🚮", terms: ["dump station"]),
            Rule(emoji: "🚰", terms: ["rv water refill"]),
            Rule(emoji: "🚉", terms: ["transit station", "transit stop", "transit depot"])
        ],
        WanderPlaceCategory.workEducation: [
            Rule(emoji: "🏢", terms: ["corporate office", "business center"]),
            Rule(emoji: "💼", terms: ["co working space", "coworking"]),
            Rule(emoji: "🏭", terms: ["manufacturer", "supplier"]),
            Rule(emoji: "🚜", terms: ["farm", "ranch"]),
            Rule(emoji: "📺", terms: ["television studio"]),
            Rule(emoji: "📚", terms: ["library"]),
            Rule(emoji: "🎓", terms: ["university", "academic department"]),
            Rule(emoji: "🧸", terms: ["preschool"]),
            Rule(emoji: "🏫", terms: [
                "primary school", "secondary school", "school", "educational institution"
            ]),
            Rule(emoji: "🔬", terms: ["research institute"])
        ],
        WanderPlaceCategory.civicFaith: [
            Rule(emoji: "📮", terms: ["post office"]),
            Rule(emoji: "👮", terms: ["neighborhood police station", "police"]),
            Rule(emoji: "🚒", terms: ["fire station"]),
            Rule(emoji: "⛪️", terms: ["church", "chapel", "cathedral"]),
            Rule(emoji: "🕌", terms: ["mosque"]),
            Rule(emoji: "🕍", terms: ["synagogue"]),
            Rule(emoji: "🛕", terms: ["hindu temple"]),
            Rule(emoji: "☸️", terms: ["buddhist temple"]),
            Rule(emoji: "⛩️", terms: ["shinto shrine", "shrine"]),
            Rule(emoji: "🙏", terms: ["place of worship"]),
            Rule(emoji: "🏳️", terms: ["embassy"]),
            Rule(emoji: "🏛️", terms: [
                "city hall", "local government office", "government office", "courthouse"
            ])
        ],
        WanderPlaceCategory.areasAddresses: [
            Rule(emoji: "🏢", terms: [
                "apartment building", "apartment complex", "condominium complex", "housing complex"
            ]),
            Rule(emoji: "🏙️", terms: ["neighborhood", "locality city", "town"]),
            Rule(emoji: "📮", terms: ["postal area"]),
            Rule(emoji: "🗺️", terms: ["region", "country"]),
            Rule(emoji: "🛣️", terms: ["route street"]),
            Rule(emoji: "🚦", terms: ["intersection"]),
            Rule(emoji: "🗿", terms: ["landmark"]),
            Rule(emoji: "#️⃣", terms: ["plus code"]),
            Rule(emoji: "📍", terms: ["address"])
        ],
        WanderPlaceCategory.facilitiesOther: [
            Rule(emoji: "🛁", terms: ["public bath"]),
            Rule(emoji: "🚻", terms: ["public bathroom", "restroom"]),
            Rule(emoji: "🐎", terms: ["stable"]),
            Rule(emoji: "📍", terms: ["generic establishment", "point of interest", "unknown"])
        ]
    ]

    private static let restaurantCuisineEmojis: [String: String] = Dictionary(
        uniqueKeysWithValues: [
            ("American", "🍔"),
            ("Mexican", "🌮"),
            ("Thai", "🇹🇭"),
            ("Vietnamese", "🍜"),
            ("Chinese", "🥟"),
            ("Korean", "🇰🇷"),
            ("Japanese", "🇯🇵"),
            ("Sushi", "🍣"),
            ("Indian", "🍛"),
            ("Italian", "🍝"),
            ("Mediterranean", "🫒"),
            ("Greek", "🇬🇷"),
            ("French", "🥐"),
            ("Spanish", "🥘"),
            ("Tex-Mex", "🌮"),
            ("Asian fusion", "🥢"),
            ("Cantonese", "🥟"),
            ("Taiwanese", "🧋"),
            ("Izakaya", "🍶"),
            ("Yakitori", "🍢"),
            ("Yakiniku", "🥩"),
            ("North Indian", "🍛"),
            ("South Indian", "🍛"),
            ("Pakistani", "🇵🇰"),
            ("Sri Lankan", "🇱🇰"),
            ("Bangladeshi", "🇧🇩"),
            ("Nepalese", "🇳🇵"),
            ("Malaysian", "🇲🇾"),
            ("Singaporean", "🇸🇬"),
            ("Indonesian", "🇮🇩"),
            ("Filipino", "🇵🇭"),
            ("Burmese", "🇲🇲"),
            ("Cambodian", "🇰🇭"),
            ("Laotian", "🇱🇦"),
            ("Asian", "🥢"),
            ("Tibetan", "🥟"),
            ("Mongolian", "🇲🇳"),
            ("Georgian", "🇬🇪"),
            ("Armenian", "🇦🇲"),
            ("Uzbek", "🇺🇿"),
            ("Mongolian BBQ", "🥩"),
            ("Korean BBQ", "🥩"),
            ("Japanese BBQ", "🥩"),
            ("Japanese curry", "🍛"),
            ("Tonkatsu", "🍛"),
            ("Afghan", "🇦🇫"),
            ("Middle Eastern", "🧆"),
            ("Lebanese", "🇱🇧"),
            ("Persian", "🇮🇷"),
            ("Turkish", "🇹🇷"),
            ("Israeli", "🇮🇱"),
            ("Palestinian", "🇵🇸"),
            ("Syrian", "🇸🇾"),
            ("Iraqi", "🇮🇶"),
            ("Jordanian", "🇯🇴"),
            ("Yemeni", "🇾🇪"),
            ("Egyptian", "🇪🇬"),
            ("Moroccan", "🇲🇦"),
            ("Tunisian", "🇹🇳"),
            ("Algerian", "🇩🇿"),
            ("Ethiopian", "🇪🇹"),
            ("Eritrean", "🇪🇷"),
            ("Somali", "🇸🇴"),
            ("Kenyan", "🇰🇪"),
            ("Nigerian", "🇳🇬"),
            ("Ghanaian", "🇬🇭"),
            ("Senegalese", "🇸🇳"),
            ("South African", "🇿🇦"),
            ("African", "🌍"),
            ("Tapas", "🥘"),
            ("Portuguese", "🇵🇹"),
            ("Basque", "🇪🇸"),
            ("German", "🇩🇪"),
            ("Austrian", "🇦🇹"),
            ("Bavarian", "🥨"),
            ("Swiss", "🇨🇭"),
            ("Dutch", "🇳🇱"),
            ("Belgian", "🇧🇪"),
            ("British", "🇬🇧"),
            ("Irish", "🇮🇪"),
            ("Scandinavian", "🐟"),
            ("Swedish", "🇸🇪"),
            ("Norwegian", "🇳🇴"),
            ("Finnish", "🇫🇮"),
            ("Danish", "🇩🇰"),
            ("Polish", "🇵🇱"),
            ("Ukrainian", "🇺🇦"),
            ("Russian", "🇷🇺"),
            ("Czech", "🇨🇿"),
            ("Slovak", "🇸🇰"),
            ("Hungarian", "🇭🇺"),
            ("Romanian", "🇷🇴"),
            ("Croatian", "🇭🇷"),
            ("Serbian", "🇷🇸"),
            ("Bosnian", "🇧🇦"),
            ("Bulgarian", "🇧🇬"),
            ("Albanian", "🇦🇱"),
            ("Slovenian", "🇸🇮"),
            ("Lithuanian", "🇱🇹"),
            ("European", "🇪🇺"),
            ("Eastern European", "🇪🇺"),
            ("Canadian", "🇨🇦"),
            ("Caribbean", "🏝️"),
            ("Jamaican", "🇯🇲"),
            ("Puerto Rican", "🇵🇷"),
            ("Dominican", "🇩🇴"),
            ("Haitian", "🇭🇹"),
            ("Panamanian", "🇵🇦"),
            ("Cuban", "🇨🇺"),
            ("Brazilian", "🇧🇷"),
            ("Argentinian", "🇦🇷"),
            ("Colombian", "🇨🇴"),
            ("Chilean", "🇨🇱"),
            ("Peruvian", "🇵🇪"),
            ("Venezuelan", "🇻🇪"),
            ("Ecuadorian", "🇪🇨"),
            ("Bolivian", "🇧🇴"),
            ("Uruguayan", "🇺🇾"),
            ("Salvadoran", "🇸🇻"),
            ("Guatemalan", "🇬🇹"),
            ("South American", "🌎"),
            ("Latin American", "🌎"),
            ("Southwestern", "🌶️"),
            ("Cajun", "🦐"),
            ("Californian", "🥑"),
            ("Hawaiian", "🍍"),
            ("Poke", "🥗"),
            ("Australian", "🇦🇺"),
            ("New Zealand", "🇳🇿"),
            ("Fijian", "🇫🇯"),
            ("Samoan", "🇼🇸"),
            ("Tongan", "🇹🇴")
        ].map { cuisine, emoji in
            (WanderPlaceCategory.normalizedCategoryText(cuisine), emoji)
        }
    )
}
