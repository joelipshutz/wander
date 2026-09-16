import Foundation

/// An optional, firsthand answer about one visit. Merely presenting a question
/// never supplies an answer; callers persist only explicit selections.
struct PlaceCheckInQuestion: Identifiable, Equatable, Sendable {
    let id: String
    let displayLabel: String
    let prompt: String
    let options: [String]
    private let searchableAnswers: [String: [String]]

    var valueType: String { "single_choice" }

    init(
        id: String,
        displayLabel: String,
        prompt: String,
        options: [String],
        searchableAnswers: [String: [String]] = [:]
    ) {
        self.id = id
        self.displayLabel = displayLabel
        self.prompt = prompt
        self.options = options
        self.searchableAnswers = searchableAnswers
    }

    /// Search gets only deliberately supported positive/qualified evidence.
    /// Unknown values and negative observations must not match an amenity.
    func searchTerms(for answer: String) -> [String] {
        guard options.contains(answer) else { return [] }
        return searchableAnswers[answer] ?? []
    }
}

struct PlaceCheckInQuestionProfile: Equatable, Sendable {
    let categoryID: String
    let subcategories: [String]
    let questionIDs: [String]
}

enum PlaceCheckInQuestionCatalog {
    static let keyPrefix = "place_detail_"
    static let allQuestions = coreQuestions + everydayQuestions
    static let profiles = coreProfiles + everydayProfiles

    /// Historical answers keep their original definitions and option values.
    /// Retired trivia is excluded from new selections, never rewritten into a
    /// different fact (for example apparatus used is not a reformer-class answer).
    static let retiredQuestionIDs: Set<String> = [
        "place_detail_bread",
        "place_detail_rice",
        "place_detail_small_plates",
        "place_detail_dessert",
        "place_detail_menu_guidance",
        "place_detail_fresh_herbs",
        "place_detail_broth",
        "place_detail_noodles",
        "place_detail_dumplings",
        "place_detail_bao",
        "place_detail_dim_sum",
        "place_detail_hotpot",
        "place_detail_roast_meats",
        "place_detail_skewers",
        "place_detail_sushi_menu",
        "place_detail_curry",
        "place_detail_crispy_takeaway",
        "place_detail_flatbread",
        "place_detail_dips",
        "place_detail_coffee_after",
        "place_detail_stew",
        "place_detail_shared_platter",
        "place_detail_grilled",
        "place_detail_pastry",
        "place_detail_seafood",
        "place_detail_pasta",
        "place_detail_tapas",
        "place_detail_fondue",
        "place_detail_tacos",
        "place_detail_salsa",
        "place_detail_sandwich",
        "place_detail_burger",
        "place_detail_barbecue",
        "place_detail_wings",
        "place_detail_steak",
        "place_detail_bowl",
        "place_detail_soup",
        "place_detail_oysters",
        "place_detail_tea",
        "place_detail_tea_shop",
        "place_detail_smoothie",
        "place_detail_toppings",
        "place_detail_cake",
        "place_detail_karaoke_charge",
        "place_detail_garden_labels",
        "place_detail_fishing_pier_setup",
        "place_detail_class_size",
        "place_detail_pilates_format",
        "place_detail_pilates_intro",
        "place_detail_everyday_browsing",
        "place_detail_everyday_barrier",
    ]
    static let availableQuestions = allQuestions.filter { !retiredQuestionIDs.contains($0.id) }


    /// Category fallbacks are used only for a user-written/unknown subtype.
    /// Known selectable subtypes must have an explicit profile above.
    static let defaultQuestionIDs: [String: [String]] = [
        "restaurants_food": ["dog_access", "outdoor_seating", "booking_policy"],
        "coffee_tea_sweets": ["laptop", "outlets", "dog_access"],
        "bars_nightlife": ["noise", "alcohol_free", "outdoor_seating"],
        "outdoors_nature": ["leash", "shade", "restroom"],
        "things_to_do": ["admission", "visit_time", "step_free"],
        "shopping": ["dog_access", "everyday_staff_help", "everyday_payment"],
        "wellness_fitness": ["step_free", "waiting", "restroom"],
        "stays": ["everyday_room_noise", "everyday_luggage", "everyday_room_cooling"],
        "services_errands": ["everyday_appointment", "waiting", "everyday_prices"],
        "travel_transit": ["everyday_wayfinding", "seating", "restroom"],
        "work_education": ["wifi", "outlets", "noise"],
        "civic_faith": ["everyday_visitor_access", "step_free", "everyday_visitor_guidance"],
        "areas_addresses": ["everyday_getting_around", "everyday_rest_seats", "everyday_wayfinding"],
        "facilities_other": ["step_free", "seating", "restroom"],
        "place": ["step_free", "seating", "restroom"]
    ]

    static func isDetailQuestion(_ key: String) -> Bool {
        key.hasPrefix(keyPrefix)
    }

    static func question(id: String) -> PlaceCheckInQuestion? {
        questionsByID[id]
    }

    /// Food type can correct a culinary label (Ramen to Thai), while a venue
    /// format such as a truck or food court still determines useful questions.
    /// This affects question/preference context only, never saved categorization.
    static func questionSubtype(categoryID: String, subcategory: String?, cuisine: String?) -> String? {
        let category = WanderPlaceCategory.normalizedPrimaryCategory(categoryID)
        let subtype = WanderPlaceCategory.canonicalSubcategory(subcategory, primaryCategory: category)
        guard category == WanderPlaceCategory.restaurantsFood else { return subtype }

        let selectedFoodType = WanderPlaceCategory.canonicalSubcategory(cuisine, primaryCategory: category)
        // An explicit format selected in Food type can replace a provider format.
        if let selectedFormat = diningVenueFormats[WanderPlaceCategory.normalizedCategoryText(selectedFoodType)] {
            return selectedFormat
        }
        if let venueFormat = diningVenueFormats[WanderPlaceCategory.normalizedCategoryText(subtype)] {
            return venueFormat
        }
        return selectedFoodType ?? subtype
    }

    /// Exact formats only: culinary labels such as Ramen, Sushi and Thai are
    /// deliberately absent. Legacy/custom formats keep their own scope and use
    /// the normal category fallback when no curated profile exists.
    private static let diningVenueFormats: [String: String] = Dictionary(uniqueKeysWithValues: [
        "Taco stand", "Taco truck", "Food court", "Diner", "Deli", "Bistro",
        "Steakhouse", "Bar & grill", "Oyster bar", "Snack bar", "Gastropub",
        "Food truck", "Food stand", "Buffet", "Cafeteria", "Fast food", "Takeout",
        "Fine dining", "Casual/family"
    ].map { (WanderPlaceCategory.normalizedCategoryText($0), $0) })

    static func questions(categoryID: String, subcategory: String?) -> [PlaceCheckInQuestion] {
        if let curated = curatedQuestions(categoryID: categoryID, subcategory: subcategory) {
            return curated
        }
        let category = WanderPlaceCategory.normalizedPrimaryCategory(categoryID)
        return resolved(defaultQuestionIDs[category] ?? defaultQuestionIDs["place"] ?? [])
    }

    /// Unlike `questions`, this exposes missing curation rather than hiding it
    /// behind a fallback. Coverage tests enumerate the actual selectable types.
    static func curatedQuestions(categoryID: String, subcategory: String?) -> [PlaceCheckInQuestion]? {
        let key = preferenceKey(categoryID: categoryID, subcategory: subcategory)
        guard let ids = questionIDsBySubtype[key] else { return nil }
        return resolved(ids)
    }

    static func preferenceKey(categoryID: String, subcategory: String?) -> String {
        let category = WanderPlaceCategory.normalizedPrimaryCategory(categoryID)
        let subtype = subtypeDisplayTitle(categoryID: category, subcategory: subcategory)
        return category + ":" + WanderPlaceCategory.normalizedCategoryText(subtype)
    }

    static func subtypeDisplayTitle(categoryID: String, subcategory: String?) -> String {
        let category = WanderPlaceCategory.normalizedPrimaryCategory(categoryID)
        return WanderPlaceCategory.canonicalSubcategory(subcategory, primaryCategory: category)
            ?? WanderPlaceCategory.defaultSubcategory(for: category)
            ?? "Place"
    }

    private static let questionsByID = Dictionary(
        uniqueKeysWithValues: allQuestions.map { ($0.id, $0) }
    )

    private static let questionIDsBySubtype: [String: [String]] = {
        var result: [String: [String]] = [:]
        for profile in profiles {
            for subtype in profile.subcategories {
                result[preferenceKey(categoryID: profile.categoryID, subcategory: subtype)] = profile.questionIDs
            }
        }
        return result
    }()

    private static func resolved(_ ids: [String]) -> [PlaceCheckInQuestion] {
        ids.compactMap { questionsByID[keyPrefix + $0] }
    }
}
