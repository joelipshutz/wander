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

    /// Category fallbacks are used only for a user-written/unknown subtype.
    /// Known selectable subtypes must have an explicit profile above.
    static let defaultQuestionIDs: [String: [String]] = [
        "restaurants_food": ["booking", "noise", "vegetarian"],
        "coffee_tea_sweets": ["laptop", "outlets", "dog_access"],
        "bars_nightlife": ["noise", "alcohol_free", "outdoor_seating"],
        "outdoors_nature": ["shade", "restroom", "path_surface"],
        "things_to_do": ["admission", "visit_time", "step_free"],
        "shopping": ["everyday_browsing", "everyday_staff_help", "everyday_payment"],
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
