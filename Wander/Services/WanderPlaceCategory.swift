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

struct PlaceMemoryDefaultSuggestions: Equatable {
    let tagOptions: [String]
    let defaultTags: [String]
    let labelOptions: [String]
    let defaultLabels: [String]
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
        let subcategoryKey = WanderPlaceCategory.normalizedCategoryText(subcategory)
        let cuisineKey = WanderPlaceCategory.normalizedCategoryText(cuisine)
        let context = SuggestionContext(
            primaryCategory: primary,
            subcategory: subcategory,
            subcategoryKey: subcategoryKey,
            cuisine: cuisine,
            cuisineKey: cuisineKey,
            status: status,
            locality: locality
        )
        let base = baseDefaults(for: context)

        return PlaceMemoryDefaultSuggestions(
            tagOptions: merged(base.tagOptions, localTagOptions),
            defaultTags: base.defaultTags,
            labelOptions: merged(base.labelOptions, localLabelOptions),
            defaultLabels: base.defaultLabels
        )
    }

    static func tagOptions(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus,
        localOptions: [String] = []
    ) -> [String] {
        suggestions(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            cuisine: cuisine,
            status: status,
            localTagOptions: localOptions
        ).tagOptions
    }

    static func defaultTags(
        primaryCategory: String,
        subcategory: String? = nil,
        cuisine: String? = nil,
        status: PlaceStatus
    ) -> [String] {
        suggestions(
            primaryCategory: primaryCategory,
            subcategory: subcategory,
            cuisine: cuisine,
            status: status
        ).defaultTags
    }

    private struct Defaults {
        let tagOptions: [String]
        let selectedTags: [String]
        let wannaTagOptions: [String]?
        let selectedWannaTags: [String]?
        let labelOptions: [String]
        let selectedLabels: [String]
        let wannaLabelOptions: [String]?
        let selectedWannaLabels: [String]?

        init(
            tagOptions: [String],
            selectedTags: [String],
            wannaTagOptions: [String]? = nil,
            selectedWannaTags: [String]? = nil,
            labelOptions: [String],
            selectedLabels: [String],
            wannaLabelOptions: [String]? = nil,
            selectedWannaLabels: [String]? = nil
        ) {
            self.tagOptions = tagOptions
            self.selectedTags = selectedTags
            self.wannaTagOptions = wannaTagOptions
            self.selectedWannaTags = selectedWannaTags
            self.labelOptions = labelOptions
            self.selectedLabels = selectedLabels
            self.wannaLabelOptions = wannaLabelOptions
            self.selectedWannaLabels = selectedWannaLabels
        }

        func resolved(status: PlaceStatus) -> (tagOptions: [String], defaultTags: [String], labelOptions: [String], defaultLabels: [String]) {
            if status == .wannaGo {
                return (
                    wannaTagOptions ?? tagOptions,
                    selectedWannaTags ?? Array(selectedTags.prefix(1)),
                    wannaLabelOptions ?? labelOptions,
                    selectedWannaLabels ?? []
                )
            }

            return (tagOptions, selectedTags, labelOptions, selectedLabels)
        }
    }

    private struct SuggestionContext {
        let primaryCategory: String
        let subcategory: String?
        let subcategoryKey: String
        let cuisine: String?
        let cuisineKey: String
        let status: PlaceStatus
        let locality: String?
    }

    private static func baseDefaults(for context: SuggestionContext) -> PlaceMemoryDefaultSuggestions {
        let defaults = specificDefaults(for: context) ?? primaryDefaults(for: context.primaryCategory)
        let resolved = defaults.resolved(status: context.status)
        let localFavorite = favoriteLabel(for: context.locality)
        let locationLabels = context.status == .wannaGo
            ? [plannedLabel(for: context.locality), "shortlist"]
            : [localFavorite]
        let labelOptions = merged(locationLabels, resolved.labelOptions)
        let defaultLabels = merged(resolved.defaultLabels, locationLabels).prefix(1)

        return PlaceMemoryDefaultSuggestions(
            tagOptions: unique(resolved.tagOptions),
            defaultTags: unique(resolved.defaultTags).filter { resolved.tagOptions.containsCaseInsensitive($0) },
            labelOptions: labelOptions,
            defaultLabels: Array(defaultLabels).filter { labelOptions.containsCaseInsensitive($0) }
        )
    }

    private static func specificDefaults(for context: SuggestionContext) -> Defaults? {
        let key = context.subcategoryKey
        let cuisineKey = context.cuisineKey

        if context.primaryCategory == WanderPlaceCategory.restaurantsFood {
            if containsAny(key, ["fast food", "food court", "takeout", "cafeteria", "taco stand", "taco truck", "burrito", "taco", "falafel", "gyro", "kebab", "shawarma", "snack bar"]) {
                return Defaults(
                    tagOptions: cuisineAware(["quick bite", "low lift", "counter order", "reliable", "good value"], cuisine: context.cuisine),
                    selectedTags: ["quick bite", "good value"],
                    wannaTagOptions: cuisineAware(["quick bite", "nearby", "good value", "easy stop", "recommended"], cuisine: context.cuisine),
                    selectedWannaTags: ["quick bite"],
                    labelOptions: ["lunch rotation", "easy dinner", "road stop", "solo bite", "neighborhood standby"],
                    selectedLabels: ["lunch rotation"],
                    wannaLabelOptions: ["try soon", "quick list", "nearby option", "solo shortlist", "backup plan"],
                    selectedWannaLabels: ["try soon"]
                )
            }

            if containsAny(key, ["fine dining", "steakhouse", "oyster bar", "seafood", "fondue"]) {
                return Defaults(
                    tagOptions: cuisineAware(["special occasion", "date night", "worth planning", "great service", "reservations"], cuisine: context.cuisine),
                    selectedTags: ["special occasion", "worth planning"],
                    wannaTagOptions: cuisineAware(["date night", "book ahead", "special occasion", "recommended", "splurge"], cuisine: context.cuisine),
                    selectedWannaTags: ["date night"],
                    labelOptions: ["celebration list", "birthday list", "date night", "client friendly", "splurge-worthy"],
                    selectedLabels: ["celebration list"],
                    wannaLabelOptions: ["reservation list", "date shortlist", "birthday idea", "client shortlist", "splurge list"],
                    selectedWannaLabels: ["reservation list"]
                )
            }

            if containsAny(key, ["breakfast", "brunch", "bagel", "sandwich", "deli", "bakery"]) {
                return Defaults(
                    tagOptions: cuisineAware(["morning stop", "casual", "good coffee", "quick bite", "weekend"], cuisine: context.cuisine),
                    selectedTags: ["morning stop", "quick bite"],
                    wannaTagOptions: cuisineAware(["breakfast idea", "weekend maybe", "nearby", "recommended", "easy"], cuisine: context.cuisine),
                    selectedWannaTags: ["breakfast idea"],
                    labelOptions: ["breakfast rotation", "weekend morning", "workday lunch", "bring visitors", "neighborhood staple"],
                    selectedLabels: ["breakfast rotation"],
                    wannaLabelOptions: ["breakfast shortlist", "weekend list", "nearby morning", "visitor idea", "try soon"],
                    selectedWannaLabels: ["breakfast shortlist"]
                )
            }

            if containsAny(key, ["pizza", "burgers", "hot dogs", "barbecue", "chicken", "wings"]) {
                return Defaults(
                    tagOptions: cuisineAware(["comfort food", "group order", "casual", "craveable", "good value"], cuisine: context.cuisine),
                    selectedTags: ["comfort food", "craveable"],
                    wannaTagOptions: cuisineAware(["comfort food", "group maybe", "recommended", "easy dinner", "good value"], cuisine: context.cuisine),
                    selectedWannaTags: ["comfort food"],
                    labelOptions: ["comfort rotation", "group dinner", "casual night", "takeout list", "neighborhood standby"],
                    selectedLabels: ["comfort rotation"],
                    wannaLabelOptions: ["comfort shortlist", "group idea", "takeout shortlist", "try soon", "casual list"],
                    selectedWannaLabels: ["comfort shortlist"]
                )
            }

            if containsAny(key, ["ramen", "noodles", "dumplings", "dim sum", "hot pot"]) || !cuisineKey.isEmpty {
                let cuisineTag = context.cuisine.map { "\($0) craving" } ?? "craveable"
                return Defaults(
                    tagOptions: unique([cuisineTag, "comfort food", "worth a detour", "casual", "group-friendly"]),
                    selectedTags: unique([cuisineTag, "worth a detour"]),
                    wannaTagOptions: unique([cuisineTag, "recommended", "group maybe", "worth a detour", "try soon"]),
                    selectedWannaTags: [cuisineTag],
                    labelOptions: cuisineAware(["craving list", "dinner rotation", "bring friends", "neighborhood staple", "date night"], cuisine: context.cuisine),
                    selectedLabels: ["craving list"],
                    wannaLabelOptions: cuisineAware(["cuisine shortlist", "dinner shortlist", "friend rec", "try soon", "date idea"], cuisine: context.cuisine),
                    selectedWannaLabels: ["cuisine shortlist"]
                )
            }

            return nil
        }

        switch context.primaryCategory {
        case WanderPlaceCategory.coffeeTeaSweets:
            if containsAny(key, ["coffee", "cafe", "roastery", "tea"]) {
                return Defaults(
                    tagOptions: ["work-friendly", "quiet", "good coffee", "cozy", "outlets"],
                    selectedTags: ["work-friendly", "quiet"],
                    wannaTagOptions: ["work maybe", "cute", "good coffee", "nearby", "recommended"],
                    selectedWannaTags: ["work maybe"],
                    labelOptions: ["work rotation", "morning loop", "meeting spot", "neighborhood staple", "solo reset"],
                    selectedLabels: ["work rotation"],
                    wannaLabelOptions: ["coffee shortlist", "work maybe", "morning list", "try soon", "meeting idea"],
                    selectedWannaLabels: ["coffee shortlist"]
                )
            }

            if containsAny(key, ["bakery", "bagel", "donut", "cake", "pastry", "dessert", "ice cream", "candy", "chocolate", "confectionery", "acai", "smoothie", "juice"]) {
                return Defaults(
                    tagOptions: ["sweet treat", "bring home", "cute", "shareable", "worth a detour"],
                    selectedTags: ["sweet treat", "shareable"],
                    wannaTagOptions: ["sweet treat", "bring home", "recommended", "cute", "try soon"],
                    selectedWannaTags: ["sweet treat"],
                    labelOptions: ["dessert list", "treat stop", "bring visitors", "giftable", "weekend sweet"],
                    selectedLabels: ["dessert list"],
                    wannaLabelOptions: ["dessert shortlist", "treat list", "visitor idea", "gift idea", "try soon"],
                    selectedWannaLabels: ["dessert shortlist"]
                )
            }

        case WanderPlaceCategory.barsNightlife:
            if containsAny(key, ["cocktail", "wine", "lounge", "jazz", "hi fi"]) {
                return Defaults(
                    tagOptions: ["date drinks", "good music", "low light", "not too loud", "special night"],
                    selectedTags: ["date drinks", "not too loud"],
                    wannaTagOptions: ["date idea", "good music", "book ahead", "recommended", "late night"],
                    selectedWannaTags: ["date idea"],
                    labelOptions: ["date drinks", "night out", "client friendly", "birthday drinks", "after dinner"],
                    selectedLabels: ["date drinks"],
                    wannaLabelOptions: ["drinks shortlist", "date shortlist", "night-out list", "birthday idea", "after-dinner list"],
                    selectedWannaLabels: ["drinks shortlist"]
                )
            }

            if containsAny(key, ["brewery", "brewpub", "beer garden", "pub", "irish pub", "sports bar", "billiards", "bar and grill"]) {
                return Defaults(
                    tagOptions: ["group-friendly", "casual drinks", "patio", "games", "walk-in"],
                    selectedTags: ["group-friendly", "walk-in"],
                    wannaTagOptions: ["group maybe", "casual drinks", "patio", "recommended", "easy night"],
                    selectedWannaTags: ["group maybe"],
                    labelOptions: ["group drinks", "game night", "casual night", "neighborhood standby", "bring friends"],
                    selectedLabels: ["group drinks"],
                    wannaLabelOptions: ["group shortlist", "game-day list", "casual drinks", "friend rec", "try soon"],
                    selectedWannaLabels: ["group shortlist"]
                )
            }

            if containsAny(key, ["club", "disco", "nightclub", "karaoke", "live music", "comedy", "casino", "dance hall"]) {
                return Defaults(
                    tagOptions: ["late night", "high energy", "group-friendly", "tickets", "celebration"],
                    selectedTags: ["late night", "group-friendly"],
                    wannaTagOptions: ["late night", "group maybe", "tickets", "recommended", "special night"],
                    selectedWannaTags: ["late night"],
                    labelOptions: ["night out", "birthday list", "bring friends", "live night", "weekend plan"],
                    selectedLabels: ["night out"],
                    wannaLabelOptions: ["night-out shortlist", "birthday idea", "ticket list", "weekend list", "group plan"],
                    selectedWannaLabels: ["night-out shortlist"]
                )
            }

        case WanderPlaceCategory.outdoorsNature:
            if containsAny(key, ["hike", "trail", "hiking", "mountain", "viewpoint", "overlook", "waterfall", "cave", "scenic", "nature preserve", "wildlife"]) {
                return Defaults(
                    tagOptions: ["views", "sunset", "good walk", "bring water", "weekend"],
                    selectedTags: ["views", "weekend"],
                    wannaTagOptions: ["views", "sunset", "weekend maybe", "dog friendly", "recommended"],
                    selectedWannaTags: ["views"],
                    labelOptions: ["weekend list", "reset spot", "bring visitors", "sunset list", "nature day"],
                    selectedLabels: ["weekend list"],
                    wannaLabelOptions: ["outdoor shortlist", "weekend plan", "sunset idea", "visitor idea", "reset list"],
                    selectedWannaLabels: ["outdoor shortlist"]
                )
            }

            if containsAny(key, ["beach", "lake", "river", "hot spring", "marina", "fishing"]) {
                return Defaults(
                    tagOptions: ["water day", "sunset", "low effort", "bring friends", "scenic"],
                    selectedTags: ["water day", "scenic"],
                    wannaTagOptions: ["water day", "sunset", "bring friends", "recommended", "weekend maybe"],
                    selectedWannaTags: ["water day"],
                    labelOptions: ["water day", "summer list", "bring visitors", "weekend reset", "photo spot"],
                    selectedLabels: ["water day"],
                    wannaLabelOptions: ["water shortlist", "summer list", "visitor idea", "weekend plan", "photo idea"],
                    selectedWannaLabels: ["water shortlist"]
                )
            }

            if containsAny(key, ["campground", "rv", "camping", "cabin", "cottage", "ski", "cycling", "skate", "off roading", "adventure"]) {
                return Defaults(
                    tagOptions: ["overnight", "gear needed", "group-friendly", "weekend", "worth planning"],
                    selectedTags: ["weekend", "worth planning"],
                    wannaTagOptions: ["book ahead", "gear needed", "group maybe", "weekend", "recommended"],
                    selectedWannaTags: ["book ahead"],
                    labelOptions: ["weekend trip", "camping list", "adventure list", "group trip", "seasonal"],
                    selectedLabels: ["weekend trip"],
                    wannaLabelOptions: ["trip shortlist", "camping shortlist", "gear list", "group idea", "seasonal list"],
                    selectedWannaLabels: ["trip shortlist"]
                )
            }

        case WanderPlaceCategory.shopping:
            if containsAny(key, ["grocery", "supermarket", "market", "butcher", "health food", "liquor", "food store", "farmers", "asian grocery"]) {
                return Defaults(
                    tagOptions: ["weekly errand", "good selection", "fresh", "quick stop", "specialty find"],
                    selectedTags: ["good selection", "quick stop"],
                    wannaTagOptions: ["errand idea", "specialty find", "nearby", "recommended", "stock up"],
                    selectedWannaTags: ["specialty find"],
                    labelOptions: ["grocery rotation", "errand loop", "specialty run", "pantry stop", "neighborhood staple"],
                    selectedLabels: ["grocery rotation"],
                    wannaLabelOptions: ["errand shortlist", "specialty list", "pantry list", "nearby option", "try soon"],
                    selectedWannaLabels: ["errand shortlist"]
                )
            }

            if containsAny(key, ["book", "art", "craft", "gift", "toy", "jewelry", "cosmetic", "beauty", "thrift"]) {
                return Defaults(
                    tagOptions: ["giftable", "browse-worthy", "specialty find", "cute", "local shop"],
                    selectedTags: ["browse-worthy", "specialty find"],
                    wannaTagOptions: ["gift idea", "browse later", "specialty find", "recommended", "local shop"],
                    selectedWannaTags: ["browse later"],
                    labelOptions: ["gift list", "browse day", "local shop", "creative supplies", "visitor stop"],
                    selectedLabels: ["gift list"],
                    wannaLabelOptions: ["shopping shortlist", "gift idea", "creative list", "browse later", "visitor idea"],
                    selectedWannaLabels: ["shopping shortlist"]
                )
            }

        default:
            break
        }

        return nil
    }

    private static func primaryDefaults(for primaryCategory: String) -> Defaults {
        switch primaryCategory {
        case WanderPlaceCategory.restaurantsFood:
            return Defaults(
                tagOptions: ["cozy", "worth it", "good table", "share plates", "great service"],
                selectedTags: ["cozy", "worth it"],
                wannaTagOptions: ["looks cozy", "recommended", "good table", "date idea", "share plates"],
                selectedWannaTags: ["recommended"],
                labelOptions: ["dinner rotation", "date night", "bring friends", "client friendly", "neighborhood staple"],
                selectedLabels: ["dinner rotation"],
                wannaLabelOptions: ["food shortlist", "date shortlist", "friend rec", "try soon", "group idea"],
                selectedWannaLabels: ["food shortlist"]
            )
        case WanderPlaceCategory.coffeeTeaSweets:
            return Defaults(
                tagOptions: ["cozy", "quick stop", "sweet treat", "good coffee", "cute"],
                selectedTags: ["cozy", "quick stop"],
                wannaTagOptions: ["cute", "recommended", "nearby", "work maybe", "sweet treat"],
                selectedWannaTags: ["recommended"],
                labelOptions: ["morning loop", "treat stop", "work rotation", "meeting spot", "neighborhood staple"],
                selectedLabels: ["morning loop"],
                wannaLabelOptions: ["coffee shortlist", "treat list", "work maybe", "try soon", "nearby option"],
                selectedWannaLabels: ["coffee shortlist"]
            )
        case WanderPlaceCategory.barsNightlife:
            return Defaults(
                tagOptions: ["good music", "not too loud", "group-friendly", "walk-in", "late night"],
                selectedTags: ["good music", "not too loud"],
                wannaTagOptions: ["date idea", "recommended", "good music", "group maybe", "late night"],
                selectedWannaTags: ["date idea"],
                labelOptions: ["night out", "date drinks", "group drinks", "birthday list", "after dinner"],
                selectedLabels: ["night out"],
                wannaLabelOptions: ["drinks shortlist", "night-out list", "date shortlist", "birthday idea", "try soon"],
                selectedWannaLabels: ["drinks shortlist"]
            )
        case WanderPlaceCategory.outdoorsNature:
            return Defaults(
                tagOptions: ["views", "low effort", "reset spot", "dog friendly", "bring visitors"],
                selectedTags: ["views", "reset spot"],
                wannaTagOptions: ["views", "weekend maybe", "dog friendly", "recommended", "bring visitors"],
                selectedWannaTags: ["views"],
                labelOptions: ["weekend list", "reset spot", "bring visitors", "sunset list", "nature day"],
                selectedLabels: ["weekend list"],
                wannaLabelOptions: ["outdoor shortlist", "weekend plan", "visitor idea", "reset list", "sunset idea"],
                selectedWannaLabels: ["outdoor shortlist"]
            )
        case WanderPlaceCategory.thingsToDo:
            return Defaults(
                tagOptions: ["bring visitors", "rainy day", "date idea", "kid-friendly", "tickets"],
                selectedTags: ["bring visitors", "rainy day"],
                wannaTagOptions: ["bring visitors", "tickets", "date idea", "recommended", "rainy day"],
                selectedWannaTags: ["bring visitors"],
                labelOptions: ["visitor list", "weekend plan", "culture day", "date idea", "rainy day"],
                selectedLabels: ["visitor list"],
                wannaLabelOptions: ["things-to-do shortlist", "visitor idea", "ticket list", "weekend plan", "date shortlist"],
                selectedWannaLabels: ["things-to-do shortlist"]
            )
        case WanderPlaceCategory.shopping:
            return Defaults(
                tagOptions: ["browse-worthy", "good selection", "giftable", "local shop", "quick errand"],
                selectedTags: ["browse-worthy", "good selection"],
                wannaTagOptions: ["browse later", "gift idea", "recommended", "specialty find", "quick errand"],
                selectedWannaTags: ["browse later"],
                labelOptions: ["errand loop", "gift list", "local shop", "specialty run", "browse day"],
                selectedLabels: ["errand loop"],
                wannaLabelOptions: ["shopping shortlist", "gift idea", "errand idea", "browse later", "specialty list"],
                selectedWannaLabels: ["shopping shortlist"]
            )
        case WanderPlaceCategory.wellnessFitness:
            return Defaults(
                tagOptions: ["routine", "recovery", "easy booking", "clean", "worth returning"],
                selectedTags: ["routine", "worth returning"],
                wannaTagOptions: ["try soon", "easy booking", "recommended", "routine", "recovery"],
                selectedWannaTags: ["try soon"],
                labelOptions: ["health routine", "recovery list", "fitness rotation", "self-care", "trusted care"],
                selectedLabels: ["health routine"],
                wannaLabelOptions: ["wellness shortlist", "fitness idea", "self-care list", "care option", "try soon"],
                selectedWannaLabels: ["wellness shortlist"]
            )
        case WanderPlaceCategory.stays:
            return Defaults(
                tagOptions: ["good location", "quiet", "book again", "family-friendly", "worth the rate"],
                selectedTags: ["good location", "book again"],
                wannaTagOptions: ["book ahead", "good location", "recommended", "trip idea", "family-friendly"],
                selectedWannaTags: ["book ahead"],
                labelOptions: ["stay again", "trip base", "family stay", "weekend away", "work trip"],
                selectedLabels: ["stay again"],
                wannaLabelOptions: ["stay shortlist", "trip idea", "book later", "family option", "work trip"],
                selectedWannaLabels: ["stay shortlist"]
            )
        case WanderPlaceCategory.servicesErrands:
            return Defaults(
                tagOptions: ["reliable", "fast", "fair price", "easy booking", "recommended"],
                selectedTags: ["reliable", "easy booking"],
                wannaTagOptions: ["recommended", "nearby", "easy booking", "fair price", "try soon"],
                selectedWannaTags: ["recommended"],
                labelOptions: ["trusted service", "errand loop", "home help", "life admin", "backup option"],
                selectedLabels: ["trusted service"],
                wannaLabelOptions: ["service shortlist", "errand idea", "backup option", "home help", "try soon"],
                selectedWannaLabels: ["service shortlist"]
            )
        case WanderPlaceCategory.travelTransit:
            return Defaults(
                tagOptions: ["easy access", "reliable", "good parking", "fast stop", "useful"],
                selectedTags: ["easy access", "useful"],
                wannaTagOptions: ["trip planning", "easy access", "useful", "recommended", "near route"],
                selectedWannaTags: ["trip planning"],
                labelOptions: ["travel utility", "route stop", "parking note", "airport plan", "road trip"],
                selectedLabels: ["travel utility"],
                wannaLabelOptions: ["travel shortlist", "route idea", "parking option", "trip planning", "road trip"],
                selectedWannaLabels: ["travel shortlist"]
            )
        case WanderPlaceCategory.workEducation:
            return Defaults(
                tagOptions: ["quiet", "productive", "good wifi", "meeting-friendly", "useful"],
                selectedTags: ["productive", "useful"],
                wannaTagOptions: ["work maybe", "learn more", "good wifi", "recommended", "quiet"],
                selectedWannaTags: ["work maybe"],
                labelOptions: ["work rotation", "learning list", "meeting spot", "research note", "quiet place"],
                selectedLabels: ["work rotation"],
                wannaLabelOptions: ["work shortlist", "learning idea", "meeting option", "research list", "try soon"],
                selectedWannaLabels: ["work shortlist"]
            )
        case WanderPlaceCategory.civicFaith:
            return Defaults(
                tagOptions: ["important", "community", "quiet", "service info", "bring visitors"],
                selectedTags: ["important", "community"],
                wannaTagOptions: ["service info", "community", "bring visitors", "recommended", "quiet"],
                selectedWannaTags: ["service info"],
                labelOptions: ["community", "civic errand", "faith", "visitor context", "important place"],
                selectedLabels: ["community"],
                wannaLabelOptions: ["civic shortlist", "faith list", "visitor idea", "service info", "community"],
                selectedWannaLabels: ["civic shortlist"]
            )
        case WanderPlaceCategory.areasAddresses:
            return Defaults(
                tagOptions: ["home base", "favorite area", "meet here", "remember address", "useful"],
                selectedTags: ["useful", "remember address"],
                wannaTagOptions: ["area to explore", "meet here", "remember address", "trip planning", "useful"],
                selectedWannaTags: ["area to explore"],
                labelOptions: ["area note", "address book", "meetup spot", "neighborhood", "trip area"],
                selectedLabels: ["area note"],
                wannaLabelOptions: ["area shortlist", "address note", "explore later", "trip planning", "meetup idea"],
                selectedWannaLabels: ["area shortlist"]
            )
        case WanderPlaceCategory.facilitiesOther:
            return Defaults(
                tagOptions: ["useful", "quick stop", "hard to find", "clean", "backup option"],
                selectedTags: ["useful", "quick stop"],
                wannaTagOptions: ["useful", "near route", "backup option", "hard to find", "remember"],
                selectedWannaTags: ["useful"],
                labelOptions: ["useful facility", "route note", "backup option", "remember this", "practical"],
                selectedLabels: ["useful facility"],
                wannaLabelOptions: ["facility shortlist", "route note", "backup option", "remember this", "practical"],
                selectedWannaLabels: ["facility shortlist"]
            )
        default:
            return Defaults(
                tagOptions: ["worth it", "useful", "bring friends", "easy", "remember this"],
                selectedTags: ["worth it"],
                wannaTagOptions: ["recommended", "useful", "try soon", "bring friends", "remember this"],
                selectedWannaTags: ["recommended"],
                labelOptions: ["Joe rec", "weekend list", "bring visitors", "go-to", "remember this"],
                selectedLabels: ["remember this"],
                wannaLabelOptions: ["shortlist", "try soon", "Joe rec", "weekend list", "remember this"],
                selectedWannaLabels: ["shortlist"]
            )
        }
    }

    private static func cuisineAware(_ values: [String], cuisine: String?) -> [String] {
        guard let cuisine, !cuisine.isEmpty else { return values }
        return unique(["\(cuisine) craving"] + values)
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

    private static func plannedLabel(for locality: String?) -> String {
        let favorite = favoriteLabel(for: locality)
        if favorite == "local favorite" {
            return "local shortlist"
        }
        return favorite.replacingOccurrences(of: "favorite", with: "shortlist")
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { needle in
            value.contains(WanderPlaceCategory.normalizedCategoryText(needle))
        }
    }

    private static func merged(_ values: [String]...) -> [String] {
        unique(values.flatMap { $0 })
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = WanderPlaceCategory.normalizedCategoryText(trimmed)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }

        return result
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
            emoji: "🍽️",
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
            emoji: "☕️",
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
            emoji: "🍸",
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
            emoji: "🌲",
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
            "Dance hall", "Barbecue area"
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
            "Pet store", "Auto parts", "Thrift store", "Discount supermarket", "Cosmetics"
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
            "dermatologist", "pediatrician", "podiatrist"
        ],
            subcategories: [
            "Gym", "Fitness center", "Yoga studio", "Wellness studio", "Wellness center", "Sports club",
            "Sports complex", "Sports coaching", "Sports school", "Athletic field", "Swimming pool",
            "Tennis court", "Golf course", "Indoor golf", "Ice skating rink", "Volleyball court", "Soccer field",
            "Basketball court", "Pickleball court", "Spa", "Massage", "Massage spa", "Sauna", "Chiropractor",
            "Dentist", "Dental clinic", "Optometrist", "Ophthalmologist", "Eye care center", "Doctor",
            "Dermatologist", "Pediatrician", "Urgent care", "Medical clinic", "Medical center", "Hospital",
            "Medical lab", "Pharmacy", "Drugstore", "Physiotherapist", "Physical therapy", "Foot care",
            "Podiatrist", "Veterinary care", "Mental health/therapy", "Retreat"
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

    static let restaurantCuisineOptions: [String] = {
        restaurantCuisineGroups().flatMap(\.subcategories)
    }()

    private static let normalizedRestaurantCuisineOptions: [(name: String, normalized: String)] = {
        restaurantCuisineOptions
            .map { cuisine in
                (name: cuisine, normalized: normalizedCategoryText(cuisine))
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

        return normalizedRestaurantCuisineOptions.first { cuisine in
            normalized == cuisine.normalized
                || normalized.contains(cuisine.normalized)
                || withoutCuisineSuffix == cuisine.normalized
        }?.name
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

        if containsAny(normalizedName, ["nail salon", "nails", "manicure", "pedicure", "hair salon", "barbershop", "barber shop", "tattoo"]) {
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
